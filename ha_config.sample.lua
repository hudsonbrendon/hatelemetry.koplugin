-- Copy this file to ha_config.lua and fill in your details.
-- ha_config.lua is gitignored so your token never gets committed.
return {
    host = "192.168.1.10", -- Home Assistant IP or hostname
    port = 8123,           -- HA port (usually 8123, or 443 for HTTPS)
    https = false,         -- true only if HA is served over HTTPS
    token = "PasteYourHomeAssistantLong-LivedAccessTokenHere",
}
