local directory = assert(debug.getinfo(1, "S").source:match("^@(.+[\\/])"))
local buildControls = dofile(directory .. "controls.lua")
local buildAnimation = dofile(directory .. "animation.lua")

return function(ue, pc, rect, raised, assetPath, binds, reticle, controller)
    local ui = { raised = raised }
    local dpi, w, h = rect.dpi, rect.width, rect.height
    local unit = math.min(w / (h > w and 540 or 960), h / 540)
    local function rgb(r, g, b, a)
        return { R = r, G = g, B = b, A = a or 1 }
    end
    local ink = rgb(0.78, 0.81, 0.72)
    local dim = rgb(0.39, 0.43, 0.36)
    local matte = rgb(0.005, 0.007, 0.006)
    local edge = rgb(0.08, 0.10, 0.085)
    local widgetClass = ue.load("/Game/UI/Widget_ConaptUnlockText.Widget_ConaptUnlockText_C")
    local library = ue.object("/Script/UMG.Default__WidgetBlueprintLibrary")
    local widget = library:Create(pc, widgetClass, pc)
    assert(ue.valid(widget), "Cannot create the photo overlay")
    local tree = widget.WidgetTree
    local canvas = StaticConstructObject(ue.object("/Script/UMG.CanvasPanel"), tree)
    assert(ue.valid(canvas), "Cannot create the viewfinder canvas")
    tree.RootWidget = canvas
    local font = ue.load("/Engine/EngineFonts/Roboto.Roboto")

    local function add(kind, x, y, width, height, parent)
        local child = StaticConstructObject(ue.object("/Script/UMG." .. kind), tree)
        assert(ue.valid(child), "Cannot construct " .. kind)
        local slot = ue.call("/Script/UMG.CanvasPanel:AddChildToCanvas", parent or canvas, child)
        slot:SetPosition({ X = x / dpi, Y = y / dpi })
        slot:SetSize({ X = width / dpi, Y = height / dpi })
        return child
    end

    local function block(x, y, width, height, color, parent)
        local border = add("Border", x, y, width, height, parent)
        border:SetBrushColor(color)
        return border
    end

    local function text(x, y, width, height, size, color, value, parent)
        local label = add("TextBlock", x, y, width, height, parent)
        local settings = { TypefaceFontName = FName("Regular"), Size = size * unit / dpi }
        if ue.valid(font) then settings.FontObject = font end
        label:SetFont(settings)
        label:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
        label:SetText(FText(value or ""))
        return label
    end

    local textures = {}
    local function picture(name, x, y, width, height, opacity, parent)
        local texture = textures[name]
        if not ue.valid(texture) then
            local library = ue.object("/Script/Engine.Default__KismetRenderingLibrary")
            texture = library:ImportFileAsTexture2D(pc, assetPath .. name .. ".png")
            assert(ue.valid(texture), "Cannot load camera art " .. name)
            textures[name] = texture
        end
        local image = add("Image", x, y, width, height, parent)
        image:SetBrushFromTexture(texture, false)
        ue.call("/Script/UMG.Widget:SetRenderOpacity", image, opacity)
        return image
    end

    buildControls(ue, ui, { add = add, block = block, text = text, picture = picture }, unit)
    local cameraArt
    local toastY
    local formatIcon = rect.portrait and "Controls/portrait" or "Controls/landscape"
    local key = binds.token
    local lens = controller and { "lens", 77, "LENS", "←", "→" }
        or { "lens", 77, "LENS", key("lensPrev"), key("lensNext") }
    local frame = { "frame", 78, "ROTATE", controller and "RB + Y" or key("frame") }
    local walk = { "walk", 88, "SLOW WALK", controller and "L3" or key("walk") }
    local studio = { "studio", 94, "STUDIO", controller and "Y" or key("studio") }
    local placeSubject = { "placeStart", 103, "PLACE SUBJECT", key("placeStart") }

    if raised then
        local x, y, fw, fh = rect.x, rect.y, rect.w, rect.h
        block(0, 0, w, y, matte)
        block(0, y + fh, w, h - y - fh, matte)
        block(0, y, x, fh, matte)
        block(x + fw, y, w - x - fw, fh, matte)
        local lip = math.max(2, 3 * unit)
        block(x - lip, y - lip, fw + lip * 2, lip, edge)
        block(x - lip, y + fh, fw + lip * 2, lip, edge)
        block(x - lip, y, lip, fh, edge)
        block(x + fw, y, lip, fh, edge)

        local tabY = y - 40 * unit
        local topWidth = math.min(w-20*unit,math.max(fw,400*unit))
        local topLeft = (w - topWidth) / 2
        local gap = 4 * unit
        local cell = (topWidth - 4*gap) / 5
        local gold = rgb(.94,.69,.38)
        local good = rgb(.62,.83,.52)
        local lit = rgb(.18,.17,.10)
        local fields, backgrounds, autoTags = {}, {}, {}
        for i, item in ipairs({{"mode","EXPOSURE"},{"aperture","APERTURE"},
                {"shutter","SHUTTER"},{"iso","SENSITIVITY"},{"meter","METER"}}) do
            local bx = topLeft+(i-1)*(cell+gap)
            backgrounds[item[1]] = block(bx,tabY,cell,33*unit,edge)
            block(bx,tabY,cell,unit,dim)
            text(bx+5*unit,tabY+3*unit,cell-10*unit,10*unit,7,gold,item[2])
            fields[item[1]] = text(bx+5*unit,tabY+13*unit,cell-10*unit,18*unit,11,ink)
            if i >= 2 and i <= 4 then
                autoTags[item[1]] = text(bx+cell-22*unit,tabY+4*unit,20*unit,9*unit,6,good,"AUTO")
            end
        end
        local last = {}
        local meterX = topLeft+4*(cell+gap)
        local meterScale = add("CanvasPanel",meterX+6*unit,tabY+26*unit,cell-12*unit,6*unit)
        local scaleW = cell-12*unit
        block(0,2*unit,scaleW,unit,dim,meterScale)
        for i=0,4 do block(scaleW*i/4,0,unit,5*unit,dim,meterScale) end
        local needle = block(scaleW/2,0,2*unit,5*unit,good,meterScale)
        fields.meterWarning = text(meterX+5*unit,tabY+25*unit,cell-9*unit,8*unit,6.5,gold)
        local function value(id, value)
            if last[id] == value then return end
            last[id] = value
            fields[id]:SetText(FText(value))
        end
        function ui.setExposure(mode, values, speed)
            value("mode",mode)
            value("aperture",string.format("f/%.1f",values.aperture))
            value("shutter",speed)
            value("iso","ISO "..values.iso)
            for id, tag in pairs(autoTags) do
                local auto = values[id.."Auto"]
                if last[id.."Auto"] ~= auto then
                    ue.call("/Script/UMG.Widget:SetVisibility",tag,auto and 3 or 2)
                    last[id.."Auto"] = auto
                end
            end
            value("meter",mode=="GAME" and "GAME" or (values.errorEV and
                string.format("%+.1f EV",values.errorEV) or "NO METER"))
            value("meterWarning",values.limited or "")
            local hasMeter = values.errorEV and not values.limited
            ue.call("/Script/UMG.Widget:SetVisibility",meterScale,hasMeter and 3 or 2)
            if hasMeter then
                local offset = math.max(-2,math.min(2,values.errorEV)) * scaleW/4
                ue.call("/Script/UMG.Widget:SetRenderTranslation",needle,{X=offset/dpi,Y=0})
            end
        end

        local readoutX, readoutY = x + 9*unit, y + 9*unit
        local focusW = math.min(173*unit,fw-18*unit)
        block(readoutX,readoutY,focusW,30*unit,rgb(.009,.018,.012,.89))
        local indicators = {}
        for i, key in ipairs({"near","aligned","far"}) do
            indicators[i] = picture("Studio/focus-"..key, readoutX+(5+(i-1)*17)*unit,
                readoutY+3*unit,14*unit,14*unit,.20)
        end
        ui.focus = text(readoutX+59*unit,readoutY+2*unit,focusW-62*unit,15*unit,9,ink)
        ui.subject = text(readoutX+59*unit,readoutY+15*unit,focusW-62*unit,13*unit,8,dim)
        local lastIndicator
        function ui.setFocusIndicator(direction)
            if lastIndicator == direction then return end
            lastIndicator = direction
            for i, indicator in ipairs(indicators) do
                ue.call("/Script/UMG.Widget:SetRenderOpacity",indicator,i == direction and 1 or .20)
            end
        end

        if reticle ~= 3 then
            local cx, cy = x + fw / 2, y + fh / 2
            local targetW = math.min(fw, fh) * (reticle == 2 and .24 or .12)
            local targetH = targetW * (reticle == 2 and 1 or .75)
            local art = reticle == 2 and "Studio/reticle-circle" or "Controls/focus-ring"
            ui.focusIdleOpacity = reticle == 2 and .58 or .38
            ui.focusRing = picture(art, cx - targetW / 2, cy - targetH / 2, targetW, targetH, ui.focusIdleOpacity)
        end
        ui.curtain = add("CanvasPanel", x, y, fw, fh)
        ue.call("/Script/UMG.Widget:SetClipping", ui.curtain, 1)
        ui.topCurtain = block(0, 0, fw, fh / 2, matte, ui.curtain)
        ui.bottomCurtain = block(0, fh / 2, fw, fh / 2, matte, ui.curtain)
        ui.curtainTravel = fh / (2 * dpi)
        ue.call("/Script/UMG.Widget:SetVisibility", ui.curtain, 2)
        toastY = y + fh - 30 * unit

        local infoW = math.min(176*unit,fw*.70)
        local info = add("CanvasPanel",x+9*unit,y+fh-28*unit,infoW,19*unit)
        block(0,0,infoW,19*unit,rgb(.009,.018,.012,.89),info)
        picture(formatIcon,4*unit,3*unit,17*unit,13*unit,1,info)
        ui.lens = text(25*unit,2.5*unit,infoW-29*unit,16*unit,9,ink,"",info)
        local dialW = math.min(211*unit,fw*.85)
        local dialPanel = add("CanvasPanel",x+fw-dialW-9*unit,y+fh-52*unit,dialW,22*unit)
        block(0,0,dialW,22*unit,rgb(.023,.032,.024,.96),dialPanel)
        block(0,0,2*unit,22*unit,gold,dialPanel)
        local dialText = text(7*unit,4*unit,dialW-12*unit,16*unit,9,gold,"",dialPanel)
        local previousDial, previousHint
        ue.call("/Script/UMG.Widget:SetVisibility",dialPanel,2)
        function ui.setDial(id, hint)
            if id == previousDial and hint == previousHint then return end
            if backgrounds[previousDial] then backgrounds[previousDial]:SetBrushColor(edge) end
            if backgrounds[id] then backgrounds[id]:SetBrushColor(lit) end
            ue.call("/Script/UMG.Widget:SetVisibility",dialPanel,hint and 3 or 2)
            if hint then dialText:SetText(FText(hint)) end
            previousDial, previousHint = id, hint
        end

        local tall = h > w
        local dockWidth, dockY = math.min(w - 24 * unit, 808 * unit), y + fh + 4 * unit
        local dockX = (w - dockWidth) / 2
        block(dockX, dockY, dockWidth, (tall and 69 or 46) * unit, rgb(.018,.029,.023,.96))
        block(dockX, dockY, dockWidth, unit, rgb(.24,.31,.25))
        block(dockX, dockY + unit, 2 * unit, (tall and 68 or 45) * unit, rgb(.62,.44,.22))
        local dockInset, rowWidth = dockX + 7 * unit, dockWidth - 14 * unit
        local shoot = { "shoot", 104, "TAKE PHOTO", controller and "RT" or key("shoot") }
        local finder = { "finder", 110, "LOWER FINDER", controller and "LT" or key("finder") }
        local autofocus = { "af", 132, "SINGLE-SHOT AF", controller and "A" or key("af") }
        local mode = { "mode", 72, "AF/MF", controller and "X" or key("mode") }
        local focusKeys = binds.focusTokens()
        local focus = { "focus", 74, "FOCUS", table.unpack(focusKeys) }
        local fine = { "fine", 91, "FINE", key("fine"), table.unpack(focusKeys) }
        local dof = { "dof", 62, "DOF", controller and "B" or key("dof") }
        local aperture = { "aperture", 93, "APERTURE", "Ctrl", "mouse-wheel" }
        local shutter = { "speed", 93, "SHUTTER", "Alt", "mouse-wheel" }
        local iso = { "iso", 93, "ISO", "Ctrl + Alt", "mouse-wheel" }
        if controller then
            ui.addControlRow(dockInset,dockY+4*unit,rowWidth,{shoot,finder,autofocus,lens,studio},nil,true)
            ui.addControlRow(dockInset,dockY+25*unit,rowWidth,{mode,dof,walk,
                {"exposure",90,"EXPOSURE","LB"}, {"focus",97,"FOCUS / ISO","RB"},
                {"ratio",87,"MODE / FRAME","↑","↓"}},nil,true)
        elseif tall then
            ui.addControlRow(dockInset, dockY + 4 * unit, rowWidth, { shoot, finder, autofocus }, nil, true)
            ui.addControlRow(dockInset, dockY + 25 * unit, rowWidth, { mode, focus, fine, dof, studio }, nil, true)
            ui.addControlRow(dockInset, dockY + 46 * unit, rowWidth, { aperture, shutter, iso, lens }, nil, true)
        else
            ui.addControlRow(dockInset, dockY + 4 * unit, rowWidth, { shoot, finder, autofocus, lens, frame, studio }, nil, true)
            ui.addControlRow(dockInset, dockY + 25 * unit, rowWidth, { mode, focus, fine, dof, aperture, shutter, iso }, nil, true)
        end
    else
        local width = math.min(616 * unit, w - 30 * unit)
        local cardHeight = 91
        local x, y = (w - width) / 2, h - (cardHeight + 23) * unit
        block(x, y, width, cardHeight * unit, rgb(0.014, 0.019, 0.016, 0.96))
        block(x, y, width, 1 * unit, rgb(0.31, 0.35, 0.29))
        block(x, y + 1 * unit, 3 * unit, (cardHeight - 1) * unit, rgb(0.64, 0.39, 0.20))
        local cellW, cellH = 74 * unit, (96 / 112) * 74 * unit
        cameraArt = add("CanvasPanel", x + 8 * unit, y + (cardHeight * unit - cellH) / 2, cellW, cellH)
        ue.call("/Script/UMG.Widget:SetClipping", cameraArt, 1)
        local atlas = picture("Studio/camera", 0, 0, 8 * cellW, 6 * cellH, 1, cameraArt)
        local started, previous
        function ui.tickCameraArt(now)
            started = started or now
            local frame = math.floor((now - started) * 10) % 48
            if frame == previous then return end
            previous = frame
            ue.call("/Script/UMG.Widget:SetRenderTranslation", atlas,
                { X = -(frame % 8) * cellW / dpi, Y = -math.floor(frame / 8) * cellH / dpi })
        end
        block(x + 82 * unit, y + 8 * unit, unit, (cardHeight-16) * unit, rgb(.16,.22,.17))
        text(x + 92 * unit, y + 8 * unit, 133 * unit, 17 * unit, 12, ink, "35 MM CAMERA")
        ui.lens = text(x + 225 * unit, y + 5 * unit, width - 239 * unit, 21 * unit, 15, ink)
        picture(formatIcon, x + 92 * unit, y + 29 * unit, 18 * unit, 14 * unit, 1)
        ui.summary = text(x + 115 * unit, y + 28 * unit, width - 126 * unit, 16 * unit, 9.5, dim)
        local controlsX = x + 92 * unit
        local controlsWidth = width - 104 * unit
        local finder = { "finder", 110, "RAISE FINDER", controller and "LT" or key("finder") }
        local shooting = add("CanvasPanel",controlsX,y+47*unit,controlsWidth,19*unit)
        ui.addControlRow(0, 0, controlsWidth, { finder, lens, frame }, shooting, true)
        ui.addControlRow(controlsX, y + 69 * unit, controlsWidth, { walk, studio, placeSubject }, nil, true)

        local placement = add("CanvasPanel", x, y - 72*unit, width, 45*unit)
        block(0, 0, width, 45*unit, rgb(0.014, 0.019, 0.016, 0.96), placement)
        block(0, 0, width, unit, rgb(0.31, 0.35, 0.29), placement)
        block(0, unit, 3*unit, 44*unit, rgb(0.64, 0.39, 0.20), placement)
        local poseLabel = text(12*unit, 4*unit, width-24*unit, 16*unit, 11, ink, "", placement)
        ui.addControlRow(12*unit, 22*unit, width - 24*unit, {
            { "place", 68, "PLACE", controller and "RT" or key("shoot") },
            { "finish", 73, "FINISH", controller and "LT" or key("finder") },
            controller and { "turn",85,"TURN","←","→" } or { "turn",85,"TURN",key("placeLeft"),key("placeRight") },
            { "pose", 64, "POSE", controller and "↑" or key("placePose") },
            { "undo", 71, "UNDO", controller and "X" or key("placeUndo") },
        }, placement, true)
        local placing, lastPose
        function ui.setPlacement(pose)
            local visible = type(pose) == "string"
            if visible ~= placing then
                ue.call("/Script/UMG.Widget:SetVisibility", placement, visible and 3 or 2)
                ue.call("/Script/UMG.Widget:SetVisibility", shooting, visible and 2 or 3)
                ui.setControlVisible("placeStart", not visible)
                placing = visible
            end
            if visible and pose ~= lastPose then
                lastPose = pose
                poseLabel:SetText(FText("PLACE SUBJECTS   /   " .. pose))
            end
        end
        ui.setPlacement(false)
        toastY = y - 26 * unit
    end

    ui.notice = add("CanvasPanel", w / 2 - 110 * unit, toastY, 220 * unit, 21 * unit)
    block(0, 0, 220 * unit, 21 * unit, rgb(0.025, 0.036, 0.029, 0.90), ui.notice)
    ui.status = text(0, 2 * unit, 220 * unit, 17 * unit, 11, ink, "", ui.notice)
    ue.call("/Script/UMG.TextLayoutWidget:SetJustification", ui.status, 1)
    ue.call("/Script/UMG.Widget:SetRenderOpacity", ui.notice, 0)
    buildAnimation(ue, ui, canvas, unit, dpi, cameraArt)

    ue.call("/Script/UMG.Widget:SetVisibility", widget, 3)
    function ui.visible(visible)
        ue.call("/Script/UMG.Widget:SetVisibility", widget, visible and 3 or 2)
    end

    ue.call("/Script/UMG.UserWidget:AddToViewport", widget, 80)
    ue.call("/Script/UMG.UserWidget:SetDesiredSizeInViewport", widget, { X = w / dpi, Y = h / dpi })
    ue.call("/Script/UMG.UserWidget:SetPositionInViewport", widget, { X = 0, Y = 0 }, false)
    ui.widget = widget
    return ui
end
