-- game/account/user.lua
--
-- User 对象:玩家在游戏世界里的数据容器
--
-- 设计要点:
--   1. 字段按业务系统分表:基础数据 / 干员 / 物品 / 权限 → 1 张 mongodb 4 个 fields
--   2. 脏标到 fields 粒度:set 一次只标脏对应 fields, save 只写脏表
--   3. 加载/保存走 dbserver 通用接口(findOne / update)
--   4. 加载失败返回 (false, err),由 caller 决定如何处理(agent.lua 选择拒绝启动)
--
-- 用法(在 agent.lua 里):
--   local User = require "game.account.user"
--   self.user = User.new(self.uid, self)
--   self.user:load()        -- 初始化时加载
--   ...
--   self.user:set_var("level", 10)
--   self.user:get_var("level")
--   self.user:save_dirty / save_all()        -- 登出/AFK 时保存
--   self.user:close()       -- 主动清理(save + 释放引用)

local skynet = require "skynet"
local const = require "const"

-- 每个 fields 对应 mongodb的一个字段 角色的数据存在 entities 表里
-- mongondb 表里, 每个角色的_id 是uid
-- 角色要持久化的数据都存在_data里, SAVE_KEY定义了要存盘的字段 可以代表一个系统，也可以是单个数据
local SAVE_KEY = {
    -- 玩家基础数据
    "uid", "name", "level", "exp",
    "reason",                   -- 理智(体力值)
    -- 系统数据
    "items_data",               -- 物品系统
    "char_data",                -- 干员系统

}


-- User 类
local User = {}
User.__index = User

-- 构造
-- @param uid        角色唯一 ID
-- @param agent      关联的 agent 对象(便于回调 / 后续扩展;目前仅缓存引用)
function User.new(uid, agent)
    local self = setmetatable({}, User)
    self.uid          = uid             -- 唯一id
    self.agent        = agent           -- 所属的agent 服务id   这个感觉不用记,因为userobj通常只在自己的agent存在

    self.db_server    = skynet.uniqueservice(const.public_server_name.DB_SERVER)        -- 数据所在的dbserver 服务id
    self._loaded      = false       -- 是否已加载过
    self._dirty       = {}          -- {fields = true}          有变化的数据 下一次存盘时进行存盘
    self._saving      = false       -- 防止 save 并发
    self._data        = {}          -- 数据 [fields = {系统数据}]
    return self
end


function User:set_var(key, value)
    --  不支持删除字段
    --   value 不能传 nil(传 nil 在 Lua 里等于删 _data 的 key,
    --   save_dirty 那边会跳过这个脏字段然后清掉 dirty 标记,
    --   最终 mongo 里旧值不变 → set nil 等于无效操作)
    --   业务侧需要清除字段时,先确认 dbserver 支持 $unset,否则不要这么做
    self._data[key] = value
    self:_mark_dirty(key)
end

function User:get_var(key)
    return self._data[key]
end

function User:smart_set_var(key, value)
    local function_name = "set_" .. key
    local set_func = self[function_name]
    if set_func ~= nil then
        set_func(self, value)
    else
        self:set_var(key, value)
    end
end

function User:smart_get_var(key)
    local function_name = "get_" .. key
    local get_func = self[function_name]
    if get_func ~= nil then
        return get_func(self, key)
    else
        return self:get_var(key)
    end
end

function User:has_var(key)
    local has = self._data[key]
    if has == nil then
        return false
    else
        return true
    end
end

function User:get_uid()
    return self.uid
end

function User:get_data()
    return self._data
end

-- 获取角色数据 可安全的被sproto序列化
function User:get_safe_data()
    local data = {}
    for k, v in pairs(self._data) do
        if k ~= "_id" then -- 避免 影响sproto  序列化 TODO 用黑名单过滤
            data[k] = v
        end
    end
    return data
end


-- 把 mongodb 拉到的 data 翻译到 obj 上
-- @param data      mongodb findOne 返回的 table
-- @param fields    SAVE_KEY 那张 {fields}
local function _apply_data(self, data)
    if not data then
        return
    end
    for field, value in pairs(data) do
        skynet.debug("_apply_data field=", field, " value=", value)
        self._data[field] = value
    end
end

-- 从 entities 加载
-- @param fields       SAVE_KEYs
function User:_do_load()
    local data = skynet.call(
        self.db_server, "lua", "findOne",
        "entities", { uid = self.uid }
    )
    if data then
        _apply_data(self, data)
        return true, ""
    end
    error("User:load file uid=" .. tostring(self.uid))
end

-- 初始化:加载所有 fields 的数据
-- 失败则拒绝登录, 中断后续流程, 清除玩家所有登录数据, 避免污染正常数据
-- @return self (链式)
function User:load()
    if self._loaded then
        return false, self
    end
    -- 再用 db 数据覆盖
    local ok, err = pcall(self._do_load, self)
    if not ok then
        error(string.format(
            "User:load for uid=%s, err=%s",
            tostring(self.uid), tostring(err)
        ))
        return false, self
    end
    self._loaded = true
    self._dirty  = {}      -- 加载完视为干净
    return true, self
end

-- #####################################  dirty START   #####################################
-- 标记某个 fields 为脏
-- @param fields fields 名
function User:_mark_dirty(fields)
    if not fields then
        return
    end
    self._dirty[fields] = true
end

-- 检查某个 fields 是否脏
function User:is_dirty(fields)
    return self._dirty[fields] == true
end

-- 检查是否加载完成
function User:is_loaded()
    return self._loaded
end

-- #####################################  dirty END   #####################################


-- 生成存盘数据 通过save_key
-- @param fields  SAVE_KEY[fields]
-- @return update_doc  {db_field = value, ...}
local function _build_persistent_data(self)
    local data = {}
    for _, fields in pairs(SAVE_KEY) do
        if self:get_var(fields) then
            data[fields] = self:get_var(fields)
        end
    end
    -- 其他系统通过 get_persistent_dict 接口返回存盘的数据

    return data
end

-- 保存所有脏的 fields
-- 只在协程内能 yield 的上下文里调用(skynet.call)
-- @return ok, err  (任一表写失败,整体返回 false)
function User:save_dirty()
    if not self._loaded then
        return false, "not loaded"
    end
    if self._saving then
        return false, "save already in progress"
    end
    self._saving = true
    local ok, err = pcall(self._do_save_dirty, self)
    self._saving = false
    if not ok then
        return false, tostring(err)
    end
    return true, ""
end

-- 只保存有变化的数据 定期存盘使用
function User:_do_save_dirty()
    local any_error
    local save_doc = {}     -- 需要存盘的 fields: {key = value, ...}
    for fields in pairs(self._dirty) do
        if self:get_var(fields) ~= nil then
            save_doc[fields] = self:get_var(fields)
        else
            -- (set_var 不支持删字段) 这不该发生, 这里只记 debug
            skynet.debug("do_save_dirty: skip nil field=", fields, " (set_var(nil) 触发的非法调用)")
        end
    end
    local ok, err = self:_do_save(save_doc)
    if not ok then
        skynet.error(string.format(
            "User:save for uid=%s failed: %s",
            tostring(self.uid), tostring(err)
        ))
        any_error = any_error or err
    else
        self._dirty = {}        -- 保存成功 则清空赃标记
    end
    if any_error then
        error(any_error)
    end
    return true, ""
end

-- 执行存盘原子操作 远程通知db
function User:_do_save(update_doc)
    local ok, err = skynet.call(
    self.db_server, "lua", "update",
    "entities", { uid = self.uid }, update_doc
    )
    return ok, err
end

-- 强制全量保存(忽略 dirty,所有 collection 都写)
-- 用于登出 / 主动落盘
-- @return ok, err
function User:save_all()
    if not self._loaded then
        return false, "not loaded"
    end
    local save_doc = _build_persistent_data(self)
    return self:_do_save(save_doc)
end

-- 关闭:save 一次,后续访问会失败(防误用)
-- @return ok, err
function User:close()
    if not self._loaded then
        return true
    end
    local ok, err = self:save_all()
    self._loaded = false
    return ok, err
end

-- 暴露 SAVE_KEY 给外部(只读),便于调试 / 文档
User._save_key          = SAVE_KEY

return User
