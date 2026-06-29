local BaseBag = require "game.bag.bag"
local const = require "const"

-- 继承背包基类 基类会把新的背包类型注册到registry里面
local NormalBag = BaseBag:extend(const.BAG_TYPE.BAG_TYPE_NORMAL)

function NormalBag:new(uid, bag_type, get_owner)
    local obj = BaseBag:new(uid, bag_type, get_owner)
    setmetatable(obj, self)
    obj.bag_size = 100
    return obj
end


-- 获取用于存盘数据
function NormalBag:get_persistent_table()
    return {""}
end