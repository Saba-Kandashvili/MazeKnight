-- Player Module
-- Handles player character with grid-based movement and animations

local TileMapper = require("src.tile_mapper")
local Renderer = require("src.renderer")

local Player = {}
Player.__index = Player

-- Animation configuration for knight.png spritesheet (1-indexed for Lua)
local ANIMATIONS = {
    idle = { row = 0, frames = {1, 2, 3, 4, 5}, frameCount = 5, speed = 0.1 },
    run = { row = 1, frames = {1, 2, 3, 4, 5, 6, 7, 8}, frameCount = 8, speed = 0.08 },
    jump = { row = 2, frames = {1, 2, 3}, frameCount = 3, speed = 0.1 },
    fall = { row = 3, frames = {1, 2}, frameCount = 2, speed = 0.15 },
    attack = { row = 4, frames = {1, 2, 3, 4, 5, 6}, frameCount = 6, speed = 0.06 },
    damage = { row = 5, frames = {1}, frameCount = 1, speed = 0.1 },
    dead = { row = 6, frames = {1, 2, 3, 4, 5, 6, 7}, frameCount = 7, speed = 0.12 },
    shield = { row = 7, frames = {1, 2}, frameCount = 2, speed = 0.15 }
}

function Player.new(x, y, maze)
    local self = setmetatable({}, Player)
    
    self.gridX = x
    self.gridY = y
    self.maze = maze
    
    local ts = Renderer.tileSize
    self.pixelX = (x - 1) * ts + ts / 2
    self.pixelY = (y - 1) * ts + ts / 2
    
    self.targetGridX = x
    self.targetGridY = y
    self.isMoving = false
    self.moveSpeed = 4
    self.direction = "right"
    
    self.spritesheet = nil
    self.frameWidth = 64  -- knight.png is 512x512, 8x8 grid = 64x64 per frame
    self.frameHeight = 64
    self.spriteScale = 0.375  -- Scale down to 24 pixels (64 * 0.375 = 24)
    self.currentAnimation = "idle"
    self.currentFrame = 1
    self.animationTimer = 0
    self.animationLoop = true
    
    self.isAttacking = false
    self.attackCooldown = 0
    self.health = 100
    self.isDead = false
    self.isTakingDamage = false
    self.damageTimer = 0
    
    self:loadSprite()
    
    return self
end

function Player:loadSprite()
    local path = "assets/tiles/player/knight.png"
    local success, image = pcall(love.graphics.newImage, path)
    
    if success then
        self.spritesheet = image
        local w, h = image:getWidth(), image:getHeight()
        print(string.format("Loaded player spritesheet: %s (%dx%d pixels)", path, w, h))
        print(string.format("  Frames per row: %d, Total rows: %d", w / self.frameWidth, h / self.frameHeight))
    else
        print("ERROR: Could not load player spritesheet: " .. path)
        print("  Using placeholder circle instead")
    end
end

function Player:update(dt)
    if self.isDead then
        self:updateAnimation(dt)
        return
    end
    
    if self.isTakingDamage then
        self.damageTimer = self.damageTimer - dt
        if self.damageTimer <= 0 then
            self.isTakingDamage = false
            self.currentAnimation = "idle"
        end
        self:updateAnimation(dt)
        return
    end
    
    if self.isAttacking then
        self.attackCooldown = self.attackCooldown - dt
        if self.attackCooldown <= 0 then
            self.isAttacking = false
            self.currentAnimation = "idle"
        end
        self:updateAnimation(dt)
        return
    end
    
    if self.isMoving then
        self:updateMovement(dt)
    else
        self:handleInput()
    end
    
    self:updateAnimation(dt)
end

function Player:handleInput()
    local newGridX = self.gridX
    local newGridY = self.gridY
    local moved = false
    
    if love.keyboard.isDown("space") then
        self:startAttack()
        return
    end
    
    if love.keyboard.isDown("w") or love.keyboard.isDown("up") then
        newGridY = self.gridY - 1
        self.direction = "up"
        moved = true
    elseif love.keyboard.isDown("s") or love.keyboard.isDown("down") then
        newGridY = self.gridY + 1
        self.direction = "down"
        moved = true
    elseif love.keyboard.isDown("a") or love.keyboard.isDown("left") then
        newGridX = self.gridX - 1
        self.direction = "left"
        moved = true
    elseif love.keyboard.isDown("d") or love.keyboard.isDown("right") then
        newGridX = self.gridX + 1
        self.direction = "right"
        moved = true
    end
    
    if moved then
        if self:canMoveTo(newGridX, newGridY) then
            self.targetGridX = newGridX
            self.targetGridY = newGridY
            self.isMoving = true
            self.currentAnimation = "run"
        end
    else
        if self.currentAnimation == "run" then
            self.currentAnimation = "idle"
        end
    end
end

function Player:canMoveTo(gridX, gridY)
    if gridX < 1 or gridX > self.maze.width or gridY < 1 or gridY > self.maze.height then
        return false
    end
    
    local targetTile = self.maze.tiles[gridY][gridX]
    if not targetTile or targetTile.tileType == TileMapper.TileType.EMPTY then
        return false
    end
    
    local currentTile = self.maze.tiles[self.gridY][self.gridX]
    local direction = self:getDirectionTo(gridX, gridY)
    
    if not self:canExitTile(currentTile, direction) then
        print(string.format("Cannot exit tile at (%d,%d) code=%d towards %s", 
            self.gridX, self.gridY, currentTile.code, direction))
        return false
    end
    
    local oppositeDir = self:getOppositeDirection(direction)
    if not self:canEnterTile(targetTile, oppositeDir) then
        print(string.format("Cannot enter tile at (%d,%d) code=%d from %s", 
            gridX, gridY, targetTile.code, oppositeDir))
        return false
    end
    
    return true
end

function Player:getDirectionTo(targetX, targetY)
    if targetX < self.gridX then return "west"
    elseif targetX > self.gridX then return "east"
    elseif targetY < self.gridY then return "north"
    elseif targetY > self.gridY then return "south"
    end
    return nil
end

function Player:getOppositeDirection(direction)
    if direction == "north" then return "south"
    elseif direction == "south" then return "north"
    elseif direction == "east" then return "west"
    elseif direction == "west" then return "east"
    end
    return nil
end

function Player:canExitTile(tile, direction)
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
        return code == PF.East_West_Corridor or
               code == PF.North_East_Corridor or
               code == PF.South_East_Corridor or
               code == PF.North_T_Corridor or
               code == PF.South_T_Corridor or
               code == PF.East_T_Corridor or
               code == PF.Normal_X_Corridor or
               code == PF.East_DeadEnd
               
    elseif direction == "west" then
        return code == PF.East_West_Corridor or
               code == PF.North_West_Corridor or
               code == PF.South_West_Corridor or
               code == PF.North_T_Corridor or
               code == PF.South_T_Corridor or
               code == PF.West_T_Corridor or
               code == PF.Normal_X_Corridor or
               code == PF.West_DeadEnd
    end
    
    return false
end

function Player:canEnterTile(tile, fromDirection)
    return self:canExitTile(tile, fromDirection)
end

function Player:updateMovement(dt)
    local ts = Renderer.tileSize
    local targetPixelX = (self.targetGridX - 1) * ts + ts / 2
    local targetPixelY = (self.targetGridY - 1) * ts + ts / 2
    
    local moveDistance = self.moveSpeed * ts * dt
    
    local dx = targetPixelX - self.pixelX
    local dy = targetPixelY - self.pixelY
    local distance = math.sqrt(dx * dx + dy * dy)
    
    if distance <= moveDistance then
        self.pixelX = targetPixelX
        self.pixelY = targetPixelY
        self.gridX = self.targetGridX
        self.gridY = self.targetGridY
        self.isMoving = false
        self.currentAnimation = "idle"
    else
        local ratio = moveDistance / distance
        self.pixelX = self.pixelX + dx * ratio
        self.pixelY = self.pixelY + dy * ratio
    end
end

function Player:startAttack()
    if not self.isAttacking and not self.isMoving then
        self.isAttacking = true
        self.currentAnimation = "attack"
        self.currentFrame = 1
        self.animationTimer = 0
        self.attackCooldown = ANIMATIONS.attack.speed * #ANIMATIONS.attack.frames
    end
end

function Player:takeDamage(amount)
    if self.isDead then return end
    
    self.health = self.health - amount
    
    if self.health <= 0 then
        self.health = 0
        self.isDead = true
        self.currentAnimation = "dead"
        self.currentFrame = 1
        self.animationTimer = 0
        self.animationLoop = false
        print("Player died!")
    else
        self.isTakingDamage = true
        self.currentAnimation = "damage"
        self.currentFrame = 1
        self.animationTimer = 0
        self.damageTimer = 0.3
    end
end

function Player:updateAnimation(dt)
    local anim = ANIMATIONS[self.currentAnimation]
    if not anim then return end
    
    self.animationTimer = self.animationTimer + dt
    
    if self.animationTimer >= anim.speed then
        self.animationTimer = self.animationTimer - anim.speed
        self.currentFrame = self.currentFrame + 1
        
        if self.currentFrame > #anim.frames then
            if self.animationLoop or self.currentAnimation == "idle" or self.currentAnimation == "run" then
                self.currentFrame = 1
            else
                self.currentFrame = #anim.frames
            end
        end
    end
end

function Player:draw()
    -- Draw placeholder if no sprite loaded
    if not self.spritesheet then
        love.graphics.setColor(0.2, 1.0, 0.3)
        love.graphics.circle("fill", self.pixelX, self.pixelY - 8, 20)
        love.graphics.setColor(1, 1, 1)
        
        if self.direction == "right" then
            love.graphics.circle("fill", self.pixelX + 8, self.pixelY - 8, 4)
        elseif self.direction == "left" then
            love.graphics.circle("fill", self.pixelX - 8, self.pixelY - 8, 4)
        elseif self.direction == "up" then
            love.graphics.circle("fill", self.pixelX, self.pixelY - 16, 4)
        else
            love.graphics.circle("fill", self.pixelX, self.pixelY, 4)
        end
        self:drawHealthBar()
        return
    end
    
    local anim = ANIMATIONS[self.currentAnimation]
    if not anim then 
        self.currentAnimation = "idle"
        anim = ANIMATIONS["idle"]
    end
    
    if self.currentFrame < 1 then 
        self.currentFrame = 1 
    elseif self.currentFrame > anim.frameCount then 
        self.currentFrame = anim.frameCount 
    end
    
    local frameCol = (self.currentFrame - 1)
    local frameRow = anim.row
    
    local quad = love.graphics.newQuad(
        frameCol * self.frameWidth, 
        frameRow * self.frameHeight,
        self.frameWidth, 
        self.frameHeight,
        self.spritesheet:getWidth(), 
        self.spritesheet:getHeight()
    )
    
    local scaleX = self.spriteScale
    if self.direction == "left" then
        scaleX = -self.spriteScale
    end
    
    if self.isTakingDamage then
        love.graphics.setColor(1, 0.3, 0.3, 1)
    else
        love.graphics.setColor(1, 1, 1, 1)
    end
    
    -- Draw centered on position with small upward offset
    love.graphics.draw(
        self.spritesheet,
        quad,
        self.pixelX,
        self.pixelY - 8,
        0,
        scaleX,
        self.spriteScale,
        self.frameWidth / 2,
        self.frameHeight / 2
    )
    
    love.graphics.setColor(1, 1, 1, 1)
    self:drawHealthBar()
end

function Player:drawHealthBar()
    local barWidth = 40
    local barHeight = 4
    local x = self.pixelX - barWidth / 2
    local y = self.pixelY - 24
    
    love.graphics.setColor(0.2, 0.2, 0.2)
    love.graphics.rectangle("fill", x, y, barWidth, barHeight)
    
    local healthPercent = self.health / 100
    if healthPercent > 0.6 then
        love.graphics.setColor(0.2, 0.8, 0.2)
    elseif healthPercent > 0.3 then
        love.graphics.setColor(0.8, 0.8, 0.2)
    else
        love.graphics.setColor(0.8, 0.2, 0.2)
    end
    love.graphics.rectangle("fill", x, y, barWidth * healthPercent, barHeight)
    
    love.graphics.setColor(1, 1, 1)
end

return Player