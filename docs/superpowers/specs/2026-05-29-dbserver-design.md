# dbserver 设计文档

> 日期：2026-05-29

## 目标

将 `db_proxy` 重构为通用的 `dbserver`，提供纯数据访问层接口。

## 架构

```
业务层  →  dbserver  →  MongoDB
              ↑
         白名单集合列表
```

`dbserver` 只做数据访问，不承载业务逻辑。

## 接口设计

| 方法 | 参数 | 返回值 |
|------|------|--------|
| `insert(collection, doc)` | 集合名(白名单验证), 文档 | `ok, err, ret` |
| `update(collection, query, update)` | 集合名, 查询条件, `{['$set'] = doc}` | `ok, err` |
| `delete(collection, query)` | 集合名, 查询条件 | `ok, err` |
| `findOne(collection, query)` | 集合名, 查询条件 | 文档或 nil |
| `find(collection, query)` | 集合名, 查询条件 | cursor 对象 |

**说明：**
- `update` 强制使用 `$set` 操作符
- `delete` 默认单条删除（`single: true`），防止误删
- `find` 返回 cursor，支持 `.sort()`、`.skip()`、`.limit()` 链式调用

## 白名单机制

`dbserver.init()` 时传入允许集合列表：

```lua
dbserver.init({
    collections = {"accounts", "players", "guilds"},
    mongo_conf = {...}
})
```

不在白名单内的集合操作直接拒绝，返回错误。

## dispatch 封装

保持现有 `skynet.dispatch("lua")` 模式，业务层通过 `skynet.call("dbserver", "lua", cmd, ...)` 调用。

## 实施步骤

1. 创建 `service/db/dbserver.lua`
2. 实现白名单校验
3. 实现 5 个基础接口
4. 更新启动脚本
5. 删除旧的 `db_proxy.lua`