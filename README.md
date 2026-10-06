
# Guard

**The network layer for Roblox.** Guard runs all your remote traffic through one RemoteEvent (plus one UnreliableRemoteEvent) and checks every call before it reaches your code: rate limits, argument validation, and reusable checks. You write the config and the handlers. Guard handles everything in between.

> **v0.1.0** · early release. The API may still change before 1.0.

---

## Why Guard?

- **One remote instead of hundreds.** Events are routed by name, so you stop creating and managing a RemoteEvent for every action.
- **Rate limiting per player, per event.** Spam is dropped before it reaches your handler. In testing, a flood of 150,000 calls at an event limited to 5 per second let exactly the limit through.
- **Argument validation.** Types, argument counts, number ranges, string lengths, NaN and infinity are all checked automatically from your config.
- **Reusable checks.** Write a rule once (is the player alive, is the target in range) and list it on any event.
- **Loud errors for you, silent drops for exploiters.** Your mistakes fail at startup with a clear message. Bad input from clients is dropped quietly and only logged in Debug mode, so exploiters can't flood your output.

---

## Installation

1. Download `Guard.rbxm` from the [latest release](../../releases).
2. Drag it into **ReplicatedStorage**.
3. Configure your events in `Guard/Configs` (see below).

---

## Quick start

**Server** (a Script in ServerScriptService):

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Guard = require(ReplicatedStorage.Guard)

Guard.Init()

Guard.On("Attack", function(player, target, power)
	print(player.Name, "attacked", target, "with power", power)
end)
```

**Client** (a LocalScript):

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Guard = require(ReplicatedStorage:WaitForChild("Guard"))

Guard.Init()

Guard.Fire("Attack", workspace.Dummy, 0.8)
```

**Config** (in `Guard/Configs`):

```lua
Configs.Events = {
	Attack = {
		Args = { "Instance", "number" },
		ArgNames = { "target", "power" },
		MinNumberValue = 0,
		MaxNumberValue = 1,
		MaxCallsPerSecond = 8,
	},
}
```

Every `Attack` call now has to pass the rate limit and match the argument types and ranges before your handler runs.

---

## How a call is processed

Every call from a client goes through these steps, in order. If any step fails, the call is dropped and your handler never runs.

1. **Event lookup.** The event name must be a string, exist in your config, and have a handler.
2. **Remote check.** The call must arrive through the right remote (reliable or unreliable) for that event.
3. **Rate limit.** The player must have calls left for this event.
4. **Argument validation.** Count, types, and values must match the config.
5. **Checks.** Every check listed on the event must pass.
6. **Handler.** Your code runs.

---

## API

### `Guard.Init(configs?)`
Sets Guard up. Call it once on the server and once on each client, before anything else. Optionally takes a table of config overrides that are merged into `Guard/Configs`.

### `Guard.On(eventName, handler)`
Registers the function that runs when an event arrives.
- **Server:** `handler(player, ...)` runs after the call passes every check.
- **Client:** `handler(...)` runs when the server fires the event.

Each event can have one handler per side. Registering a second one errors.

### `Guard.Fire(eventName, ...)` · client only
Sends an event to the server.

### `Guard.FireClient(player, eventName, ...)` · server only
Sends an event to one client.

### `Guard.AddCheck(name, fn)` · server only
Registers a custom check. Call it **before** `Guard.On` for any event that uses it, since `Guard.On` verifies that every listed check exists.

### `Guard.VERSION`
The installed version, for example `"0.1.0"`.

---

## Configuration

All configuration lives in `Guard/Configs`.

### Event options

| Option | Type | Description |
| --- | --- | --- |
| `Args` | `{ string }` | Exact argument types, in order: `"string"`, `"number"`, `"boolean"`, `"Instance"`. Calls must match exactly. |
| `ArgNames` | `{ string }` | A name for each argument, in the same order as `Args`. Required when the event uses `Checks`. |
| `MaxCallsPerSecond` | `number` | Rate limit per player for this event. |
| `MinNumberValue` | `number` | Smallest allowed value for number arguments. |
| `MaxNumberValue` | `number` | Largest allowed value for number arguments. |
| `MaxStringLength` | `number` | Longest allowed string argument. |
| `RejectBadNumbers` | `boolean` | Drop NaN and infinity. |
| `MaxArgs` | `number` | Used when `Args` isn't set: the maximum number of arguments. |
| `AllowedTypes` | `{ [string]: true }` | Used when `Args` isn't set: which types are allowed. |
| `IsUnreliable` | `boolean` | Send this event through the UnreliableRemoteEvent. Good for small, frequent data where losing a message is fine. |
| `Checks` | `{ check }` | Checks to run after validation. See below. |

Anything an event doesn't set falls back to `Configs.Defaults`.

> **Tip:** Always set `Args` when you can. Events without it only get the looser `MaxArgs` and `AllowedTypes` checks, and Guard warns you about it in Debug mode.

### Settings

| Setting | Description |
| --- | --- |
| `Debug` | Logs every dropped call with the reason. Use it in Studio while setting up. |
| `Cracked` | Turns off rate limits, validation, and checks. **Testing only.** It only works in Studio and is ignored in live servers, so it can't be shipped by accident. |

---

## Checks

Checks are your game's rules, written once and reused on any event.

### Writing a check

A check receives the player, the call's arguments by name, and its own settings from the config. It returns `true` to pass, or `false` and a reason to fail.

```lua
Guard.AddCheck("inRange", function(player, data, settings)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false, "no character"
	end
	local distance = (root.Position - data.target.Position).Magnitude
	return distance <= settings.max, `distance {math.floor(distance)} is above {settings.max}`
end)
```

### Using a check

List it on any event, with its settings:

```lua
Attack = {
	Args = { "Instance", "number" },
	ArgNames = { "target", "power" },
	Checks = {
		{ Name = "inRange", Args = { max = 20 } },
	},
},
Interact = {
	Args = { "Instance" },
	ArgNames = { "target" },
	Checks = {
		{ Name = "inRange", Args = { max = 10 } },
	},
},
```

Checks run in the order they're listed and stop at the first failure.

### Rules for checks

- **Don't yield.** No `task.wait`, no DataStore calls. Checks run on every call, before your handler.
- **Put cheap checks first,** so expensive ones rarely run.
- **Errors count as failures.** If a check errors, the call is dropped instead of crashing, and the error shows in Debug mode.
- **Misspelled check names error at startup,** so typos are caught before anyone plays.

---

## Updating

In v0.1, your events live in `Guard/Configs`, which is replaced when you update Guard. **Back up your config before updating**, then copy your events into the new version.

Keeping your config outside Guard's folder is planned for v0.2, so future updates won't touch it.

---

## Roadmap

- **v0.2:** config outside Guard's folder, with migration between versions. Remote functions (client-to-server requests with a response).
- **Later:** a global per-player rate limit across all events, a violation callback for logging and kicking, built-in checks, batching and packet packing, and an extension system.

---

## Credits

Made by **Counde**.

- Discord: `@counde`
- Website: Coming soon 

Guard is free and open source. If it helps your game, you can support development by donating, coming soon as well.

## License

Counde.
