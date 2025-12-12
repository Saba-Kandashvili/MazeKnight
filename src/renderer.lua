local TileMapper = require("src.tile_mapper")

local Renderer = {}
Renderer.tileSize = 96
Renderer.tiles = {}
Renderer.camera = {
    x = 0,
    y = 0,
    scale = 1.0
}
Renderer.showingOverview = false
Renderer.showGrid = false

function Renderer.init()
    local TT = TileMapper.TileType

    Renderer.tiles[TT.DEADEND] = Renderer.loadTileImage("D.png")
    Renderer.tiles[TT.STRAIGHT] = Renderer.loadTileImage("I.png")
    Renderer.tiles[TT.CORNER] = Renderer.loadTileImage("L.png")
    Renderer.tiles[TT.T_JUNCTION] = Renderer.loadTileImage("T.png")
    Renderer.tiles[TT.CROSSROAD] = Renderer.loadTileImage("X.png")
    Renderer.tiles.SPAWN = Renderer.loadTileImage("S.png")
    Renderer.tiles.FINISH = Renderer.loadTileImage("F.png")
    Renderer.tiles[TT.EMPTY] = Renderer.loadTileImage("E.png")

    print("Renderer initialized")

    -- 1. Load Enemy (Bat)
    local enemyPath = "assets/enemy/bat.png"
    local ok, enemyImage = pcall(love.graphics.newImage, enemyPath)
    if ok and enemyImage then
        Renderer.enemy = {}
        Renderer.enemy.spritesheet = enemyImage
        if enemyImage.setFilter then enemyImage:setFilter("nearest", "nearest") end

        -- Bat is 32x32 frames
        Renderer.enemy.frameSize = 32
        Renderer.enemy.quads = {}
        local tile = Renderer.enemy.frameSize
        local w, h = enemyImage:getWidth(), enemyImage:getHeight()
        for row = 1, 4 do
            Renderer.enemy.quads[row] = {}
            for col = 1, 4 do
                Renderer.enemy.quads[row][col] = love.graphics.newQuad(
                    (col - 1) * tile, (row - 1) * tile, tile, tile, w, h
                )
            end
        end
        Renderer.enemy.scale = Renderer.tileSize / Renderer.enemy.frameSize
        print("Loaded enemy spritesheet: " .. enemyPath)
    else
        print("Warning: could not load enemy spritesheet: " .. enemyPath)
        Renderer.enemy = nil
    end

    -- 2. Load Seeker (New 64x64 sheet)
    local seekerPath = "assets/enemy/seeker.png"
    local skOk, seekerImage = pcall(love.graphics.newImage, seekerPath)
    if skOk and seekerImage then
        Renderer.seeker = {}
        Renderer.seeker.spritesheet = seekerImage
        if seekerImage.setFilter then seekerImage:setFilter("nearest", "nearest") end

        -- Auto-detect frame size.
        -- If image is 64px wide and has 4 cols, frame is 16px.
        Renderer.seeker.frameSize = seekerImage:getWidth() / 4

        Renderer.seeker.quads = {}
        local tile = Renderer.seeker.frameSize
        local w, h = seekerImage:getWidth(), seekerImage:getHeight()

        -- Create quads for 4 rows x 4 cols
        for row = 1, 4 do
            Renderer.seeker.quads[row] = {}
            for col = 1, 4 do
                Renderer.seeker.quads[row][col] = love.graphics.newQuad(
                    (col - 1) * tile, (row - 1) * tile, tile, tile, w, h
                )
            end
        end

        -- Calculate scale to match the tile size (makes the 16px sprite look big)
        Renderer.seeker.scale = Renderer.tileSize / Renderer.seeker.frameSize
        print(string.format("Loaded seeker: %s (Frame: %dx%d)", seekerPath, tile, tile))
    else
        Renderer.seeker = nil
        print("Warning: could not load seeker spritesheet: " .. seekerPath)
    end
end

function Renderer.loadTileImage(filename)
    local path = "assets/tiles/" .. filename
    local success, image = pcall(love.graphics.newImage, path)
    if success then
        if image.setFilter then image:setFilter("nearest", "nearest") end
        return image
    else
        print("Could not load tile: " .. filename)
        return nil
    end
end

function Renderer.drawTile(tile, x, y, tintColor)
    local image = Renderer.tiles[tile.tileType]
    if tile.isSpawn then image = Renderer.tiles.SPAWN
    elseif tile.isFinish then image = Renderer.tiles.FINISH end

    local rotation = TileMapper.getRotationRadians(tile.rotation)
    local drawX = x * Renderer.tileSize
    local drawY = y * Renderer.tileSize

    if image then
        if tintColor then love.graphics.setColor(tintColor) end
        love.graphics.draw(image, drawX + Renderer.tileSize/2, drawY + Renderer.tileSize/2, rotation, 1, 1, image:getWidth()/2, image:getHeight()/2)
        love.graphics.setColor(1, 1, 1)
    end

    -- Debug Grid
    love.graphics.setColor(0.5, 0.5, 0.5, 0.3)
    if Renderer.showGrid then
        love.graphics.rectangle("line", drawX, drawY, Renderer.tileSize, Renderer.tileSize)
    end
    love.graphics.setColor(1, 1, 1)
end

-- Modified to accept particles
function Renderer.drawMaze(maze, enemies, player, particles)
    if not maze then return end
    love.graphics.push()

    if player and not Renderer.showingOverview then
        local sw, sh = love.graphics.getDimensions()
        love.graphics.translate(sw/2, sh/2)
        love.graphics.scale(Renderer.camera.scale, Renderer.camera.scale)
        love.graphics.translate(-math.floor(player.pixelX + 0.5), -math.floor(player.pixelY + 0.5))
    else
        love.graphics.translate(-math.floor(Renderer.camera.x + 0.5), -math.floor(Renderer.camera.y + 0.5))
        love.graphics.scale(Renderer.camera.scale, Renderer.camera.scale)
    end

    -- Draw tiles
    for y = 1, maze.height do
        for x = 1, maze.width do
            local tile = maze.tiles[y][x]
            if tile then
                Renderer.drawTile(tile, x - 1, y - 1)
                if tile.isFinish then
                    Renderer._finishCenterX = (x - 1) * Renderer.tileSize + Renderer.tileSize / 2
                    Renderer._finishCenterY = (y - 1) * Renderer.tileSize + Renderer.tileSize / 2
                end
            end
        end
    end

    -- Draw enemies
    if enemies then
        for _, enemy in ipairs(enemies) do enemy:draw() end
    end

    -- Draw particles (if any)
    if particles then
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(particles, 0, 0)
    end

    -- Draw player
    local playerScreenX, playerScreenY
    if player then
        player:draw()
        playerScreenX = player.pixelX
        playerScreenY = player.pixelY - 8
    end

    -- Draw finish glow
    if Renderer._finishCenterX and Renderer._finishCenterY and player then
        local fx, fy = Renderer._finishCenterX, Renderer._finishCenterY
        local dist = math.sqrt((fx-player.pixelX)^2 + (fy-player.pixelY)^2)
        if dist <= 270 then -- hardcoded radius logic approx
             love.graphics.setBlendMode("add")
             love.graphics.setColor(1, 0.6, 0.2, 0.3)
             love.graphics.circle("fill", fx, fy, Renderer.tileSize, 32)
             love.graphics.setBlendMode("alpha")
             love.graphics.setColor(1, 1, 1)
        end
    end

    love.graphics.pop()
    return playerScreenX, playerScreenY
end

function Renderer.centerCamera(maze, screenWidth, screenHeight)
    -- Simplified for brevity
end

function Renderer.fitMazeToScreen(maze, screenWidth, screenHeight)
    local mazePixelWidth = maze.width * Renderer.tileSize
    local mazePixelHeight = maze.height * Renderer.tileSize
    local scaleX = screenWidth / mazePixelWidth
    local scaleY = screenHeight / mazePixelHeight
    Renderer.camera.scale = math.min(scaleX, scaleY) * 0.9
    Renderer.centerCamera(maze, screenWidth, screenHeight)
end

return Renderer