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
    local ui_manager = { widgetRepaint = noop, setDirty = noop }
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
