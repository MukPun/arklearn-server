-- game/dispatcher.lua
--
-- 协议分发:在 协议名称 和业务 handler 函数之间做映射。
--
-- 设计原则:
--   1. 所有处理客户端请求的协议必须在Dispatcher注册, 且存在c2s内。
--   2. 业务逻辑通过 game 模块的工厂函数 → 闭包 → 在 handler 内访问 agent
--   3. 纯函数式:输入 raw_msg,输出 packed_resp;handler 自身错误抛给调用方
--
--
-- 后续可扩展:
--   - server-push 主动发包(新增 :push(protocol_name, args) 方法)
--   - 中间件(超时/重试/限流/aop)通过包装 handler 实现
--   - 按 tag 数字注册替代协议名(便于和已有二进制数据兼容)


local module = {
    "game.account.account",
    "game.system.init"
}

local Dispatcher = {}
Dispatcher.__index = Dispatcher

-- 构造
-- 
function Dispatcher.new(c2s_sp)
    local self = setmetatable({}, Dispatcher)
    self.handlers = {}   -- 缓存:[sproto_name] = handle
    self.c2s = c2s_sp    -- c2s sproto
    return self
end


-- 注册所有模块的 handler
function Dispatcher:register_all_handlers()
    for i, module_name in ipairs(module) do
        local handlers = require(module_name)
        for sproto_name, handle in pairs(handlers) do
            self:register(sproto_name, handle)
        end
    end
end


-- 注册协议 handler
-- @param protocol_name  协议名(如 "LoginRequest"),必须存在于 c2s_sp
-- @param handler        业务函数 fun(req: table): table
-- @return self (链式调用)
function Dispatcher:register(protocol_name, handler)
    local proto = self.c2s:queryproto(protocol_name)
    assert(proto, string.format("Dispatcher:register protocol not found: %s",
                                tostring(protocol_name)))
    assert(type(handler) == "function", "Dispatcher:register handler must be a function")
    assert(not self.handlers[protocol_name], string.format("Dispatcher:register protocol already registered: %s",
                                                           tostring(protocol_name)))
    self.handlers[protocol_name] = handler
    return self
end


-- 获取协议处理函数
-- @param protocol_name 协议名
-- @return handler or nil
function Dispatcher:get_handler_by_name(protocol_name)
    -- 根据协议名称获取 处理函数
    return self.handlers[protocol_name]
end

-- 处理一条进站消息
-- 由外部完成按照协议格式解包后 把数据传递给本函数
-- 本函数负责找到对应的协议处理函数
-- @param user_info  接受协议的用户对象数据 TODO 正常是不只有发给用户的协议,也有单纯发给服务器的才对, 但是目前暂且先不考虑
-- @param type  数据类型 "REQUEST" 只能是 REQUEST
-- @param name  协议名称
-- @param args  解包后的数据
-- @

return Dispatcher
