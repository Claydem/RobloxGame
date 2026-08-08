--[[
	ServerMain.server.lua
	ServerScriptService.ServerMain

	Головний серверний скрипт ініціалізації:
	Автоматично завантажує та запускає всі серверні модулі та ремоути гри.
--]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Create Remote Events & Remote Functions folder if missing
local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "Events"
	eventsFolder.Parent = ReplicatedStorage
end

local function ensureRemoteFunction(name)
	local rf = eventsFolder:FindFirstChild(name)
	if not rf then
		rf = Instance.new("RemoteFunction")
		rf.Name = name
		rf.Parent = eventsFolder
	end
	return rf
end

local function ensureRemoteEvent(name)
	local re = eventsFolder:FindFirstChild(name)
	if not re then
		re = Instance.new("RemoteEvent")
		re.Name = name
		re.Parent = eventsFolder
	end
	return re
end

ensureRemoteFunction("OpenCase")
ensureRemoteFunction("GetPlayerData")
ensureRemoteFunction("StartBattle")
ensureRemoteFunction("BuyShopItem")
ensureRemoteFunction("UseConsumable")
ensureRemoteEvent("InventoryUpdate")
ensureRemoteEvent("ConsumablesUpdate")
ensureRemoteEvent("BuffStateUpdate")
ensureRemoteEvent("ToggleEquipPet")
ensureRemoteEvent("CaseAnimationFinished")

print("[ServerMain] 🚀 Booting Brainrot Tycoon Server Modules...")

local modulesFolder = ServerScriptService:WaitForChild("Modules", 10)
if modulesFolder then
	require(modulesFolder:WaitForChild("DataManager"))
	require(modulesFolder:WaitForChild("MapManager"))
	require(modulesFolder:WaitForChild("PetService"))
	require(modulesFolder:WaitForChild("GachaService"))
	require(modulesFolder:WaitForChild("BattleService"))
	require(modulesFolder:WaitForChild("TeleportService"))
	require(modulesFolder:WaitForChild("ShopService"))

	print("[ServerMain] ✅ All 7 Server Services successfully initialized and running!")
end
