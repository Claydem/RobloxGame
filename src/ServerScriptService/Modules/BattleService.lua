--[[
	BattleService.lua  v4.0 — Team-Based Alternating Combat
	ServerScriptService.Modules.BattleService

	Система:
	  - Гравець обирає до 3 брейнротів для команди
	  - Покрокові ходи: P1 атакує → P2 захищається → P2 атакує → P1 захищається
	  - Коли юніт помирає — автоматична заміна на наступного
	  - Бій закінчується коли у однієї сторони не лишилось юнітів
	  - PvP та PvE (бот) підтримка
--]]

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace           = game:GetService("Workspace")
local HttpService         = game:GetService("HttpService")
local Players             = game:GetService("Players")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local ModelLoader  = require(ReplicatedStorage.Modules.ModelLoader)

local function getDataManager()
	if _G.DataManager then return _G.DataManager end
	return require(ServerScriptService:WaitForChild("DataManager"))
end

local BattleService   = {}
local activeBattles   = {} -- [battleId] = session
local playerBattles   = {} -- [player]   = battleId

local ZONES     = { "Head", "Torso", "Legs" }
local ZONE_SET  = { Head = true, Torso = true, Legs = true }

local ATTACK_PHASE_TIME  = 7   -- zone(3s) + mash(2.5s) + precision(1.5s)
local DEFEND_PHASE_TIME  = 4.5 -- zone(2.5s) + timing(2s)
local WIN_REWARD         = 80

-- ═══════════════════════════════════════════════════════
--  HELPERS
-- ═══════════════════════════════════════════════════════

local function fireClient(player, eventName, data)
	if not player then return end
	local ev = ReplicatedStorage:FindFirstChild("Events")
	if ev and ev:FindFirstChild(eventName) then
		ev[eventName]:FireClient(player, data)
	end
end

local function getActiveUnit(session, side)
	local team = session[side .. "_Team"]
	local idx  = session[side .. "_ActiveIdx"]
	return team and team[idx]
end

local function countAlive(team)
	local n = 0
	for _, u in ipairs(team) do
		if u.HP > 0 then n = n + 1 end
	end
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
	if extra then
		for k, v in pairs(extra) do base[k] = v end
	end
	return base
end

local function sendPhase(session, phase, extra)
	local data = makePhaseData(session, phase, extra)
	if session.Player1 then
		data.YourSide = "P1"
		data.Role = (session.CurrentAttacker == "P1") and "Attacker" or "Defender"
		fireClient(session.Player1, "BattlePhaseUpdate", data)
	end
	if session.Player2 then
		local d2 = {}
		for k, v in pairs(data) do d2[k] = v end
		d2.YourSide = "P2"
		d2.Role = (session.CurrentAttacker == "P2") and "Attacker" or "Defender"
		fireClient(session.Player2, "BattlePhaseUpdate", d2)
	end
end

-- ═══════════════════════════════════════════════════════
--  ARENA MODEL MANAGEMENT
-- ═══════════════════════════════════════════════════════

local function spawnModel(arena, itemId, padName)
	if not arena then return nil end
	local pad1 = arena:FindFirstChild("P1_SpawnPad")
	local pad2 = arena:FindFirstChild("P2_SpawnPad")
	local pad = arena:FindFirstChild(padName)
	local model = ModelLoader.LoadUnitModel(itemId)
	if pad and model and pad1 and pad2 then
		local _, bboxSize = model:GetBoundingBox()
		local padHeightOffset = (pad:IsA("BasePart") and pad.Size.Y / 2) or 0.5
		local elev = math.clamp(bboxSize.Y / 2, 0.5, 6) + padHeightOffset + 0.1

		local spawnPos = pad.Position + Vector3.new(0, elev, 0)

		-- P1 (X=190) дивиться на +X (до P2), P2 (X=210) дивиться на -X (до P1)
		local facingAngle = (padName == "P1_SpawnPad") and math.rad(-90) or math.rad(90)
		local natRot = model:GetAttribute("NaturalRotation") or model:GetPivot().Rotation

		-- Застосовуємо позицію, поворот до суперника ТА оригінальне збережене обертання моделі
		local finalCF = CFrame.new(spawnPos) * CFrame.Angles(0, facingAngle, 0) * natRot.Rotation
		model:PivotTo(finalCF)
	end
	model.Parent = arena
	return model
end

local function swapModel(session, side)
	-- Destroy old model
	local modelKey = side .. "_Model"
	if session[modelKey] then
		session[modelKey]:Destroy()
		session[modelKey] = nil
	end
	-- Spawn new model for active unit
	local unit = getActiveUnit(session, side)
	if unit then
		local padName = side == "P1" and "P1_SpawnPad" or "P2_SpawnPad"
		session[modelKey] = spawnModel(session.ArenaFolder, unit.ItemId, padName)
	end
end

local function teleportToArena(player, pos)
	if not player or not player.Character then return end
	local root = player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		player.Character:PivotTo(CFrame.new(pos))
	end
end

local function teleportToBase(player)
	if not player or not player.Character then return end
	local root = player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		local baseFolder = Workspace:FindFirstChild("Base_" .. player.UserId)
		if baseFolder then
			local spawnLoc = baseFolder:FindFirstChild("SpawnLocation")
			if spawnLoc then
				player.Character:PivotTo(CFrame.new(spawnLoc.Position + Vector3.new(0, 3, 10)))
				return
			end
		end
		player.Character:PivotTo(CFrame.new(0, 4, 20))
	end
end

-- ═══════════════════════════════════════════════════════
--  COMBAT HALF-TURN
-- ═══════════════════════════════════════════════════════

local function runHalfTurn(session)
	if session.Status ~= "InProgress" then return end

	-- ──── BURN DOT (Lava class) ────────────────────────
	if session._pendingBurnDmg and session._pendingBurnDmg > 0 and session._pendingBurnTarget then
		local burnTarget = getActiveUnit(session, session._pendingBurnTarget)
		if burnTarget and burnTarget.HP > 0 then
			local burnDmg = session._pendingBurnDmg
			burnTarget.HP = math.max(0, burnTarget.HP - burnDmg)
			sendPhase(session, "BurnDot", {
				BurnTarget = session._pendingBurnTarget,
				BurnDamage = burnDmg,
				TargetName = burnTarget.Name,
				TargetHP = burnTarget.HP,
				TargetMaxHP = burnTarget.MaxHP,
			})
			task.wait(1)
			-- Check if burn killed the unit
			if burnTarget.HP <= 0 then
				local burnSide = session._pendingBurnTarget
				local burnTeam = session[burnSide .. "_Team"]
				local burnIdx = session[burnSide .. "_ActiveIdx"]
				local nextIdx = nil
				for i = burnIdx + 1, #burnTeam do
					if burnTeam[i].HP > 0 then nextIdx = i; break end
				end
				if nextIdx then
					session[burnSide .. "_ActiveIdx"] = nextIdx
					swapModel(session, burnSide)
					sendPhase(session, "UnitSwap", {
						SwapSide = burnSide,
						DeadName = burnTarget.Name,
						NewUnit = burnTeam[nextIdx].Name,
					})
					task.wait(2)
				else
					local otherSide = burnSide == "P1" and "P2" or "P1"
					session.Status = otherSide .. "_Won"
				end
			end
		end
		session._pendingBurnDmg = 0
		session._pendingBurnTarget = nil
	end
	if session.Status ~= "InProgress" then return end

	local atkSide = session.CurrentAttacker
	local defSide = (atkSide == "P1") and "P2" or "P1"
	local atkPlayer = session[atkSide .. "_Player"]
	local defPlayer = session[defSide .. "_Player"]
	local atkUnit   = getActiveUnit(session, atkSide)
	local defUnit   = getActiveUnit(session, defSide)

	if not atkUnit or not defUnit then return end

	-- Track participation
	session.P1_Participated = session.P1_Participated or {}
	session.P2_Participated = session.P2_Participated or {}

	if atkUnit and atkUnit.UUID then
		session[atkSide .. "_Participated"][atkUnit.UUID] = true
	end
	if defUnit and defUnit.UUID then
		session[defSide .. "_Participated"][defUnit.UUID] = true
	end

	-- Reset temp data
	session._atkZone     = nil
	session._mashCount   = 0
	session._precHit     = false
	session._defZone     = nil
	session._defSuccess  = false

	-- ──── PHASE: ATTACK ───────────────────────────────
	sendPhase(session, "Attack", { TimeLeft = ATTACK_PHASE_TIME })

	-- Bot auto-attack
	if session.IsBot and atkSide == "P2" then
		task.delay(0.5, function()
			session._atkZone   = ZONES[math.random(1, 3)]
			session._mashCount = math.random(12, 30)
			session._precHit   = (math.random() < 0.35)
		end)
	end

	-- Wait for attacker data
	local deadline = os.clock() + ATTACK_PHASE_TIME + 0.5
	while os.clock() < deadline do
		if session._atkZone and session._mashCount > 0 then break end
		task.wait(0.15)
	end
	session._atkZone = session._atkZone or ZONES[math.random(1, 3)]

	-- ──── PHASE: DEFEND ───────────────────────────────
	sendPhase(session, "Defend", {
		TimeLeft   = DEFEND_PHASE_TIME,
		AttackZone = session.IsBot and "?" or "?", -- приховуємо зону від захисника
	})

	-- Bot auto-defend
	if session.IsBot and defSide == "P2" then
		task.delay(0.3, function()
			session._defZone    = ZONES[math.random(1, 3)]
			session._defSuccess = (math.random() < 0.45)
		end)
	end

	deadline = os.clock() + DEFEND_PHASE_TIME + 0.5
	while os.clock() < deadline do
		if session._defZone then break end
		task.wait(0.15)
	end
	session._defZone = session._defZone or ZONES[math.random(1, 3)]

	-- ──── DAMAGE CALCULATION ──────────────────────────
	local atkAbility = atkUnit.ClassAbility or "None"
	local healAmt = 0
	local burnApplied = false
	local glitchApplied = false

	local powerMult     = math.clamp(1.0 + (session._mashCount / 40), 1.0, 2.0)
	local precisionMult = session._precHit and 1.5 or 1.0
	local rawDmg        = math.floor(atkUnit.Damage * powerMult * precisionMult)
	
	local critChance = 0.25
	local critMult = 1.5
	if atkUnit.ClassAbility == "CritBoost" then
		critChance = 0.50
		critMult = 1.75
	end
	local isCrit = session._precHit and (math.random() < critChance)
	if isCrit then rawDmg = math.floor(rawDmg * critMult) end

	local finalDmg    = rawDmg
	local blockResult = "MISS" -- зони не співпали

	-- Hacker: Glitch — 20% chance to downgrade enemy block
	if atkAbility == "Glitch" and session._atkZone == session._defZone then
		if math.random() < 0.20 then
			if session._defSuccess then
				session._defSuccess = false -- Perfect Block → Partial Block
			else
				session._defZone = nil -- Partial Block → Miss
			end
			glitchApplied = true
		end
	end

	if session._atkZone == session._defZone then
		if session._defSuccess then
			finalDmg    = 0
			blockResult = "PERFECT_BLOCK"
		else
			finalDmg    = math.floor(rawDmg * 0.5)
			blockResult = "PARTIAL_BLOCK"
		end
	end

	-- Counter-attack on perfect block
	local counterDmg = 0
	if blockResult == "PERFECT_BLOCK" then
		counterDmg = math.floor(defUnit.Damage * 0.25)
		atkUnit.HP = math.max(0, atkUnit.HP - counterDmg)
	end

	defUnit.HP = math.max(0, defUnit.HP - finalDmg)

	-- ──── CLASS ABILITIES ────────────────────────────
	-- Diamante: Vampirism — heal 20% of damage dealt
	if atkAbility == "Vampirism" and finalDmg > 0 then
		healAmt = math.floor(finalDmg * 0.20)
		atkUnit.HP = math.min(atkUnit.MaxHP, atkUnit.HP + healAmt)
	end

	-- Lava: Burn DoT — 15% of damage dealt applied next turn
	if atkAbility == "Burn" and finalDmg > 0 then
		session._pendingBurnDmg = math.floor(finalDmg * 0.15)
		session._pendingBurnTarget = defSide
		burnApplied = true
	end

	-- ──── PHASE: RESOLUTION ───────────────────────────
	sendPhase(session, "Resolution", {
		AttackZone  = session._atkZone,
		DefendZone  = session._defZone,
		DamageDealt = finalDmg,
		BlockResult = blockResult,
		IsCrit      = isCrit,
		CounterDmg  = counterDmg,
		PowerMult   = powerMult,
		HealAmount  = healAmt,
		BurnApplied = burnApplied,
		GlitchApplied = glitchApplied,
		AtkClassAbility = atkAbility,
		AtkClassIcon = atkUnit.ClassAbilityIcon or "",
	})

	task.wait(2.5)

	-- ──── CHECK UNIT DEATH ────────────────────────────
	if defUnit.HP <= 0 then
		-- Шукаємо наступного живого юніта у захисника
		local defTeam = session[defSide .. "_Team"]
		local defIdx  = session[defSide .. "_ActiveIdx"]
		local nextIdx = nil

		for i = defIdx + 1, #defTeam do
			if defTeam[i].HP > 0 then nextIdx = i; break end
		end

		if nextIdx then
			session[defSide .. "_ActiveIdx"] = nextIdx
			swapModel(session, defSide)
			sendPhase(session, "UnitSwap", {
				SwapSide  = defSide,
				DeadName  = defUnit.Name,
				NewUnit   = defTeam[nextIdx].Name,
			})
			task.wait(2)
		else
			-- Усі юніти захисника загинули
			session.Status = atkSide .. "_Won"
		end
	end

	-- Counter-attack could also kill the attacker
	if atkUnit.HP <= 0 and session.Status == "InProgress" then
		local atkTeam = session[atkSide .. "_Team"]
		local atkIdx  = session[atkSide .. "_ActiveIdx"]
		local nextIdx = nil

		for i = atkIdx + 1, #atkTeam do
			if atkTeam[i].HP > 0 then nextIdx = i; break end
		end

		if nextIdx then
			session[atkSide .. "_ActiveIdx"] = nextIdx
			swapModel(session, atkSide)
			sendPhase(session, "UnitSwap", {
				SwapSide = atkSide,
				DeadName = atkUnit.Name,
				NewUnit  = atkTeam[nextIdx].Name,
			})
			task.wait(2)
		else
			session.Status = defSide .. "_Won"
		end
	end
end

-- ═══════════════════════════════════════════════════════
--  MAIN COMBAT LOOP
-- ═══════════════════════════════════════════════════════

local function runBattle(session)
	-- Intro
	sendPhase(session, "Intro", { TimeLeft = 2 })
	task.wait(2.5)

	session.CurrentAttacker = "P1" -- Гравець атакує першим
	session.Turn = 1

	while session.Status == "InProgress" do
		runHalfTurn(session)
		if session.Status ~= "InProgress" then break end

		-- Swap attacker/defender
		session.CurrentAttacker = (session.CurrentAttacker == "P1") and "P2" or "P1"
		session.Turn = session.Turn + 1
		task.wait(1)
	end

	-- ── BATTLE END ────────────────────────────────────
	local DM = getDataManager()
	local resultData = { BattleId = session.BattleId }

	if session.Status == "P1_Won" then
		resultData.Result = "P1_Won"
		resultData.WinnerSide = "P1"
		resultData.Reward = WIN_REWARD
		if session.Player1 then DM.AddBrainCells(session.Player1, WIN_REWARD) end

		-- Oro: Double Reward
		local hasOro = false
		if session.P1_Team then
			for _, u in ipairs(session.P1_Team) do
				if u.ClassAbility == "DoubleReward" then hasOro = true; break end
			end
		end
		if hasOro then
			if session.Player1 then DM.AddBrainCells(session.Player1, WIN_REWARD) end -- Extra reward
			resultData.OroBonus = WIN_REWARD
		end

		-- XP Awarding Logic
		if session.Player1 then
			local totalBotLevel = 0
			if session.P2_Team then
				for _, botUnit in ipairs(session.P2_Team) do
					totalBotLevel = totalBotLevel + (botUnit.Level or 1)
				end
			end
			local totalXPPool = 150 + (totalBotLevel * 15)

			local partUnits = {}
			for uuid, _ in pairs(session.P1_Participated or {}) do
				table.insert(partUnits, uuid)
			end
			if #partUnits == 0 and session.P1_Team then
				for _, u in ipairs(session.P1_Team) do
					table.insert(partUnits, u.UUID)
				end
			end

			local shareXP = math.floor(totalXPPool / math.max(1, #partUnits))
			resultData.XPAwarded = shareXP
			resultData.ParticipatedCount = #partUnits

			for _, uuid in ipairs(partUnits) do
				DM.AddXPToUnit(session.Player1, uuid, shareXP)
			end
		end

	elseif session.Status == "P2_Won" then
		resultData.Result = "P2_Won"
		resultData.WinnerSide = "P2"
		resultData.Reward = WIN_REWARD
		if session.Player2 then DM.AddBrainCells(session.Player2, WIN_REWARD) end
		
		-- Oro: Double Reward
		local hasOro = false
		if session.P2_Team then
			for _, u in ipairs(session.P2_Team) do
				if u.ClassAbility == "DoubleReward" then hasOro = true; break end
			end
		end
		if hasOro then
			if session.Player2 then DM.AddBrainCells(session.Player2, WIN_REWARD) end -- Extra reward
			resultData.OroBonus = WIN_REWARD
		end

		-- XP Awarding Logic for P2 (Bot)
		if session.Player2 then
			local totalP1Level = 0
			if session.P1_Team then
				for _, unit in ipairs(session.P1_Team) do
					totalP1Level = totalP1Level + (unit.Level or 1)
				end
			end
			local totalXPPool = 150 + (totalP1Level * 15)
			local partUnits = {}
			for uuid, _ in pairs(session.P2_Participated or {}) do
				table.insert(partUnits, uuid)
			end
			if #partUnits == 0 and session.P2_Team then
				for _, u in ipairs(session.P2_Team) do
					table.insert(partUnits, u.UUID)
				end
			end
			local shareXP = math.floor(totalXPPool / math.max(1, #partUnits))
			for _, uuid in ipairs(partUnits) do
				DM.AddXPToUnit(session.Player2, uuid, shareXP)
			end
		end
	else
		resultData.Result = "Draw"
	end

	if session.Player1 then
		resultData.YourSide = "P1"
		fireClient(session.Player1, "BattleEnd", resultData)
	end
	if session.Player2 then
		resultData.YourSide = "P2"
		fireClient(session.Player2, "BattleEnd", resultData)
	end

	-- Cleanup
	task.delay(5, function()
		if session.P1_Model then session.P1_Model:Destroy() end
		if session.P2_Model then session.P2_Model:Destroy() end
		if session.Player1 then 
			teleportToBase(session.Player1)
			playerBattles[session.Player1] = nil 
		end
		if session.Player2 and not session.IsBot then 
			teleportToBase(session.Player2)
			playerBattles[session.Player2] = nil 
		end
		if session.ArenaFolder then
			session.ArenaFolder:Destroy()
		end
		activeBattles[session.BattleId] = nil
	end)
end

-- ═══════════════════════════════════════════════════════
--  BUILD TEAM FROM UUIDS & BOT LEVEL SCALING
-- ═══════════════════════════════════════════════════════

local function getPlayerTop3AvgLevel(player)
	local DM = getDataManager()
	local data = DM.GetPlayerData(player)
	if not data or not data.Inventory or #data.Inventory == 0 then return 1 end

	local levels = {}
	for _, inv in ipairs(data.Inventory) do
		table.insert(levels, inv.Level or 1)
	end
	table.sort(levels, function(a, b) return a > b end)

	local sum, count = 0, 0
	for i = 1, math.min(3, #levels) do
		sum = sum + levels[i]
		count = count + 1
	end
	return count > 0 and math.max(1, math.floor(sum / count)) or 1
end

local function buildTeam(player, teamUUIDs, teamSize)
	teamSize = teamSize or 3
	local DM   = getDataManager()
	local data = DM.GetPlayerData(player)
	if not data or not data.Inventory then return nil end

	local team = {}
	for _, uuid in ipairs(teamUUIDs) do
		if #team >= teamSize then break end
		for _, inv in ipairs(data.Inventory) do
			if inv.UUID == uuid then
				local stats = ItemDatabase.GetUnitStats(inv)
				if stats then
					table.insert(team, {
						UUID   = uuid,
						ItemId = inv.ItemId,
						Name   = stats.Name,
						Class  = stats.Class,
						ClassAbility = stats.ClassConfig and stats.ClassConfig.Ability or "None",
						ClassAbilityIcon = stats.ClassConfig and stats.ClassConfig.AbilityIcon or "",
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

local function buildBotTeam(player, teamSize)
	teamSize = teamSize or 3
	local avgLevel = getPlayerTop3AvgLevel(player)
	local allItems = ItemDatabase.GetAllItemIds and ItemDatabase.GetAllItemIds()
	local classes = { "Normal", "Lava", "Oro", "Hacker", "Galaxia", "Diamante" }

	local team = {}
	if allItems and #allItems > 0 then
		for _ = 1, teamSize do
			local id = allItems[math.random(1, #allItems)]
			local botLevel = math.clamp(avgLevel + math.random(-3, 3), 1, 100)
			local botClass = classes[math.random(1, #classes)]
			local stats = ItemDatabase.GetUnitStats({
				ItemId = id,
				Class = botClass,
				Level = botLevel,
			})
			if stats then
				table.insert(team, {
					UUID   = HttpService:GenerateGUID(false),
					ItemId = id,
					Name   = stats.Name .. " (" .. botClass .. ")",
					Class  = botClass,
					ClassAbility = stats.ClassConfig and stats.ClassConfig.Ability or "None",
					ClassAbilityIcon = stats.ClassConfig and stats.ClassConfig.AbilityIcon or "",
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
			Name = "Bot Brainrot", Class = "Normal", Level = 1, HP = 120, MaxHP = 120, Damage = 12,
			ClassAbility = "None", ClassAbilityIcon = "",
		})
	end
	return team
end

-- ═══════════════════════════════════════════════════════
--  PUBLIC: START BOT BATTLE
-- ═══════════════════════════════════════════════════════

function BattleService.StartBotBattle(player, teamUUIDs, teamSize)
	teamSize = math.clamp(teamSize or 3, 1, 3)
	if playerBattles[player] then
		return { Success = false, Error = "Ви вже в бою!" }
	end

	if not teamUUIDs or #teamUUIDs == 0 then
		local DM = getDataManager()
		local data = DM.GetPlayerData(player)
		return { Success = false, NeedTeam = true, Inventory = data and data.Inventory or {} }
	end

	local pTeam = buildTeam(player, teamUUIDs, teamSize)
	if not pTeam then
		return { Success = false, Error = "Не вдалося зібрати команду!" }
	end

	local botTeam = buildBotTeam(player, teamSize)
	local battleId = HttpService:GenerateGUID(false)
	
	-- Generate specific arena for this battle
	local MapManager = require(game:GetService("ServerScriptService"):WaitForChild("Modules"):WaitForChild("MapManager"))
	local arenaInfo = MapManager.GenerateIsolatedArena(battleId)
	
	teleportToArena(player, arenaInfo.P1_Pos)

	local session = {
		BattleId = battleId,
		IsBot    = true,
		Player1  = player,
		Player2  = nil,
		ArenaFolder = arenaInfo.Folder,

		P1_Team      = pTeam,
		P1_ActiveIdx = 1,
		P1_Model     = spawnModel(arenaInfo.Folder, pTeam[1].ItemId, "P1_SpawnPad"),

		P2_Team      = botTeam,
		P2_ActiveIdx = 1,
		P2_Model     = spawnModel(arenaInfo.Folder, botTeam[1].ItemId, "P2_SpawnPad"),

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

-- ═══════════════════════════════════════════════════════
--  PUBLIC: START PVP BATTLE
-- ═══════════════════════════════════════════════════════

function BattleService.StartPvPBattle(p1, p2)
	if playerBattles[p1] or playerBattles[p2] then return end

	-- Для PvP — кожен гравець використовує всіх своїх equipped юнітів
	local DM = getDataManager()
	local d1 = DM.GetPlayerData(p1)
	local d2 = DM.GetPlayerData(p2)

	local t1, t2 = {}, {}
	if d1 and d1.Inventory then
		for _, u in ipairs(d1.Inventory) do
			if u.Equipped and #t1 < 3 then
				local cfg = ItemDatabase.GetUnitStats(u)
				if cfg then table.insert(t1, { UUID=u.UUID, ItemId=u.ItemId, Name=cfg.Name, Class=cfg.Class, ClassAbility=cfg.ClassConfig and cfg.ClassConfig.Ability or "None", ClassAbilityIcon=cfg.ClassConfig and cfg.ClassConfig.AbilityIcon or "", HP=cfg.MaxHP, MaxHP=cfg.MaxHP, Damage=cfg.Damage }) end
			end
		end
	end
	if d2 and d2.Inventory then
		for _, u in ipairs(d2.Inventory) do
			if u.Equipped and #t2 < 3 then
				local cfg = ItemDatabase.GetUnitStats(u)
				if cfg then table.insert(t2, { UUID=u.UUID, ItemId=u.ItemId, Name=cfg.Name, Class=cfg.Class, ClassAbility=cfg.ClassConfig and cfg.ClassConfig.Ability or "None", ClassAbilityIcon=cfg.ClassConfig and cfg.ClassConfig.AbilityIcon or "", HP=cfg.MaxHP, MaxHP=cfg.MaxHP, Damage=cfg.Damage }) end
			end
		end
	end

	if #t1 == 0 or #t2 == 0 then return end

	local battleId = HttpService:GenerateGUID(false)
	
	-- Generate specific arena for this battle
	local MapManager = require(game:GetService("ServerScriptService"):WaitForChild("Modules"):WaitForChild("MapManager"))
	local arenaInfo = MapManager.GenerateIsolatedArena(battleId)

	teleportToArena(p1, arenaInfo.P1_Pos)
	teleportToArena(p2, arenaInfo.P2_Pos)

	local session = {
		BattleId = battleId, IsBot = false,
		Player1 = p1, Player2 = p2,
		ArenaFolder = arenaInfo.Folder,
		P1_Team = t1, P1_ActiveIdx = 1, P1_Model = spawnModel(arenaInfo.Folder, t1[1].ItemId, "P1_SpawnPad"),
		P2_Team = t2, P2_ActiveIdx = 1, P2_Model = spawnModel(arenaInfo.Folder, t2[1].ItemId, "P2_SpawnPad"),
		CurrentAttacker = "P1", Turn = 1, Status = "InProgress",
	}

	activeBattles[battleId] = session
	playerBattles[p1] = battleId
	playerBattles[p2] = battleId

	task.spawn(function() task.wait(0.5); runBattle(session) end)
end
_G.BattleService = BattleService

-- ═══════════════════════════════════════════════════════
--  EVENT HANDLERS
-- ═══════════════════════════════════════════════════════

local events = ReplicatedStorage:WaitForChild("Events")

-- Start battle
events:WaitForChild("StartBattle").OnServerInvoke = function(player, teamUUIDs, teamSize)
	return BattleService.StartBotBattle(player, teamUUIDs, teamSize)
end

-- QTE results from client (attack & defense data combined)
events:WaitForChild("QTEResult").OnServerEvent:Connect(function(player, qteType, dataTable)
	local bid = playerBattles[player]
	if not bid then return end
	local s = activeBattles[bid]
	if not s then return end

	local mySide = (s.Player1 == player) and "P1" or (s.Player2 == player) and "P2" or nil
	if not mySide then return end

	if qteType == "Attack" and s.CurrentAttacker == mySide then
		s._atkZone   = ZONE_SET[dataTable.zone] and dataTable.zone or nil
		s._mashCount = math.clamp(dataTable.mashCount or 0, 0, 60)
		s._precHit   = (dataTable.precisionHit == true)
	elseif qteType == "Defend" and s.CurrentAttacker ~= mySide then
		s._defZone    = ZONE_SET[dataTable.zone] and dataTable.zone or nil
		s._defSuccess = (dataTable.success == true)
	end
end)

-- Legacy events (backward compat)
events:WaitForChild("SelectZone").OnServerEvent:Connect(function() end)
events:WaitForChild("SubmitBattleTurn").OnServerEvent:Connect(function() end)

-- Cleanup
Players.PlayerRemoving:Connect(function(player)
	local bid = playerBattles[player]
	if bid then
		local s = activeBattles[bid]
		if s then
			s.Status = "Abandoned"
			if s.P1_Model then s.P1_Model:Destroy() end
			if s.P2_Model then s.P2_Model:Destroy() end
			if s.ArenaFolder then s.ArenaFolder:Destroy() end
			activeBattles[bid] = nil
		end
		playerBattles[player] = nil
	end
end)

return BattleService
