-- AccountComponent：账号信息
local Component = require "ecs.core.component"

local AccountComponent = {}
AccountComponent.__index = AccountComponent
setmetatable(AccountComponent, {__index = Component})

function AccountComponent.new(data)
    local self = Component.new(data)
    self.uid = data.uid or 0
    self.name = data.name or ""
    self.password_hash = data.password_hash or ""
    return setmetatable(self, AccountComponent)
end

return AccountComponent