local skynet = require "skynet"

skynet.start(function()
	skynet.error("ArkServer starting...")
	if not skynet.getenv "daemon" then
		local console = skynet.newservice("console")
	end
	-- 启动监控
	skynet.newservice("debug_console", 8000)

	-- 加载协议
	local proto = skynet.uniqueservice "protoloader"
	skynet.call(proto, "lua", "load", {
		"proto.c2s",
		"proto.s2c",
	})

	-- DbProxy
	-- 初始化 DB Proxy
	local dbProxy = skynet.uniqueservice("db/db_proxy")
	skynet.call(dbProxy, "lua", "init")

	-- 启动Login_Manager
	local login_manager = skynet.newservice("login.login_manager")
	-- 启动Agent_Manager
	local agent_manager = skynet.newservice("agent.agent_manager")
	-- 启动 Gate 这里先用skynet提供的  GateServer
	local watchdog = skynet.newservice("gate.watchdog")
	local addr, port = skynet.call(watchdog, "lua", "start")
	skynet.error("Watchdog listen on " .. addr .. ":" .. port)
	skynet.exit()
end)
