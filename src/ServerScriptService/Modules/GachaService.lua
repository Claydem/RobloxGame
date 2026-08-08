--[[
	GachaService.lua
	ServerScriptService.Modules.GachaService

	Виправлена версія:
	- Прибрано безкоштовну роздачу BrainCells
	- Надійна перевірка коштів
	- Додано рейт-ліміт на відкриття кейсів (анти-спам)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)

local DataManager = _G.DataManager
if not DataManager then
	local ok, DM = pcall(function()
		return require(script.Parent:WaitForChild("DataManager", 5))
	end)
	if ok then DataManager = DM end
end

local eventsFolder = ReplicatedStorage:WaitForChild("Events")
local openCaseFunction = eventsFolder:WaitForChild("OpenCase") :: RemoteFunction
local caseAnimFinishedEvent = eventsFolder:WaitForChild("CaseAnimationFinished") :: RemoteEvent
local inventoryUpdateEvent = eventsFolder:WaitForChild("InventoryUpdate") :: RemoteEvent

local GachaService = {}

-- ═══════════════════════════════════════════════════════
--  ROLL LOGIC
-- ═══════════════════════════════════════════════════════

function GachaService.RollRandomItem()
	local totalWeight = 0
	local weightTable = {}
	for rarityName, rarityInfo in pairs(ItemDatabase.Rarities) do
		table.insert(weightTable, { Name = rarityName, Weight = rarityInfo.Weight })
		totalWeight = totalWeight + rarityInfo.Weight
	end
	if totalWeight <= 0 then return nil end

	local roll = math.random() * totalWeight
	local selectedRarity = weightTable[1] and weightTable[1].Name or "Common"
	local cumulative = 0
	for _, entry in ipairs(weightTable) do
		cumulative = cumulative + entry.Weight
		if roll <= cumulative then
			selectedRarity = entry.Name
			break
		end
	end

	local pool = ItemDatabase.GetItemsByRarity(selectedRarity)
	if not pool or #pool == 0 then
		-- Fallback: повернути будь-який перший предмет
		for _, item in pairs(ItemDatabase.Items) do
			return item
		end
		return nil
	end
	return pool[math.random(1, #pool)]
end

-- ═══════════════════════════════════════════════════════
--  RATE LIMIT
-- ═══════════════════════════════════════════════════════

local lastOpen = {}
local OPEN_COOLDOWN = 1.2 -- секунд

-- ═══════════════════════════════════════════════════════
--  HANDLER
-- ═══════════════════════════════════════════════════════

openCaseFunction.OnServerInvoke = function(player)
	if not player or not player:IsDescendantOf(game) then
		return { Success = false, Error = "Invalid player" }
	end
	local data = DataManager and DataManager.GetPlayerData(player)
	if not data then
		return { Success = false, Error = "Дані гравця ще не завантажено, спробуй за мить" }
	end

	local now = os.clock()
	if lastOpen[player] and (now - lastOpen[player]) < OPEN_COOLDOWN then
		return { Success = false, Error = "Не так швидко!" }
	end
	lastOpen[player] = now

	local price = ItemDatabase.CaseConfig.Price or 50

	-- Списання коштів (без чіт-роздачі!)
	local ok = DataManager.AddBrainCells(player, -price)
	if not ok then
		return { Success = false, Error = "Недостатньо BrainCells! Потрібно " .. tostring(price) }
	end

	local rolledItem = GachaService.RollRandomItem()
	if not rolledItem then
		-- Повертаємо кошти через помилку розрахунку
		DataManager.AddBrainCells(player, price)
		return { Success = false, Error = "Помилка розрахунку випадіння" }
	end

	local newUnit = DataManager.AddUnitToInventory(player, rolledItem.Id)
	if not newUnit then
		DataManager.AddBrainCells(player, price)
		return { Success = false, Error = "Помилка додавання в інвентар" }
	end

	print(("[Gacha] %s → %s (%s) [%s]"):format(player.Name, rolledItem.Name, rolledItem.Rarity, newUnit.UUID))

	return {
		Success = true,
		Item = {
			Id = rolledItem.Id,
			Name = rolledItem.Name,
			Rarity = rolledItem.Rarity,
			Damage = rolledItem.Damage,
			MaxHP = rolledItem.MaxHP,
			IncomeRate = rolledItem.IncomeRate,
			Color = rolledItem.Color,
		},
		UnitData = newUnit,
	}
end

-- Оновлення 3D моделей після анімації рулетки
caseAnimFinishedEvent.OnServerEvent:Connect(function(player)
	if not player then return end
	if _G.PetService and _G.PetService.UpdatePlayerPetModels then
		pcall(_G.PetService.UpdatePlayerPetModels, _G.PetService, player)
	end
end)

-- Очищення кешу рейт-ліміту при виході
game:GetService("Players").PlayerRemoving:Connect(function(player)
	lastOpen[player] = nil
end)

return GachaService
