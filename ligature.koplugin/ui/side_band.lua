-- The strips between the one-handed keys and the screen edge: plain
-- spans that show the page, or, with the hatch setting, the page under
-- ZenOS's background hatching (common/ui/hatching.lua in ZenOS): KOReader's
-- own diagonal hatch in black at 40% opacity, so the page still shows
-- through while the keyboard reads as one band across the screen.
local SideBand = {
    SETTING = "ligature_one_handed_hatch",
    -- ZenOS's values: stripe width before scaling, and opacity.
    STRIPE = 2,
    ALPHA = 0.4,
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
    }, self)
end

function SideBand:hatched()
    return self.settings:nilOrTrue(self.SETTING)
end

-- A strip width by height pixels. Hatched, it draws over whatever is
-- already on screen there, the page, rather than filling it first.
function SideBand:create(width, height)
    if width <= 0 or not self:hatched() then
        return self.horizontal_span:new{ width = math.max(0, width) }
    end
    local band = self
    return self.widget:new{
        dimen = self.geometry:new{ w = width, h = height },
        paintTo = function(strip, bb, x, y)
            local size = strip.dimen
            bb:hatchRect(x, y, size.w, size.h,
                math.max(1, band.screen:scaleBySize(band.STRIPE)),
                band.blitbuffer.COLOR_BLACK, band.ALPHA)
        end,
    }
end

return SideBand
