# ARK Server 登录功能设计文档 v3

**日期**: 2026-05-19
**版本**: 3.0
**状态**: 设计阶段
**基于**: v2.0 (2026-05-17) 目录结构优化

---

## 1. 项目概述

### 1.1 项目背景

使用 skynet 框架构建游戏服务端，采用 ECS（Entity-Component-System）架构，支持后续功能迭代。项目为抽卡游戏的长线练手项目。

### 1.2 技术栈

| 组件 | 技术选型 |
|------|----------|
| 服务端框架 | skynet |
| 脚本语言 | Lua |
| 客户端框架 | Unity (C#) |
| 数据库 | MongoDB |
| 协议 | sproto (两端统一) |
| 密码加密 | bcrypt(sha256_str) |
| 预期规模 | 5000 并发 |

### 1.3 部署策略

单节点部署，架构设计预留多节点扩展能力。

### 1.4 Demo 范围

| 功能 | 说明 |
|------|------|
| 登录 | 账号密码验证、顶号检查、断线重连 |
| 角色展示 | 玩家数据加载、干员列表展示 |
| 基本存档 | 定时自动存档 |

---

## 2. 目录结构

### 2.1 当前目录结构

```
ark-server/
├── skynet/              # skynet 源码（submodule）
├── service/             # Skynet 基础设施服务
│   ├── gate/            # 网关服务
│   ├── login/           # 登录服务
│   │   ├── login_master.lua
│   │   ├── login_worker.lua
│   │   └── config
│   ├── db/              # 数据库代理
│   │   └── db_proxy.lua
│   ├── agent_mgr/       # Agent 管理器
│   │   └── agent_mgr.lua
│   └── agent/           # Agent 服务（每个玩家的 Actor）
│       ├── agent.lua
│       └── world.lua
├── src/                 # 纯 Lua 业务代码（不依赖 skynet）
│   └── ecs/             # ECS 核心框架
│       ├── core/        # ECS 引擎核心
│       │   ├── world.lua
│       │   ├── component.lua
│       │   ├── processor.lua
│       │   └── entity.lua
│       └── components/   # 组件定义
│           ├── account.lua
│           └── player_data.lua
├── proto/               # sproto 协议定义
│   └── login.sproto
├── etc/                 # 业务配置
│   ├── database.lua     # MongoDB 配置
│   ├── gate.lua         # Gate 配置
│   └── login.lua        # Login 配置
├── config/              # skynet 启动配置
├── Makefile             # 编译脚本
├── run.sh               # 启动脚本
└── shutdown.sh          # 关闭脚本
```

### 2.2 目录划分原则

**分离标准**：
- `service/` - skynet service，继承 skynet 生命周期，需要 `skynet.start()`
- `src/` - 纯 Lua 模块，不依赖 skynet，可被 service 和测试直接引用

**为什么要分离**：
- `service/` 目录的代码与 skynet 框架强绑定，只能在 skynet 环境下运行
- `src/` 目录的代码是纯 Lua 逻辑，可以独立测试，也可以被多个 service 复用
- ECS 核心框架（World、Component、Entity、Processor）不依赖 skynet，放在 `src/ecs/` 可以独立验证逻辑

### 2.3 配置文件说明

| 目录/文件 | 用途 |
|-----------|------|
| `config/` | skynet 启动配置文件（thread、lua_path、luaservice 等） |
| `etc/` | 业务配置文件（数据库连接、服务参数等） |
| `service/*/config` | skynet service 启动参数 |

### 2.4 lua_path 配置

`config` 中的 `lua_path` 需要支持 `src/?/?.lua` 模式，以解析点号路径的模块引用：

```lua
lua_path = root .. "lualib/?.lua;" .. root .. "skynet/lualib/?.lua;" .. root .. "skynet/lualib/?/init.lua;" .. root .. "src/?.lua;" .. root .. "src/?/init.lua;" .. root .. "src/?/?.lua"
```

这样 `require "ecs.core.entity"` 会正确查找 `src/ecs/core/entity.lua`。

---

## 3. 系统架构

### 3.1 整体架构

```
客户端 (Unity + sproto)
        │
        │ TCP/KCP + sproto
        ↓
┌─────────────────────────────────────────────────────────┐
│                     Skynet Node                          │
│                                                          │
│  [Gate/Watchdog] ──sproto──→ [Login_Master]             │
│         │                           │                     │
│         │                           ├── [Login_Worker × N]│
│         │                           │         │          │
│         │                           └── [DB_Proxy]       │
│         │                                     │          │
│         │                           [Agent_Mgr]         │
│         │                                     │          │
│         │                    ┌────────────────┼────────┐│
│         │                    ↓                ↓        ↓│
│         │              [Agent 1]  [Agent 2]  ... [Agent N]│
│         │              (ECS World) (ECS World)   (ECS)  │
│         │                                                      │
└─────────┴──────────────────────────────────────────────────────┘
                    │                         │
                    ↓                         ↓
               [MongoDB]                 [In-Memory Cache]
```

### 3.2 服务职责

| 服务 | 职责 |
|------|------|
| Gate / Watchdog | 维持 TCP/KCP 连接，处理 sproto 封包/解包，消息路由 |
| Login_Master | 登录大厅主服务，处理排队、分发登录请求，顶号检查 |
| Login_Worker (池) | 执行 bcrypt 校验，防止阻塞主服务 |
| DB_Proxy | MongoDB 交互代理 |
| Agent_Mgr | 代理管理器，负责拉起和管理 Agent |
| Agent | 玩家专属 Actor，内跑 ECS World，处理游戏逻辑 |

### 3.3 服务间通信（简化设计）

**直接使用 Skynet 原生消息**，不需要额外的消息封装：

```lua
-- 直接调用，skynet 内部已经是队列化
local result = skynet.call(service, "lua", "method", param1, param2)

-- 异步发送
skynet.send(service, "lua", "method", param1, param2)
```

**服务接口直接用 Lua 函数定义**：

| 服务 | 暴露方法 |
|------|----------|
| Login_Master | `login_request`, `register_request` |
| DB_Proxy | `query_account`, `create_account`, `load_player`, `save_player` |
| Agent | `query_player_data`, `get_fight_power`, `handle_game_message` |

### 3.5 Agent_Mgr OOP 设计

**设计原则**：使用 Lua 面向对象模式，将 AgentManager 作为类实现，方法与数据绑定。

**类定义**：
```lua
local AgentManager = {}
AgentManager.__index = AgentManager

function AgentManager.new()
    return setmetatable({agents = {}}, AgentManager)
end

function AgentManager:create_agent(uid, gate_service)
    -- 踢掉旧 Agent
    if self.agents[uid] then
        pcall(skynet.call, self.agents[uid], "lua", "logout")
    end
    -- 创建新 Agent
    local agent = skynet.newservice("agent")
    skynet.call(agent, "lua", "start", uid, gate_service)
    self.agents[uid] = agent
    return agent
end

function AgentManager:get_agent(uid)
    return self.agents[uid]
end

function AgentManager:remove_agent(uid)
    if self.agents[uid] then
        pcall(skynet.call, self.agents[uid], "lua", "logout")
        self.agents[uid] = nil
    end
end

function AgentManager:list_online_players()
    local online = {}
    for uid, _ in pairs(self.agents) do
        table.insert(online, uid)
    end
    return online
end
```

**Skynet 入口**：
```lua
local manager = AgentManager.new()

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = manager[cmd]
        if f then
            local ret = f(manager, ...)
            if session > 0 then
                skynet.ret(skynet.pack(ret))
            end
        end
    end)
end)
```

**优势**：
- `self.agents` 显式管理，不依赖闭包变量
- 方法与数据绑定，职责清晰
- 便于后续扩展（如添加 `get_all_agents()`、`broadcast()` 等）

---

## 4. ECS 设计

### 4.1 设计理念

ECS 架构遵循以下核心原则：
- **C（Component）**：纯数据载体，不包含逻辑
- **E（Entity）**：实体的标识，通过挂载不同 Component 组合获得不同功能
- **S（Processor）**：控制逻辑，处理拥有特定 Component 的实体

**Demo 阶段采用单实体方案**：每个玩家一个 PlayerEntity，包含 Account + PlayerData。charList 作为嵌入式数组，不拆成独立 Entity。

后续扩展时可通过组件组合将 CharData 拆为独立 Entity。

### 4.2 组件定义

**AccountComponent**（账号信息）：
```lua
AccountComponent = {
    uid = 0,
    name = "",
    password_hash = "",
}
```

**PlayerDataComponent**（玩家游戏数据）：
```lua
PlayerDataComponent = {
    uid = 0,
    name = "",
    level = 1,
    exp = 0,
    reason = 100,
    charList = {},      -- {[id] = CharData}
    squad = {},         -- {[id] = char_id}
    desktopChar = "",
    items = {},         -- {[id] = ItemStack}
}
```

### 4.3 ECS Core 实现

位于 `src/ecs/core/`：
- `world.lua` - World 管理器
- `component.lua` - Component 基类
- `entity.lua` - Entity 实现
- `processor.lua` - Processor 基类

位于 `src/ecs/components/`：
- `account.lua` - AccountComponent
- `player_data.lua` - PlayerDataComponent

---

## 5. 登录流程

### 5.1 消息流设计

**Gate 消息转发机制**：
- Gate 服务的 `handler.message` 会根据 `connection[fd].agent` 判断消息发送目标
- 无 agent 时 → 消息发给 Watchdog
- 有 agent 时 → 消息通过 `skynet.redirect` 重定向到 Agent

**动态转发流程**：
1. 客户端连接 → Gate → Watchdog
2. 登录验证成功 → Agent_Mgr 创建 Agent
3. Agent 准备就绪后 → 沿调用链返回 Agent 地址
4. Watchdog 调用 `gate:forward(fd, client, agent_address)` 设置转发
5. 后续该 fd 的消息直接发给 Agent

### 5.2 完整时序

```
客户端                    Gate              Watchdog          Login_Master         Agent_Mgr         Agent
   │                        │                   │                    │                  │               │
   │──TCP连接───────────────>│                   │                    │                  │               │
   │                        │──connect────────>│                    │                  │               │
   │                        │                   │                    │                  │               │
   │──C2G_Login────────────>│──message────────>│                    │                  │               │
   │                        │                   │──login_request───>│                  │               │
   │                        │                   │                    │                  │               │
   │                        │                   │──检查在线(顶号)───>│                  │               │
   │                        │                   │                    │                  │               │
   │                        │                   │──query_account───────────────────────>│               │
   │                        │                   │<─bcrypt_hash─────────────────────────│               │
   │                        │                   │                    │                  │               │
   │                        │                   │──bcrypt_verify──>│                  │               │
   │                        │                   │<─验证结果────────│                  │               │
   │                        │                   │                    │                  │               │
   │                        │                   │──create_agent────────────────>│               │               │
   │                        │                   │                    │<──创建Agent────│               │
   │                        │                   │                    │                  │               │
   │                        │                   │                    │<─Agent就绪─────│               │
   │                        │                   │                    │                  │               │
   │                        │<─────────────────│<─agent_address────│                  │               │
   │                        │                   │                    │                  │               │
   │                        │──forward(fd,─────────────────────────>│                  │               │
   │                        │    agent_addr)                      │                  │               │
   │                        │                   │                    │                  │               │
   │<──G2C_Login_Success────│                   │                    │                  │               │
   │                        │                   │                    │                  │               │
   │──后续消息────────────>│                   │                    │                  │               │
   │                        │──redirect────────────────────────────────────────────>│               │
   │                        │──直接发给Agent                           │                  │               │
```

### 5.3 Gate forward 接口

```lua
-- gate.lua CMD.forward
function CMD.forward(source, fd, client, address)
    local c = assert(connection[fd])
    c.client = client or 0
    c.agent = address      -- 设置消息重定向目标
    gateserver.openclient(fd)  -- 开启该 fd 的消息
end
```

调用示例：
```lua
-- Watchdog 收到 Agent 就绪通知后
skynet.call(gate, "lua", "forward", fd, client_fd, agent_address)
```

---

## 6. Sproto 协议定义

```sproto
.LoginRequest {
    account 0 : string
    password_hash 1 : string
    token 2 : string
    device_id 3 : string
}

.LoginResponse {
    error_code 0 : integer
    uid 1 : integer
    token 2 : string
    player_data 3 : PlayerData
}

.RegisterRequest {
    account 0 : string
    password_hash 1 : string
    device_id 2 : string
}

.RegisterResponse {
    error_code 0 : integer
    uid 1 : integer
}

login 1 {
    request LoginRequest
    response LoginResponse
}

register 2 {
    request RegisterRequest
    response RegisterResponse
}
```

---

## 7. 设计确认清单

- [x] 目录结构（service/ + src/ 分离）
- [x] ECS Core 位置（src/ecs/core/）
- [x] ECS Components 位置（src/ecs/components/）
- [x] lua_path 配置支持点号路径
- [x] 业务配置目录（etc/）
- [x] skynet 启动配置目录（config/）
- [x] 服务间通信简化设计
- [x] 登录流程设计
- [x] sproto 协议定义

---

## 8. 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| v1.0 | 2026-05-15 | 初始设计 |
| v2.0 | 2026-05-17 | 简化服务间通信，ECS 单实体设计 |
| v3.0 | 2026-05-19 | 目录结构调整（service/ + src/ 分离）+ Gate 消息转发机制 |
| v3.1 | 2026-05-21 | Agent_Mgr OOP 重构 |