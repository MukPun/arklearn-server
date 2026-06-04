-- Agent 服务：玩家在服务端的代理
local skynet = require "skynet"
local AgentWorld = require "agent.world"
local const = require "const"
local sprotoloader = require "sprotoloader"
local dispatcher = require "dispatcher"
local log = require "log"
local c2s_sproto

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
    obj.dispatcher = nil        -- 协议分发
    return setmetatable(obj, Agent)
end

-- Agent初始化入口
function Agent:start(conf)
    self.gate = conf.gate
    -- 创建 ECS World
    self.world = AgentWorld.new(self.uid)

    -- 异步加载玩家数据
    local db_proxy = skynet.uniqueservice("db_proxy", "lua")
    self.world:load_from_db(db_proxy)

    -- 加载协议
	c2s_sproto = sprotoloader.load(1)
    self.dispatcher_obj = dispatcher.new(c2s_sproto)
    self.dispatcher_obj:register_all_handlers()
    return true
end

function Agent:query_player_data(uid)
    if uid ~= self.uid then
        return nil
    end
    return self.world:get_component(self.uid, "PlayerDataComponent")
end

function Agent:get_fight_power(uid)
    local player_data = self.world:get_component(self.uid, "PlayerDataComponent")
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
    local f = self[cmd] or self.CMD[cmd]
    if f then
        return f(...)
    end
    return {error_code = 1003, message = "unknown command"}
end

function Agent:logout()
    -- 保存数据
    local db_proxy = skynet.uniqueservice("db_proxy", "lua")
    local player_data = self.world:get_component(self.uid, "PlayerDataComponent")
    if player_data then
        skynet.call(db_proxy, "lua", "save_player", self.uid, player_data)
    end
end


function Agent:client_dispatch(_, _, msg)
    -- 客户端请求处理
    local tag, msg = string.unpack(">I4c"..#msg-4, msg)
    local sproto_type = c2s_sproto:queryproto(tag)
    if sproto_type and sproto_type.name then
        local args = c2s_sproto:request_decode(tag, msg)  -- 解码获取参数
        local name = sproto_type.name       -- 协议名称
        local handle_ok, response = pcall(self.dispatcher_obj.handle, self.dispatcher_obj, self.user_info, name, args)
        log.log("[agent ]client_dispatch proto:%s, ok: %s", sproto_type.name, handle_ok)
        local response_ok, response_str = pcall(c2s_sproto.response_encode, c2s_sproto, tag, response)
        if response_ok then
            skynet.ret(response_str)
        else
            skynet.error("msgagent handle proto failed!", sproto_type.name)
            skynet.ignoreret()
        end

    else
        skynet.error("recieve wrong proto string : ", msg)
        skynet.ignoreret()
    end

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