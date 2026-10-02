local RunService = game:GetService("RunService")

local Configs = require(script.Configs)
local Checks = require(script.Checks)

local remote

local initialised = false

local isServer = game:GetService("RunService"):IsServer()

local handlers = {}

local rates = {}


local Guard = {}

function Guard.Init(old_configs)
	if initialised then
		warn("Guard has already been initialised!")
		return
	end

	local cfigs = Configs.Init(old_configs)
	local checks = Checks.Init()
	if not (cfigs and checks) then
		error("Guard failed to initialise!")
	end

	if isServer then
		remote = Instance.new("RemoteEvent")
		remote.Name = "GuardRemote"
		remote.Parent = game:GetService("ReplicatedStorage")

		local settings = Configs.Settings

		local isCracked = settings.Cracked

		if isCracked then
			if RunService:IsStudio() then
				warn("Cracked mode is enabled! All checks will be bypassed. This is for testing purposes only!")
			else
				isCracked = false
				warn("Cracked mode disabled in live environment!")
			end
		end

		remote.OnServerEvent:Connect(function(player, event_name, ...)
			local start = os.clock()

			if typeof(event_name) ~= "string" then
				return
			end

			local handler = handlers[event_name]
			if not handler then
				return
			end

			local cfig = Configs.Events[event_name]
			

			local playerRates = rates[player.UserId]
			if not playerRates then
				playerRates = {}
				rates[player.UserId] = playerRates
			end

			local bucket = playerRates[event_name]
			if not bucket then
				bucket = { tokens = cfig.MaxCallsPerSecond, last = start }
				playerRates[event_name] = bucket
			end

			local max = cfig.MaxCallsPerSecond
			bucket.tokens = math.min(max, bucket.tokens + (start - bucket.last) * max)
			bucket.last = start

			if bucket.tokens < 1 then
				return
			end
			bucket.tokens -= 1

			local argsTable = { ... }

			if cfig.Args then
				if isCracked then
					if settings.Debug then
						warn("Guard: Cracked mode is enabled! Skipping argument checks for event '" .. event_name .. "'. This is for testing purposes only!")
						
					else
						if #argsTable ~= #cfig.Args then
							warn("Guard: Argument count mismatch for event '" .. event_name .. "'. Expected " .. #cfig.Args .. ", got " .. #argsTable .. ". Dropping event call.")
							return
						end
						for i, argType in ipairs(cfig.Args) do
							local arg = argsTable[i]
							local currentArgType = typeof(arg)
							if currentArgType ~= argType then
								warn("Guard: Argument type mismatch for event '" .. event_name .. "'. Expected " .. argType .. ", got " .. currentArgType .. " Dropping event call.")
								return
							end


							if argType =="number" and cfig.MaxNumberValue and arg > cfig.MaxNumberValue then
								warn("Guard: Argument value exceeds maximum for event '" .. event_name .. "'. Expected <= " .. cfig.MaxNumberValue .. ", got " .. arg .. ". Dropping event call.")
								return
							elseif argType == "number" and cfig.MinNumberValue and arg < cfig.MinNumberValue then
								warn("Guard: Argument value below minimum for event '" .. event_name .. "'. Expected >= " .. cfig.MinNumberValue .. ", got " .. arg .. ". Dropping event call.")
								return
							end

							if argType == "number" and cfig.RejectBadNumbers and (arg == math.huge or arg == -math.huge or arg ~= arg) then
								warn("Guard: Argument is an invalid number for event '" .. event_name .. "'. Dropping event call.")
								return
							end

							if argType == "string" and cfig.MaxStringLength and #arg > cfig.MaxStringLength then
								warn("Guard: Argument string length exceeds maximum for event '" .. event_name .. "'. Expected <= " .. cfig.MaxStringLength .. ", got " .. #arg .. ". Dropping event call.")
								return
							end
						end
					end
				end
	
				
			else
				if settings.Debug then
					warn("Guard: No argument types defined for event '" .. event_name .. "'. Skipping argument checks. However, this is not recommended for security reasons.")
				end

				
			end


			

			handler(player, ...)
		end)
	else
		remote = game:GetService("ReplicatedStorage"):WaitForChild("GuardRemote")
	end

	initialised = true
	print("Guard Successfully initialised!")
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