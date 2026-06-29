local util = require "util"
local uuid = require "uuid"
local dataModel = require "base.data_model"
local item_type_mgr = require "items.item_type_mgr"

-- 初始化道具策略分发中心
item_type_mgr.init()

-- 道具的容器负责数据持有 和行为解耦 用策略模式选择处理函数 以及对外提供统一接口
local Item = {}
Item.__index = Item
setmetatable(Item, {__index = dataModel})

-- 基础属性 会自动生成 get/set 函数
-- 注意:DEFAULT_DATA 的 value 不能为 nil(否则该 key 不会被存入 table,init_data 循环失效,
--       Item 的 get_/set_ 方法无法被自动生成)
Item.DEFAULT_DATA = {
    owner_id = 0,               -- 拥有者uid
    id = 0,                     -- item唯一id 每个道具唯一 和导表无关
    item_id = "",               -- 道具导表id 同 导表 itemId
    type = "",                  -- 道具类型 同 导表 itemType
    amount = 0,                 -- 道具数量
    name = "",                  -- 道具命名
    trade = 0,                  -- 是否可交易(0/1)
    bage_type = "",             -- 当前所在的背包类型
}

-- 创建的时候 直接通过data注入数据
function Item:new(data)
    local self = setmetatable({}, Item)
    self:init_data(data)
    return self
end

function Item:on_create()
    if self:get_id() == nil then
        self:create_init_data()
    end
end

function Item:create_init_data()
    self:set_id(uuid.genid())
end

-- 基础存盘字段
function Item:get_bas_persistent()
    return self:get_data()
end

-- 额外存盘字段 现在暂时没用到
function Item:get_extra_persistent()
    return {}
end

-- 存盘数据
function Item:get_persistent_table()
    local data = {}
    util.tab.update(data, self:get_bas_persistent())
    util.tab.update(data, self:get_extra_persistent())
    return data
end

-- 策略处理
function Item:get_handler()
    return item_type_mgr.get_handler(self.type)
end

function Item:can_use(user_obj, amount)
    return self:get_handler():can_use(user_obj, amount)
end

function Item:use(user_obj, amount)
    return self:get_handler():use(user_obj, amount)
end

function Item:can_sell()
    return self:get_handler():can_sell()
end

function Item:can_gift()
    return self:get_handler():can_gift()
end


-- 下发给客户的的数据
function Item:get_sync_client_data()
    return {
        id = self:get_item_id(),
        amount = self:get_amount(),
    }
end


-- 对外接口 
function Item.create_Item(data)
    local item_obj = Item:new(data)
    item_obj:on_create()
    return item_obj
end

return Item