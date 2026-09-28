-- Widths for the suggestion boxes: each in proportion to its word, so a
-- long word gets room and short ones give theirs up, but none narrower
-- than MIN_SHARE of an equal share. Spare room is shared out evenly.
local CandidateWidths = {
    MIN_SHARE = 0.6,
}

-- wants: the width each box would like (its word and padding); avail:
-- the width the boxes share. min_share: minimum share as a fraction
-- (must be at most 1); defaults to MIN_SHARE. Returns whole-pixel
-- widths summing to avail.
function CandidateWidths.compute(wants, avail, min_share)
    local n = #wants
    if n == 0 then
        return {}
    end
    local min_width = (min_share or CandidateWidths.MIN_SHARE) * avail / n
    local sized, total = {}, 0
    for index, want in ipairs(wants) do
        sized[index] = math.max(min_width, want)
        total = total + sized[index]
    end
    local widths = {}
    if total <= avail then
        local spare = (avail - total) / n
        for index = 1, n do
            widths[index] = sized[index] + spare
        end
    else
        -- Too wide: the boxes above the minimum give up room in
        -- proportion to how far above it they are.
        local scale = (avail - n * min_width) / (total - n * min_width)
        for index = 1, n do
            widths[index] = min_width + (sized[index] - min_width) * scale
        end
    end
    -- Largest-remainder rounding: floor each width, then hand out the
    -- leftover pixels one each to the boxes with the largest fractional
    -- parts. Ties go to the lower index.
    local out, total_floor = {}, 0
    local fractions = {}
    for index = 1, n do
        out[index] = math.floor(widths[index])
        fractions[index] = widths[index] - out[index]
        total_floor = total_floor + out[index]
    end
    local leftover = avail - total_floor
    -- table.sort is not stable, so the comparator breaks ties itself,
    -- to keep them going to the lower index every time.
    local indices = {}
    for index = 1, n do
        indices[index] = index
    end
    table.sort(indices, function(a, b)
        if fractions[a] ~= fractions[b] then
            return fractions[a] > fractions[b]
        else
            return a < b
        end
    end)
    for i = 1, leftover do
        out[indices[i]] = out[indices[i]] + 1
    end
    return out
end

return CandidateWidths
