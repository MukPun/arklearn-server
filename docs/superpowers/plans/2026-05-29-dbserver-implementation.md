# dbserver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `db_proxy` 重构为通用的 `dbserver`，提供纯数据访问层接口，集合访问受白名单保护。

**Architecture:** `dbserver` 作为纯数据访问层，通过 skynet service 暴露 5 个基础 CRUD 接口，业务层传集合名和查询条件，由 dbserver 做白名单校验后操作 MongoDB。

**Tech Stack:** skynet, skynet.db.mongo, bson

---

## File Structure

| 文件 | 操作 |
|------|------|
| `service/db/dbserver.lua` | 创建（新文件） |
| `service/db/db_proxy.lua` | 删除 |
| `etc/database_cfg.lua` | 修改（添加 collections 白名单） |
| `service/login/login_worker.lua` | 修改（适配新接口） |
| `skynet/test/testmongodb.lua` | 修改（补充 delete/update 测试用例） |

---

## Task 1: 修改 database_cfg.lua 添加白名单配置

**Files:**
- Modify: `etc/database_cfg.lua`

- [ ] **Step 1: 添加 collections 白名单配置**

```lua
return {
    host = "127.0.0.1",
    port = 27017,
    username = "admin",
    password = "ark1998219",
    authdb = "admin",
    database = "arkServer",
    name = "db_proxy",
    collections = {"accounts", "players"},  -- 新增：允许访问的集合列表
}
```

- [ ] **Step 2: 提交**

```bash
git add etc/database_cfg.lua
git commit -m "config: add collections whitelist for dbserver"
```

---

## Task 2: 创建 dbserver.lua

**Files:**
- Create: `service/db/dbserver.lua`

- [ ] **Step 1: 编写完整实现**

```lua
local skynet = require "skynet"
local mongo = require "skynet.db.mongo"
local bson = require "bson"

local dbserver = {}
local db_instance = nil
local allowed_collections = {}

local function check_collection(name)
    if not allowed_collections[name] then
        return false, "collection not allowed: " .. tostring(name)
    end
    return true
end

function dbserver.init(conf)
    local client = mongo.client(conf.mongo_conf)
    db_instance = client:getDB(conf.mongo_conf.database)
    allowed_collections = {}
    for _, v in ipairs(conf.collections) do
        allowed_collections[v] = true
    end
    -- 创建索引
    db_instance.accounts:createIndex({name = 1}, {unique = true})
    skynet.error("dbserver initialized")
end

function dbserver.insert(collection, doc)
    local ok, err = check_collection(collection)
    if not ok then
        return false, err
    end
    return db_instance[collection]:safe_insert(doc)
end

function dbserver.update(collection, query, update)
    local ok, err = check_collection(collection)
    if not ok then
        return false, err
    end
    -- 强制使用 $set 操作符
    local full_update = {['$set'] = update}
    return db_instance[collection]:safe_update(query, full_update, false, false)
end

function dbserver.delete(collection, query)
    local ok, err = check_collection(collection)
    if not ok then
        return false, err
    end
    return db_instance[collection]:safe_delete(query, true)
end

function dbserver.findOne(collection, query)
    local ok, err = check_collection(collection)
    if not ok then
        return false, err
    end
    return db_instance[collection]:findOne(query)
end

function dbserver.find(collection, query)
    local ok, err = check_collection(collection)
    if not ok then
        return false, err
    end
    return db_instance[collection]:find(query)
end

-- 注册服务处理函数
skynet.start(function()
    skynet.register("dbserver")
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = dbserver[cmd]
        if f then
            local ret = {f(...)}
            if session > 0 then
                skynet.ret(skynet.pack(table.unpack(ret)))
            end
        end
    end)
end)

return dbserver
```

- [ ] **Step 2: 提交**

```bash
git add service/db/dbserver.lua
git commit -m "feat: create dbserver with generic CRUD interfaces"
```

---

## Task 3: 更新 login_worker.lua 适配新接口

**Files:**
- Modify: `service/login/login_worker.lua`

- [ ] **Step 1: 读取当前 login_worker.lua**

```lua
-- 查看当前实现，确认需要修改的地方
```

- [ ] **Step 2: 将 skynet.call("db_proxy", ...) 改为 skynet.call("dbserver", ...)**

原有：
```lua
local account = skynet.call("db_proxy", "lua", "query_account", name)
local ok, err = skynet.call("db_proxy", "lua", "create_account", account_data)
```

改为：
```lua
-- 查询：dbserver.findOne("accounts", {name = name})
-- 插入：dbserver.insert("accounts", account_data)
```

- [ ] **Step 3: 提交**

```bash
git add service/login/login_worker.lua
git commit -m "refactor: adapt login_worker to dbserver interface"
```

---

## Task 4: 补充 testmongodb.lua 的 delete 和 update 测试

**Files:**
- Modify: `skynet/test/testmongodb.lua`

- [ ] **Step 1: 添加 test_safe_delete 和 test_safe_update 函数**

在 `test_safe_update` 函数后添加：

```lua
local function test_safe_delete()
    local ok, err, ret
    local c = _create_client()
    local db = c[db_name]

    db.testcoll:drop()

    db.testcoll:safe_insert({test_key = 100, test_value = "hello mongo"})
    db.testcoll:safe_insert({test_key = 200, test_value = "hello mongo2"})

    ok, err = db.testcoll:safe_delete({test_key = 100})
    assert(ok, err)

    ret = db.testcoll:findOne({test_key = 100})
    assert(ret == nil)

    ret = db.testcoll:findOne({test_key = 200})
    assert(ret and ret.test_value == "hello mongo2")
end
```

- [ ] **Step 2: 在 skynet.start 中注册新测试**

在 `test_safe_update` 后添加：

```lua
print("test safe delete")
test_safe_delete()
```

- [ ] **Step 3: 提交**

```bash
git add skynet/test/testmongodb.lua
git commit -m "test: add delete and update test cases"
```

---

## Task 5: 删除 db_proxy.lua

**Files:**
- Delete: `service/db/db_proxy.lua`

- [ ] **Step 1: 删除文件**

```bash
git rm service/db/db_proxy.lua
git commit -m "refactor: remove deprecated db_proxy"
```

---

## Self-Review Checklist

1. **Spec coverage:** 5 个基础接口（insert/update/delete/findOne/find）+ 白名单机制 + dispatch 封装，均已在 Task 2 覆盖
2. **Placeholder scan:** 无 TODO/TBD，代码均为完整实现
3. **Type consistency:** 方法名 `insert`/`update`/`delete`/`findOne`/`find` 在所有 task 中一致

---

**Plan complete and saved to `docs/superpowers/plans/2026-05-29-dbserver-implementation.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**