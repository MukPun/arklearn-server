-- Login Worker：执行 密码验证，不阻塞主服务
require "skynet.manager"
local skynet = require "skynet"
local crypt = require "skynet.crypt"
local socket = require "skynet.socket"
local logger = require "log"
local const = require "const"
local util = require "util"

local socket_error = {}

local function log(fmt, ...)
	logger.format("[Ark Login Worker] " .. fmt, ...)
end

-- 验证逻辑
local function auth_handler(token)
	-- the token is base64(user)@base64(server):base64(password)
	local user, server, password = token:match("([^@]+)@([^:]+):(.+)")
	user = crypt.base64decode(user)		-- 账号名
	server = crypt.base64decode(server)	-- 登录 目标服务器
	password = crypt.base64decode(password)	-- 账号密码
    log("do auth: ", user, server, password)
    -- 请求MongoDB获取账号数据进行校验
    local account_data = skynet.call(const.public_server_name.DB_SERVER, "lua", "findOne", "accounts", {name = user})
    if account_data and account_data.uid and account_data.password then
        assert(password == account_data.password, "Invalid password")
    else
        assert(false, "Invalid account")
    end
	log("auth success: %s", util.Dumpstr(account_data))
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
		log("start auth.")
		local challenge = crypt.randomkey()
		write("auth", fd, crypt.base64encode(challenge).."\n")		-- 下发 challenge 给客户端

		local handshake = assert_socket("auth", socket.readline(fd), fd)
		local clientkey = crypt.base64decode(handshake)		-- 解码获取客户端发送的 随机clientkey
		if #clientkey ~= 8 then
			error "Invalid client key"
		end
		local serverkey = crypt.randomkey()			-- 获取随机 serverkey
		write("auth", fd, crypt.base64encode(crypt.dhexchange(serverkey)).."\n")		-- 通过dhexchange生成公钥发送给客户端

		local secret = crypt.dhsecret(clientkey, serverkey)		-- 通过对方公钥、自己公钥serverkey 算出一致共享密钥

		local response = assert_socket("auth", socket.readline(fd), fd)		-- 接收客户端发送的hmac
		local hmac = crypt.hmac64(challenge, secret)		-- 用共同密钥 对 challenge进行加密 获得hmac

		if hmac ~= crypt.base64decode(response) then		-- 校验双端的 hmac是否一致
			error "challenge failed"
		end

		local etoken = assert_socket("auth", socket.readline(fd),fd)		-- 接收客户端发来的编码后的token

		local token = crypt.desdecode(secret, crypt.base64decode(etoken))		-- 解码token
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
end)