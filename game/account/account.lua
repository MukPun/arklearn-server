local skynet = require "skynet"

local account = {} 


function account.handshake()
    skynet.error("handshake")
    return {result = 1}
end


function account.heartbeat()
    skynet.error("handshake")
    return {result = 2}
end

return account