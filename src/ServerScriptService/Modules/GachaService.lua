--[[
	GachaService.lua
	ServerScriptService.Modules.GachaService
	
	v2.0 — Дворівнева Gacha: рол класу + рол виду за рідкістю
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)

local function getDataManager()
	if _G.DataManager then return _G.DataManager end
	local modules = ServerScriptService:FindFirstChild("Modules") or ServerScriptService
	return require(modules:WaitForChild("DataManager"))
end

local GachaService = {}

function GachaService.RollRandomItem()
	-- Крок 1: Ролимо рідкість виду та конкретний вид
	local speciesId, rarityKey = ItemDatabase.RollRandomSpecies()
	
	-- Крок 2: Ролимо клас
	local classKey = ItemDatabase.RollRandomClass()
	
	local speciesData = ItemDatabase.GetItem(speciesId)
	
	return {
		SpeciesId = speciesId,
		ClassKey = classKey,
		RarityKey = rarityKey,
		Item = speciesData,
	}
end

local eventsFolder = ReplicatedStorage:WaitForChild("Events")
local openCaseFunction = eventsFolder:WaitForChild("OpenCase") :: RemoteFunction

openCaseFunction.OnServerInvoke = function(player: Player)
	print("[GachaService] OnServerInvoke called for player:", player.Name)
	local DataManager = getDataManager()
	local price = ItemDatabase.CaseConfig.Price

	local ok = DataManager.AddBrainCells(player, -price)
	print("[GachaService] Deducted price, ok:", ok)
	if not ok then
		return { Success = false, Error = "Недостатньо BrainCells!" }
	end

	local rollResult = GachaService.RollRandomItem()
	print("[GachaService] Rolled:", rollResult.Item.Name, "Class:", rollResult.ClassKey, "Rarity:", rollResult.RarityKey)
	
	if not rollResult then
		DataManager.AddBrainCells(player, price)
		return { Success = false, Error = "Помилка розрахунку випадіння" }
	end

	local newUnit = DataManager.AddUnitToInventory(player, rollResult.SpeciesId, rollResult.ClassKey)
	print("[GachaService] Added to inventory, unit UUID:", newUnit and newUnit.UUID or "nil")

	-- Формуємо display name з префіксом класу
	local classCfg = ItemDatabase.Classes[rollResult.ClassKey]
	local displayName = rollResult.Item.Name
	if classCfg and classCfg.NamePrefix and classCfg.NamePrefix ~= "" then
		displayName = classCfg.NamePrefix .. " " .. rollResult.Item.Name
	end

	local rarityCfg = ItemDatabase.Rarities[rollResult.RarityKey]

	print(string.format("[Gacha] %s → %s [%s] (%s)", player.Name, displayName, rollResult.ClassKey, rollResult.RarityKey))

	-- 🌐 БРОАДКАСТ ВІДКРИТТЯ КЕЙСА ДЛЯ ВСІХ ГРАВЦІВ
	local globalUnboxEvent = eventsFolder:FindFirstChild("GlobalCaseUnboxed")
	if globalUnboxEvent then
		globalUnboxEvent:FireAllClients(player.Name, player.UserId, {
			Id = rollResult.SpeciesId,
			Name = displayName,
			Rarity = rollResult.RarityKey,
			RarityName = rarityCfg and rarityCfg.Name or "Common",
			RarityIcon = rarityCfg and rarityCfg.Icon or "⚪",
			RarityColor = rarityCfg and rarityCfg.Color or Color3.fromRGB(200, 200, 200),
			Class = rollResult.ClassKey,
			ClassColor = classCfg and classCfg.Color or Color3.fromRGB(220, 220, 220),
			ClassAbilityIcon = classCfg and classCfg.AbilityIcon or "",
		})
	end

	return {
		Success = true,
		Item = {
			Id = rollResult.SpeciesId,
			Name = displayName,
			Rarity = rollResult.RarityKey,
			RarityColor = rarityCfg and rarityCfg.Color or Color3.fromRGB(200, 200, 200),
			Class = rollResult.ClassKey,
			ClassColor = classCfg and classCfg.Color or Color3.fromRGB(220, 220, 220),
			ClassAbilityIcon = classCfg and classCfg.AbilityIcon or "",
			Damage = rollResult.Item.Damage,
			MaxHP = rollResult.Item.MaxHP,
			IncomeRate = rollResult.Item.IncomeRate,
		},
		UnitData = newUnit,
	}
end

-- Динамічне оновлення спавну 3D моделей у PetCareZone після анімації рулетки
local caseAnimFinishedEvent = eventsFolder:FindFirstChild("CaseAnimationFinished")
if not caseAnimFinishedEvent then
	caseAnimFinishedEvent = Instance.new("RemoteEvent")
	caseAnimFinishedEvent.Name = "CaseAnimationFinished"
	caseAnimFinishedEvent.Parent = eventsFolder
end

caseAnimFinishedEvent.OnServerEvent:Connect(function(player: Player)
	if _G.PetService then
		pcall(function()
			_G.PetService.UpdatePlayerPetModels(player)
		end)
	end
end)

return GachaService
