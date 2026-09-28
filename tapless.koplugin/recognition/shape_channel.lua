-- Words a long swipe could be, by the shape of its whole path. Fingers
-- flatten long words, so their swipes often miss letters the word needs;
-- the shape still shows. Candidates are words whose first and last keys
-- lie near the swipe's ends and whose ideal path is about as long as the
-- swipe, ranked by how closely the paths match, and by frequency.
local ShapeChannel = {
    -- Letters a swipe must cross for the channel to run. Recorded long
    -- words gained as much from 8 to 16, and 8 also fixed the most
    -- shorter words; long swipes cross far more letters, so it costs them
    -- no more time.
    TRIGGER_LETTERS = 8,
    -- The shortest word looked at.
    MIN_LETTERS = 6,
    -- How far a word's first or last key may be from the swipe's ends, in
    -- key sizes.
    REACH = 1.0,
    -- The swipe's length over the word's ideal path length.
    MIN_RATIO = 0.7,
    MAX_RATIO = 1.4,
    -- How many candidates are handed on. 20 put the same words first on
    -- the recorded sessions but took about 1.5 ms more per long swipe on
    -- a PC, over the device's budget.
    KEEP = 10,
    -- rank = SHAPE_WEIGHT * shape score - frequency, lower is better; also
    -- the shape weight of the merged ranking on long swipes. Replaying the
    -- recorded sessions, it fixed more long words than the lower weights
    -- fitted to their long swipes (4243, and 3620 between that and the
    -- reranker's 3089).
    SHAPE_WEIGHT = 6000,
}
ShapeChannel.__index = ShapeChannel

local WEAK_KEYS = { __mode = "k" }

function ShapeChannel:new(dictionary_store, path_shape, personal_dictionary,
        blocked_words)
    return setmetatable({
        dictionary_store = assert(dictionary_store),
        path_shape = assert(path_shape),
        personal_dictionary = personal_dictionary,
        blocked_words = blocked_words,
        -- Each word list's path lengths (see _paths), for the layout
        -- paths_layout; a list dropped from memory drops its own.
        paths = setmetatable({}, WEAK_KEYS),
        paths_layout = nil,
        -- Reused for each word's resampled path: most are compared once
        -- and never again, so keeping a table for each is only garbage.
        samples = {},
    }, self)
end

-- Whether a swipe crossing these letters is long enough for the channel.
function ShapeChannel:triggered(signature)
    return #(signature or "") >= self.TRIGGER_LETTERS
end

-- The letters whose key centre lies within REACH key sizes of point.
function ShapeChannel:_lettersNear(point, key_centers)
    local letters = {}
    for code = string.byte("a"), string.byte("z") do
        local center = key_centers[code]
        if center then
            local dx = center.x - point.x
            local dy = center.y - point.y
            if math.sqrt(dx * dx + dy * dy)
                    <= self.REACH * math.max(1, center.size or 1) then
                letters[#letters + 1] = string.char(code)
            end
        end
    end
    return letters
end

-- The trimmed swipe's first and last touch points. PathShape.resample
-- keeps a path's own endpoints exactly, and path_shape:swipe trims to
-- the first and last letters the trace crossed, so these are where the
-- swipe's first and last letters were, not wherever the raw trace ends:
-- overshoot past the keyboard or a settle before lift is not part of
-- the word, so it must not move the bucket lookup.
local function swipeEnds(swipe)
    local samples = swipe.samples
    local last = #samples
    return { x = samples[1], y = samples[2] },
        { x = samples[last - 1], y = samples[last] }
end

-- The ideal path length and average key size of each of entries' words,
-- as two arrays in the same order, worked out once for the layout in use
-- and kept with the list: nearly every word the channel looks at is cut
-- by its length alone, and working that out afresh on every swipe cost
-- more on the device than all the rest of the channel. A length of -1
-- marks a word too short to look at, 0 one with a letter off the
-- keyboard.
function ShapeChannel:_paths(entries, key_centers)
    local paths = self.paths[entries]
    if paths and paths.count == #entries
            and paths.min_letters == self.MIN_LETTERS then
        return paths
    end
    local lengths, scales = {}, {}
    for index, entry in ipairs(entries) do
        local signature = entry.gesture_signature or entry.signature
        local length, scale = -1, 0
        if entry.word and signature
                and #(entry.signature or signature) >= self.MIN_LETTERS then
            length, scale = self.path_shape.measure(signature, key_centers)
            if not length then
                length, scale = 0, 0
            end
        end
        lengths[index], scales[index] = length, scale
    end
    paths = { count = #entries, min_letters = self.MIN_LETTERS,
        lengths = lengths, scales = scales }
    self.paths[entries] = paths
    return paths
end

-- Inserts item into found, kept sorted by rank and at most limit long.
local function keep(found, item, limit)
    local position = #found + 1
    while position > 1 and found[position - 1].rank > item.rank do
        position = position - 1
    end
    if position > limit then
        return
    end
    table.insert(found, position, item)
    if #found > limit then
        found[#found] = nil
    end
end

-- options: signature (the letters crossed), points (the swipe's touch
-- points), key_centers, dictionary, data_language, normalization_profile.
-- Returns up to KEEP { entry, shape, rank }, best first; nothing unless
-- triggered.
function ShapeChannel:candidates(options)
    local points = options.points
    if not self:triggered(options.signature) or not points
            or #points < 2 then
        return {}
    end
    local path_shape = self.path_shape
    local swipe = path_shape:swipe(points)
    if not swipe then
        return {}
    end
    local key_centers = options.key_centers or {}
    local layout = path_shape:useLayout(key_centers)
    if layout ~= self.paths_layout then
        self.paths = setmetatable({}, WEAK_KEYS)
        self.paths_layout = layout
    end
    local dictionary = options.dictionary or "en"
    local data_lang = options.data_language or dictionary
    local found, seen = {}, {}
    local limit = self.KEEP
    local sample_count = path_shape.SAMPLE_COUNT
    local max_score = path_shape.MAX_SCORE
    local a = swipe.samples
    local b = self.samples
    -- length and scale: the word's path, from _paths; length is -1 for a
    -- word too short to look at, which is left out before anything else.
    local function consider(entry, length, scale)
        local word = entry.word
        if seen[word]
                or (entry.lang and entry.lang ~= dictionary
                    and entry.lang ~= data_lang)
                or (self.blocked_words
                    and self.blocked_words:contains(dictionary, word)) then
            return
        end
        seen[word] = true
        if length <= 0 then
            return
        end
        local ratio = swipe.length / length
        if ratio < self.MIN_RATIO or ratio > self.MAX_RATIO then
            return
        end
        path_shape:resampleInto(entry.gesture_signature or entry.signature,
            length, b)
        local length_term = math.min(max_score,
            math.abs(swipe.length - length) / math.max(scale, length))
        local length_component = 0.15 * length_term
        local freq = entry.freq or 0

        -- Once found already holds limit items, a candidate whose rank
        -- can already not beat the current worst kept one is going to be
        -- discarded regardless of how the rest of its samples compare.
        -- partial, below, only grows sample by sample (every term added
        -- is a sqrt, so >= 0, and every step after that -- the *0.85,
        -- the + length_component, the min, the *SHAPE_WEIGHT, the -freq
        -- -- keeps that order under round-to-nearest), so the rank it
        -- implies is a lower bound on the final rank at every step, and
        -- at the last sample it equals rank exactly (mirrors the shape
        -- and rank below; change both together): the two are compared
        -- as ranks throughout, not converted to a score-space threshold
        -- first, so this is exact rather than only true on this data.
        local worst = #found >= limit and found[limit].rank or nil

        local total = 0
        for index = 1, 2 * sample_count, 2 do
            local dx = a[index] - b[index]
            local dy = a[index + 1] - b[index + 1]
            total = total + math.sqrt(dx * dx + dy * dy)
            if worst then
                local partial = math.min(max_score,
                    0.85 * (total / sample_count / scale)
                        + length_component)
                if self.SHAPE_WEIGHT * partial - freq >= worst then
                    -- Would not have survived keep() below either, so
                    -- stopping here changes nothing but the time spent.
                    return
                end
            end
        end
        local shape = math.min(max_score,
            (total / sample_count / scale) * 0.85 + length_component)
        local rank = self.SHAPE_WEIGHT * shape - freq
        if #found >= limit and rank >= found[limit].rank then
            -- keep() would reject this anyway; skip its table too.
            return
        end
        keep(found, { entry = entry, shape = shape, rank = rank }, limit)
    end
    local function scan(bucket)
        local entries = bucket and bucket.entries
        if not entries then
            return
        end
        local paths = self:_paths(entries, key_centers)
        local lengths, scales = paths.lengths, paths.scales
        for index = 1, #entries do
            local length = lengths[index]
            if length >= 0 then
                consider(entries[index], length, scales[index])
            end
        end
    end
    local first_point, last_point = swipeEnds(swipe)
    local lasts = self:_lettersNear(last_point, key_centers)
    for _, first in ipairs(self:_lettersNear(first_point, key_centers)) do
        for _, last in ipairs(lasts) do
            if self.personal_dictionary then
                scan(self.personal_dictionary:getBucket(first, last,
                    dictionary, options.normalization_profile))
            end
            scan(self.dictionary_store:loadBucket(first, last, dictionary))
        end
    end
    return found
end

return ShapeChannel
