-- Maze Renderer Module
-- Handles drawing the maze to the screen

local TileMapper = require("src.tile_mapper")

local Renderer = {}
Renderer.tileSize = 64  -- Default tile size (64x64 pixels)
Renderer.tiles = {}     -- Store loaded tile images
Renderer.camera = {
    x = 0,
    y = 0,
    scale = 1.0
}

-- Initialize the renderer and load tile assets
function Renderer.init()
    local TT = TileMapper.TileType
    
    -- Try to load tile images
    -- If they don't exist, we'll create colored rectangles as placeholders
    Renderer.tiles[TT.DEADEND] = Renderer.loadTileImage("D.png")
    Renderer.tiles[TT.STRAIGHT] = Renderer.loadTileImage("I.png")
    Renderer.tiles[TT.CORNER] = Renderer.loadTileImage("L.png")
    Renderer.tiles[TT.T_JUNCTION] = Renderer.loadTileImage("T.png")
    Renderer.tiles[TT.CROSSROAD] = Renderer.loadTileImage("X.png")
    Renderer.tiles[TT.EMPTY] = nil  -- Empty tiles are not drawn
    
    print("Renderer initialized")
end

-- Load a tile image or create a placeholder
function Renderer.loadTileImage(filename)
    local path = "assets/tiles/" .. filename
    local success, image = pcall(love.graphics.newImage, path)
    
    if success then
        print("Loaded tile: " .. filename)
        return image
    else
        print("Could not load tile: " .. filename .. " (using placeholder)")
        return nil  -- Will use colored rectangles instead
    end
end

-- Draw a single tile with rotation
function Renderer.drawTile(tile, x, y, tintColor)
    local image = Renderer.tiles[tile.tileType]
    local rotation = TileMapper.getRotationRadians(tile.rotation)
    
    local drawX = x * Renderer.tileSize
    local drawY = y * Renderer.tileSize
    
    if image then
        -- Apply tint color if specified
        if tintColor then
            love.graphics.setColor(tintColor[1], tintColor[2], tintColor[3])
        end
        
        -- Draw the tile image
        love.graphics.draw(
            image,
            drawX + Renderer.tileSize / 2,
            drawY + Renderer.tileSize / 2,
            rotation,
            1, 1,
            image:getWidth() / 2,
            image:getHeight() / 2
        )
        
        -- Reset color
        love.graphics.setColor(1, 1, 1)
    else
        -- Draw a colored placeholder rectangle
        love.graphics.push()
        love.graphics.translate(drawX + Renderer.tileSize / 2, drawY + Renderer.tileSize / 2)
        love.graphics.rotate(rotation)
        
        -- Set color based on tile type
        local TT = TileMapper.TileType
        if tile.tileType == TT.DEADEND then
            love.graphics.setColor(0.8, 0.2, 0.2)  -- Red
        elseif tile.tileType == TT.STRAIGHT then
            love.graphics.setColor(0.2, 0.8, 0.2)  -- Green
        elseif tile.tileType == TT.CORNER then
            love.graphics.setColor(0.2, 0.2, 0.8)  -- Blue
        elseif tile.tileType == TT.T_JUNCTION then
            love.graphics.setColor(0.8, 0.8, 0.2)  -- Yellow
        elseif tile.tileType == TT.CROSSROAD then
            love.graphics.setColor(0.8, 0.2, 0.8)  -- Magenta
        else
            love.graphics.setColor(0.3, 0.3, 0.3)  -- Gray
        end
        
        -- Draw the rectangle centered at origin
        love.graphics.rectangle("fill", -Renderer.tileSize / 2, -Renderer.tileSize / 2, Renderer.tileSize, Renderer.tileSize)
        
        -- Draw a directional indicator (small triangle pointing "north")
        love.graphics.setColor(1, 1, 1)
        love.graphics.polygon("fill", 0, -20, -8, -10, 8, -10)
        
        love.graphics.pop()
        love.graphics.setColor(1, 1, 1)  -- Reset color
    end
    
    -- Draw grid lines
    love.graphics.setColor(0.5, 0.5, 0.5, 0.3)
    love.graphics.rectangle("line", drawX, drawY, Renderer.tileSize, Renderer.tileSize)
    love.graphics.setColor(1, 1, 1)
end

-- Draw the entire maze
function Renderer.drawMaze(maze, enemies)
    if not maze then return end
    
    love.graphics.push()
    love.graphics.translate(-Renderer.camera.x, -Renderer.camera.y)
    love.graphics.scale(Renderer.camera.scale)
    
    -- Draw background
    love.graphics.setColor(0.1, 0.1, 0.1)
    love.graphics.rectangle(
        "fill",
        0, 0,
        maze.width * Renderer.tileSize,
        maze.height * Renderer.tileSize
    )
    love.graphics.setColor(1, 1, 1)
    
    -- Draw all tiles
    for y = 1, maze.height do
        for x = 1, maze.width do
            local tile = maze.tiles[y][x]
            if tile and tile.tileType ~= TileMapper.TileType.EMPTY then
                -- Determine tint color for spawn and goal tiles
                local tintColor = nil
                
                -- Spawn tile: RED
                if maze.spawnTile and tile.x == maze.spawnTile.x and tile.y == maze.spawnTile.y then
                    tintColor = {1.0, 0.2, 0.2}  -- Bright red
                -- Goal tile: GREEN
                elseif maze.goalTile and tile.x == maze.goalTile.x and tile.y == maze.goalTile.y then
                    tintColor = {0.2, 1.0, 0.2}  -- Bright green
                end
                
                Renderer.drawTile(tile, x - 1, y - 1, tintColor)  -- -1 because screen coordinates start at 0
            end
        end
    end
    
    -- Draw enemies
    if enemies then
        for _, enemy in ipairs(enemies) do
            enemy:draw()
        end
    end
    
    love.graphics.pop()
end

-- Update camera to center on maze
function Renderer.centerCamera(maze, screenWidth, screenHeight)
    if not maze then return end
    
    local mazePixelWidth = maze.width * Renderer.tileSize
    local mazePixelHeight = maze.height * Renderer.tileSize
    
    Renderer.camera.x = (mazePixelWidth * Renderer.camera.scale - screenWidth) / 2
    Renderer.camera.y = (mazePixelHeight * Renderer.camera.scale - screenHeight) / 2
end

-- Adjust camera zoom to fit maze on screen
function Renderer.fitMazeToScreen(maze, screenWidth, screenHeight)
    if not maze then return end
    
    local mazePixelWidth = maze.width * Renderer.tileSize
    local mazePixelHeight = maze.height * Renderer.tileSize
    
    local scaleX = screenWidth / mazePixelWidth
    local scaleY = screenHeight / mazePixelHeight
    
    Renderer.camera.scale = math.min(scaleX, scaleY) * 0.9  -- 90% to add padding
    Renderer.centerCamera(maze, screenWidth, screenHeight)
end

return Renderer
