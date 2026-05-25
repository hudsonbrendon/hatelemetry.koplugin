-- Home Assistant REST client. Builders + validation are pure; the network
-- call lazily requires KOReader's bundled libs so tests can require this file.
local HAClient = {}

function HAClient.build_url(cfg, entity_id)
    local protocol = cfg.https == true and "https" or "http"
    return string.format("%s://%s:%d/api/states/%s",
        protocol, cfg.host, cfg.port, entity_id)
end

-- json_encode: function(table) -> string
function HAClient.build_request(cfg, entity, json_encode)
    local body = json_encode({ state = entity.state, attributes = entity.attributes })
    return {
        url = HAClient.build_url(cfg, entity.entity_id),
        method = "POST",
        headers = {
            ["Authorization"] = "Bearer " .. cfg.token,
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#body),
        },
        body = body,
    }
end

-- Returns ok(boolean), message(string|nil)
function HAClient.validate(cfg)
    if not cfg.host or cfg.host == "" then return false, "host is empty" end
    if type(cfg.port) ~= "number" then return false, "port must be a number" end
    if not cfg.token or cfg.token == "" or cfg.token:find("PasteYour") then
        return false, "token is not set"
    end
    return true, nil
end

-- Posts one entity state. Returns ok(boolean), error(string|nil).
function HAClient.post(cfg, entity)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local rapidjson = require("rapidjson")

    http.TIMEOUT = 6
    local req = HAClient.build_request(cfg, entity, rapidjson.encode)
    local response_body = {}
    local result, code = http.request{
        url = req.url,
        method = req.method,
        headers = req.headers,
        source = ltn12.source.string(req.body),
        sink = ltn12.sink.table(response_body),
    }

    if result == nil then
        return false, tostring(code)
    elseif code ~= 200 and code ~= 201 then
        return false, tostring(code) .. " | " .. table.concat(response_body)
    end
    return true, nil
end

return HAClient
