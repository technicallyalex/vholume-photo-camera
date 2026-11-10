return function(ue, ui, rect, binds, controller, draw)
    local u, dpi = rect.unit, rect.dpi
    local x, y, fw, fh, w = rect.x, rect.y, rect.w, rect.h, rect.width
    local bottom = y + fh
    local function rgb(r, g, b) return {R=r,G=g,B=b,A=1} end
    local ink, dim = rgb(.75,.81,.72), rgb(.39,.49,.42)
    local gold, activeInk = rgb(.99,.76,.44), rgb(.68,.92,.58)
    local lcd, lcdInk, lcdActive = rgb(.46,.52,.36), rgb(.017,.029,.019), rgb(.19,.075,.015)
    local edge, rail = rgb(.055,.075,.062), rgb(.010,.016,.013)
    local function block(left, top, width, height, color)
        return draw.block(left,top,width,height,color)
    end
    local function label(left, top, width, size, color, value, justify)
        if value then size = math.min(size, width / (u * .67 * math.max(1, utf8.len(value)))) end
        local element = draw.text(left,top,width,math.max(9,size+3)*u,size,color,value)
        if justify then ue.call("/Script/UMG.TextLayoutWidget:SetJustification",element,justify) end
        return element
    end
    local function shortcut(id, title, key, left, top, width, color, highlight, justify)
        local value = title .. " [" .. key .. "]"
        local element = label(left,top,width,7,color,value,justify)
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
    local focusWidth = math.min(227*u,leftWidth)
    local focusX = headerX+headerWidth-focusWidth
    local fields, last = {}, {}
    local function set(id, value)
        if last[id] ~= value then fields[id]:SetText(FText(value)); last[id] = value end
    end

    label(headerX,headerY+2*u,24*u,6.5,dim,"FRAME")
    block(headerX+25*u,headerY+u,29*u,12*u,edge)
    fields.number = label(headerX+25*u,headerY+2*u,29*u,8,ink,nil,1)
    function ui.setFrameNumber(number) set("number",string.format("%03d",number)) end

    shortcut("aperture","APERTURE",dial("aperture","LB+↑/↓"),w/2-55*u,headerY,110*u,ink,gold,1)
    block(w/2-41*u,headerY+10*u,82*u,17*u,edge)
    block(w/2-40*u,headerY+11*u,80*u,15*u,lcd)
    fields.aperture = label(w/2-40*u,headerY+11*u,80*u,10.5,lcdInk,nil,1)

    local afWidth = focusWidth*.43
    shortcut("af","SINGLE-SHOT AF",controller and "A" or token("af"),focusX,headerY,afWidth,ink,gold)
    local indicators = {}
    for i, name in ipairs({"near","aligned","far"}) do
        indicators[i] = draw.picture("Studio/focus-"..name,focusX+afWidth+(i-1)*10*u,headerY,9*u,9*u,.20)
    end
    local modeX = focusX+afWidth+33*u
    shortcut("mode","AF/MF",controller and "X" or token("mode"),modeX,headerY,focusX+focusWidth-modeX,ink,activeInk,2)
    local focusKeys = binds.focusTokens()
    for i, key in ipairs(focusKeys) do focusKeys[i] = mouseNames[key] or key end
    local focusInput = table.concat(focusKeys,"/")
    shortcut("focus","FOCUS",controller and "RB+←/→" or focusInput,
        focusX,headerY+10*u,focusWidth*.47,ink,gold)
    shortcut("fine","FINE FOCUS",controller and "RB+A+←/→" or token("fine").."+"..focusInput,
        focusX+focusWidth*.47,headerY+10*u,focusWidth*.53,ink,gold,2)
    ui.focus = label(focusX,headerY+20*u,focusWidth*.5,7,ink)
    ui.subject = label(focusX+focusWidth*.5,headerY+20*u,focusWidth*.5,7,dim,nil,2)
    local lastIndicator
    function ui.setFocusIndicator(direction)
        if lastIndicator == direction then return end
        lastIndicator = direction
        for i, indicator in ipairs(indicators) do
            ue.call("/Script/UMG.Widget:SetRenderOpacity",indicator,i == direction and 1 or .20)
        end
    end

    local lcdW = math.min(w-16*u,435*u)
    local lcdX, lcdY = (w-lcdW)/2,bottom+2*u
    block(lcdX,lcdY,lcdW,27*u,edge)
    block(lcdX+u,lcdY+u,lcdW-2*u,25*u,lcd)
    block(lcdX+u,lcdY+u,lcdW-2*u,u,rgb(.62,.67,.49))
    local cellX = lcdX+u
    for i, item in ipairs({
        {"exposureMode","MODE",dial("mode","↑"),.23},
        {"shutter","SHUTTER",dial("shutter","LB+←/→"),.27},
        {"iso","ISO",dial("iso","RB+↑/↓"),.26},
        {"lens","LENS",dial("lens","←/→"),.24},
    }) do
        local id, title, input, fraction = table.unpack(item)
        local cellW = (lcdW-2*u)*fraction
        if i > 1 then block(cellX,lcdY+3*u,u,21*u,rgb(.31,.38,.26)) end
        shortcut(id,title,input,cellX+5*u,lcdY+2*u,cellW-10*u,lcdInk,lcdActive)
        fields[id] = label(cellX+2*u,lcdY+9*u,cellW-4*u,12.5,lcdInk,nil,1)
        cellX = cellX+cellW
    end
    ui.lens = fields.lens

    local side = rect.sideMeter
    local meterX, meterY, meterW
    if side then
        meterW = math.min(x-10*u,94*u)
        meterX, meterY = x+fw+6*u,y+fh/2-80*u
    else
        meterX, meterY, meterW = headerX,headerY+14*u,math.min(100*u,leftWidth-2*u)
    end
    local track = side and math.min(114*u,fh*.55) or (meterW-12*u)
    local trackX, trackY = side and (meterX+meterW*.40) or (meterX+6*u), meterY+(side and 24 or 11)*u
    local needle
    if side then
        label(meterX,meterY,meterW,8,ink,"EV",1)
        for i=0,12 do
            local ty = trackY+track*i/12
            local whole = i%3 == 0
            local width = (whole and 14 or 8)*u
            block(trackX-width/2,ty,width,.6*u,dim)
            if whole then
                local ev = 2-i/3
                label(trackX+10*u,ty-4*u,meterW*.43,7,dim,ev == 0 and "0" or string.format("%+d",ev))
            end
        end
        needle = block(trackX-11*u,trackY+track/2,22*u,1.15*u,gold)
    else
        block(trackX,trackY+2*u,track,.6*u,dim)
        for i=0,4 do block(trackX+track*i/4,trackY,u,4*u,dim) end
        needle = block(trackX+track/2,trackY,1.4*u,4*u,gold)
    end
    local meterTextY = side and trackY+track+9*u or meterY
    fields.meter = label(meterX,meterTextY,meterW,8,gold,nil,side and 1 or nil)
    if side then fields.warning = label(meterX,meterTextY+11*u,meterW,7,gold,nil,1) end
    local lastEV
    function ui.setExposure(mode, values, speed)
        set("exposureMode",mode)
        set("aperture",string.format("f/%.1f",values.aperture)..(values.apertureAuto and "  AUTO" or ""))
        set("shutter",speed..(values.shutterAuto and "  AUTO" or ""))
        set("iso",tostring(values.iso)..(values.isoAuto and "  AUTO" or ""))
        local ev = values.errorEV
        local reading = mode == "GAME" and "GAME" or (ev and string.format("%+.1f EV",ev) or "NO METER")
        set("meter",side and reading or (values.limited or reading))
        if side then set("warning",values.limited or "") end
        if lastEV ~= ev then
            lastEV = ev
            ue.call("/Script/UMG.Widget:SetVisibility",needle,ev and 3 or 2)
            if ev then
                local offset = math.max(-2,math.min(2,ev))*track/(4*dpi)
                ue.call("/Script/UMG.Widget:SetRenderTranslation",needle,
                    {X=side and 0 or offset,Y=side and -offset or 0})
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
        block(left-5*u,formatY-8*u,width+10*u,62*u,rail)
        block(left,formatY-4*u,width,.7*u,edge)
        shortcut("film","FILM",filmKey,left,formatY,width,ink,gold)
        fields.film = label(left,formatY+10*u,width,10,ink)
        block(left,formatY+24*u,width,.7*u,edge)
        shortcut("ratio","ASPECT",ratioKey,left,formatY+28*u,width,ink,gold)
        fields.ratio = label(left,formatY+38*u,width,10,ink)
        local actionY = bottom-math.min(111*u,fh*.23)
        block(left-5*u,actionY-7*u,width+10*u,84*u,rail)
        block(left,actionY-3*u,width,.7*u,edge)
        for i, item in ipairs(actions) do
            shortcut(item[1],item[2],item[3],left,actionY+(i-1)*12*u,width,ink,item[4])
        end
    else
        local footerX, footerW = 8*u,w-16*u
        fields.film = label(footerX,bottom+29*u,footerW/2,7,ink,nil,1)
        fields.ratio = label(footerX+footerW/2,bottom+29*u,footerW/2,7,ink,nil,1)
        ui.trackControl("film",fields.film,ink,gold)
        ui.trackControl("ratio",fields.ratio,ink,gold)
        local cellW = footerW/#actions
        for i, item in ipairs(actions) do
            shortcut(item[1],item[2],item[3],footerX+(i-1)*cellW,bottom+37*u,cellW,ink,item[4],1)
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
