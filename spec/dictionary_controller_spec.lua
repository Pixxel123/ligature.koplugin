local T = require("helper")
local it = T.it

-- The KOReader layout file each language is typed with, as manifests say.
local LAYOUT_FILES = { en = "en_keyboard", it = "en_keyboard",
    da = "da_keyboard", ["pt-br"] = "pt_keyboard" }
-- Part of KOReader's VirtualKeyboard.lang_to_keyboard_layout.
local KOREADER_LAYOUTS = { en = "en_keyboard", da = "da_keyboard",
    pt_BR = "pt_keyboard", ru = "ru_keyboard" }

local function newController(installed, stored)
    local DictionaryController = T.load("dictionary_controller")
    stored = stored or {}
    local kept = {}
    local controller = DictionaryController:new{
        plugin_dir = ".",
        manager = {
            listInstalled = function() return installed end,
            isDictionaryAvailable = function(_, id)
                for _, info in ipairs(installed) do
                    if info.id == id then return true end
                end
                return false
            end,
        },
        registry = {
            get = function(_, id)
                return { normalization_profile = id .. "-profile",
                    keyboard_layout = LAYOUT_FILES[id] }
            end,
        },
        store = {
            invalidate = function() end,
            keepOnly = function(_, id) kept[#kept + 1] = id end,
        },
        scoring = {},
        ui_manager = {},
        settings = {
            readSetting = function(_, key) return stored[key] end,
            saveSetting = function(_, key, value) stored[key] = value end,
        },
        logger = { info = function() end },
        setting_key = "dictionary",
        enabled_setting_key = "enabled",
        setup_setting_key = "setup",
        default_profile = "latin",
        layouts = KOREADER_LAYOUTS,
    }
    return controller, kept
end

local function newKeyboard(dictionary)
    local calls = {}
    return {
        swype_mvp_dictionary = dictionary,
        _swypeCommitPendingContext = function()
            calls.committed = true
        end,
        _swypeSetDictionary = function(_, id)
            calls.set = id
            return true
        end,
    }, calls
end

it("leaves the keyboard alone when there is no other language", function()
    local keyboard, calls = newKeyboard("en")
    T.eq(newController({ { id = "en" } }):toggle(keyboard), false)
    T.eq(calls.set, nil)
    T.eq(calls.committed, nil)
end)

it("switches to the next language", function()
    local keyboard, calls = newKeyboard("en")
    T.eq(newController({ { id = "en" }, { id = "pl" } }):toggle(keyboard),
        true)
    T.eq(calls.set, "pl")
end)

it("uses the saved language for personal words without a keyboard",
        function()
    local controller = newController({ { id = "en" }, { id = "de" } },
        { dictionary = "de" })
    local language, profile = controller:personalContext(nil)
    T.eq(language, "de")
    T.eq(profile, "de-profile")
end)

it("uses the keyboard's language for personal words", function()
    local controller = newController({ { id = "en" }, { id = "de" } },
        { dictionary = "de" })
    local keyboard = newKeyboard("en")
    keyboard.swype_mvp_normalization_profile = "latin"
    local language, profile = controller:personalContext(keyboard)
    T.eq(language, "en")
    T.eq(profile, "latin")
end)

-- A keyboard setDictionary can work on, showing, built with layout (a
-- value of KOReader's layout setting).
local function shownKeyboard(dictionary, layout)
    local calls = {}
    local keyboard = {
        swype_mvp_dictionary = dictionary,
        visible = true,
        getKeyboardLayout = function() return layout end,
        setKeyboardLayout = function(_, name) calls.layout = name end,
    }
    for _, name in ipairs({ "_swypeCommitPendingContext",
            "_swypeCancelBucketPrefetch", "_swypeClearCandidateRow",
            "_swypeRefreshLanguageIndicator", "_swypeScheduleWarmUp" }) do
        keyboard[name] = function() calls[name] = true end
    end
    return keyboard, calls
end

local BOTH = { { id = "en" }, { id = "da" } }

it("passes holding space's switch on, for the layout to wait for the lift",
        function()
    local keyboard, calls = newKeyboard("en")
    keyboard._swypeSetDictionary = function(_, id, on_lift)
        calls.set, calls.on_lift = id, on_lift
    end
    newController(BOTH):toggle(keyboard)
    T.eq(calls.set, "da")
    T.eq(calls.on_lift, true)
end)

it("switches KOReader's layout with the language", function()
    local stored = { keyboard_layout = "en" }
    local controller = newController(BOTH, stored)
    local keyboard, calls = shownKeyboard("en", "en")
    T.eq(controller:setDictionary(keyboard, "da", true), true)
    T.eq(keyboard.swype_mvp_layout_on_lift, "da", "held: on the lift")
    T.eq(calls.layout, nil)
    keyboard.swype_mvp_layout_on_lift = nil
    controller:setDictionary(keyboard, "da")
    T.eq(calls.layout, "da", "otherwise at once")
end)

it("uses KOReader's name for a layout", function()
    local stored = { keyboard_layout = "en" }
    local controller = newController({ { id = "en" }, { id = "pt-br" } },
        stored)
    local keyboard, calls = shownKeyboard("en", "en")
    controller:setDictionary(keyboard, "pt-br")
    T.eq(calls.layout, "pt_BR")
end)

it("leaves a layout the language is already typed with", function()
    local stored = { keyboard_layout = "en" }
    local controller = newController({ { id = "en" }, { id = "it" } },
        stored)
    local keyboard, calls = shownKeyboard("en", "en")
    controller:setDictionary(keyboard, "it")
    T.eq(calls.layout, nil)
    T.eq(keyboard.swype_mvp_layout_on_lift, nil)
end)

it("saves the layout for the next keyboard when none is showing",
        function()
    local stored = { keyboard_layout = "en" }
    local controller = newController(BOTH, stored)
    T.eq(controller:selectDictionary("da", nil), true)
    T.eq(stored.dictionary, "da")
    T.eq(stored.keyboard_layout, "da")
end)

it("takes the language KOReader's layout is for when the keyboard is built",
        function()
    local stored = { dictionary = "en" }
    local controller = newController(BOTH, stored)
    local keyboard = shownKeyboard(nil, "da")
    controller:initialize(keyboard)
    T.eq(keyboard.swype_mvp_dictionary, "da")
    T.eq(stored.dictionary, "da")
end)

it("keeps the language when the layout is its own or no language's",
        function()
    local stored = { dictionary = "it" }
    local controller = newController({ { id = "en" }, { id = "it" } },
        stored)
    local keyboard = shownKeyboard(nil, "en")
    controller:initialize(keyboard)
    T.eq(keyboard.swype_mvp_dictionary, "it", "shares English's layout")
    keyboard = shownKeyboard(nil, "ru")
    controller:initialize(keyboard)
    T.eq(keyboard.swype_mvp_dictionary, "it", "no language uses Russian")
    T.eq(stored.keyboard_layout, nil, "and the layout stays")
end)

it("leaves the old language behind when a new layout rebuilds the keyboard",
        function()
    local stored = { dictionary = "en" }
    local controller, kept = newController(BOTH, stored)
    local keyboard, calls = shownKeyboard("en", "da")
    controller:initialize(keyboard)
    T.eq(keyboard.swype_mvp_dictionary, "da")
    T.eq(calls._swypeCommitPendingContext, true)
    T.eq(kept[1], "da")
end)

it("gives a language it falls back to its layout", function()
    local stored = { dictionary = "xx", enabled = { "da" },
        keyboard_layout = "en" }
    local controller = newController(BOTH, stored)
    local keyboard = shownKeyboard(nil, "en")
    controller:initialize(keyboard)
    T.eq(keyboard.swype_mvp_dictionary, "da")
    T.eq(stored.keyboard_layout, "da")
end)
