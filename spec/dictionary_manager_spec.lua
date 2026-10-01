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
