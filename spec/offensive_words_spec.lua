local T = require("helper")
local it = T.it

local OffensiveWords = T.load("offensive_words")

-- A folder of lists: en with two words, pt with one, written to a
-- temporary directory.
local function newLists(enabled)
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p " .. dir)
    local function write(language, text)
        local file = assert(io.open(dir .. "/" .. language .. ".txt", "w"))
        file:write(text)
        file:close()
    end
    write("en", "# a comment\nfoo\nbarbaz\n\n")
    write("pt", "porra\n")
    return OffensiveWords:new(dir, function() return enabled ~= false end),
        dir
end

it("penalizes a listed word, and no other", function()
    local words = newLists()
    T.eq(words:penalty("en", "foo", 0), words.PENALTY)
    T.eq(words:penalty("en", "barbaz", 0), words.PENALTY)
    T.eq(words:penalty("en", "food", 0), 0)
    T.eq(words:penalty("en", "# a comment", 0), 0, "comments are no words")
end)

it("finds a regional dictionary's list under its language", function()
    local words = newLists()
    T.eq(words:penalty("pt-br", "porra", 0), words.PENALTY)
    T.eq(words:penalty("pt", "porra", 0), words.PENALTY)
    T.eq(words:penalty("en", "porra", 0), 0)
end)

it("leaves alone a language with no list", function()
    local words = newLists()
    T.eq(words:penalty("xx", "foo", 0), 0)
    T.eq(words:penalty(nil, "foo", 0), 0)
end)

it("stops penalizing a listed word the user keeps using", function()
    local words = newLists()
    T.eq(words:penalty("en", "foo", words.KNOWN_USES - 1), words.PENALTY)
    T.eq(words:penalty("en", "foo", words.KNOWN_USES), 0)
end)

it("penalizes nothing when switched off", function()
    local words = newLists(false)
    T.eq(words:penalty("en", "foo", 0), 0)
end)
