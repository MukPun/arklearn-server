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

	-- 加载导表(json -> sharedata)
	-- 这一步必须在所有业务服务(login/agent)起来之前完成,
	-- 否则业务层调用 game.info.get 会查不到数据
	local info_loader = skynet.uniqueservice("info/info_loader")
	skynet.call(info_loader, "lua", "load")
	require("info.init").mark_ready()

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
