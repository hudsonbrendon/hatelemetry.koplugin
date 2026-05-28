local Snapshot = require("snapshot")

local function fake_device(opts)
    opts = opts or {}
    return {
        model = opts.model or "Kindle Oasis",
        hasBattery = function() return opts.has_battery ~= false end,
        hasFrontlight = function() return opts.has_frontlight == true end,
        hasNaturalLight = function() return opts.has_natural_light == true end,
    }
end

local function fake_powerd(opts)
    opts = opts or {}
    return {
        getCapacity = function() return opts.capacity or 90 end,
        isCharging = function() return opts.charging == true end,
        frontlightIntensity = function() return opts.frontlight or 10 end,
        isFrontlightOn = function() return opts.frontlight_on ~= false end,
        frontlightWarmth = function() return opts.warmth or 0 end,
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

    it("calcula pages_left e pages_left_chapter via toc.getChapterPagesLeft", function()
        local ui = {
            document = { getPageCount = function() return 200 end },
            doc_props = {},
            doc_settings = { readSetting = function() return nil end },
            toc = {
                getTocTitleByPage = function(_, p) return "Ch" end,
                getChapterPagesLeft = function(_, p) return 15 end,
            },
        }
        local s = Snapshot.collect{
            device = fake_device(), powerd = fake_powerd{},
            network = fake_network(true), ui = ui, cur_page = 120,
            now = function() return "T" end,
        }
        assert.are.equal(80, s.pages_left)           -- 200 - 120
        assert.are.equal(15, s.pages_left_chapter)
    end)

    it("calcula time_to_finish_book_min e time_to_finish_chapter_min a partir da velocidade", function()
        -- reading_speed_pph = round(30 pages / 0.5h) = 60 pph
        -- pages_left = 200 - 120 = 80; time = round(80/60*60) = 80 min
        -- pages_left_chapter = 15; time = round(15/60*60) = 15 min
        local ui = {
            document = { getPageCount = function() return 200 end },
            doc_props = {},
            doc_settings = { readSetting = function() return nil end },
            toc = {
                getTocTitleByPage = function(_, p) return "Ch" end,
                getChapterPagesLeft = function(_, p) return 15 end,
            },
            statistics = {
                getTodayBookStats = function() return 1800, 30 end, -- 30 pages in 30 min → 60 pph
                getCurrentBookStats = function() return 0 end,
            },
        }
        local s = Snapshot.collect{
            device = fake_device(), powerd = fake_powerd{},
            network = fake_network(true), ui = ui, cur_page = 120,
            now = function() return "T" end,
        }
        assert.are.equal(60, s.reading_speed_pph)
        assert.are.equal(80, s.time_to_finish_book_min)
        assert.are.equal(15, s.time_to_finish_chapter_min)
    end)

    it("captura book_language, book_series e book_format a partir de doc_props e document.file", function()
        local ui = {
            document = {
                getPageCount = function() return 100 end,
                file = "/books/mybook.epub",
            },
            doc_props = {
                language = "pt-BR",
                series = "Foundation",
            },
            doc_settings = { readSetting = function() return nil end },
        }
        local s = Snapshot.collect{
            device = fake_device(), powerd = fake_powerd{},
            network = fake_network(true), ui = ui, cur_page = 10,
            now = function() return "T" end,
        }
        assert.are.equal("pt-BR", s.book_language)
        assert.are.equal("Foundation", s.book_series)
        assert.are.equal("EPUB", s.book_format)
    end)

    it("captura total_time_min do sidecar e annotations_count", function()
        local ui = {
            document = { getPageCount = function() return 100 end },
            doc_props = {},
            doc_settings = {
                readSetting = function(_, key)
                    if key == "stats" then
                        return { total_time_in_sec = 7200 } -- 120 min
                    end
                    return nil
                end,
            },
            annotation = {
                getNumberOfHighlightsAndNotes = function() return 7 end,
            },
        }
        local s = Snapshot.collect{
            device = fake_device(), powerd = fake_powerd{},
            network = fake_network(true), ui = ui, cur_page = 50,
            now = function() return "T" end,
        }
        assert.are.equal(120, s.total_time_min)
        assert.are.equal(7, s.annotations_count)
    end)

    it("captura koreader_version a partir das deps", function()
        local s = Snapshot.collect{
            device = fake_device(), powerd = fake_powerd{},
            network = fake_network(true), ui = { document = nil },
            koreader_version = "v2024.04",
            now = function() return "T" end,
        }
        assert.are.equal("v2024.04", s.koreader_version)
    end)

    it("separa highlights_count e notes_count da lista de anotações", function()
        local ui = {
            document = { getPageCount = function() return 100 end },
            doc_props = {},
            annotation = {
                getNumberOfHighlightsAndNotes = function() return 4 end,
                annotations = {
                    { page = 1 },
                    { page = 2, note = "uma nota" },
                    { page = 3 },
                    { page = 4, note = "outra nota" },
                },
            },
        }
        local s = Snapshot.collect{
            device = fake_device(), powerd = fake_powerd{},
            network = fake_network(true), ui = ui, cur_page = 10,
            now = function() return "T" end,
        }
        assert.are.equal(2, s.highlights_count)
        assert.are.equal(2, s.notes_count)
    end)

    it("reporta frontlight_on quando o dispositivo tem frontlight", function()
        local s = Snapshot.collect{
            device = fake_device{ has_frontlight = true },
            powerd = fake_powerd{ frontlight_on = true },
            network = fake_network(true),
            ui = { document = nil },
            now = function() return "T" end,
        }
        assert.is_true(s.frontlight_on)
    end)

    it("reporta warmth quando o dispositivo tem luz natural", function()
        local s = Snapshot.collect{
            device = fake_device{ has_frontlight = true, has_natural_light = true },
            powerd = fake_powerd{ warmth = 42 },
            network = fake_network(true),
            ui = { document = nil },
            now = function() return "T" end,
        }
        assert.are.equal(42, s.warmth)
    end)

    it("nao reporta warmth quando o dispositivo nao tem luz natural", function()
        local s = Snapshot.collect{
            device = fake_device{ has_natural_light = false },
            powerd = fake_powerd{ warmth = 42 },
            network = fake_network(true),
            ui = { document = nil },
            now = function() return "T" end,
        }
        assert.is_nil(s.warmth)
    end)
end)
