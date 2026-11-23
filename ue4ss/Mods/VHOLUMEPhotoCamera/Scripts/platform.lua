-- Platform boundary only; camera, capture and queue logic is shared byte-for-byte.
return function(scriptPath)
    local host={}
    function host.ready() return true end
    function host.launchDng(path,encoded)
        local helper=(scriptPath.."../Tools/PhotoCameraDng.exe"):gsub("/","\\")
        assert(not helper:find('[%%!"\r\n]'),"DNG converter path is unsupported")
        local file=assert(io.open(helper,"rb"),"DNG converter is missing");file:close()
        assert(os.execute('start "" /b "'..helper..'" '..encoded),"Could not launch the DNG converter")
    end
    return host
end
