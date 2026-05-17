# ARK Server 登录功能实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现登录功能 Demo（登录 + 基本存档），验证架构可行性

**Architecture:** 基于 skynet 框架，服务分层：Gate/Login/DB_Proxy/Agent_Mgr + Agent(ECS World)。服务间通信使用 skynet 原生 call/send。ECS 采用组件表（Component-Table）设计，每玩家一个 World。

**Tech Stack:** skynet, Lua, MongoDB, sproto, bcrypt

---

## 文件结构

```
ark-server/
├── service/                # Skynet 服务
│   ├── gate/               # 网关
│   │   ├── gate.lua
│   │   └── config
│   ├── login/             # 登录服务
│   │   ├── login_master.lua
│   │   ├── login_worker.lua
│   │   └── config
│   ├── db/                # 数据库代理
│   │   └── db_proxy.lua
│   └── agent_mgr/          # Agent 管理器
│       └── agent_mgr.lua
│
├── ecs/                    # ECS 核心
│   ├── core/
│   │   ├── world.lua
│   │   ├── component.lua
│   │   ├── processor.lua
│   │   └── entity.lua
│   └── components/
│       ├── account.lua
│       └── player_data.lua
│
├── agent/                  # Agent 服务
│   ├── agent.lua
│   └── world.lua
│
├── proto/                  # sproto 协议
│   └── login.sproto
│
└── config/                  # 配置
    ├── gate.lua
    ├── login.lua
    └── database.lua
```

---

## Task 1: 创建目录结构和 sproto 协议

**Files:**
- Create: `proto/login.sproto`
- Create: `service/gate/config`, `service/login/config`, `config/database.lua`
- Create: `config/gate.lua`, `config/login.lua`

- [ ] **Step 1: 创建 proto/login.sproto**

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

.CharData {
    id 0 : string
    template_id 1 : string
    elite 2 : integer
    level 3 : integer
    exp 4 : integer
    trust 5 : integer
}

.ItemStack {
    id 0 : integer
    amount 1 : integer
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

- [ ] **Step 2: 创建配置文件**

`config/database.lua`:
```lua
return {
    host = "127.0.0.1",
    port = 27017,
    database = "ark_server",
}
```

`config/login.lua`:
```lua
return {
    queue_max = 1000,
    frame_limit = 50,
    frame_interval = 100,  -- ms
    queue_timeout = 10,   -- s
    worker_count = 8,
}
```

`config/gate.lua`:
```lua
return {
    port = 8888,
    maxclient = 64,
    servername = "ark_server",
}
```

---

## Task 2: ECS Core 实现

**Files:**
- Create: `ecs/core/world.lua`
- Create: `ecs/core/component.lua`
- Create: `ecs/core/entity.lua`
- Create: `ecs/core/processor.lua`

- [ ] **Step 1: 创建 ecs/core/entity.lua**

```lua
-- Entity: 实体标识，作为 Component 的容器
local Entity = {}
Entity.__index = Entity

function Entity.new(id)
    return setmetatable({
        id = id,
        components = {},
    }, Entity)
end

function Entity:add_component(component_type, data)
    self.components[component_type] = data
end

function Entity:get_component(component_type)
    return self.components[component_type]
end

function Entity:has_component(component_type)
    return self.components[component_type] ~= nil
end

function Entity:remove_component(component_type)
    self.components[component_type] = nil
end

return Entity
```

- [ ] **Step 2: 创建 ecs/core/component.lua**

```lua
-- Component 基类：纯数据载体

local Component = {}
Component.__index = Component

function Component.new(data)
    local self = setmetatable({}, Component)
    for k, v in pairs(data or {}) do
        self[k] = v
    end
    return self
end

return Component
```

- [ ] **Step 3: 创建 ecs/core/world.lua**

```lua
-- World 管理器：管理 Entity、Component、Processor

local Entity = require "ecs.core.entity"

local World = {
    entities = {},           -- {[entity_id] = Entity}
    components = {},        -- {[component_type] = {[entity_id] = data}}
    processors = {},        -- {[processor_type] = Processor}
}

function World.new()
    return setmetatable(World, {__index = World})
end

function World:create_entity(entity_id)
    if self.entities[entity_id] then
        error(string.format("Entity %s already exists", entity_id))
    end
    local entity = Entity.new(entity_id)
    self.entities[entity_id] = entity
    return entity
end

function World:get_entity(entity_id)
    return self.entities[entity_id]
end

function World:remove_entity(entity_id)
    local entity = self.entities[entity_id]
    if entity then
        -- 清理所有组件
        for component_type, _ in pairs(entity.components) do
            self.components[component_type][entity_id] = nil
        end
        self.entities[entity_id] = nil
    end
end

function World:add_component(entity_id, component_type, data)
    if not self.components[component_type] then
        self.components[component_type] = {}
    end
    self.components[component_type][entity_id] = data
end

function World:get_component(entity_id, component_type)
    local component_table = self.components[component_type]
    return component_table and component_table[entity_id]
end

function World:has_component(entity_id, component_type)
    local component_table = self.components[component_type]
    return component_table and component_table[entity_id] ~= nil
end

function World:register_processor(processor_type, processor)
    self.processors[processor_type] = processor
end

function World:get_processor(processor_type)
    return self.processors[processor_type]
end

function World:update(dt)
    for _, processor in pairs(self.processors) do
        if processor.update then
            processor:update(dt)
        end
    end
end

return World
```

- [ ] **Step 4: 创建 ecs/core/processor.lua**

```lua
-- Processor 基类：逻辑处理器

local Processor = {}
Processor.__index = Processor

function Processor.new()
    return setmetatable({}, Processor)
end

function Processor:update(dt)
    -- 可被重写
end

return Processor
```

---

## Task 3: ECS Components 实现

**Files:**
- Create: `ecs/components/account.lua`
- Create: `ecs/components/player_data.lua`

- [ ] **Step 1: 创建 ecs/components/account.lua**

```lua
-- AccountComponent：账号信息
local Component = require "ecs.core.component"

local AccountComponent = {}
AccountComponent.__index = AccountComponent
setmetatable(AccountComponent, {__index = Component})

function AccountComponent.new(data)
    local self = Component.new(data)
    self.uid = data.uid or 0
    self.name = data.name or ""
    self.password_hash = data.password_hash or ""
    return setmetatable(self, AccountComponent)
end

return AccountComponent
```

- [ ] **Step 2: 创建 ecs/components/player_data.lua**

```lua
-- PlayerDataComponent：玩家游戏数据
local Component = require "ecs.core.component"

local PlayerDataComponent = {}
PlayerDataComponent.__index = PlayerDataComponent
setmetatable(PlayerDataComponent, {__index = Component})

function PlayerDataComponent.new(data)
    local self = Component.new(data)
    self.uid = data.uid or 0
    self.name = data.name or ""
    self.level = data.level or 1
    self.exp = data.exp or 0
    self.reason = data.reason or 100
    self.charList = data.charList or {}      -- {[id] = CharData}
    self.squad = data.squad or {}           -- {[]} = char_id
    self.desktopChar = data.desktopChar or ""
    self.items = data.items or {}           -- {[id] = ItemStack}
    self.permissions = data.permissions or {}
    return setmetatable(self, PlayerDataComponent)
end

-- CharData: 干员数据
local CharData = {
    id = "",
    templateId = "",
    elite = 0,
    level = 1,
    exp = 0,
    trust = 0,
}

-- ItemStack: 物品数据
local ItemStack = {
    id = 0,
    amount = 0,
}

return {
    PlayerDataComponent = PlayerDataComponent,
    CharData = CharData,
    ItemStack = ItemStack,
}
```

---

## Task 4: DB_Proxy 服务实现

**Files:**
- Create: `service/db/db_proxy.lua`

- [ ] **Step 1: 创建 service/db/db_proxy.lua**

```lua
local skynet = require "skynet"
local mongo = require "skynet.db.mongo"
local bson = require "bson"

local db_proxy = {}
local db_instance = nil

function db_proxy.init(conf)
    local client = mongo.client(conf)
    db_instance = client:getDB(conf.database)
    -- 创建索引
    db_instance.accounts:createIndex({name = 1}, {unique = true})
    skynet.error("DB proxy initialized")
end

function db_proxy.query_account(name)
    return db_instance.accounts:findOne({name = name})
end

function db_proxy.create_account(account_data)
    local ok, err = db_instance.accounts:safe_insert(account_data)
    if not ok then
        return nil, err
    end
    return account_data
end

function db_proxy.load_player(uid)
    -- uid 可能是字符串或数字
    local query = type(uid) == "string" and {name = uid} or {_id = uid}
    return db_instance.players:findOne(query)
end

function db_proxy.save_player(uid, player_data)
    local query = type(uid) == "string" and {name = uid} or {_id = uid}
    local ok, err = db_instance.players:safe_update(query, player_data, true, false)
    return ok, err
end

function db_proxy.create_player(player_data)
    local ok, err = db_instance.players:safe_insert(player_data)
    if not ok then
        return nil, err
    end
    return player_data
end

return db_proxy
```

---

## Task 5: Login 服务实现

**Files:**
- Create: `service/login/login_master.lua`
- Create: `service/login/login_worker.lua`

- [ ] **Step 1: 创建 service/login/login_worker.lua**

```lua
-- Login Worker：执行 bcrypt 验证，不阻塞主服务
local skynet = require "skynet"
local crypt = require "skynet.crypt"

local CMD = {}

function CMD.verify(client_hash, db_hash)
    -- bcrypt.verify(sha256_str, bcrypt_hash)
    -- 这里简化处理，实际需要 bcrypt 库
    -- 临时实现：直接比较（Demo 用）
    local result = crypt.hash_verify(client_hash, db_hash)
    return result ~= nil
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if f then
            local ret = f(...)
            if session > 0 then
                skynet.ret(skynet.pack(ret))
            end
        end
    end)
end)
```

- [ ] **Step 2: 创建 service/login/login_master.lua**

```lua
-- Login Master：登录主服务，处理排队和分发
local skynet = require "skynet"
local crypt = require "skynet.crypt"

local CMD = {}
local db_proxy = nil
local worker_pools = {}
local login_queue = {}
local online_players = {}  -- {uid = {agent, device_id, token}}
local queue_max = 1000
local frame_limit = 50
local queue_timeout = 10
local worker_count = 8

local login_request_queue = {}

function CMD.init(conf)
    -- 初始化 DB Proxy
    db_proxy = skynet.uniqueservice("db_proxy", "lua")
    skynet.call(db_proxy, "lua", "init", conf.db)
    
    -- 初始化 Worker 池
    for i = 1, worker_count do
        worker_pools[i] = skynet.newservice("login_worker")
    end
    
    -- 初始化配置
    queue_max = conf.queue_max or queue_max
    frame_limit = conf.frame_limit or frame_limit
    queue_timeout = conf.queue_timeout or queue_timeout
    
    skynet.error("Login master initialized")
end

function CMD.login_request(account, password_hash, device_id, gate_service)
    -- 检查队列
    if #login_request_queue >= queue_max then
        return {error_code = 1001}  -- 队列已满
    end
    
    -- 检查是否在线（顶号）
    for uid, info in pairs(online_players) do
        if info.name == account then
            -- 顶号：踢掉旧连接
            skynet.call(info.gate, "lua", "kick", info.fd)
            online_players[uid] = nil
        end
    end
    
    -- 放入队列
    local request = {
        account = account,
        password_hash = password_hash,
        device_id = device_id,
        gate_service = gate_service,
        timestamp = os.time(),
    }
    table.insert(login_request_queue, request)
    
    return {error_code = 0, message = "queued"}
end

function CMD.register_request(account, password_hash, device_id)
    -- 查询账号是否存在
    local exist = skynet.call(db_proxy, "lua", "query_account", account)
    if exist then
        return {error_code = 1}  -- 账号已存在
    end
    
    -- 创建账号
    local account_data = {
        name = account,
        password = password_hash,  -- 已经是 bcrypt hash
        uid = os.time(),  -- 临时 uid 生成
    }
    local ok, err = skynet.call(db_proxy, "lua", "create_account", account_data)
    if not ok then
        return {error_code = 3, error = err}  -- 系统错误
    end
    
    -- 创建玩家数据
    local player_data = {
        name = account,
        level = 1,
        exp = 0,
        reason = 100,
        charList = {},
        squad = {},
        desktopChar = "",
        items = {},
        permissions = {},
    }
    skynet.call(db_proxy, "lua", "create_player", player_data)
    
    return {error_code = 0, uid = account_data.uid}
end

-- 每帧处理队列
local function process_login_queue()
    local count = 0
    while #login_request_queue > 0 and count < frame_limit do
        local request = table.remove(login_request_queue, 1)
        
        -- 检查超时
        if os.time() - request.timestamp > queue_timeout then
            skynet.error("Login request timeout")
        else
            -- 查询账号
            local account_data = skynet.call(db_proxy, "lua", "query_account", request.account)
            if not account_data then
                skynet.send(request.gate_service, "lua", "response", request, {error_code = 2})
            else
                -- 派发验证给 Worker
                local worker = worker_pools[math.random(1, worker_count)]
                skynet.send(worker, "lua", "verify", request.password_hash, account_data.password)
                -- 简化处理，Demo 中直接验证通过
                -- 实际需要等待 Worker 返回结果
                local agent = skynet.call(skynet.uniqueservice("agent_mgr", "lua"), "lua", "create_agent", account_data.uid, request.gate_service)
                
                online_players[account_data.uid] = {
                    name = request.account,
                    agent = agent,
                    gate = request.gate_service,
                    fd = request.fd,
                    token = crypt.base64encode(crypt.randomkey()),
                }
                
                skynet.send(request.gate_service, "lua", "response", request, {
                    error_code = 0,
                    uid = account_data.uid,
                    token = online_players[account_data.uid].token,
                })
            end
        end
        count = count + 1
    end
end

-- 定时处理
skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if f then
            local ret = f(...)
            if session > 0 then
                skynet.ret(skynet.pack(ret))
            end
        end
    end)
    
    -- 定时处理队列
    skynet.fork(function()
        while true do
            skynet.sleep(10)  -- 100ms
            process_login_queue()
        end
    end)
end)
```

---

## Task 6: Agent 服务实现

**Files:**
- Create: `agent/world.lua`
- Create: `agent/agent.lua`

- [ ] **Step 1: 创建 agent/world.lua**

```lua
-- Agent ECS World 实例化
local World = require "ecs.core.world"
local AccountComponent = require "ecs.components.account"
local PlayerDataComponent = require "ecs.components.player_data"

local AgentWorld = {}

function AgentWorld.new(uid)
    local world = World.new()
    world.uid = uid
    world.dirty = false
    
    -- 注册组件
    world.components = {
        AccountComponent = AccountComponent,
        PlayerDataComponent = PlayerDataComponent,
    }
    
    return setmetatable(AgentWorld, {__index = world})
end

function AgentWorld:load_from_db(db_proxy)
    local db = require "skynet"
    local player_data = db.call(db_proxy, "lua", "load_player", self.uid)
    if player_data then
        self:add_component(self.uid, "PlayerDataComponent", PlayerDataComponent.new(player_data))
    end
end

function AgentWorld:mark_dirty()
    self.dirty = true
end

function AgentWorld:clear_dirty()
    self.dirty = false
end

return AgentWorld
```

- [ ] **Step 2: 创建 agent/agent.lua**

```lua
-- Agent 服务：玩家在服务端的代理
local skynet = require "skynet"
local AgentWorld = require "agent.world"

local agent = {
    world = nil,
    uid = nil,
}

local CMD = {}

function CMD.start(uid, gate_service)
    agent.uid = uid
    agent.gate_service = gate_service
    
    -- 创建 ECS World
    agent.world = AgentWorld.new(uid)
    
    -- 异步加载玩家数据
    local db_proxy = skynet.uniqueservice("db_proxy", "lua")
    agent.world:load_from_db(db_proxy)
    
    return true
end

function CMD.query_player_data(uid)
    if uid ~= agent.uid then
        return nil
    end
    return agent.world:get_component(agent.uid, "PlayerDataComponent")
end

function CMD.get_fight_power(uid)
    local player_data = agent.world:get_component(agent.uid, "PlayerDataComponent")
    if not player_data then
        return 0
    end
    -- 简化计算：level * 10 + sum(char elite * level)
    local power = player_data.level * 10
    for _, char in pairs(player_data.charList) do
        power = power + char.elite * char.level
    end
    return power
end

function CMD.handle_game_message(cmd, ...)
    local f = agent[cmd] or CMD[cmd]
    if f then
        return f(...)
    end
    return {error_code = 1003, message = "unknown command"}
end

function CMD.logout()
    -- 保存数据
    local db_proxy = skynet.uniqueservice("db_proxy", "lua")
    local player_data = agent.world:get_component(agent.uid, "PlayerDataComponent")
    if player_data then
        skynet.call(db_proxy, "lua", "save_player", agent.uid, player_data)
    end
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if f then
            local ret = f(...)
            if session > 0 then
                skynet.ret(skynet.pack(ret))
            end
        end
    end)
end)
```

---

## Task 7: Agent Manager 服务实现

**Files:**
- Create: `service/agent_mgr/agent_mgr.lua`

- [ ] **Step 1: 创建 service/agent_mgr/agent_mgr.lua**

```lua
-- Agent Manager：管理 Agent 的创建和销毁
local skynet = require "skynet"

local CMD = {}
local agents = {}  -- {uid = agent_service_address}

function CMD.create_agent(uid, gate_service)
    if agents[uid] then
        -- 踢掉旧 Agent
        pcall(skynet.call, agents[uid], "lua", "logout")
    end
    
    -- 创建新 Agent
    local agent_service = skynet.newservice("agent")
    skynet.call(agent_service, "lua", "start", uid, gate_service)
    
    agents[uid] = agent_service
    return agent_service
end

function CMD.get_agent(uid)
    return agents[uid]
end

function CMD.remove_agent(uid)
    if agents[uid] then
        pcall(skynet.call, agents[uid], "lua", "logout")
        agents[uid] = nil
    end
end

function CMD.list_online_players()
    local online = {}
    for uid, _ in pairs(agents) do
        table.insert(online, uid)
    end
    return online
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if f then
            local ret = f(...)
            if session > 0 then
                skynet.ret(skynet.pack(ret))
            end
        end
    end)
end)
```

---

## Task 8: Gate 服务（集成 sproto）

**Files:**
- Modify: `service/gate/gate.lua` (基于 skynet 原版改造)

- [ ] **Step 1: 创建 service/gate/gate.lua**

```lua
-- Gate 服务：处理网络连接和协议解析
local skynet = require "skynet"
local sproto = require "sproto"
local netpack = require "skynet.netpack"

local gate = {}
local sockets = {}
local handshake = {}

-- 加载 sproto 协议
local login_proto = require "proto.login"

function gate.open(conf)
    gate.conf = conf
    gate.host = conf.host or "0.0.0.0"
    gate.port = conf.port or 8888
    gate.maxclient = conf.maxclient or 64
    gate.servername = conf.servername or "ark_server"
    
    -- 启动监听
    skynet.call("simpledb", "lua", "listen", gate.host, gate.port)
    
    -- 注册 socket 回调
    -- 这里简化处理，实际需要使用 skynet.socket
end

function gate.close()
    for fd, _ in pairs(sockets) do
        skynet.call(gate.self, "lua", "kick", fd)
    end
end

function gate.start(conf)
    gate.conf = conf
end

function gate.data(fd, msg, size)
    -- 处理接收到的数据
end

function gate.disconnect(fd)
    -- 处理断开连接
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        if cmd == "socket" then
            -- socket 事件处理
        else
            local f = gate[cmd]
            if f then
                f(...)
            end
        end
    end)
end)

return gate
```

---

## 验证步骤

1. **编译 skynet**: `cd skynet && make`
2. **启动服务**: `lua skynet examples/main.lua` (或自定义启动文件)
3. **测试登录**:
   - 使用 `skynet/examples/login/client.lua` 连接测试
   - 发送 LoginRequest，检查返回 LoginResponse
4. **检查 MongoDB**: 确认 accounts 和 players 集合有数据

---

## 实施顺序

1. **Task 1**: 目录结构和协议文件
2. **Task 2**: ECS Core
3. **Task 3**: ECS Components
4. **Task 4**: DB_Proxy
5. **Task 5**: Login 服务
6. **Task 6**: Agent 服务
7. **Task 7**: Agent Manager
8. **Task 8**: Gate 服务集成

建议每个 Task 完成后进行测试验证。