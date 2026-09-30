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

-- A keyboard whose learned touch offset shifts swipes by shift, and whose
-- letter keys the offset was worked out for are keys.
local function shiftingKeyboard(shift, keys)
    local keyboard = newKeyboard(newLayout())
    function keyboard:_swypeTouchShift() return shift, keys end
    return keyboard
end

it("keeps a swipe as the finger went, and gives recognition its keys "
        .. "read shifted by the learned touch offset", function()
    local keys = {}
    local keyboard = shiftingKeyboard({ x = 70, y = 0 }, keys)
    local controller = newController()
    local start = { x = 40, y = 150 }
    controller:onPan(keyboard, pan(start, { x = 140, y = 150 }))
    controller:onPanRelease(keyboard, pan(start, { x = 140, y = 250 }))
    local finalized = keyboard.finalized[1]
    T.eq(finalized.signature, "qws", "as the finger went")
    T.eq(finalized.trace_info.points[1].x, 40)
    local recognition = finalized.trace_info.recognition
    T.eq(recognition.signature, "wed", "q w s read 70 px to the right")
    T.eq(recognition.trace_info.points[1].x, 110)
    T.eq(recognition.trace_info.released, true)
    T.eq(finalized.trace_info.touch_keys, keys)
end)

it("keeps a swipe's start where the finger touched when the shift takes "
        .. "it off every key", function()
    local keyboard = shiftingKeyboard({ x = 60, y = 0 })
    local controller = newController()
    local start = { x = 260, y = 150 }
    controller:onPan(keyboard, pan(start, { x = 110, y = 150 }))
    controller:onPanRelease(keyboard, pan(start, { x = 10, y = 150 }))
    local finalized = keyboard.finalized[1]
    T.eq(finalized.signature, "ewq")
    -- Moved 60 px right, the start is past the keyboard's edge: it stays
    -- on e, where the finger touched, rather than losing the e.
    local recognition = finalized.trace_info.recognition
    T.eq(recognition.signature, "ewq")
    T.eq(recognition.trace_info.points[1].x, 260)
    T.eq(recognition.trace_info.points[2].x, 170)
end)

it("shifts nothing for a tap, and nothing with no offset learned",
        function()
    local keyboard = shiftingKeyboard({ x = 70, y = 0 })
    local controller = newController()
    local start = { x = 40, y = 150 }
    controller:onPanRelease(keyboard, pan(start, { x = 45, y = 150 }))
    T.eq(keyboard.finalized[1].signature, "q")
    T.eq(keyboard.finalized[1].trace_info.recognition, nil, "a tap")

    local plain = shiftingKeyboard(nil)
    controller:onPan(plain, pan(start, { x = 140, y = 150 }))
    controller:onPanRelease(plain, pan(start, { x = 140, y = 250 }))
    T.eq(plain.finalized[1].signature, "qws")
    T.eq(plain.finalized[1].trace_info.recognition, nil)
end)
