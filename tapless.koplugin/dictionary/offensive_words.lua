-- Offensive words, one list per language, ranked below the words a swipe
-- could equally be. They are not hidden: the lists are other people's,
-- written for filtering chat, and hold words with innocent uses a reader
-- may want ("dick", "bastard"). A listed word still comes first when its
-- swipe fits it clearly best, and once the user has kept it KNOWN_USES
-- times it is ranked like any other word.
--
-- The lists live in dictionary/offensive/<language>.txt, one word a line,
-- lower case as the dictionaries spell them, "#" lines comments (see
-- tools/build_offensive_lists.py). A regional dictionary ("pt-br") uses its
-- language's list ("pt") when it has none of its own; a language with no
-- list is left alone.
local OffensiveWords = {
    -- What a listed word loses in the ranking, in frequency units (Zipf
    -- x 1000): as if it were this much rarer. Replaying the recorded
    -- one-handed sessions, 3500 left no listed word first where 2000 left
    -- two, and one in the suggestions 2 times where there had been 18;
    -- 8000 left none there, but made more listed words on the clean sets
    -- need a precise swipe (6 against 4 or 5 a set).
    PENALTY = 3500,
    -- Kept this often (see UsageModel), a listed word is the user's own.
    KNOWN_USES = 2,
}
OffensiveWords.__index = OffensiveWords

-- dir: the folder of lists; enabled(): whether to rank them down at all.
function OffensiveWords:new(dir, enabled)
    return setmetatable({
        dir = assert(dir),
        enabled = enabled or function() return true end,
        lists = {},
    }, self)
end

function OffensiveWords:_read(language)
    local words
    local file = io.open(self.dir .. "/" .. language .. ".txt", "rb")
    if file then
        words = {}
        for line in file:lines() do
            local word = line:gsub("\r$", ""):match("^%s*(.-)%s*$")
            if word ~= "" and word:sub(1, 1) ~= "#" then
                words[word] = true
            end
        end
        file:close()
    end
    return words
end

-- The list for a dictionary, false when there is none.
function OffensiveWords:_list(dictionary)
    local list = self.lists[dictionary]
    if list == nil then
        list = self:_read(dictionary)
        local base = dictionary:match("^(%a+)[-_]")
        if not list and base then
            list = self:_read(base)
        end
        list = list or false
        self.lists[dictionary] = list
    end
    return list
end

-- What word loses in the ranking in dictionary, having been kept uses
-- times: PENALTY for a listed word, else 0. Called for every word a swipe
-- is compared with, so it is one lookup once the list is read.
function OffensiveWords:penalty(dictionary, word, uses)
    if not dictionary or not word then
        return 0
    end
    local list = self:_list(dictionary)
    if not list or not list[word] or (uses or 0) >= self.KNOWN_USES
            or not self.enabled() then
        return 0
    end
    return self.PENALTY
end

return OffensiveWords
