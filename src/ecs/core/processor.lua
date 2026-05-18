-- Processor 基类：逻辑处理器

local Processor = {}
Processor.__index = Processor

function Processor.new()
    return setmetatable({}, Processor)
end

function Processor:update(dt)
    -- 可被重写
end

return Processor