local T = require("helper")
local it = T.it

local TouchOffset = T.load("touch_offset")

local function newSettings(values)
    local settings = { values = values or {}, saved = 0 }
    function settings:readSetting(key, default)
        if self.values[key] == nil then return default end
        return self.values[key]
    end
    function settings:saveSetting(key, value)
        self.values[key] = value
        self.saved = self.saved + 1
    end
    function settings:delSetting(key)
        self.values[key] = nil
    end
    return settings
end

local function newModel(values)
    local settings = newSettings(values)
    return TouchOffset:new(settings, "touch"), settings
end

local function near(actual, expected, message)
    T.truthy(math.abs(actual - expected) < 1e-9, (message or "value")
        .. ": expected " .. expected .. ", got " .. actual)
end

-- Learns words landing error (x, y) times, as a start and a lift error.
local function learnWords(model, mode, words, x, y)
    for _ = 1, words do
        model:learn(mode, { { x = x, y = y }, { x = x, y = y } }, 1)
    end
end

it("shifts nothing until enough words are learned", function()
    local model = newModel()
    learnWords(model, "one-handed", model.MIN_WORDS - 1, -0.2, 0)
    local dx, dy = model:shift("one-handed")
    T.eq(dx, 0)
    T.eq(dy, 0)
    learnWords(model, "one-handed", 1, -0.2, 0)
    dx, dy = model:shift("one-handed")
    near(dx, 0.2 * model.STRENGTH, "shift against the landing error")
    near(dy, 0)
end)

it("keeps each keyboard mode's offset apart", function()
    local model = newModel()
    learnWords(model, "one-handed", 10, -0.2, 0.1)
    local _, _, words = model:offset("full-width")
    T.eq(words, 0)
    T.eq(model:shift("full-width"), 0)
    local x, y, one_handed = model:offset("one-handed")
    near(x, -0.2)
    near(y, 0.1)
    T.eq(one_handed, 10)
end)

it("averages the first words, then moves slowly", function()
    local model = newModel()
    model:learn("full-width", { { x = -0.4, y = 0 } }, 1)
    model:learn("full-width", { { x = 0, y = 0 } }, 1)
    near((model:offset("full-width")), -0.2, "mean of the first two")
    learnWords(model, "full-width", 40, -0.2, 0)
    model:learn("full-width", { { x = 0.6, y = 0 } }, 1)
    local x = model:offset("full-width")
    near(x, -0.2 + model.RATE * 0.8, "one late word moves it a little")
end)

it("counts a suggestion picked from the row twice", function()
    local model = newModel()
    model:learn("one-handed", { { x = -0.2, y = 0 } }, 2)
    local _, _, words = model:offset("one-handed")
    T.eq(words, 2)
end)

it("ignores a landing error too large to be the word's key", function()
    local model = newModel()
    model:learn("one-handed", { { x = -0.2, y = 0 } }, 1)
    T.eq(model:learn("one-handed", { { x = -1.5, y = 0 } }, 1), false)
    T.eq(model:learn("one-handed", { { x = 0, y = 0.9 } }, 1), false)
    local x, _, words = model:offset("one-handed")
    near(x, -0.2)
    T.eq(words, 1)
end)

it("caps the shift", function()
    local model = newModel()
    learnWords(model, "one-handed", 20, -0.75, 0.75)
    local dx, dy = model:shift("one-handed")
    near(dx, model.CAP)
    near(dy, -model.CAP)
end)

it("reads landing errors against the kept word's first and last keys",
        function()
    local model = newModel()
    local sample = {
        start = { x = 90, y = 50 },
        lift = { x = 190, y = 110 },
        keys = {
            c = { x = 100, y = 50, w = 50, h = 60 },
            t = { x = 200, y = 110, w = 50, h = 60 },
        },
    }
    local errors = model:errors(sample, "cat")
    T.eq(#errors, 2)
    near(errors[1].x, -0.2)
    near(errors[1].y, 0)
    near(errors[2].x, -0.2)
    T.eq(#model:errors(sample, "cab"), 1, "no key for b: only the start")
    T.eq(#model:errors(sample, "x"), 0, "a one-letter word teaches nothing")
end)

it("turns a shift in key units into pixels at the keys' size", function()
    local model = newModel()
    local x, y = model:toPixels(0.2, -0.1, {
        a = { x = 0, y = 0, w = 50, h = 60 },
        s = { x = 50, y = 0, w = 50, h = 60 },
    })
    near(x, 10)
    near(y, -6)
end)

it("tells the full-width keyboard from the one-handed one on either side",
        function()
    local left = { a = { x = 40 }, l = { x = 300 } }
    local right = { a = { x = 700 }, l = { x = 960 } }
    T.eq(TouchOffset.mode(false, left, 1000), "full-width")
    T.eq(TouchOffset.mode(true, left, 1000), "one-handed left")
    T.eq(TouchOffset.mode(true, right, 1000), "one-handed right")
end)

it("gives the shift in pixels, or nothing to shift", function()
    local model = newModel()
    local keys = { a = { x = 25, y = 30, w = 50, h = 60 } }
    T.eq(model:pixelShift("full-width", keys), nil)
    learnWords(model, "full-width", 10, -0.2, 0)
    local shift = model:pixelShift("full-width", keys)
    near(shift.x, 0.2 * model.STRENGTH * 50)
    near(shift.y, 0)
end)

it("takes a swipe's first and last points to learn from, leaving out a "
        .. "start off the letter keys", function()
    local points = { { x = 1, y = 2 }, { x = 3, y = 4 }, { x = 5, y = 6 } }
    local keys = {}
    local sample = TouchOffset.sample("full-width", points, keys)
    T.eq(sample.mode, "full-width")
    T.eq(sample.start.x, 1)
    T.eq(sample.lift.y, 6)
    T.eq(sample.keys, keys)
    local off = TouchOffset.sample("full-width", points, keys,
        function() return false end)
    T.eq(off.start, nil)
    T.eq(off.lift.x, 5)
    T.eq(TouchOffset.sample("full-width", { points[1] }, keys), nil)
end)

it("reads a damaged setting as nothing learned", function()
    local model = newModel({ touch = { ["one-handed"] = { x = "left",
        words = {} }, ["full-width"] = 3 } })
    T.eq(model:shift("one-handed"), 0)
    local _, _, words = model:offset("full-width")
    T.eq(words, 0)
    T.truthy(model:learn("one-handed", { { x = -0.2, y = 0 } }, 1))
end)

it("saves what it learns", function()
    local model, settings = newModel()
    learnWords(model, "one-handed", 3, -0.2, 0)
    T.truthy(settings.values.touch and settings.values.touch["one-handed"])
    local again = TouchOffset:new(settings, "touch")
    local _, _, words = again:offset("one-handed")
    T.eq(words, 3)
end)
