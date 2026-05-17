-- Entity: 实体标识，作为 Component 的容器
local Entity = {}
Entity.__index = Entity

function Entity.new(id)
    return setmetatable({
        id = id,
        components = {},
    }, Entity)
end

function Entity:add_component(component_type, data)
    self.components[component_type] = data
end

function Entity:get_component(component_type)
    return self.components[component_type]
end

function Entity:has_component(component_type)
    return self.components[component_type] ~= nil
end

function Entity:remove_component(component_type)
    self.components[component_type] = nil
end

return Entity