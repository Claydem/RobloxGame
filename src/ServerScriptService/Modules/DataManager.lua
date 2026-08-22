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

local DATA_STORE_NAME = "BrainrotDataStore_v3"
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
	},
	Boosts = {
		ExpBoostExpire = 0,
		BrainCellsBoostExpire = 0,
	},
	Stats = {
		BotWins = 0,
		BotLosses = 0,
		DuelWins = 0,
		DuelLosses = 0,
	},
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
	getOrMakeRemote("RosterError", "RemoteEvent")
	getOrMakeRemote("RosterUpdate", "RemoteEvent")
	getOrMakeRemote("BoostStateUpdate", "RemoteEvent")
	getOrMakeRemote("PromptPurchase", "RemoteEvent")
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

	
	local now = os.time()
	if amount > 0 and data.Boosts and data.Boosts.BrainCellsBoostExpire > now then
		amount = amount * 2
	end
	data.BrainCells = data.BrainCells + amount

	DataManager.UpdateLeaderstats(player)
	return true
end

function DataManager.UpdateLeaderstats(player: Player)
	local data = sessionData[player]
	if not data then return end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	local brainCellsVal = leaderstats:FindFirstChild("BrainCells")
	if brainCellsVal then
		brainCellsVal.Value = data.BrainCells or 0
	end

	local stats = data.Stats or {}
	local botWins = stats.BotWins or 0
	local botLosses = stats.BotLosses or 0
	local botTotal = botWins + botLosses
	local botWRPercent = botTotal > 0 and math.floor((botWins / botTotal) * 100) or 0

	local duelWins = stats.DuelWins or 0
	local duelLosses = stats.DuelLosses or 0
	local duelTotal = duelWins + duelLosses
	local duelWRPercent = duelTotal > 0 and math.floor((duelWins / duelTotal) * 100) or 0

	local duelVal = leaderstats:FindFirstChild("Duel WR")
	if not duelVal then
		duelVal = Instance.new("StringValue")
		duelVal.Name = "Duel WR"
		duelVal.Parent = leaderstats
	end
	duelVal.Value = string.format("%d%%", duelWRPercent)

	local botVal = leaderstats:FindFirstChild("Bot WR")
	if not botVal then
		botVal = Instance.new("StringValue")
		botVal.Name = "Bot WR"
		botVal.Parent = leaderstats
	end
	botVal.Value = string.format("%d%%", botWRPercent)
end

function DataManager.RecordBattleResult(player: Player, isBot: boolean, won: boolean)
	local data = sessionData[player]
	if not data then return end
	data.Stats = data.Stats or { BotWins = 0, BotLosses = 0, DuelWins = 0, DuelLosses = 0 }

	if isBot then
		if won then
			data.Stats.BotWins = (data.Stats.BotWins or 0) + 1
		else
			data.Stats.BotLosses = (data.Stats.BotLosses or 0) + 1
		end
	else
		if won then
			data.Stats.DuelWins = (data.Stats.DuelWins or 0) + 1
		else
			data.Stats.DuelLosses = (data.Stats.DuelLosses or 0) + 1
		end
	end

	DataManager.UpdateLeaderstats(player)
	task.spawn(function()
		saveData(player)
	end)
end

function DataManager.AddUnitToInventory(player: Player, itemId: string, optionalClass: string?)
	local data = sessionData[player]
	if not data then return nil end

	local MAX_CARE_ZONE = 12
	local equippedCount = 0
	for _, u in ipairs(data.Inventory or {}) do
		if u.Equipped then
			equippedCount = equippedCount + 1
		end
	end

	local shouldEquip = (equippedCount < MAX_CARE_ZONE)

	local newUnit = {
		UUID = HttpService:GenerateGUID(false),
		ItemId = itemId,
		Class = optionalClass or "Normal",
		Level = 1,
		XP = 0,
		Hunger = 100,
		Equipped = shouldEquip,
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
	local success, result = pcall(function()
		return BrainrotDataStore:GetAsync("Player_" .. player.UserId)
	end)
	if success then
		savedData = result
	end

	if success and savedData then
		sessionData[player] = savedData
		if not sessionData[player].Inventory then
			sessionData[player].Inventory = {}
		else
			-- Cap equipped pets to max 12 if over limit from legacy data
			local MAX_CARE_ZONE = 12
			local equippedCount = 0
			for _, unit in ipairs(sessionData[player].Inventory) do
				if unit.Equipped then
					equippedCount = equippedCount + 1
					if equippedCount > MAX_CARE_ZONE then
						unit.Equipped = false
					end
				end
			end
		end
		if not sessionData[player].Consumables then
			sessionData[player].Consumables = deepCopy(DEFAULT_DATA.Consumables)
		end
		if not sessionData[player].ActiveBuffs then
			sessionData[player].ActiveBuffs = deepCopy(DEFAULT_DATA.ActiveBuffs)
		end
		if not sessionData[player].Boosts then
			sessionData[player].Boosts = { ExpBoostExpire = 0, BrainCellsBoostExpire = 0 }
		end
		if not sessionData[player].Stats then
			sessionData[player].Stats = deepCopy(DEFAULT_DATA.Stats)
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
	brainCells.Value = sessionData[player].BrainCells or 0
	brainCells.Parent = leaderstats

	local duelVal = Instance.new("StringValue")
	duelVal.Name = "Duel WR"
	duelVal.Value = "0%"
	duelVal.Parent = leaderstats

	local botVal = Instance.new("StringValue")
	botVal.Name = "Bot WR"
	botVal.Value = "0%"
	botVal.Parent = leaderstats

	DataManager.UpdateLeaderstats(player)

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

task.delay(1, function()
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if eventsFolder then
		local getPlayerDataRF = eventsFolder:FindFirstChild("GetPlayerData")
		if getPlayerDataRF and getPlayerDataRF:IsA("RemoteFunction") then
			getPlayerDataRF.OnServerInvoke = function(player)
				return DataManager.GetPlayerData(player)
			end
		end
	end
end)

_G.DataManager = DataManager
return DataManager
