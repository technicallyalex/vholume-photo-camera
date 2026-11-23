local scriptPath=scripts
local factory=dofile(scriptPath..'dng.lua')
local execute,clock=os.execute,os.time
local now=1000;os.time=function() return now end;os.execute=function() return true end
local function module() local m=factory(scriptPath,function() end);m.load(fixture);return m end
local function shot()
 local base=fixture..'/VHOLUME_dng-test'
 return {partPath=base..'.part.png',exrPartPath=base..'.part.exr',dngPartPath=base..'.part.dng',width=1280,height=720,iso=100,aperture=2,shutterSeconds=1/125,focalLength=50,exposureMode=1,captured='2026:11:22 12:00:00'}
end
local function write(path,text) local f=assert(io.open(path,'wb'));f:write(text);f:close() end
local function exists(path) local f=io.open(path,'rb');if f then f:close();return true end end
local function jobpath() local f=assert(io.open(fixture..'/VHOLUMEPhotoCamera.dng-active','rb'));local p=f:read('*a');f:close();return p end
local m=module();local s=shot();m.begin(s);assert(m.busy());local path=jobpath()
write(path..'.progress','42');now=1110;m.poll();now=1220;m.poll();local status,progress=m.status(s);assert(status=='working' and progress==42)
write(path..'.result','OK\n1280\n720');m.poll();assert(m.status(s)=='done');m.release(s);assert(not m.busy() and not exists(path))
m.begin(s);path=jobpath();write(s.exrPartPath,'temporary');write(s.dngPartPath..'.writing','temporary');m.cancel(s);now=1226;m.poll()
assert(not m.busy() and not exists(s.exrPartPath) and not exists(s.dngPartPath..'.writing') and not exists(path))
m.begin(s);path=jobpath();now=1347;m.poll();assert(m.status(s)=='error');m.cancel(s);m.poll();assert(not m.busy())
m.begin(s);path=jobpath();write(s.dngPartPath,'interrupted');local recovered=module();assert(recovered.busy());now=1353;recovered.poll()
assert(not recovered.busy() and not exists(s.dngPartPath) and not exists(path));m.release(s)
os.execute=function() return nil end
assert(not pcall(m.begin,s));assert(not m.busy() and not exists(fixture..'/VHOLUMEPhotoCamera.dng-active'))
os.execute,os.time=execute,clock
print('PASS: DNG progress, completion, cancellation, timeout, interrupted-job recovery, and launch failure cleanup.')
