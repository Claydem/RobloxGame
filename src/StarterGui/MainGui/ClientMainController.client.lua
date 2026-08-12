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

-- 🧹 ЗНИЩУЄМО БУДЬ-ЯКІ ДУБЛІКАТИ ScreenGui "MainGui" У PlayerGui
for _, child in ipairs(PlayerGui:GetChildren()) do
	if child:IsA("ScreenGui") and child.Name == "MainGui" and child ~= screenGui then
		child:Destroy()
	end
end

-- 🧹 ОЧИЩАЄМО ДОЧІРНІ GUI ЕЛЕМЕНТИ ВСЕРЕДИНІ ЕКРАНА ДЛЯ УНИКНЕННЯ ДУБЛЮВАННЯ
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

-- === 1. TOGGLE BUTTON (Top Left Corner - Below Roblox TopBar Inset) ===
local toggleMenuBtn = Instance.new("TextButton")
toggleMenuBtn.Name = "ToggleMenuBtn"
toggleMenuBtn.Size = UDim2.new(0, 160, 0, 42)
toggleMenuBtn.Position = UDim2.new(0, 15, 0, 48)
toggleMenuBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 50)
toggleMenuBtn.Text = "🧠 HIDE MENU"
toggleMenuBtn.TextColor3 = Color3.fromRGB(255, 215, 0)
toggleMenuBtn.TextSize = 13
toggleMenuBtn.Font = Enum.Font.GothamBold
toggleMenuBtn.ZIndex = 1000
toggleMenuBtn.Active = true
toggleMenuBtn.Parent = screenGui
createCorner(toggleMenuBtn, 10)
createStroke(toggleMenuBtn, Color3.fromRGB(255, 200, 0), 1.5)

-- === 2. MAIN FRAME ===
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 780, 0, 470)
mainFrame.Position = UDim2.new(0, 15, 0, 98)
mainFrame.BackgroundColor3 = Color3.fromRGB(22, 24, 32)
mainFrame.BorderSizePixel = 0
mainFrame.Visible = true
mainFrame.ZIndex = 1
mainFrame.Parent = screenGui
createCorner(mainFrame, 12)
createStroke(mainFrame, Color3.fromRGB(50, 55, 75), 2)

local currentActiveTab = "Gacha"
local setTab = nil

local function setMenuState(open: boolean)
	mainFrame.Visible = open
	toggleMenuBtn.Text = open and "🧠 HIDE MENU" or "🧠 OPEN MENU"
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

local btnStartBotBattle = Instance.new("TextButton")
btnStartBotBattle.Size = UDim2.new(0, 240, 0, 48)
btnStartBotBattle.Position = UDim2.new(0.5, -120, 0.35, 0)
btnStartBotBattle.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
btnStartBotBattle.Text = "⚔️ BATTLE VS BOT"
btnStartBotBattle.TextColor3 = Color3.fromRGB(255, 255, 255)
btnStartBotBattle.TextSize = 15
btnStartBotBattle.Font = Enum.Font.GothamBold
btnStartBotBattle.Parent = lobbySubFrame
createCorner(btnStartBotBattle, 10)

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

	-- Render Pets Inventory
	local function renderInventory(inv)
		if inv ~= nil then
			currentInventory = inv
		end
		currentInventory = currentInventory or {}

		for _, child in ipairs(petScroll:GetChildren()) do
			if child:IsA("Frame") then child:Destroy() end
		end

		local itemDB = ItemDatabase or (ModulesFolder and ModulesFolder:FindFirstChild("ItemDatabase") and require(ModulesFolder.ItemDatabase))
		if not itemDB then return end

		for _, unit in ipairs(currentInventory) do
			local stats = itemDB.GetUnitStats and itemDB.GetUnitStats(unit) or itemDB.GetItem(unit.ItemId)
			if not stats then continue end

			local level = unit.Level or stats.Level or 1
			local xp = unit.XP or stats.XP or 0
			local maxXP = stats.MaxXP or (itemDB.GetXPRequired and itemDB.GetXPRequired(level)) or 100
			local xpRemaining = math.max(0, maxXP - xp)
			local progressPct = math.clamp(xp / math.max(1, maxXP), 0, 1)

			local card = Instance.new("Frame")
			card.Size = UDim2.new(1, -8, 0, 100)
			card.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
			card.Parent = petScroll
			createCorner(card, 10)
			local rarityColor = stats.RarityConfig and stats.RarityConfig.Color or Color3.fromRGB(60, 65, 80)
			createStroke(card, rarityColor, 1)

			-- 3D Viewport Preview
			local viewport = Instance.new("ViewportFrame")
			viewport.Size = UDim2.new(0, 72, 0, 72)
			viewport.Position = UDim2.new(0, 10, 0.5, -36)
			viewport.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
			viewport.BorderSizePixel = 0
			viewport.Parent = card
			createCorner(viewport, 8)

			-- Level badge overlaid on viewport
			local lvlBadge = Instance.new("TextLabel")
			lvlBadge.Size = UDim2.new(1, 0, 0, 18)
			lvlBadge.Position = UDim2.new(0, 0, 1, -18)
			lvlBadge.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
			lvlBadge.BackgroundTransparency = 0.3
			lvlBadge.Text = "Lvl. " .. tostring(level)
			lvlBadge.TextColor3 = Color3.fromRGB(255, 215, 0)
			lvlBadge.TextSize = 10
			lvlBadge.Font = Enum.Font.GothamBold
			lvlBadge.Parent = viewport

			if ModelLoader then
				task.spawn(function()
					local petModel = ModelLoader.LoadUnitModel(unit.ItemId)
					if petModel then
						petModel.Parent = viewport
						local cam = Instance.new("Camera")
						cam.Parent = viewport
						viewport.CurrentCamera = cam
						local prim = petModel.PrimaryPart or petModel:FindFirstChildOfClass("BasePart")
						if prim then
							cam.CFrame = CFrame.new(prim.Position + Vector3.new(0, 1.2, 3.8), prim.Position)
						end
					end
				end)
			end

			-- Title + Class Tag
			local title = Instance.new("TextLabel")
			title.Size = UDim2.new(0, 320, 0, 22)
			title.Position = UDim2.new(0, 92, 0, 8)
			title.BackgroundTransparency = 1
			local rarityIcon = stats.RarityConfig and stats.RarityConfig.Icon or "⚪"
			local classIcon = stats.ClassConfig and stats.ClassConfig.AbilityIcon or ""
			local classTag = string.format(" [%s]", (stats.Class or unit.Class or "Normal"):upper())
			title.Text = rarityIcon .. " " .. (stats.Name or unit.ItemId) .. classTag .. " " .. classIcon .. (unit.Equipped and " ✅" or "")
			title.TextColor3 = stats.ClassConfig and stats.ClassConfig.Color or Color3.fromRGB(255, 255, 255)
			title.TextSize = 13
			title.Font = Enum.Font.GothamBold
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.Parent = card

			-- Dynamic Stats
			local statsLbl = Instance.new("TextLabel")
			statsLbl.Size = UDim2.new(0, 350, 0, 18)
			statsLbl.Position = UDim2.new(0, 92, 0, 32)
			statsLbl.BackgroundTransparency = 1
			statsLbl.Text = string.format("⚔️ DMG: %d  |  ❤️ HP: %d  |  🌟 +%d/5s  |  🍗 %d%%", stats.Damage or 10, stats.MaxHP or 100, stats.IncomeRate or 3, unit.Hunger or 100)
			statsLbl.TextColor3 = Color3.fromRGB(200, 205, 220)
			statsLbl.TextSize = 10
			statsLbl.Font = Enum.Font.GothamMedium
			statsLbl.TextXAlignment = Enum.TextXAlignment.Left
			statsLbl.Parent = card

			-- Class Perk label
			local perkLbl = Instance.new("TextLabel")
			perkLbl.Size = UDim2.new(0, 350, 0, 14)
			perkLbl.Position = UDim2.new(0, 92, 0, 48)
			perkLbl.BackgroundTransparency = 1
			local perkText = stats.ClassConfig and stats.ClassConfig.Perk or "Standard fighter"
			perkLbl.Text = (stats.ClassConfig and stats.ClassConfig.AbilityIcon or "") .. " " .. perkText
			perkLbl.TextColor3 = stats.ClassConfig and stats.ClassConfig.Color or Color3.fromRGB(150, 150, 170)
			perkLbl.TextSize = 8
			perkLbl.Font = Enum.Font.Gotham
			perkLbl.TextXAlignment = Enum.TextXAlignment.Left
			perkLbl.TextTruncate = Enum.TextTruncate.AtEnd
			perkLbl.Parent = card

			-- 📊 XP Progress Bar (Visual Track + Fill)
			local xpTrack = Instance.new("Frame")
			xpTrack.Size = UDim2.new(0, 280, 0, 18)
			xpTrack.Position = UDim2.new(0, 92, 0, 66)
			xpTrack.BackgroundColor3 = Color3.fromRGB(15, 18, 25)
			xpTrack.Parent = card
			createCorner(xpTrack, 8)
			createStroke(xpTrack, Color3.fromRGB(50, 55, 75), 1)

			local xpFill = Instance.new("Frame")
			xpFill.Size = UDim2.new(progressPct, 0, 1, 0)
			xpFill.BackgroundColor3 = Color3.fromRGB(155, 89, 182)
			xpFill.Parent = xpTrack
			createCorner(xpFill, 8)

			local xpText = Instance.new("TextLabel")
			xpText.Size = UDim2.new(1, 0, 1, 0)
			xpText.BackgroundTransparency = 1
			xpText.Text = string.format("XP: %d/%d (%d needed for Lvl %d)", xp, maxXP, xpRemaining, level + 1)
			xpText.TextColor3 = Color3.fromRGB(255, 255, 255)
			xpText.TextSize = 9
			xpText.Font = Enum.Font.GothamBold
			xpText.ZIndex = 5
			xpText.Parent = xpTrack

			-- Action Buttons
			local btnSelect = Instance.new("TextButton")
			btnSelect.Size = UDim2.new(0, 95, 0, 32)
			btnSelect.Position = UDim2.new(1, -210, 0.5, -16)
			btnSelect.BackgroundColor3 = (selectedPetForFeedUUID == unit.UUID) and Color3.fromRGB(241, 196, 15) or Color3.fromRGB(45, 52, 68)
			btnSelect.Text = (selectedPetForFeedUUID == unit.UUID) and "Selected" or "Select"
			btnSelect.TextColor3 = Color3.fromRGB(255, 255, 255)
			btnSelect.TextSize = 11
			btnSelect.Font = Enum.Font.GothamBold
			btnSelect.Parent = card
			createCorner(btnSelect, 8)

			btnSelect.MouseButton1Click:Connect(function()
				selectedPetForFeedUUID = unit.UUID
				renderInventory(currentInventory)
			end)

			local btnEquip = Instance.new("TextButton")
			btnEquip.Size = UDim2.new(0, 95, 0, 32)
			btnEquip.Position = UDim2.new(1, -105, 0.5, -16)
			btnEquip.BackgroundColor3 = unit.Equipped and Color3.fromRGB(149, 165, 166) or Color3.fromRGB(52, 152, 219)
			btnEquip.Text = unit.Equipped and "Unequip" or "Equip"
			btnEquip.TextColor3 = Color3.fromRGB(255, 255, 255)
			btnEquip.TextSize = 11
			btnEquip.Font = Enum.Font.GothamBold
			btnEquip.Parent = card
			createCorner(btnEquip, 8)

			btnEquip.MouseButton1Click:Connect(function()
				if ToggleEquipPetEvent then
					ToggleEquipPetEvent:FireServer(unit.UUID)
				end
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
			if isBusy then
				pendingInventory = currentInventory
			else
				renderInventory(currentInventory)
			end
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
				table.insert(textList, string.format("🌟 x2 Дохід (%ds)", buffs.IncomeBuffEndTime - now))
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

	btnStartBotBattle.MouseButton1Click:Connect(function()
		-- Відкриваємо BattleGui для вибору команди
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
			battleGuiScreen.Enabled = false
			task.wait()
			battleGuiScreen.Enabled = true
			setMenuState(false)
			toggleMenuBtn.Visible = false
		end
	end)

	btnSubmitTurn.MouseButton1Click:Connect(function()
		if not selectedAttackZone or not selectedDefenseZone or not SubmitTurnEvent then return end
		SubmitTurnEvent:FireServer(selectedAttackZone, selectedDefenseZone)
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
				end)
			end
		end)
	end

	-- Повертаємо меню після завершення бою
	local BattleEndEvent = EventsFolder and EventsFolder:FindFirstChild("BattleEnd")
	if BattleEndEvent and BattleEndEvent:IsA("RemoteEvent") then
		BattleEndEvent.OnClientEvent:Connect(function()
			task.delay(5, function()
				setMenuState(true)
				toggleMenuBtn.Visible = true
			end)
		end)
	end

	renderShop()
end)

print("[ClientMainController] Готово!")
