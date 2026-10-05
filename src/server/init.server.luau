local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Guard = require(ReplicatedStorage.Guard)

Guard.Init()

Guard.AddCheck("TestCheck", function(player, data, settings)
    local text = data.text
    local textSettings = settings.text or "hello"
    if not text then
        return false
    end
    if text == textSettings then
        return true
    else
        return false
    end
end)

Guard.On("Test", function(player, text, x, y)
    print(player)
    print("Test event received with arguments:", text, x, y)
    
end)