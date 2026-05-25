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
