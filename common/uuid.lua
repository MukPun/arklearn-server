
local skynet = require "skynet"

local UUID = {}

-- 基准时间戳: 2025-01-01 08:00:00 准确到毫秒
local EPOCH = 1735689600000
-- 时间戳 bit 长度 32
local TIMESTAMP_LEN = 32
local TIMESTAMP_SHIFT = (1 << TIMESTAMP_LEN) - 1
-- harbor bit 长度 10
local HARBOR_LEN = 10
local HARBOR_SHIFT = (1 << HARBOR_LEN) - 1
-- 服务句柄 bit 长度 11
local SERVER_LEN = 11
local SERVER_SHIFT = (1 << SERVER_LEN) - 1
-- 递增序列号 bit 长度 10
local SEQUENCE_LEN = 10
local SEQUENCE_SHIFT = (1 << SEQUENCE_LEN) - 1


-- 状态变量
local last_timestamp = 0        -- 上一次的时间戳
local sequence = 0              -- 同一毫秒内的 递增序列号
local harbor = nil              -- skynet.getenv "harbor") 进程harbor
local service_id = nil          -- skynet.self()  服务句柄


local function init_env()
    if not harbor then
        harbor = (skynet.getenv("harbor") or 0) & HARBOR_SHIFT
        service_id = skynet.self() & SERVER_SHIFT
    end
end


local function get_ms_time()
    return math.floor(skynet.time() * 1000)
end

local function wait_next_ms(last_time_stamp)
    local ts = get_ms_time()
    while ts <= last_time_stamp do
        ts = get_ms_time()
    end
    return ts
end

function UUID.genid()
    init_env()
    -- skynet.time() 是当前 Unix 时间戳, 取整
    local current_timestamp = get_ms_time() - EPOCH

    if current_timestamp < last_timestamp then
        skynet.error("Clock moved back. Refusing to generate id")
        current_timestamp = last_timestamp
    end

    -- 在同一毫秒内 序列号递增
    if current_timestamp == last_timestamp then
        sequence = (sequence + 1) & SEQUENCE_SHIFT
        -- 1毫秒内序列号 溢出
        if sequence == 0 then
            current_timestamp = wait_next_ms(current_timestamp)
            sequence = 0
        end
    else
        -- 跨毫秒
        sequence = 0
    end

    -- 步进
    last_timestamp = current_timestamp

    -- 64 位整数
    --结构: [留空1位] [时间32位] [服ID 10位] [服务ID 11位] [序列号 10位]
    local uuid = (current_timestamp & TIMESTAMP_SHIFT) << 31
                | (harbor << 21)
                | (service_id << 10)
                | sequence
    return uuid
end

return UUID