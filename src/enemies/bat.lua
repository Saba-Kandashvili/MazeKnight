local BaseEnemy = require("src.enemy")
local Renderer = require("src.renderer")

local Bat = {}
Bat.__index = Bat
setmetatable(Bat, {__index = BaseEnemy})

function Bat.new(x, y, maze)
    local self = BaseEnemy.new(x, y, maze)
    setmetatable(self, Bat)
    
    self.spriteSheet = Renderer.enemy and Renderer.enemy.spritesheet or nil
    self.frameWidth = 32
    self.frameHeight = 32
    self.spriteScale = ((Renderer.enemy and Renderer.enemy.scale) or (Renderer.tileSize / self.frameWidth)) * 0.8
    
    local dirs = {"north", "south", "east", "west"}
    for i = 1, 10 do
        local d = dirs[math.random(1, 4)]
        if self:canGo(d) then
            self.direction = d
            break
        end
    end
    
    return self
end

function Bat:decideNextMove()
    if self.direction and self:canGo(self.direction) then
        return
    end
    
    local reverse = {north="south", south="north", east="west", west="east"}
    local backDir = reverse[self.direction]
    
    if backDir and self:canGo(backDir) then
        self.direction = backDir
        return
    end
    
    local dirs = {"north", "south", "east", "west"}
    for _, d in ipairs(dirs) do
        if self:canGo(d) then
            self.direction = d
            return
        end
    end
    
    self.direction = nil
end

return Bat