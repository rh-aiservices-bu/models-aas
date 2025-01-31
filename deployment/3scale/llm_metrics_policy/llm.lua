local len = string.len
local ipairs = ipairs
local pairs = pairs
local tinsert = table.insert

local policy = require('apicast.policy')
local prometheus = require('apicast.prometheus')
local Condition = require('apicast.conditions.condition')
local LinkedList = require('apicast.linked_list')
local TemplateString = require('apicast.template_string')
local Operation = require('apicast.conditions.operation')
local Usage = require('apicast.usage')
local resty_env = require ('resty.env')
local resty_url = require 'resty.url'
local cjson = require 'cjson.safe'

local response = require ('response')
local portal_client = require('portal_client')
local custom_metrics = require('custom_metrics')

local default_combine_op = "and"
local default_template_type = "plain"
local liquid_template_type = "liquid"

local _M = policy.new('LLM metrics', 'builtin')

local new = _M.new

-- Register metrics
local llm_prompt_tokens_count = prometheus(
  'counter',
  'llm_prompt_tokens_count',
  'Token count for a prompt',
  {'service_id', 'service_system_name', 'application_id', 'application_system_name'}
)

local llm_completion_tokens_count = prometheus(
  'counter',
  'llm_completion_tokens_count',
  "Token count for a completion",
  {'service_id', 'service_system_name', 'application_id', 'application_system_name'}
)

local llm_total_token_count = prometheus(
  'counter',
  'llm_total_token_count',
  "Total token count",
  {'service_id', 'service_system_name', 'application_id', 'application_system_name'}
)

local function get_context(context)
  local ctx = { }
  ctx.req = {
    headers=ngx.req.get_headers(),
  }

  ctx.resp = {
    headers=ngx.resp.get_headers(),
  }

  ctx.usage = context.usage
  ctx.service = context.service or {}
  ctx.original_request = context.original_request
  ctx.jwt = context.jwt or {}
  ctx.application = context.application or {}
  ctx.llm_usage = context.llm_usage or {}
  return LinkedList.readonly(ctx, ngx.var)
end

local function load_condition(condition_config)
  if not condition_config then
    return nil
  end
  local operations = {}
  for _, operation in ipairs(condition_config.operations or {}) do
    tinsert( operations,
      Operation.new(
        operation.left,
        operation.left_type or default_template_type,
        operation.op,
        operation.right,
        operation.right_type or default_template_type))
  end

  return Condition.new(
    operations,
    condition_config.combine_op or default_combine_op)
end

local function load_rules(self, config_rules)
  if not config_rules then
    return
  end
  local rules = {}
  for _,rule in pairs(config_rules) do
      tinsert(rules, {
        condition = load_condition(rule.condition),
        metric = TemplateString.new(rule.metric or "", liquid_template_type),
        increment = TemplateString.new(rule.increment or "0", liquid_template_type)
      })
  end
  self.rules = rules
end

--- Initialize llm policy
-- @tparam[opt] table config Policy configuration.
function _M.new(config)
  local self = new(config)
  self.endpoint = resty_env.get('THREESCALE_PORTAL_ENDPOINT')
  local path = resty_url.split(self.endpoint or '')
  self.path = path and path[6]
  self.rules = {}
  self.enable_sse_support = config.enable_sse_support
  load_rules(self, config.rules or {})
  return self
end

-- Rewrite request to make sure token usage is included in the response
function _M.rewrite(context)
  ngx.req.read_body()
  local req_body = ngx.req.get_body_data()
  if not req_body then
    return
  end

  local success, payload = pcall(cjson.decode, req_body)
  if not success then
    ngx.log(ngx.ERR, "Failed to decode JSON payload")
    return
  end

  -- Check and modify the payload
  if payload.stream == true then
    -- Ensure "stream_options" exists
    if not payload.stream_options then
      payload.stream_options = {
        include_usage = true,
        continuous_usage_stats = true
      }
    end

    -- Modify "include_usage" to true if it's false
    if payload.stream_options.include_usage == false then
      payload.stream_options.include_usage = true
    end
  end

  -- Encode the modified payload back to JSON
  local modified_body = cjson.encode(payload)
  ngx.req.clear_header("Content-Length")
  ngx.req.set_body_data(modified_body)
  ngx.req.set_header("Content-Length", #modified_body)
end

-- Need to fetch application here as cosocket is disabled
-- in body_filter phase
function _M:access(context)
  if self.path then
    context.application = { id = "", name = "" }
  else
    local service = context.service
    if not service then
      ngx.log(ngx.ERR, 'No service in the context')
      return
    end

    local credentials = context.credentials
    if not credentials then
      ngx.log(ngx.WARN, "cannot get credentials: ", err or 'unknown error')
      return
    end

    local application, err = portal_client.find_application(self.endpoint, service.id, credentials)
    if not application then
      ngx.log(ngx.WARN, "cannot get application details: ", err or 'unknown error')
      return
    end

    context.application = application.application
  end
end

local function report_metrics(context)
    local service = context.service
    if not service then
       ngx.log(ngx.ERR, 'No service in the context')
       return
    end

    local application = context.application
    local usage = context.llm_usage

    if usage and usage.prompt_tokens and usage.prompt_tokens > 0 then
      llm_prompt_tokens_count:inc(usage.prompt_tokens, {
        service.id or "",
        service.system_name or "",
        application.id or "",
        application.name or ""
      })
    end

    if usage and usage.completion_tokens and usage.completion_tokens > 0 then
      llm_completion_tokens_count:inc(usage.completion_tokens, {
        service.id or "",
        service.system_name or "",
        application.id or "",
        application.name or ""
      })
    end

    if usage and usage.total_tokens and usage.total_tokens > 0 then
      llm_total_token_count:inc(usage.total_tokens, {
        service.id or "",
        service.system_name or "",
        application.id or "",
        application.name or ""
      })
    end
end

function _M:body_filter(context)
  local content_type = ngx.resp.get_headers()["Content-Type"]
  local chunk, finished = ngx.arg[1], ngx.arg[2]

  if self.enable_sse_support and response.isSSEStreamingResponse(content_type) then
    if finished then
      return report_metrics(context)
    end

    local events = response.get_sse_events(chunk)

    -- -- no events, continue
    if not events then
      return
    end

    for _, event in ipairs(events) do
      if event.data ~= response.CONST.SSE_TERMINATOR then
        local json, err = cjson.decode(event.data)
        if err then
          -- Silencing this for the moment
          -- ngx.log(ngx.ERR, "unable to read response_body, err: " .. err)
          ngx.exit(500)
        end

        -- Some model include usage field in each event, we only want to
        -- take the last one.
        local usage = json.usage
        if usage then
          context.llm_usage = usage
        end
      end
    end
  else
    local response_body, err = response.get_json_body(chunk, finished)
    if err then
      ngx.log(ngx.ERR, "unable to read response_body, err: " .. err)
      ngx.exit(500)
    end
    if response_body then
      local usage = response_body.usage
      local inspect = require 'inspect'

      context.llm_usage = usage
      return report_metrics(context)
    end
  end
end

function _M:post_action(context)
  -- context with all variables are needed to retrieve information about API
  -- response
  local ctx = get_context(context)

  -- We initialize the usage, and if any rule match, we report the usage to
  -- backend.
  local match = false
  local usage = Usage.new()

  for _, rule in ipairs(self.rules) do
    if rule.condition:evaluate(ctx) then
      local metric = rule.metric:render(ctx)
      if len(metric) > 0 then
        usage:add(metric, tonumber(rule.increment:render(ctx)) or 0)
        match = true
      end
    end
  end

  if not match then
    return
  end

  -- If cached key authrep call will happen on APICast policy, so no need to
  -- report only one metric. If no cached key will report only the new metrics.
  if ngx.var.cached_key then
    context.usage:merge(usage)
    return
  end
  custom_metrics.report(context, usage)
end

return _M
