local TileMapper = require("src.tile_mapper")

local Enemy = {}
Enemy.__index = Enemy

function Enemy.new(x, y, maze)
    local self = setmetatable({}, Enemy)
    
    self.x = x
    self.y = y
    self.pixelX = (x - 1) * 64 + 32
    self.pixelY = (y - 1) * 64 + 32
    self.maze = maze
    self.direction = nil
    self.speed = 80
    self.radius = 12
    
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
    if not self.direction then
        self:chooseNewDirection()
        return
    end
    
    local movement = self.speed * dt
    local targetPixelX = (self.x - 1) * 64 + 32
    local targetPixelY = (self.y - 1) * 64 + 32
    
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
end

function Enemy:draw()
    love.graphics.setColor(1, 0, 0)
    love.graphics.circle("fill", self.pixelX, self.pixelY, self.radius)
    
    love.graphics.setColor(1, 1, 1, 0.8)
    if self.direction == "north" then
        love.graphics.polygon("fill", self.pixelX, self.pixelY - 8, 
                                      self.pixelX - 4, self.pixelY - 4, 
                                      self.pixelX + 4, self.pixelY - 4)
    elseif self.direction == "south" then
        love.graphics.polygon("fill", self.pixelX, self.pixelY + 8, 
                                      self.pixelX - 4, self.pixelY + 4, 
                                      self.pixelX + 4, self.pixelY + 4)
    elseif self.direction == "east" then
        love.graphics.polygon("fill", self.pixelX + 8, self.pixelY, 
                                      self.pixelX + 4, self.pixelY - 4, 
                                      self.pixelX + 4, self.pixelY + 4)
    elseif self.direction == "west" then
        love.graphics.polygon("fill", self.pixelX - 8, self.pixelY, 
                                      self.pixelX - 4, self.pixelY - 4, 
                                      self.pixelX - 4, self.pixelY + 4)
    end
    
    love.graphics.setColor(1, 1, 1)
end

return Enemy
