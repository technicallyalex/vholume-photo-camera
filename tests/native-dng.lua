local root='C:/Projects/VHOLUME Viewmodel/Photo Camera/Capture Preview/'
local work=root..'.work/'
local out=assert(io.open(work..'native-dng.log','wb'))
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
local function completed(cancelled)
 if value('pending') or value('captureResolution').busy() or value('rawOutput').busy() then return false end
 assert(restored(),'Video restoration failed')
 assert(not lastShot.actor,'Render actor leaked')
 local image=dofile(root..'ue4ss/Mods/VHOLUMEPhotoCamera/Scripts/image_file.lua')
 for _,v in ipairs({{'png',lastShot.path,image.png,lastShot.png},{'exr',lastShot.exrPath,image.exr,lastShot.keepEXR},{'dng',lastShot.dngPath,image.dng,lastShot.dng}}) do
  local w,h=v[3](v[2])
  if not cancelled and v[4] then assert(w==lastShot.width and h==lastShot.height,'Missing/invalid '..v[1]) else assert(not w,'Unexpected '..v[1]) end
 end
 for _,suffix in ipairs({'.part.png','.part.exr','.part.dng','.part.dng.writing'}) do local f=io.open(lastShot.base..suffix,'rb');if f then f:close();error('Leaked '..suffix) end end
 report('PASS '..(cancelled and 'cancel/error cleanup' or lastShot.formatName..' validated')..' '..lastShot.width..'x'..lastShot.height..'; video restored')
 return true
end
local rawBegin
local tasks={
 function()
  local _,v,m=video();stored={X=v.X,Y=v.Y};mode=m
  value('photos').directory=function() return work end;value('photos').prepare=function() return true end
  value('binds').persist=function() return true end
  startPhoto(4)
 end,
 function() return completed() end,
 function() startPhoto(5) end,
 function() return completed() end,
 function() startPhoto(6) end,
 function() return completed() end,
 function() startPhoto(7) end,
 function() return completed() end,
 function() startPhoto(4,2,4,2) end,
 function() return completed() end,
 function() startPhoto(4,6,1) end,
 function() return completed() end,
 function() startPhoto(6,7,3) end,
 function() return completed() end,
 function() startPhoto(4,7,3) end,
 function()
  if not lastShot.convertingDNG then assert(value('pending'),'DNG finished before cancel');return false end
  tap('RightMouseButton');report('CANCEL during DNG conversion')
 end,
 function() return completed(true) end,
 function()
  rawBegin=value('rawOutput').begin
  value('rawOutput').begin=function(shot) local f=assert(io.open(shot.exrPartPath,'wb'));f:write('corrupt EXR fixture');f:close();return rawBegin(shot) end
  startPhoto(7,2,4,2)
 end,
 function()
  if not completed(true) then return false end
  value('rawOutput').begin=rawBegin;report('PASS worker failure restores video and removes paired temporary images')
 end,
 function() startPhoto(4,2,4,1,true);assert(lastShot.duration>0) end,
 function() return completed() end,
 function()
  value('captureConfig').format=7
  tap('Six');state().studio.focus('outputOpen',nil,1);tap('Enter');assert(state().outputPage)
 end,
 function() shot('ui-dng-output');report('PASS all-format output screen') end,
 function() tap('Five');report('PASS DNG integration QA complete');command('quit') end,
}

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
