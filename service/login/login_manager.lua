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