local T = require("helper")
local it = T.it

-- A reference over stand-ins for KOReader's widgets and a screen whose
-- size can change, recording what it shows, closes and schedules.
local function setup(values, back_keys)
    local calls = { shown = {}, closed = {}, scheduled = {}, painted = 0 }
    values = values or {}
    local size = { w = 1272, h = 1696 }
    local function widget()
        return { new = function(_, o) return o end }
    end
    local reference = T.load("gesture_reference"):new{
        settings = {
            isTrue = function(_, key) return values[key] == true end,
            saveSetting = function(_, key, value) values[key] = value end,
            flush = function()
                calls.flushed = (calls.flushed or 0) + 1
            end,
        },
        ui_manager = {
            show = function(_, view, refresh)
                calls.shown[#calls.shown + 1] = { view, refresh }
            end,
            close = function(_, view, refresh)
                calls.closed[#calls.closed + 1] = { view, refresh }
            end,
            scheduleIn = function(_, delay, fn)
                calls.scheduled[#calls.scheduled + 1] = { delay, fn }
            end,
        },
        screen = {
            getWidth = function() return size.w end,
            getHeight = function() return size.h end,
        },
        input_container = {
            new = function(_, o)
                o.paintTo = function() calls.painted = calls.painted + 1 end
                return o
            end,
        },
        frame_container = widget(),
        image_widget = widget(),
        geometry = widget(),
        blitbuffer = { COLOR_WHITE = "white" },
        image = "/plugin/images/gesture_reference.png",
        back_keys = back_keys,
    }
    return reference, calls, values, size
end

-- A key press that matches the Back key group only.
local function key(is_back)
    return { match = function() return is_back end }
end

it("shows the page full screen, scaled to fit and centred, on white, "
        .. "above the keyboard", function()
    local reference, calls = setup()
    local view = reference:show()
    T.eq(calls.shown[1][1], view)
    T.eq(calls.shown[1][2], "flashui")
    T.eq(view.modal, true, "above the keyboard, which is modal")
    T.eq(view.covers_fullscreen, true)
    T.eq(view.dimen.w, 1272)
    T.eq(view.dimen.h, 1696)
    local frame = view[1]
    T.eq(frame.background, "white")
    local image = frame[1]
    T.eq(image.file, "/plugin/images/gesture_reference.png")
    T.eq(image.scale_factor, 0, "best fit, centred by the image itself")
    T.eq(image.width, 1272)
    T.eq(image.height, 1696)
end)

it("lays itself out again when the screen turns", function()
    local reference, calls, _, size = setup()
    local view = reference:show()
    size.w, size.h = 1696, 1272
    view:paintTo({}, 0, 0)
    T.eq(view.dimen.w, 1696)
    T.eq(view[1][1].width, 1696)
    T.eq(view[1][1].height, 1272)
    T.eq(calls.painted, 1)
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

it("closes on Back, and takes every other key so none is typed into the "
        .. "text box underneath", function()
    local asked = 0
    local reference, calls = setup(nil, function()
        asked = asked + 1
        return { "Back" }
    end)
    local view = reference:show()
    T.eq(asked, 1, "asked when it opens, in case keys came later")
    T.eq(view:onKeyPress(key(false)), true, "a letter is taken")
    T.eq(view:onKeyRepeat(key(false)), true)
    T.eq(view:onKeyRelease(key(false)), true)
    T.eq(#calls.closed, 0)
    T.eq(view:onKeyPress(key(true)), true)
    T.eq(calls.closed[1][1], view, "closed by Back")

    local keyless, keyless_calls = setup(nil, function() return nil end)
    local plain = keyless:show()
    T.eq(plain:onKeyPress(key(true)), true, "still taken")
    T.eq(#keyless_calls.closed, 0, "no Back without keys")
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
    reference:open()
    T.eq(#calls.shown, 2, "from the menu")
end)

it("writes the settings just after showing the page, not before it or "
        .. "only when KOReader exits", function()
    local reference, calls = setup()
    reference:showOnce()
    T.eq(calls.flushed, nil, "not before the page is drawn")
    T.eq(#calls.scheduled, 1)
    T.eq(calls.scheduled[1][1], reference.FLUSH_DELAY)
    calls.scheduled[1][2]()
    T.eq(calls.flushed, 1)
end)

it("counts opening it from the menu as the first-run showing", function()
    local reference, calls, values = setup()
    reference:open()
    T.eq(values[reference.SETTING_KEY], true)
    T.eq(reference:due(), false)
    T.eq(reference:showOnce(), false, "not again by itself")
    T.eq(#calls.shown, 1)
    reference:open()
    T.eq(#calls.scheduled, 1, "written once")
end)

it("ships the page as a 1272 by 1696 PNG", function()
    local path = T.plugin_dir .. "/images/gesture_reference.png"
    local f = assert(io.open(path, "rb"), path)
    local head = f:read(24)
    f:close()
    T.eq(head:sub(1, 8), "\137PNG\r\n\26\n", "a PNG")
    local function be32(s)
        local a, b, c, d = s:byte(1, 4)
        return ((a * 256 + b) * 256 + c) * 256 + d
    end
    T.eq(be32(head:sub(17, 20)), 1272, "width")
    T.eq(be32(head:sub(21, 24)), 1696, "height")
end)
