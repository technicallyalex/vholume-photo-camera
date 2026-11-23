local root='C:/Projects/VHOLUME Viewmodel/Photo Camera/Capture Preview/'
local work=root..'.work/'
local out=assert(io.open(work..'native-ui-safety.log','wb'))
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
local tasks={
 function()
  local _,size,m=video();stored={X=size.X,Y=size.Y};mode=m
  value('binds').persist=function() return true end
  value('captureConfig').step=function(key,step)
   local cfg=value('captureConfig');local n=key=='format' and 3 or key=='resolution' and #cfg.edges or 2
   cfg[key]=(cfg[key]-1+step)%n+1;return true
  end
  tap('Six');assert(state().studio and not state().raised)
  shot('ui-main-1920');report('PASS Studio entry and default keybinds')
 end,
 function() tap('Enter');assert(state().outputPage);shot('ui-output-1920');report('PASS Photos Enter opens output settings') end,
 function()
  local cfg=value('captureConfig');local old=cfg.format
  tap('Right');assert(cfg.format~=old,'Output arrow did not change selected row');tap('Left');assert(cfg.format==old)
  tap('Down');assert(state().studio.focused().card=='resolution')
  tap('Six');assert(not state().outputPage and state().studio)
  state().studio.focus('exposureOpen',nil,5);tap('Enter');assert(state().exposurePage)
  local exp=value('exposure');local oldMode=exp.mode
  tap('Right');assert(exp.mode~=oldMode,'Exposure mode arrows did not work')
  state().studio.focus('auto');tap('Right');assert(exp.auto);tap('Left');assert(not exp.auto)
  shot('ui-exposure-1920');report('PASS consistent page back and arrow adjustment')
 end,
 function()
  tap('Six');state().studio.focus('keybinds');tap('Enter');assert(state().keyPage)
  shot('ui-keys-1920')
 end,
 function()
  local pad=value('pad');state().controller=true
  state().studio.keyStatus(nil,nil,nil,true);shot('ui-keys-controller')
  report('PASS controller keybind-page hints')
  tap('Six');assert(not state().keyPage)
  local notice=state().studio.notice
  state().studio.notice=function(message) if message=='PHOTO FOLDER OPENED' or message=='COULD NOT OPEN PHOTO FOLDER' then folderMessage=message end;notice(message) end
  state().studio.focus('openPhotos',nil,1);tap('Enter');report('START actual UI Open Folder')
  folderStarted=os.time()
 end,
 function()
  -- Helper acknowledgment is consumed by the real main tick; the result path is removed there.
  if not folderMessage then assert(os.time()-folderStarted<15,'No folder acknowledgment');return false end
  assert(folderMessage=='PHOTO FOLDER OPENED','Folder did not open');report('PASS actual Explorer folder acknowledged')
  state().studio.focus('outputOpen',nil,1);tap('Enter');assert(state().outputPage)
  local r=state().studioRect
  local _,size,m=video()
  command('r.SetRes 1280x720w')
  report('PASS Open Folder UI dispatched without blocking navigation')
 end,
 function()
  local size=object('/Script/UMG.Default__WidgetLayoutLibrary'):GetViewportSize(pc)
  if size.X~=1280 or size.Y~=720 then return false end
  shot('ui-output-1280');tap('Six')
 end,
 function() shot('ui-main-1280');state().studio.focus('exposureOpen',nil,5);tap('Enter') end,
 function() shot('ui-exposure-1280');tap('Six');state().studio.focus('keybinds');tap('Enter') end,
 function() shot('ui-keys-1280');tap('RightMouseButton');assert(state().raised and not state().studio);shot('ui-finder-1280') end,
 function() tap('Six');command('r.SetRes 960x1280w') end,
 function()
  local size=object('/Script/UMG.Default__WidgetLayoutLibrary'):GetViewportSize(pc)
  if size.X~=960 or size.Y~=1280 then return false end
  shot('ui-main-portrait');state().studio.focus('outputOpen',nil,1);tap('Enter')
 end,
 function() shot('ui-output-portrait');tap('RightMouseButton');command('r.SetRes 1920x1080w') end,
 function()
  local size=object('/Script/UMG.Default__WidgetLayoutLibrary'):GetViewportSize(pc)
  if size.X~=1920 or size.Y~=1080 then return false end
  value('photos').directory=function() return work end;value('photos').prepare=function() return true end
  local cfg=value('captureConfig');cfg.format=3;cfg.resolution=2;cfg.method=2
  value('settings').frame=4;value('exposure').mode=2;value('exposure').shutter=1
  begin();report('START cancellation during allocated exposure')
 end,
 function()
  if not lastShot.actor then return false end
  tap('RightMouseButton');assert(not value('pending'));assert(not lastShot.actor,'Cancel leaked capture actor')
 end,
 function() if not restored() then return false end;report('PASS RMB cancellation restored actual and stored resolution/mode');begin() end,
 function()
  if not lastShot.actor or not lastShot.accumulated or lastShot.accumulated<=0 then return false end
  tap('Five');assert(not value('pending'));report('START stow cancellation')
 end,
 function() if state() or not restored() then return false end;report('PASS stow cancellation restored resolution/mode');begin() end,
 function()
  if not lastShot.actor then return false end
  gp():SetGamePaused(pc,true);step({});assert(not value('pending'),'Pause did not cancel capture')
 end,
 function()
  if not restored() then return false end
  report('PASS paused-game cancellation restored resolution/mode');gp():SetGamePaused(pc,false);step({})
  local blocker=assert(io.open(work..'blocked-export','wb'));blocker:write('block');blocker:close()
  value('photos').directory=function() return work..'blocked-export/' end
  value('exposure').mode=1;begin();report('START blocked-destination export failure')
 end,
 function()
  if not restored() then return false end
  assert(not lastShot.actor,'Failed export leaked actor');assert(not io.open(lastShot.path,'rb'))
  report('PASS export failure restored resolution/mode and released targets')
  value('photos').directory=function() return work end
  allocationStart=value('motion').start
  value('motion').start=function() error('QA injected allocation failure') end
  begin();report('START allocation failure')
 end,
 function()
  if not restored() then return false end
  value('motion').start=allocationStart
  assert(not lastShot.actor);report('PASS allocation failure restored resolution/mode')
  begin();lastShot.width=lastShot.width+1;lastShot.requestedAt=-10
  report('START resolution settling timeout')
 end,
 function()
  if not restored() then return false end
  assert(not lastShot.actor);report('PASS resolution timeout restored resolution/mode')
  tap('Five')
 end,
 function() report('PASS UI and restoration safety QA complete');command('quit') end,
}
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
