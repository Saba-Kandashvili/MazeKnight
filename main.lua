-- MazeKnight - Main Game File
-- A procedural maze explorer using Wave Function Collapse

local MazeGenerator = require("src.maze_generator")
local Renderer = require("src.renderer")
local Enemy = require("src.enemy")
local Player = require("src.player")

-- Simple logger: writes to stdout (if available) and appends to `game.log` for troubleshooting
local function log(...)
    local parts = {}
    for i = 1, select('#', ...) do
        parts[#parts+1] = tostring(select(i, ...))
    end
    local line = table.concat(parts, " ")
    -- Try stdout (may not be visible if running without console)
    pcall(function()
        io.stdout:write(line .. "\n")
        io.stdout:flush()
    end)
    -- Append to log file so output is always available
    pcall(function()
        local f = io.open("game.log", "a")
        if f then
            f:write(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. line .. "\n")
            f:close()
        end
    end)
end

-- Game state
local game = {
    maze = nil,
    seed = nil,
    mazeWidth = 10,
    mazeHeight = 10,
    debug = true,
    enemies = {},
    player = nil,
    showingMazeOverview = false,
    savedCamera = { x = 0, y = 0, scale = 1 },  -- Store camera state when showing overview
    finishTileX = nil,  -- Finish tile coordinates
    finishTileY = nil,
    -- Level transition
    transitioning = false,
    transitionAlpha = 0,
    transitionState = "none",  -- "none", "fade_out", "fade_in"
    transitionSpeed = 2.0,  -- How fast the fade happens
    currentLevel = 1,
    -- Darkness/Vision settings
    visionRadius = 200,  -- Radius in pixels of the visible area around player
    darknessAlpha = 0.85  -- How dark the fog is (0 = invisible, 1 = completely black)
}

-- Safe volume-set helper (file-scope) so update/draw can call it
local function setSrcVolume(label, src, v)
    if not src then
        log(string.format("[vol] %s: source missing, cannot set volume to %.2f", label, tonumber(v) or 0))
        return
    end
    local ok, err = pcall(function() src:setVolume(v) end)
    if not ok then
        log(string.format("[vol] %s: setVolume failed: %s", label, tostring(err)))
    end
    -- Log the attempt (this will show repeated fades)
    log(string.format("[vol] %s: setVolume=%.2f src=%s", label, tonumber(v) or 0, tostring(src)))
end

function love.load()
    print("=== MazeKnight Starting ===")
    print("Love2D Version: " .. love.getVersion())
    
    -- Open console on Windows for debugging
    if love.system.getOS() == "Windows" then
        io.stdout:setvbuf("no")
    end
    
    -- Set up graphics
    love.graphics.setBackgroundColor(0.05, 0.05, 0.05)
    love.graphics.setDefaultFilter("nearest", "nearest")  -- Pixel art style
    
    -- Initialize renderer
    Renderer.init()
    -- Create global darkness shader (used for gradient overlay)
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
    
    -- Generate initial maze
    generateNewMaze()
    
    -- Load damage and death sounds for player feedback
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

    

    -- Damage flash timer (screen red flash when player hurt)
    game.damageFlash = 0
    game.damageFlashDuration = 0.22

    -- Time scale for slow-motion effects (1.0 = normal)
    game.timeScale = 1.0
    -- Death sequence state
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
    -- Use high-resolution time to ensure unique seeds even when called rapidly
    game.seed = math.floor(love.timer.getTime() * 1000)  -- Milliseconds since start
    print("\n--- Generating new maze ---")
    
    -- Generate maze using the DLL
    game.maze = MazeGenerator.generate(game.mazeWidth, game.mazeHeight, game.seed)
    
    -- Find crossroads near the edges for player spawn
    local TileMapper = require("src.tile_mapper")
    local PF = TileMapper.PrefabCodes
    local edgeCrossroads = {}
    local edgeThreshold = 3  -- How far from edge to consider "near edge"
    
    for y = 1, game.maze.height do
        for x = 1, game.maze.width do
            local tile = game.maze.tiles[y][x]
            -- Check if it's a crossroad (Normal_X_Corridor or Special_X_Corridor)
            if tile.code == PF.Normal_X_Corridor or tile.code == PF.Special_X_Corridor then
                -- Check if near any edge
                local nearEdge = (x <= edgeThreshold or x > game.maze.width - edgeThreshold or
                                 y <= edgeThreshold or y > game.maze.height - edgeThreshold)
                if nearEdge then
                    table.insert(edgeCrossroads, {x = x, y = y})
                end
            end
        end
    end
    
    -- Create player at random edge crossroad (or fallback to any valid tile)
    local playerSpawnX, playerSpawnY = nil, nil
    if #edgeCrossroads > 0 then
        local spawnTile = edgeCrossroads[math.random(1, #edgeCrossroads)]
        playerSpawnX = spawnTile.x
        playerSpawnY = spawnTile.y
        print(string.format("Player spawned at edge crossroad (%d, %d)", playerSpawnX, playerSpawnY))
    else
        -- Fallback: find any valid tile
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
    
    -- Create player and mark spawn tile
    if playerSpawnX then
        game.player = Player.new(playerSpawnX, playerSpawnY, game.maze)
        -- Mark the spawn tile so it renders with S.png instead of X.png
        game.maze.tiles[playerSpawnY][playerSpawnX].isSpawn = true
        
        -- Find finish tile at opposite edge from spawn
        -- Determine which edge the spawn is on and calculate center point of opposite edge
        local spawnOnLeft = playerSpawnX <= edgeThreshold
        local spawnOnRight = playerSpawnX > game.maze.width - edgeThreshold
        local spawnOnTop = playerSpawnY <= edgeThreshold
        local spawnOnBottom = playerSpawnY > game.maze.height - edgeThreshold
        
        -- Determine target edge position
        local targetX, targetY
        if spawnOnLeft then
            targetX = game.maze.width  -- Right edge
            targetY = game.maze.height / 2
        elseif spawnOnRight then
            targetX = 1  -- Left edge
            targetY = game.maze.height / 2
        elseif spawnOnTop then
            targetX = game.maze.width / 2
            targetY = game.maze.height  -- Bottom edge
        elseif spawnOnBottom then
            targetX = game.maze.width / 2
            targetY = 1  -- Top edge
        else
            -- Spawn in middle, choose any edge
            targetX = game.maze.width
            targetY = game.maze.height / 2
        end
        
        -- Find all crossroads and choose the one closest to the target edge position
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
        
        -- Choose the crossroad closest to the target edge position
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
    
    -- Spawn enemies at random valid tiles
    game.enemies = {}
    local numEnemies = 3  -- Spawn 3 enemies
    
    -- Find all valid tiles for spawning
    local validSpawnTiles = {}
    for y = 1, game.maze.height do
        for x = 1, game.maze.width do
            local tile = game.maze.tiles[y][x]
            if tile.tileType ~= "empty" then
                table.insert(validSpawnTiles, {x = x, y = y})
            end
        end
    end
    
    -- Spawn enemies at random locations
    for i = 1, math.min(numEnemies, #validSpawnTiles) do
        local spawnTile = validSpawnTiles[math.random(1, #validSpawnTiles)]
        local enemy = Enemy.new(spawnTile.x, spawnTile.y, game.maze)
        table.insert(game.enemies, enemy)
    end
    
    print(string.format("Spawned %d enemies", #game.enemies))
    
    -- Set camera to follow player instead of fitting maze to screen
    if game.player then
        local screenWidth, screenHeight = love.graphics.getDimensions()
        Renderer.camera.scale = 0.8  -- Good zoom level for gameplay
        Renderer.camera.x = game.player.pixelX - screenWidth / (2 * Renderer.camera.scale)
        Renderer.camera.y = game.player.pixelY - screenHeight / (2 * Renderer.camera.scale)
    end
    
    print("--- Maze ready ---\n")
end

function love.update(dt)
    -- Apply global time scale for slow-motion effects
    local timeScale = game.timeScale or 1.0
    local scaledDt = dt * timeScale

    -- Update player (use scaled dt so animations/movement slow during sequences)
    if game.player then
        game.player:update(scaledDt)
        
        -- Check if player reached finish tile center (1,1)
        if game.finishTileX and game.finishTileY and not game.transitioning then
            local finishSubX = (game.finishTileX - 1) * 3 + 2  -- Center of finish tile in sub-grid (1,1 = index 2)
            local finishSubY = (game.finishTileY - 1) * 3 + 2
            
            if game.player.gridX == finishSubX and game.player.gridY == finishSubY then
                print(string.format("\n=== LEVEL %d COMPLETE! ===", game.currentLevel))
                print(string.format("Player at (%d, %d), Finish at (%d, %d)", 
                    game.player.gridX, game.player.gridY, finishSubX, finishSubY))
                game.transitioning = true
                game.transitionState = "fade_out"
                game.transitionAlpha = 0
            end
        end
        
        -- Handle level transition
        if game.transitioning then
            if game.transitionState == "fade_out" then
                game.transitionAlpha = game.transitionAlpha + (dt * game.transitionSpeed)
                if game.transitionAlpha >= 1 then
                    game.transitionAlpha = 1
                    -- Screen is fully black, generate new level
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
                    print("Transition complete!\n")
                end
            end
        end
        
        -- Debug mode: Show entire maze when backspace is held
        if game.debug and love.keyboard.isDown("backspace") then
            if not game.showingMazeOverview then
                -- Save current camera state
                game.savedCamera.x = Renderer.camera.x
                game.savedCamera.y = Renderer.camera.y
                game.savedCamera.scale = Renderer.camera.scale
                game.showingMazeOverview = true
                    Renderer.showingOverview = true
                
                -- Calculate scale to fit entire maze
                local screenWidth, screenHeight = love.graphics.getDimensions()
                local mazePixelWidth = game.maze.width * Renderer.tileSize
                local mazePixelHeight = game.maze.height * Renderer.tileSize
                
                -- Calculate scale to fit the entire maze with padding
                local scaleX = screenWidth / mazePixelWidth
                local scaleY = screenHeight / mazePixelHeight
                Renderer.camera.scale = math.min(scaleX, scaleY) * 0.95  -- 0.95 for some padding
                
                -- Position camera so (0,0) of maze is visible and maze is centered
                local scaledScreenWidth = screenWidth / Renderer.camera.scale
                local scaledScreenHeight = screenHeight / Renderer.camera.scale
                Renderer.camera.x = -(scaledScreenWidth - mazePixelWidth) / 2
                Renderer.camera.y = -(scaledScreenHeight - mazePixelHeight) / 2
            end
        else
            if game.showingMazeOverview then
                -- Restore camera to follow player
                Renderer.camera.x = game.savedCamera.x
                Renderer.camera.y = game.savedCamera.y
                Renderer.camera.scale = game.savedCamera.scale
                game.showingMazeOverview = false
                Renderer.showingOverview = false
            end
        end
    end
    
    -- Update enemies (use scaled dt)
    for _, enemy in ipairs(game.enemies) do
        enemy:update(scaledDt)
    end

    -- Check collisions between enemies and player (simple proximity check)
    if game.player then
        for _, enemy in ipairs(game.enemies) do
            if not game.player.isDead and not game.player.isTakingDamage then
                local dx = enemy.pixelX - game.player.pixelX
                local dy = enemy.pixelY - game.player.pixelY
                local dist = math.sqrt(dx*dx + dy*dy)
                local hitThreshold = (enemy.radius or 12) + 12
                if dist <= hitThreshold and (not enemy.damageCooldown or enemy.damageCooldown <= 0) then
                    -- Apply damage: 20 (20% of 100)
                    game.player:takeDamage(20)

                    -- Start damage flash and play random damage sound
                    game.damageFlash = game.damageFlashDuration
                    if game.sounds and game.sounds.damage and #game.sounds.damage > 0 then
                        local idx = math.random(1, #game.sounds.damage)
                        local src = game.sounds.damage[idx]
                        if src then
                            src:stop()
                            src:play()
                        end
                    end

                    -- Give this enemy a short cooldown so it doesn't hit repeatedly while overlapping
                    enemy.damageCooldown = 0.48
                end
            end
        end
    end

    -- Decrease damage flash timer
    if game.damageFlash and game.damageFlash > 0 then
        game.damageFlash = game.damageFlash - dt
        if game.damageFlash < 0 then game.damageFlash = 0 end
    end

    -- Death sequence handling (real-time dt)
    if game.player and game.player.isDead then
        local ds = game.deathSeq
        if not ds.active then
                -- Start death sequence: slow down time, zoom camera, play intro
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
                -- Audio intro control: get duration & fade settings
                ds.introFadeIn = 0.5
                ds.introFadeOut = 0.6
                if game.sounds and game.sounds.death_intro then
                    local src = game.sounds.death_intro
                    local ok, dur = pcall(function() return src:getDuration() end)
                    ds.introDuration = (ok and dur) or 2.0
                    -- start intro with volume 0 and play
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
                    -- (no fade-out here; the intro file contains its own fade-out)
                end

                -- When both death animation and intro finish, proceed to fade
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

                    -- Start death_bells immediately as fade begins (with fade-in)
                    if game.sounds and game.sounds.death_bells then
                        local bell = game.sounds.death_bells
                        local ok, err = pcall(function()
                            bell:stop()
                            bell:setLooping(false)
                            -- Start bells immediately at full volume (play once)
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
                    -- Stop intro if still playing
                    if ds.introPlaying and game.sounds and game.sounds.death_intro then
                        local src = game.sounds.death_intro
                        src:stop()
                        ds.introPlaying = false
                    end
                    -- death_bells already started when fade began; do not restart here
                end

                -- Bells are started at full volume; no per-frame fade applied here.

            elseif ds.phase == "text_fade" then
                ds.timer = ds.timer + dt
                ds.textAlpha = math.min(1, ds.timer / ds.textFadeDuration)
                -- keep screen fully faded during text fade
                ds.fade = 1
                game.timeScale = 0.0
            end
        end
    end
    
    -- Zoom controls (+ and -) - disabled during overview
    if not game.showingMazeOverview then
        if love.keyboard.isDown("=") or love.keyboard.isDown("+") then
            Renderer.camera.scale = Renderer.camera.scale * (1 + dt)
        end
        if love.keyboard.isDown("-") then
            Renderer.camera.scale = Renderer.camera.scale * (1 - dt)
            if Renderer.camera.scale < 0.1 then Renderer.camera.scale = 0.1 end
        end
    end
end

function love.draw()
    -- Always center camera on player before drawing (unless showing overview)
    if game.player and not game.showingMazeOverview then
        local screenWidth = love.graphics.getWidth()
        local screenHeight = love.graphics.getHeight()
        Renderer.camera.x = game.player.pixelX - (screenWidth / (2 * Renderer.camera.scale))
        Renderer.camera.y = game.player.pixelY - (screenHeight / (2 * Renderer.camera.scale))
    end
    
    -- Draw the maze and enemies
    Renderer.drawMaze(game.maze, game.enemies, game.player)
    
    -- Draw fade transition overlay
    if game.transitioning and game.transitionAlpha > 0 then
        love.graphics.setColor(0, 0, 0, game.transitionAlpha)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setColor(1, 1, 1)
    end
    
    -- Draw darkness overlay centered on screen center (which is where player is because camera is centered)
    if game.player and not game.showingMazeOverview then
        local screenWidth = love.graphics.getWidth()
        local screenHeight = love.graphics.getHeight()

        -- Player is ALWAYS at screen center because camera is centered on player
        local playerScreenX = screenWidth / 2
        local playerScreenY = screenHeight / 2

        -- If global shader available, use gradient overlay; otherwise fallback to stencil circle
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
            -- Fallback: stencil-based circle (older behavior)
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
    
    -- (debug overlay moved to draw last so it remains visible over death screens)

    -- Draw large bottom health bar for player
    if game.player then
        local sw, sh = love.graphics.getDimensions()
        -- Make the bar a bit smaller: 75% width and slightly shorter height
        local barW = sw * 0.75
        local barH = 28
        local barX = (sw - barW) / 2
        local barY = sh - barH - 12

        -- Background
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", barX, barY, barW, barH, 6, 6)

        -- Health fill
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

        -- Border
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.rectangle("line", barX, barY, barW, barH, 6, 6)
        love.graphics.setColor(1, 1, 1)
    end

    -- Draw damage flash overlay (subtle red) if active
    if game.damageFlash and game.damageFlash > 0 then
        local alpha = (game.damageFlash / (game.damageFlashDuration or 0.22)) * 0.45
        love.graphics.setColor(1, 0, 0, alpha)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setColor(1, 1, 1)
    end

    -- Death sequence drawing: fade and 'You Died' text
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
            love.graphics.setColor(1, 0, 0, alpha)
            local w, h = love.graphics.getDimensions()
            local txt = "YOU DIED"
            local font = love.graphics.getFont()
            local size = (font and font:getHeight()) or 24
            love.graphics.setFont(font)
            local tw = font and font:getWidth(txt) or (string.len(txt) * 12)
            love.graphics.printf(txt, 0, h * 0.45, w, "center")
            love.graphics.setColor(1, 1, 1)
        end
    end

    -- Draw debug UI overlay last so it stays visible over death screens
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

        -- Audio debug info
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

        -- Additional audio status
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

        -- Draw FPS
        love.graphics.setColor(0, 1, 0)
        love.graphics.print("FPS: " .. love.timer.getFPS(), 20, love.graphics.getHeight() - 30)
        love.graphics.setColor(1, 1, 1)
    end
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "space" then
        -- If in death text phase, restart the game
        if game.deathSeq and game.deathSeq.active and game.deathSeq.phase == "text_fade" then
            -- Stop any death sounds
            if game.sounds and game.sounds.death_bells then
                game.sounds.death_bells:stop()
            end
            if game.sounds and game.sounds.death_intro then
                game.sounds.death_intro:stop()
            end
            -- Reset timeScale and deathSeq and regenerate maze
            game.timeScale = 1.0
            game.deathSeq = { active = false, phase = nil, timer = 0, fade = 0, textAlpha = 0 }
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
        -- Regenerate with same seed
        print("\n--- Regenerating maze with seed: " .. game.seed .. " ---")
        game.maze = MazeGenerator.generate(game.mazeWidth, game.mazeHeight, game.seed)
        
        -- Respawn player at first valid tile
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
    -- Recenter camera when window is resized
    Renderer.centerCamera(game.maze, w, h)
end
