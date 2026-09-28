-- The strips between the one-handed keys and the screen edge: plain
-- spans that show the page, or, with the hatch setting, white strips of
-- fine diagonal lines, so the keyboard reads as one band across the
-- screen. KOReader's FrameContainer draws the stripes; night mode
-- inverts them with the rest of the screen.
local SideBand = {
    SETTING = "tapless_one_handed_hatch",
    -- Stripe width in millimetres; the gaps are as wide.
    STRIPE_MM = 0.25,
}
SideBand.__index = SideBand

function SideBand:new(options)
    return setmetatable({
        settings = assert(options.settings),
        screen = assert(options.screen),
        horizontal_span = assert(options.horizontal_span),
        frame_container = assert(options.frame_container),
        widget = assert(options.widget),
        geometry = assert(options.geometry),
        blitbuffer = assert(options.blitbuffer),
    }, self)
end

function SideBand:hatched()
    return self.settings:nilOrTrue(self.SETTING)
end

function SideBand:stripeWidth()
    return math.max(1, math.floor(
        self.STRIPE_MM * self.screen:getDPI() / 25.4 + 0.5))
end

-- A strip width by height pixels.
function SideBand:create(width, height)
    if width <= 0 or not self:hatched() then
        return self.horizontal_span:new{ width = math.max(0, width) }
    end
    return self.frame_container:new{
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = self.blitbuffer.COLOR_WHITE,
        stripe_width = self:stripeWidth(),
        stripe_color = self.blitbuffer.COLOR_DARK_GRAY,
        allow_mirroring = false,
        self.widget:new{
            dimen = self.geometry:new{ w = width, h = height },
        },
    }
end

return SideBand
