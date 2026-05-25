# KOReader → Home Assistant Telemetry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a KOReader plugin (`hatelemetry.koplugin`) that pushes the maximum useful reading + device telemetry from a jailbroken Kindle Oasis into Home Assistant as graphable sensors, over Home Assistant's REST API.

**Architecture:** Fork the proven `heartbeat.koplugin` (moritz-john) approach. KOReader events (`onReaderReady`, `onPageUpdate`, `onSuspend`, `onResume`, `onCloseDocument`) trigger a *collect → map → push* pipeline. The plugin is split into focused modules: `snapshot.lua` (the only module coupled to KOReader runtime objects) gathers a plain telemetry table; `sensors.lua` (pure) maps that table to a list of Home Assistant entity-state definitions; `ha_client.lua` (pure builders + a thin POST) talks to HA's `POST /api/states/<entity_id>` REST endpoint with a long-lived access token. Pure modules are unit-tested with `busted`; the KOReader-coupled glue is verified on-device with a built-in "Show current snapshot" debug menu and HA's *Developer Tools → States*.

**Tech Stack:** Lua 5.1 / LuaJIT (KOReader runtime), KOReader plugin API (`WidgetContainer`), `socket.http` + `ltn12` + `rapidjson` (bundled in KOReader), Home Assistant REST API. Tests: `busted` (run on host macOS). HA side: Lovelace dashboard + automations YAML.

**Why REST (not MQTT):** KOReader ships **no MQTT client**. The REST API path is proven by `heartbeat.koplugin` and needs only HTTP, which KOReader already bundles. Decision locked with the user.

**Scope (locked with user):** Telemetry only — Kindle → HA. Rich reading sensors + device sensors. *Not* in scope: controlling HA from the Kindle, or controlling the Kindle from HA.

**Known limitation to communicate:** Entities created via `POST /api/states` are runtime states, not config entities — they do **not** survive a Home Assistant restart. They reappear on the next telemetry push (next wake / page turn / periodic loop). Long-term history still works via the recorder while they exist. This is documented in Task 7.

---

## Reference: verified KOReader API surface

These are confirmed from `heartbeat.koplugin` source and KOReader `readerfooter.lua` / `statistics.koplugin`. Use exactly these calls.

| Datum | Call | Notes |
|---|---|---|
| Device model | `Device.model` | string |
| Has battery | `Device:hasBattery()` | bool |
| Battery % | `powerd:getCapacity()` | 0–100; `powerd = Device:getPowerDevice()` |
| Charging | `powerd:isCharging()` | bool |
| Has frontlight | `Device:hasFrontlight()` | bool |
| Frontlight level | `powerd:frontlightIntensity()` | guard with `hasFrontlight()` + `pcall` |
| Network up | `NetworkMgr:isConnected()` | `NetworkMgr = require("ui/network/manager")` |
| Book title | `self.ui.doc_props.display_title` | only when a doc is open |
| Book authors | `self.ui.doc_props.authors` | newline-separated; join with `, ` |
| Total pages | `self.ui.document:getPageCount()` | |
| Current page | `onPageUpdate(pageno)` event, fallback `self.ui.view.state.page` | track in plugin |
| Progress fraction | `self.ui.doc_settings:readSetting("percent_finished")` | 0–1, persisted, reliable |
| Chapter title | `self.ui.toc:getTocTitleByPage(page)` | |
| Today time+pages | `self.ui.statistics:getTodayBookStats()` | returns `(seconds, pages)` |
| Session time+pages | `self.ui.statistics:getCurrentBookStats()` | returns `(seconds, pages)` |
| Stats DB (optional) | `DataStorage:getSettingsDir() .. "/statistics.sqlite3"` | table `book(total_read_time, md5, ...)` |
| HA set state | `POST http(s)://host:port/api/states/<entity_id>` | header `Authorization: Bearer <token>` |

Plugin folder layout (all paths below are under the project root `/Users/hudsonbrendon/Github/hatelemetry.koplugin/`):

```
hatelemetry.koplugin/
  _meta.lua            # plugin metadata
  main.lua             # WidgetContainer: events, push pipeline, settings, menu
  snapshot.lua         # collect telemetry from KOReader objects (only KOReader-coupled module)
  sensors.lua          # pure: snapshot table -> list of HA entity definitions
  ha_client.lua        # pure builders + thin REST POST
  ha_config.sample.lua # template connection config (committed)
  ha_config.lua        # real connection config (gitignored)
  .busted              # busted lpath config
  .gitignore
  README.md
  spec/
    smoke_spec.lua
    sensors_spec.lua
    snapshot_spec.lua
    ha_client_spec.lua
  docs/
    home-assistant/
      dashboard.yaml
      automations.yaml
    superpowers/plans/2026-05-25-koreader-ha-telemetry.md  # this file
```

---

## Task 0: Project scaffold, git, and test toolchain

**Files:**
- Create: `/Users/hudsonbrendon/Github/hatelemetry.koplugin/_meta.lua`
- Create: `/Users/hudsonbrendon/Github/hatelemetry.koplugin/ha_config.sample.lua`
- Create: `/Users/hudsonbrendon/Github/hatelemetry.koplugin/.gitignore`
- Create: `/Users/hudsonbrendon/Github/hatelemetry.koplugin/.busted`
- Test: `/Users/hudsonbrendon/Github/hatelemetry.koplugin/spec/smoke_spec.lua`

- [ ] **Step 1: Install the Lua test toolchain (macOS)**

Run:
```bash
brew install luarocks
luarocks install busted
```
Expected: `busted` resolves. Verify:
```bash
busted --version
```
Expected: prints a version number (e.g. `2.x`).

- [ ] **Step 2: Create the project directory and initialize git**

Run:
```bash
mkdir -p /Users/hudsonbrendon/Github/hatelemetry.koplugin/spec
mkdir -p /Users/hudsonbrendon/Github/hatelemetry.koplugin/docs/home-assistant
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin && git init
```
Expected: `Initialized empty Git repository`.

- [ ] **Step 3: Write `_meta.lua`**

`_meta.lua`:
```lua
return {
    name = "hatelemetry",
    fullname = "HA Telemetry",
    description = "Pushes KOReader reading and device telemetry to Home Assistant via its REST API.",
    version = "v0.1.0",
}
```

- [ ] **Step 4: Write `ha_config.sample.lua`**

`ha_config.sample.lua`:
```lua
-- Copy this file to ha_config.lua and fill in your details.
-- ha_config.lua is gitignored so your token never gets committed.
return {
    host = "192.168.1.10", -- Home Assistant IP or hostname
    port = 8123,           -- HA port (usually 8123, or 443 for HTTPS)
    https = false,         -- true only if HA is served over HTTPS
    token = "PasteYourHomeAssistantLong-LivedAccessTokenHere",
}
```

- [ ] **Step 5: Write `.gitignore`**

`.gitignore`:
```
ha_config.lua
ha_debug_config.lua
*.zip
```

- [ ] **Step 6: Write `.busted`**

`.busted`:
```lua
return {
    default = {
        lpath = "./?.lua;./?/init.lua",
        pattern = "_spec",
    },
}
```

- [ ] **Step 7: Write the toolchain smoke test**

`spec/smoke_spec.lua`:
```lua
describe("toolchain", function()
    it("runs busted", function()
        assert.are.equal(4, 2 + 2)
    end)
end)
```

- [ ] **Step 8: Run the smoke test**

Run (from the plugin dir):
```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin && busted
```
Expected: `1 success / 0 failures`.

- [ ] **Step 9: Commit**

```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin
git add _meta.lua ha_config.sample.lua .gitignore .busted spec/smoke_spec.lua
git commit -m "chore: scaffold hatelemetry.koplugin with busted toolchain"
```

---

## Task 1: `sensors.lua` — pure snapshot → HA entities mapping

**Files:**
- Create: `/Users/hudsonbrendon/Github/hatelemetry.koplugin/sensors.lua`
- Test: `/Users/hudsonbrendon/Github/hatelemetry.koplugin/spec/sensors_spec.lua`

This module is pure (no KOReader, no network). It takes a telemetry snapshot table and returns the list of Home Assistant entities to set. A sensor is emitted only when its value is present (non-`nil`), so unknown values don't clobber HA history with garbage. The `status` and `charging`/`wifi` binary sensors are always emitted.

- [ ] **Step 1: Write the failing test**

`spec/sensors_spec.lua`:
```lua
local Sensors = require("sensors")

local function find(entities, id)
    for _, e in ipairs(entities) do
        if e.entity_id == id then return e end
    end
    return nil
end

describe("Sensors.build", function()
    it("always emits the status binary_sensor reflecting reading state", function()
        assert.are.equal("on", find(Sensors.build({ reading = true }, {}),
            "binary_sensor.koreader_status").state)
        assert.are.equal("off", find(Sensors.build({ reading = false }, {}),
            "binary_sensor.koreader_status").state)
    end)

    it("honours a custom entity prefix", function()
        local e = Sensors.build({ reading = true }, { prefix = "oasis" })
        assert.is_not_nil(find(e, "binary_sensor.oasis_status"))
    end)

    it("emits a battery sensor with battery device_class when present", function()
        local bat = find(Sensors.build({ reading = true, battery_level = 87 }, {}),
            "sensor.koreader_battery")
        assert.are.equal("87", bat.state)
        assert.are.equal("battery", bat.attributes.device_class)
        assert.are.equal("%", bat.attributes.unit_of_measurement)
    end)

    it("omits sensors whose snapshot value is nil", function()
        local e = Sensors.build({ reading = true }, {})
        assert.is_nil(find(e, "sensor.koreader_battery"))
        assert.is_nil(find(e, "sensor.koreader_progress"))
        assert.is_nil(find(e, "sensor.koreader_chapter"))
    end)

    it("maps charging to a battery_charging binary_sensor", function()
        local c = find(Sensors.build({ reading = true, is_charging = true }, {}),
            "binary_sensor.koreader_charging")
        assert.are.equal("on", c.state)
        assert.are.equal("battery_charging", c.attributes.device_class)
    end)

    it("emits reading sensors when present", function()
        local snap = {
            reading = true, progress_percent = 42, current_page = 130,
            total_pages = 310, chapter = "Chapter 5",
            reading_time_today_min = 35, pages_read_today = 40,
            session_time_min = 12, reading_speed_pph = 68,
        }
        local e = Sensors.build(snap, {})
        assert.are.equal("42", find(e, "sensor.koreader_progress").state)
        assert.are.equal("130", find(e, "sensor.koreader_current_page").state)
        assert.are.equal("310", find(e, "sensor.koreader_total_pages").state)
        assert.are.equal("Chapter 5", find(e, "sensor.koreader_chapter").state)
        assert.are.equal("35", find(e, "sensor.koreader_reading_time_today").state)
        assert.are.equal("68", find(e, "sensor.koreader_reading_speed").state)
    end)
end)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin && busted spec/sensors_spec.lua
```
Expected: FAIL with `module 'sensors' not found`.

- [ ] **Step 3: Write `sensors.lua`**

`sensors.lua`:
```lua
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
    local function num_sensor(name, value, attributes)
        if value == nil then return end
        out[#out + 1] = {
            entity_id = entity("sensor", name),
            state = tostring(value),
            attributes = attributes,
        }
    end

    num_sensor("battery", snapshot.battery_level, {
        friendly_name = "KOReader Battery", device_class = "battery",
        unit_of_measurement = "%", state_class = "measurement" })
    num_sensor("frontlight", snapshot.frontlight, {
        friendly_name = "KOReader Frontlight", icon = "mdi:brightness-6",
        unit_of_measurement = "%", state_class = "measurement" })
    num_sensor("book_title", snapshot.book_title, {
        friendly_name = "KOReader Book Title", icon = "mdi:book" })
    num_sensor("book_author", snapshot.book_author, {
        friendly_name = "KOReader Book Author", icon = "mdi:account-edit" })
    num_sensor("progress", snapshot.progress_percent, {
        friendly_name = "KOReader Progress", icon = "mdi:percent",
        unit_of_measurement = "%", state_class = "measurement" })
    num_sensor("current_page", snapshot.current_page, {
        friendly_name = "KOReader Current Page", icon = "mdi:book-open-page-variant",
        state_class = "measurement" })
    num_sensor("total_pages", snapshot.total_pages, {
        friendly_name = "KOReader Total Pages", icon = "mdi:book-open-page-variant" })
    num_sensor("chapter", snapshot.chapter, {
        friendly_name = "KOReader Chapter", icon = "mdi:format-list-bulleted" })
    num_sensor("reading_time_today", snapshot.reading_time_today_min, {
        friendly_name = "KOReader Reading Time Today", device_class = "duration",
        unit_of_measurement = "min", state_class = "total_increasing" })
    num_sensor("pages_today", snapshot.pages_read_today, {
        friendly_name = "KOReader Pages Read Today", icon = "mdi:counter",
        state_class = "total_increasing" })
    num_sensor("session_time", snapshot.session_time_min, {
        friendly_name = "KOReader Session Time", device_class = "duration",
        unit_of_measurement = "min", state_class = "measurement" })
    num_sensor("reading_speed", snapshot.reading_speed_pph, {
        friendly_name = "KOReader Reading Speed", icon = "mdi:speedometer",
        unit_of_measurement = "pages/h", state_class = "measurement" })

    return out
end

return Sensors
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin && busted spec/sensors_spec.lua
```
Expected: PASS (6 successes / 0 failures).

- [ ] **Step 5: Commit**

```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin
git add sensors.lua spec/sensors_spec.lua
git commit -m "feat: add pure snapshot->HA entity mapping (sensors.lua)"
```

---

## Task 2: `snapshot.lua` — collect telemetry from KOReader objects

**Files:**
- Create: `/Users/hudsonbrendon/Github/hatelemetry.koplugin/snapshot.lua`
- Test: `/Users/hudsonbrendon/Github/hatelemetry.koplugin/spec/snapshot_spec.lua`

This is the only module coupled to KOReader, but it receives all runtime objects via a `deps` table (dependency injection), so it is fully unit-testable with fakes. It reads battery/frontlight/network always, and book/progress/chapter/stats only when a document is open.

- [ ] **Step 1: Write the failing test**

`spec/snapshot_spec.lua`:
```lua
local Snapshot = require("snapshot")

local function fake_device(opts)
    opts = opts or {}
    return {
        model = opts.model or "Kindle Oasis",
        hasBattery = function() return opts.has_battery ~= false end,
        hasFrontlight = function() return opts.has_frontlight == true end,
    }
end

local function fake_powerd(opts)
    opts = opts or {}
    return {
        getCapacity = function() return opts.capacity or 90 end,
        isCharging = function() return opts.charging == true end,
        frontlightIntensity = function() return opts.frontlight or 10 end,
    }
end

local function fake_network(connected)
    return { isConnected = function() return connected ~= false end }
end

describe("Snapshot.collect", function()
    it("reports device + power telemetry with no document open", function()
        local s = Snapshot.collect{
            device = fake_device(),
            powerd = fake_powerd{ capacity = 73, charging = true },
            network = fake_network(true),
            ui = { document = nil },
            now = function() return "T" end,
        }
        assert.is_false(s.reading)
        assert.are.equal("Kindle Oasis", s.device_model)
        assert.are.equal(73, s.battery_level)
        assert.is_true(s.is_charging)
        assert.is_true(s.wifi_connected)
        assert.is_nil(s.book_title)
    end)

    it("reads book metadata, pages, percent and chapter when a doc is open", function()
        local ui = {
            document = { getPageCount = function() return 310 end },
            doc_props = { display_title = "Dune", authors = "Frank Herbert" },
            doc_settings = {
                readSetting = function(_, key)
                    if key == "percent_finished" then return 0.5 end
                end,
            },
            toc = { getTocTitleByPage = function(_, p) return "Chapter X" end },
            view = { state = { page = 155 } },
        }
        local s = Snapshot.collect{
            device = fake_device(), powerd = fake_powerd{},
            network = fake_network(true), ui = ui, cur_page = 155,
            now = function() return "T" end,
        }
        assert.is_true(s.reading)
        assert.are.equal("Dune", s.book_title)
        assert.are.equal("Frank Herbert", s.book_author)
        assert.are.equal(310, s.total_pages)
        assert.are.equal(155, s.current_page)
        assert.are.equal(50, s.progress_percent)
        assert.are.equal("Chapter X", s.chapter)
    end)

    it("derives reading speed from today's statistics", function()
        local ui = {
            document = { getPageCount = function() return 100 end },
            doc_props = {},
            doc_settings = { readSetting = function() return nil end },
            statistics = {
                getTodayBookStats = function() return 1800, 30 end, -- 30 min, 30 pages
                getCurrentBookStats = function() return 600, 10 end, -- 10 min session
            },
        }
        local s = Snapshot.collect{
            device = fake_device(), powerd = fake_powerd{},
            network = fake_network(true), ui = ui, cur_page = 50,
            now = function() return "T" end,
        }
        assert.are.equal(30, s.reading_time_today_min)
        assert.are.equal(30, s.pages_read_today)
        assert.are.equal(60, s.reading_speed_pph) -- 30 pages / 0.5h
        assert.are.equal(10, s.session_time_min)
    end)
end)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin && busted spec/snapshot_spec.lua
```
Expected: FAIL with `module 'snapshot' not found`.

- [ ] **Step 3: Write `snapshot.lua`**

`snapshot.lua`:
```lua
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin && busted spec/snapshot_spec.lua
```
Expected: PASS (3 successes / 0 failures).

- [ ] **Step 5: Commit**

```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin
git add snapshot.lua spec/snapshot_spec.lua
git commit -m "feat: collect KOReader telemetry into a plain snapshot table"
```

---

## Task 3: `ha_client.lua` — REST builders + thin POST

**Files:**
- Create: `/Users/hudsonbrendon/Github/hatelemetry.koplugin/ha_client.lua`
- Test: `/Users/hudsonbrendon/Github/hatelemetry.koplugin/spec/ha_client_spec.lua`

URL building, request building, and config validation are pure and tested. The actual network call (`post`) lazily requires KOReader's bundled `socket.http` / `ltn12` / `rapidjson` so this module can be `require`d under `busted` without those libs; `post` is verified on-device in Task 6.

- [ ] **Step 1: Write the failing test**

`spec/ha_client_spec.lua`:
```lua
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin && busted spec/ha_client_spec.lua
```
Expected: FAIL with `module 'ha_client' not found`.

- [ ] **Step 3: Write `ha_client.lua`**

`ha_client.lua`:
```lua
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin && busted spec/ha_client_spec.lua
```
Expected: PASS (5 successes / 0 failures).

- [ ] **Step 5: Run the full suite**

Run:
```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin && busted
```
Expected: all specs pass (smoke + sensors + snapshot + ha_client).

- [ ] **Step 6: Commit**

```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin
git add ha_client.lua spec/ha_client_spec.lua
git commit -m "feat: add HA REST client builders, validation, and POST"
```

---

## Task 4: `main.lua` core — events + push pipeline + settings

**Files:**
- Create: `/Users/hudsonbrendon/Github/hatelemetry.koplugin/main.lua`

`main.lua` cannot be unit-tested off-device (it needs the live KOReader environment), so verification here is a static syntax check plus an explicit on-device check in Task 6. This task writes the full plugin entry point: settings load/save, page tracking, the collect→build→push pipeline, and the KOReader lifecycle event handlers. The menu is added in Task 5.

- [ ] **Step 1: Write `main.lua` (core, no menu yet)**

`main.lua`:
```lua
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
```

- [ ] **Step 2: Syntax-check the file with LuaJIT (or lua)**

Run (uses whatever Lua `luarocks`/`brew` installed; this only checks it parses — KOReader `require`s will be unresolved, which is expected):
```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin && luajit -bl main.lua >/dev/null && echo "PARSE OK"
```
If `luajit` is not installed, use:
```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin && luac -p main.lua && echo "PARSE OK"
```
Expected: prints `PARSE OK` with no syntax error. (Do **not** try to `require`/run it — KOReader modules only exist on-device.)

- [ ] **Step 3: Confirm the test suite still passes (modules unchanged)**

Run:
```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin && busted
```
Expected: all specs pass (main.lua is not imported by any spec).

- [ ] **Step 4: Commit**

```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin
git add main.lua
git commit -m "feat: add plugin core (events, push pipeline, settings)"
```

---

## Task 5: `main.lua` menu — config UI, test, and debug snapshot

**Files:**
- Modify: `/Users/hudsonbrendon/Github/hatelemetry.koplugin/main.lua` (add `addToMainMenu` before the final `return HATelemetry`)

Adds a *Tools → HA Telemetry* menu: enable toggle, periodic-updates toggle, entity prefix, update interval, a "Test connection" action (validates config then posts the status entity), and a "Show current snapshot" debugging view that renders the collected telemetry as text — essential for the on-device verification in Task 6.

- [ ] **Step 1: Add the `addToMainMenu` function**

Insert this function in `main.lua` immediately **before** the final `return HATelemetry` line:

```lua
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
```

- [ ] **Step 2: Syntax-check again**

Run:
```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin && luac -p main.lua && echo "PARSE OK"
```
Expected: `PARSE OK`.

- [ ] **Step 3: Commit**

```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin
git add main.lua
git commit -m "feat: add HA Telemetry config/test/debug menu"
```

---

## Task 6: Deploy to the Kindle and verify end-to-end

**Files:**
- Create: `/Users/hudsonbrendon/Github/hatelemetry.koplugin/ha_config.lua` (local, gitignored — created from the sample)

This task has no automated tests; it is the real end-to-end verification on the device against a live Home Assistant.

- [ ] **Step 1: Create a Home Assistant long-lived access token**

In Home Assistant: click your **profile** (bottom-left) → **Security** tab → scroll to **Long-lived access tokens** → **Create token**. Name it `koreader`. Copy the token (shown once).

- [ ] **Step 2: Create the local `ha_config.lua`**

Run (edit values to match your HA):
```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin && cp ha_config.sample.lua ha_config.lua
```
Then edit `ha_config.lua` and set `host`, `port`, `https`, and paste your `token`.

- [ ] **Step 3: Copy the plugin folder to the Kindle**

Connect the Kindle via USB (it mounts as a volume, typically named `Kindle`). KOReader plugins live in `koreader/plugins/`. Copy the whole folder (excluding the dev-only files):
```bash
rsync -av --exclude 'spec' --exclude 'docs' --exclude '.git' --exclude '.busted' \
  /Users/hudsonbrendon/Github/hatelemetry.koplugin \
  /Volumes/Kindle/koreader/plugins/
```
> If your KOReader install path differs (e.g. `/mnt/us/koreader/plugins/` accessed over SSH), copy there instead. The plugin folder name **must** keep the `.koplugin` suffix.

- [ ] **Step 4: Restart KOReader and confirm the menu appears**

Safely eject the Kindle. In KOReader: **top menu → Tools** and confirm **HA Telemetry** appears (it has a heart-pulse icon). If it's missing, check `koreader/crash.log` on the device for a load error.

- [ ] **Step 5: Test the connection**

Open **Tools → HA Telemetry → Test connection** while the Kindle is on WiFi.
Expected: an InfoMessage saying **"Success!"**. If it shows "Config error", fix `ha_config.lua`. If it shows "Failure: …", note the HTTP code (401 = bad token, connection refused = wrong host/port).

- [ ] **Step 6: Inspect the snapshot**

Open a book, then **Tools → HA Telemetry → Show current snapshot**.
Expected: a populated list — `reading: true`, `book_title`, `current_page`, `total_pages`, `progress_percent`, `battery_level`, etc. Note any field showing `nil` that you expected to be set (e.g. stats fields are `nil` if the Statistics plugin is disabled — enable it under Tools if so).

- [ ] **Step 7: Enable telemetry and verify entities in Home Assistant**

In the menu, toggle **"Send telemetry on sleep/wake & open/close"** ON. Turn a page or two.
In Home Assistant: **Developer Tools → States**, filter by your prefix (`koreader`).
Expected: entities present and populated, e.g. `binary_sensor.koreader_status` (on), `sensor.koreader_battery`, `sensor.koreader_progress`, `sensor.koreader_current_page`, `sensor.koreader_chapter`, `sensor.koreader_reading_time_today`, `sensor.koreader_reading_speed`, `binary_sensor.koreader_charging`, `binary_sensor.koreader_wifi`.

- [ ] **Step 8: Verify the sleep transition**

Put the Kindle to sleep. After a moment check **Developer Tools → States**.
Expected: `binary_sensor.koreader_status` flips to **off** (sent just before WiFi drops on suspend).

- [ ] **Step 9: Finalize the README and commit**

`README.md`:
```markdown
# hatelemetry.koplugin

A KOReader plugin that pushes reading + device telemetry to Home Assistant via
its REST API. Tested on a jailbroken Kindle Oasis running KOReader.

## What it reports

Entities (prefix configurable, default `koreader`):

- `binary_sensor.koreader_status` — reading on/off (+ book title/author, model, last_seen attributes)
- `binary_sensor.koreader_charging`, `binary_sensor.koreader_wifi`
- `sensor.koreader_battery`, `sensor.koreader_frontlight`
- `sensor.koreader_book_title`, `sensor.koreader_book_author`
- `sensor.koreader_progress`, `sensor.koreader_current_page`, `sensor.koreader_total_pages`, `sensor.koreader_chapter`
- `sensor.koreader_reading_time_today`, `sensor.koreader_pages_today`, `sensor.koreader_session_time`, `sensor.koreader_reading_speed`

## Install

1. In Home Assistant create a long-lived access token (Profile → Security).
2. `cp ha_config.sample.lua ha_config.lua` and fill in host/port/https/token.
3. Copy this folder to `koreader/plugins/` on your device. Restart KOReader.
4. Tools → HA Telemetry → Test connection, then enable telemetry.

## Limitation

Entities are created via `POST /api/states` and do not survive a Home Assistant
restart; they reappear on the next push (wake / page turn / periodic loop).

## Development

```bash
brew install luarocks && luarocks install busted
busted            # run unit tests
```

## Credits

Architecture and the proven REST approach are based on
[moritz-john/heartbeat.koplugin](https://github.com/moritz-john/heartbeat.koplugin) (MIT).
```

```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin
git add README.md
git commit -m "docs: add README with install, entities, and limitations"
```

---

## Task 7: Home Assistant dashboard + automations

**Files:**
- Create: `/Users/hudsonbrendon/Github/hatelemetry.koplugin/docs/home-assistant/dashboard.yaml`
- Create: `/Users/hudsonbrendon/Github/hatelemetry.koplugin/docs/home-assistant/automations.yaml`

These are HA-side configs the user pastes into Home Assistant. No unit tests; verified by loading them in HA.

- [ ] **Step 1: Write the Lovelace dashboard**

`docs/home-assistant/dashboard.yaml`:
```yaml
# Add as a new manual dashboard, or paste cards into an existing view.
# Replace the `koreader` prefix if you changed the entity prefix.
title: Kindle
views:
  - title: Kindle
    cards:
      - type: entities
        title: KOReader
        entities:
          - entity: binary_sensor.koreader_status
            name: Reading
          - entity: sensor.koreader_book_title
            name: Book
          - entity: sensor.koreader_book_author
            name: Author
          - entity: sensor.koreader_chapter
            name: Chapter
          - entity: sensor.koreader_current_page
            name: Page
          - entity: sensor.koreader_total_pages
            name: Total pages
          - entity: binary_sensor.koreader_charging
            name: Charging
          - entity: binary_sensor.koreader_wifi
            name: WiFi

      - type: gauge
        entity: sensor.koreader_progress
        name: Progress
        unit: "%"
        min: 0
        max: 100
        severity:
          green: 66
          yellow: 33
          red: 0

      - type: gauge
        entity: sensor.koreader_battery
        name: Battery
        unit: "%"
        min: 0
        max: 100
        severity:
          green: 40
          yellow: 20
          red: 0

      - type: history-graph
        title: Reading over time
        hours_to_show: 168
        entities:
          - entity: sensor.koreader_reading_time_today
          - entity: sensor.koreader_pages_today
          - entity: sensor.koreader_reading_speed

      - type: history-graph
        title: Reading sessions
        hours_to_show: 72
        entities:
          - entity: binary_sensor.koreader_status
```

- [ ] **Step 2: Write example automations**

`docs/home-assistant/automations.yaml`:
```yaml
# Paste into Settings → Automations (YAML mode), or append to automations.yaml.

# Turn on the reading lamp when you start reading after dark.
- alias: "KOReader: reading lamp on when reading starts"
  trigger:
    - platform: state
      entity_id: binary_sensor.koreader_status
      from: "off"
      to: "on"
  condition:
    - condition: state
      entity_id: sun.sun
      state: below_horizon
  action:
    - service: light.turn_on
      target:
        entity_id: light.reading_lamp

# Turn the lamp off when you stop reading (sleep).
- alias: "KOReader: reading lamp off when reading stops"
  trigger:
    - platform: state
      entity_id: binary_sensor.koreader_status
      from: "on"
      to: "off"
  action:
    - service: light.turn_off
      target:
        entity_id: light.reading_lamp

# Notify when the Kindle battery is low and not charging.
- alias: "KOReader: low battery alert"
  trigger:
    - platform: numeric_state
      entity_id: sensor.koreader_battery
      below: 15
  condition:
    - condition: state
      entity_id: binary_sensor.koreader_charging
      state: "off"
  action:
    - service: notify.notify
      data:
        title: "Kindle battery low"
        message: "Kindle at {{ states('sensor.koreader_battery') }}% — plug it in."
```

- [ ] **Step 3: Verify in Home Assistant**

Paste `dashboard.yaml` into a new manual dashboard (Settings → Dashboards → ⋮ → raw config editor) and confirm cards render with live values. Add one automation from `automations.yaml`, trigger it (turn a page after dark / let battery sensor cross threshold) and confirm it fires.

> **Persistence note (state in the docs):** Because the entities are set via the REST `/api/states` endpoint, they are recreated on each push but are lost on HA restart until the next push. For uninterrupted long-term history, keep the recorder enabled (default) and consider enabling **Periodic updates** in the plugin so the entities are refreshed regularly while the device is awake.

- [ ] **Step 4: Commit**

```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin
git add docs/home-assistant/dashboard.yaml docs/home-assistant/automations.yaml
git commit -m "docs: add Home Assistant dashboard and example automations"
```

---

## Task 8 (OPTIONAL / STRETCH): total reading time for the current book

**Files:**
- Modify: `/Users/hudsonbrendon/Github/hatelemetry.koplugin/snapshot.lua`
- Modify: `/Users/hudsonbrendon/Github/hatelemetry.koplugin/sensors.lua`
- Modify: `/Users/hudsonbrendon/Github/hatelemetry.koplugin/spec/sensors_spec.lua`

Adds `total_time_min` (lifetime reading time for the current book), read from KOReader's `statistics.sqlite3` via its bundled `lua-ljsqlite3` binding. Only attempt this after Task 6 confirms the base works; it touches the live stats DB read-only. Verify on-device with **Show current snapshot** that the book's `md5` is available before relying on it.

- [ ] **Step 1: Add the `total_time_min` mapping test**

Append to `spec/sensors_spec.lua` inside the `describe("Sensors.build", ...)` block:
```lua
    it("emits total reading time when present", function()
        local e = Sensors.build({ reading = true, total_time_min = 540 }, {})
        local t = nil
        for _, x in ipairs(e) do
            if x.entity_id == "sensor.koreader_total_time" then t = x end
        end
        assert.are.equal("540", t.state)
        assert.are.equal("duration", t.attributes.device_class)
    end)
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin && busted spec/sensors_spec.lua
```
Expected: FAIL — `attempt to index a nil value (local 't')`.

- [ ] **Step 3: Add the sensor mapping**

In `sensors.lua`, add this `num_sensor` call alongside the other reading sensors (e.g. right after the `session_time` one):
```lua
    num_sensor("total_time", snapshot.total_time_min, {
        friendly_name = "KOReader Total Reading Time", device_class = "duration",
        unit_of_measurement = "min", state_class = "total_increasing" })
```

- [ ] **Step 4: Run the sensors test to verify it passes**

Run:
```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin && busted spec/sensors_spec.lua
```
Expected: PASS.

- [ ] **Step 5: Add the DB read in `snapshot.lua`**

Add this helper near the top of `snapshot.lua` (after `round`):
```lua
-- Reads lifetime reading time (minutes) for the current book from
-- statistics.sqlite3. Best-effort: returns nil if anything is unavailable.
local function total_book_time_min(ui)
    if not (ui and ui.doc_settings) then return nil end
    local stats = ui.doc_settings:readSetting("stats")
    local md5 = stats and stats.md5
    if not md5 then return nil end

    local ok_sq, SQ3 = pcall(require, "lua-ljsqlite3/init")
    if not ok_sq then return nil end
    local ok_ds, DataStorage = pcall(require, "datastorage")
    if not ok_ds then return nil end

    local db_path = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local ok_read, minutes = pcall(function()
        local conn = SQ3.open(db_path, "ro")
        local stmt = conn:prepare("SELECT total_read_time FROM book WHERE md5 = ?")
        local row = stmt:reset():bind(md5):step()
        conn:close()
        if row and row[1] then
            return math.floor(tonumber(row[1]) / 60)
        end
        return nil
    end)
    if ok_read then return minutes end
    return nil
end
```

Then, inside `Snapshot.collect`, within the `if has_doc then` block (e.g. right after the statistics section), add:
```lua
        s.total_time_min = total_book_time_min(ui)
```

- [ ] **Step 6: Add `total_time` to the debug menu key list**

In `main.lua`, in the "Show current snapshot" `keys` list, add `"total_time_min"` so it's visible on-device.

- [ ] **Step 7: Run the full suite, syntax-check, deploy, verify**

Run:
```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin && busted && luac -p main.lua && echo OK
```
Expected: all pass + `OK`. Then redeploy (Task 6 Step 3), open a book with prior reading history, and **Show current snapshot** — confirm `total_time_min` is a number (not `nil`). Then check `sensor.koreader_total_time` in HA.

> If `total_time_min` stays `nil`, the book's `md5` was not in `doc_settings.stats`, or the stats DB schema differs on your KOReader build. Leave the helper in place (it fails safe to `nil`) and skip the sensor — do not block on this stretch task.

- [ ] **Step 8: Commit**

```bash
cd /Users/hudsonbrendon/Github/hatelemetry.koplugin
git add snapshot.lua sensors.lua spec/sensors_spec.lua main.lua
git commit -m "feat: add lifetime reading time per book from statistics.sqlite3"
```

---

## Self-Review

**Spec coverage:**
- "máximo de informações do Kindle" → battery, charging, frontlight, wifi, model (device sensors); title, author, progress %, current/total pages, chapter, today time, today pages, session time, reading speed, (optional) lifetime time (reading sensors). ✅ Tasks 1–2, 8.
- "exibisse essas informações" → HA dashboard with entities/gauges/history graphs. ✅ Task 7.
- "alterar sensores" → interpreted as creating/updating HA sensors from the Kindle (locked scope: telemetry only). Push pipeline creates and updates all entities. ✅ Tasks 4, 6. (Bidirectional control was explicitly out of scope per the user's answers.)
- "via integração ou MQTT" → researched; MQTT rejected (no KOReader client) in favor of the proven REST API. ✅ documented in header.
- "informações vão vindo com o koreader para o HomeAssistant" → push on events + optional periodic loop. ✅ Task 4.

**Placeholder scan:** No `TBD`/`implement later`. Every code step has complete, copy-paste-ready code.

**Type consistency checks:**
- Snapshot keys produced in `snapshot.lua` (`reading, device_model, battery_level, is_charging, frontlight, wifi_connected, book_title, book_author, current_page, total_pages, progress_percent, chapter, reading_time_today_min, pages_read_today, session_time_min, reading_speed_pph, last_seen`, + Task 8 `total_time_min`) exactly match the keys consumed in `sensors.lua` and listed in the debug menu. ✅
- `HAClient.build_request(cfg, entity, json_encode)` signature matches its call inside `HAClient.post`. ✅
- `Sensors.build(snapshot, opts)` with `opts.prefix` matches the call in `main.lua` (`{ prefix = self.settings.entity_prefix }`). ✅
- `Snapshot.collect{ device, powerd, network, ui, cur_page, now }` matches the deps built in `HATelemetry:collect`. ✅
- Settings keys (`entity_prefix, enabled, loop_enabled, interval, resume_delay`) are consistent between `default_settings`, `loadSettings`, the menu, and the event handlers. ✅
- `getTodayBookStats()`/`getCurrentBookStats()` both return `(seconds, pages)` and are unpacked in that order. ✅

---

## Execution Handoff

(Filled in by the chat after this plan is saved.)
