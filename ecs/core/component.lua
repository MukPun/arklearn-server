-- Component 基类：纯数据载体

local Component = {}
Component.__index = Component

function Component.new(data)
    local self = setmetatable({}, Component)
    for k, v in pairs(data or {}) do
        self[k] = v
    end
    return self
end

return Component