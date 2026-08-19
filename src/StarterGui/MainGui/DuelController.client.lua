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

-- ── 4. ПРИХОВУВАННЯ ПІДКАЗКИ НА ВЛАСНОМУ ПЕРСОНАЖІ ──
local function hideSelfPrompts(char)
	if not char then return end
	local function check(item)
		if item:IsA("ProximityPrompt") then
			item.Enabled = false
			item.MaxActivationDistance = 0
		end
	end
	for _, desc in ipairs(char:GetDescendants()) do
		check(desc)
	end
	char.DescendantAdded:Connect(check)
end

if LocalPlayer.Character then
	task.spawn(hideSelfPrompts, LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(hideSelfPrompts)

ProximityPromptService.PromptShown:Connect(function(prompt)
	if LocalPlayer.Character and prompt:IsDescendantOf(LocalPlayer.Character) then
		prompt.Enabled = false
		prompt.MaxActivationDistance = 0
	end
end)

-- ── 5. КЛІЄНТСЬКЕ СПРАЦЮВАННЯ PROXIMITY PROMPT ──
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt.Name == "DuelPrompt" and prompt.Parent then
		local targetChar = prompt.Parent:IsA("Model") and prompt.Parent or prompt.Parent.Parent
		local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
		if targetPlayer and targetPlayer ~= LocalPlayer then
			print(string.format("[DuelController] 🎯 Кнопка E затиснута на гравцеві %s! Відправка запиту на сервер...", targetPlayer.Name))
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
	banner.Size = UDim2.new(0, 460, 0, 52)
	banner.Position = UDim2.new(0.5, -230, 0, -80)
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
		Position = UDim2.new(0.5, -230, 0, 30)
	})
	openTween:Play()

	task.delay(4.5, function()
		if banner and banner.Parent then
			local closeTween = TweenService:Create(banner, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(0.5, -230, 0, -80)
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
	print("[DuelController] ⚔️ Отримано виклик на дуель від: " .. tostring(senderName))
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
	modal.Size = UDim2.new(0, 380, 0, 200)
	modal.Position = UDim2.new(0.5, -190, 0.4, -100)
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
	desc.Text = string.format("<b>%s</b> викликає вас на PvP битву!", senderName)
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
	timerLbl.Text = string.format("⏳ Авто-відхилення через: %d сек", timeoutSec)
	timerLbl.TextColor3 = Color3.fromRGB(255, 200, 80)
	timerLbl.TextSize = 12
	timerLbl.Font = Enum.Font.GothamBold
	timerLbl.ZIndex = 1001
	timerLbl.Parent = modal

	-- Кнопка ПРИЙНЯТИ
	local acceptBtn = Instance.new("TextButton")
	acceptBtn.Size = UDim2.new(0, 155, 0, 44)
	acceptBtn.Position = UDim2.new(0, 25, 0, 130)
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
	declineBtn.Size = UDim2.new(0, 155, 0, 44)
	declineBtn.Position = UDim2.new(1, -180, 0, 130)
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
