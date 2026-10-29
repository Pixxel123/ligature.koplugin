local T = require("helper")
local it = T.it

local Replay = dofile(T.plugin_dir .. "/../tools/replay.lua")
local CleanSwipes = dofile(T.plugin_dir .. "/../tools/clean_swipes.lua")
local ShapeChannel = T.load("shape_channel")
local PathShape = T.load("path_shape")

local store = Replay.loadPlugin(T.plugin_dir).engine.dictionary_store
local LONG = string.rep("x", 12) -- letters crossed: enough to trigger

-- A clean swipe of word, its vertical movement scaled by squash around
-- the middle row (1 leaves it as it is).
local function swipe(word, squash)
    local keys = CleanSwipes.defaultKeys()
    local attempt = CleanSwipes.attempt(word, keys)
    local centers, middle = {}, nil
    for _, key in ipairs(keys) do
        centers[string.byte(key.key)] = { x = key.x + key.w / 2,
            y = key.y + key.h / 2, size = math.max(key.w, key.h) }
        if key.key == "a" then middle = key.y + key.h / 2 end
    end
    local points = {}
    for _, event in ipairs(attempt.events) do
        points[#points + 1] = { x = event.pos[1],
            y = middle + (event.pos[2] - middle) * (squash or 1) }
    end
    return points, centers
end

local function channel(blocked)
    return ShapeChannel:new(store, PathShape:new(), nil, blocked)
end

local function words(found)
    local out = {}
    for index, item in ipairs(found) do out[index] = item.entry.word end
    return out
end

local function position(list, word)
    for index, item in ipairs(list) do
        if item == word then return index end
    end
end

-- The trimmed swipe's first and last touch points, as ShapeChannel itself
-- takes them from path_shape:swipe's resampled path.
local function ends(swiped)
    local samples = swiped.samples
    local last = #samples
    return { x = samples[1], y = samples[2] },
        { x = samples[last - 1], y = samples[last] }
end

it("finds a long word by the shape of its swipe", function()
    local points, centers = swipe("important")
    local found = words(channel():candidates{ signature = LONG,
        points = points, key_centers = centers })
    local at = position(found, "important")
    T.truthy(at and at <= 3, table.concat(found, ","))
end)

it("finds a short word by the shape of its swipe", function()
    -- A clean swipe of "help", with the letters a recorded swipe of it
    -- crossed: enough to run the channel, which now looks at words this
    -- short.
    local points, centers = swipe("help")
    local found = words(channel():candidates{ signature = "hgrerghjkop",
        points = points, key_centers = centers })
    local at = position(found, "help")
    T.truthy(at and at <= 3, table.concat(found, ","))
end)

it("does nothing for a swipe crossing few letters", function()
    local points, centers = swipe("important")
    T.eq(#channel():candidates{ signature = "imt", points = points,
        key_centers = centers }, 0)
end)

it("only offers words whose ends and length fit the swipe", function()
    local points, centers = swipe("important")
    local shapes = PathShape:new()
    local swiped = shapes:swipe(points)
    local ch = channel()
    local found = ch:candidates{ signature = LONG, points = points,
        key_centers = centers }
    T.truthy(#found > 0 and #found <= ch.KEEP)
    local function near(letter, point)
        local c = centers[string.byte(letter)]
        return math.sqrt((c.x - point.x) ^ 2 + (c.y - point.y) ^ 2)
            <= ch.REACH * c.size
    end
    local first_point, last_point = ends(swiped)
    for index, item in ipairs(found) do
        local signature = item.entry.gesture_signature
        T.truthy(near(signature:sub(1, 1), first_point), signature)
        T.truthy(near(signature:sub(-1), last_point), signature)
        local ratio = swiped.length / shapes:ideal(signature, centers).length
        T.truthy(ratio >= ch.MIN_RATIO and ratio <= ch.MAX_RATIO, signature)
        if index > 1 then
            T.truthy(found[index - 1].rank <= item.rank, "sorted")
        end
    end
end)

it("never offers a blocked word", function()
    local points, centers = swipe("important")
    local blocked = { contains = function(_, _, word)
        return word == "important"
    end }
    local found = words(channel(blocked):candidates{ signature = LONG,
        points = points, key_centers = centers })
    T.eq(position(found, "important"), nil)
end)

it("finds a long word swiped flat", function()
    local points, centers = swipe("important", 0.4)
    local found = words(channel():candidates{ signature = LONG,
        points = points, key_centers = centers })
    T.truthy(position(found, "important"), table.concat(found, ","))
end)

it("finds a long word past an untagged tail off the keyboard", function()
    local points, centers = swipe("important")
    -- Tag every point that landed on a letter key, as a real trace
    -- does; trimTrace only needs the first and last tagged point, but
    -- tagging them all matches a real trace's shape.
    for index, point in ipairs(points) do
        point.letter_index = index
    end
    -- Overshoot past the keyboard's edge before the finger lifts: no
    -- letter there, so the trace collector leaves these untagged.
    local last = points[#points]
    for step = 1, 5 do
        points[#points + 1] = { x = last.x + step * 60,
            y = last.y + step * 60 }
    end
    local found = words(channel():candidates{ signature = LONG,
        points = points, key_centers = centers })
    local at = position(found, "important")
    T.truthy(at and at <= 3, table.concat(found, ","))
end)

it("works its word lengths out again when the keys move", function()
    local points, centers = swipe("important")
    local ch = channel()
    local before = words(ch:candidates{ signature = LONG, points = points,
        key_centers = centers })
    -- The same swipe on a keyboard twice the size: words kept from the
    -- first layout would all be half as long as the swipe.
    local bigger, doubled = {}, {}
    for code, center in pairs(centers) do
        bigger[code] = { x = center.x * 2, y = center.y * 2,
            size = center.size * 2 }
    end
    for index, point in ipairs(points) do
        doubled[index] = { x = point.x * 2, y = point.y * 2 }
    end
    local after = words(ch:candidates{ signature = LONG, points = doubled,
        key_centers = bigger })
    T.eq(table.concat(after, ","), table.concat(before, ","))
end)

it("counts a letter as near a point on another key typing it", function()
    local ch = ShapeChannel:new({}, PathShape:new())
    local centers = {
        [string.byte("a")] = { x = 0, y = 200, size = 100,
            others = { { x = 1000, y = 0, size = 100 } } },
        [string.byte("p")] = { x = 900, y = 0, size = 100 },
    }
    T.eq(table.concat(ch:_lettersNear({ x = 1000, y = 0 }, centers), ","),
        "a,p", "on Danish å, next to p")
    T.eq(table.concat(ch:_lettersNear({ x = 0, y = 200 }, centers), ","), "a")
end)

it("takes each end's nearest letters first, at most MAX_END_LETTERS",
        function()
    local ch = ShapeChannel:new({}, PathShape:new())
    local centers = {}
    for index, letter in ipairs({ "q", "w", "e", "r", "t", "y" }) do
        centers[string.byte(letter)] = { x = index * 20, y = 0, size = 100 }
    end
    local letters, distances = ch:_lettersNear({ x = 60, y = 0 }, centers)
    T.eq(table.concat(letters, ","), "e,r,w,q,t")
    T.eq(distances.e, 0)
    ch.MAX_END_LETTERS = 2
    T.eq(table.concat(ch:_lettersNear({ x = 110, y = 0 }, centers), ","),
        "t,y", "a tie goes alphabetically")
end)

-- The real store, recording the word lists read, with a clock that moves
-- on step microseconds each time it is read.
local function recordingStore(step)
    local clock = 0
    local recording = { read = {}, time = {
        now = function()
            clock = clock + (step or 0)
            return clock
        end,
        ms = function(n) return n * 1000 end,
    } }
    function recording:loadBucket(first, last, dictionary)
        self.read[#self.read + 1] = first .. last
        return store:loadBucket(first, last, dictionary)
    end
    return recording
end

it("reads the nearest letter pair first and stops at its limits",
        function()
    local points, centers = swipe("important")
    local options = { signature = LONG, points = points,
        key_centers = centers }
    local all = recordingStore()
    local before = words(ShapeChannel:new(all, PathShape:new())
        :candidates(options))
    T.eq(all.read[1], "it", "the swipe's own ends")
    T.truthy(#all.read >= 6, table.concat(all.read, ","))

    local few = recordingStore()
    local limited = ShapeChannel:new(few, PathShape:new())
    limited.MAX_ENTRIES = 1
    local found = words(limited:candidates(options))
    T.eq(table.concat(few.read, ","), "it", "only the nearest pair")
    T.eq(found[1], before[1])

    local slow = recordingStore(10000)
    ShapeChannel:new(slow, PathShape:new()):candidates(options)
    -- The clock is read when the nearest pair is done and before each
    -- pair after it: 10, 20, 30 and 40 ms on, then 50, which stops it.
    T.eq(#slow.read, 5, table.concat(slow.read, ","))
end)
