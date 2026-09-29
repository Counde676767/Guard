local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Guard = require(ReplicatedStorage.Guard)

Guard.Init()
-- event spammer 5000
for frame = 1, 300 do
	for i = 1, 500 do
		Guard.Fire("Test", "hello", "world", 123)
	end
	task.wait()
end