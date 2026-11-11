return function(ue, ui, canvas, unit, dpi, art)
    local widget = "/Script/UMG.Widget:"
    local transitions = {
        equip = { .22, 23 }, raise = { .20, 19 }, lower = { .18, -15 },
        frame = { .19, 0 }, stow = { .16, 24 },
    }
    local pulse = {
        lens = "lens", aperture = "aperture", af_lock = "af", af_miss = "af", focus = "focus",
        mode = "mode", walk = "walk", dof = "dof", frame = "frame", shutter = "shoot",
        raise = "finder", lower = "finder", stow = "stow", saved = "shoot",
    }
    local transition, lensTurn, focusPulse, shutter, notice
    local scale = unit / dpi

    local function opacity(element, alpha)
        ue.call(widget .. "SetRenderOpacity", element, alpha)
    end

    local function offset(element, x, y)
        ue.call(widget .. "SetRenderTranslation", element, { X = x, Y = y })
    end

    function ui.setNotice(message, now)
        if not message then
            opacity(ui.notice, 0)
            notice = nil
            return
        end
        ui.status:SetText(FText(message))
        opacity(ui.notice, 1)
        notice = now
    end

    function ui.playEffect(effect, now, direction)
        local id = pulse[effect]
        if id then ui.pulseControl(id, now) end
        local params = transitions[effect]
        if params then transition = { now, params[1], params[2], effect == "stow" } end
        if effect == "lens" then lensTurn = { now, direction or 1 } end
        if (effect == "af_lock" or effect == "af_miss") and ui.focusRing then
            local locked = effect == "af_lock"
            ui.focusRing:SetColorAndOpacity(locked and { R = .70, G = .91, B = .62, A = 1 }
                or { R = .94, G = .61, B = .34, A = 1 })
            focusPulse = now
        end
        if effect == "shutter" and ui.curtain then
            shutter = now
            ue.call(widget .. "SetVisibility", ui.curtain, 3)
        end
        ui.tickEffects(now)
    end

    function ui.tickEffects(now)
        ui.tickControls(now)
        if ui.tickMeter then ui.tickMeter(now) end
        if ui.tickCameraArt then ui.tickCameraArt(now) end
        if transition then
            local t = math.min(1, math.max(0, (now - transition[1]) / transition[2]))
            local remain = (1 - t) ^ 3
            local amount = transition[4] and 1 - remain or remain
            opacity(canvas, 1 - amount)
            offset(canvas, 0, amount * transition[3] * scale)
            if t == 1 then transition = nil end
        end
        if lensTurn then
            local t = math.min(1, math.max(0, (now - lensTurn[1]) / .23))
            local bump = math.sin(t * math.pi) * (1 - t)
            ue.call(widget .. "SetRenderTransformAngle", art or ui.lens, 9 * lensTurn[2] * bump)
            if t == 1 then lensTurn = nil end
        end
        if focusPulse then
            local t = math.min(1, math.max(0, (now - focusPulse) / .54))
            local idle = ui.focusIdleOpacity
            opacity(ui.focusRing, idle + (1 - idle) * (1 - t) ^ 1.4)
            local size = 1 + .24 * (1 - t) ^ 2
            ue.call(widget .. "SetRenderScale", ui.focusRing, { X = size, Y = size })
            if t == 1 then
                ui.focusRing:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = 1 })
                focusPulse = nil
            end
        end
        if shutter then
            local t = math.min(1, math.max(0, (now - shutter) / .15))
            local open = t < .12 and (.24 * (1 - t / .12)) or math.max(0, (t - .40) / .60)
            offset(ui.topCurtain, 0, -open * ui.curtainTravel)
            offset(ui.bottomCurtain, 0, open * ui.curtainTravel)
            if t == 1 then
                ue.call(widget .. "SetVisibility", ui.curtain, 2)
                shutter = nil
            end
        end
        if notice then
            local elapsed = now - notice
            opacity(ui.notice, math.max(0, 1 - math.max(0, elapsed - 1.30) / .36))
            if elapsed >= 1.66 then notice = nil end
        end
    end
end
