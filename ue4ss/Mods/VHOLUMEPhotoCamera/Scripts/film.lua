local film = {}
film.stocks = {
    { "Neutral", "neutral", "Game color" },
    { "Warm Color 200", "warm-color-200", "Warm sunlight, vivid color", sat=1.13, contrast=1.04,
        gamma={1.07,1.02,.96}, gain={1.075,1.025,.94}, grain=.26, size=.95, shoulder=.84 },
    { "Soft Color 400", "soft-color-400", "Soft color and highlights", sat=.87, contrast=.94,
        gamma={1.035,1.02,1.015}, gain={1.04,1.015,.99}, grain=.21, size=.88, shoulder=.91 },
    { "Crisp B&W 400", "crisp-bw-400", "Crisp black and white", sat=0, contrast=1.16,
        gamma={1.025,1.025,1.025}, grain=.29, size=.94, shoulder=.82 },
    { "Fine B&W 100", "fine-bw-100", "Fine grain, smooth shadows", sat=0, contrast=1.055,
        gamma={.94,.94,.94}, gain={1.04,1.04,1.04}, grain=.13, size=.72, shoulder=.89 },
    { "Instant Color 600", "instant-color-600", "Cool shadows and soft contrast", sat=.76, contrast=.89,
        gamma={1.01,1.04,1.085}, gain={1.065,1.025,.97}, grain=.35, size=1.14, shoulder=.93 },
    { "Vivid Slide 50", "vivid-slide-50", "Rich greens and reds", sat=1.30, contrast=1.12,
        gamma={.99,1.035,1.025}, gain={1.045,1.065,1.025}, grain=.10, size=.70, shoulder=.83 },
    { "Vivid Color 100", "vivid-color-100", "Clean color, vivid reds", sat=1.23, contrast=1.07,
        gamma={1.045,1.015,.99}, gain={1.08,1.02,1.02}, grain=.15, size=.76, shoulder=.88 },
    { "Grainy B&W 400", "grainy-bw-400", "Textured black and white", sat=0, contrast=1.10,
        gamma={1.06,1.06,1.06}, grain=.43, size=1.22, shoulder=.86 },
    { "Tungsten 800", "tungsten-800", "Cool tungsten palette", sat=.91, contrast=1.02,
        gamma={.98,1.03,1.105}, gain={.98,1.045,1.13}, grain=.48, size=1.25, shoulder=.92 },
    { "Fast Color 1600", "fast-color-1600", "Fast color, coarse grain", sat=1.08, contrast=1.11,
        gamma={1.055,1.075,1.005}, gain={1.025,1.06,1.01}, grain=.68, size=1.52, shoulder=.85 },
}
film.frames = {
    { "35 mm", 3, 2 }, { "Classic", 4, 3 }, { "Square", 1, 1 },
    { "Wide", 16, 9 }, { "Print", 5, 4 },
}

local function vector(rgb, default)
    return { X=rgb and rgb[1] or default, Y=rgb and rgb[2] or default,
        Z=rgb and rgb[3] or default, W=1 }
end

function film.apply(component, index, grainTexture)
    local pp = component.PostProcessSettings
    local s = film.stocks[index]
    local enabled = index ~= 1
    pp.bOverride_ColorSaturation = enabled
    pp.bOverride_ColorContrast = enabled
    pp.bOverride_ColorGamma = enabled
    pp.bOverride_ColorGain = enabled
    pp.bOverride_FilmGrainIntensity = enabled
    pp.bOverride_FilmGrainIntensityShadows = enabled
    pp.bOverride_FilmGrainIntensityMidtones = enabled
    pp.bOverride_FilmGrainIntensityHighlights = enabled
    pp.bOverride_FilmGrainTexelSize = enabled
    pp.bOverride_FilmGrainTexture = enabled and grainTexture ~= nil
    pp.bOverride_FilmShoulder = enabled
    if enabled then
        pp.ColorSaturation = vector(nil, s.sat)
        pp.ColorContrast = vector(nil, s.contrast)
        pp.ColorGamma = vector(s.gamma, 1)
        pp.ColorGain = vector(s.gain, 1)
        pp.FilmGrainIntensity = s.grain
        pp.FilmGrainIntensityShadows = 1.1
        pp.FilmGrainIntensityMidtones = 1.0
        pp.FilmGrainIntensityHighlights = .60
        pp.FilmGrainTexelSize = s.size
        if grainTexture then pp.FilmGrainTexture = grainTexture end
        pp.FilmShoulder = s.shoulder
    end
end

function film.ratio(index, portrait)
    local frame = film.frames[index]
    if portrait then return frame[3], frame[2] end
    return frame[2], frame[3]
end

return film
