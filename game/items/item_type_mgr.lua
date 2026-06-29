-- 策略分发中心
-- 管理道具的使用策略, 通过道具的itemType来区分
-- 把道具的数据容器(Item)、类型策略(handler) 拆分
local skynet = require "skynet"

local ItemTypeMgr = {}
local handlers = {}
local init_ed = false

-- 注册处理器
-- 以itemType 为策略划分
function ItemTypeMgr.register(item_type, handler_table)
    if handlers[item_type] then
        skynet.error("重复注册道具处理器: " .. item_type)
        return
    end
    handlers[item_type] = handler_table
end

function ItemTypeMgr.get_handler(item_type)
    return handlers[item_type]
end

function ItemTypeMgr.init()
    if init_ed then
        return
    end
    init_ed = true

    local cwd = skynet.cwd and skynet.cwd() or "."
    local handler_dir = cwd .. "/game/items/handler/"
    local cmd
    if package.config:sub(1, 1) == "\\" then
        cmd = '(dir /b "' .. handler_dir .. '")'
    else
        cmd = '(ls "' .. handler_dir .. '")'
    end

    local p = io.popen(cmd)
    if not p then
        skynet.error("ItemTypeMgr.init: 无法列举目录 " .. handler_dir)
        init_ed = false  -- 列举失败,允许重试
        return
    end
    for file in p:lines() do
        if file:match("%.lua$") and file ~= "init.lua" then
            local mod = "items.handler." .. file:sub(1, -5)
            local ok, err = pcall(require, mod)
            if not ok then
                skynet.error("ItemTypeMgr.init: 加载 " .. mod .. " 失败 " .. tostring(err))
            end
        end
    end
    p:close()
end

return ItemTypeMgr