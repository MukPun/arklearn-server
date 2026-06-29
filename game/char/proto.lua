local skynet = require("skynet")
local util = require("util")
local log = require("log")

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
        items = user_obj:get_component("BagMgr"):get_sync_client_data_all(),
    }
    skynet.error("getHomePagePlayerData  data = ", util.Dumpstr(home_page_data))
    return home_page_data
end


function char_proto:getAllBagItems(user_obj)
    log("[c2s] getAllBagItems uid:%s", user_obj.get_uid())
    return {}
end

return char_proto