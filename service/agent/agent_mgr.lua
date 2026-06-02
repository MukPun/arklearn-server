-- Agent Manager：管理 Agent 的创建和销毁（OOP 模式）
require "skynet.manager"
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


-- 登录服处理完登录后,通过gate服调用
-- @param source 登录服句柄
-- @param uid 角色唯一 ID
-- @param sid 
-- @param secret 登录服分配的 secret
function AgentManager:login(source, uid, sid, secret)
    -- 尝试分配Agent
    -- 初始化Agent
    -- 待Agent初始化完成后添加到Agent列表，把结果返回给gate
    
    local agent = self:create_agent(source, uid, sid, secret)
    return true, "Allocation agent success", agent
end

-- 登录成功后创建 Agent
function AgentManager:create_agent(source, uid, sid, secret)
    -- 踢掉旧 Agent（如果存在）
    if self.agents[uid] then
        self:remove_agent(uid)
    end

    -- 创建新 Agent
    local agent_service = skynet.newservice("agent")
    skynet.call(agent_service, "lua", "start", source, uid, sid, secret)

    self.agents[uid] = {
        agent = agent_service,      -- 创建的Agent 服务句柄 TODO: 后续考虑用agent池优化
        gate = source,              -- 所属的gate 服务句柄
    }
    return agent_service
end

-- 获取指定 uid 的 信息
function AgentManager:get_agent(uid)
    return self.agents[uid]
end

-- 移除Agent
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
            local ret = f(manager, source, ...)
            if session > 0 then
                skynet.ret(skynet.pack(ret))
            end
        end
    end)
    skynet.register(".AgentManager")
end)