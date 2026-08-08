--[[
	ShopService.lua
	ServerScriptService.ShopService
	
	Сервіс Магазину Товарів для Догляду (Care Shop) та системи бафів.
	Функціонал:
	1. Купівля товарів магазина за BrainCells з серверною перевіркою коштів.
	2. Використання витратних предметів:
	   - Звичайний корм (+25% голоду юніта)
	   - Супер-корм (100% голоду + x2 Баф Доходу на 3 хв)
	   - Еліксир сили (+25% Урону в Fight Club на 5 хв)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)

local function getDataManager()
	if _G.DataManager then
		return _G.DataManager
	end
	return require(ServerScriptService:WaitForChild("DataManager"))
end

local ShopService = {}

local eventsFolder = ReplicatedStorage:WaitForChild("Events")
local buyItemFunc = eventsFolder:WaitForChild("BuyShopItem") :: RemoteFunction
local useItemFunc = eventsFolder:WaitForChild("UseShopItem") :: RemoteFunction
local consumablesUpdateEvent = eventsFolder:WaitForChild("ConsumablesUpdate") :: RemoteEvent
local buffStateUpdateEvent = eventsFolder:WaitForChild("BuffStateUpdate") :: RemoteEvent
local inventoryUpdateEvent = eventsFolder:WaitForChild("InventoryUpdate") :: RemoteEvent

-- Купівля предмета у магазині
buyItemFunc.OnServerInvoke = function(player: Player, shopItemId: string)
	local DataManager = getDataManager()
	local data = DataManager.GetPlayerData(player)
	if not data then return { Success = false, Error = "Дані не завантажено" } end

	local itemConfig = ItemDatabase.GetShopItem(shopItemId)
	if not itemConfig then
		return { Success = false, Error = "Предмет не знайдено у магазині" }
	end

	-- Списання коштів
	local successDeduct = DataManager.AddBrainCells(player, -itemConfig.Price)
	if not successDeduct then
		return { Success = false, Error = "Недостатньо BrainCells!" }
	end

	-- Додавання в інвентар витратних предметів
	data.Consumables[shopItemId] = (data.Consumables[shopItemId] or 0) + 1

	-- Сповіщення клієнта
	consumablesUpdateEvent:FireClient(player, data.Consumables)

	print(string.format("[ShopService] Гравець %s придбав %s", player.Name, itemConfig.Name))

	return {
		Success = true,
		Item = itemConfig,
		Count = data.Consumables[shopItemId],
	}
end

-- Використання предмета
useItemFunc.OnServerInvoke = function(player: Player, shopItemId: string, targetUnitUUID: string?)
	local DataManager = getDataManager()
	local data = DataManager.GetPlayerData(player)
	if not data then return { Success = false, Error = "Дані не завантажено" } end

	local count = data.Consumables[shopItemId] or 0
	if count <= 0 then
		return { Success = false, Error = "У вас немає цього предмета!" }
	end

	local itemConfig = ItemDatabase.GetShopItem(shopItemId)
	if not itemConfig then return { Success = false, Error = "Невідомий предмет" } end

	local now = os.time()

	if shopItemId == "regular_food" then
		if not targetUnitUUID then return { Success = false, Error = "Оберіть юніта для годування!" } end
		local targetUnit = nil
		for _, unit in ipairs(data.Inventory) do
			if unit.UUID == targetUnitUUID then
				targetUnit = unit
				break
			end
		end
		if not targetUnit then return { Success = false, Error = "Юніта не знайдено!" } end

		targetUnit.Hunger = math.min(100, targetUnit.Hunger + itemConfig.HungerRestored)
		data.Consumables[shopItemId] = data.Consumables[shopItemId] - 1

		inventoryUpdateEvent:FireClient(player, data.Inventory)
		consumablesUpdateEvent:FireClient(player, data.Consumables)

		return { Success = true, Message = "Юніт відновлено на +25%!" }

	elseif shopItemId == "super_food" then
		if not targetUnitUUID then return { Success = false, Error = "Оберіть юніта для супер-годування!" } end
		local targetUnit = nil
		for _, unit in ipairs(data.Inventory) do
			if unit.UUID == targetUnitUUID then
				targetUnit = unit
				break
			end
		end
		if not targetUnit then return { Success = false, Error = "Юніта не знайдено!" } end

		targetUnit.Hunger = 100
		data.Consumables[shopItemId] = data.Consumables[shopItemId] - 1

		-- Активація бафу доходу
		data.ActiveBuffs.IncomeMultiplier = itemConfig.IncomeBuffMultiplier
		data.ActiveBuffs.IncomeBuffEndTime = now + itemConfig.IncomeBuffDuration

		inventoryUpdateEvent:FireClient(player, data.Inventory)
		consumablesUpdateEvent:FireClient(player, data.Consumables)
		buffStateUpdateEvent:FireClient(player, data.ActiveBuffs)

		return { Success = true, Message = "100% Голоду + Активовано x2 Баф Доходу на 3 хвилини!" }

	elseif shopItemId == "strength_elixir" then
		data.Consumables[shopItemId] = data.Consumables[shopItemId] - 1

		-- Активація бафу урону
		data.ActiveBuffs.DamageMultiplier = itemConfig.DamageBuffMultiplier
		data.ActiveBuffs.DamageBuffEndTime = now + itemConfig.DamageBuffDuration

		consumablesUpdateEvent:FireClient(player, data.Consumables)
		buffStateUpdateEvent:FireClient(player, data.ActiveBuffs)

		return { Success = true, Message = "Активовано +25% Урону в Fight Club на 5 хвилин!" }
	end

	return { Success = false, Error = "Помилка використання" }
end

return ShopService
