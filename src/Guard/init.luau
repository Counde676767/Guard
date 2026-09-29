local Configs = require(script.Configs)
local Checks = require(script.Checks)

local remote

local initialised = false

local isServer = game:GetService("RunService"):IsServer()

local handlers = {}

local rates = {}

local received, handled = 0, 0

local stats = {} -- stats[event_name] = { calls = 0, time = 0 }



 -- in the listener: received += 1 at the top, handled += 1 right before the handler runs

task.spawn(function()
	while true do
	    task.wait(1)
		print(`received {received}, handled {handled}`)
		received, handled = 0, 0
        for name, s in stats do
	        print(`{name}: {s.calls} calls, avg {math.round(s.time / s.calls * 1e6 * 100) / 100} µs`)
        end
        table.clear(stats)
	end
end)


local function record(event_name, start)
	local key = if typeof(event_name) == "string" then event_name else "<invalid>"
	local s = stats[key]
	if not s then
		s = { calls = 0, time = 0 }
		stats[key] = s
	end
	s.calls += 1
	s.time += os.clock() - start
end

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

		remote.OnServerEvent:Connect(function(player, event_name, ...)
			local start = os.clock()
			received += 1

			if typeof(event_name) ~= "string" then
				record(event_name, start)
				return
			end

			local handler = handlers[event_name]
			if not handler then
				record(event_name, start)
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
				record(event_name, start)
				return
			end
			bucket.tokens -= 1

			handled += 1
			record(event_name, start)
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