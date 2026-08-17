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
local ServerScriptService = game:GetService("ServerScriptService")
local modulesFolder = ServerScriptService:WaitForChild("Modules", 10) or ServerScriptService

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

Players.PlayerAdded:Connect(function(player)
	-- Виділяємо унікальний індекс бази для гравця
	local baseIndex = nextBaseIndex
	nextBaseIndex += 1
	playerBaseIndices[player.UserId] = baseIndex
	
	-- Генеруємо власну базу для гравця
	local playerBaseFolder = MapManager.GeneratePlayerBase(player, baseIndex)
	local spawnLoc = playerBaseFolder:WaitForChild("SpawnLocation", 5)
	
	if spawnLoc then
		-- Призначаємо цю базу місцем для спавну гравця
		player.RespawnLocation = spawnLoc
	end
	
	player.CharacterAdded:Connect(function(char)
		-- Коли персонаж завантажується, переконуємося, що він з'явиться на своїй базі (якщо RespawnLocation не спрацює миттєво)
		task.wait(0.5)
		if spawnLoc and char:FindFirstChild("HumanoidRootPart") then
			char.HumanoidRootPart.CFrame = spawnLoc.CFrame + Vector3.new(0, 3, 0)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	playerBaseIndices[player.UserId] = nil
	-- (Optional: Можна видаляти базу гравця, коли він виходить)
	local baseFolder = game:GetService("Workspace"):FindFirstChild("Base_" .. player.UserId)
	if baseFolder then
		baseFolder:Destroy()
	end
end)

print("==================================================")
print("🎉 [ServerInit] Усі сервіси сервера успішно активовано!")
print("==================================================")
