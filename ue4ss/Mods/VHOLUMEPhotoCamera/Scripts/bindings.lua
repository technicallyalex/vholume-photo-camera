return function(ue, log, exposure)
    local binds = {}
    binds.groups = {
        {"Camera",
            {"equip","Equip / stow","Five"},
            {"studio","Open / close Photo Studio","Four"}, {"finder","Raise / lower finder","RightMouseButton"},
            {"shoot","Shutter / place subject","LeftMouseButton"},
            {"lensPrev","Previous lens","LeftBracket"}, {"lensNext","Next lens","RightBracket"},
            {"walk","Toggle slow walk","V"}, {"frame","Rotate frame","P"}},
        {"Focus",
            {"af","Single-shot autofocus","MiddleMouseButton"}, {"mode","Auto / manual focus","F"},
            {"dof","Toggle depth of field","B"}, {"focusFar","Focus farther","MouseScrollUp"},
            {"focusNear","Focus nearer","MouseScrollDown"}, {"fine","Fine focus modifier","LeftShift"},
            {"apertureDown","Open aperture","Comma"}, {"apertureUp","Close aperture","Period"}},
        {"Subjects",
            {"placeStart","Start subject placement","G"},
            {"placeLeft","Turn subject left","Z"}, {"placeRight","Turn subject right","X"},
            {"placePose","Cycle pose in placement","C"},
            {"placeUndo","Undo last placed subject","BackSpace"}},
        {"Studio",
            {"menuLeft","Previous card","Left"}, {"menuRight","Next card","Right"},
            {"menuNext","Next value","Up"}, {"menuPrev","Previous value","Down"},
            {"menuSelect","Use selected card","Six"}},
    }

    local labels = {
        Five="5", Zero="0", Six="6", One="1", Two="2", Three="3", Four="4",
        Seven="7", Eight="8", Nine="9", LeftBracket="[", RightBracket="]",
        Comma=",", Period=".", Slash="/", Backslash="\\", Hyphen="-", Equals="=",
        Semicolon=";", Apostrophe="'", LeftShift="Left Shift", RightShift="Right Shift",
        LeftControl="Left Ctrl", RightControl="Right Ctrl", LeftAlt="Left Alt", RightAlt="Right Alt",
        BackSpace="Backspace", SpaceBar="Space", PageUp="Page Up", PageDown="Page Down",
        LeftMouseButton="Left Mouse", RightMouseButton="Right Mouse", MiddleMouseButton="Middle Mouse",
        ThumbMouseButton="Mouse 4", ThumbMouseButton2="Mouse 5",
        MouseScrollUp="Wheel Up", MouseScrollDown="Wheel Down",
    }
    local tokens = {
        LeftMouseButton="mouse-left", RightMouseButton="mouse-right", MiddleMouseButton="mouse-middle",
        ThumbMouseButton="M4", ThumbMouseButton2="M5", MouseScrollUp="WhUp", MouseScrollDown="WhDn",
        LeftShift="Shift", RightShift="RShift", LeftControl="Ctrl", RightControl="RCtrl",
        LeftAlt="Alt", RightAlt="RAlt", BackSpace="Bksp", PageUp="PgUp", PageDown="PgDn",
        Delete="Del", Insert="Ins",
        Left="←", Right="→", Up="↑", Down="↓",
    }
    local modifiers = {
        LeftShift=true,RightShift=true,LeftControl=true,RightControl=true,LeftAlt=true,RightAlt=true,
    }
    local reserved = { F9=true,Enter=true,Tab=true }
    local choices, allowed, keys = {}, {}, {}
    local function add(name)
        choices[#choices+1] = name
        allowed[name] = true
    end
    for char = 65, 90 do add(string.char(char)) end
    for i = 1, 12 do add("F"..i) end
    for _,name in ipairs({
        "Zero","One","Two","Three","Four","Five","Six","Seven","Eight","Nine",
        "Left","Right","Up","Down","Home","End","PageUp","PageDown","Insert","Delete","BackSpace","SpaceBar","Tab","Enter",
        "LeftBracket","RightBracket","Comma","Period","Slash","Backslash","Hyphen","Equals","Semicolon","Apostrophe",
        "LeftMouseButton","RightMouseButton","MiddleMouseButton","ThumbMouseButton","ThumbMouseButton2",
        "MouseScrollUp","MouseScrollDown","LeftShift","RightShift","LeftControl","RightControl","LeftAlt","RightAlt",
    }) do add(name) end

    local actions, defaults, current, order = {}, {}, {}, {}
    for _,group in ipairs(binds.groups) do
        for i=2,#group do
            local id,title,name = table.unpack(group[i])
            actions[id], defaults[id], current[id] = title,name,name
            order[#order+1] = id
        end
    end
    local path
    local aimScaling = true
    local pressed = "/Script/Engine.PlayerController:WasInputKeyJustPressed"
    local down = "/Script/Engine.PlayerController:IsInputKeyDown"
    local analog = "/Script/Engine.PlayerController:GetInputAnalogKeyState"
    local wheelShortcut, wheelEdge, previousWheel

    function binds.raw(name)
        if not keys[name] then keys[name] = {KeyName=FName(name,1)} end
        return keys[name]
    end
    function binds.key(id) return binds.raw(current[id]) end
    function binds.name(id) return current[id] end
    function binds.action(id) return actions[id] end
    function binds.label(id)
        local name = current[id]
        return labels[name] or name
    end
    function binds.token(id)
        local name = current[id]
        return tokens[name] or labels[name] or name
    end
    function binds.focusTokens()
        if current.focusFar=="MouseScrollUp" and current.focusNear=="MouseScrollDown" then
            return {"mouse-wheel"}
        end
        return {binds.token("focusFar"),binds.token("focusNear")}
    end
    function binds.tabHint()
        return "Tab"
    end
    function binds.shiftDown(pc)
        return ue.call(down,pc,binds.raw("LeftShift")) or ue.call(down,pc,binds.raw("RightShift"))
    end

    binds.wheelChords = {
        mode="Tab + Ctrl", ratio="Tab + Alt", film="Tab + Shift", lens="Tab",
        iso="Ctrl + Alt", aperture="Ctrl", shutter="Alt",
    }

    local function wheelDial(pc)
        local function held(name) return ue.call(down,pc,binds.raw(name)) end
        local ctrl = held("LeftControl") or held("RightControl")
        local alt = held("LeftAlt") or held("RightAlt")
        if held("Tab") then
            if ctrl then return "mode" end
            if alt then return "ratio" end
            if binds.shiftDown(pc) then return "film" end
            return "lens"
        end
        if ctrl and alt then return "iso" end
        if ctrl then return "aperture" end
        if alt then return "shutter" end
    end

    local function permitted(id, name)
        if not allowed[name] or reserved[name] then return false end
        if name == "LeftMouseButton" and id ~= "shoot" then return false end
        if id == "fine" then return name == "LeftShift" or name == "RightShift" end
        return not modifiers[name]
    end

    local function use(values)
        current = values
        wheelShortcut, wheelEdge, previousWheel = false,nil,0
        for id,name in pairs(values) do
            if id ~= "focusFar" and id ~= "focusNear"
                    and (name == "MouseScrollUp" or name == "MouseScrollDown") then
                wheelShortcut = true
                break
            end
        end
    end

    function binds.load(saved)
        if path then return end
        local stable = saved:gsub("[/\\]+$","").."/VHOLUMEPhotoCamera.keys"
        local previous = stable..".exposure-preview"
        path = stable..".finder-preview"
        local file = io.open(path,"rb") or io.open(path..".bak","rb")
            or io.open(previous,"rb") or io.open(previous..".bak","rb")
            or io.open(stable,"rb") or io.open(stable..".bak","rb")
        if not file then return end
        local body = file:read(8193)
        file:close()
        if not body or #body > 8192 then return end
        exposure.loadOptions("\n"..body.."\n")
        local loaded, legacy = {}, false
        for id,name in body:gmatch("([%a]+)=([%w]+)") do
            if actions[id] and permitted(id,name) then loaded[id] = name end
            if id == "stow" then legacy = true end
            if id == "aimScaling" and (name == "0" or name == "1") then aimScaling = name == "1" end
        end
        if legacy then
            for id,name in pairs(loaded) do
                if id ~= "studio" and name == "Four" then loaded[id] = loaded.studio end
            end
            loaded.studio = "Four"
        end
        local used = {}
        for _,id in ipairs(order) do
            local name = loaded[id]
            if name then
                if used[name] then log("Duplicate key in Photo Camera settings. Using defaults."); return end
                used[name] = true
            end
        end
        for _,id in ipairs(order) do
            if not loaded[id] then
                local name = defaults[id]
                if used[name] then
                    for _,candidate in ipairs(choices) do
                        if not used[candidate] and permitted(id,candidate) then name = candidate; break end
                    end
                end
                loaded[id], used[name] = name, true
            end
        end
        use(loaded)
    end

    local function save(updated, scaling)
        if not path then return false end
        local temp, backup = path..".tmp", path..".bak"
        local file = io.open(temp,"wb")
        if not file then return false end
        local lines = {"aimScaling="..(scaling and "1" or "0")}
        for _,line in ipairs(exposure.optionLines()) do lines[#lines+1] = line end
        for _,id in ipairs(order) do lines[#lines+1] = id.."="..updated[id] end
        local written = file:write(table.concat(lines,"\n"),"\n")
        local closed = file:close()
        if not written or not closed then os.remove(temp); return false end
        local before = io.open(path,"rb")
        if before then
            before:close()
            os.remove(backup)
            if not os.rename(path,backup) then os.remove(temp); return false end
        end
        if not os.rename(temp,path) then
            if before then os.rename(backup,path) end
            os.remove(temp)
            return false
        end
        os.remove(backup)
        aimScaling = scaling
        use(updated)
        return true
    end

    function binds.aimScaling() return aimScaling end

    function binds.setAimScaling(enabled)
        return save(current,enabled)
    end

    function binds.persist() return save(current,aimScaling) end

    function binds.assign(id,name)
        if not permitted(id,name) then
            if id == "fine" then return false,"Choose Left Shift or Right Shift for fine focus." end
            return false,(labels[name] or name).." is reserved."
        end
        for _,other in ipairs(order) do
            if other ~= id and current[other] == name then return false,"Already used by "..actions[other].."." end
        end
        if name == current[id] then return true end
        local updated = {}
        for _,other in ipairs(order) do updated[other] = current[other] end
        updated[id] = name
        if not save(updated,aimScaling) then return false,"Could not save keybinds." end
        return true
    end

    function binds.reset()
        return save(defaults,aimScaling)
    end

    function binds.capture(pc)
        for _,name in ipairs(choices) do
            if ue.call(pressed,pc,binds.raw(name)) then return name end
        end
        local delta = ue.call(analog,pc,binds.raw("MouseWheelAxis"))
        if math.abs(delta) >= .01 then return delta > 0 and "MouseScrollUp" or "MouseScrollDown" end
    end

    function binds.beginFrame(pc, finderRaised)
        binds.wheel = 0
        wheelEdge = nil
        binds.dial = nil
        if not finderRaised and not wheelShortcut then previousWheel = 0; return end
        if finderRaised then binds.dial = wheelDial(pc) end
        local delta = ue.call(analog,pc,binds.raw("MouseWheelAxis"))
        local up = ue.call(pressed,pc,binds.raw("MouseScrollUp"))
        local downWheel = ue.call(pressed,pc,binds.raw("MouseScrollDown"))
        if up ~= downWheel then
            binds.wheel = (up and 1 or -1) * math.max(1, math.abs(delta))
        elseif math.abs(previousWheel or 0) < .01 and math.abs(delta) >= .01 then
            binds.wheel = delta
        end
        previousWheel = delta
        if binds.wheel ~= 0 then wheelEdge = binds.wheel > 0 and "MouseScrollUp" or "MouseScrollDown" end
    end

    function binds.pressed(pc,id)
        if binds.dial and current[id]:find("MouseScroll",1,true) then return false end
        return ue.call(pressed,pc,binds.key(id)) or wheelEdge == current[id]
    end

    function binds.isFine(pc)
        return ue.call(down,pc,binds.key("fine")) or (current.fine == "LeftShift"
            and ue.call(down,pc,binds.raw("RightShift")))
    end

    return binds
end
