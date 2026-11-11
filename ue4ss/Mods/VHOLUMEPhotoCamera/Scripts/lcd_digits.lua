return function(ue, draw, dpi, x, y, width, height)
    local group = draw.add("CanvasPanel",x,y,width,height)
    ue.call("/Script/UMG.Widget:SetClipping",group,1)
    local slots, previous = {}, nil
    local characters = "0123456789./fs- "
    local advances = {["."]=.36, ["/"]=.67, f=1, s=.72}
    return {set=function(value)
        if previous == value then return end
        previous = value
        local units = 0
        for i=1,#value do units = units+(advances[value:sub(i,i)] or 1) end
        local cellW = math.min(height*36/56,width/math.max(1,units))
        local cellH = cellW*56/36
        local left = (width-units*cellW)/2
        for i=1,math.max(#value,#slots) do
            local character = value:sub(i,i)
            local slot = slots[i]
            if not slot then
                local mask = draw.add("CanvasPanel",0,0,cellW,cellH,group)
                ue.call("/Script/UMG.Widget:SetClipping",mask,1)
                slot = {mask=mask,image=draw.picture("Controls/finder-digits",0,0,16*cellW,cellH,1,mask)}
                slots[i] = slot
            end
            ue.call("/Script/UMG.Widget:SetVisibility",slot.mask,i<=#value and 3 or 2)
            if i<=#value then
                local index = (characters:find(character,1,true) or 15)-1
                local advance = cellW*(advances[character] or 1)
                ue.call("/Script/UMG.CanvasPanelSlot:SetPosition",slot.mask.Slot,{X=left/dpi,Y=(height-cellH)/(2*dpi)})
                ue.call("/Script/UMG.CanvasPanelSlot:SetSize",slot.mask.Slot,{X=advance/dpi,Y=cellH/dpi})
                ue.call("/Script/UMG.CanvasPanelSlot:SetSize",slot.image.Slot,{X=16*cellW/dpi,Y=cellH/dpi})
                ue.call("/Script/UMG.Widget:SetRenderTranslation",slot.image,{X=-index*cellW/dpi,Y=0})
                left = left+advance
            end
        end
    end}
end
