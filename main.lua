-- Waiting until game is loaded
if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- Loading API
loadstring(game:HttpGet("https://raw.githubusercontent.com/0xSteak/libraries/main/steakAPI.lua"))()

if not Steak then
    warn("Failed to load API")
    return
end

if shared.sapphire then
    for i,v in pairs(shared.sapphire.connections) do
        v:Disconnect()
    end
    shared.sapphire.stopThreads = true
    shared.sapphire.destroyUI()
end

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
-- Remotes
local RoundEndFade = ReplicatedStorage.Remotes.Gameplay.RoundEndFade
local CoinCollected = ReplicatedStorage.Remotes.Gameplay.CoinCollected
local CoinsStarted = ReplicatedStorage.Remotes.Gameplay.CoinsStarted
local GetPlayerData = ReplicatedStorage.Remotes.Extras.GetPlayerData
local PlayerDataChanged = ReplicatedStorage.Remotes.Gameplay.PlayerDataChanged
local LoadingMap = ReplicatedStorage.Remotes.Gameplay.LoadingMap
-- Game Objects
local Map
local CoinContainer
-- Variables
local runArgs = {...}
local LocalPlayer = Players.LocalPlayer
local tpCooldown = tick()
local canCollect = true
local safeMode = false
local coinBag
local gamemode
local whitelist = {"void_functionn", "N0TSTEAK"}
-- UI Library
local SteakUI = Steak.UI()

-- Main Table
local sapphire = {
    autoFarm = {
        enabled = false,
        tweenSpeed = 16,
        murdTweenSpeed = 16,
        lostCoinResetTime = 20,
    },
    stopThreads = false,
    connections = {},
    uiConfig = {}
}

-- Safe Part
local safePart = Instance.new("Part")
safePart.Parent = workspace
safePart.CanCollide = true
safePart.Transparency = 1
safePart.Anchored = true
safePart.Size = Vector3.new(30, 1, 30)
safePart.Position = Vector3.zero

---------------------------
-------- Functions --------
---------------------------

-- Tweening the character to <pos> at speed <speed> (smooth/slow teleport)
local function tween(pos, speed)
    local rootPart = Steak.hrp()
    if not rootPart then return end

    local distance = (rootPart.Position - pos).Magnitude

    local tween = TweenService:Create(rootPart, TweenInfo.new(distance / speed, Enum.EasingStyle.Linear), {CFrame = CFrame.new(pos)})
    rootPart.Anchored = true
    tween:Play()
    tween.Completed:Connect(function()
        rootPart.Anchored = false
    end)
    return tween
end

-- Just teleport, with cooldown
local function tp(pos)
    repeat task.wait() until tick() >= tpCooldown

    local rootPart = Steak.hrp()
    if not rootPart then return end

    rootPart.CFrame = CFrame.new(pos)

    tpCooldown = tick() + 5

    task.wait(0.5)
end

-- Get the closest coin for autofarm
local function getClosestCoin()
    local coins = CoinContainer:GetChildren()
    local rootPart = Steak.hrp()
    local closestDistance
    local closestCoin = {}

    if not rootPart then return end

    for i,v in pairs(coins) do
        if v:FindFirstChild("CoinVisual") and v.CoinVisual.Transparency == 0 then
            local distance = (rootPart.Position -  v.Position).Magnitude

            if not closestDistance or distance < closestDistance then
                closestDistance = distance
                closestCoin = v
            end
        end
    end

    return closestCoin, closestDistance and closestDistance > 100
end

local function getRandomClosestCoin()
    local coins = CoinContainer:GetChildren()
    local rootPart = Steak.hrp()

    table.sort(coins, function(a, b)
        if a:FindFirstChild("CoinVisual") and a.CoinVisual.Transparency == 0 and b:FindFirstChild("CoinVisual") and b.CoinVisual.Transparency == 0 then
            local distanceA = (a.Position - rootPart.Position).Magnitude
            local distanceB = (b.Position - rootPart.Position).Magnitude
            return distanceA < distanceB
        end
    end)

    local randomCoin

    if #coins >= 5 then
        randomCoin = coins[math.random(1, #coins)]
    end

    return randomCoin, (randomCoin.Position - rootPart.Position).Magnitude > 100
end

-- Get player who has the murderer role
local function getMurderer()
    if gamemode == "Infection" then return end
    for i,v in pairs(Players:GetPlayers()) do
        if v.Backpack:FindFirstChild("Knife") or v.Character and v.Character:FindFirstChild("Knife") then
            return v
        end
    end
end

-- Check if local player have the gun
local function getGun()
    local character = Steak.char()
    return character and character:FindFirstChild("Gun") or LocalPlayer.Backpack:FindFirstChild("Gun")
end

-- Teleport to murderer and shoot him
local function shootMurderer()
    local character = Steak.char()
    local gun = getGun()
    local murderer = getMurderer()
    if character and gun and murderer then
        if gun.Parent.Name == "Backpack" then
            gun.Parent = character
        end

        local murdRootPart = Steak.hrp(murderer)
        local murdLookVector = murdRootPart.CFrame.LookVector
        local murdHumanoid = Steak.hmnd(murderer)
        local murdChar = Steak.char(murderer)

        Steak.hrp().CFrame = CFrame.new(murdRootPart.Position - (murdLookVector * 5), murdRootPart.Position)
        
        task.wait(LocalPlayer:GetNetworkPing() + 0.1)

        local aimPos

        if murdHumanoid:GetState() == Enum.HumanoidStateType.Freefall then
            aimPos = murdChar.RightLowerLeg.CFrame
        elseif murdHumanoid:GetState() == Enum.HumanoidStateType.Jumping then
            aimPos = murdChar.Head.CFrame
        else
            aimPos = murdRootPart.CFrame
        end

        task.spawn(function()
            gun.KnifeLocal.CreateBeam.RemoteFunction:InvokeServer(1, (aimPos + (murdHumanoid.MoveDirection * murdHumanoid.WalkSpeed) / 16).Position, "AH2")
        end)

        task.wait(LocalPlayer:GetNetworkPing() + 0.1)

        Steak.hrp().CFrame = CFrame.new(safePart.Position + Vector3.new(0, 3, 0))
    end
end

-- Pick gun drop
local function pickGun()
    local gunDrop = workspace:FindFirstChild("GunDrop", true)
    if gunDrop and gunDrop.Parent:FindFirstChild("CoinContainer") and Steak.hrp() then
        local oldPos = Steak.hrp().CFrame
        Steak.hrp().CFrame = CFrame.new(gunDrop.Position)
        task.wait(0.1)
        Steak.hrp().CFrame = oldPos
    end
end

-- Kill everyone as murderer
local function murdKillAll()
    local knife = LocalPlayer.Backpack:FindFirstChild("Knife") or Steak.char() and Steak.char():FindFirstChild("Knife")
    if knife then
        knife.Parent = Steak.char()
        for i,v in pairs(Players:GetPlayers()) do
            if v.Name ~= LocalPlayer.Name and Steak.hrp(v) then
                local rootPart = Steak.hrp(v)
                knife.Stab:FireServer("Down")
                task.wait()
                task.spawn(function()
                    firetouchinterest(rootPart, knife.Handle, 0)
                    firetouchinterest(rootPart, knife.Handle, 1)
                end)
            end
        end
    else
        return 0
    end
end

-- Get all infected players (Infection gamemode)
local function getAllInfected()
    local infected = {}
    for i,v in pairs(Players:GetPlayers()) do
        if v.Name ~= LocalPlayer.Name then
            if v.Backpack:FindFirstChild("Knife") or v.Character and v.Character:FindFirstChild("Knife") then
                table.insert(infected, v)
            end
        end
    end
    return infected
end

-- Check if local player is the last alive except the murderer (needed for resetting the local player in this case to not waste time)
local function checkLast()
    local playerData = GetPlayerData:InvokeServer()
    local someoneElseAlive = false
    if playerData then
        for i,v in pairs(playerData) do
            if v.Role ~= "Murderer" and not v.Dead and i ~= LocalPlayer.Name and not table.find(whitelist, i) then
                someoneElseAlive = true
                break
            end
        end
    end
    if not someoneElseAlive and playerData[LocalPlayer.Name] and not playerData[LocalPlayer.Name].Dead then
        return true
    end
end

-- Get local player role
local function getMyRole()
    local playerData = GetPlayerData:InvokeServer()
    if playerData and playerData[LocalPlayer.Name] then
        return playerData[LocalPlayer.Name].Role
    end
end

-- End the round using few methods
local function endRound()
    if gamemode == "Infection" then
        if LocalPlayer.Backpack:FindFirstChild("Knife") or Steak.char():FindFirstChild("Knife") then
            repeat
                task.wait(1)
            until murdKillAll() == 0
        else
            repeat
                local infecteds = getAllInfected()
                local infected = #infecteds > 0 and infecteds[math.random(1, #infecteds)]
                if infected and Steak.hrp(infected) and Steak.hrp() then
                    local rootPart = Steak.hrp(infected)
                    Steak.hrp().CFrame = CFrame.new(rootPart.Position + rootPart.CFrame.LookVector * 5)
                    task.wait(5)
                end
                task.wait()
            until LocalPlayer.Backpack:FindFirstChild("Knife") or Steak.char():FindFirstChild("Knife") or not workspace:FindFirstChild("Barn")
            murdKillAll()
        end
        return
    end

    if not getGun() then
        pickGun()
        task.wait(0.5)
    end

    local gun = getGun()

    if gun and getMurderer() and not table.find(whitelist, getMurderer().Name) and not checkLast() then
        tp(safePart.Position + Vector3.new(0, 3, 0))
        task.wait(0.1)
        repeat shootMurderer() task.wait(3) until not getMurderer() or checkLast()
        if checkLast() and not table.find(whitelist, getMurderer().Name) then
            game.Players.LocalPlayer.Character.Humanoid.Health = 0
        end
    elseif getMurderer() and getMurderer().Name ~= game.Players.LocalPlayer.Name and not getGun() and not checkLast() then
        tp(safePart.Position + Vector3.new(0, 3, 0))
        repeat pickGun() task.wait(1) until getGun() or not getMurderer() or checkLast()
        if checkLast() and not table.find(whitelist, getMurderer().Name) then
            game.Players.LocalPlayer.Character.Humanoid.Health = 0
        elseif getGun() then
            endRound()
        end
    else
        game.Players.LocalPlayer.Character.Humanoid.Health = 0
    end
end

local function loadConfig(fileName)
    if not isfolder("Sapphire/") then makefolder("Sapphire") end
    if not isfolder("Sapphire/MM2/") then makefolder("Sapphire/MM2") end
    if not isfile("Sapphire/MM2/"..fileName) then return 0 end
    local encodedConfig = readfile("Sapphire/MM2/"..fileName)
    local config = HttpService:JSONDecode(encodedConfig)
    for i,v in pairs(config) do
        if sapphire.uiConfig[i] then
            sapphire.uiConfig[i].set(v)
        end
    end
end

local function saveConfig(fileName, autoLoad)
    if not isfolder("Sapphire/") then makefolder("Sapphire") end
    if not isfolder("Sapphire/MM2/") then makefolder("Sapphire/MM2") end
    local config = {}
    for i,v in pairs(sapphire.uiConfig) do
        config[i] = v.get()
    end
    local encodedConfig = HttpService:JSONEncode(config)
    writefile("Sapphire/MM2/"..fileName, encodedConfig)
    if autoLoad then
        writefile("Sapphire/MM2/autoload", fileName)
    end
end

local function autoLoadConfig()
    if not isfolder("Sapphire/") then return end
    if not isfolder("Sapphire/MM2/") then return end
    if not isfile("Sapphire/MM2/autoload") then return end
    loadConfig(readfile("Sapphire/MM2/autoload"))
end

---------------------------
---------- Loops ----------
---------------------------

-- Coin Container checker
task.spawn(function()
    while not sapphire.stopThreads do
        if not CoinContainer then
            CoinContainer = workspace:FindFirstChild("CoinContainer", true)
            if CoinContainer and not CoinContainer.Parent:IsA("Model") then
                CoinContainer = nil
                for i,v in pairs(game:GetDescendants()) do
                    if v.Name == "CoinContainer" and v:IsA("Model") and v.Parent:IsA("Model") then
                        CoinContainer = v
                    end
                end
            end
        else
            CoinContainer.Destroying:Wait()
            CoinContainer = nil
        end

        task.wait(1)
    end
end)
-- Main Auto Farm Loop
task.spawn(function()
    local lostCoinResetTimer = tick()
    local lostCoinCount = 0
    local tweenSpeed

    while not sapphire.stopThreads do
        local suc, msg = pcall(function()
            tweenSpeed = getMyRole() == "Murderer" and sapphire.autoFarm.murdTweenSpeed or sapphire.autoFarm.tweenSpeed
            if CoinContainer and canCollect and sapphire.autoFarm.enabled then
                local closestCoin, isFar

                if lostCoinCount >= 5 then
                    closestCoin, isFar = getRandomClosestCoin()
                    lostCoinCount = 0
                else
                    closestCoin, isFar = getClosestCoin()
                end
        
                if closestCoin and closestCoin.Position then
                    local coinBagBefore = coinBag
                    if not isFar then
                        local t: Tween = tween(closestCoin.Position + Vector3.new(0, 3.15, 0), tweenSpeed)
                        repeat task.wait(0.1) until t.PlaybackState ~= Enum.PlaybackState.Playing or closestCoin and closestCoin:FindFirstChild("CoinVisual") and closestCoin.CoinVisual.Transparency ~= 0 or getClosestCoin() ~= closestCoin or sapphire.stopThreads
                        if sapphire.stopThreads then
                            return
                        end
                        if t.PlaybackState == Enum.PlaybackState.Playing and closestCoin.CoinVisual.Transparency ~= 0 then
                            lostCoinCount += 1
                        else
                            task.delay(LocalPlayer:GetNetworkPing() + 0.1, function()
                                if coinBag == coinBagBefore then
                                    lostCoinCount += 1
                                end
                            end)
                        end
                        t:Cancel()
                    else
                        tp(closestCoin.Position + Vector3.new(0, 5, 0))
                    end
                end

                if tick() >= lostCoinResetTimer then
                    lostCoinCount = 0
                    lostCoinResetTimer = tick() + sapphire.autoFarm.lostCoinResetTime
                end
    
                --[[if lostCoinCount >= 5 then
                    local coins = CoinContainer:GetChildren()
                    local t: Tween = tween(coins[math.random(1, #coins)].Position + Vector3.new(0, 5, 0), tweenSpeed)
                    t.Completed:Wait()
                    lostCoinCount = 0
                end]]
    
                if closestCoin and closestCoin:FindFirstChild("CoinVisual") then
                    closestCoin.CoinVisual.Transparency = 0.01
                end
                task.delay(1, function()
                    if closestCoin and closestCoin:FindFirstChild("CoinVisual") and closestCoin.CoinVisual.Transparency == 0.01 then
                        closestCoin.CoinVisual.Transparency = 0
                    end
                end)
            end
        end)

        if not suc then
            warn(msg)
        end

        task.wait(0.1)
    end
end)

---------------------------
------- Connections -------
---------------------------

sapphire.connections[1] = LoadingMap.OnClientEvent:Connect(function(mode)
    gamemode = mode
end)

sapphire.connections[2] = CoinCollected.OnClientEvent:Connect(function(coinType, collected, max)
    coinBag = collected
    if collected == max then
        coinBag = 0
        canCollect = false
        endRound()
    end
end)

sapphire.connections[3] = RoundEndFade.OnClientEvent:Connect(function()
    canCollect = false
end)

sapphire.connections[4] = CoinsStarted.OnClientEvent:Connect(function()
    canCollect = true
end)

sapphire.connections[5] = game.CoreGui.RobloxPromptGui.promptOverlay.ChildAdded:Connect(function()
    queue_on_teleport('loadstring(game:HttpGet("https://raw.githubusercontent.com/0xSteak/mm/refs/heads/main/main.lua"))(true)')
    game:GetService("TeleportService").TeleportInitFailed:Connect(function()
        game:GetService("TeleportService"):Teleport(game.PlaceId)
    end)
    if #game.Players:GetPlayers() <= 5 then
        game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId)
    else
        game:GetService("TeleportService"):Teleport(game.PlaceId)
    end
end)

sapphire.connections[6] = LocalPlayer.Idled:Connect(function()
    game:GetService("VirtualUser"):CaptureController()
    game:GetService("VirtualUser"):ClickButton2(Vector2.new())
end)

---------------------------
----------- UI ------------
---------------------------

local UI = SteakUI.new({
    name = "Sapphire",
    showAtStart = false,
    icon = "rbxassetid://12114859949"
})

local AutoFarm = UI.addTab("Auto Farm")
local AutoFarm_Section = AutoFarm.addSection("Auto Farm")
sapphire.uiConfig.autoFarmToggle = AutoFarm_Section.addToggle({
    name = "Auto Farm",
    callback = function(value)
        sapphire.autoFarm.enabled = value
    end
})
local AutoFarm_Settings = AutoFarm.addSection("Settings")
sapphire.uiConfig.autoFarmTweenSpeed = AutoFarm_Settings.addSlider({
    name = "Tween Speed",
    min = 1,
    max = 30,
    initVal = sapphire.autoFarm.tweenSpeed,
    decimals = 1,
    callback = function(value)
        sapphire.autoFarm.tweenSpeed = value
    end
})
sapphire.uiConfig.autoFarmMurdTweenSpeed = AutoFarm_Settings.addSlider({
    name = "Murderer Tween Speed",
    min = 1,
    max = 30,
    initVal = sapphire.autoFarm.murdTweenSpeed,
    decimals = 1,
    callback = function(value)
        sapphire.autoFarm.murdTweenSpeed = value
    end
})
sapphire.uiConfig.lostCoinResetTime = AutoFarm_Settings.addSlider({
    name = "Lost Coins Reset Time",
    min = 1,
    max = 60,
    initVal = sapphire.autoFarm.lostCoinResetTime,
    decimals = 1,
    callback = function(value)
        sapphire.autoFarm.lostCoinResetTime = value
    end
})

local Config = UI.addTab("Config")
local Config_Section = Config.addSection("Config")
local ConfigName = Config_Section.addTextField({
    name = "Config Name",
    placeholder = "ex. myConfig"
})
local AutoLoad = Config_Section.addToggle({
    name = "Autoload this config"
})
Config_Section.addButton({
    name = "Load",
    callback = function()
        if #ConfigName.get() < 1 then
            UI.messageBox("Error", "File name cannot be empty", {"Ok"})
            return
        end
        local cleanConfigName = string.gsub(ConfigName.get(), "[\\/:*?\"<>|]", "")
        local success, result = pcall(loadConfig, cleanConfigName..".json")
        if success and result == 0 then
            UI.messageBox("Error", "File doesn't exist", {"Ok"})
            return
        elseif not success then
            UI.messageBox("Error", result, {"Ok"})
            return
        end
        UI.messageBox("Success", "Config loaded successfully", {"Ok"})
    end
})
Config_Section.addButton({
    name = "Save",
    callback = function()
        if #ConfigName.get() < 1 then
            UI.messageBox("Error", "File name cannot be empty", {"Ok"})
            return
        end
        local cleanConfigName = string.gsub(ConfigName.get(), "[\\/:*?\"<>|]", "")
        local success, result = pcall(saveConfig, cleanConfigName..".json", AutoLoad.get())
        if not success then
            UI.messageBox("Error", result, {"Ok"})
            return
        end
        UI.messageBox("Success", "Config saved successfully", {"Ok"})
    end
})

autoLoadConfig()

UI.show()

sapphire.destroyUI = UI.destroy
shared.sapphire = sapphire