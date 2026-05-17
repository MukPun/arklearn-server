-- World 管理器：管理 Entity、Component、Processor

local Entity = require "ecs.core.entity"

local World = {
    entities = {},           -- {[entity_id] = Entity}
    components = {},        -- {[component_type] = {[entity_id] = data}}
    processors = {},        -- {[processor_type] = Processor}
}

function World.new()
    return setmetatable(World, {__index = World})
end

function World:create_entity(entity_id)
    if self.entities[entity_id] then
        error(string.format("Entity %s already exists", entity_id))
    end
    local entity = Entity.new(entity_id)
    self.entities[entity_id] = entity
    return entity
end

function World:get_entity(entity_id)
    return self.entities[entity_id]
end

function World:remove_entity(entity_id)
    local entity = self.entities[entity_id]
    if entity then
        -- 清理所有组件
        for component_type, _ in pairs(entity.components) do
            self.components[component_type][entity_id] = nil
        end
        self.entities[entity_id] = nil
    end
end

function World:add_component(entity_id, component_type, data)
    if not self.components[component_type] then
        self.components[component_type] = {}
    end
    self.components[component_type][entity_id] = data
end

function World:get_component(entity_id, component_type)
    local component_table = self.components[component_type]
    return component_table and component_table[entity_id]
end

function World:has_component(entity_id, component_type)
    local component_table = self.components[component_type]
    return component_table and component_table[entity_id] ~= nil
end

function World:register_processor(processor_type, processor)
    self.processors[processor_type] = processor
end

function World:get_processor(processor_type)
    return self.processors[processor_type]
end

function World:update(dt)
    for _, processor in pairs(self.processors) do
        if processor.update then
            processor:update(dt)
        end
    end
end

return World