local lenses = {16, 24, 35, 50, 85, 135, 200, 600}
local speedFields = {"MaxWalkSpeed", "MaxWalkSpeedCrouched"}
local lensIndex, slow = 4, false
local walkSpeed = 125 -- Unreal centimeters per second.
local state
local pending
local shotNumber = 0
local lastError
local engine
local optics
local subjects
local scriptPath = assert(debug.getinfo(1, "S").source:match("^@(.+[\\/])"))
local buildFinder = dofile(scriptPath .. "finder.lua")
local buildStudio = dofile(scriptPath .. "studio_ui.lua")
local film = dofile(scriptPath .. "film.lua")
local settings = { stock=1, frame=1, pose=1, reticle=1 }
local reticles = { "Square", "Circle", "None" }
local studioCards = { "photos", "lens", "film", "frame", "subjects" }
local lensCard, frameCard = 2, 4
local assetPath = scriptPath .. "../Assets/"

local function log(message)
    print("[VHOLUME Photo] " .. tostring(message) .. "\n")
end

local function valid(object)
    return object ~= nil and object:IsValid()
end

local function address(object)
    return valid(object) and object:GetAddress() or nil
end

local objects = {}
local function object(path)
    local value = objects[path]
    if not valid(value) then
        value = StaticFindObject(path)
        assert(valid(value), "Missing Unreal object " .. path)
        objects[path] = value
    end
    return value
end

local function call(path, context, ...)
    return object(path)(context, ...)
end

local function system()
    return object("/Script/Engine.Default__KismetSystemLibrary")
end

local function gameplay()
    return object("/Script/Engine.Default__GameplayStatics")
end

local function load(path)
    local loaded = StaticFindObject(path)
    if valid(loaded) then return loaded end
    local library = system()
    return library:LoadAsset_Blocking(library:Conv_SoftObjPathToSoftObjRef(library:MakeSoftObjectPath(path)))
end

local ue = { valid = valid, object = object, call = call, load = load }
local binds = dofile(scriptPath .. "bindings.lua")(ue, log)
local bindingsLoaded
local audio = dofile(scriptPath .. "audio.lua")(ue, assetPath, log)
local lensTransition = .19

local function localPlayer()
    if not valid(engine) then engine = FindFirstOf("GameEngine") end
    if not valid(engine) or not valid(engine.GameViewport) then return end
    local pc = gameplay():GetPlayerController(engine.GameViewport, 0)
    if not valid(pc) then return end
    return pc
end

local function component(actor, kind)
    return call("/Script/Engine.Actor:GetComponentByClass", actor, object("/Script/Engine." .. kind))
end

local function gate(pc, portrait)
    local layout = object("/Script/UMG.Default__WidgetLayoutLibrary")
    local size = layout:GetViewportSize(pc)
    local w, h = math.floor(size.X), math.floor(size.Y)
    if portrait == nil then portrait = h > w end
    local columns, rows = film.ratio(settings.frame, portrait)
    local full = math.min(w / columns, h / rows)
    local tall = h > w
    local unit = math.min(w / (tall and 540 or 960), h / 540)
    local limit = (h - (tall and 154 or 112) * unit) / rows
    local frames = math.floor(math.min(full * .85, limit) / 2) * 2
    assert(frames * math.min(columns, rows) >= 64, "Viewport is too small for the photo camera")
    local width, height = frames * columns, frames * rows
    local filmWidth = portrait and math.min(24,36*columns/rows) or math.min(36,24*columns/rows)
    return {
        width = w, height = h, dpi = math.max(0.01, layout:GetViewportScale(pc)),
        x = math.floor((w - width) / 2), y = math.floor((h - height) / 2),
        w = width, h = height, fullWidth = full * columns, portrait = portrait,
        filmWidth = filmWidth, columns = columns, rows = rows,
    }
end

local grainTexture
local function releaseFilm(active)
    if active.restoreGrain and valid(active.pc) then
        if system():GetConsoleVariableIntValue("r.FilmGrain") == 1 then
            system():ExecuteConsoleCommand(active.pc,"r.FilmGrain 0",active.pc)
        end
        active.restoreGrain = nil
    end
end

local function applyFilm(active)
    if active.stock ~= 1 then
        if not valid(grainTexture) then
            local path = "/Engine/EngineResources/FilmGrains/Marcie_Grain_v3_128_M2_000"
            grainTexture = load(path .. ".Marcie_Grain_v3_128_M2_000")
        end
        if system():GetConsoleVariableIntValue("r.FilmGrain") == 0 then
            system():ExecuteConsoleCommand(active.pc,"r.FilmGrain 1",active.pc)
            active.restoreGrain = true
        end
    else
        releaseFilm(active)
    end
    film.apply(active.lens,active.stock,valid(grainTexture) and grainTexture or nil)
end

local function updateFocusLabels(active)
    local ui = active.ui
    if not active.raised or not ui or not valid(ui.widget) then return end
    local aperture, focus, subject = optics.readout(active)
    if ui.apertureText ~= aperture then
        ui.aperture:SetText(FText(aperture))
        ui.apertureText = aperture
    end
    if ui.focusText ~= focus then
        ui.focus:SetText(FText(focus))
        ui.focusText = focus
    end
    if ui.subjectText ~= subject then
        ui.subject:SetText(FText(subject))
        ui.subjectText = subject
    end
    ui.setFocusIndicator(optics.focusIndicator(active))
    ui.setControlActive("dof", optics.enabled)
    ui.setControlActive("mode", optics.manual)
end

local function updateLabels(active, message)
    local ui = active.ui
    if not ui or not valid(ui.widget) then return end
    ui.lens:SetText(FText(string.format("%d mm", lenses[lensIndex])))
    ui.setControlActive("walk", slow)
    if active.raised then
        updateFocusLabels(active)
    else
        local format = active.rect.portrait and "PORTRAIT" or "LANDSCAPE"
        ui.summary:SetText(FText(string.format("%s  %d:%d   /   %s   /   %s",format,
            active.rect.columns,active.rect.rows,film.stocks[settings.stock][1],
            slow and "SLOW WALK ON" or "SLOW WALK OFF")))
        ui.setPlacement(active.placing and subjects.poses[settings.pose][1])
    end
    if message then ui.setNotice(message, gameplay():GetRealTimeSeconds(active.pc)) end
end

local function present(active, effect, message, direction)
    local now = gameplay():GetRealTimeSeconds(active.pc)
    active.lastEffect = effect
    active.ui.playEffect(effect, now, direction)
    if message then active.ui.setNotice(message, now) end
    audio.play(active, effect, now)
end

local controllerPath = "/Script/Engine.PlayerController:"
local function setLookScales(pc, yaw, pitch)
    call(controllerPath .. "SetDeprecatedInputYawScale", pc, yaw)
    call(controllerPath .. "SetDeprecatedInputPitchScale", pc, pitch)
end

local function restoreLookScales(active)
    local look = active.lookScales
    if not look then return end
    if valid(active.pc) then setLookScales(active.pc, look.yaw, look.pitch) end
    active.lookScales = nil
end

local function updateLookScales(active)
    if not binds.aimScaling() or not active.raised or active.studio or active.menuOpen or active.stowAt then
        restoreLookScales(active)
        return
    end
    -- Match gameplay's projected motion when zoomed in. Wider views keep stock input.
    local finderTangent = math.tan(math.rad(active.lens.FieldOfView) / 2)
    local gameplayTangent = math.tan(math.rad(active.firstPerson.FieldOfView) / 2)
    local scale = finderTangent / gameplayTangent
    if scale >= 1 - 1e-6 then
        restoreLookScales(active)
        return
    end
    local look = active.lookScales
    if not look then
        look = { yaw = active.pc.InputYawScale, pitch = active.pc.InputPitchScale }
        active.lookScales = look
    end
    if scale ~= look.scale then
        setLookScales(active.pc, look.yaw * scale, look.pitch * scale)
        look.scale = scale
    end
end

local setFov = "/Script/Engine.CameraComponent:SetFieldOfView"
local function applyLens(active, animate)
    if not active.raised then return end
    -- Preserve the lens's angle for either orientation of a 36 x 24 mm frame.
    local rect = active.rect
    active.focalLength = lenses[lensIndex]
    local gateWidth = rect.filmWidth * rect.fullWidth / rect.w
    local angle = math.deg(2 * math.atan(gateWidth / (2 * active.focalLength)))
    local now = gameplay():GetRealTimeSeconds(active.pc)
    call("/Script/Engine.CameraComponent:SetAspectRatio", active.lens, rect.w / rect.h)
    if animate then
        active.lensMotion = { from = active.lens.FieldOfView, to = angle, time = now }
        active.readyAt = math.max(active.readyAt or 0, now + lensTransition + .045)
    else
        active.lensMotion = nil
        call(setFov, active.lens, angle)
        active.readyAt = math.max(active.readyAt or 0, now + .075)
    end
    updateLookScales(active)
end

local function tickLens(active, now)
    local motion = active.lensMotion
    if not active.raised or not motion then return end
    local t = math.min(1, math.max(0, (now - motion.time) / lensTransition))
    local eased = t * t * (3 - 2 * t)
    call(setFov, active.lens, motion.from + (motion.to - motion.from) * eased)
    if t == 1 then active.lensMotion = nil end
end

local function removeOverlay(active)
    if active.ui and valid(active.ui.widget) then
        call("/Script/UMG.Widget:RemoveFromParent", active.ui.widget)
    end
    active.ui = nil
end

local function rebuildOverlay(active, rect)
    removeOverlay(active)
    active.rect = rect
    active.ui = buildFinder(ue, active.pc, rect, active.raised, assetPath, binds, settings.reticle)
    applyLens(active)
    if active.raised then applyFilm(active) end
    optics.apply(active)
    updateLabels(active)
    active.ui.visible(not active.studio and not active.menuOpen)
end

local function solo(pc)
    return system():IsStandalone(pc) or (system():IsServer(pc) and gameplay():GetNumPlayerControllers(pc) == 1)
end

local function restoreWalk(active)
    if active.walk and valid(active.movement) then
        for field, speed in pairs(active.walk) do
            if active.movement[field] == speed.limit then active.movement[field] = speed.original end
        end
    end
    active.walk = nil
end

local function updateWalk(active)
    if not slow or not solo(active.pc) then
        restoreWalk(active)
        if slow then
            slow = false
            updateLabels(active)
        end
        return
    end
    local movement = active.movement
    active.walk = active.walk or {}
    for _, field in ipairs(speedFields) do
        local current, previous = movement[field], active.walk[field]
        if not previous or current ~= previous.limit then
            local limit = math.min(current, walkSpeed)
            active.walk[field] = { original = current, limit = limit }
            movement[field] = limit
        end
    end
end

local function cameraPose(active)
    local location = call("/Script/Engine.SceneComponent:K2_GetComponentLocation", active.firstPerson)
    local position = { X = location.X, Y = location.Y, Z = location.Z }
    local rotation = call("/Script/Engine.Controller:GetControlRotation", active.pc)
    return position, { Pitch = rotation.Pitch, Yaw = rotation.Yaw, Roll = 0 }
end

optics = dofile(scriptPath .. "optics.lua")(ue, system, cameraPose, updateFocusLabels, binds)
subjects = dofile(scriptPath .. "subjects.lua")(ue, system, cameraPose, log)

local function trackCamera(active)
    local location, rotation = cameraPose(active)
    call("/Script/Engine.Actor:K2_SetActorLocationAndRotation",
        active.camera, location, rotation, false, {}, true)
end

local function hideLocalBody(active)
    -- Component visibility stays local even when the level has a net driver.
    local meshes = call("/Script/Engine.Actor:K2_GetComponentsByClass", active.pawn, object("/Script/Engine.MeshComponent"))
    active.hiddenMeshes = {}
    for index = 1, #meshes do
        local mesh = meshes[index]:get()
        if valid(mesh) and mesh.bHiddenInGame == false then
            active.hiddenMeshes[#active.hiddenMeshes + 1] = mesh
            call("/Script/Engine.SceneComponent:SetHiddenInGame", mesh, true, false)
        end
    end
end

local function releaseView(active, controller, pawn)
    restoreLookScales(active)
    for _, mesh in ipairs(active.hiddenMeshes or {}) do
        if valid(mesh) then call("/Script/Engine.SceneComponent:SetHiddenInGame", mesh, false, false) end
    end
    active.hiddenMeshes = nil
    if active.raised and valid(controller) and valid(pawn)
            and address(active.pc) == address(controller) then
        call("/Script/Engine.PlayerController:SetViewTargetWithBlend", controller, pawn, 0, 0, 0, false)
    end
    active.raised = false
end

local function setStudioInput(active, locked)
    if (active.studioInput == true) == locked then return end
    if valid(active.pc) then
        call("/Script/Engine.Controller:SetIgnoreMoveInput",active.pc,locked)
        call("/Script/Engine.Controller:SetIgnoreLookInput",active.pc,locked)
    end
    active.studioInput = locked
end

local widgetLibrary = "/Script/UMG.WidgetBlueprintLibrary:"
local function setStudioCursor(active, visible)
    if (active.studioCursor == true) == visible or not valid(active.pc) then return end
    active.studioCursor = visible
    active.pc.bShowMouseCursor = visible
    local lib = object("/Script/UMG.Default__WidgetBlueprintLibrary")
    if visible then
        call(widgetLibrary.."SetInputMode_GameAndUIEx",lib,active.pc,nil,0,false,false)
    else
        call(widgetLibrary.."SetInputMode_GameOnly",lib,active.pc,false)
    end
end

local function refreshStudio(active)
    if active.keyPage then
        active.studio.keyStatus(active.keyCapture,active.keyNotice,active.keyReset)
        return
    end
    local stock, frame = film.stocks[settings.stock], film.frames[settings.frame]
    local portrait = active.portrait
    if portrait == nil then portrait = active.rect.portrait end
    local x,y = film.ratio(settings.frame,portrait)
    local orientation = x == y and "Square frame" or (portrait and "Portrait frame" or "Landscape frame")
    active.studio.update(active.studioCard,{
        photos={"Photo folder","Open in File Explorer","folder"},
        lens={string.format("%d mm",lenses[lensIndex]),"Focal length","lens"..lenses[lensIndex],binds.aimScaling()},
        film={stock[1],stock[3],stock[2],stock.grain or 0},
        frame={frame[1].."  "..x..":"..y,orientation,
            "frame"..settings.frame..(portrait and x~=y and "p" or "")},
        subjects={subjects.poses[settings.pose][1],"Robert","subject"..settings.pose},
    },portrait,x==y,reticles[settings.reticle])
    active.studio.notice("")
end

local function buildOptions(active, rect)
    local focused
    if active.studio then
        if active.studioKeyPage == active.keyPage then focused = active.studio.focused() end
        active.studio.close()
    end
    active.studio = buildStudio(ue,active.pc,rect,assetPath,binds,studioCards,active.keyPage,active.raised)
    active.studioKeyPage = active.keyPage
    if focused then active.studio.focus(focused.action,focused.step,focused.card) end
    active.studioRect = rect
    refreshStudio(active)
end

local function closeStudio(active)
    if not active.studio then return end
    active.studio.close()
    active.studio = nil
    active.studioRect = nil
    active.studioKeyPage = nil
    active.keyPage, active.keyCapture, active.keyNotice, active.keyReset = nil,nil,nil,nil
    setStudioCursor(active,false)
    setStudioInput(active,false)
    if active.ui and valid(active.ui.widget) then active.ui.visible(not active.menuOpen) end
end

local function showStudio(active)
    if active.placing then subjects.cancel(active); updateLabels(active) end
    active.studioCard = active.studioCard or 1
    buildOptions(active,gate(active.pc,active.portrait))
    updateLookScales(active)
    setStudioInput(active,true)
    setStudioCursor(active,true)
    active.ui.visible(false)
end

local function photoDirectory()
    local saved = system():GetProjectSavedDirectory():ToString():gsub("[/\\]+$","")
    return saved .. "/Screenshots/Windows/"
end

local function openPhotos(active)
    local dir = photoDirectory():gsub("/", "\\"):gsub("\\+$","")
    -- This path is engine-owned. Reject shell expansion and quote every use.
    if not dir:match("^[A-Za-z]:\\") or dir:find('[%%!"\r\n]') then
        active.studio.notice("PHOTO FOLDER PATH UNAVAILABLE")
        return
    end
    os.execute('if not exist "'..dir..'" mkdir "'..dir..'"')
    local opened = os.execute('start "" "%SystemRoot%\\explorer.exe" "'..dir..'"')
    active.studio.notice(opened and "PHOTO FOLDER OPENED" or "COULD NOT OPEN PHOTO FOLDER")
end

local function stow(departing)
    if not state then return end
    local active = state
    state = nil
    local pc = departing and active.pc or localPlayer()
    local pawn = departing and active.pawn or (valid(pc) and gameplay():GetPlayerPawn(pc, 0)) or nil
    local steps = {
        function() optics.release(active, pc or active.pc) end,
        function() releaseFilm(active) end,
        function() releaseView(active, pc, pawn) end,
        function() restoreWalk(active) end,
        function() closeStudio(active) end,
        function() subjects.clear(active) end,
        function() removeOverlay(active) end,
        function() audio.release(active) end,
        function()
            if valid(active.camera) then call("/Script/Engine.Actor:K2_DestroyActor", active.camera) end
        end,
    }
    for _, cleanup in ipairs(steps) do
        local ok, err = pcall(cleanup)
        if not ok then log("Photo cleanup: " .. tostring(err)) end
    end
end

local function requestStow()
    if not state or state.stowAt then return end
    closeStudio(state)
    restoreLookScales(state)
    subjects.cancel(state)
    updateLabels(state)
    present(state, "stow")
    state.stowAt = gameplay():GetRealTimeSeconds(state.pc) + .23
end

local function equip(pc, pawn)
    if state then requestStow(); return end
    if not valid(pawn) then
        log("Camera needs a possessed player pawn.")
        return
    end
    local cameras = call("/Script/Engine.Actor:K2_GetComponentsByClass", pawn, object("/Script/Engine.CameraComponent"))
    local firstPerson
    for index = 1, #cameras do
        local camera = cameras[index]:get()
        if valid(camera) and call("/Script/Engine.ActorComponent:IsActive", camera) then
            firstPerson = firstPerson or camera
            if camera:GetFName():ToString() == "FirstPersonCamera" then
                firstPerson = camera
                break
            end
        end
    end
    local movement = component(pawn, "CharacterMovementComponent")
    if not valid(firstPerson) or not valid(movement) then
        log("No active player camera and movement component are available.")
        return
    end
    state = { pc = pc, pawn = pawn, firstPerson = firstPerson, movement = movement, raised = false, menuOpen = false, stock = settings.stock }
    rebuildOverlay(state, gate(pc))
    updateWalk(state)
    present(state, "equip")
    showStudio(state)
    log("Equipped at " .. lenses[lensIndex] .. " mm.")
end

local function raiseOrLower()
    local active = state
    if not active or gameplay():IsGamePaused(active.pc) then return end
    if active.placing then
        subjects.cancel(active)
        updateLabels(active,"PLACEMENT FINISHED")
        return
    end
    local wasRaised = active.raised
    if wasRaised then
        releaseView(active, active.pc, active.pawn)
        optics.release(active, active.pc)
        releaseFilm(active)
        active.subjectDistance, active.subjectCheck = nil, nil
        active.focusGoal = nil
    else
        if not valid(active.camera) then
            local location, rotation = cameraPose(active)
            active.camera = active.pawn:GetWorld():SpawnActor(object("/Script/Engine.CameraActor"), location, rotation)
            assert(valid(active.camera), "Cannot spawn the photo camera")
            active.lens = component(active.camera, "CameraComponent")
            assert(valid(active.lens), "Photo camera is missing its lens component")
            call("/Script/Engine.CameraComponent:SetConstraintAspectRatio", active.lens, true)
        end
        active.raised = true
        trackCamera(active)
        hideLocalBody(active)
        call("/Script/Engine.PlayerController:SetViewTargetWithBlend", active.pc, active.camera, 0.10, 1, 0, false)
        active.readyAt = gameplay():GetRealTimeSeconds(active.pc) + 0.23
    end
    rebuildOverlay(active, gate(active.pc, active.portrait))
    present(active, wasRaised and "lower" or "raise")
end

local function changeLens(direction)
    if not state or gameplay():IsGamePaused(state.pc) then return end
    lensIndex = (lensIndex + direction - 1) % #lenses + 1
    applyLens(state, not state.studio)
    if state.raised then optics.apply(state) end
    updateLabels(state)
    present(state, "lens", nil, direction)
end

local function toggleFrame()
    if pending then
        if state.studio then state.studio.notice("Wait for the photo to finish saving.") end
        return false
    end
    local frame = film.frames[settings.frame]
    if frame[2] == frame[3] then
        if state.studio then
            state.studio.notice("Choose a rectangular ratio to rotate the frame.")
        else
            updateLabels(state,"SQUARE FRAME")
        end
        return false
    end
    state.portrait = not state.rect.portrait
    rebuildOverlay(state, gate(state.pc, state.portrait))
    if state.raised then
        state.readyAt = math.max(state.readyAt, gameplay():GetRealTimeSeconds(state.pc) + .22)
    end
    present(state,"frame",string.format("%s  /  %d:%d",
        state.rect.portrait and "PORTRAIT" or "LANDSCAPE",state.rect.columns,state.rect.rows))
    return true
end

local function toggleWalk()
    if not state or gameplay():IsGamePaused(state.pc) then return end
    if not solo(state.pc) then
        updateLabels(state, "WALK SOLO ONLY")
        return
    end
    slow = not slow
    updateWalk(state)
    updateLabels(state)
    present(state, "walk", slow and "SLOW WALK ON" or "SLOW WALK OFF")
end

local function adjustOptics(effect, direction)
    local active = state
    if not active or not active.raised then return end
    if effect == "af" then
        local locked = optics.autofocus(active)
        present(active, locked and "af_lock" or "af_miss", locked and "Focused" or "NO AF TARGET")
    elseif effect == "dof" then
        optics.toggle(active)
        present(active, effect, optics.enabled and "DEPTH OF FIELD ON" or "DEPTH OF FIELD OFF")
    elseif effect == "mode" then
        optics.toggleManual(active)
        present(active, effect, optics.manual and "MANUAL FOCUS" or "CONTINUOUS AUTOFOCUS")
    elseif optics.stepAperture(active, direction) then
        present(active, effect)
    end
end

local function pngDimensions(path)
    local file = io.open(path, "rb")
    if not file then return end
    local head = file:read(24)
    local finish = file:seek("end", -12) and file:read(12)
    file:close()
    if head and #head == 24 and head:sub(1, 8) == "\137PNG\13\10\26\10"
            and finish and finish:sub(5, 8) == "IEND" then
        return string.unpack(">I4I4", head, 17)
    end
end

local function finishShot(shot, tries)
    if pending ~= shot then return end
    local width, height = pngDimensions(shot.path)
    if not width and tries > 0 then
        ExecuteInGameThreadWithDelay(250, function() finishShot(shot, tries - 1) end)
        return
    end
    pending = nil
    local good = width == shot.width and height == shot.height
    if good then log("Saved " .. shot.path)
    else log("Photo did not finish with the expected frame: " .. shot.path) end
    if state == shot.owner and not state.stowAt then
        local message = good and "PHOTO SAVED" or "PHOTO SAVE FAILED"
        if state.studio and not state.keyPage then
            state.studio.notice(message)
        elseif good and not state.menuOpen then
            present(state, "saved", message)
        else
            updateLabels(state, message)
        end
    end
end

local function shutter()
    local active = state
    if active and active.placing then
        updateLabels(active,subjects.place(active,settings))
        return
    end
    if not active or not active.raised or gameplay():IsGamePaused(active.pc) then return end
    if pending then
        updateLabels(active,"SAVING PHOTO")
        return
    end
    if gameplay():GetRealTimeSeconds(active.pc) < active.readyAt then
        updateLabels(active,"CAMERA READYING")
        return
    end
    local current = gate(active.pc, active.portrait)
    if current.width ~= active.rect.width or current.height ~= active.rect.height then
        rebuildOverlay(active, current)
        return
    end
    local dir = photoDirectory()
    local path
    repeat
        shotNumber = shotNumber + 1
        path = string.format("%sVHOLUME_%s_%03d_%dmm_%s_%dx%d.png", dir,
            os.date("%Y%m%d_%H%M%S"), shotNumber, lenses[lensIndex],film.stocks[active.stock][2],
            current.columns,current.rows)
        local file = io.open(path, "rb")
        if file then file:close() else break end
    until false
    local shot = { path = path, width = current.w, height = current.h, owner = active }
    local command = string.format('HighResShot filename="%s" 1 %d %d %d %d 0 0 0 0',
        path, current.x, current.y, current.w, current.h)
    system():ExecuteConsoleCommand(active.pc, command, active.pc)
    pending = shot
    present(active, "shutter")
    ExecuteInGameThreadWithDelay(250, function() finishShot(shot, 11) end)
end

local function guarded(action)
    local ok, err = pcall(action)
    if not ok then
        if err ~= lastError then log(err) end
        lastError = err
        local restored, recovery = pcall(stow)
        if not restored then log("Photo cleanup: " .. tostring(recovery)) end
    end
end

local function binding(id, action)
    return { id=id, action=action }
end

local equipBindings = { binding("equip"), { key=binds.raw("F9") } }
local studioKey = binding("studio")
local placementKey = binding("placeStart")
local tabKey = { key=binds.raw("Tab") }
local studioInputs = {
    left=binding("menuLeft"), right=binding("menuRight"), up=binding("menuNext"), down=binding("menuPrev"),
    select=binding("menuSelect"), finder=binding("finder"),
    click={key=binds.raw("LeftMouseButton")}, enter={key=binds.raw("Enter")},
    portrait=binding("frame"), lensPrev=binding("lensPrev"), lensNext=binding("lensNext"),
}
local function undoSubject()
    if subjects.undo(state) then updateLabels(state,"SUBJECT REMOVED") end
end
local function rotateSubject(step)
    if state.placing then subjects.rotate(state,step) end
end
local function cyclePose()
    if state.placing then
        settings.pose = settings.pose % #subjects.poses + 1
        state.subjectCheckAt = 0
        updateLabels(state)
    end
end
local placementBindings = {
    binding("placeUndo",undoSubject),
    binding("placeLeft",function() rotateSubject(-1) end),
    binding("placeRight",function() rotateSubject(1) end),
    binding("placePose",cyclePose),
}
local cameraBindings = {
    binding("finder", raiseOrLower),
    binding("shoot", shutter),
    binding("af", function() adjustOptics("af") end),
    binding("lensPrev", function() changeLens(-1) end),
    binding("lensNext", function() changeLens(1) end),
    binding("walk", toggleWalk),
    binding("frame", toggleFrame),
    binding("dof", function() adjustOptics("dof") end),
    binding("mode", function() adjustOptics("mode") end),
    binding("apertureDown", function() adjustOptics("aperture", -1) end),
    binding("apertureUp", function() adjustOptics("aperture", 1) end),
}

local function justPressed(input, pc)
    local pressed = valid(pc) and (input.id and binds.pressed(pc,input.id)
        or input.key and call("/Script/Engine.PlayerController:WasInputKeyJustPressed", pc, input.key)) or false
    local edge = pressed and not input.pressed
    input.pressed = pressed
    return edge
end

local function closeOptions(active)
    closeStudio(active)
    rebuildOverlay(active,gate(active.pc,active.portrait))
    for _, input in ipairs(cameraBindings) do justPressed(input,active.pc) end
    for _, input in ipairs(placementBindings) do justPressed(input,active.pc) end
end

local function startPlacement(active)
    if active.placing then return end
    if active.studio then closeOptions(active) end
    if active.raised then raiseOrLower() end
    subjects.start(active)
    updateLabels(active)
end

local function cancelKeyCapture(active)
    active.keyCapture, active.keyNotice, active.keyReset = nil,nil,nil
end

local function changeKeyPage(active, page)
    active.keyPage = page
    cancelKeyCapture(active)
    buildOptions(active,active.studioRect)
    if page then
        active.studio.focus("bindKey",binds.groups[page][2][1])
    else
        active.studio.focus("keybinds")
    end
end

local function keybindTick(active, now, target)
    if active.keyCapture then
        if target and target.action == "bindBack" then
            cancelKeyCapture(active)
        elseif now >= active.keyReady then
            local name = binds.capture(active.pc)
            if not name then return end
            local id = active.keyCapture
            local ok, reason = binds.assign(id,name)
            if ok then
                cancelKeyCapture(active)
                active.studio.focus("bindKey",id)
                active.keyNotice = binds.action(id).." set to "..binds.label(id).."."
            else
                active.keyNotice = reason
            end
        else
            return
        end
    elseif target then
        if target.action == "bindBack" or target.action == "bindPage" then
            changeKeyPage(active,target.step)
            return
        elseif target.action == "bindReset" then
            if active.keyReset then
                active.keyReset = nil
                active.keyNotice = binds.reset() and "Defaults restored." or "Could not save keybinds."
            else
                active.keyReset = true
                active.keyNotice = "Confirm to restore all Photo Mode keybinds."
            end
        elseif target.action == "bindKey" then
            active.keyCapture = target.step
            active.keyReady = now + .12
            active.keyNotice, active.keyReset = nil,nil
        end
    else
        return
    end
    refreshStudio(active)
end

local function studioTick(active, now, tab)
    if now >= (active.studioLayoutCheck or 0) then
        active.studioLayoutCheck = now + .25
        local rect = gate(active.pc,active.portrait)
        local previous = active.studioRect
        if rect.width~=previous.width or rect.height~=previous.height or rect.dpi~=previous.dpi then
            buildOptions(active,rect)
        end
    end
    local pressed = {}
    for name, input in pairs(studioInputs) do pressed[name] = justPressed(input,active.pc) end
    local layout = object("/Script/UMG.Default__WidgetLayoutLibrary")
    local mouse = layout:GetMousePositionOnViewport(active.pc)
    local target = active.studio.pointer(mouse.X,mouse.Y,pressed.click)
    if tab ~= nil then
        active.studio.tab(tab)
        local focused = active.studio.focused()
        if focused.card then
            active.studioCard = focused.card
            refreshStudio(active)
        end
        if active.keyReset and focused.action ~= "bindReset" then
            active.keyReset,active.keyNotice = nil,nil
            refreshStudio(active)
        end
        return
    end
    local focused = active.studio.focused()
    if not pressed.click and pressed.enter then target = focused end
    if active.keyPage then
        if not active.keyCapture and not target then
            if pressed.left or pressed.right then
                local direction = pressed.right and 1 or -1
                changeKeyPage(active,(active.keyPage-1+direction)%#binds.groups+1)
                return
            elseif pressed.up or pressed.down then
                local group = binds.groups[active.keyPage]
                local index
                if focused and focused.action == "bindKey" then
                    for i=2,#group do
                        if group[i][1] == focused.step then index = i end
                    end
                end
                local nextRow = index and ((index-2+(pressed.up and -1 or 1))%(#group-1)+2)
                    or (pressed.up and #group or 2)
                active.studio.focus("bindKey",group[nextRow][1])
                active.keyReset,active.keyNotice = nil,nil
                refreshStudio(active)
                return
            end
        end
        keybindTick(active,now,target)
        return
    end
    if target and target.action == "keybinds" then
        changeKeyPage(active,1)
        return
    end
    if target and target.action == "close" then
        closeOptions(active)
        return
    end
    if pressed.finder or (target and target.action == "finder") then
        closeOptions(active)
        raiseOrLower()
        return
    end
    if target and target.action == "aimScaling" then
        active.studioCard = lensCard
        local saved = binds.setAimScaling(not binds.aimScaling())
        refreshStudio(active)
        if not saved then active.studio.notice("Could not save sensitivity scaling.") end
        return
    end
    local lensStep = pressed.lensPrev and -1 or pressed.lensNext and 1
    if lensStep then
        active.studioCard = lensCard
        changeLens(lensStep)
        refreshStudio(active)
        return
    end
    if target and target.action == "reticle" then
        settings.reticle = (settings.reticle - 1 + target.step) % #reticles + 1
        active.studioCard = frameCard
        refreshStudio(active)
        return
    end
    local nextCard = target and target.card
    if not nextCard and (pressed.left or pressed.right) then
        nextCard = (active.studioCard - 1 + (pressed.right and 1 or -1)) % #studioCards + 1
        active.studio.focus()
    end
    if nextCard and nextCard ~= active.studioCard then
        active.studioCard = nextCard
        refreshStudio(active)
    end
    local step = pressed.up and 1 or (pressed.down and -1 or 0)
    local select = pressed.select or pressed.enter
    local portrait = pressed.portrait
    if target then
        if target.action == "step" then step = target.step end
        select = target.action == "select"
        portrait = target.action == "portrait"
    end
    local card = studioCards[active.studioCard]
    if step ~= 0 or (select and (card == "lens" or card == "film" or card == "frame")) then
        if step == 0 then step = 1 end
        if card == "lens" then
            changeLens(step)
        elseif card == "film" then
            settings.stock = (settings.stock - 1 + step) % #film.stocks + 1
            active.stock = settings.stock
            if active.raised then applyFilm(active) end
        elseif card == "frame" then
            settings.frame = (settings.frame - 1 + step) % #film.frames + 1
        elseif card == "subjects" then
            settings.pose = (settings.pose - 1 + step) % #subjects.poses + 1
        end
        refreshStudio(active)
    end
    if portrait then
        active.studioCard = frameCard
        refreshStudio(active)
        if toggleFrame() then refreshStudio(active) end
    end
    if select and card == "photos" then openPhotos(active) end
    if select and card == "subjects" then
        startPlacement(active)
        return
    end
    active.studio.tick(now)
end

local function stockMenuOpen(pc)
    if not valid(pc) then return false end
    if gameplay():IsGamePaused(pc) then return true end
    local lib = object("/Script/Angelscript.Default__Module_UI_MenuFlowSubsystemStatics")
    local flow = lib:GetMenuFlowSubsystem(pc)
    if valid(flow) then
        local current = flow:GetCurrentWidget()
        if valid(current) and current:GetClass():GetFName():ToString() ~= "Widget_GameplayUI_C" then return true end
        if valid(flow:GetCurrentPopup()) then return true end
    end
    -- Studio shows its own cursor. Outside Studio, other stock interfaces can own it.
    return (not state or not state.studio) and pc.bShowMouseCursor == true
end

local function tick()
    guarded(function()
        local pc = localPlayer()
        if not bindingsLoaded and valid(pc) then
            binds.load(system():GetProjectSavedDirectory():ToString())
            bindingsLoaded = true
        end
        if valid(pc) then binds.beginFrame(pc) end
        local now = valid(pc) and gameplay():GetRealTimeSeconds(pc) or 0
        local toggle = false
        for _, input in ipairs(equipBindings) do
            if justPressed(input, pc) then toggle = true end
        end
        if not state and not toggle then return end
        local menuOpen = stockMenuOpen(pc)
        if not state and menuOpen then return end

        local pawn = valid(pc) and gameplay():GetPlayerPawn(pc, 0) or nil
        if state and (address(pc) ~= address(state.pc) or address(pawn) ~= address(state.pawn)) then
            stow()
            return
        end
        if state and state.stowAt and now >= state.stowAt then
            stow()
            return
        end
        local options = justPressed(studioKey,pc)
        local place = justPressed(placementKey,pc)
        if state and menuOpen ~= state.menuOpen then
            state.menuOpen = menuOpen
            updateLookScales(state)
            state.ui.visible(not state.studio and not menuOpen)
            if state.studio then
                state.studio.visible(not menuOpen)
                if menuOpen then
                    if state.keyPage then
                        cancelKeyCapture(state)
                        refreshStudio(state)
                    end
                    setStudioInput(state,false)
                    -- Leave cursor and input mode changes to the stock menu.
                    state.studioCursor = false
                else
                    setStudioInput(state,true)
                    setStudioCursor(state,true)
                end
            end
            if not menuOpen then
                -- A click that closes the menu must not fire the shutter.
                for _, input in ipairs(cameraBindings) do justPressed(input, pc) end
                for _, input in ipairs(placementBindings) do justPressed(input, pc) end
                for _, input in pairs(studioInputs) do justPressed(input, pc) end
                justPressed(tabKey,pc)
                return
            end
        end
        if menuOpen then return end
        if state and state.stowAt then
            state.ui.tickEffects(now)
            return
        end
        local tab = justPressed(tabKey,pc)
        if state and state.studio then
            if options and state.keyPage then
                if state.keyCapture then
                    cancelKeyCapture(state)
                    refreshStudio(state)
                else
                    changeKeyPage(state,nil)
                end
                return
            end
            if state.keyCapture then
                studioTick(state,now)
                return
            end
            if tab then
                local backward = binds.shiftDown(pc)
                if backward or binds.tabHint() == "Tab" then
                    studioTick(state,now,backward)
                    return
                end
            end
        end
        if toggle then
            equip(pc, pawn)
            for _, input in ipairs(cameraBindings) do
                input.pressed = false
                if state then justPressed(input, pc) end
            end
        end
        local active = state
        if not active then return end
        if active.stowAt then return end
        if options then
            if active.studio then closeOptions(active) else showStudio(active) end
            for _, input in pairs(studioInputs) do justPressed(input,pc) end
            return
        end
        if place and not active.keyPage and not active.placing then
            startPlacement(active)
            return
        end
        if active.studio then
            studioTick(active,now)
            return
        end
        local notice = subjects.update(active,now,settings)
        if notice then updateLabels(active,notice) end
        local placing = active.placing
        for _, input in ipairs(placementBindings) do
            if justPressed(input,pc) and placing then input.action() end
        end
        for _, input in ipairs(cameraBindings) do
            if justPressed(input,pc) and (not placing
                    or input.id == "finder" or (input.id == "shoot" and active.placing)) then
                input.action()
            end
        end
        updateWalk(active)
        if active.raised then trackCamera(active) end
        tickLens(active, now)
        if active.raised then updateLookScales(active) end
        local focusInput = optics.tick(active, now)
        if focusInput then
            if active.lastEffect == "af_lock" then
                active.ui.setNotice(nil,now)
                active.lastEffect = nil
            end
            active.ui.pulseControl(focusInput, now)
            audio.play(active, "focus", now)
        end
        active.ui.tickEffects(now)
        if now >= (active.layoutCheck or 0) then
            active.layoutCheck = now + 0.25
            local nextRect = gate(pc, active.portrait)
            if nextRect.width ~= active.rect.width or nextRect.height ~= active.rect.height
                    or nextRect.portrait ~= active.rect.portrait
                    or nextRect.dpi ~= active.rect.dpi then rebuildOverlay(active, nextRect) end
        end
    end)
end

-- Release Studio's input and widgets while the outgoing controller is still alive.
RegisterLoadMapPreHook(function()
    if state then stow(true) end
end)

if LoopInGameThreadAfterFrames then
    LoopInGameThreadAfterFrames(1, tick)
else
    LoopInGameThreadWithDelay(1, tick)
end

log("Ready. Press 5 or F9 to select the 35mm camera.")
