local Enemy = require("src.enemy")
local Renderer = require("src.renderer")

local Seeker = {}
Seeker.__index = Seeker
setmetatable(Seeker, {__index = Enemy})

function Seeker.new(x, y, maze)
    local self = Enemy.new(x, y, maze)
    setmetatable(self, Seeker)

    -- Assign specific sprite for Seeker if available, else fallback
    self.spriteSheet = (Renderer.seeker and Renderer.seeker.spritesheet) or (Renderer.enemy and Renderer.enemy.spritesheet) or self.spriteSheet
    self.frameWidth = (Renderer.seeker and Renderer.seeker.frameSize) or self.frameWidth
    self.frameHeight = self.frameWidth
    self.spriteScale = ((Renderer.seeker and Renderer.seeker.scale) or (Renderer.tileSize / self.frameWidth)) * 0.8

    self.speed = 95
    self.path = nil
    
    -- Path re-calculation settings
    self.repathTimer = 0
    self.repathInterval = 0.5 -- Check every 0.5 seconds
    self.lastPlayerX = -1
    self.lastPlayerY = -1
    
    return self
end

-- Called automatically by Base Enemy at the start of update(dt)
function Seeker:preMovementUpdate(dt)
    self.repathTimer = self.repathTimer - dt
    
    local player = _G.game and _G.game.player
    if not player then return end

    if self.repathTimer <= 0 then
        local pGridX = math.floor((player.gridX - 1) / 3) + 1
        local pGridY = math.floor((player.gridY - 1) / 3) + 1
        
        -- Only recompute if player changed tile or we have no path
        local playerMoved = (pGridX ~= self.lastPlayerX or pGridY ~= self.lastPlayerY)
        local noPath = (not self.path or #self.path == 0)
        
        if playerMoved or noPath then
            -- Budget check
            if not _G.game.pathfinderUsed or _G.game.pathfinderUsed < (_G.game.pathfinderBudget or 4) then
                if _G.game then _G.game.pathfinderUsed = (_G.game.pathfinderUsed or 0) + 1 end
                
                self.path = self:findPathToPlayer(2000)
                self.lastPlayerX = pGridX
                self.lastPlayerY = pGridY
            end
        end
        
        self.repathTimer = self.repathInterval
    end
end

function Seeker:decideNextMove()
    if self.path and #self.path > 0 then
        local nextStep = self.path[1]
        
        if self:canGo(nextStep) then
            self.direction = nextStep
            table.remove(self.path, 1)
        else
            -- Path is blocked or invalid
            self.path = nil 
            self.direction = nil
        end
    else
        self.direction = nil
    end
end

function Seeker:draw()
    -- Draw Base Sprite
    Enemy.draw(self)
    
    -- Red Identity Dot
    love.graphics.setColor(1, 0, 0, 0.8)
    love.graphics.circle("fill", self.pixelX, self.pixelY, 6)
    
    -- Debug Path Visualization
    if _G.game and _G.game.debug and self.path then
        love.graphics.setColor(1, 1, 0, 0.6) -- Yellow dots
        
        local ts = Renderer.tileSize
        local simX, simY = self.x, self.y
        local mapDirs = { north = {0, -1}, south = {0, 1}, east = {1, 0}, west = {-1, 0} }
        
        for _, dir in ipairs(self.path) do
            local delta = mapDirs[dir]
            if delta then
                simX = simX + delta[1]
                simY = simY + delta[2]
                
                local drawX = (simX - 1) * ts + ts / 2
                local drawY = (simY - 1) * ts + ts / 2
                
                love.graphics.circle("fill", drawX, drawY, 3)
            end
        end
    end
    
    love.graphics.setColor(1, 1, 1)
end

return Seeker