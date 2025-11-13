-- maps tile codes from my WFC algorithm to tile types and rotations

local TileMapper = {}

-- matching the C code
TileMapper.PrefabCodes = {
    Empty_Tile = 0,
    North_East_Corridor = 1,                    -- 1 << 0
    South_East_Corridor = 2,                    -- 1 << 1
    South_West_Corridor = 4,                    -- 1 << 2
    North_West_Corridor = 8,                    -- 1 << 3
    North_South_Corridor = 16,                  -- 1 << 4
    West_East_Corridor = 32,                    -- 1 << 5
    North_T_Corridor = 64,                      -- 1 << 6
    East_T_Corridor = 128,                      -- 1 << 7
    South_T_Corridor = 256,                     -- 1 << 8
    West_T_Corridor = 512,                      -- 1 << 9
    Normal_X_Corridor = 1024,                   -- 1 << 10
    Special_X_Corridor = 2048,                  -- 1 << 11
    North_DeadEnd = 4096,                       -- 1 << 12
    East_DeadEnd = 8192,                        -- 1 << 13
    South_DeadEnd = 16384,                      -- 1 << 14
    West_DeadEnd = 32768                        -- 1 << 15
}

-- types
TileMapper.TileType = {
    DEADEND = "deadend",
    STRAIGHT = "straight",
    CORNER = "corner",
    T_JUNCTION = "t_junction",
    CROSSROAD = "crossroad",
    EMPTY = "empty"
}

-- type and rotation
function TileMapper.codeToTile(code)
    local PF = TileMapper.PrefabCodes
    local TT = TileMapper.TileType
    
    -- L
    if code == PF.North_East_Corridor then
        return { tileType = TT.CORNER, rotation = 0 }
    elseif code == PF.South_East_Corridor then
        return { tileType = TT.CORNER, rotation = 1 }
    elseif code == PF.South_West_Corridor then
        return { tileType = TT.CORNER, rotation = 2 }
    elseif code == PF.North_West_Corridor then
        return { tileType = TT.CORNER, rotation = 3 }
    
    -- I
    elseif code == PF.North_South_Corridor then
        return { tileType = TT.STRAIGHT, rotation = 0 }
    elseif code == PF.West_East_Corridor then
        return { tileType = TT.STRAIGHT, rotation = 1 }
    
    -- T
    elseif code == PF.North_T_Corridor then
        return { tileType = TT.T_JUNCTION, rotation = 0 }
    elseif code == PF.East_T_Corridor then
        return { tileType = TT.T_JUNCTION, rotation = 1 }
    elseif code == PF.South_T_Corridor then
        return { tileType = TT.T_JUNCTION, rotation = 2 }
    elseif code == PF.West_T_Corridor then
        return { tileType = TT.T_JUNCTION, rotation = 3 }
    
    -- X
    elseif code == PF.Normal_X_Corridor or code == PF.Special_X_Corridor then
        return { tileType = TT.CROSSROAD, rotation = 0 }
    
    -- Dead ends
    elseif code == PF.North_DeadEnd then
        return { tileType = TT.DEADEND, rotation = 0 }
    elseif code == PF.East_DeadEnd then
        return { tileType = TT.DEADEND, rotation = 1 }
    elseif code == PF.South_DeadEnd then
        return { tileType = TT.DEADEND, rotation = 2 }
    elseif code == PF.West_DeadEnd then
        return { tileType = TT.DEADEND, rotation = 3 }
    
    -- empty
    else
        return { tileType = TT.EMPTY, rotation = 0 }
    end
end

function TileMapper.getRotationRadians(rotation)
    return rotation * (math.pi / 2)  -- Convert 0-3 to radians
end

function TileMapper.isValidTile(code)
    local PF = TileMapper.PrefabCodes
    return code == PF.North_East_Corridor or
           code == PF.South_East_Corridor or
           code == PF.South_West_Corridor or
           code == PF.North_West_Corridor or
           code == PF.North_South_Corridor or
           code == PF.West_East_Corridor or
           code == PF.North_T_Corridor or
           code == PF.East_T_Corridor or
           code == PF.South_T_Corridor or
           code == PF.West_T_Corridor or
           code == PF.Normal_X_Corridor or
           code == PF.Special_X_Corridor or
           code == PF.North_DeadEnd or
           code == PF.East_DeadEnd or
           code == PF.South_DeadEnd or
           code == PF.West_DeadEnd
end

return TileMapper
