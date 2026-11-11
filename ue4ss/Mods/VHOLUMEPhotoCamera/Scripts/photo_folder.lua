-- Proton edition: the native Linux launcher handles desktop dialogs and folders.
return function(scriptPath)
    local photos = {}
    local default, selected, setting, pending, prepared
    local sequence = 0
    local ipc = scriptPath..'../Proton/ipc/'
    local function read(path, limit)
        local file = io.open(path,'rb')
        if not file then return end
        local value = file:read(limit+1)
        file:close()
        if value and #value <= limit then return value end
    end
    local function normalize(path)
        if not path or path:find('[%z\r\n"<>|?*]') then return end
        path = path:gsub('\\','/')
        if not path:match('^[A-Za-z]:/') or path:sub(3):find(':') then return end
        return path:gsub('/+$','')..'/'
    end
    local function alive()
        local stamp = tonumber(read(ipc..'ready',30) or '')
        return stamp and math.abs(os.time()-stamp) <= 5
    end
    local function send(action)
        if pending then return false end
        sequence = sequence+1
        local id = os.time()..'-'..sequence
        local name = ipc..'request-'..id..'.txt'
        local file = io.open(name..'.tmp','wb')
        if not file then return false end
        local written, closed = file:write(action..'\n'..selected),file:close()
        if not written or not closed or not os.rename(name..'.tmp',name) then
            os.remove(name..'.tmp')
            return false
        end
        pending = {reply=ipc..'reply-'..id..'.txt',request=name,action=action,path=selected,time=os.time()}
        return true
    end
    local function persist(path)
        local temp, backup = setting..'.tmp',setting..'.bak'
        local file = io.open(temp,'wb')
        if not file then return false end
        local written,closed = file:write(path),file:close()
        if not written or not closed then os.remove(temp); return false end
        local previous = io.open(setting,'rb')
        if previous then
            previous:close();os.remove(backup)
            if not os.rename(setting,backup) then os.remove(temp); return false end
        end
        if not os.rename(temp,setting) then
            if previous then os.rename(backup,setting) end
            os.remove(temp);return false
        end
        os.remove(backup)
        selected,prepared = path,nil
        return true
    end
    function photos.load(saved)
        if setting then return end
        saved = saved:gsub('[/\\]+$','')
        default = assert(normalize(saved..'/Screenshots/Windows'))
        setting = saved..'/VHOLUMEPhotoCamera.output-folder'
        selected = normalize(read(setting,32768) or read(setting..'.bak',32768)) or default
        send('Prepare')
    end
    function photos.directory() return assert(selected,'Photo folder has not loaded') end
    function photos.caption()
        local leaf = photos.directory():gsub('/+$',''):match('([^/]+)$') or selected
        local limit = utf8.offset(leaf,21)
        return limit and leaf:sub(1,limit-1)..'…' or leaf
    end
    function photos.choose()
        if pending then return 'WAIT FOR THE FOLDER HELPER' end
        if not alive() then return 'USE THE LINUX STEAM LAUNCH OPTION' end
        return send('Choose') and 'CHOOSE A PHOTO FOLDER' or 'COULD NOT OPEN FOLDER CHOOSER'
    end
    function photos.poll()
        if not pending then return end
        local result = read(pending.reply,32780)
        if not result then
            local timeout = pending.action == 'Choose' and 1800 or 90
            if os.time()-pending.time < timeout then return end
            os.remove(pending.request);pending=nil
            return 'FOLDER HELPER TIMED OUT; CHECK THE LINUX LAUNCH OPTION'
        end
        os.remove(pending.reply)
        local request = pending
        pending = nil
        if result == 'CANCELLED' then return 'PHOTO FOLDER UNCHANGED' end
        if result == 'NO_DIALOG' then return 'INSTALL ZENITY OR KDIALOG FOR FOLDER SELECTION' end
        if result == 'NO_OPENER' then return 'INSTALL XDG-UTILS TO OPEN THE PHOTO FOLDER' end
        local path = normalize(result:match('^OK\n(.+)$'))
        if not path then return 'COULD NOT USE PHOTO FOLDER; CHECK THE LINUX HELPER' end
        if request.action == 'Choose' then
            if not persist(path) then return 'COULD NOT SAVE PHOTO FOLDER' end
            prepared=path
            return 'PHOTO FOLDER UPDATED'
        end
        if request.path == selected then prepared=selected end
        if request.action == 'Open' then return 'PHOTO FOLDER OPENED' end
    end
    function photos.reset()
        if pending then return 'CLOSE THE FOLDER CHOOSER FIRST' end
        if not persist(default) then return 'COULD NOT SAVE PHOTO FOLDER' end
        send('Prepare')
        return 'DEFAULT PHOTO FOLDER RESTORED'
    end
    function photos.prepare()
        if not alive() then return false end
        if prepared == selected then return true end
        if not pending then send('Prepare') end
        return false
    end
    function photos.open()
        if pending then return 'WAIT FOR THE FOLDER HELPER' end
        if not alive() then return 'USE THE LINUX STEAM LAUNCH OPTION' end
        return send('Open') and 'OPENING PHOTO FOLDER' or 'COULD NOT OPEN PHOTO FOLDER'
    end
    return photos
end
