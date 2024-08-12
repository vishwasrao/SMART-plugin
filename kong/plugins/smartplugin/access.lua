local fmt = string.format
local kong = kong
local string_find = string.find
local string_byte = string.byte
local random_string = require("kong.tools.rand").random_string

local _M = {}

local SLASH = string_byte("/")
local ERROR = "error"


local function launch(conf)
    kong.log.inspect(conf) -- check the logs for a pretty-printed config!
    -- Custom Code for SMART plugin starts here
    kong.log.debug("SMART plugin: launch handler")

    local path_params = kong.request.get_path()
    local query_params = kong.request.get_query()

    local app_name = path_params:match("/launch/([^/]+)")
    local iss = query_params["iss"]

    local launch = query_params["launch"]

    if not app_name or not iss then
        kong.log.err("Missing app_name or iss in the request")
        return kong.response.exit(400, { message = "Missing app_name or iss in the request" })
    end

    kong.log.debug("Received app_name: ", app_name)
    kong.log.debug("Received iss: ", iss)

    --Load the app details from the database
    local appDetails, err = kong.db.smart_apps:select({ app_name = app_name, issuer = iss })
    if err then
        kong.log.err("Error fetching app details: ", err)
        return kong.response.exit(500, { message = "Error fetching app details" })
    end
    --Check if the app exists
    if not appDetails then
        kong.log.err("App not found: ", app_name)
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
    --kong.log.debug("Capability Statement: ", capabilityStatement)

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
    -- Redirect to authorize endpoint with query params client_id, scope, redirect_uri etc.
    local authorize_url = authorizeEndpoint ..
        "?response_type=code" ..
        "&client_id=" ..
        appDetails.client_id ..
        "&redirect_uri=" ..
        appDetails.app_redirect_url ..
        "&scope=" .. appDetails.scope .. "&state=" .. sessionId .. "&launch=" .. launch .. "&aud=" .. iss
    kong.response.set_header("Location", authorize_url)
    kong.response.exit(302)

    -- Custom Code for SMART plugin ends here
end

local function authcallback(conf)
    kong.log.debug("SMART plugin: authcallback handler")
    kong.log.inspect(kong.request.get_headers())
end

local function invalid_method(endpoint_name, realm)
    return {
        status = 405,
        message = {
            [ERROR] = "invalid_method",
            error_description = "The HTTP method " ..
                kong.request.get_method() ..
                " is invalid for the " .. endpoint_name .. " endpoint"
        },
        headers = {
            ["WWW-Authenticate"] = 'Bearer' .. realm .. ' error=' ..
                '"invalid_method" error_description=' ..
                '"The HTTP method ' .. kong.request.get_method()
                .. ' is invalid for the ' ..
                endpoint_name .. ' endpoint"'
        }
    }
end

function _M.execute(conf)
    local path = kong.request.get_path()
    local has_end_slash = string_byte(path, -1) == SLASH

    local realm = conf.realm and fmt(' realm="%s"', conf.realm) or ''

    if string_find(path, "/launch/([^/]+)") then
        if kong.request.get_method() ~= "GET" then
            local err = invalid_method("launch", realm)
            return kong.response.exit(err.status, err.message, err.headers)
        end

        return launch(conf)
    end

    if string_find(path, "/authcallback", has_end_slash and -14 or -13, true) then
        if kong.request.get_method() ~= "GET" then
            local err = invalid_method("authcallback", realm)
            return kong.response.exit(err.status, err.message, err.headers)
        end

        return authcallback(conf)
    end
end

return _M
