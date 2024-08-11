local url = require "socket.url"
local constants = require "kong.constants"
local timestamp = require "kong.tools.timestamp"


local sha256_base64url = require "kong.tools.sha256".sha256_base64url

local fmt = string.format
local kong = kong
local type = type
local next = next
local table = table
local error = error
local split = require("kong.tools.string").split
local strip = require("kong.tools.string").strip
local string_find = string.find
local string_gsub = string.gsub
local string_byte = string.byte
local check_https = require("kong.tools.http").check_https
local encode_args = require("kong.tools.http").encode_args
local random_string = require("kong.tools.rand").random_string
local table_contains = require("kong.tools.table").table_contains
local random_string = require("kong.tools.rand").random_string

local ngx_decode_args = ngx.decode_args
local ngx_re_gmatch = ngx.re.gmatch
local ngx_decode_base64 = ngx.decode_base64
local ngx_encode_base64 = ngx.encode_base64

local _M = {}

local EMPTY = {}
local SLASH = string_byte("/")
local RESPONSE_TYPE = "response_type"
local STATE = "state"
local CODE = "code"
local CODE_CHALLENGE = "code_challenge"
local CODE_CHALLENGE_METHOD = "code_challenge_method"
local CODE_VERIFIER = "code_verifier"
local CLIENT_TYPE_PUBLIC = "public"
local CLIENT_TYPE_CONFIDENTIAL = "confidential"
local TOKEN = "token"
local REFRESH_TOKEN = "refresh_token"
local SCOPE = "scope"
local CLIENT_ID = "client_id"
local CLIENT_SECRET = "client_secret"
local REDIRECT_URI = "redirect_uri"
local ACCESS_TOKEN = "access_token"
local GRANT_TYPE = "grant_type"
local GRANT_AUTHORIZATION_CODE = "authorization_code"
local GRANT_CLIENT_CREDENTIALS = "client_credentials"
local GRANT_REFRESH_TOKEN = "refresh_token"
local GRANT_PASSWORD = "password"
local ERROR = "error"
local AUTHENTICATED_USERID = "authenticated_userid"


local base64url_encode
local base64url_decode
do
    local BASE64URL_ENCODE_CHARS = "[+/]"
    local BASE64URL_ENCODE_SUBST = {
        ["+"] = "-",
        ["/"] = "_",
    }

    base64url_encode = function(value)
        value = ngx_encode_base64(value, true)
        if not value then
            return nil
        end

        return string_gsub(value, BASE64URL_ENCODE_CHARS, BASE64URL_ENCODE_SUBST)
    end


    local BASE64URL_DECODE_CHARS = "[-_]"
    local BASE64URL_DECODE_SUBST = {
        ["-"] = "+",
        ["_"] = "/",
    }

    base64url_decode = function(value)
        value = string_gsub(value, BASE64URL_DECODE_CHARS, BASE64URL_DECODE_SUBST)
        return ngx_decode_base64(value)
    end
end

local function launch(conf)
    kong.log.inspect(conf) -- check the logs for a pretty-printed config!
    -- Custom Code for SMART plugin starts here
    kong.log.debug("SMART plugin: launch handler")

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
    local appDetails, err = kong.db.smart_apps:select({ appName = appName, issuer = iss })
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
    -- Redirect to authorize endpoint with query params clientId, clientSecret, etc.
    local authorize_url = authorizeEndpoint ..
    "?response_type=code" ..
    "&client_id=" ..
    appDetails.clientId ..
    "&redirect_uri=" .. appDetails.appRedirectUrl .. "&scope=" .. appDetails.scope .. "&state=" .. sessionId .. "&launch=" .. launch .. "&aud=" .. iss
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
