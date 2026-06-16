-- Agent 服务：玩家在服务端的代理
local skynet = require "skynet"
local AgentWorld = require "agent.world"
local const = require "const"
local sprotoloader = require "sprotoloader"
local dispatcher = require "dispatcher"
local logger = require "log"
local util = require "util"
local c2s_sproto
local host
local request


skynet.register_protocol { -- 注册client类型消息的处理方式
	name = "client",
	id = skynet.PTYPE_CLIENT,
	unpack = skynet.tostring,
}

local function log(fmt, ...)
    logger.format("[Agent ]" .. fmt, ...)
end

-- Agent类
local Agent = {}
Agent.__index = Agent
Agent.CMD = {}

function Agent.new()
    local obj = {}
    obj.gate = nil              -- gate 服务句柄
    obj.socketFd = nil          -- socket 唯一id
    obj.world = nil
    obj.uid = nil
    obj.state = const.loginState.LOGIN_STATE_NONE      -- Agent 状态 未登录、登录中、登录成功、登录失败
    obj.dispatcher = nil        -- 协议分发
    return setmetatable(obj, Agent)
end

-- Agent初始化入口
function Agent:start(source, uid, sid, secret, mgr_addr)
    skynet.error(source, uid, sid, secret, mgr_addr)
    self.gate = source
    self.uid = uid
    self.mgr_addr = mgr_addr
    log("uid is :", uid, "sid is :", sid)
    -- 创建 ECS World
    self.world = AgentWorld.new(self.uid)

    -- 异步加载玩家数据
    local db_server = skynet.uniqueservice("db/dbserver", "lua")
    self.world:load_from_db(db_server)

    -- 加载协议
	c2s_sproto = sprotoloader.load(1)
    host = c2s_sproto:host("package")                 -- 用于解包 c2s的协议
    request = host:attach(sprotoloader.load(2))       -- 用于s2c主动发送协议时,打包数据
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
    local db_server = skynet.uniqueservice("db/dbserver", "lua")
    local player_data = self.world:get_component(self.uid, "PlayerDataComponent")
    if player_data then
        skynet.call(db_server, "lua", "update", "players", {uid = self.uid}, player_data)
    end
    -- 通知 Agent Mgr
    skynet.call(self.mgr_addr, "lua", "logout", self.uid)
end


function Agent:client_dispatch(msg)
    -- 客户端请求处理
    log("client_dispatch1 msg=%s", msg)
    local type, protoname, result, gen_response, ud = host:dispatch(msg)
    skynet.error("client_dispatch", "type: ", type, "name: ", protoname, "result: ", result, "gen_response:", gen_response, "ud", ud)
    local handler = self.dispatcher_obj:get_handler_by_name(protoname)
    if handler then
        local ok, response = pcall(handler, args)
        skynet.error("Agent:client_dispatch ok:", ok, "response:", util.Dumpstr(response))
        if ok and gen_response ~= nil then
            -- 按照协议 response协议编码 数据 返回给客户的
            local encode_ok, response_str = pcall(gen_response, response)
            skynet.error("Agent:client_dispatch encode_ok:", encode_ok, "response_str", response_str)
            if encode_ok then
                skynet.ret(response_str)
            else
                skynet.error("agent handle proto failed!", " name:", protoname)
                skynet.ignoreret()
            end
        else
            skynet.ignoreret()
        end
    end
end



function Agent.CMD:start(source, uid, sid, secret, mgr_addr)
    return self:start(source, uid, sid, secret, mgr_addr)
end


function Agent.CMD:afk()
    -- TODO: 标记玩家离线、清理资源
    return true
end

function Agent.CMD:logout()
    return self:logout()
end


local agentObj = Agent.new()

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        skynet.error("call agent session", session, cmd)
        local f = agentObj.CMD[cmd]
        if f then
            if session > 0 then
                skynet.ret(skynet.pack(f(agentObj, ...)))
            end
        end
    end)
    skynet.dispatch("client", function (_, _, msg)
        agentObj:client_dispatch(msg)
    end)
end)