return function(ue,log)
    local resolution={}
    local restoring={}
    local settingsPath="/Script/Engine.GameUserSettings:"
    local function command(shot,width,height,mode)
        local suffix=mode==0 and "f" or mode==1 and "wf" or "w"
        ue.object("/Script/Engine.Default__KismetSystemLibrary"):ExecuteConsoleCommand(shot.owner.pc,
            string.format("r.SetRes %dx%d%s",width,height,suffix),shot.owner.pc)
    end
    local function settings()
        return ue.call(settingsPath.."GetGameUserSettings",ue.object("/Script/Engine.Default__GameUserSettings"))
    end
    function resolution.begin(shot,config)
        if config.method~=2 then return end
        local user=settings()
        local size=ue.call(settingsPath.."GetScreenResolution",user)
        shot.restoreResolution={user=user,width=size.X,height=size.Y,
            fullscreen=ue.call(settingsPath.."GetFullscreenMode",user),
            viewportWidth=shot.rect.width,viewportHeight=shot.rect.height}
        local old=shot.restoreResolution
        old.viewportMode=old.fullscreen
        -- Launch overrides can make the running mode differ from the saved preference.
        -- Probe dirty-state without applying or saving any of these temporary values.
        if ue.call(settingsPath.."IsFullscreenModeDirty",user) then
            for mode=0,2 do
                ue.call(settingsPath.."SetFullscreenMode",user,mode)
                if not ue.call(settingsPath.."IsFullscreenModeDirty",user) then old.viewportMode=mode;break end
            end
            ue.call(settingsPath.."SetFullscreenMode",user,old.fullscreen)
        end
        -- Apply only to the running session; never call SaveSettings or ConfirmVideoMode.
        ue.call(settingsPath.."SetScreenResolution",user,{X=shot.width,Y=shot.height})
        ue.call(settingsPath.."ApplyResolutionSettings",user,false)
        -- Some game settings overrides accept the value without resizing the viewport.
        -- Use a temporary window to support sizes that differ from the desktop mode.
        command(shot,shot.width,shot.height,2)
        shot.waitResolution=true
    end
    function resolution.restore(shot)
        local old=shot.restoreResolution
        if not old then return true end
        if old.requested then return true end
        local ok,err=pcall(function()
            if not ue.valid(old.user) then error("Video settings unavailable") end
            ue.call(settingsPath.."SetScreenResolution",old.user,{X=old.width,Y=old.height})
            ue.call(settingsPath.."SetFullscreenMode",old.user,old.fullscreen)
            ue.call(settingsPath.."ApplyResolutionSettings",old.user,false)
            command(shot,old.viewportWidth,old.viewportHeight,old.viewportMode)
        end)
        if ok then
            old.requested=os.time()
            restoring[shot]=true
        else log("Resolution restore failed: "..tostring(err)) end
        return ok
    end
    function resolution.restored(shot)
        local old=shot.restoreResolution
        if not old then return true end
        if not old.requested then return false end
        if not ue.valid(shot.owner.pc) then return false end
        local size=ue.object("/Script/UMG.Default__WidgetLayoutLibrary"):GetViewportSize(shot.owner.pc)
        if size.X==old.viewportWidth and size.Y==old.viewportHeight then
            shot.restoreResolution=nil;restoring[shot]=nil
            return true
        end
        return false
    end
    function resolution.poll()
        for shot in pairs(restoring) do
            local ok,ready=pcall(resolution.restored,shot)
            if not ok or not ready then
                local old=shot.restoreResolution
                local elapsed=os.time()-old.requested
                if elapsed>=10 then
                    log("Could not restore the viewport; reopen the game's video settings.")
                    shot.restoreFailed=true;restoring[shot]=nil
                elseif elapsed>=2 and old.retryAt~=os.time() then
                    old.retryAt=os.time()
                    pcall(command,shot,old.viewportWidth,old.viewportHeight,old.viewportMode)
                end
            end
        end
    end
    return resolution
end
