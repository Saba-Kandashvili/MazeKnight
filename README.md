MazeKnight
=========

A small procedural maze explorer I made with LÖVE (Love2D).

**What it is:**
- A top-down, grid-based roguelike-lite where you explore generated mazes, fight simple enemies, and try to reach the exit.

**Run (dev):**
1. Install LÖVE 11.4 (https://love2d.org)
2. From the project root:
```
love .
```

**Notes:**
- Audio and image assets are under `assets/`.
- Game code lives in `src/` and `main.lua`.
- If you see a `game.log` file it is a runtime log — I ignore it in `.gitignore`.

**Build / Debug tips:**
- Run `love .` to start. If the game can't find the native lib, double-check the platform binary and that it matches the LÖVE architecture (32 vs 64-bit).

Debug
- Default: debug mode is OFF when the game starts.
- Toggle debug: press `F3` to enable/disable debug overlays.
- When debug is ON:
	- Hold `Backspace` to show a full overview of the maze (camera will fit the entire map).
	- A debug overlay shows FPS, audio source status, and other runtime info.
- Darkness: press `F` to cycle darkness presets (changes how the radial darkness around the player looks).



**Credits:**
**Credits:**
- Maze generator: the game uses a C native library I developed — it's a heavily modified wave fucntioncollapse algorythim with
maze solvability validation. 
- Audio: all sounds were recorded and produced by me (guitar).

**License**
This project is provided under the Creative Commons Attribution-NonCommercial 4.0 International license (CC BY-NC 4.0). You may copy, modify, and distribute the game and its source, but you may not use it for commercial purposes or resell it for a price. See `LICENSE` for details and a link to the full license.