local skynet = require "skynet"
local config = require "etc.gate"
local struct = require "common.struct"

local CMD = {}
local SOCKET = {}
local gate
local agent = {}
local createingAgent = {}		-- 创建中的Agent

local function checkScoektAccept(fd, addr)
	-- 检查客户端连接
	if createingAgent[fd] then
		skynet.error("Client " .. fd .. " is creating agent")
		return false
	end
	-- 检查 Agent数量

	-- 检查 登录队列情况
	
	return true
end

-- 客户端连接成功 accept 后调用
-- @param linkObj struct.login.linkObj @链接对象
function SOCKET.open(linkObj)
	if not checkScoektAccept(linkObj.fd, linkObj.addr) then
		return
	end
	-- 优化为向AgentManager发送消息 创建Agent
	skynet.error("New client from : " .. linkObj.addr)
	table.insert(createingAgent, linkObj.fd)
	skynet.call("agent_mgr", "lua", "create_agent", {gate = gate, client = linkObj.fd, watchdog = skynet.self()})
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

function CMD.start()
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
