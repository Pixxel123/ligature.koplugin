-- The words before the cursor that a slide left from ⌫ can delete: where
-- each step's deletion would start, and how many steps a slide covers.
local WordDelete = {
    -- The furthest a slide reaches back, in words.
    MAX_WORDS = 50,
    -- Travel, in key widths, before the first word is picked; after it,
    -- one more word per key width.
    FIRST_STEP = 0.4,
}

local SPACES = { [" "] = true, ["\t"] = true, ["\u{00A0}"] = true }

-- The char index each step's deletion starts at, nearest the cursor
-- first. charlist holds one character per entry, as KOReader's InputText
-- does; the cursor sits before charlist[charpos]. A step is a word and
-- the spaces after it, and no step crosses a newline: a slide deletes
-- within its line.
function WordDelete.boundaries(charlist, charpos, max)
    max = max or WordDelete.MAX_WORDS
    -- Clamp the cursor to the valid range; the index returned is used to
    -- delete real characters, so we never look past the end of charlist.
    charpos = math.min(charpos, #charlist + 1)
    local starts = {}
    local index = charpos - 1
    while index >= 1 and #starts < max and charlist[index] ~= "\n" do
        while index >= 1 and SPACES[charlist[index]] do
            index = index - 1
        end
        while index >= 1 and charlist[index] ~= "\n"
                and not SPACES[charlist[index]] do
            index = index - 1
        end
        starts[#starts + 1] = index + 1
    end
    return starts
end

-- How many words a slide distance pixels to the left picks, with keys
-- key_width wide and available words to pick from.
function WordDelete.count(distance, key_width, available)
    local first = WordDelete.FIRST_STEP * key_width
    if key_width <= 0 or distance < first then
        return 0
    end
    return math.min(available,
        math.floor((distance - first) / key_width) + 1)
end

return WordDelete
