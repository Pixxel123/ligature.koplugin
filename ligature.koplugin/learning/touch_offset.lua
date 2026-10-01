-- Where the user's finger lands against the keys it means, learned from
-- the words they keep. A thumb reaching across a one-handed keyboard lands
-- short of the keys further away, so swipes start and end off the word's
-- first and last keys the same way again and again; later swipes are
-- shifted back to allow for it before their keys are read.
--
-- Offsets are in key widths (x) and heights (y), so they hold when the
-- keyboard is resized, and kept apart for the full-width keyboard and the
-- one-handed keyboard on either side, where the hand reaches differently
-- (see mode). They live in the settings as { [mode] = { x, y, words } }.
local TouchOffset = {
    -- The settings key the device keeps the offsets under.
    SETTING_KEY = "ligature_touch_offset",
    -- Words learned before any shift: a few words say little.
    MIN_WORDS = 8,
    -- The shift is this share of the learned offset. More than all of it:
    -- the kept words it learns from are the ones recognition chose, whose
    -- keys lie nearer where the finger landed than the words meant, so
    -- the offset learned is smaller than the true one (0.07 of a key
    -- against 0.12 on the recorded one-handed sessions). Replaying every
    -- recorded session in order, learning as the device does, 1.25 fixed
    -- 53 one-handed swipes and broke 15, and 32 and 15 full-width; 0.75
    -- fixed fewer (35, 14; 21, 7), 1.75 broke more (57, 27; 40, 24).
    STRENGTH = 1.25,
    -- The largest shift, in key sizes, whatever was learned.
    CAP = 0.4,
    -- A landing error beyond this, in key sizes, is taken as a swipe
    -- meant for other keys, or a word changed afterwards, and not learned.
    MAX_ERROR = 0.8,
    -- The first 1 / RATE words are averaged; after that each word moves
    -- the offset by RATE of its difference, so it follows a change of
    -- habit slowly and one odd swipe hardly at all.
    RATE = 0.05,
}
TouchOffset.__index = TouchOffset

function TouchOffset:new(settings, setting_key)
    return setmetatable({
        settings = assert(settings),
        setting_key = assert(setting_key),
    }, self)
end

function TouchOffset:_state()
    local state = self.settings:readSetting(self.setting_key)
    return type(state) == "table" and state or {}
end

-- The learned landing error for mode, in key sizes: x, y, and how many
-- words it was learned from (picks count twice).
function TouchOffset:offset(mode)
    local learned = self:_state()[mode]
    if type(learned) ~= "table" then
        return 0, 0, 0
    end
    return tonumber(learned.x) or 0, tonumber(learned.y) or 0,
        tonumber(learned.words) or 0
end

local function clamp(value, limit)
    return math.max(-limit, math.min(limit, value))
end

-- What to add to a swipe's points on mode's keyboard, in key sizes: none
-- until MIN_WORDS words are learned.
function TouchOffset:shift(mode)
    local x, y, words = self:offset(mode)
    if words < self.MIN_WORDS then
        return 0, 0
    end
    return clamp(-self.STRENGTH * x, self.CAP),
        clamp(-self.STRENGTH * y, self.CAP)
end

-- Learns one kept word's landing errors (a list of { x, y } in key
-- sizes: where its swipe started against its first key, and where it
-- lifted against its last) as weight words. False when none was close
-- enough to learn from.
function TouchOffset:learn(mode, errors, weight)
    local sum_x, sum_y, count = 0, 0, 0
    for _, err in ipairs(errors or {}) do
        if math.abs(err.x) <= self.MAX_ERROR
                and math.abs(err.y) <= self.MAX_ERROR then
            sum_x, sum_y, count = sum_x + err.x, sum_y + err.y, count + 1
        end
    end
    if count == 0 or not mode then
        return false
    end
    weight = weight or 1
    local x, y, words = self:offset(mode)
    words = words + weight
    local rate = math.min(0.5, weight / math.min(words, 1 / self.RATE))
    if words == weight then
        rate = 1
    end
    x = x + rate * (sum_x / count - x)
    y = y + rate * (sum_y / count - y)
    local state = self:_state()
    state[mode] = { x = x, y = y, words = words }
    self.settings:saveSetting(self.setting_key, state)
    return true
end

-- The landing errors of a kept word, from sample (a swipe's unshifted
-- first and last points, start and lift, and keys: each letter's key
-- centre and size, { x, y, w, h }) and letters, the word as the keys
-- spell it. A word of one letter teaches nothing.
function TouchOffset:errors(sample, letters)
    local errors = {}
    if not sample or not sample.keys or not letters or #letters < 2 then
        return errors
    end
    local function against(point, letter)
        local key = sample.keys[letter]
        if point and key and key.w and key.w > 0 and key.h and key.h > 0 then
            errors[#errors + 1] = { x = (point.x - key.x) / key.w,
                y = (point.y - key.y) / key.h }
        end
    end
    against(sample.start, letters:sub(1, 1))
    against(sample.lift, letters:sub(-1))
    return errors
end

-- Learns from sample and letters (see errors) as weight words.
function TouchOffset:learnSample(sample, letters, weight)
    if not sample then
        return false
    end
    return self:learn(sample.mode, self:errors(sample, letters), weight)
end

-- A shift in key sizes as pixels, at the median letter key's size in keys.
function TouchOffset:toPixels(dx, dy, keys)
    local widths, heights = {}, {}
    for _, key in pairs(keys or {}) do
        widths[#widths + 1] = key.w
        heights[#heights + 1] = key.h
    end
    if #widths == 0 then
        return 0, 0
    end
    table.sort(widths)
    table.sort(heights)
    local middle = math.floor((#widths + 1) / 2)
    return dx * widths[middle], dy * heights[middle]
end

-- What a swipe should be shifted by on mode's keyboard with keys (see
-- KeyboardGeometry:letterKeys), as { x, y } pixels; nil when nothing is
-- to be shifted.
function TouchOffset:pixelShift(mode, keys)
    local dx, dy = self:shift(mode)
    if dx == 0 and dy == 0 then
        return nil
    end
    local x, y = self:toPixels(dx, dy, keys)
    return { x = x, y = y }
end

-- The keyboard a swipe was made on, whose offset it learns and uses:
-- "full-width", or the one-handed keyboard on the side of the screen
-- (screen_width wide) its letter keys (keys) are on, as the other thumb
-- may be used there.
function TouchOffset.mode(one_handed, keys, screen_width)
    if not one_handed then
        return "full-width"
    end
    local left, right
    for _, key in pairs(keys or {}) do
        left = math.min(left or key.x, key.x)
        right = math.max(right or key.x, key.x)
    end
    if not left or not screen_width then
        return "one-handed right"
    end
    return (left + right) / 2 < screen_width / 2 and "one-handed left"
        or "one-handed right"
end

-- What a finished swipe teaches, once its word is kept: where it began
-- and lifted off (the first and last of points, where the finger went)
-- on mode's keyboard with keys. A swipe begun off the letter keys, on the
-- number row say, which counts as the letter below, says nothing about
-- where the finger lands on letters: its start is left out when
-- on_letter(point) says so. nil for a swipe of fewer than two points.
function TouchOffset.sample(mode, points, keys, on_letter)
    if not points or #points < 2 then
        return nil
    end
    local first, last = points[1], points[#points]
    local start = { x = first.x, y = first.y }
    if on_letter and not on_letter(start) then
        start = nil
    end
    return {
        mode = mode,
        start = start,
        lift = { x = last.x, y = last.y },
        keys = keys,
    }
end

return TouchOffset
