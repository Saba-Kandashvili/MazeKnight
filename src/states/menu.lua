local Menu = {}

function Menu.enter()
    -- Reset selection when entering menu
    Menu.selection = 1
    Menu.options = {"START GAME", "QUIT"}
end

function Menu.update(dt)
    -- Add menu animations here if you want later
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