-- Pure mapping from a telemetry snapshot (see snapshot.lua) to a list of
-- Home Assistant entity-state definitions. No KOReader / network coupling.
local Sensors = {}

-- snapshot: telemetry table. opts: { prefix = "koreader" }
-- returns: array of { entity_id = string, state = string, attributes = table }
function Sensors.build(snapshot, opts)
    opts = opts or {}
    local prefix = opts.prefix or "koreader"
    local out = {}

    local function entity(domain, name)
        return domain .. "." .. prefix .. "_" .. name
    end

    -- Always: reading status
    out[#out + 1] = {
        entity_id = entity("binary_sensor", "status"),
        state = snapshot.reading and "on" or "off",
        attributes = {
            friendly_name = "KOReader Status",
            icon = snapshot.reading and "mdi:book-open-variant" or "mdi:book-off",
            device_model = snapshot.device_model,
            book_title = snapshot.book_title,
            book_author = snapshot.book_author,
            last_seen = snapshot.last_seen,
        },
    }

    -- Always: charging + wifi (booleans are always known)
    out[#out + 1] = {
        entity_id = entity("binary_sensor", "charging"),
        state = snapshot.is_charging and "on" or "off",
        attributes = { friendly_name = "KOReader Charging", device_class = "battery_charging" },
    }
    out[#out + 1] = {
        entity_id = entity("binary_sensor", "wifi"),
        state = snapshot.wifi_connected and "on" or "off",
        attributes = { friendly_name = "KOReader WiFi", device_class = "connectivity" },
    }

    -- Value sensors: emitted only when present
    local function value_sensor(name, value, attributes)
        if value == nil then return end
        out[#out + 1] = {
            entity_id = entity("sensor", name),
            state = tostring(value),
            attributes = attributes,
        }
    end

    value_sensor("battery", snapshot.battery_level, {
        friendly_name = "KOReader Battery", device_class = "battery",
        unit_of_measurement = "%", state_class = "measurement" })
    value_sensor("frontlight", snapshot.frontlight, {
        friendly_name = "KOReader Frontlight", icon = "mdi:brightness-6",
        unit_of_measurement = "%", state_class = "measurement" })
    value_sensor("book_title", snapshot.book_title, {
        friendly_name = "KOReader Book Title", icon = "mdi:book" })
    value_sensor("book_author", snapshot.book_author, {
        friendly_name = "KOReader Book Author", icon = "mdi:account-edit" })
    value_sensor("progress", snapshot.progress_percent, {
        friendly_name = "KOReader Progress", icon = "mdi:percent",
        unit_of_measurement = "%", state_class = "measurement" })
    value_sensor("current_page", snapshot.current_page, {
        friendly_name = "KOReader Current Page", icon = "mdi:book-open-page-variant",
        state_class = "measurement" })
    value_sensor("total_pages", snapshot.total_pages, {
        friendly_name = "KOReader Total Pages", icon = "mdi:book-open-page-variant" })
    value_sensor("chapter", snapshot.chapter, {
        friendly_name = "KOReader Chapter", icon = "mdi:format-list-bulleted" })
    value_sensor("reading_time_today", snapshot.reading_time_today_min, {
        friendly_name = "KOReader Reading Time Today", device_class = "duration",
        unit_of_measurement = "min", state_class = "total_increasing" })
    value_sensor("pages_today", snapshot.pages_read_today, {
        friendly_name = "KOReader Pages Read Today", icon = "mdi:counter",
        state_class = "total_increasing" })
    value_sensor("session_time", snapshot.session_time_min, {
        friendly_name = "KOReader Session Time", device_class = "duration",
        unit_of_measurement = "min", state_class = "measurement" })
    value_sensor("reading_speed", snapshot.reading_speed_pph, {
        friendly_name = "KOReader Reading Speed", icon = "mdi:speedometer",
        unit_of_measurement = "pages/h", state_class = "measurement" })

    return out
end

return Sensors
