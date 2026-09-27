local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Guard = require(ReplicatedStorage.Guard)

Guard.Init()
Guard.Fire("Test", "hello", "world", 123)