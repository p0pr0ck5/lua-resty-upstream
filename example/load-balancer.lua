local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local flush = ngx.flush
local print = ngx.print
local req = ngx.req
local ngx_var = ngx.var
local str_lower = string.lower
local res_header = ngx.header

local httpc = http_upstream
local upstream = upstream

if ngx.var.scheme == "https" then
    httpc = https_upstream
    upstream = upstream_ssl
end

local client_body_reader, err = httpc:get_client_body_reader()
if not client_body_reader then
    if err == "chunked request bodies not supported yet" then
        ngx.status = 411
        ngx.say("411 Length Required")
        ngx.exit(ngx.status)
        return
    elseif err ~= nil then
        ngx_log(ngx_ERR, "Error getting client body reader: ", err)
    end
end

local res, conn_info = httpc:request{
    method = req.get_method(),
    path = (ngx_var.uri .. ngx_var.is_args .. (ngx_var.args or "")),
    body = client_body_reader,
    headers = req.get_headers(),
}

if not res then
    ngx.status = conn_info.status
    ngx.say(conn_info.err)
    return ngx.exit(ngx.status)
end

ngx.status = res.status

local HOP_BY_HOP_HEADERS = {
    ["connection"]          = true,
    ["keep-alive"]          = true,
    ["proxy-authenticate"]  = true,
    ["proxy-authorization"] = true,
    ["te"]                  = true,
    ["trailers"]            = true,
    ["transfer-encoding"]   = true,
    ["upgrade"]             = true,
}

for k,v in pairs(res.headers) do
    if not HOP_BY_HOP_HEADERS[str_lower(k)] then
        res_header[k] = v
    end
end

local reader = res.body_reader
if reader then
    repeat
        local chunk, err = reader(65536)
        if err then
          ngx_log(ngx_ERR, "Read Error: "..(err or ""))
          break
        end

        if chunk then
          print(chunk)
          flush(true)
        end
    until not chunk
end

local ok,err = httpc:set_keepalive()

upstream:process_failed_hosts()

