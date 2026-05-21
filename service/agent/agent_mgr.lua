-- Agent Manager：管理 Agent 的创建和销毁（OOP 模式）
-- 单一映射表：uid 登录前代表 fd，登录后代表角色唯一 ID
local skynet = require "skynet"

-- AgentManager 类
local AgentManager = {}
AgentManager.__index = AgentManager

function AgentManager.new()
    local obj = {}
    obj.agents = {}  -- {[uid] = {agent, fd, gate, uid_type, ...}}
    return setmetatable(obj, AgentManager)
end

-- 连接时创建 Agent（uid 为 fd）
function AgentManager:create_agent(conf)
    -- 踢掉旧 Agent（如果存在）
    local fd = conf.fd
    if self.agents[fd] then
        self:remove_agent(fd)   -- 出现重复的fd 通常只有旧的fd c层的ss已经释放了, 但是lua层没有处理, 所以保险期间 还是把旧Agent关掉
    end

    -- 创建新 Agent
    local agent_service = skynet.newservice("agent")
    skynet.call(agent_service, "lua", "start", conf)

    self.agents[fd] = {
        agent = agent_service,
        fd = fd,
        gate = conf.gate,
        uid_type = "connection",  -- 登录前状态
    }
    return agent_service
end

-- 登录成功后绑定 uid（fd -> player_uid）
function AgentManager:bind_uid(fd, player_uid)
    if not self.agents[fd] then
        return false, "connection not found"
    end

    -- 同一 Agent，更新 uid
    local agent_data = self.agents[fd]
    self.agents[player_uid] = agent_data
    self.agents[fd] = nil
    agent_data.uid_type = "player"
    agent_data.player_uid = player_uid
    return true
end

function AgentManager:get_agent(uid)
    return self.agents[uid]
end

function AgentManager:remove_agent(uid)
    local agent_data = self.agents[uid]
    if agent_data then
        pcall(skynet.call, agent_data.agent, "lua", "logout")
        self.agents[uid] = nil
    end
end

function AgentManager:list_online_players()
    local online = {}
    for uid, data in pairs(self.agents) do
        if data.uid_type == "player" then
            table.insert(online, uid)
        end
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