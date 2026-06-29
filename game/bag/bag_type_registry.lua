-- bag_type_registry.lua
-- 把 bag_type 字符串映射到具体类
local M = {}
M._map = {}

-- 注册:Bag 子类在文件加载时自报家门
function M.register(bag_type, cls)
    M._map[bag_type] = cls
end

-- 创建:BagMgr 用它来实例化
function M.create(uid, bag_type, get_owner)
    local cls = M._map[bag_type] or M._default  -- 没注册就用 BaseBag
    return cls:new(uid, bag_type, get_owner)
end

-- 设置默认类(没注册的 bag_type 会用这个)
function M.set_default(cls)
    M._default = cls
end

return M
