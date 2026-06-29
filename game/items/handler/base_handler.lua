-- 道具处理器基类

local item_type_mgr = require "items.item_type_mgr"
local base_handler = {}

-- 判断道具是否可用
function base_handler:can_use(item_obj, user_obj, amount)
    amount = amount or 1
    return true, ""
end

-- 道具使用逻辑 
--TODO 可以套导表配置的行为, 达到配置导表 配置道具的行为
function base_handler:use(item_obj, user_obj, amount, extra, tag)
    local can_use, msg = item_obj:can_use(user_obj, amount)
    if not can_use then
        return false, msg
    end
    return true, ""
end

function base_handler:can_sell(item_obj)
    return false, "不可出售"
end

function base_handler:can_gift(item_obj)
    return false, "不可赠送"
end

item_type_mgr.register("BASE", base_handler)