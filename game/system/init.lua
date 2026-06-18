local skynet = require "skynet"

local system = {} 


-- 登录成功后,首次进行握手
-- 由于简化登录流程 没用选择角色的过程, 首次握手协议保留, 方便后续拓展
-- 角色数据又客户端握手成功后,通过query_player_data请求
function system.handshake(user_obj)
    skynet.error("handshake success. uid=", user_obj:get_uid())
    return {result = 1}
end

-- 心跳协议,目前不知道做什么,就正常返回，告诉服务端正常即可。
function system.heartbeat(user_obj)
    skynet.error("heartbeat uid=", user_obj:get_uid())
    return {result = 2}
end

return system