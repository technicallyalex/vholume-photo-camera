return function()
    local config = {format=1,resolution=1,method=1}
    -- Existing indices remain stable for saved capture preferences.
    config.formats = {"PNG", "EXR", "PNG + EXR", "DNG", "PNG + DNG", "EXR + DNG", "PNG + EXR + DNG"}
    config.outputs = {{png=true},{exr=true},{png=true,exr=true},{dng=true},
        {png=true,dng=true},{exr=true,dng=true},{png=true,exr=true,dng=true}}
    config.resolutions = {"Game resolution", "1280 px", "1920 px", "2560 px", "3840 px", "5760 px", "7680 px"}
    config.edges = {0,1280,1920,2560,3840,5760,7680}
    config.methods = {"Dedicated render", "Switch game resolution"}
    local path
    function config.load(saved)
        if path then return end
        path = saved:gsub("[/\\]+$","").."/VHOLUMEPhotoCamera.capture"
        local file=io.open(path,"rb") or io.open(path..".bak","rb")
        if not file then return end
        local body=file:read(1025);file:close()
        if not body or #body>1024 then return end
        for key,limit in pairs({format=#config.formats,resolution=#config.edges,method=2}) do
            local value=tonumber(("\n"..body.."\n"):match("\n"..key.."=(%d+)[\r\n]"))
            if value and value>=1 and value<=limit then config[key]=value end
        end
    end
    function config.step(key,direction)
        local lists={format=config.formats,resolution=config.resolutions,method=config.methods}
        if not lists[key] then return false end
        local old=config[key]
        config[key]=(old-1+direction)%#lists[key]+1
        local file=path and io.open(path..".tmp","wb")
        if not file then config[key]=old;return false end
        local ok=file:write(string.format("format=%d\nresolution=%d\nmethod=%d\n",config.format,config.resolution,config.method))
        local closed=file:close()
        if not ok or not closed then os.remove(path..".tmp");config[key]=old;return false end
        local previous=io.open(path,"rb")
        if previous then
            previous:close();os.remove(path..".bak")
            if not os.rename(path,path..".bak") then os.remove(path..".tmp");config[key]=old;return false end
        end
        if not os.rename(path..".tmp",path) then
            if previous then os.rename(path..".bak",path) end
            config[key]=old;return false
        end
        os.remove(path..".bak");return true
    end
    function config.dimensions(rect)
        -- Resolution is the complete image's long edge, never the finder HUD crop.
        local edge=config.edges[config.resolution]
        if edge==0 then edge=math.max(rect.width,rect.height) end
        edge=math.min(7680,math.max(256,edge))
        local scale=math.max(1,math.floor(edge/math.max(rect.columns,rect.rows)))
        return scale*rect.columns,scale*rect.rows
    end
    function config.help(key)
        if key=="format" then
            local output=config.outputs[config.format]
            if output.dng then
                return output.png and "PNG includes the film look. DNG keeps HDR data for Lightroom / Camera Raw."
                    or "DNG keeps HDR data for Lightroom / Camera Raw. No film look or grain is baked in."
            end
            return config.format==1 and "PNG includes the selected film look and ISO grain."
                or "EXR saves linear HDR with no film look or grain. Optics and exposure are retained."
        elseif key=="method" then
            return config.method==1 and "Renders at the selected size without changing gameplay resolution."
                or "Temporarily changes the game window; restores it afterward.\nUse Dedicated render for sizes the display cannot apply."
        end
        return "Sets the full image's long edge. Aspect ratio and portrait orientation are preserved."
    end
    return config
end
