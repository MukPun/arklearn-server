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