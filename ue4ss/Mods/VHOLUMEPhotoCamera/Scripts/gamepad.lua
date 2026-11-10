return function(ue, binds)
    local pad = { held = {}, pressed = {}, repeatAt = {}, repeating = {} }
    local keys = {
        view="Special_Left", lt="LeftTrigger", rt="RightTrigger",
        lb="LeftShoulder", rb="RightShoulder", walk="LeftThumbstick",
        a="FaceButton_Bottom", b="FaceButton_Right", x="FaceButton_Left", y="FaceButton_Top",
        left="DPad_Left", right="DPad_Right", up="DPad_Up", down="DPad_Down",
    }
    local directions = {left=true,right=true,up=true,down=true}

    function pad.poll(pc, now)
        pad.touched = false
        for id, name in pairs(keys) do
            local held = pc and ue.call("/Script/Engine.PlayerController:IsInputKeyDown", pc,
                binds.raw("Gamepad_" .. name)) or false
            local edge = held and not pad.held[id]
            pad.held[id], pad.pressed[id], pad.repeating[id] = held, edge, edge
            if edge then pad.touched = true end
            if directions[id] then
                if edge then
                    pad.repeatAt[id] = now + .34
                elseif not held then
                    pad.repeatAt[id] = nil
                elseif pad.repeatAt[id] and now >= pad.repeatAt[id] then
                    pad.repeating[id], pad.repeatAt[id] = true, now + .10
                end
            end
        end
    end

    function pad.layer()
        if pad.held.lb then return "exposure" end
        if pad.held.rb then return "focus" end
    end

    return pad
end
