-- Collects a plain telemetry table from KOReader runtime objects.
-- All KOReader coupling is isolated here; objects arrive via the deps table
-- so this module is fully unit-testable with fakes.
local Snapshot = {}

local function round(x)
    if x == nil then return nil end
    return math.floor(x + 0.5)
end

-- deps = {
--   device   = Device,                 -- require("device")
--   powerd   = Device:getPowerDevice(),
--   network  = NetworkMgr,             -- require("ui/network/manager")
--   ui       = plugin.ui,              -- ReaderUI / FileManager instance (may have no document)
--   cur_page = number|nil,             -- last page from onPageUpdate
--   now      = function() return ISO8601 string end,
-- }
function Snapshot.collect(deps)
    local device, powerd, network, ui = deps.device, deps.powerd, deps.network, deps.ui
    local now = deps.now or function() return os.date("!%Y-%m-%dT%H:%M:%SZ") end

    local s = {}
    s.last_seen = now()
    s.device_model = device.model

    -- Power
    if device:hasBattery() then
        s.battery_level = powerd:getCapacity()
        s.is_charging = powerd:isCharging() and true or false
    else
        s.is_charging = false
    end

    -- Frontlight (guarded; not all devices have one)
    if device:hasFrontlight() then
        local ok, level = pcall(function() return powerd:frontlightIntensity() end)
        if ok then s.frontlight = level end
    end

    -- Network
    s.wifi_connected = network:isConnected() and true or false

    -- Reading state
    local has_doc = ui ~= nil and ui.document ~= nil
    s.reading = has_doc and true or false

    if has_doc then
        local props = ui.doc_props or {}
        if props.display_title and props.display_title ~= "" then
            s.book_title = props.display_title
        end
        if props.authors and props.authors ~= "" then
            s.book_author = props.authors:gsub("\n", ", ")
        end

        local total = ui.document:getPageCount()
        if total and total > 0 then s.total_pages = total end

        -- Current page: prefer event-tracked value, fall back to view state
        local cur = deps.cur_page
        if cur == nil and ui.view and ui.view.state then
            cur = ui.view.state.page
        end

        -- Progress fraction: persisted value is most reliable across formats
        local frac
        if ui.doc_settings then
            frac = ui.doc_settings:readSetting("percent_finished")
        end
        if frac == nil and cur and s.total_pages then
            frac = cur / s.total_pages
        end
        if frac ~= nil then s.progress_percent = round(frac * 100) end

        if cur == nil and frac and s.total_pages then
            cur = round(frac * s.total_pages)
        end
        if cur then s.current_page = cur end

        -- Chapter title
        if ui.toc and cur then
            local ok, title = pcall(function() return ui.toc:getTocTitleByPage(cur) end)
            if ok and title and title ~= "" then s.chapter = title end
        end

        -- Reading statistics (statistics plugin may be disabled)
        local stats = ui.statistics
        if stats then
            local ok_today, today_sec, today_pages = pcall(function()
                return stats:getTodayBookStats()
            end)
            if ok_today and today_sec then
                s.reading_time_today_min = round(today_sec / 60)
                s.pages_read_today = today_pages
                if today_sec > 0 and today_pages then
                    s.reading_speed_pph = round(today_pages / (today_sec / 3600))
                end
            end

            local ok_sess, sess_sec = pcall(function()
                return stats:getCurrentBookStats()
            end)
            if ok_sess and sess_sec then
                s.session_time_min = round(sess_sec / 60)
            end
        end
    end

    return s
end

return Snapshot
