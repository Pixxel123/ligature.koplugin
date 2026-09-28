local T = require("helper")
local it = T.it

local scoring = T.load("scoring"):new(T.normalization)

local function align(candidate, trace, missing_cost)
    local trace_chars = scoring:buildNextPositions(trace)
    return scoring:dynamicMatchScore(candidate, trace_chars, false, nil,
        nil, nil, nil, false, nil, missing_cost)
end

it("skips a word's inner letters the swipe never crossed", function()
    local score, _, matched, missing = align("abcd", "ad", 2)
    T.eq(score, 4)
    T.eq(missing, 2)
    T.eq(matched[1], 1)
    T.eq(matched[2], nil)
    T.eq(matched[3], nil)
    T.eq(matched[4], 2)
end)

it("keeps the wall without a cost", function()
    T.truthy(align("abcd", "ad") >= 1000)
end)

it("scores a fully crossed word the same either way", function()
    T.eq(align("abcd", "axbcyd", 2), align("abcd", "axbcyd"))
    local _, _, _, missing = align("abcd", "axbcyd", 2)
    T.eq(missing, 0)
end)

it("never skips the first or last letter", function()
    T.truthy(align("abcd", "bcd", 2) >= 1000, "first")
    T.truthy(align("abcd", "abc", 2) >= 1000, "last")
end)

it("uses the move only where the plain alignment fails", function()
    local trace = "abgh"
    local trace_chars = scoring:buildNextPositions(trace)
    local far = { word = "abcdefgh", signature = "abcdefgh", freq = 3000 }
    local plain = scoring:scoreEntryDynamic(trace, far, trace_chars, nil,
        nil, false, 0, false, nil, 0)
    local missing = scoring:scoreEntryDynamic(trace, far, trace_chars, nil,
        nil, false, 0, false, nil, 0, 2)
    T.truthy(plain >= 1000, "wall without the move")
    T.truthy(missing < 1000, "four letters missing, finite")
    local near = { word = "abgh", signature = "abgh", freq = 3000 }
    T.eq(scoring:scoreEntryDynamic(trace, near, trace_chars, nil, nil,
        false, 0, false, nil, 0, 2),
        scoring:scoreEntryDynamic(trace, near, trace_chars, nil, nil,
        false, 0, false, nil, 0))
end)

it("tells beforehand when the plain alignment must fail", function()
    -- Six keys in a row, 100 apart: each lends its neighbours.
    local centers = {}
    for index, letter in ipairs({ "a", "b", "c", "d", "e", "f" }) do
        centers[string.byte(letter)] = { x = index * 100, y = 50,
            size = 100 }
    end
    math.randomseed(7)
    local function word(length)
        local letters = {}
        for index = 1, length do
            letters[index] = string.char(96 + math.random(6))
        end
        return table.concat(letters)
    end
    local said_no = 0
    for _ = 1, 3000 do
        local trace = word(math.random(1, 9))
        local candidate = word(math.random(1, 7))
        local trace_chars = scoring:buildNextPositions(trace)
        local near = math.random(2) == 1
            and scoring:buildNearPositions(trace_chars, centers) or nil
        local ends = math.random(2) == 1
        local start = math.random(2) == 1
        local may = scoring:_mayAlign(candidate, trace_chars, ends, start,
            near)
        local score = scoring:dynamicMatchScore(candidate, trace_chars, ends,
            nil, nil, nil, nil, start, near)
        T.eq(may, score < 1000, candidate .. " in " .. trace)
        if not may then
            said_no = said_no + 1
        end
    end
    T.truthy(said_no > 100, "some words cannot align")
end)
