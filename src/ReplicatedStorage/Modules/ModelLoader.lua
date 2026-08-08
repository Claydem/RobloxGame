--[[
	ModelLoader.lua
	ReplicatedStorage.Modules.ModelLoader
	
	Модуль надійного завантаження 3D моделей через InsertService.
	Включає процедурну генерацію красивих Fallback 3D персонажів,
	якщо InsertService не має доступу або моделі недоступні в автономному режимі.
--]]

local InsertService = game:GetService("InsertService")
local ItemDatabase = require(script.Parent:WaitForChild("ItemDatabase"))

local ModelLoader = {}

-- Створення fallback 3D моделі у разі недоступності InsertService
local function createFallbackModel(itemConfig)
	local model = Instance.new("Model")
	model.Name = itemConfig.Name

	-- Тулуб (PrimaryPart)
	local torso = Instance.new("Part")
	torso.Name = "HumanoidRootPart"
	torso.Size = Vector3.new(2, 3, 2)
	torso.Color = itemConfig.Color or Color3.fromRGB(150, 150, 150)
	torso.Material = Enum.Material.SmoothPlastic
	torso.Anchored = true
	torso.CanCollide = false
	torso.Parent = model
	model.PrimaryPart = torso

	-- Голова
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.5, 1.5, 1.5)
	head.Position = torso.Position + Vector3.new(0, 2.2, 0)
	head.Color = itemConfig.Color or Color3.fromRGB(200, 200, 200)
	head.Material = Enum.Material.SmoothPlastic
	head.Anchored = true
	head.CanCollide = false
	head.Parent = model

	-- Гуманоїд для нативності
	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model

	return model
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function sanitizeModel(model: Model, itemConfig)
	if not model then return nil end

	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
		end
	end

	local primary = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChildOfClass("BasePart")
	if not primary then
		primary = Instance.new("Part")
		primary.Name = "HumanoidRootPart"
		primary.Size = Vector3.new(2, 2, 2)
		primary.Transparency = 1
		primary.CanCollide = false
		primary.Anchored = true
		primary.Parent = model
	end
	model.PrimaryPart = primary

	-- Зберігаємо оригінальне обертання півота моделі як атрибут
	local origPivot = model:GetPivot()
	model:SetAttribute("NaturalRotation", origPivot.Rotation)

	return model
end

local function cleanStr(s)
	return string.lower(string.gsub(tostring(s or ""), "[%s_%-%W]", ""))
end

-- Перевіряємо чи модель є "листовою" (не містить інших системних чи вкладених Model всередині)
local function isLeafModel(m: Instance)
	if not m:IsA("Model") then return false end
	for _, child in ipairs(m:GetChildren()) do
		if child:IsA("Model") then
			return false
		end
	end
	return true
end

local function findCustomModel(itemId, itemName)
	local targetIdClean = cleanStr(itemId)
	local targetNameClean = cleanStr(itemName)

	local searchContainers = { ReplicatedStorage:FindFirstChild("Models"), ReplicatedStorage }

	-- 1. Перший прохід: Точний збіг за назвою (ТІЛЬКИ по окремих листових моделях)
	for _, container in ipairs(searchContainers) do
		if not container then continue end
		for _, desc in ipairs(container:GetDescendants()) do
			if isLeafModel(desc) then
				local descClean = cleanStr(desc.Name)
				if (targetIdClean ~= "" and descClean == targetIdClean) or (targetNameClean ~= "" and descClean == targetNameClean) then
					local clone = desc:Clone()
					clone.Name = desc.Name -- Зберігаємо справжню оригінальну назву 3D моделі!
					print("[ModelLoader] 🎯 Знайдено точну 3D модель:", desc.Name, "для", itemName or itemId)
					return clone
				end
			end
		end
	end

	-- 2. Другий прохід: Частковий збіг (без переплутування Gold / Rainbow / Lava варіантів)
	for _, container in ipairs(searchContainers) do
		if not container then continue end
		for _, desc in ipairs(container:GetDescendants()) do
			if isLeafModel(desc) then
				local descClean = cleanStr(desc.Name)
				-- Перевіряємо чи відрізняються префікси (золотий/лава/тощо)
				local isGoldVariant = string.find(descClean, "gold", 1, true) or string.find(descClean, "lava", 1, true)
				local isTargetVariant = string.find(targetIdClean, "gold", 1, true) or string.find(targetNameClean, "gold", 1, true) or
				                        string.find(targetIdClean, "lava", 1, true) or string.find(targetNameClean, "lava", 1, true)

				-- Частковий збіг дозволений ТІЛЬКИ якщо обидва є варіантами або обидва НЕ є варіантами!
				if (isGoldVariant and isTargetVariant) or (not isGoldVariant and not isTargetVariant) then
					if (string.len(targetIdClean) > 3 and string.find(descClean, targetIdClean, 1, true)) or
					   (string.len(targetNameClean) > 3 and string.find(descClean, targetNameClean, 1, true)) then
						local clone = desc:Clone()
						clone.Name = desc.Name
						print("[ModelLoader] 🎯 Знайдено часткову 3D модель:", desc.Name, "для", itemName or itemId)
						return clone
					end
				end
			end
		end
	end

	return nil
end

local function getDeterministicIndex(str, maxCount)
	if maxCount <= 0 then return 1 end
	local hash = 0
	local s = tostring(str or "")
	for i = 1, #s do
		hash = (hash * 31 + string.byte(s, i)) % 2147483647
	end
	return (hash % maxCount) + 1
end

-- Основна функція завантаження 3D моделі
function ModelLoader.LoadUnitModel(itemId: string, optionalItemName: string?): Model
	local itemConfig = ItemDatabase and ItemDatabase.GetItem(itemId)
	local itemName = optionalItemName or (itemConfig and itemConfig.Name) or itemId

	-- 1. Пошук у користувацьких модельках з паку
	local customModel = findCustomModel(itemId, itemName)
	if customModel then
		return sanitizeModel(customModel, itemConfig)
	end

	local loadedModel = nil
	if itemConfig and itemConfig.AssetId and itemConfig.AssetId > 0 then
		local success, modelContainer = pcall(function()
			return InsertService:LoadAsset(itemConfig.AssetId)
		end)

		if success and modelContainer then
			local actualModel = modelContainer:FindFirstChildOfClass("Model") or modelContainer:FindFirstChildOfClass("BasePart")
			if actualModel then
				if actualModel:IsA("BasePart") then
					local wrapper = Instance.new("Model")
					actualModel.Parent = wrapper
					wrapper.PrimaryPart = actualModel
					loadedModel = wrapper
				else
					loadedModel = actualModel
				end
				loadedModel.Name = itemName
			end
		end
	end

	-- 3. Якщо точності немає — беремо детерміновану модель з паку (однакову для одного й того ж itemId)
	if not loadedModel then
		local modelsFolder = ReplicatedStorage:FindFirstChild("Models")
		if modelsFolder then
			local leafModels = {}
			for _, child in ipairs(modelsFolder:GetDescendants()) do
				if isLeafModel(child) and child.Name ~= "MainGui" then
					table.insert(leafModels, child)
				end
			end
			if #leafModels > 0 then
				local idx = getDeterministicIndex(itemId, #leafModels)
				local picked = leafModels[idx]
				local clone = picked:Clone()
				clone.Name = itemName
				print("[ModelLoader] 🎯 Детерміновано обрано 3D модель з паку:", picked.Name, "для", itemId)
				loadedModel = clone
			end
		end
	end

	-- Якщо зовсім нічого немає — створюємо Fallback
	if not loadedModel then
		loadedModel = createFallbackModel(itemConfig or { Name = itemName, Color = Color3.fromRGB(200, 200, 200) })
	end

	return sanitizeModel(loadedModel, itemConfig)
end

-- Аліас для сумісності з різними контролерами
ModelLoader.LoadModel = ModelLoader.LoadUnitModel

return ModelLoader
