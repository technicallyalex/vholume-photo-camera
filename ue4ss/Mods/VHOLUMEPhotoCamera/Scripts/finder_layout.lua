return function(width, height, columns, rows)
    local unit = math.min(width / (height > width and 540 or 960), height / 540)
    local function fit(rail)
        -- The constrained camera and HighResShot use a centered, even-sized crop.
        return math.floor(math.min((width - 12 * unit) / columns,
            (height - 2 * rail * unit) / rows) / 2) * 2
    end
    local frames = fit(32)
    if math.floor((width - frames * columns) / 2) < 120 * unit then frames = fit(47) end
    assert(frames * math.min(columns, rows) >= 64, "Viewport is too small for the photo camera")
    local w, h = frames * columns, frames * rows
    local x, y = math.floor((width - w) / 2), math.floor((height - h) / 2)
    return {
        x = x, y = y, w = w, h = h, unit = unit,
        sideControls = x >= 120 * unit, sideMeter = x >= 42 * unit,
    }
end
