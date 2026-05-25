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

    it("emits the extended reading + device sensors when present", function()
        local snap = {
            reading = true,
            pages_left = 209, pages_left_chapter = 12,
            time_to_finish_book_min = 140, time_to_finish_chapter_min = 8,
            book_series = "Foundation", book_format = "EPUB", book_language = "en",
            total_time_min = 320, annotations_count = 7,
            warmth = 25, frontlight_on = true,
        }
        local e = Sensors.build(snap, {})
        assert.are.equal("209", find(e, "sensor.koreader_pages_left").state)
        assert.are.equal("12", find(e, "sensor.koreader_pages_left_in_chapter").state)
        assert.are.equal("140", find(e, "sensor.koreader_time_to_finish_book").state)
        assert.are.equal("8", find(e, "sensor.koreader_time_to_finish_chapter").state)
        assert.are.equal("Foundation", find(e, "sensor.koreader_book_series").state)
        assert.are.equal("EPUB", find(e, "sensor.koreader_book_format").state)
        assert.are.equal("en", find(e, "sensor.koreader_book_language").state)
        assert.are.equal("320", find(e, "sensor.koreader_total_reading_time").state)
        assert.are.equal("7", find(e, "sensor.koreader_annotations").state)
        assert.are.equal("25", find(e, "sensor.koreader_warmth").state)
        assert.are.equal("on", find(e, "binary_sensor.koreader_frontlight_on").state)
    end)

    it("omits the extended sensors when their values are nil", function()
        local e = Sensors.build({ reading = true }, {})
        assert.is_nil(find(e, "sensor.koreader_pages_left"))
        assert.is_nil(find(e, "sensor.koreader_total_reading_time"))
        assert.is_nil(find(e, "sensor.koreader_annotations"))
        assert.is_nil(find(e, "binary_sensor.koreader_frontlight_on"))
    end)
end)
