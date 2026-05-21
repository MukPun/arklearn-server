-- common/struct.lua
local struct = {}


struct.login = {
    linkObj = {                 -- 链接对象 此时客户端链接成功 但还未进行登录
        fd = nil,				-- socket 唯一id
		ip = nil,				-- 客户端地址信息
		agent = nil,			-- agent服务句柄
    }
}

return struct