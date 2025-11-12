-- MazeKnight - Main Game File
-- A procedural maze explorer using Wave Function Collapse

local MazeGenerator = require("src.maze_generator")
local Renderer = require("src.renderer")
local Enemy = require("src.enemy")

-- Game state
local game = {
    maze = nil,
    seed = nil,
    mazeWidth = 20,
    mazeHeight = 20,
    debug = true,
    enemies = {}
}

function love.load()
    print("=== MazeKnight Starting ===")
    print("Love2D Version: " .. love.getVersion())
    
    -- Set up graphics
    love.graphics.setBackgroundColor(0.05, 0.05, 0.05)
    love.graphics.setDefaultFilter("nearest", "nearest")  -- Pixel art style
    
    -- Initialize renderer
    Renderer.init()
    
    -- Generate initial maze
    generateNewMaze()
    
    print("=== Game Loaded ===")
    print("Press SPACE to generate a new maze")
    print("Press F to fit maze to screen")
    print("Press ESC to quit")
end

function generateNewMaze()
    -- Use high-resolution time to ensure unique seeds even when called rapidly
    game.seed = math.floor(love.timer.getTime() * 1000)  -- Milliseconds since start
    print("\n--- Generating new maze ---")
    
    -- Generate maze using the DLL
    game.maze = MazeGenerator.generate(game.mazeWidth, game.mazeHeight, game.seed)
    
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
    
    -- Fit maze to screen
    local screenWidth, screenHeight = love.graphics.getDimensions()
    Renderer.fitMazeToScreen(game.maze, screenWidth, screenHeight)
    
    print("--- Maze ready ---\n")
end

function love.update(dt)
    -- Update enemies
    for _, enemy in ipairs(game.enemies) do
        enemy:update(dt)
    end
    
    -- Camera controls (arrow keys)
    local moveSpeed = 300 * dt
    
    if love.keyboard.isDown("left") then
        Renderer.camera.x = Renderer.camera.x - moveSpeed
    end
    if love.keyboard.isDown("right") then
        Renderer.camera.x = Renderer.camera.x + moveSpeed
    end
    if love.keyboard.isDown("up") then
        Renderer.camera.y = Renderer.camera.y - moveSpeed
    end
    if love.keyboard.isDown("down") then
        Renderer.camera.y = Renderer.camera.y + moveSpeed
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
    Renderer.drawMaze(game.maze, game.enemies)
    
    -- Draw UI overlay
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 10, 10, 350, 120)
    love.graphics.setColor(1, 1, 1)
    
    love.graphics.print("MazeKnight - Procedural Maze Explorer", 20, 20)
    love.graphics.print(string.format("Maze Size: %dx%d", game.mazeWidth, game.mazeHeight), 20, 40)
    love.graphics.print(string.format("Seed: %d", game.seed or 0), 20, 60)
    love.graphics.print(string.format("Zoom: %.2f", Renderer.camera.scale), 20, 80)
    love.graphics.print("SPACE: New Maze | F: Fit | Arrows: Pan | +/-: Zoom", 20, 100)
    
    -- Draw FPS
    love.graphics.setColor(0, 1, 0)
    love.graphics.print("FPS: " .. love.timer.getFPS(), 20, love.graphics.getHeight() - 30)
    love.graphics.setColor(1, 1, 1)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "space" then
        generateNewMaze()
    elseif key == "f" then
        local screenWidth, screenHeight = love.graphics.getDimensions()
        Renderer.fitMazeToScreen(game.maze, screenWidth, screenHeight)
    elseif key == "r" then
        -- Regenerate with same seed
        print("\n--- Regenerating maze with seed: " .. game.seed .. " ---")
        game.maze = MazeGenerator.generate(game.mazeWidth, game.mazeHeight, game.seed)
    end
end

function love.resize(w, h)
    -- Recenter camera when window is resized
    Renderer.centerCamera(game.maze, w, h)
end
