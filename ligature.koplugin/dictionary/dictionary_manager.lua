-- Ligature dictionary catalog, download and installation manager.
-- The manager is intentionally independent from the swipe-scoring code so
-- network and archive work can only start from an explicit user action.

local Archiver = require("ffi/archiver")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local json = require("json")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ltn12 = require("ltn12")
local NetworkMgr = require("ui/network/manager")
local sha2 = require("ffi/sha2")
local http = require("socket.http")
local socketutil = require("socketutil")
local UIManager = require("ui/uimanager")
local util = require("util")
local Screen = require("device").screen


local CATALOG_URL = "https://pixxel123.github.io/ligature.dictionaries/catalog.json"
local RELEASE_BASE_URL = "https://github.com/Pixxel123/ligature.dictionaries/releases/download/v"
local MAX_PACKAGE_BYTES = 16 * 1024 * 1024
local MAX_UNCOMPRESSED_BYTES = 20 * 1024 * 1024
local MAX_CATALOG_BYTES = 256 * 1024
local REQUIRED_FILES = {
    ["manifest.tsv"] = true,
    ["words.buckets.tsv"] = true,
    ["words.buckets.idx"] = true,
    ["words.popular.tsv"] = true,
    ["words.popular.idx"] = true,
}
local OPTIONAL_FILES = {
    ["ATTRIBUTION.txt"] = true,
    ["LICENSE-wordfreq.txt"] = true,
    ["DATA-LICENSE.txt"] = true,
    ["words.pairs.tsv"] = true,
    ["words.pairs.idx"] = true,
}
local Manager = {
    -- The keyboard's own registry, so an install or removal here
    -- invalidates the list the keyboard reads, not a second copy of it.
    registry = nil,
    catalog = nil,
    catalog_path = nil,
    plugin_dir = nil,
    keyboard = nil,
    personal_dictionary = nil,
    blocked_words = nil,
    language_controller = nil,
    gesture_reference = nil,
    menu = nil,
    language_setup_menu = nil,
    language_setup_selected = nil,
    loading_message = nil,
    -- Ids of the packages waiting for runWhenOnline or downloading.
    queued = {},
}

local function isSafeId(value)
    return Manager.registry:isSafeId(value)
end

local function isSafeFilename(value)
    return type(value) == "string"
        and value:match("^[A-Za-z0-9][A-Za-z0-9_.-]*$") ~= nil
end

local function exists(path)
    return path and lfs.attributes(path) ~= nil
end

local function isDirectory(path)
    return path and lfs.attributes(path, "mode") == "directory"
end

local function removeTree(path)
    if not path or not exists(path) then
        return true
    end
    if not isDirectory(path) then
        return os.remove(path) == true
    end
    for name in lfs.dir(path) do
        if name ~= "." and name ~= ".." then
            local child = path .. "/" .. name
            if not removeTree(child) then
                return false
            end
        end
    end
    return lfs.rmdir(path) ~= nil
end

local function readFile(path, max_bytes)
    local file = io.open(path, "rb")
    if not file then
        return nil, "Cannot open file"
    end
    local data = file:read(max_bytes and (max_bytes + 1) or "*a")
    file:close()
    if max_bytes and data and #data > max_bytes then
        return nil, "File is too large"
    end
    return data
end

local function writeFile(path, data)
    local file = io.open(path, "wb")
    if not file then
        return nil, "Cannot write file"
    end
    local ok, err = file:write(data)
    file:close()
    if not ok then
        return nil, err or "Write error"
    end
    return true
end

local function hexDigest(value)
    if type(value) ~= "string" then
        return nil
    end
    if #value == 64 and value:match("^[0-9a-fA-F]+$") then
        return value:lower()
    end
    if #value == 32 then
        return (value:gsub(".", function(char)
            return string.format("%02x", string.byte(char))
        end))
    end
end

local function sha256File(path)
    local data, err = readFile(path)
    if not data then
        return nil, err
    end
    local ok, digest = pcall(sha2.sha256, data)
    if not ok then
        return nil, digest
    end
    digest = hexDigest(digest)
    if not digest then
        return nil, "Unsupported SHA-256 result"
    end
    return digest
end

local function validatePackageRecord(package)
    if type(package) ~= "table"
            or not isSafeId(package.id)
            or type(package.name) ~= "string"
            or package.name == ""
            or type(package.version) ~= "string"
            or package.version == ""
            or not isSafeFilename(package.archive)
            or type(package.sha256) ~= "string"
            or #package.sha256 ~= 64
            or not package.sha256:match("^[0-9a-fA-F]+$")
            or type(package.size) ~= "number"
            or package.size < 1
            or package.size > MAX_PACKAGE_BYTES then
        return nil
    end
    return {
        id = package.id,
        name = package.name,
        version = package.version,
        archive = package.archive,
        size = math.floor(package.size),
        sha256 = package.sha256:lower(),
        download_url = type(package.download_url) == "string" and package.download_url or nil,
    }
end

local function validateCatalog(data)
    if type(data) ~= "table" or tonumber(data.format) ~= 1 or type(data.packages) ~= "table" then
        return nil, "Unsupported catalog format"
    end
    local packages = {}
    for _, package in ipairs(data.packages) do
        local valid = validatePackageRecord(package)
        if valid then
            packages[valid.id] = valid
        end
    end
    if not next(packages) then
        return nil, "Catalog contains no valid packages"
    end
    return { packages = packages }
end

local function localRoot()
    return DataStorage:getDataDir() .. "/ligature"
end

local function installedPath(id, plugin_dir)
    local descriptor = Manager.registry:get(id, plugin_dir)
    if descriptor then
        return descriptor.path, descriptor.bundled
    end
end

function Manager:shortLabel(id)
    return Manager.registry:shortLabel(id, self.plugin_dir)
end

function Manager:isDictionaryAvailable(id, plugin_dir)
    return Manager.registry:isAvailable(id, plugin_dir or self.plugin_dir)
end

function Manager:listInstalled(plugin_dir)
    return Manager.registry:list(plugin_dir or self.plugin_dir)
end

local function readCatalog(path)
    local data = path and readFile(path, MAX_CATALOG_BYTES)
    if not data then
        return nil
    end
    local ok, decoded = pcall(json.decode, data)
    if not ok then
        return nil
    end
    return (validateCatalog(decoded))
end

function Manager:_loadCachedCatalog()
    local catalog = readCatalog(self.catalog_path)
    if catalog then
        self.catalog = catalog
    end
    return self.catalog
end

-- The catalog's packages by id: the last catalog downloaded, else the copy
-- that ships with the plugin, so setup can offer every language offline.
function Manager:catalogPackages(plugin_dir)
    self.catalog_path = self.catalog_path or localRoot() .. "/catalog.json"
    if not self.catalog then
        self:_loadCachedCatalog()
    end
    local dir = plugin_dir or self.plugin_dir
    if not self.catalog and dir then
        local shipped = readCatalog(dir .. "/catalog.json")
        if shipped then
            shipped.shipped = true
            self.catalog = shipped
        end
    end
    return self.catalog and self.catalog.packages or {}
end

local function httpToFile(url, target)
    for redirect_count = 0, 5 do
        local file = io.open(target, "wb")
        if not file then
            return nil, "Cannot create temporary file"
        end
        socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
        local ok, result, code, headers = pcall(function()
            return http.request{
                url = url,
                method = "GET",
                headers = { ["User-Agent"] = "Ligature-KOReader" },
                sink = ltn12.sink.file(file),
            }
        end)
        socketutil:reset_timeout()
        -- ltn12.sink.file closes the handle after the response; on an error
        -- it may still be open, so closing it must be idempotent.
        pcall(function() file:close() end)
        if not ok then
            os.remove(target)
            return nil, result
        end
        code = tonumber(code)
        if result and code and code >= 200 and code < 300 then
            return true
        end
        local location = headers and (headers.location or headers.Location)
        os.remove(target)
        if not (code and code >= 300 and code < 400 and location
                and redirect_count < 5) then
            return nil, "Server returned HTTP " .. tostring(code or result)
        end
        url = location
    end
    os.remove(target)
    return nil, "Too many redirects"
end

function Manager:_fetchCatalog()
    local temp_path = localRoot() .. "/catalog.json.part"
    util.makePath(localRoot())
    local ok, err = httpToFile(CATALOG_URL, temp_path)
    if not ok then
        return nil, err
    end
    local data, read_err = readFile(temp_path, MAX_CATALOG_BYTES)
    if not data then
        os.remove(temp_path)
        return nil, read_err
    end
    local decoded_ok, decoded = pcall(json.decode, data)
    local catalog, catalog_err
    if decoded_ok then
        catalog, catalog_err = validateCatalog(decoded)
    else
        catalog_err = decoded
    end
    if not catalog then
        os.remove(temp_path)
        return nil, catalog_err
    end
    local write_ok, write_err = writeFile(self.catalog_path, data)
    os.remove(temp_path)
    if not write_ok then
        return nil, write_err
    end
    self.catalog = catalog
    return catalog
end

function Manager:_closeLoading()
    if self.loading_message then
        UIManager:close(self.loading_message)
        self.loading_message = nil
    end
end

function Manager:_showLoading(text)
    self:_closeLoading()
    self.loading_message = InfoMessage:new{ text = text, timeout = 0 }
    UIManager:show(self.loading_message)
    -- Downloads block until they finish; draw the message before they start.
    UIManager:forceRePaint()
end

function Manager:_closeMenu()
    if self.menu then
        UIManager:close(self.menu)
        self.menu = nil
    end
end

function Manager:_notify(text)
    UIManager:show(InfoMessage:new{ text = text, timeout = 3 })
end

function Manager:_select(id)
    self:_closeMenu()
    if not self.language_controller:selectDictionary(id, self.keyboard) then
        self:_notify("Cannot select dictionary " .. id .. ".")
        self:showMenu()
    end
end

function Manager:_setEnabled(id, enabled)
    local ok, err = self.language_controller:setEnabled(
        id, enabled, self.keyboard)
    if not ok then
        self:_notify(err or "Cannot change dictionary state.")
    end
    self:showMenu()
end

function Manager:_uninstall(id, name)
    local path, bundled = installedPath(id, self.plugin_dir)
    if not path then
        self:_notify("This dictionary is not installed.")
        return
    end

    local replacement
    for _, info in ipairs(self:listInstalled(self.plugin_dir)) do
        if info.id ~= id then
            replacement = replacement or info.id
        end
    end

    if not replacement then
        self:_notify(
            "Install another dictionary before removing the last one.")
        return
    end

    local warning = bundled
        and "\n\nThis removes files from the plugin folder. "
            .. "A plugin update may restore them."
        or "\n\nThe downloaded dictionary files will be removed."

    UIManager:show(ConfirmBox:new{
        text = "Uninstall dictionary " .. (name or id) .. "?" .. warning,
        ok_text = "Uninstall",
        ok_callback = function()
            if not self.language_controller:prepareRemoval(
                    id, replacement, self.keyboard) then
                self:_notify(
                    "Cannot switch dictionaries before uninstalling.")
                return
            end

            local removed = removeTree(path)
            Manager.registry:invalidate()
            if removed then
                self.language_controller:onDictionaryRemoved(id)
                self:_notify("Uninstalled dictionary: " .. (name or id))
            else
                self:_notify("Failed to uninstall dictionary: " .. (name or id))
            end
            self:showMenu()
        end,
    })
end

function Manager:_personalContext()
    return self.language_controller:personalContext(self.keyboard)
end

function Manager:_removePersonalWord(word)
    local language, profile = self:_personalContext()
    UIManager:show(ConfirmBox:new{
        text = "Remove \"" .. word .. "\" from personal words?",
        ok_text = "Remove",
        ok_callback = function()
            local removed, err = self.personal_dictionary:remove(
                language, word, profile)
            if removed then
                self:_notify("Removed personal word: " .. word)
            else
                self:_notify("Failed to remove personal word:\n"
                    .. tostring(err or word))
            end
            self:showPersonalWords()
        end,
    })
end

-- A page of words, each with one action, then Back.
function Manager:_showWordList(title, words, empty_text, action_text,
        on_action)
    local buttons = {}
    local action_width = Screen:scaleBySize(140)
    for _, word in ipairs(words) do
        table.insert(buttons, {
            {
                text = word,
                align = "left",
                enabled = false,
                callback = function() end,
            },
            {
                text = action_text,
                width = action_width,
                callback = function() on_action(word) end,
            },
        })
    end
    if #words == 0 then
        table.insert(buttons, {
            {
                text = empty_text,
                enabled = false,
                callback = function() end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = "Back",
            callback = function() self:showMenu() end,
        },
    })
    self.menu = ButtonDialog:new{
        title = title,
        width_factor = 0.95,
        rows_per_page = 8,
        buttons = buttons,
    }
    UIManager:show(self.menu)
end

function Manager:showBlockedWords()
    self:_closeMenu()
    local language = self:_personalContext()
    self:_showWordList(
        "Ligature: Blocked words (" .. string.upper(language) .. ")",
        self.blocked_words:list(language),
        "No blocked words. Hold a suggestion to block it.",
        "Unblock",
        function(word)
            local removed, err = self.blocked_words:remove(language, word)
            if removed == nil then
                self:_notify("Failed to unblock:\n" .. tostring(err or word))
            end
            self:showBlockedWords()
        end)
end

function Manager:showPersonalWords()
    self:_closeMenu()
    local language, profile = self:_personalContext()
    self:_showWordList(
        "Ligature: Personal words (" .. string.upper(language) .. ")",
        self.personal_dictionary:list(language, profile),
        "No personal words",
        "Remove",
        function(word) self:_removePersonalWord(word) end)
end

function Manager:_packageUrl(package)
    if package.download_url and package.download_url:match("^https://") then
        return package.download_url
    end
    return RELEASE_BASE_URL .. package.version .. "/" .. package.archive
end

local function validateArchivePath(path)
    return type(path) == "string"
        and path:match("^[A-Za-z0-9_.-]+$") ~= nil
        and (REQUIRED_FILES[path] or OPTIONAL_FILES[path])
end

function Manager:_extractAndValidate(package, zip_path, temp_dir)
    local reader = Archiver.Reader:new()
    local ok, err = pcall(function()
        reader:open(zip_path)
        local seen = {}
        for entry in reader:iterate() do
            local path = entry.path
            if not validateArchivePath(path) or seen[path] then
                error("Forbidden or duplicate file in ZIP: " .. tostring(path))
            end
            seen[path] = true
        end
        for filename in pairs(REQUIRED_FILES) do
            if not seen[filename] then
                error("Missing file in ZIP: " .. filename)
            end
        end
        -- Archiver.Reader on KOReader has no rewind method. Reopen the
        -- archive after the validation pass before extracting its entries.
        reader:close()
        reader = Archiver.Reader:new()
        reader:open(zip_path)
        util.makePath(temp_dir)
        for entry in reader:iterate() do
            reader:extractToPath(entry.path, temp_dir .. "/" .. entry.path)
        end
        reader:close()
    end)
    if not ok then
        pcall(function() reader:close() end)
        return nil, err
    end

    local extracted_bytes = 0
    for _, files in ipairs{ REQUIRED_FILES, OPTIONAL_FILES } do
        for filename in pairs(files) do
            local size =
                lfs.attributes(temp_dir .. "/" .. filename, "size") or 0
            extracted_bytes = extracted_bytes + size
        end
    end
    if extracted_bytes > MAX_UNCOMPRESSED_BYTES then
        return nil, "Extracted package exceeds size limit"
    end

    local manifest, manifest_err = Manager.registry:parseManifest(
        temp_dir .. "/manifest.tsv")
    if not manifest then
        return nil, manifest_err
    end
    if manifest.id ~= package.id then
        return nil, "Manifest ID does not match package"
    end
    local checksums = {
        { "words.buckets.tsv", manifest.sha256_data },
        { "words.buckets.idx", manifest.sha256_index },
        { "words.popular.tsv", manifest.sha256_popular_data },
        { "words.popular.idx", manifest.sha256_popular_index },
        { "words.pairs.tsv", manifest.sha256_pairs_data },
        { "words.pairs.idx", manifest.sha256_pairs_index },
    }
    for _, item in ipairs(checksums) do
        if item[2] then
            local digest, digest_err = sha256File(temp_dir .. "/" .. item[1])
            if not digest then
                return nil, digest_err
            end
            if digest ~= string.lower(item[2]) then
                return nil, "Checksum mismatch for file " .. item[1]
            end
        end
    end
    return true
end

function Manager:_installPackage(package, zip_path)
    local dictionaries_root = Manager.registry:externalRoot()
    local install_root = localRoot() .. "/install"
    local temp_dir = install_root .. "/" .. package.id .. ".tmp"
    local destination = dictionaries_root .. "/" .. package.id
    local backup = dictionaries_root .. "/." .. package.id .. ".backup"
    removeTree(temp_dir)
    removeTree(backup)
    util.makePath(install_root)
    util.makePath(dictionaries_root)

    local ok, err = self:_extractAndValidate(package, zip_path, temp_dir)
    if not ok then
        removeTree(temp_dir)
        return nil, err
    end
    if exists(destination) and not os.rename(destination, backup) then
        removeTree(temp_dir)
        return nil, "Cannot prepare replacement for existing dictionary"
    end
    if not os.rename(temp_dir, destination) then
        if exists(backup) then
            os.rename(backup, destination)
        end
        removeTree(temp_dir)
        return nil, "Cannot install dictionary"
    end
    removeTree(backup)
    Manager.registry:invalidate()
    return true
end

function Manager:_downloadAndInstall(package)
    local download_root = localRoot() .. "/downloads"
    util.makePath(download_root)
    local zip_path = download_root .. "/" .. package.archive .. ".part"
    os.remove(zip_path)
    local ok, err = httpToFile(self:_packageUrl(package), zip_path)
    if not ok then
        return nil, err
    end
    local size = lfs.attributes(zip_path, "size")
    if not size or size ~= package.size then
        os.remove(zip_path)
        return nil, "Downloaded package size mismatch"
    end
    local digest, digest_err = sha256File(zip_path)
    if not digest then
        os.remove(zip_path)
        return nil, digest_err
    end
    if digest ~= package.sha256 then
        os.remove(zip_path)
        return nil, "Downloaded package checksum mismatch"
    end
    local installed, install_err = self:_installPackage(package, zip_path)
    os.remove(zip_path)
    return installed, install_err
end

-- Whether id is waiting to download, or downloading.
function Manager:isQueued(id)
    return self.queued[id] == true
end

-- Downloads and installs packages in turn once online, then calls
-- done(failed), failed listing { package =, err = } for each that failed.
-- runWhenOnline drops the callback when the user declines Wi-Fi, so the
-- menu stays and nothing is shown before it runs; the packages then stay
-- queued until KOReader restarts.
function Manager:_downloadPackages(packages, done)
    for _, package in ipairs(packages) do
        self.queued[package.id] = true
    end
    NetworkMgr:runWhenOnline(function()
        self:_closeMenu()
        local failed = {}
        for index, package in ipairs(packages) do
            local text = "Downloading dictionary: " .. package.name
            if #packages > 1 then
                text = text .. " (" .. index .. " of " .. #packages .. ")"
            end
            self:_showLoading(text .. "...")
            local call_ok, ok, err = pcall(self._downloadAndInstall, self,
                package)
            if not call_ok then
                ok, err = false, ok
            end
            if not ok then
                logger.warn("Ligature dictionary install failed",
                    package.id, err)
                failed[#failed + 1] = { package = package, err = err }
            end
            self.queued[package.id] = nil
        end
        self:_closeLoading()
        done(failed)
    end)
end

local function failureText(failed)
    local lines = {}
    for _, item in ipairs(failed) do
        lines[#lines + 1] = item.package.name .. ": " .. tostring(item.err)
    end
    return "Failed to install dictionary:\n" .. table.concat(lines, "\n")
end

local function names(packages)
    local list = {}
    for _, package in ipairs(packages) do
        list[#list + 1] = package.name
    end
    return table.concat(list, ", ")
end

local function megabytes(bytes)
    return string.format("%.1f MB", bytes / (1024 * 1024))
end

-- Tells the user how a download went: what failed, else what installed.
function Manager:_notifyInstalled(packages, failed)
    if failed[1] then
        self:_notify(failureText(failed))
    else
        self:_notify((#packages > 1 and "Installed dictionaries: "
            or "Installed dictionary: ") .. names(packages))
    end
end

function Manager:_download(package)
    self:_downloadPackages({ package }, function(failed)
        self:_notifyInstalled({ package }, failed)
        self:showMenu()
    end)
end

-- Asks about enabled languages that aren't installed: chosen in setup,
-- but declining Wi-Fi or a failed download left them out. Not now, and a
-- download that fails, take them out of the enabled languages; one that
-- installs is enabled already.
function Manager:offerDownloads(plugin_dir, packages)
    self.plugin_dir = plugin_dir or self.plugin_dir
    local size = 0
    local ids = {}
    for _, package in ipairs(packages) do
        size = size + package.size
        ids[#ids + 1] = package.id
    end
    local it = #packages > 1 and "them" or "it"
    UIManager:show(ConfirmBox:new{
        text = "Ligature: " .. names(packages)
            .. (#packages > 1 and " are" or " is")
            .. " enabled but not downloaded. Download " .. it .. " now ("
            .. megabytes(size) .. ")?\n\nYou can also download " .. it
            .. " later under Manage dictionaries.",
        ok_text = "Download",
        cancel_text = "Not now",
        ok_callback = function()
            -- Only those still missing: a download setup started may have
            -- finished while the question was up.
            local still = {}
            for _, package in ipairs(
                    self.language_controller:missingLanguages()) do
                still[package.id] = true
            end
            local wanted = {}
            for _, package in ipairs(packages) do
                if still[package.id] then
                    wanted[#wanted + 1] = package
                end
            end
            if not wanted[1] then
                return
            end
            self:_downloadPackages(wanted, function(failed)
                local failed_ids = {}
                for _, item in ipairs(failed) do
                    failed_ids[#failed_ids + 1] = item.package.id
                end
                self.language_controller:forgetMissing(failed_ids)
                self:_notifyInstalled(wanted, failed)
            end)
        end,
        cancel_callback = function()
            self.language_controller:forgetMissing(ids)
        end,
    })
end

-- Fetches the current catalog once online. The menu stays until then,
-- so declining Wi-Fi leaves it showing.
function Manager:_refreshCatalog()
    NetworkMgr:runWhenOnline(function()
        self:_closeMenu()
        self:_showLoading("Downloading dictionary catalog...")
        local call_ok, catalog, err = pcall(self._fetchCatalog, self)
        if not call_ok then
            catalog, err = nil, catalog
        end
        self:_closeLoading()
        if not catalog then
            self:_notify("Failed to download catalog:\n" .. tostring(err))
        end
        self:showMenu()
    end)
end

function Manager:showMenu()
    self:_closeMenu()
    local installed = {}
    for _, info in ipairs(self:listInstalled(self.plugin_dir)) do
        installed[info.id] = info
    end
    local packages = self.catalog and self.catalog.packages or {}
    local ids = {}
    for id in pairs(installed) do ids[id] = true end
    for id in pairs(packages) do ids[id] = true end
    local ordered = {}
    for id in pairs(ids) do table.insert(ordered, id) end
    table.sort(ordered, Manager.registry.compareIds)
    local buttons = {}
    local action_width = Screen:scaleBySize(105)
    local personal_language, personal_profile = self:_personalContext()
    local personal_count =
        #self.personal_dictionary:list(personal_language, personal_profile)
    table.insert(buttons, {
        {
            text = "Personal words (" .. personal_count .. ")",
            callback = function() self:showPersonalWords() end,
        },
    })
    local blocked_language = self:_personalContext()
    local blocked_count = #self.blocked_words:list(blocked_language)
    table.insert(buttons, {
        {
            text = "Blocked words (" .. blocked_count .. ")",
            callback = function() self:showBlockedWords() end,
        },
    })
    for _, id in ipairs(ordered) do
        local info = installed[id]
        local package = packages[id]
        local name = package and package.name or (info and info.name or id)
        if info then
            local active =
                self.language_controller:activeDictionary(self.keyboard) == id
            local enabled = self.language_controller:isEnabled(id)
            table.insert(buttons, {
                {
                    text = active and "✓ " .. name or name,
                    align = "left",
                    callback = function() self:_select(id) end,
                },
                {
                    text = enabled and "Disable" or "Enable",
                    width = action_width,
                    callback = function()
                        self:_setEnabled(id, not enabled)
                    end,
                },
                {
                    text = "Uninstall",
                    width = action_width,
                    callback = function()
                        self:_uninstall(
                            id, package and package.name or info.name)
                    end,
                },
            })
            -- The catalog has another version of an installed dictionary.
            if package and package.version ~= info.version then
                table.insert(buttons, {
                    {
                        text = "Update " .. name .. " to "
                            .. package.version,
                        callback = function() self:_download(package) end,
                    },
                })
            end
        elseif package then
            table.insert(buttons, {
                {
                    text = name,
                    align = "left",
                    enabled = false,
                    callback = function() end,
                },
                {
                    text = "Download",
                    width = action_width,
                    callback = function() self:_download(package) end,
                },
            })
        end
    end
    table.insert(buttons, {
        {
            text = "Refresh catalog",
            callback = function() self:_refreshCatalog() end,
        },
    })
    table.insert(buttons, {
        {
            text = "Close",
            callback = function() self:_closeMenu() end,
        },
    })
    self.menu = ButtonDialog:new{
        title = "Ligature: Dictionaries",
        width_factor = 0.95,
        rows_per_page = 8,
        buttons = buttons,
    }
    UIManager:show(self.menu)
end

-- What setup offers: the installed languages and the catalog's others,
-- each { id =, name =, package = }, package set when it is to download.
function Manager:setupChoices(plugin_dir)
    local choices = {}
    local installed = {}
    local packages = self:catalogPackages(plugin_dir)
    for _, info in ipairs(self:listInstalled(plugin_dir)) do
        installed[info.id] = true
        local package = packages[info.id]
        choices[#choices + 1] = { id = info.id,
            name = package and package.name or info.name or info.id }
    end
    for id, package in pairs(packages) do
        if not installed[id] then
            choices[#choices + 1] =
                { id = id, name = package.name, package = package }
        end
    end
    table.sort(choices, function(left, right)
        return Manager.registry.compareIds(left.id, right.id)
    end)
    return choices
end

function Manager:_closeLanguageSetup()
    if self.language_setup_menu then
        UIManager:close(self.language_setup_menu)
        self.language_setup_menu = nil
    end
end

function Manager:_showLanguageSetupMenu()
    self:_closeLanguageSetup()

    local selected = self.language_setup_selected or {}
    local buttons = {}

    for _, choice in ipairs(self:setupChoices()) do
        local id = choice.id
        local name = choice.name
        if choice.package then
            name = name .. " (" .. megabytes(choice.package.size)
                .. " download)"
        end
        table.insert(buttons, {
            {
                text = (selected[id] and "[x] " or "[ ] ") .. name,
                align = "left",
                callback = function()
                    selected[id] = not selected[id]
                    self:_showLanguageSetupMenu()
                end,
            },
        })
    end

    table.insert(buttons, {
        {
            -- Over the picker; closing the page comes back to it.
            text = "Show gestures",
            callback = function()
                self.gesture_reference:open()
            end,
        },
        {
            text = "Use selected languages",
            callback = function()
                local ok, err = self.language_controller:
                    completeLanguageSetup(selected, self.keyboard)
                if not ok then
                    self:_notify(err or "Cannot save language selection.")
                    return
                end

                self:_closeLanguageSetup()
                self.language_setup_selected = nil
                -- Chosen languages still to download. One that fails stays
                -- enabled, so offerDownloads asks about it next time.
                local missing = self.language_controller:missingLanguages()
                if missing[1] then
                    self:_downloadPackages(missing, function(failed)
                        self:_notifyInstalled(missing, failed)
                    end)
                end
            end,
        },
    })

    self.language_setup_menu = ButtonDialog:new{
        title = "Ligature: Choose languages",
        width_factor = 0.9,
        rows_per_page = 8,
        buttons = buttons,
        -- Tapping outside closes the dialog without choosing; forget it so
        -- that setup is offered again the next time the keyboard opens.
        tap_close_callback = function()
            self.language_setup_menu = nil
        end,
    }
    UIManager:show(self.language_setup_menu)
end

function Manager:showLanguageSetup(keyboard, plugin_dir, selected)
    local menu = self.language_setup_menu
    if menu and UIManager.isWidgetShown
            and not UIManager:isWidgetShown(menu) then
        self.language_setup_menu = nil
    end
    if self.language_setup_menu then
        return
    end

    self.keyboard = keyboard
    self.plugin_dir = plugin_dir or self.plugin_dir
    self.language_setup_selected = selected or {}
    self:_showLanguageSetupMenu()
end

function Manager:open(keyboard, plugin_dir, personal_dictionary)
    self.keyboard = keyboard
    self.plugin_dir = plugin_dir or self.plugin_dir
    self.personal_dictionary = personal_dictionary or self.personal_dictionary
    self.catalog_path = localRoot() .. "/catalog.json"
    if not self.catalog or self.catalog.shipped then
        self:_loadCachedCatalog()
    end
    -- The menu shows at once, from the copy shipped with the plugin until
    -- a catalog has been downloaded, and the first time that is fetched.
    self:catalogPackages()
    self:showMenu()
    if not self.catalog or self.catalog.shipped then
        self:_refreshCatalog()
    end
end

return Manager
