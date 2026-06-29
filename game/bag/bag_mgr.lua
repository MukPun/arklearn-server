-- 背包管理器
-- 管理所有背包对象
local const = require "const"
local component_registry = require "char.component_registry"
local bag_type_registry = require "bag.bag_type_registry"
local BaseBag            = require "bag.bag"
local ComponentBase      = require "char.component_base"

-- 设为默认类:BagMgr 在找不到具体 bag_type 注册时回退到 BaseBag
bag_type_registry.set_default(BaseBag)

local BagMgr = {}
BagMgr.__index = BagMgr
setmetatable(BagMgr, {__index = ComponentBase})


local BAG_TYPE_LIST = const.BAG_TYPE


function BagMgr:new(uid, get_owner)
    local self = setmetatable({}, BagMgr)
    self.uid = uid
    self._get_owner = get_owner     -- 闭包函数 返回角色对象
    self._bags = {}                 -- 背包对象 {}
    self:init()
    return self
end

-- 工厂:根据 bag_type 选具体 Bag 类,未注册的回退到 BaseBag
function BagMgr:bag_maker(bag_type)
    local bag_local = bag_type_registry.create(self.uid, bag_type, self._get_owner)
    return bag_local
end

function BagMgr:init()
    -- 初始化背包对象
    for _, bage_type in pairs(BAG_TYPE_LIST) do
        self._bags[bage_type] = self:bag_maker(bage_type)
    end
end

-- 从数据库加载数据
-- @param data_table    User._apply_data  items_data 文档
-- BagMgr 在其中查找自己的子表 items_data,然后按 bag_type 分发到对应 Bag
function BagMgr:apply_data(data_table)
    for save_key, data in pairs(data_table) do
        -- save_key 是 bag_type 字符串(例如 "NORMAL"),通过 self._bags 直接校验是否已注册
        if self._bags[save_key] then
            self._bags[save_key]:apply_data(data)
        end
    end
end

function BagMgr:get_persistent_table()
    local data = {}
    -- 遍历所有背包类 存盘对应的数据
    for bag_type, bag_obj in pairs(self._bags) do
        data[bag_type] = bag_obj:get_persistent_table()
    end
    return data
end

-- 获取所有背包的所有道具
function BagMgr:get_all_items()
    return {}
end

-- 获取下发给客户的的数据 全部背包的数据
function BagMgr:get_sync_client_data_all()
    local res_data = {}
    for _, bag_obj in pairs(self._bags) do
        for _, item_data in pairs(bag_obj:get_sync_client_data_all()) do
            table.insert(res_data, item_data)
        end
    end
    return res_data
end



-- 模块加载时 自动注册
component_registry.register("BagMgr", function (uid, get_owner)
    return BagMgr:new(uid, get_owner)
end)

return BagMgr