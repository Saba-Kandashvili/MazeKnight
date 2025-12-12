local Enemy = require("src.enemy")
local Renderer = require("src.renderer")

local Seeker = {}
Seeker.__index = Seeker
setmetatable(Seeker, {__index = Enemy})

function Seeker.new(x, y, maze)
    local self = Enemy.new(x, y, maze)
    setmetatable(self, Seeker)

    -- visual setup
    if Renderer.seeker then
        self.spriteSheet = Renderer.seeker.spritesheet
        self.frameWidth = Renderer.seeker.frameSize
        self.frameHeight = self.frameWidth
        -- scale: was 0.8, now 0.4 (twice as small)
        self.spriteScale = (Renderer.seeker.scale or 1) * 0.4
    else
        -- fallback
        self.spriteSheet = (Renderer.enemy and Renderer.enemy.spritesheet)
        self.frameWidth = 32
        self.spriteScale = 1
    end

    self.speed = 95
    self.path = nil

    -- path re-calculation settings
    self.repathTimer = 0
    self.repathInterval = 0.5
    self.lastPlayerX = -1
    self.lastPlayerY = -1

    -- aggro settings
    self.detectionRadius = 200 -- distance to START chasing
    self.chaseRadius = 350     -- distance to STOP chasing (must run far away to lose it)
    self.warningRadius = 260   -- distance where "!" appears to warn player
    
    self.state = "idle" -- "idle" or "chase"

    return self
end

function Seeker:preMovementUpdate(dt)
    self.repathTimer = self.repathTimer - dt
    local player = _G.game and _G.game.player
    if not player then return end

    -- distance check
    local dx = self.pixelX - player.pixelX
    local dy = self.pixelY - player.pixelY
    local dist = math.sqrt(dx*dx + dy*dy)

    -- state switching logic with hysteresis
    if self.state == "idle" then
        -- if we get too close, get angry
        if dist < self.detectionRadius then
            self.state = "chase"
        end
    elseif self.state == "chase" then
        -- if we run far enough away, it gives up
        if dist > self.chaseRadius then
            self.state = "idle"
            self.path = nil -- stop moving immediately
        end
    end

    -- pathfinding logic (only when chasing)
    if self.state == "chase" and self.repathTimer <= 0 then
        local pGridX = math.floor((player.gridX - 1) / 3) + 1
        local pGridY = math.floor((player.gridY - 1) / 3) + 1

        local playerMoved = (pGridX ~= self.lastPlayerX or pGridY ~= self.lastPlayerY)
        local noPath = (not self.path or #self.path == 0)

        if playerMoved or noPath then
            -- check budget
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
    if self.state == "chase" then
        -- follow the path logic
        if self.path and #self.path > 0 then
            local nextStep = self.path[1]

            if self:canGo(nextStep) then
                self.direction = nextStep
                table.remove(self.path, 1)
            else
                self.path = nil
                self.direction = nil
            end
        else
            self.direction = nil
        end
    else
        -- idle mode: just wander around aimlessly
        self:wander()
    end
end

function Seeker:draw()
    -- check distance for the "!" visibility
    local showAlert = false
    if _G.game and _G.game.player and not self.isDead then
        local dx = self.pixelX - _G.game.player.pixelX
        local dy = self.pixelY - _G.game.player.pixelY
        local dist = math.sqrt(dx*dx + dy*dy)

        -- show if chasing OR if player is inside warning zone
        if self.state == "chase" or dist < self.warningRadius then
            showAlert = true
        end
    end

    -- draw the "!" notification
    if showAlert then
        local t = love.timer.getTime() * 5
        local bobOffset = math.sin(t) * 3 -- bob up and down
        local exX = self.pixelX
        local exY = self.pixelY - 28 + bobOffset 

        love.graphics.setColor(1, 0, 0, 1) -- pure red
        
        -- draw pixelated "!" manually
        -- top part
        love.graphics.rectangle("fill", exX - 2, exY - 10, 4, 12)
        -- dot part
        love.graphics.rectangle("fill", exX - 2, exY + 4, 4, 4)
        
        love.graphics.setColor(1, 1, 1, 1)
    end

    if self.spriteSheet and Renderer.seeker and Renderer.seeker.quads then
        local rowMap = { south = 1, west = 2, east = 3, north = 4 }
        local row = rowMap[self.direction] or 1
        local col = 1

        if self.direction and not self.isDead then
            col = self.animFrame
        end

        if Renderer.seeker.quads[row] and Renderer.seeker.quads[row][col] then
            local quad = Renderer.seeker.quads[row][col]

            -- death effect: darken if dead
            if self.isDead then
                love.graphics.setColor(0.2, 0.2, 0.2, 1)
            else
                love.graphics.setColor(1, 1, 1, 1)
            end

            love.graphics.draw(
                self.spriteSheet,
                quad,
                self.pixelX,
                self.pixelY - 8,
                0,
                self.spriteScale,
                self.spriteScale,
                self.frameWidth / 2,
                self.frameHeight / 2
            )
            love.graphics.setColor(1, 1, 1)
        end
    else
        -- fallback draw
        if self.isDead then
            love.graphics.setColor(0.2, 0.2, 0.2)
        else
            love.graphics.setColor(0.8, 0.2, 0.2)
        end
        love.graphics.circle("fill", self.pixelX, self.pixelY, self.radius)
        love.graphics.setColor(1, 1, 1)
    end

    -- debug visuals
    if _G.game and _G.game.debug and not self.isDead then
        -- red identity dot
        love.graphics.setColor(1, 0, 0, 0.8)
        love.graphics.circle("fill", self.pixelX, self.pixelY, 4)

        -- path dots
        if self.path then
            love.graphics.setColor(1, 1, 0, 0.6)
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
                    love.graphics.circle("fill", drawX, drawY, 2)
                end
            end
        end
        love.graphics.setColor(1, 1, 1)
    end
end

return Seeker