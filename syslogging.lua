--- Logging policy

local _M  = require('apicast.policy').new('SysLogging Policy')
local logger = require('socket')
local cjson = require('cjson')

local new = _M.new

function _M.new(config)
  local self = new(config)

  host = os.getenv('SYSLOG_HOST')
  port = os.getenv('SYSLOG_PORT')
  proto = os.getenv('SYSLOG_PROTOCOL') or 'tcp'
  base64_flag = os.getenv('APICAST_PAYLOAD_BASE64') or 'false'
  flush_limit = os.getenv('SYSLOG_FLUSH_LIMIT') or '0'
  periodic_flush = os.getenv('SYSLOG_PERIODIC_FLUSH') or '5'
  drop_limit = os.getenv('SYSLOG_DROP_LIMIT') or '1048576'  

  if (host == nil or host == "") then
    ngx.log(ngx.ERR, "The environment SYSLOG_HOST is NOT defined !")
  end

  if (port == nil or port == "") then
    ngx.log(ngx.ERR, "The environment SYSLOG_PORT is NOT defined !")
  end

  port = tonumber(port)
  flush_limit = tonumber(flush_limit)
  drop_limit = tonumber(drop_limit)
  periodic_flush = tonumber(periodic_flush)

  ngx.log(ngx.WARN, "Sending custom logs to " .. proto .. "://" .. (host or "") .. ":" .. (port or "") .. " with flush_limit = " .. flush_limit .. " bytes, periodic_flush = " .. periodic_flush .. " sec. and drop_limit = " .. drop_limit .. " bytes")

  local params = {
    host = host,
    port = port,
    sock_type = proto,
    flush_limit = flush_limit,
    drop_limit = drop_limit
    }

-- periodic_flush == 0 means 'disable this feature'
    if periodic_flush > 0 then
    params["periodic_flush"] = periodic_flush
    end
  ngx.log(ngx.INFO, "Initializing the underlying logger")
  
  local ok, err = logger.init(params)
  if not ok then
      ngx.log(ngx.ERR, "failed to initialize the logger: ", err)
  end

  return self
end

function do_log(payload)
    -- construct the custom access log message in
    -- the Lua variable "msg"
    --
    -- do not forget the \n in order to have one request per line on the syslog server
    --
    local bytes, err = logger.log(payload .. "\n")
    if err then
        ngx.log(ngx.ERR, "failed to log message: ", err)
    end
end


function _M:log()
  local dict = {}

  -- Gather information of the request
  local request = {}
  if ngx.var.request_body then
    if (base64_flag == 'true') then
      request["body"] = ngx.encode_base64(ngx.var.request_body)
    else
      request["body"] = ngx.var.request_body
    end
  end
  request["headers"] = ngx.req.get_headers()
  request["start_time"] = ngx.req.start_time()
  request["http_version"] = ngx.req.http_version()
  if (base64_flag == 'true') then
    request["raw"] = ngx.encode_base64(ngx.req.raw_header())
  else
    request["raw"] = ngx.req.raw_header()
  end

  request["method"] = ngx.req.get_method()
  request["uri_args"] = ngx.req.get_uri_args()
  request["request_id"] = ngx.var.request_id
  dict["request"] = request

  -- Gather information of the response
  local response = {}
  if ngx.ctx.buffered then
    if (base64_flag == 'true') then
      response["body"] = ngx.encode_base64(ngx.ctx.buffered)
    else
      response["body"] = ngx.ctx.buffered
    end
  end
  response["headers"] = ngx.resp.get_headers()
  response["status"] = ngx.status
  dict["response"] = response

  -- timing stats
  local upstream = {}
  upstream["addr"] = ngx.var.upstream_addr
  upstream["bytes_received"] = ngx.var.upstream_bytes_received
  upstream["cache_status"] = ngx.var.upstream_cache_status
  upstream["connect_time"] = ngx.var.upstream_connect_time
  upstream["header_time"] = ngx.var.upstream_header_time
  upstream["response_length"] = ngx.var.upstream_response_length
  upstream["response_time"] = ngx.var.upstream_response_time
  upstream["status"] = ngx.var.upstream_status
  dict["upstream"] = upstream

  do_log(cjson.encode(dict))
  
end
return _M 