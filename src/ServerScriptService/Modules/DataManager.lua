--[[
	DataManager.lua
	ServerScriptService.DataManager
	
	Оновлений DataManager:
	- Додано підтримку Consumables (Інвентар витратних предметів магазину)
	- Додано підтримку ActiveBuffs (Активні бафи доходу та урону з таймерами)
	- Автоматична реєстрація RemoteEvents для ShopService
--]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DATA_STORE_NAME = "BrainrotDataStore_v2"
local BrainrotDataStore = DataStoreService:GetDataStore(DATA_STORE_NAME)

local DataManager = {}
local sessionData = {}
local saveData = nil

-- Початковий стан нового гравця
local DEFAULT_DATA = {
	BrainCells = 10000,
	Inventory = {},
	Consumables = {
		regular_food = 0,
		super_food = 0,
		strength_elixir = 0,
	},
	ActiveBuffs = {
		IncomeMultiplier = 1.0,
		IncomeBuffEndTime = 0,
		DamageMultiplier = 1.0,
		DamageBuffEndTime = 0,
	}
}

local function deepCopy(t)
	local copy = {}
	for k, v in pairs(t) do
		if type(v) == "table" then
			copy[k] = deepCopy(v)
		else
			copy[k] = v
		end
	end
	return copy
end

-- Автоматична реєстрація всіх необхідних RemoteEvents/Functions
local function setupRemotes()
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end

	local function getOrMakeRemote(name, className)
		local remote = eventsFolder:FindFirstChild(name)
		if not remote then
			remote = Instance.new(className)
			remote.Name = name
			remote.Parent = eventsFolder
		end
		return remote
	end

	getOrMakeRemote("OpenCase", "RemoteFunction")
	getOrMakeRemote("FeedPet", "RemoteEvent")
	getOrMakeRemote("ToggleEquipPet", "RemoteEvent")
	getOrMakeRemote("StartBattle", "RemoteFunction")
	getOrMakeRemote("SubmitBattleTurn", "RemoteEvent")
	getOrMakeRemote("BattleStateUpdate", "RemoteEvent")
	getOrMakeRemote("InventoryUpdate", "RemoteEvent")
	getOrMakeRemote("BuyShopItem", "RemoteFunction")
	getOrMakeRemote("UseShopItem", "RemoteFunction")
	getOrMakeRemote("ConsumablesUpdate", "RemoteEvent")
	getOrMakeRemote("BuffStateUpdate", "RemoteEvent")
end

setupRemotes()

function DataManager.GetPlayerData(player: Player)
	return sessionData[player]
end

function DataManager.AddBrainCells(player: Player, amount: number): boolean
	local data = sessionData[player]
	if not data then
		loadData(player)
		data = sessionData[player]
	end
	if not data then return false end

	if amount < 0 and math.abs(amount) > data.BrainCells then
		return false
	end

	data.BrainCells = data.BrainCells + amount

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local brainCellsVal = leaderstats:FindFirstChild("BrainCells")
		if brainCellsVal then
			brainCellsVal.Value = data.BrainCells
		end
	end

	return true
end

function DataManager.AddUnitToInventory(player: Player, itemId: string, optionalClass: string?)
	local data = sessionData[player]
	if not data then return nil end

	local newUnit = {
		UUID = HttpService:GenerateGUID(false),
		ItemId = itemId,
		Class = optionalClass or "Normal",
		Level = 1,
		XP = 0,
		Hunger = 100,
		Equipped = true,
	}

	table.insert(data.Inventory, newUnit)

	task.spawn(function()
		saveData(player)
	end)

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if eventsFolder and eventsFolder:FindFirstChild("InventoryUpdate") then
		eventsFolder.InventoryUpdate:FireClient(player, data.Inventory)
	end

	return newUnit
end

function DataManager.AddXPToUnit(player: Player, unitUUID: string, xpAmount: number)
	local data = sessionData[player]
	if not data or not data.Inventory then return nil end

	for _, unit in ipairs(data.Inventory) do
		if unit.UUID == unitUUID then
			unit.Level = unit.Level or 1
			unit.XP = (unit.XP or 0) + math.floor(math.max(0, xpAmount))

			local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
			local maxLvl = 100
			local leveledUp = false

			while unit.Level < maxLvl do
				local reqXP = ItemDatabase.GetXPRequired(unit.Level)
				if unit.XP >= reqXP then
					unit.XP = unit.XP - reqXP
					unit.Level = unit.Level + 1
					leveledUp = true
				else
					break
				end
			end

			task.spawn(function()
				saveData(player)
			end)

			local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
			if eventsFolder and eventsFolder:FindFirstChild("InventoryUpdate") then
				eventsFolder.InventoryUpdate:FireClient(player, data.Inventory)
			end

			return { LeveledUp = leveledUp, Level = unit.Level, XP = unit.XP }
		end
	end
	return nil
end

local RunService = game:GetService("RunService")

local function loadData(player: Player)
	if sessionData[player] then return end

	local savedData = nil
	local success, err = pcall(function()
		return BrainrotDataStore:GetAsync("Player_" .. player.UserId)
	end)

	if success and savedData then
		sessionData[player] = savedData
		if not sessionData[player].Inventory then
			sessionData[player].Inventory = {}
		end
		if not sessionData[player].Consumables then
			sessionData[player].Consumables = deepCopy(DEFAULT_DATA.Consumables)
		end
		if not sessionData[player].ActiveBuffs then
			sessionData[player].ActiveBuffs = deepCopy(DEFAULT_DATA.ActiveBuffs)
		end
		print("[DataManager] 💾 Завантажено збережені дані для " .. player.Name .. " (Предметів в інвентарі: " .. #sessionData[player].Inventory .. ")")
	else
		sessionData[player] = deepCopy(DEFAULT_DATA)
		print("[DataManager] ✨ Створено новий профіль для " .. player.Name)
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local brainCells = Instance.new("IntValue")
	brainCells.Name = "BrainCells"
	brainCells.Value = sessionData[player].BrainCells
	brainCells.Parent = leaderstats

	task.delay(1, function()
		if player:IsDescendantOf(Players) then
			local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
			if eventsFolder then
				if eventsFolder:FindFirstChild("InventoryUpdate") then
					eventsFolder.InventoryUpdate:FireClient(player, sessionData[player].Inventory)
				end
				if eventsFolder:FindFirstChild("ConsumablesUpdate") then
					eventsFolder.ConsumablesUpdate:FireClient(player, sessionData[player].Consumables)
				end
				if eventsFolder:FindFirstChild("BuffStateUpdate") then
					eventsFolder.BuffStateUpdate:FireClient(player, sessionData[player].ActiveBuffs)
				end
			end
		end
	end)
end

saveData = function(player: Player)
	local data = sessionData[player]
	if not data then return end

	local key = "Player_" .. player.UserId
	local success, err = pcall(function()
		BrainrotDataStore:SetAsync(key, data)
	end)

	if not success then
		warn("[DataManager] Помилка збереження даних для " .. player.Name .. ": " .. tostring(err))
	else
		print("[DataManager] Дані збережено успішно для " .. player.Name)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		loadData(player)
	end)
end

Players.PlayerAdded:Connect(loadData)

Players.PlayerRemoving:Connect(function(player)
	saveData(player)
	sessionData[player] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveData(player)
	end
end)

_G.DataManager = DataManager
return DataManager
