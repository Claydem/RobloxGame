--[[
	DuelController.client.lua
	StarterGui.MainGui.DuelController

	Повний автономний клієнтський контролер дуелей:
	1. Приховує ProximityPrompt на власному персонажі (щоб ніколи не бачити кнопку на собі).
	2. Перехоплює затискання кнопки [E] на інших гравцях і гарантовано шле сигнал на сервер.
	3. Відображає красивий Toast-банер сповіщень угорі екрана.
	4. Відображає модальне вікно виклику на дуель (ACCEPT / DECLINE) з таймером.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local SoundService = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ── 1. ЗНАХОДИМО АБО СТВОРЮЄМО SCREEN GUI ──
local function getScreenGui()
	local found = PlayerGui:FindFirstChild("MainGui")
	if found and found:IsA("ScreenGui") then
		return found
	end
	local anyGui = PlayerGui:FindFirstChildOfClass("ScreenGui")
	if anyGui then return anyGui end

	local newGui = Instance.new("ScreenGui")
	newGui.Name = "MainGui"
	newGui.ResetOnSpawn = false
	newGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	newGui.Parent = PlayerGui
	return newGui
end

-- ── 2. СИСТЕМА ДИЗАЙНУ ТА ЗВУКІВ ──
local function createCorner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

local function createStroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.fromRGB(60, 60, 80)
	s.Thickness = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function playSound(soundId, volume)
	task.spawn(function()
		local s = Instance.new("Sound")
		s.SoundId = soundId
		s.Volume = volume or 0.6
		s.Parent = SoundService
		s:Play()
		s.Ended:Connect(function() s:Destroy() end)
	end)
end

-- ── 3. МЕРЕЖЕВІ ПОДІЇ (REMOTE EVENTS) ──
local eventsFolder = ReplicatedStorage:WaitForChild("Events", 15) or ReplicatedStorage:FindFirstChild("Events")

local function getEvent(name)
	if not eventsFolder then return nil end
	return eventsFolder:WaitForChild(name, 10) or eventsFolder:FindFirstChild(name)
end

local DuelRequestEvent = getEvent("DuelRequest")
local DuelRespondEvent = getEvent("DuelRespond")
local DuelNoticeEvent  = getEvent("DuelNotice")
local TriggerDuelEvent = getEvent("TriggerDuel")
local DuelSelectPetEvent = getEvent("DuelSelectPet")
local DuelSubmitPetsEvent = getEvent("DuelSubmitPets")

-- Кеш інвентарю для вибору
local cachedInventory = {}
local InventoryUpdate = ReplicatedStorage:WaitForChild("Events"):FindFirstChild("InventoryUpdate")
if InventoryUpdate then
	InventoryUpdate.OnClientEvent:Connect(function(inv)
		cachedInventory = inv or {}
	end)
end


-- ── 4. ПРИХОВУВАННЯ ПІДКАЗКИ НА ВЛАСНОМУ ПЕРСОНАЖІ ──
ProximityPromptService.PromptShown:Connect(function(prompt)
	if prompt.Name == "DuelPrompt" and LocalPlayer.Character and prompt:IsDescendantOf(LocalPlayer.Character) then
		prompt.Enabled = false
	end
end)

-- Також гарантовано ховаємо при спавні
local function hideOwnDuelPrompt(char)
	if not char then return end
	local function checkPrompt(desc)
		if desc:IsA("ProximityPrompt") and desc.Name == "DuelPrompt" then
			desc.Enabled = false
		end
	end
	for _, d in ipairs(char:GetDescendants()) do
		checkPrompt(d)
	end
	char.DescendantAdded:Connect(checkPrompt)
end

if LocalPlayer.Character then
	task.spawn(hideOwnDuelPrompt, LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(hideOwnDuelPrompt)

-- ── 5. КЛІЄНТСЬКЕ СПРАЦЮВАННЯ PROXIMITY PROMPT ──
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt.Name == "DuelPrompt" and prompt.Parent then
		local targetChar = prompt.Parent:IsA("Model") and prompt.Parent or prompt.Parent.Parent
		local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
		if targetPlayer and targetPlayer ~= LocalPlayer then
			print(string.format("[DuelUIController] 🎯 Prompt triggered on %s! Sending request...", targetPlayer.Name))
			playSound("rbxassetid://6895079853", 0.5)
			if TriggerDuelEvent then
				TriggerDuelEvent:FireServer(targetPlayer.UserId)
			end
		end
	end
end)

-- ── 6. ВІДОБРАЖЕННЯ TOAST-БАНЕРА СПОВІЩЕНЬ ──
local function showDuelNotice(messageText)
	print("[DuelController] 📢 Сповіщення: " .. tostring(messageText))
	local screenGui = getScreenGui()
	if not screenGui then return end

	local banner = Instance.new("Frame")
	banner.Name = "DuelNoticeBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Size = UDim2.new(0.85, 0, 0, 48)
	local bannerConstraint = Instance.new("UISizeConstraint")
	bannerConstraint.MaxSize = Vector2.new(460, 48)
	bannerConstraint.MinSize = Vector2.new(280, 40)
	bannerConstraint.Parent = banner
	banner.Position = UDim2.new(0.5, 0, 0, -80)
	banner.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
	banner.ZIndex = 500
	banner.Parent = screenGui
	createCorner(banner, 10)
	createStroke(banner, Color3.fromRGB(255, 200, 50), 1.5)

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -24, 1, 0)
	lbl.Position = UDim2.new(0, 12, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = messageText
	lbl.TextColor3 = Color3.fromRGB(255, 240, 200)
	lbl.TextSize = 13
	lbl.Font = Enum.Font.GothamBold
	lbl.TextWrapped = true
	lbl.ZIndex = 501
	lbl.Parent = banner

	-- Анімація появи через TweenService
	local openTween = TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 25)
	})
	openTween:Play()

	task.delay(4.5, function()
		if banner and banner.Parent then
			local closeTween = TweenService:Create(banner, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(0.5, 0, 0, -80)
			})
			closeTween:Play()
			closeTween.Completed:Connect(function()
				if banner and banner.Parent then banner:Destroy() end
			end)
		end
	end)
end

if DuelNoticeEvent then
	DuelNoticeEvent.OnClientEvent:Connect(showDuelNotice)
end

-- ── 7. МОДАЛЬНЕ ВІКНО ЗАПРОШЕННЯ НА ДУЕЛЬ ──
local activeDuelModal = nil

local function showDuelModal(senderName, timeoutSec)
	print("[DuelController] ⚔️ Duel challenge received from: " .. tostring(senderName))
	timeoutSec = timeoutSec or 15

	if activeDuelModal and activeDuelModal.Parent then
		activeDuelModal:Destroy()
		activeDuelModal = nil
	end

	local screenGui = getScreenGui()
	if not screenGui then return end

	playSound("rbxassetid://6895079853", 0.8)

	local modal = Instance.new("Frame")
	modal.Name = "DuelChallengeModal"
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Size = UDim2.new(0.85, 0, 0.4, 0)
	local modalConstraint = Instance.new("UISizeConstraint")
	modalConstraint.MaxSize = Vector2.new(390, 200)
	modalConstraint.MinSize = Vector2.new(280, 180)
	modalConstraint.Parent = modal
	modal.Position = UDim2.new(0.5, 0, 0.45, 0)
	modal.BackgroundColor3 = Color3.fromRGB(16, 20, 28)
	modal.ZIndex = 1000
	modal.Parent = screenGui
	activeDuelModal = modal
	createCorner(modal, 12)
	createStroke(modal, Color3.fromRGB(231, 76, 60), 2.5)

	-- Заголовок
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 36)
	title.Position = UDim2.new(0, 0, 0, 10)
	title.BackgroundTransparency = 1
	title.Text = "⚔️ DUEL CHALLENGE!"
	title.TextColor3 = Color3.fromRGB(255, 75, 75)
	title.TextSize = 18
	title.Font = Enum.Font.GothamBlack
	title.ZIndex = 1001
	title.Parent = modal

	-- Опис
	local desc = Instance.new("TextLabel")
	desc.Size = UDim2.new(1, -24, 0, 40)
	desc.Position = UDim2.new(0, 12, 0, 46)
	desc.BackgroundTransparency = 1
	desc.Text = string.format("<b>%s</b> is challenging you to a PvP battle!", senderName)
	desc.TextColor3 = Color3.fromRGB(230, 235, 245)
	desc.TextSize = 14
	desc.Font = Enum.Font.GothamMedium
	desc.RichText = true
	desc.TextWrapped = true
	desc.ZIndex = 1001
	desc.Parent = modal

	-- Таймер
	local timerLbl = Instance.new("TextLabel")
	timerLbl.Size = UDim2.new(1, 0, 0, 22)
	timerLbl.Position = UDim2.new(0, 0, 0, 90)
	timerLbl.BackgroundTransparency = 1
	timerLbl.Text = string.format("⏳ Auto-decline in: %d sec", timeoutSec)
	timerLbl.TextColor3 = Color3.fromRGB(255, 200, 80)
	timerLbl.TextSize = 12
	timerLbl.Font = Enum.Font.GothamBold
	timerLbl.ZIndex = 1001
	timerLbl.Parent = modal

	-- Кнопка ПРИЙНЯТИ
	local acceptBtn = Instance.new("TextButton")
	acceptBtn.Size = UDim2.new(0.42, 0, 0, 42)
	acceptBtn.Position = UDim2.new(0.06, 0, 1, -54)
	acceptBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
	acceptBtn.Text = "⚔️ ACCEPT"
	acceptBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	acceptBtn.TextSize = 14
	acceptBtn.Font = Enum.Font.GothamBlack
	acceptBtn.ZIndex = 1001
	acceptBtn.Parent = modal
	createCorner(acceptBtn, 8)

	-- Кнопка ВІДХИЛИТИ
	local declineBtn = Instance.new("TextButton")
	declineBtn.Size = UDim2.new(0.42, 0, 0, 42)
	declineBtn.Position = UDim2.new(0.52, 0, 1, -54)
	declineBtn.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
	declineBtn.Text = "✖ DECLINE"
	declineBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	declineBtn.TextSize = 14
	declineBtn.Font = Enum.Font.GothamBlack
	declineBtn.ZIndex = 1001
	declineBtn.Parent = modal
	createCorner(declineBtn, 8)

	local isResponded = false
	local function respond(accept)
		if isResponded then return end
		isResponded = true
		if DuelRespondEvent then
			DuelRespondEvent:FireServer(accept)
		end
		if modal and modal.Parent then
			modal:Destroy()
		end
		if activeDuelModal == modal then
			activeDuelModal = nil
		end
	end

	acceptBtn.MouseButton1Click:Connect(function()
		playSound("rbxassetid://6895079853", 0.7)
		respond(true)
	end)

	declineBtn.MouseButton1Click:Connect(function()
		playSound("rbxassetid://6895079853", 0.5)
		respond(false)
	end)

	-- Таймер зворотного відліку
	task.spawn(function()
		local remaining = timeoutSec
		while remaining > 0 and not isResponded and modal and modal.Parent do
			task.wait(1)
			remaining -= 1
			if timerLbl and timerLbl.Parent then
				timerLbl.Text = string.format("⏳ Авто-відхилення через: %d сек", remaining)
			end
		end
		if not isResponded then
			respond(false)
		end
	end)
end

if DuelRequestEvent then
	DuelRequestEvent.OnClientEvent:Connect(function(senderName, timeoutSec)
		showDuelModal(senderName, timeoutSec)
	end)
end

print("✅ [DuelController] Клієнтський модуль дуелей успішно запущено!")


-- ── 8. ЕКРАН ВИБОРУ ПЕТІВ (PET SELECTION) ──
local selectionModal = nil

local function showPetSelection(opponentName)
	if selectionModal and selectionModal.Parent then selectionModal:Destroy() end

	local screenGui = getScreenGui()
	if not screenGui then return end

	local modal = Instance.new("Frame")
	modal.Name = "PetSelectionModal"
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Size = UDim2.new(0.85, 0, 0.85, 0)
	local petModalConstraint = Instance.new("UISizeConstraint")
	petModalConstraint.MaxSize = Vector2.new(540, 380)
	petModalConstraint.MinSize = Vector2.new(340, 260)
	petModalConstraint.Parent = modal
	modal.Position = UDim2.new(0.5, 0, 0.5, 0)
	modal.BackgroundColor3 = Color3.fromRGB(16, 20, 28)
	modal.ZIndex = 2000
	modal.Parent = screenGui
	selectionModal = modal
	createCorner(modal, 12)
	createStroke(modal, Color3.fromRGB(80, 150, 255), 2.5)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Position = UDim2.new(0, 0, 0, 10)
	title.BackgroundTransparency = 1
	title.Text = "SELECT TEAM (VS " .. opponentName .. ")"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 20
	title.Font = Enum.Font.GothamBlack
	title.ZIndex = 2001
	title.Parent = modal

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -20, 1, -120)
	scroll.Position = UDim2.new(0, 10, 0, 60)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 6
	scroll.ZIndex = 2001
	scroll.Parent = modal

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0, 100, 0, 120)
	layout.CellPadding = UDim2.new(0, 10, 0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	
	local selectedUUIDs = {}
	local countLbl = Instance.new("TextLabel")
	countLbl.Size = UDim2.new(1, 0, 0, 20)
	countLbl.Position = UDim2.new(0, 0, 1, -50)
	countLbl.BackgroundTransparency = 1
	countLbl.Text = "Selected: 0/3"
	countLbl.TextColor3 = Color3.fromRGB(200, 200, 200)
	countLbl.TextSize = 14
	countLbl.Font = Enum.Font.GothamBold
	countLbl.ZIndex = 2001
	countLbl.Parent = modal

	local submitBtn = Instance.new("TextButton")
	submitBtn.Size = UDim2.new(0, 200, 0, 40)
	submitBtn.Position = UDim2.new(0.5, -100, 1, -45)
	submitBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
	submitBtn.Text = "CONFIRM"
	submitBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	submitBtn.TextSize = 16
	submitBtn.Font = Enum.Font.GothamBlack
	submitBtn.ZIndex = 2001
	submitBtn.AutoButtonColor = false
	submitBtn.Parent = modal
	createCorner(submitBtn, 8)

	-- Заповнюємо сітку інвентарем
	local ModFolder = ReplicatedStorage:WaitForChild("Modules", 10)
	local ItemDB = ModFolder and require(ModFolder:WaitForChild("ItemDatabase"))
	
	local sortedInventory = {}
	for _, u in ipairs(cachedInventory) do
		table.insert(sortedInventory, u)
	end
	table.sort(sortedInventory, function(a, b)
		local statsA = ItemDB and ItemDB.GetUnitStats(a)
		local statsB = ItemDB and ItemDB.GetUnitStats(b)
		local nameA = (statsA and statsA.Name) or a.ItemId or ""
		local nameB = (statsB and statsB.Name) or b.ItemId or ""
		return string.lower(nameA) < string.lower(nameB)
	end)

	for i, u in ipairs(sortedInventory) do
		local cfg = ItemDB and ItemDB.GetUnitStats(u)
		if cfg then
			local btn = Instance.new("TextButton")
			btn.Text = ""
			btn.BackgroundColor3 = Color3.fromRGB(30, 35, 45)
			btn.ZIndex = 2002
			btn.Parent = scroll
			createCorner(btn, 8)
			local str = createStroke(btn, Color3.fromRGB(60, 60, 60), 2)
			
			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.new(1, 0, 1, 0)
			lbl.BackgroundTransparency = 1
			lbl.Text = cfg.Name .. "\nLvl " .. (u.Level or 1)
			lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
			lbl.TextSize = 14
			lbl.Font = Enum.Font.GothamBold
			lbl.ZIndex = 2003
			lbl.Parent = btn

			local isSelected = false
			btn.MouseButton1Click:Connect(function()
				if isSelected then
					isSelected = false
					str.Color = Color3.fromRGB(60, 60, 60)
					for idx, v in ipairs(selectedUUIDs) do
						if v == u.UUID then table.remove(selectedUUIDs, idx) break end
					end
				else
					if #selectedUUIDs < 3 then
						isSelected = true
						str.Color = Color3.fromRGB(80, 255, 100)
						table.insert(selectedUUIDs, u.UUID)
					end
				end
				countLbl.Text = "Selected: " .. #selectedUUIDs .. "/3"
				if #selectedUUIDs > 0 then
					submitBtn.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
				else
					submitBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
				end
			end)
		end
	end
	
	-- Підгонка розміру скролу
	scroll.CanvasSize = UDim2.new(0, 0, 0, math.ceil(#cachedInventory / 4) * 130)

	submitBtn.MouseButton1Click:Connect(function()
		if #selectedUUIDs > 0 then
			submitBtn.Text = "WAITING..."
			submitBtn.BackgroundColor3 = Color3.fromRGB(200, 150, 50)
			submitBtn.Active = false
			if DuelSubmitPetsEvent then
				DuelSubmitPetsEvent:FireServer(selectedUUIDs)
			end
			task.delay(1, function()
				if selectionModal and selectionModal.Parent then selectionModal:Destroy() end
			end)
		end
	end)
end

if DuelSelectPetEvent then
	DuelSelectPetEvent.OnClientEvent:Connect(function(opponentName)
		showPetSelection(opponentName)
	end)
end
