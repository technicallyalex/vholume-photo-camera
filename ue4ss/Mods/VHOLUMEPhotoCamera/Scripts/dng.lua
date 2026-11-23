return function(scriptPath,log)
    local raw={}
    local jobs,sequence={},0
    local saved,pointer
    local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local function encode(value)
        local out={}
        for i=1,#value,3 do
            local a,b,c=value:byte(i,i+2)
            local n=a*65536+(b or 0)*256+(c or 0)
            out[#out+1]=alphabet:sub(math.floor(n/262144)%64+1,math.floor(n/262144)%64+1)
                ..alphabet:sub(math.floor(n/4096)%64+1,math.floor(n/4096)%64+1)
                ..(b and alphabet:sub(math.floor(n/64)%64+1,math.floor(n/64)%64+1) or "=")
                ..(c and alphabet:sub(n%64+1,n%64+1) or "=")
        end
        return table.concat(out)
    end
    local function decode(value)
        if not value or #value%4~=0 or value:find('[^%w+/=]') then return end
        local out={}
        for i=1,#value,4 do
            local digits={}
            for j=0,3 do
                local c=value:sub(i+j,i+j)
                local at=alphabet:find(c,1,true)
                if not at and c~="=" then return end
                digits[j+1]=at and at-1 or 0
            end
            local n=digits[1]*262144+digits[2]*4096+digits[3]*64+digits[4]
            out[#out+1]=string.char(math.floor(n/65536)%256)
            if value:sub(i+2,i+2)~="=" then out[#out+1]=string.char(math.floor(n/256)%256) end
            if value:sub(i+3,i+3)~="=" then out[#out+1]=string.char(n%256) end
        end
        return table.concat(out)
    end
    local function read(path,limit)
        local f=io.open(path,"rb");if not f then return end
        local text=f:read(limit+1);f:close()
        if text and #text<=limit then return text end
    end
    local function write(path,text)
        local f=io.open(path,"wb");if not f then return false end
        local ok=f:write(text);local closed=f:close();return ok and closed
    end
    local function remove(path)
        if not path then return true end
        local file=io.open(path,"rb");if not file then return true end
        file:close();return os.remove(path)~=nil
    end
    local function controls(job)
        for _,suffix in ipairs({"",".result",".result.tmp",".progress",".cancel"}) do os.remove(job.path..suffix) end
        if read(pointer,32768)==job.path then os.remove(pointer) end
    end
    local function cleanup(shot)
        local good=true
        for _,path in ipairs({shot.partPath,shot.exrPartPath,shot.dngPartPath,shot.dngPartPath..".writing"}) do
            if not remove(path) then good=false end
        end
        return good
    end
    function raw.load(directory)
        if saved then return end
        saved=directory:gsub("[/\\]+$","")
        pointer=saved.."/VHOLUMEPhotoCamera.dng-active"
        local path=read(pointer,32768)
        if not path then return end
        local prefix=saved.."/VHOLUMEPhotoCamera.dng-job-"
        if path:sub(1,#prefix)~=prefix or path:sub(#prefix+1):find('[^%w%-]') then os.remove(pointer);return end
        local body=read(path,65536)
        local source=body and decode(body:match("\nsource=([^\r\n]+)"))
        local destination=body and decode(body:match("\ndestination=([^\r\n]+)"))
        local base=source and source:match("^(.*[/\\]VHOLUME_[^/\\]+)%.part%.exr$")
        if base and destination==base..".part.dng" then
            local shot={partPath=base..".part.png",exrPartPath=source,dngPartPath=destination}
            jobs[shot]={path=path,started=os.time(),cancelled=true,cancelAt=os.time(),recovered=true}
            write(path..".cancel","cancel")
            log("Cleaning an interrupted DNG conversion.")
        else
            os.remove(pointer)
        end
    end
    function raw.busy() return next(jobs)~=nil end
    function raw.begin(shot)
        assert(saved and not raw.busy(),"DNG converter is already busy")
        local helper=(scriptPath.."../Tools/PhotoCameraDng.exe"):gsub("/","\\")
        assert(not helper:find('[%%!"\r\n]'),"DNG converter path is unsupported")
        local file=assert(io.open(helper,"rb"),"DNG converter is missing");file:close()
        sequence=sequence+1
        local path=saved.."/VHOLUMEPhotoCamera.dng-job-"..os.time().."-"..sequence.."-"..math.random(100000,999999)
        local body=table.concat({"version=1","source="..encode(shot.exrPartPath),"destination="..encode(shot.dngPartPath),
            "result="..encode(path..".result"),"width="..shot.width,"height="..shot.height,"iso="..shot.iso,
            "aperture="..shot.aperture,"shutter="..string.format("%.9f",shot.shutterSeconds),"focal="..shot.focalLength,
            "mode="..shot.exposureMode,"captured="..shot.captured},"\n").."\n"
        if not write(path,body) or not write(pointer,path) then
            os.remove(path);if read(pointer,32768)==path then os.remove(pointer) end
            error("Cannot start the DNG job")
        end
        local job={path=path,started=os.time()}
        jobs[shot]=job
        local ok=os.execute('start "" /b "'..helper..'" '..encode(path))
        if not ok then controls(job);jobs[shot]=nil;error("Could not launch the DNG converter") end
    end
    function raw.cancel(shot)
        local job=jobs[shot]
        if not job then return end
        job.cancelled=true;job.cancelAt=job.cancelAt or os.time()
        write(job.path..".cancel","cancel")
    end
    function raw.poll()
        for shot,job in pairs(jobs) do
            if not job.result then job.result=read(job.path..".result",8192) end
            local progress=tonumber(read(job.path..".progress",8) or "")
            if progress and progress~=job.progress then
                job.progress=math.max(0,math.min(100,progress));job.progressAt=os.time()
            end
            if os.time()-(job.progressAt or job.started)>=120 and not job.result then
                job.result="ERROR\nDNG converter timed out"
                write(job.path..".cancel","cancel")
            end
            if job.cancelled then
                if job.result or os.time()-(job.cancelAt or job.started)>=5 then
                    if cleanup(shot) then controls(job);jobs[shot]=nil end
                end
            end
        end
    end
    function raw.status(shot)
        local job=assert(jobs[shot],"DNG conversion disappeared")
        if job.result then
            if job.result=="OK\n"..shot.width.."\n"..shot.height then return "done" end
            return "error",job.result
        end
        return "working",job.progress or 0
    end
    function raw.release(shot)
        local job=jobs[shot]
        if job then controls(job);jobs[shot]=nil end
    end
    return raw
end
