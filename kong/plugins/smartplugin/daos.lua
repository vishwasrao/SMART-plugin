local typedefs = require "kong.db.schema.typedefs"

local smart_apps = {
    name = "smart_apps",
    primary_key = { "app_name", "issuer" },
    fields = {
      { app_name = { type = "string", required = true}, },
      { issuer = { type = "string", required = true}, },
      { app_launch_url = { type = "string"}, },
      { app_redirect_url = { type = "string"}, },
      { scope = { type = "string"}, },
      { client_id = { type = "string"}, },
      { client_secret = { type = "string"}, },
      { created_at = typedefs.auto_timestamp_s },
      { updated_at = typedefs.auto_timestamp_s },
    },
}

local smart_launches = {
    name = "smart_launches",
    primary_key = { "session_id" },
    fields = {
      { session_id = { type = "string", required = true }, },
      { client_id = { type = "string", required = true }, },
      { client_secret = { type = "string" }, },
      { app_name = { type = "string", required = true }, },
      { app_launch_url = { type = "string" }, },
      { app_redirect_url = { type = "string" }, },
      { token_endpoint_url = { type = "string" }, },
      { fhir_server_url = { type = "string", required = true }, },
      { authorization_code = { type = "string", }, },
      { access_token = { type = "string" }, },
      { refresh_token = { type = "string" }, },
      { id_token = { type = "string" }, },
      { token_type = { type = "string" }, },
      { scope = { type = "string" }, },
      { patient = { type = "string" }, },
      { encounter = { type = "string" }, },
      { practitioner = { type = "string" }, },
      { appContext = { type = "string" }, },
      { created_at = typedefs.auto_timestamp_s },
      { updated_at = typedefs.auto_timestamp_s },
    },
}

return {
  smart_apps,
  smart_launches,
}
