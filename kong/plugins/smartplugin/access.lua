local http = require "resty.http"
local cjson = require("cjson")
local jwt_decoder = require("kong.plugins.jwt.jwt_parser")

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

    -- Insert data into smart_launches table
    local smart_launches = kong.db.smart_launches
    local data = {
        session_id = sessionId,
        client_id = appDetails.client_id,
        client_secret = appDetails.client_secret,
        app_name = appDetails.app_name,
        app_launch_url = appDetails.app_launch_url,
        app_redirect_url = appDetails.app_redirect_url,
        token_endpoint_url = tokenEndpoint,
        fhir_server_url = iss,
        scope = appDetails.scope
    }
    local res, err = smart_launches:insert(data)
    if err then
        kong.log.err("Error inserting data into smart_launches table: ", err)
        return kong.response.exit(500, { message = "Error inserting data into smart_launches table" })
    end
    kong.log.debug("Data inserted into smart_launches table: ", res)

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
   
    -- Get query parameters
    local query_params = kong.request.get_query()

    -- Get code, state, error, error_description, and error_uri from query parameters
    local code = query_params["code"]
    local state = query_params["state"]
    local error = query_params["error"]
    local error_description = query_params["error_description"]
    local error_uri = query_params["error_uri"]

    -- Check if error exists
    if error then
        kong.log.err("Received error: ", error)
        if error_uri then
            kong.response.set_header("Location", error_uri)
            kong.response.exit(302)
        else
            return kong.response.exit(403, { message = "Error occurred during authcallback", error = error, error_description = error_description })
        end
    end

    -- Validate code and state are not empty
    if not code or not state then
        kong.log.err("Missing code or state in the request")
        return kong.response.exit(400, { message = "Missing code or state in the request" })
    end

    -- Fetch data from smart_launches table using sessionId
    local smart_launches = kong.db.smart_launches
    local smart_launches_details, err = smart_launches:select({ session_id = state })
    if err then
        kong.log.err("Error fetching data from smart_launches table: ", err)
        return kong.response.exit(500, { message = "Error fetching data from smart_launches table" })
    end

    -- Check if data exists
    if not smart_launches_details then
        kong.log.err("Data not found for sessionId: ", state)
        return kong.response.exit(404, { message = "Data not found" })
    end
    --Print the smart_launches details
    kong.log.inspect("Data fetched from smart_launches table: ", smart_launches_details)

    -- Send POST request to token endpoint
    
    local httpc = http.new()
    local res, err = httpc:request_uri(smart_launches_details.token_endpoint_url, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Authorization"] = "Basic " .. ngx.encode_base64(smart_launches_details.client_id .. ":" .. smart_launches_details.client_secret)
        },
        body = ngx.encode_args({
            scope = smart_launches_details.scope,
            redirect_uri = smart_launches_details.app_redirect_url,
            code = code,
            grant_type = "authorization_code"
        })
    })

    if not res then
        kong.log.err("Error sending POST request to token endpoint: ", err)
        return kong.response.exit(500, { message = "Error sending POST request to token endpoint" })
        end

        local access_token_response = res.body
        kong.log.debug("Received response from token endpoint: ", access_token_response)

        -- Parse the response to get access_token, token_type, expires_in, patient, refresh_token, id_token, Optionally encounter, location
        local response = cjson.decode(access_token_response)
        local access_token = response.access_token
        local token_type = response.token_type
        local expires_in = response.expires_in
        local patient = response.patient
        local refresh_token = response.refresh_token
        local id_token = response.id_token
        local encounter = response.encounter
        local location = response.location

        -- Decode id_token to get the user details, get fhirUser from it
        local jwt_obj = jwt_decoder:new(id_token)
        local fhir_user = jwt_obj.claims.fhirUser
        local user_type, user_id = string.match(fhir_user, "([^/]+)/([^/]+)")
        kong.log.debug("User Type: ", user_type)
        kong.log.debug("User ID: ", user_id)

        kong.log.inspect(jwt_obj)
        --kong.log.inspect(fhirUser)
        
        
        -- Store all these details in smart_launches table using sessionId
        local smart_launches = kong.db.smart_launches
        local update_data = {
        authorization_code  = code,
        access_token = access_token,
        token_type = token_type,
        expires_in = expires_in,
        patient = patient,
        refresh_token = refresh_token,
        id_token = id_token,
        encounter = encounter,
        location = location,
        user_type = user_type,
        user_id = user_id
        }
        local update_res, update_err = smart_launches:update({ session_id = state }, update_data)
        if update_err then
        kong.log.err("Error updating data in smart_launches table: ", update_err)
        return kong.response.exit(500, { message = "Error updating data in smart_launches table" })
        end
        kong.log.debug("Data updated in smart_launches table: ", update_res)

        -- Redirect to app launch URL
        kong.response.set_header("Location", smart_launches_details.app_launch_url)
        kong.response.set_header("Set-Cookie", "vishwasCookie=" .. smart_launches_details.session_id .. "; Secure; Max-Age=3600; HttpOnly")
        kong.response.exit(302)
    -- Continue with the rest of the code
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
