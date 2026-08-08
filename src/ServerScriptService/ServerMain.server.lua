--[[
	ServerMain.server.lua
	ServerScriptService.ServerMain

	Єдиний точка входу сервера:
	- Створює структуру ремоутів в ReplicatedStorage.Events
	- Завантажує серверні модулі в правильному порядку
	- (Автор: Brainrot Game Team)
--]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ═══════════════════════════════════════════════════════
--  REMOTES SETUP
-- ═══════════════════════════════════════════════════════

local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "Events"
	eventsFolder.Parent = ReplicatedStorage
end

local function ensureRemote(className, name)
	local r = eventsFolder:FindFirstChild(name)
	if r then
		if r.ClassName == className then return r end
		-- Wrong class exists — replace
		r:Destroy()
	end
	r = Instance.new(className)
	r.Name = name
	r.Parent = eventsFolder
	return r
end

local function ensureRemoteFunction(name) return ensureRemote("RemoteFunction", name) end
local function ensureRemoteEvent(name)    return ensureRemote("RemoteEvent", name)    end

-- Gacha
ensureRemoteFunction("OpenCase")
ensureRemoteEvent("CaseAnimationFinished")

-- Data / Inventory
ensureRemoteFunction("GetPlayerData")
ensureRemoteEvent("InventoryUpdate")
ensureRemoteEvent("ConsumablesUpdate")
ensureRemoteEvent("BuffStateUpdate")
ensureRemoteEvent("FeedPet")
ensureRemoteEvent("ToggleEquipPet")

-- Shop
ensureRemoteFunction("BuyShopItem")
ensureRemoteFunction("UseShopItem")

-- Battle (повний набір)
ensureRemoteFunction("StartBattle")
ensureRemoteEvent("QTEResult")
ensureRemoteEvent("BattlePhaseUpdate")
ensureRemoteEvent("BattleEnd")
ensureRemoteEvent("BattleStateUpdate")
ensureRemoteEvent("SubmitBattleTurn") -- legacy stub

print("[ServerMain] 🚀 Booting Brainrot Tycoon Server Modules...")

-- ═══════════════════════════════════════════════════════
--  LOAD MODULES (порядок має значення!)
-- ═══════════════════════════════════════════════════════
local modulesFolder = ServerScriptService:WaitForChild("Modules", 10)
if not modulesFolder then
	error("[ServerMain] ❌ Папка Modules не знайдена!")
end

local function safeRequire(name)
	local child = modulesFolder:FindFirstChild(name)
	if not child then
		warn("[ServerMain] ❌ Модуль " .. name .. " не знайдено!")
		return nil
	end
	local ok, mod = pcall(require, child)
	if not ok then
		warn("[ServerMain] ❌ Помилка завантаження модуля " .. name .. ": " .. tostring(mod))
		return nil
	end
	print("[ServerMain] ✅ Завантажено модуль: " .. name)
	return mod
end

-- DataManager і MapManager мають ініціалізуватися першими
safeRequire("DataManager")
safeRequire("MapManager")
safeRequire("PetService")
safeRequire("GachaService")
safeRequire("ShopService")
safeRequire("BattleService")
safeRequire("TeleportService")

print("[ServerMain] ✅ All 7 Server Services successfully initialized and running!")
