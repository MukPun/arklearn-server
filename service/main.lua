local skynet = require "skynet"
local gate_config = require "gate_cfg"

skynet.start(function()
	skynet.error("ArkServer starting...")
	-- 加载协议
	local proto = skynet.uniqueservice("protoloader")		-- 全局唯一 只加载一次
	skynet.call(proto, "lua", "load", {
		"proto.c2s",		-- 1
		"proto.s2c",		-- 2
	})
	-- 启动监控
	-- if not skynet.getenv "daemon" then
	-- 	local console = skynet.newservice("console")
	-- end
	skynet.newservice("debug_console", 8000)
	-- -- 启动Login_Manager
	local loginServer = skynet.newservice("login/login_mgr")
	-- 启动Agent_Manager
	local agent_manager = skynet.newservice("agent/agent_mgr")

	-- -- 启动 Gate
	local gate = skynet.newservice("gate", loginServer)
	skynet.call(gate, "lua", "open" , gate_config)

	-- -- DbProxy
	-- -- 初始化 DB Proxy
	local dbProxy = skynet.uniqueservice("db/dbserver")
	skynet.call(dbProxy, "lua", "init")


	skynet.exit()
end)
