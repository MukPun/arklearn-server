-- Login Manager：登录主服务，处理登录协议
-- 接收客户端 sproto 消息，自主解析和打包
local skynet = require "skynet"
local crypt = require "skynet.crypt"
local sproto = require "sproto"
local sprotoloader = require "sprotoloader"
local core = require "sproto.core"

-- 加载协议
local protoloader = require "protoloader"
protoloader.load({"proto.c2s", "proto.s2c"})

local c2s_proto = sprotoloader.load(protoloader.index("proto.c2s"))
local s2c_proto = sprotoloader.load(protoloader.index("proto.s2c"))

-- 获取 .package 类型用于解析 header
local package_type = core.querytype(c2s_proto.__cobj, "package")

local CMD = {}
local db_proxy = nil
local worker_pools = {}
local online_players = {}  -- {uid = {agent, device_id, token, gate, fd}}
local queue_max = 1000
local frame_limit = 50
local queue_timeout = 10
local worker_count = 8

-- 发送 sproto 响应
local function send_response(gate_service, client, fd, tag, protoname, response_data)
    -- 获取协议信息
    local p = s2c_proto:queryproto(protoname)
    local resp = s2c_proto:encode(p.response, response_data)

    -- 构建 package header
    local header_tmp = {
        type = tag,
        session = 0,
        ud = "",
    }
    local header = s2c_proto:encode(".package", header_tmp)
    local packed = s2c_proto:pack(header .. resp)

    skynet.redirect(gate_service, client, "client", fd, packed, #packed)
end

local function handle_login(fd, content, gate_service, client)
    -- 解码登录请求
    local request = c2s_proto:decode("LoginRequest", content)
    local account = request.account
    local password_hash = request.password_hash
    local device_id = request.device_id

    skynet.error("Login request:", account, "device:", device_id)

    -- 检查是否在线（顶号）
    for uid, info in pairs(online_players) do
        if info.name == account then
            -- 顶号：踢掉旧连接
            skynet.call(info.gate, "lua", "kick", info.fd)
            online_players[uid] = nil
        end
    end

    -- 查询账号
    local account_data = skynet.call(db_proxy, "lua", "query_account", account)
    if not account_data then
        send_response(gate_service, client, fd, 2, "login", {error_code = 2})
        return
    end

    -- 派发验证给 Worker
    local worker = worker_pools[math.random(1, worker_count)]
    local ok = skynet.call(worker, "lua", "verify", password_hash, account_data.password)
    if not ok then
        send_response(gate_service, client, fd, 2, "login", {error_code = 3})
        return
    end

    -- 创建 Agent
    local agent_mgr = skynet.uniqueservice("agent_mgr")
    local agent = skynet.call(agent_mgr, "lua", "create_agent", {
        fd = fd,
        gate = gate_service,
        uid = account_data.uid,
    })

    -- 生成 token
    local token = crypt.base64encode(crypt.randomkey())

    -- 记录在线
    online_players[account_data.uid] = {
        name = account,
        agent = agent,
        gate = gate_service,
        fd = fd,
        token = token,
        device_id = device_id,
    }

    -- 切换 Gate 路由目标到 Agent
    skynet.call(gate_service, "lua", "setRoute", fd, agent)
    skynet.call(gate_service, "lua", "set_client", fd, client)

    -- 通知 Agent 登录成功
    skynet.send(agent, "lua", "on_login_success", fd, client, account_data.uid)

    -- 发送登录成功响应
    send_response(gate_service, client, fd, 2, "login", {
        error_code = 0,
        uid = account_data.uid,
        token = token,
    })
end

local function handle_register(fd, content, gate_service, client)
    -- 解码注册请求
    local request = c2s_proto:decode("RegisterRequest", content)
    local account = request.account
    local password_hash = request.password_hash
    local device_id = request.device_id

    skynet.error("Register request:", account)

    -- 查询账号是否存在
    local exist = skynet.call(db_proxy, "lua", "query_account", account)
    if exist then
        send_response(gate_service, client, fd, 2, "register", {error_code = 1})
        return
    end

    -- 创建账号
    local uid = os.time()  -- 临时 uid 生成
    local account_data = {
        name = account,
        password = password_hash,
        uid = uid,
    }
    local ok, err = skynet.call(db_proxy, "lua", "create_account", account_data)
    if not ok then
        send_response(gate_service, client, fd, 2, "register", {error_code = 3, error = err})
        return
    end

    -- 创建玩家数据
    local player_data = {
        uid = uid,
        name = account,
        level = 1,
        exp = 0,
        reason = 100,
        charList = {},
        squad = {},
        desktopChar = "",
        items = {},
        permissions = {},
    }
    skynet.call(db_proxy, "lua", "create_player", player_data)

    send_response(gate_service, client, fd, 2, "register", {
        error_code = 0,
        uid = uid,
    })
end

function CMD.init(conf)
    -- 初始化 Worker 池
    for i = 1, worker_count do
        worker_pools[i] = skynet.newservice("login_worker")
    end

    -- 初始化配置
    queue_max = conf.queue_max or queue_max
    frame_limit = conf.frame_limit or frame_limit
    queue_timeout = conf.queue_timeout or queue_timeout

    skynet.error("Login manager initialized")
end

-- 处理客户端消息（由 gate redirect过来）
function CMD.client_message(fd, msg, sz, gate_service, client)
    -- 解包 sproto
    local bin = core.unpack(msg, sz)

    -- 解析 package header
    local header = {}
    local header_size = core.decode(package_type, bin, header)
    local content = bin:sub(header_size + 1)
    local tag = header.type

    if tag == 1 then  -- login
        handle_login(fd, content, gate_service, client)
    elseif tag == 2 then  -- register
        handle_register(fd, content, gate_service, client)
    else
        skynet.error("Unknown protocol tag:", tag)
        send_response(gate_service, client, fd, 2, "login", {error_code = 1001})
    end
end

-- 定时处理
skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        if cmd == "client_message" then
            -- 客户端消息：fd, msg, sz, gate_service, client
            local fd, msg, sz, gate_service, client = ...
            CMD.client_message(fd, msg, sz, gate_service, client)
            if session > 0 then
                skynet.ret(skynet.pack(nil))
            end
        else
            local f = CMD[cmd]
            if f then
                local ret = f(...)
                if session > 0 then
                    skynet.ret(skynet.pack(ret))
                end
            end
        end
    end)
end)