local root='C:/Projects/VHOLUME Viewmodel/Photo Camera/Capture Preview/'
local work=root..'.work/'
local marker=io.open(work..'queue-resume','rb');local resume=marker~=nil;if marker then marker:close() end
local out=assert(io.open(work..(resume and 'native-queue-resume.log' or 'native-queue.log'),'wb'))
local function report(s) out:write(tostring(s)..'\n');out:flush() end
local function valid(o) return o and o:IsValid() end
local originalFind=StaticFindObject
local function object(path) local o=originalFind(path);assert(valid(o),path);return o end
local function call(path,ctx,...) return object(path)(ctx,...) end
local function gp() return object('/Script/Engine.Default__GameplayStatics') end
local pc,tick,up,down,opened,arrival,pawnAt,due
local phase=0
local finished=false
local lastShot
up,down={},{}
local function inputObject(path)
 local analog=path:match(':GetInputAnalogKeyState$')
 if not analog and not path:match(':WasInputKeyJustPressed$') and not path:match(':IsInputKeyDown$') then return originalFind(path) end
 return setmetatable({IsValid=function() return true end},{__call=function(_,player,key)
  if analog then return 0 end
  local name=key.KeyName:ToString()
  return (path:match(':IsInputKeyDown$') and down[name] or up[name]) or false
 end})
end
local function step(keys)
 up,down=keys or {},keys or {}
 StaticFindObject=inputObject
 local ok,err=pcall(tick)
 StaticFindObject=originalFind
 assert(ok,err)
 up,down={},{}
end
local function tap(key) step({[key]=true});step({}) end
local function value(name)
 local visited={}
 local function find(fn,depth)
  if visited[fn] or depth>5 then return false end
  visited[fn]=true
  local functions={}
  for i=1,150 do
   local id,v=debug.getupvalue(fn,i);if not id then break end
   if id==name then return true,v end
   if type(v)=='function' then functions[#functions+1]=v end
  end
  for _,child in ipairs(functions) do local found,v=find(child,depth+1);if found then return true,v end end
  return false
 end
 local found,v=find(tick,0);assert(found,'Missing QA upvalue '..name);return v
end
local function state() return value('state') end
local function expect(studio,raised)
 local s=assert(state(),'Camera state unexpectedly absent')
 assert((s.studio~=nil)==studio,'Unexpected Studio visibility')
 assert(s.raised==raised,'Unexpected viewfinder state')
 return s
end
local function command(text)
 object('/Script/Engine.Default__KismetSystemLibrary'):ExecuteConsoleCommand(pc,text,pc)
end
local function shot(name) command('Shot SHOWUI filename="'..work..name..'.png"') end
local loaded=false
local stored,folderStarted,folderMessage,initialSize,mode,allocationStart
local userPath='/Script/Engine.GameUserSettings:'
local function video()
 local user=call(userPath..'GetGameUserSettings',object('/Script/Engine.Default__GameUserSettings'))
 local size=call(userPath..'GetScreenResolution',user)
 local mode=call(userPath..'GetFullscreenMode',user)
 return user,size,mode
end
local function restored()
 if value('pending') or value('captureResolution').busy() then return false end
 local size=object('/Script/UMG.Default__WidgetLayoutLibrary'):GetViewportSize(pc)
 if size.X~=1920 or size.Y~=1080 then return false end
 local _,storedSize,storedMode=video()
 assert(storedSize.X==stored.X and storedSize.Y==stored.Y and storedMode==mode,'Stored video values changed')
 return true
end
local function finder()
 if not state() then tap('Five') end
 if state().studio then tap('RightMouseButton') elseif not state().raised then tap('RightMouseButton') end
 state().readyAt=0
end
local function begin()
 finder();tap('LeftMouseButton');lastShot=assert(value('pending'),'Shutter did not start')
end
local function output() tap('Six');tap('Enter');assert(state().outputPage,'Photo card did not open Output Settings') end
local function startPhoto(fmt,res,frame,method,moving)
 finder()
 local cfg=value('captureConfig');cfg.format=fmt;cfg.resolution=res or 2;cfg.method=method or 1
 value('settings').frame=frame or 4;value('exposure').mode=moving and 2 or 1
 if moving then value('exposure').shutter=9;step({}) end
 state().readyAt=0;tap('LeftMouseButton');lastShot=assert(value('pending'))
 report('START '..lastShot.formatName..' '..lastShot.width..'x'..lastShot.height..' method '..cfg.method)
end
local originalPoll
local shots={}
local function filewrite(path,body) local f=assert(io.open(path,'wb'));f:write(body);f:close() end
local function validate(s,failed)
 local image=dofile(root..'ue4ss/Mods/VHOLUMEPhotoCamera/Scripts/image_file.lua')
 for _,v in ipairs({{'png',s.path,image.png,s.png},{'exr',s.exrPath,image.exr,s.keepEXR},{'dng',s.dngPath,image.dng,true}}) do
  local w,h=v[3](v[2]);if not failed and v[4] then assert(w==s.width and h==s.height,'Missing '..v[1]) else assert(not w,'Unexpected '..v[1]) end
 end
 for _,suffix in ipairs({'.part.png','.part.exr','.part.dng','.part.dng.writing'}) do local f=io.open(s.base..suffix,'rb');if f then f:close();error('Leaked '..suffix) end end
end
local function start(res,fmt)
 startPhoto(fmt or 4,res or 2,4,1)
 shots[#shots+1]=lastShot
end
local tasks={}
local function add(fn) tasks[#tasks+1]=fn end
if not resume then
 add(function()
  local _,v,m=video();stored={X=v.X,Y=v.Y};mode=m
  value('photos').directory=function() return work end;value('photos').prepare=function() return true end
  value('binds').persist=function() return true end
  originalPoll=value('rawOutput').poll;value('rawOutput').poll=function() end
  start(2,7)
 end)
 for i=1,8 do
  add(function()
   if value('pending') then return false end
   assert(value('rawOutput').count()==i,'Wrong queue count')
   assert(not lastShot.actor,'Queued photo retained GPU actor')
   if i==3 then filewrite(lastShot.exrPartPath,'bad middle queued input') end
   report('PASS captured photo '..i..' while older DNG jobs waited; '..lastShot.focalLength..' mm')
  end)
  if i<8 then add(function() tap('RightBracket');start(2,i%3==0 and 5 or 4) end) end
 end
 add(function()
  assert(value('rawOutput').full());state().readyAt=0;tap('LeftMouseButton');assert(not value('pending'))
  assert(value('rawOutput').count()==8);report('PASS full queue prevents ninth capture without replacing any photo')
  shot('queue-full-finder')
 end)
 add(function() tap('RightMouseButton');tap('Six');assert(state().studio);shot('queue-full-studio') end)
 add(function()
  tap('Five');value('rawOutput').poll=originalPoll;report('PROCESS real FIFO while camera is stowed')
 end)
 add(function()
  if value('rawOutput').busy() then return false end
  for i,s in ipairs(shots) do validate(s,i==3) end
  assert(not state());report('PASS seven saves completed; failed middle photo isolated; every queued GPU target released')
  originalPoll=value('rawOutput').poll;value('rawOutput').poll=function() end
  start(7,7)
 end)
 add(function() if value('pending') then return false end;start(2,5) end)
 add(function() if value('pending') then return false end;start(2,4) end)
 add(function()
  if value('pending') then return false end
  assert(value('rawOutput').count()==3)
  local data={'return {'}
  for _,s in ipairs(value('rawOutput').shots()) do
   data[#data+1]=string.format('{base=%q,path=%q,exrPath=%q,dngPath=%q,width=%d,height=%d,png=%s,keepEXR=%s},',s.base,s.path,s.exrPath,s.dngPath,s.width,s.height,tostring(s.png),tostring(s.keepEXR))
  end
  data[#data+1]='}';filewrite(work..'queue-expected.lua',table.concat(data,'\n'));filewrite(work..'queue-resume','resume')
  value('rawOutput').poll=originalPoll;step({})
  report('PASS queued 8K plus two following photos; quitting with converter active for restart recovery')
  command('quit')
 end)
else
 add(function()
  local _,v,m=video();stored={X=v.X,Y=v.Y};mode=m
  value('binds').persist=function() return true end
  report('RESUME '..value('rawOutput').count()..' persisted saves')
 end)
 add(function()
  if value('rawOutput').busy() then return false end
  for _,s in ipairs(dofile(work..'queue-expected.lua')) do validate(s,false) end
  report('PASS restart recovered every photo including running 8K conversion; journal drained without leftovers')
  command('quit')
 end)
end

LoopInGameThreadWithDelay(250,function()
 if finished then return end
 local ok,err=pcall(function()
  local engine=FindFirstOf('GameEngine')
  if not valid(engine) or not valid(engine.GameViewport) then return end
  pc=gp():GetPlayerController(engine.GameViewport,0);if not valid(pc) then return end
  local now=gp():GetRealTimeSeconds(pc);assert(now<480,'QA timeout at phase '..phase)
  if not opened then
   arrival=arrival or now;if now-arrival<4 then return end
   opened=true;gp():OpenLevel(pc,FName('/Game/Levels/DemoConapt/Demo00_Conapt00'),true,'');return
  end
  local pawn=call('/Script/Engine.Controller:K2_GetPawn',pc);if not valid(pawn) then return end
  pawnAt=pawnAt or now;if now-pawnAt<3 then return end
  if not loaded then
   loaded=true
   local after,delay=LoopInGameThreadAfterFrames,LoopInGameThreadWithDelay
   LoopInGameThreadAfterFrames=function(_,callback) tick=callback end
   LoopInGameThreadWithDelay=function(_,callback) tick=callback end
   StaticFindObject=inputObject
   local yes,reason=pcall(dofile,root..'ue4ss/Mods/VHOLUMEPhotoCamera/Scripts/main.lua')
   StaticFindObject=originalFind;LoopInGameThreadAfterFrames,LoopInGameThreadWithDelay=after,delay
   assert(yes,reason);assert(tick);step({})
  end
  step({});if due and now<due then return end
  local action=tasks[phase+1];if not action then finished=true;return end
  if action()==false then due=now+.25;return end
  phase=phase+1;due=now+.7
 end)
 if not ok then
  finished=true;StaticFindObject=originalFind;report('ERROR phase '..phase..' '..tostring(err))
  if valid(pc) then gp():SetGamePaused(pc,false);command('r.SetRes 1920x1080w');command('quit') end
 end
end)
