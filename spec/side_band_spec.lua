local T = require("helper")
local it = T.it

local SideBand = T.load("side_band")

local function newBand(values, dpi)
    return SideBand:new{
        settings = {
            nilOrTrue = function(_, name) return values[name] ~= false end,
        },
        screen = { getDPI = function() return dpi or 300 end },
        horizontal_span = { new = function(_, o) o.span = true; return o end },
        frame_container = { new = function(_, o) o.frame = true; return o end },
        widget = { new = function(_, o) return o end },
        geometry = { new = function(_, o) return o end },
        blitbuffer = { COLOR_WHITE = "white", COLOR_DARK_GRAY = "dark" },
    }
end

it("hatches the strip beside the keys by default", function()
    local strip = newBand({}):create(120, 400)
    T.truthy(strip.frame, "a frame")
    T.eq(strip.bordersize, 0)
    T.eq(strip.padding, 0)
    T.eq(strip.background, "white")
    T.eq(strip.stripe_color, "dark")
    T.eq(strip.stripe_width, 3, "0.25 mm at 300 ppi")
    T.eq(strip[1].dimen.w, 120)
    T.eq(strip[1].dimen.h, 400)
end)

it("keeps stripes at least a pixel wide", function()
    T.eq(newBand({}, 60):create(10, 10).stripe_width, 1)
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
