-- Aplica comandos vindos do Home Assistant no Kindle. As dependências do KOReader
-- chegam via `deps` (injeção), então a lógica é testável com fakes.
local Commands = {}

-- deps = {
--   powerd       = Device:getPowerDevice(),
--   network      = NetworkMgr,
--   show_message = function(text, timeout) ... end,  -- exibe InfoMessage
--   request_sync = function() ... end,               -- agenda envio imediato
-- }
function Commands.apply(cmd, deps)
    if type(cmd) ~= "table" or type(cmd.type) ~= "string" then return end

    if cmd.type == "set_frontlight" then
        local v = tonumber(cmd.value)
        if v and deps.powerd and deps.powerd.setIntensity then
            if v > 0 and deps.powerd.turnOnFrontlight then
                pcall(function() deps.powerd:turnOnFrontlight() end)
            end
            pcall(function() deps.powerd:setIntensity(v) end)
        end

    elseif cmd.type == "show_message" then
        if deps.show_message and cmd.text and cmd.text ~= "" then
            pcall(deps.show_message, tostring(cmd.text), cmd.timeout)
        end

    elseif cmd.type == "set_wifi" then
        if deps.network then
            if cmd.value == true and deps.network.turnOnWifi then
                pcall(function() deps.network:turnOnWifi() end)
            elseif cmd.value == false and deps.network.turnOffWifi then
                pcall(function() deps.network:turnOffWifi() end)
            end
        end

    elseif cmd.type == "sync_now" then
        if deps.request_sync then
            pcall(deps.request_sync)
        end

    elseif cmd.type == "set_warmth" then
        local v = tonumber(cmd.value)
        if v and deps.powerd and deps.powerd.setWarmth then
            pcall(function() deps.powerd:setWarmth(v, true) end)
        end

    elseif cmd.type == "set_frontlight_power" then
        if deps.powerd then
            if cmd.value == true and deps.powerd.turnOnFrontlight then
                pcall(function() deps.powerd:turnOnFrontlight() end)
            elseif cmd.value == false and deps.powerd.turnOffFrontlight then
                pcall(function() deps.powerd:turnOffFrontlight() end)
            end
        end

    elseif cmd.type == "page_turn" then
        local rel = tonumber(cmd.value)
        if rel and deps.turn_page then pcall(deps.turn_page, rel) end

    elseif cmd.type == "goto_page" then
        local n = tonumber(cmd.value)
        if n and deps.goto_page then pcall(deps.goto_page, n) end

    elseif cmd.type == "refresh" then
        if deps.refresh then pcall(deps.refresh) end
    end
end

function Commands.apply_all(cmds, deps)
    if type(cmds) ~= "table" then return end
    for _, cmd in ipairs(cmds) do
        Commands.apply(cmd, deps)
    end
end

return Commands
