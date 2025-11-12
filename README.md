# MazeKnight - Procedural Maze Explorer

A Love2D game that generates procedural mazes using Wave Function Collapse algorithm via a C DLL.

## Project Structure

```
MazeKnight/
├── main.lua              # Main game entry point
├── conf.lua              # Love2D configuration
├── src/                  # Source code modules
│   ├── ffi_wrapper.lua   # FFI bindings for the C DLL
│   ├── tile_mapper.lua   # Maps tile codes to types/rotations
│   ├── maze_generator.lua # Maze generation logic
│   └── renderer.lua      # Rendering system
├── assets/               # Game assets
│   └── tiles/            # Tile images (96x96 PNG files)
│       ├── deadend.png
│       ├── straight.png
│       ├── corner.png
│       ├── t_junction.png
│       └── crossroad.png
└── lib/                  # External libraries
    └── mazegen.dll       # Your WFC DLL (place here)
```

## Setup Instructions

### 1. Install Love2D

Download and install Love2D from: https://love2d.org/

### 2. Place Your DLL

Copy your compiled Wave Function Collapse DLL to the `lib/` folder and rename it to `mazegen.dll`

### 3. Add Tile Images

Place your 96x96 pixel tile PNG images in the `assets/tiles/` folder:

- **deadend.png** - Dead end corridor (opening facing north)
- **straight.png** - Straight corridor (north-south orientation)
- **corner.png** - L-shaped corner (opening north and east)
- **t_junction.png** - T-junction (opening north, east, and west)
- **crossroad.png** - 4-way crossroad (all directions open)

**Note:** The game will work without tile images using colored placeholder rectangles. Rotation is handled automatically.

### 4. Run the Game

From the project directory, run:

```
love .
```

Or drag the MazeKnight folder onto the Love2D executable.

## Controls

- **SPACE** - Generate a new random maze
- **F** - Fit maze to screen
- **Arrow Keys** - Pan camera
- **+/-** - Zoom in/out
- **R** - Regenerate with same seed
- **ESC** - Quit

## Tile Mapping

Each tile type represents a different corridor configuration:

| Tile Code | Type       | Rotation | Description   |
| --------- | ---------- | -------- | ------------- |
| 1         | Corner     | 0°       | North-East    |
| 2         | Corner     | 90°      | South-East    |
| 4         | Corner     | 180°     | South-West    |
| 8         | Corner     | 270°     | North-West    |
| 16        | Straight   | 0°       | North-South   |
| 32        | Straight   | 90°      | West-East     |
| 64        | T-Junction | 0°       | North opening |
| 128       | T-Junction | 90°      | East opening  |
| 256       | T-Junction | 180°     | South opening |
| 512       | T-Junction | 270°     | West opening  |
| 1024      | Crossroad  | -        | Normal X      |
| 2048      | Crossroad  | -        | Special X     |
| 4096      | Dead End   | 0°       | North opening |
| 8192      | Dead End   | 90°      | East opening  |
| 16384     | Dead End   | 180°     | South opening |
| 32768     | Dead End   | 270°     | West opening  |

## Technical Details

- **FFI**: Uses LuaJIT's FFI to call C functions from the DLL
- **Wave Function Collapse**: Maze generation algorithm implemented in C
- **Rotation**: Tiles are rotated programmatically (0°, 90°, 180°, 270°)
- **Default Maze Size**: 20x20 tiles
-- **Tile Size**: 96x96 pixels

## Troubleshooting

### DLL Not Loading

- Ensure the DLL is in the `lib/` folder
- Verify the DLL name matches `mazegen.dll` in `src/ffi_wrapper.lua`
- Check that the DLL is compiled for your system architecture (x64/x86)

### Missing Tiles

- The game will use colored placeholders if tile images are missing
- Check that tile images are 96x96 pixels
- Verify PNG format and file names match exactly

## Future Enhancements

- Player character and movement
- Enemies and combat
- Multiple maze layers
- Minimap
- Collectibles and objectives
