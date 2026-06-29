-- 数据驱动模式基类
-- 继承后会把需要存盘的数据保存在 self._data 中
local util = require "util"
local DataModel = {}
DataModel.__index = DataModel

-- 子类需要覆盖这个表，定义自己有哪些字段以及对应的默认值
DataModel.DEFAULT_DATA = {} 

-- 构造函数
function DataModel:new(sub_obj)
    sub_obj = sub_obj or {}
    -- 统一在此处初始化数据容器
    sub_obj._data = {}
    setmetatable(sub_obj, self)
    return sub_obj
end

function DataModel:init_data(data)
    self._data = {}
    data = data or {}

    for k, v in pairs(data) do
        self._data[k] = v
    end

    for key, default_val in pairs(self.DEFAULT_DATA) do
        if self._data[key] == nil then
            -- 注意：如果 default_val 是 table，这里需要用深拷贝(deepcopy)
            -- 简单数据类型(number, string, boolean)直接赋值即可
            self._data[key] = default_val
        end
        -- 自动创建对应的get/set方法
        DataModel["set_" .. tostring(key)] = function (self, value)
            self:set_var(key, value)
        end
        DataModel["get_" .. tostring(key)] = function (self)
            return self:get_var(key)
        end
    end
end

function DataModel:get_var(key)
    return self._data[key]
end

function DataModel:set_var(key, value)
    self._data[key] = value
end

function DataModel:smart_get_var(key)
    local func_name = "get_" .. tostring(key)
    if self[func_name] ~= nil then
        return self:func_name()
    else
        return self:get_var(key)
    end
end

function DataModel:smart_set_var(key, value)
    local func_name = "set_" .. tostring(key)
    if self[func_name] ~= nil then
        self:func_name(value)
    else
        self:set_var(key, value)
    end
end

function DataModel:get_data()
    return self._data
end

return DataModel