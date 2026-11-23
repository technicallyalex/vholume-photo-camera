local root='C:/Projects/VHOLUME Viewmodel/Photo Camera/Capture Preview/'
local work=root..'.work/'
local out=assert(io.open(work..'release-screenshots.log','wb'))
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
local poseRotation
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
 if poseRotation then originalFind('/Script/Engine.Controller:SetControlRotation')(pc,poseRotation) end
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
local mapSpec=dofile(work..'release-scene.lua')
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
local anchor
local function viewpoint(x,y,z,pitch,yaw)
 poseRotation={Pitch=pitch,Yaw=yaw,Roll=0}
 if not anchor then
  local pawn=call('/Script/Engine.Controller:K2_GetPawn',pc)
  anchor=pawn:GetWorld():SpawnActor(object('/Script/Engine.CameraActor'),{X=x,Y=y,Z=z},poseRotation)
  local component=call('/Script/Engine.Actor:GetComponentByClass',anchor,object('/Script/Engine.CameraComponent'))
  component.PostProcessSettings=state().firstPerson.PostProcessSettings
  state().firstPerson=component
 end
 call('/Script/Engine.Actor:K2_SetActorLocationAndRotation',anchor,{X=x,Y=y,Z=z},poseRotation,false,{},true)
 state().subjectCheck=0;step({});tap('MiddleMouseButton')
 local loc=call('/Script/Engine.SceneComponent:K2_GetComponentLocation',state().firstPerson)
 report(string.format('VIEW %.0f %.0f %.0f',loc.X,loc.Y,loc.Z))
end
local originalPoll
local function initialize()
 value('binds').persist=function()return true end
 value('captureConfig').step=function(key,amount)
  local cfg=value('captureConfig');local n=key=='format' and #cfg.formats or key=='resolution' and #cfg.edges or 2
  cfg[key]=(cfg[key]-1+amount)%n+1;return true
 end
 value('photos').directory=function()return work..'Release Photos/'end;value('photos').prepare=function()return true end
 local cfg=value('captureConfig');cfg.format=7;cfg.resolution=7;cfg.method=1
 local exp=value('exposure');exp.mode=1;exp.auto=false;exp.dofBoost=1;exp.grid=true;exp.iso=7;exp.aperture=16
 value('settings').frame=1;value('settings').reticle=1
 finder();value('changeLens')(mapSpec.lens or -2);value('changeFilm')(state(),mapSpec.film or 1)
 viewpoint(mapSpec.x,mapSpec.y,mapSpec.z,mapSpec.pitch,mapSpec.yaw)
 report('MAP '..mapSpec.map)
end
local tasks={initialize}
local function add(fn)tasks[#tasks+1]=fn end
if mapSpec.name=='city' then
 add(function()shot('release-city-finder')end)
 add(function()tap('Six')end)
 add(function()shot('release-city-studio')end)
 add(function()state().studio.focus('outputOpen',nil,1);tap('Enter')end)
 add(function()shot('release-city-output')end)
 add(function()tap('Six');state().studio.focus('exposureOpen',nil,5);tap('Enter');local exp=value('exposure');exp.mode=3;exp.auto=true;value('refreshStudio')(state())end)
 add(function()shot('release-city-exposure')end)
 add(function()tap('Six');step({Gamepad_LeftTrigger=true});step({});step({Gamepad_RightShoulder=true});step({});assert(state().controller)end)
 add(function()shot('release-city-controller')end)
 add(function()tap('Six');value('exposure').mode=1;value('exposure').auto=false;tap('RightMouseButton')end)
 add(function()
  originalPoll=value('rawOutput').poll;value('rawOutput').poll=function()end
  value('captureConfig').resolution=2;state().readyAt=0;tap('LeftMouseButton')
 end)
 add(function()if value('pending')then return false end;state().readyAt=0;tap('LeftMouseButton')end)
 add(function()if value('pending')then return false end;assert(value('rawOutput').count()==2);shot('release-city-queue')end)
 add(function()tap('Six')end)
 add(function()shot('release-city-studio-queue')end)
 add(function()value('rawOutput').poll=originalPoll end)
 add(function()if value('rawOutput').busy()then return false end;report('PASS two genuine captured RAW jobs saved')end)
elseif mapSpec.name=='nightlife' then
 add(function()value('changeRatio')(state(),6)end)
 add(function()shot('release-nightlife-panorama')end)
 add(function()value('changeRatio')(state(),4)end)
 add(function()shot('release-nightlife-wide')end)
else
 add(function()local exp=value('exposure');exp.aperture=16;exp.iso=10;exp.dofBoost=1;value('applyExposure')(state(),true);tap('MiddleMouseButton');value('updateLabels')(state())end)
 add(function()shot('release-showers-focus')end)
end
add(function()report('PASS genuine v1.1.0 screenshots: '..mapSpec.name);command('quit')end)


LoopInGameThreadWithDelay(250,function()
 if finished then return end
 local ok,err=pcall(function()
  local engine=FindFirstOf('GameEngine')
  if not valid(engine) or not valid(engine.GameViewport) then return end
  pc=gp():GetPlayerController(engine.GameViewport,0);if not valid(pc) then return end
  local now=gp():GetRealTimeSeconds(pc);assert(now<240,'QA timeout at phase '..phase)
  if not opened then
   arrival=arrival or now;if now-arrival<4 then return end
   opened=true;gp():OpenLevel(pc,FName(mapSpec.map),true,'');return
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
  phase=phase+1;due=now+2.2
 end)
 if not ok then
  finished=true;StaticFindObject=originalFind;report('ERROR phase '..phase..' '..tostring(err))
  if valid(pc) then gp():SetGamePaused(pc,false);command('r.SetRes 1920x1080w');command('quit') end
 end
end)
