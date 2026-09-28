-- The strips between the one-handed keys and the screen edge: plain
-- spans that show the page, or, with the hatch setting, thin
-- diagonal lines over the page, like ZenOS, so the keyboard reads as
-- one band across the screen. The lines paint straight into the
-- framebuffer rather than filling a background, so the page shows
-- through the gaps; night mode needs no special handling, since the
-- lines invert with the rest of the screen like any other pixel.
local SideBand = {
    SETTING = "tapless_one_handed_hatch",
    -- Line width, and the period from one line to the next, in
    -- millimetres, of the 45 degree hatch.
    LINE_MM = 0.2,
    SPACING_MM = 1.5,
}
SideBand.__index = SideBand

function SideBand:new(options)
    return setmetatable({
        settings = assert(options.settings),
        screen = assert(options.screen),
        horizontal_span = assert(options.horizontal_span),
        widget = assert(options.widget),
        geometry = assert(options.geometry),
        blitbuffer = assert(options.blitbuffer),
        -- Cached hatch tiles, by period then line width.
        tiles = {},
    }, self)
end

function SideBand:hatched()
    return self.settings:nilOrTrue(self.SETTING)
end

local function round(value)
    return math.floor(value + 0.5)
end

-- Line width and tile period in pixels, from millimetres at the
-- screen's DPI. The period never shrinks below the line's own width
-- plus a visible gap, however coarse the screen.
local function pattern(band)
    local dpi = band.screen:getDPI()
    local line = math.max(1, round(band.LINE_MM * dpi / 25.4))
    local period = math.max(line + 2,
        round(band.SPACING_MM * dpi / 25.4))
    return line, period
end

-- The period x period BB8A tile of the 45 degree hatch, cached on
-- the instance and keyed by (period, line): stamping a small tile
-- with alphablitFrom is far cheaper than setting the strip's pixels
-- one at a time. A new BB8A starts fully transparent, so only the
-- line pixels need setting.
local function tile(band, line, period)
    local by_line = band.tiles[period]
    if not by_line then
        by_line = {}
        band.tiles[period] = by_line
    end
    local cached = by_line[line]
    if cached then
        return cached
    end
    local bb = band.blitbuffer
    cached = bb.new(period, period, bb.TYPE_BB8A)
    local on = bb.Color8A(0x00, 0xFF)
    for y = 0, period - 1 do
        for x = 0, period - 1 do
            if (x + y) % period < line then
                cached:setPixel(x, y, on)
            end
        end
    end
    by_line[line] = cached
    return cached
end

-- A strip width by height pixels: a plain span showing the page
-- when the hatch is off or there is no width, otherwise a widget
-- that paints the hatch straight into the framebuffer, over
-- whatever is already there.
function SideBand:create(width, height)
    if width <= 0 or not self:hatched() then
        return self.horizontal_span:new{ width = math.max(0, width) }
    end
    local line, period = pattern(self)
    local stamp = tile(self, line, period)
    return self.widget:new{
        dimen = self.geometry:new{ w = width, h = height },
        paintTo = function(_, bb, x, y)
            for dy = 0, height - 1, period do
                local h = math.min(period, height - dy)
                for dx = 0, width - 1, period do
                    local w = math.min(period, width - dx)
                    bb:alphablitFrom(stamp, x + dx, y + dy, 0, 0, w, h)
                end
            end
        end,
    }
end

return SideBand
