--[[
	InitServer.server.lua
	ServerScriptService.InitServer
	
	Головний серверний скрипт (Entry Point).
	Автоматично завантажує всі серверні модулі з ServerScriptService.Modules.
--]]

print("==================================================")
print("🚀 [ServerInit] Запуск Brainrot Case & Fight Club...")
print("==================================================")

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

safeRequire("MapManager")
safeRequire("DataManager")
safeRequire("GachaService")
safeRequire("PetService")
safeRequire("BattleService")
safeRequire("ShopService")
safeRequire("TeleportService")

print("==================================================")
print("🎉 [ServerInit] Усі сервіси сервера успішно активовано!")
print("==================================================")
