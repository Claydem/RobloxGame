--[[
	InitServer.server.lua
	ServerScriptService.InitServer
	
	Головний серверний скрипт (Entry Point).
	Автоматично завантажує всі серверні модулі з ServerScriptService.Modules.
--]]

print("==================================================")
print("🚀 [ServerInit] Запуск Brainrot Case & Fight Club...")
print("==================================================")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local modulesFolder = ServerScriptService:WaitForChild("Modules", 10) or ServerScriptService

-- ── ГАРАНТОВАНЕ СТВОРЕННЯ ВСІХ REMOTE EVENTS ТА FUNCTIONS НА СТАРТІ ──
local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "Events"
	eventsFolder.Parent = ReplicatedStorage
end

local remoteEventsList = {
	"DuelRequest", "DuelRespond", "DuelNotice",
	"QTEResult", "BattlePhaseUpdate", "BattleStateUpdate",
	"FeedPet", "ToggleEquipPet", "InventoryUpdate", "CurrencyUpdate",
	"RosterUpdate", "RosterError", "SelectZone", "SubmitBattleTurn"
}
for _, evName in ipairs(remoteEventsList) do
	if not eventsFolder:FindFirstChild(evName) then
		local ev = Instance.new("RemoteEvent")
		ev.Name = evName
		ev.Parent = eventsFolder
	end
end

local remoteFunctionsList = {
	"StartBattle", "OpenCase", "BuyItem"
}
for _, fnName in ipairs(remoteFunctionsList) do
	if not eventsFolder:FindFirstChild(fnName) then
		local fn = Instance.new("RemoteFunction")
		fn.Name = fnName
		fn.Parent = eventsFolder
	end
end

local function safeRequire(name)
	local child = modulesFolder:WaitForChild(name, 5) or ServerScriptService:FindFirstChild(name)
	if not child then
		warn("❌ [ServerInit] Модуль " .. name .. " не знайдено!")
		return nil
	end
	local ok, mod = pcall(require, child)
	if not ok then
		warn("❌ [ServerInit] Помилка завантаження модуля " .. name .. ": " .. tostring(mod))
		return nil
	end
	print("✅ [ServerInit] Завантажено модуль: " .. name)
	return mod
end

local MapManager = safeRequire("MapManager")
safeRequire("DataManager")
safeRequire("GachaService")
safeRequire("PetService")
safeRequire("BattleService")
safeRequire("ShopService")
safeRequire("TeleportService")
safeRequire("DuelService")

-- ── DYNAMIC PLAYER BASE ALLOCATION ──
local playerBaseIndices = {}
local nextBaseIndex = 1

local function setupPlayerBase(player)
	if not player or not player.Parent then return end

	local baseIndex = playerBaseIndices[player.UserId]
	if not baseIndex then
		baseIndex = nextBaseIndex
		nextBaseIndex += 1
		playerBaseIndices[player.UserId] = baseIndex
	end

	-- Генеруємо власну базу для гравця
	local playerBaseFolder = MapManager.GeneratePlayerBase(player, baseIndex)
	local spawnLoc = playerBaseFolder and playerBaseFolder:WaitForChild("SpawnLocation", 5)

	if spawnLoc then
		player.RespawnLocation = spawnLoc
	end

	local function positionCharacter(char)
		task.wait(0.2)
		local root = char:WaitForChild("HumanoidRootPart", 5)
		if root and spawnLoc then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			char:PivotTo(spawnLoc.CFrame + Vector3.new(0, 3, 0))
			print(string.format("[InitServer] 🏡 %s успішно розміщено на власній базі #%d", player.Name, baseIndex))
		end
	end

	if player.Character then
		task.spawn(positionCharacter, player.Character)
	end
	player.CharacterAdded:Connect(positionCharacter)
end

Players.PlayerAdded:Connect(setupPlayerBase)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayerBase, player)
end

Players.PlayerRemoving:Connect(function(player)
	playerBaseIndices[player.UserId] = nil
	local baseFolder = game:GetService("Workspace"):FindFirstChild("Base_" .. player.UserId)
	if baseFolder then
		baseFolder:Destroy()
	end
end)

print("==================================================")
print("🎉 [ServerInit] Усі сервіси сервера успішно активовано!")
print("==================================================")
