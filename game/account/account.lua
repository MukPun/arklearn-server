local skynet = require "skynet"

local account = {} 


function account.test_func()
    skynet.error("test_func")
    return true
end


return account