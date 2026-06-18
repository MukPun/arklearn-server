-- Agent ECS World 实例化
local skynet = require "skynet"
local World = require "ecs.core.world"
local AccountComponent = require "ecs.components.account"
local PlayerDataComponent = require "ecs.components.player_data"
local const = require "const"


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
    local player_data = skynet.call(const.public_server_name.DB_SERVER, "lua", "findOne", "players", {_id = self.uid})
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