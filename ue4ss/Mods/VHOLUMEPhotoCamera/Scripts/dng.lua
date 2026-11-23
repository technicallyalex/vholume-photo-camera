return function(scriptPath,log)
    local raw={}
    local host=dofile(scriptPath.."platform.lua")(scriptPath)
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
    local order={}
    raw.limit=8
    local function exists(path)
        local file=io.open(path,"rb");if not file then return false end;file:close();return true
    end
    local function persist(exclude)
        local lines={"version=2"}
        for _,shot in ipairs(order) do if shot~=exclude then lines[#lines+1]=jobs[shot].path end end
        if #lines==1 then
            if not remove(pointer) then return false end
            os.remove(pointer..".bak");return true
        end
        if not write(pointer..".tmp",table.concat(lines,"\n").."\n") then return false end
        local previous=exists(pointer)
        if previous then
            os.remove(pointer..".bak")
            if not os.rename(pointer,pointer..".bak") then os.remove(pointer..".tmp");return false end
        end
        if not os.rename(pointer..".tmp",pointer) then
            if previous then os.rename(pointer..".bak",pointer) end
            return false
        end
        os.remove(pointer..".bak");return true
    end
    local function controls(job)
        for _,suffix in ipairs({"",".result",".result.tmp",".progress",".cancel",".started",".lock"}) do os.remove(job.path..suffix) end
    end
    local function cleanup(shot)
        local good=true
        for _,path in ipairs({shot.partPath,shot.exrPartPath,shot.dngPartPath,shot.dngPartPath..".writing"}) do
            if not remove(path) then good=false end
        end
        return good
    end
    local function discard(shot)
        if not persist(shot) then return false end
        controls(jobs[shot]);jobs[shot]=nil
        for i,value in ipairs(order) do if value==shot then table.remove(order,i);break end end
        return true
    end
    local function fields(body)
        local result={}
        for key,value in body:gmatch("([^=\r\n]+)=([^\r\n]*)") do
            if result[key] then return end
            result[key]=value
        end
        return result
    end
    local function recover(path)
        local prefix=saved.."/VHOLUMEPhotoCamera.dng-job-"
        if path:sub(1,#prefix)~=prefix or path:sub(#prefix+1):find('[^%w%-]') then return end
        local body=read(path,65536);local f=body and fields(body);if not f then return end
        local source,destination=decode(f.source),decode(f.destination)
        local base=source and source:match("^(.*[/\\]VHOLUME_[^/\\]+)%.part%.exr$")
        if not base or destination~=base..".part.dng" or base:find('\0',1,true) or base:find('[\r\n]') then return end
        local shot={base=base,path=base..".png",partPath=base..".part.png",exrPath=base..".exr",exrPartPath=source,
            dngPath=base..".dng",dngPartPath=destination,dng=true,exr=true,renderReleased=true,convertingDNG=true}
        local job={path=path,started=exists(path..".started") and os.time() or nil}
        if f.jobversion~="2" then
            job.cancelled=true;job.cancelAt=os.time();write(path..".cancel","cancel")
        else
            for key,range in pairs({width={1,7680},height={1,7680},iso={1,65535},aperture={.1,128},
                    shutter={.000001,3600},focal={1,10000},mode={1,4},samples={0,1000000}}) do
                local n=tonumber(f[key] or "");if not n or n~=n or n<range[1] or n>range[2] then return end
                shot[key]=n
            end
            if shot.width%1~=0 or shot.height%1~=0 or (f.png~="0" and f.png~="1") or (f.keepEXR~="0" and f.keepEXR~="1") then return end
            shot.png=f.png=="1";shot.keepEXR=f.keepEXR=="1"
            shot.shutterSeconds=shot.shutter;shot.focalLength=shot.focal;shot.exposureMode=shot.mode
            shot.film=decode(f.film);shot.method=decode(f.method);shot.captured=f.captured
            if not shot.film or not shot.method or not shot.captured or not shot.captured:match('^%d%d%d%d:%d%d:%d%d %d%d:%d%d:%d%d$') then return end
            shot.formatName=(shot.png and "PNG + " or "")..(shot.keepEXR and "EXR + " or "").."DNG"
            shot.recovered=true
            if exists(path..".result") then job.started=os.time() end
        end
        jobs[shot]=job;order[#order+1]=shot
        return true
    end
    function raw.load(directory)
        if saved then return end
        saved=directory:gsub("[/\\]+$","");pointer=saved.."/VHOLUMEPhotoCamera.dng-active"
        local body=read(pointer,262144) or read(pointer..".bak",262144)
        if not body then return end
        local seen={}
        if body:sub(1,10)=="version=2\n" then
            for path in body:sub(11):gmatch('[^\r\n]+') do
                if not seen[path] and #order<raw.limit then recover(path);seen[path]=true end
            end
        else recover(body) end
        assert(persist(),"Could not recover the photo save queue")
        if #order>0 then log("Recovered "..#order.." queued photo save(s).") end
    end
    function raw.count() return #order end
    function raw.full() return #order>=raw.limit end
    function raw.busy() return #order>0 end
    function raw.shots()
        local list={};for _,shot in ipairs(order) do if not jobs[shot].cancelled then list[#list+1]=shot end end
        return list
    end
    local function launch(job)
        if not host.ready() then return end -- Keep persisted photos queued until the helper is available.
        assert(write(job.path..".started",tostring(os.time())),"Cannot mark DNG job started")
        job.started=os.time()
        host.launchDng(job.path,encode(job.path))
    end
    function raw.begin(shot)
        assert(saved and not raw.full(),"Photo save queue is full")
        sequence=sequence+1
        local path=saved.."/VHOLUMEPhotoCamera.dng-job-"..os.time().."-"..sequence.."-"..math.random(100000,999999)
        local body=table.concat({"version=1","jobversion=2","source="..encode(shot.exrPartPath),"destination="..encode(shot.dngPartPath),
            "result="..encode(path..".result"),"width="..shot.width,"height="..shot.height,"iso="..shot.iso,
            "aperture="..shot.aperture,"shutter="..string.format("%.9f",shot.shutterSeconds),"focal="..shot.focalLength,
            "mode="..shot.exposureMode,"captured="..shot.captured,"png="..(shot.png and "1" or "0"),
            "keepEXR="..(shot.keepEXR and "1" or "0"),"film="..encode(shot.film or "Neutral"),
            "method="..encode(shot.method or "Dedicated render"),"samples="..(shot.samples or 0)},"\n").."\n"
        assert(write(path,body),"Cannot write the DNG job")
        jobs[shot]={path=path};order[#order+1]=shot
        if not persist() then jobs[shot]=nil;table.remove(order);os.remove(path);error("Cannot save the photo queue") end
        -- A single converter owns CPU work; other captured frames wait on disk.
    end
    function raw.cancel(shot)
        local job=jobs[shot];if not job then return end
        job.cancelled=true;job.cancelAt=job.cancelAt or os.time();write(job.path..".cancel","cancel")
    end
    function raw.poll()
        local active=false
        local snapshot={};for _,shot in ipairs(order) do snapshot[#snapshot+1]=shot end
        for _,shot in ipairs(snapshot) do
            local job=jobs[shot]
            if job.started then
                if not job.result then job.result=read(job.path..".result",8192) end
                local progress=tonumber(read(job.path..".progress",8) or "")
                if progress and progress~=job.progress then job.progress=math.max(0,math.min(100,progress));job.progressAt=os.time() end
                if os.time()-(job.progressAt or job.started)>=120 and not job.result then
                    job.result="ERROR\nDNG converter timed out";write(job.path..".cancel","cancel")
                end
            end
            if job.cancelled then
                if not job.started or job.result or os.time()-job.cancelAt>=5 then
                    if cleanup(shot) then discard(shot) end
                end
            end
            if jobs[shot] and job.started then active=true end
        end
        if not active then
            for _,shot in ipairs(order) do
                local job=jobs[shot]
                if not job.cancelled then
                    local ok,reason=pcall(launch,job)
                    if not ok then job.started=os.time();job.result="ERROR\n"..tostring(reason) end
                    break
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
        return job.started and "working" or "queued",job.progress or 0
    end
    function raw.release(shot)
        if jobs[shot] then assert(discard(shot),"Cannot commit the photo save queue") end
    end
    return raw
end
