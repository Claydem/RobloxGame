--[[
	TeleportService.lua  v2.1
	ServerScriptService.Modules.TeleportService

	Виправлення:
	- Матчмейкінг проти бота передає правильну команду (через дефолт BattleService)
	- Debounce для MatchmakingPad по Touched і по ProximityPrompt
	- Перевірка що обидва гравці досі в грі перед PvP
	- Більш надійна перевірка падіння в void
	- Знято дублювання викликів handleMatchmaking (Тouched + Prompt)
--]]

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TeleportService = {}

local DESTINATIONS = {
	TP_ToCare           = Vector3.new(-200, 4, 0),
	TP_ToArena          = Vector3.new(200, 4, 0),
	TP_ToHub_FromCare   = Vector3.new(0, 4, 20),
	TP_ToHub_FromArena  = Vector3.new(0, 4, 20),
}

local TELEPORT_COOLDOWN = 1.5
local MM_COOLDOWN = 3.0

local debounce = {}
local mmDebounce = {}
local inQueue = {} -- player -> true

local function teleportPlayer(player, destination, padName)
	if not player or not player.Character then return end
	local char = player.Character
	local root = char:FindFirstChild("HumanoidRootPart")
	local hum  = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then return end
	local now  = os.clock()
	local last = debounce[player] or 0
	if now - last < TELEPORT_COOLDOWN then return end
	debounce[player] = now

	root.AssemblyLinearVelocity  = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	char:PivotTo(CFrame.new(destination))
	print(string.format("[TeleportService] 🌀 %s → %s (%s)", player.Name, padName or "?", tostring(destination)))
end

-- ═══════════════════════════════════════════════════════
--  MATCHMAKING
-- ═══════════════════════════════════════════════════════

local matchmakingQueue = {}

local function removeFromQueue(player)
	inQueue[player] = nil
	for i, p in ipairs(matchmakingQueue) do
		if p == player then table.remove(matchmakingQueue, i); return true end
	end
	return false
end

local function handleMatchmaking(player)
	if not player or not player:IsDescendantOf(Players) then return end
	-- Перевіряємо через _G.BattleService, чи гравець вже у битві
	local alreadyInBattle = false
	if _G.BattleService and type(_G.BattleService.IsPlayerInBattle) == "function" then
		alreadyInBattle = _G.BattleService.IsPlayerInBattle(player)
	end
	if alreadyInBattle then return end

	local now = os.clock()
	if (mmDebounce[player] or 0) + MM_COOLDOWN > now then return end
	mmDebounce[player] = now

	-- Не додаємо вдруге
	if inQueue[player] then return end
	table.insert(matchmakingQueue, player)
	inQueue[player] = true
	print(string.format("[TeleportService] ⚔️ %s у черзі (%d)", player.Name, #matchmakingQueue))

	if #matchmakingQueue >= 2 then
		local p1 = table.remove(matchmakingQueue, 1)
		local p2 = table.remove(matchmakingQueue, 1)
		inQueue[p1] = nil; inQueue[p2] = nil
		if p1:IsDescendantOf(Players) and p2:IsDescendantOf(Players) then
			teleportPlayer(p1, Vector3.new(190, 4, 30), "MatchmakingPad")
			teleportPlayer(p2, Vector3.new(210, 4, 30), "MatchmakingPad")
			task.wait(0.5)
			if _G.BattleService then
				local res = _G.BattleService.StartPvPBattle(p1, p2)
				if res and res.Success then
					print(string.format("[TeleportService] ⚔️ PvP: %s vs %s", p1.Name, p2.Name))
				else
					warn("[TeleportService] PvP не стартував: " .. tostring(res and res.Error or "?"))
				end
			end
		else
			-- Повернути того хто залишився до черги
			if p1:IsDescendantOf(Players) then table.insert(matchmakingQueue, 1, p1); inQueue[p1] = true end
			if p2:IsDescendantOf(Players) then table.insert(matchmakingQueue, 1, p2); inQueue[p2] = true end
		end
	else
		-- Чекаємо 8 сек, потім бій з ботом
		task.delay(8, function()
			if not inQueue[player] then return end
			removeFromQueue(player)
			if not player:IsDescendantOf(Players) then return end
			if _G.BattleService and not (playerBattles and playerBattles[player]) then
				teleportPlayer(player, Vector3.new(190, 4, 30), "MatchmakingPad")
				task.wait(0.5)
				local res = _G.BattleService.StartBotBattle(player) -- команда обереться автоматично
				if not res or not res.Success then
					warn("[TeleportService] Bot battle failed: " .. tostring(res and res.Error or "?"))
				end
			end
		end)
	end
end

-- ═══════════════════════════════════════════════════════
--  PAD BINDING
-- ═══════════════════════════════════════════════════════

local boundPads = {}

local function bindPad(pad)
	if not pad:IsA("BasePart") then return end
	if boundPads[pad] then return end
	boundPads[pad] = true

	local dest = DESTINATIONS[pad.Name]
	local isMM = (pad.Name == "MatchmakingPad")
	if not dest and not isMM then return end

	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Triggered:Connect(function(player)
			if isMM then handleMatchmaking(player)
			else teleportPlayer(player, dest, pad.Name) end
		end)
	end

	-- Додамо локальний debounce для Touched (наpad), щоб не спамити
	local touchCooldown = {}
	pad.Touched:Connect(function(hit)
		local character = hit.Parent
		if not character then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end
		local now = os.clock()
		if (touchCooldown[player] or 0) + 1.5 > now then return end
		touchCooldown[player] = now
		if isMM then
			handleMatchmaking(player)
		else
			teleportPlayer(player, dest, pad.Name)
		end
	end)

	print("[TeleportService] ✅ Підключено: " .. pad.Name .. (isMM and " (Matchmaking)" or ""))
end

local function scanAndBindAll()
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("BasePart") and (DESTINATIONS[desc.Name] or desc.Name == "MatchmakingPad") then
			bindPad(desc)
		end
	end
	Workspace.DescendantAdded:Connect(function(desc)
		if desc:IsA("BasePart") and (DESTINATIONS[desc.Name] or desc.Name == "MatchmakingPad") then
			task.wait(0.1)
			bindPad(desc)
		end
	end)
end

-- ═══════════════════════════════════════════════════════
--  VOID FALL PROTECTION
-- ═══════════════════════════════════════════════════════

task.spawn(function()
	while true do
		task.wait(0.5)
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local hum  = char and char:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 and root.Position.Y < -25 then
				local now = os.clock()
				if (debounce[player] or 0) + 1.0 > now then continue end
				debounce[player] = now
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				char:PivotTo(CFrame.new(0, 4, 20))
				print(string.format("[TeleportService] 🛡️ %s повернено до Hub з void (Y=%.1f)", player.Name, root.Position.Y))
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	removeFromQueue(player)
	debounce[player] = nil
	mmDebounce[player] = nil
end)

task.spawn(scanAndBindAll)

return TeleportService
