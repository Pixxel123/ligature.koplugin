local T = require("helper")
local it = T.it

local KeyboardGeometry = T.load("keyboard_geometry")

-- KOReader's Geom:contains (frontend/ui/geometry.lua) reads the other
-- rectangle's w and h, so a bare point without them raises an error.
local function strictContains(self, geom)
    return self.x <= geom.x and self.y <= geom.y
        and self.x + self.w >= geom.x + geom.w
        and self.y + self.h >= geom.y + geom.h
end

-- Two 100px keys side by side: q from 0 to 100, w from 100 to 200.
local function newLayout()
    local row = {}
    for index, letter in ipairs({ "q", "w" }) do
        row[index] = {
            key = letter,
            dimen = {
                x = (index - 1) * 100, y = 0, w = 100, h = 100,
                contains = strictContains,
            },
        }
    end
    return { row }
end

it("finds the key under a trace point, which has no size", function()
    local geometry = KeyboardGeometry:new(T.normalization)
    T.eq(geometry:keyAt(newLayout(), { x = 150, y = 50, time = 1 }), "w")
end)

it("takes a point on a shared edge as the first key, as KOReader does",
        function()
    local geometry = KeyboardGeometry:new(T.normalization)
    T.eq(geometry:keyAt(newLayout(), { x = 100, y = 50 }), "q")
end)

-- A number row of 1 and 2 above the letters q and w, each 100px square.
local function newNumberRowLayout()
    local function rowOf(keys, y)
        local row = {}
        for index, key in ipairs(keys) do
            row[index] = {
                key = key,
                dimen = {
                    x = (index - 1) * 100, y = y, w = 100, h = 100,
                    contains = strictContains,
                },
            }
        end
        return row
    end
    return { rowOf({ "1", "2" }, 0), rowOf({ "q", "w" }, 100) }
end

it("starts a swipe that lands on a number-row key on the letter below",
        function()
    local geometry = KeyboardGeometry:new(T.normalization)
    local layout = newNumberRowLayout()
    local letter, key = geometry:startKeyAt(layout, { x = 150, y = 90 })
    T.eq(letter, "w")
    T.eq(key.key, "w")
    letter, key = geometry:startKeyAt(layout, { x = 30, y = 5 })
    T.eq(letter, "q", "even high in the number row")
end)

it("counts the shift layer's number row, whose keys carry the digit as alternate",
        function()
    local geometry = KeyboardGeometry:new(T.normalization)
    local layout = newNumberRowLayout()
    layout[1][2].key = "@"
    layout[1][2].alt_label = "2"
    local letter, key = geometry:startKeyAt(layout, { x = 150, y = 90 })
    T.eq(letter, "w")
    T.eq(key.key, "w")
    layout[1][2].alt_label = "!"
    T.eq(geometry:startKeyAt(layout, { x = 150, y = 90 }), nil,
        "a symbol key with no digit is not a number key")
end)

it("still takes a number-row key as no letter when only asked what is there",
        function()
    local geometry = KeyboardGeometry:new(T.normalization)
    local letter, key = geometry:keyAt(newNumberRowLayout(),
        { x = 150, y = 90 })
    T.eq(letter, nil)
    T.eq(key.key, "2")
end)

it("starts a swipe on a letter key where it landed", function()
    local geometry = KeyboardGeometry:new(T.normalization)
    local letter, key = geometry:startKeyAt(newNumberRowLayout(),
        { x = 150, y = 150 })
    T.eq(letter, "w")
    T.eq(key.key, "w")
end)

it("leaves a number-row key with no letter below it as a digit key", function()
    local geometry = KeyboardGeometry:new(T.normalization)
    local layout = newNumberRowLayout()
    table.remove(layout[2], 2)
    local letter, key = geometry:startKeyAt(layout, { x = 150, y = 90 })
    T.eq(letter, nil)
    T.eq(key.key, "2")
    layout[2] = nil
    letter, key = geometry:startKeyAt(layout, { x = 50, y = 90 })
    T.eq(letter, nil)
    T.eq(key.key, "1")
end)

it("does not move a start off a key that is not a number", function()
    local geometry = KeyboardGeometry:new(T.normalization)
    local layout = newNumberRowLayout()
    layout[1][2].key = "Shift"
    local letter, key = geometry:startKeyAt(layout, { x = 150, y = 90 })
    T.eq(letter, nil)
    T.eq(key.key, "Shift")
end)

it("finds no start for a point outside every key", function()
    local geometry = KeyboardGeometry:new(T.normalization)
    T.eq(geometry:startKeyAt(newNumberRowLayout(), { x = 500, y = 500 }), nil)
    T.eq(geometry:startKeyAt(nil, { x = 50, y = 50 }), nil)
    T.eq(geometry:startKeyAt(newNumberRowLayout(), nil), nil)
end)

it("gives each letter key's centre and size, and the key centres from them",
        function()
    local geometry = KeyboardGeometry:new(T.normalization)
    local layout = newLayout()
    layout[1][2].dimen.h = 80
    local keys = geometry:letterKeys(layout)
    T.eq(keys.q.x, 50)
    T.eq(keys.w.x, 150)
    T.eq(keys.w.y, 40)
    T.eq(keys.w.w, 100)
    T.eq(keys.w.h, 80)
    local centers = geometry:keyCenters(layout)
    T.eq(centers[string.byte("w")].x, 150)
    T.eq(centers[string.byte("w")].size, 100)
end)

-- Folds the accented letters of the layouts below to a-z, as the
-- latin-extended profile does, and leaves the rest to T.normalization.
local ACCENTS = { ["ě"] = "e", ["č"] = "c", ["ñ"] = "n", ["å"] = "a",
    ["ı"] = "i", ["ğ"] = "g" }
local folding = setmetatable({
    normalizeText = function(self, text)
        if ACCENTS[text] then return ACCENTS[text] end
        return T.normalization.normalizeText(self, text)
    end,
}, { __index = T.normalization })

-- Rows of 100px keys, top row first.
local function rowsOf(...)
    local layout = {}
    for row_index, keys in ipairs({ ... }) do
        local row = {}
        for index, key in ipairs(keys) do
            row[index] = {
                key = key,
                dimen = { x = (index - 1) * 100, y = (row_index - 1) * 100,
                    w = 100, h = 100 },
            }
        end
        layout[row_index] = row
    end
    return layout
end

it("places a letter on its own key, not an accented key above it",
        function()
    local geometry = KeyboardGeometry:new(folding)
    -- Czech: ě and č on the number row, e and c below.
    local keys = geometry:letterKeys(rowsOf({ "ě", "č" }, { "e", "x" },
        { "z", "c" }))
    T.eq(keys.e.y, 150, "e")
    T.eq(keys.c.x, 150, "c")
    T.eq(keys.c.y, 250, "c")
    -- Spanish ñ beside l, above n; Danish å at the end of the top row.
    keys = geometry:letterKeys(rowsOf({ "q", "å" }, { "a", "ñ" }, { "n" }))
    T.eq(keys.n.y, 250, "n")
    T.eq(keys.a.y, 150, "a")
    -- Turkish ı and ğ on the top row, i and g on the next.
    keys = geometry:letterKeys(rowsOf({ "ı", "ğ" }, { "g", "i" }))
    T.eq(keys.i.x, 150, "i")
    T.eq(keys.g.x, 50, "g")
end)

it("keeps a letter's accented keys beside its own key", function()
    local geometry = KeyboardGeometry:new(folding)
    -- Danish: å at the end of the top row, a below.
    local keys = geometry:letterKeys(rowsOf({ "q", "å" }, { "a", "s" }))
    T.eq(keys.a.x, 50)
    T.eq(#keys.a.others, 1)
    T.eq(keys.a.others[1].x, 150)
    T.eq(keys.a.others[1].y, 50)
    T.eq(keys.s.others, nil, "a letter with one key")
    local centers = geometry:keyCenters(rowsOf({ "q", "å" }, { "a", "s" }))
    local a = centers[string.byte("a")]
    T.eq(a.x, 50)
    T.eq(a.others[1].x, 150)
    T.eq(a.others[1].size, 100)
end)

it("still places a letter that only has an accented key", function()
    local geometry = KeyboardGeometry:new(folding)
    local keys = geometry:letterKeys(rowsOf({ "ñ", "q" }))
    T.eq(keys.n.x, 50)
    T.eq(geometry:keyCenters(rowsOf({ "ñ" }))[string.byte("n")].x, 50)
end)
