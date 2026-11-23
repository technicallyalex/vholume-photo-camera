-- Proton calls the native Linux helper through the launcher's private IPC directory.
return function(scriptPath)
    local host={}
    local ipc=scriptPath.."../Proton/ipc/"
    function host.ready()
        local file=io.open(ipc.."ready","rb");if not file then return false end
        local stamp=tonumber(file:read(31) or "");file:close()
        return stamp and math.abs(os.time()-stamp)<=5 or false
    end
    function host.launchDng(path,encoded)
        local id=assert(path:match("VHOLUMEPhotoCamera%.dng%-job%-([%d%-]+)$"),"Invalid DNG job name")
        local request=ipc.."dng-request-"..id..".txt"
        local file=assert(io.open(request..".tmp","wb"),"Cannot contact the Linux DNG helper")
        local ok=file:write(encoded);local closed=file:close()
        assert(ok and closed and os.rename(request..".tmp",request),"Cannot submit the Linux DNG job")
    end
    return host
end
