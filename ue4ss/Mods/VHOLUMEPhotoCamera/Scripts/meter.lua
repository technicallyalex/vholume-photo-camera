return function(ue, pose, log)
    local meter = {}
    local rendering = "/Script/Engine.Default__KismetRenderingLibrary"
    local capturePath = "/Script/Engine.SceneCaptureComponent2D:"
    local destroy = "/Script/Engine.Actor:K2_DestroyActor"

    function meter.release(active)
        local actor = active.meterActor
        active.meterActor, active.meterCapture, active.meterTarget = nil, nil, nil
        active.sceneEV, active.meterAt = nil, nil
        if ue.valid(actor) then ue.call(destroy, actor) end
    end

    local function sample(active)
        local location, rotation = pose(active)
        if not ue.valid(active.meterActor) then
            local actor = active.pawn:GetWorld():SpawnActor(ue.object("/Script/Engine.SceneCapture2D"), location, rotation)
            active.meterActor = actor
            assert(ue.valid(actor), "Cannot create meter capture")
            local capture = ue.call("/Script/Engine.Actor:GetComponentByClass", actor,
                ue.object("/Script/Engine.SceneCaptureComponent2D"))
            assert(ue.valid(capture), "Meter capture has no component")
            active.meterCapture = capture
            capture.bCaptureEveryFrame = false
            capture.bCaptureOnMovement = false
            capture.bAlwaysPersistRenderingState = false
            capture.CaptureSource = 0 -- SCS_SceneColorHDR, linear scene color before grading
            local pp = capture.PostProcessSettings
            pp.bOverride_AutoExposureMethod = true
            pp.bOverride_AutoExposureApplyPhysicalCameraExposure = true
            pp.bOverride_AutoExposureBias = true
            pp.AutoExposureMethod = 2
            pp.AutoExposureApplyPhysicalCameraExposure = false
            pp.AutoExposureBias = 0
            capture.PostProcessBlendWeight = 1
            ue.call("/Script/Engine.SceneCaptureComponent:HideActorComponents", capture, active.pawn, true)
        end
        local capture = active.meterCapture
        local ratio = active.rect.w / active.rect.h
        local w, h = math.max(8, math.floor(24 * math.min(1, ratio) + .5)),
            math.max(8, math.floor(24 * math.min(1, 1 / ratio) + .5))
        if not ue.valid(active.meterTarget) or active.meterWidth ~= w or active.meterHeight ~= h then
            local target = ue.object(rendering):CreateRenderTarget2D(active.pc, w, h, 6,
                {R=0,G=0,B=0,A=1}, false, false) -- RTF_RGBA16f
            assert(ue.valid(target), "Cannot allocate HDR meter target")
            capture.TextureTarget = target
            active.meterTarget, active.meterWidth, active.meterHeight = target, w, h
        end
        local tangent = math.tan(math.rad(active.lens.FieldOfView) / 2) * active.rect.w / active.rect.fullWidth
        capture.FOVAngle = math.deg(2 * math.atan(tangent * math.max(1, 1 / ratio)))
        ue.call("/Script/Engine.Actor:K2_SetActorLocationAndRotation", active.meterActor,
            location, rotation, false, {}, true)
        ue.call(capturePath .. "CaptureScene", capture)

        local pixels = {}
        if not ue.object(rendering):ReadRenderTargetRaw(active.pc, active.meterTarget, pixels, false) then return end
        local weighted, weights = 0, 0
        for y = 1, h do
            for x = 1, w do
                local pixel = pixels[(y - 1) * w + x]
                if pixel then
                    if type(pixel) == "userdata" then pixel = pixel:get() end
                    local light = .2126 * pixel.R + .7152 * pixel.G + .0722 * pixel.B
                    if light > 0 and light < math.huge then
                        local dx, dy = (2*x-1)/w-1, (2*y-1)/h-1
                        local weight = 1 + 3 * math.max(0, 1 - dx*dx - dy*dy)
                        weighted = weighted + weight * math.log(math.max(1e-6, light), 2)
                        weights = weights + weight
                    end
                end
            end
        end
        if weights > 0 then return math.max(-10, math.min(22, weighted / weights - math.log(.18, 2))) end
    end

    function meter.tick(active, now)
        if active.meterFailed or now < (active.meterAt or 0) then return false end
        active.meterAt = now + .55
        local ok, value = pcall(sample, active)
        if not ok then
            log("Exposure meter unavailable: " .. tostring(value))
            meter.release(active)
            active.meterFailed = true
            return true
        end
        if value and active.sceneEV then value = active.sceneEV + .72 * (value - active.sceneEV) end
        if value and active.sceneEV and math.abs(value - active.sceneEV) < .04 then return false end
        local changed = value ~= active.sceneEV
        active.sceneEV = value
        return changed
    end
    return meter
end
