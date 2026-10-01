local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local source = debug.getinfo(1, "S").source
local plugin_dir = source:match("^@(.+)/main%.lua$") or "."
local virtualkeyboard_module = "ui/widget/virtualkeyboard"
local replacement_path = plugin_dir .. "/virtualkeyboard.lua"

local Screen = require("device").screen
local modules = dofile(plugin_dir .. "/modules.lua")
local OneHanded = dofile(plugin_dir .. "/" .. modules.one_handed)

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
    logger.info("Ligature: thin VirtualKeyboard adapter loaded")

    -- InputText caches the keyboard class during its own module initialization.
    -- Re-run that binding so an early-loaded InputText also uses Ligature.
    local InputText = require("ui/widget/inputtext")
    InputText.initInputEvents()
    logger.info("Ligature: InputText keyboard binding refreshed")
else
    logger.err("Ligature: failed to load VirtualKeyboard implementation", replacement)
end

local Ligature = WidgetContainer:extend{
    name = "ligature",
    is_doc_only = false,
}

function Ligature:init()
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

function Ligature:openDictionaryManager()
    if replacement and replacement.ligatureOpenDictionaryManager then
        replacement.ligatureOpenDictionaryManager()
    else
        logger.err("Ligature: dictionary manager is unavailable")
    end
end

function Ligature:openGestureReference()
    if replacement and replacement.ligatureOpenGestureReference then
        replacement.ligatureOpenGestureReference()
    else
        logger.err("Ligature: gesture reference is unavailable")
    end
end

-- A radio menu entry that saves value under setting_key, checked while
-- the setting (default when unset) is value.
local function choice(text, setting_key, value, default)
    return {
        text = text,
        radio = true,
        checked_func = function()
            return G_reader_settings:readSetting(setting_key, default)
                == value
        end,
        callback = function()
            G_reader_settings:saveSetting(setting_key, value)
        end,
    }
end

function Ligature:addToMainMenu(menu_items)
    local plugin = self

    menu_items.ligature_settings = {
        text = "Ligature",
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = "Manage dictionaries",
                callback = function()
                    plugin:openDictionaryManager()
                end,
            },
            {
                text = "Gesture reference",
                callback = function()
                    plugin:openGestureReference()
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
                                "ligature_keyboard_size") == nil
                        end,
                        callback = function()
                            G_reader_settings:delSetting(
                                "ligature_keyboard_size")
                        end,
                    },
                    choice("Extra compact", "ligature_keyboard_size",
                        "extra_compact"),
                    choice("Compact", "ligature_keyboard_size", "compact"),
                    choice("Normal", "ligature_keyboard_size", "normal"),
                    choice("Large", "ligature_keyboard_size", "large"),
                },
            },
            {
                text = "Keyboard text size",
                sub_item_table = {
                    choice("Auto", "ligature_keyboard_font_size", "auto",
                        "auto"),
                    choice("Small", "ligature_keyboard_font_size", 18,
                        "auto"),
                    choice("Normal", "ligature_keyboard_font_size", 22,
                        "auto"),
                    choice("Large", "ligature_keyboard_font_size", 26,
                        "auto"),
                },
            },
            {
                text = "Slide on space to move cursor",
                help_text = "Slide left or right along the space bar to "
                    .. "move the text cursor. Holding space still switches "
                    .. "language.",
                checked_func = function()
                    return G_reader_settings:isTrue("ligature_space_cursor")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("ligature_space_cursor")
                end,
            },
            {
                text = "Double space types a period",
                help_text = "A second space right after a word, or a space "
                    .. "right after a swiped word, becomes \". \". Not used "
                    .. "on Chinese, Japanese, Korean or Vietnamese layouts.",
                checked_func = function()
                    return G_reader_settings:isTrue(
                        "ligature_double_space_period")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse(
                        "ligature_double_space_period")
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
                        "ligature_rank_down_offensive")
                end,
                callback = function()
                    G_reader_settings:flipNilOrTrue(
                        "ligature_rank_down_offensive")
                end,
            },
            {
                text = "One-handed keyboard",
                sub_item_table = {
                    {
                        text = "Use one-handed keyboard",
                        help_text = "Narrows the keys to one side of the "
                            .. "screen, with the page beside them. A ◨ "
                            .. "handle at the end of the suggestion row: "
                            .. "swipe up to leave, outwards to move the "
                            .. "keys to the other side, or inwards to "
                            .. "resize them. Tap or hold it for a menu. "
                            .. "Hold the globe key and lift to switch it on "
                            .. "or off while typing. Portrait and landscape "
                            .. "are remembered separately.",
                        checked_func = function()
                            return OneHanded:new(G_reader_settings)
                                :state(screenInfo()).enabled
                        end,
                        callback = function()
                            OneHanded:new(G_reader_settings)
                                :toggle(screenInfo())
                        end,
                    },
                    {
                        text = "Background blur",
                        help_text = "Covers the space between the one-handed "
                            .. "keys and the screen edge with fine diagonal "
                            .. "lines, instead of showing the page there. "
                            .. "Tapping it still closes the keyboard.",
                        checked_func = function()
                            return G_reader_settings:nilOrTrue(
                                "ligature_one_handed_hatch")
                        end,
                        callback = function()
                            G_reader_settings:flipNilOrTrue(
                                "ligature_one_handed_hatch")
                        end,
                    },
                },
            },
        },
    }
end

return Ligature
