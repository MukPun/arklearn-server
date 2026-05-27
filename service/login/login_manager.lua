-- Login Manager：登录主服务，处理客户端的
-- 连接请求
-- 账密校验
local skynet = require "skynet"
local crypt = require "skynet.crypt"
local core = require "sproto.core"
local config = require "etc.login_cfg"
local socket = require "skynet.socket"

-- 获取 .package 类型用于解析 header
local package_type = core.querytype(c2s_proto.__cobj, "package")

local db_proxy = nil
local worker_pools = {}         -- {workeId -> workerServerId}
local user_online = {}  -- 在线的玩家 {uid = {agent, device_id, token, gate, fd}} 
local user_login = {}       -- 登录中的用户
local queue_max = 1000
local frame_limit = 50
local queue_timeout = 10
local worker_count = 8
local worker_index = 1      -- 当前workeId
local socket_error = {}
local server_list = {}      -- {server_name -> server_id} 服务名 映射 服务句柄


local function assert_socket(service, v, fd)
	if v then
		return v
	else
		skynet.error(string.format("%s failed: socket (fd = %d) closed", service, fd))
		error(socket_error)
	end
end

local function write(service, fd, text)
	assert_socket(service, socket.write(fd, text), fd)
end


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


-- 登录处理
local function login_handler(server, uid, secret)
    print(string.format("%s@%s is login, secret is %s", uid, server, crypt.hexencode(secret)))
	local gameserver = assert(server_list[server], "Unknown server")        -- 获取角色目标服务器
	-- only one can login, because disallow multilogin
	local last = user_online[uid]       -- 查看玩家是否已经登录
	if last then
        -- 顶号：踢掉旧连接
		skynet.call(last.address, "lua", "kick", uid, last.subid)
	end
	if user_online[uid] then
		error(string.format("user %s is already online", uid))
	end
    -- 请求游戏服 进行登录请求
	local subid = tostring(skynet.call(gameserver, "lua", "login", uid, secret))
	user_online[uid] = { address = gameserver, subid = subid , server = server}
	return subid
end


local function get_worker(fd)
    local worker = worker_pools[worker_index]
    worker_index = worker_index + 1

    if worker_index > #worker_pools then
        worker_index = 1
    end 
    return worker
end

-- 处理建立连接后的逻辑
local function accept_handle(worker, fd, addr)
    -- 通知worker 进行验证
    -- 返回 结果 玩家的分配的路由id uid  
    local ok, server, uid, secret = skynet.call(worker, "lua", "auth_fd", fd, addr)
    -- worker 处理 验证

    if not ok then
		if ok ~= nil then
			write("response 401", fd, "401 Unauthorized\n")
		end
		error(server)
    end

    if not config.multilogin then
        -- 是否允许重复登录
        if user_login[uid] then
			write("response 406", fd, "406 Not Acceptable\n")
			error(string.format("User %s is already login", uid)) 
        end
        user_login[uid] = true
    end

	local ok, err = pcall(login_handler, server, uid, secret)
	-- unlock login
	user_login[uid] = nil

    if ok then
        -- 登录成功 返回结果给客户端
		err = err or ""
		write("response 200", fd,  "200 "..crypt.base64encode(err).."\n")
	else
		write("response 403", fd,  "403 Forbidden\n")
		error(err)
	end
end

-- 和客户端建立好连接后
local function accept(fd, addr)
    -- 分发worker 给客户端连接
    local worker = get_worker(fd)
    local ok, err = pcall(accept_handle, worker, fd, addr)
    if not ok then
        if err ~= socket_error then
            skynet.error(string.format("invalid client (fd = %d) error = %s", fd, err))
        end
    end
    socket.close(fd)
end

-- 启动 Worker 处理验证服务
local function launchWorker()
    
end
local CMD = {}

-- 启动 Manager：登录主服务
local function launchManager()
    -- 注册socket监听端口 单独处理客户端发来的协议 处理 登录
    skynet.error("[Ark Login Server] launch manager...")
	local workerCount = config.worker_count or 8
	assert(workerCount > 0)
	local host = config.host or "0.0.0.0"
	local port = assert(tonumber(config.port))

    -- 注册服务间调用处理器
	skynet.dispatch("lua", function(_,source,command, ...)
		skynet.ret(skynet.pack(CMD[command](...)))
	end)

    -- 初始化 Worker 池
    for i = 1, worker_count do
        worker_pools[i] = skynet.newservice("login/login_worker")
    end

	skynet.error(string.format("[Ark Login Server] login server listen at : %s %d", host, port))
    -- 启动监听 待回调后执行 accept
    local socketId = socket.listen(host, port)
    socket.start(socketId, accept)
end

-- 服务启动
skynet.start(function()
    -- launch Manager 
    skynet.error("[Ark Login Server] login manager starting...")
    skynet.register(config.name or "login_manager")
    launchManager()
end)

-- 注册 游戏服映射 
-- 通常是服务器名 映射到 gate的服务句柄
function CMD.register_gate(server, address)
	server_list[server] = address
end
