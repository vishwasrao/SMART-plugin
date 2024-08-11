

local random_string = require("kong.tools.rand").random_string
-- If you're not sure your plugin is executing, uncomment the line below and restart Kong
-- then it will throw an error which indicates the plugin is being loaded at least.


--assert(ngx.get_phase() == "timer", "The world is coming to an end!")


---------------------------------------------------------------------------------------------
-- In the code below, just remove the opening brackets; `[[` to enable a specific handler
--
-- The handlers are based on the OpenResty handlers, see the OpenResty docs for details
-- on when exactly they are invoked and what limitations each handler has.
---------------------------------------------------------------------------------------------






local plugin = {
  PRIORITY = 1000, -- set the plugin priority, which determines plugin execution order
  VERSION = "0.1", -- version in X.Y.Z format. Check hybrid-mode compatibility requirements.
}






-- do initialization here, any module level code runs in the 'init_by_lua_block',
-- before worker processes are forked. So anything you add here will run once,
-- but be available in all workers.






-- handles more initialization, but AFTER the worker process has been forked/created.
-- It runs in the 'init_worker_by_lua_block'
function plugin:init_worker()


  -- your custom code here
  kong.log.debug("saying hi from the 'init_worker' handler")


end --]]






--[[ runs in the 'ssl_certificate_by_lua_block'
-- IMPORTANT: during the `certificate` phase neither `route`, `service`, nor `consumer`
-- will have been identified, hence this handler will only be executed if the plugin is
-- configured as a global plugin!
function plugin:certificate(plugin_conf)


  -- your custom code here
  kong.log.debug("saying hi from the 'certificate' handler")


end --]]






--[[ runs in the 'rewrite_by_lua_block'
-- IMPORTANT: during the `rewrite` phase neither `route`, `service`, nor `consumer`
-- will have been identified, hence this handler will only be executed if the plugin is
-- configured as a global plugin!
function plugin:rewrite(plugin_conf)


  -- your custom code here
  kong.log.debug("saying hi from the 'rewrite' handler")


end --]]






-- runs in the 'access_by_lua_block'
function plugin:access(plugin_conf)


  -- your custom code here
  kong.log.inspect(plugin_conf)   -- check the logs for a pretty-printed config!
  -- kong.service.request.set_header(plugin_conf.request_header, "this is on a request")


   -- Custom Code for SMART plugin starts here
   kong.log.debug("SMART plugin: Access handler")


local path_params = kong.request.get_path()
local query_params = kong.request.get_query()


local appName = path_params:match("/launch/([^/]+)")
local iss = query_params["iss"]


local launch = query_params["launch"]


if not appName or not iss then
  kong.log.err("Missing appName or iss in the request")
  return kong.response.exit(400, { message = "Missing appName or iss in the request" })
end


kong.log.debug("Received appName: ", appName)
kong.log.debug("Received iss: ", iss)


--Load the app details from the database
local appDetails, err = kong.db.smart_apps:select({appName = appName, issuer = iss})
if err then
  kong.log.err("Error fetching app details: ", err)
  return kong.response.exit(500, { message = "Error fetching app details" })
end
--Check if the app exists
if not appDetails then
  kong.log.err("App not found: ", appName)
  return kong.response.exit(404, { message = "App not found" })
end
--Print the app details
kong.log.inspect(appDetails)


--Make a API call to issuer + "metadata" to get the metadata of FHIR  server
local http = require "resty.http"
local httpc = http.new()
local res, err = httpc:request_uri(appDetails.issuer .. "/metadata", {
  method = "GET",
  headers = {
    ["Accept"] = "application/json"
  }
})
if not res then
  kong.log.err("Error fetching SMART configuration: ", err)
  return kong.response.exit(500, { message = "Error fetching SMART configuration" })
end
local capabilityStatement = res.body
kong.log.debug("Capability Statement: ", capabilityStatement)


-- Parse the capability statement to get the authorize and token endpoints
local cjson = require("cjson")
local capability = cjson.decode(capabilityStatement)


local securityInfoExtension = capability.rest[1].security.extension[1].extension
local authorizeEndpoint, tokenEndpoint


for _, extension in ipairs(securityInfoExtension) do
  if extension.url == "authorize" then
    authorizeEndpoint = extension.valueUri
  elseif extension.url == "token" then
    tokenEndpoint = extension.valueUri
  end
end


-- Check if the authorize and token endpoints are found
if not authorizeEndpoint or not tokenEndpoint then
  kong.log.err("Missing authorize or token endpoint in capability statement")
  return kong.response.exit(500, { message = "Missing authorize or token endpoint" })
end


kong.log.debug("Authorize Endpoint: ", authorizeEndpoint)
kong.log.debug("Token Endpoint: ", tokenEndpoint)


-- Generate random string as UUID and store it in sessionId variable
local sessionId = random_string()
kong.log.debug("Session ID: ", sessionId)
-- Redirect to authorize endpoint with query params clientId, clientSecret, etc.
local redirect_uri = kong.request.get_scheme() .. "://" .. kong.request.get_host() .. "/callback"
local authorize_url = authorizeEndpoint .. "?response_type=code" .. "&client_id=" .. appDetails.clientId .. "&redirect_uri=" .. redirect_uri .. "&scope=launch&state=" .. sessionId
kong.response.set_header("Location", authorize_url)
kong.response.exit(302)




-- Custom Code for SMART plugin ends here


end --]]




-- runs in the 'header_filter_by_lua_block'
function plugin:header_filter(plugin_conf)
  kong.log.debug("SMART plugin: Header filter handler")


  -- your custom code here, for example;
  -- kong.response.set_header(plugin_conf.response_header, "this is on the response")


end --]]




--[[ runs in the 'body_filter_by_lua_block'
function plugin:body_filter(plugin_conf)


  -- your custom code here
  kong.log.debug("saying hi from the 'body_filter' handler")


end --]]




--[[ runs in the 'log_by_lua_block'
function plugin:log(plugin_conf)


  -- your custom code here
  kong.log.debug("saying hi from the 'log' handler")


end --]]




-- return our plugin object
return plugin



