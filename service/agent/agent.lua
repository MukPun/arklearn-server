-- Agent 服务：玩家在服务端的代理
local skynet = require "skynet"
local AgentWorld = require "agent.world"

local agent = {
    world = nil,
    uid = nil,
}

local CMD = {}

function CMD.start(uid, gate_service)
    agent.uid = uid
    agent.gate_service = gate_service

    -- 创建 ECS World
    agent.world = AgentWorld.new(uid)

    -- 异步加载玩家数据
    local db_proxy = skynet.uniqueservice("db_proxy", "lua")
    agent.world:load_from_db(db_proxy)

    return true
end

function CMD.query_player_data(uid)
    if uid ~= agent.uid then
        return nil
    end
    return agent.world:get_component(agent.uid, "PlayerDataComponent")
end

function CMD.get_fight_power(uid)
    local player_data = agent.world:get_component(agent.uid, "PlayerDataComponent")
    if not player_data then
        return 0
    end
    -- 简化计算：level * 10 + sum(char elite * level)
    local power = player_data.level * 10
    for _, char in pairs(player_data.charList) do
        power = power + char.elite * char.level
    end
    return power
end

function CMD.handle_game_message(cmd, ...)
    local f = agent[cmd] or CMD[cmd]
    if f then
        return f(...)
    end
    return {error_code = 1003, message = "unknown command"}
end

function CMD.logout()
    -- 保存数据
    local db_proxy = skynet.uniqueservice("db_proxy", "lua")
    local player_data = agent.world:get_component(agent.uid, "PlayerDataComponent")
    if player_data then
        skynet.call(db_proxy, "lua", "save_player", agent.uid, player_data)
    end
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if f then
            local ret = f(...)
            if session > 0 then
                skynet.ret(skynet.pack(ret))
            end
        end
    end)
end)