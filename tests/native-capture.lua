local root='C:/Projects/VHOLUME Viewmodel/Photo Camera/Capture Preview/'
local work=root..'.work/'
local out=assert(io.open(work..'native-capture.log','wb'))
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
 for i=1,100 do
  local id,v=debug.getupvalue(tick,i)
  if not id then break end
  if id==name then return v end
 end
 error('Missing QA upvalue '..name)
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
LoopInGameThreadWithDelay(250,function()
 if finished then return end
 local ok,err=pcall(function()
  local engine=FindFirstOf('GameEngine')
  if not valid(engine) or not valid(engine.GameViewport) then return end
  pc=gp():GetPlayerController(engine.GameViewport,0)
  if not valid(pc) then return end
  local now=gp():GetRealTimeSeconds(pc)
  assert(now<240,"Capture QA timeout")
  if not opened then
   arrival=arrival or now
   if now-arrival<4 then return end
   opened=true;gp():OpenLevel(pc,FName('/Game/Levels/DemoConapt/Demo00_Conapt00'),true,'');return
  end
  local pawn=call('/Script/Engine.Controller:K2_GetPawn',pc)
  if not valid(pawn) then return end
  pawnAt=pawnAt or now
  if now-pawnAt<3 then return end
  if tick then step({}) end
  if due and now<due then return end
  if phase==0 then
   local after,delay=LoopInGameThreadAfterFrames,LoopInGameThreadWithDelay
   LoopInGameThreadAfterFrames=function(_,callback) tick=callback end
   LoopInGameThreadWithDelay=function(_,callback) tick=callback end
   StaticFindObject=inputObject
   local loaded,reason=pcall(dofile,root..'ue4ss/Mods/VHOLUMEPhotoCamera/Scripts/main.lua')
   StaticFindObject=originalFind
   LoopInGameThreadAfterFrames,LoopInGameThreadWithDelay=after,delay
   assert(loaded,reason);assert(tick)
   step({})
   value('photos').directory=function() return work end
   value('photos').prepare=function() return true end
   local cfg=value('captureConfig');cfg.format=3;cfg.resolution=1;cfg.method=1
   report('PASS native capture module loaded')
  elseif phase==1 then tap('Five');tap('RightMouseButton');expect(false,true)
  elseif phase==2 then
   tap('Six');state().studio.focus('outputOpen',nil,1);tap('Enter')
   assert(state().outputPage);shot('output-settings');report('PASS output page opens')
  elseif phase==3 then tap('RightMouseButton');expect(false,true)
  elseif phase==4 then tap('LeftMouseButton');assert(value('pending'));lastShot=value('pending');report('START native size PNG + EXR')
  elseif phase==5 then
   if value('pending') then lastShot=value('pending');due=now+.25;return end
   assert(lastShot and dofile(root..'ue4ss/Mods/VHOLUMEPhotoCamera/Scripts/image_file.lua').png(lastShot.path) and dofile(root..'ue4ss/Mods/VHOLUMEPhotoCamera/Scripts/image_file.lua').exr(lastShot.exrPath),'Shot output missing')
   report('PASS native shot completed');tap('Six');shot('studio-output')
  elseif phase==6 then
   local cfg=value('captureConfig');cfg.resolution=4;tap('RightMouseButton');state().readyAt=now;tap('LeftMouseButton');assert(value('pending'));lastShot=value('pending');report('START larger 2560 render')
  elseif phase==7 then
   if value('pending') then lastShot=value('pending');due=now+.25;return end
   assert(lastShot and dofile(root..'ue4ss/Mods/VHOLUMEPhotoCamera/Scripts/image_file.lua').png(lastShot.path) and dofile(root..'ue4ss/Mods/VHOLUMEPhotoCamera/Scripts/image_file.lua').exr(lastShot.exrPath),'Shot output missing')
   report('PASS larger render completed')
   local cfg=value('captureConfig');cfg.resolution=2;cfg.method=2
   value('settings').frame=4
   tap('Six');tap('RightMouseButton')
  elseif phase==8 then
   tap('LeftMouseButton');assert(value('pending'));lastShot=value('pending');report('START temporary game resolution')
  elseif phase==9 then
   if value('pending') then lastShot=value('pending');due=now+.25;return end
   assert(lastShot and dofile(root..'ue4ss/Mods/VHOLUMEPhotoCamera/Scripts/image_file.lua').png(lastShot.path) and dofile(root..'ue4ss/Mods/VHOLUMEPhotoCamera/Scripts/image_file.lua').exr(lastShot.exrPath),'Shot output missing')
   local user=call('/Script/Engine.GameUserSettings:GetGameUserSettings',object('/Script/Engine.Default__GameUserSettings'))
   local size=call('/Script/Engine.GameUserSettings:GetScreenResolution',user)
   assert(size.X==1920 and size.Y==1080,'Settings resolution did not restore')
   local vp=object('/Script/UMG.Default__WidgetLayoutLibrary'):GetViewportSize(pc)
   assert(vp.X==1920 and vp.Y==1080,'Actual viewport did not restore')
   report('PASS temporary resolution capture returned to 1920x1080')
  elseif phase==10 then
   local cfg=value('captureConfig');cfg.method=1
   local exp=value('exposure');exp.mode=2;exp.shutter=9
   tap('Six');tap('RightMouseButton')
  elseif phase==11 then tap('LeftMouseButton');assert(value('pending'));lastShot=value('pending');report('START integrated motion PNG + EXR')
  elseif phase==12 then
   if value('pending') then lastShot=value('pending');due=now+.25;return end
   assert(lastShot and dofile(root..'ue4ss/Mods/VHOLUMEPhotoCamera/Scripts/image_file.lua').png(lastShot.path) and dofile(root..'ue4ss/Mods/VHOLUMEPhotoCamera/Scripts/image_file.lua').exr(lastShot.exrPath),'Shot output missing')
   report('PASS motion completed')
   local cfg=value('captureConfig');cfg.method=2;cfg.resolution=3
   tap('LeftMouseButton');assert(value('pending'))
  elseif phase==13 then
   tap('RightMouseButton');assert(not value('pending'));report('PASS cancellation restores capture state')
  elseif phase==14 then
   local vp=object('/Script/UMG.Default__WidgetLayoutLibrary'):GetViewportSize(pc)
   assert(vp.X==1920 and vp.Y==1080,'Cancellation did not restore viewport')
   report('PASS cancellation restored actual viewport')
   local cfg=value('captureConfig');cfg.format=1;cfg.method=1;cfg.resolution=2
   value('exposure').mode=1;tap('RightMouseButton')
  elseif phase==15 then tap('LeftMouseButton');lastShot=value('pending');assert(lastShot);report('START PNG only')
  elseif phase==16 then
   if value('pending') then due=now+.25;return end
   assert(dofile(root..'ue4ss/Mods/VHOLUMEPhotoCamera/Scripts/image_file.lua').png(lastShot.path),'PNG-only output missing')
   local f=io.open(lastShot.exrPath,'rb');assert(not f,'Unexpected EXR in PNG-only mode')
   report('PASS PNG only')
   local cfg=value('captureConfig');cfg.format=2;value('settings').frame=6
   tap('Six');tap('RightMouseButton')
  elseif phase==17 then tap('LeftMouseButton');lastShot=value('pending');assert(lastShot);report('START EXR-only 21:9')
  elseif phase==18 then
   if value('pending') then due=now+.25;return end
   local w,h=dofile(root..'ue4ss/Mods/VHOLUMEPhotoCamera/Scripts/image_file.lua').exr(lastShot.exrPath)
   assert(w and w*9==h*21,'EXR-only 21:9 missing')
   report('PASS EXR only ultrawide')
   value('captureConfig').format=3;value('settings').frame=7
   tap('Six');tap('RightMouseButton');tap('P')
  elseif phase==19 then tap('LeftMouseButton');lastShot=value('pending');assert(lastShot);report('START panoramic portrait')
  elseif phase==20 then
   if value('pending') then due=now+.25;return end
   local w,h=dofile(root..'ue4ss/Mods/VHOLUMEPhotoCamera/Scripts/image_file.lua').exr(lastShot.exrPath)
   assert(w and w*65==h*24,'Portrait panoramic output missing')
   report('PASS portrait panoramic PNG + EXR')
   local blocker=assert(io.open(work..'blocked-output','wb'));blocker:write('not a directory');blocker:close()
   value('photos').directory=function() return work..'blocked-output/' end
   value('captureConfig').method=2;value('settings').frame=4
   tap('Six');tap('RightMouseButton');if state().portrait then tap('P') end
  elseif phase==21 then tap('LeftMouseButton');lastShot=value('pending');assert(lastShot);report('START forced export failure')
  elseif phase==22 then
   if value('pending') then due=now+.25;return end
   assert(not lastShot.actor,'Failed capture leaked an actor')
   assert(not io.open(lastShot.path,'rb'),'Forced failure unexpectedly saved PNG')
   assert(not io.open(lastShot.exrPath,'rb'),'Forced failure unexpectedly saved EXR')
   local vp=object('/Script/UMG.Default__WidgetLayoutLibrary'):GetViewportSize(pc)
   if vp.X~=1920 or vp.Y~=1080 then due=now+.25;return end
   report('PASS forced save failure cleaned up and restored viewport')
   value('photos').directory=function() return work end
   value('captureConfig').method=2;value('captureConfig').resolution=4
  elseif phase==23 then tap('LeftMouseButton');lastShot=value('pending');assert(lastShot);report('START above-game temporary 2560x1440')
  elseif phase==24 then
   if value('pending') then due=now+.25;return end
   local w,h=dofile(root..'ue4ss/Mods/VHOLUMEPhotoCamera/Scripts/image_file.lua').exr(lastShot.exrPath)
   assert(w==2560 and h==1440,'Above-game temporary capture failed')
   report('PASS above-game temporary resolution capture restored viewport')
   value('captureConfig').method=1;value('captureConfig').resolution=5
  elseif phase==25 then tap('LeftMouseButton');lastShot=value('pending');assert(lastShot);report('START dedicated 3840x2160')
  elseif phase==26 then
   if value('pending') then due=now+.25;return end
   local w,h=dofile(root..'ue4ss/Mods/VHOLUMEPhotoCamera/Scripts/image_file.lua').exr(lastShot.exrPath)
   assert(w==3840 and h==2160,'4K capture failed')
   assert(dofile(root..'ue4ss/Mods/VHOLUMEPhotoCamera/Scripts/image_file.lua').png(lastShot.path)==3840)
   report('PASS paired full-resolution 4K capture')
   tap('Six');state().studio.focus('outputOpen',nil,1);tap('Enter');shot('output-settings-final')
  elseif phase==27 then tap('Five')
  elseif phase==28 then report('PASS native capture QA complete');command('quit');return
  end
  phase=phase+1;due=now+.7
 end)
 if not ok then
  finished=true;StaticFindObject=originalFind;report('ERROR '..tostring(err))
  if valid(pc) then command('quit') end
 end
end)
