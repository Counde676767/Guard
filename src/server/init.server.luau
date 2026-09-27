local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Guard = require(ReplicatedStorage.Guard)

Guard.Init()
Guard.On("Test", function(player, arg1, arg2, arg3)
    print("Received Test event from player:", player.Name)
    print("Arguments:", arg1, arg2, arg3)
end)