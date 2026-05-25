local Commands = require("commands")

-- Fakes que registram o que foi chamado
local function make_deps()
    local calls = {}
    local deps = {
        powerd = {
            setIntensity = function(_, v) calls.frontlight = v end,
            turnOnFrontlight = function() calls.fl_on = true end,
            turnOffFrontlight = function() calls.fl_off = true end,
            setWarmth = function(_, v) calls.warmth = v end,
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
        turn_page = function(rel) calls.turn_page = rel end,
        goto_page = function(n) calls.goto_page = n end,
        refresh = function() calls.refresh = true end,
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

    it("set_warmth ajusta o warmth do frontlight", function()
        local deps, calls = make_deps()
        Commands.apply({ type = "set_warmth", value = 75 }, deps)
        assert.are.equal(75, calls.warmth)
    end)

    it("set_frontlight_power true liga o frontlight", function()
        local deps, calls = make_deps()
        Commands.apply({ type = "set_frontlight_power", value = true }, deps)
        assert.is_true(calls.fl_on)
        assert.is_nil(calls.fl_off)
    end)

    it("set_frontlight_power false desliga o frontlight", function()
        local deps, calls = make_deps()
        Commands.apply({ type = "set_frontlight_power", value = false }, deps)
        assert.is_true(calls.fl_off)
        assert.is_nil(calls.fl_on)
    end)

    it("page_turn passa o valor relativo para turn_page", function()
        local deps, calls = make_deps()
        Commands.apply({ type = "page_turn", value = 1 }, deps)
        assert.are.equal(1, calls.turn_page)
    end)

    it("page_turn com valor negativo volta pagina", function()
        local deps, calls = make_deps()
        Commands.apply({ type = "page_turn", value = -1 }, deps)
        assert.are.equal(-1, calls.turn_page)
    end)

    it("goto_page navega para a pagina especificada", function()
        local deps, calls = make_deps()
        Commands.apply({ type = "goto_page", value = 42 }, deps)
        assert.are.equal(42, calls.goto_page)
    end)

    it("refresh aciona o refresh de tela", function()
        local deps, calls = make_deps()
        Commands.apply({ type = "refresh" }, deps)
        assert.is_true(calls.refresh)
    end)
end)
