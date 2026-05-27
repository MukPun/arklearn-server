-- 负责加载协议的服务
local sprotoparser = require "sprotoparser"
local sprotoloader = require "sprotoloader"
local service = require "service"
local log = require "log"

local loader = {}
local data = {}

local function load(name)
	local filename = string.format("proto/%s.sproto", name)
	local f = assert(io.open(filename), "Can't open " .. name)
	local t = f:read "a"
	f:close()
	return sprotoparser.parse(t)
end

function loader.load(list)
	for i, name in ipairs(list) do
		local p = load(name)
		log("load proto [%s] in slot %d", name, i)
		data[name] = i
		sprotoloader.save(p, i)
	end
end

function loader.index(name)		-- 获取协议索引
	return data[name]
end

service.init {
	command = loader,
	info = data
}
