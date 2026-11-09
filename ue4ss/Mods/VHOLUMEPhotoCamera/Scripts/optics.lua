return function(ue, system, pose, refresh, binds)
    local optics = { enabled = true, manual = false, aperture = 3, distance = 400 }
    local apertures = {1.0, 1.4, 2, 2.8, 4, 5.6, 8, 11, 16}
    local maxDistance = 100000 -- One kilometer is treated as infinity.
    local minDistance = 35
    local noColor = { R = 0, G = 0, B = 0, A = 0 }

    -- The installed UE 5.4 build's cinematic DOF profile. Affect only DOF
    -- while the optical finder is raised and blur is enabled.
    local quality = {
        {"r.DepthOfFieldQuality", 4},
        {"r.DOF.Gather.ResolutionDivisor", 1},
        {"r.DOF.Gather.AccumulatorQuality", 1},
        {"r.DOF.Gather.PostfilterMethod", 1},
        {"r.DOF.Gather.EnableBokehSettings", 1},
        {"r.DOF.Gather.RingCount", 5},
        {"r.DOF.Scatter.ForegroundCompositing", 1},
        {"r.DOF.Scatter.BackgroundCompositing", 2},
        {"r.DOF.Scatter.EnableBokehSettings", 1},
        {"r.DOF.Scatter.MaxSpriteRatio", 0.25},
        {"r.DOF.Recombine.Quality", 2},
        {"r.DOF.Recombine.EnableBokehSettings", 1},
        {"r.DOF.TemporalAAQuality", 1},
        {"r.DOF.Kernel.MaxForegroundRadius", 0.025},
        {"r.DOF.Kernel.MaxBackgroundRadius", 0.025},
    }

    local function value(name, target)
        if math.type(target) == "integer" then return system():GetConsoleVariableIntValue(name) end
        return system():GetConsoleVariableFloatValue(name)
    end

    local function set(pc, name, number)
        system():ExecuteConsoleCommand(pc, string.format("%s %.9g", name, number), pc)
    end

    local function setQuality(active)
        if active.dofSettings then return end
        active.dofSettings = {}
        for _, setting in ipairs(quality) do
            local name, target = setting[1], setting[2]
            local before = value(name, target)
            if math.abs(before - target) > 0.000001 then
                active.dofSettings[#active.dofSettings + 1] = {name, before, target}
                set(active.pc, name, target)
            end
        end
    end

    function optics.release(active, pc)
        if active.dofSettings and ue.valid(pc) then
            for _, setting in ipairs(active.dofSettings) do
                local name, before, target = setting[1], setting[2], setting[3]
                if math.abs(value(name, target) - target) < 0.000001 then set(pc, name, before) end
            end
        end
        active.dofSettings = nil
    end

    local function clampDistance(active, distance)
        local closest = math.max(minDistance, active.focalLength * .12)
        return math.max(closest, math.min(maxDistance, distance))
    end

    local function traceSubject(active)
        local start, rotation = pose(active)
        local yaw, pitch = math.rad(rotation.Yaw), math.rad(rotation.Pitch)
        local horizontal = math.cos(pitch) * maxDistance
        local finish = {
            X = start.X + math.cos(yaw) * horizontal,
            Y = start.Y + math.sin(yaw) * horizontal,
            Z = start.Z + math.sin(pitch) * maxDistance,
        }
        local hit = {}
        if system():LineTraceSingle(active.pawn, start, finish, 0, true, {active.camera},
                0, hit, true, noColor, noColor, 0) then
            return hit.Distance
        end
    end

    local function sampleSubject(active)
        active.subjectDistance = traceSubject(active)
        return active.subjectDistance
    end

    function optics.autofocus(active)
        if not active.raised then return end
        local subject = sampleSubject(active)
        if subject then
            active.focusGoal = nil
            optics.distance = clampDistance(active, subject)
            optics.enabled, optics.manual, optics.locked = true, true, true
            optics.apply(active)
        end
        refresh(active)
        return subject ~= nil
    end

    function optics.focusIndicator(active)
        local subject = active.subjectDistance
        if not subject then return 0 end
        local focalLength = active.focalLength
        local subjectMm = math.max(focalLength + 1, subject * 10)
        local focusMm = optics.distance * 10
        -- Use a fixed reference aperture so the indicator stays sensitive when stopped down.
        local errorMm = focalLength ^ 2 * (1 / subjectMm - 1 / focusMm)
            / (2.8 * (1 - focalLength / focusMm))
        -- Limit the distance tolerance as well as the blur, especially on wide lenses.
        local relativeError = math.abs(math.log(subjectMm / focusMm))
        if math.abs(errorMm) <= 0.0015 and relativeError <= 0.002 then return 2 end
        return errorMm < 0 and 3 or 1
    end

    function optics.apply(active)
        if not active.raised then return end
        optics.distance = clampDistance(active, optics.distance)
        if active.focusGoal then active.focusGoal = clampDistance(active, active.focusGoal) end
        local pp = active.lens.PostProcessSettings
        -- Zero focus distance disables cinematic DOF on the photo camera.
        pp.bOverride_DepthOfFieldFocalDistance = true
        pp.DepthOfFieldFocalDistance = optics.enabled and optics.distance or 0
        if optics.enabled then
            setQuality(active)
            pp.bOverride_DepthOfFieldFstop = true
            pp.DepthOfFieldFstop = apertures[optics.aperture]
            pp.bOverride_DepthOfFieldMinFstop = true
            pp.DepthOfFieldMinFstop = apertures[1]
            pp.bOverride_DepthOfFieldBladeCount = true
            pp.DepthOfFieldBladeCount = 9
            pp.bOverride_DepthOfFieldSensorWidth = true
            pp.DepthOfFieldSensorWidth = active.rect.filmWidth * active.rect.fullWidth / active.rect.w
        else
            optics.release(active, active.pc)
        end
        active.lens.PostProcessBlendWeight = 1
    end

    local function turnFocus(active, ticks, fine, now)
        local start = active.focusGoal or optics.distance
        local step = 0.04
        if fine then
            local focalLength = active.focalLength
            step = math.min(0.0012, 0.0008 * 2.8 * (start * 10 - focalLength) / focalLength ^ 2)
        end
        active.focusGoal = clampDistance(active, start * math.exp(ticks * step))
        active.focusUpdateAt = now
        optics.locked = false
        refresh(active)
    end

    local function animateFocus(active, now)
        local goal = active.focusGoal
        if not goal then return end
        local remaining = math.log(goal / optics.distance)
        local elapsed = math.max(0, now - active.focusUpdateAt)
        active.focusUpdateAt = now
        if math.abs(remaining) < 0.000001 then
            optics.distance, active.focusGoal = goal,nil
        else
            optics.distance = optics.distance * math.exp(remaining * (1 - math.exp(-elapsed / 0.035)))
        end
        if optics.enabled then
            active.lens.PostProcessSettings.DepthOfFieldFocalDistance = optics.distance
        end
        refresh(active)
    end

    local wheelAxis = binds.raw("MouseWheelAxis")

    local function wheelFocus(active, now)
        local method = "/Script/Engine.PlayerController:WasInputKeyJustPressed"
        local up = ue.call(method, active.pc, binds.key("focusFar"))
        local down = ue.call(method, active.pc, binds.key("focusNear"))
        local far, near = binds.name("focusFar"), binds.name("focusNear")
        local delta = 0
        if far:find("MouseScroll",1,true) or near:find("MouseScroll",1,true) then
            delta = ue.call("/Script/Engine.PlayerController:GetInputAnalogKeyState", active.pc, wheelAxis)
        end
        local wheel = math.abs(delta) >= .01 and (delta > 0 and "MouseScrollUp" or "MouseScrollDown")
        local previous = active.wheelAxis or 0
        active.wheelAxis = delta
        local ticks = 0
        if up ~= down then
            local direction = up and 1 or -1
            ticks = (up and far or near) == wheel and math.abs(delta) or 1
            ticks = ticks * direction
        elseif wheel and math.abs(previous) < 0.01 then
            ticks = (wheel == far and 1 or (wheel == near and -1 or 0)) * math.abs(delta)
        end
        if ticks ~= 0 then
            local fine = binds.isFine(active.pc)
            turnFocus(active, ticks, fine, now)
            return fine and "fine" or "focus"
        end
    end

    function optics.tick(active, now)
        if not active.raised then return end
        if now >= (active.subjectCheck or 0) then
            active.subjectCheck = now + 0.07
            local subject = sampleSubject(active)
            if not optics.manual then
                local distance = clampDistance(active, subject or maxDistance)
                if math.abs(optics.distance - distance) >= 0.1 then
                    optics.distance = distance
                    if optics.enabled then optics.apply(active) end
                end
            end
            refresh(active)
        end
        if optics.manual then
            animateFocus(active, now)
            return wheelFocus(active, now)
        end
    end

    function optics.toggle(active)
        if not active.raised then return end
        optics.enabled = not optics.enabled
        if optics.enabled and not optics.manual then
            optics.distance = clampDistance(active, sampleSubject(active) or maxDistance)
        end
        optics.apply(active)
        refresh(active)
    end

    function optics.toggleManual(active)
        if not active.raised then return end
        active.focusGoal = nil
        if not optics.enabled or optics.manual then
            optics.distance = clampDistance(active, sampleSubject(active) or maxDistance)
        end
        optics.manual = not optics.manual
        optics.locked = false
        active.wheelAxis = nil
        optics.enabled = true
        optics.apply(active)
        refresh(active)
    end

    function optics.stepAperture(active, direction)
        if not active.raised then return end
        local nextAperture = math.max(1, math.min(#apertures, optics.aperture + direction))
        if nextAperture == optics.aperture then return false end
        optics.aperture = nextAperture
        optics.apply(active)
        refresh(active)
        return true
    end

    local function meters(distance)
        if distance >= maxDistance then return "INF" end
        if distance < 1000 then return string.format("%.3f m", distance / 100) end
        return string.format("%.2f m", distance / 100)
    end

    function optics.readout(active)
        local mode = optics.locked and "AF-L " or (optics.manual and "MF " or "AF ")
        local aperture = string.format("f/%.1f", apertures[optics.aperture])
        local subject = active.subjectDistance
        return aperture, mode .. meters(optics.distance), subject and ("SUBJ " .. meters(subject)) or "NO TARGET"
    end

    return optics
end

