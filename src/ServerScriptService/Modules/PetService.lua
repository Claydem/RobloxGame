--[[
	PetService.lua
	ServerScriptService.Modules.PetService

	Виправлена версія:
	1. Завантажує та спавнить 3D моделі брейнротів у PetCareZone.
	2. BillboardGui індикатори голоду.
	3. Пасивний дохід з урахуванням бафу Супер-Корму (IncomeMultiplier).
	4. Поступове зниження голоду.
	5. Серверна перевірка належності UUID при годуванні/екіпіруванні.
	6. Обмеження на кількість екіпірованих петів (MAX_EQUIPPED).
	7. Hunger-tick оновлює тільки billboard, без повного respawn моделей.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local ModelLoader = require(ReplicatedStorage.Modules.ModelLoader)

local FEED_COST = 10
local MAX_EQUIPPED = 6
local INCOME_TICK = 5
local HUNGER_TICK = 60
local SAVE_DEBOUNCE = 30

local DataManager = _G.DataManager
if not DataManager then
	local ok, DM = pcall(function()
		return require(script.Parent:WaitForChild("DataManager", 5))
	end)
	if ok then DataManager = DM end
end

local PetService = {}
local spawnedPetModels = {} -- [player] = { [unitUUID] = Model }
local lastSaveAt = {}       -- [player] = os.clock()

local eventsFolder = ReplicatedStorage:WaitForChild("Events")
local feedPetEvent = eventsFolder:WaitForChild("FeedPet") :: RemoteEvent
local toggleEquipEvent = eventsFolder:WaitForChild("ToggleEquipPet") :: RemoteEvent
local inventoryUpdateEvent = eventsFolder:WaitForChild("InventoryUpdate") :: RemoteEvent

-- ═══════════════════════════════════════════════════════
--  BILLBOARD
-- ═══════════════════════════════════════════════════════

local function updatePetBillboard(model, unitName, hunger)
	if not model then return end
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

		local bg = Instance.new("Frame"); bg.Name = "BG"; bg.Size = UDim2.new(1,0,1,0)
		bg.BackgroundColor3 = Color3.fromRGB(20,24,32); bg.BackgroundTransparency = 0.2; bg.Parent = bbGui
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,8); c.Parent = bg

		local title = Instance.new("TextLabel"); title.Name = "Title"; title.Size = UDim2.new(1,0,0,22)
		title.BackgroundTransparency = 1; title.TextColor3 = Color3.fromRGB(255,255,255)
		title.TextSize = 12; title.Font = Enum.Font.GothamBold; title.Parent = bg

		local barBG = Instance.new("Frame"); barBG.Name = "BarBG"
		barBG.Size = UDim2.new(1,-12,0,14); barBG.Position = UDim2.new(0,6,0,26)
		barBG.BackgroundColor3 = Color3.fromRGB(40,45,55); barBG.Parent = bg
		local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0,4); bc.Parent = barBG

		local fill = Instance.new("Frame"); fill.Name = "Fill"
		fill.Size = UDim2.new(1,0,1,0); fill.BackgroundColor3 = Color3.fromRGB(46,204,113); fill.Parent = barBG
		local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0,4); fc.Parent = fill
	end

	local bg = bbGui:FindFirstChild("BG")
	if bg then
		local title = bg:FindFirstChild("Title")
		if title then title.Text = string.format("%s (🍗 %d%%)", tostring(unitName or "?"), math.floor(hunger or 0)) end
		local barBG = bg:FindFirstChild("BarBG")
		if barBG then
			local fill = barBG:FindFirstChild("Fill")
			if fill then
				local h = math.clamp(hunger or 0, 0, 100)
				fill.Size = UDim2.new(h/100, 0, 1, 0)
				if h < 20 then fill.BackgroundColor3 = Color3.fromRGB(231,76,60)
				elseif h < 50 then fill.BackgroundColor3 = Color3.fromRGB(241,196,15)
				else fill.BackgroundColor3 = Color3.fromRGB(46,204,113) end
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════
--  SPAWN / UPDATE PET MODELS
-- ═══════════════════════════════════════════════════════

local function placeModelOnPad(model, pad, unit)
	if not model or not pad then return end
	local _, bboxSize = model:GetBoundingBox()
	local elev = math.clamp(bboxSize.Y/2, 1, 6) + 0.25
	unit.Rotation = unit.Rotation or 0
	local natRot = model:GetAttribute("NaturalRotation") or model:GetPivot().Rotation
	local rotCF = CFrame.Angles(0, math.rad(unit.Rotation), 0) * natRot.Rotation
	model:PivotTo(CFrame.new(pad.Position + Vector3.new(0, elev, 0)) * rotCF)
end

function PetService.UpdatePlayerPetModels(player)
	local data = DataManager.GetPlayerData(player)
	if not data or not data.Inventory then return end

	local careZone = Workspace:FindFirstChild("PetCareZone")
	if not careZone then
		careZone = Workspace:WaitForChild("PetCareZone", 10)
		if not careZone then
			warn("[PetService] PetCareZone не знайдено!")
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
	local pads = {}
	if padsFolder then
		for _, child in ipairs(padsFolder:GetChildren()) do
			if child:IsA("BasePart") and string.sub(child.Name, 1, 7) == "PetPad_" then
				table.insert(pads, child)
			end
		end
		table.sort(pads, function(a, b)
			local na = tonumber(string.match(a.Name, "%d+")) or 0
			local nb = tonumber(string.match(b.Name, "%d+")) or 0
			return na < nb
		end)
	end

	local padIndex = 1
	local activeUUIDs = {}

	for _, unit in ipairs(data.Inventory) do
		if unit.Equipped and padIndex <= #pads then
			activeUUIDs[unit.UUID] = true
			local itemConfig = ItemDatabase.GetItem(unit.ItemId)
			if itemConfig then
				local model = spawnedPetModels[player][unit.UUID]
				if not model or not model.Parent then
					model = ModelLoader.LoadUnitModel(unit.ItemId)
					model.Parent = playerPetFolder
					spawnedPetModels[player][unit.UUID] = model
				end
				local pad = pads[padIndex]
				placeModelOnPad(model, pad, unit)

				local prim = model.PrimaryPart or model:FindFirstChildOfClass("BasePart")
				if prim and not prim:FindFirstChild("RotatePrompt") then
					local p = Instance.new("ProximityPrompt")
					p.Name = "RotatePrompt"; p.ActionText = "Rotate (90°)"
					p.ObjectText = "🔄 " .. (model.Name or "Brainrot")
					p.MaxActivationDistance = 10; p.HoldDuration = 0.2; p.Parent = prim
					p.Triggered:Connect(function(triggeringPlayer)
						if triggeringPlayer ~= player then return end
						unit.Rotation = ((unit.Rotation or 0) + 90) % 360
						placeModelOnPad(model, pad, unit)
						inventoryUpdateEvent:FireClient(player, data.Inventory)
					end)
				end

				local displayName = model.Name or itemConfig.Name or unit.ItemId
				updatePetBillboard(model, displayName, unit.Hunger)
				padIndex = padIndex + 1
			end
		end
	end

	-- Прибрати моделі неекіпірованих / видалених
	for uuid, model in pairs(spawnedPetModels[player]) do
		if not activeUUIDs[uuid] then
			if model then model:Destroy() end
			spawnedPetModels[player][uuid] = nil
		end
	end
end

-- Оновлення тільки індикаторів голоду (легкий виклик з hunger-тіка)
local function refreshAllBillboardsForPlayer(player)
	local models = spawnedPetModels[player]
	if not models then return end
	local data = DataManager.GetPlayerData(player)
	if not data or not data.Inventory then return end
	local unitByName = {}
	for _, u in ipairs(data.Inventory) do unitByName[u.UUID] = u end
	for uuid, m in pairs(models) do
		local u = unitByName[uuid]
		if u then updatePetBillboard(m, m.Name, u.Hunger) end
	end
end

-- ═══════════════════════════════════════════════════════
--  LOOPS
-- ═══════════════════════════════════════════════════════

-- Пасивний дохід
task.spawn(function()
	while true do
		task.wait(INCOME_TICK)
		if not DataManager then continue end
		local now = os.time()
		for _, player in ipairs(Players:GetPlayers()) do
			local data = DataManager.GetPlayerData(player)
			if data and data.Inventory then
				local mult = 1.0
				if data.ActiveBuffs and now < (data.ActiveBuffs.IncomeBuffEndTime or 0) then
					mult = data.ActiveBuffs.IncomeMultiplier or 2.0
				end
				local total = 0
				for _, unit in ipairs(data.Inventory) do
					if unit.Equipped then
						local cfg = ItemDatabase.GetItem(unit.ItemId)
						if cfg then
							local inc = cfg.IncomeRate or 1
							if (unit.Hunger or 100) < 20 then inc = inc * 0.5 end
							total = total + inc * mult
						end
					end
				end
				if total > 0 then
					DataManager.AddBrainCells(player, math.floor(total))
					-- Збереження з debounce
					local last = lastSaveAt[player] or 0
					if (os.clock() - last) >= SAVE_DEBOUNCE then
						lastSaveAt[player] = os.clock()
						DataManager.RequestSave(player)
					end
				end
			end
		end
	end
end)

-- Зниження голоду
task.spawn(function()
	while true do
		task.wait(HUNGER_TICK)
		if not DataManager then continue end
		local changedPlayers = {}
		for _, player in ipairs(Players:GetPlayers()) do
			local data = DataManager.GetPlayerData(player)
			if data and data.Inventory then
				local changed = false
				for _, unit in ipairs(data.Inventory) do
					if (unit.Hunger or 0) > 0 then
						unit.Hunger = math.max(0, (unit.Hunger or 0) - 5)
						changed = true
					end
				end
				if changed then
					refreshAllBillboardsForPlayer(player)
					inventoryUpdateEvent:FireClient(player, data.Inventory)
					DataManager.RequestSave(player)
				end
			end
		end
	end
end)

-- ═══════════════════════════════════════════════════════
--  EVENT HANDLERS
-- ═══════════════════════════════════════════════════════

feedPetEvent.OnServerEvent:Connect(function(player, unitUUID)
	if type(unitUUID) ~= "string" then return end
	local data = DataManager.GetPlayerData(player)
	if not data then return end
	local targetUnit = DataManager.GetUnitByUUID(player, unitUUID)
	if not targetUnit then return end
	if (targetUnit.Hunger or 0) >= 100 then return end
	local ok = DataManager.AddBrainCells(player, -FEED_COST)
	if not ok then return end
	targetUnit.Hunger = 100
	updatePetBillboard(spawnedPetModels[player] and spawnedPetModels[player][unitUUID], nil, 100)
	inventoryUpdateEvent:FireClient(player, data.Inventory)
	DataManager.RequestSave(player)
end)

toggleEquipEvent.OnServerEvent:Connect(function(player, unitUUID)
	if type(unitUUID) ~= "string" then return end
	local data = DataManager.GetPlayerData(player)
	if not data then return end
	local targetUnit = DataManager.GetUnitByUUID(player, unitUUID)
	if not targetUnit then return end

	if not targetUnit.Equipped then
		-- Порахувати скільки вже екіпіровано
		local n = 0
		for _, u in ipairs(data.Inventory) do if u.Equipped then n = n + 1 end end
		if n >= MAX_EQUIPPED then return end
	end
	targetUnit.Equipped = not targetUnit.Equipped
	PetService.UpdatePlayerPetModels(player)
	inventoryUpdateEvent:FireClient(player, data.Inventory)
	DataManager.RequestSave(player)
end)

-- Клієнт може попросити редрав (наприклад після гучі)
inventoryUpdateEvent.OnServerEvent:Connect(function(player)
	PetService.UpdatePlayerPetModels(player)
end)

local function initPlayerPetModels(player)
	task.spawn(function()
		for _ = 1, 30 do
			if DataManager.GetPlayerData(player) then break end
			task.wait(0.5)
		end
		task.wait(1.5) -- Дочекатись побудови карти
		PetService.UpdatePlayerPetModels(player)
	end)
end

Players.PlayerAdded:Connect(initPlayerPetModels)
for _, p in ipairs(Players:GetPlayers()) do initPlayerPetModels(p) end

Players.PlayerRemoving:Connect(function(player)
	local models = spawnedPetModels[player]
	if models then
		for _, m in pairs(models) do if m then m:Destroy() end end
		spawnedPetModels[player] = nil
	end
	lastSaveAt[player] = nil
end)

_G.PetService = PetService
return PetService
