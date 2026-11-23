local factory=dofile(scripts..'capture_settings.lua')
local config=factory();config.load(fixture)
assert(config.format==1 and config.resolution==1 and config.method==1)
local ratios={{3,2},{4,3},{1,1},{16,9},{5,4},{21,9},{65,24}}
local count=0
for i=1,#config.edges do
    config.resolution=i
    for _,ratio in ipairs(ratios) do
        for portrait=0,1 do
            local x,y=ratio[1],ratio[2]
            if portrait==1 then x,y=y,x end
            local rect={width=2560,height=1440,columns=x,rows=y}
            local w,h=config.dimensions(rect)
            assert(w*y==h*x,'Aspect ratio drift')
            assert(math.max(w,h)<=7680 and w>0 and h>0)
            if i==1 then assert(math.max(w,h)>2500,'Native render is still HUD sized') end
            count=count+1
        end
    end
end
config.resolution=4
assert(config.step('format',1));assert(config.format==2)
assert(config.step('method',1));assert(config.method==2)
local reloaded=factory();reloaded.load(fixture)
assert(reloaded.format==2 and reloaded.resolution==4 and reloaded.method==2)
assert(not config.step('bogus',1))
-- A failed settings commit must not change the live selection.
local rename=os.rename
os.rename=function() return nil,'injected write failure' end
local old=config.format
assert(not config.step('format',1) and config.format==old)
os.rename=rename

local user={IsValid=function() return true end}
local events={}
local ue={valid=function(v) return v==user end}
local viewport={X=1920,Y=1080}
ue.object=function() return {
    ExecuteConsoleCommand=function(_,_,command) events[#events+1]=command end,
    GetViewportSize=function() return viewport end,
} end
ue.call=function(path,_,arg)
    local fn=path:match(':([^:]+)$')
    if fn=='GetGameUserSettings' then return user end
    if fn=='GetScreenResolution' then return {X=2560,Y=1440} end
    if fn=='GetFullscreenMode' then return 1 end
    events[#events+1]={fn,arg}
end
local resolution=dofile(scripts..'capture_resolution.lua')(ue,function() end)
local shot={owner={pc=user},width=1280,height=720,rect={width=1920,height=1080}}
resolution.begin(shot,{method=1});assert(#events==0 and not shot.restoreResolution)
resolution.begin(shot,{method=2})
assert(shot.restoreResolution.width==2560 and shot.waitResolution)
assert(events[#events]=='r.SetRes 1280x720w')
assert(resolution.restore(shot));assert(shot.restoreResolution)
assert(events[#events]=='r.SetRes 1920x1080wf')
viewport={X=1280,Y=720}
assert(not resolution.restored(shot),'Restore completed before the actual viewport resized')
viewport={X=1920,Y=1080}
resolution.poll();assert(not shot.restoreResolution)
local n=#events;resolution.restore(shot);assert(#events==n,'Repeated restore changed video state')
for _,event in ipairs(events) do
    if type(event)=='table' then assert(event[1]~='SaveSettings' and event[1]~='ConfirmVideoMode') end
end
local normalCall=ue.call
local clock=os.time
local now=2000
os.time=function() return now end
local failed={owner={pc=user},width=1280,height=720,rect={width=1920,height=1080}}
resolution.begin(failed,{method=2})
ue.call=function(path,...)
    if path:match(':SetScreenResolution$') then error('injected video API failure') end
    return normalCall(path,...)
end
assert(not resolution.restore(failed) and resolution.busy(),'Failed restore was discarded')
ue.call=normalCall
viewport={X=1280,Y=720};now=2003
resolution.poll(user)
assert(failed.restoreResolution.valuesRestored and resolution.busy(),'Restore was not retried')
viewport={X=1920,Y=1080}
ue.call=function(path,...)
    if path:match(':IsFullscreenModeDirty$') then return true end
    return normalCall(path,...)
end
assert(not resolution.restored(failed),'Matched size hid an incorrect display mode')
ue.call=normalCall
resolution.poll(user)
assert(not resolution.busy() and not failed.restoreResolution)
os.time=clock
print('PASS: '..count..' capture size/aspect cases; settings persistence; write failure; temporary resolution restoration and idempotence.')
print('PASS: failed video API restores remain queued; retries recover; original running mode is verified.')
