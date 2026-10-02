-- The gesture reference: one page listing every Ligature gesture, drawn
-- ahead of time as an image (images/gesture_reference.png). It opens from
-- the language picker's Show gestures button and from Tools → Ligature →
-- Gesture reference. A tap anywhere, or Back, closes it. It takes every
-- other gesture and key press too, so none reaches the keyboard or text
-- box underneath.
local GestureReference = {}
GestureReference.__index = GestureReference

-- options: ui_manager, screen, the KOReader widget classes
-- (input_container, frame_container, image_widget), geometry, blitbuffer,
-- image (the page's path) and back_keys, a function giving KOReader's
-- Back key group when the device has keys (asked each time the page
-- opens, as a keyboard can be plugged in later).
function GestureReference:new(options)
    return setmetatable({
        ui_manager = assert(options.ui_manager),
        screen = assert(options.screen),
        input_container = assert(options.input_container),
        frame_container = assert(options.frame_container),
        image_widget = assert(options.image_widget),
        geometry = assert(options.geometry),
        blitbuffer = assert(options.blitbuffer),
        image = assert(options.image),
        back_keys = options.back_keys,
    }, self)
end

function GestureReference:open()
    return self:show()
end

-- Shows the page full screen, scaled to fit, on white. It lays itself out
-- again when the screen's size changes, as after a rotation.
function GestureReference:show()
    local view = self.input_container:new{
        -- KOReader puts a widget that isn't modal below the modal ones,
        -- and the keyboard is modal.
        modal = true,
        covers_fullscreen = true,
    }
    local built_w, built_h
    local function build()
        built_w, built_h = self.screen:getWidth(), self.screen:getHeight()
        view.dimen = self.geometry:new{ x = 0, y = 0, w = built_w, h = built_h }
        view[1] = self.frame_container:new{
            bordersize = 0,
            padding = 0,
            margin = 0,
            background = self.blitbuffer.COLOR_WHITE,
            -- Given a width and height, it scales the page to fit and
            -- centres it.
            self.image_widget:new{
                file = self.image,
                width = built_w,
                height = built_h,
                scale_factor = 0,
                file_do_cache = false,
            },
        }
    end
    build()
    local paint = view.paintTo
    view.paintTo = function(widget, bb, x, y)
        if self.screen:getWidth() ~= built_w
                or self.screen:getHeight() ~= built_h then
            build()
        end
        return paint(widget, bb, x, y)
    end

    local ui_manager = self.ui_manager
    local function close()
        ui_manager:close(view, "flashui")
        return true
    end
    view.onGesture = function(_, ges)
        if ges and ges.ges == "tap" then
            close()
        end
        return true
    end
    local back = self.back_keys and self.back_keys()
    view.onKeyPress = function(_, key)
        if back and key and key.match and key:match(back) then
            close()
        end
        return true
    end
    view.onKeyRepeat = function() return true end
    view.onKeyRelease = function() return true end
    ui_manager:show(view, "flashui")
    return view
end

return GestureReference
