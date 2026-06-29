-- user 组件基类

local ComponentBase = {}
ComponentBase.__index = ComponentBase


-- 获取用于存盘数据
function ComponentBase:get_persistent_table()
    return {}
end

-- 从数据库加载数据
function ComponentBase:apply_data(data)
end