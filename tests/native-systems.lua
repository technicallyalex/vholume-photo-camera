local root='C:/Projects/VHOLUME Viewmodel/Photo Camera/Capture Preview/'
local work=root..'.work/'
local out=assert(io.open(work..'native-systems.log','wb'))
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
local baseYaw,basePitch,moveSpeeds,checks=0,0,{},0
local function near(a,b) assert(math.abs(a-b)<.0001,tostring(a)..' differs from '..tostring(b)) end
local function wheel(modifier,other)
 local keys={MouseScrollUp=true};if modifier then keys[modifier]=true end;if other then keys[other]=true end;step(keys);step({})
end
local tasks={}
local function add(f) tasks[#tasks+1]=f end
add(function()
 value('binds').persist=function() return true end
 baseYaw,basePitch=pc.InputYawScale,pc.InputPitchScale
 finder();assert(value('optics').enabled,'DOF not enabled by default')
 moveSpeeds={state().movement.MaxWalkSpeed,state().movement.MaxWalkSpeedCrouched}
 report('PASS default controls enter finder; DOF is on before autofocus')
end)
for i=1,8 do
 add(function()
  assert(state().focalLength>0);assert(math.abs(pc.InputYawScale)<=math.abs(baseYaw)+.0001,'Wide lens sped up yaw')
  assert(math.abs(pc.InputPitchScale)<=math.abs(basePitch)+.0001,'Wide lens sped up pitch')
  report('PASS lens '..state().focalLength..' mm FOV '..state().lens.FieldOfView..'; aim scale '..pc.InputYawScale)
  wheel('R')
 end)
end
add(function()
 tap('RightMouseButton');near(pc.InputYawScale,baseYaw);near(pc.InputPitchScale,basePitch);tap('RightMouseButton')
 local old=value('lensIndex');wheel('R');assert(value('lensIndex')~=old)
 local a=value('exposure').aperture;wheel('LeftControl');assert(value('exposure').aperture~=a)
 local mode=value('exposure').mode;wheel('U');assert(value('exposure').mode~=mode)
 local iso=value('exposure').iso;wheel('LeftControl','LeftAlt');assert(value('exposure').iso~=iso)
 local speed=value('exposure').shutter;wheel('LeftAlt');assert(value('exposure').shutter~=speed)
 report('PASS dedicated R/U/Ctrl/Alt/Ctrl+Alt wheel controls; original look scales restored on lower')
end)
for i=1,4 do add(function()
 local exp=value('exposure');exp.mode=i;exp.auto=i~=1;exp.minISO=2;exp.maxISO=13
 value('updateExposure')(state(),true)
 local v=state().exposure;assert(not state().meterFailed and (i==1 or (v.iso>=125 and v.iso<=1600)))
 if i~=1 then assert(state().lens.PostProcessSettings.AutoExposureMethod==2) end
 report('PASS exposure mode '..exp.modes[i][1]..' / Auto ISO '..v.iso)
end) end
add(function()
 local exp=value('exposure');exp.mode=2;exp.auto=false;exp.aperture=1;exp.shutter=#exp.speeds
 value('updateExposure')(state(),true);assert(state().exposure.speed==32000 and state().exposure.aperture==1)
 local bias=state().lens.PostProcessSettings.AutoExposureBias
 exp.iso=7;value('updateExposure')(state(),true);assert(state().lens.PostProcessSettings.AutoExposureBias>bias)
 exp.dofBoost=4;value('updateExposure')(state(),true);near(state().lens.PostProcessSettings.DepthOfFieldFstop,state().exposure.aperture/8)
 report('PASS f/1, 1/32000 s, ISO brightness and 8x lens blur')
 exp.mode=1;exp.auto=false;value('updateExposure')(state(),true)
end)
add(function()
 local o=value('optics');tap('F');if not o.manual then tap('F') end
 o.distance=400;state().focusGoal=nil;wheel();local coarse=state().focusGoal or o.distance
 o.distance=400;state().focusGoal=nil;wheel('LeftShift');local fine=state().focusGoal or o.distance
 assert(math.abs(fine-400)<math.abs(coarse-400),'Fine focus is not finer')
 tap('MiddleMouseButton');assert(o.locked,'Single-shot AF did not lock focus')
 tap('B');assert(not o.enabled);tap('B');assert(o.enabled)
 tap('V');assert(state().movement.MaxWalkSpeed<=moveSpeeds[1]);tap('V');near(state().movement.MaxWalkSpeed,moveSpeeds[1])
 report('PASS manual/fine focus, single-shot AF, DOF toggle and slow-walk restore')
end)
add(function()
 local e=value('exposure');e.iso=1;value('updateExposure')(state(),true);local low=state().lens.PostProcessSettings.FilmGrainIntensity
 e.iso=#e.isos;value('updateExposure')(state(),true);assert(state().lens.PostProcessSettings.FilmGrainIntensity>low)
 for i=1,#value('film').stocks do wheel('T');assert(state().lens.PostProcessSettings.FilmGrainIntensity>low) end
 report('PASS all 11 film looks; ISO controls rendered grain intensity')
end)
for i=1,7 do add(function()
 wheel('Y');local r=state().rect;assert(r.x>=50 and r.width-r.x-r.w>=50,'Sidebar margin disappeared')
 local f=value('film').frames[value('settings').frame];assert(math.abs(r.w/r.h-f[2]/f[3])<.01)
 if f[2]~=f[3] then local p=r.portrait;tap('P');assert(state().rect.portrait~=p);tap('P') end
 if f[2]==65 or f[2]==16 then shot('systems-finder-'..f[2]..'x'..f[3]) end
 report('PASS '..f[2]..':'..f[3]..' frame, fixed sidebars and portrait rotation')
end) end
add(function()
 tap('Six');for i=1,4 do state().studio.focus('reticle',1,4);tap('Enter') end
 state().studio.focus('grid',nil,4);local old=value('exposure').grid;tap('Enter');assert(value('exposure').grid~=old)
 state().studio.focus('dofBoost',1,2);local boost=value('exposure').dofBoost;tap('Enter');assert(value('exposure').dofBoost~=boost)
 tap('RightMouseButton');report('PASS all four reticles, thirds grid and Studio DOF arrows')
end)
add(function()
 step({Gamepad_LeftShoulder=true,Gamepad_DPad_Up=true});step({});assert(state().controller)
 step({Gamepad_RightShoulder=true,Gamepad_DPad_Right=true});step({});assert(value('optics').manual)
 step({Gamepad_DPad_Up=true});step({});step({Gamepad_RightShoulder=true,Gamepad_FaceButton_Right=true});step({})
 step({Gamepad_LeftTrigger=true});step({});assert(not state().raised)
 step({Gamepad_LeftTrigger=true});step({});assert(state().raised)
 report('PASS simulated controller layers, exposure/focus, Auto ISO and finder controls; hardware not connected')
end)
add(function()
 call('/Script/Engine.Controller:SetControlRotation',pc,{Pitch=-35,Yaw=0,Roll=0})
 tap('G');assert(state().placing);report('START subject placement with default G shortcut')
end)
for i=1,5 do
 add(function() if value('settings').pose~=i then tap('C') end;state().subjectCheckAt=0 end)
 add(function()
  assert(state().subjectPreview and not state().subjectPreview.posePending,'Subject pose did not load')
  assert(state().subjectPreview.pose==i,'Wrong subject pose')
  report('PASS subject pose '..value('subjects').poses[i][1]..' with stock closed-eye head')
  if i==2 then shot('systems-subject-pose') end
 end)
end
add(function()
 tap('LeftMouseButton');assert(#state().placedSubjects==1,'Place subject failed');tap('BackSpace');assert(#state().placedSubjects==0)
 tap('RightMouseButton');assert(not state().placing);report('PASS place/undo/end subject workflow')
 finder();value('audio').play(state(),'shutter',gp():GetRealTimeSeconds(pc))
end)
add(function()
 assert(not state().soundFailed and state().soundChannels.handling)
 local player=state().soundChannels.handling.player
 assert(player:IsReady(),'Camera sound media did not become ready')
 report('PASS real camera audio player opened handling cue; listening quality not assessed')
 tap('Five')
end)
add(function()
 if state() then return false end
 near(pc.InputYawScale,baseYaw);near(pc.InputPitchScale,basePitch)
 report('PASS final stow and original input scales restored');command('quit')
end)

LoopInGameThreadWithDelay(250,function()
 if finished then return end
 local ok,err=pcall(function()
  local engine=FindFirstOf('GameEngine')
  if not valid(engine) or not valid(engine.GameViewport) then return end
  pc=gp():GetPlayerController(engine.GameViewport,0);if not valid(pc) then return end
  local now=gp():GetRealTimeSeconds(pc);assert(now<240,'QA timeout at phase '..phase)
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
