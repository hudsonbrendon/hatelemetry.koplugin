local Commands = require("commands")

-- Fakes que registram o que foi chamado
local function make_deps()
    local calls = {}
    local deps = {
        powerd = {
            setIntensity = function(_, v) calls.frontlight = v end,
            turnOnFrontlight = function() calls.fl_on = true end,
        },
        network = {
            turnOnWifi = function() calls.wifi = "on" end,
            turnOffWifi = function() calls.wifi = "off" end,
        },
        show_message = function(text, timeout)
            calls.message = text
            calls.timeout = timeout
        end,
        request_sync = function() calls.sync = true end,
    }
    return deps, calls
end

describe("Commands.apply", function()
    it("set_frontlight ajusta intensidade", function()
        local deps, calls = make_deps()
        Commands.apply({ type = "set_frontlight", value = 20 }, deps)
        assert.are.equal(20, calls.frontlight)
    end)
    it("show_message exibe texto com timeout", function()
        local deps, calls = make_deps()
        Commands.apply({ type = "show_message", text = "oi", timeout = 5 }, deps)
        assert.are.equal("oi", calls.message)
        assert.are.equal(5, calls.timeout)
    end)
    it("set_wifi true liga o wifi", function()
        local deps, calls = make_deps()
        Commands.apply({ type = "set_wifi", value = true }, deps)
        assert.are.equal("on", calls.wifi)
    end)
    it("set_wifi false desliga o wifi", function()
        local deps, calls = make_deps()
        Commands.apply({ type = "set_wifi", value = false }, deps)
        assert.are.equal("off", calls.wifi)
    end)
    it("sync_now pede sync", function()
        local deps, calls = make_deps()
        Commands.apply({ type = "sync_now" }, deps)
        assert.is_true(calls.sync)
    end)
    it("ignora comando desconhecido sem erro", function()
        local deps = make_deps()
        assert.has_no.errors(function()
            Commands.apply({ type = "wat" }, deps)
        end)
    end)
    it("apply_all aplica uma lista", function()
        local deps, calls = make_deps()
        Commands.apply_all({
            { type = "set_frontlight", value = 30 },
            { type = "sync_now" },
        }, deps)
        assert.are.equal(30, calls.frontlight)
        assert.is_true(calls.sync)
    end)
end)
