# Tile Asset Instructions

Place your 64x64 pixel PNG tile images in this folder.

## Required Files:

1. **deadend.png** - Dead end corridor tile

   - Opening facing NORTH (upward)
   - All other sides are walls

2. **straight.png** - Straight corridor tile

   - Openings on NORTH and SOUTH
   - East and West sides are walls

3. **corner.png** - L-shaped corner tile

   - Openings on NORTH and EAST
   - South and West sides are walls

4. **t_junction.png** - T-junction tile

   - Openings on NORTH, EAST, and WEST
   - South side is a wall

5. **crossroad.png** - 4-way intersection tile
   - Openings on all four sides (NORTH, EAST, SOUTH, WEST)

## Important Notes:

- All tiles should be designed with the "opening" facing NORTH (upward)
- The game will automatically rotate tiles as needed
- If tiles are missing, the game will use colored placeholder rectangles
- Recommended: Dark walls with light corridors for visibility
- Format: PNG with transparency (optional)
- Dimensions: Exactly 64x64 pixels

## Color Legend (Placeholders):

If you run the game without tiles, you'll see these colors:

- Red = Dead End
- Green = Straight Corridor
- Blue = Corner
- Yellow = T-Junction
- Magenta = Crossroad

White triangles point "north" to show orientation.
