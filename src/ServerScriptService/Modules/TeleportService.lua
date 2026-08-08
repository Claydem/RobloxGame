--[[
	TeleportService.lua  v2.0
	ServerScriptService.Modules.TeleportService

	Забезпечує телепортацію між 3 зонами + Matchmaking Pad:
	  - Central Hub     (0, 4, 20)
	  - Pet Care Zone   (-200, 4, 0)
	  - Fight Club Arena(200, 4, 0)

	Працює через Touched + ProximityPrompt.
	Автоматично підхоплює нові пади при динамічній генерації карти.
--]]

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TeleportService = {}

-- ═══ Destination Map ═══════════════════════════════════
local DESTINATIONS = {
	TP_ToCare           = Vector3.new(-200, 4, 0),
	TP_ToArena          = Vector3.new(200, 4, 0),
	TP_ToHub_FromCare   = Vector3.new(0, 4, 20),
	TP_ToHub_FromArena  = Vector3.new(0, 4, 20),
}

-- ═══ Anti-spam ═════════════════════════════════════════
local debounce = {}
local COOLDOWN = 1.5

local function teleportPlayer(player: Player, destination: Vector3, padName: string)
	if not player or not player.Character then return end
	local char = player.Character
	local root = char:FindFirstChild("HumanoidRootPart")
	local hum  = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then return end

	local now  = os.clock()
	local last = debounce[player] or 0
	if now - last < COOLDOWN then return end
	debounce[player] = now

	-- Скидання швидкості та м'яке переміщення
	root.AssemblyLinearVelocity  = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	char:PivotTo(CFrame.new(destination))

	print(string.format("[TeleportService] 🌀 %s → %s (%s)", player.Name, padName, tostring(destination)))
end

-- ═══ Matchmaking Queue ═════════════════════════════════
local matchmakingQueue = {}

local function handleMatchmaking(player: Player)
	-- Якщо гравець вже у черзі — ігноруємо
	for _, p in ipairs(matchmakingQueue) do
		if p == player then return end
	end

	table.insert(matchmakingQueue, player)
	print(string.format("[TeleportService] ⚔️ %s додано до черги матчмейкінгу (%d у черзі)",
		player.Name, #matchmakingQueue))

	-- Перевірка пари
	if #matchmakingQueue >= 2 then
		local p1 = table.remove(matchmakingQueue, 1)
		local p2 = table.remove(matchmakingQueue, 1)

		-- Телепортуємо обох на ринг
		teleportPlayer(p1, Vector3.new(190, 4, 0), "MatchmakingPad")
		teleportPlayer(p2, Vector3.new(210, 4, 0), "MatchmakingPad")

		-- Запуск PvP бою через BattleService
		print(string.format("[TeleportService] ⚔️ Матч: %s vs %s!", p1.Name, p2.Name))
		if _G.BattleService then
			_G.BattleService.StartPvPBattle(p1, p2)
		end
	else
		-- Один гравець у черзі — через 8 сек запускаємо бій проти бота
		task.delay(8, function()
			for i, p in ipairs(matchmakingQueue) do
				if p == player then
					table.remove(matchmakingQueue, i)
					teleportPlayer(player, Vector3.new(190, 4, 0), "MatchmakingPad")
					print("[TeleportService] ⏰ Суперника не знайдено, запуск бою з ботом для " .. player.Name)
					if _G.BattleService then
						_G.BattleService.StartBotBattle(player)
					end
					break
				end
			end
		end)
	end
end

-- ═══ Pad Binding ═══════════════════════════════════════
local boundPads = {}

local function bindPad(pad: Instance)
	if not pad:IsA("BasePart") then return end
	if boundPads[pad] then return end -- уникаємо подвійної підписки
	boundPads[pad] = true

	local dest = DESTINATIONS[pad.Name]
	local isMatchmaking = (pad.Name == "MatchmakingPad")

	if not dest and not isMatchmaking then return end

	-- 1. ProximityPrompt
	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Triggered:Connect(function(player)
			if isMatchmaking then
				handleMatchmaking(player)
			else
				teleportPlayer(player, dest, pad.Name)
			end
		end)
	end

	-- 2. Touched
	pad.Touched:Connect(function(hit)
		local character = hit.Parent
		if not character then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end

		if isMatchmaking then
			handleMatchmaking(player)
		else
			teleportPlayer(player, dest, pad.Name)
		end
	end)

	print("[TeleportService] ✅ Підключено: " .. pad.Name .. (isMatchmaking and " (Matchmaking)" or ""))
end

-- ═══ Scanner ═══════════════════════════════════════════
local function scanAndBindAll()
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("BasePart") and (DESTINATIONS[desc.Name] or desc.Name == "MatchmakingPad") then
			bindPad(desc)
		end
	end

	Workspace.DescendantAdded:Connect(function(desc)
		if desc:IsA("BasePart") and (DESTINATIONS[desc.Name] or desc.Name == "MatchmakingPad") then
			task.wait(0.1) -- дрібна затримка, щоб ProximityPrompt встиг з'явитися
			bindPad(desc)
		end
	end)
end

-- ═══ Void Fall Protection ══════════════════════════════
task.spawn(function()
	while true do
		task.wait(0.5)
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and root.Position.Y < -25 then
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				char:PivotTo(CFrame.new(0, 4, 20))
				print(string.format("[TeleportService] 🛡️ Teleported %s back to Hub from void (Y: %.1f)", player.Name, root.Position.Y))
			end
		end
	end
end)

task.spawn(scanAndBindAll)

return TeleportService
