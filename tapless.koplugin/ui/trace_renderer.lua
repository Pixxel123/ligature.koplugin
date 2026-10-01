-- Draws the swipe trail on e-ink: a round brush about WIDTH_MM wide along
-- smooth curves through the touch points, showing only the last TAIL_MM
-- of the path, so the trail follows the finger. It inverts the pixels
-- under the brush, so erasing is inverting them back, and refreshes each
-- step, new piece and erased tail together, with A2, the fast black and
-- white waveform. Lifting clears what is left and refreshes everywhere
-- the trail went, which also clears any ghosting the erasing left.
local TraceRenderer = {
    WIDTH_MM = 0.75,
    -- How much of the path stays drawn behind the finger; 0 keeps it all.
    TAIL_MM = 30,
}
TraceRenderer.__index = TraceRenderer

function TraceRenderer:new(screen, ui_manager, geometry)
    return setmetatable({
        screen = assert(screen),
        ui_manager = assert(ui_manager),
        geometry = assert(geometry),
    }, self)
end

function TraceRenderer:pixelsPerMM()
    local dpi = self.screen.getDPI and self.screen:getDPI() or 160
    return dpi / 25.4
end

-- The brush's pixels, as offsets from its centre: a disc WIDTH_MM across
-- at the screen's dpi, at least 3 pixels.
function TraceRenderer:brush()
    local radius = math.max(1,
        math.floor(self.WIDTH_MM * self:pixelsPerMM() / 2 + 0.5))
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
    return points, length
end

-- Flips a pixel in a set of pixels to invert: flipping it twice in one
-- step leaves it as it was.
local function flip(set, x, y)
    local row = set[y]
    if not row then
        row = {}
        set[y] = row
    end
    row[x] = not row[x] or nil
end

-- A pixel newly covered by a piece of trail (count 0 to 1) or no longer
-- covered by any (1 to 0) changes colour; where pieces cross, it stays.
local function cover(trace, x, y, by, changed)
    local row = trace.cover[y]
    if not row then
        row = {}
        trace.cover[y] = row
    end
    local count = (row[x] or 0) + by
    row[x] = count > 0 and count or nil
    if (by > 0 and count == 1) or (by < 0 and count == 0) then
        flip(changed, x, y)
    end
end

function TraceRenderer:drawSegment(trace, previous, current)
    if not trace or not current then
        return
    end
    trace.cover = trace.cover or {}
    trace.pieces = trace.pieces or {}
    trace.shown_length = trace.shown_length or 0
    local before = trace.render_before
    trace.render_before = previous
    local centres, length = { current }, 0
    if previous then
        centres, length = self.curve(before, previous, current)
    end

    -- The new piece's pixels, each once.
    local brush = self:brush()
    local pixels, seen = {}, {}
    for _, centre in ipairs(centres) do
        local cx = math.floor(centre.x + 0.5)
        local cy = math.floor(centre.y + 0.5)
        for _, offset in ipairs(brush) do
            local x, y = cx + offset[1], cy + offset[2]
            local key = y * 65536 + x
            if not seen[key] then
                seen[key] = true
                pixels[#pixels + 1] = { x, y }
            end
        end
    end

    local changed = {}
    for _, p in ipairs(pixels) do
        cover(trace, p[1], p[2], 1, changed)
        local reach = trace.reach
        if not reach then
            trace.reach = { p[1], p[2], p[1], p[2] }
        else
            reach[1] = math.min(reach[1], p[1])
            reach[2] = math.min(reach[2], p[2])
            reach[3] = math.max(reach[3], p[1])
            reach[4] = math.max(reach[4], p[2])
        end
    end
    local pieces = trace.pieces
    pieces[#pieces + 1] = { pixels = pixels, length = length }
    trace.shown_length = trace.shown_length + length

    -- Erase the oldest pieces beyond the tail, keeping the newest.
    if self.TAIL_MM > 0 then
        local tail = self.TAIL_MM * self:pixelsPerMM()
        local first = trace.first_piece or 1
        while first < #pieces and trace.shown_length - pieces[first].length > tail do
            for _, p in ipairs(pieces[first].pixels) do
                cover(trace, p[1], p[2], -1, changed)
            end
            trace.shown_length = trace.shown_length - pieces[first].length
            pieces[first] = false
            first = first + 1
        end
        trace.first_piece = first
    end

    local region = self:invertPixelSet(changed)
    if region then
        self.ui_manager:setDirty(nil, "a2", region)
    end
end

function TraceRenderer:clear(trace, refresh_type)
    if not trace or not trace.cover then
        return
    end
    local shown = {}
    for y, row in pairs(trace.cover) do
        for x in pairs(row) do
            flip(shown, x, y)
        end
    end
    self:invertPixelSet(shown)
    local reach = trace.reach
    trace.cover, trace.pieces, trace.reach = nil, nil, nil
    trace.shown_length, trace.first_piece, trace.render_before = nil, nil, nil
    if reach then
        self.ui_manager:setDirty(nil, refresh_type or "ui", self.geometry:new{
            x = reach[1],
            y = reach[2],
            w = reach[3] - reach[1] + 1,
            h = reach[4] - reach[2] + 1,
        })
    end
end

return TraceRenderer
