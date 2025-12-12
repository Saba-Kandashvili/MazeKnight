-- MazeKnight
-- Main Entry Point

-- Load States
local MenuState = require("src.states.menu")
local GameState = require("src.states.game")
local Renderer = require("src.renderer")

-- Global State Manager
State = {
    current = nil,
    currentName = "menu"
}

function State.switch(target)
    State.currentName = target
    if target == "menu" then
        State.current = MenuState
    elseif target == "game" then
        State.current = GameState
    end
    
    if State.current.enter then
        State.current.enter()
    end
end

-- Global Game Data (Shared across states)
_G.game = {
    highScore = 0,
    mazeWidth = 15,
    mazeHeight = 15,
    debug = false,
    -- ... other properties are reset by GameState.enter()
    enemies = {},
    menu = {}
}

function love.load()
    if love.system.getOS() == "Windows" then
        io.stdout:setvbuf("no")
    end

    love.filesystem.setIdentity("MazeKnight_Save")
    
    -- Load High Score
    if love.filesystem.getInfo("highscore.txt") then
        local data = love.filesystem.read("highscore.txt")
        game.highScore = tonumber(data) or 0
    end

    love.graphics.setBackgroundColor(0.05, 0.05, 0.05)
    love.graphics.setDefaultFilter("nearest", "nearest")

    -- Load Fonts
    game.fonts = {}
    local function loadFont(p, s)
        local ok, f = pcall(love.graphics.newFont, p, s)
        if ok then f:setFilter("nearest","nearest") return f end
        return love.graphics.newFont(s)
    end
    game.fonts.deathLarge = loadFont("assets/fonts/BleedingPixels.ttf", 96)
    game.fonts.default = loadFont("assets/fonts/minecraft_font.ttf", 16)
    game.fonts.deathSmall = loadFont("assets/fonts/minecraft_font.ttf", 24)
    game.fonts.level = loadFont("assets/fonts/minecraft_font.ttf", 20)
    love.graphics.setFont(game.fonts.default)

    -- Load Sounds
    game.sounds = {}
    local function loadSnd(p) 
        local ok, s = pcall(love.audio.newSource, p, "static")
        return ok and s or nil
    end
    game.sounds.damage = { loadSnd("assets/audio/damage/damage_1.wav"), loadSnd("assets/audio/damage/damage_2.wav") }
    game.sounds.death_intro = loadSnd("assets/audio/death/death_intro.wav")
    game.sounds.death_bells = loadSnd("assets/audio/death/death_bells.wav")
    game.sounds.door = loadSnd("assets/audio/door/door.wav")
    if game.sounds.door then game.sounds.door:setLooping(true) end
    
    game.sounds.attack = { loadSnd("assets/audio/attack/slash_1.wav"), loadSnd("assets/audio/attack/slash_2.wav") }
    game.sounds.ambient = {}
    for i=1,5 do table.insert(game.sounds.ambient, loadSnd("assets/audio/ambient/amb_"..i..".wav")) end

    -- Initialize Renderer
    Renderer.init()
    
    -- Initialize Darkness Shader
    local shaderCode = [[
        extern number cx; extern number cy; extern number innerRadius; extern number outerRadius; extern number exponent;
        vec4 effect(vec4 color, Image texture, vec2 texCoord, vec2 px) {
            float dist = distance(px, vec2(cx, cy));
            float t = clamp((dist - innerRadius) / (outerRadius - innerRadius), 0.0, 1.0);
            t = pow(t, exponent);
            return vec4(0.0, 0.0, 0.0, t * color.a);
        }
    ]]
    local ok, s = pcall(love.graphics.newShader, shaderCode)
    if ok then game.darknessShader = s end

    -- Attack Helper Global
    _G.performPlayerAttack = function(player)
        -- Keep logic from previous main.lua, just accessing global game
        -- (Logic for hit detection is inside GameState anyway usually, but keeping global for Player class)
        local range = 64
        local px, py = player.pixelX, player.pixelY
        local fx, fy = 0, 0
        if player.direction == "right" then fx = 1 elseif player.direction == "left" then fx = -1 elseif player.direction == "up" then fy = -1 else fy = 1 end
        
        for _, e in ipairs(game.enemies) do
            if not e.isDead then
                local dist = math.sqrt((e.pixelX-px)^2 + (e.pixelY-py)^2)
                if dist <= range then
                    local nx, ny = (e.pixelX-px)/dist, (e.pixelY-py)/dist
                    if (fx==0 and fy==0) or (nx*fx + ny*fy >= 0) then
                        e.isDead = true
                        e.direction = nil
                        if game.hitParticles then 
                            game.hitParticles:setPosition(e.pixelX, e.pixelY)
                            game.hitParticles:emit(20)
                        end
                    end
                end
            end
        end
    end
    
    _G.playAttackSound = function()
        if #game.sounds.attack > 0 then
            local s = game.sounds.attack[math.random(1, #game.sounds.attack)]
            if s then s:stop(); s:play() end
        end
    end

    -- Start in Menu
    State.switch("menu")
end

function love.update(dt)
    if State.current and State.current.update then
        State.current.update(dt)
    end
end

function love.draw()
    if State.current and State.current.draw then
        State.current.draw()
    end
end

function love.keypressed(key)
    if State.current and State.current.keypressed then
        State.current.keypressed(key)
    end
end

function love.resize(w, h)
    Renderer.centerCamera(game.maze, w, h)
end