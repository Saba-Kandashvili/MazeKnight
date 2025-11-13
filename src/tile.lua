-- Tile Class
-- Smart tiles with collision data that rotates with the tile

local TileMapper = require("src.tile_mapper")

local Tile = {}
Tile.__index = Tile

-- Collision data for each base tile type (3x3 grid, 1 = walkable, 0 = wall)
-- These are defined in the tile's "natural" orientation (rotation = 0)
local COLLISION_DATA = {
    [TileMapper.TileType.DEADEND] = {
        -- Dead end: open only in center and one direction
        {0, 1, 0},
        {0, 1, 0},
        {0, 0, 0}
    },
    
    [TileMapper.TileType.STRAIGHT] = {
        -- Straight corridor: open in center column
        {0, 1, 0},
        {0, 1, 0},
        {0, 1, 0}
    },
    
    [TileMapper.TileType.CORNER] = {
        -- L-shaped corner: open in center and two perpendicular directions
        {0, 1, 0},
        {0, 1, 1},
        {0, 0, 0}
    },
    
    [TileMapper.TileType.T_JUNCTION] = {
        -- T-junction: open in three directions
        {0, 1, 0},
        {1, 1, 1},
        {0, 0, 0}
    },
    
    [TileMapper.TileType.CROSSROAD] = {
        -- X/+ crossroad: open in all four directions
        {0, 1, 0},
        {1, 1, 1},
        {0, 1, 0}
    },
    
    [TileMapper.TileType.EMPTY] = {
        -- Empty: all walls
        {0, 0, 0},
        {0, 0, 0},
        {0, 0, 0}
    }
}

function Tile.new(x, y, tileType, rotation, code)
    local self = setmetatable({}, Tile)
    
    self.x = x  -- Tile position in maze grid
    self.y = y
    self.tileType = tileType
    self.rotation = rotation  -- 0, 1, 2, or 3 (90° increments)
    self.code = code
    self.isSpawn = false  -- Mark if this is the player spawn location
    self.isFinish = false  -- Mark if this is the finish location
    
    -- Generate rotated collision grid
    self.collisionGrid = self:generateCollisionGrid()
    
    return self
end

-- Rotate a 3x3 grid clockwise by 90 degrees
function Tile:rotateGrid90(grid)
    local rotated = {{0, 0, 0}, {0, 0, 0}, {0, 0, 0}}
    for row = 1, 3 do
        for col = 1, 3 do
            -- Rotate: new[col][3-row+1] = old[row][col]
            rotated[col][4 - row] = grid[row][col]
        end
    end
    return rotated
end

-- Generate collision grid with proper rotation applied
function Tile:generateCollisionGrid()
    local baseGrid = COLLISION_DATA[self.tileType]
    if not baseGrid then
        -- Default to all walls if unknown type
        return {{0, 0, 0}, {0, 0, 0}, {0, 0, 0}}
    end
    
    -- Deep copy the base grid
    local grid = {}
    for i = 1, 3 do
        grid[i] = {}
        for j = 1, 3 do
            grid[i][j] = baseGrid[i][j]
        end
    end
    
    -- Apply rotation
    for i = 1, self.rotation do
        grid = self:rotateGrid90(grid)
    end
    
    return grid
end

-- Check if a sub-cell is walkable (subX, subY are 1-3)
function Tile:isWalkable(subX, subY)
    if subX < 1 or subX > 3 or subY < 1 or subY > 3 then
        return false
    end
    return self.collisionGrid[subY][subX] == 1
end

-- Check if can exit tile in a direction from a sub-cell
function Tile:canExitFrom(subX, subY, direction)
    if not self:isWalkable(subX, subY) then
        return false
    end
    
    -- Check if we're at the edge and the cell allows exit
    if direction == "north" and subY == 1 then
        return true
    elseif direction == "south" and subY == 3 then
        return true
    elseif direction == "east" and subX == 3 then
        return true
    elseif direction == "west" and subX == 1 then
        return true
    end
    
    return false
end

-- Check if a sub-cell can be entered from a given direction (fromDirection is where the mover comes from)
function Tile:canEnterFrom(subX, subY, fromDirection)
    if not self:isWalkable(subX, subY) then
        return false
    end

    -- If entering from north, the entry point should be at the top row (subY == 1)
    if fromDirection == "north" and subY == 1 then
        return true
    elseif fromDirection == "south" and subY == 3 then
        return true
    elseif fromDirection == "west" and subX == 1 then
        return true
    elseif fromDirection == "east" and subX == 3 then
        return true
    end

    return false
end

-- Debug: Print collision grid
function Tile:printCollisionGrid()
    print(string.format("Tile (%d,%d) %s rot=%d:", self.x, self.y, self.tileType, self.rotation))
    for row = 1, 3 do
        local line = ""
        for col = 1, 3 do
            line = line .. (self.collisionGrid[row][col] == 1 and "." or "#")
        end
        print("  " .. line)
    end
end

return Tile
