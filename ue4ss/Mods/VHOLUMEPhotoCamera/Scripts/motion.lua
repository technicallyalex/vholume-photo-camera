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
        if ue.valid(shot.rawCapture) then ue.call(scenePath.."CaptureScene",shot.rawCapture) end
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
        if shot.png==nil then shot.png=true end -- Earlier platform overlays produce PNG only.
        local active = shot.owner
        local location, rotation = pose(active)
        shot.actor = active.pawn:GetWorld():SpawnActor(ue.object("/Script/Engine.SceneCapture2D"),location,rotation)
        assert(ue.valid(shot.actor), "Cannot create exposure camera")
        shot.capture = ue.call(actorPath.."GetComponentByClass",shot.actor,ue.object(captureClass))
        assert(ue.valid(shot.capture), "Exposure camera has no capture component")
        shot.capture.bCaptureEveryFrame = false
        shot.capture.bCaptureOnMovement = false
        shot.capture.bAlwaysPersistRenderingState = true
        shot.capture.CaptureSource = shot.png and 9 or 8 -- Tone mapped PNG / untonemapped HDR
        shot.capture.PostProcessSettings = active.lens.PostProcessSettings
        shot.capture.PostProcessBlendWeight = 1
        local pp = shot.capture.PostProcessSettings
        -- The exposure itself integrates motion. Avoid blurring each sample twice.
        pp.bOverride_MotionBlurAmount = true
        pp.MotionBlurAmount = 0
        local function neutral(component)
            local raw = component.PostProcessSettings
            for _,field in ipairs({"ColorSaturation","ColorContrast","ColorGamma","ColorGain"}) do
                raw["bOverride_"..field]=true
                raw[field]={X=1,Y=1,Z=1,W=1}
            end
            raw.bOverride_ColorOffset=true;raw.ColorOffset={X=0,Y=0,Z=0,W=0}
            raw.bOverride_FilmGrainIntensity=true;raw.FilmGrainIntensity=0
            raw.bOverride_ColorGradingIntensity=true;raw.ColorGradingIntensity=0
        end
        if not shot.png then neutral(shot.capture) end
        local tangent = math.tan(math.rad(active.lens.FieldOfView) / 2) * rect.w / rect.fullWidth
        shot.capture.FOVAngle = math.deg(2 * math.atan(tangent * math.max(1,rect.h/rect.w)))
        ue.call("/Script/Engine.SceneCaptureComponent:HideActorComponents",shot.capture,active.pawn,true)
        shot.sampleTarget = target(shot,6) -- RTF_RGBA16f
        shot.capture.TextureTarget = shot.sampleTarget
        -- A dormant component keeps the accumulator reachable by Unreal's GC.
        local function retain(rt)
            local holder=ue.call(actorPath.."AddComponentByClass",shot.actor,ue.object(captureClass),false,identity,true)
            assert(ue.valid(holder),"Cannot retain photo render target")
            holder.bCaptureEveryFrame=false;holder.bCaptureOnMovement=false;holder.TextureTarget=rt
            ue.call(actorPath.."FinishAddComponent",shot.actor,holder,false,identity)
            return holder
        end
        if shot.duration>0 then
            shot.sumTarget=target(shot,6);retain(shot.sumTarget)
            ue.object(rendering):ClearRenderTarget2D(active.pc,shot.sumTarget,black)
        end
        if shot.png and shot.exr then
            shot.rawTarget=target(shot,6)
            shot.rawCapture=retain(shot.rawTarget)
            shot.rawCapture.bAlwaysPersistRenderingState=true
            shot.rawCapture.CaptureSource=8
            shot.rawCapture.FOVAngle=shot.capture.FOVAngle
            shot.rawCapture.PostProcessSettings=shot.capture.PostProcessSettings
            shot.rawCapture.PostProcessBlendWeight=1
            neutral(shot.rawCapture)
            ue.call("/Script/Engine.SceneCaptureComponent:HideActorComponents",shot.rawCapture,active.pawn,true)
            if shot.duration>0 then
                shot.rawSumTarget=target(shot,6);retain(shot.rawSumTarget)
                ue.object(rendering):ClearRenderTarget2D(active.pc,shot.rawSumTarget,black)
            end
        end
        sample(shot,location,rotation)
    end

    function motion.warmup(shot)
        sample(shot,pose(shot.owner))
    end

    function motion.tick(shot, now)
        local elapsed = math.min(shot.duration,math.max(0,now - shot.startedAt))
        local dt = elapsed - shot.accumulated
        if dt > 0 and (elapsed == shot.duration or dt >= sampleInterval) then
            draw(shot,shot.sampleTarget,shot.sumTarget,dt/shot.duration,3) -- BLEND_Additive
            if shot.rawTarget then draw(shot,shot.rawTarget,shot.rawSumTarget,dt/shot.duration,3) end
            shot.accumulated = elapsed
            if elapsed < shot.duration then sample(shot,pose(shot.owner)) end
        end
        return elapsed == shot.duration, shot.duration - elapsed
    end

    function motion.save(shot)
        local source=shot.sumTarget or shot.sampleTarget
        if shot.png then
            shot.outputTarget = target(shot,3) -- RTF_RGBA8_SRGB
            draw(shot,source,shot.outputTarget,1,0)
            local dir,file=shot.partPath:match("^(.*)[/\\]([^/\\]+)$")
            assert(dir and file,"Invalid photo output path")
            ue.object(rendering):ExportRenderTarget(shot.owner.pc,shot.outputTarget,dir,file)
        end
        if shot.exr then
            local raw=shot.rawSumTarget or shot.rawTarget or source
            local lib=ue.object("/Script/ImageWriteQueue.Default__ImageWriteBlueprintLibrary")
            ue.call("/Script/ImageWriteQueue.ImageWriteBlueprintLibrary:ExportToDisk",lib,raw,shot.exrPartPath,
                {Format=3,CompressionQuality=0,bOverwriteFile=false,bAsync=false})
        end
    end

    function motion.release(shot)
        if ue.valid(shot.actor) then ue.call(actorPath.."K2_DestroyActor",shot.actor) end
        local lib = ue.object(rendering)
        for _,name in ipairs({"sampleTarget","sumTarget","outputTarget","rawTarget","rawSumTarget"}) do
            local rt=shot[name]
            if ue.valid(rt) then lib:ReleaseRenderTarget2D(rt) end
            shot[name]=nil
        end
        shot.actor,shot.capture,shot.rawCapture = nil,nil,nil
    end

    return motion
end
