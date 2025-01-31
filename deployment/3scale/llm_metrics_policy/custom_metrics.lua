local tinsert = table.insert

local http_ng_resty = require ('resty.http_ng.backend.resty')
local ReportsBatch = require('apicast.policy.3scale_batcher.reports_batch')
local backend_client = require('apicast.backend_client')

local _M = {}

-- report: Report the given usage information to the backend
function _M.report(context, usage)
  local backend = backend_client:new(context.service, http_ng_resty)
  local reports = {}
  for key, value in pairs(usage.deltas) do
    local result = deepcopy(context.credentials)
    result.metric = key
    result.value = value
    result.service_id = context.service.id
    tinsert(reports, result)
  end

  local res = backend:report(ReportsBatch.new(context.service.id, reports))
  if res.status ~= 200 then
    ngx.log(ngx.INFO, "Custom metric report usage failed")
  end
end

return _M
