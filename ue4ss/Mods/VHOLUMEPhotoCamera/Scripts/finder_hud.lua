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
        return binds.wheelChord(id):gsub(" ", "") .. "+Wheel"
    end

    local headerWidth = math.min(w-16*u,math.max(fw,510*u))
    local headerX, headerY = (w-headerWidth)/2, y-31*u
    local fields, last, digits, autoTags, fitSpecs = {}, {}, {}, {}, {}
    local displayFont = ue.load("/Engine/EngineFonts/Roboto.Roboto")
    local function set(id, value)
        if last[id] == value then return end
        last[id] = value
        if digits[id] then digits[id].set(value)
        else
            local spec = fitSpecs[id]
            if spec then
                local size = math.min(spec.size,spec.width/(u*math.max(1,ui.textWidth(value,1))))
                fields[id]:SetFont({FontObject=displayFont,TypefaceFontName=FName("Regular"),Size=size*u/dpi})
            end
            fields[id]:SetText(FText(value))
        end
    end

    label(headerX,headerY+2*u,24*u,6.5,dim,"FRAME")
    block(headerX+25*u,headerY+u,29*u,12*u,edge)
    fields.number = label(headerX+25*u,headerY+2*u,29*u,8,ink,nil,1)
    function ui.setFrameNumber(number) set("number",string.format("%03d",number)) end

    local lcdW = math.min(fw,550*u)
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
            digits[id] = buildDigits(ue,draw,dpi,cellX+6*u,lcdY+10*u,cellW-24*u,13*u)
            autoTags[id] = label(cellX+cellW-20*u,lcdY+17*u,18*u,5,lcdInk,"AUTO",2)
            ue.call("/Script/UMG.Widget:SetVisibility",autoTags[id],2)
        else
            fields[id] = label(cellX+6*u,lcdY+10*u,cellW-12*u,10,lcdInk,nil,1)
            fitSpecs[id] = {width=cellW-12*u,size=10}
        end
        cellX = cellX+cellW
    end
    ui.lens = fields.lens
    function ui.setLens(value) set("lens",value) end

    local sideWidth = 91*u
    local focusX = x+fw+10*u
    local panelY = y+fh/2-74*u
    local indicatorX = rect.bottomFocus and 8*u or lcdX-70*u
    local indicatorY = rect.bottomFocus and bottom+34*u or lcdY+4*u
    local indicators = {}
    for i, name in ipairs({"near","aligned","far"}) do
        indicators[i] = draw.picture("Studio/focus-"..name,indicatorX+(i-1)*20*u,indicatorY,18*u,18*u,.16)
    end
    local focusKeys = binds.focusTokens()
    for i, key in ipairs(focusKeys) do focusKeys[i] = mouseNames[key] or key end
    local focusInput = table.concat(focusKeys,"/")
    shortcut("focus","FOCUS",controller and "RB+←/→" or focusInput,
        focusX,panelY,sideWidth,dim,gold)
    block(focusX,panelY-4*u,sideWidth,.6*u,edge)
    fields.focus = label(focusX,panelY+10*u,sideWidth,11,ink)
    fitSpecs.focus = {width=sideWidth,size=11}
    block(focusX,panelY+24*u,sideWidth,.6*u,edge)
    label(focusX,panelY+28*u,sideWidth,6.3,dim,"SUBJECT DISTANCE")
    fields.subject = label(focusX,panelY+38*u,sideWidth,11,ink)
    fitSpecs.subject = {width=sideWidth,size=11}
    label(focusX,panelY+62*u,sideWidth,6,dim,"FOCUS CONTROLS")
    shortcut("af","SINGLE-SHOT AF",controller and "A" or token("af"),focusX,panelY+74*u,sideWidth,ink,gold)
    shortcut("mode","AF/MF",controller and "X" or token("mode"),focusX,panelY+86*u,sideWidth,ink,activeInk)
    shortcut("fine","FINE FOCUS",controller and "RB+A+←/→" or token("fine").."+"..focusInput,
        focusX,panelY+98*u,sideWidth,ink,gold)
    block(focusX,panelY+116*u,sideWidth,.6*u,edge)
    label(focusX,panelY+120*u,sideWidth,6.3,dim,"LENS BLUR")
    fields.blur = label(focusX,panelY+130*u,sideWidth,11,ink)
    ui.focus,ui.subject = fields.focus,fields.subject
    function ui.setFocusDetails(focus,subject)
        set("focus",focus)
        set("subject",subject)
    end
    local lastIndicator
    function ui.setFocusIndicator(direction)
        if lastIndicator == direction then return end
        lastIndicator = direction
        for i, indicator in ipairs(indicators) do
            ue.call("/Script/UMG.Widget:SetRenderOpacity",indicator,i == direction and 1 or .16)
        end
    end


    local track = math.min(236*u,headerWidth*.46)
    local trackX, trackY = w/2-track/2,headerY+14*u
    local centerX = trackX+track/2
    label(trackX-27*u,trackY-5*u,20*u,6,dim,"EV")
    block(trackX,trackY,track,.5*u,rgb(.20,.26,.215))
    for i=0,12 do
        local whole = i%3 == 0
        block(trackX+track*i/12,trackY-(whole and 2.5 or 1)*u,.6*u,(whole and 5 or 2)*u,dim)
        if whole then
            local ev = i/3-2
            label(trackX+track*i/12-9*u,trackY+4*u,18*u,5,dim,
                ev == 0 and "0" or string.format("%+d",ev),1)
        end
    end
    block(centerX-.5*u,trackY-4*u,u,8*u,ink)
    local needle = draw.picture("Controls/finder-pointer",centerX-3*u,trackY-7*u,6*u,5*u,1)
    fields.meter = label(trackX+track+11*u,trackY-6*u,70*u,8,gold)
    fields.warning = label(trackX+track+11*u,trackY+5*u,
        (headerWidth-track)/2-15*u,6,gold,nil,2)
    local lastEV, meterGoal, meterOffset, meterAt = nil,nil,0,nil
    function ui.tickMeter(now)
        local elapsed = meterAt and math.max(0,now-meterAt) or 0
        meterAt = now
        if not meterGoal or math.abs(meterGoal-meterOffset) < .01 then return end
        meterOffset = meterOffset+(meterGoal-meterOffset)*(1-math.exp(-elapsed/.07))
        ue.call("/Script/UMG.Widget:SetRenderTranslation",needle,{X=meterOffset/dpi,Y=0})
    end
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
            meterGoal = ev and math.max(-2,math.min(2,ev))*track/4 or nil
            if ev then
                fields.meter:SetColorAndOpacity({SpecifiedColor=gold,ColorUseRule=0})
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
    do
        local left, width = x-101*u,sideWidth
        local formatY = panelY
        block(left,formatY-4*u,width,.7*u,edge)
        shortcut("film","FILM",filmKey,left,formatY,width,dim,gold)
        fields.film = label(left,formatY+10*u,width,11,ink)
        fitSpecs.film = {width=width,size=11}
        block(left,formatY+24*u,width,.7*u,edge)
        shortcut("ratio","ASPECT",ratioKey,left,formatY+28*u,width,dim,gold)
        fields.ratio = label(left,formatY+38*u,width,11,ink)
        fitSpecs.ratio = {width=width,size=11}
        label(left,formatY+62*u,width,6,dim,"CAMERA CONTROLS")
        local actionY = formatY+74*u
        for i, item in ipairs(actions) do
            shortcut(item[1],item[2],item[3],left,actionY+(i-1)*12*u,width,ink,item[4])
        end
    end
    function ui.setFormat(stock,multiplier)
        local ratio = string.format("%d:%d",rect.columns,rect.rows)
        set("film",stock)
        set("ratio",ratio)
        set("blur",string.format("%gx",multiplier or 1))
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
