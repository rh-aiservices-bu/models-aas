local cjson = require 'cjson.safe'
local Mime = require 'resty.mime'

local str_find = string.find
local str_sub = string.sub
local concat = table.concat
local split = require 'pl.stringx'.split

local arg = ngx.arg

local json_content_types = {
  ["application/json"] = true,
}

local sse_content_types = {
  ["text/event-stream"] = true,
}

local _M = {}

_M.CONST = {
  ["SSE_TERMINATOR"] = "[DONE]",
}

-- Buffering the response body in the internal request context
-- and return the full body when last chunk has been read
function _M.get_raw_body(chunk, finished)
  local buffered = ngx.ctx.buffered_response_body

  -- Single chunk
  if finished and not buffered then
    return chunk
  end

  if type(chunk) == "string" and chunk ~= "" then
    if not buffered then
      buffered = {} -- XXX we can use table.new here
      ngx.ctx.buffered_response_body = buffered
    end

    buffered[#buffered+1] = chunk
    ngx.arg[1] = nil
  end

  -- End of chunk
  if finished then
    if buffered then
      buffered = concat(buffered)
    else
      buffered = ""
    end

    -- Send response and clear the buffered body
    arg[1] = buffered
    ngx.ctx.buffered_response_body = nil
    return buffered
  end

  arg[1] = nil
  return nil
end

local function mime_type(content_type)
    return Mime.new(content_type).media_type
end

function _M.isSSEStreamingResponse(content_type)
  return sse_content_types[mime_type(content_type)]
end


function _M.decode_json(response)
    if json_content_types[mime_type(response.headers.content_type)] then
        return cjson.decode(response.body)
    else
        return nil, 'not json'
    end
end

function _M.get_json_body(chunk, finished)
  local response_body = _M.get_raw_body(chunk, finished)
  if response_body then
    local err
    if type(response_body) == "string" then
      response_body, err = cjson.decode(response_body)
      if err then
        return nil, err
      end
      return response_body
    else
      return nil, "unknown response body type"
    end
  end

  return nil
end

local function process_field(event, field, value)
  if field == "event" then event.event = value
  elseif field == "data" then event.data = value
  elseif field == "id" then
    -- empty IDs are valid, only IDs that contain the null byte must be ignored:
    local null_terminator, _ = str_find(value, "\0")
    if not null_terminator then
      event.id =value
    end
  elseif field == "retry" then
    -- won't handle this field, we only want to extract the token
  else
    -- ignore
    return
  end
end

-- Parses an SSE stream and yields all incoming events,
--
-- The "retry" field is ignore.
--
-- https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation
local function parse_sse_events(chunk)
  local events = {}
  local buffered = ngx.ctx.sse_truncated_event

  if (not chunk) or (#chunk < 1) or (type(chunk)) ~= "string" then
    return
  end

  -- A single chunk can contains multiple lines
  local event_lines = split(chunk, "\n")

  -- When a stream is parsed, a data buffer, an event type buffer, and a last
  -- event ID buffer must be associated with it. They must be initialized to
  -- the empty string.
  local event = {event = "", id = "", data = ""}

  -- Read line by line
  for i, line in ipairs(event_lines) do
    if #line < 1 then
       events[#events + 1] = event
       event = { event = "", id = "", data = "" }
    end

    -- check if this is a truncated line
    if #line > 0 and #event_lines == i then
      if not buffered then
        buffered = {} -- XXX we can use table.new here
        ngx.ctx.sse_truncated_event = buffered
      end

      buffered[#buffered+1] = line
      break
    end

    -- continue from the previous truncated chunk
    if buffered then
      buffered[#buffered+1] = line
      line = concat(buffered)
      ngx.ctx.sse_truncated_event = nil
    end

    -- find where the first colon position is
    local colon_pos, _ = str_find(line, ":")

    -- Ignore line start with (:) character
    if colon_pos == 1 then
      return
    end

    -- If the line contains COLON (:) character
    if colon_pos then
       -- Collect the characters on the line before and after the the first U+003A COLON character (:).
      local field = str_sub(line, 1, colon_pos-1) -- returns "data" from data: hello world
      local value = str_sub(line, colon_pos+1) -- returns "hello world" from data: hello world

      -- Remove leading white space character from value
      value = value:gsub("^%s*", "")

      process_field(event, field, value)
    else
      -- the string is not empty but does not contain a COLON character (:)
      process_field(event, line, "")
    end
  end

  return events
end

function _M.get_sse_events(chunk)
  return parse_sse_events(chunk)
end

return _M
