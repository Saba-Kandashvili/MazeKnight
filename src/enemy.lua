local TileMapper = require("src.tile_mapper")
local Renderer = require("src.renderer")

local Enemy = {}
Enemy.__index = Enemy

function Enemy.new(x, y, maze)
    local self = setmetatable({}, Enemy)
    self.x = x
    self.y = y
    self.maze = maze
    
    local ts = Renderer.tileSize
    self.pixelX = (x - 1) * ts + ts / 2
    self.pixelY = (y - 1) * ts + ts / 2
    
    self.direction = nil
    self.speed = 80
    self.radius = 12
    
    -- Visuals
    self.spriteSheet = nil
    self.frameWidth = 32
    self.frameHeight = 32
    self.spriteScale = 1
    self.animFrame = 1
    self.animTimer = 0
    self.animSpeed = 0.12
    self.isDead = false
    self.damageCooldown = 0
    
    return self
end

function Enemy.canMoveBetween(fromTile, toTile, direction)
    if not fromTile or not toTile then return false end
    
    local code = fromTile.code
    local PF = TileMapper.PrefabCodes
    local canExit = false
    
    if direction == "north" then
        canExit = (code == PF.North_South_Corridor or code == PF.North_East_Corridor or code == PF.North_West_Corridor or
                   code == PF.North_T_Corridor or code == PF.East_T_Corridor or code == PF.West_T_Corridor or
                   code == PF.Normal_X_Corridor or code == PF.North_DeadEnd)
    elseif direction == "south" then
        canExit = (code == PF.North_South_Corridor or code == PF.South_East_Corridor or code == PF.South_West_Corridor or
                   code == PF.South_T_Corridor or code == PF.East_T_Corridor or code == PF.West_T_Corridor or
                   code == PF.Normal_X_Corridor or code == PF.South_DeadEnd)
    elseif direction == "east" then
        canExit = (code == PF.West_East_Corridor or code == PF.North_East_Corridor or code == PF.South_East_Corridor or
                   code == PF.East_T_Corridor or code == PF.North_T_Corridor or code == PF.South_T_Corridor or
                   code == PF.Normal_X_Corridor or code == PF.East_DeadEnd)
    elseif direction == "west" then
        canExit = (code == PF.West_East_Corridor or code == PF.North_West_Corridor or code == PF.South_West_Corridor or
                   code == PF.West_T_Corridor or code == PF.North_T_Corridor or code == PF.South_T_Corridor or
                   code == PF.Normal_X_Corridor or code == PF.West_DeadEnd)
    end
    
    return canExit
end

function Enemy:canGo(direction)
    local nextX, nextY = self.x, self.y
    if direction == "north" then nextY = nextY - 1
    elseif direction == "south" then nextY = nextY + 1
    elseif direction == "east" then nextX = nextX + 1
    elseif direction == "west" then nextX = nextX - 1 end
    
    if nextX < 1 or nextX > self.maze.width or nextY < 1 or nextY > self.maze.height then return false end
    
    local currentTile = self.maze.tiles[self.y][self.x]
    local nextTile = self.maze.tiles[nextY][nextX]
    
    return Enemy.canMoveBetween(currentTile, nextTile, direction)
end

function Enemy:update(dt)
    if self.isDead then return end

    -- Allow subclasses to perform logic before movement (e.g., path updates)
    if self.preMovementUpdate then self:preMovementUpdate(dt) end

    local ts = Renderer.tileSize
    local targetX = (self.x - 1) * ts + ts / 2
    local targetY = (self.y - 1) * ts + ts / 2
    
    local dx = targetX - self.pixelX
    local dy = targetY - self.pixelY
    local dist = math.sqrt(dx*dx + dy*dy)
    
    -- Check if centered
    if dist < (self.speed * dt * 1.5) then
        self.pixelX = targetX
        self.pixelY = targetY
        
        self:decideNextMove()
        
        if self.direction then
            if self:canGo(self.direction) then
                if self.direction == "north" then self.y = self.y - 1
                elseif self.direction == "south" then self.y = self.y + 1
                elseif self.direction == "east" then self.x = self.x + 1
                elseif self.direction == "west" then self.x = self.x - 1
                end
            else
                self.direction = nil
            end
        end
    else
        local angle = math.atan2(dy, dx)
        self.pixelX = self.pixelX + math.cos(angle) * self.speed * dt
        self.pixelY = self.pixelY + math.sin(angle) * self.speed * dt
    end

    self.animTimer = self.animTimer + dt
    if self.animTimer >= self.animSpeed then
        self.animTimer = self.animTimer - self.animSpeed
        self.animFrame = self.animFrame + 1
        if self.animFrame > 3 then self.animFrame = 1 end
    end
    
    if self.damageCooldown > 0 then self.damageCooldown = self.damageCooldown - dt end
end

function Enemy:decideNextMove()
    self.direction = nil
end

function Enemy:findPathToPlayer(maxNodes)
    local player = _G.game and _G.game.player
    if not player then return nil end

    local startX, startY = self.x, self.y
    local goalX, goalY = math.floor((player.gridX - 1) / 3) + 1, math.floor((player.gridY - 1) / 3) + 1

    if startX == goalX and startY == goalY then return {} end

    local dims = { w = self.maze.width, h = self.maze.height }
    local dirs = { "north", "south", "east", "west" }
    
    local queue = { {x=startX, y=startY, path={}} }
    local visited = {}
    visited[startX..","..startY] = true
    
    local iterations = 0
    local head = 1
    
    while head <= #queue do
        iterations = iterations + 1
        if maxNodes and iterations > maxNodes then return nil end
        
        local cur = queue[head]
        head = head + 1
        
        if cur.x == goalX and cur.y == goalY then return cur.path end
        
        local currentTile = self.maze.tiles[cur.y][cur.x]
        
        for _, dir in ipairs(dirs) do
            local nx, ny = cur.x, cur.y
            if dir == "north" then ny = ny - 1
            elseif dir == "south" then ny = ny + 1
            elseif dir == "east" then nx = nx + 1
            elseif dir == "west" then nx = nx - 1 end
            
            if nx >= 1 and nx <= dims.w and ny >= 1 and ny <= dims.h then
                local nextTile = self.maze.tiles[ny][nx]
                local key = nx..","..ny
                
                if not visited[key] and Enemy.canMoveBetween(currentTile, nextTile, dir) then
                    visited[key] = true
                    local newPath = {unpack(cur.path)}
                    table.insert(newPath, dir)
                    table.insert(queue, {x=nx, y=ny, path=newPath})
                end
            end
        end
    end
    return nil
end

function Enemy:draw()
    if self.spriteSheet and Renderer.enemy and Renderer.enemy.quads then
        local rowMap = { north = 3, east = 2, south = 1, west = 4 }
        local row = rowMap[self.direction] or 2
        local quad = nil
        if self.isDead then 
            quad = Renderer.enemy.quads[row][1]
        else 
            local col = 5 - self.animFrame
            quad = Renderer.enemy.quads[row][col] 
        end
        
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(self.spriteSheet, quad, self.pixelX, self.pixelY - 8, 0, self.spriteScale, self.spriteScale, self.frameWidth / 2, self.frameHeight / 2)
    else
        love.graphics.setColor(1, 0, 0)
        love.graphics.circle("fill", self.pixelX, self.pixelY, self.radius)
        love.graphics.setColor(1, 1, 1)
    end
end

return Enemy