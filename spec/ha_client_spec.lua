local HAClient = require("ha_client")

describe("HAClient.build_url", function()
    it("builds an http URL by default", function()
        assert.are.equal("http://10.0.0.5:8123/api/states/sensor.koreader_battery",
            HAClient.build_url({ host = "10.0.0.5", port = 8123, https = false },
                "sensor.koreader_battery"))
    end)
    it("uses https when configured", function()
        assert.are.equal("https://ha.local:443/api/states/binary_sensor.koreader_status",
            HAClient.build_url({ host = "ha.local", port = 443, https = true },
                "binary_sensor.koreader_status"))
    end)
end)

describe("HAClient.build_request", function()
    it("builds a POST with bearer auth and a json body", function()
        local cfg = { host = "h", port = 8123, https = false, token = "TKN" }
        local entity = { entity_id = "sensor.x", state = "5", attributes = { a = 1 } }
        local captured
        local req = HAClient.build_request(cfg, entity, function(t)
            captured = t
            return '{"state":"5","attributes":{"a":1}}'
        end)
        assert.are.equal("POST", req.method)
        assert.are.equal("Bearer TKN", req.headers["Authorization"])
        assert.are.equal("application/json", req.headers["Content-Type"])
        assert.are.equal("5", captured.state)
        assert.are.equal(1, captured.attributes.a)
        assert.are.equal(tostring(#req.body), req.headers["Content-Length"])
    end)
end)

describe("HAClient.validate", function()
    it("rejects an unset token", function()
        local ok = HAClient.validate{ host = "h", port = 8123,
            token = "PasteYourHomeAssistantLong-LivedAccessTokenHere" }
        assert.is_false(ok)
    end)
    it("rejects a non-numeric port", function()
        local ok = HAClient.validate{ host = "h", port = "8123", token = "abc" }
        assert.is_false(ok)
    end)
    it("accepts a complete config", function()
        assert.is_true((HAClient.validate{ host = "h", port = 8123, token = "abc" }))
    end)
end)
