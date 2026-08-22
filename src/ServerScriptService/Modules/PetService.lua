--[[
	PetService.lua
	ServerScriptService.PetService
	
	Оновлений PetService:
	1. Завантажує та спавнить 3D моделі брейнротів через ModelLoader у PetCareZone.
	2. Створює та оновлює 3D BillboardGui індикатори голоду над головами юнітів.
	3. Розраховує пасивний дохід з урахуванням бафу Супер-Корму (x2 multiplier).
	4. По поступове зниження рівня голоду (щохвилини -5%).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local ModelLoader = require(ReplicatedStorage.Modules.ModelLoader)

local FEED_COST = 10

local function getDataManager()
	if _G.DataManager then
		return _G.DataManager
	end
	return require(ServerScriptService:WaitForChild("DataManager"))
end

local PetService = {}
local spawnedPetModels = {} -- [player] = { [unitUUID] = Model }

-- Створення або оновлення 3D BillboardGui над головою юніта
local function updatePetBillboard(model: Model, unitName: string, hunger: number)
	local head = model.PrimaryPart or model:FindFirstChild("Head") or model:FindFirstChildOfClass("BasePart")
	if not head then return end

	local bbGui = head:FindFirstChild("PetStatusGui")
	if not bbGui then
		bbGui = Instance.new("BillboardGui")
		bbGui.Name = "PetStatusGui"
		bbGui.Size = UDim2.new(0, 130, 0, 36)
		bbGui.StudsOffset = Vector3.new(0, 2.5, 0)
		bbGui.AlwaysOnTop = false
		bbGui.MaxDistance = 25
		bbGui.Parent = head

		local bg = Instance.new("Frame")
		bg.Name = "BG"
		bg.Size = UDim2.new(1, 0, 1, 0)
		bg.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
		bg.BackgroundTransparency = 0.2
		bg.Parent = bbGui
		
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = bg

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size = UDim2.new(1, 0, 0, 22)
		title.BackgroundTransparency = 1
		title.TextColor3 = Color3.fromRGB(255, 255, 255)
		title.TextSize = 12
		title.Font = Enum.Font.GothamBold
		title.Parent = bg

		local barBG = Instance.new("Frame")
		barBG.Name = "BarBG"
		barBG.Size = UDim2.new(1, -12, 0, 14)
		barBG.Position = UDim2.new(0, 6, 0, 26)
		barBG.BackgroundColor3 = Color3.fromRGB(40, 45, 55)
		barBG.Parent = bg
		
		local barCorner = Instance.new("UICorner")
		barCorner.CornerRadius = UDim.new(0, 4)
		barCorner.Parent = barBG

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.new(1, 0, 1, 0)
		fill.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
		fill.Parent = barBG
		
		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, 4)
		fillCorner.Parent = fill
	end

	local bg = bbGui:FindFirstChild("BG")
	if bg then
		local title = bg:FindFirstChild("Title")
		if title then title.Text = string.format("%s (🍗 %d%%)", unitName, hunger) end

		local barBG = bg:FindFirstChild("BarBG")
		if barBG then
			local fill = barBG:FindFirstChild("Fill")
			if fill then
				fill.Size = UDim2.new(math.clamp(hunger / 100, 0, 1), 0, 1, 0)
				if hunger < 20 then
					fill.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
				elseif hunger < 50 then
					fill.BackgroundColor3 = Color3.fromRGB(241, 196, 15)
				else
					fill.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
				end
			end
		end
	end
end

-- Оновлення 3D моделей у власній базі гравця
function PetService.UpdatePlayerPetModels(player: Player)
	local DataManager = getDataManager()
	local data = DataManager.GetPlayerData(player)
	if not data or not data.Inventory then return end

	local baseName = "Base_" .. player.UserId
	local careZone = Workspace:FindFirstChild(baseName) or Workspace:FindFirstChild("PetCareZone")
	if not careZone then
		careZone = Workspace:WaitForChild(baseName, 3)
		if not careZone then
			return
		end
	end

	spawnedPetModels[player] = spawnedPetModels[player] or {}
	local playerPetFolder = careZone:FindFirstChild("PlayerPets_" .. player.UserId)
	if not playerPetFolder then
		playerPetFolder = Instance.new("Folder")
		playerPetFolder.Name = "PlayerPets_" .. player.UserId
		playerPetFolder.Parent = careZone
	end

	local padsFolder = careZone:FindFirstChild("PetPads")
	local rawChildren = padsFolder and padsFolder:GetChildren() or {}
	local pads = {}
	for _, child in ipairs(rawChildren) do
		-- Беремо ТІЛЬКИ платформи PetPad_, ігноруємо рамки PetPadBorder_
		if string.sub(child.Name, 1, 7) == "PetPad_" then
			table.insert(pads, child)
		end
	end

	table.sort(pads, function(a, b)
		local numA = tonumber(string.match(a.Name, "%d+")) or 0
		local numB = tonumber(string.match(b.Name, "%d+")) or 0
		return numA < numB
	end)

	local padIndex = 1
	local activeUUIDs = {}

	for _, unit in ipairs(data.Inventory) do
		if unit.Equipped then
			activeUUIDs[unit.UUID] = true
			local itemConfig = ItemDatabase.GetItem(unit.ItemId)
			if itemConfig then
				local existingModel = spawnedPetModels[player][unit.UUID]
				if not existingModel or not existingModel.Parent then
					-- Спавнимо нову 3D модель
					existingModel = ModelLoader.LoadUnitModel(unit.ItemId)
					existingModel.Parent = playerPetFolder
					spawnedPetModels[player][unit.UUID] = existingModel
					print(string.format("[CareZone Verification] 🏡 Spawning Pet for Item: '%s' | Model: '%s'", tostring(unit.ItemId), tostring(existingModel.Name)))
				end

				local pad = pads[padIndex] or pads[#pads] or careZone
				if pad and existingModel then
					-- Розрахунок точної висоти над платформою
					local _, bboxSize = existingModel:GetBoundingBox()
					local elev = math.clamp(bboxSize.Y / 2, 1, 6) + 0.25
					unit.Rotation = unit.Rotation or 0

					-- Суворе горизонтальне обертання навколо вертикальної осі Y з збереженням орієнтації моделі
					local natRot = existingModel:GetAttribute("NaturalRotation") or existingModel:GetPivot().Rotation
					local rotCF = CFrame.Angles(0, math.rad(unit.Rotation), 0) * natRot.Rotation
					existingModel:PivotTo(CFrame.new(pad.Position + Vector3.new(0, elev, 0)) * rotCF)

					-- Додавання ProximityPrompt для годування
					local prim = existingModel.PrimaryPart or existingModel:FindFirstChildOfClass("BasePart")
					if prim then
						local oldRot = prim:FindFirstChild("RotatePrompt")
						if oldRot then oldRot:Destroy() end
						
						if not prim:FindFirstChild("FeedPrompt") then
							local feedPrompt = Instance.new("ProximityPrompt")
							feedPrompt.Name = "FeedPrompt"
							feedPrompt.ActionText = "🍖 Feed"
							feedPrompt.ObjectText = existingModel.Name or "Brainrot"
							feedPrompt.MaxActivationDistance = 10
							feedPrompt.HoldDuration = 0.2
							feedPrompt.Parent = prim

							feedPrompt.Triggered:Connect(function(triggeringPlayer)
								if triggeringPlayer == player then
									local ev = ReplicatedStorage:FindFirstChild("Events")
									if ev and ev:FindFirstChild("PromptFeedUI") then
										ev.PromptFeedUI:FireClient(player, unit.UUID)
									end
								end
							end)
						end
					end
				end

				local displayName = (existingModel and existingModel.Name) or (itemConfig and itemConfig.Name) or unit.ItemId
				updatePetBillboard(existingModel, displayName, unit.Hunger)
				padIndex = padIndex + 1
			end
		end
	end

	-- Очищення неекіпірованих моделей
	for uuid, model in pairs(spawnedPetModels[player]) do
		if not activeUUIDs[uuid] then
			if model then model:Destroy() end
			spawnedPetModels[player][uuid] = nil
		end
	end
end

-- 1. Цикл пасивного доходу (кожні 5 секунд)
task.spawn(function()
	while true do
		task.wait(5)
		local DataManager = getDataManager()
		local now = os.time()

		for _, player in ipairs(Players:GetPlayers()) do
			local data = DataManager.GetPlayerData(player)
			if data and data.Inventory then
				local totalIncome = 0

				-- Перевірка активності Супер-Корм бафу (x2 multiplier)
				local incomeMult = 1.0
				if data.ActiveBuffs and now < (data.ActiveBuffs.IncomeBuffEndTime or 0) then
					incomeMult = data.ActiveBuffs.IncomeMultiplier or 2.0
				end

				for _, unit in ipairs(data.Inventory) do
					if unit.Equipped then
						local itemConfig = ItemDatabase.GetItem(unit.ItemId)
						if itemConfig then
							local baseIncome = itemConfig.IncomeRate or 1
							if unit.Hunger == 0 then
								baseIncome = 0
							elseif unit.Hunger < 20 then
								baseIncome = baseIncome * 0.5
							end
							totalIncome = totalIncome + (baseIncome * incomeMult)
						end
					end
				end

				if totalIncome > 0 then
					DataManager.AddBrainCells(player, math.floor(totalIncome))
				end
			end
		end
	end
end)

-- 2. Цикл зниження голоду (щохвилини на 5%)
task.spawn(function()
	while true do
		task.wait(60)
		local DataManager = getDataManager()

		for _, player in ipairs(Players:GetPlayers()) do
			local data = DataManager.GetPlayerData(player)
			if data and data.Inventory then
				for _, unit in ipairs(data.Inventory) do
					if unit.Hunger > 0 then
						unit.Hunger = math.max(0, unit.Hunger - 5)
					end
				end

				PetService.UpdatePlayerPetModels(player)

				local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
				if eventsFolder and eventsFolder:FindFirstChild("InventoryUpdate") then
					eventsFolder.InventoryUpdate:FireClient(player, data.Inventory)
				end
			end
		end
	end
end)

-- Обробники подій
local eventsFolder = ReplicatedStorage:WaitForChild("Events")
local feedPetEvent = eventsFolder:WaitForChild("FeedPet") :: RemoteEvent
local toggleEquipEvent = eventsFolder:WaitForChild("ToggleEquipPet") :: RemoteEvent
local inventoryUpdateEvent = eventsFolder:WaitForChild("InventoryUpdate") :: RemoteEvent
local petFedEffect = eventsFolder:FindFirstChild("PetFedEffect")
if not petFedEffect then
	petFedEffect = Instance.new("RemoteEvent")
	petFedEffect.Name = "PetFedEffect"
	petFedEffect.Parent = eventsFolder
end

feedPetEvent.OnServerEvent:Connect(function(player: Player, unitUUID: string, foodId: string)
	local DataManager = getDataManager()
	local data = DataManager.GetPlayerData(player)
	if not data then return end

	local targetUnit = nil
	for _, unit in ipairs(data.Inventory) do
		if unit.UUID == unitUUID then
			targetUnit = unit
			break
		end
	end

	if not targetUnit then return end
	if targetUnit.Hunger >= 100 and foodId == "basic_food" then return end

	local itemConfig = ItemDatabase.GetShopItem(foodId)
	if not itemConfig then return end
	
	-- Check if player owns this food in consumables
	local currentCount = data.Consumables[foodId] or 0
	if currentCount <= 0 then return end
	
	-- Consume food
	data.Consumables[foodId] = currentCount - 1
	
	-- Apply hunger
	targetUnit.Hunger = math.min(100, targetUnit.Hunger + (itemConfig.HungerRestored or 0))
	if petFedEffect then petFedEffect:FireAllClients(player.UserId, targetUnit.UUID) end
	
	-- Apply buff if it has one
	if itemConfig.BuffType then
		if petFedEffect then petFedEffect:FireAllClients(player.UserId, targetUnit.UUID) end
	targetUnit.ActiveBuff = {
			Type = itemConfig.BuffType,
			ExpireTimestamp = os.time() + (itemConfig.BuffDuration or 1800)
		}
	end

	PetService.UpdatePlayerPetModels(player)
	
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if eventsFolder then
		if eventsFolder:FindFirstChild("InventoryUpdate") then
			eventsFolder.InventoryUpdate:FireClient(player, data.Inventory)
		end
		if eventsFolder:FindFirstChild("ConsumablesUpdate") then
			eventsFolder.ConsumablesUpdate:FireClient(player, data.Consumables)
		end
	end
end)

toggleEquipEvent.OnServerEvent:Connect(function(player: Player, unitUUID: string)
	local DataManager = getDataManager()
	local data = DataManager.GetPlayerData(player)
	if not data then return end

	local MAX_CARE_ZONE = 12

	for _, unit in ipairs(data.Inventory) do
		if unit.UUID == unitUUID then
			-- Якщо юніт НЕ в зоні і намагаємось його виставити — перевіряємо ліміт
			if not unit.Equipped then
				local equippedCount = 0
				for _, u in ipairs(data.Inventory) do
					if u.Equipped then equippedCount = equippedCount + 1 end
				end
				if equippedCount >= MAX_CARE_ZONE then
					local eventsF = ReplicatedStorage:FindFirstChild("Events")
					if eventsF and eventsF:FindFirstChild("RosterError") then
						eventsF.RosterError:FireClient(player, "Care Zone is full! Remove a brainrot first. (Max 12)")
					end
					return
				end
			end

			unit.Equipped = not unit.Equipped
			PetService.UpdatePlayerPetModels(player)

			-- Відправляємо оновлений інвентар і поточний рахунок слотів
			local equippedCount = 0
			for _, u in ipairs(data.Inventory) do
				if u.Equipped then equippedCount = equippedCount + 1 end
			end
			inventoryUpdateEvent:FireClient(player, data.Inventory)
			local eventsF = ReplicatedStorage:FindFirstChild("Events")
			if eventsF and eventsF:FindFirstChild("RosterUpdate") then
				eventsF.RosterUpdate:FireClient(player, equippedCount, MAX_CARE_ZONE)
			end
			break
		end
	end
end)


inventoryUpdateEvent.OnServerEvent:Connect(function(player: Player)
	PetService.UpdatePlayerPetModels(player)
end)

local function initPlayerPetModels(player: Player)
	task.spawn(function()
		local DataManager = getDataManager()
		for i = 1, 20 do
			if DataManager.GetPlayerData(player) then
				break
			end
			task.wait(0.5)
		end
		PetService.UpdatePlayerPetModels(player)
	end)
end

Players.PlayerAdded:Connect(initPlayerPetModels)
for _, player in ipairs(Players:GetPlayers()) do
	initPlayerPetModels(player)
end

Players.PlayerRemoving:Connect(function(player)
	if spawnedPetModels[player] then
		for _, model in pairs(spawnedPetModels[player]) do
			if model then model:Destroy() end
		end
		spawnedPetModels[player] = nil
	end
end)

_G.PetService = PetService
return PetService
