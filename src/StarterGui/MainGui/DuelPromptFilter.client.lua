--[[
	DuelPromptFilter.client.lua
	StarterGui.MainGui.DuelPromptFilter

	Миттєво приховує та вимикає будь-які ProximityPrompt на власному персонажі гравця,
	щоб гравець ніколи не бачив кнопку "Challenge to Duel" на собі,
	а бачив її ТІЛЬКИ при наближенні до ІНШИХ гравців.
--]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local LocalPlayer = Players.LocalPlayer

local function filterSelfPrompts(char)
	if not char then return end

	local function disablePrompt(item)
		if item:IsA("ProximityPrompt") then
			item.Enabled = false
			item.MaxActivationDistance = 0
		end
	end

	for _, desc in ipairs(char:GetDescendants()) do
		disablePrompt(desc)
	end
	char.DescendantAdded:Connect(disablePrompt)
end

if LocalPlayer.Character then
	task.spawn(filterSelfPrompts, LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(filterSelfPrompts)

-- Подвійний захист: перехоплення показу будь-якої підказки на власному персонажі
ProximityPromptService.PromptShown:Connect(function(prompt)
	if LocalPlayer.Character and prompt:IsDescendantOf(LocalPlayer.Character) then
		prompt.Enabled = false
		prompt.MaxActivationDistance = 0
	end
end)

-- Пряме спрацювання клієнтського затискання кнопки E на іншому гравцеві
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10) or ReplicatedStorage:FindFirstChild("Events")
local TriggerDuelEvent = eventsFolder and eventsFolder:WaitForChild("TriggerDuel", 10)

ProximityPromptService.PromptTriggered:Connect(function(prompt, inputType)
	if prompt.Name == "DuelPrompt" and prompt.Parent then
		local targetChar = prompt.Parent:IsA("Model") and prompt.Parent or prompt.Parent.Parent
		local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
		if targetPlayer and targetPlayer ~= LocalPlayer then
			print(string.format("[DuelPromptFilter] 🎯 Client PromptTriggered on %s! Firing TriggerDuel...", targetPlayer.Name))
			if TriggerDuelEvent then
				TriggerDuelEvent:FireServer(targetPlayer.UserId)
			end
		end
	end
end)
