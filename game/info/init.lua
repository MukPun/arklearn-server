-- game/info/init.lua
--
-- 导表数据查询入口(全服唯一的访问门面)
--   所有业务层都通过 require "game.info" 拿数据,不要直接 require skynet.sharedata
--   这样做的好处:
--     1. 集中处理 sharedata 未就绪的情况(防止加载期 race)
--     2. 提供统一的"查不到返回 nil"语义,业务层不用关心 boxed object
--     3. 后续要切换后端(比如换 redis / 换本地缓存)只改这一个文件
--
-- 用法:
--   local info = require "game.info"
--   local row  = info.get("items", "5001")           -- 按主键取一行
--   local name = info.field("items", "5001", "name") -- 安全取单个字段(nil-safe)
--   for id, row in info.iter("items") do ... end    -- 遍历整张表
--   if info.exists("items", "5001") then ... end    -- 存在性检查

local skynet     = require "skynet"
local sharedata  = require "skynet.sharedata"

local M = {}

-- ##################################### 就绪标记 #####################################
-- sharedata 注册发生在 service/info/info_loader.lua
-- main.lua 在 loader.load() 完成之后会调用 mark_ready()
-- 未就绪时的查询全部返回 nil 并打 error 日志(防止业务层踩空)

local _ready = false

function M.mark_ready()
    _ready = true
end

function M.is_ready()
    return _ready
end

local function _check_ready(op, name, key)
    if _ready then return end
    skynet.error(string.format(
        "[game.info] %s(%s, %s) called before mark_ready - sharedata 还没注册完成",
        op, tostring(name), tostring(key or "<no key>")
    ))
end

-- ##################################### 查询接口 #####################################

-- 按主键取一行
-- @param table_name  sharedata 注册名(对应 game/info/info_list.lua 的 key)
-- @param key         主键(一般是字符串 id)
-- @return row | nil
function M.get(table_name, key)
    _check_ready("get", table_name, key)
    local ok, t = pcall(sharedata.query, table_name)
    if not ok then
        -- 表没注册过(可能 list 里漏写)
        skynet.error("[game.info] sharedata.query(%s) failed: %s",
            tostring(table_name), tostring(t))
        return nil
    end
    if key == nil then
        return t   -- 不传 key 时返回整张表
    end
    return t[key]
end

-- 安全取单个字段
-- 比业务层写 info.get(...).name 更安全,避免 id 不存在时 nil.xxx 崩
-- @return value | nil
function M.field(table_name, key, field)
    local row = M.get(table_name, key)
    if row == nil then return nil end
    return row[field]
end

-- 遍历整张表
-- 注意:返回的是迭代器,不是数组。for k,v in info.iter("items") do ... end
function M.iter(table_name)
    _check_ready("iter", table_name)
    local ok, t = pcall(sharedata.query, table_name)
    if not ok then
        skynet.error("[game.info] sharedata.query(%s) failed: %s",
            tostring(table_name), tostring(t))
        return pairs({})   -- 返回空表的迭代器,与正常路径返回类型一致
    end
    return pairs(t)
end

-- 检查某 key 是否存在
function M.exists(table_name, key)
    if not _ready then return false end
    local ok, t = pcall(sharedata.query, table_name)
    if not ok then return false end
    return t[key] ~= nil
end

-- 统计行数(调试用)
function M.count(table_name)
    if not _ready then return 0 end
    local ok, t = pcall(sharedata.query, table_name)
    if not ok then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- 强制重查(开发调试用,绕过 sharedata.query 的本地缓存)
-- 生产别用,这里只是为了排查"是不是缓存了旧版本"
function M.fresh_query(table_name)
    _check_ready("fresh_query", table_name)
    -- deepcopy 不走 cache,直接拿远端最新值
    return sharedata.deepcopy(table_name)
end

return M