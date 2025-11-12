-- FFI Wrapper for the Wave Function Collapse DLL
local ffi = require("ffi")

-- Define the C function signatures
ffi.cdef[[
    typedef unsigned short uint16_t;
    typedef unsigned int uint32_t;
    
    uint16_t*** generateGrid(uint32_t width, uint32_t length, uint32_t height, uint32_t seed, uint32_t targetFullness);
    void freeGrid(uint16_t*** grid, uint32_t width, uint32_t length, uint32_t height);
]]

local FFIWrapper = {}

-- Load the DLL (you need to place your compiled DLL in the lib folder)
-- The DLL should be named something like "mazegen.dll" or "libmazegen.dll"
local dll_name = "lib/libWFC.dll"  -- Adjust this to your DLL name
local success, dll = pcall(function()
    return ffi.load(dll_name)
end)

if not success then
    error("Failed to load DLL: " .. dll_name .. "\nError: " .. tostring(dll))
end

FFIWrapper.dll = dll

-- Wrapper function to generate a maze grid
-- Returns a Lua table representation of the grid
function FFIWrapper.generateMaze(width, height, layers, seed, fullness)
    layers = layers or 1
    seed = seed or os.time()
    fullness = fullness or 80
    
    -- Call the C function
    local grid_ptr = dll.generateGrid(width, height, layers, seed, fullness)
    
    if grid_ptr == nil then
        error("Failed to generate maze grid")
    end
    
    -- Convert the C array to a Lua table
    local lua_grid = {}
    
    for layer = 0, layers - 1 do
        lua_grid[layer + 1] = {}
        for y = 0, height - 1 do
            lua_grid[layer + 1][y + 1] = {}
            for x = 0, width - 1 do
                -- Access the 3D array: grid[layer][y][x]
                local tile_value = grid_ptr[layer][y][x]
                lua_grid[layer + 1][y + 1][x + 1] = tonumber(tile_value)
            end
        end
    end
    
    -- Free the C memory
    dll.freeGrid(grid_ptr, width, height, layers)
    
    return lua_grid
end

return FFIWrapper
