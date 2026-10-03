local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = require(script.Configs)
local Checks = require(script.Checks)

local remote
local unreliableRemote

local initialised = false
local isServer = RunService:IsServer()

local handlers = {}
local rates = {}

local Guard = {}

local function debugWarn(...)
	if Configs.Settings.Debug then
		warn("[Guard]", ...)
	end
end

local function checkValue(cfig, event_name, index, arg)
	local argType = typeof(arg)

	if argType == "number" then
		if cfig.RejectBadNumbers and (arg ~= arg or arg == math.huge or arg == -math.huge) then
			debugWarn(`'{event_name}' arg {index}: invalid number (NaN or infinity). Dropped.`)
			return false
		end
		if cfig.MinNumberValue and arg < cfig.MinNumberValue then
			debugWarn(`'{event_name}' arg {index}: {arg} is below the minimum {cfig.MinNumberValue}. Dropped.`)
			return false
		end
		if cfig.MaxNumberValue and arg > cfig.MaxNumberValue then
			debugWarn(`'{event_name}' arg {index}: {arg} is above the maximum {cfig.MaxNumberValue}. Dropped.`)
			return false
		end
	elseif argType == "string" then
		if cfig.MaxStringLength and #arg > cfig.MaxStringLength then
			debugWarn(`'{event_name}' arg {index}: string length {#arg} is above the maximum {cfig.MaxStringLength}. Dropped.`)
			return false
		end
	end

	return true
end

local function checkArgs(cfig, event_name, args)
	local count = args.n

	if cfig.Args then

		if count ~= #cfig.Args then
			debugWarn(`'{event_name}': expected {#cfig.Args} args, got {count}. Dropped.`)
			return false
		end
		for i, expectedType in cfig.Args do
			local arg = args[i]
			if typeof(arg) ~= expectedType then
				debugWarn(`'{event_name}' arg {i}: expected {expectedType}, got {typeof(arg)}. Dropped.`)
				return false
			end
			if not checkValue(cfig, event_name, i, arg) then
				return false
			end
		end
	else

		if cfig.MaxArgs and count > cfig.MaxArgs then
			debugWarn(`'{event_name}': {count} args is above the maximum {cfig.MaxArgs}. Dropped.`)
			return false
		end
		for i = 1, count do
			local arg = args[i]
			if cfig.AllowedTypes and not cfig.AllowedTypes[typeof(arg)] then
				debugWarn(`'{event_name}' arg {i}: type {typeof(arg)} is not allowed. Dropped.`)
				return false
			end
			if not checkValue(cfig, event_name, i, arg) then
				return false
			end
		end
	end

	return true
end

local function allowCall(player, event_name, cfig, now)
	local playerRates = rates[player.UserId]
	if not playerRates then
		playerRates = {}
		rates[player.UserId] = playerRates
	end

	local max = cfig.MaxCallsPerSecond
	local bucket = playerRates[event_name]
	if not bucket then
		bucket = { tokens = max, last = now }
		playerRates[event_name] = bucket
	end

	bucket.tokens = math.min(max, bucket.tokens + (now - bucket.last) * max)
	bucket.last = now

	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

function Guard.Init(old_configs)
	if initialised then
		warn("[Guard] Guard has already been initialised!")
		return
	end

	local cfigs = Configs.Init(old_configs)
	local checks = Checks.Init()
	if not (cfigs and checks) then
		error("[Guard] Guard failed to initialise!")
	end

	if isServer then
		remote = Instance.new("RemoteEvent")
		remote.Name = "GuardRemote"
		remote.Parent = ReplicatedStorage

		unreliableRemote = Instance.new("UnreliableRemoteEvent")
		unreliableRemote.Name = "GuardUnreliableRemote"
		unreliableRemote.Parent = ReplicatedStorage

		local isCracked = Configs.Settings.Cracked
		if isCracked then
			if RunService:IsStudio() then
				warn("[Guard] Cracked mode is enabled! Rate limits and argument checks are bypassed. Testing only!")
			else
				isCracked = false
				warn("[Guard] Cracked mode is ignored in live servers.")
			end
		end

		local function dispatch(player, isUnreliable, event_name, ...)
			if typeof(event_name) ~= "string" then
				return
			end

			local handler = handlers[event_name]
			if not handler then
				return
			end

			local cfig = Configs.Events[event_name]

			if (cfig.IsUnreliable == true) ~= isUnreliable then
				debugWarn(`'{event_name}' arrived through the wrong remote. Dropped.`)
				return
			end

			if not isCracked then
				if not allowCall(player, event_name, cfig, os.clock()) then
					return
				end
				if not checkArgs(cfig, event_name, table.pack(...)) then
					return
				end
			end

			handler(player, ...)
		end

		remote.OnServerEvent:Connect(function(player, event_name, ...)
			dispatch(player, false, event_name, ...)
		end)

		unreliableRemote.OnServerEvent:Connect(function(player, event_name, ...)
			dispatch(player, true, event_name, ...)
		end)

		Players.PlayerRemoving:Connect(function(player)
			rates[player.UserId] = nil
		end)
	else
		remote = ReplicatedStorage:WaitForChild("GuardRemote")
		unreliableRemote = ReplicatedStorage:WaitForChild("GuardUnreliableRemote")
	end

	initialised = true
	if RunService:IsStudio() then
		print("[Guard] Initialised")
	end
end

function Guard.Fire(event_name: string, ...: any)
	if not initialised then
		error("[Guard] Call Guard.Init() before Guard.Fire()")
	end
	if isServer then
		error("[Guard] Guard.Fire() is client-only. Use Guard.FireClient() on the server.")
	end

	local cfig = Configs.Events[event_name]
	if not cfig then
		error(`[Guard] Event '{event_name}' is not in Configs.Events`)
	end

	if cfig.IsUnreliable then
		unreliableRemote:FireServer(event_name, ...)
	else
		remote:FireServer(event_name, ...)
	end
end

function Guard.On(event_name: string, action: (...any) -> ())
	if not initialised then
		error("[Guard] Call Guard.Init() before Guard.On()")
	end
	if not isServer then
		error("[Guard] Guard.On() is server-only for now.")
	end

	local cfig = Configs.Events[event_name]
	if not cfig then
		error(`[Guard] Event '{event_name}' is not in Configs.Events`)
	end
	if handlers[event_name] then
		error(`[Guard] Event '{event_name}' already has a handler`)
	end
	if not cfig.Args then
		debugWarn(`'{event_name}' has no Args defined. Only basic type checks will run.`)
	end

	handlers[event_name] = action
end

return Guard