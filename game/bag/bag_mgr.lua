-- 背包管理器
-- 管理所有背包对象
local const = require "const"
local component_registry = require "char.component_registry"
local bag_registry       = require "bag.bag_type_registry"
local BaseBag            = require "bag.bag"
local ComponentBase      = require "char.component_base"

-- 主策基类
bag_registry.register(BaseBag)

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

function BagMgr:init()
    -- 初始化背包对象
    for _, bage_type in pairs(BAG_TYPE_LIST) do
        self._bags[bage_type] = self.bag_maker(bage_type)
    end
end

-- 从数据库加载数据
function BagMgr:apply_data(data_table)
    for save_key, data in pairs(data_table) do
        -- 背包导入数据
        if BAG_TYPE_LIST[save_key] ~= nil then
            self._bags[save_key].apply_data(data)
        end
    end
end

function BagMgr:get_persistent_table()
    local data = {}
    -- 遍历所有背包类 存盘对应的数据
    for bag_type, bag_obj in pairs(self.bags) do
        data[bag_type] = bag_obj.get_persistent_table()
    end
    return data
end

-- 
function BagMgr:get_all_items()
    return {}
end

-- 获取下发给客户的的数据 全部背包的数据
function BagMgr:get_sync_client_data_all()
    local res_data = {}
    for bag_type, bag_obj in pairs(self._bags) do
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