--[[
	ShopService.lua
	ServerScriptService.Modules.ShopService

	Виправлення:
	- Валідація вхідних даних (UUID, itemId)
	- Перевірка належності targetUnit гравцю
	- Перезавантаження бафів (заміна, а не множення); зберігання по ос.time()
	- Відправка оновлення клієнту після будь-якої дії
	- Списання коштів ПІСЛЯ всіх перевірок (atomic-стайл)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local DataManager = _G.DataManager
if not DataManager then
	DataManager = require(script.Parent:WaitForChild("DataManager", 5))
end

local ShopService = {}

local eventsFolder = ReplicatedStorage:WaitForChild("Events")
local buyItemFunc = eventsFolder:WaitForChild("BuyShopItem") :: RemoteFunction
local useItemFunc = eventsFolder:WaitForChild("UseShopItem") :: RemoteFunction
local consumablesUpdateEvent = eventsFolder:WaitForChild("ConsumablesUpdate") :: RemoteEvent
local buffStateUpdateEvent = eventsFolder:WaitForChild("BuffStateUpdate") :: RemoteEvent
local inventoryUpdateEvent = eventsFolder:WaitForChild("InventoryUpdate") :: RemoteEvent

-- ═══════════════════════════════════════════════════════
--  BUY
-- ═══════════════════════════════════════════════════════

buyItemFunc.OnServerInvoke = function(player, shopItemId)
	if type(shopItemId) ~= "string" then return { Success = false, Error = "Invalid item id" } end
	local data = DataManager.GetPlayerData(player)
	if not data then return { Success = false, Error = "Дані не завантажено" } end

	local itemConfig = ItemDatabase.GetShopItem(shopItemId)
	if not itemConfig then return { Success = false, Error = "Предмет не знайдено" } end
	if type(itemConfig.Price) ~= "number" or itemConfig.Price < 0 then
		return { Success = false, Error = "Некоректна ціна" }
	end

	local ok = DataManager.AddBrainCells(player, -itemConfig.Price)
	if not ok then
		return { Success = false, Error = "Недостатньо BrainCells!" }
	end

	data.Consumables = data.Consumables or {}
	data.Consumables[shopItemId] = (data.Consumables[shopItemId] or 0) + 1

	consumablesUpdateEvent:FireClient(player, data.Consumables)
	DataManager.RequestSave(player)

	print(string.format("[ShopService] %s придбав %s", player.Name, itemConfig.Name))
	return {
		Success = true,
		Item = itemConfig,
		Count = data.Consumables[shopItemId],
	}
end

-- ═══════════════════════════════════════════════════════
--  USE
-- ═══════════════════════════════════════════════════════

useItemFunc.OnServerInvoke = function(player, shopItemId, targetUnitUUID)
	if type(shopItemId) ~= "string" then return { Success = false, Error = "Invalid item" } end
	local data = DataManager.GetPlayerData(player)
	if not data then return { Success = false, Error = "Дані не завантажено" } end

	local count = (data.Consumables and data.Consumables[shopItemId]) or 0
	if count <= 0 then return { Success = false, Error = "У вас немає цього предмета!" } end

	local itemConfig = ItemDatabase.GetShopItem(shopItemId)
	if not itemConfig then return { Success = false, Error = "Невідомий предмет" } end

	local now = os.time()
	data.ActiveBuffs = data.ActiveBuffs or {
		IncomeMultiplier = 1.0, IncomeBuffEndTime = 0,
		DamageMultiplier = 1.0, DamageBuffEndTime = 0,
	}

	-- Спільний блок: списати предмет ПІСЛЯ успішного застосування, отже робимо це наприкінці
	local function consume()
		data.Consumables[shopItemId] = math.max(0, (data.Consumables[shopItemId] or 1) - 1)
		consumablesUpdateEvent:FireClient(player, data.Consumables)
		buffStateUpdateEvent:FireClient(player, data.ActiveBuffs)
		DataManager.RequestSave(player)
	end

	if shopItemId == "regular_food" then
		if type(targetUnitUUID) ~= "string" then
			return { Success = false, Error = "Оберіть юніта для годування!" }
		end
		local target = DataManager.GetUnitByUUID(player, targetUnitUUID)
		if not target then return { Success = false, Error = "Юніта не знайдено!" } end

		target.Hunger = math.min(100, (target.Hunger or 0) + (itemConfig.HungerRestored or 25))
		consume()
		inventoryUpdateEvent:FireClient(player, data.Inventory)
		return { Success = true, Message = "Юніта нагодовано! +" .. tostring(itemConfig.HungerRestored or 25) .. " голоду." }

	elseif shopItemId == "super_food" then
		-- Якщо задано конкретного улюбленця — нагодувати його; інакше — всі екіпіровані
		if type(targetUnitUUID) == "string" and targetUnitUUID ~= "" then
			local target = DataManager.GetUnitByUUID(player, targetUnitUUID)
			if not target then return { Success = false, Error = "Юніта не знайдено!" } end
			target.Hunger = 100
		else
			for _, u in ipairs(data.Inventory) do if u.Equipped then u.Hunger = 100 end end
		end

		-- Баф доходу: перезаписуємо мультиплікатор, якщо нова тривалість довша за поточну
		local newEnd = now + (itemConfig.IncomeBuffDuration or 180)
		if newEnd > (data.ActiveBuffs.IncomeBuffEndTime or 0) then
			data.ActiveBuffs.IncomeBuffEndTime = newEnd
		end
		data.ActiveBuffs.IncomeMultiplier = math.max(data.ActiveBuffs.IncomeMultiplier or 1, itemConfig.IncomeBuffMultiplier or 2.0)

		consume()
		inventoryUpdateEvent:FireClient(player, data.Inventory)
		return { Success = true, Message = "Супер-їжа активована! x" .. tostring(itemConfig.IncomeBuffMultiplier or 2.0) .. " дохід на " .. tostring(itemConfig.IncomeBuffDuration or 180) .. "s!" }

	elseif shopItemId == "strength_elixir" then
		local newEnd = now + (itemConfig.DamageBuffDuration or 300)
		if newEnd > (data.ActiveBuffs.DamageBuffEndTime or 0) then
			data.ActiveBuffs.DamageBuffEndTime = newEnd
		end
		data.ActiveBuffs.DamageMultiplier = math.max(data.ActiveBuffs.DamageMultiplier or 1, itemConfig.DamageBuffMultiplier or 1.25)
		consume()
		return { Success = true, Message = "Зілля сили активоване: +" .. tostring(math.floor((itemConfig.DamageBuffMultiplier or 1.25)*100 - 100)) .. "% DMG!" }
	end

	return { Success = false, Error = "Помилка використання" }
end

-- ═══════════════════════════════════════════════════════
--  BUFF TICK (оновити множники до 1.0 коли баф завершився)
-- ═══════════════════════════════════════════════════════

task.spawn(function()
	local Players = game:GetService("Players")
	while true do
		task.wait(1)
		local now = os.time()
		for _, player in ipairs(Players:GetPlayers()) do
			local data = DataManager.GetPlayerData(player)
			if data and data.ActiveBuffs then
				local changed = false
				if now >= (data.ActiveBuffs.IncomeBuffEndTime or 0) and (data.ActiveBuffs.IncomeMultiplier or 1) ~= 1 then
					data.ActiveBuffs.IncomeMultiplier = 1.0
					data.ActiveBuffs.IncomeBuffEndTime = 0
					changed = true
				end
				if now >= (data.ActiveBuffs.DamageBuffEndTime or 0) and (data.ActiveBuffs.DamageMultiplier or 1) ~= 1 then
					data.ActiveBuffs.DamageMultiplier = 1.0
					data.ActiveBuffs.DamageBuffEndTime = 0
					changed = true
				end
				if changed then
					buffStateUpdateEvent:FireClient(player, data.ActiveBuffs)
				end
			end
		end
	end
end)

return ShopService
