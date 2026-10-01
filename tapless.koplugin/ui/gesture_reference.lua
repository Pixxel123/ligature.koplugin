-- The gesture reference: one page listing every Tapless gesture, drawn
-- ahead of time as an image (images/gesture_reference.png). It shows
-- once, the first time the keyboard opens with no languages left to
-- choose, and any time from Tools → Tapless → Gesture reference. A tap
-- anywhere, or Back, closes it; it takes every other gesture too, so
-- none reaches the keyboard underneath.
local GestureReference = {
    SETTING_KEY = "tapless_gesture_reference_shown",
}
GestureReference.__index = GestureReference

-- options: settings, ui_manager, screen, the KOReader widget classes
-- (input_container, frame_container, center_container, image_widget),
-- geometry, blitbuffer, image (the page's path) and, on devices with
-- keys, back_keys (KOReader's Back key group).
function GestureReference:new(options)
    return setmetatable({
        settings = assert(options.settings),
        ui_manager = assert(options.ui_manager),
        screen = assert(options.screen),
        input_container = assert(options.input_container),
        frame_container = assert(options.frame_container),
        center_container = assert(options.center_container),
        image_widget = assert(options.image_widget),
        geometry = assert(options.geometry),
        blitbuffer = assert(options.blitbuffer),
        image = assert(options.image),
        back_keys = options.back_keys,
    }, self)
end

-- Whether the first-run showing is still to come.
function GestureReference:due()
    return not self.settings:isTrue(self.SETTING_KEY)
end

-- Shows the page if the first-run showing is still to come, and
-- remembers that it has been shown.
function GestureReference:showOnce()
    if not self:due() then
        return false
    end
    self.settings:saveSetting(self.SETTING_KEY, true)
    self:show()
    return true
end

-- Shows the page full screen, scaled to fit, on white.
function GestureReference:show()
    local w, h = self.screen:getWidth(), self.screen:getHeight()
    local view = self.input_container:new{
        dimen = self.geometry:new{ x = 0, y = 0, w = w, h = h },
        -- KOReader puts a widget that isn't modal below the modal ones,
        -- and the keyboard is modal.
        modal = true,
        self.frame_container:new{
            bordersize = 0,
            padding = 0,
            margin = 0,
            background = self.blitbuffer.COLOR_WHITE,
            self.center_container:new{
                dimen = self.geometry:new{ w = w, h = h },
                self.image_widget:new{
                    file = self.image,
                    width = w,
                    height = h,
                    scale_factor = 0,
                    file_do_cache = false,
                },
            },
        },
    }
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
    if self.back_keys then
        view.key_events = { TaplessCloseReference = { self.back_keys } }
        view.onTaplessCloseReference = close
    end
    ui_manager:show(view, "flashui")
    return view
end

return GestureReference
