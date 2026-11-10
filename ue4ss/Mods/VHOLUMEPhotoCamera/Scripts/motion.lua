return function(ue, pose)
    local motion = {}
    local actorPath = "/Script/Engine.Actor:"
    local scenePath = "/Script/Engine.SceneCaptureComponent2D:"
    local captureClass = "/Script/Engine.SceneCaptureComponent2D"
    local rendering = "/Script/Engine.Default__KismetRenderingLibrary"
    local zero, uvSize = {X=0,Y=0}, {X=1,Y=1}
    local black = {R=0,G=0,B=0,A=1}
    local identity = {
        Rotation={X=0,Y=0,Z=0,W=1}, Translation={X=0,Y=0,Z=0}, Scale3D={X=1,Y=1,Z=1},
    }
    local sampleInterval = 1 / 45

    function motion.dimensions(rect)
        local units = math.min(rect.w / rect.columns, math.floor(3840 / math.max(rect.columns,rect.rows)))
        return units * rect.columns, units * rect.rows
    end

    local function target(shot, format)
        local rt = ue.object(rendering):CreateRenderTarget2D(
            shot.owner.pc,shot.width,shot.height,format,black,false,false)
        assert(ue.valid(rt), "Cannot allocate exposure render target")
        return rt
    end

    local function sample(shot, location, rotation)
        ue.call(actorPath.."K2_SetActorLocationAndRotation",shot.actor,location,rotation,false,{},true)
        ue.call(scenePath.."CaptureScene",shot.capture)
        shot.samples = (shot.samples or 0) + 1
    end

    local function draw(shot, source, destination, weight, blend)
        local lib = ue.object(rendering)
        local out = {}
        -- Use one table for all out params. UE4SS writes Canvas by name
        -- and copies the render context struct's fields into that table.
        lib:BeginDrawCanvasToRenderTarget(shot.owner.pc,destination,out,out,out)
        local ok, err = pcall(function()
            assert(ue.valid(out.Canvas), "Cannot open exposure render canvas")
            ue.call("/Script/Engine.Canvas:K2_DrawTexture",out.Canvas,source,zero,
                {X=shot.width,Y=shot.height},zero,uvSize,{R=weight,G=weight,B=weight,A=1},blend,0,zero)
        end)
        lib:EndDrawCanvasToRenderTarget(shot.owner.pc,out)
        if not ok then error(err) end
    end

    function motion.start(shot, rect)
        local active = shot.owner
        local location, rotation = pose(active)
        shot.actor = active.pawn:GetWorld():SpawnActor(ue.object("/Script/Engine.SceneCapture2D"),location,rotation)
        assert(ue.valid(shot.actor), "Cannot create exposure camera")
        shot.capture = ue.call(actorPath.."GetComponentByClass",shot.actor,ue.object(captureClass))
        assert(ue.valid(shot.capture), "Exposure camera has no capture component")
        shot.capture.bCaptureEveryFrame = false
        shot.capture.bCaptureOnMovement = false
        shot.capture.bAlwaysPersistRenderingState = true
        shot.capture.CaptureSource = 9 -- SCS_FinalToneCurveHDR, linear output with film look
        shot.capture.PostProcessSettings = active.lens.PostProcessSettings
        shot.capture.PostProcessBlendWeight = 1
        local pp = shot.capture.PostProcessSettings
        -- The exposure itself integrates motion. Avoid blurring each sample twice.
        pp.bOverride_MotionBlurAmount = true
        pp.MotionBlurAmount = 0
        local tangent = math.tan(math.rad(active.lens.FieldOfView) / 2) * rect.w / rect.fullWidth
        shot.capture.FOVAngle = math.deg(2 * math.atan(tangent * math.max(1,rect.h/rect.w)))
        ue.call("/Script/Engine.SceneCaptureComponent:HideActorComponents",shot.capture,active.pawn,true)
        shot.sampleTarget = target(shot,6) -- RTF_RGBA16f
        shot.capture.TextureTarget = shot.sampleTarget
        shot.sumTarget = target(shot,6)
        -- A dormant component keeps the accumulator reachable by Unreal's GC.
        local holder = ue.call(actorPath.."AddComponentByClass",shot.actor,
            ue.object(captureClass),true,identity,true)
        assert(ue.valid(holder), "Cannot retain exposure render target")
        holder.bCaptureEveryFrame = false
        holder.bCaptureOnMovement = false
        holder.TextureTarget = shot.sumTarget
        ue.call(actorPath.."FinishAddComponent",shot.actor,holder,true,identity)
        ue.object(rendering):ClearRenderTarget2D(active.pc,shot.sumTarget,black)
        sample(shot,location,rotation)
    end

    function motion.tick(shot, now)
        local elapsed = math.min(shot.duration,math.max(0,now - shot.startedAt))
        local dt = elapsed - shot.accumulated
        if dt > 0 and (elapsed == shot.duration or dt >= sampleInterval) then
            draw(shot,shot.sampleTarget,shot.sumTarget,dt/shot.duration,3) -- BLEND_Additive
            shot.accumulated = elapsed
            if elapsed < shot.duration then sample(shot,pose(shot.owner)) end
        end
        return elapsed == shot.duration, shot.duration - elapsed
    end

    function motion.save(shot)
        shot.outputTarget = target(shot,3) -- RTF_RGBA8_SRGB
        draw(shot,shot.sumTarget,shot.outputTarget,1,0)
        local dir, file = shot.partPath:match("^(.*)[/\\]([^/\\]+)$")
        assert(dir and file, "Invalid exposure output path")
        ue.object(rendering):ExportRenderTarget(shot.owner.pc,shot.outputTarget,dir,file)
    end

    function motion.release(shot)
        if ue.valid(shot.actor) then ue.call(actorPath.."K2_DestroyActor",shot.actor) end
        local lib = ue.object(rendering)
        for _,rt in pairs({shot.sampleTarget,shot.sumTarget,shot.outputTarget}) do
            if ue.valid(rt) then lib:ReleaseRenderTarget2D(rt) end
        end
        shot.actor,shot.capture,shot.sampleTarget,shot.sumTarget,shot.outputTarget = nil,nil,nil,nil,nil
    end

    return motion
end
