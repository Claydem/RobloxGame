--[[
	FeedAndBoostsUI.client.lua
	StarterPlayerScripts.FeedAndBoostsUI
	
	Handles:
	  1. ⚡ Robux Boosts HUD Timers & Robux Shop UI
	  2. 🍖 Pet Feeding Proximity Prompt & Food Selection Popup
	  3. ❤️ Heart Particle/Floating Animation on Pet Feeding
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local Events = ReplicatedStorage:WaitForChild("Events")
local FeedUIEvent = Events:FindFirstChild("PromptFeedUI")
local FeedPetEvent = Events:FindFirstChild("FeedPet")
local BoostStateUpdate = Events:FindFirstChild("BoostStateUpdate")
local ConsumablesUpdate = Events:FindFirstChild("ConsumablesUpdate")
local PetFedEffect = Events:FindFirstChild("PetFedEffect")

local ItemDatabase = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ItemDatabase"))

local currentConsumables = {}
if ConsumablesUpdate then
	ConsumablesUpdate.OnClientEvent:Connect(function(c)
		currentConsumables = c or {}
	end)
end

-- ══════════════════════════════════════════════════════════
-- 1. BOOSTS HUD (2x EXP, 2x Coins Active Timers)
-- ══════════════════════════════════════════════════════════
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BoostsHUD"
screenGui.ResetOnSpawn = false
screenGui.Parent = PlayerGui

local boostContainer = Instance.new("Frame")
boostContainer.Size = UDim2.new(0, 320, 0, 40)
boostContainer.Position = UDim2.new(0.5, -160, 0, 10)
boostContainer.BackgroundTransparency = 1
boostContainer.Parent = screenGui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, 10)
layout.Parent = boostContainer

local expLbl = Instance.new("TextLabel")
expLbl.Size = UDim2.new(0, 150, 0, 32)
expLbl.BackgroundColor3 = Color3.fromRGB(155, 89, 182)
expLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
expLbl.Font = Enum.Font.GothamBold
expLbl.TextSize = 13
expLbl.Text = "⚡ 2x EXP: 0:00"
expLbl.Visible = false
Instance.new("UICorner", expLbl).CornerRadius = UDim.new(0, 8)
local expStroke = Instance.new("UIStroke", expLbl)
expStroke.Color = Color3.fromRGB(200, 140, 220)
expStroke.Thickness = 1.5
expLbl.Parent = boostContainer

local coinsLbl = Instance.new("TextLabel")
coinsLbl.Size = UDim2.new(0, 150, 0, 32)
coinsLbl.BackgroundColor3 = Color3.fromRGB(241, 196, 15)
coinsLbl.TextColor3 = Color3.fromRGB(20, 20, 20)
coinsLbl.Font = Enum.Font.GothamBold
coinsLbl.TextSize = 13
coinsLbl.Text = "🧠 2x Coins: 0:00"
coinsLbl.Visible = false
Instance.new("UICorner", coinsLbl).CornerRadius = UDim.new(0, 8)
local coinsStroke = Instance.new("UIStroke", coinsLbl)
coinsStroke.Color = Color3.fromRGB(255, 230, 100)
coinsStroke.Thickness = 1.5
coinsLbl.Parent = boostContainer

local currentBoosts = nil
if BoostStateUpdate then
	BoostStateUpdate.OnClientEvent:Connect(function(boosts)
		currentBoosts = boosts
	end)
end

task.spawn(function()
	while true do
		task.wait(1)
		local now = os.time()
		if currentBoosts then
			if currentBoosts.ExpBoostExpire and currentBoosts.ExpBoostExpire > now then
				local left = currentBoosts.ExpBoostExpire - now
				local m = math.floor(left / 60)
				local s = left % 60
				expLbl.Text = string.format("⚡ 2x EXP: %d:%02d", m, s)
				expLbl.Visible = true
			else
				expLbl.Visible = false
			end
			if currentBoosts.BrainCellsBoostExpire and currentBoosts.BrainCellsBoostExpire > now then
				local left = currentBoosts.BrainCellsBoostExpire - now
				local m = math.floor(left / 60)
				local s = left % 60
				coinsLbl.Text = string.format("🧠 2x Coins: %d:%02d", m, s)
				coinsLbl.Visible = true
			else
				coinsLbl.Visible = false
			end
		end
	end
end)

-- ══════════════════════════════════════════════════════════
-- 2. PET FEEDING POPUP & SMART SELECTION
-- ══════════════════════════════════════════════════════════
local feedGui = Instance.new("ScreenGui")
feedGui.Name = "FeedUIPopup"
feedGui.ResetOnSpawn = false
feedGui.Enabled = false
feedGui.Parent = PlayerGui

local bg = Instance.new("Frame")
bg.Size = UDim2.new(0, 420, 0, 320)
bg.Position = UDim2.new(0.5, -210, 0.5, -160)
bg.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
bg.Parent = feedGui
Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 14)
local bgStroke = Instance.new("UIStroke", bg)
bgStroke.Color = Color3.fromRGB(70, 80, 110)
bgStroke.Thickness = 2

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 44)
title.BackgroundTransparency = 1
title.Text = "🍖 Choose Food for Brainrot"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 17
title.Parent = bg

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 32, 0, 32)
closeBtn.Position = UDim2.new(1, -42, 0, 6)
closeBtn.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 15
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)
closeBtn.Parent = bg
closeBtn.MouseButton1Click:Connect(function() feedGui.Enabled = false end)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -20, 1, -60)
scroll.Position = UDim2.new(0, 10, 0, 50)
scroll.BackgroundTransparency = 1
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ScrollBarThickness = 5
scroll.ScrollBarImageColor3 = Color3.fromRGB(100, 110, 140)
scroll.Parent = bg

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 8)
listLayout.Parent = scroll

local currentTargetUUID = nil

local function openFeedMenu(unitUUID)
	currentTargetUUID = unitUUID
	
	-- Check available foods in inventory
	local ownedFoods = {}
	for id, cfg in pairs(ItemDatabase.ShopItems) do
		if cfg.HungerRestored then
			local count = currentConsumables[id] or 0
			if count > 0 then
				table.insert(ownedFoods, { Id = id, Config = cfg, Count = count })
			end
		end
	end
	
	-- IF EXACTLY 1 FOOD TYPE OWNED: Feed directly without prompting!
	if #ownedFoods == 1 then
		if FeedPetEvent and currentTargetUUID then
			FeedPetEvent:FireServer(currentTargetUUID, ownedFoods[1].Id)
		end
		return
	end
	
	-- IF 0 OR 2+ FOOD TYPES OWNED: Open popup
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then child:Destroy() end
	end
	
	if #ownedFoods == 0 then
		local noFoodLbl = Instance.new("TextLabel")
		noFoodLbl.Size = UDim2.new(1, -10, 0, 100)
		noFoodLbl.BackgroundTransparency = 1
		noFoodLbl.Text = "🚫 You don't have any food!\nBuy food in the Shop (🥫 Basic Food, 🥩 Power Meat, 🧀 Shield Cheese, 🍯 Speed Honey)."
		noFoodLbl.TextColor3 = Color3.fromRGB(231, 76, 60)
		noFoodLbl.Font = Enum.Font.GothamBold
		noFoodLbl.TextSize = 13
		noFoodLbl.TextWrapped = true
		noFoodLbl.Parent = scroll
	else
		for _, f in ipairs(ownedFoods) do
			local cfg = f.Config
			local id = f.Id
			local count = f.Count
			
			local card = Instance.new("Frame")
			card.Size = UDim2.new(1, -10, 0, 64)
			card.BackgroundColor3 = Color3.fromRGB(32, 38, 52)
			card.Parent = scroll
			Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
			local stroke = Instance.new("UIStroke", card)
			stroke.Color = Color3.fromRGB(55, 65, 85)
			stroke.Thickness = 1
			
			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.new(1, -100, 1, 0)
			lbl.Position = UDim2.new(0, 10, 0, 0)
			lbl.BackgroundTransparency = 1
			lbl.Text = string.format("%s %s (Owned: %d)\n%s", cfg.Icon or "🥫", cfg.Name or id, count, cfg.Description or "")
			lbl.TextColor3 = Color3.fromRGB(240, 240, 255)
			lbl.TextSize = 11
			lbl.Font = Enum.Font.GothamMedium
			lbl.TextWrapped = true
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.Parent = card
			
			local feedBtn = Instance.new("TextButton")
			feedBtn.Size = UDim2.new(0, 80, 0, 36)
			feedBtn.Position = UDim2.new(1, -90, 0.5, -18)
			feedBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
			feedBtn.Text = "Feed"
			feedBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			feedBtn.Font = Enum.Font.GothamBold
			feedBtn.TextSize = 13
			Instance.new("UICorner", feedBtn).CornerRadius = UDim.new(0, 8)
			feedBtn.Parent = card
			
			feedBtn.MouseButton1Click:Connect(function()
				if FeedPetEvent and currentTargetUUID then
					FeedPetEvent:FireServer(currentTargetUUID, id)
					feedGui.Enabled = false
				end
			end)
		end
	end
	
	feedGui.Enabled = true
end

if FeedUIEvent then
	FeedUIEvent.OnClientEvent:Connect(openFeedMenu)
end
_G.OpenFeedUI = openFeedMenu

-- ══════════════════════════════════════════════════════════
-- 3. ❤️ HEART ANIMATION EFFECT OVER PET
-- ══════════════════════════════════════════════════════════
local function spawnHeartsOverModel(petModel)
	if not petModel then return end
	local prim = petModel.PrimaryPart or petModel:FindFirstChildOfClass("BasePart")
	if not prim then return end
	
	for i = 1, 6 do
		task.delay((i - 1) * 0.12, function()
			if not prim.Parent then return end
			local heartBB = Instance.new("BillboardGui")
			heartBB.Size = UDim2.new(0, 40, 0, 40)
			heartBB.StudsOffset = Vector3.new(math.random(-15, 15) / 10, 2.5, math.random(-15, 15) / 10)
			heartBB.AlwaysOnTop = true
			heartBB.Parent = prim
			
			local heartLbl = Instance.new("TextLabel")
			heartLbl.Size = UDim2.new(1, 0, 1, 0)
			heartLbl.BackgroundTransparency = 1
			heartLbl.Text = "💖"
			heartLbl.TextSize = 14
			heartLbl.Parent = heartBB
			
			local tweenInfo = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local tween = TweenService:Create(heartBB, tweenInfo, {
				StudsOffset = heartBB.StudsOffset + Vector3.new(0, 3, 0)
			})
			local textTween = TweenService:Create(heartLbl, tweenInfo, {
				TextSize = 28,
				TextTransparency = 1
			})
			tween:Play()
			textTween:Play()
			
			task.delay(1.3, function()
				heartBB:Destroy()
			end)
		end)
	end
end

if PetFedEffect then
	PetFedEffect.OnClientEvent:Connect(function(userId, unitUUID)
		local baseName = "Base_" .. tostring(userId)
		local careZone = Workspace:FindFirstChild(baseName) or Workspace:FindFirstChild("PetCareZone")
		if careZone then
			local playerPets = careZone:FindFirstChild("PlayerPets_" .. tostring(userId))
			if playerPets then
				for _, m in ipairs(playerPets:GetChildren()) do
					spawnHeartsOverModel(m)
				end
			end
		end
	end)
end

-- ══════════════════════════════════════════════════════════
-- 4. ⚡ ROBUX BOOSTS SHOP POPUP
-- ══════════════════════════════════════════════════════════
local robuxBtn = Instance.new("TextButton")
robuxBtn.Size = UDim2.new(0, 56, 0, 56)
robuxBtn.Position = UDim2.new(1, -70, 0, 75)
robuxBtn.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
robuxBtn.Text = "⚡\nBOOSTS"
robuxBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
robuxBtn.Font = Enum.Font.GothamBold
robuxBtn.TextSize = 11
Instance.new("UICorner", robuxBtn).CornerRadius = UDim.new(1, 0)
local rStroke = Instance.new("UIStroke", robuxBtn)
rStroke.Color = Color3.fromRGB(255, 200, 100)
rStroke.Thickness = 2
robuxBtn.Parent = screenGui

local robuxGui = feedGui:Clone()
robuxGui.Name = "RobuxShopPopup"
robuxGui.Enabled = false
robuxGui.Parent = PlayerGui

local rBg = robuxGui.Frame
rBg.TextLabel.Text = "⚡ Robux Boosts Shop"
local rClose = rBg.TextButton
rClose.MouseButton1Click:Connect(function() robuxGui.Enabled = false end)

local rScroll = rBg.ScrollingFrame
for _, child in ipairs(rScroll:GetChildren()) do
	if child:IsA("Frame") or child:IsA("TextLabel") then child:Destroy() end
end

local BOOSTS = {
	{ Name = "⚡ 2x EXP Boost (15 Min)", Price = 80, Id = 3709381787, Color = Color3.fromRGB(155, 89, 182) },
	{ Name = "⚡ 2x EXP Boost (30 Min)", Price = 120, Id = 3709382241, Color = Color3.fromRGB(155, 89, 182) },
	{ Name = "⚡ 2x EXP Boost (60 Min)", Price = 160, Id = 3709382324, Color = Color3.fromRGB(155, 89, 182) },
	{ Name = "🧠 2x Coins Boost (15 Min)", Price = 80, Id = 3709382478, Color = Color3.fromRGB(241, 196, 15) },
	{ Name = "🧠 2x Coins Boost (30 Min)", Price = 120, Id = 3709382531, Color = Color3.fromRGB(241, 196, 15) },
	{ Name = "🧠 2x Coins Boost (60 Min)", Price = 160, Id = 3709382572, Color = Color3.fromRGB(241, 196, 15) },
}

for _, b in ipairs(BOOSTS) do
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, -10, 0, 52)
	card.BackgroundColor3 = Color3.fromRGB(32, 38, 52)
	card.Parent = rScroll
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke", card)
	stroke.Color = b.Color
	stroke.Thickness = 1
	
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -110, 1, 0)
	lbl.Position = UDim2.new(0, 10, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = b.Name
	lbl.TextColor3 = b.Color
	lbl.TextSize = 13
	lbl.Font = Enum.Font.GothamBold
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = card
	
	local buyBtn = Instance.new("TextButton")
	buyBtn.Size = UDim2.new(0, 85, 0, 34)
	buyBtn.Position = UDim2.new(1, -95, 0.5, -17)
	buyBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
	buyBtn.Text = "🛒 Buy"
	buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	buyBtn.Font = Enum.Font.GothamBold
	buyBtn.TextSize = 13
	Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 8)
	buyBtn.Parent = card
	
	buyBtn.MouseButton1Click:Connect(function()
		local promptEvent = Events:FindFirstChild("PromptPurchase")
		if promptEvent then
			promptEvent:FireServer(b.Id)
		end
	end)
end

robuxBtn.MouseButton1Click:Connect(function()
	robuxGui.Enabled = not robuxGui.Enabled
end)
