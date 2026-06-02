-- 
local msgserver = require "snax.msgserver"
local crypt = require "skynet.crypt"
local skynet = require "skynet"

local start_arge = {...}
local loginservice = tonumber(start_arge[1])


local server = {}
local users = {}
local username_map = {}
local internal_id = 0
local servername

-- login server disallow multi login, so login_handler never be reentry
-- call by login server 从登录服务 调用
function server.login_handler(uid, secret)
	if users[uid] then
		error(string.format("%s is already login", uid))
	end

	internal_id = internal_id + 1
	local id = internal_id	-- don't use internal_id directly
	local username = msgserver.username(uid, id, servername)
	-- 首次登录的时候,默认都请求Agent,分配一个Agent
	local agent = skynet.uniqueservice(".AgentManager")

	local u = {
		username = username,
		agent = agent,
		uid = uid,
		subid = id,
	}

	-- trash subid (no used)
	local ok, err, allocated_agent = skynet.call(agent, "lua", "login", uid, id, secret)
	if not ok then
		error(string.format("login %s failed: %s", uid, err))
	end
	u.agent = allocated_agent		-- 登录成功后，分配的Agent 替换掉 登录前的AgentManager
	users[uid] = u
	username_map[username] = u

	msgserver.login(username, secret)

	-- you should return unique subid
	return id
end

-- call by agent
function server.logout_handler(uid, subid)
	local u = users[uid]
	if u then
		local username = msgserver.username(uid, subid, servername)
		assert(u.username == username)
		msgserver.logout(u.username)
		users[uid] = nil
		-- if username_map[u.username] and username_map[u.username].agent then
			-- table.insert(pool, username_map[u.username].agent)
		-- end
		username_map[u.username] = nil
		skynet.call(loginservice, "lua", "logout",uid, subid)
	end
end

-- call by login server
function server.kick_handler(uid, subid)
	local u = users[uid]
	if u then
		local username = msgserver.username(uid, subid, servername)
		assert(u.username == username)
		-- NOTICE: logout may call skynet.exit, so you should use pcall.
		pcall(skynet.call, u.agent, "lua", "logout")
	end
end

-- call by self (when socket disconnect)
function server.disconnect_handler(username)
	local u = username_map[username]
	if u then
		skynet.call(u.agent, "lua", "afk")
	end
end

-- call by self (when recv a request from client) 客户端消息转发
function server.request_handler(username, msg)
	local u = username_map[username]
	return skynet.tostring(skynet.rawcall(u.agent, "client", msg))
end

-- call by self (when gate open)
function server.register_handler(name)
	servername = name
	skynet.call(loginservice, "lua", "register_gate", servername, skynet.self())
end

msgserver.start(server)

