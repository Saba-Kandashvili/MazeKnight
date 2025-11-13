-- MazeKnight - Main Game File
-- A procedural maze explorer using Wave Function Collapse

local MazeGenerator = require("src.maze_generator")
local Renderer = require("src.renderer")
local Enemy = require("src.enemy")
local Player = require("src.player")

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
    -- Update player
    if game.player then
        game.player:update(dt)
        
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
            
            -- Normal camera follow player (center on player)
            if not game.showingMazeOverview then
                local screenWidth = love.graphics.getWidth()
                local screenHeight = love.graphics.getHeight()
                Renderer.camera.x = game.player.pixelX - (screenWidth / (2 * Renderer.camera.scale))
                Renderer.camera.y = game.player.pixelY - (screenHeight / (2 * Renderer.camera.scale))
            end
        end
    end
    
    -- Update enemies
    for _, enemy in ipairs(game.enemies) do
        enemy:update(dt)
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
    -- Draw the maze and enemies
    Renderer.drawMaze(game.maze, game.enemies, game.player)
    
    -- Draw fade transition overlay
    if game.transitioning and game.transitionAlpha > 0 then
        love.graphics.setColor(0, 0, 0, game.transitionAlpha)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setColor(1, 1, 1)
    end
    
    -- Draw darkness overlay with clear vision circle centered on player
    if game.player and not game.showingMazeOverview then
        local screenWidth = love.graphics.getWidth()
        local screenHeight = love.graphics.getHeight()

        -- Calculate player's position on screen (world to screen coordinates)
        local playerScreenX = (game.player.pixelX - Renderer.camera.x) * Renderer.camera.scale
        local playerScreenY = (game.player.pixelY - Renderer.camera.y) * Renderer.camera.scale

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
    
    -- Draw debug UI overlay (only when debug mode is enabled)
    if game.debug then
        love.graphics.setColor(0, 0, 0, 0.9)
        love.graphics.rectangle("fill", 10, 10, 450, 140)
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
        
        -- Draw FPS
        love.graphics.setColor(0, 1, 0)
        love.graphics.print("FPS: " .. love.timer.getFPS(), 20, love.graphics.getHeight() - 30)
        love.graphics.setColor(1, 1, 1)
    end
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
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
