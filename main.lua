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
    mazeWidth = 20,
    mazeHeight = 20,
    debug = true,
    enemies = {},
    player = nil
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
    
    -- Find a valid starting position for the player
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
    
    -- Create player
    if playerSpawnX then
        game.player = Player.new(playerSpawnX, playerSpawnY, game.maze)
        print(string.format("Player spawned at (%d, %d)", playerSpawnX, playerSpawnY))
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
        
        -- Center camera on player
        local ts = Renderer.tileSize
        Renderer.camera.x = game.player.pixelX - love.graphics.getWidth() / (2 * Renderer.camera.scale)
        Renderer.camera.y = game.player.pixelY - love.graphics.getHeight() / (2 * Renderer.camera.scale)
    end
    
    -- Update enemies
    for _, enemy in ipairs(game.enemies) do
        enemy:update(dt)
    end
    
    -- Zoom controls (+ and -)
    if love.keyboard.isDown("=") or love.keyboard.isDown("+") then
        Renderer.camera.scale = Renderer.camera.scale * (1 + dt)
    end
    if love.keyboard.isDown("-") then
        Renderer.camera.scale = Renderer.camera.scale * (1 - dt)
        if Renderer.camera.scale < 0.1 then Renderer.camera.scale = 0.1 end
    end
end

function love.draw()
    -- Draw the maze and enemies
    Renderer.drawMaze(game.maze, game.enemies, game.player)
    
    -- Draw UI overlay
    love.graphics.setColor(0, 0, 0, 0.9)
    love.graphics.rectangle("fill", 10, 10, 450, 140)
    love.graphics.setColor(1, 1, 1)
    
    love.graphics.print("MazeKnight - Procedural Maze Explorer", 20, 20)
    love.graphics.print(string.format("Maze Size: %dx%d", game.mazeWidth, game.mazeHeight), 20, 40)
    love.graphics.print(string.format("Seed: %d", game.seed or 0), 20, 60)
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

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
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
