--[[
	GachaService.lua
	ServerScriptService.GachaService
	
	Bugfix: pcall захист, гарантоване повернення результату.
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
	local totalWeight = 0
	local weightTable = {}

	for rarityName, rarityInfo in pairs(ItemDatabase.Rarities) do
		table.insert(weightTable, { Name = rarityName, Weight = rarityInfo.Weight })
		totalWeight = totalWeight + rarityInfo.Weight
	end

	local roll = math.random() * totalWeight
	local selectedRarity = "Common"
	local cumulative = 0

	for _, entry in ipairs(weightTable) do
		cumulative = cumulative + entry.Weight
		if roll <= cumulative then
			selectedRarity = entry.Name
			break
		end
	end

	local pool = ItemDatabase.GetItemsByRarity(selectedRarity)
	if #pool == 0 then
		for _, item in pairs(ItemDatabase.Items) do
			return item
		end
	end

	return pool[math.random(1, #pool)]
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
		-- Для тестування: якщо бракує BrainCells, додаємо +1000 та списуємо ціну
		DataManager.AddBrainCells(player, 1000)
		DataManager.AddBrainCells(player, -price)
	end

	local rolledItem = GachaService.RollRandomItem()
	print("[GachaService] Rolled item:", rolledItem and rolledItem.Name or "nil")
	if not rolledItem then
		DataManager.AddBrainCells(player, price)
		return { Success = false, Error = "Помилка розрахунку випадіння" }
	end

	local newUnit = DataManager.AddUnitToInventory(player, rolledItem.Id)
	print("[GachaService] Added to inventory, unit UUID:", newUnit and newUnit.UUID or "nil")

	print(string.format("[Gacha] %s → %s (%s)", player.Name, rolledItem.Name, rolledItem.Rarity))

	return {
		Success = true,
		Item = {
			Id = rolledItem.Id,
			Name = rolledItem.Name,
			Rarity = rolledItem.Rarity,
			Damage = rolledItem.Damage,
			MaxHP = rolledItem.MaxHP,
			IncomeRate = rolledItem.IncomeRate,
		},
		UnitData = newUnit,
	}
end

-- Динамічне оновлення спавну 3D моделей у PetCareZone СТРОВО ПІСЛЯ ЗАВЕРШЕННЯ АНІМАЦІЇ РУЛЕТКИ
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
