local concat = table.concat
local insert = table.insert
local len = string.len

local user_agent = require('apicast.user_agent')
local resty_url = require ('resty.url')
local http_ng = require ('resty.http_ng')
local http_ng_resty = require ('resty.http_ng.backend.resty')
local resty_env = require ('resty.env')
local response = require ('response')

local _M = {}

local function build_args(args)
  local query = {}

  for i=1, #args do
    local arg = ngx.encode_args(args[i])
    if len(arg) > 0 then
      insert(query, arg)
    end
  end

  return concat(query, '&')
end

local function application_find_endpoint(portal_endpoint)
  return resty_url.join(portal_endpoint, '/admin/api/applications/find.json')
end

-- Call /admin/api/applications/find.json
function _M.find_application(endpoint, service_id, credentials)
  if not endpoint then
    return nil, "No endpoint available"
  end

  local base_url = application_find_endpoint(endpoint)
  local authentication = { service_id = service_id }
  local args = {authentication, credentials}

  local url = base_url.."?".. build_args(args)

  ngx.log(ngx.DEBUG, 'fetching application details at ', url)

  local http_client = http_ng.new{
    backend = http_ng_resty,
    options = {
      headers = {
        ['User-Agent'] = user_agent()
      },
      ssl = { verify = resty_env.enabled('OPENSSL_VERIFY') }
    }
  }

  local res = http_client.get(url)

  if res.status == 200 then
    local val, err = response.decode_json(res)
      if err then
      ngx.log(ngx.ERR, 'invalid application response, cannot decode the message: ', res.headers.content_type, ', error:', err ,', body: ', res.body)
      return nil, "Cannot decode application request response"
    end
    return val
  else
    return nil, 'invalid response - status: ' .. res.status
  end
end


return _M
