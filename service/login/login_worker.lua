-- Login Worker：执行 密码验证，不阻塞主服务
local skynet = require "skynet"
local crypt = require "skynet.crypt"
local socket = require "skynet.socket"
local db_config = require "etc.database_cfg"

local socket_error = {}

-- 验证逻辑
local function auth_handler(token)
	-- the token is base64(user)@base64(server):base64(password)
	local user, server, password = token:match("([^@]+)@([^:]+):(.+)")
	user = crypt.base64decode(user)
	server = crypt.base64decode(server)
	password = crypt.base64decode(password)
    skynet.error("[Ark login worker] auth_handler: ", user, server, password)
    -- 请求MongoDB user 获取角色数据进行校验
    local accountServer = skynet.localname(db_config.name)
    local is_succeed, result = skynet.call(accountServer, "lua", "select_by_key", "Account", "account_id", user)
    if is_succeed then
        local account_data = result and result[1]
        if account_data and account_data.uid and account_data.password then
            assert(password == account_data.password, "Invalid password")
        end
    else
        -- 查询数据库失败
        assert(false, "Invalid account")
    end
	return server, user
    
end

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


-- 打包结果
local function ret_pack(ok, err, ...)
    if ok then
        return skynet.pack(err, ...)
    else
        if err == socket_error then
            return skynet.pack(nil, "socket error")
        else
            return skynet.pack(false, err)
        end
    end
end

-- 采用skynet提供的账密校验方式
local function auth(fd, addr)
		-- set socket buffer limit (8K) 设置 socket 接收缓冲区的最大限制
		-- If the attacker send large package, close the socket
		socket.limit(fd, 8192)

		local challenge = crypt.randomkey()
		write("auth", fd, crypt.base64encode(challenge).."\n")

		local handshake = assert_socket("auth", socket.readline(fd), fd)
		local clientkey = crypt.base64decode(handshake)
		if #clientkey ~= 8 then
			error "Invalid client key"
		end
		local serverkey = crypt.randomkey()
		write("auth", fd, crypt.base64encode(crypt.dhexchange(serverkey)).."\n")

		local secret = crypt.dhsecret(clientkey, serverkey)

		local response = assert_socket("auth", socket.readline(fd), fd)
		local hmac = crypt.hmac64(challenge, secret)

		if hmac ~= crypt.base64decode(response) then
			error "challenge failed"
		end

		local etoken = assert_socket("auth", socket.readline(fd),fd)

		local token = crypt.desdecode(secret, crypt.base64decode(etoken))
        -- 游戏业务层 校验 token 并且返回 登录的服务名、 用户uid
		local ok, server, uid =  pcall(auth_handler, token)

		return ok, server, uid, secret
end

local CMD = {}

function CMD.auth_fd(fd, addr)
    skynet.error(string.format("[Ark Login Worker]connect from %s (fd = %d)", addr, fd))
    socket.start(fd)	-- may raise error here
    local msg, len = ret_pack(pcall(auth, fd, addr))
    socket.abandon(fd)	-- never raise error here
    return msg, len
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if f then
            local ok, msg, len = pcall(f, ...)
            if ok then
                skynet.ret(msg, len)
            else
                skynet.ret(skynet.pack(false, msg))
            end
        end
    end)
    skynet.register("login_worker")
end)