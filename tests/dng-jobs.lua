local originalDofile=dofile
_G.dofile=function(path)
 if path==scripts..'platform.lua' then return function() return {
  ready=function() return true end,
  launchDng=function() assert(os.execute('test converter'),'launch failed') end,
 } end end
 return originalDofile(path)
end
local factory=dofile(scripts..'dng.lua')
local execute,clock=os.execute,os.time
local now,launches,serial=1000,0,0
os.time=function() return now end
os.execute=function() launches=launches+1;return true end
local function module() local m=factory(scripts,function() end);m.load(fixture);return m end
local function shot()
 serial=serial+1
 local base=fixture..'/VHOLUME_dng-test-'..serial
 return {base=base,path=base..'.png',partPath=base..'.part.png',exrPath=base..'.exr',exrPartPath=base..'.part.exr',
 dngPath=base..'.dng',dngPartPath=base..'.part.dng',dng=true,png=true,keepEXR=false,
 width=1280,height=720,iso=100,aperture=2,shutterSeconds=1/125,focalLength=50,exposureMode=1,
 captured='2026:11:23 12:00:00',film='Neutral',method='Dedicated render',samples=5}
end
local function write(path,text) local f=assert(io.open(path,'wb'));f:write(text);f:close() end
local function exists(path) local f=io.open(path,'rb');if f then f:close();return true end end
local function paths()
 local f=assert(io.open(fixture..'/VHOLUMEPhotoCamera.dng-active','rb'));local p=f:read('*a');f:close()
 local values={};for path in p:sub(11):gmatch('[^\r\n]+') do values[#values+1]=path end;return values
end
local m=module();local shots={}
for i=1,8 do shots[i]=shot();m.begin(shots[i]) end
assert(m.count()==8 and m.full() and launches==0)
assert(not pcall(m.begin,shot()) and m.count()==8)
assert(m.status(shots[2])=='queued');m.poll();assert(launches==1)
local job=paths()[1];write(job..'.progress','42');now=1110;m.poll();now=1220;m.poll()
local status,progress=m.status(shots[1]);assert(status=='working' and progress==42 and launches==1)
write(job..'.result','OK\n1280\n720');m.poll();assert(m.status(shots[1])=='done')
m.release(shots[1]);m.poll();assert(launches==2 and m.count()==7 and m.status(shots[2])=='working')
-- A failed head does not cancel any later captured image.
job=paths()[1];write(job..'.result','ERROR\nfixture failure');m.poll();assert(m.status(shots[2])=='error')
m.cancel(shots[2]);m.poll();assert(m.count()==6 and launches==3 and m.status(shots[3])=='working')
-- Queued cancellation never starts another worker or touches another job's parts.
write(shots[4].exrPartPath,'temporary');write(shots[5].exrPartPath,'keep')
m.cancel(shots[4]);m.poll();assert(m.count()==5 and not exists(shots[4].exrPartPath) and exists(shots[5].exrPartPath))
-- Recover a live head plus waiting jobs with immutable capture settings.
local recovered=module();local list=recovered.shots();assert(#list==5 and list[1].iso==100 and list[1].samples==5)
assert(list[1].png and not list[1].keepEXR and list[1].film=='Neutral' and list[1].renderReleased)
assert(recovered.status(list[1])=='working' and recovered.status(list[2])=='queued')
recovered.poll();assert(launches==3,'Recovery launched a second converter')
-- Publishing can be acknowledged after reload; the next job starts in FIFO order.
job=paths()[1];write(job..'.result','OK\n1280\n720');recovered.poll();recovered.release(list[1]);recovered.poll();assert(launches==4)
-- A no-progress timeout is confined to the active job.
now=1347;recovered.poll();assert(recovered.status(list[2])=='error');recovered.cancel(list[2]);recovered.poll()
assert(recovered.count()==3 and launches==5)
for _,s in ipairs(recovered.shots()) do recovered.cancel(s) end
now=1353;recovered.poll();assert(not recovered.busy() and not exists(fixture..'/VHOLUMEPhotoCamera.dng-active'))
-- Journal failure must leave the existing queue intact.
m=module();local one=shot();m.begin(one)
local rename=os.rename;os.rename=function() return nil,'injected failure' end
assert(not pcall(m.begin,shot()) and m.count()==1);os.rename=rename
m.cancel(one);m.poll();assert(not m.busy())
-- Launch failure is reported to the owner, then cleaned without a dead queue.
os.execute=function() return nil end
one=shot();m.begin(one);m.poll();assert(m.status(one)=='error');m.cancel(one);m.poll();assert(not m.busy())
os.execute,os.time=execute,clock
_G.dofile=originalDofile
print('PASS: 8-photo FIFO, full-queue backpressure, one worker, progress, failure isolation, queued cancellation, persisted recovery, timeout, journal/launch failure cleanup.')
