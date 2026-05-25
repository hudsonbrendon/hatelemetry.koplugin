-- Copy this file to ha_config.lua and fill in your details.
-- ha_config.lua is gitignored so your token never gets committed.
return {
    host = "192.168.1.10", -- Home Assistant IP or hostname
    port = 8123,           -- HA port (usually 8123, or 443 for HTTPS)
    https = false,         -- true if HA uses HTTPS; recommended if HA is reachable beyond your trusted LAN (token is sent in cleartext over http)
    token = "PasteYourHomeAssistantLong-LivedAccessTokenHere",
}
