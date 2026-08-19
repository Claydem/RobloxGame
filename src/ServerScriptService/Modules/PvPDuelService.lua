--[[
	DuelService.lua
	ServerScriptService.Modules.DuelService

	Обробляє запити на дуелі між гравцями:
	- Додає ProximityPrompt до кожного гравця.
	- Забороняє дуелі самому собі.
	- 5-хвилинний кулдаун (300 сек), якщо суперник відхилив дуель.
	- Тайм-аут на очікування відповіді (15 сек).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DuelService = {}

local pendingDuels = {}   -- [targetId] = { senderId = number, timestamp = number }
local duelCooldowns = {}  -- ["senderId_targetId"] = expireTimestamp (os.clock())

local DECLINE_COOLDOWN_SECONDS = 300 -- 5 хвилин
local REQUEST_TIMEOUT_SECONDS  = 15  -- 15 секунд на відповідь

-- Створюємо RemoteEvents у ReplicatedStorage.Events
local events = ReplicatedStorage:FindFirstChild("Events")
if not events then
	events = Instance.new("Folder")
	events.Name = "Events"
	events.Parent = ReplicatedStorage
end

local function getOrCreateEvent(name)
	local ev = events:FindFirstChild(name)
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = events
	end
	return ev
end

local DuelRequestEvent = getOrCreateEvent("DuelRequest")
local DuelRespondEvent = getOrCreateEvent("DuelRespond")
local DuelNoticeEvent  = getOrCreateEvent("DuelNotice")
local TriggerDuelEvent = getOrCreateEvent("TriggerDuel")

-- ── ЄДИНА ЛОГІКА НАДСИЛАННЯ ВИКЛИКУ НА ДУЕЛЬ ──
local function handleDuelChallenge(sender, targetPlayer)
	if not sender or not targetPlayer or not sender.Parent or not targetPlayer.Parent then return end

	-- Захист від подвійного спрацювання (клієнт + сервер одночасно)
	local dbKey = "trigger_debounce_" .. sender.UserId
	if duelCooldowns[dbKey] and os.clock() < duelCooldowns[dbKey] then return end
	duelCooldowns[dbKey] = os.clock() + 1.5 -- 1.5 сек анти-спам

	if sender.UserId == targetPlayer.UserId then
		DuelNoticeEvent:FireClient(sender, "⚠️ You cannot challenge yourself to a duel! Approach another player.")
		return
	end

	-- 1. Перевірка, чи гравці не в бою
	if _G.BattleService and _G.BattleService.IsInBattle then
		if _G.BattleService.IsInBattle(sender) then
			DuelNoticeEvent:FireClient(sender, "⚔️ You are already in a battle!")
			return
		end
		if _G.BattleService.IsInBattle(targetPlayer) then
			DuelNoticeEvent:FireClient(sender, string.format("⚔️ %s is currently in a battle!", targetPlayer.Name))
			return
		end
	end

	-- 2. Перевірка 5-хвилинного кулдауну
	local cdKey = sender.UserId .. "_" .. targetPlayer.UserId
	local cdExp = duelCooldowns[cdKey]
	if cdExp and os.clock() < cdExp then
		local remainSec = math.ceil(cdExp - os.clock())
		local mins = math.floor(remainSec / 60)
		local secs = remainSec % 60
		DuelNoticeEvent:FireClient(sender, string.format("⏳ %s recently declined. Try again in %d min %d sec!", targetPlayer.Name, mins, secs))
		return
	end

	-- 3. Перевірка, чи не зайнятий вже гравець іншим викликом
	if pendingDuels[targetPlayer.UserId] then
		DuelNoticeEvent:FireClient(sender, string.format("⏳ %s is already considering another duel request!", targetPlayer.Name))
		return
	end

	-- 4. Реєстрація запиту
	pendingDuels[targetPlayer.UserId] = {
		senderId = sender.UserId,
		timestamp = os.clock()
	}

	print(string.format("[DuelService] ⚔️ %s sent duel challenge to %s", sender.Name, targetPlayer.Name))
	DuelRequestEvent:FireClient(targetPlayer, sender.Name, REQUEST_TIMEOUT_SECONDS)
	DuelNoticeEvent:FireClient(sender, string.format("⚔️ Challenge sent to %s! Waiting for response...", targetPlayer.Name))

	-- 5. Автоматичний тайм-аут через 15 секунд
	task.delay(REQUEST_TIMEOUT_SECONDS + 1, function()
		local cur = pendingDuels[targetPlayer.UserId]
		if cur and cur.senderId == sender.UserId then
			pendingDuels[targetPlayer.UserId] = nil
			duelCooldowns[cdKey] = os.clock() + DECLINE_COOLDOWN_SECONDS
			DuelNoticeEvent:FireClient(sender, string.format("⏰ %s did not respond. Cooldown: 5 minutes.", targetPlayer.Name))
		end
	end)
end

-- Обробка прямого виклику з клієнта (надійний fallback, якщо серверний Prompt.Triggered не спрацює)
TriggerDuelEvent.OnServerEvent:Connect(function(sender, targetUserId)
	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if targetPlayer then
		handleDuelChallenge(sender, targetPlayer)
	end
end)

-- ── ПРИКРІПЛЕННЯ PROXIMITY PROMPT ДО ГРАВЦІВ ──
local function setupPlayerPrompt(player)
	local function attachPrompt(char)
		local root = char:WaitForChild("HumanoidRootPart", 5)
		if root and not root:FindFirstChild("DuelPrompt") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "DuelPrompt"
			prompt.ActionText = "Challenge to Duel"
			prompt.ObjectText = player.Name
			prompt.RequiresLineOfSight = false
			prompt.MaxActivationDistance = 14
			prompt.HoldDuration = 0.5
			prompt.ClickablePrompt = true
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.Parent = root

			prompt.Triggered:Connect(function(sender)
				handleDuelChallenge(sender, player)
			end)
		end
	end

	if player.Character then
		task.spawn(attachPrompt, player.Character)
	end
	player.CharacterAdded:Connect(attachPrompt)
end

-- ProximityPromptService global listener disabled. We rely on prompt.Triggered.

Players.PlayerAdded:Connect(setupPlayerPrompt)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayerPrompt, player)
end

-- ── ОБРОБКА ВІДПОВІДІ НА ДУЕЛЬ ──
DuelRespondEvent.OnServerEvent:Connect(function(player, accepted)
	local duelData = pendingDuels[player.UserId]
	if not duelData then return end
	pendingDuels[player.UserId] = nil

	local sender = Players:GetPlayerByUserId(duelData.senderId)
	local cdKey = duelData.senderId .. "_" .. player.UserId

	if accepted == true then
		if sender then
			print(string.format("[DuelService] ✅ %s accepted challenge from %s! Starting battle...", player.Name, sender.Name))
			DuelNoticeEvent:FireClient(sender, string.format("⚔️ %s accepted your challenge! Teleporting to arena...", player.Name))
			DuelNoticeEvent:FireClient(player, string.format("⚔️ You accepted %s's challenge! Teleporting to arena...", sender.Name))

			task.wait(0.5)
			-- Замість миттєвого початку бою, відправляємо гравцям запит на вибір пета
			local DuelSelectPetEvent = game:GetService("ReplicatedStorage"):WaitForChild("Events"):WaitForChild("DuelSelectPet")
			
			-- Зберігаємо стан очікування
			pendingDuels[player.UserId] = { state = "SelectingPets", p1 = sender, p2 = player, p1_pets = nil, p2_pets = nil }
			
			DuelSelectPetEvent:FireClient(sender, player.Name)
			DuelSelectPetEvent:FireClient(player, sender.Name)
		end
	else
		-- Гравець відхилив дуель — ставимо 5 хвилин кулдауну для того, хто надіслав
		duelCooldowns[cdKey] = os.clock() + DECLINE_COOLDOWN_SECONDS
		print(string.format("[DuelService] ❌ %s declined duel from %s (Cooldown 5 min)", player.Name, sender and sender.Name or "Unknown"))

		if sender then
			DuelNoticeEvent:FireClient(sender, string.format("❌ %s declined your duel challenge. Cooldown: 5 minutes.", player.Name))
		end
	end
end)

-- Обробка відправки вибраних петів
local DuelSubmitPetsEvent = getOrCreateEvent("DuelSubmitPets")
DuelSubmitPetsEvent.OnServerEvent:Connect(function(sender, selectedUUIDs)
	-- Шукаємо, в якому активному дуелі бере участь цей гравець
	for hostId, duel in pairs(pendingDuels) do
		if duel.state == "SelectingPets" and (duel.p1.UserId == sender.UserId or duel.p2.UserId == sender.UserId) then
			if duel.p1.UserId == sender.UserId then
				duel.p1_pets = selectedUUIDs
			else
				duel.p2_pets = selectedUUIDs
			end
			
			DuelNoticeEvent:FireClient(sender, "✅ Pets selected! Waiting for opponent...")
			
			-- Якщо обидва вибрали
			if duel.p1_pets and duel.p2_pets then
				pendingDuels[hostId] = nil
				if _G.BattleService then
					_G.BattleService.StartPvPBattle(duel.p1, duel.p2, duel.p1_pets, duel.p2_pets)
				else
					warn("[DuelService] ❌ BattleService not found!")
				end
			end
			break
		end
	end
end)

return DuelService
