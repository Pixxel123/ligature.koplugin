local T = require("helper")
local it = T.it

-- A renderer over a screen at dpi, drawing dither of its pixels (solid
-- unless given), that records every inverted pixel (a pixel inverted
-- twice is back to white) and every refresh.
local function setup(dpi, dither)
    local calls = { black = {}, dirty = {} }
    local screen = {
        getDPI = function() return dpi or 300 end,
        bb = {
            invertRect = function(_, x, y, w, h)
                for py = y, y + h - 1 do
                    for px = x, x + w - 1 do
                        local key = px .. "," .. py
                        calls.black[key] = not calls.black[key] or nil
                    end
                end
            end,
        },
    }
    local renderer = T.load("trace_renderer"):new(screen, {
        setDirty = function(_, _, mode, region)
            calls.dirty[#calls.dirty + 1] = { mode = mode, region = region }
        end,
    }, { new = function(_, o) return o end })
    renderer.DITHER = dither or 1
    return renderer, calls
end

local function black(calls)
    local n = 0
    for _ in pairs(calls.black) do n = n + 1 end
    return n
end

it("draws a round brush about 0.75 mm wide", function()
    local renderer, calls = setup(300)
    renderer:drawSegment({}, nil, { x = 100, y = 100 })
    -- 0.75 mm at 300 dpi is 8.9 pixels: a disc 9 pixels across.
    T.truthy(calls.black["96,100"] and calls.black["104,100"], "9 across")
    T.eq(calls.black["95,100"], nil)
    T.eq(calls.black["104,104"], nil, "round, not square")
    T.eq(calls.dirty[1].mode, "a2")
    local thin = setup(100)
    T.eq(#thin:brush(), 9, "at least 3 pixels across on a coarse screen")
end)

it("ends each piece at the finger, so the trail never lags it", function()
    local renderer, calls = setup(300)
    local trace = {}
    local points = { { x = 100, y = 300 }, { x = 160, y = 260 }, { x = 230, y = 300 } }
    renderer:drawSegment(trace, nil, points[1])
    renderer:drawSegment(trace, points[1], points[2])
    renderer:drawSegment(trace, points[2], points[3])
    for _, p in ipairs(points) do
        T.truthy(calls.black[p.x .. "," .. p.y], "through " .. p.x)
    end
end)

it("curves through a turn instead of meeting it at a corner", function()
    local curve = T.load("trace_renderer").curve
    -- Heading right, then a step up and right: the curve leaves the
    -- corner still heading right, so it bows below the straight line.
    local points = curve({ x = 0, y = 100 }, { x = 100, y = 100 }, { x = 200, y = 0 })
    local middle = points[math.floor(#points / 2)]
    T.truthy(middle.y > 100 - (middle.x - 100) + 5, "bows: " .. middle.x .. "," .. middle.y)
    T.eq(points[1].x, 100)
    T.eq(points[#points].x, 200)
    T.eq(points[#points].y, 0)
    for i = 2, #points do
        local dx = points[i].x - points[i - 1].x
        local dy = points[i].y - points[i - 1].y
        T.truthy(math.sqrt(dx * dx + dy * dy) <= 1.5, "no gaps")
    end
end)

it("clears exactly what it drew, crossings included", function()
    local renderer, calls = setup(300)
    local trace = {}
    renderer:drawSegment(trace, nil, { x = 100, y = 100 })
    renderer:drawSegment(trace, { x = 100, y = 100 }, { x = 200, y = 200 })
    renderer:drawSegment(trace, { x = 200, y = 200 }, { x = 200, y = 100 })
    renderer:drawSegment(trace, { x = 200, y = 100 }, { x = 100, y = 200 })
    T.truthy(black(calls) > 0)
    renderer:clear(trace)
    T.eq(black(calls), 0, "all white again")
    T.eq(trace.render_before, nil)
    T.eq(calls.dirty[#calls.dirty].mode, "ui")
end)

it("draws a grey trail by dithering: half the pixels, by default", function()
    T.eq(T.load("trace_renderer").DITHER, 0.5)
    for _, case in ipairs({ { 0.5, 0.45, 0.55 }, { 0.75, 0.7, 0.8 } }) do
        local dither, low, high = case[1], case[2], case[3]
        local solid_renderer, solid = setup(300)
        local renderer, grey = setup(300, dither)
        local path = { { x = 100, y = 300 }, { x = 220, y = 280 }, { x = 360, y = 320 } }
        local solid_trace = {}
        for i, p in ipairs(path) do
            solid_renderer:drawSegment(solid_trace, path[i - 1], p)
        end
        local trace = {}
        for i, p in ipairs(path) do
            renderer:drawSegment(trace, path[i - 1], p)
        end
        local share = black(grey) / black(solid)
        T.truthy(share > low and share < high, dither .. ": " .. share)
        renderer:clear(trace)
        T.eq(black(grey), 0, dither .. ": clears to white")
    end
end)

it("keeps the dither pattern fixed to the screen, so pieces that overlap "
        .. "or cross don't leave holes or blotches", function()
    local renderer, calls = setup(300, 0.5)
    local trace = {}
    renderer:drawSegment(trace, nil, { x = 100, y = 100 })
    renderer:drawSegment(trace, { x = 100, y = 100 }, { x = 200, y = 100 })
    renderer:drawSegment(trace, { x = 200, y = 100 }, { x = 100, y = 100 })
    for key in pairs(calls.black) do
        local x, y = key:match("(%d+),(%d+)")
        T.eq((tonumber(x) + tonumber(y)) % 2, 0, "only pattern pixels: " .. key)
    end
    T.truthy(calls.black["150,100"] and calls.black["151,101"], "both lines of the grid")
end)
