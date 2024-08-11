local typedefs = require "kong.db.schema.typedefs"


return {
  {
    name = "smart_apps",
    primary_key = { "appName", "issuer" },
    fields = {
      { appName = { type = "string", required = true}, },
      { issuer = { type = "string", required = true}, },
      { appLaunchUrl = { type = "string"}, },
      { appRedirectUrl = { type = "string"}, },
      { scope = { type = "string"}, },
      { clientId = { type = "string"}, },
      { clientSecret = { type = "string"}, },
      { clinicalData = { type = "string"}, },
      { created_at = typedefs.auto_timestamp_s },
      { updated_at = typedefs.auto_timestamp_s },
    },
  },
}

