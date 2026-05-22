local skynet = require "skynet"
local mongo = require "skynet.db.mongo"
local bson = require "bson"
local conf = require "etc.database"

local db_proxy = {}
local db_instance = nil

function db_proxy.init()
    local client = mongo.client(conf)
    db_instance = client:getDB(conf.database)
    -- 创建索引
    db_instance.accounts:createIndex({name = 1}, {unique = true})
    skynet.error("DB proxy initialized")
end

local function test_auth()
    print("Test auth start")
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
	if conf.username then
		print("Test auth")
		test_auth()
	end
	skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = db_proxy[cmd]
        if f then
            local ret = f(...)
            if session > 0 then
                skynet.ret(skynet.pack(ret))
            end
        end
	end)

end)

return db_proxy