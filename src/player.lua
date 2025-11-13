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
    
    -- Use sub-grid coordinates (each tile is 3x3 sub-cells)
    -- Start at (1,1) within the tile, which is the center and always walkable
    self.gridX = (x - 1) * 3 + 2  -- Convert tile coords to sub-grid coords, then add 1 for center
    self.gridY = (y - 1) * 3 + 2  -- This puts player at (1,1) within the 3x3 tile grid
    self.maze = maze
    self.cellSize = 32  -- Each sub-cell is 32x32 pixels (96/3)
    
    self.pixelX = (self.gridX - 1) * self.cellSize + self.cellSize / 2
    self.pixelY = (self.gridY - 1) * self.cellSize + self.cellSize / 2
    
    self.targetGridX = self.gridX
    self.targetGridY = self.gridY
    self.isMoving = false
    self.moveSpeed = 8  -- Cells per second (faster since cells are smaller)
    self.direction = "right"
    
    self.spritesheet = nil
    self.frameWidth = 64  -- knight.png is 512x512, 8x8 grid = 64x64 per frame
    self.frameHeight = 64
    self.spriteScale = 1.5  -- Scale to make player more visible (64 * 0.75 = 48 pixels)
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
    -- Darkness (radial gradient) presets and shader
    self.darknessPresets = {
        { name = "Subtle", innerRadius = 160, outerRadius = 420, exponent = 1.4, alpha = 0.85 },
        { name = "Night",  innerRadius = 120, outerRadius = 320, exponent = 2.2, alpha = 0.98 },
        { name = "Tunnel", innerRadius =  80, outerRadius = 240, exponent = 3.0, alpha = 1.00 }
    }
    self.currentDarknessPreset = 2 -- default to "Night"
    self.darkness = {}
    local function applyPreset(idx)
        local p = self.darknessPresets[idx]
        if not p then return end
        self.darkness.innerRadius = p.innerRadius
        self.darkness.outerRadius = p.outerRadius
        self.darkness.exponent = p.exponent
        self.darkness.alpha = p.alpha
    end
    applyPreset(self.currentDarknessPreset)

    -- key debounce for cycling presets (press 'f' to cycle)
    self._fWasDown = false
    
    return self
end

function Player:loadSprite()
    local path = "assets/player/knight.png"
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

function Player:loadDarknessShader()
    -- Shader drawing is handled centrally in main.lua now.
    -- Kept for API compatibility if code expects this method to exist.
    return nil
end

function Player:applyDarknessPreset(idx)
    if not self.darknessPresets then return end
    idx = idx or self.currentDarknessPreset or 1
    local p = self.darknessPresets[idx]
    if not p then return end
    self.currentDarknessPreset = idx
    self.darkness.innerRadius = p.innerRadius
    self.darkness.outerRadius = p.outerRadius
    self.darkness.exponent = p.exponent
    self.darkness.alpha = p.alpha
    print(string.format("Darkness preset applied: %s", p.name))
end

function Player:cycleDarknessPreset()
    if not self.darknessPresets then return end
    local nextIdx = (self.currentDarknessPreset % #self.darknessPresets) + 1
    self:applyDarknessPreset(nextIdx)
end

function Player:update(dt)
    -- Handle cycling darkness presets with 'f' (debounced)
    local fDown = love.keyboard.isDown("f")
    if fDown and not self._fWasDown then
        self._fWasDown = true
        self:cycleDarknessPreset()
    elseif not fDown and self._fWasDown then
        self._fWasDown = false
    end

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
    -- Convert sub-grid coordinates to tile coordinates and sub-cell position
    local tileX = math.floor((gridX - 1) / 3) + 1
    local tileY = math.floor((gridY - 1) / 3) + 1
    local subX = ((gridX - 1) % 3) + 1
    local subY = ((gridY - 1) % 3) + 1
    
    local currentTileX = math.floor((self.gridX - 1) / 3) + 1
    local currentTileY = math.floor((self.gridY - 1) / 3) + 1
    local currentSubX = ((self.gridX - 1) % 3) + 1
    local currentSubY = ((self.gridY - 1) % 3) + 1
    
    -- Check if within maze bounds
    if tileX < 1 or tileX > self.maze.width or tileY < 1 or tileY > self.maze.height then
        return false
    end
    
    local targetTile = self.maze.tiles[tileY][tileX]
    if not targetTile then
        return false
    end
    
    local direction = self:getDirectionTo(gridX, gridY)
    
    -- If moving within the same tile, check collision grid
    if tileX == currentTileX and tileY == currentTileY then
        return targetTile:isWalkable(subX, subY)
    end
    
    -- If moving to a different tile, check if we can exit current and enter target
    local currentTile = self.maze.tiles[currentTileY][currentTileX]
    
    -- Check if we can exit from current sub-cell
    if not currentTile:canExitFrom(currentSubX, currentSubY, direction) then
        return false
    end
    
    -- Check if target sub-cell is walkable
    if not targetTile:isWalkable(subX, subY) then
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

function Player:updateMovement(dt)
    local targetPixelX = (self.targetGridX - 1) * self.cellSize + self.cellSize / 2
    local targetPixelY = (self.targetGridY - 1) * self.cellSize + self.cellSize / 2
    
    local moveDistance = self.moveSpeed * self.cellSize * dt
    
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

    -- Draw a radial darkness overlay centered on the player (skip during overview)
    if not Renderer.showingOverview then
        local w = love.graphics.getWidth()
        local h = love.graphics.getHeight()

        -- Darkness overlay is handled globally in main.lua; nothing to draw here.
    end
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