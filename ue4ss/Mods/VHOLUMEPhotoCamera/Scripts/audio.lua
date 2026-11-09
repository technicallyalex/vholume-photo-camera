return function(ue, assetPath, log)
    local audio = {}
    local media = "/Script/MediaAssets.MediaPlayer:"
    local synth = "/Script/AudioMixer.SynthComponent:"
    local componentPath = "/Script/MediaAssets.MediaSoundComponent:"
    local relativeTransform = {
        Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
        Translation = { X = 0, Y = 0, Z = 0 },
        Scale3D = { X = 1, Y = 1, Z = 1 },
    }

    local function makeChannel(active, name)
        local channel = {}
        active.soundChannels[name] = channel
        channel.component = ue.call("/Script/Engine.Actor:AddComponentByClass", active.pc,
            ue.object("/Script/MediaAssets.MediaSoundComponent"), true, relativeTransform, true)
        assert(ue.valid(channel.component), "Camera audio component unavailable")
        channel.player = StaticConstructObject(ue.object("/Script/MediaAssets.MediaPlayer"), channel.component)
        assert(ue.valid(channel.player), "Camera audio player unavailable")
        channel.player.PlayOnOpen = true
        channel.player.NativeAudioOut = false
        channel.component.bIsUISound = true
        local soundClass = ue.load("/Game/Audio/SoundClasses/SC_UI.SC_UI")
        if ue.valid(soundClass) then channel.component.SoundClass = soundClass end
        ue.call(componentPath .. "SetMediaPlayer", channel.component, channel.player)
        -- Retain the player through the component's reflected media asset field.
        channel.component.MediaPlayer = channel.player
        ue.call("/Script/Engine.Actor:FinishAddComponent", active.pc, channel.component, true, relativeTransform)
        ue.call(synth .. "SetVolumeMultiplier", channel.component, name == "dial" and .32 or .62)
        ue.call("/Script/Engine.ActorComponent:Activate", channel.component, true)
        return channel
    end

    function audio.play(active, cue, now)
        if active.soundFailed then return end
        local name = cue == "focus" and "dial" or "handling"
        if name == "dial" and now < (active.nextDialSound or 0) then return end
        local ok, err = pcall(function()
            active.soundChannels = active.soundChannels or {}
            local channel = active.soundChannels[name] or makeChannel(active, name)
            -- VHOLUME's WMF player opens WAVs but does not play these PCM clips.
            assert(ue.call(media .. "OpenFile", channel.player, assetPath .. "Sounds/" .. cue .. ".mp4"),
                "Could not open camera cue " .. cue)
            if name == "dial" then active.nextDialSound = now + .115 end
        end)
        if not ok then
            active.soundFailed = true
            log("Camera sound: " .. tostring(err))
        end
    end

    function audio.release(active)
        for _, channel in pairs(active.soundChannels or {}) do
            if ue.valid(channel.player) then ue.call(media .. "Close", channel.player) end
            if ue.valid(channel.component) then
                ue.call("/Script/Engine.ActorComponent:K2_DestroyComponent", channel.component, active.pc)
            end
        end
        active.soundChannels = nil
    end

    return audio
end
