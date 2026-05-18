-- PlayerDataComponent：玩家游戏数据
local Component = require "ecs.core.component"

local PlayerDataComponent = {}
PlayerDataComponent.__index = PlayerDataComponent
setmetatable(PlayerDataComponent, {__index = Component})

function PlayerDataComponent.new(data)
    local self = Component.new(data)
    self.uid = data.uid or 0
    self.name = data.name or ""
    self.level = data.level or 1
    self.exp = data.exp or 0
    self.reason = data.reason or 100
    self.charList = data.charList or {}      -- {[id] = CharData}
    self.squad = data.squad or {}           -- {[]} = char_id
    self.desktopChar = data.desktopChar or ""
    self.items = data.items or {}           -- {[id] = ItemStack}
    self.permissions = data.permissions or {}
    return setmetatable(self, PlayerDataComponent)
end

-- CharData: 干员数据
local CharData = {
    id = "",
    templateId = "",
    elite = 0,
    level = 1,
    exp = 0,
    trust = 0,
}

-- ItemStack: 物品数据
local ItemStack = {
    id = 0,
    amount = 0,
}

return {
    PlayerDataComponent = PlayerDataComponent,
    CharData = CharData,
    ItemStack = ItemStack,
}