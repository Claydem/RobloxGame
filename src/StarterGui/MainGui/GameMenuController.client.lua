--[[
	ClientMainController.client.lua
	StarterGui.MainGui.ClientMainController
	
	Головний клієнтський контролер UI:
	- Позиціонування вікна БЕЗ перекриття кнопки відкриття/закриття.
	- Анімація відкриття кейсів (Рулетка з поступовим уповільненням).
	- Гарантований захист pcall() та timeout: рулетка ніколи не застрягає.
	- Повна ініціалізація без затримок.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

print("[GameMenuController] Script started! v3")

-- Enable default Roblox leaderboard (User requested original design)
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)
end)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local EventsFolder = ReplicatedStorage:WaitForChild("Events", 10) or ReplicatedStorage:FindFirstChild("Events")
local ModulesFolder = ReplicatedStorage:WaitForChild("Modules", 10) or ReplicatedStorage:FindFirstChild("Modules")

local ItemDatabase = nil
local ModelLoader = nil
if ModulesFolder then
	if ModulesFolder:FindFirstChild("ItemDatabase") then
		ItemDatabase = require(ModulesFolder.ItemDatabase)
	end
	if ModulesFolder:FindFirstChild("ModelLoader") then
		ModelLoader = require(ModulesFolder.ModelLoader)
	end
end

local isBusy = false
local currentInventory = {}
local currentConsumables = {}
local selectedPetForFeedUUID = nil
local selectedAttackZone = nil
local selectedDefenseZone = nil

-- FORCE KILL OLD GHOST SCRIPTS THAT CREATE BANNERS
for _, child in ipairs(PlayerGui:GetDescendants()) do
	if child:IsA("LocalScript") and (child.Name == "MainUIController" or child.Name == "ClientMainController") then
		pcall(function() child.Disabled = true; child:Destroy() end)
	end
end

local screenGui = script:FindFirstAncestorOfClass("ScreenGui")
if not screenGui then
	local found = PlayerGui:FindFirstChild("MainGui")
	if found and found:IsA("ScreenGui") then
		screenGui = found
	end
end

if not screenGui then
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MainGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = PlayerGui
end
screenGui.Enabled = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Destroy duplicate ScreenGuis
for _, child in ipairs(PlayerGui:GetChildren()) do
	if child:IsA("ScreenGui") and child.Name == "MainGui" and child ~= screenGui then
		child:Destroy()
	end
end

-- Clean up leftover UI elements to prevent duplication
for _, child in ipairs(screenGui:GetChildren()) do
	if child:IsA("GuiObject") then
		child:Destroy()
	end
end

local function createCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
	return corner
end

local function createStroke(parent, color, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Color3.fromRGB(60, 60, 80)
	stroke.Thickness = thickness or 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

-- === 1. TOGGLE BUTTON (TOP LEFT — custom placement) ===
local toggleMenuBtn = Instance.new("TextButton")
toggleMenuBtn.Name = "ToggleMenuBtn"
toggleMenuBtn.Size = UDim2.new(0, 160, 0, 42)
toggleMenuBtn.Position = UDim2.new(0, 16, 0, 16)
toggleMenuBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 50)
toggleMenuBtn.Text = "HIDE MENU"
toggleMenuBtn.TextColor3 = Color3.fromRGB(255, 215, 0)
toggleMenuBtn.TextSize = 13
toggleMenuBtn.Font = Enum.Font.GothamBold
toggleMenuBtn.ZIndex = 5000
toggleMenuBtn.Active = true
toggleMenuBtn.Parent = screenGui
createCorner(toggleMenuBtn, 10)
createStroke(toggleMenuBtn, Color3.fromRGB(255, 200, 0), 1.5)

print("[GameMenuController] Toggle button created at Position:", toggleMenuBtn.Position)

-- === 2. MAIN FRAME (Centered on screen — fixed pixel sizing) ===
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 780, 0, 470)
mainFrame.Position = UDim2.new(0.5, -390, 0.5, -220)
mainFrame.BackgroundColor3 = Color3.fromRGB(22, 24, 32)
mainFrame.BorderSizePixel = 0
mainFrame.Visible = true
mainFrame.ZIndex = 1
mainFrame.Parent = screenGui
createCorner(mainFrame, 12)
createStroke(mainFrame, Color3.fromRGB(50, 55, 75), 2)

print("[GameMenuController] MainFrame created, Visible:", mainFrame.Visible)

local currentActiveTab = "Gacha"
local setTab = nil

local function setMenuState(open: boolean)
	mainFrame.Visible = open
	toggleMenuBtn.Text = open and "HIDE MENU" or "OPEN MENU"
	toggleMenuBtn.BackgroundColor3 = open and Color3.fromRGB(30, 35, 50) or Color3.fromRGB(46, 204, 113)
	toggleMenuBtn.TextColor3 = open and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(255, 255, 255)
	if open and setTab then
		setTab(currentActiveTab)
	end
end

toggleMenuBtn.MouseButton1Click:Connect(function()
	setMenuState(not mainFrame.Visible)
end)

-- TopBar
local topBar = Instance.new("Frame")
topBar.Size = UDim2.new(1, 0, 0, 46)
topBar.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
topBar.Parent = mainFrame
createCorner(topBar, 12)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(0, 260, 1, 0)
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "🧠 Brainrot Case & Fight Club"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextSize = 16
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = topBar

local buffLabel = Instance.new("TextLabel")
buffLabel.Size = UDim2.new(0, 220, 0, 30)
buffLabel.Position = UDim2.new(1, -410, 0.5, -15)
buffLabel.BackgroundTransparency = 1
buffLabel.Text = ""
buffLabel.TextColor3 = Color3.fromRGB(46, 204, 113)
buffLabel.TextSize = 11
buffLabel.Font = Enum.Font.GothamMedium
buffLabel.TextXAlignment = Enum.TextXAlignment.Right
buffLabel.Parent = topBar

local currencyFrame = Instance.new("Frame")
currencyFrame.Size = UDim2.new(0, 170, 0, 30)
currencyFrame.Position = UDim2.new(1, -180, 0.5, -15)
currencyFrame.BackgroundColor3 = Color3.fromRGB(32, 35, 45)
currencyFrame.Parent = topBar
createCorner(currencyFrame, 15)
createStroke(currencyFrame, Color3.fromRGB(255, 200, 0), 1)

local currencyLabel = Instance.new("TextLabel")
currencyLabel.Size = UDim2.new(1, -8, 1, 0)
currencyLabel.Position = UDim2.new(0, 4, 0, 0)
currencyLabel.BackgroundTransparency = 1
currencyLabel.Text = "BrainCells: ..."
currencyLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
currencyLabel.TextSize = 13
currencyLabel.Font = Enum.Font.GothamBold
currencyLabel.Parent = currencyFrame

-- Tabs Bar
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -20, 0, 36)
tabBar.Position = UDim2.new(0, 10, 0, 52)
tabBar.BackgroundTransparency = 1
tabBar.Parent = mainFrame

local function createTabButton(name, text, positionX)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.new(0, 180, 1, 0)
	btn.Position = UDim2.new(0, positionX, 0, 0)
	btn.BackgroundColor3 = Color3.fromRGB(35, 40, 52)
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(200, 200, 220)
	btn.TextSize = 12
	btn.Font = Enum.Font.GothamMedium
	btn.Parent = tabBar
	createCorner(btn, 8)
	createStroke(btn, Color3.fromRGB(55, 60, 75), 1)
	return btn
end

local btnGachaTab = createTabButton("GachaTab", "📦 Gacha Cases", 0)
local btnPetTab = createTabButton("PetTab", "🐱 Pets / Care", 190)
local btnShopTab = createTabButton("ShopTab", "🛒 Care Shop", 380)
local btnBattleTab = createTabButton("BattleTab", "⚔️ Fight Club", 570)

-- Content Container
local contentContainer = Instance.new("Frame")
contentContainer.Size = UDim2.new(1, -20, 1, -98)
contentContainer.Position = UDim2.new(0, 10, 0, 92)
contentContainer.BackgroundTransparency = 1
contentContainer.Parent = mainFrame

-- ====== 1. GACHA FRAME ======
local gachaFrame = Instance.new("Frame")
gachaFrame.Size = UDim2.new(1, 0, 1, 0)
gachaFrame.BackgroundTransparency = 1
gachaFrame.Parent = contentContainer

local caseCard = Instance.new("Frame")
caseCard.Size = UDim2.new(0, 320, 0, 280)
caseCard.Position = UDim2.new(0.5, -160, 0.05, 0)
caseCard.BackgroundColor3 = Color3.fromRGB(30, 33, 44)
caseCard.Parent = gachaFrame
createCorner(caseCard, 12)
createStroke(caseCard, Color3.fromRGB(255, 170, 0), 2)

local caseTitle = Instance.new("TextLabel")
caseTitle.Size = UDim2.new(1, 0, 0, 40)
caseTitle.BackgroundTransparency = 1
caseTitle.Text = "🎰 Brainrot Case"
caseTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
caseTitle.TextSize = 18
caseTitle.Font = Enum.Font.GothamBold
caseTitle.Parent = caseCard

local resultDisplay = Instance.new("TextLabel")
resultDisplay.Size = UDim2.new(1, -20, 0, 120)
resultDisplay.Position = UDim2.new(0, 10, 0, 50)
resultDisplay.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
resultDisplay.Text = "Click the button below!\nPrice: 50 🧠"
resultDisplay.TextColor3 = Color3.fromRGB(200, 200, 220)
resultDisplay.TextSize = 13
resultDisplay.Font = Enum.Font.GothamMedium
resultDisplay.TextWrapped = true
resultDisplay.Parent = caseCard
createCorner(resultDisplay, 8)
createStroke(resultDisplay, Color3.fromRGB(45, 50, 65), 1)

local btnOpenCase = Instance.new("TextButton")
btnOpenCase.Size = UDim2.new(1, -24, 0, 45)
btnOpenCase.Position = UDim2.new(0, 12, 1, -58)
btnOpenCase.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
btnOpenCase.Text = "OPEN CASE (50 🧠)"
btnOpenCase.TextColor3 = Color3.fromRGB(255, 255, 255)
btnOpenCase.TextSize = 14
btnOpenCase.Font = Enum.Font.GothamBold
btnOpenCase.Parent = caseCard
createCorner(btnOpenCase, 8)

-- ====== 2. PET FRAME ======
local petFrame = Instance.new("Frame")
petFrame.Size = UDim2.new(1, 0, 1, 0)
petFrame.BackgroundTransparency = 1
petFrame.Visible = false
petFrame.Parent = contentContainer

local petScroll = Instance.new("ScrollingFrame")
petScroll.Size = UDim2.new(1, 0, 1, 0)
petScroll.BackgroundTransparency = 1
petScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
petScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
petScroll.ScrollBarThickness = 6
petScroll.Parent = petFrame
Instance.new("UIListLayout", petScroll).Padding = UDim.new(0, 8)

-- ====== 3. SHOP FRAME ======
local shopFrame = Instance.new("Frame")
shopFrame.Size = UDim2.new(1, 0, 1, 0)
shopFrame.BackgroundTransparency = 1
shopFrame.Visible = false
shopFrame.Parent = contentContainer

local shopScroll = Instance.new("ScrollingFrame")
shopScroll.Size = UDim2.new(1, 0, 1, 0)
shopScroll.BackgroundTransparency = 1
shopScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
shopScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
shopScroll.ScrollBarThickness = 6
shopScroll.Parent = shopFrame
Instance.new("UIListLayout", shopScroll).Padding = UDim.new(0, 8)

-- ====== 4. BATTLE FRAME ======
local battleFrame = Instance.new("Frame")
battleFrame.Size = UDim2.new(1, 0, 1, 0)
battleFrame.BackgroundTransparency = 1
battleFrame.Visible = false
battleFrame.Parent = contentContainer

local lobbySubFrame = Instance.new("Frame")
lobbySubFrame.Size = UDim2.new(1, 0, 1, 0)
lobbySubFrame.BackgroundTransparency = 1
lobbySubFrame.Parent = battleFrame

local btnStartBattle = Instance.new("TextButton")
btnStartBattle.Size = UDim2.new(0, 260, 0, 48)
btnStartBattle.Position = UDim2.new(0.5, -130, 0.20, 0)
btnStartBattle.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
btnStartBattle.Text = "⚔️ BATTLE"
btnStartBattle.TextColor3 = Color3.fromRGB(255, 255, 255)
btnStartBattle.TextSize = 17
btnStartBattle.Font = Enum.Font.GothamBlack
btnStartBattle.Parent = lobbySubFrame
createCorner(btnStartBattle, 10)
createStroke(btnStartBattle, Color3.fromRGB(255, 215, 0), 2)

local battleHint = Instance.new("TextLabel")
battleHint.Size = UDim2.new(0, 300, 0, 20)
battleHint.Position = UDim2.new(0.5, -150, 0.20, 50)
battleHint.BackgroundTransparency = 1
battleHint.Text = "⚡ PvP Matchmaking with players"
battleHint.TextColor3 = Color3.fromRGB(180, 185, 205)
battleHint.TextSize = 11
battleHint.Font = Enum.Font.GothamMedium
battleHint.Parent = lobbySubFrame

local btnStartBotBattle = Instance.new("TextButton")
btnStartBotBattle.Size = UDim2.new(0, 260, 0, 48)
btnStartBotBattle.Position = UDim2.new(0.5, -130, 0.52, 0)
btnStartBotBattle.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
btnStartBotBattle.Text = "🤖 BATTLE VS BOT"
btnStartBotBattle.TextColor3 = Color3.fromRGB(255, 255, 255)
btnStartBotBattle.TextSize = 16
btnStartBotBattle.Font = Enum.Font.GothamBold
btnStartBotBattle.Parent = lobbySubFrame
createCorner(btnStartBotBattle, 10)
createStroke(btnStartBotBattle, Color3.fromRGB(255, 100, 80), 1.5)

local botHint = Instance.new("TextLabel")
botHint.Size = UDim2.new(0, 300, 0, 20)
botHint.Position = UDim2.new(0.5, -150, 0.52, 50)
botHint.BackgroundTransparency = 1
botHint.Text = "🎯 Solo training match against AI"
botHint.TextColor3 = Color3.fromRGB(180, 185, 205)
botHint.TextSize = 11
botHint.Font = Enum.Font.GothamMedium
botHint.Parent = lobbySubFrame

local arenaSubFrame = Instance.new("Frame")
arenaSubFrame.Size = UDim2.new(1, 0, 1, 0)
arenaSubFrame.BackgroundTransparency = 1
arenaSubFrame.Visible = false
arenaSubFrame.Parent = battleFrame

local p1HPLabel = Instance.new("TextLabel")
p1HPLabel.Size = UDim2.new(0, 220, 0, 36)
p1HPLabel.Position = UDim2.new(0, 8, 0, 0)
p1HPLabel.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
p1HPLabel.Text = "You: 100 HP"
p1HPLabel.TextColor3 = Color3.fromRGB(46, 204, 113)
p1HPLabel.TextSize = 13
p1HPLabel.Font = Enum.Font.GothamBold
p1HPLabel.Parent = arenaSubFrame
createCorner(p1HPLabel, 8)

local p2HPLabel = Instance.new("TextLabel")
p2HPLabel.Size = UDim2.new(0, 220, 0, 36)
p2HPLabel.Position = UDim2.new(1, -228, 0, 0)
p2HPLabel.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
p2HPLabel.Text = "Bot: 100 HP"
p2HPLabel.TextColor3 = Color3.fromRGB(231, 76, 60)
p2HPLabel.TextSize = 13
p2HPLabel.Font = Enum.Font.GothamBold
p2HPLabel.Parent = arenaSubFrame
createCorner(p2HPLabel, 8)

local battleLogLabel = Instance.new("TextLabel")
battleLogLabel.Size = UDim2.new(1, -16, 0, 55)
battleLogLabel.Position = UDim2.new(0, 8, 0, 44)
battleLogLabel.BackgroundColor3 = Color3.fromRGB(14, 16, 22)
battleLogLabel.Text = "Select ATTACK and DEFENSE..."
battleLogLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
battleLogLabel.TextSize = 11
battleLogLabel.Font = Enum.Font.Gotham
battleLogLabel.TextWrapped = true
battleLogLabel.Parent = arenaSubFrame
createCorner(battleLogLabel, 8)

local attackPanel = Instance.new("Frame")
attackPanel.Size = UDim2.new(0.48, 0, 0, 130)
attackPanel.Position = UDim2.new(0, 8, 0, 108)
attackPanel.BackgroundColor3 = Color3.fromRGB(26, 30, 40)
attackPanel.Parent = arenaSubFrame
createCorner(attackPanel, 8)

local defensePanel = Instance.new("Frame")
defensePanel.Size = UDim2.new(0.48, 0, 0, 130)
defensePanel.Position = UDim2.new(0.52, 0, 0, 108)
defensePanel.BackgroundColor3 = Color3.fromRGB(26, 30, 40)
defensePanel.Parent = arenaSubFrame
createCorner(defensePanel, 8)

local attackButtons, defenseButtons = {}, {}
local zoneNames = {"Head", "Torso", "Legs"}
for i, zName in ipairs(zoneNames) do
	local abtn = Instance.new("TextButton")
	abtn.Size = UDim2.new(1, -16, 0, 28)
	abtn.Position = UDim2.new(0, 8, 0, 26 + (i - 1) * 32)
	abtn.BackgroundColor3 = Color3.fromRGB(42, 48, 62)
	abtn.Text = "🎯 " .. zName
	abtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	abtn.TextSize = 12
	abtn.Font = Enum.Font.Gotham
	abtn.Parent = attackPanel
	createCorner(abtn, 6)
	attackButtons[zName] = abtn

	local dbtn = Instance.new("TextButton")
	dbtn.Size = UDim2.new(1, -16, 0, 28)
	dbtn.Position = UDim2.new(0, 8, 0, 26 + (i - 1) * 32)
	dbtn.BackgroundColor3 = Color3.fromRGB(42, 48, 62)
	dbtn.Text = "🛡️ " .. zName
	dbtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	dbtn.TextSize = 12
	dbtn.Font = Enum.Font.Gotham
	dbtn.Parent = defensePanel
	createCorner(dbtn, 6)
	defenseButtons[zName] = dbtn
end

local btnSubmitTurn = Instance.new("TextButton")
btnSubmitTurn.Size = UDim2.new(1, -16, 0, 42)
btnSubmitTurn.Position = UDim2.new(0, 8, 1, -48)
btnSubmitTurn.BackgroundColor3 = Color3.fromRGB(155, 89, 182)
btnSubmitTurn.Text = "CONFIRM TURN"
btnSubmitTurn.TextColor3 = Color3.fromRGB(255, 255, 255)
btnSubmitTurn.TextSize = 14
btnSubmitTurn.Font = Enum.Font.GothamBold
btnSubmitTurn.Parent = arenaSubFrame
createCorner(btnSubmitTurn, 8)

-- Tab Switcher
setTab = function(tabName)
	currentActiveTab = tabName or "Gacha"
	gachaFrame.Visible = (currentActiveTab == "Gacha")
	petFrame.Visible = (currentActiveTab == "Pets")
	shopFrame.Visible = (currentActiveTab == "Shop")
	battleFrame.Visible = (currentActiveTab == "Battle")

	-- Закриваємо Inspection Panel при переключенні вкладок
	if inspectionPanel and inspectionPanel.Visible then
		inspectionPanel.Visible = false
		for _, c in ipairs(inspectionPanel:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
	end

	btnGachaTab.BackgroundColor3 = (currentActiveTab == "Gacha") and Color3.fromRGB(55, 65, 85) or Color3.fromRGB(35, 40, 52)
	btnPetTab.BackgroundColor3 = (currentActiveTab == "Pets") and Color3.fromRGB(55, 65, 85) or Color3.fromRGB(35, 40, 52)
	btnShopTab.BackgroundColor3 = (currentActiveTab == "Shop") and Color3.fromRGB(55, 65, 85) or Color3.fromRGB(35, 40, 52)
	btnBattleTab.BackgroundColor3 = (currentActiveTab == "Battle") and Color3.fromRGB(55, 65, 85) or Color3.fromRGB(35, 40, 52)
end

btnGachaTab.MouseButton1Click:Connect(function() setTab("Gacha") end)
btnPetTab.MouseButton1Click:Connect(function() setTab("Pets") end)
btnShopTab.MouseButton1Click:Connect(function() setTab("Shop") end)
btnBattleTab.MouseButton1Click:Connect(function() setTab("Battle") end)

-- Leaderstats Binding
task.spawn(function()
	local leaderstats = LocalPlayer:WaitForChild("leaderstats", 15)
	if leaderstats then
		local brainCellsVal = leaderstats:WaitForChild("BrainCells", 10)
		if brainCellsVal then
			local function updateCurrency()
				currencyLabel.Text = "BrainCells: " .. tostring(brainCellsVal.Value)
			end
			brainCellsVal.Changed:Connect(updateCurrency)
			updateCurrency()
		end
	end
end)

-- ═══════════════════════════════════════════════════════
--  GLOBAL CASE UNBOXED BROADCAST
-- ═══════════════════════════════════════════════════════

-- 3. Глобальне сповіщення про відкриття кейсів для ВСІХ гравців
local GlobalCaseUnboxedEvent = EventsFolder:WaitForChild("GlobalCaseUnboxed", 10) or EventsFolder:FindFirstChild("GlobalCaseUnboxed")

if GlobalCaseUnboxedEvent then
	GlobalCaseUnboxedEvent.OnClientEvent:Connect(function(unboxingPlayerName, unboxingUserId, itemData)
		print(string.format("[GlobalUnbox] 📦 %s unboxed %s [%s] (%s)", unboxingPlayerName, tostring(itemData.Name), tostring(itemData.Class or "Normal"), tostring(itemData.Rarity or "Common")))

		-- Banner removed
		

		-- 2. Якщо в Хабі є GachaStation — показуємо 3D ефект на п'єдесталі
		local hub = workspace:FindFirstChild("Hub")
		local gachaStation = hub and hub:FindFirstChild("GachaStation")
		local pedestal = gachaStation and gachaStation:FindFirstChild("CasePedestal")
		if pedestal and ModelLoader and ModelLoader.LoadModel then
			task.spawn(function()
				local showcaseModel = ModelLoader.LoadModel(itemData.Id, itemData.Class or "Normal")
				if showcaseModel then
					showcaseModel.Name = "Showcase_" .. unboxingPlayerName
					showcaseModel.Parent = gachaStation
					if showcaseModel.PrimaryPart then
						showcaseModel:SetPrimaryPartCFrame(CFrame.new(pedestal.Position + Vector3.new(0, 4, 0)))
					end

					-- Обертання 3D моделі протягом 6 секунд
					local spinConn
					local tStart = os.clock()
					spinConn = game:GetService("RunService").RenderStepped:Connect(function()
						if showcaseModel and showcaseModel.Parent and showcaseModel.PrimaryPart then
							local angle = (os.clock() - tStart) * 3
							showcaseModel:SetPrimaryPartCFrame(CFrame.new(pedestal.Position + Vector3.new(0, 4 + math.sin(angle * 2) * 0.5, 0)) * CFrame.Angles(0, angle, 0))
						else
							if spinConn then spinConn:Disconnect() end
						end
					end)

					task.delay(6, function()
						if spinConn then spinConn:Disconnect() end
						if showcaseModel and showcaseModel.Parent then
							showcaseModel:Destroy()
						end
					end)
				end
			end)
		end
	end)
end

-- (Duel system handled in DuelController.client.lua)
-- Async Server Events Binding
task.spawn(function()
	if not EventsFolder then
		warn("[ClientMainController] Events folder missing!")
		return
	end

	local OpenCaseFunc = EventsFolder:WaitForChild("OpenCase", 5) :: RemoteFunction
	local StartBattleFunc = EventsFolder:WaitForChild("StartBattle", 5) :: RemoteFunction
	local SubmitTurnEvent = EventsFolder:WaitForChild("SubmitBattleTurn", 5) :: RemoteEvent
	local BattleStateUpdate = EventsFolder:WaitForChild("BattleStateUpdate", 5) :: RemoteEvent
	local InventoryUpdate = EventsFolder:WaitForChild("InventoryUpdate", 5) :: RemoteEvent
	local BuyShopItemFunc = EventsFolder:WaitForChild("BuyShopItem", 5) :: RemoteFunction
	local UseShopItemFunc = EventsFolder:WaitForChild("UseShopItem", 5) :: RemoteFunction
	local ConsumablesUpdate = EventsFolder:WaitForChild("ConsumablesUpdate", 5) :: RemoteEvent
	local BuffStateUpdate = EventsFolder:WaitForChild("BuffStateUpdate", 5) :: RemoteEvent
	local ToggleEquipPetEvent = EventsFolder:WaitForChild("ToggleEquipPet", 5) :: RemoteEvent
	local RosterErrorEvent = EventsFolder:FindFirstChild("RosterError") :: RemoteEvent
	local RosterUpdateEvent = EventsFolder:FindFirstChild("RosterUpdate") :: RemoteEvent

	-- Inspection panel як TextButton — поглинає всі кліки і не пропускає їх крізь себе
	local inspectionPanel = Instance.new("TextButton")
	inspectionPanel.Size = UDim2.new(1, 0, 1, 0)
	inspectionPanel.Position = UDim2.new(0, 0, 0, 0)
	inspectionPanel.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	inspectionPanel.BackgroundTransparency = 0.05
	inspectionPanel.Text = ""
	inspectionPanel.AutoButtonColor = false
	inspectionPanel.ZIndex = 10
	inspectionPanel.Visible = false
	inspectionPanel.Parent = petScroll.Parent -- same parent as petScroll
	createCorner(inspectionPanel, 12)

	local function closeInspectionPanel()
		inspectionPanel.Visible = false
		for _, c in ipairs(inspectionPanel:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
	end

	local function showInspectionPanel(unit, stats, activeCount, maxCount)
		-- Clear previous content
		for _, c in ipairs(inspectionPanel:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		inspectionPanel.Visible = true

		local rarityColor = stats.RarityConfig and stats.RarityConfig.Color or Color3.fromRGB(180, 180, 180)
		local classColor = stats.ClassConfig and stats.ClassConfig.Color or Color3.fromRGB(220, 220, 220)
		local rarityIcon = stats.RarityConfig and stats.RarityConfig.Icon or "⚪"
		local classIcon = stats.ClassConfig and stats.ClassConfig.AbilityIcon or ""
		local level = unit.Level or 1
		local xp = unit.XP or 0
		local maxXP = stats.MaxXP or 100
		local xpRemaining = math.max(0, maxXP - xp)
		local progressPct = math.clamp(xp / math.max(1, maxXP), 0, 1)

		-- Name + Rarity + Class header
		local headerFrame = Instance.new("Frame")
		headerFrame.Size = UDim2.new(1, -16, 0, 48)
		headerFrame.Position = UDim2.new(0, 8, 0, 8)
		headerFrame.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
		headerFrame.ZIndex = 11
		headerFrame.Parent = inspectionPanel
		createCorner(headerFrame, 10)
		createStroke(headerFrame, rarityColor, 2)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -50, 0, 24)
		nameLabel.Position = UDim2.new(0, 12, 0, 2)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = rarityIcon .. " " .. (stats.Name or unit.ItemId)
		nameLabel.TextColor3 = rarityColor
		nameLabel.TextSize = 16
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.ZIndex = 12
		nameLabel.Parent = headerFrame

		local classLabel = Instance.new("TextLabel")
		classLabel.Size = UDim2.new(1, -12, 0, 20)
		classLabel.Position = UDim2.new(0, 12, 0, 24)
		classLabel.BackgroundTransparency = 1
		classLabel.Text = string.format("%s [%s]  %s", classIcon, (stats.Class or "Normal"):upper(), stats.RarityConfig and stats.RarityConfig.Name or "Common")
		classLabel.TextColor3 = classColor
		classLabel.TextSize = 11
		classLabel.Font = Enum.Font.GothamMedium
		classLabel.TextXAlignment = Enum.TextXAlignment.Left
		classLabel.ZIndex = 12
		classLabel.Parent = headerFrame
		
		-- Massive Close button (Fixes "cannot go back" bug)
		local closeBtn = Instance.new("TextButton")
		closeBtn.Size = UDim2.new(0, 44, 0, 44)
		closeBtn.Position = UDim2.new(1, -52, 0, 10)
		closeBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
		closeBtn.Text = "X"
		closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		closeBtn.TextSize = 20
		closeBtn.Font = Enum.Font.GothamBold
		closeBtn.ZIndex = 100 -- Extremely high ZIndex to prevent overlap issues
		closeBtn.Parent = inspectionPanel
		createCorner(closeBtn, 8)
		closeBtn.MouseButton1Click:Connect(closeInspectionPanel)

		-- 3D Viewport for Pet Model
		local viewportFrame = Instance.new("ViewportFrame")
		viewportFrame.Size = UDim2.new(1, -16, 0, 130)
		viewportFrame.Position = UDim2.new(0, 8, 0, 64)
		viewportFrame.BackgroundColor3 = Color3.fromRGB(15, 18, 26)
		viewportFrame.ZIndex = 11
		viewportFrame.Parent = inspectionPanel
		createCorner(viewportFrame, 10)
		createStroke(viewportFrame, Color3.fromRGB(40, 45, 60), 1)

		local camera = Instance.new("Camera")
		camera.FieldOfView = 50
		viewportFrame.CurrentCamera = camera
		viewportFrame.LightColor = Color3.fromRGB(255, 255, 255)
		viewportFrame.Ambient = Color3.fromRGB(150, 150, 150)

		-- Load model into viewport
		if ModelLoader and ModelLoader.LoadModel then
			local petModel = ModelLoader.LoadModel(unit.ItemId, stats.Class or "Normal")
			if petModel then
				petModel.Parent = viewportFrame
				if petModel.PrimaryPart then
					local cf = petModel.PrimaryPart.CFrame
					local targetPos = cf.Position + (cf.LookVector * 4) + Vector3.new(0, 1.5, 0)
					camera.CFrame = CFrame.new(targetPos, cf.Position)
					
					-- Simple idle rotation animation
					task.spawn(function()
						local t = 0
						while viewportFrame.Parent and petModel.Parent do
							t = t + wait()
							local rot = CFrame.Angles(0, t * 1.5, 0)
							petModel:SetPrimaryPartCFrame(cf * rot)
						end
					end)
				end
			end
		end

		-- Stats grid
		local statsFrame = Instance.new("Frame")
		statsFrame.Size = UDim2.new(1, -16, 0, 60)
		statsFrame.Position = UDim2.new(0, 8, 0, 202)
		statsFrame.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
		statsFrame.ZIndex = 11
		statsFrame.Parent = inspectionPanel
		createCorner(statsFrame, 10)

		local statsData = {
			{ icon = "❤️", label = "HP",     value = tostring(stats.MaxHP or 0) },
			{ icon = "⚔️",  label = "Damage", value = tostring(stats.Damage or 0) },
			{ icon = "🌟", label = "GPS",    value = "+"..tostring(stats.IncomeRate or 0).."/5s" },
			{ icon = "🍗", label = "Hunger", value = tostring(unit.Hunger or 100) .. "%" },
		}
		for i, sd in ipairs(statsData) do
			local col = (i - 1) % 2
			local row = math.floor((i - 1) / 2)
			local statBlock = Instance.new("Frame")
			statBlock.Size = UDim2.new(0.5, -8, 0, 26)
			statBlock.Position = UDim2.new(col * 0.5, col == 0 and 6 or 2, 0, 6 + row * 28)
			statBlock.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
			statBlock.ZIndex = 12
			statBlock.Parent = statsFrame
			createCorner(statBlock, 6)

			local statText = Instance.new("TextLabel")
			statText.Size = UDim2.new(1, 0, 1, 0)
			statText.BackgroundTransparency = 1
			statText.Text = sd.icon .. " " .. sd.label .. ": " .. sd.value
			statText.TextColor3 = Color3.fromRGB(220, 225, 240)
			statText.TextSize = 11
			statText.Font = Enum.Font.GothamBold
			statText.ZIndex = 13
			statText.Parent = statBlock
		end

		-- Class ability description
		local perkFrame = Instance.new("Frame")
		perkFrame.Size = UDim2.new(1, -16, 0, 40)
		perkFrame.Position = UDim2.new(0, 8, 0, 270)
		perkFrame.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
		perkFrame.ZIndex = 11
		perkFrame.Parent = inspectionPanel
		createCorner(perkFrame, 10)
		createStroke(perkFrame, classColor, 1)

		local perkText = Instance.new("TextLabel")
		perkText.Size = UDim2.new(1, -12, 1, 0)
		perkText.Position = UDim2.new(0, 6, 0, 0)
		perkText.BackgroundTransparency = 1
		perkText.Text = classIcon .. " " .. (stats.ClassConfig and stats.ClassConfig.Perk or "Standard fighter. No special effects.")
		perkText.TextColor3 = classColor
		perkText.TextSize = 10
		perkText.Font = Enum.Font.GothamMedium
		perkText.TextWrapped = true
		perkText.TextXAlignment = Enum.TextXAlignment.Left
		perkText.ZIndex = 12
		perkText.Parent = perkFrame

		-- XP bar
		local xpTrack = Instance.new("Frame")
		xpTrack.Size = UDim2.new(1, -16, 0, 22)
		xpTrack.Position = UDim2.new(0, 8, 0, 318)
		xpTrack.BackgroundColor3 = Color3.fromRGB(15, 18, 25)
		xpTrack.ZIndex = 11
		xpTrack.Parent = inspectionPanel
		createCorner(xpTrack, 8)
		createStroke(xpTrack, Color3.fromRGB(50, 55, 75), 1)

		local xpFill = Instance.new("Frame")
		xpFill.Size = UDim2.new(progressPct, 0, 1, 0)
		xpFill.BackgroundColor3 = Color3.fromRGB(155, 89, 182)
		xpFill.ZIndex = 12
		xpFill.Parent = xpTrack
		createCorner(xpFill, 8)

		local xpLabel = Instance.new("TextLabel")
		xpLabel.Size = UDim2.new(1, 0, 1, 0)
		xpLabel.BackgroundTransparency = 1
		xpLabel.Text = string.format("Lv.%d  XP: %d / %d  (%d to Lv.%d)", level, xp, maxXP, xpRemaining, level + 1)
		xpLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		xpLabel.TextSize = 9
		xpLabel.Font = Enum.Font.GothamBold
		xpLabel.ZIndex = 13
		xpLabel.Parent = xpTrack

		-- Roster & Feed buttons
		local canAdd = not unit.Equipped and (activeCount < maxCount)
		local isFull = not unit.Equipped and (activeCount >= maxCount)
		local btnColor = unit.Equipped and Color3.fromRGB(180, 60, 60) or (canAdd and Color3.fromRGB(46, 160, 80) or Color3.fromRGB(70, 75, 90))
		local btnText = unit.Equipped and "✖ Care Zone" or (canAdd and "🏡 Care Zone" or "🚫 Full")

		local rosterBtn = Instance.new("TextButton")
		rosterBtn.Size = UDim2.new(0.5, -10, 0, 38)
		rosterBtn.Position = UDim2.new(0, 8, 0, 348)
		rosterBtn.BackgroundColor3 = btnColor
		rosterBtn.Text = btnText
		rosterBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		rosterBtn.TextSize = 12
		rosterBtn.Font = Enum.Font.GothamBold
		rosterBtn.ZIndex = 15
		rosterBtn.Active = unit.Equipped or canAdd
		rosterBtn.Parent = inspectionPanel
		createCorner(rosterBtn, 10)

		local feedBtn = Instance.new("TextButton")
		feedBtn.Size = UDim2.new(0.5, -10, 0, 38)
		feedBtn.Position = UDim2.new(0.5, 2, 0, 348)
		feedBtn.BackgroundColor3 = Color3.fromRGB(230, 126, 34)
		feedBtn.Text = "🍖 Feed"
		feedBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		feedBtn.TextSize = 13
		feedBtn.Font = Enum.Font.GothamBold
		feedBtn.ZIndex = 15
		feedBtn.Parent = inspectionPanel
		createCorner(feedBtn, 10)

		feedBtn.MouseButton1Click:Connect(function()
			if _G.OpenFeedUI then
				_G.OpenFeedUI(unit.UUID)
			else
				local ev = EventsFolder:FindFirstChild("PromptFeedUI")
				if ev then
					local feedEv = EventsFolder:FindFirstChild("FeedPet")
					if feedEv then
						feedEv:FireServer(unit.UUID, "basic_food")
					end
				end
			end
		end)

		-- Active counter label
		local counterLbl = Instance.new("TextLabel")
		counterLbl.Size = UDim2.new(1, -16, 0, 20)
		counterLbl.Position = UDim2.new(0, 8, 0, 390)
		counterLbl.BackgroundTransparency = 1
		counterLbl.Text = string.format("🏡 Active: %d / %d", activeCount, maxCount)
		counterLbl.TextColor3 = activeCount >= maxCount and Color3.fromRGB(231, 76, 60) or Color3.fromRGB(46, 204, 113)
		counterLbl.TextSize = 12
		counterLbl.Font = Enum.Font.GothamBold
		counterLbl.ZIndex = 11
		counterLbl.Parent = inspectionPanel

		rosterBtn.MouseButton1Click:Connect(function()
			if not (unit.Equipped or canAdd) then return end
			if ToggleEquipPetEvent then
				ToggleEquipPetEvent:FireServer(unit.UUID)
				closeInspectionPanel()
			end
		end)
	end

	-- Render Pets Inventory
	local function renderInventory(inv)
		if inv ~= nil then
			currentInventory = inv
		end
		currentInventory = currentInventory or {}

		for _, child in ipairs(petScroll:GetChildren()) do
			if child:IsA("GuiObject") and not child:IsA("UIListLayout") and not child:IsA("UIGridLayout") then
				child:Destroy()
			end
		end

		-- Count Care Zone active slots
		local activeCount = 0
		for _, u in ipairs(currentInventory) do
			if u.Equipped then activeCount = activeCount + 1 end
		end
		local MAX_CARE_ZONE = 12

		local counterHeader = Instance.new("TextLabel")
		counterHeader.Size = UDim2.new(1, -8, 0, 30)
		counterHeader.BackgroundTransparency = 1
		counterHeader.Text = string.format("🏡 Care Zone Active: %d / %d", activeCount, MAX_CARE_ZONE)
		counterHeader.TextColor3 = Color3.fromRGB(200, 205, 220)
		counterHeader.TextSize = 14
		counterHeader.Font = Enum.Font.GothamBold
		counterHeader.Parent = petScroll

		local itemDB = ItemDatabase or (ModulesFolder and ModulesFolder:FindFirstChild("ItemDatabase") and require(ModulesFolder.ItemDatabase))
		if not itemDB then return end

		-- Sort inventory alphabetically by Name (A-Z)
		local sortedInventory = {}
		for _, u in ipairs(currentInventory) do
			table.insert(sortedInventory, u)
		end
		table.sort(sortedInventory, function(a, b)
			local statsA = itemDB.GetUnitStats and itemDB.GetUnitStats(a) or itemDB.GetItem(a.ItemId)
			local statsB = itemDB.GetUnitStats and itemDB.GetUnitStats(b) or itemDB.GetItem(b.ItemId)
			local nameA = (statsA and statsA.Name) or a.ItemId or ""
			local nameB = (statsB and statsB.Name) or b.ItemId or ""
			return string.lower(nameA) < string.lower(nameB)
		end)

		-- Compact clickable cards
		for _, unit in ipairs(sortedInventory) do
			local stats = itemDB.GetUnitStats and itemDB.GetUnitStats(unit) or itemDB.GetItem(unit.ItemId)
			if not stats then continue end

			local card = Instance.new("TextButton")
			card.Size = UDim2.new(1, -8, 0, 56)
			card.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
			card.Text = ""
			card.AutoButtonColor = false
			card.Parent = petScroll
			createCorner(card, 10)
			local rarityColor = stats.RarityConfig and stats.RarityConfig.Color or Color3.fromRGB(60, 65, 80)
			local classColor = stats.ClassConfig and stats.ClassConfig.Color or Color3.fromRGB(220, 220, 220)
			createStroke(card, unit.Equipped and rarityColor or Color3.fromRGB(50, 55, 70), unit.Equipped and 1.5 or 1)

			-- Status dot
			local statusDot = Instance.new("TextLabel")
			statusDot.Size = UDim2.new(0, 32, 0, 32)
			statusDot.Position = UDim2.new(0, 8, 0.5, -16)
			statusDot.BackgroundColor3 = unit.Equipped and Color3.fromRGB(46, 204, 113) or Color3.fromRGB(50, 55, 70)
			statusDot.Text = unit.Equipped and "✅" or "📦"
			statusDot.TextSize = 14
			statusDot.Font = Enum.Font.GothamBold
			statusDot.TextColor3 = Color3.fromRGB(255, 255, 255)
			statusDot.Parent = card
			createCorner(statusDot, 8)

			-- Name + class
			local rarityIcon = stats.RarityConfig and stats.RarityConfig.Icon or "⚪"
			local classIcon = stats.ClassConfig and stats.ClassConfig.AbilityIcon or ""
			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(1, -120, 0, 22)
			nameLabel.Position = UDim2.new(0, 50, 0, 8)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = rarityIcon .. " " .. (stats.Name or unit.ItemId) .. " " .. classIcon
			nameLabel.TextColor3 = classColor
			nameLabel.TextSize = 13
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Parent = card

			-- Level + stats mini
			local level = unit.Level or 1
			local infoLabel = Instance.new("TextLabel")
			infoLabel.Size = UDim2.new(1, -120, 0, 18)
			infoLabel.Position = UDim2.new(0, 50, 0, 30)
			infoLabel.BackgroundTransparency = 1
			infoLabel.Text = string.format("Lv.%d  ⚔️%d  ❤️%d  🌟+%d/5s  🍗%d%%", level, stats.Damage or 0, stats.MaxHP or 0, stats.IncomeRate or 0, unit.Hunger or 100)
			infoLabel.TextColor3 = Color3.fromRGB(160, 165, 185)
			infoLabel.TextSize = 9
			infoLabel.Font = Enum.Font.GothamMedium
			infoLabel.TextXAlignment = Enum.TextXAlignment.Left
			infoLabel.Parent = card

			-- "Inspect" arrow hint
			local arrowBtn = Instance.new("TextLabel")
			arrowBtn.Size = UDim2.new(0, 30, 0, 30)
			arrowBtn.Position = UDim2.new(1, -36, 0.5, -15)
			arrowBtn.BackgroundTransparency = 1
			arrowBtn.Text = "›"
			arrowBtn.TextColor3 = Color3.fromRGB(100, 110, 140)
			arrowBtn.TextSize = 24
			arrowBtn.Font = Enum.Font.GothamBold
			arrowBtn.Parent = card

			-- Click opens inspection panel
			local capturedUnit = unit
			local capturedStats = stats
			card.MouseButton1Click:Connect(function()
				showInspectionPanel(capturedUnit, capturedStats, activeCount, MAX_CARE_ZONE)
			end)
		end
	end

	-- Render Care Shop
	local function renderShop()
		for _, child in ipairs(shopScroll:GetChildren()) do
			if child:IsA("Frame") then child:Destroy() end
		end

		if not ItemDatabase then return end

		for itemId, itemConfig in pairs(ItemDatabase.ShopItems) do
			local card = Instance.new("Frame")
			card.Size = UDim2.new(1, -8, 0, 70)
			card.BackgroundColor3 = Color3.fromRGB(30, 34, 44)
			card.Parent = shopScroll
			createCorner(card, 8)

			local title = Instance.new("TextLabel")
			title.Size = UDim2.new(0, 260, 0, 22)
			title.Position = UDim2.new(0, 12, 0, 6)
			title.BackgroundTransparency = 1
			title.Text = itemConfig.Icon .. " " .. itemConfig.Name
			title.TextColor3 = Color3.fromRGB(255, 255, 255)
			title.TextSize = 14
			title.Font = Enum.Font.GothamBold
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.Parent = card

			local desc = Instance.new("TextLabel")
			desc.Size = UDim2.new(0, 380, 0, 30)
			desc.Position = UDim2.new(0, 12, 0, 30)
			desc.BackgroundTransparency = 1
			desc.Text = itemConfig.Description
			desc.TextColor3 = Color3.fromRGB(160, 160, 180)
			desc.TextSize = 10
			desc.Font = Enum.Font.Gotham
			desc.TextXAlignment = Enum.TextXAlignment.Left
			desc.TextWrapped = true
			desc.Parent = card

			local count = currentConsumables[itemId] or 0

			local btnBuy = Instance.new("TextButton")
			btnBuy.Size = UDim2.new(0, 110, 0, 28)
			btnBuy.Position = UDim2.new(1, -240, 0.5, -14)
			btnBuy.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
			btnBuy.Text = string.format("Buy (%d🧠)", itemConfig.Price)
			btnBuy.TextColor3 = Color3.fromRGB(255, 255, 255)
			btnBuy.TextSize = 11
			btnBuy.Font = Enum.Font.GothamBold
			btnBuy.Parent = card
			createCorner(btnBuy, 6)

			local btnUse = Instance.new("TextButton")
			btnUse.Size = UDim2.new(0, 110, 0, 28)
			btnUse.Position = UDim2.new(1, -120, 0.5, -14)
			btnUse.BackgroundColor3 = count > 0 and Color3.fromRGB(52, 152, 219) or Color3.fromRGB(80, 80, 90)
			btnUse.Text = string.format("Use (%d)", count)
			btnUse.TextColor3 = Color3.fromRGB(255, 255, 255)
			btnUse.TextSize = 11
			btnUse.Font = Enum.Font.GothamBold
			btnUse.Parent = card
			createCorner(btnUse, 6)

			btnBuy.MouseButton1Click:Connect(function()
				if isBusy or not BuyShopItemFunc then return end
				isBusy = true
				pcall(function() BuyShopItemFunc:InvokeServer(itemId) end)
				isBusy = false
			end)

			btnUse.MouseButton1Click:Connect(function()
				if isBusy or count <= 0 or not UseShopItemFunc then return end
				isBusy = true
				local targetUUID = selectedPetForFeedUUID
				if not targetUUID and #currentInventory > 0 then
					targetUUID = currentInventory[1].UUID
				end
				pcall(function() UseShopItemFunc:InvokeServer(itemId, targetUUID) end)
				isBusy = false
			end)
		end
	end

	-- ====== 🎥 3D РУЛЕТКА ВІДКРИТТЯ КЕЙСА (БЕЗПЕЧНА ТА СИНХРОНІЗОВАНА) ======
	local function play3DRouletteAnimation(finalItem)
		if not finalItem then return end
		local camera = workspace.CurrentCamera
		if not camera then return end

		-- Ховаємо UI на час 3D шоу
		mainFrame.Visible = false
		toggleMenuBtn.Visible = false

		local folder = Instance.new("Folder")
		folder.Name = "Gacha3DRouletteContainer"
		folder.Parent = workspace

		pcall(function()
			local winId = finalItem.Id or finalItem.ItemId or "skibidi_toilet"
			local winName = finalItem.Name or winId

			-- Формуємо послідовність з 12 брейнротів
			local allItemIds = ItemDatabase and ItemDatabase.GetAllItemIds and ItemDatabase.GetAllItemIds() or { winId }
			local sequence = {}
			for i = 1, 11 do
				local randId = allItemIds[math.random(1, #allItemIds)]
				local cfg = ItemDatabase and ItemDatabase.GetItem(randId)
				table.insert(sequence, { id = randId, name = cfg and cfg.Name or randId })
			end
			-- 12-й брейнрот - ТОЧНО ТОЙ, ЯКИЙ ВИПАВ НА СЕРВЕРІ!
			table.insert(sequence, { id = winId, name = winName })

			local camCF = camera.CFrame
			local char = LocalPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")

			-- Рівна вертикальна позиція перед гравцем (на рівні очей, без нахилу камери)
			local centerPos
			if root then
				centerPos = root.Position + (root.CFrame.LookVector * 9.5) + Vector3.new(0, 1.2, 0)
			else
				centerPos = camCF.Position + (camCF.LookVector * 12.0)
			end

			local facingAngle = root and (root.Orientation.Y + 180) or 180

			-- ⚡ 1. ПОПЕРЕДНЄ ЗАВАНТАЖЕННЯ МОДЕЛЕЙ
			local preloadedModels = {}
			for i, entry in ipairs(sequence) do
				local m = nil
				if ModelLoader and ModelLoader.LoadUnitModel then
					pcall(function()
						m = ModelLoader.LoadUnitModel(entry.id, entry.name)
					end)
				end
				if m and m:IsA("Model") then
					m.Name = "RouletteUnit_" .. i
					m.Parent = folder

					local itemCfg = ItemDatabase and ItemDatabase.GetItem(entry.id)
					local rarityCol = itemCfg and itemCfg.Color or Color3.fromRGB(255, 215, 0)
					local isFinal = (i == #sequence)

					local hl = Instance.new("Highlight")
					hl.FillColor = rarityCol
					hl.FillTransparency = isFinal and 0.2 or 0.6
					hl.OutlineColor = rarityCol
					hl.OutlineTransparency = isFinal and 0.0 or 0.3
					hl.Parent = m

					local natRot = m:GetAttribute("NaturalRotation")
					local rotCFrame = natRot and natRot.Rotation or CFrame.identity
					m:PivotTo(CFrame.new(centerPos) * CFrame.Angles(0, math.rad(facingAngle), 0) * rotCFrame)

					-- Сховуємо модель на час черги
					for _, p in ipairs(m:GetDescendants()) do
						if p:IsA("BasePart") then p.Transparency = 1 end
					end

					table.insert(preloadedModels, { model = m, itemId = entry.id, rotCFrame = rotCFrame, isFinal = isFinal })
				end
			end

			-- 🌀 2. АНІМАЦІЯ ЗМІНИ 3D МОДЕЛЕЙ
			local delays = { 0.08, 0.08, 0.09, 0.10, 0.12, 0.15, 0.18, 0.23, 0.30, 0.40, 0.55, 0.70 }

			local function setModelTransparency(m, val)
				for _, p in ipairs(m:GetDescendants()) do
					if p:IsA("BasePart") then p.Transparency = val end
				end
			end

			for i, entry in ipairs(preloadedModels) do
				local model = entry.model
				if model and model.Parent then
					setModelTransparency(model, 0)

					if entry.isFinal then
						-- 🌟 3D МОДЕЛЬ, ЯКА ВИПАЛА: ПІДНОСИТЬСЯ ВГОРУ (+2.2 студа) ТА СЯЄ ПЕРЕД ОЧИМА!
						print(string.format("[Roulette Verification] 🏆 Final Win Item: '%s' | Model: '%s'", tostring(entry.itemId), tostring(model.Name)))

						local mainPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
						if mainPart then
							local light = Instance.new("PointLight")
							light.Range = 25
							light.Brightness = 5
							light.Color = Color3.fromRGB(255, 215, 100)
							light.Parent = mainPart
						end

						local holdStart = os.clock()
						while (os.clock() - holdStart) < 2.0 do
							if not model or not model.Parent then break end
							local dt = os.clock() - holdStart

							-- 🚀 Плавне анімоване піднесення вгору на +2.2 студа за 0.7с (Eased Cubic Out)
							local liftProgress = math.clamp(dt / 0.7, 0, 1)
							local easedLift = 1 - math.pow(1 - liftProgress, 3)
							local currentLift = easedLift * 2.2

							local winPos = centerPos + Vector3.new(0, currentLift, 0)
							local rotAngle = dt * math.pi * 1.5

							model:PivotTo(CFrame.new(winPos) * CFrame.Angles(0, math.rad(facingAngle) + rotAngle, 0) * entry.rotCFrame)
							task.wait(0.016)
						end

						-- 💥 Зникання в інвентар (політ вгору)
						local shrinkStart = os.clock()
						local finalPos = centerPos + Vector3.new(0, 2.2, 0)
						while (os.clock() - shrinkStart) < 0.6 do
							if not model or not model.Parent then break end
							local st = (os.clock() - shrinkStart) / 0.6
							local shrinkPos = finalPos + Vector3.new(0, st * 2.0, 0)
							model:PivotTo(CFrame.new(shrinkPos) * CFrame.Angles(0, math.rad(facingAngle) + (st * 8), 0) * entry.rotCFrame)
							task.wait(0.016)
						end
						if model and model.Parent then model:Destroy() end
					else
						-- Проміжна модель (рівне обертання навколо Y осі)
						local delayTime = delays[i] or 0.1
						local stepStart = os.clock()
						while (os.clock() - stepStart) < delayTime do
							if not model or not model.Parent then break end
							local dt = os.clock() - stepStart
							local spin = (dt / delayTime) * math.pi * 0.8
							model:PivotTo(CFrame.new(centerPos) * CFrame.Angles(0, math.rad(facingAngle) + spin, 0) * entry.rotCFrame)
							task.wait(0.016)
						end
						if model and model.Parent then model:Destroy() end
					end
				end
			end
		end)

		-- Завжди очищаємо контейнер та повертаємо UI
		pcall(function() folder:Destroy() end)
		setMenuState(true)
		toggleMenuBtn.Visible = true

		-- Повідомляємо сервер, що анімація рулетки завершилася
		local caseAnimDone = EventsFolder and EventsFolder:FindFirstChild("CaseAnimationFinished")
		if caseAnimDone then
			pcall(function() caseAnimDone:FireServer() end)
		end
	end

	-- ====== 🎁 КРУТІННЯ КЕЙСА (ГАРАНТОВАНО ІЗ СТИЛЬНОЮ АНІМАЦІЄЮ РУЛЕТКИ) ======
	local pendingInventory = nil

	btnOpenCase.MouseButton1Click:Connect(function()
		print("[Client] Case button clicked! isBusy:", isBusy, "OpenCaseFunc:", OpenCaseFunc)
		if isBusy or not OpenCaseFunc then return end
		isBusy = true

		-- 🎯 НЕГАЙНО ховаємо меню при натисканні кнопки відкриття кейсу!
		setMenuState(false)
		toggleMenuBtn.Visible = false

		btnOpenCase.BackgroundColor3 = Color3.fromRGB(100, 100, 110)
		btnOpenCase.Text = "🎲 Requesting Server..."
		resultDisplay.TextColor3 = Color3.fromRGB(255, 215, 0)

		-- Safe call with 8s timeout
		local function callServerWithTimeout(timeout)
			local done = false
			local ok, res
			task.spawn(function()
				ok, res = pcall(function() return OpenCaseFunc:InvokeServer() end)
				done = true
			end)
			local start = os.clock()
			while not done and (os.clock() - start) < timeout do
				task.wait(0.05)
			end
			if not done then
				done = true
				print("[Client] callServerWithTimeout TIMED OUT!")
				return false, { Success = false, Error = "Server Timeout! Check connection." }
			end
			print("[Client] callServerWithTimeout finished naturally, ok:", ok)
			return ok, res
		end

		print("[Client] Invoking OpenCaseFunc...")
		local serverSuccess, response = callServerWithTimeout(8)
		print("[Client] Invoke returned! Success:", serverSuccess, "Response:", response)

		if serverSuccess and response and response.Success then
			local finalItem = response.Item

			-- 🎬 3D ROULETTE SHOW
			play3DRouletteAnimation(finalItem)

			-- 3. Final Reward UI Display
			resultDisplay.Text = string.format(
				"🎉 UNLOCKED BRAINROT!\n%s (%s)\n⚔️ DMG: %d  |  🌟 Income: +%d/5s",
				finalItem.Name, finalItem.Rarity, finalItem.Damage, finalItem.IncomeRate
			)
			resultDisplay.TextColor3 = Color3.fromRGB(46, 204, 113)

		elseif serverSuccess and response then
			resultDisplay.Text = "❌ " .. (response.Error or "Error opening case")
			resultDisplay.TextColor3 = Color3.fromRGB(231, 76, 60)
			setMenuState(true)
			toggleMenuBtn.Visible = true
		else
			resultDisplay.Text = "❌ Server connection error. Please try again!"
			resultDisplay.TextColor3 = Color3.fromRGB(231, 76, 60)
			setMenuState(true)
			toggleMenuBtn.Visible = true
		end

		task.wait(0.5)
		btnOpenCase.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
		btnOpenCase.Text = "OPEN CASE (50 🧠)"
		isBusy = false

		if pendingInventory then
			renderInventory(pendingInventory)
			pendingInventory = nil
		end
	end)

	-- Register Listeners
	if InventoryUpdate then
		InventoryUpdate.OnClientEvent:Connect(function(inv)
			currentInventory = inv or currentInventory or {}
			closeInspectionPanel()
			if isBusy then
				pendingInventory = currentInventory
			else
				renderInventory(currentInventory)
			end
		end)
	end
	
	if RosterErrorEvent then
		RosterErrorEvent.OnClientEvent:Connect(function(errorMsg)
			-- Show a temporary error toast
			local toast = Instance.new("TextLabel")
			toast.Size = UDim2.new(0, 340, 0, 44)
			toast.Position = UDim2.new(0.5, -170, 0, 80)
			toast.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
			toast.Text = "🚫 " .. (errorMsg or "Care Zone is full!")
			toast.TextColor3 = Color3.fromRGB(255, 255, 255)
			toast.TextSize = 13
			toast.Font = Enum.Font.GothamBold
			toast.ZIndex = 20
			toast.Parent = PlayerGui:FindFirstChildOfClass("ScreenGui") or mainFrame.Parent
			createCorner(toast, 10)
			task.delay(3, function()
				if toast and toast.Parent then toast:Destroy() end
			end)
		end)
	end

	-- Початкове завантаження інвентаря при вході у гру
	local GetPlayerDataFunc = EventsFolder:FindFirstChild("GetPlayerData") or EventsFolder:WaitForChild("GetPlayerData", 5) :: RemoteFunction
	if GetPlayerDataFunc then
		task.spawn(function()
			local ok, data = pcall(function() return GetPlayerDataFunc:InvokeServer() end)
			if ok and data and data.Inventory then
				renderInventory(data.Inventory)
			end
		end)
	end
	if ConsumablesUpdate then
		ConsumablesUpdate.OnClientEvent:Connect(function(consumables)
			currentConsumables = consumables or {}
			renderShop()
		end)
	end

	if BuffStateUpdate then
		BuffStateUpdate.OnClientEvent:Connect(function(buffs)
			local now = os.time()
			local textList = {}
			if buffs and (buffs.IncomeBuffEndTime or 0) > now then
				table.insert(textList, string.format("x2 Income (%ds)", buffs.IncomeBuffEndTime - now))
			end
			if buffs and (buffs.DamageBuffEndTime or 0) > now then
				table.insert(textList, string.format("🧪 +25%% DMG (%ds)", buffs.DamageBuffEndTime - now))
			end
			buffLabel.Text = #textList > 0 and table.concat(textList, " | ") or ""
		end)
	end

	-- Battle buttons
	for zName, btn in pairs(attackButtons) do
		btn.MouseButton1Click:Connect(function()
			selectedAttackZone = zName
			for name, b in pairs(attackButtons) do
				b.BackgroundColor3 = (name == zName) and Color3.fromRGB(231, 76, 60) or Color3.fromRGB(42, 48, 62)
			end
		end)
	end

	for zName, btn in pairs(defenseButtons) do
		btn.MouseButton1Click:Connect(function()
			selectedDefenseZone = zName
			for name, b in pairs(defenseButtons) do
				b.BackgroundColor3 = (name == zName) and Color3.fromRGB(52, 152, 219) or Color3.fromRGB(42, 48, 62)
			end
		end)
	end

	local function openBattleGui(battleMode)
		local battleGuiScreen = PlayerGui:FindFirstChild("BattleGui")
		if not battleGuiScreen or not battleGuiScreen:IsA("ScreenGui") then
			for _, child in ipairs(PlayerGui:GetChildren()) do
				if child:IsA("ScreenGui") and child.Name == "BattleGui" then
					battleGuiScreen = child
					break
				end
			end
		end

		if battleGuiScreen and battleGuiScreen:IsA("ScreenGui") then
			battleGuiScreen:SetAttribute("SelectedBattleType", battleMode or "PvP")
			battleGuiScreen.Enabled = false
			task.wait()
			battleGuiScreen.Enabled = true
			setMenuState(false)
			toggleMenuBtn.Visible = false
		end
	end

	btnStartBattle.MouseButton1Click:Connect(function()
		openBattleGui("PvP")
	end)
	btnStartBotBattle.MouseButton1Click:Connect(function()
		openBattleGui("Bot")
	end)

	btnSubmitTurn.MouseButton1Click:Connect(function()
		if not selectedAttackZone or not selectedDefenseZone or not SubmitTurnEvent then return end
		SubmitTurnEvent:FireServer(selectedAttackZone, selectedDefenseZone)
	end)

	local BattleEnd = EventsFolder:WaitForChild("BattleEnd", 5) or EventsFolder:FindFirstChild("BattleEnd")
	if BattleEnd then
		BattleEnd.OnClientEvent:Connect(function(data)
			task.delay(5.0, function()
				toggleMenuBtn.Visible = true
			end)
		end)
	end

	-- Always restore toggleMenuBtn when BattleGui is disabled
	task.spawn(function()
		local battleGui = PlayerGui:WaitForChild("BattleGui", 10)
		if battleGui then
			local prop = battleGui:IsA("ScreenGui") and "Enabled" or "Visible"
			battleGui:GetPropertyChangedSignal(prop):Connect(function()
				local isVis = battleGui:IsA("ScreenGui") and battleGui.Enabled or battleGui.Visible
				if not isVis then
					task.wait(0.1)
					toggleMenuBtn.Visible = true
				end
			end)
		end
	end)

	if BattleStateUpdate then
		BattleStateUpdate.OnClientEvent:Connect(function(session)
			p1HPLabel.Text = string.format("%s: %d/%d HP", session.P1_Name or "?", session.P1_HP or 0, session.P1_MaxHP or 0)
			p2HPLabel.Text = string.format("%s: %d/%d HP", session.P2_Name or "?", session.P2_HP or 0, session.P2_MaxHP or 0)
			battleLogLabel.Text = session.LastLog or ""

			if session.Status ~= "InProgress" then
				task.delay(3.5, function()
					arenaSubFrame.Visible = false
					lobbySubFrame.Visible = true
					toggleMenuBtn.Visible = true
				end)
			end
		end)
	end
end)
