local T = require("helper")
local it = T.it

local SideBand = T.load("side_band")

local function newBand(values)
    return SideBand:new{
        settings = {
            nilOrTrue = function(_, name)
                return values[name] ~= false
            end,
        },
        screen = {
            scaleBySize = function(_, v) return v * 1.5 end,
        },
        horizontal_span = {
            new = function(_, o) o.span = true; return o end,
        },
        widget = {
            new = function(_, o) return o end,
        },
        geometry = {
            new = function(_, o) return o end,
        },
        blitbuffer = {
            COLOR_BLACK = "black",
        },
    }
end

it("hatched by default: create(120, 400) sized, paintTo makes " ..
        "hatchRect(10, 20, 120, 400, 3, 'black', 0.4)", function()
    local band = newBand({})
    local strip = band:create(120, 400)
    T.eq(strip.dimen.w, 120)
    T.eq(strip.dimen.h, 400)
    T.eq(type(strip.paintTo), "function")

    local calls = {}
    local bb = {
        hatchRect = function(self, x, y, w, h, sw, c, a)
            table.insert(calls, { x, y, w, h, sw, c, a })
        end,
    }
    strip.paintTo(strip, bb, 10, 20)
    T.eq(#calls, 1, "exactly one hatchRect call")
    local call = calls[1]
    T.eq(call[1], 10, "x")
    T.eq(call[2], 20, "y")
    T.eq(call[3], 120, "w")
    T.eq(call[4], 400, "h")
    T.eq(call[5], 3, "stripe: 2 × 1.5")
    T.eq(call[6], "black", "colour")
    T.eq(call[7], 0.4, "opacity: ZenOS's 40%")
end)

it("stripe is at least 1 px when scaleBySize returns 0", function()
    local band = SideBand:new{
        settings = {
            nilOrTrue = function(_, name) return true end,
        },
        screen = {
            scaleBySize = function(_, v) return 0 end,
        },
        horizontal_span = {
            new = function(_, o) o.span = true; return o end,
        },
        widget = {
            new = function(_, o) return o end,
        },
        geometry = {
            new = function(_, o) return o end,
        },
        blitbuffer = {
            COLOR_BLACK = "black",
        },
    }
    local calls = {}
    local bb = {
        hatchRect = function(self, x, y, w, h, sw, c, a)
            table.insert(calls, { x, y, w, h, sw, c, a })
        end,
    }
    local strip = band:create(10, 10)
    strip.paintTo(strip, bb, 0, 0)
    T.eq(calls[1][5], 1, "min stripe width is 1")
end)

it("off (setting false) gives a plain span", function()
    local band = newBand({ ligature_one_handed_hatch = false })
    local strip = band:create(120, 400)
    T.truthy(strip.span, "a span")
    T.eq(strip.width, 120)
end)

it("width 0 gives a plain span", function()
    local band = newBand({})
    local strip = band:create(0, 400)
    T.truthy(strip.span)
    T.eq(strip.width, 0)
end)

it("no fill: the only draw call is hatchRect", function()
    local band = newBand({})
    local strip = band:create(10, 10)

    local calls = {}
    local bb = {}
    setmetatable(bb, {
        __index = function(_, method)
            if method == "hatchRect" then
                return function(self, ...)
                    table.insert(calls, method)
                end
            end
            table.insert(calls, method)
            error("Unexpected method: " .. method)
        end,
    })
    strip.paintTo(strip, bb, 0, 0)
    T.eq(#calls, 1, "exactly one method call")
    T.eq(calls[1], "hatchRect", "the only method is hatchRect")
end)
