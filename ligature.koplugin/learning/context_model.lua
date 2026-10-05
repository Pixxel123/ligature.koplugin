local ContextModel = {
    -- The setting the learned pairs are saved under, kept apart by
    -- language: { en = { the = { cat = 2 } } }.
    SETTING_KEY = "ligature_word_pairs",
    -- The most a word earns for following the previous word, from learned
    -- pairs and the dictionary's word-pair table together.
    MAX_BONUS = 3600,
    -- The most words followed by another kept for one previous word, and
    -- the most previous words kept for each language.
    MAX_FOLLOWERS = 24,
    MAX_PREVIOUS = 2000,
}
ContextModel.__index = ContextModel

-- Pairs learned or asked for with no language are English, the keyboard's
-- own default.
local DEFAULT_LANGUAGE = "en"

function ContextModel:new(settings, setting_key)
    return setmetatable({
        settings = assert(settings),
        setting_key = assert(setting_key),
        counts = nil,
        sizes = {},
        dirty = false,
    }, self)
end

function ContextModel:_allCounts()
    if not self.counts then
        local counts = self.settings:readSetting(self.setting_key, {})
        self.counts = type(counts) == "table" and counts or {}
    end
    return self.counts
end

-- The pairs learned in language, made empty if there are none yet.
function ContextModel:getCounts(language)
    language = language or DEFAULT_LANGUAGE
    local all = self:_allCounts()
    local counts = all[language]
    if type(counts) ~= "table" then
        counts = {}
        all[language] = counts
    end
    if not self.sizes[language] then
        local size = 0
        for _ in pairs(counts) do
            size = size + 1
        end
        self.sizes[language] = size
    end
    return counts
end

-- What word earns for following previous_word in language: the learned
-- pair's bonus plus pair_bonus, the word-pair table's, capped together.
function ContextModel:bonus(previous_word, word, pair_bonus, language)
    local learned = 0
    local counts = self:_allCounts()[language or DEFAULT_LANGUAGE]
    if previous_word and word and type(counts) == "table" then
        local previous_counts = counts[previous_word]
        local count = previous_counts and previous_counts[word] or 0
        if count > 0 then
            learned = math.floor(600 * math.log(count + 1) / math.log(2))
        end
    end
    return math.min(self.MAX_BONUS, learned + (pair_bonus or 0))
end

local function total(followers)
    local sum = 0
    for _, count in pairs(followers) do
        sum = sum + count
    end
    return sum
end

function ContextModel:learn(previous_word, word, language)
    if not previous_word or not word or #previous_word == 0 or #word == 0 then
        return
    end
    language = language or DEFAULT_LANGUAGE
    local counts = self:getCounts(language)
    if not counts[previous_word] then
        counts[previous_word] = {}
        self.sizes[language] = self.sizes[language] + 1
    end
    local previous_counts = counts[previous_word]
    previous_counts[word] = math.min(255, (previous_counts[word] or 0) + 1)

    local entries = 0
    for _ in pairs(previous_counts) do
        entries = entries + 1
    end
    if entries > self.MAX_FOLLOWERS then
        local least_word
        local least_count
        for candidate_word, candidate_count in pairs(previous_counts) do
            if not least_count or candidate_count < least_count then
                least_word = candidate_word
                least_count = candidate_count
            end
        end
        if least_word and least_word ~= word then
            previous_counts[least_word] = nil
        end
    end
    -- Too many previous words: the one followed least often goes.
    if self.sizes[language] > self.MAX_PREVIOUS then
        local least_previous
        local least_total
        for candidate, followers in pairs(counts) do
            if candidate ~= previous_word then
                local candidate_total = total(followers)
                if not least_total or candidate_total < least_total then
                    least_previous = candidate
                    least_total = candidate_total
                end
            end
        end
        if least_previous then
            counts[least_previous] = nil
            self.sizes[language] = self.sizes[language] - 1
        end
    end
    self.dirty = true
end

function ContextModel:commit(pending)
    if not pending or pending.context_committed then
        return
    end
    self:learn(pending.previous_word, pending.word, pending.language)
    pending.context_committed = true
end

function ContextModel:save()
    if self.dirty and self.counts then
        self.settings:saveSetting(self.setting_key, self.counts)
        self.dirty = false
    end
end

return ContextModel
