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
