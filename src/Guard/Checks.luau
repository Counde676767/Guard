local Checks = {}

function Checks.Init()
    print("Checks Successfully initialised!")
    return true
end

Checks.CheckLists = {}

function Checks.CheckLists.TestCheck(player, data, settings)
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
end

return Checks