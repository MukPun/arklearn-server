-- 背包基类
-- 其余所有类型的背包都继承这个类, 如基础物品背包、养成材料背包。

local BaseBag = {}
BaseBag.__index = BaseBag

function BaseBag:new(uid, bag_type)
    local self = setmetatable({}, BaseBag)

    -- 背包类型
    self.bag_type = nil
    -- 背包容量
    self.bag_size = 0
    -- 背包数据
    self.bag_data = {}
end
