local skynet = require "skynet"
local mongo = require "skynet.db.mongo"
local bson = require "bson"
local conf = require "database_cfg"


local dbserver = {}
local db_instance = nil
local black_list = {}


local function test_auth()
    skynet.error("Test auth start")
	local ok, err, ret
	local c = mongo.client(conf)
	local db = c["admin"]
	db:auth(conf.username, conf.password)

	db.testcoll:dropIndex("*")
	db.testcoll:drop()

	ok, err, ret = db.testcoll:safe_insert({test_key = 1});
	assert(ok and ret and ret.n == 1, err)

	ok, err, ret = db.testcoll:safe_insert({test_key = 1});
	assert(ok and ret and ret.n == 1, err)
    skynet.error("Test auth success")
end


local function check_collection(name)
    if not name or black_list[name] then
        return false, "black list not allowed: " .. tostring(name)
    end
    return true
end

function dbserver.init()
    local client = mongo.client(conf)
    db_instance = client:getDB(conf.database)
    -- 读取黑名单
    black_list = {}
    if conf.black_list and type(conf.black_list) == "table" then
        for _, v in ipairs(conf.black_list) do
            black_list[v] = true
        end
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
    -- 强制使用 $set 操作符 (设计决策: 避免误操作覆盖整个文档)
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
