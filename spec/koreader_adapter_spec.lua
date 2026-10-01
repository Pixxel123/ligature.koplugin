local T = require("helper")
local it = T.it

-- KOReader's VirtualKeyboard, reduced to the methods Tapless wraps.
local function newKeyboardClass(calls)
    local VirtualKeyboard = {}
    VirtualKeyboard.__index = VirtualKeyboard
    function VirtualKeyboard:init() end
    function VirtualKeyboard:onShow() end
    function VirtualKeyboard:onCloseWidget()
        calls.stock_close = (calls.stock_close or 0) + 1
    end
    function VirtualKeyboard:_refresh(want_flash, fullscreen)
        calls.refresh_calls = calls.refresh_calls or {}
        table.insert(calls.refresh_calls,
            { want_flash = want_flash, fullscreen = fullscreen })
    end
    return VirtualKeyboard
end

-- A text box holding "one two", whose pixels record every inversion.
local function newInputBox(calls)
    local box = {
        _bb = {
            getHeight = function() return 40 end,
            invertRect = function(_, x, y, w, h)
                calls.inverted = calls.inverted or {}
                calls.inverted[#calls.inverted + 1] =
                    table.concat({ x, y, w, h }, ",")
            end,
        },
        vertical_string_list = { {} },
        getNonXtextHighlightRects = function(_, first, last)
            return { { x = first, y = 0, w = last - first + 1, h = 20 } }
        end,
        dimen = { x = 0, y = 0 },
    }
    local inputbox = { charlist = {}, text_widget = box,
        isTextEditable = function() return true end }
    for char in ("one two"):gmatch(".") do
        inputbox.charlist[#inputbox.charlist + 1] = char
    end
    inputbox.charpos = #inputbox.charlist + 1
    return inputbox
end

local function setup(settings)
    local calls = {}
    settings = settings or {}
    local function noop() end
    local ui_manager = {
        widgetRepaint = noop,
        setDirty = function(_, mode, fn)
            calls.setDirty_calls = calls.setDirty_calls or {}
            table.insert(calls.setDirty_calls,
                { mode = mode, fn = fn })
        end,
    }
    local VirtualKeyboard = newKeyboardClass(calls)
    T.load("koreader_adapter"):new{
        settings = {
            nilOrTrue = function(_, name) return settings[name] ~= false end,
        },
        word_delete = T.load("word_delete"),
        text_highlight = T.load("text_highlight")
            :new(ui_manager, { new = function(_, o) return o end }),
        ui_manager = ui_manager,
        gesture_controller = { reset = noop },
        dictionary_controller = { stopWarmUp = noop },
        input_controller = { commitPendingContext = noop,
            saveContext = noop, clearCandidateState = noop },
    }:install(VirtualKeyboard)
    local keyboard = setmetatable({
        inputbox = newInputBox(calls),
        swype_mvp_prefetch_controller = { cancel = noop },
    }, VirtualKeyboard)
    return calls, keyboard
end

it("offers the words before the cursor to a slide from backspace",
        function()
    local _, keyboard = setup()
    T.eq(keyboard:_swypeDeleteSlideBegin(), 2)
end)

it("leaves backspace to KOReader while Tapless is off", function()
    local _, keyboard = setup{ keyboard_swype_mvp_enabled = false }
    T.eq(keyboard:_swypeDeleteSlideBegin(), 0)
end)

it("leaves backspace alone while the keyboard is resized", function()
    local _, keyboard = setup()
    keyboard.swype_mvp_resize = {}
    T.eq(keyboard:_swypeDeleteSlideBegin(), 0)
end)

it("keeps the slide in the symbol layers", function()
    local _, keyboard = setup()
    keyboard.symbolmode = true
    T.eq(keyboard:_swypeDeleteSlideBegin(), 2)
end)

it("takes the highlight off the text when the keyboard closes", function()
    local calls, keyboard = setup()
    keyboard:_swypeDeleteSlideBegin()
    keyboard:_swypeDeleteSlideShow(1)
    T.eq(#calls.inverted, 1, "word highlighted")
    keyboard.swype_mvp_delete_slide = {}
    keyboard:onCloseWidget()
    T.eq(#calls.inverted, 2, "inverted back")
    T.eq(calls.inverted[2], calls.inverted[1])
    T.eq(keyboard.swype_mvp_text_highlight, nil)
    T.eq(keyboard.swype_mvp_delete_slide, nil)
    T.eq(calls.stock_close, 1)
end)

-- A screen rectangle with KOReader Geom's copy and combine.
local function rect(x, w)
    return {
        x = x, y = 100, w = w, h = 40,
        copy = function(self) return rect(self.x, self.w) end,
        combine = function(self, other)
            local left = math.min(self.x, other.x)
            local right = math.max(self.x + self.w, other.x + other.w)
            return rect(left, right - left)
        end,
    }
end

it("_refresh with bands calls setDirty('all', fn) with closure " ..
        "that builds region after paint", function()
    local calls, keyboard = setup()
    keyboard.dimen = { w = 100, h = 40 }
    keyboard.swype_mvp_side_bands = {
        rect(0, 10),
        rect(110, 20),
    }
    keyboard:_refresh(false)
    T.eq(#calls.setDirty_calls, 1, "one setDirty call")
    local call = calls.setDirty_calls[1]
    T.eq(call.mode, "all", "mode is 'all'")
    T.eq(type(call.fn), "function", "fn is closure")
end)

local NIL_X = "attempt to perform arithmetic on field 'x' (a nil value)"

it("_refresh closure builds region after dimen is painted", function()
    local calls, keyboard = setup()
    -- Pre-paint dimen: has w, h but no x, y (like KOReader's getSize).
    -- Geom-like: copy and combine will fail on nil x/y if called eagerly.
    keyboard.dimen = {
        w = 100, h = 40,
        copy = function(self)
            if not self.x then
                error(NIL_X)
            end
            return rect(self.x, self.w)
        end,
        combine = function(self, other)
            if not self.x then
                error(NIL_X)
            end
            local left = math.min(self.x, other.x)
            local right = math.max(self.x + self.w, other.x + other.w)
            return rect(left, right - left)
        end,
    }
    -- Bands that don't span keys: only left band.
    keyboard.swype_mvp_side_bands = { { x = 0, y = 100, w = 10, h = 40 } }
    keyboard:_refresh(false)
    local call = calls.setDirty_calls[1]
    local fn = call.fn
    -- Simulate paint: add x and y to dimen.
    keyboard.dimen.x = 10
    keyboard.dimen.y = 100
    -- Call closure as paint would.
    local refresh_type, region = fn()
    T.eq(refresh_type, "ui")
    T.truthy(region, "region built after paint")
    -- Region must be keys ∪ bands: x=0 (band), w=110 (band 10 + keys 100).
    -- If region were bands only, w would be 10.
    T.eq(region.x, 0, "region x = 0 (left band)")
    T.eq(region.w, 110, "region w = 110 (keys 10-110 ∪ band 0-10)")
    T.eq(region.y, 100, "region y = keys y")
    T.eq(region.h, 40, "region h = keys h")
end)

it("_refresh without bands calls original unchanged", function()
    local calls, keyboard = setup()
    keyboard.dimen = { w = 100, h = 40, x = 10, y = 100 }
    keyboard:_refresh(false)
    T.eq(#calls.refresh_calls, 1, "original _refresh called")
    T.eq(calls.refresh_calls[1].want_flash, false)
    T.eq(calls.refresh_calls[1].fullscreen, nil)
    T.eq(#(calls.setDirty_calls or {}), 0, "no setDirty")
end)

it("_refresh(true, true) fullscreen goes to original", function()
    local calls, keyboard = setup()
    keyboard.dimen = { w = 100, h = 40, x = 10, y = 100 }
    keyboard.swype_mvp_side_bands = { rect(0, 10) }
    keyboard:_refresh(true, true)
    T.eq(#calls.refresh_calls, 1, "original _refresh called")
    T.eq(calls.refresh_calls[1].want_flash, true)
    T.eq(calls.refresh_calls[1].fullscreen, true)
    T.eq(#(calls.setDirty_calls or {}), 0, "no setDirty, fullscreen mode")
end)

-- A painted suggestion key (or the handle) that records being freed.
local function paintedKey(calls, label, x)
    return {
        label = label,
        { dimen = rect(x, 50) },
        free = function()
            calls.freed[#calls.freed + 1] = label
        end,
    }
end

-- The handle's size as the new row is laid out and painted.
local function handleSize(calls)
    local handle = calls.handle
    return handle and handle.dimen.w .. "x" .. handle.dimen.h
end

-- A keyboard showing "one two", with a handle at handle_x, whose row is
-- rebuilt from the session's candidates.
local function setupRow(candidates, handle_x)
    local calls = { freed = {}, painted = {}, repainted = {}, dirty = {} }
    local new_row = { widget = { new = true }, layout = { new = true },
        keys = {} }
    local VirtualKeyboard = newKeyboardClass(calls)
    T.load("koreader_adapter"):new{
        candidate_row = T.load("candidate_row"),
        keyboard_ui = {
            createCandidateRow = function(_, _, options)
                calls.row_options = options
                calls.handle_built = handleSize(calls)
                return new_row
            end,
        },
        screen = { bb = { paintRect = function(_, ...)
            calls.painted[#calls.painted + 1] = { ... }
        end } },
        ui_manager = {
            widgetRepaint = function(_, widget, x, y)
                calls.repainted[#calls.repainted + 1] = { widget, x, y }
                calls.handle_painted = handleSize(calls)
            end,
            setDirty = function(_, widget, refresh_type, region)
                calls.dirty[#calls.dirty + 1] =
                    { widget, refresh_type, region }
            end,
        },
    }:install(VirtualKeyboard)
    local keys = {}
    for index, word in ipairs{ "one", "two", " ", " " } do
        keys[index] = paintedKey(calls, word, 100 + 60 * (index - 1))
    end
    if handle_x then
        -- As KOReader's VirtualKey:paintTo left it: grown by the 2 px key
        -- padding for its touch area.
        calls.handle = paintedKey(calls, "handle", handle_x)
        calls.handle.width, calls.handle.height = 50, 40
        calls.handle.dimen = { x = handle_x - 1, y = 99, w = 52, h = 42 }
    end
    local old_row = { old = true }
    local keyboard = setmetatable({
        swype_mvp_session = {
            getCandidates = function() return candidates end,
            getPersonalOffer = function() end,
        },
        swype_mvp_candidate_keys = keys,
        swype_mvp_handle = calls.handle,
        swype_mvp_candidate_group = { old_row, "gap" },
        swype_mvp_candidate_row_options = { row = true },
        swype_mvp_frame_background = "grey",
        layout = { { old = true }, { "letters" } },
    }, VirtualKeyboard)
    return calls, keyboard, new_row
end

it("keeps the suggestion row while its words stay the same", function()
    local calls, keyboard = setupRow{ { word = "one" }, { word = "two" } }
    T.eq(keyboard:_swypeRebuildCandidateRow("ui"), false)
    T.eq(calls.row_options, nil, "not rebuilt")
    T.eq(#calls.painted + #calls.repainted + #calls.dirty, 0)
end)

it("rebuilds the suggestion row in place when its words change",
        function()
    local calls, keyboard, new_row = setupRow({ { word = "three" } }, 30)
    T.eq(keyboard:_swypeRebuildCandidateRow("fast"), true)
    T.eq(calls.row_options.row, true, "the row's own options")
    T.eq(keyboard.swype_mvp_candidate_group[1], new_row.widget)
    T.eq(keyboard.swype_mvp_candidate_group[2], "gap")
    T.eq(keyboard.layout[1], new_row.layout)
    T.eq(keyboard.layout[2][1], "letters")
    T.eq(keyboard.swype_mvp_candidate_keys, new_row.keys)
    -- The handle belongs to the new row too.
    T.eq(table.concat(calls.freed, "|"), "one|two| | ")
    -- The old row ran from the left handle to the end of the last key.
    local painted = calls.painted[1]
    T.eq(table.concat(painted, ","), "30,100,300,40,grey")
    T.eq(calls.repainted[1][1], new_row.widget)
    T.eq(calls.repainted[1][2], 30)
    T.eq(calls.repainted[1][3], 100)
    T.eq(calls.dirty[1][2], "fast")
    T.eq(calls.dirty[1][3].x, 30)
    T.eq(calls.dirty[1][3].w, 300)
end)

it("leaves the row alone while a resize is under way", function()
    local calls, keyboard = setupRow({ { word = "three" } }, 30)
    keyboard.swype_mvp_resize = {}
    T.eq(keyboard:_swypeRebuildCandidateRow("ui"), false)
    T.eq(calls.row_options, nil, "not rebuilt")
    T.eq(#calls.painted + #calls.repainted + #calls.dirty, 0)
    T.eq(#calls.freed, 0, "old keys kept")
    T.eq(keyboard.swype_mvp_candidate_group[1].old, true)
    T.eq(keyboard.layout[1].old, true)
    T.eq(calls.handle.dimen.w, 52, "not yet set to its own size")
end)

it("lays out a rebuilt row with the handle at its real size", function()
    local calls, keyboard = setupRow({ { word = "three" } }, 30)
    local dimen = calls.handle.dimen
    keyboard:_swypeRebuildCandidateRow("ui")
    T.eq(calls.handle_built, "50x40", "as the row is built")
    T.eq(calls.handle_painted, "50x40", "as the row is painted")
    -- Its gesture ranges hold this table.
    T.eq(calls.handle.dimen, dimen, "the same table")
end)

it("swaps in a row not yet on screen without painting it", function()
    local calls, keyboard, new_row = setupRow{ { word = "three" } }
    for _, key in ipairs(keyboard.swype_mvp_candidate_keys) do
        key[1].dimen = { w = 50, h = 40 }
    end
    T.eq(keyboard:_swypeRebuildCandidateRow("ui"), true)
    T.eq(keyboard.swype_mvp_candidate_group[1], new_row.widget)
    T.eq(#calls.painted + #calls.repainted + #calls.dirty, 0)
end)

-- Text as many px a letter as its font size, so "abcd" at size 22 is
-- 88 px wide.
local function setupLabels()
    local calls = { freed = 0, made = {} }
    local text_widget = {}
    function text_widget:new(options)
        calls.made[#calls.made + 1] = options
        options.getWidth = function(widget)
            return #widget.text * widget.face.orig_size
        end
        options.free = function() calls.freed = calls.freed + 1 end
        return options
    end
    local VirtualKeyboard = newKeyboardClass(calls)
    T.load("koreader_adapter"):new{
        text_widget = text_widget,
        font = { getFace = function(_, font, size)
            return { orig_font = font, orig_size = size }
        end },
        key_adapter = { keyFontSize = function() return 22 end },
        settings = { isTrue = function() return false end },
        screen = { getDPI = function() return 300 end },
    }:install(VirtualKeyboard)
    return calls, setmetatable({}, VirtualKeyboard)
end

local function labelledKey(calls, text)
    local label = { text = text, bold = true, fgcolor = "black",
        face = { orig_font = "infont", orig_size = 22 } }
    label.getWidth = function(widget)
        return #widget.text * widget.face.orig_size
    end
    label.free = function() calls.freed = calls.freed + 1 end
    return { swype_mvp_label_widget = label, { { label } } }, label
end

it("shrinks a suggestion a size at a time to fit its box", function()
    local calls, keyboard = setupLabels()
    local key = labelledKey(calls, "abcd")
    keyboard:_swypeFitLabel(key, 60)
    local label = key.swype_mvp_label_widget
    T.eq(label.face.orig_size, 15, "4 letters at 15 px")
    T.eq(key[1][1][1], label, "shown in the key")
    T.eq(label.bold, true)
    T.eq(label.fgcolor, "black")
    T.eq(calls.freed, 7, "each replaced label freed")
end)

it("stops shrinking a suggestion at size 8", function()
    local calls, keyboard = setupLabels()
    local key = labelledKey(calls, "abcdefgh")
    keyboard:_swypeFitLabel(key, 1)
    T.eq(key.swype_mvp_label_widget.face.orig_size, 8)
end)

it("leaves a key whose label is not its only content", function()
    local calls, keyboard = setupLabels()
    local key, label = labelledKey(calls, "abcd")
    key[1][1][1] = { overlap = true }
    keyboard:_swypeFitLabel(key, 60)
    T.eq(key.swype_mvp_label_widget, label)
    T.eq(#calls.made, 0)
end)

it("measures a suggestion in the keys' font", function()
    local calls, keyboard = setupLabels()
    T.eq(keyboard:_swypeMeasureLabel(" ", false), 0, "empty slot")
    T.eq(keyboard:_swypeMeasureLabel("abc", true), 66)
    T.eq(calls.made[1].bold, true)
    T.eq(calls.made[1].face.orig_font, "infont")
    T.eq(calls.freed, 1)
    T.eq(keyboard:_swypeLabelPad(), 18, "1.5 mm at 300 dpi")
end)

-- An adapter whose touch offset model has learned a landing error of a
-- fifth of a key left on the one-handed keyboard at the left of the
-- screen, with keys 50 wide and 60 tall: a, s and d in a row.
local function touchSetup()
    local values = { touch = { ["one-handed left"] = { x = -0.2, y = 0,
        words = 20 } } }
    local model = T.load("touch_offset"):new({
        readSetting = function(_, key) return values[key] end,
        saveSetting = function(_, key, value) values[key] = value end,
    }, "touch")
    local VirtualKeyboard = newKeyboardClass({})
    T.load("koreader_adapter"):new{
        settings = {
            nilOrTrue = function() return true end,
        },
        touch_model = model,
        keyboard_geometry = T.load("keyboard_geometry"):new(T.normalization),
        one_handed = { state = function() return { enabled = true } end },
        screen = {
            getWidth = function() return 600 end,
            getHeight = function() return 800 end,
            getDPI = function() return 300 end,
        },
    }:install(VirtualKeyboard)
    local row = {}
    for index, letter in ipairs({ "a", "s", "d" }) do
        row[index] = { key = letter, dimen = { x = (index - 1) * 50,
            y = 500, w = 50, h = 60 } }
    end
    return setmetatable({ layout = { row } }, VirtualKeyboard)
end

it("shifts a swipe back by the offset learned on this side's one-handed "
        .. "keyboard, in pixels", function()
    local keyboard = touchSetup()
    local shift, keys = keyboard:_swypeTouchShift()
    local strength = T.load("touch_offset").STRENGTH
    T.truthy(math.abs(shift.x - 0.2 * strength * 50) < 1e-9,
        "x " .. shift.x)
    T.eq(shift.y, 0)
    T.eq(keys.s.x, 75, "the letter keys it was worked out for")
end)

it("keeps where a swipe went to learn from, over the keys of its shift",
        function()
    local keyboard = touchSetup()
    local _, keys = keyboard:_swypeTouchShift()
    local sample = keyboard:_swypeTouchSample({
        points = { { x = 30, y = 530 }, { x = 110, y = 540 } },
        touch_keys = keys,
    })
    T.eq(sample.mode, "one-handed left")
    T.eq(sample.start.x, 30)
    T.eq(sample.lift.x, 110)
    T.eq(sample.lift.y, 540)
    T.eq(sample.keys, keys)
end)

it("learns nothing from where a swipe began off the letter keys, as on "
        .. "the number row", function()
    local keyboard = touchSetup()
    local _, keys = keyboard:_swypeTouchShift()
    local sample = keyboard:_swypeTouchSample({
        points = { { x = 30, y = 450 }, { x = 110, y = 540 } },
        touch_keys = keys,
    })
    T.eq(sample.start, nil, "began above the letters")
    T.eq(sample.lift.x, 110)
end)

-- The ◨ handle with the one-handed keys against the screen's keys_side
-- edge, recording what its swipes do.
local function handleSetup(keys_side)
    local calls = {}
    local one_handed = {
        target = function() return keys_side == "right" and "left" or "right" end,
        setEnabled = function(_, _, enabled) calls.enabled = enabled end,
        moveToTarget = function() calls.moved = true end,
    }
    local VirtualKeyboard = newKeyboardClass(calls)
    T.load("koreader_adapter"):new{
        virtual_key = { new = function(_, key) return key end },
        one_handed = one_handed,
        icon_dir = "/icons",
        ui_manager = { close = function() end },
    }:install(VirtualKeyboard)
    local keyboard = setmetatable({
        _swypeSetOneHanded = function(_, change) change(one_handed, {}) end,
        _swypeStartResize = function() calls.resized = true end,
    }, VirtualKeyboard)
    return calls, keyboard:_swypeHandle(50, 40, {}, {})
end

local HANDLE_SIDES = {
    { keys = "right", outward = "west", inward = "east", arrow = "left" },
    { keys = "left", outward = "east", inward = "west", arrow = "right" },
}

it("leaves on a swipe up from the handle, moves the keys on a swipe "
        .. "outwards and resizes on a swipe inwards", function()
    for _, side in ipairs(HANDLE_SIDES) do
        local function swipe(direction)
            local calls, handle = handleSetup(side.keys)
            handle.swipe_callback({ direction = direction })
            return calls
        end
        T.eq(swipe("north").enabled, false, side.keys .. ": up leaves")
        T.truthy(swipe(side.outward).moved, side.keys .. ": outwards moves")
        T.truthy(swipe("north" .. side.outward).moved,
            side.keys .. ": up and outwards moves")
        T.truthy(swipe(side.inward).resized, side.keys .. ": inwards resizes")
        T.truthy(swipe("north" .. side.inward).resized,
            side.keys .. ": up and inwards resizes")
        local calls = swipe("south")
        T.eq(calls.enabled, nil, side.keys .. ": down does nothing")
        T.eq(calls.moved, nil)
        T.eq(calls.resized, nil)
    end
end)

it("lays the handle's menu out as its swipes go: move outwards, leave "
        .. "in the middle, resize inwards", function()
    for _, side in ipairs(HANDLE_SIDES) do
        local _, handle = handleSetup(side.keys)
        local chars = handle.key_chars
        T.eq(chars[1].key, "leave", side.keys)
        T.eq(chars[side.outward].key, "move", side.keys)
        T.eq(chars[side.outward].icon, "/icons/" .. side.arrow .. ".svg")
        T.eq(chars[side.inward].key, "resize", side.keys)
    end
end)

-- A keyboard whose gesture reference is or isn't still due, with language
-- setup still needed or done, recording what is scheduled and shown.
local function referenceSetup(due, needs_setup)
    local calls = { scheduled = {} }
    local VirtualKeyboard = newKeyboardClass(calls)
    T.load("koreader_adapter"):new{
        gesture_reference = {
            due = function() return due end,
            showOnce = function() calls.shown = true end,
        },
        dictionary_controller = {
            needsLanguageSetup = function() return needs_setup end,
        },
        ui_manager = {
            scheduleIn = function(_, delay, fn)
                calls.scheduled[#calls.scheduled + 1] = { delay, fn }
            end,
        },
    }:install(VirtualKeyboard)
    return calls, setmetatable({}, VirtualKeyboard)
end

it("shows the gesture reference the first time the keyboard opens with "
        .. "no languages left to choose", function()
    local calls, keyboard = referenceSetup(true, false)
    keyboard:_swypeScheduleGestureReference()
    T.eq(#calls.scheduled, 1)
    calls.scheduled[1][2]()
    T.truthy(calls.shown)
end)

it("leaves the gesture reference for later while languages are being "
        .. "chosen, and once it has been shown", function()
    local calls, keyboard = referenceSetup(true, true)
    keyboard:_swypeScheduleGestureReference()
    T.eq(#calls.scheduled, 0, "language setup first")
    calls, keyboard = referenceSetup(false, false)
    keyboard:_swypeScheduleGestureReference()
    T.eq(#calls.scheduled, 0, "already shown")
end)

it("doesn't show the gesture reference over a keyboard that closed before "
        .. "its turn came", function()
    local calls, keyboard = referenceSetup(true, false)
    keyboard:_swypeScheduleGestureReference()
    keyboard.swype_mvp_closed = true
    calls.scheduled[1][2]()
    T.eq(calls.shown, nil)
end)
