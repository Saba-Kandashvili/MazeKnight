-- MazeKnight
-- a procedural maze explorer using my implementation of Wave Function Collapse

local MazeGenerator = require("src.maze_generator")
local Renderer = require("src.renderer")
local Bat = require("src.enemies.bat")
local Seeker = nil
pcall(function() Seeker = require("src.enemies.seeker") end)
local Player = require("src.player")

--writes to stdout (if available) and appends to `game.log` for troubleshooting
local function log(...)
    local parts = {}
    for i = 1, select('#', ...) do
        parts[#parts+1] = tostring(select(i, ...))
    end
    local line = table.concat(parts, " ")
    -- try stdout (may not be visible if running without console)
    pcall(function()
        io.stdout:write(line .. "\n")
        io.stdout:flush()
    end)
    -- append to log file so output is always available
    pcall(function()
        local f = io.open("game.log", "a")
        if f then
            f:write(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. line .. "\n")
            f:close()
        end
    end)
end

-- state
local game = {
    state = "menu", -- "menu", "playing"
    menu = {
        selection = 1,
        options = {"START GAME", "QUIT"}
    },
    maze = nil,
    seed = nil,
    mazeWidth = 15,
    mazeHeight = 15,
    debug = false,
    enemies = {},
    player = nil,
    showingMazeOverview = false,
    savedCamera = { x = 0, y = 0, scale = 1 },
    finishTileX = nil,
    finishTileY = nil,
    -- level transition
    transitioning = false,
    transitionAlpha = 0,
    transitionState = "none",
    transitionSpeed = 2.0,
    currentLevel = 1,
    -- darkness/vision settings
    visionRadius = 200,
    darknessAlpha = 0.85,
    -- particles
    hitParticles = nil
}

-- safe volume-set helper
local function setSrcVolume(label, src, v)
    if not src then return end
    pcall(function() src:setVolume(v) end)
end

function love.load()
    print("=== MazeKnight Starting ===")
    
    if love.system.getOS() == "Windows" then
        io.stdout:setvbuf("no")
    end

    love.graphics.setBackgroundColor(0.05, 0.05, 0.05)
    love.graphics.setDefaultFilter("nearest", "nearest")

    -- === PARTICLE SYSTEM ===
    -- Create a 2x2 white pixel texture programmatically
    local particleImg = love.image.newImageData(2, 2)
    particleImg:mapPixel(function() return 255, 255, 255, 255 end)
    local pTexture = love.graphics.newImage(particleImg)

    game.hitParticles = love.graphics.newParticleSystem(pTexture, 200)
    game.hitParticles:setParticleLifetime(0.2, 0.5) -- Lasts 0.2 to 0.5 seconds
    game.hitParticles:setSpeed(100, 250)            -- Fast explosion
    game.hitParticles:setLinearAcceleration(0, 200, 0, 500) -- Gravity (fall down)
    game.hitParticles:setSpread(math.pi * 2)        -- Explode in circle
    game.hitParticles:setSizes(2, 1, 0)             -- Shrink over time
    -- Color: Starts Orange -> Turns Grey -> Fades to Dark
    game.hitParticles:setColors(
        1, 0.6, 0.1, 1,    -- Bright Orange
        0.6, 0.6, 0.6, 0.8, -- Grey
        0.1, 0.1, 0.1, 0    -- Dark/Invisible
    )
    -- =======================

    -- === FONT LOADING ===
    game.fonts = {}
    local function loadPixelFont(path, size)
        local ok, font = pcall(love.graphics.newFont, path, size)
        if ok then
            font:setFilter("nearest", "nearest")
            return font
        else
            print("Warning: Font not found at " .. path .. ". Using default.")
            return love.graphics.newFont(size)
        end
    end

    -- Fonts
    game.fonts.deathLarge = loadPixelFont("assets/fonts/BleedingPixels.ttf", 96) 
    game.fonts.default = loadPixelFont("assets/fonts/minecraft_font.ttf", 16)
    game.fonts.deathSmall = loadPixelFont("assets/fonts/minecraft_font.ttf", 24) 
    game.fonts.level = loadPixelFont("assets/fonts/minecraft_font.ttf", 20)

    love.graphics.setFont(game.fonts.default)
    -- ====================

    Renderer.init()
    
    -- Darkness Shader
    do
        local ok, shader = pcall(function()
            return love.graphics.newShader([[
                extern number cx;
                extern number cy;
                extern number innerRadius;
                extern number outerRadius;
                extern number exponent;

                vec4 effect(vec4 color, Image texture, vec2 texCoord, vec2 px)
                {
                    float dist = distance(px, vec2(cx, cy));
                    float t = 0.0;
                    if (outerRadius > innerRadius) {
                        t = clamp((dist - innerRadius) / (outerRadius - innerRadius), 0.0, 1.0);
                    } else {
                        t = step(innerRadius, dist);
                    }
                    t = pow(t, exponent);
                    float alpha = t * color.a;
                    return vec4(0.0, 0.0, 0.0, alpha);
                }
            ]])
        end)
        if ok and shader then
            game.darknessShader = shader
        else
            game.darknessShader = nil
        end
    end

    -- Make game state accessible global
    _G.game = game

    -- Load Sounds
    game.sounds = game.sounds or {}
    game.sounds.damage = {}
    do
        local ok1, s1 = pcall(love.audio.newSource, "assets/audio/damage/damage_1.wav", "static")
        local ok2, s2 = pcall(love.audio.newSource, "assets/audio/damage/damage_2.wav", "static")
        if ok1 and s1 then table.insert(game.sounds.damage, s1) end
        if ok2 and s2 then table.insert(game.sounds.damage, s2) end
    end
    
    game.sounds.death_intro = nil
    game.sounds.death_bells = nil
    do
        local ok3, d1 = pcall(love.audio.newSource, "assets/audio/death/death_intro.wav", "static")
        local ok4, d2 = pcall(love.audio.newSource, "assets/audio/death/death_bells.wav", "static")
        if ok3 and d1 then game.sounds.death_intro = d1 end
        if ok4 and d2 then game.sounds.death_bells = d2 end
    end

    do
        local okd, doorSrc = pcall(love.audio.newSource, "assets/audio/door/door.wav", "static")
        if okd and doorSrc then
            game.sounds.door = doorSrc
            pcall(function() doorSrc:setLooping(true) end)
            pcall(function() setSrcVolume("door", doorSrc, 0) end)
        end
    end

    game.sounds.attack = {}
    do
        local ok1, a1 = pcall(love.audio.newSource, "assets/audio/attack/slash_1.wav", "static")
        local ok2, a2 = pcall(love.audio.newSource, "assets/audio/attack/slash_2.wav", "static")
        if ok1 and a1 then table.insert(game.sounds.attack, a1) end
        if ok2 and a2 then table.insert(game.sounds.attack, a2) end
    end
    game.nextAttackSoundIndex = 1

    for i, src in ipairs(game.sounds.attack) do
        pcall(function() setSrcVolume("attack_" .. tostring(i), src, 0.5) end)
    end

    _G.playAttackSound = function()
        if not game.sounds or not game.sounds.attack or #game.sounds.attack == 0 then return end
        local idx = game.nextAttackSoundIndex or 1
        local src = game.sounds.attack[idx]
        if src then
            pcall(function() src:stop(); src:play() end)
        end
        game.nextAttackSoundIndex = (idx % #game.sounds.attack) + 1
    end

    game.sounds.ambient = {}
    do
        for i=1,5 do
            local ok, s = pcall(love.audio.newSource, "assets/audio/ambient/amb_"..i..".wav", "static")
            if ok and s then table.insert(game.sounds.ambient, s) end
        end
    end
    game.ambient = { minInterval = 10, maxInterval = 30, volume = 0.18 }
    for i, src in ipairs(game.sounds.ambient) do
        pcall(function() setSrcVolume("ambient_" .. tostring(i), src, game.ambient.volume) end)
        pcall(function() src:setLooping(false) end)
    end
    game.nextAmbientTime = love.timer.getTime() + game.ambient.minInterval + (math.random() * (game.ambient.maxInterval - game.ambient.minInterval))

    _G.performPlayerAttack = function(player)
        if not player or not game or not game.enemies then return end
        local attackRange = 64 
        local px, py = player.pixelX, player.pixelY
        local fx, fy = 0, 0
        if player.direction == "right" then fx, fy = 1, 0
        elseif player.direction == "left" then fx, fy = -1, 0
        elseif player.direction == "up" then fx, fy = 0, -1
        elseif player.direction == "down" then fx, fy = 0, 1
        end

        for _, enemy in ipairs(game.enemies) do
            if enemy and not enemy.isDead then
                local ex, ey = enemy.pixelX, enemy.pixelY
                local dx, dy = ex - px, ey - py
                local dist2 = dx*dx + dy*dy
                if dist2 <= (attackRange * attackRange) then
                    local dist = math.sqrt(dist2)
                    local hit = false
                    
                    if fx == 0 and fy == 0 then
                        hit = true
                    else
                        local nx, ny = dx / dist, dy / dist
                        local dot = nx * fx + ny * fy
                        if dot >= 0 then
                            hit = true
                        end
                    end
                    
                    if hit then
                        enemy.isDead = true
                        enemy.direction = nil
                        enemy.speed = 0
                        -- SPAWN PARTICLES
                        if game.hitParticles then
                            game.hitParticles:setPosition(enemy.pixelX, enemy.pixelY)
                            game.hitParticles:emit(20) -- burst of 20 sparks
                        end
                    end
                end
            end
        end
    end

    game.damageFlash = 0
    game.damageFlashDuration = 0.22
    game.timeScale = 1.0
    game.deathSeq = { active = false, phase = nil, timer = 0, fade = 0, textAlpha = 0 }
end

function generateNewMaze()
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

    if game.player then
        local screenWidth, screenHeight = love.graphics.getDimensions()
        Renderer.camera.scale = 0.8  
        Renderer.camera.x = game.player.pixelX - screenWidth / (2 * Renderer.camera.scale)
        Renderer.camera.y = game.player.pixelY - screenHeight / (2 * Renderer.camera.scale)
    end
end

function love.update(dt)
    if game.state == "menu" then
        -- Menu Logic (nothing dynamic yet)
        return
    end

    local timeScale = game.timeScale or 1.0
    local scaledDt = dt * timeScale

    -- UPDATE PARTICLES
    if game.hitParticles then
        game.hitParticles:update(scaledDt)
    end

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
                game.transitionAlpha = game.transitionAlpha + (dt * game.transitionSpeed)
                if game.transitionAlpha >= 1 then
                    game.transitionAlpha = 1
                    game.currentLevel = game.currentLevel + 1
                    generateNewMaze()
                    game.transitionState = "fade_in"
                end
            elseif game.transitionState == "fade_in" then
                game.transitionAlpha = game.transitionAlpha - (dt * game.transitionSpeed)
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
                Renderer.camera.x = game.savedCamera.x
                Renderer.camera.y = game.savedCamera.y
                Renderer.camera.scale = game.savedCamera.scale
                game.showingMazeOverview = false
                Renderer.showingOverview = false
            end
        end
    end

    game.pathfinderBudget = game.pathfinderBudget or 4
    game.pathfinderUsed = 0
    for _, enemy in ipairs(game.enemies) do
        enemy:update(scaledDt)
    end

    if game.player then
        for _, enemy in ipairs(game.enemies) do
            if not game.player.isDead and not game.player.isTakingDamage then
                local dx = enemy.pixelX - game.player.pixelX
                local dy = enemy.pixelY - game.player.pixelY
                local dist = math.sqrt(dx*dx + dy*dy)
                local hitThreshold = (enemy.radius or 12) + 12
                if dist <= hitThreshold and (not enemy.damageCooldown or enemy.damageCooldown <= 0) then
                    game.player:takeDamage(20)
                    game.damageFlash = game.damageFlashDuration
                    if game.sounds and game.sounds.damage and #game.sounds.damage > 0 then
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

    if game.player and game.player.isDead then
        local ds = game.deathSeq
        if not ds.active then
            ds.active = true
            ds.phase = "slowdown"
            ds.timer = 0
            ds.originalTimeScale = game.timeScale or 1.0
            ds.targetTimeScale = 0.12
            ds.originalCameraScale = Renderer.camera.scale
            ds.targetCameraScale = (Renderer.camera.scale or 1.0) * 1.9
            ds.fade = 0
            ds.textAlpha = 0
            ds.fadeDuration = 1.0
            ds.textFadeDuration = 2.0
            ds.introFadeIn = 0.5
            if game.sounds and game.sounds.death_intro then
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

                if ds.introPlaying and game.sounds and game.sounds.death_intro then
                    local src = game.sounds.death_intro
                    if ds.timer <= ds.introFadeIn then
                        local v = math.max(0, math.min(1, ds.timer / ds.introFadeIn))
                        setSrcVolume("death_intro", src, v)
                    end
                end

                local introDone = true
                if ds.introPlaying and game.sounds and game.sounds.death_intro then
                    local ok, playing = pcall(function() return game.sounds.death_intro:isPlaying() end)
                    if ok then introDone = not playing else introDone = ds.timer >= (ds.introDuration or 0) end
                end

                if game.player.deathAnimationDone and introDone then
                    ds.phase = "fade_to_black"
                    ds.timer = 0
                    if ds.introPlaying and game.sounds and game.sounds.death_intro then
                        pcall(function() game.sounds.death_intro:stop() end)
                        ds.introPlaying = false
                    end
                    if game.sounds and game.sounds.death_bells then
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

    if game.sounds and game.sounds.ambient and #game.sounds.ambient > 0 then
        local now = love.timer.getTime()
        if not game.nextAmbientTime then
            game.nextAmbientTime = now + (game.ambient and game.ambient.minInterval or 10)
        end
        if now >= game.nextAmbientTime then
            local idx = math.random(1, #game.sounds.ambient)
            local src = game.sounds.ambient[idx]
            if src then
                pcall(function()
                    src:stop()
                    if game.ambient and game.ambient.volume then setSrcVolume("ambient_" .. tostring(idx), src, game.ambient.volume) end
                    src:setLooping(false)
                    src:play()
                end)
            end
            local minI = (game.ambient and game.ambient.minInterval) or 10
            local maxI = (game.ambient and game.ambient.maxInterval) or 30
            local interval = minI + math.random() * (math.max(0, maxI - minI))
            game.nextAmbientTime = now + interval
        end
    end

    if game.sounds and game.sounds.door and game.finishTileX and game.finishTileY and game.player then
        local ts = Renderer.tileSize or 96
        local fx = (game.finishTileX - 1) * ts + ts / 2
        local fy = (game.finishTileY - 1) * ts + ts / 2
        local dx = fx - game.player.pixelX
        local dy = fy - game.player.pixelY
        local dist = math.sqrt(dx*dx + dy*dy)
        local visibleRadius = (game.player.darkness and game.player.darkness.innerRadius) or game.visionRadius or 200
        local triggerMultiplier = 1.35
        local triggerRadius = visibleRadius * triggerMultiplier
        local src = game.sounds.door
        if dist <= triggerRadius then
            local maxVol = 0.45 
            local vol = maxVol * (1 - (dist / triggerRadius))
            if vol < 0.01 then vol = 0.01 end
            pcall(function() setSrcVolume("door", src, vol) end)
            local ok, playing = pcall(function() return src:isPlaying() end)
            if not (ok and playing) then
                pcall(function() src:stop(); src:play() end)
            end
        else
            local ok, playing = pcall(function() return src:isPlaying() end)
            if ok and playing then
                pcall(function() setSrcVolume("door", src, 0); src:stop() end)
            end
        end
    end
end

-- HELPER: Draw the main menu
local function drawMenu()
    local w, h = love.graphics.getDimensions()
    
    -- Title (Orange, BleedingPixels)
    love.graphics.setFont(game.fonts.deathLarge)
    love.graphics.setColor(1, 0.5, 0, 1) -- Orange
    love.graphics.printf("MAZEKNIGHT", 0, h * 0.25, w, "center")
    
    -- Options (Minecraft Font)
    love.graphics.setFont(game.fonts.deathSmall)
    for i, opt in ipairs(game.menu.options) do
        if i == game.menu.selection then
            love.graphics.setColor(1, 1, 1, 1) -- Selected: White
            love.graphics.printf("> " .. opt .. " <", 0, h * 0.55 + (i * 40), w, "center")
        else
            love.graphics.setColor(0.5, 0.5, 0.5, 1) -- Unselected: Gray
            love.graphics.printf(opt, 0, h * 0.55 + (i * 40), w, "center")
        end
    end
    
    love.graphics.setColor(1, 1, 1, 1)
end

function love.draw()
    if game.state == "menu" then
        drawMenu()
        return
    end

    if game.player and not game.showingMazeOverview then
        local screenWidth = love.graphics.getWidth()
        local screenHeight = love.graphics.getHeight()
        Renderer.camera.x = game.player.pixelX - (screenWidth / (2 * Renderer.camera.scale))
        Renderer.camera.y = game.player.pixelY - (screenHeight / (2 * Renderer.camera.scale))
    end

    -- Pass particles to renderer so they draw in world space
    Renderer.drawMaze(game.maze, game.enemies, game.player, game.hitParticles)

    if game.transitioning and game.transitionAlpha > 0 then
        love.graphics.setColor(0, 0, 0, game.transitionAlpha)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setColor(1, 1, 1)
    end

    if game.player and not game.showingMazeOverview then
        local screenWidth = love.graphics.getWidth()
        local screenHeight = love.graphics.getHeight()
        local playerScreenX = screenWidth / 2
        local playerScreenY = screenHeight / 2

        if game.darknessShader then
            local inner = (game.player.darkness and game.player.darkness.innerRadius or game.visionRadius) * Renderer.camera.scale
            local outer = (game.player.darkness and game.player.darkness.outerRadius or (game.visionRadius * 2)) * Renderer.camera.scale
            local exponent = (game.player.darkness and game.player.darkness.exponent) or 1.6
            local alpha = (game.player.darkness and game.player.darkness.alpha) or game.darknessAlpha

            game.darknessShader:send("cx", playerScreenX)
            game.darknessShader:send("cy", playerScreenY)
            game.darknessShader:send("innerRadius", inner)
            game.darknessShader:send("outerRadius", outer)
            game.darknessShader:send("exponent", exponent)

            love.graphics.setShader(game.darknessShader)
            love.graphics.setColor(0, 0, 0, alpha)
            love.graphics.rectangle("fill", 0, 0, screenWidth, screenHeight)
            love.graphics.setShader()
            love.graphics.setColor(1, 1, 1)
        else
            love.graphics.stencil(function()
                love.graphics.circle("fill", playerScreenX, playerScreenY, game.visionRadius, 128)
            end, "replace", 1)
            love.graphics.setStencilTest("equal", 0)
            love.graphics.setColor(0, 0, 0, game.darknessAlpha)
            love.graphics.rectangle("fill", 0, 0, screenWidth, screenHeight)
            love.graphics.setStencilTest()
            love.graphics.setColor(1, 1, 1)
        end
    end

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

    if game.damageFlash and game.damageFlash > 0 then
        local alpha = (game.damageFlash / (game.damageFlashDuration or 0.22)) * 0.45
        love.graphics.setColor(1, 0, 0, alpha)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setColor(1, 1, 1)
    end

    do
        local passed = math.max(0, (game.currentLevel or 1) - 1)
        local txt = string.format("Levels Passed: %d", passed)
        local f = (game.fonts and game.fonts.level) or game.fonts.default
        love.graphics.setFont(f)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(txt, 8, 8)
        love.graphics.setColor(1, 1, 1)
        if game.fonts and game.fonts.default then love.graphics.setFont(game.fonts.default) end
    end

    if game.deathSeq and game.deathSeq.active then
        local ds = game.deathSeq
        if ds.fade and ds.fade > 0 then
            love.graphics.setColor(0, 0, 0, math.min(1, ds.fade))
            love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
            love.graphics.setColor(1, 1, 1)
        end

        if ds.phase == "text_fade" then
            local alpha = ds.textAlpha or 0
            local w, h = love.graphics.getDimensions()
            
            -- "DEATH IS CALLING..." using BleedingPixels
            love.graphics.setFont(game.fonts.deathLarge)
            love.graphics.setColor(1, 0, 0, alpha)
            love.graphics.printf("DEATH IS CALLING...\nwill you answer?", 0, h * 0.40, w, "center")
            love.graphics.setColor(1, 1, 1)

            if (ds.textAlpha or 0) >= 1 then
                -- Subtext using Minecraft font
                love.graphics.setFont(game.fonts.deathSmall)
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.printf("Press SPACE to restart", 0, h * 0.65, w, "center")
                love.graphics.setColor(1, 1, 1)
            end
            
            if game.fonts.default then love.graphics.setFont(game.fonts.default) end
        end
    end

    if game.debug then
        love.graphics.setFont(game.fonts.default)
        love.graphics.setColor(0, 0, 0, 0.9)
        love.graphics.rectangle("fill", 10, 10, 480, 160)
        love.graphics.setColor(1, 1, 1)

        love.graphics.print("MazeKnight - Procedural Maze Explorer", 20, 20)
        love.graphics.print(string.format("Level: %d | Maze: %dx%d | Seed: %d",
            game.currentLevel, game.mazeWidth, game.mazeHeight, game.seed or 0), 20, 40)
        if game.player then
            love.graphics.print(string.format("Health: %d | Pos: (%d, %d) | Anim: %s",
                game.player.health, game.player.gridX, game.player.gridY, game.player.currentAnimation), 20, 80)
            love.graphics.print(string.format("Pixel: (%.0f, %.0f) | Sprite: %s",
                game.player.pixelX, game.player.pixelY, game.player.spritesheet and "OK" or "MISSING"), 20, 100)
        end
        
        love.graphics.setColor(0, 1, 0)
        love.graphics.print("FPS: " .. love.timer.getFPS(), 20, love.graphics.getHeight() - 30)
        love.graphics.setColor(1, 1, 1)
    end
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    end

    if game.state == "menu" then
        if key == "up" or key == "w" then
            game.menu.selection = game.menu.selection - 1
            if game.menu.selection < 1 then game.menu.selection = #game.menu.options end
        elseif key == "down" or key == "s" then
            game.menu.selection = game.menu.selection + 1
            if game.menu.selection > #game.menu.options then game.menu.selection = 1 end
        elseif key == "return" or key == "space" then
            if game.menu.selection == 1 then
                -- Start Game
                game.state = "playing"
                generateNewMaze()
            elseif game.menu.selection == 2 then
                -- Quit
                love.event.quit()
            end
        end
        return
    end

    -- Playing state inputs
    if key == "space" then
        if game.deathSeq and game.deathSeq.active and game.deathSeq.phase == "text_fade" then
            if game.sounds and game.sounds.death_bells then game.sounds.death_bells:stop() end
            if game.sounds and game.sounds.death_intro then game.sounds.death_intro:stop() end
            game.timeScale = 1.0
            game.deathSeq = { active = false, phase = nil, timer = 0, fade = 0, textAlpha = 0 }
            game.currentLevel = 1
            game.transitioning = false
            game.transitionAlpha = 0
            
            -- Restart to menu or game? Usually restart restarts the game
            game.state = "playing" 
            generateNewMaze()
            return
        end
    elseif key == "f3" then
        game.debug = not game.debug
    elseif key == "n" then
        generateNewMaze()
    elseif key == "f" then
        local screenWidth, screenHeight = love.graphics.getDimensions()
        Renderer.fitMazeToScreen(game.maze, screenWidth, screenHeight)
    elseif key == "r" then
        print("\n--- Regenerating maze with seed: " .. game.seed .. " ---")
        game.maze = MazeGenerator.generate(game.mazeWidth, game.mazeHeight, game.seed)
        local playerSpawnX, playerSpawnY = nil, nil
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
        if playerSpawnX and game.player then
            game.player.gridX = playerSpawnX
            game.player.gridY = playerSpawnY
            game.player.targetGridX = playerSpawnX
            game.player.targetGridY = playerSpawnY
            local ts = Renderer.tileSize
            game.player.pixelX = (playerSpawnX - 1) * ts + ts / 2
            game.player.pixelY = (playerSpawnY - 1) * ts + ts / 2
            game.player.maze = game.maze
        end
    end
end

function love.resize(w, h)
    Renderer.centerCamera(game.maze, w, h)
end