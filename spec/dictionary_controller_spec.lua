local T = require("helper")
local it = T.it

-- The KOReader layout file each language is typed with, as manifests say.
local LAYOUT_FILES = { en = "en_keyboard", it = "en_keyboard",
    da = "da_keyboard", ["pt-br"] = "pt_keyboard" }
-- Part of KOReader's VirtualKeyboard.lang_to_keyboard_layout.
local KOREADER_LAYOUTS = { en = "en_keyboard", da = "da_keyboard",
    pt_BR = "pt_keyboard", ru = "ru_keyboard" }

local function compareIds(left, right)
    if left == right then return false end
    if left == "en" then return true end
    if right == "en" then return false end
    return left < right
end

-- catalog: the catalog's packages by id, for languages to download;
-- queued: ids the manager is downloading.
local function newController(installed, stored, catalog, queued)
    local DictionaryController = T.load("dictionary_controller")
    stored = stored or {}
    local kept = {}
    local manager = {
        listInstalled = function() return installed end,
        isDictionaryAvailable = function(_, id)
            for _, info in ipairs(installed) do
                if info.id == id then return true end
            end
            return false
        end,
        catalogPackages = function() return catalog or {} end,
        -- As Manager:setupChoices: installed, then the catalog's others.
        setupChoices = function()
            local choices, seen = {}, {}
            for _, info in ipairs(installed) do
                seen[info.id] = true
                choices[#choices + 1] = { id = info.id }
            end
            for id in pairs(catalog or {}) do
                if not seen[id] then choices[#choices + 1] = { id = id } end
            end
            table.sort(choices, function(a, b)
                return compareIds(a.id, b.id)
            end)
            return choices
        end,
        isQueued = function(_, id) return (queued or {})[id] == true end,
    }
    local controller = DictionaryController:new{
        plugin_dir = ".",
        manager = manager,
        registry = {
            get = function(_, id)
                return { normalization_profile = id .. "-profile",
                    keyboard_layout = LAYOUT_FILES[id] }
            end,
            compareIds = compareIds,
        },
        store = {
            invalidate = function() end,
            keepOnly = function(_, id) kept[#kept + 1] = id end,
        },
        scoring = {},
        ui_manager = {
            scheduleIn = function(_, _, fn) fn() end,
        },
        settings = {
            readSetting = function(_, key, default)
                if stored[key] == nil then return default end
                return stored[key]
            end,
            saveSetting = function(_, key, value) stored[key] = value end,
            isTrue = function(_, key) return stored[key] == true end,
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

local POLISH = { id = "pl", name = "Polish", size = 1176037 }

it("offers setup when the catalog has languages to download", function()
    local controller = newController({ { id = "en" } }, {},
        { en = { id = "en" }, pl = POLISH })
    T.eq(controller:needsLanguageSetup(), true)
end)

it("skips setup when English is all there is", function()
    local stored = {}
    local controller = newController({ { id = "en" } }, stored,
        { en = { id = "en" } })
    T.eq(controller:needsLanguageSetup(), false)
    T.eq(stored.enabled[1], "en")
    T.eq(stored.setup, true)
end)

it("setup enables a language to download and types in English meanwhile",
        function()
    local stored = { dictionary = "en" }
    local controller = newController({ { id = "en" } }, stored,
        { en = { id = "en" }, pl = POLISH })
    T.eq(controller:completeLanguageSetup({ pl = true }), true)
    T.eq(#stored.enabled, 1)
    T.eq(stored.enabled[1], "pl")
    T.eq(stored.dictionary, "en", "nothing chosen is installed yet")
    T.eq(controller:listEnabled()[1].id, "en")
    T.eq(stored.enabled[1], "pl", "listing doesn't forget it")
    local missing = controller:missingLanguages()
    T.eq(#missing, 1)
    T.eq(missing[1], POLISH)
end)

it("forgetting the only enabled language enables an installed one",
        function()
    local stored = { enabled = { "pl" } }
    local controller = newController({ { id = "en" } }, stored,
        { pl = POLISH })
    controller:forgetMissing({ "pl" })
    T.eq(#stored.enabled, 1)
    T.eq(stored.enabled[1], "en")
end)

it("doesn't forget a language that has installed meanwhile", function()
    local installed = { { id = "en" } }
    local stored = { enabled = { "pl" } }
    local controller = newController(installed, stored, { pl = POLISH })
    installed[2] = { id = "pl" }
    controller:forgetMissing({ "pl" })
    T.eq(table.concat(stored.enabled, ","), "pl")
end)

it("doesn't offer a language that is already downloading", function()
    local stored = { enabled = { "en", "pl" }, setup = true }
    local controller = newController({ { id = "en" } }, stored,
        { en = { id = "en" }, pl = POLISH }, { pl = true })
    T.eq(#controller:missingLanguages(), 0)
    T.eq(table.concat(stored.enabled, ","), "en,pl", "still enabled")
end)

it("forgets an enabled language nothing can install", function()
    local stored = { enabled = { "en", "xx" } }
    local controller = newController({ { id = "en" } }, stored,
        { en = { id = "en" } })
    T.eq(#controller:missingLanguages(), 0)
    T.eq(table.concat(stored.enabled, ","), "en")
end)

it("enabling and disabling change only that language's place", function()
    local stored = { enabled = { "de", "pl", "en" } }
    local controller = newController({ { id = "en" }, { id = "de" } },
        stored, { pl = POLISH })
    T.eq(controller:setEnabled("de", false), true)
    T.eq(table.concat(stored.enabled, ","), "pl,en")
    T.eq(controller:setEnabled("de", true), true)
    T.eq(table.concat(stored.enabled, ","), "pl,en,de")
    T.eq(controller:setEnabled("en", true), true)
    T.eq(table.concat(stored.enabled, ","), "pl,en,de", "already there")
    controller:setEnabled("de", false)
    T.eq(controller:setEnabled("en", false), false,
        "the last installed one stays")
end)

it("disabling a language keeps the ones still to download", function()
    local stored = { enabled = { "en", "de", "pl" } }
    local controller = newController({ { id = "en" }, { id = "de" } },
        stored, { pl = POLISH })
    T.eq(controller:setEnabled("de", false), true)
    T.eq(table.concat(stored.enabled, ","), "en,pl")
end)

it("removing a dictionary keeps the ones still to download", function()
    local stored = { enabled = { "en", "de", "pl" }, dictionary = "en" }
    local controller = newController({ { id = "en" } }, stored,
        { pl = POLISH })
    controller:onDictionaryRemoved("de")
    T.eq(table.concat(stored.enabled, ","), "en,pl")
end)

it("offers the download instead of setup once languages are chosen",
        function()
    local stored = { enabled = { "en", "pl" }, setup = true }
    local controller = newController({ { id = "en" } }, stored,
        { en = { id = "en" }, pl = POLISH })
    local offered, closed
    controller.manager.offerDownloads = function(_, _, packages)
        offered = packages
    end
    local keyboard = newKeyboard("en")
    keyboard.onClose = function() closed = true end
    T.eq(controller:scheduleLanguageSetup(keyboard), true)
    T.eq(closed, true)
    T.eq(offered[1], POLISH)
end)

it("leaves the keyboard open when nothing is missing", function()
    local stored = { enabled = { "en" }, setup = true }
    local controller = newController({ { id = "en" } }, stored,
        { en = { id = "en" }, pl = POLISH })
    T.eq(controller:scheduleLanguageSetup(newKeyboard("en")), false)
end)
