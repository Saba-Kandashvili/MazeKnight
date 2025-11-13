function love.conf(t)
    t.title = "MazeKnight - Procedural Maze Explorer"
    t.version = "11.4"
    t.window.width = 1280
    t.window.height = 720
    -- launch the game fullscreen and prevent the window from being resized (resizing causes many problems so it's not allowed)
    t.window.resizable = false
    t.window.fullscreen = true
    -- use 'desktop' fullscreen to match the user's current desktop resolution
    t.window.fullscreenType = "desktop"
    t.window.vsync = 1
    t.window.msaa = 0
    
    t.modules.joystick = false
    t.modules.physics = false
end
