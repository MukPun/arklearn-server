-- Agent ECS World 实例化
local World = require "ecs.core.world"
local AccountComponent = require "ecs.components.account"
local PlayerDataComponent = require "ecs.components.player_data"

local AgentWorld = {}

function AgentWorld.new(uid)
    local world = World.new()
    world.uid = uid
    world.dirty = false

    -- 注册组件
    world.components = {
        AccountComponent = AccountComponent,
        PlayerDataComponent = PlayerDataComponent,
    }

    return setmetatable(world, {__index = AgentWorld})
end

function AgentWorld:load_from_db(db_proxy)
    local db = require "skynet"
    local player_data = db.call(db_proxy, "lua", "load_player", self.uid)
    if player_data then
        self:add_component(self.uid, "PlayerDataComponent", PlayerDataComponent.new(player_data))
    end
end

function AgentWorld:mark_dirty()
    self.dirty = true
end

function AgentWorld:clear_dirty()
    self.dirty = false
end

return AgentWorld