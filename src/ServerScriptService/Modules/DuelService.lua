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
			prompt.Parent = root

			prompt.Triggered:Connect(function(sender)
				if not sender or not sender.Parent then return end
				if sender.UserId == player.UserId then return end -- не можна дуелитись із собою

				-- 1. Перевірка 5-хвилинного кулдауну
				local cdKey = sender.UserId .. "_" .. player.UserId
				local cdExp = duelCooldowns[cdKey]
				if cdExp and os.clock() < cdExp then
					local remainSec = math.ceil(cdExp - os.clock())
					local mins = math.floor(remainSec / 60)
					local secs = remainSec % 60
					DuelNoticeEvent:FireClient(sender, string.format("⏳ %s відхилив дуель. Спробуйте знову через %d хв %d сек!", player.Name, mins, secs))
					return
				end

				-- 2. Перевірка, чи не зайнятий вже гравець іншим боєм або дуеллю
				if pendingDuels[player.UserId] then
					DuelNoticeEvent:FireClient(sender, string.format("⏳ %s вже розглядає інший виклик на дуель!", player.Name))
					return
				end

				-- 3. Реєстрація запиту
				pendingDuels[player.UserId] = {
					senderId = sender.UserId,
					timestamp = os.clock()
				}

				print(string.format("[DuelService] ⚔️ %s надіслав виклик на дуель до %s", sender.Name, player.Name))
				DuelRequestEvent:FireClient(player, sender.Name, REQUEST_TIMEOUT_SECONDS)
				DuelNoticeEvent:FireClient(sender, string.format("⚔️ Виклик надіслано до %s. Очікування відповіді...", player.Name))

				-- 4. Автоматичний тайм-аут через 15 секунд
				task.delay(REQUEST_TIMEOUT_SECONDS + 1, function()
					local cur = pendingDuels[player.UserId]
					if cur and cur.senderId == sender.UserId then
						pendingDuels[player.UserId] = nil
						-- Застосовуємо кулдаун 5 хвилин при ігноруванні/таймауті
						duelCooldowns[cdKey] = os.clock() + DECLINE_COOLDOWN_SECONDS
						DuelNoticeEvent:FireClient(sender, string.format("⏰ %s не відповів на виклик. Кулдаун: 5 хвилин.", player.Name))
					end
				end)
			end)
		end
	end

	if player.Character then
		task.spawn(attachPrompt, player.Character)
	end
	player.CharacterAdded:Connect(attachPrompt)
end

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
			print(string.format("[DuelService] ✅ %s прийняв виклик від %s! Запуск бою...", player.Name, sender.Name))
			DuelNoticeEvent:FireClient(sender, string.format("⚔️ %s прийняв ваш виклик! Телепортація на арену...", player.Name))
			DuelNoticeEvent:FireClient(player, string.format("⚔️ Ви прийняли виклик %s! Телепортація на арену...", sender.Name))

			task.wait(0.5)
			if _G.BattleService then
				_G.BattleService.StartPvPBattle(sender, player)
			else
				warn("[DuelService] ❌ BattleService не знайдено!")
			end
		end
	else
		-- Гравець відхилив дуель — ставимо 5 хвилин кулдауну для того, хто надіслав
		duelCooldowns[cdKey] = os.clock() + DECLINE_COOLDOWN_SECONDS
		print(string.format("[DuelService] ❌ %s відхилив дуель від %s (Кулдаун 5 хв)", player.Name, sender and sender.Name or "Unknown"))

		if sender then
			DuelNoticeEvent:FireClient(sender, string.format("❌ %s відхилив ваш виклик на дуель. Кулдаун: 5 хвилин.", player.Name))
		end
	end
end)

return DuelService
