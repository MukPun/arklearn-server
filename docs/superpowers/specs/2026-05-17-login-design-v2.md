# ARK Server 登录功能设计文档 v2

**日期**: 2026-05-17
**版本**: 2.0
**状态**: 设计阶段
**基于**: v1.0 (2026-05-15) 完善

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

## 2. 系统架构

### 2.1 整体架构

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

### 2.2 服务职责

| 服务 | 职责 |
|------|------|
| Gate / Watchdog | 维持 TCP/KCP 连接，处理 sproto 封包/解包，消息路由 |
| Login_Master | 登录大厅主服务，处理排队、分发登录请求，顶号检查 |
| Login_Worker (池) | 执行 bcrypt 校验，防止阻塞主服务 |
| DB_Proxy | MongoDB 交互代理 |
| Agent_Mgr | 代理管理器，负责拉起和管理 Agent |
| Agent | 玩家专属 Actor，内跑 ECS World，处理游戏逻辑 |

### 2.3 架构分层

```
┌─────────────────────────────────────────────────────────────┐
│              Skynet Service Layer (service/)                │
│                                                              │
│   基础设施层：actor 级别的服务，处理玩家登录前的逻辑                 │
│                                                              │
│   Gate         ─  网络连接、协议解析                            │
│   Login_Master ─  登录排队、验证分发                           │
│   Login_Worker ─  bcrypt 校验（独立运行）                      │
│   DB_Proxy     ─  数据库操作                                  │
│   Agent_Mgr    ─  Agent 管理                                │
└────────────────────────────┬────────────────────────────────┘
                             │ 玩家登录后进入...
                             ↓
┌─────────────────────────────────────────────────────────────┐
│                 ECS World Layer (agent/)                    │
│                                                              │
│   游戏逻辑层：玩家进入后，逻辑在 Agent 内的 ECS World 中运行        │
│                                                              │
│   Agent (Actor) ─ 持有 ECS World                            │
│     └── World                                               │
│           ├── Components (数据)                             │
│           └── Processors (玩法逻辑)  ← ECS System            │
│                                                              │
│   ECS System = Agent 内的玩法系统，处理玩家数据                  │
└─────────────────────────────────────────────────────────────┘
```

### 2.4 服务间通信（简化设计）

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

---

## 3. 目录结构

```
ark-server/
├── skynet/                 # skynet 源码（submodule）
│
├── service/                # Skynet 服务
│   ├── gate/               # 网关服务（保持 skynet 原版）
│   │   ├── gate.lua
│   │   └── config
│   ├── login/              # 登录服务
│   │   ├── login_master.lua
│   │   ├── login_worker.lua
│   │   └── config
│   ├── db/                 # 数据库代理
│   │   ├── db_proxy.lua
│   │   └── mongo_client.lua
│   └── agent_mgr/           # Agent 管理器
│       └── agent_mgr.lua
│
├── ecs/                    # ECS 核心框架
│   ├── core/
│   │   ├── world.lua        # World 管理器
│   │   ├── component.lua    # Component 基类
│   │   ├── processor.lua     # Processor 基类
│   │   └── entity.lua       # Entity 实现
│   └── components/
│       ├── account.lua     # 账号组件
│       └── player_data.lua # 玩家数据组件
│
├── agent/                   # Agent 服务（ECS World 容器）
│   ├── agent.lua           # Skynet Actor 入口
│   └── world.lua           # ECS World 实例化
│
├── proto/                   # sproto 协议定义
│   └── login.sproto
│
└── config/                  # 配置文件
    ├── gate.lua
    ├── login.lua
    └── database.lua
```

---

## 4. 服务设计

### 4.1 Login_Master

**职责**：
- 接收登录请求，写入登录队列
- 每帧处理登录队列
- 检查账号是否在线（顶号逻辑）
- 向 DB_Proxy 查询账号 bcrypt_hash
- 派发验证任务给 Login_Worker
- 接收验证结果，通知 Agent_Mgr
- 持有服务器登录信息（在线玩家 uid 列表、在线玩家数量等）

**接口**：
```lua
local CMD = {}

-- 登录请求
function CMD.login_request(account, password_hash, device_id)
    -- 检查是否在线（顶号）
    -- 查询 bcrypt_hash
    -- 派发验证给 Worker
    -- 返回验证结果
end

-- 注册请求
function CMD.register_request(account, password_hash, device_id)
    -- 检查账号是否存在
    -- 创建账号
end
```

**关键参数**：

| 参数 | 建议值 | 说明 |
|------|-------|------|
| 登录队列最大长度 | 1000 | 超出拒绝请求 |
| 每帧处理数 | 50 | 根据性能调整 |
| 帧间隔 | 100ms | 1秒约处理500登录 |
| 队列超时 | 10s | 超时返回失败 |

### 4.2 Login_Worker (池)

**职责**：
- 执行 bcrypt 验证
- 独立运行，不阻塞其他服务

**配置**：8-16 个 Worker 服务

### 4.3 DB_Proxy

**职责**：
- MongoDB 操作封装
- 提供统一的数据库接口

**接口**：
```lua
local DB_PROXY = {}

-- 查询账号
function DB_PROXY.query_account(name)
    return db:find_one("accounts", {name = name})
end

-- 创建账号
function DB_PROXY.create_account(account_data)
    return db:insert_one("accounts", account_data)
end

-- 加载玩家数据
function DB_PROXY.load_player(uid)
    return db:find_one("players", {_id = uid})
end

-- 保存玩家数据
function DB_PROXY.save_player(uid, player_data)
    return db:update_one("players", {_id = uid}, player_data)
end
```

### 4.4 Agent (PlayerObject)

Agent 是玩家在服务端的代理，既是 ECS World 的容器，也是玩家数据的对外接口。

**职责**：
- 接收玩家消息，处理游戏逻辑
- 异步拉取玩家数据（通过 DB_Proxy）
- 构建 ECS World，管理玩家数据
- 直接响应客户端（LoginResponse）
- 后续所有玩家交互由 Agent 处理

**对外接口**：

| 接口 | 调用方 | 说明 |
|------|--------|------|
| `query_player_data(uid)` | RankingService, TeamManager 等 | 获取玩家完整数据 |
| `get_fight_power(uid)` | RankingService | 获取战斗力（排行榜用） |
| `handle_game_message(cmd, ...)` | Gate | 处理游戏逻辑消息 |

**内部实现**：
```lua
local agent = {}

function agent:handle_message(cmd, ...)
    local f = self[cmd]
    if f then
        return f(self, ...)
    end
end

function agent:query_player_data(uid)
    return self.world:get_component(uid, "PlayerDataComponent")
end

function agent:get_fight_power(uid)
    local player_data = self:query_player_data(uid)
    return calculate_fight_power(player_data)
end
```

---

## 5. ECS 设计（单实体）

### 5.1 设计理念

ECS 架构遵循以下核心原则：
- **C（Component）**：纯数据载体，不包含逻辑
- **E（Entity）**：实体的标识，通过挂载不同 Component 组合获得不同功能
- **S（Processor）**：控制逻辑，处理拥有特定 Component 的实体

**Demo 阶段采用单实体方案**：每个玩家一个 PlayerEntity，包含 Account + PlayerData。charList 作为嵌入式数组，不拆成独立 Entity。

后续扩展时可通过组件组合将 CharData 拆为独立 Entity。

### 5.2 组件定义

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

**CharData**（干员数据，嵌入 PlayerData）：
```lua
CharData = {
    id = "",
    templateId = "",
    elite = 0,
    level = 1,
    exp = 0,
    trust = 0,
}
```

**ItemStack**（物品数据，嵌入 PlayerData）：
```lua
ItemStack = {
    id = 0,
    amount = 0,
}
```

### 5.3 Entity 结构

```
PlayerEntity (id = uid)
├── AccountComponent     (账号信息)
└── PlayerDataComponent  (玩家数据，包含 charList 和 items)
```

### 5.4 ECS Core 实现

**World 管理器**：
```lua
-- ecs/core/world.lua
World = {
    entities = {},           -- {[entity_id] = Entity}
    components = {},        -- {[component_type] = {[entity_id] = data}}
    processors = {},        -- {[processor_type] = Processor}
    
    -- 创建实体
    function World:create_entity(entity_id)
        local entity = Entity.new(entity_id)
        self.entities[entity_id] = entity
        return entity
    end,
    
    -- 添加组件
    function World:add_component(entity_id, component_type, data)
        if not self.components[component_type] then
            self.components[component_type] = {}
        end
        self.components[component_type][entity_id] = data
    end,
    
    -- 获取组件
    function World:get_component(entity_id, component_type)
        return self.components[component_type][entity_id]
    end,
    
    -- 注册 Processor
    function World:register_processor(processor_type, processor)
        self.processors[processor_type] = processor
    end,
    
    -- 帧更新
    function World:update(dt)
        for _, processor in pairs(self.processors) do
            processor:update(self, dt)
        end
    end,
}
```

**Processor 基类**：
```lua
-- ecs/core/processor.lua
Processor = {
    update = function(world, dt)
        -- 帧更新逻辑
    end,
}
```

### 5.5 Processor 定义

| Processor | 职责 |
|-----------|------|
| LoadProcessor | 从 MongoDB 加载玩家数据到 ECS |
| SaveProcessor | 定期将 ECS 数据回写 MongoDB |

### 5.6 ECS 与 Skynet 消息桥接

```lua
-- agent/agent.lua
Agent = {
    world = nil,  -- ECS World
    
    -- Skynet 消息处理
    handle_message = function(cmd, ...)
        local processor = self.world.processors[cmd]
        if processor then
            return processor:handle(self.world, ...)
        end
        
        -- fallback: 直接方法调用
        local f = self[cmd]
        if f then
            return f(self, ...)
        end
    end,
}
```

---

## 6. 登录流程

### 6.1 完整时序

```
客户端                    Gate/WD             Login_Master         Login_Worker    DB_Proxy         Agent_Mgr        Agent
   │                        │                      │                    │              │                  │               │
   │──TCP连接───────────────>│                      │                    │              │                  │               │
   │                        │                      │                    │              │                  │               │
   │──C2G_Login────────────>│                      │                    │              │                  │               │
   │                        │──login_request──────>│                    │              │                  │               │
   │                        │                      │                    │              │                  │               │
   │                        │                      │──检查在线(顶号)────>│              │                  │               │
   │                        │                      │                    │              │                  │               │
   │                        │                      │──query_account────>│              │                  │               │
   │                        │                      │<─bcrypt_hash───────│              │                  │               │
   │                        │                      │                    │              │                  │               │
   │                        │                      │──bcrypt_verify───>│              │                  │               │
   │                        │                      │<─验证结果─────────│              │                  │               │
   │                        │                      │                    │              │                  │               │
   │                        │                      │──create_agent─────────────────────>│              │               │
   │                        │                      │                    │              │               │               │
   │                        │                      │                    │              │<─agent启动─────────│               │
   │                        │                      │                    │              │──load_player─────>│               │
   │                        │                      │                    │              │<─player_data──────────────────────│    │
   │                        │                      │                    │              │                  │               │
   │                        │                      │                    │              │                  │<─构建ECS World │
   │                        │                      │                    │              │                  │               │
   │<──G2C_Login_Success────│                      │                    │              │                  │               │
   │                        │                      │                    │              │                  │<─后续消息──────>
```

### 6.2 第一阶段：客户端发起

1. 客户端输入密码
2. 在 Unity 端执行 SHA256(password)
3. 客户端连接到 Gate
4. 通过 sproto 发送 login 请求（account + password_hash + device_id）

### 6.3 第二阶段：服务端验证

1. Gate 收到消息，转发 Login_Master
2. Login_Master 检查账号是否在线（顶号逻辑）
3. 向 DB_Proxy 请求查询账号 bcrypt_hash
4. 将验证任务派发给空闲的 Login_Worker
5. Login_Worker 执行 bcrypt.verify(client_sha256, db_bcrypt_hash)
6. 返回验证结果给 Login_Master

### 6.4 第三阶段：Agent 创建与 ECS 初始化

1. Login_Master 验证成功，生成 Token
2. 通知 Agent_Mgr 拉起 Agent
3. Agent 启动，异步向 DB_Proxy 请求玩家数据
4. Agent 收到数据，构建 ECS World（Entity + Components）
5. Agent 通知 Agent_Mgr 注册自己

### 6.5 第四阶段：登录成功响应

1. Agent 组装 LoginResponse（uid + token + playerData）
2. Agent 直接响应客户端
3. 客户端收到成功响应，保存 Token，进入游戏

---

## 7. 密码安全设计

### 7.1 密码存储

```
注册时：
  password (明文)
       ↓
  SHA256(password) = sha256_str
       ↓
  bcrypt(sha256_str) = bcrypt_hash
       ↓
  存入 MongoDB (accounts.password)

登录时：
  client_sha256 = SHA256(password) (客户端)
       ↓
  bcrypt.verify(client_sha256, db_bcrypt_hash)
```

### 7.2 安全特性

- **客户端 SHA256**：不传输明文密码
- **服务端 bcrypt**：哈希存储，防彩虹表攻击
- **加盐**：bcrypt 自动处理 salt
- **bcrypt 成本**：10-12 轮，平衡安全性和性能

---

## 8. 数据持久化

### 8.1 MongoDB 集合设计

| 集合 | 文档结构 | 说明 |
|------|----------|------|
| `accounts` | `{ _id, name, password, uid }` | 账号信息 |
| `players` | 玩家完整数据（见下方结构） | 玩家游戏数据 |

**players 集合结构**：

```javascript
{
  _id: ObjectId,          // 玩家唯一ID (uid)
  name: "xxx",            // 玩家昵称
  level: 10,              // 等级
  exp: 5000,              // 经验值
  reason: 100,           // 理智
  charList: [             // 玩家持有的所有干员（嵌入式）
    { id: "char_001", templateId: "operator_001", elite: 0, level: 1, exp: 0, trust: 0 },
    { id: "char_002", templateId: "operator_002", elite: 1, level: 30, exp: 500, trust: 100 }
  ],
  squad: ["char_001", "char_002"],  // 队伍干员ID列表
  desktopChar: "char_001",          // 桌面干员ID
  items: [               // 玩家持有物品（嵌入式）
    { id: 1001, amount: 100 },
    { id: 2002, amount: 50 }
  ],
  permissions: ["admin"] // 权限列表
}
```

### 8.2 索引设计

```javascript
// accounts - 用户名唯一索引
db.accounts.createIndex({ "name": 1 }, { unique: true })

// players - uid 唯一索引（由 _id 提供，自动有唯一索引）
// players.name 如需按昵称查询可加索引（预留）
db.players.createIndex({ "name": 1 })
```

### 8.3 存盘策略（Demo 版）

**简化设计**：
```
数据变更 → 标记 dirty → 定时30秒批量存盘
                          │
                          ↓
                    DB_Proxy:save_player()
```

**关键参数**：

| 参数 | 建议值 | 说明 |
|------|-------|------|
| 定时存档间隔 | 30s | 平衡性能和数据安全 |
| 每帧处理数 | 20 | 根据 DB 性能调整 |

**关服流程**：

```
收到关服指令 → 停止接受新请求 → 处理存盘队列（全部）
                                ↓
                         所有数据落盘 → 执行 skynet.exit()
```

---

## 9. Sproto 协议定义

### 9.1 协议文件

```sproto
# login.sproto

.LoginRequest {
    account 0 : string       # 账号名
    password_hash 1 : string # 密码的 SHA256 (客户端预处理)
    token 2 : string         # 断线重连 Token (空=新登录)
    device_id 3 : string     # 设备唯一标识
}

.LoginResponse {
    error_code 0 : integer   # 0:成功, 1:密码错误, 2:账号不存在, 3:服务器维护
    uid 1 : integer          # 玩家全局唯一ID
    token 2 : string          # 通讯 Token
    player_data 3 : PlayerData
}

# 注册请求
.RegisterRequest {
    account 0 : string       # 账号名
    password_hash 1 : string # 密码的 SHA256 (客户端预处理)
    device_id 2 : string     # 设备唯一标识
}

# 注册结果
.RegisterResponse {
    error_code 0 : integer   # 0:成功, 1:账号已存在, 2:密码格式不对, 3:系统错误
    uid 1 : integer          # 玩家全局唯一ID (注册成功时)
}

# RPC 绑定
login 1 {
    request LoginRequest
    response LoginResponse
}

register 2 {
    request RegisterRequest
    response RegisterResponse
}

# 玩家数据
.PlayerData {
    name 0 : string
    level 1 : integer
    exp 2 : integer
    reason 3 : integer
    char_list 4 : []CharData
    squad 5 : []string
    desktop_char 6 : string
    items 7 : []ItemStack
    permissions 8 : []string
}

# 干员数据
.CharData {
    id 0 : string
    template_id 1 : string
    elite 2 : integer
    level 3 : integer
    exp 4 : integer
    trust 5 : integer
}

# 物品数据
.ItemStack {
    id 0 : integer
    amount 1 : integer
}
```

### 9.2 错误码

| 错误码 | 含义 |
|--------|------|
| 0 | 成功 |
| 1 | 密码错误 / 账号已存在（注册时） |
| 2 | 账号不存在 / 密码格式不对（注册时） |
| 3 | 服务器维护 |
| 4 | Token 无效（重连时） |
| 1001 | 队列已满 |
| 1002 | 登录超时 |
| 1003 | 系统错误 |

**错误码范围**：
- `0-99`：通用成功/失败
- `1-99`：登录相关
- `1001+`：系统级错误（队列、服务器等）

---

## 10. 设计确认清单

- [x] 整体架构（Gate + Login + Agent）
- [x] Login_Worker 池设计
- [x] DB_Proxy 设计
- [x] Agent 异步拉数据
- [x] 密码存储方案（bcrypt(sha256_str)）
- [x] 顶号逻辑（device_id）
- [x] Token 重连支持
- [x] ECS 单实体设计
- [x] 每玩家一个 ECS World
- [x] MongoDB 集合设计
- [x] 存盘队列设计（简化版）
- [x] 关服流程
- [x] sproto 协议定义
- [x] 项目目录结构（简化版）
- [x] 服务间通信简化设计
- [x] Demo 范围定义

---

## 11. 下一步

进入实现阶段，创建详细的实现计划。

**实现顺序**：
1. 服务目录结构搭建
2. ECS Core 核心实现
3. DB_Proxy + MongoDB 连接
4. Login_Master + Login_Worker
5. Gate + Watchdog 集成
6. Agent + ECS World 集成
7. 登录流程联调
8. 存盘功能实现