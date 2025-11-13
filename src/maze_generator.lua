
local FFIWrapper = require("src.ffi_wrapper")
local TileMapper = require("src.tile_mapper")
local Tile = require("src.tile")

local MazeGenerator = {}

-- generate a new maze
function MazeGenerator.generate(width, height, seed)
    seed = seed or os.time()
    
    local maxAttempts = 10
    local minFillPercent = 60  -- at least 60% of tiles should be non-empty
    
    for attempt = 1, maxAttempts do
        local currentSeed = seed + attempt - 1
        print(string.format("Generating maze: %dx%d (W×H), seed: %d (attempt %d)", width, height, currentSeed, attempt))
        
        -- generate using the DLL (single layer)
        -- width, height, layers, seed, fullness
        local raw_grid = FFIWrapper.generateMaze(width, height, 1, currentSeed, 80)
        
        -- count valid tiles (only tiles with valid codes)
        local validTileCount = 0
        local totalTiles = width * height
        
        for y = 1, height do
            for x = 1, width do
                local code = raw_grid[1][y][x]
                if TileMapper.isValidTile(code) then
                    validTileCount = validTileCount + 1
                end
            end
        end
        
        local fillPercent = (validTileCount / totalTiles) * 100
        print(string.format("Maze fill: %.1f%% (%d/%d tiles)", fillPercent, validTileCount, totalTiles))
        
        -- check if maze is good enough
        if fillPercent >= minFillPercent then
            print("Maze generation complete!")
            -- process the grid into a more usable format
            local processed_grid = MazeGenerator.processGrid(raw_grid[1], width, height)
            return processed_grid
        else
            print(string.format("Maze too empty (%.1f%%), regenerating...", fillPercent))
        end
    end
    
    -- all attempts failed - just use the last one (I know this is not ideal but theres a problem with my dll and i dotn have time to fix giant C project beofre this assigment is due :'(    )
    print("Warning: Could not generate well-filled maze after " .. maxAttempts .. " attempts, using last attempt")
    local raw_grid = FFIWrapper.generateMaze(width, height, 1, seed + maxAttempts - 1, 80)
    local processed_grid = MazeGenerator.processGrid(raw_grid[1], width, height)
    return processed_grid
end

-- process raw grid into tile information
function MazeGenerator.processGrid(raw_layer, width, height)
    local grid = {}
    local edgeTiles = {
        top = {},    -- y == 1
        bottom = {}, -- y == height
        left = {},   -- x == 1
        right = {}   -- x == width
    }
    
    -- first pass: create tile grid and collect valid edge tiles
    for y = 1, height do
        grid[y] = {}
        for x = 1, width do
            local code = raw_layer[y][x]
            
            -- treat Special_X_Corridor (2048) as Normal_X_Corridor (1024) [speacial X is a connecting tile taht conencts different layers toegther but no use for that in this game sicne its fully 2D]
            if code == 2048 then
                code = 1024
            end
            
            local tile_info = TileMapper.codeToTile(code)
            
            -- create a Tile object instead of plain data
            grid[y][x] = Tile.new(x, y, tile_info.tileType, tile_info.rotation, code)
            
            -- collect valid edge tiles (only tiles with valid codes on edges)
            if TileMapper.isValidTile(code) then
                if y == 1 then
                    table.insert(edgeTiles.top, {x = x, y = y, edge = "top"})
                end
                if y == height then
                    table.insert(edgeTiles.bottom, {x = x, y = y, edge = "bottom"})
                end
                if x == 1 then
                    table.insert(edgeTiles.left, {x = x, y = y, edge = "left"})
                end
                if x == width then
                    table.insert(edgeTiles.right, {x = x, y = y, edge = "right"})
                end
            end
        end
    end
    
    -- collect all valid tiles for fallback (only tiles with valid codes)
    local allValidTiles = {}
    for y = 1, height do
        for x = 1, width do
            if TileMapper.isValidTile(grid[y][x].code) then
                table.insert(allValidTiles, {x = x, y = y})
            end
        end
    end
    
    -- helper function to find closest tile to a target edge
    local function findClosestToEdge(edgeName)
        local closest = nil
        local minDist = math.huge
        
        for _, tile in ipairs(allValidTiles) do
            local dist
            if edgeName == "top" then
                dist = tile.y  -- distance from top
            elseif edgeName == "bottom" then
                dist = height - tile.y  -- distance from bottom
            elseif edgeName == "left" then
                dist = tile.x  -- distance from left
            elseif edgeName == "right" then
                dist = width - tile.x  -- distance from right
            end
            
            if dist < minDist then
                minDist = dist
                closest = tile
            end
        end
        
        return closest
    end
    
    -- pick spawn and goal on opposite edges
    local spawnTile = nil
    local goalTile = nil
    
    -- define opposite edge mapping
    local oppositeEdge = {
        top = {name = "bottom", tiles = edgeTiles.bottom},
        bottom = {name = "top", tiles = edgeTiles.top},
        left = {name = "right", tiles = edgeTiles.right},
        right = {name = "left", tiles = edgeTiles.left}
    }
    
    -- collect all available edge tiles
    local allEdgeTiles = {}
    for edgeName, tiles in pairs(edgeTiles) do
        for _, tile in ipairs(tiles) do
            table.insert(allEdgeTiles, {x = tile.x, y = tile.y, edge = edgeName})
        end
    end
    
    if #allEdgeTiles > 0 then
        -- randomly pick spawn from any edge
        local randomIndex = math.random(1, #allEdgeTiles)
        spawnTile = allEdgeTiles[randomIndex]
        
        -- get opposite edge
        local opposite = oppositeEdge[spawnTile.edge]
        
        if #opposite.tiles > 0 then
            -- randomly pick goal from opposite edge
            local randomGoalIndex = math.random(1, #opposite.tiles)
            goalTile = opposite.tiles[randomGoalIndex]
        else
            -- no valid tiles on opposite edge, find closest to that edge
            goalTile = findClosestToEdge(opposite.name)
        end
    end
    
    if spawnTile and goalTile then
        print(string.format("Spawn (RED) at (%d, %d) [%s edge], Goal (GREEN) at (%d, %d)", 
            spawnTile.x, spawnTile.y, spawnTile.edge or "?", goalTile.x, goalTile.y))
    else
        print("Warning: Could not find valid spawn/goal tiles!")
    end
    
    return {
        width = width,
        height = height,
        tiles = grid,
        spawnTile = spawnTile,  -- red tile TODO: remove this red/green stuff, it was usied for testing only
        goalTile = goalTile     -- green tile
    }
end

return MazeGenerator
