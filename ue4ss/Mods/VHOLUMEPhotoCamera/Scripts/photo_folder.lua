return function(scriptPath)
    local photos = {}
    local default, selected, setting, request, prepared
    local sequence = 0
    local function read(path, limit)
        local file = io.open(path,"rb")
        if not file then return end
        local value = file:read(limit+1)
        file:close()
        if value and #value <= limit then return value end
    end
    local function normalize(path)
        if not path or path:find('[%z\r\n"<>|?*]') then return end
        path = path:gsub("\\","/")
        if not (path:match("^[A-Za-z]:/") or path:match("^//[^/]+/[^/]+")) then return end
        if path:sub(3):find(":") then return end
        return path:gsub("/+$","").."/"
    end
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local function base64(value)
        local encoded = {}
        for offset=1,#value,3 do
            local a,b,c = value:byte(offset,offset+2)
            local bits = a*65536+(b or 0)*256+(c or 0)
            encoded[#encoded+1] = alphabet:sub(math.floor(bits/262144)%64+1,math.floor(bits/262144)%64+1)
                ..alphabet:sub(math.floor(bits/4096)%64+1,math.floor(bits/4096)%64+1)
                ..(b and alphabet:sub(math.floor(bits/64)%64+1,math.floor(bits/64)%64+1) or "=")
                ..(c and alphabet:sub(bits%64+1,bits%64+1) or "=")
        end
        return table.concat(encoded)
    end
    local function command(action, result)
        local helper = (scriptPath.."Photo-Folder.ps1"):gsub("/","\\")
        if helper:find('[%%!"\r\n]') then return end
        return 'powershell.exe'
            ..' -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "'..helper..'"'
            ..' -Action '..action..' -InitialPathBase64 '..base64(selected)
            ..(result and (' -ResultPathBase64 '..base64(result)) or "")
    end
    local function persist(path)
        local temp, backup = setting..".tmp",setting..".bak"
        local file = io.open(temp,"wb")
        if not file then return false end
        local written,closed = file:write(path),file:close()
        if not written or not closed then os.remove(temp); return false end
        local previous = io.open(setting,"rb")
        if previous then
            previous:close()
            os.remove(backup)
            if not os.rename(setting,backup) then os.remove(temp); return false end
        end
        if not os.rename(temp,setting) then
            if previous then os.rename(backup,setting) end
            os.remove(temp)
            return false
        end
        os.remove(backup)
        selected = path
        prepared = nil
        return true
    end
    function photos.load(saved)
        if setting then return end
        saved = saved:gsub("[/\\]+$","")
        default = assert(normalize(saved.."/Screenshots/Windows"))
        setting = saved.."/VHOLUMEPhotoCamera.output-folder"
        selected = normalize(read(setting,32768) or read(setting..".bak",32768)) or default
    end
    function photos.directory() return assert(selected,"Photo folder has not loaded") end
    function photos.caption()
        local path = photos.directory():gsub("/+$","")
        local leaf = path:match("([^/]+)$") or path
        local limit = utf8.offset(leaf,21)
        return limit and leaf:sub(1,limit-1).."…" or leaf
    end
    function photos.choose()
        if request then return "FOLDER CHOOSER ALREADY OPEN" end
        sequence = sequence+1
        local result = setting..".choose-"..os.time().."-"..sequence
        os.remove(result)
        local launch = command("Choose",result)
        if not launch then return "FOLDER CHOOSER PATH UNAVAILABLE" end
        if not os.execute('start "" /b '..launch) then return "COULD NOT OPEN FOLDER CHOOSER" end
        request = result
        return "CHOOSE A PHOTO FOLDER"
    end
    function photos.poll()
        if not request then return end
        local result = read(request,32780)
        if not result then return end
        os.remove(request)
        request = nil
        if result == "CANCELLED" then return "PHOTO FOLDER UNCHANGED" end
        local path = normalize(result:match("^OK\n(.+)$"))
        if not path then return "COULD NOT USE PHOTO FOLDER" end
        local probe = path..".photo-camera-write-"..os.time().."-"..sequence..".tmp"
        local file = io.open(probe,"wb")
        if not file then return "GAME CANNOT WRITE TO THAT PHOTO FOLDER" end
        local written, closed = file:write(""), file:close()
        os.remove(probe)
        if not written or not closed then return "PHOTO FOLDER IS NOT WRITABLE" end
        return persist(path) and "PHOTO FOLDER UPDATED" or "COULD NOT SAVE PHOTO FOLDER"
    end
    function photos.reset()
        if request then return "CLOSE THE FOLDER CHOOSER FIRST" end
        return persist(default) and "DEFAULT PHOTO FOLDER RESTORED" or "COULD NOT SAVE PHOTO FOLDER"
    end
    function photos.prepare()
        if prepared == selected then return true end
        local launch = command("Prepare")
        if not launch or not os.execute(launch) then return false end
        prepared = selected
        return true
    end
    function photos.open()
        local launch = command("Open")
        return launch and os.execute('start "" /b '..launch) and "PHOTO FOLDER OPENED"
            or "COULD NOT OPEN PHOTO FOLDER"
    end
    return photos
end
