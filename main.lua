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

--- Collect + push every sensor to Home Assistant.
function HATelemetry:push(reading)
    if not NetworkMgr:isConnected() then
        if not self._offline_logged then
            logger.info("[HATelemetry]: no network, skipping push")
            self._offline_logged = true
        end
        return
    end
    self._offline_logged = false

    local snap = self:collect(reading)
    local entities = Sensors.build(snap, { prefix = self.settings.entity_prefix })

    for _, entity in ipairs(entities) do
        local ok_post, err = HAClient.post(ha_config, entity)
        if not ok_post then
            logger.info("[HATelemetry]: push failed for", entity.entity_id, "-", err)
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

return HATelemetry
