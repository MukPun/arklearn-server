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

-- 注册服务处理函数
skynet.start(function()


end)

return db_proxy