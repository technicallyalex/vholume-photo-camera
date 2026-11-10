local exposure = {
    modes = {{"GAME","Game exposure"}, {"M","Manual"}, {"A","Aperture Priority"}, {"S","Shutter Priority"}},
    apertures = {1,1.1,1.2,1.4,1.6,1.8,2,2.2,2.5,2.8,3.2,3.5,4,4.5,5,5.6,6.3,7.1,8,9,10,11,13,14,16},
    speeds = {1,1.25,1.6,2,2.5,3.2,4,5,6,8,10,13,15,20,25,30,40,50,60,80,100,125,
        160,200,250,320,400,500,640,800,1000,1250,1600,2000,2500,3200,4000},
    isos = {100,125,160,200,250,320,400,500,640,800,1000,1250,1600,2000,2500,3200,4000,5000,6400},
    mode = 1, aperture = 7, shutter = 22, iso = 1,
    auto = false, minISO = 1, maxISO = 13, minShutter = 19,
    -- VHOLUME's baked lighting uses game-relative HDR values. Map those
    -- values to camera EV without changing the size of an exposure stop.
    sceneCalibrationEV = 10,
}

local apertures, speeds, isos = exposure.apertures, exposure.speeds, exposure.isos
local log2 = function(n) return math.log(n, 2) end
local function clamp(value, low, high) return math.max(low, math.min(high, value)) end

function exposure.ev(aperture, speed, iso)
    return log2(aperture * aperture * speed * 100 / iso)
end

-- Choose the closest step in stops, including at the configured limits.
local function nearest(values, value, low, high)
    for i = low, high - 1 do
        if value <= math.sqrt(values[i] * values[i + 1]) then return i end
    end
    return high
end

local function atLeast(values, value, low, high)
    for i = low, high - 1 do
        if value <= values[i] then return i end
    end
    return high
end

function exposure.solve(config, sceneEV)
    local a, s, i = config.aperture, config.shutter, config.iso
    local auto = config.mode ~= 1 and config.auto
    local shutterAuto, apertureAuto = config.mode == 3, config.mode == 4
    if auto then i = config.minISO end
    if sceneEV and config.mode ~= 1 then
        local gain = 2 ^ sceneEV
        if shutterAuto then
            local base = gain / (apertures[a] ^ 2)
            if auto and base * isos[i] / 100 < speeds[config.minShutter] then
                i = atLeast(isos, speeds[config.minShutter] * 100 / base, i, config.maxISO)
            end
            s = nearest(speeds, base * isos[i] / 100, 1, #speeds)
        elseif apertureAuto then
            local base = gain / (100 * speeds[s])
            if auto then
                if base * isos[i] < apertures[1] ^ 2 then
                    i = nearest(isos, apertures[1] ^ 2 / base, i, config.maxISO)
                elseif base * isos[i] > apertures[#apertures] ^ 2 then
                    i = nearest(isos, apertures[#apertures] ^ 2 / base, i, config.maxISO)
                end
            end
            a = nearest(apertures, math.sqrt(base * isos[i]), 1, #apertures)
        elseif auto then
            i = nearest(isos, 100 * apertures[a] ^ 2 * speeds[s] / gain, i, config.maxISO)
        end
    end
    local ev = exposure.ev(apertures[a], speeds[s], isos[i])
    local errorEV = config.mode ~= 1 and sceneEV and sceneEV - ev or nil
    return {
        aperture=apertures[a], speed=speeds[s], iso=isos[i], ev=ev, errorEV=errorEV,
        shutterAuto=shutterAuto, apertureAuto=apertureAuto, isoAuto=auto,
        limited=errorEV and math.abs(errorEV) >= .3 and auto
            and ((errorEV < 0 and i == config.maxISO and "ISO AT MAX")
                or (errorEV > 0 and i == config.minISO and "ISO AT MIN")) or nil,
    }
end

function exposure.speedText(speed)
    if speed == 1 then return "1 s" end
    return string.format("1/%g s", speed)
end

function exposure.grain(iso)
    local stops = clamp(log2(iso / 100), 0, 6)
    return .07 + .045 * stops + .012 * stops ^ 2, .78 + .14 * stops
end

function exposure.step(which, direction)
    local limits = {
        aperture={1,#apertures}, shutter={1,#speeds}, iso={1,#isos},
        minISO={1,exposure.maxISO}, maxISO={exposure.minISO,#isos}, minShutter={1,#speeds},
    }
    if which == "mode" then
        exposure.mode = (exposure.mode - 1 + direction) % #exposure.modes + 1
        return true
    end
    local bound = limits[which]
    local old = exposure[which]
    exposure[which] = clamp(old + direction, bound[1], bound[2])
    return old ~= exposure[which]
end

function exposure.loadOptions(body)
    local function option(key, fallback, max)
        local v = tonumber(body:match("[\r\n]" .. key .. "=(%d+)[\r\n]"))
        return v and clamp(v, 1, max) or fallback
    end
    local low = option("minISO", exposure.minISO, #isos)
    local high = option("maxISO", exposure.maxISO, #isos)
    if low <= high then exposure.minISO, exposure.maxISO = low, high end
    exposure.minShutter = option("minShutter", exposure.minShutter, #speeds)
    exposure.auto = body:match("[\r\n]autoISO=1[\r\n]") ~= nil
end

function exposure.optionLines()
    return {"autoISO=" .. (exposure.auto and "1" or "0"), "minISO=" .. exposure.minISO,
        "maxISO=" .. exposure.maxISO, "minShutter=" .. exposure.minShutter}
end

local stockFields = {"AutoExposureMethod", "AutoExposureApplyPhysicalCameraExposure", "AutoExposureBias",
    "AutoExposureMinBrightness", "AutoExposureMaxBrightness", "AutoExposureSpeedUp", "AutoExposureSpeedDown",
    "AutoExposureLowPercent", "AutoExposureHighPercent", "AutoExposureBiasCurve", "AutoExposureMeterMask",
    "CameraISO", "CameraShutterSpeed", "MotionBlurAmount", "MotionBlurMax", "MotionBlurTargetFPS"}

local simulatedFields = {
    AutoExposureMethod=true, AutoExposureApplyPhysicalCameraExposure=true, AutoExposureBias=true,
    MotionBlurAmount=true, MotionBlurMax=true, MotionBlurTargetFPS=true,
}

function exposure.apply(pp, values, stock)
    local simulated = exposure.mode ~= 1
    for _,field in ipairs(stockFields) do
        local flag = "bOverride_" .. field
        -- Preserve explicitly authored player-camera overrides in Game mode.
        -- A fresh camera otherwise uses the same level post-process volumes.
        if not simulated then
            local override = stock and stock[flag] == true or false
            pp[flag] = override
            if override then pp[field] = stock[field] end
        else
            pp[flag] = simulatedFields[field] == true
        end
    end
    if simulated then
        -- Compute EV once for metering and rendering. The explicit bias keeps
        -- exposure independent of the camera's DOF toggle and lens metadata.
        pp.AutoExposureMethod = 2 -- AEM_Manual
        pp.AutoExposureApplyPhysicalCameraExposure = false
        pp.AutoExposureBias = exposure.sceneCalibrationEV - values.ev
        -- Unreal's velocity blur approximates the selected integration time.
        local fps = math.min(60, math.floor(values.speed))
        pp.MotionBlurTargetFPS = fps
        pp.MotionBlurAmount = fps / values.speed
        pp.MotionBlurMax = 5
    end
end

return exposure
