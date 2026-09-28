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
    -- Six keys in a row, 100 apart: whether a trace position lends
    -- its neighbours is drawn at random too, so both branches of
    -- _lendsNeighbours run (a shallow turn that does not lend, and a
    -- sharp one, either way, that does).
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
    local function observationsFor(length)
        local observations = {}
        for position = 1, length do
            if math.random(2) == 1 then
                observations[position] = { signed_turn = 0.1 }
            else
                observations[position] = { signed_turn =
                    math.random(2) == 1 and 0.5 or -0.5 }
            end
        end
        return observations
    end
    local said_no = 0
    for _ = 1, 3000 do
        local trace = word(math.random(1, 9))
        local candidate = word(math.random(1, 7))
        local trace_chars = scoring:buildNextPositions(trace)
        local observations = observationsFor(#trace)
        local near = math.random(2) == 1
            and scoring:buildNearPositions(trace_chars, centers,
                observations) or nil
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

it("scores a word matched partly by a near key and partly by a skip",
        function()
    -- Six keys in a row, 100 apart: each is a neighbour of the one
    -- next to it only.
    local centers = {}
    for index, letter in ipairs({ "a", "b", "c", "d", "e", "f" }) do
        centers[string.byte(letter)] = { x = index * 100, y = 50,
            size = 100 }
    end
    -- Candidate "adzf" against trace "acf": a matches a; d has no key
    -- of its own in the trace, so it borrows the c the path did
    -- cross (a near key, used 1); z is not a key on this board at
    -- all, so the only way past it is a missing-letter skip; f
    -- matches f.
    local trace = "acf"
    local trace_chars = scoring:buildNextPositions(trace)
    local near = scoring:buildNearPositions(trace_chars, centers)
    local score, _, matched, missing = scoring:dynamicMatchScore(
        "adzf", trace_chars, false, nil, nil, nil, nil, false, near, 2)
    -- By dynamicMatchScore's costs: a exact (0) + d from near key c
    -- (NEAR_KEY_COST 0.5) + z missing (missing_cost 2) + f exact (0)
    -- = 2.5. The alignment that instead leaves both d and z missing
    -- and skips c outright costs more: d missing (2) + skipped c (1,
    -- its intent weight) + z missing (2) = 5, so the near key wins.
    T.eq(score, 2.5)
    T.eq(missing, 1)
    T.eq(matched[1], 1)
    T.eq(matched[2], 2)
    T.eq(matched[3], nil)
    T.eq(matched[4], 3)
end)
