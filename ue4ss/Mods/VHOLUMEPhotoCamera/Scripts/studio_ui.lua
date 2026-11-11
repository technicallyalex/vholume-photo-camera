local directory = assert(debug.getinfo(1, "S").source:match("^@(.+[\\/])"))
local buildControls = dofile(directory .. "controls.lua")

return function(ue, pc, rect, assets, binds, cards, keyPage, raised, exposurePage, exposure)
    local ui = {}
    local w, h, dpi = rect.width, rect.height, rect.dpi
    local wide = w >= h
    local columns = wide and #cards or 3
    local rows = math.ceil(#cards / columns)
    local unit = math.min(w / (wide and 1180 or 620), h / (wide and 460 or 665))
    local tileW, tileH, gap = 178*unit, 249*unit, 9*unit
    local panelW = columns*tileW + (columns-1)*gap + 26*unit
    local panelH = rows*tileH + (rows-1)*gap + 136*unit
    local x, y = (w-panelW)/2, (h-panelH)/2

    local cls = ue.load("/Game/UI/Widget_ConaptUnlockText.Widget_ConaptUnlockText_C")
    local lib = ue.object("/Script/UMG.Default__WidgetBlueprintLibrary")
    local widget = lib:Create(pc,cls,pc)
    assert(ue.valid(widget),"Cannot open the Photo Studio")
    local tree = widget.WidgetTree
    local root = StaticConstructObject(ue.object("/Script/UMG.CanvasPanel"),tree)
    tree.RootWidget = root
    local font = ue.load("/Engine/EngineFonts/Roboto.Roboto")
    local widgetPath = "/Script/UMG.Widget:"
    local function color(r,g,b,a) return {R=r,G=g,B=b,A=a or 1} end
    local ink = color(.89,.88,.79)
    local quiet = color(.56,.62,.55)
    local gold = color(.94,.69,.38)
    local buttonColor, hoverColor = color(.092,.119,.097), color(.20,.22,.14)

    local function add(kind,px,py,sx,sy,parent)
        local child = StaticConstructObject(ue.object("/Script/UMG."..kind),tree)
        local slot = ue.call("/Script/UMG.CanvasPanel:AddChildToCanvas",parent or root,child)
        ue.call("/Script/UMG.CanvasPanelSlot:SetPosition",slot,{X=px/dpi,Y=py/dpi})
        ue.call("/Script/UMG.CanvasPanelSlot:SetSize",slot,{X=sx/dpi,Y=sy/dpi})
        return child
    end
    local function block(px,py,sx,sy,c,parent)
        local b = add("Border",px,py,sx,sy,parent)
        b:SetBrushColor(c)
        return b
    end
    local function label(px,py,sx,sy,size,value,c,center,parent)
        local t = add("TextBlock",px,py,sx,sy,parent)
        t:SetFont({FontObject=font,TypefaceFontName=FName("Regular"),Size=size*unit/dpi})
        t:SetText(FText(value))
        t:SetColorAndOpacity({SpecifiedColor=c,ColorUseRule=0})
        if center then ue.call("/Script/UMG.TextLayoutWidget:SetJustification",t,1) end
        return t
    end
    local textures = {}
    local function texture(name)
        if not ue.valid(textures[name]) then
            local rendering = ue.object("/Script/Engine.Default__KismetRenderingLibrary")
            textures[name] = rendering:ImportFileAsTexture2D(pc,assets..name..".png")
            assert(ue.valid(textures[name]),"Missing Photo Studio art "..name)
        end
        return textures[name]
    end
    local function picture(name,px,py,sx,sy,opacity,parent)
        local image = add("Image",px,py,sx,sy,parent)
        image:SetBrushFromTexture(texture(name),false)
        if opacity ~= 1 then ue.call(widgetPath.."SetRenderOpacity",image,opacity) end
        return image
    end
    local function glyph(name,px,py,size)
        return picture("Studio/ui-"..name,px,py,size,size,1)
    end
    buildControls(ue,ui,{
        add=add,block=block,picture=picture,
        text=function(px,py,sx,sy,size,c,value,parent)
            return label(px,py,sx,sy,size,value,c,false,parent)
        end,
    },unit)

    local targets, buttons = {}, {}
    local function hitBox(px,py,sx,sy,action,card,step,background)
        local target = {
            x=px/dpi,y=py/dpi,w=sx/dpi,h=sy/dpi,
            action=action,card=card,step=step,background=background,
        }
        targets[#targets+1] = target
        if background then
            target.focusMark = block(px+unit,py+3*unit,2*unit,sy-6*unit,gold)
            ue.call(widgetPath.."SetVisibility",target.focusMark,2)
            buttons[#buttons+1] = target
            target.index = #buttons
        end
        return target
    end
    local function button(px,py,sx,sy,title,action,card,step,size,icon)
        local background = block(px,py,sx,sy,buttonColor)
        block(px,py,sx,unit,color(.16,.21,.17))
        local iconWidth = icon and 18*unit or 0
        local image = icon and glyph(icon,px+5*unit,py+(sy-12*unit)/2,12*unit)
        local text = label(px+iconWidth,py+(size and 1 or 4)*unit,sx-iconWidth-2*unit,sy,
            size or (icon and 9.2 or 10),title,ink,true)
        local target = hitBox(px,py,sx,sy,action,card,step,background)
        return text,image,target
    end
    local function stepper(px,py,sx,titleSize,action,card)
        local arrowW, height = 22*unit, 22*unit
        button(px,py,arrowW,height,"‹",action,card,-1,15)
        button(px+sx-arrowW,py,arrowW,height,"›",action,card,1,15)
        return label(px+arrowW,py+3*unit,sx-2*arrowW,height,titleSize,"",ink,true)
    end

    local hovered, focused, lastX, lastY, updateContext
    local function paint(target)
        if not target or not target.background then return end
        target.background:SetBrushColor(target == hovered and hoverColor or buttonColor)
        ue.call(widgetPath.."SetVisibility",target.focusMark,target == focused and 3 or 2)
    end
    local function focus(target)
        local previous = focused
        focused = target
        paint(previous)
        paint(focused)
        if updateContext then updateContext() end
    end
    function ui.focus(action, step, card)
        for _, target in ipairs(buttons) do
            if target.action == action and target.step == step and (not card or target.card == card) then
                focus(target)
                return
            end
        end
        focus(nil)
    end
    function ui.tab(backward)
        local index = focused and focused.index or (backward and 1 or 0)
        focus(buttons[(index - 1 + (backward and -1 or 1)) % #buttons + 1])
    end
    function ui.focused() return focused end

    function ui.pointer(px,py,clicked)
        local target
        if px and py then
            for i = #targets, 1, -1 do
                local item = targets[i]
                if px>=item.x and px<item.x+item.w and py>=item.y and py<item.y+item.h then
                    target = item
                    break
                end
            end
        end
        if clicked or (lastX and px and (lastX ~= px or lastY ~= py)) then focus(nil) end
        lastX, lastY = px, py
        if target ~= hovered then
            local previous = hovered
            hovered = target
            paint(previous)
            paint(hovered)
            if updateContext then updateContext() end
        end
        if clicked then return target end
    end
    function ui.visible(visible)
        if not visible then
            local previous = hovered
            hovered, lastX, lastY = nil, nil, nil
            paint(previous)
        end
        ue.call(widgetPath.."SetVisibility",widget,visible and 3 or 2)
    end
    function ui.close() ue.call(widgetPath.."RemoveFromParent",widget) end
    local function attach()
        ui.visible(true)
        ue.call("/Script/UMG.UserWidget:AddToViewport",widget,90)
        ue.call("/Script/UMG.UserWidget:SetDesiredSizeInViewport",widget,{X=w/dpi,Y=h/dpi})
        ue.call("/Script/UMG.UserWidget:SetPositionInViewport",widget,{X=0,Y=0},false)
        return ui
    end

    block(0,0,w,h,color(.006,.011,.009,.67))
    if keyPage then
        local group = binds.groups[keyPage]
        local keyW,keyH = math.min(panelW,550*unit), (145 + (#group-1)*29)*unit
        local left,top = (w-keyW)/2,(h-keyH)/2
        local innerX,innerW = left+13*unit,keyW-26*unit
        block(left,top,keyW,keyH,color(.025,.038,.032,.98))
        block(left,top,keyW,2*unit,gold)
        label(innerX,top+8*unit,innerW,30*unit,20,"PHOTO STUDIO / KEYBINDS",ink)
        local tabW = (innerW-(#binds.groups-1)*5*unit)/#binds.groups
        for i, group in ipairs(binds.groups) do
            local px = innerX+(i-1)*(tabW+5*unit)
            button(px,top+41*unit,tabW,23*unit,group[1]:upper(),"bindPage",nil,i)
            if i == keyPage then block(px,top+62*unit,tabW,2*unit,gold) end
        end
        local captions = {}
        for i=2,#group do
            local id,title = group[i][1],group[i][2]
            local py = top+(72+(i-2)*29)*unit
            local background = block(innerX,py,innerW,25*unit,buttonColor)
            label(innerX+8*unit,py+4*unit,innerW-153*unit,20*unit,11,title,ink)
            block(innerX+innerW-138*unit,py+2*unit,134*unit,21*unit,color(.15,.18,.15))
            local caption = label(innerX+innerW-138*unit,py+4*unit,134*unit,21*unit,10,binds.label(id),ink,true)
            captions[id] = caption
            hitBox(innerX,py,innerW,25*unit,"bindKey",nil,id,background)
        end
        local footerY = top+keyH-69*unit
        local back = button(innerX,footerY,123*unit,24*unit,"BACK TO STUDIO","bindBack",nil,nil,nil,"back")
        local reset = button(innerX+innerW-132*unit,footerY,132*unit,24*unit,"RESET DEFAULTS","bindReset")
        local status = label(innerX,footerY+27*unit,innerW,18*unit,10,"",gold)
        ui.addControlRow(innerX,footerY+46*unit,innerW,{
            {"tab",0,"Focus",binds.tabHint()}, {"enter",0,"Activate","Enter"},
            {"studio",0,"Back",binds.token("studio")},
        },nil,true,.83)
        function ui.keyStatus(capturing, message, resetting)
            for id, caption in pairs(captions) do
                caption:SetText(FText(id == capturing and "PRESS INPUT" or binds.label(id)))
            end
            back:SetText(FText(capturing and "CANCEL REBIND" or "BACK TO STUDIO"))
            reset:SetText(FText(resetting and "CONFIRM RESET" or "RESET DEFAULTS"))
            local prompt = "Select a binding to change it. Changes save automatically."
            if capturing == "fine" then
                prompt = "Press Left Shift or Right Shift."
            elseif capturing then
                prompt = "Press the new key, mouse button, or wheel direction."
            end
            status:SetText(FText(message or prompt))
        end
        return attach()
    end

    if exposurePage then
        local pw, ph = (wide and 960 or 580)*unit, (wide and 374 or 524)*unit
        local left, top = (w-pw)/2, (h-ph)/2
        local innerX, innerW = left+13*unit, pw-26*unit
        block(left,top,pw,ph,color(.025,.038,.032,.98))
        block(left,top,pw,2*unit,gold)
        glyph("exposure",innerX,top+13*unit,21*unit)
        label(innerX+29*unit,top+9*unit,innerW,26*unit,19,"PHOTO STUDIO / EXPOSURE",ink)
        local modesY, isoY = top+49*unit, top+(wide and 49 or 220)*unit
        local column = wide and (innerW-16*unit)/2 or innerW
        local isoX = wide and innerX+column+16*unit or innerX
        label(innerX,modesY,column,18*unit,10,"EXPOSURE MODE",gold)
        label(isoX,isoY,column,18*unit,10,"SENSITIVITY / OPTICS",gold)
        local rows, markers, values = {}, {}, {}
        local descriptions = {"Game controls brightness", "You set aperture and shutter",
            "You set aperture", "You set shutter speed"}
        for i, mode in ipairs(exposure.modes) do
            local py = modesY+(21+(i-1)*34)*unit
            local _,_,target = button(innerX,py,column,29*unit,"","exposureMode",nil,i)
            label(innerX+12*unit,py+6*unit,41*unit,18*unit,11,mode[1],gold)
            label(innerX+57*unit,py+3*unit,column-62*unit,14*unit,10,mode[2],ink)
            label(innerX+57*unit,py+15*unit,column-62*unit,12*unit,8,descriptions[i],quiet)
            markers[i] = block(innerX+column-6*unit,py+5*unit,2*unit,19*unit,gold)
            rows[#rows+1] = target
        end
        local names = {{"auto","Auto ISO"}, {"minISO","Minimum ISO"},
            {"maxISO","Maximum ISO"}, {"minShutter","Minimum shutter in A"},
            {"dofBoost","Depth of field strength"}}
        for i, row in ipairs(names) do
            local id, title = row[1], row[2]
            local py = isoY+(21+(i-1)*34)*unit
            block(isoX,py,column,29*unit,buttonColor)
            hitBox(isoX,py,column,29*unit,"exposureHelp",nil,id)
            label(isoX+9*unit,py+7*unit,column-134*unit,17*unit,10,title,ink)
            if i == 1 then
                local caption,_,target = button(isoX+column-120*unit,py,120*unit,29*unit,"",id)
                values[id], rows[#rows+1] = caption, target
            else
                local sx = isoX+column-120*unit
                local _,_,target = button(sx,py,23*unit,29*unit,"‹",id,nil,-1,15)
                button(isoX+column-23*unit,py,23*unit,29*unit,"›",id,nil,1,15)
                values[id] = label(sx+23*unit,py+7*unit,74*unit,17*unit,10,"",ink,true)
                rows[#rows+1] = target
            end
        end
        local infoY = isoY+195*unit
        local info = label(isoX,infoY,column,18*unit,9,"",quiet)
        local currentConfig
        updateContext = function()
            if not currentConfig then return end
            local target = hovered or focused
            local action = target and target.action
            if action == "exposureHelp" then action = target.step end
            info:SetText(FText(exposure.help(currentConfig,action,target and target.step)))
        end
        local footerY = top+ph-68*unit
        button(innerX,footerY,132*unit,24*unit,"BACK TO STUDIO","exposureBack",nil,nil,nil,"back")
        button(innerX+innerW-134*unit,footerY,134*unit,24*unit,
            raised and "LOWER VIEWFINDER" or "RAISE VIEWFINDER","finder",nil,nil,nil,"finder")
        local notice = label(innerX,footerY+25*unit,innerW,16*unit,9,"",gold)
        local hint = label(innerX,footerY+43*unit,innerW,16*unit,9,"",quiet)
        function ui.notice(value) notice:SetText(FText(value)) end
        function ui.update(_,_,_,_,_,config,controller)
            currentConfig = config
            for i, mark in ipairs(markers) do ue.call(widgetPath.."SetVisibility",mark,i==config.mode and 3 or 2) end
            values.auto:SetText(FText(config.auto and "ON" or "OFF"))
            values.minISO:SetText(FText(tostring(config.isos[config.minISO])))
            values.maxISO:SetText(FText(tostring(config.isos[config.maxISO])))
            values.minShutter:SetText(FText(config.speedText(config.speeds[config.minShutter])))
            values.dofBoost:SetText(FText(config.dofStrengths[config.dofBoost].."x"))
            updateContext()
            hint:SetText(FText(controller and "D-PAD   Navigate / adjust       A   Select       B   Back"
                or "ARROWS   Navigate / adjust       ENTER   Select       TAB   Next control"))
        end
        function ui.moveExposureFocus(direction)
            local index
            for i,target in ipairs(rows) do
                if focused and target.action==focused.action
                        and (target.action~="exposureMode" or target.step==focused.step) then index=i; break end
            end
            focus(rows[index and ((index-1+direction)%#rows+1) or (direction>0 and 1 or #rows)])
        end
        function ui.tick() end
        return attach()
    end

    block(x,y,panelW,panelH,color(.025,.038,.032,.98))
    block(x,y,panelW,2*unit,gold)
    local innerX, innerW = x+13*unit,panelW-26*unit
    glyph("finder",innerX,y+13*unit,21*unit)
    label(innerX+29*unit,y+7*unit,innerW-29*unit,27*unit,19,"PHOTO STUDIO",ink)
    label(innerX+29*unit,y+32*unit,innerW-29*unit,16*unit,9,"CAMERA SETUP",quiet)

    local footerY = y+panelH-67*unit
    local notice = label(innerX,footerY-16*unit,innerW,16*unit,10,"",gold)
    local keyboardHints = add("CanvasPanel",innerX,footerY+29*unit,innerW,36*unit)
    local controllerHints = add("CanvasPanel",innerX,footerY+29*unit,innerW,36*unit)
    ui.addControlRow(0,0,innerW,{
        {"cards",0,"Card",binds.token("menuLeft"),binds.token("menuRight")},
        {"values",0,"Change",binds.token("menuNext"),binds.token("menuPrev")},
        {"use",0,"Card action",binds.token("menuSelect")},
    },keyboardHints,true,.86)
    ui.addControlRow(0,18*unit,innerW,{
        {"tab",0,"Focus",binds.tabHint()}, {"enter",0,"Activate","Enter"},
        {"studio",0,"Back",binds.token("studio")},
    },keyboardHints,true,.86)
    ui.addControlRow(0,0,innerW,{
        {"padCards",0,"Card","←","→"}, {"padValues",0,"Change","↑","↓"},
        {"padControls",0,"Control","LB","RB"},
        {"padSelect",0,"Select","A"}, {"padBack",0,"Back","B"}, {"padFinder",0,"Finder","LT"},
    },controllerHints,true,.86)

    local tiles = {}
    local cellW, cellH = 100*unit, (96/112)*100*unit
    for i, card in ipairs(cards) do
        local row = math.floor((i-1)/columns)
        local rowCount = math.min(columns,#cards-row*columns)
        local px = x+13*unit+((i-1)%columns+(columns-rowCount)/2)*(tileW+gap)
        local py = y+49*unit+row*(tileH+gap)
        local tile = {}
        tiles[card] = tile
        tile.back = block(px,py,tileW,tileH,color(.049,.067,.056))
        tile.rule = block(px,py,2*unit,tileH,color(.21,.27,.21))
        block(px+2*unit,py+1*unit,tileW-3*unit,20*unit,color(.030,.047,.039))
        local icon = card == "subjects" and "subject" or card
        glyph(icon,px+9*unit,py+5*unit,12*unit)
        label(px+27*unit,py+5*unit,tileW-34*unit,17*unit,9,("%02d  %s"):format(i,card:upper()),quiet)
        do
            local clip = add("CanvasPanel",px+(tileW-cellW)/2,py+19*unit,cellW,cellH)
            ue.call(widgetPath.."SetClipping",clip,1)
            tile.image = add("Image",0,0,8*cellW,6*cellH,clip)
        end
        hitBox(px,py,tileW,tileH,"card",i)
        local innerX, innerW = px+9*unit,tileW-18*unit
        if card == "photos" then
            tile.value = label(innerX,py+110*unit,innerW,20*unit,14,"",ink,true)
            tile.detail = label(innerX,py+134*unit,innerW,17*unit,10,"",quiet,true)
            button(innerX,py+156*unit,innerW,21*unit,"OPEN FOLDER","select",i,nil,nil,"photos")
            button(innerX,py+181*unit,innerW,21*unit,"CHOOSE FOLDER","choosePhotos",i,nil,nil,"photos")
            button(innerX,py+205*unit,innerW,12*unit,"USE DEFAULT","resetPhotos",i,nil,7)
        elseif card == "exposure" then
            tile.value = label(innerX,py+110*unit,innerW,20*unit,13,"",ink,true)
            tile.detail = label(innerX,py+134*unit,innerW,17*unit,10,"",quiet,true)
            button(innerX,py+156*unit,innerW,21*unit,"EDIT EXPOSURE","exposureOpen",i)
        else
            tile.value = stepper(innerX,py+108*unit,innerW,card == "film" and 8.6 or 11,"step",i)
            tile.detail = label(innerX,py+135*unit,innerW,18*unit,card == "film" and 9 or 10,"",quiet,true)
            if card == "lens" then
                ui.addControlRow(px+tileW/2,py+160*unit,innerW,{
                    {"lens",0,"Change lens",binds.token("lensPrev"),binds.token("lensNext")},
                },nil,false,.85)
                tile.scaling = button(innerX,py+189*unit,innerW,22*unit,"","aimScaling",i)
            elseif card == "film" then
                label(innerX,py+159*unit,innerW,15*unit,9,"Grain follows ISO",quiet,true)
            elseif card == "frame" then
                tile.rotate = button(innerX,py+156*unit,innerW,21*unit,"ROTATE FRAME","portrait",i,nil,nil,"rotate")
                glyph("reticle",innerX+3*unit,py+181*unit,11*unit)
                label(innerX+20*unit,py+181*unit,innerW-20*unit,13*unit,8,"RETICLE",quiet)
                tile.reticle = stepper(innerX,py+194*unit,innerW,9.5,"reticle",i)
                tile.grid = button(innerX,py+223*unit,innerW,21*unit,"","grid",i,nil,nil,"frame")
            elseif card == "subjects" then
                button(innerX,py+156*unit,innerW,21*unit,"PLACE SUBJECT","select",i,nil,nil,"subject")
                ui.addControlRow(px+tileW/2,py+185*unit,innerW,{
                    {"placeStart",0,"Shortcut",binds.token("placeStart")},
                },nil,false,.85)
            end
        end
    end

    local footerGap = 8*unit
    local backW, keyW, finderW = 126*unit, 86*unit, 134*unit
    button(innerX,footerY,backW,24*unit,"BACK TO CAMERA","close",nil,nil,nil,"back")
    button(innerX+backW+footerGap,footerY,keyW,24*unit,"KEYBINDS","keybinds",nil,nil,nil,"keybinds")
    button(innerX+innerW-finderW,footerY,finderW,24*unit,
        raised and "LOWER VIEWFINDER" or "RAISE VIEWFINDER","finder",nil,nil,nil,"finder")

    local function drawFrame(tile, cell)
        ue.call(widgetPath.."SetRenderTranslation",tile.image,
            {X=-(cell%8)*cellW/dpi,Y=-math.floor(cell/8)*cellH/dpi})
    end
    local previous
    function ui.update(selected,content,portrait,square,reticle,config,controller)
        ue.call(widgetPath.."SetVisibility",keyboardHints,controller and 2 or 3)
        ue.call(widgetPath.."SetVisibility",controllerHints,controller and 3 or 2)
        for i, card in ipairs(cards) do
            local tile, data = tiles[card], content[card]
            tile.back:SetBrushColor(i == selected and color(.12,.145,.103) or color(.049,.067,.056))
            tile.rule:SetBrushColor(i == selected and gold or color(.21,.27,.21))
            if card == "exposure" then
                local mode = config.modes[config.mode]
                tile.value:SetText(FText(mode[2]))
                tile.detail:SetText(FText(config.auto and config.mode~=1 and "Auto ISO on"
                    or "ISO "..config.isos[config.iso]))
            else
                tile.value:SetText(FText(data[1]))
                tile.detail:SetText(FText(data[2]))
            end
            local art = card == "exposure" and "exposure" or data[3]
            if tile.image and tile.art ~= art then
                tile.image:SetBrushFromTexture(texture("Studio/"..art),false)
                tile.art = art
                tile.start = previous
                drawFrame(tile,0)
            end
        end
        local rotate = tiles.frame.rotate
        rotate:SetText(FText(square and "SQUARE FRAME" or (portrait and "SET LANDSCAPE" or "SET PORTRAIT")))
        rotate:SetColorAndOpacity({SpecifiedColor=square and quiet or ink,ColorUseRule=0})
        tiles.frame.reticle:SetText(FText(reticle))
        tiles.frame.grid:SetText(FText(config.grid and "THIRDS GRID ON" or "THIRDS GRID OFF"))
        tiles.lens.scaling:SetText(FText(content.lens[4] and "AIM SCALING ON" or "AIM SCALING OFF"))
    end
    function ui.tick(now)
        local frame = math.floor(now*10)
        if previous == frame then return end
        previous = frame
        for _,tile in pairs(tiles) do
            if tile.image then
                tile.start = tile.start or frame
                drawFrame(tile,(frame-tile.start)%48)
            end
        end
    end
    function ui.notice(value) notice:SetText(FText(value)) end
    return attach()
end
