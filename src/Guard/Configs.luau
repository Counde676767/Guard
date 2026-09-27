local Configs = {
    Events = {}, -- ADD EVENTS HERE
    General = {
        Base_EventRate = 1000,
        Base_EventMaxPacketSize = 1000,
        Base_MaxAllowedArgs = 10,
        Base_MaxAllowedArgSize = 1000,
        Base_AllowedArgTypes = { string = true, number = true, boolean = true, Instance = true },
    },
}

function Configs.Init(old_configs)
    if old_configs then
        for key, value in pairs(old_configs) do
            if Configs[key] then
                Configs[key] = value or Configs[key]
            end

        end
    end
    print("Configs Successfully initialised!")
    return true
end

return Configs