local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local source = debug.getinfo(1, "S").source
local plugin_dir = source:match("^@(.+)/main%.lua$") or "."
local virtualkeyboard_module = "ui/widget/virtualkeyboard"
local replacement_path = plugin_dir .. "/virtualkeyboard.lua"

local Screen = require("device").screen
local modules = dofile(plugin_dir .. "/modules.lua")
local OneHanded = dofile(plugin_dir .. "/" .. modules.one_handed)
local TouchOffset = dofile(plugin_dir .. "/" .. modules.touch_offset)

-- What the keyboard has learned about where the finger lands.
local function touchOffset()
    return TouchOffset:new(G_reader_settings, TouchOffset.SETTING_KEY)
end

local function screenInfo()
    return {
        w = Screen:getWidth(),
        h = Screen:getHeight(),
        dpi = Screen:getDPI(),
    }
end

-- KOReader loads plugin main files before normal text dialogs are created.
-- Replace the module cache entry so future keyboard instances use the plugin
-- implementation without modifying KOReader's installed core files.
local ok, replacement = pcall(dofile, replacement_path)
if ok and replacement then
    package.loaded[virtualkeyboard_module] = replacement
    logger.info("Tapless: thin VirtualKeyboard adapter loaded")

    -- InputText caches the keyboard class during its own module initialization.
    -- Re-run that binding so an early-loaded InputText also uses Tapless.
    local InputText = require("ui/widget/inputtext")
    InputText.initInputEvents()
    logger.info("Tapless: InputText keyboard binding refreshed")
else
    logger.err("Tapless: failed to load VirtualKeyboard implementation", replacement)
end

local Tapless = WidgetContainer:extend{
    name = "tapless",
    is_doc_only = false,
}

function Tapless:init()
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

function Tapless:openDictionaryManager()
    if replacement and replacement.taplessOpenDictionaryManager then
        replacement.taplessOpenDictionaryManager()
    else
        logger.err("Tapless: dictionary manager is unavailable")
    end
end

function Tapless:addToMainMenu(menu_items)
    local plugin = self

    menu_items.tapless_settings = {
        text = "Tapless",
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = "Manage dictionaries",
                callback = function()
                    plugin:openDictionaryManager()
                end,
            },
            {
                text = "Keyboard size",
                sub_item_table = {
                    {
                        text = "Same as KOReader",
                        help_text = "Follows KOReader's compact keyboard "
                            .. "setting, and KOReader's key text size when "
                            .. "the text size is Auto.",
                        radio = true,
                        checked_func = function()
                            return G_reader_settings:readSetting(
                                "tapless_keyboard_size") == nil
                        end,
                        callback = function()
                            G_reader_settings:delSetting(
                                "tapless_keyboard_size")
                        end,
                    },
                    {
                        text = "Extra compact",
                        radio = true,
                        checked_func = function()
                            return G_reader_settings:readSetting(
                                "tapless_keyboard_size") == "extra_compact"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting(
                                "tapless_keyboard_size", "extra_compact")
                        end,
                    },
                    {
                        text = "Compact",
                        radio = true,
                        checked_func = function()
                            local value = G_reader_settings:readSetting(
                                "tapless_keyboard_size")
                            return value == "compact"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting(
                                "tapless_keyboard_size", "compact")
                        end,
                    },
                    {
                        text = "Normal",
                        radio = true,
                        checked_func = function()
                            local value = G_reader_settings:readSetting(
                                "tapless_keyboard_size")
                            return value == "normal"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting(
                                "tapless_keyboard_size", "normal")
                        end,
                    },
                    {
                        text = "Large",
                        radio = true,
                        checked_func = function()
                            return G_reader_settings:readSetting(
                                "tapless_keyboard_size") == "large"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting(
                                "tapless_keyboard_size", "large")
                        end,
                    },
                },
            },
            {
                text = "Keyboard text size",
                sub_item_table = {
                    {
                        text = "Auto",
                        radio = true,
                        checked_func = function()
                            return G_reader_settings:readSetting(
                                "tapless_keyboard_font_size", "auto") == "auto"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting(
                                "tapless_keyboard_font_size", "auto")
                        end,
                    },
                    {
                        text = "Small",
                        radio = true,
                        checked_func = function()
                            return G_reader_settings:readSetting(
                                "tapless_keyboard_font_size", "auto") == 18
                        end,
                        callback = function()
                            G_reader_settings:saveSetting(
                                "tapless_keyboard_font_size", 18)
                        end,
                    },
                    {
                        text = "Normal",
                        radio = true,
                        checked_func = function()
                            return G_reader_settings:readSetting(
                                "tapless_keyboard_font_size", "auto") == 22
                        end,
                        callback = function()
                            G_reader_settings:saveSetting(
                                "tapless_keyboard_font_size", 22)
                        end,
                    },
                    {
                        text = "Large",
                        radio = true,
                        checked_func = function()
                            return G_reader_settings:readSetting(
                                "tapless_keyboard_font_size", "auto") == 26
                        end,
                        callback = function()
                            G_reader_settings:saveSetting(
                                "tapless_keyboard_font_size", 26)
                        end,
                    },
                },
            },
            {
                text = "Slide on space to move cursor",
                help_text = "Slide left or right along the space bar to "
                    .. "move the text cursor. Holding space still switches "
                    .. "language.",
                checked_func = function()
                    return G_reader_settings:isTrue("tapless_space_cursor")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("tapless_space_cursor")
                end,
            },
            {
                text = "Double space types a period",
                help_text = "A second space right after a word, or a space "
                    .. "right after a swiped word, becomes \". \". Not used "
                    .. "on Chinese, Japanese, Korean or Vietnamese layouts.",
                checked_func = function()
                    return G_reader_settings:isTrue(
                        "tapless_double_space_period")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse(
                        "tapless_double_space_period")
                end,
            },
            {
                text = "Suggest words while typing",
                help_text = "When you pause while tapping out a word, the "
                    .. "suggestion row offers words that finish it. Tap one "
                    .. "to use it.",
                checked_func = function()
                    return G_reader_settings:nilOrTrue(
                        "tapless_tap_completions")
                end,
                callback = function()
                    G_reader_settings:flipNilOrTrue(
                        "tapless_tap_completions")
                end,
            },
            {
                text = "Learn how I swipe",
                help_text = "Learns, from the words you keep, where your "
                    .. "finger lands against the keys you mean, and allows "
                    .. "for it when reading swipes. A thumb tends to land "
                    .. "short of keys further away, most of all on the "
                    .. "one-handed keyboard. Learned apart for the "
                    .. "one-handed and full-width keyboard; it starts "
                    .. "after a few words and settles within a few dozen.",
                checked_func = function()
                    return G_reader_settings:nilOrTrue(
                        "tapless_touch_learning")
                end,
                callback = function()
                    G_reader_settings:flipNilOrTrue(
                        "tapless_touch_learning")
                end,
            },
            {
                text = "Forget how I swipe",
                help_text = "Clears what Tapless has learned about where "
                    .. "your finger lands, so it learns again from the "
                    .. "next words you swipe.",
                keep_menu_open = true,
                enabled_func = function()
                    return touchOffset():learned()
                end,
                callback = function()
                    touchOffset():reset()
                end,
            },
            {
                text = "Rank offensive words down",
                help_text = "Swear words and slurs are suggested only when "
                    .. "a swipe fits them clearly better than any other "
                    .. "word, so they stop taking the place of the words "
                    .. "you mean. A word you keep using is ranked like any "
                    .. "other. Tapping out a word letter by letter types it "
                    .. "as always.",
                checked_func = function()
                    return G_reader_settings:nilOrTrue(
                        "tapless_rank_down_offensive")
                end,
                callback = function()
                    G_reader_settings:flipNilOrTrue(
                        "tapless_rank_down_offensive")
                end,
            },
            {
                text = "One-handed keyboard",
                help_text = "Narrows the keys to one side of the screen, "
                    .. "with the page beside them. A ◨ handle at the "
                    .. "end of the suggestion row opens a menu of leave, "
                    .. "move and resize. Tap it, hold it, or swipe "
                    .. "towards an option. Hold the globe key and lift to "
                    .. "switch it on or off while typing. Portrait and "
                    .. "landscape are remembered separately.",
                checked_func = function()
                    return OneHanded:new(G_reader_settings)
                        :state(screenInfo()).enabled
                end,
                callback = function()
                    OneHanded:new(G_reader_settings):toggle(screenInfo())
                end,
            },
            {
                text = "Hatch beside one-handed keys",
                help_text = "Fills the space between the one-handed keys "
                    .. "and the screen edge with fine diagonal lines, "
                    .. "instead of showing the page there. Tapping it "
                    .. "still closes the keyboard.",
                checked_func = function()
                    return G_reader_settings:nilOrTrue(
                        "tapless_one_handed_hatch")
                end,
                callback = function()
                    G_reader_settings:flipNilOrTrue(
                        "tapless_one_handed_hatch")
                end,
            },
        },
    }
end

return Tapless
