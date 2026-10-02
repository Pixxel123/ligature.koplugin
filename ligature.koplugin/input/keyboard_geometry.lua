local KeyboardGeometry = {
    -- How far past a key's edge a swipe may start and still be taken as
    -- aimed at that key, as a fraction of the key's width or height.
    START_REACH = 0.25,
}
KeyboardGeometry.__index = KeyboardGeometry

function KeyboardGeometry:new(normalization)
    return setmetatable({
        normalization = assert(normalization),
    }, self)
end

-- Whether pos lies in dimen, edges included, as KOReader's Geom:contains
-- judges it. Trace points carry no size, and Geom:contains would fail on
-- them, so a point without one counts as zero-sized.
local function containsPoint(dimen, pos)
    return dimen.x <= pos.x and dimen.y <= pos.y
        and dimen.x + dimen.w >= pos.x + (pos.w or 0)
        and dimen.y + dimen.h >= pos.y + (pos.h or 0)
end

-- The letter key types, normalized; nil for any other key.
function KeyboardGeometry:_letterOf(key, profile)
    local normalized = self.normalization:normalizeText(
        key.key or key.label, profile)
    return #normalized == 1 and normalized or nil
end

function KeyboardGeometry:keyAt(layout, pos, profile)
    if not pos or not layout then
        return
    end
    for _, row in ipairs(layout) do
        for _, key in ipairs(row) do
            if key.dimen and containsPoint(key.dimen, pos) then
                if key.is_swype_candidate then
                    return
                end
                return self:_letterOf(key, profile), key
            end
        end
    end
end

-- A number key, or the shift layer's symbol on the same key, which has the
-- digit as its alternate label.
local function isNumberKey(key)
    return not key.is_swype_candidate
        and ((type(key.key) == "string" and key.key:match("^%d$") ~= nil)
            or (type(key.alt_label) == "string"
                and key.alt_label:match("^%d$") ~= nil))
end

-- The key a swipe started on. A finger aiming at a key on the top letter
-- row often lands just above it, on the number row, so a start on a number
-- key counts as a start on the letter key straight below it. A number key
-- with no letter below it stays a number key.
function KeyboardGeometry:startKeyAt(layout, pos, profile)
    local letter, key = self:keyAt(layout, pos, profile)
    if letter or not key or not isNumberKey(key) then
        return letter, key
    end
    local bottom = key.dimen.y + key.dimen.h
    local below
    for _, row in ipairs(layout) do
        for _, candidate in ipairs(row) do
            local dimen = candidate.dimen
            if dimen and not candidate.is_swype_candidate
                    and dimen.y >= bottom
                    and pos.x >= dimen.x and pos.x <= dimen.x + dimen.w
                    and (not below or dimen.y < below.dimen.y) then
                below = candidate
            end
        end
    end
    local letter_below = below and self:_letterOf(below, profile)
    if letter_below then
        return letter_below, below
    end
    return letter, key
end

-- Distance from pos to the nearest point of a key, in key widths across
-- and key heights down.
local function gapTo(dimen, pos)
    local dx = math.max(dimen.x - pos.x, 0, pos.x - (dimen.x + dimen.w))
    local dy = math.max(dimen.y - pos.y, 0, pos.y - (dimen.y + dimen.h))
    dx = dx / math.max(1, dimen.w)
    dy = dy / math.max(1, dimen.h)
    return math.sqrt(dx * dx + dy * dy)
end

-- exact_last first, then the letters of the two keys nearest pos. With
-- reach, only keys less than that fraction of a key away from pos count.
function KeyboardGeometry:endpointLetters(layout, pos, exact_last, profile,
        reach)
    local candidates = {}
    local seen = {}
    if exact_last and #exact_last == 1 then
        table.insert(candidates, exact_last)
        seen[exact_last] = true
    end
    if not pos or not layout then
        return candidates
    end
    local nearby = {}
    for _, row in ipairs(layout) do
        for _, key in ipairs(row) do
            if key.dimen and not key.is_swype_candidate
                    and (not reach
                        or gapTo(key.dimen, pos) < reach) then
                local normalized = self:_letterOf(key, profile)
                if normalized and not seen[normalized] then
                    local center_x = key.dimen.x + key.dimen.w / 2
                    local center_y = key.dimen.y + key.dimen.h / 2
                    local dx = pos.x - center_x
                    local dy = pos.y - center_y
                    table.insert(nearby, {
                        letter = normalized,
                        distance = dx * dx + dy * dy,
                    })
                end
            end
        end
    end
    table.sort(nearby, function(left, right)
        return left.distance < right.distance
    end)
    for index = 1, math.min(2, #nearby) do
        table.insert(candidates, nearby[index].letter)
    end
    return candidates
end

-- The key a swipe started on, then any neighbouring key it started close to.
function KeyboardGeometry:startLetters(layout, pos, exact_first, profile)
    return self:endpointLetters(layout, pos, exact_first, profile,
        self.START_REACH)
end

-- Each letter's key, as the letter it types (normalized) to its centre
-- and size: { x, y, w, h, others }. A key labelled with the letter itself
-- counts over an accented key that normalizes to it, wherever that is:
-- Czech has ě on the number row above e, Spanish ñ above n, Danish å
-- above a, Turkish ı and ğ above i and g. Otherwise the first key typing
-- a letter counts. others lists the letter's other keys, the same way,
-- or is nil: a swipe through å is as good as one through a.
function KeyboardGeometry:letterKeys(layout, profile)
    local keys = {}
    if not layout then
        return keys
    end
    -- Every key typing each letter, in layout order, and the first of
    -- them labelled with the letter itself.
    local places = {}
    local own_index = {}
    for _, row in ipairs(layout) do
        for _, key in ipairs(row) do
            if key.dimen and not key.is_swype_candidate then
                local normalized = self:_letterOf(key, profile)
                if normalized then
                    local list = places[normalized] or {}
                    places[normalized] = list
                    list[#list + 1] = {
                        x = key.dimen.x + key.dimen.w / 2,
                        y = key.dimen.y + key.dimen.h / 2,
                        w = key.dimen.w,
                        h = key.dimen.h,
                    }
                    local label = key.key or key.label
                    if not own_index[normalized] and type(label) == "string"
                            and label:lower() == normalized then
                        own_index[normalized] = #list
                    end
                end
            end
        end
    end
    for letter, list in pairs(places) do
        local primary = table.remove(list, own_index[letter] or 1)
        primary.others = list[1] and list or nil
        keys[letter] = primary
    end
    return keys
end

local function center(key)
    return {
        x = key.x,
        y = key.y,
        size = math.max(key.w, key.h),
    }
end

-- Letter byte to key centre and size: { x, y, size, others }, others as in
-- letterKeys.
function KeyboardGeometry:keyCenters(layout, profile)
    local centers = {}
    for letter, key in pairs(self:letterKeys(layout, profile)) do
        local entry = center(key)
        if key.others then
            entry.others = {}
            for index, other in ipairs(key.others) do
                entry.others[index] = center(other)
            end
        end
        centers[string.byte(letter)] = entry
    end
    return centers
end

return KeyboardGeometry
