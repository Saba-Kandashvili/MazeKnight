-- MazeKnight

-- load States
local MenuState = require("src.states.menu")
local GameState = require("src.states.game")
local Renderer = require("src.renderer")

-- global State Manager
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

    -- Load music tracks (random play, fade in/out)
    -- tracks are stored as { src = <Source>, name = <filename> }
    game.music = { tracks = {}, current = nil, currentIdx = nil, currentName = nil, lastIdx = nil, targetVolume = 0.47, fadeTime = 2.0, minGap = 8, maxGap = 25, state = "idle", timer = 0, currentTargetVolume = 0, gapDuration = 0 }

    local function loadMusicTracks()
        -- try to load everything inside assets/audio/tracks
        if not love.filesystem.getDirectoryItems then return end
        local items = love.filesystem.getDirectoryItems("assets/audio/tracks")
        for _, fname in ipairs(items) do
            local path = "assets/audio/tracks/" .. fname
            local ok, s = pcall(love.audio.newSource, path, "stream")
            if ok and s then
                s:setLooping(false)
                s:setVolume(0)
                table.insert(game.music.tracks, { src = s, name = fname })
            end
        end
    end

    function game.music:startTrack(idx)
        if #self.tracks == 0 then return end
        idx = idx or math.random(1, #self.tracks)
        -- avoid repeating the last played track if possible
        if #self.tracks > 1 and idx == self.lastIdx then
            idx = (idx % #self.tracks) + 1
        end

        -- stop existing source
        if self.current then
            self.current:stop()
        end

        local entry = self.tracks[idx]
        if not entry then return end
        local s = entry.src or entry
        -- remember previous current index to avoid immediate repeats
        self.lastIdx = self.currentIdx
        self.current = s
        self.currentIdx = idx
        self.currentName = entry.name or ("track_" .. tostring(idx))
        -- small per-track volume variation so quiet tracks can be a bit louder
        local perTrackMul = 0.95 + (math.random() * 0.1) -- 0.95 .. 1.05
        self.currentTargetVolume = (self.targetVolume or 0.47) * perTrackMul
        s:stop(); s:seek(0); s:setVolume(0); s:play()
        self.state = "fading_in"
        self.timer = 0
    end

    function game.music:startRandom()
        if #self.tracks == 0 then return end
        if #self.tracks == 1 then
            self:startTrack(1)
            return
        end
        -- try to pick a track that isn't the last played or currently playing
        local idx = math.random(1, #self.tracks)
        if idx == self.currentIdx or idx == self.lastIdx then
            for i = 1, 6 do
                idx = math.random(1, #self.tracks)
                if idx ~= self.currentIdx and idx ~= self.lastIdx then break end
            end
        end
        -- fallback to sequential pick if unlucky
        if idx == self.currentIdx or idx == self.lastIdx then
            idx = ((self.currentIdx or 0) % #self.tracks) + 1
            if idx == self.lastIdx then idx = (idx % #self.tracks) + 1 end
        end
        self:startTrack(idx)
    end

    function game.music:update(dt)
        -- handle gap/silence waiting between tracks
        if self.state == "gap" then
            self.timer = self.timer + dt
            if self.timer >= (self.gapDuration or self.minGap) then
                self.timer = 0
                self.state = "idle"
                self:startRandom()
            end
            return
        end

        if not self.current then return end

        if self.state == "fading_in" then
            self.timer = self.timer + dt
            local t = math.min(self.timer / self.fadeTime, 1)
            local tv = self.currentTargetVolume or self.targetVolume
            self.current:setVolume((tv or 0.47) * t)
            if t >= 1 then self.state = "playing"; self.timer = 0 end
        elseif self.state == "playing" then
            local dur = self.current:getDuration()
            local ok, pos = pcall(function() return self.current:tell() end)
            if dur and ok and pos and (dur - pos) <= self.fadeTime then
                self.state = "fading_out"
                self.timer = 0
            end
        elseif self.state == "fading_out" then
            self.timer = self.timer + dt
            local t = math.min(self.timer / self.fadeTime, 1)
            local tv = self.currentTargetVolume or self.targetVolume
            self.current:setVolume((tv or 0.47) * (1 - t))
            if t >= 1 then
                -- finish track and schedule silence gap
                self.current:stop()
                self.current:setVolume(0)
                self.lastIdx = self.currentIdx
                self.current = nil
                self.currentIdx = nil
                self.currentTargetVolume = 0
                self.state = "gap"
                self.timer = 0
                self.gapDuration = math.random(self.minGap or 8, self.maxGap or 25)
            end
        end
    end

    loadMusicTracks()
    -- don't start music automatically here; let states decide when to start it
    -- (Menu will remain silent for first 10s, Game will start music immediately)

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

    -- attack helper global
    _G.performPlayerAttack = function(player)
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
                        -- play the attack sound when enemy is hit (same as bat)
                        if _G and type(_G.playAttackSound) == "function" then
                            pcall(function() _G.playAttackSound() end)
                        end
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

    -- start in Menu
    State.switch("menu")
end

function love.update(dt)
    if State.current and State.current.update then
        State.current.update(dt)
    end

    -- update music manager
    if game.music and game.music.update then game.music:update(dt) end
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