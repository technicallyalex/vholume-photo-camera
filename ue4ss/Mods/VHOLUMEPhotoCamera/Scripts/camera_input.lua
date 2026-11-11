return function(ue, binds)
    local layer = {}
    local context, subsystem, controller
    local interface = "/Script/EnhancedInput.EnhancedInputSubsystemInterface:"
    local options = {bIgnoreAllPressedKeysUntilRelease=false,bForceImmediately=true}
    local releaseOptions = {bIgnoreAllPressedKeysUntilRelease=true,bForceImmediately=true}
    local movement = {"IA_MoveForward","IA_MoveBackward","IA_MoveLeft","IA_MoveRight","IA_Turn","IA_LookUp"}

    function layer.disable()
        if ue.valid(context) and ue.valid(subsystem) then
            ue.call(interface.."RemoveMappingContext",subsystem,context,releaseOptions)
        end
        context,subsystem,controller = nil,nil,nil
    end

    function layer.enable(pc)
        if ue.valid(context) and ue.valid(controller) and controller:GetAddress()==pc:GetAddress() then return end
        layer.disable()
        subsystem = ue.call("/Script/Engine.SubsystemBlueprintLibrary:GetLocalPlayerSubSystemFromPlayerController",
            ue.object("/Script/Engine.Default__SubsystemBlueprintLibrary"),pc,
            ue.object("/Script/EnhancedInput.EnhancedInputLocalPlayerSubsystem"))
        assert(ue.valid(subsystem),"Camera input subsystem is unavailable")
        local protected = {W=true,A=true,S=true,D=true,SpaceBar=true,MouseX=true,MouseY=true,Mouse2D=true,
            Gamepad_LeftX=true,Gamepad_LeftY=true,Gamepad_RightX=true,Gamepad_RightY=true}
        for _, name in ipairs(movement) do
            local action = ue.load("/Game/Inputs/Actions/"..name.."."..name)
            if ue.valid(action) then
                local keys = ue.call(interface.."QueryKeysMappedToAction",subsystem,action)
                for i=1,#keys do protected[keys[i]:get().KeyName:ToString()] = true end
            end
        end
        context = StaticConstructObject(ue.object("/Script/EnhancedInput.InputMappingContext"),pc)
        assert(ue.valid(context),"Cannot create camera input context")
        local action = StaticConstructObject(ue.object("/Script/EnhancedInput.InputAction"),context)
        assert(ue.valid(action),"Cannot create camera input action")
        action.ValueType = 0
        action.bConsumeInput = true
        action.bConsumesActionAndAxisMappings = true
        action.bTriggerWhenPaused = false
        for _, key in ipairs(binds.cameraKeys()) do
            if not protected[key] then
                ue.call("/Script/EnhancedInput.InputMappingContext:MapKey",context,action,binds.raw(key))
            end
        end
        controller = pc
        ue.call(interface.."AddMappingContext",subsystem,context,1000000,options)
    end
    return layer
end
