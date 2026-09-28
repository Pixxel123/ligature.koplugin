local T = require("helper")
local it = T.it

local SideBand = T.load("side_band")

-- A fake BB8A tile: records every setPixel call so a test can check
-- exactly which pixels were switched on.
local function newTile(w, h)
    local tile = { w = w, h = h, set = {} }
    tile.setPixel = function(self, x, y, color)
        self.set[y * self.w + x] = color
    end
    return tile
end

-- A fake blitbuffer module: counts how many tiles it is asked to
-- build, so a test can check the tile is cached rather than rebuilt.
local function newBlitbuffer()
    local fake = {
        TYPE_BB8A = "bb8a",
        COLOR_BLACK = "black",
        tile_calls = 0,
    }
    fake.Color8A = function(a, alpha) return { a = a, alpha = alpha } end
    fake.new = function(w, h, kind)
        fake.tile_calls = fake.tile_calls + 1
        T.eq(kind, fake.TYPE_BB8A, "tile is BB8A")
        return newTile(w, h)
    end
    return fake
end

local function newBand(values, dpi, blitbuffer)
    return SideBand:new{
        settings = {
            nilOrTrue = function(_, name) return values[name] ~= false end,
        },
        screen = { getDPI = function() return dpi or 300 end },
        horizontal_span = { new = function(_, o) o.span = true; return o end },
        widget = { new = function(_, o) return o end },
        geometry = { new = function(_, o) return o end },
        blitbuffer = blitbuffer or newBlitbuffer(),
    }
end

it("hatches the strip beside the keys by default", function()
    local strip = newBand({}):create(120, 400)
    T.eq(strip.frame, nil, "no frame")
    T.eq(strip.background, nil, "no white background")
    T.eq(strip.dimen.w, 120)
    T.eq(strip.dimen.h, 400)
    T.eq(type(strip.paintTo), "function", "paints its own lines")
end)

it("builds one tile, its pixels on the 45 degree line", function()
    local blitbuffer = newBlitbuffer()
    local band = newBand({}, 300, blitbuffer)
    local strip = band:create(40, 30)
    band:create(50, 60) -- a second strip: still the same tile.
    local bb = { calls = {} }
    bb.alphablitFrom = function(self, ...)
        table.insert(self.calls, { ... })
    end
    strip.paintTo(strip, bb, 0, 0)
    strip.paintTo(strip, bb, 0, 0) -- a second paint: no rebuild.
    T.eq(blitbuffer.tile_calls, 1, "the tile is built once")

    local tile = bb.calls[1][1]
    T.eq(tile.w, 18, "1.5 mm period at 300 ppi")
    T.eq(tile.h, 18, "1.5 mm period at 300 ppi")
    local line = 0
    for y = 0, tile.h - 1 do
        for x = 0, tile.w - 1 do
            local on = (x + y) % 18 < 2
            local pixel = tile.set[y * tile.w + x]
            T.eq(pixel ~= nil, on, "pixel " .. x .. "," .. y)
            if pixel then
                T.eq(pixel.a, 0x00, "black")
                T.eq(pixel.alpha, 0xFF, "fully opaque")
                if y == 0 then line = line + 1 end
            end
        end
    end
    T.eq(line, 2, "0.2 mm line at 300 ppi")
end)

it("keeps a coarse screen's line at least a pixel wide", function()
    local blitbuffer = newBlitbuffer()
    local strip = newBand({}, 60, blitbuffer):create(10, 10)
    local bb = { calls = {} }
    bb.alphablitFrom = function(self, ...)
        table.insert(self.calls, { ... })
    end
    strip.paintTo(strip, bb, 0, 0)
    local tile = bb.calls[1][1]
    local line = 0
    for x = 0, tile.w - 1 do
        if tile.set[x] then line = line + 1 end
    end
    T.eq(line, 1, "one pixel wide")
    T.truthy(tile.w >= line + 2, "a gap around the line")
end)

it("stamps the tile across the strip, clipped to its edges", function()
    local strip = newBand({}):create(40, 30)
    local bb = { calls = {} }
    bb.alphablitFrom = function(self, _, dest_x, dest_y, offs_x,
            offs_y, w, h)
        table.insert(self.calls,
            { dest_x, dest_y, offs_x, offs_y, w, h })
    end
    strip.paintTo(strip, bb, 10, 20)
    local expected = {
        { 10, 20, 0, 0, 18, 18 },
        { 28, 20, 0, 0, 18, 18 },
        { 46, 20, 0, 0,  4, 18 },
        { 10, 38, 0, 0, 18, 12 },
        { 28, 38, 0, 0, 18, 12 },
        { 46, 38, 0, 0,  4, 12 },
    }
    T.eq(#bb.calls, #expected, "one stamp per tile, clipped at the edge")
    for i, call in ipairs(expected) do
        for j, value in ipairs(call) do
            T.eq(bb.calls[i][j], value, "call " .. i .. " arg " .. j)
        end
    end
end)

it("shows the page when the hatch is off", function()
    local strip = newBand({ tapless_one_handed_hatch = false })
        :create(120, 400)
    T.truthy(strip.span, "a span")
    T.eq(strip.width, 120)
end)

it("leaves an empty strip empty", function()
    local strip = newBand({}):create(0, 400)
    T.truthy(strip.span)
    T.eq(strip.width, 0)
end)
