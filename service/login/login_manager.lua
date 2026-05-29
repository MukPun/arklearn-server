-- Login Manager：登录主服务，处理客户端的
-- 连接请求
-- 账密校验
require "skynet.manager"
local skynet = require "skynet"
local crypt = require "skynet.crypt"
local config = require "login_cfg"
local socket = require "skynet.socket"

local db_proxy = nil
local worker_pools = {}         -- {workeId -> workerServerId}
local user_online = {}  -- 在线的玩家 {uid = {agent, device_id, token, gate, fd}} 
local user_login = {}       -- 登录中的用户
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
    skynet.error("[Ark Login Manager] launch manager...")
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
        skynet.error(string.format("[Ark Login worker] id: %d", i))
    end

	skynet.error(string.format("[Ark Login Manager] login server listen at : %s %d", host, port))
    -- 启动监听 待回调后执行 accept
    local socketId = socket.listen(host, port)
    socket.start(socketId, accept)
end

-- 服务启动
skynet.start(function()
    -- launch Manager 
    skynet.error("[Ark Login Manager] login manager starting...")
    skynet.register(config.name or ".LoginManager")
    launchManager()
end)

-- 注册 游戏服映射 
-- 通常是服务器名 映射到 gate的服务句柄
function CMD.register_gate(server, address)
	server_list[server] = address
end
