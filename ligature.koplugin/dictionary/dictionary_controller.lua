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

function DictionaryController:_isInstalled(id)
    return self.manager:isDictionaryAvailable(id, self.plugin_dir)
end

-- The installed dictionaries' ids, as a set.
function DictionaryController:_installedIds()
    local ids = {}
    for _, info in ipairs(self:_installed()) do
        ids[info.id] = true
    end
    return ids
end

-- The enabled setting's ids, or nil when there is none. It can name
-- languages chosen but not installed yet.
function DictionaryController:_configured()
    local configured = self.settings:readSetting(self.enabled_setting_key)
    if type(configured) ~= "table" then
        return nil
    end
    local ids = {}
    for _, id in ipairs(configured) do
        if type(id) == "string" then
            ids[#ids + 1] = id
        end
    end
    return ids
end

-- The enabled ids, as the setting has them or, with no setting, every
-- installed dictionary's.
function DictionaryController:_enabledIds()
    local ids = self:_configured()
    if not ids then
        ids = {}
        for _, info in ipairs(self:_installed()) do
            ids[#ids + 1] = info.id
        end
    end
    return ids
end

-- Saves ids as the enabled setting, putting the first installed
-- dictionary first when none of them is installed: the keyboard always
-- has a language to type in.
function DictionaryController:_saveEnabled(ids)
    local installed = self:_installedIds()
    local any = false
    for _, id in ipairs(ids) do
        any = any or installed[id] == true
    end
    local first = self:_installed()[1]
    if not any and first then
        table.insert(ids, 1, first.id)
    end
    self.settings:saveSetting(self.enabled_setting_key, ids)
end

-- Every language setup can offer, installed or in the catalog, in order.
function DictionaryController:_choiceIds()
    local ids = {}
    for _, choice in ipairs(self.manager:setupChoices(self.plugin_dir)) do
        ids[#ids + 1] = choice.id
    end
    return ids
end

-- The catalog packages of the enabled languages that aren't installed,
-- leaving out those already downloading. An enabled language neither
-- installed nor in the catalog (a dictionary removed by hand, say) is
-- taken out of the setting, as nothing could install it.
function DictionaryController:missingLanguages()
    local configured = self:_configured()
    if not configured then
        return {}
    end
    local installed = self:_installedIds()
    local missing = {}
    for _, id in ipairs(configured) do
        if not installed[id] then
            missing[#missing + 1] = id
        end
    end
    if not missing[1] then
        return {}
    end
    local packages = self.manager:catalogPackages(self.plugin_dir)
    local result, unknown = {}, {}
    for _, id in ipairs(missing) do
        if not packages[id] then
            unknown[#unknown + 1] = id
        elseif not self.manager:isQueued(id) then
            result[#result + 1] = packages[id]
        end
    end
    if unknown[1] then
        self:forgetMissing(unknown)
    end
    return result
end

-- Takes those of ids that aren't installed out of the enabled setting.
function DictionaryController:forgetMissing(ids)
    local installed = self:_installedIds()
    local forget = {}
    for _, id in ipairs(ids) do
        forget[id] = not installed[id]
    end
    local kept = {}
    for _, id in ipairs(self:_configured() or {}) do
        if not forget[id] then
            kept[#kept + 1] = id
        end
    end
    self:_saveEnabled(kept)
end

function DictionaryController:listEnabled()
    local installed = self:_installed()
    local configured = self:_configured()

    -- Existing users start with all installed dictionaries enabled.
    if not configured then
        return installed
    end

    local wanted = {}
    for _, id in ipairs(configured) do
        wanted[id] = true
    end

    local enabled = {}
    for _, info in ipairs(installed) do
        if wanted[info.id] then
            table.insert(enabled, info)
        end
    end

    -- Settings can name only languages that aren't installed: ones still
    -- to download. Type in the first installed one meanwhile,
    -- without forgetting them. The manager still prevents deliberately
    -- disabling the last one.
    if #enabled == 0 and #installed > 0 then
        table.insert(enabled, installed[1])
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

-- Enables or disables an installed dictionary, changing only its own
-- place in the setting.
function DictionaryController:setEnabled(id, enabled, keyboard)
    if not self.manager:isDictionaryAvailable(id, self.plugin_dir) then
        return false, "Dictionary is not installed."
    end

    local result, present = {}, false
    for _, other in ipairs(self:_enabledIds()) do
        if other ~= id then
            result[#result + 1] = other
        elseif enabled then
            result[#result + 1] = id
            present = true
        end
    end
    if enabled and not present then
        result[#result + 1] = id
    end

    local installed = self:_installedIds()
    local any = false
    for _, other in ipairs(result) do
        any = any or installed[other] == true
    end
    if not any then
        return false, "At least one dictionary must remain enabled."
    end

    self.settings:saveSetting(self.enabled_setting_key, result)

    local first = self:listEnabled()[1]
    if self:activeDictionary(keyboard) == id and not self:isEnabled(id)
            and not (first and self:_activate(keyboard, first.id)) then
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
    for _, other in ipairs(self:_enabledIds()) do
        if other ~= id then
            enabled_ids[#enabled_ids + 1] = other
        end
    end
    self:_saveEnabled(enabled_ids)

    local active = self.settings:readSetting(self.setting_key, "en")
    local first = self:listEnabled()[1]
    if not self:isEnabled(active) and first then
        self.settings:saveSetting(self.setting_key, first.id)
    end
end

function DictionaryController:needsLanguageSetup()
    if self.settings:isTrue(self.setup_setting_key) then
        return false
    end

    local installed = self:_installed()

    -- There is nothing useful to choose when zero or one language exists,
    -- installed or in the catalog.
    if #self:_choiceIds() <= 1 then
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

    -- Keep an existing enabled-language choice when upgrading, including
    -- languages to download.
    if type(configured) == "table" then
        local offered = {}
        for _, id in ipairs(self:_choiceIds()) do
            offered[id] = true
        end
        for _, id in ipairs(configured) do
            if offered[id] then
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

-- Enables the selected languages, including ones still to download (the
-- manager downloads them next). The active language moves to the first
-- installed one chosen; with none installed it stays until they are.
function DictionaryController:completeLanguageSetup(selected, keyboard)
    local enabled_ids = {}
    local first_installed

    for _, id in ipairs(self:_choiceIds()) do
        if selected[id] then
            table.insert(enabled_ids, id)
            if not first_installed and self:_isInstalled(id) then
                first_installed = id
            end
        end
    end

    if #enabled_ids == 0 then
        return false, "Choose at least one language."
    end

    local previous = self.settings:readSetting(self.enabled_setting_key)
    self.settings:saveSetting(self.enabled_setting_key, enabled_ids)

    local active_enabled =
        includes(enabled_ids, self:activeDictionary(keyboard))

    if not active_enabled and first_installed
            and not self:_activate(keyboard, first_installed) then
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

-- Whether it scheduled language setup, or the offer to download enabled
-- languages that aren't installed; either closes the keyboard.
function DictionaryController:scheduleLanguageSetup(keyboard)
    local setup = self:needsLanguageSetup()
    local missing = not setup and self:missingLanguages() or {}
    if not setup and not missing[1] then
        return false
    end

    self.ui_manager:scheduleIn(0, function()
        if keyboard.swype_mvp_closed then
            return
        end

        local selected = setup and self:initialLanguageSelection(keyboard)

        -- The dialog should replace the keyboard rather than appear
        -- behind it. Passing no keyboard also makes setup update the saved
        -- active language, which is applied when the keyboard opens again.
        keyboard:onClose()

        self.ui_manager:scheduleIn(0, function()
            if setup then
                self.manager:showLanguageSetup(
                    nil, self.plugin_dir, selected)
            else
                self.manager:offerDownloads(self.plugin_dir, missing)
            end
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
    if not self:_isInstalled(dictionary)
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
