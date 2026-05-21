-- Agent Manager：管理 Agent 的创建和销毁（OOP 模式）
local skynet = require "skynet"

-- AgentManager 类
local AgentManager = {}
AgentManager.__index = AgentManager

function AgentManager.new()
    return setmetatable({agents = {}}, AgentManager)
end

function AgentManager:create_agent(uid, gate_service)
    -- 踢掉旧 Agent
    if self.agents[uid] then
        pcall(skynet.call, self.agents[uid], "lua", "logout")
    end

    -- 创建新 Agent
    local agent_service = skynet.newservice("agent")
    skynet.call(agent_service, "lua", "start", uid, gate_service)

    self.agents[uid] = agent_service
    return agent_service
end

function AgentManager:get_agent(uid)
    return self.agents[uid]
end

function AgentManager:remove_agent(uid)
    if self.agents[uid] then
        pcall(skynet.call, self.agents[uid], "lua", "logout")
        self.agents[uid] = nil
    end
end

function AgentManager:list_online_players()
    local online = {}
    for uid, _ in pairs(self.agents) do
        table.insert(online, uid)
    end
    return online
end

-- Skynet 入口
local manager = AgentManager.new()

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = manager[cmd]
        if f then
            local ret = f(manager, ...)
            if session > 0 then
                skynet.ret(skynet.pack(ret))
            end
        end
    end)
end)