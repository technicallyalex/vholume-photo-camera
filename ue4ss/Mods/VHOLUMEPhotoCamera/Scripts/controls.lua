return function(ue, ui, draw, unit)
    local chips = {}
    local ink = { R = .84, G = .86, B = .79, A = 1 }
    local quiet = { R = .68, G = .72, B = .64, A = 1 }
    local cap = { R = .10, G = .14, B = .12, A = 1 }
    local capEdge = { R = .23, G = .30, B = .25, A = 1 }
    local bevel = { R = .16, G = .20, B = .17, A = .9 }

    local function refresh(chip, pulse)
        local level = math.max(chip.active and .55 or 0, pulse)
        if chip.label then
            local highlighted = level > 0
            if chip.highlighted == highlighted then return end
            chip.highlighted = highlighted
            chip.label:SetColorAndOpacity({ SpecifiedColor = highlighted and chip.highlight or chip.color, ColorUseRule = 0 })
            return
        end
        chip.back:SetBrushColor({
            R = .027 + .20 * level, G = .039 + .12 * level,
            B = .033 + .043 * level, A = .96,
        })
    end

    function ui.trackControl(id, label, color, highlight)
        chips[id] = { label = label, color = color, highlight = highlight, highlighted = false }
    end

    local glyphWidths = { [" "]=.31, I=.34, W=.96, M=.91, i=.30, l=.33, t=.40, f=.39, ["/"]=.49 }
    local function textWidth(value, fontSize)
        local ems = 0
        for _, code in utf8.codes(value) do
            local char = utf8.char(code)
            ems = ems + (glyphWidths[char] or (char:match("%l") and .60 or .72))
        end
        return ems * fontSize * 1.34
    end
    ui.textWidth = textWidth

    local function badgeWidth(token)
        if token:sub(1, 6) == "mouse-" then return 20 end
        return math.max(17, 8 + textWidth(token,9))
    end

    local function inputBadge(parent, token, x, size)
        if token:sub(1, 6) == "mouse-" then
            draw.picture("Controls/" .. token, x - size, size, 22 * size, 17 * size, 1, parent)
            return 20 * size
        end
        local width = badgeWidth(token) * size
        draw.block(x, 2 * size, width, 15 * size, capEdge, parent)
        draw.block(x + size, 3 * size, width - 2 * size, 13 * size, cap, parent)
        local label = draw.text(x, 2.6 * size, width, 14 * size, 9 * size / unit, ink, token, parent)
        ue.call("/Script/UMG.TextLayoutWidget:SetJustification", label, 1)
        return width
    end

    function ui.addControlRow(anchor, y, available, row, parent, leftAligned, scale)
        local gap = 6
        local total = (#row - 1) * gap
        local widths = {}
        for i, item in ipairs(row) do
            local width = 17 + textWidth(item[3],9.5)
            for index = 4, #item do width = width + badgeWidth(item[index]) + 3 end
            widths[i] = math.max(item[2],width)
            total = total + widths[i]
        end
        local size = math.min(unit * (scale or 1), available / total)
        local left = leftAligned and anchor or anchor - total * size / 2
        for i, item in ipairs(row) do
            local id, width, title = item[1], widths[i] * size, item[3]
            local group = draw.add("CanvasPanel", left, y, width, 19 * size, parent)
            local chip = { group = group, back = draw.block(0, 0, width, 19 * size, cap, group) }
            chips[id] = chip
            refresh(chip, 0)
            draw.block(0,0,width,.8*size,bevel,group)
            local x = 5 * size
            for index = 4, #item do x = x + inputBadge(group, item[index], x, size) + 3 * size end
            x = x + 4 * size
            draw.text(x, 2.4 * size, width - x - 6 * size, 15 * size, 9.5 * size / unit, quiet, title, group)
            left = left + width + gap * size
        end
    end

    function ui.setControlVisible(id, visible)
        ue.call("/Script/UMG.Widget:SetVisibility", chips[id].group, visible and 3 or 2)
    end

    function ui.setControlActive(id, active)
        local chip = chips[id]
        if chip and chip.active ~= active then
            chip.active = active
            refresh(chip, 0)
        end
    end

    function ui.pulseControl(id, now)
        local chip = chips[id]
        if chip then
            chip.pulseAt = now
            refresh(chip, 1)
        end
    end

    function ui.tickControls(now)
        for _, chip in pairs(chips) do
            if chip.pulseAt then
                local elapsed = math.max(0, now - chip.pulseAt)
                refresh(chip, math.max(0, 1 - elapsed / .28))
                if elapsed >= .28 then chip.pulseAt = nil end
            end
        end
    end
end
