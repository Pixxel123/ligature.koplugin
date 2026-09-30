local T = require("helper")
local it = T.it

local KeyboardGeometry = T.load("keyboard_geometry")
local TraceCollector = T.load("trace_collector")
local GestureController = T.load("gesture_controller")

-- Number row 1 2 3, then q w e, then a s d: 100px square keys.
local function newLayout()
    local function rowOf(keys, y)
        local row = {}
        for index, key in ipairs(keys) do
            row[index] = {
                key = key,
                dimen = { x = (index - 1) * 100, y = y, w = 100, h = 100 },
            }
        end
        return row
    end
    return {
        rowOf({ "1", "2", "3" }, 0),
        rowOf({ "q", "w", "e" }, 100),
        rowOf({ "a", "s", "d" }, 200),
    }
end

-- A keyboard that records what the gesture controller finalizes.
local function newKeyboard(layout)
    local geometry = KeyboardGeometry:new(T.normalization)
    local keyboard = { layout = layout, finalized = {} }
    function keyboard:isSwypeMvpEnabled() return true end
    function keyboard:_swypeKeyAt(pos)
        return geometry:keyAt(self.layout, pos)
    end
    function keyboard:_swypeStartKeyAt(pos)
        return geometry:startKeyAt(self.layout, pos)
    end
    function keyboard:_swypeGetPreviousWord() end
    function keyboard:_swypeFinalizeSignature(signature, trace_info)
        table.insert(self.finalized, { signature = signature,
            trace_info = trace_info })
        return true
    end
    for _, name in ipairs({ "_swypeDrawTraceSegment", "_swypeClearTracePixels",
            "_swypeCancelBucketPrefetch", "_swypeScheduleBucketPrefetch",
            "_swypeCommitPendingContext", "_swypeClearCandidateState" }) do
        keyboard[name] = function() end
    end
    return keyboard
end

local function newController()
    local clock = { now = 0 }
    local time = {
        now = function()
            clock.now = clock.now + 1000
            return clock.now
        end,
        ms = function(ms) return ms * 1000 end,
    }
    local ui_manager = { scheduleIn = function() end }
    local geometry = { new = function(_, point) return point end }
    return GestureController:new(TraceCollector, ui_manager, time, geometry)
end

local function pan(start, pos)
    return { start_pos = start, pos = pos }
end

it("starts a slow swipe from the number row on the letter below", function()
    local keyboard = newKeyboard(newLayout())
    local controller = newController()
    local start = { x = 150, y = 90 }
    T.truthy(controller:onPan(keyboard, pan(start, { x = 150, y = 120 })))
    T.truthy(controller:onPan(keyboard, pan(start, { x = 250, y = 150 })))
    T.truthy(controller:onPanRelease(keyboard,
        pan(start, { x = 250, y = 250 })))
    T.eq(#keyboard.finalized, 1)
    T.eq(keyboard.finalized[1].signature, "wed")
end)

it("starts a swipe gesture from the number row on the letter below",
        function()
    local keyboard = newKeyboard(newLayout())
    local controller = newController()
    T.truthy(controller:onPathRelease(keyboard, {
        start_pos = { x = 250, y = 95 }, pos = { x = 50, y = 250 },
    }))
    T.eq(keyboard.finalized[1].signature, "ea")
end)

it("leaves the first point on the number key, so a short slide from it is known",
        function()
    local keyboard = newKeyboard(newLayout())
    local controller = newController()
    local start = { x = 150, y = 60 }
    T.truthy(controller:onPan(keyboard, pan(start, { x = 160, y = 70 })))
    T.truthy(controller:onPanRelease(keyboard, pan(start,
        { x = 165, y = 75 })))
    local finalized = keyboard.finalized[1]
    T.eq(finalized.signature, "w")
    T.eq(finalized.trace_info.released, true)
    local _, key = keyboard:_swypeKeyAt(finalized.trace_info.letter_points[1])
    T.eq(key.key, "2", "the trace still begins on the number key")
end)

it("ignores points on the number row after the start", function()
    local keyboard = newKeyboard(newLayout())
    local controller = newController()
    local start = { x = 150, y = 90 }
    controller:onPan(keyboard, pan(start, { x = 250, y = 60 }))
    controller:onPan(keyboard, pan(start, { x = 250, y = 150 }))
    controller:onPanRelease(keyboard, pan(start, { x = 250, y = 250 }))
    T.eq(keyboard.finalized[1].signature, "wed")
end)

it("takes no swipe from a number key with no letter below it", function()
    local layout = newLayout()
    layout[2] = nil
    layout[3] = nil
    local keyboard = newKeyboard(layout)
    local controller = newController()
    local start = { x = 150, y = 60 }
    T.eq(controller:onPan(keyboard, pan(start, { x = 250, y = 60 })), false)
    T.eq(controller:onPanRelease(keyboard, pan(start,
        { x = 250, y = 60 })), false)
    T.eq(controller:onPathRelease(keyboard, {
        start_pos = start, pos = { x = 250, y = 60 },
    }), false)
    T.eq(#keyboard.finalized, 0)
end)

it("still begins a swipe on a letter where it lands", function()
    local keyboard = newKeyboard(newLayout())
    local controller = newController()
    local start = { x = 150, y = 150 }
    controller:onPan(keyboard, pan(start, { x = 250, y = 150 }))
    controller:onPanRelease(keyboard, pan(start, { x = 250, y = 250 }))
    T.eq(keyboard.finalized[1].signature, "wed")
end)

it("reads a swipe's keys shifted by the learned touch offset, and draws "
        .. "it where the finger went", function()
    local keyboard = newKeyboard(newLayout())
    local drawn = {}
    function keyboard:_swypeDrawTraceSegment(_, point)
        drawn[#drawn + 1] = point.x
    end
    function keyboard:_swypeTouchShift() return { x = 70, y = 0 } end
    local controller = newController()
    local start = { x = 40, y = 150 }
    controller:onPan(keyboard, pan(start, { x = 140, y = 150 }))
    controller:onPanRelease(keyboard, pan(start, { x = 140, y = 250 }))
    local finalized = keyboard.finalized[1]
    T.eq(finalized.signature, "wed", "q w s read 70 px to the right")
    T.eq(finalized.trace_info.points[1].x, 110)
    T.eq(finalized.trace_info.touch_shift.x, 70)
    T.eq(drawn[1], 40, "the trail starts under the finger")
    T.eq(drawn[#drawn], 140)
    T.eq(keyboard.swype_mvp_touch_shift, nil, "forgotten after the swipe")
end)

it("reads a swipe as it went when no touch offset is learned", function()
    local keyboard = newKeyboard(newLayout())
    function keyboard:_swypeTouchShift() return nil end
    local controller = newController()
    local start = { x = 40, y = 150 }
    controller:onPan(keyboard, pan(start, { x = 140, y = 150 }))
    controller:onPanRelease(keyboard, pan(start, { x = 140, y = 250 }))
    T.eq(keyboard.finalized[1].signature, "qws")
    T.eq(keyboard.finalized[1].trace_info.touch_shift, nil)
end)
