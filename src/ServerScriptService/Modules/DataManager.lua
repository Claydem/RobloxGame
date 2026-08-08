--[[
	DataManager.lua
	ServerScriptService.Modules.DataManager

	Виправлена версія:
	- Справжнє завантаження/збереження даних через DataStoreService
	- Глибоке злиття з DEFAULT_DATA (для міграції схем)
	- Захист від гонок записів (серіалізація збереження)
	- Повторні спроби при DataStore-таймаутах
	- BindToClose чекає завершення всіх збережень
	- Без дублюючого setupRemotes (ремоути створено в ServerMain)
--]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DATA_STORE_NAME = "BrainrotDataStore_v3"
local BrainrotDataStore = DataStoreService:GetDataStore(DATA_STORE_NAME)

local DataManager = {}
local sessionData = {} -- [player] = data table
local saveInProgress = {} -- [player] = true
local pendingSave = {}    -- [player] = true (потрібно перезберегти після поточного)

-- Початковий стан нового гравця
local DEFAULT_DATA = {
	DataVersion = 3,
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
}

-- ═══════════════════════════════════════════════════════
--  HELPERS
-- ═══════════════════════════════════════════════════════

local function deepCopy(t)
	if type(t) ~= "table" then return t end
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

-- Злиття завантажених даних поверх дефолтних (заповнює відсутні ключі, додає нові поля)
local function mergeWithDefaults(saved, defaults)
	local result = deepCopy(defaults)
	if type(saved) ~= "table" then return result end
	for k, v in pairs(saved) do
		if type(v) == "table" and type(result[k]) == "table" then
			result[k] = mergeWithDefaults(v, result[k])
		else
			result[k] = v
		end
	end
	return result
end

local function safeCloneForSave(data)
	-- Можемо додати фільтрацію небезпечних значень (наприклад, не зберігати метатаблиці тощо)
	return deepCopy(data)
end

-- ═══════════════════════════════════════════════════════
--  EVENTS HELPER
-- ═══════════════════════════════════════════════════════

local function getEvents()
	return ReplicatedStorage:FindFirstChild("Events")
end

local function fireClient(player, eventName, ...)
	local evts = getEvents()
	local ev = evts and evts:FindFirstChild(eventName)
	if ev and ev:IsA("RemoteEvent") then
		ev:FireClient(player, ...)
	end
end

-- ═══════════════════════════════════════════════════════
--  SAVE / LOAD
-- ═══════════════════════════════════════════════════════

local MAX_SAVE_RETRIES = 3

function DataManager.GetPlayerData(player)
	return sessionData[player]
end

function DataManager.AddBrainCells(player, amount)
	local data = sessionData[player]
	if not data then return false end
	if data.BrainCells == nil then data.BrainCells = DEFAULT_DATA.BrainCells end

	-- Не дозволяємо піти в мінус при списанні
	if amount < 0 and data.BrainCells + amount < 0 then
		return false
	end
	data.BrainCells = data.BrainCells + amount

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local bc = leaderstats:FindFirstChild("BrainCells")
		if bc and bc:IsA("IntValue") then
			bc.Value = data.BrainCells
		end
	end
	return true
end

function DataManager.AddUnitToInventory(player, itemId, optionalClass)
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
		Rotation = 0,
	}

	table.insert(data.Inventory, newUnit)
	DataManager.RequestSave(player)
	fireClient(player, "InventoryUpdate", data.Inventory)
	return newUnit
end

function DataManager.AddXPToUnit(player, unitUUID, xpAmount)
	local data = sessionData[player]
	if not data or not data.Inventory then return nil end

	local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)

	for _, unit in ipairs(data.Inventory) do
		if unit.UUID == unitUUID then
			unit.Level = unit.Level or 1
			unit.XP = (unit.XP or 0) + math.floor(math.max(0, xpAmount))

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

			DataManager.RequestSave(player)
			fireClient(player, "InventoryUpdate", data.Inventory)
			return { LeveledUp = leveledUp, Level = unit.Level, XP = unit.XP }
		end
	end
	return nil
end

-- Перевірка належності UUID гравцеві
function DataManager.GetUnitByUUID(player, unitUUID)
	local data = sessionData[player]
	if not data or not unitUUID then return nil end
	for _, unit in ipairs(data.Inventory) do
		if unit.UUID == unitUUID then return unit end
	end
	return nil
end

-- ═══════════════════════════════════════════════════════
--  ASYNC SAVE (queued, serialized, retried)
-- ═══════════════════════════════════════════════════════

function DataManager.RequestSave(player)
	if not sessionData[player] then return end
	if saveInProgress[player] then
		pendingSave[player] = true
		return
	end
	task.spawn(function()
		DataManager.SaveNow(player)
	end)
end

function DataManager.SaveNow(player)
	if not sessionData[player] then return end
	if saveInProgress[player] then
		pendingSave[player] = true
		return
	end

	saveInProgress[player] = true
	pendingSave[player] = false

	local key = "Player_" .. player.UserId
	local payload = safeCloneForSave(sessionData[player])

	local attempts = 0
	local success = false
	local err
	while attempts < MAX_SAVE_RETRIES and not success do
		attempts += 1
		success, err = pcall(function()
			BrainrotDataStore:SetAsync(key, payload)
		end)
		if not success then
			warn(("[DataManager] ❌ Спроба %d збереження для %s провалилась: %s"):format(attempts, player.Name, tostring(err)))
			task.wait(1)
		end
	end

	if not success then
		warn(("[DataManager] ❌ Не вдалося зберегти дані для %s після %d спроб: %s"):format(player.Name, MAX_SAVE_RETRIES, tostring(err)))
	end

	saveInProgress[player] = false

	if pendingSave[player] then
		pendingSave[player] = false
		task.spawn(function() DataManager.SaveNow(player) end)
	end
end

-- ═══════════════════════════════════════════════════════
--  LOAD
-- ═══════════════════════════════════════════════════════

local function loadData(player)
	if sessionData[player] then return end

	local key = "Player_" .. player.UserId
	local saved = nil
	local attempts = 0
	local success, result
	while attempts < MAX_SAVE_RETRIES do
		attempts += 1
		success, result = pcall(function()
			return BrainrotDataStore:GetAsync(key)
		end)
		if success then break end
		warn(("[DataManager] ❌ Спроба %d завантаження для %s провалилась: %s"):format(attempts, player.Name, tostring(result)))
		task.wait(1)
	end

	if not success then
		warn(("[DataManager] ❌ Не вдалося завантажити дані для %s — кикаємо гравця."):format(player.Name))
		player:Kick("Не вдалося завантажити твій профіль. Будь ласка, зайди через кілька хвилин.")
		return
	end

	saved = result

	if saved and type(saved) == "table" then
		sessionData[player] = mergeWithDefaults(saved, DEFAULT_DATA)
		print(("[DataManager] 💾 Завантажено профіль для %s (предметів: %d, версія: %s)"):format(
			player.Name,
			#(sessionData[player].Inventory or {}),
			tostring(sessionData[player].DataVersion)
		))
	else
		sessionData[player] = deepCopy(DEFAULT_DATA)
		print(("[DataManager] ✨ Створено новий профіль для %s"):format(player.Name))
	end

	-- leaderstats
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then leaderstats:Destroy() end
	leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local bc = Instance.new("IntValue")
	bc.Name = "BrainCells"
	bc.Value = sessionData[player].BrainCells
	bc.Parent = leaderstats

	-- Відсилаємо стартовий стан клієнту після завантаження
	task.delay(1, function()
		if not player:IsDescendantOf(Players) then return end
		fireClient(player, "InventoryUpdate", sessionData[player].Inventory)
		fireClient(player, "ConsumablesUpdate", sessionData[player].Consumables)
		fireClient(player, "BuffStateUpdate", sessionData[player].ActiveBuffs)
	end)
end

-- ═══════════════════════════════════════════════════════
--  EVENTS SETUP
-- ═══════════════════════════════════════════════════════

local events = getEvents()
if events then
	local getPlayerDataRF = events:FindFirstChild("GetPlayerData")
	if getPlayerDataRF and getPlayerDataRF:IsA("RemoteFunction") then
		function getPlayerDataRF.OnServerInvoke(player)
			local data = sessionData[player]
			if not data then return nil end
			-- Повертаємо тільки потрібні поля безпечно
			return {
				BrainCells = data.BrainCells,
				Inventory = data.Inventory,
				Consumables = data.Consumables,
				ActiveBuffs = data.ActiveBuffs,
			}
		end
	end
end

-- ═══════════════════════════════════════════════════════
--  PLAYER LIFECYCLE
-- ═══════════════════════════════════════════════════════

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(loadData, player)
end

Players.PlayerAdded:Connect(loadData)

Players.PlayerRemoving:Connect(function(player)
	if sessionData[player] then
		DataManager.SaveNow(player)
		sessionData[player] = nil
	end
	saveInProgress[player] = nil
	pendingSave[player] = nil
end)

game:BindToClose(function()
	-- Зберігаємо всіх гравців синхронно
	local threads = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if sessionData[player] then
			local th = task.spawn(function()
				DataManager.SaveNow(player)
			end)
			table.insert(threads, th)
		end
	end
	-- Трішки зачекати на завершення
	local deadline = os.clock() + 25 -- Roblox дає ~30с
	while next(saveInProgress) and os.clock() < deadline do
		task.wait(0.2)
	end
end)

_G.DataManager = DataManager
return DataManager
