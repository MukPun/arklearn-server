local skynet = require "skynet"
local util = require("util")

local char_proto = {}

function char_proto.getHomePagePlayerData(user_obj)
    skynet.error("getHomePagePlayerData, uid:", user_obj:get_uid())
    local home_page_data = {
        result = 1,
        name = tostring(user_obj:get_var("name")),
        level = user_obj:get_var("level"),
        exp = user_obj:get_var("exp"),
        maxExp = user_obj:get_var("max_exp"),
        reason = user_obj:get_var("reason"),
        maxReason = user_obj:get_var("max_reason"),
        items = user_obj:get_var("items_data")
    }
    skynet.error("getHomePagePlayerData  data = ", util.Dumpstr(home_page_data))
    return home_page_data
end

return char_proto