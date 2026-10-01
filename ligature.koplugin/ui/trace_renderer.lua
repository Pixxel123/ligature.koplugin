-- Draws the swipe trail on e-ink: a round brush about WIDTH_MM wide along
-- smooth curves through the touch points. It inverts the pixels under the
-- brush, so clearing the trail is inverting them back, and refreshes each
-- new piece with A2, the fast black and white waveform. A2 shows only
-- black and white, so a grey trail is dithered: only DITHER of the
-- brush's pixels are inverted, in a pattern fixed to the screen so pieces
-- that overlap line up. Inverting keeps it readable in night mode too,
-- where it shows light on the dark keys.
local TraceRenderer = {
    WIDTH_MM = 0.75,
    -- The share of pixels drawn: 1 is solid, 0.75 dark grey, 0.5 grey.
    DITHER = 0.5,
    -- The refresh that clears the trail when the finger lifts: quick, so
    -- the next swipe isn't held up.
    CLEAR_REFRESH = "ui",
    -- A2 leaves faint traces that "ui" doesn't wipe, so they build up over
    -- a long spell of typing, and only a flashing refresh clears them
    -- (REAGL, tried first, didn't). So once swiping pauses for
    -- CLEANUP_DELAY seconds, after at least CLEANUP_EVERY swipes since the
    -- last clean-up, everywhere those trails went gets one flash. Never
    -- at a lift: a slow refresh there held up the screen and lost the
    -- next swipe.
    CLEANUP_REFRESH = "flashui",
    -- In recorded sessions only 9% of the gaps before the next word were
    -- longer than 3 s, so the flash mostly falls at a sentence's end.
    CLEANUP_DELAY = 3,
    CLEANUP_EVERY = 8,
}
TraceRenderer.__index = TraceRenderer

-- Whether the dither pattern draws the pixel at x, y.
function TraceRenderer:inPattern(x, y)
    local dither = self.DITHER
    if dither >= 1 then
        return true
    elseif dither >= 0.75 then
        return x % 2 == 0 or y % 2 == 0
    end
    return (x + y) % 2 == 0
end

function TraceRenderer:new(screen, ui_manager, geometry)
    return setmetatable({
        screen = assert(screen),
        ui_manager = assert(ui_manager),
        geometry = assert(geometry),
    }, self)
end

-- The brush's pixels, as offsets from its centre: a disc WIDTH_MM across
-- at the screen's dpi, at least 3 pixels.
function TraceRenderer:brush()
    local dpi = self.screen:getDPI()
    local radius = math.max(1,
        math.floor(self.WIDTH_MM * dpi / 25.4 / 2 + 0.5))
    if self.brush_radius ~= radius then
        local offsets = {}
        local limit = radius * radius + radius
        for dy = -radius, radius do
            for dx = -radius, radius do
                if dx * dx + dy * dy <= limit then
                    offsets[#offsets + 1] = { dx, dy }
                end
            end
        end
        self.brush_offsets, self.brush_radius = offsets, radius
    end
    return self.brush_offsets
end

function TraceRenderer:invertPixelSet(pixel_set)
    local min_x, min_y = math.huge, math.huge
    local max_x, max_y = -math.huge, -math.huge
    for y, row in pairs(pixel_set or {}) do
        local run_start
        local previous_x
        local xs = {}
        for x in pairs(row) do
            table.insert(xs, x)
        end
        table.sort(xs)
        for _, current_x in ipairs(xs) do
            min_x = math.min(min_x, current_x)
            min_y = math.min(min_y, y)
            max_x = math.max(max_x, current_x)
            max_y = math.max(max_y, y)
            if not run_start then
                run_start = current_x
            elseif current_x ~= previous_x + 1 then
                self.screen.bb:invertRect(
                    run_start, y, previous_x - run_start + 1, 1)
                run_start = current_x
            end
            previous_x = current_x
        end
        if run_start then
            self.screen.bb:invertRect(
                run_start, y, previous_x - run_start + 1, 1)
        end
    end
    if min_x == math.huge then
        return
    end
    return self.geometry:new{
        x = min_x,
        y = min_y,
        w = max_x - min_x + 1,
        h = max_y - min_y + 1,
    }
end

-- The piece of trail from previous to current, as points a pixel or less
-- apart. It is a curve that leaves previous in the direction the trail
-- was heading there (from the point before it, before, towards current)
-- and arrives at current along the last step, so it ends at the finger,
-- with no lag, and joins the piece before it smoothly.
function TraceRenderer.curve(before, previous, current)
    local x0, y0 = previous.x, previous.y
    local x1, y1 = current.x, current.y
    local back = before or previous
    local m0x, m0y = (x1 - back.x) / 2, (y1 - back.y) / 2
    local m1x, m1y = x1 - x0, y1 - y0
    local length = math.sqrt(m1x * m1x + m1y * m1y)
    local steps = math.max(1, math.ceil(length))
    local points = {}
    for step = 0, steps do
        local t = step / steps
        local t2, t3 = t * t, t * t * t
        local h00 = 2 * t3 - 3 * t2 + 1
        local h10 = t3 - 2 * t2 + t
        local h01 = -2 * t3 + 3 * t2
        local h11 = t3 - t2
        points[#points + 1] = {
            x = h00 * x0 + h10 * m0x + h01 * x1 + h11 * m1x,
            y = h00 * y0 + h10 * m0y + h01 * y1 + h11 * m1y,
        }
    end
    return points
end

function TraceRenderer:drawSegment(trace, previous, current)
    if not trace or not current then
        return
    end
    -- Swiping again: a clean-up due now waits for the next pause.
    self.cleanup_generation = (self.cleanup_generation or 0) + 1
    trace.drawn_pixels = trace.drawn_pixels or {}
    local before = trace.render_before
    trace.render_before = previous
    local centres = previous and self.curve(before, previous, current)
        or { current }
    local brush = self:brush()
    local new_pixels = {}
    for _, centre in ipairs(centres) do
        local cx = math.floor(centre.x + 0.5)
        local cy = math.floor(centre.y + 0.5)
        for _, offset in ipairs(brush) do
            local x, y = cx + offset[1], cy + offset[2]
            local row = trace.drawn_pixels[y]
            if not row then
                row = {}
                trace.drawn_pixels[y] = row
            end
            if not row[x] and self:inPattern(x, y) then
                row[x] = true
                local new_row = new_pixels[y]
                if not new_row then
                    new_row = {}
                    new_pixels[y] = new_row
                end
                new_row[x] = true
            end
        end
    end
    local region = self:invertPixelSet(new_pixels)
    if region then
        self.ui_manager:setDirty(nil, "a2", region)
    end
end

function TraceRenderer:clear(trace)
    if not trace or not trace.drawn_pixels then
        return
    end
    local region = self:invertPixelSet(trace.drawn_pixels)
    trace.drawn_pixels = nil
    trace.render_before = nil
    if region then
        self.ui_manager:setDirty(nil, self.CLEAR_REFRESH, region)
        self:_scheduleCleanup(region)
    end
end

-- Adds region to the area the next clean-up refreshes, and, once enough
-- swipes have built up, schedules the clean-up for when swiping has
-- paused.
function TraceRenderer:_scheduleCleanup(region)
    self.cleanup_swipes = (self.cleanup_swipes or 0) + 1
    local area = self.cleanup_area
    if area then
        local x0 = math.min(area.x, region.x)
        local y0 = math.min(area.y, region.y)
        local x1 = math.max(area.x + area.w, region.x + region.w)
        local y1 = math.max(area.y + area.h, region.y + region.h)
        area.x, area.y, area.w, area.h = x0, y0, x1 - x0, y1 - y0
    else
        self.cleanup_area = self.geometry:new{
            x = region.x, y = region.y, w = region.w, h = region.h,
        }
    end
    if self.cleanup_swipes < self.CLEANUP_EVERY then
        return
    end
    self.cleanup_generation = (self.cleanup_generation or 0) + 1
    local generation = self.cleanup_generation
    self.ui_manager:scheduleIn(self.CLEANUP_DELAY, function()
        if self.cleanup_generation ~= generation or not self.cleanup_area then
            return
        end
        local cleanup = self.cleanup_area
        self.cleanup_area, self.cleanup_swipes = nil, 0
        self.ui_manager:setDirty(nil, self.CLEANUP_REFRESH, cleanup)
    end)
end

return TraceRenderer
