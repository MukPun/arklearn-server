-- Agent Manager：管理 Agent 的创建和销毁
local skynet = require "skynet"

local CMD = {}
local agents = {}  -- {uid = agent_service_address}

function CMD.create_agent(uid, gate_service)
    if agents[uid] then
        -- 踢掉旧 Agent
        pcall(skynet.call, agents[uid], "lua", "logout")
    end

    -- 创建新 Agent
    local agent_service = skynet.newservice("agent")
    skynet.call(agent_service, "lua", "start", uid, gate_service)

    agents[uid] = agent_service
    return agent_service
end

function CMD.get_agent(uid)
    return agents[uid]
end

function CMD.remove_agent(uid)
    if agents[uid] then
        pcall(skynet.call, agents[uid], "lua", "logout")
        agents[uid] = nil
    end
end

function CMD.list_online_players()
    local online = {}
    for uid, _ in pairs(agents) do
        table.insert(online, uid)
    end
    return online
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