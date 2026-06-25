-- 导表加载服务
--
-- 职责:
--   1. 读取 game.info_list 拿到所有 json 文件清单
--   2. 解析 json(顶层若有 root,只取子表)
--   3. 把数据通过 sharedata.new 注册到 sharedatad(C 层共享内存)


local cjson     = require "cjson.safe"
local service   = require "service"
local log       = require "log"
local sharedata = require "skynet.sharedata"   -- 拉起 sharedatad,并拿到它的 handle

local loader = {}

-- ##################################### 工具函数 #####################################

-- 读取 json 文件,失败时直接 error(启动期 fail-fast,不允许带病运行)
local function _read_json(path)
    local f, err = io.open(path, "rb")
    if not f then
        error(string.format("[info_loader] open file failed: %s, err=%s", path, tostring(err)))
    end
    local content = f:read("*a")
    f:close()
    if not content or #content == 0 then
        error(string.format("[info_loader] empty file: %s", path))
    end
    local data, jerr = cjson.decode(content)
    if not data then
        error(string.format("[info_loader] json decode failed [%s]: %s", path, tostring(jerr)))
    end
    return data
end

-- 从原始 json 中取出要注册的子表
--   - cfg.root 存在:取 data[cfg.root] 子表(常见包装结构 {"items": {...}})
--   - cfg.root 缺省:整张 data 直接注册
local function _extract(data, cfg)
    if cfg.root then
        local sub = data[cfg.root]
        if type(sub) ~= "table" then
            error(string.format(
                "[info_loader] json root field [%s] is not a table (file=%s)",
                cfg.root, cfg.file
            ))
        end
        return sub
    end
    return data
end

-- 统计行数(用于启动日志)
local function _count(t)
    if type(t) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- cjson.safe 把 JSON null 解码成 cjson.null(userdata),
-- 但 sharedata.host.new 不支持 userdata,会抛 "Unsupport value type userdata"
-- 递归把 cjson.null 替换成 lua nil(sharedata 接受 nil)
local _cjson_null = cjson.null
local function _clean_nulls(tbl)
    if type(tbl) ~= "table" then return end
    for k, v in pairs(tbl) do
        if v == _cjson_null then
            tbl[k] = nil
        elseif type(v) == "table" then
            _clean_nulls(v)
        end
    end
end

-- ##################################### 命令 #####################################

-- 加载所有在 game.info_list 里声明的导表
-- @return true
function loader.load()
    local list = require "game.info.info_list"
    local count = 0
    for name, cfg in pairs(list) do
        if type(cfg) == "string" then
            -- 兼容简写形式: items = "game/info/item_table.json"
            cfg = { file = cfg }
        end
        local raw   = _read_json(cfg.file)
        local data  = _extract(raw, cfg)
        -- 清理 cjson.null(把json一些数据洗成lua可读)
        _clean_nulls(data)
        -- 注册到 sharedatad,所有服务从此都能 query 到
        -- 注意:这里走 sharedata.new 而不是 skynet.call(".sharedatad", ...),
        -- 因为 sharedatad 服务**没有通过 skynet.register 暴露本地名**,
        -- 唯一能拿到它的方式是通过 shareddata.lua 闭包里保存的 handle
        sharedata.new(name, data)
        count = count + 1
        log("[info_loader] loaded [%s] <- %s, rows=%d", name, cfg.file, _count(data))
    end
    log("[info_loader] done, %d tables registered", count)
    return true
end

-- 重载(开发期手动触发,生产可关)
-- 用法: skynet.call(info_loader, "lua", "reload")
function loader.reload()
    local list = require "game.info.info_list"
    for name, cfg in pairs(list) do
        if type(cfg) == "string" then
            cfg = { file = cfg }
        end
        local raw   = _read_json(cfg.file)
        local data  = _extract(raw, cfg)
        _clean_nulls(data)
        -- update 会让所有正在 query 的服务自动收到新版本(走 monitor 机制)
        sharedata.update(name, data)
        log("[info_loader] reloaded [%s]", name)
    end
    return true
end

-- 调试:查询某个表是否已注册
function loader.status(name)
    local ok, err = pcall(sharedata.query, name)
    return ok and true or false
end

-- ##################################### 服务注册 #####################################

service.init {
    command = loader,
    info    = { desc = "导表数据加载服务(sharedata 注册入口)" },
}