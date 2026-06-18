-- /tmp/insert_entities.lua
-- 通过 debug_console inject 调 dbserver.insert
local skynet = require "skynet"

local DB = ".DbServer"

-- entities 测试角色(对应 test11@10001 这套凭据)
local entity = {
    uid        = 10001,
    name       = "tester",
    level      = 5,
    exp        = 100,
    reason     = 100,
    items_data = {},
    char_data  = {},
}

skynet.call(DB, "lua", "insert", "entities", entity)
print("[ok] insert entities uid=test11")
