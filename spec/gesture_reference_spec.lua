local T = require("helper")
local it = T.it

-- A reference over stand-ins for KOReader's widgets, recording what it
-- shows and closes.
local function setup(values, back_keys)
    local calls = { shown = {}, closed = {} }
    values = values or {}
    local function widget()
        return { new = function(_, o) return o end }
    end
    local reference = T.load("gesture_reference"):new{
        settings = {
            isTrue = function(_, key) return values[key] == true end,
            saveSetting = function(_, key, value) values[key] = value end,
        },
        ui_manager = {
            show = function(_, view, refresh)
                calls.shown[#calls.shown + 1] = { view, refresh }
            end,
            close = function(_, view, refresh)
                calls.closed[#calls.closed + 1] = { view, refresh }
            end,
        },
        screen = {
            getWidth = function() return 1272 end,
            getHeight = function() return 1696 end,
        },
        input_container = widget(),
        frame_container = widget(),
        center_container = widget(),
        image_widget = widget(),
        geometry = widget(),
        blitbuffer = { COLOR_WHITE = "white" },
        image = "/plugin/images/gesture_reference.png",
        back_keys = back_keys,
    }
    return reference, calls, values
end

it("shows the page full screen, scaled to fit, on white", function()
    local reference, calls = setup()
    local view = reference:show()
    T.eq(calls.shown[1][1], view)
    T.eq(calls.shown[1][2], "flashui")
    T.eq(view.dimen.w, 1272)
    T.eq(view.dimen.h, 1696)
    T.eq(view.modal, true, "above the keyboard, which is modal")
    local frame = view[1]
    T.eq(frame.background, "white")
    local image = frame[1][1]
    T.eq(image.file, "/plugin/images/gesture_reference.png")
    T.eq(image.scale_factor, 0, "best fit")
    T.eq(image.width, 1272)
    T.eq(image.height, 1696)
end)

it("closes on a tap anywhere, and takes every other gesture so none "
        .. "reaches the keyboard underneath", function()
    local reference, calls = setup()
    local view = reference:show()
    T.eq(view:onGesture({ ges = "swipe" }), true, "swipe taken")
    T.eq(view:onGesture({ ges = "pan" }), true, "pan taken")
    T.eq(view:onGesture({ ges = "hold" }), true, "hold taken")
    T.eq(#calls.closed, 0, "still open")
    T.eq(view:onGesture({ ges = "tap" }), true)
    T.eq(calls.closed[1][1], view, "closed by a tap")
end)

it("closes on Back where the device has keys", function()
    local back = { "Back" }
    local reference, calls = setup(nil, back)
    local view = reference:show()
    T.eq(view.key_events.TaplessCloseReference[1], back)
    view:onTaplessCloseReference()
    T.eq(calls.closed[1][1], view)
    local keyless = setup()
    T.eq(keyless:show().key_events, nil, "no keys, no key events")
end)

it("shows once on first run, then only when asked", function()
    local reference, calls, values = setup()
    T.truthy(reference:due())
    T.truthy(reference:showOnce())
    T.eq(#calls.shown, 1)
    T.eq(values[reference.SETTING_KEY], true, "remembered")
    T.eq(reference:due(), false)
    T.eq(reference:showOnce(), false)
    T.eq(#calls.shown, 1, "not again")
    reference:show()
    T.eq(#calls.shown, 2, "from the menu")
end)
