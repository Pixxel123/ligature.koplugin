local GestureController = {}
GestureController.__index = GestureController

function GestureController:new(trace_collector, ui_manager, time_api, geometry)
    return setmetatable({
        trace_collector = assert(trace_collector),
        ui_manager = assert(ui_manager),
        time = assert(time_api),
        geometry = assert(geometry),
    }, self)
end

function GestureController:reset(keyboard, keep_prefetch)
    if keyboard.swype_mvp_trace then
        keyboard:_swypeClearTracePixels()
    end
    if not keep_prefetch then
        keyboard:_swypeCancelBucketPrefetch()
    end
    keyboard.swype_mvp_trace_generation =
        (keyboard.swype_mvp_trace_generation or 0) + 1
    keyboard.swype_mvp_trace = nil
    keyboard.swype_mvp_last_point_time = nil
end

function GestureController:scheduleFinalize(keyboard)
    keyboard.swype_mvp_trace_generation =
        (keyboard.swype_mvp_trace_generation or 0) + 1
    local generation = keyboard.swype_mvp_trace_generation
    self.ui_manager:scheduleIn(0.4, function()
        if keyboard.swype_mvp_closed
                or keyboard.swype_mvp_trace_generation ~= generation
                or not keyboard.swype_mvp_trace
                or not keyboard.swype_mvp_last_point_time
                or self.time.now() - keyboard.swype_mvp_last_point_time
                    < self.time.ms(350) then
            return
        end
        self:finalizeTrace(keyboard)
    end)
end

function GestureController:addPoint(keyboard, pos)
    if not pos or not pos.x or not pos.y then
        return
    end
    local now = self.time.now()
    if keyboard.swype_mvp_trace and keyboard.swype_mvp_last_point_time
            and now - keyboard.swype_mvp_last_point_time > self.time.ms(500) then
        self:reset(keyboard)
    end
    keyboard.swype_mvp_last_point_time = now
    local letter, key
    if keyboard.swype_mvp_trace then
        letter, key = keyboard:_swypeKeyAt(pos)
    else
        keyboard.swype_mvp_trace = self.trace_collector:newTrace()
        letter, key = keyboard:_swypeStartKeyAt(pos)
    end
    local result = self.trace_collector:addPoint(
        keyboard.swype_mvp_trace, pos, letter, key and key.dimen, now)
    if result and result.point_added then
        keyboard:_swypeDrawTraceSegment(result.previous_point, result.point)
    end
    if not letter then
        self:scheduleFinalize(keyboard)
        return
    end
    if result and result.letter_rejected then
        self:scheduleFinalize(keyboard)
        return
    end
    if result and result.letter_added then
        keyboard:_swypeScheduleBucketPrefetch()
    end
    self:scheduleFinalize(keyboard)
end

function GestureController:addKeyCenter(keyboard, key)
    if key and key.dimen then
        self:addPoint(keyboard, self.geometry:new{
            x = key.dimen.x + math.floor(key.dimen.w / 2),
            y = key.dimen.y + math.floor(key.dimen.h / 2),
            w = 1,
            h = 1,
        })
    end
end

-- The swipe of points read again with each point moved by shift (pixels,
-- the learned touch offset): its letters and trace as recognition should
-- see them, { signature, trace_info }, or nil when that leaves fewer than
-- two letters. A start the shift takes off every key stays where the
-- finger touched, so the first letter is not lost.
function GestureController:_shiftedTrace(keyboard, points, shift, trace_info)
    local trace = self.trace_collector:newTrace()
    for index, point in ipairs(points) do
        local pos = { x = math.floor(point.x + shift.x + 0.5),
            y = math.floor(point.y + shift.y + 0.5) }
        local letter, key
        if index == 1 then
            letter, key = keyboard:_swypeStartKeyAt(pos)
            if not letter then
                pos = { x = point.x, y = point.y }
                letter, key = keyboard:_swypeStartKeyAt(pos)
            end
        else
            letter, key = keyboard:_swypeKeyAt(pos)
        end
        self.trace_collector:addPoint(trace, pos, letter, key and key.dimen,
            point.time)
    end
    local snapshot = self.trace_collector:snapshot(trace)
    if #snapshot.signature < 2 then
        return nil
    end
    return {
        signature = snapshot.signature,
        trace_info = {
            letter_points = snapshot.letter_points,
            endpoint_pos = snapshot.endpoint_pos,
            points = snapshot.points,
            observations = snapshot.observations,
            previous_word = trace_info.previous_word,
            released = trace_info.released,
        },
    }
end

function GestureController:finalizeTrace(keyboard, released)
    if not keyboard.swype_mvp_trace then
        return false
    end
    local snapshot = self.trace_collector:snapshot(keyboard.swype_mvp_trace)
    local trace_info = {
        letter_points = snapshot.letter_points,
        endpoint_pos = snapshot.endpoint_pos,
        points = snapshot.points,
        observations = snapshot.observations,
        previous_word = keyboard:_swypeGetPreviousWord(),
        released = released,
    }
    -- The trace stays as the finger went: taps, slips and number-row
    -- starts are told apart on it. Only recognition reads the swipe
    -- shifted by the learned touch offset, from trace_info.recognition;
    -- trace_info.touch_keys are the letter keys it was worked out for.
    if #snapshot.signature >= 2 and keyboard._swypeTouchShift then
        local shift, keys = keyboard:_swypeTouchShift()
        trace_info.touch_keys = keys
        if shift then
            trace_info.recognition = self:_shiftedTrace(keyboard,
                snapshot.points, shift, trace_info)
        end
    end
    self:reset(keyboard, true)
    local finalized = keyboard:_swypeFinalizeSignature(
        snapshot.signature, trace_info)
    keyboard:_swypeCancelBucketPrefetch()
    return finalized
end

function GestureController:onPan(keyboard, ges)
    if not keyboard:isSwypeMvpEnabled() then
        self:reset(keyboard)
        return false
    end
    if not keyboard.swype_mvp_trace then
        local start_pos = ges and ges.start_pos
        local start_letter = keyboard:_swypeStartKeyAt(start_pos)
        if not start_letter then
            return false
        end
        keyboard:_swypeCommitPendingContext()
        keyboard:_swypeClearCandidateState()
        self:addPoint(keyboard, start_pos)
    end
    self:addPoint(keyboard, ges and ges.pos)
    return true
end

function GestureController:onPathRelease(keyboard, ges, source_key)
    if not keyboard:isSwypeMvpEnabled() then
        self:reset(keyboard)
        return false
    end
    local start_pos
    if not keyboard.swype_mvp_trace then
        start_pos = ges and (ges.start_pos or ges.pos)
        if start_pos then
            local start_letter = keyboard:_swypeStartKeyAt(start_pos)
            if not start_letter then
                return false
            end
        elseif not source_key then
            return false
        end
    end
    keyboard:_swypeCommitPendingContext()
    keyboard:_swypeClearCandidateState()
    if not keyboard.swype_mvp_trace then
        if start_pos then
            self:addPoint(keyboard, start_pos)
        else
            self:addKeyCenter(keyboard, source_key)
        end
    end

    local end_pos = ges and (ges.end_pos or ges.pos)
    self:addPoint(keyboard, end_pos)
    if not keyboard.swype_mvp_trace then
        self:addKeyCenter(keyboard, source_key)
    end
    return self:finalizeTrace(keyboard, true)
end

function GestureController:onPanRelease(keyboard, ges)
    if not keyboard:isSwypeMvpEnabled() then
        self:reset(keyboard)
        return false
    end
    if not keyboard.swype_mvp_trace then
        local start_pos = ges and ges.start_pos
        local start_letter = keyboard:_swypeStartKeyAt(start_pos)
        if not start_letter then
            return false
        end
        keyboard:_swypeCommitPendingContext()
        keyboard:_swypeClearCandidateState()
        self:addPoint(keyboard, start_pos)
    end
    if not keyboard.swype_mvp_trace then
        self:reset(keyboard)
        return false
    end
    self:addPoint(keyboard, ges and ges.pos)
    return self:finalizeTrace(keyboard, true)
end

return GestureController
