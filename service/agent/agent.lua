-- Agent 服务：玩家在服务端的代理
local skynet = require "skynet"
local AgentWorld = require "agent.world"
local const = require "common.const"

-- Agent类
local Agent = {}
Agent.__index = Agent

function Agent.new()
    local obj = {}
    obj.gate = nil              -- gate 服务句柄
    obj.socketFd = nil          -- socket 唯一id
    obj.world = nil
    obj.uid = nil
    obj.state = const.loginState.LOGIN_STATE_NONE      -- Agent 状态 未登录、登录中、登录成功、登录失败
    obj.CMD = {}                -- 处理其他服务的接口
    return setmetatable(obj, Agent)
end

-- Agent初始化入口
function Agent:start(conf)
    self.gate = conf.gate

    -- 创建 ECS World
    agent.world = AgentWorld.new(uid)

    -- 异步加载玩家数据
    local db_proxy = skynet.uniqueservice("db_proxy", "lua")
    agent.world:load_from_db(db_proxy)

    return true
end

function Agent:query_player_data(uid)
    if uid ~= agent.uid then
        return nil
    end
    return agent.world:get_component(agent.uid, "PlayerDataComponent")
end

function Agent:get_fight_power(uid)
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

function Agent:handle_game_message(cmd, ...)
    local f = agent[cmd] or CMD[cmd]
    if f then
        return f(...)
    end
    return {error_code = 1003, message = "unknown command"}
end

function Agent:logout()
    -- 保存数据
    local db_proxy = skynet.uniqueservice("db_proxy", "lua")
    local player_data = agent.world:get_component(agent.uid, "PlayerDataComponent")
    if player_data then
        skynet.call(db_proxy, "lua", "save_player", agent.uid, player_data)
    end
end


function Agent:client_dispatch(msg)
    -- 客户端请求处理

end


function Agent.CMD:common()
    -- 服务请求处理
    
end

local agentObj = Agent.new()

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = agentObj.CMD[cmd]
        if f then
            local ret = f(agentObj, ...)
            if session > 0 then
                skynet.ret(skynet.pack(ret))
            end
        end
    end)
    skynet.dispatch("client", agentObj.client_dispatch)
end)