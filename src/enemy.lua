local TileMapper = require("src.tile_mapper")
local Renderer = require("src.renderer")

local Enemy = {}
Enemy.__index = Enemy

function Enemy.new(x, y, maze)
    local self = setmetatable({}, Enemy)
    
    self.x = x
    self.y = y
    local ts = Renderer.tileSize
    self.pixelX = (x - 1) * ts + ts / 2
    self.pixelY = (y - 1) * ts + ts / 2
    self.maze = maze
    self.direction = nil
    self.speed = 80
    self.radius = 12
    
    -- sprite / animation defaults (bat is 32x32 inside 128x128)
    self.spriteSheet = Renderer.enemy and Renderer.enemy.spritesheet or nil
    self.frameWidth = 32
    self.frameHeight = 32
    -- (80%) of computed scale
    self.spriteScale = ((Renderer.enemy and Renderer.enemy.scale) or (ts / self.frameWidth)) * 0.8
    self.animFrame = 1
    self.animTimer = 0
    self.animSpeed = 0.12
    self.isDead = false
    -- per-enemy damage cooldown to avoid multiple hits when overlapping player
    self.damageCooldown = 0

    self:chooseNewDirection()
    
    return self
end

function Enemy.canMoveInDirection(tile, direction)
    if not tile or tile.tileType == TileMapper.TileType.EMPTY then
        return false
    end
    
    local code = tile.code
    local PF = TileMapper.PrefabCodes
    
    if direction == "north" then
        return code == PF.North_South_Corridor or
               code == PF.North_East_Corridor or
               code == PF.North_West_Corridor or
               code == PF.North_T_Corridor or
               code == PF.East_T_Corridor or
               code == PF.West_T_Corridor or
               code == PF.Normal_X_Corridor or
               code == PF.North_DeadEnd
               
    elseif direction == "south" then
        return code == PF.North_South_Corridor or
               code == PF.South_East_Corridor or
               code == PF.South_West_Corridor or
               code == PF.South_T_Corridor or
               code == PF.East_T_Corridor or
               code == PF.West_T_Corridor or
               code == PF.Normal_X_Corridor or
               code == PF.South_DeadEnd
               
    elseif direction == "east" then
        return code == PF.West_East_Corridor or
               code == PF.North_East_Corridor or
               code == PF.South_East_Corridor or
               code == PF.East_T_Corridor or
               code == PF.North_T_Corridor or
               code == PF.South_T_Corridor or
               code == PF.Normal_X_Corridor or
               code == PF.East_DeadEnd
               
    elseif direction == "west" then
        return code == PF.West_East_Corridor or
               code == PF.North_West_Corridor or
               code == PF.South_West_Corridor or
               code == PF.West_T_Corridor or
               code == PF.North_T_Corridor or
               code == PF.South_T_Corridor or
               code == PF.Normal_X_Corridor or
               code == PF.West_DeadEnd
    end
    
    return false
end

function Enemy:getValidDirections()
    local tile = self.maze.tiles[self.y][self.x]
    local valid = {}
    
    if Enemy.canMoveInDirection(tile, "north") then
        table.insert(valid, "north")
    end
    if Enemy.canMoveInDirection(tile, "south") then
        table.insert(valid, "south")
    end
    if Enemy.canMoveInDirection(tile, "east") then
        table.insert(valid, "east")
    end
    if Enemy.canMoveInDirection(tile, "west") then
        table.insert(valid, "west")
    end
    
    return valid
end

function Enemy:chooseNewDirection()
    local validDirections = self:getValidDirections()
    
    if #validDirections > 0 then
        self.direction = validDirections[math.random(1, #validDirections)]
    else
        self.direction = nil
    end
end

function Enemy:canContinue()
    if not self.direction then return false end
    
    local nextX, nextY = self.x, self.y
    
    if self.direction == "north" then
        nextY = nextY - 1
    elseif self.direction == "south" then
        nextY = nextY + 1
    elseif self.direction == "east" then
        nextX = nextX + 1
    elseif self.direction == "west" then
        nextX = nextX - 1
    end
    
    if nextX < 1 or nextX > self.maze.width or nextY < 1 or nextY > self.maze.height then
        return false
    end
    
    local nextTile = self.maze.tiles[nextY][nextX]
    local oppositeDir = {north = "south", south = "north", east = "west", west = "east"}
    
    return Enemy.canMoveInDirection(nextTile, oppositeDir[self.direction])
end

function Enemy:update(dt)
    -- if dead, stop movement and stick to dead frame
    if self.isDead then
        -- no longer moves or chooses directions
        self.direction = nil
        self.animFrame = 1
        if self.damageCooldown and self.damageCooldown > 0 then
            self.damageCooldown = self.damageCooldown - dt
            if self.damageCooldown < 0 then self.damageCooldown = 0 end
        end
        return
    end

    if not self.direction then
        self:chooseNewDirection()
        return
    end
    
    local movement = self.speed * dt
    local ts = Renderer.tileSize
    local targetPixelX = (self.x - 1) * ts + ts / 2
    local targetPixelY = (self.y - 1) * ts + ts / 2
    
    local dx = targetPixelX - self.pixelX
    local dy = targetPixelY - self.pixelY
    local distToCenter = math.sqrt(dx*dx + dy*dy)
    
    if distToCenter < 2 then
        self.pixelX = targetPixelX
        self.pixelY = targetPixelY
        
        if self:canContinue() then
            if self.direction == "north" then
                self.y = self.y - 1
            elseif self.direction == "south" then
                self.y = self.y + 1
            elseif self.direction == "east" then
                self.x = self.x + 1
            elseif self.direction == "west" then
                self.x = self.x - 1
            end
        else
            local reverseDir = {north = "south", south = "north", east = "west", west = "east"}
            self.direction = reverseDir[self.direction]
            
            if not self:canContinue() then
                self:chooseNewDirection()
            end
        end
    else
        if self.direction == "north" then
            self.pixelY = self.pixelY - movement
        elseif self.direction == "south" then
            self.pixelY = self.pixelY + movement
        elseif self.direction == "east" then
            self.pixelX = self.pixelX + movement
        elseif self.direction == "west" then
            self.pixelX = self.pixelX - movement
        end
    end

    -- no separate facing; sprite row is chosen from actual move direction

    -- wing flap animation (only when alive)
    if not self.isDead then
        self.animTimer = self.animTimer + dt
        if self.animTimer >= self.animSpeed then
            self.animTimer = self.animTimer - self.animSpeed
            self.animFrame = self.animFrame + 1
            if self.animFrame > 3 then self.animFrame = 1 end
        end
    else
        -- dead: stick to frame 1 (col 1)
        self.animFrame = 1
    end

    -- reduce per-enemy damage cooldown
    if self.damageCooldown and self.damageCooldown > 0 then
        self.damageCooldown = self.damageCooldown - dt
        if self.damageCooldown < 0 then self.damageCooldown = 0 end
    end
end

function Enemy:draw()
    -- fallback to simple shape if no sprite
    if self.spriteSheet and Renderer.enemy and Renderer.enemy.quads then
        -- mapping: north (up) -> row 3, east (right) -> row 2,
        -- south (down) -> row 1, west (left) -> row 4
        local rowMap = { north = 3, east = 2, south = 1, west = 4 }
        local row = rowMap[self.direction] or 2
        local quad = nil
        if self.isDead then
            quad = Renderer.enemy.quads[row][1] -- first column = dead
        else
            -- eeverse animation order: animFrame 1..3 -> cols 4..2
            local col = 5 - self.animFrame
            quad = Renderer.enemy.quads[row][col]
        end

        love.graphics.setColor(1, 1, 1)
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
    else
        love.graphics.setColor(1, 0, 0)
        love.graphics.circle("fill", self.pixelX, self.pixelY, self.radius)
        love.graphics.setColor(1, 1, 1)
    end
end

return Enemy
