
local info = require "info.init"
local log = require "log"



local value = info.get("items", "5001")

log("[test info loda] value = %s", value.name)