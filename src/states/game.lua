local MazeGenerator = require("src.maze_generator")
local Renderer = require("src.renderer")
local Bat = require("src.enemies.bat")
local Seeker = nil
pcall(function() Seeker = require("src.enemies.seeker") end)
local Player = require("src.player")

local Game = {}

-- Helper to set volume safely
local function setSrcVolume(label, src, v)
    if not src then return end
    pcall(function() src:setVolume(v) end)
end

function Game.enter()
    -- Reset game variables
    game.maze = nil
    game.enemies = {}
    game.player = nil
    game.finishTileX = nil
    game.finishTileY = nil
    game.currentLevel = 1
    game.timeScale = 1.0
    game.damageFlash = 0
    game.transitioning = false
    game.deathSeq = { active = false, phase = nil, timer = 0, fade = 0, textAlpha = 0 }
    
    -- Fix: Initialize Camera State for Overview
    game.savedCamera = { x = 0, y = 0, scale = 1 }
    game.showingMazeOverview = false
    Renderer.showingOverview = false
    
    -- Death Menu Variables
    Game.deathSelection = 1
    Game.deathOptions = {"RESTART", "MAIN MENU", "QUIT"}
    
    -- Particles
    local particleImg = love.image.newImageData(2, 2)
    particleImg:mapPixel(function() return 255, 255, 255, 255 end)
    local pTexture = love.graphics.newImage(particleImg)
    game.hitParticles = love.graphics.newParticleSystem(pTexture, 200)
    game.hitParticles:setParticleLifetime(0.2, 0.5)
    game.hitParticles:setSpeed(100, 250)
    game.hitParticles:setLinearAcceleration(0, 200, 0, 500)
    game.hitParticles:setSpread(math.pi * 2)
    game.hitParticles:setSizes(2, 1, 0)
    game.hitParticles:setColors(1, 0.6, 0.1, 1, 0.6, 0.6, 0.6, 0.8, 0.1, 0.1, 0.1, 0)

    -- Generate first maze
    Game.generateNewMaze()
    
    -- Setup Camera
    if game.player then
        local w, h = love.graphics.getDimensions()
        Renderer.camera.scale = 0.8  
        Renderer.camera.x = game.player.pixelX - w / (2 * Renderer.camera.scale)
        Renderer.camera.y = game.player.pixelY - h / (2 * Renderer.camera.scale)
    end
end

function Game.generateNewMaze()
    game.seed = math.floor(love.timer.getTime() * 1000)
    print("\n--- Generating new maze ---")

    game.maze = MazeGenerator.generate(game.mazeWidth, game.mazeHeight, game.seed)

    local TileMapper = require("src.tile_mapper")
    local PF = TileMapper.PrefabCodes
    local edgeCrossroads = {}
    local edgeThreshold = 3 

    for y = 1, game.maze.height do
        for x = 1, game.maze.width do
            local tile = game.maze.tiles[y][x]
            if tile.code == PF.Normal_X_Corridor or tile.code == PF.Special_X_Corridor then
                local nearEdge = (x <= edgeThreshold or x > game.maze.width - edgeThreshold or
                                 y <= edgeThreshold or y > game.maze.height - edgeThreshold)
                if nearEdge then
                    table.insert(edgeCrossroads, {x = x, y = y})
                end
            end
        end
    end

    local playerSpawnX, playerSpawnY = nil, nil
    if #edgeCrossroads > 0 then
        local spawnTile = edgeCrossroads[math.random(1, #edgeCrossroads)]
        playerSpawnX = spawnTile.x
        playerSpawnY = spawnTile.y
    else
        for y = 1, game.maze.height do
            for x = 1, game.maze.width do
                local tile = game.maze.tiles[y][x]
                if tile.tileType ~= "empty" then
                    playerSpawnX, playerSpawnY = x, y
                    break
                end
            end
            if playerSpawnX then break end
        end
    end

    if playerSpawnX then
        game.player = Player.new(playerSpawnX, playerSpawnY, game.maze)
        game.maze.tiles[playerSpawnY][playerSpawnX].isSpawn = true

        local spawnOnLeft = playerSpawnX <= edgeThreshold
        local spawnOnRight = playerSpawnX > game.maze.width - edgeThreshold
        local spawnOnTop = playerSpawnY <= edgeThreshold
        local spawnOnBottom = playerSpawnY > game.maze.height - edgeThreshold

        local targetX, targetY
        if spawnOnLeft then targetX, targetY = game.maze.width, game.maze.height / 2
        elseif spawnOnRight then targetX, targetY = 1, game.maze.height / 2
        elseif spawnOnTop then targetX, targetY = game.maze.width / 2, game.maze.height
        elseif spawnOnBottom then targetX, targetY = game.maze.width / 2, 1
        else targetX, targetY = game.maze.width, game.maze.height / 2 end

        local allCrossroads = {}
        for y = 1, game.maze.height do
            for x = 1, game.maze.width do
                local tile = game.maze.tiles[y][x]
                if (tile.code == PF.Normal_X_Corridor or tile.code == PF.Special_X_Corridor) and
                   not (x == playerSpawnX and y == playerSpawnY) then
                    local distanceToTarget = math.sqrt((x - targetX)^2 + (y - targetY)^2)
                    table.insert(allCrossroads, {x = x, y = y, distance = distanceToTarget})
                end
            end
        end
        
        if #allCrossroads > 0 then
            table.sort(allCrossroads, function(a, b) return a.distance < b.distance end)
            local finishTile = allCrossroads[1]
            game.finishTileX = finishTile.x
            game.finishTileY = finishTile.y
            game.maze.tiles[finishTile.y][finishTile.x].isFinish = true
        end
    end

    game.enemies = {}
    local validSpawnTiles = {}
    for y = 1, game.maze.height do
        for x = 1, game.maze.width do
            local tile = game.maze.tiles[y][x]
            if tile.tileType ~= "empty" then
                table.insert(validSpawnTiles, {x = x, y = y})
            end
        end
    end

    local minSpawnDistance = 3 
    local filteredSpawnTiles = {}
    for _, t in ipairs(validSpawnTiles) do
        local tileObj = game.maze.tiles[t.y][t.x]
        if not (tileObj.isSpawn or tileObj.isFinish) then
            if playerSpawnX and playerSpawnY then
                local dx = t.x - playerSpawnX
                local dy = t.y - playerSpawnY
                local dist = math.sqrt(dx*dx + dy*dy)
                if dist > minSpawnDistance then
                    table.insert(filteredSpawnTiles, t)
                end
            else
                table.insert(filteredSpawnTiles, t)
            end
        end
    end

    local baseEnemies = 4
    local perLevelIncrease = 3
    local desired = baseEnemies + math.floor(((game.currentLevel or 1) - 1) * perLevelIncrease)
    local numEnemies = math.min(desired, #filteredSpawnTiles)

    for i = 1, math.min(numEnemies, #filteredSpawnTiles) do
        local spawnTile = filteredSpawnTiles[math.random(1, #filteredSpawnTiles)]
        local isSeeker = Seeker and (math.random() < 0.20) 
        local enemy = nil
        if isSeeker then
            enemy = Seeker.new(spawnTile.x, spawnTile.y, game.maze)
        else
            enemy = Bat.new(spawnTile.x, spawnTile.y, game.maze)
        end
        table.insert(game.enemies, enemy)
    end
end

function Game.update(dt)
    local timeScale = game.timeScale or 1.0
    local scaledDt = dt * timeScale

    if game.hitParticles then game.hitParticles:update(scaledDt) end

    if game.player then
        game.player:update(scaledDt)

        if game.finishTileX and game.finishTileY and not game.transitioning then
            local finishSubX = (game.finishTileX - 1) * 3 + 2 
            local finishSubY = (game.finishTileY - 1) * 3 + 2

            if game.player.gridX == finishSubX and game.player.gridY == finishSubY then
                game.transitioning = true
                game.transitionState = "fade_out"
                game.transitionAlpha = 0
                game.timeScale = 0
            end
        end

        if game.transitioning then
            if game.transitionState == "fade_out" then
                game.transitionAlpha = game.transitionAlpha + (dt * 2.0)
                if game.transitionAlpha >= 1 then
                    game.transitionAlpha = 1
                    game.currentLevel = game.currentLevel + 1
                    Game.generateNewMaze()
                    game.transitionState = "fade_in"
                end
            elseif game.transitionState == "fade_in" then
                game.transitionAlpha = game.transitionAlpha - (dt * 2.0)
                if game.transitionAlpha <= 0 then
                    game.transitionAlpha = 0
                    game.transitioning = false
                    game.transitionState = "none"
                    game.timeScale = 1.0
                end
            end
        end

        if game.debug and love.keyboard.isDown("backspace") then
            if not game.showingMazeOverview then
                -- FIX: Initialize if somehow missing, though enter() should handle it
                if not game.savedCamera then game.savedCamera = {x=0, y=0, scale=1} end
                
                game.savedCamera.x = Renderer.camera.x
                game.savedCamera.y = Renderer.camera.y
                game.savedCamera.scale = Renderer.camera.scale
                game.showingMazeOverview = true
                Renderer.showingOverview = true

                local screenWidth, screenHeight = love.graphics.getDimensions()
                local mazePixelWidth = game.maze.width * Renderer.tileSize
                local mazePixelHeight = game.maze.height * Renderer.tileSize
                local scaleX = screenWidth / mazePixelWidth
                local scaleY = screenHeight / mazePixelHeight
                Renderer.camera.scale = math.min(scaleX, scaleY) * 0.95
                local scaledScreenWidth = screenWidth / Renderer.camera.scale
                local scaledScreenHeight = screenHeight / Renderer.camera.scale
                Renderer.camera.x = -(scaledScreenWidth - mazePixelWidth) / 2
                Renderer.camera.y = -(scaledScreenHeight - mazePixelHeight) / 2
            end
        else
            if game.showingMazeOverview then
                if game.savedCamera then
                    Renderer.camera.x = game.savedCamera.x
                    Renderer.camera.y = game.savedCamera.y
                    Renderer.camera.scale = game.savedCamera.scale
                end
                game.showingMazeOverview = false
                Renderer.showingOverview = false
            end
        end
    end

    game.pathfinderBudget = 4
    game.pathfinderUsed = 0
    for _, enemy in ipairs(game.enemies) do
        enemy:update(scaledDt)
    end

    if game.player then
        for _, enemy in ipairs(game.enemies) do
            if not enemy.isDead and not game.player.isDead and not game.player.isTakingDamage then
                local dx = enemy.pixelX - game.player.pixelX
                local dy = enemy.pixelY - game.player.pixelY
                local dist = math.sqrt(dx*dx + dy*dy)
                local hitThreshold = (enemy.radius or 12) + 12
                if dist <= hitThreshold and (not enemy.damageCooldown or enemy.damageCooldown <= 0) then
                    game.player:takeDamage(20)
                    game.damageFlash = 0.22
                    if game.sounds.damage and #game.sounds.damage > 0 then
                        local idx = math.random(1, #game.sounds.damage)
                        local src = game.sounds.damage[idx]
                        if src then src:stop(); src:play() end
                    end
                    enemy.damageCooldown = 0.48
                end
            end
        end
    end

    if game.damageFlash and game.damageFlash > 0 then
        game.damageFlash = game.damageFlash - dt
        if game.damageFlash < 0 then game.damageFlash = 0 end
    end

    -- DEATH SEQUENCE LOGIC
    if game.player and game.player.isDead then
        local ds = game.deathSeq
        if not ds.active then
            ds.active = true
            ds.phase = "slowdown"
            ds.timer = 0
            
            -- Save High Score
            local finalScore = math.max(0, game.currentLevel - 1)
            if finalScore > game.highScore then
                game.highScore = finalScore
                love.filesystem.write("highscore.txt", tostring(finalScore))
            end
            
            ds.originalTimeScale = game.timeScale or 1.0
            ds.targetTimeScale = 0.12
            ds.originalCameraScale = Renderer.camera.scale
            ds.targetCameraScale = (Renderer.camera.scale or 1.0) * 1.9
            ds.fade = 0
            ds.textAlpha = 0
            ds.fadeDuration = 1.0
            ds.textFadeDuration = 2.0
            ds.introFadeIn = 0.5
            if game.sounds.death_intro then
                local src = game.sounds.death_intro
                local ok, dur = pcall(function() return src:getDuration() end)
                ds.introDuration = (ok and dur) or 2.0
                setSrcVolume("death_intro", src, 0)
                src:stop()
                src:play()
                ds.introPlaying = true
            else
                ds.introDuration = 0
                ds.introPlaying = false
            end
        else
            if ds.phase == "slowdown" then
                ds.timer = ds.timer + dt
                local t = math.min(1, ds.timer / 1.2)
                game.timeScale = ds.originalTimeScale + (ds.targetTimeScale - ds.originalTimeScale) * t
                Renderer.camera.scale = ds.originalCameraScale + (ds.targetCameraScale - ds.originalCameraScale) * t

                if ds.introPlaying and game.sounds.death_intro then
                    local src = game.sounds.death_intro
                    if ds.timer <= ds.introFadeIn then
                        local v = math.max(0, math.min(1, ds.timer / ds.introFadeIn))
                        setSrcVolume("death_intro", src, v)
                    end
                end

                local introDone = true
                if ds.introPlaying and game.sounds.death_intro then
                    local ok, playing = pcall(function() return game.sounds.death_intro:isPlaying() end)
                    if ok then introDone = not playing else introDone = ds.timer >= (ds.introDuration or 0) end
                end

                if game.player.deathAnimationDone and introDone then
                    ds.phase = "fade_to_black"
                    ds.timer = 0
                    if ds.introPlaying and game.sounds.death_intro then
                        pcall(function() game.sounds.death_intro:stop() end)
                        ds.introPlaying = false
                    end
                    if game.sounds.death_bells then
                        local bell = game.sounds.death_bells
                        pcall(function()
                            bell:stop()
                            bell:setLooping(false)
                            setSrcVolume("death_bells", bell, 1)
                            bell:play()
                        end)
                    end
                end

            elseif ds.phase == "fade_to_black" then
                ds.timer = ds.timer + dt
                ds.fade = math.min(1, ds.timer / ds.fadeDuration)
                game.timeScale = 0.05
                if ds.fade >= 1 then
                    ds.phase = "text_fade"
                    ds.timer = 0
                end
            elseif ds.phase == "text_fade" then
                ds.timer = ds.timer + dt
                ds.textAlpha = math.min(1, ds.timer / ds.textFadeDuration)
                ds.fade = 1
                game.timeScale = 0.0
            end
        end
    end

    if not game.showingMazeOverview then
        if love.keyboard.isDown("=") or love.keyboard.isDown("+") then
            Renderer.camera.scale = Renderer.camera.scale * (1 + dt)
        end
        if love.keyboard.isDown("-") then
            Renderer.camera.scale = Renderer.camera.scale * (1 - dt)
            if Renderer.camera.scale < 0.1 then Renderer.camera.scale = 0.1 end
        end
    end

    -- Ambience logic
    if game.sounds.ambient and #game.sounds.ambient > 0 then
        local now = love.timer.getTime()
        if not game.nextAmbientTime then game.nextAmbientTime = now + 10 end
        if now >= game.nextAmbientTime then
            local idx = math.random(1, #game.sounds.ambient)
            local src = game.sounds.ambient[idx]
            if src then
                pcall(function()
                    src:stop()
                    setSrcVolume("amb", src, 0.18)
                    src:play()
                end)
            end
            game.nextAmbientTime = now + 10 + math.random() * 20
        end
    end

    -- Door Audio Proximity
    if game.sounds.door and game.finishTileX and game.finishTileY and game.player then
        local ts = Renderer.tileSize
        local fx = (game.finishTileX - 1) * ts + ts / 2
        local fy = (game.finishTileY - 1) * ts + ts / 2
        local dx = fx - game.player.pixelX
        local dy = fy - game.player.pixelY
        local dist = math.sqrt(dx*dx + dy*dy)
        local triggerRadius = 270
        local src = game.sounds.door
        if dist <= triggerRadius then
            local vol = 0.45 * (1 - (dist / triggerRadius))
            if vol < 0.01 then vol = 0.01 end
            pcall(function() setSrcVolume("door", src, vol) end)
            local ok, playing = pcall(function() return src:isPlaying() end)
            if not (ok and playing) then pcall(function() src:stop(); src:play() end) end
        else
            pcall(function() setSrcVolume("door", src, 0); src:stop() end)
        end
    end
end

function Game.draw()
    if game.player and not game.showingMazeOverview then
        local w, h = love.graphics.getDimensions()
        Renderer.camera.x = game.player.pixelX - (w / (2 * Renderer.camera.scale))
        Renderer.camera.y = game.player.pixelY - (h / (2 * Renderer.camera.scale))
    end

    Renderer.drawMaze(game.maze, game.enemies, game.player, game.hitParticles)

    if game.transitioning and game.transitionAlpha > 0 then
        love.graphics.setColor(0, 0, 0, game.transitionAlpha)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setColor(1, 1, 1)
    end

    -- Darkness Shader
    if game.player and not game.showingMazeOverview then
        local w, h = love.graphics.getDimensions()
        local px, py = w/2, h/2
        
        if game.darknessShader then
            local inner = (game.player.darkness and game.player.darkness.innerRadius or 200) * Renderer.camera.scale
            local outer = (game.player.darkness and game.player.darkness.outerRadius or 400) * Renderer.camera.scale
            local exponent = (game.player.darkness and game.player.darkness.exponent) or 1.6
            local alpha = (game.player.darkness and game.player.darkness.alpha) or 0.85

            game.darknessShader:send("cx", px)
            game.darknessShader:send("cy", py)
            game.darknessShader:send("innerRadius", inner)
            game.darknessShader:send("outerRadius", outer)
            game.darknessShader:send("exponent", exponent)

            love.graphics.setShader(game.darknessShader)
            love.graphics.setColor(0, 0, 0, alpha)
            love.graphics.rectangle("fill", 0, 0, w, h)
            love.graphics.setShader()
            love.graphics.setColor(1, 1, 1)
        end
    end

    -- HUD: Health Bar
    if game.player then
        local sw, sh = love.graphics.getDimensions()
        local barW = sw * 0.75
        local barH = 28
        local barX = (sw - barW) / 2
        local barY = sh - barH - 12

        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", barX, barY, barW, barH, 6, 6)

        local healthPct = math.max(0, math.min(1, (game.player.health or 0) / 100))
        local fillW = barW * healthPct
        if healthPct > 0.6 then love.graphics.setColor(0.2, 0.8, 0.2)
        elseif healthPct > 0.3 then love.graphics.setColor(0.95, 0.8, 0.2)
        else love.graphics.setColor(0.9, 0.25, 0.25) end
        love.graphics.rectangle("fill", barX + 4, barY + 4, math.max(0, fillW - 8), barH - 8, 4, 4)

        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.rectangle("line", barX, barY, barW, barH, 6, 6)
        love.graphics.setColor(1, 1, 1)
    end

    -- HUD: Damage Flash
    if game.damageFlash and game.damageFlash > 0 then
        local alpha = (game.damageFlash / 0.22) * 0.45
        love.graphics.setColor(1, 0, 0, alpha)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setColor(1, 1, 1)
    end

    -- HUD: Level Counter
    local passed = math.max(0, (game.currentLevel or 1) - 1)
    local f = game.fonts.level or love.graphics.getFont()
    love.graphics.setFont(f)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Levels Passed: " .. passed, 8, 8)
    love.graphics.setColor(1, 1, 1)

    -- Death UI (GAME OVER MENU)
    if game.deathSeq and game.deathSeq.active then
        local ds = game.deathSeq
        if ds.fade > 0 then
            love.graphics.setColor(0, 0, 0, math.min(1, ds.fade))
            love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
            love.graphics.setColor(1, 1, 1)
        end

        if ds.phase == "text_fade" then
            local w, h = love.graphics.getDimensions()
            
            -- Main Title (Moved UP to 30%)
            love.graphics.setFont(game.fonts.deathLarge)
            love.graphics.setColor(1, 0, 0, ds.textAlpha)
            -- Restored full string:
            love.graphics.printf("DEATH IS CALLING...\nwill you answer?", 0, h * 0.30, w, "center")
            love.graphics.setColor(1, 1, 1)

            -- Interactive Menu (Moved DOWN to 60%)
            if ds.textAlpha >= 1 then
                love.graphics.setFont(game.fonts.deathSmall)
                
                for i, opt in ipairs(Game.deathOptions) do
                    if i == Game.deathSelection then
                        love.graphics.setColor(1, 1, 1, 1) -- White + Brackets
                        love.graphics.printf("> " .. opt .. " <", 0, h * 0.60 + (i * 40), w, "center")
                    else
                        love.graphics.setColor(0.5, 0.5, 0.5, 1) -- Gray
                        love.graphics.printf(opt, 0, h * 0.60 + (i * 40), w, "center")
                    end
                end
                
                love.graphics.setColor(1, 1, 1)
            end
        end
    end

    -- Debug Info
    if game.debug then
        love.graphics.setFont(game.fonts.default)
        love.graphics.setColor(0, 0, 0, 0.9)
        love.graphics.rectangle("fill", 10, 10, 480, 160)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("MazeKnight Debug", 20, 20)
        love.graphics.print("Level: " .. game.currentLevel, 20, 40)
        love.graphics.setColor(0, 1, 0)
        love.graphics.print("FPS: " .. love.timer.getFPS(), 20, 130)
        love.graphics.setColor(1, 1, 1)
    end
end

function Game.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "f3" then
        game.debug = not game.debug
    elseif key == "n" then
        Game.generateNewMaze()
    elseif key == "f" then
        local w, h = love.graphics.getDimensions()
        Renderer.fitMazeToScreen(game.maze, w, h)
    elseif key == "r" then
        game.maze = MazeGenerator.generate(game.mazeWidth, game.mazeHeight, game.seed)
        Game.generateNewMaze() 
    end

    -- Handle Menu Input only if dead and menu is visible
    if game.deathSeq and game.deathSeq.active and game.deathSeq.phase == "text_fade" and game.deathSeq.textAlpha >= 1 then
        if key == "up" or key == "w" then
            Game.deathSelection = Game.deathSelection - 1
            if Game.deathSelection < 1 then Game.deathSelection = #Game.deathOptions end
        elseif key == "down" or key == "s" then
            Game.deathSelection = Game.deathSelection + 1
            if Game.deathSelection > #Game.deathOptions then Game.deathSelection = 1 end
        elseif key == "return" or key == "space" then
            if game.sounds.death_bells then game.sounds.death_bells:stop() end
            if game.sounds.death_intro then game.sounds.death_intro:stop() end
            
            if Game.deathSelection == 1 then
                -- Restart
                Game.enter()
            elseif Game.deathSelection == 2 then
                -- Main Menu
                State.switch("menu")
            elseif Game.deathSelection == 3 then
                -- Quit
                love.event.quit()
            end
        end
    end
end

return Game