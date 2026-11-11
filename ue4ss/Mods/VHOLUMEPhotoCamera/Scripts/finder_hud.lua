local directory = assert(debug.getinfo(1, "S").source:match("^@(.+[\\/])"))
local buildDigits = dofile(directory .. "lcd_digits.lua")

return function(ue, ui, rect, binds, controller, draw)
    local u, dpi = rect.unit, rect.dpi
    local x, y, fw, fh, w = rect.x, rect.y, rect.w, rect.h, rect.width
    local bottom = y + fh
    local function rgb(r, g, b) return {R=r,G=g,B=b,A=1} end
    local ink, dim = rgb(.75,.81,.72), rgb(.39,.49,.42)
    local gold, activeInk = rgb(.99,.76,.44), rgb(.68,.92,.58)
    local lcdInk, lcdActive = rgb(.017,.029,.019), rgb(.19,.075,.015)
    local edge = rgb(.055,.075,.062)
    local function block(left, top, width, height, color)
        return draw.block(left,top,width,height,color)
    end
    local function label(left, top, width, size, color, value, justify)
        if value then size = math.min(size, width / (u * math.max(1,ui.textWidth(value,1)))) end
        local element = draw.text(left,top,width,math.max(9,size+3)*u,size,color,value)
        if justify then ue.call("/Script/UMG.TextLayoutWidget:SetJustification",element,justify) end
        return element
    end
    local function shortcut(id, title, key, left, top, width, color, highlight, justify)
        local value = title .. " [" .. key .. "]"
        local element = label(left,top,width,6.3,color,value,justify)
        ui.trackControl(id,element,color,highlight)
    end
    local mouseNames = {["mouse-left"]="LMB", ["mouse-middle"]="MMB", ["mouse-right"]="RMB", ["mouse-wheel"]="Wheel"}
    local function token(id)
        local value = binds.token(id)
        return mouseNames[value] or value
    end
    local function dial(id, pad)
        if controller then return pad end
        return binds.wheelChords[id]:gsub(" ", "") .. "+Wheel"
    end

    local headerWidth = math.min(w-16*u,math.max(fw,510*u))
    local headerX, headerY = (w-headerWidth)/2, y-31*u
    local leftWidth = headerWidth/2-58*u
    local fields, last, digits, autoTags = {}, {}, {}, {}
    local function set(id, value)
        if last[id] == value then return end
        last[id] = value
        if digits[id] then digits[id].set(value) else fields[id]:SetText(FText(value)) end
    end

    label(headerX,headerY+2*u,24*u,6.5,dim,"FRAME")
    block(headerX+25*u,headerY+u,29*u,12*u,edge)
    fields.number = label(headerX+25*u,headerY+2*u,29*u,8,ink,nil,1)
    function ui.setFrameNumber(number) set("number",string.format("%03d",number)) end

    local lcdW = math.min(w-16*u,550*u)
    local lcdX, lcdY = (w-lcdW)/2,bottom+2*u
    block(lcdX,lcdY,lcdW,27*u,edge)
    draw.picture("Controls/finder-lcd",lcdX+u,lcdY+u,lcdW-2*u,25*u,1)
    local cellX = lcdX+u
    for i, item in ipairs({
        {"exposureMode","MODE",dial("mode","↑"),.19},
        {"shutter","SHUTTER",dial("shutter","LB+←/→"),.23},
        {"aperture","APERTURE",dial("aperture","LB+↑/↓"),.20},
        {"iso","ISO",dial("iso","RB+↑/↓"),.20},
        {"lens","LENS",dial("lens","←/→"),.18},
    }) do
        local id, title, input, fraction = table.unpack(item)
        local cellW = (lcdW-2*u)*fraction
        if i > 1 then block(cellX,lcdY+3*u,u,21*u,rgb(.31,.38,.26)) end
        shortcut(id,title,input,cellX+5*u,lcdY+2*u,cellW-10*u,lcdInk,lcdActive)
        if id == "shutter" or id == "aperture" or id == "iso" then
            digits[id] = buildDigits(ue,draw,dpi,cellX+3*u,lcdY+9*u,cellW-18*u,16*u)
            autoTags[id] = label(cellX+cellW-20*u,lcdY+17*u,18*u,5,lcdInk,"AUTO",2)
            ue.call("/Script/UMG.Widget:SetVisibility",autoTags[id],2)
        else
            fields[id] = label(cellX+2*u,lcdY+9*u,cellW-4*u,12.5,lcdInk,nil,1)
        end
        cellX = cellX+cellW
    end
    ui.lens = fields.lens

    local focusWidth = rect.bottomFocus and math.min(w-16*u,440*u)
        or math.min(215*u,(w-lcdW)/2-14*u)
    local focusX = rect.bottomFocus and (w-focusWidth)/2 or lcdX+lcdW+8*u
    local focusY = bottom+(rect.bottomFocus and 31 or 2)*u
    local afWidth = focusWidth*.43
    shortcut("af","SINGLE-SHOT AF",controller and "A" or token("af"),focusX,focusY,afWidth,ink,gold)
    local indicators = {}
    for i, name in ipairs({"near","aligned","far"}) do
        indicators[i] = draw.picture("Studio/focus-"..name,focusX+afWidth+(i-1)*10*u,focusY,9*u,9*u,.20)
    end
    local modeX = focusX+afWidth+33*u
    shortcut("mode","AF/MF",controller and "X" or token("mode"),modeX,focusY,focusX+focusWidth-modeX,ink,activeInk,2)
    local focusKeys = binds.focusTokens()
    for i, key in ipairs(focusKeys) do focusKeys[i] = mouseNames[key] or key end
    local focusInput = table.concat(focusKeys,"/")
    shortcut("focus","FOCUS",controller and "RB+←/→" or focusInput,
        focusX,focusY+10*u,focusWidth*.47,ink,gold)
    shortcut("fine","FINE FOCUS",controller and "RB+A+←/→" or token("fine").."+"..focusInput,
        focusX+focusWidth*.47,focusY+10*u,focusWidth*.53,ink,gold,2)
    ui.focus = label(focusX,focusY+20*u,focusWidth*.5,7,ink)
    ui.subject = label(focusX+focusWidth*.5,focusY+20*u,focusWidth*.5,7,dim,nil,2)
    local lastIndicator
    function ui.setFocusIndicator(direction)
        if lastIndicator == direction then return end
        lastIndicator = direction
        for i, indicator in ipairs(indicators) do
            ue.call("/Script/UMG.Widget:SetRenderOpacity",indicator,i == direction and 1 or .20)
        end
    end


    local track = math.min(236*u,headerWidth*.44)
    local trackX, trackY = w/2-track/2,headerY+15*u
    label(trackX,headerY,track,7,ink,"EXPOSURE",1)
    block(trackX,trackY,track,.6*u,dim)
    for i=0,12 do
        local whole = i%3 == 0
        block(trackX+track*i/12,trackY-(whole and 2 or 1)*u,.6*u,(whole and 5 or 3)*u,dim)
        if whole then
            local ev = i/3-2
            label(trackX+track*i/12-10*u,trackY+5*u,20*u,6,dim,
                ev == 0 and "0" or string.format("%+d",ev),1)
        end
    end
    local needle = block(w/2-u,trackY-2*u,2*u,5*u,gold)
    fields.meter = label(headerX,headerY+17*u,leftWidth,8,gold)
    fields.warning = label(headerX+headerWidth-leftWidth,headerY+17*u,leftWidth,7,gold,nil,2)
    local lastEV
    function ui.setExposure(mode, values, speed)
        set("exposureMode",mode)
        set("aperture",string.format("f/%.1f",values.aperture))
        set("shutter",speed:gsub(" s",""):gsub(" ","")..(values.speed <= 1 and "s" or ""))
        set("iso",tostring(values.iso))
        for id, tag in pairs(autoTags) do
            local auto = values[id.."Auto"] == true
            if last[id.."Auto"] ~= auto then
                last[id.."Auto"] = auto
                ue.call("/Script/UMG.Widget:SetVisibility",tag,auto and 3 or 2)
            end
        end
        local ev = values.errorEV
        set("meter",mode == "GAME" and "GAME" or (ev and string.format("%+.1f EV",ev) or "NO METER"))
        set("warning",values.limited or "")
        if lastEV ~= ev then
            lastEV = ev
            ue.call("/Script/UMG.Widget:SetVisibility",needle,ev and 3 or 2)
            if ev then
                local offset = math.max(-2,math.min(2,ev))*track/(4*dpi)
                ue.call("/Script/UMG.Widget:SetRenderTranslation",needle,{X=offset,Y=0})
            end
        end
    end
    ue.call("/Script/UMG.Widget:SetVisibility",needle,2)

    local filmKey, ratioKey = dial("film","RB+X"),dial("ratio","↓")
    local actions = {
        {"shoot","TAKE PHOTO",controller and "RT" or token("shoot"),gold},
        {"finder","LOWER FINDER",controller and "LT" or token("finder"),gold},
        {"studio","PHOTO STUDIO",controller and "Y" or token("studio"),gold},
        {"frame","ROTATE",controller and "RB+Y" or token("frame"),gold},
        {"dof","DOF",controller and "B" or token("dof"),activeInk},
        {"walk","SLOW WALK",controller and "L3" or token("walk"),activeInk},
    }
    if rect.sideControls then
        local left, width = x-101*u,91*u
        local formatY = y+fh*.37
        block(left,formatY-4*u,width,.7*u,edge)
        shortcut("film","FILM",filmKey,left,formatY,width,ink,gold)
        fields.film = label(left,formatY+10*u,width,10,ink)
        block(left,formatY+24*u,width,.7*u,edge)
        shortcut("ratio","ASPECT",ratioKey,left,formatY+28*u,width,ink,gold)
        fields.ratio = label(left,formatY+38*u,width,10,ink)
        local actionY = bottom-math.min(111*u,fh*.23)
        block(left,actionY-3*u,width,.7*u,edge)
        for i, item in ipairs(actions) do
            shortcut(item[1],item[2],item[3],left,actionY+(i-1)*12*u,width,ink,item[4])
        end
    else
        local footerX, footerW = 8*u,w-16*u
        local offset = rect.bottomFocus and 30*u or 0
        fields.film = label(footerX,bottom+29*u+offset,footerW/2,7,ink,nil,1)
        fields.ratio = label(footerX+footerW/2,bottom+29*u+offset,footerW/2,7,ink,nil,1)
        ui.trackControl("film",fields.film,ink,gold)
        ui.trackControl("ratio",fields.ratio,ink,gold)
        local cellW = footerW/#actions
        for i, item in ipairs(actions) do
            shortcut(item[1],item[2],item[3],footerX+(i-1)*cellW,bottom+37*u+offset,cellW,ink,item[4],1)
        end
    end
    function ui.setFormat(stock)
        local ratio = string.format("%d:%d",rect.columns,rect.rows)
        set("film",rect.sideControls and stock or ("FILM ["..filmKey.."]  "..stock))
        set("ratio",rect.sideControls and ratio or ("ASPECT ["..ratioKey.."]  "..ratio))
    end

    local dial, secondDial
    function ui.setDial(first, second)
        if first == "mode" then first = "exposureMode" end
        if first == dial and second == secondDial then return end
        if dial then ui.setControlActive(dial,false) end
        if secondDial then ui.setControlActive(secondDial,false) end
        if first then ui.setControlActive(first,true) end
        if second then ui.setControlActive(second,true) end
        dial,secondDial = first,second
    end
end
