--[[
	DuelService.lua
	ServerScriptService.Modules.DuelService

	Обробляє запити на дуелі між гравцями.
	Додає ProximityPrompt до персонажів для запрошення на дуель.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BattleService = _G.BattleService

local DuelService = {}

local pendingDuels = {} -- [targetId] = senderId

-- Створюємо RemoteEvents, якщо їх немає
local events = ReplicatedStorage:FindFirstChild("Events")
if not events then
	events = Instance.new("Folder")
	events.Name = "Events"
	events.Parent = ReplicatedStorage
end

local function getOrCreateEvent(name)
	local ev = events:FindFirstChild(name)
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = events
	end
	return ev
end

local DuelRequestEvent = getOrCreateEvent("DuelRequest")
local DuelRespondEvent = getOrCreateEvent("DuelRespond")

-- Додавання ProximityPrompt до нових персонажів
local function setupPlayerPrompt(player)
	local function attachPrompt(char)
		local root = char:WaitForChild("HumanoidRootPart", 5)
		if root and not root:FindFirstChildOfClass("ProximityPrompt") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Challenge to Duel"
			prompt.ObjectText = player.Name
			prompt.RequiresLineOfSight = false
			prompt.MaxActivationDistance = 15
			prompt.HoldDuration = 0.5
			prompt.Parent = root
			
			prompt.Triggered:Connect(function(sender)
				if sender == player then return end
				pendingDuels[player.UserId] = sender.UserId
				print("[DuelService] " .. sender.Name .. " challenged " .. player.Name)
				DuelRequestEvent:FireClient(player, sender.Name)
			end)
		end
	end

	if player.Character then
		task.spawn(attachPrompt, player.Character)
	end
	player.CharacterAdded:Connect(attachPrompt)
end

Players.PlayerAdded:Connect(setupPlayerPrompt)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayerPrompt, player)
end

-- Обробка відповіді від цілі
DuelRespondEvent.OnServerEvent:Connect(function(player, response)
	local senderId = pendingDuels[player.UserId]
	if senderId then
		pendingDuels[player.UserId] = nil
		local sender = Players:GetPlayerByUserId(senderId)
		if sender and response == true then
			print("[DuelService] " .. player.Name .. " accepted duel from " .. sender.Name)
			-- Start Battle!
			if _G.BattleService then
				_G.BattleService.StartPvPBattle(sender, player)
			else
				warn("[DuelService] BattleService is not loaded!")
			end
		end
	end
end)

return DuelService
