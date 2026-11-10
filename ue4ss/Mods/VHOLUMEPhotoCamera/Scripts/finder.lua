local directory = assert(debug.getinfo(1, "S").source:match("^@(.+[\\/])"))
local buildControls = dofile(directory .. "controls.lua")
local buildAnimation = dofile(directory .. "animation.lua")
local buildHUD = dofile(directory .. "finder_hud.lua")

return function(ue, pc, rect, raised, assetPath, binds, reticle, controller)
    local ui = { raised = raised }
    local dpi, w, h = rect.dpi, rect.width, rect.height
    local unit = rect.unit
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

    local draw = { add = add, block = block, text = text, picture = picture }
    buildControls(ue, ui, draw, unit)
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
        local seam = rgb(.035,.047,.040)
        block(x - lip, y - lip, fw + lip * 2, unit, seam)
        block(x - lip, y + fh + lip - unit, fw + lip * 2, unit, seam)

        buildHUD(ue, ui, rect, binds, controller, draw)

        if reticle ~= 4 then
            local cx, cy = x + fw / 2, y + fh / 2
            local diameter = math.min(fw, fh) * (reticle == 3 and .24 or reticle == 2 and .12 or .21)
            local targetH = diameter * (reticle == 2 and .75 or 1)
            local art = reticle == 1 and "Controls/reticle-optical"
                or reticle == 2 and "Controls/focus-ring" or "Studio/reticle-circle"
            ui.focusIdleOpacity = reticle == 2 and .38 or .68
            ui.focusRing = picture(art, cx - diameter / 2, cy - targetH / 2, diameter, targetH, ui.focusIdleOpacity)
        end
        ui.curtain = add("CanvasPanel", x, y, fw, fh)
        ue.call("/Script/UMG.Widget:SetClipping", ui.curtain, 1)
        ui.topCurtain = block(0, 0, fw, fh / 2, matte, ui.curtain)
        ui.bottomCurtain = block(0, fh / 2, fw, fh / 2, matte, ui.curtain)
        ui.curtainTravel = fh / (2 * dpi)
        ue.call("/Script/UMG.Widget:SetVisibility", ui.curtain, 2)
        toastY = y + fh - 30 * unit
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
