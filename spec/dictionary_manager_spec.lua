local T = require("helper")
local it = T.it

-- Stand-ins for the KOReader modules the manager requires. Its dialogs
-- are recorded rather than drawn.
local shown = {}
local function widget()
    return { new = function(_, o) return o end }
end
local stubs = {
    ["ffi/archiver"] = {},
    ["ui/widget/buttondialog"] = widget(),
    ["ui/widget/confirmbox"] = widget(),
    ["datastorage"] = { getDataDir = function() return "/nonexistent" end },
    ["ui/widget/infomessage"] = widget(),
    ["json"] = {},
    ["logger"] = { info = function() end, warn = function() end },
    ["ltn12"] = {},
    ["ui/network/manager"] = {},
    ["ffi/sha2"] = {},
    ["socket.http"] = {},
    ["socketutil"] = {},
    ["ui/uimanager"] = {
        show = function(_, dialog) shown[#shown + 1] = dialog end,
        close = function() end,
        forceRePaint = function() end,
    },
    ["util"] = {},
    ["device"] = { screen = {} },
    -- Nothing in these specs is on disk.
    ["libs/libkoreader-lfs"] = { attributes = function() return nil end },
}
for name, module in pairs(stubs) do
    package.preload[name] = package.preload[name] or function()
        return module
    end
end

-- The manager over a registry listing two dictionaries, counting how
-- often its cache is invalidated.
local function setup()
    shown = {}
    local registry = { invalidated = 0 }
    local dictionaries = {
        { id = "en", name = "English", path = "/nonexistent/en" },
        { id = "de", name = "Deutsch", path = "/nonexistent/de" },
    }
    function registry:list() return dictionaries end
    function registry:get(id)
        for _, info in ipairs(dictionaries) do
            if info.id == id then return info end
        end
    end
    function registry:isAvailable(id) return self:get(id) ~= nil end
    function registry:shortLabel(id) return id:upper() end
    function registry:invalidate() self.invalidated = self.invalidated + 1 end
    function registry:isSafeId(id) return id:match("^[a-z][a-z0-9-]*$") end
    function registry.compareIds(left, right)
        if left == right then return false end
        if left == "en" then return true end
        if right == "en" then return false end
        return left < right
    end

    local removed = {}
    local manager = T.load("dictionary_manager")
    manager.registry = registry
    manager.plugin_dir = "/plugin"
    manager.language_controller = {
        prepareRemoval = function() return true end,
        onDictionaryRemoved = function(_, id) removed[#removed + 1] = id end,
    }
    manager.showMenu = function() end
    return manager, registry, removed
end

it("the manager reads the registry it is given", function()
    local manager = setup()
    T.eq(#manager:listInstalled(), 2)
    T.eq(manager:isDictionaryAvailable("de"), true)
    T.eq(manager:isDictionaryAvailable("fr"), false)
    T.eq(manager:shortLabel("de"), "DE")
end)

it("uninstalling invalidates the registry the keyboard reads", function()
    local manager, registry, removed = setup()
    manager:_uninstall("de", "Deutsch")
    T.eq(#shown, 1, "confirmation shown")
    shown[1].ok_callback()
    T.eq(registry.invalidated, 1)
    T.eq(removed[1], "de")
end)

-- A catalog file as the manager reads it: json.decode is stubbed to map
-- the file's text to the decoded catalog.
local decoded = {}
stubs["json"].decode = function(text) return decoded[text] end
local function catalogFile(text, packages)
    decoded[text] = { format = 1, packages = packages }
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local file = assert(io.open(dir .. "/catalog.json", "wb"))
    file:write(text)
    file:close()
    return dir
end

local function package(id, name)
    return { id = id, name = name, version = "2.0.0",
        archive = "ligature-dictionary-" .. id .. ".zip",
        sha256 = string.rep("a", 64), size = 1176037 }
end

it("setup offers the shipped catalog's languages after the installed",
        function()
    local manager = setup()
    manager.plugin_dir = catalogFile("shipped",
        { package("pl", "Polish"), package("en", "English"),
            package("cs", "Czech") })
    local choices = manager:setupChoices()
    T.eq(#choices, 4)
    T.eq(choices[1].id, "en")
    T.eq(choices[1].package, nil, "installed")
    T.eq(choices[1].name, "English", "the catalog's name")
    T.eq(choices[3].name, "Deutsch", "not in the catalog")
    T.eq(choices[2].id, "cs")
    T.eq(choices[2].package.name, "Czech")
    T.eq(choices[3].id, "de")
    T.eq(choices[4].id, "pl")
    T.eq(manager.catalog.shipped, true)
end)

it("a downloaded catalog takes over from the shipped one", function()
    local manager = setup()
    manager.plugin_dir = catalogFile("shipped2", { package("pl", "Polish") })
    manager.catalog_path =
        catalogFile("cached", { package("fr", "French") }) .. "/catalog.json"
    local packages = manager:catalogPackages()
    T.truthy(packages.fr)
    T.eq(packages.pl, nil)
    T.eq(manager.catalog.shipped, nil)
end)

-- Network stand-in: online runs the download at once, offline drops it
-- the way KOReader does when the user declines Wi-Fi.
local network = stubs["ui/network/manager"]
-- install: what _downloadAndInstall does ("ok", "fail" or "throw");
-- still_missing: whether Polish is still missing when Download is tapped.
local function offerPolish(online, install, still_missing)
    local manager = setup()
    manager.queued = {}
    local forgotten, downloads = {}, 0
    manager.language_controller.forgetMissing = function(_, ids)
        for _, id in ipairs(ids) do forgotten[#forgotten + 1] = id end
    end
    manager.language_controller.missingLanguages = function()
        return still_missing == false and {} or { package("pl", "Polish") }
    end
    manager._downloadAndInstall = function()
        downloads = downloads + 1
        if install == "throw" then error("disk full") end
        return install == "ok", install ~= "ok" and "HTTP 404" or nil
    end
    network.runWhenOnline = function(_, callback)
        if online then callback() end
    end
    manager:offerDownloads("/plugin", { package("pl", "Polish") })
    return manager, forgotten, function() return downloads end
end

it("downloading an offered language leaves it enabled", function()
    local manager, forgotten = offerPolish(true, "ok")
    T.truthy(shown[1].text:find("Polish is enabled"))
    shown[1].ok_callback()
    T.eq(#forgotten, 0)
    T.truthy(shown[#shown].text:find("Installed dictionary: Polish"))
    T.eq(manager:isQueued("pl"), false)
end)

it("an offered language that fails to install is forgotten", function()
    local _, forgotten = offerPolish(true, "fail")
    shown[1].ok_callback()
    T.eq(forgotten[1], "pl")
    T.truthy(shown[#shown].text:find("HTTP 404"))
end)

it("a download that throws is reported, not left running", function()
    local manager, forgotten = offerPolish(true, "throw")
    shown[1].ok_callback()
    T.eq(forgotten[1], "pl")
    T.truthy(shown[#shown].text:find("disk full"))
    T.eq(manager:isQueued("pl"), false)
end)

it("doesn't download an offered language that has installed meanwhile",
        function()
    local _, _, downloads = offerPolish(true, "ok", false)
    shown[1].ok_callback()
    T.eq(downloads(), 0)
end)

it("declining the offer forgets the language", function()
    local _, forgotten = offerPolish(true, "ok")
    shown[1].cancel_callback()
    T.eq(forgotten[1], "pl")
end)

it("declining Wi-Fi leaves the language queued and nothing on screen",
        function()
    local manager = offerPolish(false, "ok")
    shown[1].ok_callback()
    T.eq(#shown, 1, "no download message")
    T.eq(manager:isQueued("pl"), true)
end)

it("keeps the menu when Wi-Fi is declined, and shows it from the shipped "
        .. "catalog at first", function()
    local manager = setup()
    local menus, closed = 0, 0
    manager.showMenu = function() menus = menus + 1 end
    manager._closeMenu = function() closed = closed + 1 end
    network.runWhenOnline = function() end
    manager.catalog = nil
    manager.catalog_path = nil
    manager.plugin_dir = catalogFile("shipped3", { package("pl", "Polish") })
    manager:open(nil, manager.plugin_dir)
    T.eq(menus, 1, "the menu shows at once")
    T.eq(manager.catalog.shipped, true)
    manager:_download(package("pl", "Polish"))
    T.eq(closed, 0, "nothing closes before the download starts")
end)
