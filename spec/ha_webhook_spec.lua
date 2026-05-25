local HAWebhook = require("ha_webhook")

describe("HAWebhook.build_url", function()
    it("monta a URL do webhook a partir de host/port/https/webhook_id", function()
        local cfg = { host = "homeassistant.99lab.online", port = 443, https = true,
            webhook_id = "abc123" }
        assert.are.equal("https://homeassistant.99lab.online:443/api/webhook/abc123",
            HAWebhook.build_url(cfg))
    end)
    it("usa http quando https=false", function()
        local cfg = { host = "192.168.1.10", port = 8123, https = false,
            webhook_id = "xyz" }
        assert.are.equal("http://192.168.1.10:8123/api/webhook/xyz",
            HAWebhook.build_url(cfg))
    end)
end)

describe("HAWebhook.build_request", function()
    it("monta POST com corpo JSON do snapshot", function()
        local cfg = { host = "h", port = 443, https = true, webhook_id = "id" }
        local snapshot = { battery_level = 80, reading = true }
        local captured
        local req = HAWebhook.build_request(cfg, snapshot, function(t)
            captured = t
            return '{"battery_level":80}'
        end)
        assert.are.equal("POST", req.method)
        assert.are.equal("application/json", req.headers["Content-Type"])
        assert.are.equal(80, captured.battery_level)
        assert.are.equal(tostring(#req.body), req.headers["Content-Length"])
    end)
end)

describe("HAWebhook.parse_commands", function()
    it("extrai a lista de comandos do corpo de resposta", function()
        local body = '{"commands":[{"type":"set_frontlight","value":20}]}'
        local cmds = HAWebhook.parse_commands(body, function(s)
            -- decoder fake: devolve a tabela esperada
            return { commands = { { type = "set_frontlight", value = 20 } } }
        end)
        assert.are.equal(1, #cmds)
        assert.are.equal("set_frontlight", cmds[1].type)
        assert.are.equal(20, cmds[1].value)
    end)
    it("devolve lista vazia quando não há comandos", function()
        local cmds = HAWebhook.parse_commands("{}", function() return {} end)
        assert.are.equal(0, #cmds)
    end)
end)
