local _M = require('apicast.policy').new('Remove Bearer','0.1')

function _M:rewrite(context)
    local authorization = ngx.req.get_headers()["Authorization"]
    if authorization and authorization:find("Bearer ") then
        local new_authorization = authorization:gsub("Bearer ", "")
        ngx.req.set_header("Authorization", new_authorization)
    end
end

return _M
