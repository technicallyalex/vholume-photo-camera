return function(ue, system, pose, log)
    local subjects = {}
    subjects.poses = {
        { "Standing", "/Game/Characters/Mannequins/Animations/Manny/MM_Idle", .18 },
        { "Crouching", "/Game/Animations/NielsAnims/Crouch/A_CrouchIdle1", 1.45 },
        { "Walking", "/Game/Characters/Mannequins/Animations/Manny/MM_Walk_InPlace", .67 },
        { "Running", "/Game/Characters/Mannequins/Animations/Manny/MM_Run_Fwd_Niels", .54 },
        { "Kneeling", "/Game/Animations/NielsAnims/Crouch/A_CrouchWalkInPlace1", .54 },
    }
    local zero = { X=0, Y=0, Z=0 }
    local noColor = { R=0, G=0, B=0, A=0 }
    local actorPath = "/Script/Engine.Actor:"
    local meshPath = "/Script/Engine.SkeletalMeshComponent:"
    local skinnedPath = "/Script/Engine.SkinnedMeshComponent:"
    local primitivePath = "/Script/Engine.PrimitiveComponent:"
    local scenePath = "/Script/Engine.SceneComponent:"
    local identity = { Rotation={X=0,Y=0,Z=0,W=1}, Translation=zero, Scale3D={X=1,Y=1,Z=1} }
    local bodyFolder = "/Game/Characters/Robert/RobertSkinny/"
    local ghostPath = "/Game/Environment/Materials/Mi_GhostCharacter"
    local headPath = "/Game/Characters/MainChara/PlayerHead/SM_PlayerHead_Angelo_01"

    local function asset(path)
        return ue.load(path .. "." .. path:match("([^/]+)$"))
    end

    local function destroy(model)
        if model and ue.valid(model.actor) then ue.call(actorPath .. "K2_DestroyActor", model.actor) end
    end

    local function material(model, ghost)
        local override = ghost and asset(ghostPath) or nil
        if ghost then assert(ue.valid(override), "Ghost material unavailable") end
        for _, part in ipairs({model.body, model.head}) do
            local count = ue.call(primitivePath .. "GetNumMaterials", part)
            for index = 0, count - 1 do
                ue.call(primitivePath .. "SetMaterial", part, index, override)
            end
        end
    end

    local function setPose(model, index)
        local data = subjects.poses[index]
        local animation = asset(data[2])
        assert(ue.valid(animation), "Pose asset unavailable")
        ue.call(meshPath .. "PlayAnimation", model.body, animation, false)
        ue.call(meshPath .. "SetPlayRate", model.body, 0)
        ue.call(meshPath .. "SetPosition", model.body, data[3], false)
    end

    local function create(active, location)
        local model = {}
        active.subjectPreview = model
        local rotation = { Pitch=0, Yaw=0, Roll=0 }
        model.actor = active.pawn:GetWorld():SpawnActor(ue.object("/Script/Engine.SkeletalMeshActor"), location, rotation)
        assert(ue.valid(model.actor), "Cannot create the subject")
        ue.call(actorPath .. "SetReplicates", model.actor, false)
        model.body = ue.call(actorPath .. "GetComponentByClass", model.actor, ue.object("/Script/Engine.SkeletalMeshComponent"))
        local body = asset(bodyFolder .. "SK_RobertSkinny")
        assert(ue.valid(model.body) and ue.valid(body), "Multiplayer body unavailable")
        ue.call(meshPath .. "SetSkeletalMeshAsset", model.body, body)
        model.body.VisibilityBasedAnimTickOption = 0
        model.head = ue.call(actorPath .. "AddComponentByClass", model.actor,
            ue.object("/Script/Engine.StaticMeshComponent"), true, identity, false)
        assert(ue.valid(model.head), "Cannot create the subject head")
        local head = asset(headPath)
        assert(ue.valid(head), "Multiplayer head unavailable")
        ue.call("/Script/Engine.StaticMeshComponent:SetStaticMesh", model.head, head)
        ue.call(scenePath .. "K2_AttachToComponent", model.head, model.body, FName("neck_01"), 0, 0, 0, false)
        ue.call(scenePath .. "K2_SetRelativeLocationAndRotation", model.head,
            { X=-1.29, Y=1, Z=-.03 }, { Pitch=-89.52, Yaw=-205.34, Roll=180 }, false, {}, true)
        ue.call(scenePath .. "SetRelativeScale3D", model.head, { X=.32, Y=.32, Z=.32 })
        -- The separate face and hair replace the body's opaque head shell.
        local materials = body.Materials
        for index = 1, #materials do
            if materials[index].MaterialSlotName:ToString() == "SkinnyHead" then
                local slot = index - 1
                local lods = ue.call(skinnedPath .. "GetNumLODs", model.body)
                for lod = 0, lods - 1 do
                    ue.call(skinnedPath .. "ShowMaterialSection", model.body, slot, slot, false, lod)
                end
                break
            end
        end
        ue.call(actorPath .. "SetActorEnableCollision", model.actor, false)
        for _, part in ipairs({model.body, model.head}) do
            ue.call(primitivePath .. "SetGenerateOverlapEvents", part, false)
            ue.call(primitivePath .. "SetCollisionEnabled", part, 0)
        end
        return model
    end

    local function footHeight(model)
        local left = ue.call(scenePath .. "GetSocketLocation",model.body,FName("ball_l"))
        local right = ue.call(scenePath .. "GetSocketLocation",model.body,FName("ball_r"))
        local origin = ue.call(actorPath .. "K2_GetActorLocation",model.actor)
        return math.min(left.Z,right.Z) - origin.Z
    end

    local function previewPose(active, model, index, now)
        setPose(model,index)
        model.pose, model.posePending = index,true
        ue.call(actorPath .. "SetActorHiddenInGame",model.actor,true)
        active.subjectCheckAt = now
    end

    function subjects.cancel(active)
        local preview = active.subjectPreview
        active.subjectPreview, active.placing, active.subjectTarget = nil, false, nil
        destroy(preview)
    end

    function subjects.clear(active)
        subjects.cancel(active)
        for _, model in ipairs(active.placedSubjects or {}) do destroy(model) end
        active.placedSubjects = nil
    end

    function subjects.undo(active)
        local last = table.remove(active.placedSubjects or {})
        destroy(last)
        if last then log("Removed the last placed subject.") end
        return last ~= nil
    end

    function subjects.start(active)
        active.placing = true
        active.subjectCheckAt, active.subjectYaw = 0, 0
    end

    function subjects.rotate(active, direction)
        active.subjectYaw = (active.subjectYaw + direction * 15) % 360
        active.subjectCheckAt = 0
    end

    local function trace(active, from, to)
        local ignored = {}
        if ue.valid(active.camera) then ignored[#ignored+1] = active.camera end
        for _, placed in ipairs(active.placedSubjects or {}) do
            if ue.valid(placed.actor) then ignored[#ignored+1] = placed.actor end
        end
        local hit = {}
        if system():LineTraceSingle(active.pawn, from, to, 0, true, ignored, 0, hit, true, noColor, noColor, 0) then
            return hit
        end
    end

    local function target(active)
        local from, rotation = pose(active)
        local yaw, pitch = math.rad(rotation.Yaw), math.rad(rotation.Pitch)
        local dx, dy = math.cos(yaw), math.sin(yaw)
        local xy = math.cos(pitch) * 2200
        local hit = trace(active, from,
            { X=from.X+dx*xy, Y=from.Y+dy*xy, Z=from.Z+math.sin(pitch)*2200 })
        if not hit or hit.ImpactNormal.Z < .66 then
            local d = hit and math.max(0, math.min(700, hit.Distance-70)) or 420
            local x, y = from.X+dx*d, from.Y+dy*d
            hit = trace(active, {X=x,Y=y,Z=from.Z+25}, {X=x,Y=y,Z=from.Z-520})
        end
        if not hit or hit.ImpactNormal.Z < .66 then return end
        local p = hit.ImpactPoint
        if (p.X-from.X)^2+(p.Y-from.Y)^2 < 130^2 then return end
        for _, placed in ipairs(active.placedSubjects or {}) do
            if (p.X-placed.location.X)^2+(p.Y-placed.location.Y)^2+(p.Z-placed.location.Z)^2 < 90^2 then return end
        end
        return { X=p.X, Y=p.Y, Z=p.Z+2 }, { Pitch=0, Yaw=rotation.Yaw+90+active.subjectYaw, Roll=0 }
    end

    function subjects.update(active, now, settings)
        if not active.placing or now < active.subjectCheckAt then return end
        active.subjectCheckAt = now + .065
        local ok, err = pcall(function()
            local p, r = target(active)
            active.subjectTarget = nil
            local model = active.subjectPreview
            if not p then
                if model then ue.call(actorPath .. "SetActorHiddenInGame", model.actor, true) end
                return
            end
            if not model then
                model = create(active, p)
                material(model, true)
                previewPose(active,model,1,now)
                return
            end
            if not model.standingFeet then
                -- Preserve the stock standing fit, then let the head follow the head bone.
                ue.call(scenePath .. "K2_AttachToComponent",model.head,model.body,FName("Head"),1,1,1,false)
                model.standingFeet = footHeight(model)
            end
            if model.pose ~= settings.pose then
                previewPose(active,model,settings.pose,now)
                return
            end
            if model.posePending then
                model.groundOffset = math.max(-8,math.min(10,model.standingFeet-footHeight(model)))
                model.posePending = false
            end
            p.Z = p.Z + model.groundOffset
            ue.call(actorPath .. "K2_SetActorLocationAndRotation", model.actor, p, r, false, {}, true)
            ue.call(actorPath .. "SetActorHiddenInGame", model.actor, false)
            active.subjectTarget = p
        end)
        if not ok then
            log("Subject preview: " .. tostring(err))
            subjects.cancel(active)
            return "SUBJECT UNAVAILABLE"
        end
    end

    function subjects.place(active, settings)
        local model, p = active.subjectPreview, active.subjectTarget
        if not model or not p then return "AIM AT CLEAR GROUND" end
        if model.pose ~= settings.pose or model.posePending then return "WAIT FOR POSE" end
        active.placedSubjects = active.placedSubjects or {}
        if #active.placedSubjects >= 12 then return "SUBJECT LIMIT REACHED" end
        material(model, false)
        -- Query-only visibility lets the optical rangefinder find the subject.
        ue.call(actorPath .. "SetActorEnableCollision", model.actor, true)
        ue.call(primitivePath .. "SetCollisionResponseToAllChannels", model.body, 0)
        ue.call(primitivePath .. "SetCollisionResponseToChannel", model.body, 3, 2)
        ue.call(primitivePath .. "SetCollisionEnabled", model.body, 1)
        model.location = p
        active.placedSubjects[#active.placedSubjects+1] = model
        active.subjectPreview, active.subjectTarget = nil, nil
        log("Placed Robert in " .. subjects.poses[settings.pose][1] .. " pose.")
        return "SUBJECT PLACED"
    end

    return subjects
end
