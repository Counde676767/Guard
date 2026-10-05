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
local clientHandlers = {}
local rates = {}

local Guard = {}

Guard.VERSION = "0.1.0"

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

local function doChecks(player, cfig, event_name, args)
	local checks = cfig.Checks
	if not checks or #checks == 0 then
		return true
	end

	local named = {}
	for i, name in cfig.ArgNames do
		named[name] = args[i]
	end

	for _, check in checks do
		local fn = Checks.CheckLists[check.Name]
		local ok, passed, reason = pcall(fn, player, named, table.unpack(check.Args or {}))
		if not ok then
			debugWarn(`'{event_name}' check '{check.Name}' errored: {passed}. Dropped.`)
			return false
		end
		if not passed then
			debugWarn(`'{event_name}' check '{check.Name}' failed: {reason or "no reason"}. Dropped.`)
			return false
		end
	end

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

				if not doChecks(player, cfig, event_name, table.pack(...)) then
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

function Guard.AddCheck(name: string, fn: (player: Player, data: { [string]: any }, settings: { [string]: any }) -> (boolean, string?))
	local checkList = Checks.CheckLists
	if checkList[name] then
		error(`[Guard] Check '{name}' already exists`)
	end
	checkList[name] = fn
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
	if type(action) ~= "function" then
		error(`[Guard] Guard.On('{event_name}') expected a function`)
	end

	local cfig = Configs.Events[event_name]
	if not cfig then
		error(`[Guard] Event '{event_name}' is not in Configs.Events`)
	end

	if not isServer then
		if clientHandlers[event_name] then
			error(`[Guard] Event '{event_name}' already has a client handler`)
		end
		clientHandlers[event_name] = action
		return
	end

	if handlers[event_name] then
		error(`[Guard] Event '{event_name}' already has a handler`)
	end

	if not cfig.Args then
		debugWarn(`'{event_name}' has no Args defined. Only basic type checks will run.`)
	end

	if cfig.Checks then
		if not cfig.ArgNames or #cfig.ArgNames ~= #(cfig.Args or {}) then
			error(`[Guard] '{event_name}': ArgNames must name every arg when Checks are used`)
		end
		for _, check in cfig.Checks do
			if type(Checks.CheckLists[check.Name]) ~= "function" then
				error(`[Guard] '{event_name}': check '{check.Name}' does not exist`)
			end
		end
	end

	handlers[event_name] = action
end

function Guard.FireClient(player: Player, event_name: string, ...: any)
	if not initialised then
		error("[Guard] Call Guard.Init() before Guard.FireClient()")
	end
	if not isServer then
		error("[Guard] Guard.FireClient() is server-only.")
	end

	local cfig = Configs.Events[event_name]
	if not cfig then
		error(`[Guard] Event '{event_name}' is not in Configs.Events`)
	end

	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		error(`[Guard] FireClient expected a Player, got {typeof(player)}`)
	end

	if cfig.IsUnreliable then
		unreliableRemote:FireClient(player, event_name, ...)
	else
		remote:FireClient(player, event_name, ...)
	end
end

return Guard