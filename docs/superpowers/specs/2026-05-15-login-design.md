# ARK Server 登录功能设计文档

**日期**: 2026-05-15
**版本**: 1.0
**状态**: 设计阶段

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

### 2.3 ECS 与 Actor 关系

- **Actor 模型**：作为服务分发和并发管理的基础单元
- **ECS**：在 Actor 内部运行，每个玩家一个 ECS World
- **扩展性**：单节点内服务可拆分，未来切多节点只需改配置

---

## 3. 服务设计

### 3.1 Login_Master

**职责**：
- 接收登录请求，写入登录队列
- 每帧处理登录队列
- 检查账号是否在线（顶号逻辑）
- 向 DB_Proxy 查询账号 bcrypt_hash
- 派发验证任务给 Login_Worker
- 接收验证结果，通知 Agent_Mgr
- 持有服务器登录信息。如在线玩家uid列表（检查是否顶号）、在线玩家数量等等

**关键参数**：

| 参数 | 建议值 | 说明 |
|------|-------|------|
| 登录队列最大长度 | 1000 | 超出拒绝请求 |
| 每帧处理数 | 50 | 根据性能调整 |
| 帧间隔 | 100ms | 1秒约处理500登录 |
| 队列超时 | 10s | 超时返回失败 |

### 3.2 Login_Worker (池)

**职责**：

- 执行 bcrypt 验证
- 独立运行，不阻塞其他服务

**配置**：8-16 个 Worker 服务

### 3.3 Agent

**职责**：
- 接收玩家消息
- 异步拉取玩家数据（通过 DB_Proxy）
- 构建 ECS World
- 直接响应客户端（LoginResponse）
- 后续所有玩家交互由 Agent 处理

---

## 4. 登录流程

### 4.1 完整时序

```
客户端                    Gate/WD             Login_Master         Login_Worker    DB_Proxy         Agent_Mgr        Agent
   │                        │                      │                    │              │                  │               │
   │──TCP连接───────────────>│                      │                    │              │                  │               │
   │                        │                      │                    │              │                  │               │
   │──C2G_Login────────────>│                      │                    │              │                  │               │
   │                        │──login请求──────────>│                    │              │                  │               │
   │                        │                      │                    │              │                  │               │
   │                        │                      │──检查在线(顶号)────>│              │                  │               │
   │                        │                      │                    │              │                  │               │
   │                        │                      │──查询bcrypt_hash──>│              │                  │               │
   │                        │                      │<─bcrypt_hash───────│              │                  │               │
   │                        │                      │                    │              │                  │               │
   │                        │                      │──派发验证─────────>│              │                  │               │
   │                        │                      │                    │              │                  │               │
   │                        │                      │<─验证结果──────────│              │                  │               │
   │                        │                      │                    │              │                  │               │
   │                        │                      │──拉起Agent─────────────────────────>│              │               │
   │                        │                      │                    │              │                  │               │
   │                        │                      │                    │              │<─Agent启动─────────│               │
   │                        │                      │                    │              │                  │               │
   │                        │                      │                    │              │──加载玩家数据──────>│               │
   │                        │                      │                    │              │<─玩家数据────────────────────────────│
   │                        │                      │                    │              │                  │               │
   │                        │                      │                    │              │                  │<─构建ECS World
   │                        │                      │                    │              │                  │               │
   │<──G2C_Login_Success────│                      │                    │              │                  │               │
   │                        │                      │                    │              │                  │<─后续消息──────>
   │                        │                      │                    │              │                  │               │
```

### 4.2 第一阶段：客户端发起

1. 客户端输入密码
2. 在 Unity 端执行 SHA256(password)
3. 客户端连接到 Gate
4. 通过 sproto 发送 login 请求（account + password_hash + device_id）

### 4.3 第二阶段：服务端验证

1. Gate 收到消息，转发 Login_Master
2. Login_Master 检查账号是否在线（顶号逻辑）
3. 向 DB_Proxy 请求查询账号 bcrypt_hash
4. 将验证任务派发给空闲的 Login_Worker
5. Login_Worker 执行 bcrypt.verify(client_sha256, db_bcrypt_hash)
6. 返回验证结果给 Login_Master

### 4.4 第三阶段：Agent 创建与 ECS 初始化

1. Login_Master 验证成功，生成 Token
2. 通知 Agent_Mgr 拉起 Agent
3. Agent 启动，异步向 DB_Proxy 请求玩家数据
4. Agent 收到数据，构建 ECS World（Entity + Components）
5. Agent 通知 Agent_Mgr 注册自己

### 4.5 第四阶段：登录成功响应

1. Agent 组装 LoginResponse（uid + token+playerData）
2. Agent 直接响应客户端
3. 客户端收到成功响应，保存 Token，进入游戏

---

## 5. 密码安全设计

### 5.1 密码存储

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

### 5.2 安全特性

- **客户端 SHA256**：不传输明文密码
- **服务端 bcrypt**：哈希存储，防彩虹表攻击
- **加盐**：bcrypt 自动处理 salt
- **bcrypt 成本**：10-12 轮，平衡安全性和性能

---

## 6. ECS 设计

### 6.1 设计理念

ECS 架构遵循以下核心原则：
- **C（Component）**：纯数据载体，不包含逻辑
- **E（Entity）**：实体的标识，通过挂载不同 Component 组合获得不同功能
- **S（System）**：控制逻辑，处理拥有特定 Component 的实体

### 6.2 ECS 核心（ecs/core/）

| 文件 | 职责 |
|------|------|
| `world.lua` | World 管理器，负责 Entity 创建/销毁、Component 挂载/卸载、System 执行 |
| `component.lua` | Component 基类，定义数据结构和注册机制 |
| `system.lua` | System 基类，定义逻辑更新接口 |
| `entity.lua` | Entity 实现，作为 Component 的容器 |

### 6.3 组件定义（ecs/components/）

```lua
-- Account Component (账号信息)
Account = {
    id = "",        -- 玩家全局唯一ID
    name = "",      -- 用户名（登录用）
    password = "",  -- bcrypt hash
}

-- PlayerData Component (玩家游戏数据)
PlayerData = {
    name = "",        -- 玩家昵称
    level = 0,		-- 等级
    exp = 0,		-- 经验值
    reason = 0,		--
    charList = {},    -- List<CharData> (玩家持有的所有干员)
    squad = {},       -- string[](队伍干员ID)
    desktopChar = "", -- 桌面干员ID
    items = {},       -- List<ItemStack>
    permissions = {}  -- List<string>
}

-- CharData Component (玩家持有的干员 - 养成数据)
CharData = {
    id = "",        -- 干员唯一ID
    templateId = "", -- 干员模板ID (对应静态配置)
    elite = 0,      -- 精英等级(0-2)
    level = 0,      -- 等级
    exp = 0,        -- 当前经验
    trust = 0       -- 信赖值
}

-- ItemStack Component (玩家持有物品)
ItemStack = {
    id = 0,      -- 物品ID
    amount = 0   -- 数量
}
```

### 6.2 Entity 结构

```
PlayerEntity
├── Account Component     (账号信息)
└── PlayerData Component  (玩家数据，包含 charList 和 items)
```

**说明**：CharData 和 ItemStack 作为 PlayerData 的子字段嵌入，而非独立 Component。

### 6.3 系统定义

| 系统 | 职责 |
|------|------|
| LoginSystem | 处理登录验证逻辑 |
| SaveSystem | 定期将 ECS 数据回写 MongoDB |
| LoadSystem | 从 MongoDB 加载玩家数据到 ECS |

### 6.4 架构决策：每玩家一个 ECS World

**原因**：
- 状态隔离，错误不扩散
- 数据缓存天然按玩家分
- 为多节点扩展预留接口

**代价**：
- 内存开销（5000 个 World 实例需监控）
- 跨玩家交互需通过消息路由

---

## 7. 数据持久化

### 7.1 MongoDB 集合设计

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

**设计决策**：
- `charList` 和 `items` 嵌入 `players` 文档，减少 `_id` 数量
- MongoDB 16MB 限制对正常玩家数据完全够用
- 单文档查询更高效，无需跨集合 JOIN

### 7.2 索引设计

```javascript
// accounts - 用户名唯一索引
db.accounts.createIndex({ "name": 1 }, { unique: true })

// players - uid 唯一索引（由 _id 提供，自动有唯一索引）
// players.name 如需按昵称查询可加索引（预留）
db.players.createIndex({ "name": 1 })
```

### 7.3 存盘策略

**存盘队列设计**：

```
数据变更 → 检测变化 → 加入待存盘队列
                              ↓
                    定时器每30秒拉取N个 → 批量写入MongoDB
```

**关键参数**：

| 参数 | 建议值 | 说明 |
|------|-------|------|
| 定时存档间隔 | 30s | 平衡性能和数据安全 |
| 每帧处理数 | 20 | 根据 DB 性能调整 |
| 队列最大长度 | 5000 | 超出告警 |

**关服流程**：

```
收到关服指令 → 停止接受新请求 → 处理存盘队列（全部）
                                ↓
                         所有数据落盘 → 执行 skynet.exit()
```

---

## 8. Sproto 协议定义

### 8.1 协议文件

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

### 8.2 错误码

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

## 9. 项目目录结构

```
ark-server/
├── skynet/                 # skynet 源码（submodule）
│
├── service/                # skynet 服务
│   ├── gate/               # 网关服务
│   │   ├── gate.lua
│   │   └── config
│   ├── login/              # 登录服务
│   │   ├── login_master.lua
│   │   ├── login_worker.lua
│   │   └── config
│   ├── db/                 # 数据库代理
│   │   ├── db_proxy.lua
│   │   └── mongo_client.lua
│   └── agent_mgr/          # Agent 管理器
│       └── agent_mgr.lua
│
├── ecs/                           # ECS 核心框架
│   ├── core/                      # ECS 引擎核心
│   │   ├── world.lua              # World 管理器
│   │   ├── component.lua          # Component 基类
│   │   ├── system.lua            # System 基类
│   │   └── entity.lua             # Entity 实现
│   ├── components/                # 组件定义 (C - 数据)
│   │   ├── account.lua            # 账号组件
│   │   ├── player_data.lua        # 玩家数据组件
│   │   ├── char_data.lua          # 干员数据组件
│   │   ├── item_stack.lua         # 物品组件
│   │   └── ...                    # 更多组件按需添加
│   └── systems/                   # 系统定义 (S - 逻辑)
│       ├── login_system.lua       # 登录逻辑
│       ├── save_system.lua        # 存档逻辑
│       ├── load_system.lua        # 加载逻辑
│       └── ...                    # 更多系统按需添加
│
├── entities/                      # 实体模板 (E - 实体的组装规则)
│   ├── player_entity.lua           # 玩家实体
│   ├── operator_entity.lua        # 干员实体
│   └── ...                        # 更多实体按需添加
│
├── agent/                  # Agent 服务 (ECS World 容器)
│   ├── agent.lua           # Agent 入口
│   └── world.lua           # ECS World 实例化
│
├── proto/                  # sproto 协议定义
│   ├── login.sproto
│   └── game.sproto
│
├── config/                 # 配置文件
│   ├── gate.lua
│   ├── login.lua
│   ├── agent.lua
│   └── database.lua
│
├── lib/                    # 公共库
│   ├── mongo/              # MongoDB 操作封装
│   ├── bcrypt/             # bcrypt 封装
│   └── sproto/             # sproto 封装
│
└── tools/                  # 工具脚本
    ├── init_db.js          # 初始化数据库索引
    └── gen_char_data.py    # 生成干员配置
```

---

## 10. 扩展性设计

### 10.1 多节点扩展

当前单节点架构预留多节点扩展能力：

- **服务拆分**：Gate、Login、Agent 可拆分到不同节点
- **Actor 通信**：跨节点通过 skynet 消息传递
- **数据分片**：MongoDB 分片支持数据水平扩展

### 10.2 Agent 数量扩展

- 当前：单节点运行所有 Agent
- 未来：Agent 可分布到多个 skynet node
- 路由：Agent_Mgr 维护 Agent 地址映射

---

## 11. 设计确认清单

- [x] 整体架构（Gate + Login + Agent）
- [x] Login_Worker 池设计
- [x] DB_Proxy 设计
- [x] Agent 异步拉数据
- [x] 密码存储方案（bcrypt(sha256_str)）
- [x] 顶号逻辑（device_id）
- [x] Token 重连支持
- [x] ECS 组件设计
- [x] 每玩家一个 ECS World
- [x] MongoDB 集合设计
- [x] 存盘队列设计
- [x] 关服流程
- [x] sproto 协议定义
- [x] 项目目录结构

---

**下一步**：进入实现阶段，创建详细的实现计划。