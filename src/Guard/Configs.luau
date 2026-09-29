local Configs = {}

Configs.Defaults = {
	MaxCallsPerSecond = 20, 
	MaxArgs = 8,
	MaxStringLength = 200,
	AllowedTypes = { string = true, number = true, boolean = true, Instance = true },
	RejectBadNumbers = true, 
}


Configs.Settings = {
	Debug = true,             
	LogViolations = true,    
}

-- ADD EVENTS HERE
Configs.Events = {
	Test = {
		Args = { "string", "number" }, 
		MaxCallsPerSecond = 5,
	},
}

local function populateConfig(config: { [any]: any }, default: { [any]: any })
    for key, value in pairs(default) do
        if type(value) == "table" then
            config[key] = config[key] or {}
            populateConfig(config[key], value)
        else
            if config[key] == nil then
	            config[key] = value
            end
        end
    end

    return config
end

function Configs.Init(old_configs)
    if old_configs then
        for key, value in pairs(old_configs) do
            if Configs[key] then
                Configs[key] = value or Configs[key]
            end

        end
    end

    for event_name, event_config in pairs(Configs.Events) do
        Configs.Events[event_name] = populateConfig(event_config, Configs.Defaults)
    end

    print("Configs Successfully initialised!")
    return true
end



function Configs.LoadConfig(name: string)
    if not Configs.Events[name] then
        error("Config " .. name .. " does not exist!")
    end
    
    return Configs.Events[name]
end

return Configs