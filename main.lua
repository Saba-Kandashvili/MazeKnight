-- MazeKnight
-- a procedural maze explorer using my implementation of Wave Function Collapse

local MazeGenerator = require("src.maze_generator")
local Renderer = require("src.renderer")
local Enemy = require("src.enemy")
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
    maze = nil,
    seed = nil,
    mazeWidth = 15,
    mazeHeight = 15,
    debug = false,
    enemies = {},
    player = nil,
    showingMazeOverview = false,
    savedCamera = { x = 0, y = 0, scale = 1 },  -- store camera state when showing overview
    finishTileX = nil,  -- finish tile coordinates
    finishTileY = nil,
    -- level transition
    transitioning = false,
    transitionAlpha = 0,
    transitionState = "none",  -- "none", "fade_out", "fade_in"
    transitionSpeed = 2.0,  -- how fast the fade happens
    currentLevel = 1,
    -- darkness/vision settings
    visionRadius = 200,  -- radius in pixels of the visible area around player
    darknessAlpha = 0.85  -- how dark the fog is (0 = invisible, 1 = completely black)
}

-- asfe volume-set helper (file-scope) so update/draw can call it
local function setSrcVolume(label, src, v)
    if not src then
        log(string.format("[vol] %s: source missing, cannot set volume to %.2f", label, tonumber(v) or 0))
        return
    end
    local ok, err = pcall(function() src:setVolume(v) end)
    if not ok then
        log(string.format("[vol] %s: setVolume failed: %s", label, tostring(err)))
    end
    -- log the attempt (this will show repeated fades) [this drove me crazy too]
    log(string.format("[vol] %s: setVolume=%.2f src=%s", label, tonumber(v) or 0, tostring(src)))
end

function love.load()
    print("=== MazeKnight Starting ===")
    print("Love2D Version: " .. love.getVersion())
    
    -- open console on Windows for debugging
    if love.system.getOS() == "Windows" then
        io.stdout:setvbuf("no")
    end
    
    -- set up graphics
    love.graphics.setBackgroundColor(0.05, 0.05, 0.05)
    love.graphics.setDefaultFilter("nearest", "nearest")  -- pixel art style (not really but meh)

    -- prepare fonts for death screen and HUD
    game.fonts = game.fonts or {}
    do
        local okd, fdl = pcall(love.graphics.newFont, 64)
        if okd and fdl then game.fonts.deathLarge = fdl end
        local oks, fsm = pcall(love.graphics.newFont, 18)
        if oks and fsm then game.fonts.deathSmall = fsm end
        local okl, flv = pcall(love.graphics.newFont, 14)
        if okl and flv then game.fonts.level = flv end
        game.fonts.default = love.graphics.getFont()
    end
    
    Renderer.init()
    -- create global darkness shader (gradient overlay)
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
            print("Warning: global darkness shader unavailable; falling back to stencil overlay")
        end
    end
    
    -- generate initial maze
    generateNewMaze()

    -- make game state accessible to other modules (for input/transition checks)
    _G.game = game
    
    -- load damage and death sounds
    game.sounds = game.sounds or {}
    game.sounds.damage = {}
    do
        local ok1, s1 = pcall(love.audio.newSource, "assets/audio/damage/damage_1.wav", "static")
        local ok2, s2 = pcall(love.audio.newSource, "assets/audio/damage/damage_2.wav", "static")
        if ok1 and s1 then table.insert(game.sounds.damage, s1) end
        if ok2 and s2 then table.insert(game.sounds.damage, s2) end
    end
    log("Loaded damage sounds, count=", #game.sounds.damage)
    game.sounds.death_intro = nil
    game.sounds.death_bells = nil
    do
        local ok3, d1 = pcall(love.audio.newSource, "assets/audio/death/death_intro.wav", "static")
        local ok4, d2 = pcall(love.audio.newSource, "assets/audio/death/death_bells.wav", "static")
        if ok3 and d1 then game.sounds.death_intro = d1 end
        if ok4 and d2 then game.sounds.death_bells = d2 end
    end
    log("death_intro=", tostring(game.sounds.death_intro ~= nil), " death_bells=", tostring(game.sounds.death_bells ~= nil))

    -- door sound (looping) for finish tile proximity
    do
        local okd, doorSrc = pcall(love.audio.newSource, "assets/audio/door/door.wav", "static")
        if okd and doorSrc then
            game.sounds.door = doorSrc
            pcall(function() doorSrc:setLooping(true) end)
            -- start silent
            pcall(function() setSrcVolume("door", doorSrc, 0) end)
        else
            game.sounds.door = nil
        end
    end

    -- slash sounds and prepare alternating playback
    game.sounds.attack = {}
    do
        local ok1, a1 = pcall(love.audio.newSource, "assets/audio/attack/slash_1.wav", "static")
        local ok2, a2 = pcall(love.audio.newSource, "assets/audio/attack/slash_2.wav", "static")
        if ok1 and a1 then table.insert(game.sounds.attack, a1) end
        if ok2 and a2 then table.insert(game.sounds.attack, a2) end
    end
    game.nextAttackSoundIndex = 1
    log("Loaded attack sounds, count=", #game.sounds.attack)

    for i, src in ipairs(game.sounds.attack) do
        pcall(function()
            setSrcVolume("attack_" .. tostring(i), src, 0.5)
        end)
    end

    _G.playAttackSound = function()
        if not game.sounds or not game.sounds.attack or #game.sounds.attack == 0 then return end
        local idx = game.nextAttackSoundIndex or 1
        local src = game.sounds.attack[idx]
        if src then
            pcall(function()
                src:stop()
                src:play()
            end)
        end
        -- advance index (wrap)
        game.nextAttackSoundIndex = (idx % #game.sounds.attack) + 1
    end

    -- load ambient atmosphere sounds
    game.sounds.ambient = {}
    do
        local ok1, a1 = pcall(love.audio.newSource, "assets/audio/ambient/amb_1.wav", "static")
        local ok2, a2 = pcall(love.audio.newSource, "assets/audio/ambient/amb_2.wav", "static")
        local ok3, a3 = pcall(love.audio.newSource, "assets/audio/ambient/amb_3.wav", "static")
        local ok4, a4 = pcall(love.audio.newSource, "assets/audio/ambient/amb_4.wav", "static")
        local ok5, a5 = pcall(love.audio.newSource, "assets/audio/ambient/amb_5.wav", "static")
        if ok1 and a1 then table.insert(game.sounds.ambient, a1) end
        if ok2 and a2 then table.insert(game.sounds.ambient, a2) end
        if ok3 and a3 then table.insert(game.sounds.ambient, a3) end
        if ok4 and a4 then table.insert(game.sounds.ambient, a4) end
        if ok5 and a5 then table.insert(game.sounds.ambient, a5) end
    end
    -- very low ambient volume
    game.ambient = { minInterval = 10, maxInterval = 30, volume = 0.18 }
    for i, src in ipairs(game.sounds.ambient) do
        pcall(function() setSrcVolume("ambient_" .. tostring(i), src, game.ambient.volume) end)
        pcall(function() src:setLooping(false) end)
    end
    -- schedule first ambient event a little randomized after load
    game.nextAmbientTime = love.timer.getTime() + game.ambient.minInterval + (math.random() * (game.ambient.maxInterval - game.ambient.minInterval))

    -- attack forward up and down
    _G.performPlayerAttack = function(player)
        if not player or not game or not game.enemies then return end
        local attackRange = 64 -- pixels

        local px, py = player.pixelX, player.pixelY

        -- facing vector
        local fx, fy = 0, 0
        if player.direction == "right" then fx, fy = 1, 0
        elseif player.direction == "left" then fx, fy = -1, 0
        elseif player.direction == "up" then fx, fy = 0, -1
        elseif player.direction == "down" then fx, fy = 0, 1
        end

        for _, enemy in ipairs(game.enemies) do
            if enemy and not enemy.isDead then
                local ex, ey = enemy.pixelX, enemy.pixelY
                local dx = ex - px
                local dy = ey - py
                local dist2 = dx*dx + dy*dy
                if dist2 <= (attackRange * attackRange) then
                    local dist = math.sqrt(dist2)
                    -- if player has no facing, treat as full radial (idk how thi would happen)
                    if fx == 0 and fy == 0 then
                        -- hit
                        enemy.isDead = true
                        enemy.direction = nil
                        enemy.speed = 0
                        enemy.damageCooldown = 9999
                    else
                        -- normalized vector to enemy
                        local nx, ny = dx / dist, dy / dist
                        -- dot product between facing and enemy direction
                        local dot = nx * fx + ny * fy
                        -- dot >= 0 means enemy is in front hemisphere (<= 90deg). hit those.
                        if dot >= 0 then
                            enemy.isDead = true
                            enemy.direction = nil
                            enemy.speed = 0
                            enemy.damageCooldown = 9999
                        end
                    end
                end
            end
        end
    end

    

    -- screen red flash when player hurt
    game.damageFlash = 0
    game.damageFlashDuration = 0.22

    -- time scale for slow-motion effects
    game.timeScale = 1.0
    -- death sequence state
    game.deathSeq = { active = false, phase = nil, timer = 0, fade = 0, textAlpha = 0 }
    
    print("=== Game Loaded ===")
    print("Controls:")
    print("  WASD/Arrows: Move player")
    print("  SPACE: Attack")
    print("  N: New maze")
    print("  R: Regenerate with same seed")
    print("  F: Fit maze to screen")
    print("  +/-: Zoom")
    print("  ESC: Quit")
end



function generateNewMaze()
    -- use high-resolution time to ensure unique seeds even when called rapidly
    game.seed = math.floor(love.timer.getTime() * 1000)  -- milliseconds since start | this maybe oevrkill but meh
    print("\n--- Generating new maze ---")
    
    -- maze using the DLL/SO
    game.maze = MazeGenerator.generate(game.mazeWidth, game.mazeHeight, game.seed)
    
    -- find X near the edges for player spawn
    local TileMapper = require("src.tile_mapper")
    local PF = TileMapper.PrefabCodes
    local edgeCrossroads = {}
    local edgeThreshold = 3  -- "near edge"
    
    for y = 1, game.maze.height do
        for x = 1, game.maze.width do
            local tile = game.maze.tiles[y][x]
            -- if it's a crossroad (Normal_X_Corridor or Special_X_Corridor)
            if tile.code == PF.Normal_X_Corridor or tile.code == PF.Special_X_Corridor then
                -- if near any edge
                local nearEdge = (x <= edgeThreshold or x > game.maze.width - edgeThreshold or
                                 y <= edgeThreshold or y > game.maze.height - edgeThreshold)
                if nearEdge then
                    table.insert(edgeCrossroads, {x = x, y = y})
                end
            end
        end
    end
    
    -- create player at random edge crossroad (or fallback to any valid tile)
    local playerSpawnX, playerSpawnY = nil, nil
    if #edgeCrossroads > 0 then
        local spawnTile = edgeCrossroads[math.random(1, #edgeCrossroads)]
        playerSpawnX = spawnTile.x
        playerSpawnY = spawnTile.y
        print(string.format("Player spawned at edge crossroad (%d, %d)", playerSpawnX, playerSpawnY))
    else
        -- fallback: find any valid tile
        for y = 1, game.maze.height do
            for x = 1, game.maze.width do
                local tile = game.maze.tiles[y][x]
                if tile.tileType ~= "empty" then
                    playerSpawnX = x
                    playerSpawnY = y
                    break
                end
            end
            if playerSpawnX then break end
        end
        print(string.format("Player spawned at fallback position (%d, %d)", playerSpawnX, playerSpawnY))
    end
    
    -- create player and mark spawn tile
    if playerSpawnX then
        game.player = Player.new(playerSpawnX, playerSpawnY, game.maze)
        -- mark the spawn tile so it renders with S.png instead of X.png
        game.maze.tiles[playerSpawnY][playerSpawnX].isSpawn = true
        
        -- find finish tile at opposite edge from spawn
        -- determine which edge the spawn is on and calculate center point of opposite edge
        local spawnOnLeft = playerSpawnX <= edgeThreshold
        local spawnOnRight = playerSpawnX > game.maze.width - edgeThreshold
        local spawnOnTop = playerSpawnY <= edgeThreshold
        local spawnOnBottom = playerSpawnY > game.maze.height - edgeThreshold
        
        -- determine target edge position
        local targetX, targetY
        if spawnOnLeft then
            targetX = game.maze.width  
            targetY = game.maze.height / 2
        elseif spawnOnRight then
            targetX = 1
            targetY = game.maze.height / 2
        elseif spawnOnTop then
            targetX = game.maze.width / 2
            targetY = game.maze.height  
        elseif spawnOnBottom then
            targetX = game.maze.width / 2
            targetY = 1  
        else
            -- spawn in middle, choose any edge
            targetX = game.maze.width
            targetY = game.maze.height / 2
        end
        
        -- find all crossroads and choose the one closest to the target edge position
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
        -- choose the crossroad closest to the target edge position
        if #allCrossroads > 0 then
            table.sort(allCrossroads, function(a, b) return a.distance < b.distance end)
            local finishTile = allCrossroads[1]
            game.finishTileX = finishTile.x
            game.finishTileY = finishTile.y
            game.maze.tiles[finishTile.y][finishTile.x].isFinish = true
            print(string.format("Finish tile placed at (%d, %d) - distance to target: %.1f", 
                finishTile.x, finishTile.y, finishTile.distance))
        else
            print("Warning: Could not find suitable finish tile")
        end
    end
    
    -- spawn enemies at random valid tiles
    game.enemies = {}
    -- find all valid tiles for spawning
    local validSpawnTiles = {}
    for y = 1, game.maze.height do
        for x = 1, game.maze.width do
            local tile = game.maze.tiles[y][x]
            if tile.tileType ~= "empty" then
                table.insert(validSpawnTiles, {x = x, y = y})
            end
        end
    end

    -- filter spawn tiles: avoid player's immediate area and special tiles (spawn/finish)
    local minSpawnDistance = 3 -- in tiles (exclude tiles within this radius from player spawn)
    local filteredSpawnTiles = {}
    for _, t in ipairs(validSpawnTiles) do
        -- skip spawn and finish tiles explicitly
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
    
    -- spawn enemies at random locations
    for i = 1, math.min(numEnemies, #filteredSpawnTiles) do
        local spawnTile = filteredSpawnTiles[math.random(1, #filteredSpawnTiles)]
        local enemy = Enemy.new(spawnTile.x, spawnTile.y, game.maze)
        table.insert(game.enemies, enemy)
    end
    
    print(string.format("Spawned %d enemies", #game.enemies))
    
    -- set camera to follow player instead of fitting maze to screen
    if game.player then
        local screenWidth, screenHeight = love.graphics.getDimensions()
        Renderer.camera.scale = 0.8  -- good zoom level for gameplay... jsut realised my agem might not look sme for different resolutions... MEH
        Renderer.camera.x = game.player.pixelX - screenWidth / (2 * Renderer.camera.scale)
        Renderer.camera.y = game.player.pixelY - screenHeight / (2 * Renderer.camera.scale)
    end
    
    print("--- Maze ready ---\n")
end

function love.update(dt)
    -- apply global time scale for slow-motion effects cause DRAMA
    local timeScale = game.timeScale or 1.0
    local scaledDt = dt * timeScale

    if game.player then
        game.player:update(scaledDt)
        
        --  if player reached finish tile center (1,1)
        if game.finishTileX and game.finishTileY and not game.transitioning then
            local finishSubX = (game.finishTileX - 1) * 3 + 2  -- center of finish tile in sub-grid (1,1 = index 2)
            local finishSubY = (game.finishTileY - 1) * 3 + 2
            
            if game.player.gridX == finishSubX and game.player.gridY == finishSubY then
                print(string.format("\n=== LEVEL %d COMPLETE! ===", game.currentLevel))
                print(string.format("Player at (%d, %d), Finish at (%d, %d)", 
                    game.player.gridX, game.player.gridY, finishSubX, finishSubY))
                -- begin level transition and pause gameplay time so player/enemies freeze
                game.transitioning = true
                game.transitionState = "fade_out"
                game.transitionAlpha = 0
                -- pause gameplay by zeroing timeScale (love.update still runs transitions using raw dt)
                game.timeScale = 0
            end
        end
        
        -- level transition
        if game.transitioning then
            if game.transitionState == "fade_out" then
                game.transitionAlpha = game.transitionAlpha + (dt * game.transitionSpeed)
                if game.transitionAlpha >= 1 then
                    game.transitionAlpha = 1
                    -- screen is fully black, generate new level
                    game.currentLevel = game.currentLevel + 1
                    print(string.format("Generating Level %d...", game.currentLevel))
                    generateNewMaze()
                    game.transitionState = "fade_in"
                end
            elseif game.transitionState == "fade_in" then
                game.transitionAlpha = game.transitionAlpha - (dt * game.transitionSpeed)
                if game.transitionAlpha <= 0 then
                    game.transitionAlpha = 0
                    game.transitioning = false
                    game.transitionState = "none"
                    -- resume gameplay time
                    game.timeScale = 1.0
                    print("Transition complete!\n")
                end
            end
        end
        
        -- I'll be honest, this is a sloppy implemetation but works for 15x15 mazes so meh
        -- DEBUG: show entire maze when backspace is held
        if game.debug and love.keyboard.isDown("backspace") then
            if not game.showingMazeOverview then
                -- save current camera state
                game.savedCamera.x = Renderer.camera.x
                game.savedCamera.y = Renderer.camera.y
                game.savedCamera.scale = Renderer.camera.scale
                game.showingMazeOverview = true
                    Renderer.showingOverview = true
                
                -- calculate scale to fit entire maze
                local screenWidth, screenHeight = love.graphics.getDimensions()
                local mazePixelWidth = game.maze.width * Renderer.tileSize
                local mazePixelHeight = game.maze.height * Renderer.tileSize
                
                -- calculate scale to fit the entire maze with padding
                local scaleX = screenWidth / mazePixelWidth
                local scaleY = screenHeight / mazePixelHeight
                Renderer.camera.scale = math.min(scaleX, scaleY) * 0.95
                
                -- position camera so (0,0) of maze is visible and maze is centered
                local scaledScreenWidth = screenWidth / Renderer.camera.scale
                local scaledScreenHeight = screenHeight / Renderer.camera.scale
                Renderer.camera.x = -(scaledScreenWidth - mazePixelWidth) / 2
                Renderer.camera.y = -(scaledScreenHeight - mazePixelHeight) / 2
            end
        else
            if game.showingMazeOverview then
                -- restore camera to follow player
                Renderer.camera.x = game.savedCamera.x
                Renderer.camera.y = game.savedCamera.y
                Renderer.camera.scale = game.savedCamera.scale
                game.showingMazeOverview = false
                Renderer.showingOverview = false
            end
        end
    end
    
    -- update enemies (scaled dt)
    for _, enemy in ipairs(game.enemies) do
        enemy:update(scaledDt)
    end

    -- check collisions between enemies and player
    if game.player then
        for _, enemy in ipairs(game.enemies) do
            if not game.player.isDead and not game.player.isTakingDamage then
                local dx = enemy.pixelX - game.player.pixelX
                local dy = enemy.pixelY - game.player.pixelY
                local dist = math.sqrt(dx*dx + dy*dy)
                local hitThreshold = (enemy.radius or 12) + 12
                if dist <= hitThreshold and (not enemy.damageCooldown or enemy.damageCooldown <= 0) then
                    -- apply damage: 20
                    game.player:takeDamage(20)

                    -- start damage flash and play random damage sound
                    game.damageFlash = game.damageFlashDuration
                    if game.sounds and game.sounds.damage and #game.sounds.damage > 0 then
                        local idx = math.random(1, #game.sounds.damage)
                        local src = game.sounds.damage[idx]
                        if src then
                            src:stop()
                            src:play()
                        end
                    end

                    -- give this enemy a short cooldown so it doesn't hit repeatedly while overlapping
                    enemy.damageCooldown = 0.48
                end
            end
        end
    end

    -- decrease damage flash timer
    if game.damageFlash and game.damageFlash > 0 then
        game.damageFlash = game.damageFlash - dt
        if game.damageFlash < 0 then game.damageFlash = 0 end
    end

    -- had to log everything cause it was drivign me crazy
    -- death sequence handling (real-time dt)
    if game.player and game.player.isDead then
        local ds = game.deathSeq
        if not ds.active then
                -- start death sequence: slow down time, zoom camera, play intro | will make a grown man cry :'( 
                ds.active = true
                log("[death] sequence started")
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
                ds.introFadeOut = 0.6
                if game.sounds and game.sounds.death_intro then
                    local src = game.sounds.death_intro
                    local ok, dur = pcall(function() return src:getDuration() end)
                    ds.introDuration = (ok and dur) or 2.0
                    setSrcVolume("death_intro", src, 0)
                    src:stop()
                    src:play()
                    ds.introPlaying = true
                    log("[death] death_intro started, duration=", ds.introDuration)
                else
                    ds.introDuration = 0
                    ds.introPlaying = false
                end
        else
            if ds.phase == "slowdown" then
                ds.timer = ds.timer + dt
                local t = math.min(1, ds.timer / 1.2)
                -- lerp timeScale toward target
                game.timeScale = ds.originalTimeScale + (ds.targetTimeScale - ds.originalTimeScale) * t
                -- lerp camera scale (use real time so zoom feels smooth)
                Renderer.camera.scale = ds.originalCameraScale + (ds.targetCameraScale - ds.originalCameraScale) * t

                -- audio intro fade in/out handling (if intro is playing)
                if ds.introPlaying and game.sounds and game.sounds.death_intro then
                    local src = game.sounds.death_intro
                    -- fade in
                    if ds.timer <= ds.introFadeIn then
                        local v = math.max(0, math.min(1, ds.timer / ds.introFadeIn))
                        setSrcVolume("death_intro", src, v)
                    end
                    -- (intro file contains its own fade-out)
                end

                -- when both death animation and intro finish, proceed to fade
                local introDone = true
                if ds.introPlaying and game.sounds and game.sounds.death_intro then
                    local ok, playing = pcall(function() return game.sounds.death_intro:isPlaying() end)
                    if ok then
                        introDone = not playing
                    else
                        introDone = ds.timer >= (ds.introDuration or 0)
                    end
                end
                if ds.introPlaying then log("[death] introPlaying, introDone=", introDone, " timer=", ds.timer, " introDur=", ds.introDuration) end

                if game.player.deathAnimationDone and introDone then
                    ds.phase = "fade_to_black"
                    ds.timer = 0
                    log("[death] entering fade_to_black")

                    -- ensure intro is stopped
                    if ds.introPlaying and game.sounds and game.sounds.death_intro then
                        local src = game.sounds.death_intro
                        pcall(function() src:stop() end)
                        ds.introPlaying = false
                    end
                    -- DEATH IS CALLING WILL YOU ANSWER? 
                    -- start death_bells immediately as fade begins (with fade-in)
                    if game.sounds and game.sounds.death_bells then
                        local bell = game.sounds.death_bells
                        local ok, err = pcall(function()
                            bell:stop()
                            bell:setLooping(false)
                            -- Start bells immediately at full volume (DRAMA 100)
                            setSrcVolume("death_bells", bell, 1)
                            bell:play()
                        end)
                        if not ok then
                            log("[death] failed to start death_bells:", err)
                        else
                            log("[death] death_bells play called")
                        end
                        local playingOk, isPlaying = pcall(function() return bell:isPlaying() end)
                        log("[death] death_bells isPlaying?", playingOk and tostring(isPlaying) or "(check failed)")
                        ds.bellsPlaying = true
                        ds.bellsFadeIn = 0.6
                        log("[death] ds.bellsPlaying = true, bellsFadeIn=", ds.bellsFadeIn)
                    else
                        log("[death] death_bells source missing at fade start")
                    end
                end

            elseif ds.phase == "fade_to_black" then
                ds.timer = ds.timer + dt
                ds.fade = math.min(1, ds.timer / ds.fadeDuration)
                -- slow everything further during fade
                game.timeScale = 0.05

                if ds.fade >= 1 then
                    ds.phase = "text_fade"
                    ds.timer = 0
                    -- stop intro if still playing
                    if ds.introPlaying and game.sounds and game.sounds.death_intro then
                        local src = game.sounds.death_intro
                        src:stop()
                        ds.introPlaying = false
                    end
                    -- death_bells already started when fade began; do not restart here
                end

                -- bells are started at full volume; no per-frame fade applied here.

            elseif ds.phase == "text_fade" then
                ds.timer = ds.timer + dt
                ds.textAlpha = math.min(1, ds.timer / ds.textFadeDuration)
                -- keep screen fully faded during text fade
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

        -- ambient sound scheduler (play quiet ambience occasionally, min interval enforced)
        if game.sounds and game.sounds.ambient and #game.sounds.ambient > 0 then
            local now = love.timer.getTime()
            if not game.nextAmbientTime then
                game.nextAmbientTime = now + (game.ambient and game.ambient.minInterval or 10)
            end
            if now >= game.nextAmbientTime then
                -- pick a random ambient sample and play it quietly
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
                -- schedule next ambient: at least minInterval later, up to maxInterval
                local minI = (game.ambient and game.ambient.minInterval) or 10
                local maxI = (game.ambient and game.ambient.maxInterval) or 30
                local interval = minI + math.random() * (math.max(0, maxI - minI))
                game.nextAmbientTime = now + interval
            end
        end

        -- door proximity: loop door sound when player is within visible radius of finish tile
        if game.sounds and game.sounds.door and game.finishTileX and game.finishTileY and game.player then
            local ts = Renderer.tileSize or 96
            local fx = (game.finishTileX - 1) * ts + ts / 2
            local fy = (game.finishTileY - 1) * ts + ts / 2
            local dx = fx - game.player.pixelX
            local dy = fy - game.player.pixelY
            local dist = math.sqrt(dx*dx + dy*dy)
            local visibleRadius = (game.player.darkness and game.player.darkness.innerRadius) or game.visionRadius or 200
            -- trigger a bit further away than the visible inner radius so player can hear the door earlier
            local triggerMultiplier = 1.35
            local triggerRadius = visibleRadius * triggerMultiplier
            local src = game.sounds.door
            if dist <= triggerRadius then
                -- player within audible trigger radius: ensure playing and set volume proportional to closeness
                local maxVol = 0.45 -- cap so it's not too loud
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

function love.draw()
    -- always center camera on player before drawing unless showing overview
    if game.player and not game.showingMazeOverview then
        local screenWidth = love.graphics.getWidth()
        local screenHeight = love.graphics.getHeight()
        Renderer.camera.x = game.player.pixelX - (screenWidth / (2 * Renderer.camera.scale))
        Renderer.camera.y = game.player.pixelY - (screenHeight / (2 * Renderer.camera.scale))
    end
    
    -- draw the maze and enemies
    Renderer.drawMaze(game.maze, game.enemies, game.player)
    
    -- draw fade transition overlay
    if game.transitioning and game.transitionAlpha > 0 then
        love.graphics.setColor(0, 0, 0, game.transitionAlpha)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setColor(1, 1, 1)
    end
    
    -- draw darkness overlay centered on screen center (which is where player is because camera is centered)
    if game.player and not game.showingMazeOverview then
        local screenWidth = love.graphics.getWidth()
        local screenHeight = love.graphics.getHeight()

        -- player is ALWAYS at screen center because camera is centered on player
        local playerScreenX = screenWidth / 2
        local playerScreenY = screenHeight / 2

        -- if global shader available use gradient overlay otherwise fallback to stencil circle
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
            -- fallback: stencil-based circle
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
    

    -- draw large bottom health bar for player
    if game.player then
        local sw, sh = love.graphics.getDimensions()
        local barW = sw * 0.75
        local barH = 28
        local barX = (sw - barW) / 2
        local barY = sh - barH - 12

        -- background
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", barX, barY, barW, barH, 6, 6)

        -- health fill
        local healthPct = math.max(0, math.min(1, (game.player.health or 0) / 100))
        local fillW = barW * healthPct
        if healthPct > 0.6 then
            love.graphics.setColor(0.2, 0.8, 0.2)
        elseif healthPct > 0.3 then
            love.graphics.setColor(0.95, 0.8, 0.2)
        else
            love.graphics.setColor(0.9, 0.25, 0.25)
        end
        love.graphics.rectangle("fill", barX + 4, barY + 4, math.max(0, fillW - 8), barH - 8, 4, 4)

        -- border
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.rectangle("line", barX, barY, barW, barH, 6, 6)
        love.graphics.setColor(1, 1, 1)
    end

    -- draw damage flash overlay (subtle red) if active
    if game.damageFlash and game.damageFlash > 0 then
        local alpha = (game.damageFlash / (game.damageFlashDuration or 0.22)) * 0.45
        love.graphics.setColor(1, 0, 0, alpha)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setColor(1, 1, 1)
    end

    -- level counter
    do
        local passed = math.max(0, (game.currentLevel or 1) - 1)
        local txt = string.format("Levels Passed: %d", passed)
        local f = (game.fonts and game.fonts.level) or (game.fonts and game.fonts.default) or love.graphics.getFont()
        love.graphics.setFont(f)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(txt, 8, 8)
        love.graphics.setColor(1, 1, 1)
        if game.fonts and game.fonts.default then love.graphics.setFont(game.fonts.default) end
    end

    -- death sequence drawing
    if game.deathSeq and game.deathSeq.active then
        local ds = game.deathSeq
        -- draw fade-to-black if in fade or text_fade
        if ds.fade and ds.fade > 0 then
            love.graphics.setColor(0, 0, 0, math.min(1, ds.fade))
            love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
            love.graphics.setColor(1, 1, 1)
        end

        if ds.phase == "text_fade" then
            local alpha = ds.textAlpha or 0
            local w, h = love.graphics.getDimensions()
            local fontLarge = (game.fonts and game.fonts.deathLarge) or love.graphics.getFont()
            love.graphics.setFont(fontLarge)
            love.graphics.setColor(1, 0, 0, alpha)
            love.graphics.printf("DEATH IS CALLING...\nwill you answer?", 0, h * 0.40, w, "center")
            love.graphics.setColor(1, 1, 1)

            -- the DIED text has fully appeared, show smaller restart hint
            if (ds.textAlpha or 0) >= 1 then
                local fontSmall = (game.fonts and game.fonts.deathSmall) or love.graphics.getFont()
                love.graphics.setFont(fontSmall)
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.printf("Press SPACE to restart", 0, h * 0.56, w, "center")
                love.graphics.setColor(1, 1, 1)
            end

            -- restore default font for other UI
            if game.fonts and game.fonts.default then love.graphics.setFont(game.fonts.default) end
        end
    end

    -- debug UI overlay last so it stays visible over death screens
    if game.debug then
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
        love.graphics.print(string.format("Camera: (%.0f, %.0f) Scale: %.2f | Tiles: %s", 
            Renderer.camera.x, Renderer.camera.y, Renderer.camera.scale,
            game.maze and "OK" or "NONE"), 20, 120)

        -- audio debug info
        local ay = 140
        local ax = 20
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Audio:", ax, ay)
        ay = ay + 18
        -- death_intro
        local introPlaying = false
        local introVol = "-"
        if game.sounds and game.sounds.death_intro then
            local ok, p = pcall(function() return game.sounds.death_intro:isPlaying() end)
            if ok and p then introPlaying = true end
            local ok2, v = pcall(function() return game.sounds.death_intro:getVolume() end)
            if ok2 then introVol = string.format("%.2f", v) end
        else
            introVol = "(missing)"
        end
        love.graphics.print(string.format(" intro: playing=%s vol=%s", tostring(introPlaying), introVol), ax, ay)
        ay = ay + 16
        -- death_bells
        local bellsPlaying = false
        local bellsVol = "-"
        if game.sounds and game.sounds.death_bells then
            local ok, p = pcall(function() return game.sounds.death_bells:isPlaying() end)
            if ok and p then bellsPlaying = true end
            local ok2, v = pcall(function() return game.sounds.death_bells:getVolume() end)
            if ok2 then bellsVol = string.format("%.2f", v) end
        else
            bellsVol = "(missing)"
        end
        love.graphics.print(string.format(" bells: playing=%s vol=%s", tostring(bellsPlaying), bellsVol), ax, ay)

        -- additional audio status
        ay = ay + 18
        local dmgCount = (game.sounds and game.sounds.damage) and #game.sounds.damage or 0
        love.graphics.print(string.format("Damage sounds: %d", dmgCount), 20, ay)
        ay = ay + 16

        local function srcStatus(src)
            if not src then return "missing" end
            local okPlaying, isPlaying = pcall(function() return src:isPlaying() end)
            local okVol, vol = pcall(function() return src:getVolume() end)
            return string.format("loaded | playing=%s | vol=%s", (okPlaying and tostring(isPlaying) or "?"), (okVol and string.format("%.2f", vol) or "?"))
        end

        love.graphics.print("death_intro: " .. srcStatus(game.sounds and game.sounds.death_intro), 20, ay)
        ay = ay + 16
        love.graphics.print("death_bells: " .. srcStatus(game.sounds and game.sounds.death_bells), 20, ay)
        ay = ay + 18

        --  FPS
        love.graphics.setColor(0, 1, 0)
        love.graphics.print("FPS: " .. love.timer.getFPS(), 20, love.graphics.getHeight() - 30)
        love.graphics.setColor(1, 1, 1)
    end
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "space" then
        -- if in death text phase restart the game
        if game.deathSeq and game.deathSeq.active and game.deathSeq.phase == "text_fade" then
            -- stop any death sounds
            if game.sounds and game.sounds.death_bells then
                game.sounds.death_bells:stop()
            end
            if game.sounds and game.sounds.death_intro then
                game.sounds.death_intro:stop()
            end
            -- reset timeScale and deathSeq, reset level counter and regenerate maze
            game.timeScale = 1.0
            game.deathSeq = { active = false, phase = nil, timer = 0, fade = 0, textAlpha = 0 }
            game.currentLevel = 1
            game.transitioning = false
            game.transitionAlpha = 0
            generateNewMaze()
            return
        end
    elseif key == "f3" then
        game.debug = not game.debug
        print(string.format("Debug mode: %s", game.debug and "ON" or "OFF"))
    elseif key == "n" then
        generateNewMaze()
    elseif key == "f" then
        local screenWidth, screenHeight = love.graphics.getDimensions()
        Renderer.fitMazeToScreen(game.maze, screenWidth, screenHeight)
    elseif key == "r" then
        -- regenerate with same seed
        print("\n--- Regenerating maze with seed: " .. game.seed .. " ---")
        game.maze = MazeGenerator.generate(game.mazeWidth, game.mazeHeight, game.seed)
        
        -- respawn player at first valid tile
        local playerSpawnX, playerSpawnY = nil, nil
        for y = 1, game.maze.height do
            for x = 1, game.maze.width do
                local tile = game.maze.tiles[y][x]
                if tile.tileType ~= "empty" then
                    playerSpawnX = x
                    playerSpawnY = y
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
    -- recenter camera when window is resized
    Renderer.centerCamera(game.maze, w, h)
end
