-- Widths for the suggestion boxes: each in proportion to its word, so a
-- long word gets room and short ones give theirs up, but none narrower
-- than MIN_SHARE of an equal share. Spare room is shared out evenly.
local CandidateWidths = {
    MIN_SHARE = 0.6,
}

-- wants: the width each box would like (its word and padding); avail:
-- the width the boxes share. Returns whole-pixel widths summing to avail.
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
    local out, used = {}, 0
    for index = 1, n - 1 do
        out[index] = math.floor(widths[index] + 0.5)
        used = used + out[index]
    end
    out[n] = avail - used
    return out
end

return CandidateWidths
