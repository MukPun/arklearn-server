-- 消息业务逻辑  处理linkObj对象
local skynet = require "skynet"
local config = require "gate_cfg"
local struct = require "common.struct"

local CMD = {}
local SOCKET = {}
local gate
local agent = {}
local linkObjs = {}		-- 客户端连接 fd -> struct.login.linkObj
local login_manager

-- 检查连接
local function checklinkObjs(linkObj)
	local fd, addr = linkObj.fd, linkObj.ip
	-- 检查客户端连接
	if linkObjs[fd] then
		local msg = "Client " .. fd .. " is already connecting"
		skynet.error(msg)
		return false, msg
	end
	-- 检查黑名单

	-- 检查 Agent数量

	-- 检查 登录队列情况

	return true, ""
end

-- 客户端连接成功 accept 后 gate调用
-- @param linkObj struct.login.linkObj @链接对象
function SOCKET.open(linkObj)
	-- 连接管理
	local ret, msg = checklinkObjs(linkObj)
	if not ret then
		skynet.call(gate, "lua", "kick", linkObj.fd)
		return
	end
	-- watchdog 只管理连接状态
	skynet.error("New client from : " .. linkObj.addr)
	table.insert(linkObjs, linkObj.fd)
	-- 校验通过后，设置 desServer 为 login_manager
	skynet.send(gate, "lua", "setRoute", linkObj.fd, login_manager)
end


local function close_agent(fd)
	local a = agent[fd]
	agent[fd] = nil
	if a then
		skynet.call(gate, "lua", "kick", fd)
		-- disconnect never return
		skynet.send(a, "lua", "disconnect")
	end
end

function SOCKET.close(fd)
	print("socket close",fd)
	close_agent(fd)
end

function SOCKET.error(fd, msg)
	print("socket error",fd, msg)
	close_agent(fd)
end

function SOCKET.warning(fd, size)
	-- size K bytes havn't send out in fd
	print("socket warning", fd, size)
end

function SOCKET.data(fd, msg)
end

-- 启服调用 启动gate 监听端口
function CMD.start()
	-- 获取 login_manager 地址
	login_manager = skynet.uniqueservice("login.login_manager")
	return skynet.call(gate, "lua", "open" , {
		port = config.port or 8888,
		maxclient = config.maxclient or 64,
		nodelay = true,
	})
end

function CMD.close(fd)
	close_agent(fd)
end



skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
		if cmd == "socket" then				-- 由gate 监听到socket事件后 
			local f = SOCKET[subcmd]
			f(...)
			-- socket api don't need return
		else
			local f = assert(CMD[cmd])
			skynet.ret(skynet.pack(f(subcmd, ...)))
		end
	end)

	gate = skynet.newservice("gate.gate")
end)
