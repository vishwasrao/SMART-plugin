local access = require "kong.plugins.smartplugin.access"
local kong_meta = require "kong.meta"


local SmartHandler = {
  VERSION = kong_meta.version,
  PRIORITY = 1000,
}


function SmartHandler:access(conf)
  access.execute(conf)
end


return SmartHandler
