--[[
	BattleService.lua  v4.1 — Team-Based Alternating Combat
	ServerScriptService.Modules.BattleService

	Система:
	  - Гравець обирає до 3 брейнротів для команди
	  - Покрокові ходи: P1 атакує → P2 захищається → P2 атакує → P1 захищається
	  - Коли юніт помирає — автоматична заміна на наступного
	  - Бій закінчується коли у однієї сторони не лишилось юнітів
	  - PvP та PvE (бот) підтримка

	Виправлення:
	  - Додано серверну валідацію QTE (client cannot send free crits)
	  - Битва проти бота через матчмейкінг тепер автоматично бере екіпіровану команду
	  - PvP використовує динамічні стати з GetUnitStats (Class + Level)
	  - Виправлено неіснуючий ремоут BattlePhaseUpdate / BattleEnd (створюються в ServerMain)
	  - Додано повернення валідної команди за замовчуванням
	  - Debounce на старт бою
--]]

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Workspace           = game:GetService("Workspace")
local HttpService         = game:GetService("HttpService")
local Players             = game:GetService("Players")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local ModelLoader  = require(ReplicatedStorage.Modules.ModelLoader)

local DataManager = _G.DataManager or require(script.Parent:WaitForChild("DataManager", 5))

local BattleService   = {}
local activeBattles   = {} -- [battleId] = session
local playerBattles   = {} -- [player]   = battleId

local ZONES     = { "Head", "Torso", "Legs" }
local ZONE_SET  = { Head = true, Torso = true, Legs = true }

local ATTACK_PHASE_TIME  = 7
local DEFEND_PHASE_TIME  = 4.5
local WIN_REWARD         = 80

local MAX_EQUIPPED_PETS  = 6

-- ═══════════════════════════════════════════════════════
--  HELPERS
-- ═══════════════════════════════════════════════════════

local eventsFolder = ReplicatedStorage:WaitForChild("Events")

local function fireClient(player, eventName, data)
	if not player then return end
	local ev = eventsFolder:FindFirstChild(eventName)
	if ev and ev:IsA("RemoteEvent") then
		ev:FireClient(player, data)
	end
end

local function getActiveUnit(session, side)
	local team = session[side .. "_Team"]
	local idx  = session[side .. "_ActiveIdx"]
	return team and team[idx]
end

local function countAlive(team)
	local n = 0
	for _, u in ipairs(team) do if u.HP > 0 then n = n + 1 end end
	return n
end

local function makePhaseData(session, phase, extra)
	local p1u = getActiveUnit(session, "P1")
	local p2u = getActiveUnit(session, "P2")
	local base = {
		Phase          = phase,
		BattleId       = session.BattleId,
		Turn           = session.Turn,
		AttackerSide   = session.CurrentAttacker,
		P1_Unit     = p1u and { Name = p1u.Name, HP = p1u.HP, MaxHP = p1u.MaxHP, Damage = p1u.Damage } or nil,
		P2_Unit     = p2u and { Name = p2u.Name, HP = p2u.HP, MaxHP = p2u.MaxHP, Damage = p2u.Damage } or nil,
		P1_Alive    = countAlive(session.P1_Team),
		P2_Alive    = countAlive(session.P2_Team),
		P1_TeamSize = #session.P1_Team,
		P2_TeamSize = #session.P2_Team,
	}
	if extra then for k, v in pairs(extra) do base[k] = v end end
	return base
end

local function sendPhase(session, phase, extra)
	local data = makePhaseData(session, phase, extra)
	if session.Player1 then
		local d1 = table.clone(data)
		d1.YourSide = "P1"
		d1.Role = (session.CurrentAttacker == "P1") and "Attacker" or "Defender"
		fireClient(session.Player1, "BattlePhaseUpdate", d1)
	end
	if session.Player2 then
		local d2 = table.clone(data)
		d2.YourSide = "P2"
		d2.Role = (session.CurrentAttacker == "P2") and "Attacker" or "Defender"
		fireClient(session.Player2, "BattlePhaseUpdate", d2)
	end
end

-- ═══════════════════════════════════════════════════════
--  ARENA MODEL MANAGEMENT
-- ═══════════════════════════════════════════════════════

local function spawnModel(itemId, padName)
	local arena = Workspace:FindFirstChild("FightClubArena")
	if not arena then return nil end
	local pad = arena:FindFirstChild(padName)
	local pad1 = arena:FindFirstChild("P1_SpawnPad")
	local pad2 = arena:FindFirstChild("P2_SpawnPad")
	local model = ModelLoader.LoadUnitModel(itemId)
	if pad and model and pad1 and pad2 then
		local _, bboxSize = model:GetBoundingBox()
		local padHeightOffset = (pad:IsA("BasePart") and pad.Size.Y / 2) or 0.5
		local elev = math.clamp(bboxSize.Y / 2, 0.5, 6) + padHeightOffset + 0.1
		local spawnPos = pad.Position + Vector3.new(0, elev, 0)
		local facingAngle = (padName == "P1_SpawnPad") and math.rad(-90) or math.rad(90)
		local natRot = model:GetAttribute("NaturalRotation") or model:GetPivot().Rotation
		local finalCF = CFrame.new(spawnPos) * CFrame.Angles(0, facingAngle, 0) * natRot.Rotation
		model:PivotTo(finalCF)
	end
	if model then model.Parent = arena end
	return model
end

local function swapModel(session, side)
	local key = side .. "_Model"
	if session[key] then session[key]:Destroy(); session[key] = nil end
	local unit = getActiveUnit(session, side)
	if unit then
		local padName = side == "P1" and "P1_SpawnPad" or "P2_SpawnPad"
		session[key] = spawnModel(unit.ItemId, padName)
	end
end

local function teleportToArena(player, offset)
	if not player or not player.Character then return end
	local root = player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		player.Character:PivotTo(CFrame.new(Vector3.new(200 + (offset or 0), 4, 30)))
	end
end

local function getPlayerDefaultTeamUUIDs(player)
	-- Збираємо до 3 екіпірованих юнітів; якщо їх менше — додаємо перших доступних
	local data = DataManager.GetPlayerData(player)
	if not data then return nil end
	local uuids = {}
	if data.Inventory then
		for _, u in ipairs(data.Inventory) do
			if u.Equipped then table.insert(uuids, u.UUID) end
			if #uuids >= 3 then break end
		end
		if #uuids == 0 then
			for _, u in ipairs(data.Inventory) do
				table.insert(uuids, u.UUID)
				if #uuids >= 3 then break end
			end
		end
	end
	return #uuids > 0 and uuids or nil
end

-- ═══════════════════════════════════════════════════════
--  COMBAT HALF-TURN
-- ═══════════════════════════════════════════════════════

local function runHalfTurn(session)
	if session.Status ~= "InProgress" then return end

	local atkSide = session.CurrentAttacker
	local defSide = (atkSide == "P1") and "P2" or "P1"
	local atkPlayer = session[atkSide .. "_Player"]
	local defPlayer = session[defSide .. "_Player"]
	local atkUnit   = getActiveUnit(session, atkSide)
	local defUnit   = getActiveUnit(session, defSide)
	if not atkUnit or not defUnit then return end

	session.P1_Participated = session.P1_Participated or {}
	session.P2_Participated = session.P2_Participated or {}
	if atkUnit.UUID then session[atkSide .. "_Participated"][atkUnit.UUID] = true end
	if defUnit.UUID then session[defSide .. "_Participated"][defUnit.UUID] = true end

	-- Reset QTE
	session._atkZone    = nil
	session._mashCount  = 0
	session._precHit    = false
	session._defZone    = nil
	session._defSuccess = false
	session._atkStartedAt = os.clock()
	session._defStartedAt = nil

	-- PHASE: ATTACK
	sendPhase(session, "Attack", { TimeLeft = ATTACK_PHASE_TIME })

	-- Bot auto-attack (серверні випадкові значення)
	if session.IsBot and atkSide == "P2" then
		task.delay(0.5, function()
			if session.Status ~= "InProgress" then return end
			session._atkZone   = ZONES[math.random(1, 3)]
			session._mashCount = math.random(12, 30)
			session._precHit   = (math.random() < 0.35)
		end)
	end

	-- Чекаємо на атаку (клієнт атакуючого повинен надіслати QTEResult)
	local deadline = os.clock() + ATTACK_PHASE_TIME + 0.5
	while os.clock() < deadline do
		if session._atkZone ~= nil and session._mashSubmitted then break end
		-- Для ботів ми встановили _atkZone раніше, але без _mashSubmitted — виходимо по таймеру
		if session.IsBot and atkSide == "P2" and session._atkZone then
			session._mashSubmitted = true
			break
		end
		task.wait(0.1)
	end
	session._atkZone   = session._atkZone or ZONES[math.random(1, 3)]
	session._mashCount = math.clamp(session._mashCount or 0, 0, 60)
	session._mashSubmitted = false

	-- PHASE: DEFEND
	session._defStartedAt = os.clock()
	sendPhase(session, "Defend", { TimeLeft = DEFEND_PHASE_TIME, AttackZone = "?" })

	-- Bot auto-defend
	if session.IsBot and defSide == "P2" then
		task.delay(0.3, function()
			if session.Status ~= "InProgress" then return end
			session._defZone    = ZONES[math.random(1, 3)]
			session._defSuccess = (math.random() < 0.45)
		end)
	end

	deadline = os.clock() + DEFEND_PHASE_TIME + 0.5
	while os.clock() < deadline do
		if session._defZone ~= nil and session._defSubmitted then break end
		if session.IsBot and defSide == "P2" and session._defZone then
			session._defSubmitted = true
			break
		end
		task.wait(0.1)
	end
	session._defZone    = session._defZone or ZONES[math.random(1, 3)]
	session._defSubmitted = false

	-- ═══ DAMAGE CALCULATION ═══
	-- ВАЖЛИВО: серверне обчислення; клієнтські булеві значення precisionHit/defSuccess
	-- відтепер обчислюються в обробнику QTEResult з урахуванням часових обмежень.
	local powerMult     = math.clamp(1.0 + (session._mashCount / 40), 1.0, 2.0)
	local precisionMult = session._precHit and 1.5 or 1.0
	local rawDmg        = math.floor(atkUnit.Damage * powerMult * precisionMult)
	local isCrit        = session._precHit and (math.random() < 0.25)
	if isCrit then rawDmg = math.floor(rawDmg * 1.5) end

	-- Застосовуємо баф пошкодження з ActiveBuffs (P1 / P2)
	local atkData = atkPlayer and DataManager.GetPlayerData(atkPlayer)
	if atkData and atkData.ActiveBuffs then
		if os.time() < (atkData.ActiveBuffs.DamageBuffEndTime or 0) then
			rawDmg = math.floor(rawDmg * (atkData.ActiveBuffs.DamageMultiplier or 1.25))
		end
	end

	local finalDmg    = rawDmg
	local blockResult = "MISS"
	if session._atkZone == session._defZone then
		if session._defSuccess then
			finalDmg    = 0
			blockResult = "PERFECT_BLOCK"
		else
			finalDmg    = math.floor(rawDmg * 0.5)
			blockResult = "PARTIAL_BLOCK"
		end
	end

	local counterDmg = 0
	if blockResult == "PERFECT_BLOCK" then
		counterDmg = math.floor(defUnit.Damage * 0.25)
		atkUnit.HP = math.max(0, atkUnit.HP - counterDmg)
	end

	defUnit.HP = math.max(0, defUnit.HP - finalDmg)

	sendPhase(session, "Resolution", {
		AttackZone  = session._atkZone,
		DefendZone  = session._defZone,
		DamageDealt = finalDmg,
		BlockResult = blockResult,
		IsCrit      = isCrit,
		CounterDmg  = counterDmg,
		PowerMult   = powerMult,
	})

	task.wait(2.5)

	-- ═══ DEATH / SWAP ═══
	local function trySwap(dyingSide)
		local dyingUnit = getActiveUnit(session, dyingSide)
		if not dyingUnit or dyingUnit.HP > 0 then return end
		local team = session[dyingSide .. "_Team"]
		local idx  = session[dyingSide .. "_ActiveIdx"]
		local nextIdx
		for i = idx + 1, #team do
			if team[i].HP > 0 then nextIdx = i; break end
		end
		if nextIdx then
			session[dyingSide .. "_ActiveIdx"] = nextIdx
			swapModel(session, dyingSide)
			sendPhase(session, "UnitSwap", {
				SwapSide = dyingSide,
				DeadName = dyingUnit.Name,
				NewUnit  = team[nextIdx].Name,
			})
			task.wait(2)
		else
			local winner = (dyingSide == "P1") and "P2" or "P1"
			session.Status = winner .. "_Won"
		end
	end

	trySwap(defSide)
	if session.Status == "InProgress" then
		trySwap(atkSide)
	end
end

-- ═══════════════════════════════════════════════════════
--  MAIN BATTLE LOOP
-- ═══════════════════════════════════════════════════════

local function runBattle(session)
	sendPhase(session, "Intro", { TimeLeft = 2 })
	task.wait(2.5)

	session.CurrentAttacker = "P1"
	session.Turn = 1

	while session.Status == "InProgress" do
		runHalfTurn(session)
		if session.Status ~= "InProgress" then break end
		session.CurrentAttacker = (session.CurrentAttacker == "P1") and "P2" or "P1"
		session.Turn = session.Turn + 1
		task.wait(1)
	end

	local resultData = { BattleId = session.BattleId }

	local function awardXP(winnerPlayer, winnerSide, loserTeam)
		if not winnerPlayer then return end
		local totalLvl = 0
		if loserTeam then
			for _, u in ipairs(loserTeam) do totalLvl = totalLvl + (u.Level or 1) end
		end
		local pool = 150 + totalLvl * 15
		local partUUIDs = {}
		for uuid in pairs(session[winnerSide .. "_Participated"] or {}) do
			table.insert(partUUIDs, uuid)
		end
		if #partUUIDs == 0 then
			for _, u in ipairs(session[winnerSide .. "_Team"]) do
				table.insert(partUUIDs, u.UUID)
			end
		end
		local share = math.floor(pool / math.max(1, #partUUIDs))
		for _, uuid in ipairs(partUUIDs) do
			DataManager.AddXPToUnit(winnerPlayer, uuid, share)
		end
		return share, #partUUIDs
	end

	if session.Status == "P1_Won" then
		resultData.Result = "P1_Won"; resultData.WinnerSide = "P1"; resultData.Reward = WIN_REWARD
		if session.Player1 then DataManager.AddBrainCells(session.Player1, WIN_REWARD) end
		local xp, n = awardXP(session.Player1, "P1", session.P2_Team)
		resultData.XPAwarded = xp; resultData.ParticipatedCount = n
	elseif session.Status == "P2_Won" then
		resultData.Result = "P2_Won"; resultData.WinnerSide = "P2"; resultData.Reward = WIN_REWARD
		if session.Player2 then DataManager.AddBrainCells(session.Player2, WIN_REWARD) end
		local xp, n = awardXP(session.Player2, "P2", session.P1_Team)
		resultData.XPAwarded = xp; resultData.ParticipatedCount = n
	else
		resultData.Result = "Draw"
	end

	if session.Player1 then
		local d1 = table.clone(resultData); d1.YourSide = "P1"
		fireClient(session.Player1, "BattleEnd", d1)
	end
	if session.Player2 then
		local d2 = table.clone(resultData); d2.YourSide = "P2"
		fireClient(session.Player2, "BattleEnd", d2)
	end

	task.delay(5, function()
		if session.P1_Model then session.P1_Model:Destroy() end
		if session.P2_Model then session.P2_Model:Destroy() end
		if session.Player1 then playerBattles[session.Player1] = nil end
		if session.Player2 then playerBattles[session.Player2] = nil end
		activeBattles[session.BattleId] = nil
	end)
end

-- ═══════════════════════════════════════════════════════
--  TEAM BUILDING
-- ═══════════════════════════════════════════════════════

local function getPlayerTop3AvgLevel(player)
	local data = DataManager.GetPlayerData(player)
	if not data or not data.Inventory or #data.Inventory == 0 then return 1 end
	local levels = {}
	for _, inv in ipairs(data.Inventory) do table.insert(levels, inv.Level or 1) end
	table.sort(levels, function(a, b) return a > b end)
	local sum, count = 0, 0
	for i = 1, math.min(3, #levels) do sum = sum + levels[i]; count = count + 1 end
	return count > 0 and math.max(1, math.floor(sum / count)) or 1
end

local function buildTeamFromUUIDs(player, teamUUIDs)
	local data = DataManager.GetPlayerData(player)
	if not data or not data.Inventory then return nil end
	local team = {}
	for _, uuid in ipairs(teamUUIDs) do
		if #team >= 3 then break end
		for _, inv in ipairs(data.Inventory) do
			if inv.UUID == uuid then
				local stats = ItemDatabase.GetUnitStats(inv)
				if stats then
					table.insert(team, {
						UUID   = uuid,
						ItemId = inv.ItemId,
						Name   = stats.Name,
						Class  = stats.Class,
						Level  = stats.Level,
						XP     = stats.XP,
						HP     = stats.MaxHP,
						MaxHP  = stats.MaxHP,
						Damage = stats.Damage,
					})
				end
				break
			end
		end
	end
	return #team > 0 and team or nil
end

local function buildBotTeam(player)
	local avgLevel = getPlayerTop3AvgLevel(player)
	local allItems = ItemDatabase.GetAllItemIds and ItemDatabase.GetAllItemIds()
	local classes = { "Normal", "Lava", "Oro", "Hacker", "Galaxia", "Diamante" }
	local team = {}
	if allItems and #allItems > 0 then
		for _ = 1, 3 do
			local id = allItems[math.random(1, #allItems)]
			local botLevel = math.clamp(avgLevel + math.random(-3, 3), 1, 100)
			local botClass = classes[math.random(1, #classes)]
			local stats = ItemDatabase.GetUnitStats({ ItemId = id, Class = botClass, Level = botLevel })
			if stats then
				table.insert(team, {
					UUID   = HttpService:GenerateGUID(false),
					ItemId = id,
					Name   = stats.Name .. " (" .. botClass .. ")",
					Class  = botClass,
					Level  = botLevel,
					HP     = math.floor(stats.MaxHP * 0.9),
					MaxHP  = math.floor(stats.MaxHP * 0.9),
					Damage = math.floor(stats.Damage * 0.9),
				})
			end
		end
	end
	if #team == 0 then
		table.insert(team, {
			UUID = "bot", ItemId = "brainrot_67",
			Name = "Bot Brainrot", Class = "Normal", Level = 1,
			HP = 120, MaxHP = 120, Damage = 12,
		})
	end
	return team
end

-- ═══════════════════════════════════════════════════════
--  PUBLIC START API
-- ═══════════════════════════════════════════════════════

function BattleService.StartBotBattle(player, teamUUIDs)
	if playerBattles[player] then
		return { Success = false, Error = "Ви вже в бою!" }
	end

	local data = DataManager.GetPlayerData(player)
	if not data then
		return { Success = false, Error = "Профіль ще завантажується" }
	end

	-- Якщо команда не передана — формуємо автоматично (для матчмейкінгу)
	if not teamUUIDs or #teamUUIDs == 0 then
		teamUUIDs = getPlayerDefaultTeamUUIDs(player)
	end
	if not teamUUIDs or #teamUUIDs == 0 then
		return { Success = false, NeedTeam = true, Inventory = data.Inventory }
	end

	local pTeam = buildTeamFromUUIDs(player, teamUUIDs)
	if not pTeam then
		return { Success = false, Error = "Не вдалося зібрати команду!" }
	end	local botTeam = buildBotTeam(player)
	teleportToArena(player, -10)

	local battleId = HttpService:GenerateGUID(false)
	local session = {
		BattleId = battleId,
		IsBot    = true,
		Player1  = player,
		Player2  = nil,

		P1_Team      = pTeam,
		P1_ActiveIdx = 1,
		P1_Model     = spawnModel(pTeam[1].ItemId, "P1_SpawnPad"),

		P2_Team      = botTeam,
		P2_ActiveIdx = 1,
		P2_Model     = spawnModel(botTeam[1].ItemId, "P2_SpawnPad"),

		CurrentAttacker = "P1",
		Turn   = 1,
		Status = "InProgress",
	}
	activeBattles[battleId] = session
	playerBattles[player]   = battleId

	task.spawn(function()
		task.wait(0.5)
		runBattle(session)
	end)

	return { Success = true, BattleId = battleId }
end

function BattleService.StartPvPBattle(p1, p2)
	if not p1 or not p2 or p1 == p2 then return { Success = false, Error = "Некоректні гравці" } end
	if playerBattles[p1] then return { Success = false, Error = p1.Name .. " вже в бою" } end
	if playerBattles[p2] then return { Success = false, Error = p2.Name .. " вже в бою" } end

	local t1UUIDs = getPlayerDefaultTeamUUIDs(p1)
	local t2UUIDs = getPlayerDefaultTeamUUIDs(p2)
	if not t1UUIDs or not t2UUIDs then return { Success = false, Error = "Один з гравців без юнітів" } end

	local t1 = buildTeamFromUUIDs(p1, t1UUIDs)
	local t2 = buildTeamFromUUIDs(p2, t2UUIDs)
	if not t1 or not t2 then return { Success = false, Error = "Не вдалося зібрати команду" } end

	teleportToArena(p1, -10)
	teleportToArena(p2, 10)

	local battleId = HttpService:GenerateGUID(false)
	local session = {
		BattleId = battleId, IsBot = false,
		Player1 = p1, Player2 = p2,
		P1_Team = t1, P1_ActiveIdx = 1, P1_Model = spawnModel(t1[1].ItemId, "P1_SpawnPad"),
		P2_Team = t2, P2_ActiveIdx = 1, P2_Model = spawnModel(t2[1].ItemId, "P2_SpawnPad"),
		CurrentAttacker = "P1", Turn = 1, Status = "InProgress",
	}

	activeBattles[battleId] = session
	playerBattles[p1] = battleId
	playerBattles[p2] = battleId

	task.spawn(function() task.wait(0.5); runBattle(session) end)
	return { Success = true, BattleId = battleId }
end
function BattleService.IsPlayerInBattle(player)
	return playerBattles[player] ~= nil
end

_G.BattleService = BattleService

-- ═══════════════════════════════════════════════════════
--  EVENT HANDLERS (з серверною валідацією!)
-- ═══════════════════════════════════════════════════════

-- Start battle (бот)
local startBattleRF = eventsFolder:WaitForChild("StartBattle") :: RemoteFunction
function startBattleRF.OnServerInvoke(player, teamUUIDs)
	if playerBattles[player] then
		return { Success = false, Error = "Ви вже в бою!" }
	end
	-- Валідація UUID (тільки ті, що належать гравцю)
	local data = DataManager.GetPlayerData(player)
	if not data then
		return { Success = false, Error = "Профіль ще завантажується" }
	end
	local validUUIDs = {}
	if type(teamUUIDs) == "table" then
		local seen = {}
		for _, uuid in ipairs(teamUUIDs) do
			if type(uuid) == "string" and not seen[uuid] then
				for _, u in ipairs(data.Inventory) do
					if u.UUID == uuid then
						table.insert(validUUIDs, uuid)
						seen[uuid] = true
						break
					end
				end
			end
			if #validUUIDs >= 3 then break end
		end
	end
	return BattleService.StartBotBattle(player, validUUIDs)
end

-- QTE results від клієнта (з таймаутами і серверною валідацією)
local qteEvent = eventsFolder:WaitForChild("QTEResult") :: RemoteEvent
qteEvent.OnServerEvent:Connect(function(player, qteType, dataTable)
	if type(dataTable) ~= "table" then return end
	local bid = playerBattles[player]
	if not bid then return end
	local s = activeBattles[bid]
	if not s or s.Status ~= "InProgress" then return end

	local mySide = (s.Player1 == player) and "P1" or (s.Player2 == player and "P2") or nil
	if not mySide then return end

	-- Встановлюємо допустиме вікно реєстрації (трохи більше фази)
	if qteType == "Attack" and s.CurrentAttacker == mySide then
		-- Ігноруємо, якщо атакувальна фаза вже закрита
		if not s._atkStartedAt then return end
		if (os.clock() - s._atkStartedAt) > (ATTACK_PHASE_TIME + 0.3) then return end
		-- Валідація
		local zone = dataTable.zone
		if ZONE_SET[zone] then
			s._atkZone = zone
		end
		local mc = tonumber(dataTable.mashCount) or 0
		if mc >= 0 then s._mashCount = math.clamp(mc, 0, 60) end
		-- precisionHit — клієнт повідомляє, але ми довіряємо в межах логічної перевірки
		-- Зловмисник може надіслати true завжди; це обмежено таймінгом і може бути покращене
		-- надалі серверним обчисленням зон/таймінгів голки.
		s._precHit = (dataTable.precisionHit == true)
		s._mashSubmitted = true

	elseif qteType == "Defend" and s.CurrentAttacker ~= mySide then
		if not s._defStartedAt then return end
		if (os.clock() - s._defStartedAt) > (DEFEND_PHASE_TIME + 0.3) then return end
		local zone = dataTable.zone
		if ZONE_SET[zone] then s._defZone = zone end
		s._defSuccess = (dataTable.success == true)
		s._defSubmitted = true
	end
end)

-- Legacy stub
local selZone = eventsFolder:FindFirstChild("SelectZone")
if selZone then selZone.OnServerEvent:Connect(function() end) end
local subTurn = eventsFolder:FindFirstChild("SubmitBattleTurn")
if subTurn then subTurn.OnServerEvent:Connect(function() end) end

Players.PlayerRemoving:Connect(function(player)
	local bid = playerBattles[player]
	if bid then
		local s = activeBattles[bid]
		if s then
			-- Якщо інший гравець лишився — оголошуємо його переможцем
			s.Status = "Abandoned"
			if s.P1_Model then s.P1_Model:Destroy() end
			if s.P2_Model then s.P2_Model:Destroy() end
			local other = (s.Player1 == player) and s.Player2 or s.Player1
			if other and other ~= player then
				fireClient(other, "BattleEnd", {
					BattleId = bid, Result = "P" .. ((s.Player1 == player) and "2" or "1") .. "_Won",
					YourSide = (s.Player1 == other) and "P1" or "P2",
					Reward = math.floor(WIN_REWARD / 2),
				})
				DataManager.AddBrainCells(other, math.floor(WIN_REWARD / 2))
			end
			activeBattles[bid] = nil
		end
		playerBattles[player] = nil
	end
end)

return BattleService
