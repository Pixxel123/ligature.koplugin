local T = require("helper")
local it = T.it

local WordDelete = T.load("word_delete")

-- One entry per character, as KOReader's InputText keeps its text.
local function chars(text)
    local list = {}
    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        list[#list + 1] = char
    end
    return list
end

-- The boundaries for text with the cursor at its end.
local function atEnd(text, max)
    local list = chars(text)
    return WordDelete.boundaries(list, #list + 1, max)
end

local function same(actual, expected)
    T.eq(#actual, #expected, "count")
    for index, value in ipairs(expected) do
        T.eq(actual[index], value, "boundary " .. index)
    end
end

it("steps back one word at a time", function()
    same(atEnd("hello world"), { 7, 1 })
end)

it("counts the spaces after a word as part of it", function()
    same(atEnd("hello "), { 1 })
    same(atEnd("one  two   "), { 6, 1 })
end)

it("stops at the start of the line", function()
    same(atEnd("ab\ncd ef"), { 7, 4 })
    same(atEnd("ab\n"), {})
end)

it("has nothing to delete at the start of the text", function()
    same(WordDelete.boundaries(chars("hello"), 1), {})
end)

it("keeps punctuation with its word", function()
    same(atEnd("Hi, there."), { 5, 1 })
end)

it("steps back from a cursor inside the text", function()
    same(WordDelete.boundaries(chars("hello world"), 6), { 1 })
end)

it("reaches back at most max words", function()
    same(atEnd("a b c", 2), { 5, 3 })
end)

it("counts one word per key width after the first step", function()
    T.eq(WordDelete.count(0, 100, 5), 0)
    T.eq(WordDelete.count(39, 100, 5), 0)
    T.eq(WordDelete.count(40, 100, 5), 1)
    T.eq(WordDelete.count(139, 100, 5), 1)
    T.eq(WordDelete.count(140, 100, 5), 2)
    T.eq(WordDelete.count(1000, 100, 3), 3, "capped")
    T.eq(WordDelete.count(-50, 100, 3), 0, "slid right")
    T.eq(WordDelete.count(50, 0, 3), 0, "no key width")
end)

it("treats a cursor past the end as at the end", function()
    same(WordDelete.boundaries(chars("hi "), 10), { 1 })
end)
