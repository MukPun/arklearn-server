require "skynet.manager"
local skynet = require "skynet"
local mongo = require "skynet.db.mongo"
local bson = require "bson"
local conf = require "database_cfg"
local logger = require "log"
local const = require "const"


local dbserver = {}
local db_instance
local black_list = {}


local function log(fmt, ...)
	logger.format("[DbServer] " .. fmt, ...)
end

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

local function checkandget_collection(name)
    if not name or black_list[name] then
        return false, "black list not allowed: " .. tostring(name), nil
    end
    return true, "", db_instance[name]
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
    db_instance.accounts:createIndex({uid = 1}, {unique = true})
    db_instance.entities:createIndex({uid = 1}, {unique = true})        -- 实体表 (包含角色数据)
    skynet.error("dbserver initialized")
end

-- 插入
-- @collection string 表名
-- @doc table 表
function dbserver.insert(collection, doc)
    local ok, err, collection_obj = checkandget_collection(collection)
    if not ok then
        return false, err
    end
    return collection_obj:safe_insert(doc)
end

-- 更新表 只更新指定字段而不是全替换
-- @collection string 表名
-- @query table 查询条件
-- @update table 要更新的内容
function dbserver.update(collection, query, update)
    local ok, err, collection_obj = checkandget_collection(collection)
    if not ok then
        return false, err
    end
    -- 强制使用 $set 操作符 (设计决策: 避免误操作覆盖整个文档)
    local full_update = {['$set'] = update}
    return collection_obj:safe_update(query, full_update, false, false)
end

function dbserver.delete(collection, query)
    local ok, err, collection_obj = checkandget_collection(collection)
    if not ok then
        return false, err
    end
    return collection_obj:safe_delete(query, true)
end

function dbserver.findOne(collection, query)
    local ok, err, collection_obj = checkandget_collection(collection)
    if not ok then
        return false, err
    end
    skynet.error("query=", query.uid, "collection_obj:", collection_obj)
    return collection_obj:findOne(query)
end

function dbserver.find(collection, query)
    local ok, err, collection_obj = checkandget_collection(collection)
    if not ok then
        return false, err
    end
    return collection_obj:find(query)
end

-- 注册服务处理函数
skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        log("accept message:%s", cmd)
        local f = dbserver[cmd]
        if f then
            local ret = {f(...)}
            if session > 0 then
                skynet.ret(skynet.pack(table.unpack(ret)))
            end
        end
    end)
    skynet.register(const.public_server_name.DB_SERVER)
    test_auth()
end)

return dbserver
