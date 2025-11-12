-- Maze Renderer Module
-- Handles drawing the maze to the screen

local TileMapper = require("src.tile_mapper")

local Renderer = {}
Renderer.tileSize = 96
Renderer.tiles = {}
Renderer.camera = {
    x = 0,
    y = 0,
    scale = 1.0
}

function Renderer.init()
    local TT = TileMapper.TileType
    
    Renderer.tiles[TT.DEADEND] = Renderer.loadTileImage("D.png")
    Renderer.tiles[TT.STRAIGHT] = Renderer.loadTileImage("I.png")
    Renderer.tiles[TT.CORNER] = Renderer.loadTileImage("L.png")
    Renderer.tiles[TT.T_JUNCTION] = Renderer.loadTileImage("T.png")
    Renderer.tiles[TT.CROSSROAD] = Renderer.loadTileImage("X.png")
    Renderer.tiles[TT.EMPTY] = Renderer.loadTileImage("E.png")
    
    print("Renderer initialized")
end

function Renderer.loadTileImage(filename)
    local path = "assets/tiles/" .. filename
    local success, image = pcall(love.graphics.newImage, path)
    
    if success then
        print("Loaded tile: " .. filename)
        return image
    else
        print("Could not load tile: " .. filename .. " (using placeholder)")
        return nil
    end
end

function Renderer.drawTile(tile, x, y, tintColor)
    local image = Renderer.tiles[tile.tileType]
    local rotation = TileMapper.getRotationRadians(tile.rotation)
    
    local drawX = x * Renderer.tileSize
    local drawY = y * Renderer.tileSize
    
    if image then
        if tintColor then
            love.graphics.setColor(tintColor[1], tintColor[2], tintColor[3])
        end
        
        love.graphics.draw(
            image,
            drawX + Renderer.tileSize / 2,
            drawY + Renderer.tileSize / 2,
            rotation,
            1, 1,
            image:getWidth() / 2,
            image:getHeight() / 2
        )
        
        love.graphics.setColor(1, 1, 1)
    else
        love.graphics.push()
        love.graphics.translate(drawX + Renderer.tileSize / 2, drawY + Renderer.tileSize / 2)
        love.graphics.rotate(rotation)
        
        local TT = TileMapper.TileType
        if tile.tileType == TT.DEADEND then
            love.graphics.setColor(0.8, 0.2, 0.2)
        elseif tile.tileType == TT.STRAIGHT then
            love.graphics.setColor(0.2, 0.8, 0.2)
        elseif tile.tileType == TT.CORNER then
            love.graphics.setColor(0.2, 0.2, 0.8)
        elseif tile.tileType == TT.T_JUNCTION then
            love.graphics.setColor(0.8, 0.8, 0.2)
        elseif tile.tileType == TT.CROSSROAD then
            love.graphics.setColor(0.8, 0.2, 0.8)
        else
            love.graphics.setColor(0.3, 0.3, 0.3)
        end
        
        love.graphics.rectangle("fill", -Renderer.tileSize / 2, -Renderer.tileSize / 2, Renderer.tileSize, Renderer.tileSize)
        
        love.graphics.setColor(1, 1, 1)
        love.graphics.polygon("fill", 0, -20, -8, -10, 8, -10)
        
        love.graphics.pop()
        love.graphics.setColor(1, 1, 1)
    end
    
    love.graphics.setColor(0.5, 0.5, 0.5, 0.3)
    love.graphics.rectangle("line", drawX, drawY, Renderer.tileSize, Renderer.tileSize)
    love.graphics.setColor(1, 1, 1)
end

function Renderer.drawMaze(maze, enemies, player)
    love.graphics.push()
    love.graphics.scale(Renderer.camera.scale, Renderer.camera.scale)
    love.graphics.translate(-Renderer.camera.x, -Renderer.camera.y)

    if maze then
        for y = 1, maze.height do
            for x = 1, maze.width do
                local tile = maze.tiles[y][x]
                if tile then
                    Renderer.drawTile(tile, x - 1, y - 1)
                end
            end
        end
    end

    if enemies then
        for _, enemy in ipairs(enemies) do
            enemy:draw()
        end
    end

    if player then
        player:draw()
    end

    love.graphics.pop()
end

function Renderer.drawMazeWithPlayer(maze, enemies, player, spritesheet, quads)
    if not maze then return end
    
    love.graphics.push()
    love.graphics.translate(-Renderer.camera.x, -Renderer.camera.y)
    love.graphics.scale(Renderer.camera.scale)
    
    love.graphics.setColor(0.1, 0.1, 0.1)
    love.graphics.rectangle(
        "fill",
        0, 0,
        maze.width * Renderer.tileSize,
        maze.height * Renderer.tileSize
    )
    love.graphics.setColor(1, 1, 1)
    
    for y = 1, maze.height do
        for x = 1, maze.width do
            local tile = maze.tiles[y][x]
            if tile then
                local tintColor = nil
                if maze.spawnTile and tile.x == maze.spawnTile.x and tile.y == maze.spawnTile.y then
                    tintColor = {1.0, 0.2, 0.2}
                elseif maze.goalTile and tile.x == maze.goalTile.x and tile.y == maze.goalTile.y then
                    tintColor = {0.2, 1.0, 0.2}
                end
                Renderer.drawTile(tile, x - 1, y - 1, tintColor)
            end
        end
    end
    
    if enemies then
        for _, enemy in ipairs(enemies) do
            enemy:draw()
        end
    end
    
    if player then
        player:draw(spritesheet, quads)
    end
    
    love.graphics.pop()
end

function Renderer.centerCamera(maze, screenWidth, screenHeight)
    if not maze then return end
    
    local mazePixelWidth = maze.width * Renderer.tileSize
    local mazePixelHeight = maze.height * Renderer.tileSize
    
    Renderer.camera.x = (mazePixelWidth * Renderer.camera.scale - screenWidth) / 2
    Renderer.camera.y = (mazePixelHeight * Renderer.camera.scale - screenHeight) / 2
end

function Renderer.fitMazeToScreen(maze, screenWidth, screenHeight)
    if not maze then return end
    
    local mazePixelWidth = maze.width * Renderer.tileSize
    local mazePixelHeight = maze.height * Renderer.tileSize
    
    local scaleX = screenWidth / mazePixelWidth
    local scaleY = screenHeight / mazePixelHeight
    
    Renderer.camera.scale = math.min(scaleX, scaleY) * 0.9
    Renderer.centerCamera(maze, screenWidth, screenHeight)
end

return Renderer