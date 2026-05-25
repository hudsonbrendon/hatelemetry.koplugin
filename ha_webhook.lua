-- Cliente de webhook do Home Assistant. Builders e parsing são puros (testáveis);
-- a chamada de rede carrega socket.http/ssl.https/ltn12/rapidjson de forma preguiçosa.
local HAWebhook = {}

function HAWebhook.build_url(cfg)
    local protocol = cfg.https == true and "https" or "http"
    return string.format("%s://%s:%d/api/webhook/%s",
        protocol, cfg.host, cfg.port, cfg.webhook_id)
end

-- json_encode: function(table) -> string
function HAWebhook.build_request(cfg, snapshot, json_encode)
    local body = json_encode(snapshot)
    return {
        url = HAWebhook.build_url(cfg),
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#body),
        },
        body = body,
    }
end

-- json_decode: function(string) -> table
-- Retorna sempre uma lista (array) de comandos (pode ser vazia).
function HAWebhook.parse_commands(response_body, json_decode)
    if not response_body or response_body == "" then return {} end
    local ok, decoded = pcall(json_decode, response_body)
    if not ok or type(decoded) ~= "table" then return {} end
    local cmds = decoded.commands
    if type(cmds) ~= "table" then return {} end
    return cmds
end

-- Envia o snapshot e devolve ok(boolean), commands(list), err(string|nil), kind(string|nil).
function HAWebhook.post(cfg, snapshot)
    local http = cfg.https == true and require("ssl.https") or require("socket.http")
    local ltn12 = require("ltn12")
    local rapidjson = require("rapidjson")

    local prev_timeout = http.TIMEOUT
    http.TIMEOUT = 6
    local req = HAWebhook.build_request(cfg, snapshot, rapidjson.encode)
    local response_body = {}
    local result, code = http.request{
        url = req.url,
        method = req.method,
        headers = req.headers,
        source = ltn12.source.string(req.body),
        sink = ltn12.sink.table(response_body),
    }
    http.TIMEOUT = prev_timeout

    if result == nil then
        return false, {}, tostring(code), "connection"
    elseif code ~= 200 and code ~= 201 then
        return false, {}, tostring(code) .. " | " .. table.concat(response_body), "http"
    end

    local commands = HAWebhook.parse_commands(table.concat(response_body), rapidjson.decode)
    return true, commands, nil, nil
end

return HAWebhook
