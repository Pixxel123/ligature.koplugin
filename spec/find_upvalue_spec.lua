local T = require("helper")
local it = T.it

local findUpvalue = T.load("find_upvalue")

-- A KOReader-style function that reaches a class through a local.
local function newAddKeys()
    local VirtualKey = { name = "VirtualKey" }
    return function()
        return VirtualKey
    end, VirtualKey
end

local function wrap(fn)
    local original = fn
    return function(...)
        return original(...)
    end
end

it("finds a local the function captured", function()
    local addKeys, VirtualKey = newAddKeys()
    T.eq(findUpvalue(addKeys, "VirtualKey"), VirtualKey)
    T.eq(findUpvalue(addKeys, "Missing"), nil)
end)

it("finds it through another plugin's wrappers", function()
    local addKeys, VirtualKey = newAddKeys()
    T.eq(findUpvalue(wrap(addKeys), "VirtualKey"), VirtualKey)
    T.eq(findUpvalue(wrap(wrap(addKeys)), "VirtualKey"), VirtualKey)
    T.eq(findUpvalue(wrap(wrap(wrap(addKeys))), "VirtualKey"), nil,
        "no deeper than two wrappers")
end)

it("takes the function's own local before a wrapped one", function()
    local addKeys = newAddKeys()
    local VirtualKey = { name = "own" }
    local original = addKeys
    local wrapper = function()
        return VirtualKey, original()
    end
    T.eq(findUpvalue(wrapper, "VirtualKey"), VirtualKey)
end)

it("stops on functions that capture each other", function()
    local first, second
    first = function() return second() end
    second = function() return first() end
    T.eq(findUpvalue(first, "VirtualKey"), nil)
    T.eq(findUpvalue(nil, "VirtualKey"), nil)
end)

it("finds it by a nearer way after seeing it too deep", function()
    local addKeys, VirtualKey = newAddKeys()
    -- deep reaches addKeys three functions down, too deep to search it;
    -- near reaches it two down.
    local deep = wrap(wrap(addKeys))
    local near = wrap(addKeys)
    local root = function()
        return deep(), near()
    end
    T.eq(findUpvalue(root, "VirtualKey"), VirtualKey)
end)
