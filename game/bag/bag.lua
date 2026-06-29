-- 背包基类
-- 其余所有类型的背包都继承这个类, 如基础物品背包、养成材料背包。
local util = require "util"
local agent = require "agent.agent"
local bag_registry = require "bag.bag_type_registry"
local item = require "items.item"

local BaseBag = {}
BaseBag.__index = BaseBag

function BaseBag:new(uid, bag_type, get_owner)
    local self = setmetatable({}, self)

    self.owner = uid
    -- 背包类型
    self.bag_type = bag_type
    -- 背包容量
    self.bag_size = 0       -- 格子数量
    -- 背包数据
    self.bag_data = {}
    -- 获取拥有者
    self._get_owner = get_owner

    return self
end


-- 获取用于存盘数据
function BaseBag:get_persistent_table()
    return {}
end

-- 从数据库加载数据
function BaseBag:apply_data(data)
    local items_data = data["items"] or {}

    -- 恢复 itemsobj 数据
    for id, item_data in pairs(items_data) do
        item_data[id] = id
        self.bag_data[id] = item.create_Item(data)
    end
end


function BaseBag:get_owner()
    if self._get_owner then
        return self._get_owner()
    end
    return nil
end

function BaseBag:get_bag_size()
    return self.bag_size
end

-- 添加道具 原子操作
function BaseBag:_add_item(item_obj)
    self.bag_data[item_obj.get_id()] = item_obj
    -- TODO 通知客户端
end

-- 移除道具 原子操作
function BaseBag:_del_item(item_uuid)
    self.bag_data[item_uuid] = nil
end

-- 获取同步给客户端的 全部数据
-- 目前设计, 只需要同步道具信息
function BaseBag:get_sync_client_data_all()
    local res_data = {}
    for item_uuid, item_obj in pairs(self.bag_data) do
        res_data[item_uuid] = item_obj:get_sync_client_data()
    end
    return res_data
end


-- 子类继承调用
-- 自动注册到背包类里
function BaseBag:extend(bag_type)
    local cls = {}
    cls.__index = cls
    cls.super = self
    setmetatable(cls, self)
    if bag_type then
        bag_registry.register(bag_type, cls)
    end
    return cls
end

return BaseBag