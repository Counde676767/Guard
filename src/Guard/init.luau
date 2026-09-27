local Configs = require(script.Configs)
local Checks = require(script.Checks)

local remote

local initialised = false

local isServer = game:GetService("RunService"):IsServer()

local handlers = {}

local Guard = {}

function Guard.Init(old_configs)

    if initialised then warn("Guard has already been initialised!"); return end

    if isServer then
        remote = Instance.new("RemoteEvent")
        remote.Name = "GuardRemote"
        remote.Parent = game:GetService("ReplicatedStorage")

        remote.OnServerEvent:Connect(function(player, event_name, ...)
	    if typeof(event_name) ~= "string" then return end
	    local handler = handlers[event_name]
	    if handler then
		    handler(player, ...)
	    end
    end) 
    else
        remote = game:GetService("ReplicatedStorage"):WaitForChild("GuardRemote")
    end



   

    local cfigs
    if old_configs then
        cfigs = Configs.Init(old_configs)
    else
        cfigs = Configs.Init()
    end
    local checks = Checks.Init()
    if cfigs and checks then
        print("Guard Successfully initialised!")
        initialised = true
    else
        error("Guard failed to initialise!")
    end
end


function Guard.Fire(event_name : string, ... : any)
    if not initialised then error("Guard has not been initialised! Call Guard.Init() first!") end
    if isServer then error("Failed To Call to Client from Server with fire(). Use fire_client()") end
    remote:FireServer(event_name, ...)
end

function Guard.On(event_name : string, action : ( ... any) -> ())
    if not initialised then error("Guard has not been initialised! Call Guard.Init() first!") end
    if not isServer then error("Failed To Call to Server from Client with on(). Use on_client()") end
    handlers[event_name] = action

end

return Guard