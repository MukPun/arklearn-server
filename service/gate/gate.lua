-- 消息路由 只做消息转发
local skynet = require "skynet"
local gateserver = require "snax.gateserver"
local util = require "common.util"
local struct = require "common.struct"

local watchdog
local connection = {}	-- fd -> connection : { fd , client, desServer , ip }

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
}

local function newLinkObj(fd, addr)
	local linkObj = Deepcopy(struct.login.linkObj)
	linkObj.fd = fd
	linkObj.ip = addr
	return linkObj
end

local handler = {}

function handler.open(source, conf)
	watchdog = conf.watchdog or source
	return conf.address, conf.port
end

function handler.message(fd, msg, sz)
	-- recv a package, forward it
	local c = connection[fd]
	local desServer = c.desServer
	if desServer then
		-- 这里由gate重定向了数据直接发送到desServer
		-- It's safe to redirect msg directly , gateserver framework will not free msg.
		skynet.redirect(desServer, c.client, "client", fd, msg, sz)
	else
		skynet.send(watchdog, "lua", "socket", "data", fd, skynet.tostring(msg, sz))
		-- skynet.tostring will copy msg to a string, so we must free msg here.
		skynet.trash(msg,sz)
	end
end

-- socket accept成功
function handler.connect(fd, addr)
	local linkObj = newLinkObj(fd, addr)
	-- 初始 desServer 为 nil，消息走 else 到 watchdog 校验
	connection[fd] = linkObj
	skynet.send(watchdog, "lua", "socket", "open", linkObj)
end

local function unforward(c)
	if c.agent then
		c.agent = nil
		c.client = nil
	end
	if c.desServer then
		c.desServer = nil
	end
end

local function close_fd(fd)
	local c = connection[fd]
	if c then
		unforward(c)
		connection[fd] = nil
	end
end

function handler.disconnect(fd)
	close_fd(fd)
	skynet.send(watchdog, "lua", "socket", "close", fd)
end

function handler.error(fd, msg)
	close_fd(fd)
	skynet.send(watchdog, "lua", "socket", "error", fd, msg)
end

function handler.warning(fd, size)
	skynet.send(watchdog, "lua", "socket", "warning", fd, size)
end

local CMD = {}

function CMD.forward(source, fd, client, address)
	local c = assert(connection[fd])
	unforward(c)
	c.client = client or 0
	c.agent = address or source
	gateserver.openclient(fd)
end

function CMD.accept(source, fd)
	local c = assert(connection[fd])
	unforward(c)
	gateserver.openclient(fd)
end

function CMD.kick(source, fd)
	gateserver.closeclient(fd)
end

-- 设置路由 这里先简单的实现, 因为这里只能转发到 注册了client协议的服务
function CMD.setRoute(source, fd, desServer)
	local c = connection[fd]
	if c then
		c.desServer = desServer
		skynet.error("[gate] setRoute fd:", fd, "desServer:", desServer, "source: ", source )
	end
end

-- 设置客户端标识（用于 redirect 回复）
function CMD.set_client(source, fd, client)
	local c = assert(connection[fd])
	c.client = client or 0
end

function handler.command(cmd, source, ...)
	local f = assert(CMD[cmd])
	return f(source, ...)
end

gateserver.start(handler)
