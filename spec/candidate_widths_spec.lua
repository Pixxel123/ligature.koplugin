local T = require("helper")
local it = T.it

local CandidateWidths = T.load("candidate_widths")

local function sum(list)
    local total = 0
    for _, value in ipairs(list) do total = total + value end
    return total
end

it("gives words of one length equal boxes", function()
    local widths = CandidateWidths.compute({ 50, 50, 50, 50 }, 400)
    for _, width in ipairs(widths) do T.eq(width, 100) end
end)

it("lets a long word take room from short ones", function()
    local widths = CandidateWidths.compute({ 300, 50, 50, 50 }, 400)
    T.eq(widths[1], 220)
    T.eq(widths[2], 60, "0.6 of an equal share")
    T.eq(widths[4], 60)
end)

it("shares spare room out evenly", function()
    local widths = CandidateWidths.compute({ 120, 40, 40, 40 }, 400)
    T.eq(widths[1], 145)
    T.eq(widths[2], 85)
end)

it("takes a different minimum share", function()
    local widths = CandidateWidths.compute({ 400, 10, 10, 10 }, 400, 0.4)
    T.eq(widths[2], 40)
    T.eq(widths[1], 280)
end)

it("gives equal wants at avail 402 widths differing by at most 1 px", function()
    local widths = CandidateWidths.compute({ 90, 90, 90, 90 }, 402)
    local max_w = math.max(widths[1], widths[2], widths[3], widths[4])
    local min_w = math.min(widths[1], widths[2], widths[3], widths[4])
    T.truthy(max_w - min_w <= 1, "max - min is " .. (max_w - min_w))
end)

it("keeps empty slots above the minimum", function()
    local widths = CandidateWidths.compute({ 18, 0, 0, 0 }, 30)
    local min_width = math.floor(0.6 * 30 / 4)
    for _, width in ipairs(widths) do
        T.truthy(width >= min_width, "width " .. width .. " >= " .. min_width)
    end
end)

it("always fills the row with whole pixels", function()
    for seed = 1, 200 do
        local wants, n = {}, 1 + seed % 4
        for index = 1, n do
            wants[index] = (seed + index) % 3 == 0 and 0 or (seed * 37 * index) % 331
        end
        local avail = 150 + (seed * 13) % 500
        local widths = CandidateWidths.compute(wants, avail)
        T.eq(sum(widths), avail, "sum for seed " .. seed)
        local min_floor = math.floor(0.6 * avail / n)
        for _, width in ipairs(widths) do
            T.eq(width, math.floor(width), "whole pixels")
            T.truthy(width >= min_floor,
                "minimum for seed " .. seed)
        end
    end
end)

it("has no boxes for no words", function()
    T.eq(#CandidateWidths.compute({}, 400), 0)
end)
