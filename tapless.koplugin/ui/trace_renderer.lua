-- Draws the swipe trail on e-ink: a round brush about WIDTH_MM wide along
-- smooth curves through the touch points. It inverts the pixels under the
-- brush, so clearing the trail is inverting them back, and refreshes each
-- new piece with A2, the fast black and white waveform.
local TraceRenderer = {
    WIDTH_MM = 0.75,
}
TraceRenderer.__index = TraceRenderer

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
    local dpi = self.screen.getDPI and self.screen:getDPI() or 160
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
            if not row[x] then
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

function TraceRenderer:clear(trace, refresh_type)
    if not trace or not trace.drawn_pixels then
        return
    end
    local region = self:invertPixelSet(trace.drawn_pixels)
    trace.drawn_pixels = nil
    trace.render_before = nil
    if region then
        self.ui_manager:setDirty(nil, refresh_type or "ui", region)
    end
end

return TraceRenderer
