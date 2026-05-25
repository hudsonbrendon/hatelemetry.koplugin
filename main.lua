--- hatelemetry.koplugin
-- Pushes KOReader reading + device telemetry to Home Assistant via the REST API.

local _ = require("gettext")
local UIManager = require("ui/uimanager")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Device = require("device")
local powerd = Device:getPowerDevice()
local NetworkMgr = require("ui/network/manager")
local logger = require("logger")

local Snapshot = require("snapshot")
local Sensors = require("sensors")
local HAClient = require("ha_client")
local HAWebhook = require("ha_webhook")
local Commands = require("commands")

-- Prefer a local debug config during development; fall back to ha_config.lua.
local ok, ha_config = pcall(require, "ha_debug_config")
if not ok then
    ha_config = require("ha_config")
end

local HATelemetry = WidgetContainer:extend{
    name = "hatelemetry",
    is_doc_only = false,
}

HATelemetry.default_settings = {
    entity_prefix = "koreader",
    enabled = false,
    loop_enabled = false,
    interval = 300,   -- periodic push interval (s) while awake
    resume_delay = 8, -- wait after wake for WiFi (s)
}

function HATelemetry:loadSettings()
    local saved = G_reader_settings:readSetting("hatelemetry") or {}
    self.settings = {}
    for k, default in pairs(self.default_settings) do
        self.settings[k] = (saved[k] ~= nil) and saved[k] or default
    end
end

function HATelemetry:saveSettings()
    G_reader_settings:saveSetting("hatelemetry", self.settings)
    G_reader_settings:flush()
end

function HATelemetry:init()
    self.ui.menu:registerToMainMenu(self)
    self:loadSettings()

    if not HATelemetry._initialized then
        HATelemetry._initialized = true
        if self.settings.loop_enabled then
            self:pushLoop(true)
        end
        if self.settings.enabled then
            self:push(true)
        end
    end
end

--- Track current page (fires in ReaderUI on open and on each page turn).
function HATelemetry:onPageUpdate(pageno)
    self.cur_page = pageno
end

--- Build a telemetry snapshot from current runtime state.
-- reading_override: force the "reading" flag (e.g. false on suspend).
function HATelemetry:collect(reading_override)
    local snap = Snapshot.collect{
        device = Device,
        powerd = powerd,
        network = NetworkMgr,
        ui = self.ui,
        cur_page = self.cur_page,
    }
    if reading_override ~= nil then
        snap.reading = reading_override
    end
    return snap
end

--- Constrói as dependências usadas para aplicar comandos no Kindle.
function HATelemetry:commandDeps()
    return {
        powerd = powerd,
        network = NetworkMgr,
        show_message = function(text, timeout)
            local msg = InfoMessage:new{ text = text }
            UIManager:show(msg)
            if tonumber(timeout) then
                UIManager:scheduleIn(tonumber(timeout), function() UIManager:close(msg) end)
            end
        end,
        request_sync = function()
            -- Reenvia a telemetria no próximo ciclo curto.
            UIManager:scheduleIn(1, self.push, self, true)
        end,
    }
end

--- Coleta o snapshot e envia ao Home Assistant (webhook nativo ou REST legado).
function HATelemetry:push(reading)
    if not NetworkMgr:isConnected() then
        if not self._offline_logged then
            logger.info("[HATelemetry]: sem rede, pulando envio")
            self._offline_logged = true
        end
        return
    end
    self._offline_logged = false

    local snap = self:collect(reading)

    local use_webhook = ha_config.webhook_id ~= nil
        and ha_config.webhook_id ~= ""
        and ha_config.webhook_id ~= "ColeSeuWebhookIdAqui"

    if use_webhook then
        local ok_post, commands, err = HAWebhook.post(ha_config, snap)
        if not ok_post then
            logger.info("[HATelemetry]: webhook falhou -", err)
            return
        end
        if commands and #commands > 0 then
            Commands.apply_all(commands, self:commandDeps())
        end
        return
    end

    -- Modo legado: um POST por entidade em /api/states.
    local entities = Sensors.build(snap, { prefix = self.settings.entity_prefix })
    for _, entity in ipairs(entities) do
        local ok_post, err, kind = HAClient.post(ha_config, entity)
        if not ok_post then
            logger.info("[HATelemetry]: push falhou para", entity.entity_id, "-", err)
            if kind == "connection" then
                break
            end
        end
    end
end

--- Periodic push loop that reschedules itself while awake.
function HATelemetry:pushLoop(skip_first)
    if not self.settings.loop_enabled then return end
    if not skip_first then
        self:push(true)
    end
    UIManager:scheduleIn(self.settings.interval, self.pushLoop, self)
end

-- Lifecycle events --------------------------------------------------------

function HATelemetry:onReaderReady()
    if self.settings.enabled then self:push(true) end
end

function HATelemetry:onCloseDocument()
    if self.settings.enabled then self:push(true) end
end

function HATelemetry:onSuspend()
    if self.settings.loop_enabled then
        UIManager:unschedule(self.pushLoop)
    end
    if self.settings.enabled then
        UIManager:unschedule(self.push) -- cancel any delayed "on"
        self:push(false)
    end
end

function HATelemetry:onResume()
    if self.settings.loop_enabled then
        self:pushLoop(true)
    end
    if self.settings.enabled then
        -- wait for WiFi to reconnect, then push "on"
        UIManager:scheduleIn(self.settings.resume_delay, self.push, self, true)
    end
end

function HATelemetry:addToMainMenu(menu_items)
    local sub = {}

    table.insert(sub, {
        text = "Send telemetry on sleep/wake & open/close",
        checked_func = function() return self.settings.enabled end,
        callback = function()
            self.settings.enabled = not self.settings.enabled
            if not self.settings.enabled and self.settings.loop_enabled then
                self.settings.loop_enabled = false
                UIManager:unschedule(self.pushLoop)
            end
            self:saveSettings()
            self:push(self.settings.enabled and true or false)
        end,
    })

    table.insert(sub, {
        text = "Periodic updates while awake",
        separator = true,
        enabled_func = function() return self.settings.enabled end,
        checked_func = function() return self.settings.loop_enabled end,
        callback = function()
            self.settings.loop_enabled = not self.settings.loop_enabled
            self:saveSettings()
            if self.settings.loop_enabled then
                self:pushLoop(true)
            else
                UIManager:unschedule(self.pushLoop)
            end
        end,
    })

    table.insert(sub, {
        text_func = function()
            return string.format("Entity prefix: '%s'", self.settings.entity_prefix)
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            local dialog
            dialog = InputDialog:new{
                title = "Set entity prefix",
                input = self.settings.entity_prefix,
                input_type = "string",
                buttons = {{
                    { text = _("Cancel"), id = "close",
                      callback = function() UIManager:close(dialog) end },
                    { text = _("Set"), is_enter_default = true,
                      callback = function()
                          local v = dialog:getInputText()
                          if v and v ~= "" then
                              local clean = v:lower():gsub("[%s%-]+", "_")
                                  :gsub("[^%w_]", ""):gsub("^_+", ""):gsub("_+$", "")
                              if clean ~= "" then
                                  self.settings.entity_prefix = clean
                                  self:saveSettings()
                                  if self.settings.enabled then self:push(true) end
                                  touchmenu_instance:updateItems()
                              end
                          end
                          UIManager:close(dialog)
                      end },
                }},
            }
            UIManager:show(dialog)
            dialog:onShowKeyboard()
        end,
    })

    table.insert(sub, {
        text_func = function()
            return string.format("Update interval (s): %d", self.settings.interval)
        end,
        separator = true,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            local dialog
            dialog = InputDialog:new{
                title = "Set update interval (seconds)",
                input = tostring(self.settings.interval),
                input_type = "number",
                buttons = {{
                    { text = _("Cancel"), id = "close",
                      callback = function() UIManager:close(dialog) end },
                    { text = _("Set"), is_enter_default = true,
                      callback = function()
                          local v = tonumber(dialog:getInputText())
                          if v and v > 0 then
                              self.settings.interval = v
                              self:saveSettings()
                              if self.settings.loop_enabled then
                                  UIManager:unschedule(self.pushLoop)
                                  self:pushLoop(true)
                              end
                              touchmenu_instance:updateItems()
                          end
                          UIManager:close(dialog)
                      end },
                }},
            }
            UIManager:show(dialog)
            dialog:onShowKeyboard()
        end,
    })

    table.insert(sub, {
        text = "Test connection",
        keep_menu_open = true,
        callback = function()
            local ok_cfg, msg = HAClient.validate(ha_config)
            if not ok_cfg then
                UIManager:show(InfoMessage:new{ text = "Config error: " .. msg })
                return
            end
            local ok_post, err = HAClient.post(ha_config, {
                entity_id = "binary_sensor." .. self.settings.entity_prefix .. "_status",
                state = "on",
                attributes = {
                    friendly_name = "KOReader Status",
                    last_seen = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                },
            })
            if ok_post then
                UIManager:show(InfoMessage:new{ text = "Success!" })
            else
                UIManager:show(InfoMessage:new{ text = "Failure:\n" .. tostring(err) })
            end
        end,
    })

    table.insert(sub, {
        text = "Show current snapshot",
        keep_menu_open = true,
        callback = function()
            local snap = self:collect()
            local keys = {
                "reading", "device_model", "battery_level", "is_charging", "frontlight",
                "wifi_connected", "book_title", "book_author", "current_page", "total_pages",
                "progress_percent", "chapter", "reading_time_today_min", "pages_read_today",
                "session_time_min", "reading_speed_pph", "last_seen",
            }
            local lines = {}
            for _, k in ipairs(keys) do
                lines[#lines + 1] = string.format("%s: %s", k, tostring(snap[k]))
            end
            UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n") })
        end,
    })

    menu_items.hatelemetry = {
        text = "\u{ECF5} HA Telemetry",
        sorting_hint = "tools",
        sub_item_table = sub,
    }
end

return HATelemetry
