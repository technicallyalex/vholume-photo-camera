local exposure=dofile(scripts..'exposure.lua')
local factory=dofile(scripts..'bindings.lua')
local ue={call=function() return false end}
local function write(path,body) local f=assert(io.open(path,'wb'));f:write(body);f:close() end
local function read(path) local f=assert(io.open(path,'rb'));local body=f:read('*a');f:close();return body end
local old='aimScaling=0\nthirdsGrid=1\ndofBoost=3\nstudio=Four\nlensPrev=Q\nlensNext=E\nmenuSelect=Six\n'
write(fixture..'/VHOLUMEPhotoCamera.keys.input-preview',old)
local binds=factory(ue,function() end,exposure)
binds.load(fixture)
local function defaults(b)
 local seen={}
 for _,group in ipairs(b.groups) do
  for i=2,#group do
   local id,_,key=table.unpack(group[i])
   assert(b.name(id)==key,id..' did not reset to default')
   assert(not seen[key],key..' is duplicated')
   seen[key]=true
  end
 end
end
defaults(binds)
assert(binds.name('equip')=='Five' and binds.name('studio')=='Six')
assert(binds.name('menuSelect')=='Enter' and binds.name('finder')=='RightMouseButton')
assert(binds.name('lensPrev')=='LeftBracket' and binds.name('lensNext')=='RightBracket')
assert(exposure.grid and exposure.dofBoost==3 and not binds.aimScaling())
assert(read(fixture..'/VHOLUMEPhotoCamera.keys.input-preview')==old)
assert(read(fixture..'/VHOLUMEPhotoCamera.keys.controls-preview'):find('studio=Six',1,true))
assert(not binds.assign('studio','Five'))
assert(binds.assign('studio','Four'))
local reloaded=factory(ue,function() end,exposure)
reloaded.load(fixture)
assert(reloaded.name('studio')=='Four')
assert(reloaded.reset())
defaults(reloaded)
assert(reloaded.assign('menuSelect','Enter'))
assert(not reloaded.assign('studio','Enter'))
local keys={}
for _,key in ipairs(reloaded.cameraKeys()) do keys[key]=true end
assert(keys.Five and keys.Six and keys.RightMouseButton and not keys.F9)
print('PASS: all defaults unique; 5 camera, 6 Studio, RMB finder, Enter select; fresh profile ignores old remaps; options preserved; resets persist.')
