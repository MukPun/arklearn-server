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