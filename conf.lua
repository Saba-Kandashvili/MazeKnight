-- Love2D Configuration File
function love.conf(t)
    t.title = "MazeKnight - Procedural Maze Explorer"
    t.version = "11.4"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    t.window.vsync = 1
    t.window.msaa = 0
    
    t.modules.joystick = false
    t.modules.physics = false
end
