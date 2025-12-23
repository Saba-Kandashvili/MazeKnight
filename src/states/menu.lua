local Menu = {}

function Menu.enter()
    -- Reset selection when entering menu
    Menu.selection = 1
    Menu.options = {"START GAME", "QUIT"}

    -- menu music timer: we want silence for the first 10s
    Menu.menuTimer = 0
    Menu.track2Started = false

    -- ensure nothing is playing when entering menu
    if game and game.music then
        -- stop any playing source and set state to menu_wait so update keeps silence
        if game.music.current then
            pcall(function() game.music.current:stop() end)
        end
        game.music.current = nil
        game.music.currentIdx = nil
        game.music.currentName = nil
        game.music.currentTargetVolume = 0
        game.music.state = "menu_wait"
    end
end

function Menu.update(dt)
    -- Add menu animations here if you want later
    -- Wait 10s in silence, then start track 2. After that, music manager resumes normal behavior
    if game and game.music and game.music.state == "menu_wait" and not Menu.track2Started and #game.music.tracks >= 2 then
        Menu.menuTimer = Menu.menuTimer + dt
        if Menu.menuTimer >= 10 then
            -- start the second track directly
            game.music:startTrack(2)
            Menu.track2Started = true
            -- normal behavior resumes and music manager will handle following tracks
        end
    end
end

function Menu.draw()
    local w, h = love.graphics.getDimensions()
    
    -- Title (Orange, BleedingPixels)
    love.graphics.setFont(game.fonts.deathLarge)
    love.graphics.setColor(1, 0.5, 0, 1) 
    love.graphics.printf("MAZEKNIGHT", 0, h * 0.25, w, "center")
    
    -- High Score
    love.graphics.setFont(game.fonts.deathSmall) 
    love.graphics.setColor(1, 1, 0, 1) -- Yellow
    love.graphics.printf("BEST RUN: " .. (game.highScore or 0) .. " LEVELS", 0, h * 0.45, w, "center")
    
    -- Options
    love.graphics.setFont(game.fonts.deathSmall)
    for i, opt in ipairs(Menu.options) do
        if i == Menu.selection then
            love.graphics.setColor(1, 1, 1, 1) -- Selected: White
            love.graphics.printf("> " .. opt .. " <", 0, h * 0.55 + (i * 40), w, "center")
        else
            love.graphics.setColor(0.5, 0.5, 0.5, 1) -- Unselected: Gray
            love.graphics.printf(opt, 0, h * 0.55 + (i * 40), w, "center")
        end
    end
    
    love.graphics.setColor(1, 1, 1, 1)
end

function Menu.keypressed(key)
    if key == "up" or key == "w" then
        Menu.selection = Menu.selection - 1
        if Menu.selection < 1 then Menu.selection = #Menu.options end
    elseif key == "down" or key == "s" then
        Menu.selection = Menu.selection + 1
        if Menu.selection > #Menu.options then Menu.selection = 1 end
    elseif key == "return" or key == "space" then
        if Menu.selection == 1 then
            -- Switch to Game State
            State.switch("game")
        elseif Menu.selection == 2 then
            love.event.quit()
        end
    end
end

return Menu