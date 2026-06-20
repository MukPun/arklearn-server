-- Agent 服务：玩家在服务端的代理
local skynet = require "skynet"
local const = require "const"
local sprotoloader = require "sprotoloader"
local dispatcher = require "dispatcher"
local logger = require "log"
local User = require "game.char.user"
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
    obj.uid = nil
    obj.user = nil              -- User 对象(加载/持久化玩家数据)
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

    -- 加载玩家数据(userObj 接管持久化:从 entities collection 拉,set/get 全部走 self.user)
    self.user = User.new(self.uid, self)
    local load_ok, err = self.user:load()
    if not load_ok then
        -- 数据加载失败, 则拒绝登录, 避免污染数据
        error("user load error! reason: " .. tostring(err))
    end

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
    if not (self.user and self.user:is_loaded()) then
        return nil
    end
    -- 从 userObj 读数据拼装成 PlayerData 形状
    return self.user:get_safe_data()
end

function Agent:handle_game_message(cmd, ...)
    local f = self[cmd] or self.CMD[cmd]
    if f then
        return f(...)
    end
    return {error_code = 1003, message = "unknown command"}
end

function Agent:logout()
    -- 用 userObj 全量落盘(close 内部走 save_all)
    if self.user and self.user:is_loaded() then
        local ok, err = self.user:close()
        if not ok then
            skynet.error("Agent:logout user close failed:", err)
        end
    end
    -- 通知 Agent Mgr
    skynet.call(self.mgr_addr, "lua", "logout", self.uid)
end


function Agent:client_dispatch(msg)
    -- 客户端请求处理
    log("client_dispatch msg=%s", msg)
    -- host:dispatch 返回 (type, name, args, gen_response, ud)
    --   type = "REQUEST" / "RESPONSE"
    --   name = 协议名(REQUEST 时是协议名,RESPONSE 时是 nil)
    --   args = 解码后的 table(REQUEST 时是请求参数,RESPONSE 时是响应数据)
    --   gen_response = 编码 RESPONSE 的 closure(REQUEST 时)
    --   ud = 用户数据
    local _, protoname, args, gen_response = host:dispatch(msg)
    if not protoname then
        skynet.ignoreret()
        return
    end
    local handler = self.dispatcher_obj:get_handler_by_name(protoname)
    if not handler then
        skynet.error("Agent:client_dispatch no handler for:", protoname)
        skynet.ignoreret()
        return
    end
    -- 注入 self.user 作为 user_info(handler 签名约定为 function(user, args))
    local ok, response = pcall(handler, self.user, args)
    if not ok then
        skynet.error("Agent:client_dispatch handler error name=", protoname, " err=", response)
        skynet.ignoreret()
        return
    end
    -- RESPONSE 编码 + 回包
    if gen_response then
        local enc_ok, resp_pkg = pcall(gen_response, response)
        if enc_ok and type(resp_pkg) == "string" then
            skynet.ret(resp_pkg)
        else
            skynet.error("Agent:client_dispatch encode failed name=", protoname, " err=", resp_pkg)
            skynet.ignoreret()
        end
    else
        skynet.ignoreret()
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