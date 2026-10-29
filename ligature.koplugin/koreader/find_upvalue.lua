-- Finds a local that a KOReader function captured, to reach classes
-- KOReader does not export (VirtualKey, Contact, VirtualKeyPopup).
--
-- Another plugin may have wrapped the function before Ligature loads, and
-- the wrapper captures the original rather than its locals: Appearance
-- before 1.9.0 wrapped VirtualKeyboard.addKeys, and Ligature then failed to
-- load. So the functions it captured are searched too, MAX_DEPTH levels
-- down, after its own locals.
local MAX_DEPTH = 2

local function find(fn, wanted, depth, seen)
    local captured = {}
    for index = 1, 255 do
        local name, value = debug.getupvalue(fn, index)
        if not name then
            break
        end
        if name == wanted then
            return value
        end
        -- Marked as it is queued, so a function two wrappers share is
        -- searched once; only queued where the search goes on, so one
        -- seen first too deep to search is still searched by a nearer way.
        if depth < MAX_DEPTH and type(value) == "function"
                and not seen[value] then
            seen[value] = true
            captured[#captured + 1] = value
        end
    end
    for _, inner in ipairs(captured) do
        local value = find(inner, wanted, depth + 1, seen)
        if value ~= nil then
            return value
        end
    end
end

return function(fn, wanted)
    if type(fn) ~= "function" then
        return
    end
    return find(fn, wanted, 0, { [fn] = true })
end
