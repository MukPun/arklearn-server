local skynet = require("skynet")
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
        items = user_obj:get_component("BagMgr"):get_sync_client_data_all(),
    }
    skynet.error("getHomePagePlayerData  data = ", util.Dumpstr(home_page_data))
    return home_page_data
end


-- TODO 暂未实现
-- 原 getAllBagItems 已注释:该 handler 未在 proto.c2s.sproto 中声明,
-- Dispatcher:register 会 assert 失败导致 Agent 启服崩溃
-- 启用步骤:先在 sproto 中新增 getAllBagItems 协议,然后取消下方注释 + 补全实现
--[[
function char_proto:getAllBagItems(user_obj)
    log("[c2s] getAllBagItems uid:%s", user_obj:get_uid())
    return { items = user_obj:get_component("BagMgr"):get_sync_client_data_all() }
end
]]

return char_proto