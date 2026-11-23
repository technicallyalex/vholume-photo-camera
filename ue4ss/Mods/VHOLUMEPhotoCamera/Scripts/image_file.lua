local image={}
function image.png(path)
    local file=io.open(path,"rb")
    if not file then return end
    local head=file:read(33)
    if head and #head==33 and head:sub(1,16)=="\137PNG\13\10\26\10\0\0\0\13IHDR" then
        local data=false
        while true do
            local header=file:read(8)
            if not header or #header~=8 then break end
            local size,kind=string.unpack(">I4c4",header)
            if kind=="IEND" then
                local crc=size==0 and file:read(4)
                file:close()
                if data and crc=="\174\66\96\130" then return string.unpack(">I4I4",head,17) end
                return
            end
            if kind=="IDAT" and size>0 then data=true end
            if not file:seek("cur",size+4) then break end
        end
    end
    file:close()
end
function image.exr(path)
    local file=io.open(path,"rb")
    if not file then return end
    local ok,w,h=pcall(function()
        local length=file:seek("end");file:seek("set",0)
        assert(file:read(4)=="\118\47\49\1","Invalid EXR signature")
        local version=string.unpack("<I4",assert(file:read(4)))
        assert(version==2,"Unsupported EXR layout")
        local function word()
            local result={}
            for _=1,256 do
                local c=file:read(1);assert(c,"Truncated EXR header")
                if c=="\0" then return table.concat(result) end
                result[#result+1]=c
            end
            error("Invalid EXR attribute")
        end
        local width,height,compression
        while true do
            local name=word();if name=="" then break end
            word()
            local size=string.unpack("<I4",assert(file:read(4)))
            assert(size<1048576,"EXR attribute too large")
            local data=assert(file:read(size));assert(#data==size)
            if name=="dataWindow" then
                local x0,y0,x1,y1=string.unpack("<i4i4i4i4",data)
                width,height=x1-x0+1,y1-y0+1
            elseif name=="compression" then compression=data:byte(1) end
        end
        assert(width and width>0 and height>0 and width<=7680 and height<=7680)
        local lines=({[0]=1,[1]=1,[2]=1,[3]=16,[4]=32})[compression]
        assert(lines,"Unsupported EXR compression")
        local chunks=math.ceil(height/lines)
        for _=1,chunks do
            local offset=string.unpack("<I8",assert(file:read(8)))
            local cursor=file:seek()
            assert(offset>=cursor and offset+8<length,"Truncated EXR offset")
            file:seek("set",offset)
            local y,bytes=string.unpack("<i4I4",assert(file:read(8)))
            assert(y>=0 and y<height and bytes>0 and offset+8+bytes<=length,"Truncated EXR data")
            file:seek("set",cursor)
        end
        return width,height
    end)
    file:close()
    if ok then return w,h end
end
return image
