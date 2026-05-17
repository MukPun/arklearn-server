-- Gate 服务：处理网络连接和协议解析
local skynet = require "skynet"
local sproto = require "sproto"
local netpack = require "skynet.netpack"

local gate = {}
local sockets = {}
local handshake = {}

-- 加载 sproto 协议
local login_proto = require "proto.login"

function gate.open(conf)
    gate.conf = conf
    gate.host = conf.host or "0.0.0.0"
    gate.port = conf.port or 8888
    gate.maxclient = conf.maxclient or 64
    gate.servername = conf.servername or "ark_server"

    -- 启动监听
    skynet.call("simpledb", "lua", "listen", gate.host, gate.port)

    -- 注册 socket 回调
    -- 这里简化处理，实际需要使用 skynet.socket
end

function gate.close()
    for fd, _ in pairs(sockets) do
        skynet.call(gate.self, "lua", "kick", fd)
    end
end

function gate.start(conf)
    gate.conf = conf
end

function gate.data(fd, msg, size)
    -- 处理接收到的数据
end

function gate.disconnect(fd)
    -- 处理断开连接
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        if cmd == "socket" then
            -- socket 事件处理
        else
            local f = gate[cmd]
            if f then
                f(...)
            end
        end
    end)
end)

return gate