-- Shows which words a slide from backspace will delete by inverting
-- their characters in the text box. Inverting the same rectangles again
-- restores them, which is how the highlight is cleared; a text box that
-- has been rebuilt since (any edit rebuilds it) has nothing to restore.
local TextHighlight = {}
TextHighlight.__index = TextHighlight

function TextHighlight:new(ui_manager, geometry)
    return setmetatable({
        ui_manager = assert(ui_manager),
        geometry = assert(geometry),
    }, self)
end

-- The widget holding the rendered text: InputText keeps a TextBoxWidget,
-- or a ScrollTextWidget around one.
local function textBox(inputbox)
    local widget = inputbox and inputbox.text_widget
    if widget and widget.text_widget then
        widget = widget.text_widget
    end
    return widget
end

-- The rectangles of chars first..last, relative to the text box, on the
-- lines in view.
local function rectsFor(box, first, last)
    if not (box and box._bb and box.vertical_string_list) then
        return {}
    end
    local lines = #box.vertical_string_list
    local rects
    if box.use_xtext and box._xtext then
        rects = box:getXtextHighlightRects(first, last, 1, lines)
    else
        rects = box:getNonXtextHighlightRects(first, last, 1, lines)
    end
    local height = box._bb:getHeight()
    local visible = {}
    for _, rect in ipairs(rects) do
        if rect.y >= 0 and rect.y + rect.h <= height then
            visible[#visible + 1] = rect
        end
    end
    return visible
end

-- Highlights chars first..last of keyboard.inputbox, replacing any
-- highlight shown; without first, only clears.
function TextHighlight:show(keyboard, first, last)
    local shown = keyboard.swype_mvp_text_highlight
    if shown and shown.first == first and shown.last == last then
        return
    end
    local current = textBox(keyboard.inputbox)
    local changed = {}
    keyboard.swype_mvp_text_highlight = nil
    if shown and shown.box == current and current._bb then
        self:_invert(current, shown.rects, changed)
    end
    if first and last and last >= first and current then
        local rects = rectsFor(current, first, last)
        self:_invert(current, rects, changed)
        keyboard.swype_mvp_text_highlight = { box = current, rects = rects,
            first = first, last = last }
    end
    self:_refresh(current, changed)
end

function TextHighlight:clear(keyboard)
    self:show(keyboard, nil, nil)
end

function TextHighlight:_invert(box, rects, changed)
    for _, rect in ipairs(rects) do
        box._bb:invertRect(rect.x, rect.y, rect.w, rect.h)
        changed[#changed + 1] = rect
    end
end

-- Puts the changed text box on screen, refreshing only the rectangles
-- that changed, with the quick e-ink mode used while a finger moves.
function TextHighlight:_refresh(box, changed)
    local dimen = box and box.dimen
    if #changed == 0 or not (dimen and dimen.x) then
        return
    end
    self.ui_manager:widgetRepaint(box, dimen.x, dimen.y)
    for _, rect in ipairs(changed) do
        self.ui_manager:setDirty(nil, "fast", self.geometry:new{
            x = dimen.x + rect.x, y = dimen.y + rect.y,
            w = rect.w, h = rect.h,
        })
    end
end

return TextHighlight
