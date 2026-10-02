local DictionaryController = {}
DictionaryController.__index = DictionaryController

-- KOReader's setting for the keyboard layout (VirtualKeyboard:init).
local LAYOUT_SETTING = "keyboard_layout"

local function includes(list, value)
    for _, item in ipairs(list) do
        if item == value then
            return true
        end
    end
    return false
end

function DictionaryController:new(options)
    return setmetatable({
        plugin_dir = assert(options.plugin_dir),
        manager = assert(options.manager),
        registry = assert(options.registry),
        store = assert(options.store),
        scoring = assert(options.scoring),
        ui_manager = assert(options.ui_manager),
        settings = assert(options.settings),
        logger = assert(options.logger),
        setting_key = assert(options.setting_key),
        enabled_setting_key = assert(options.enabled_setting_key),
        setup_setting_key = assert(options.setup_setting_key),
        default_profile = assert(options.default_profile),
        -- KOReader's VirtualKeyboard.lang_to_keyboard_layout: its layout
        -- setting's values to the layout files they build. Without it the
        -- language leaves KOReader's layout alone.
        layouts = options.layouts or {},
    }, self)
end

function DictionaryController:_installed()
    return self.manager:listInstalled(self.plugin_dir)
end

function DictionaryController:listEnabled()
    local installed = self:_installed()
    local configured = self.settings:readSetting(self.enabled_setting_key)

    -- Existing users start with all installed dictionaries enabled.
    if type(configured) ~= "table" then
        return installed
    end

    local wanted = {}
    for _, id in ipairs(configured) do
        if type(id) == "string" then
            wanted[id] = true
        end
    end

    local enabled = {}
    for _, info in ipairs(installed) do
        if wanted[info.id] then
            table.insert(enabled, info)
        end
    end

    -- Recover safely if settings refer only to dictionaries that no longer
    -- exist. The manager still prevents deliberately disabling the last one.
    if #enabled == 0 and #installed > 0 then
        table.insert(enabled, installed[1])
        self.settings:saveSetting(
            self.enabled_setting_key, { installed[1].id })
    end

    return enabled
end

function DictionaryController:isEnabled(id)
    for _, info in ipairs(self:listEnabled()) do
        if info.id == id then
            return true
        end
    end
    return false
end

function DictionaryController:activeDictionary(keyboard)
    return keyboard and keyboard.swype_mvp_dictionary
        or self.settings:readSetting(self.setting_key, "en")
end

-- The dictionary's normalization profile, from its registry descriptor,
-- falling back to the default when there is no descriptor or no profile.
function DictionaryController:_profile(dictionary)
    local descriptor = self.registry:get(dictionary, self.plugin_dir)
    return descriptor and descriptor.normalization_profile
        or self.default_profile
end

-- Makes id the active dictionary: on the keyboard when one is open,
-- otherwise in the settings, for when it next opens.
function DictionaryController:_activate(keyboard, id)
    if keyboard then
        return self:setDictionary(keyboard, id)
    end
    self.settings:saveSetting(self.setting_key, id)
    self:followLanguage(nil, id)
    return true
end

-- The KOReader layout file a dictionary is typed with (da_keyboard).
function DictionaryController:_layoutOf(dictionary)
    local descriptor = self.registry:get(dictionary, self.plugin_dir)
    return descriptor and descriptor.keyboard_layout
end

-- The layout file a value of KOReader's layout setting builds, as
-- VirtualKeyboard:init picks it: English for one it doesn't know.
function DictionaryController:_layoutFile(name)
    return self.layouts[name] or self.layouts.en
end

-- The value of KOReader's layout setting that builds file: da for
-- da_keyboard, pt_BR for pt_keyboard.
function DictionaryController:_layoutName(file)
    local short = file:match("^(.-)_keyboard$")
    if short and self.layouts[short] == file then
        return short
    end
    for name, other in pairs(self.layouts) do
        if other == file then
            return name
        end
    end
end

-- The enabled language typed with layout file: current when it is one
-- (English, Italian and Dutch share one), else the first; nil when no
-- enabled language is typed with it.
function DictionaryController:_languageFor(file, current)
    if not file then
        return nil
    end
    local found
    for _, info in ipairs(self:listEnabled()) do
        if self:_layoutOf(info.id) == file then
            if info.id == current then
                return current
            end
            found = found or info.id
        end
    end
    return found
end

-- Puts KOReader's layout with dictionary's: on a keyboard showing, at
-- once, or once the finger holding space lifts (on_lift), since switching
-- rebuilds the keyboard; otherwise in the setting the next keyboard is
-- built from.
function DictionaryController:followLanguage(keyboard, dictionary, on_lift)
    local file = self:_layoutOf(dictionary)
    local name = file and self:_layoutName(file)
    if not name or file == self:_layoutFile(
            self.settings:readSetting(LAYOUT_SETTING)
            or self.settings:readSetting("language")) then
        return
    end
    if keyboard and on_lift then
        keyboard.swype_mvp_layout_on_lift = name
    elseif keyboard and keyboard.visible then
        keyboard:setKeyboardLayout(name)
    else
        self.settings:saveSetting(LAYOUT_SETTING, name)
    end
end

-- The language whose personal words to show, and its normalization
-- profile: the keyboard's when one is open, otherwise the saved language.
function DictionaryController:personalContext(keyboard)
    local dictionary = self:activeDictionary(keyboard)
    local profile = keyboard and keyboard.swype_mvp_normalization_profile
        or self:_profile(dictionary)
    return dictionary, profile
end

function DictionaryController:setEnabled(id, enabled, keyboard)
    if not self.manager:isDictionaryAvailable(id, self.plugin_dir) then
        return false, "Dictionary is not installed."
    end

    local current = {}
    for _, info in ipairs(self:listEnabled()) do
        current[info.id] = true
    end

    if enabled then
        current[id] = true
    else
        current[id] = nil
    end

    local result = {}
    for _, info in ipairs(self:_installed()) do
        if current[info.id] then
            table.insert(result, info.id)
        end
    end

    if #result == 0 then
        return false, "At least one dictionary must remain enabled."
    end

    self.settings:saveSetting(self.enabled_setting_key, result)

    if not enabled and self:activeDictionary(keyboard) == id
            and not self:_activate(keyboard, result[1]) then
        return false, "Cannot switch to another dictionary."
    end

    return true
end

function DictionaryController:selectDictionary(id, keyboard)
    if not self.manager:isDictionaryAvailable(id, self.plugin_dir) then
        return false
    end

    if not self:isEnabled(id) then
        local ok = self:setEnabled(id, true, keyboard)
        if not ok then
            return false
        end
    end

    return self:_activate(keyboard, id)
end

function DictionaryController:prepareRemoval(id, replacement, keyboard)
    if self:activeDictionary(keyboard) ~= id then
        return true
    end

    local target
    for _, info in ipairs(self:listEnabled()) do
        if info.id ~= id then
            target = info.id
            break
        end
    end

    if not target then
        local enabled = self:setEnabled(replacement, true, keyboard)
        if not enabled then
            return false
        end
        target = replacement
    end

    return self:_activate(keyboard, target)
end

function DictionaryController:onDictionaryRemoved(id)
    local enabled_ids = {}
    for _, info in ipairs(self:listEnabled()) do
        if info.id ~= id then
            table.insert(enabled_ids, info.id)
        end
    end

    local installed = self:_installed()
    if #enabled_ids == 0 and #installed > 0 then
        enabled_ids[1] = installed[1].id
    end

    self.settings:saveSetting(self.enabled_setting_key, enabled_ids)

    local active = self.settings:readSetting(self.setting_key, "en")
    local active_enabled = includes(enabled_ids, active)

    if not active_enabled and enabled_ids[1] then
        self.settings:saveSetting(self.setting_key, enabled_ids[1])
    end
end

function DictionaryController:needsLanguageSetup()
    if self.settings:isTrue(self.setup_setting_key) then
        return false
    end

    local installed = self:_installed()

    -- There is nothing useful to choose when zero or one dictionary exists.
    if #installed <= 1 then
        local enabled = {}
        if installed[1] then
            enabled[1] = installed[1].id
            self.settings:saveSetting(self.setting_key, installed[1].id)
        end
        self.settings:saveSetting(self.enabled_setting_key, enabled)
        self.settings:saveSetting(self.setup_setting_key, true)
        return false
    end

    return true
end

function DictionaryController:initialLanguageSelection(keyboard)
    local selected = {}
    local configured = self.settings:readSetting(self.enabled_setting_key)

    -- Keep an existing enabled-language choice when upgrading.
    if type(configured) == "table" then
        for _, id in ipairs(configured) do
            if self.manager:isDictionaryAvailable(id, self.plugin_dir) then
                selected[id] = true
            end
        end
    end

    -- On a fresh install, start with the current dictionary only. The user
    -- can select more languages before continuing.
    if not next(selected) then
        local active = self:activeDictionary(keyboard)
        if self.manager:isDictionaryAvailable(active, self.plugin_dir) then
            selected[active] = true
        else
            local installed = self:_installed()
            if installed[1] then
                selected[installed[1].id] = true
            end
        end
    end

    return selected
end

function DictionaryController:completeLanguageSetup(selected, keyboard)
    local enabled_ids = {}

    for _, info in ipairs(self:_installed()) do
        if selected[info.id] then
            table.insert(enabled_ids, info.id)
        end
    end

    if #enabled_ids == 0 then
        return false, "Choose at least one language."
    end

    local previous = self.settings:readSetting(self.enabled_setting_key)
    self.settings:saveSetting(self.enabled_setting_key, enabled_ids)

    local active_enabled =
        includes(enabled_ids, self:activeDictionary(keyboard))

    if not active_enabled and not self:_activate(keyboard, enabled_ids[1]) then
        if previous == nil then
            self.settings:delSetting(self.enabled_setting_key)
        else
            self.settings:saveSetting(self.enabled_setting_key, previous)
        end
        return false, "Cannot select the chosen language."
    end

    self.settings:saveSetting(self.setup_setting_key, true)
    return true
end

-- Whether it scheduled language setup, which closes the keyboard.
function DictionaryController:scheduleLanguageSetup(keyboard)
    if not self:needsLanguageSetup() then
        return false
    end

    self.ui_manager:scheduleIn(0, function()
        if keyboard.swype_mvp_closed then
            return
        end

        local selected = self:initialLanguageSelection(keyboard)

        -- The setup dialog should replace the keyboard rather than appear
        -- behind it. Passing no keyboard also makes setup update the saved
        -- active language, which is applied when the keyboard opens again.
        keyboard:onClose()

        self.ui_manager:scheduleIn(0, function()
            self.manager:showLanguageSetup(
                nil, self.plugin_dir, selected)
        end)
    end)
    return true
end

-- Runs before KOReader builds the keyboard, when it opens and when its
-- layout changes.
function DictionaryController:initialize(keyboard)
    local previous = keyboard.swype_mvp_dictionary
    local dictionary = self.settings:readSetting(self.setting_key, "en")
    local fell_back = false
    if not self.manager:isDictionaryAvailable(dictionary, self.plugin_dir)
            or not self:isEnabled(dictionary) then
        local enabled = self:listEnabled()
        dictionary = enabled[1] and enabled[1].id or "en"
        self.settings:saveSetting(self.setting_key, dictionary)
        fell_back = true
    end
    -- The layout KOReader is about to build picks the language when an
    -- enabled one is typed with it: chosen from the globe key's menu, or
    -- the one KOReader opens with. A layout no enabled language uses
    -- leaves the language alone.
    local name = keyboard.getKeyboardLayout and keyboard:getKeyboardLayout()
    local typed_with = self:_languageFor(self:_layoutFile(name), dictionary)
    if typed_with and typed_with ~= dictionary then
        dictionary = typed_with
        self.settings:saveSetting(self.setting_key, dictionary)
    elseif fell_back then
        self:followLanguage(nil, dictionary)
    end
    if previous and previous ~= dictionary then
        -- Rebuilt for another layout: leave the old language behind as
        -- setDictionary does.
        keyboard:_swypeCommitPendingContext()
        keyboard:_swypeCancelBucketPrefetch()
        self.store:keepOnly(dictionary)
    end
    keyboard.swype_mvp_dictionary = dictionary
    keyboard.swype_mvp_normalization_profile = self:_profile(dictionary)
end

function DictionaryController:label(keyboard)
    return self.manager:shortLabel(keyboard.swype_mvp_dictionary)
end

-- Switches to the next enabled language. Returns false, leaving the
-- keyboard alone, when there is no other language to switch to.
function DictionaryController:toggle(keyboard)
    local installed = self:listEnabled()
    if #installed < 2 then
        return false
    end
    keyboard:_swypeCommitPendingContext()
    local current_index
    for index, info in ipairs(installed) do
        if info.id == keyboard.swype_mvp_dictionary then
            current_index = index
            break
        end
    end
    local next_info = installed[(current_index or 0) % #installed + 1]
    -- Under the finger still holding space: its layout waits for the lift.
    keyboard:_swypeSetDictionary(next_info.id, true)
    return true
end

-- layout_on_lift: switch KOReader's layout when the finger lifts.
function DictionaryController:setDictionary(keyboard, dictionary,
        layout_on_lift)
    if not self.manager:isDictionaryAvailable(dictionary, self.plugin_dir) then
        return false
    end
    keyboard:_swypeCommitPendingContext()
    keyboard:_swypeCancelBucketPrefetch()
    self.store:invalidate(dictionary)
    keyboard.swype_mvp_dictionary = dictionary
    keyboard.swype_mvp_normalization_profile = self:_profile(dictionary)
    self.store:keepOnly(dictionary)
    self.settings:saveSetting(self.setting_key, dictionary)
    self.logger.info(
        "swype mvp dictionary selected", keyboard.swype_mvp_dictionary)
    keyboard:_swypeClearCandidateRow("ui")
    keyboard:_swypeRefreshLanguageIndicator("flashui")
    keyboard:_swypeScheduleWarmUp(0.1)
    self:followLanguage(keyboard, dictionary, layout_on_lift)
    return true
end

function DictionaryController:scheduleWarmUp(keyboard, delay)
    keyboard.swype_mvp_warm_generation =
        (keyboard.swype_mvp_warm_generation or 0) + 1
    local generation = keyboard.swype_mvp_warm_generation
    local dictionary = keyboard.swype_mvp_dictionary or "en"
    self.ui_manager:scheduleIn(delay or 0.35, function()
        if keyboard.swype_mvp_warm_generation ~= generation
                or not keyboard.visible
                or keyboard.swype_mvp_dictionary ~= dictionary then
            return
        end
        if keyboard.swype_mvp_trace then
            keyboard:_swypeScheduleWarmUp(0.5)
            return
        end
        self.store:keepOnly(dictionary)
        self.store:open(dictionary)
        self.scoring:warm()
    end)
end

function DictionaryController:stopWarmUp(keyboard)
    keyboard.swype_mvp_warm_generation =
        (keyboard.swype_mvp_warm_generation or 0) + 1
end

return DictionaryController
