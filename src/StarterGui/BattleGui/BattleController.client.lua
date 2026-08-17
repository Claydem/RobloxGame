--[[
	BattleController.client.lua  v4.0
	StarterGui.BattleGui.BattleController

	Team-Based Alternating Combat UI:
	  1. Вибір команди (до 3 брейнротів з інвентаря)
	  2. Фаза Атаки: Вибір зони → Button Mash → Precision Arrow
	  3. Фаза Захисту: Вибір зони блоку → Precision Timing
	  4. Результат: Damage Numbers, Camera Shake, Flash FX
	  5. Заміна юніта при смерті
--]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")
local Camera      = workspace.CurrentCamera

local Events     = ReplicatedStorage:WaitForChild("Events", 10)
local ModFolder  = ReplicatedStorage:WaitForChild("Modules", 10)
local ItemDB     = ModFolder and ModFolder:FindFirstChild("ItemDatabase") and require(ModFolder.ItemDatabase)

local screenGuiAncestor = script:FindFirstAncestorOfClass("ScreenGui")
if not screenGuiAncestor then
	local found = PlayerGui:FindFirstChild("BattleGui")
	if found and found:IsA("ScreenGui") then
		screenGuiAncestor = found
	end
end

if not screenGuiAncestor then
	screenGuiAncestor = Instance.new("ScreenGui")
	screenGuiAncestor.Name = "BattleGui"
	screenGuiAncestor.ResetOnSpawn = false
	screenGuiAncestor.Parent = PlayerGui
end

local battleGui = screenGuiAncestor
battleGui.Enabled = false

-- 🧹 Знищуємо сторонні дублікати BattleGui у PlayerGui
for _, child in ipairs(PlayerGui:GetChildren()) do
	if child:IsA("ScreenGui") and child.Name == "BattleGui" and child ~= battleGui then
		child:Destroy()
	end
end

local function setBattleGuiVisible(visible: boolean)
	battleGui.Enabled = visible
end

local function isBattleGuiVisible()
	return battleGui.Enabled
end

-- ═══════════════════════════════════════════════════════
--  INVENTORY CACHE
-- ═══════════════════════════════════════════════════════
local cachedInventory = {}
if Events and Events:FindFirstChild("InventoryUpdate") then
	Events.InventoryUpdate.OnClientEvent:Connect(function(inv)
		cachedInventory = inv or {}
	end)
end

-- ═══════════════════════════════════════════════════════
--  UI HELPERS
-- ═══════════════════════════════════════════════════════

local function corner(p, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p; return c
end
local function stroke(p, col, th)
	local s = Instance.new("UIStroke"); s.Color = col or Color3.new(1,1,1); s.Thickness = th or 1.5; s.Parent = p; return s
end
local function tw(obj, props, dur)
	local t = TweenService:Create(obj, TweenInfo.new(dur or 0.3, Enum.EasingStyle.Quint), props)
	t:Play(); return t
end

-- ═══════════════════════════════════════════════════════
--  SOUND SYSTEM & AUDIO FX
-- ═══════════════════════════════════════════════════════

local SoundService = game:GetService("SoundService")

local SOUND_IDS = {
	Click      = "rbxassetid://12221967", -- UI Click
	Mash       = "rbxassetid://12221967", -- Mash button
	Hit        = "rbxassetid://131237241", -- Classic Punch
	CritHit    = "rbxassetid://131237241", -- Heavy Crit Punch
	Block      = "rbxassetid://138090596", -- Shield / Metal Block
	Swoosh     = "rbxassetid://12222200", -- Air Swoosh Lunge
	Victory    = "rbxassetid://12221967", -- Victory Bell
	Defeat     = "rbxassetid://12221967", -- Defeat Click
	Death      = "rbxassetid://131237241", -- Unit KO Punch
	FightVoice = "rbxassetid://12221967", -- Start Bell
}

-- КОРИСТУВАЦЬКИЙ ЗВУК: вставте сюди ваш Asset ID після завантаження MP3 (наприклад "rbxassetid://123456789")
local CUSTOM_USER_BGM_ID = ""

local BGM_TRACKS = {
	"rbxassetid://1839840134", -- Fast Combat Brass & Heavy Drums
	"rbxassetid://9042530188", -- Cyberpunk Heavy Combat Beat
	"rbxassetid://1837849285", -- Heavy Action Arena Battle
}

local bgmSound = nil

local function startBattleBGM()
	return -- Музику тимчасово вимкнено за запитом, звуки ударів і кнопок залишаються!
end

local function stopBattleBGM()
	task.spawn(function()
		if bgmSound and bgmSound.Parent then
			tw(bgmSound, { Volume = 0.0 }, 1.0)
			task.delay(1.1, function()
				if bgmSound then
					bgmSound:Stop()
				end
			end)
		end
	end)
end

local function playSFX(soundName, vol, pitch)
	local id = SOUND_IDS[soundName]
	if not id then return end
	task.spawn(function()
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = vol or 0.8
		s.PlaybackSpeed = pitch or (0.92 + math.random() * 0.16)
		s.Parent = SoundService
		pcall(function() s:Play() end)
		s.Ended:Connect(function() s:Destroy() end)
		task.delay(4, function() if s and s.Parent then s:Destroy() end end)
	end)
end

-- ═══════════════════════════════════════════════════════
--  MAIN FRAME
-- ═══════════════════════════════════════════════════════

local main = Instance.new("Frame")
main.Name = "Main"; main.Size = UDim2.new(1,0,1,0)
main.BackgroundTransparency = 1; main.Parent = battleGui

-- ── HP BARS ────────────────────────────────────────────
local hpBar = Instance.new("Frame")
hpBar.Size = UDim2.new(0,700,0,80); hpBar.Position = UDim2.new(0.5,-350,0,15)
hpBar.BackgroundTransparency = 1; hpBar.Parent = main

local function makeHPBar(x, w, col, nameDefault)
	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(0,w,0,26); bg.Position = UDim2.new(0,x,0,32)
	bg.BackgroundColor3 = Color3.fromRGB(20,24,32); bg.Parent = hpBar; corner(bg,6)
	local fill = Instance.new("Frame")
	fill.Name="Fill"; fill.Size=UDim2.new(1,0,1,0); fill.BackgroundColor3=col; fill.Parent=bg; corner(fill,6)
	local lbl = Instance.new("TextLabel")
	lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1; lbl.TextColor3=Color3.new(1,1,1)
	lbl.TextSize=12; lbl.Font=Enum.Font.GothamBold; lbl.ZIndex=2; lbl.Parent=bg; lbl.Text="?/?";
	local name = Instance.new("TextLabel")
	name.Size=UDim2.new(0,w,0,22); name.Position=UDim2.new(0,x,0,7); name.BackgroundTransparency=1
	name.TextColor3=col; name.TextSize=12; name.Font=Enum.Font.GothamBold; name.Parent=hpBar
	name.Text=nameDefault; name.TextXAlignment=Enum.TextXAlignment.Left
	-- Team dots
	local dots = Instance.new("TextLabel")
	dots.Size=UDim2.new(0,w,0,16); dots.Position=UDim2.new(0,x,0,60); dots.BackgroundTransparency=1
	dots.TextColor3=Color3.fromRGB(180,180,180); dots.TextSize=10; dots.Font=Enum.Font.Gotham; dots.Parent=hpBar
	dots.Text=""; dots.TextXAlignment=Enum.TextXAlignment.Left
	return fill, lbl, name, dots
end

local p1Fill, p1HpLbl, p1Name, p1Dots = makeHPBar(0, 290, Color3.fromRGB(46,204,113), "🟢 Player")
local p2Fill, p2HpLbl, p2Name, p2Dots = makeHPBar(410, 290, Color3.fromRGB(231,76,60), "🔴 Enemy")

local vsLbl = Instance.new("TextLabel")
vsLbl.Size=UDim2.new(0,120,0,26); vsLbl.Position=UDim2.new(0,290,0,32); vsLbl.BackgroundTransparency=1
vsLbl.Text="⚔️ VS"; vsLbl.TextColor3=Color3.fromRGB(255,215,0); vsLbl.TextSize=18
vsLbl.Font=Enum.Font.GothamBlack; vsLbl.Parent=hpBar

-- ── PHASE LABEL ────────────────────────────────────────
local phaseLbl = Instance.new("TextLabel")
phaseLbl.Size=UDim2.new(0,600,0,36); phaseLbl.Position=UDim2.new(0.5,-300,0,100)
phaseLbl.BackgroundTransparency=1; phaseLbl.TextColor3=Color3.new(1,1,1); phaseLbl.TextSize=16
phaseLbl.Font=Enum.Font.GothamBold; phaseLbl.Parent=main; phaseLbl.Text=""

-- ═══════════════════════════════════════════════════════
--  TEAM SELECTION PANEL
-- ═══════════════════════════════════════════════════════

local teamPanel = Instance.new("Frame")
teamPanel.Name="TeamSelect"; teamPanel.Size=UDim2.new(0,600,0,400)
teamPanel.Position=UDim2.new(0.5,-300,0.5,-200)
teamPanel.BackgroundColor3=Color3.fromRGB(12,14,22); teamPanel.BackgroundTransparency=0.08
teamPanel.Visible=false; teamPanel.Parent=main; corner(teamPanel,16)
stroke(teamPanel, Color3.fromRGB(255,215,0), 2)

local teamTitle = Instance.new("TextLabel")
teamTitle.Size=UDim2.new(1,0,0,28); teamTitle.BackgroundTransparency=1
teamTitle.Text="⚔️ SELECT BATTLE MODE & TEAM"; teamTitle.TextColor3=Color3.fromRGB(255,215,0)
teamTitle.TextSize=14; teamTitle.Font=Enum.Font.GothamBold; teamTitle.Parent=teamPanel

-- Battle mode selector: 1v1 or 3v3
local selectedTeamSize = 3
local modeFrame = Instance.new("Frame")
modeFrame.Size=UDim2.new(1,-20,0,32); modeFrame.Position=UDim2.new(0,10,0,28)
modeFrame.BackgroundTransparency=1; modeFrame.Parent=teamPanel

local btn1v1 = Instance.new("TextButton")
btn1v1.Size=UDim2.new(0,120,0,28); btn1v1.Position=UDim2.new(0,0,0,0)
btn1v1.BackgroundColor3=Color3.fromRGB(40,44,58); btn1v1.TextColor3=Color3.fromRGB(200,200,220)
btn1v1.Text="🥊 1 vs 1"; btn1v1.TextSize=13; btn1v1.Font=Enum.Font.GothamBold
btn1v1.Parent=modeFrame; corner(btn1v1,8)
local stroke1v1 = stroke(btn1v1, Color3.fromRGB(60,70,90), 1)

local btn3v3 = Instance.new("TextButton")
btn3v3.Size=UDim2.new(0,120,0,28); btn3v3.Position=UDim2.new(0,130,0,0)
btn3v3.BackgroundColor3=Color3.fromRGB(55,65,85); btn3v3.TextColor3=Color3.fromRGB(255,215,0)
btn3v3.Text="⚔️ 3 vs 3"; btn3v3.TextSize=13; btn3v3.Font=Enum.Font.GothamBold
btn3v3.Parent=modeFrame; corner(btn3v3,8)
local stroke3v3 = stroke(btn3v3, Color3.fromRGB(255,215,0), 1.5)

local function setMode(size)
	selectedTeamSize = size
	if size == 1 then
		btn1v1.BackgroundColor3 = Color3.fromRGB(55,65,85)
		stroke1v1.Color = Color3.fromRGB(255,215,0)
		btn1v1.TextColor3 = Color3.fromRGB(255,215,0)
		btn3v3.BackgroundColor3 = Color3.fromRGB(40,44,58)
		stroke3v3.Color = Color3.fromRGB(60,70,90)
		btn3v3.TextColor3 = Color3.fromRGB(200,200,220)
	else
		btn3v3.BackgroundColor3 = Color3.fromRGB(55,65,85)
		stroke3v3.Color = Color3.fromRGB(255,215,0)
		btn3v3.TextColor3 = Color3.fromRGB(255,215,0)
		btn1v1.BackgroundColor3 = Color3.fromRGB(40,44,58)
		stroke1v1.Color = Color3.fromRGB(60,70,90)
		btn1v1.TextColor3 = Color3.fromRGB(200,200,220)
	end
end
setMode(3) -- default 3v3

btn1v1.MouseButton1Click:Connect(function() setMode(1); renderTeamSelect() end)
btn3v3.MouseButton1Click:Connect(function() setMode(3); renderTeamSelect() end)

local teamScroll = Instance.new("ScrollingFrame")
teamScroll.Size=UDim2.new(1,-20,1,-130); teamScroll.Position=UDim2.new(0,10,0,64)
teamScroll.BackgroundTransparency=1; teamScroll.ScrollBarThickness=4
teamScroll.CanvasSize=UDim2.new(0,0,0,0); teamScroll.Parent=teamPanel
local grid = Instance.new("UIGridLayout")
grid.CellSize=UDim2.new(0,130,0,60); grid.CellPadding=UDim2.new(0,8,0,8); grid.Parent=teamScroll

local selectedTeamUUIDs = {}
local teamSlotLabels = {}

local teamSlotsFrame = Instance.new("Frame")
teamSlotsFrame.Size=UDim2.new(1,-20,0,28); teamSlotsFrame.Position=UDim2.new(0,10,1,-52)
teamSlotsFrame.BackgroundTransparency=1; teamSlotsFrame.Parent=teamPanel
for i = 1, 3 do
	local sl = Instance.new("TextLabel")
	sl.Size=UDim2.new(0,180,0,24); sl.Position=UDim2.new(0,(i-1)*190,0,0)
	sl.BackgroundColor3=Color3.fromRGB(30,34,48); sl.TextColor3=Color3.fromRGB(150,150,170)
	sl.TextSize=11; sl.Font=Enum.Font.GothamBold; sl.Text="Slot "..i..": empty"
	sl.Parent=teamSlotsFrame; corner(sl,6)
	teamSlotLabels[i] = sl
end

local startBattleBtn = Instance.new("TextButton")
startBattleBtn.Size=UDim2.new(0,200,0,40); startBattleBtn.Position=UDim2.new(1,-210,1,-52)
startBattleBtn.BackgroundColor3=Color3.fromRGB(231,76,60); startBattleBtn.TextColor3=Color3.new(1,1,1)
startBattleBtn.Text="⚔️ START BATTLE"; startBattleBtn.TextSize=15; startBattleBtn.Font=Enum.Font.GothamBlack
startBattleBtn.Parent=teamPanel; corner(startBattleBtn,10)

local function refreshTeamSlots()
	for i = 1, 3 do
		if selectedTeamUUIDs[i] then
			-- Find name
			for _, u in ipairs(cachedInventory) do
				if u.UUID == selectedTeamUUIDs[i] then
					local cfg = ItemDB and ItemDB.GetItem(u.ItemId)
					teamSlotLabels[i].Text = "Slot "..i..": "..(cfg and cfg.Name or u.ItemId)
					teamSlotLabels[i].TextColor3 = Color3.fromRGB(46,204,113)
					break
				end
			end
		else
			teamSlotLabels[i].Text = "Slot "..i..": empty"
			teamSlotLabels[i].TextColor3 = Color3.fromRGB(150,150,170)
		end
	end
	startBattleBtn.BackgroundColor3 = #selectedTeamUUIDs > 0 and Color3.fromRGB(46,204,113) or Color3.fromRGB(100,100,100)
end

local function fetchLatestInventory()
	local getFunc = Events and Events:FindFirstChild("GetPlayerData")
	if getFunc then
		local ok, data = pcall(function() return getFunc:InvokeServer() end)
		if ok and data and data.Inventory then
			cachedInventory = data.Inventory
		end
	end
end

local function renderTeamSelect()
	fetchLatestInventory()

	for _, c in ipairs(teamScroll:GetChildren()) do
		if c:IsA("TextButton") or c:IsA("TextLabel") then c:Destroy() end
	end
	selectedTeamUUIDs = {}

	local equippedUnits = {}
	for _, unit in ipairs(cachedInventory) do
		if unit.Equipped == true then
			table.insert(equippedUnits, unit)
		end
	end

	if #equippedUnits == 0 then
		local emptyLbl = Instance.new("TextLabel")
		emptyLbl.Size = UDim2.new(1, 0, 0, 60)
		emptyLbl.BackgroundTransparency = 1
		emptyLbl.Text = "🏡 Your Care Zone is empty! Add brainrots to your Care Zone first."
		emptyLbl.TextColor3 = Color3.fromRGB(255, 120, 50)
		emptyLbl.TextSize = 13; emptyLbl.Font = Enum.Font.GothamBold
		emptyLbl.TextWrapped = true
		emptyLbl.Parent = teamScroll
		refreshTeamSlots()
		return
	end

	for _, unit in ipairs(equippedUnits) do
		local cfg = ItemDB and ItemDB.GetItem(unit.ItemId)
		local name = cfg and cfg.Name or unit.ItemId

		-- Auto-select first N units based on mode
		local isAutoSelected = false
		if #selectedTeamUUIDs < selectedTeamSize then
			table.insert(selectedTeamUUIDs, unit.UUID)
			isAutoSelected = true
		end

		local btn = Instance.new("TextButton")
		local classIcon = cfg and cfg.ClassConfig and cfg.ClassConfig.AbilityIcon or ""
		local rarityIcon = cfg and cfg.RarityConfig and cfg.RarityConfig.Icon or "⚪"
		local classColor = cfg and cfg.ClassConfig and cfg.ClassConfig.Color
		btn.BackgroundColor3 = classColor or (isAutoSelected and Color3.fromRGB(40,80,50) or Color3.fromRGB(30,34,48))
		btn.TextColor3 = Color3.fromRGB(220,220,230)
		btn.TextSize = 11; btn.Font = Enum.Font.GothamBold
		btn.Text = rarityIcon .. " " .. name .. " " .. classIcon .. "\n❤️" .. (cfg and cfg.MaxHP or "?") .. " ⚔️" .. (cfg and cfg.Damage or "?")
		btn.TextWrapped = true; btn.Parent = teamScroll
		corner(btn, 8)
		local btnStroke = stroke(btn, isAutoSelected and Color3.fromRGB(46,204,113) or Color3.fromRGB(60,70,90), 1)

		btn.MouseButton1Click:Connect(function()
			-- Toggle selection
			local found = false
			for i, uuid in ipairs(selectedTeamUUIDs) do
				if uuid == unit.UUID then
					table.remove(selectedTeamUUIDs, i)
					btn.BackgroundColor3 = classColor or Color3.fromRGB(30,34,48)
					btnStroke.Color = Color3.fromRGB(60,70,90)
					found = true; break
				end
			end
			if not found and #selectedTeamUUIDs < selectedTeamSize then
				table.insert(selectedTeamUUIDs, unit.UUID)
				btn.BackgroundColor3 = classColor or Color3.fromRGB(40,80,50)
				btnStroke.Color = Color3.fromRGB(46,204,113)
			end
			refreshTeamSlots()
		end)
	end

	teamScroll.CanvasSize = UDim2.new(0, 0, 0, math.ceil(#equippedUnits / 4) * 68 + 10)
	refreshTeamSlots()
end

startBattleBtn.MouseButton1Click:Connect(function()
	if #selectedTeamUUIDs == 0 then return end
	startBattleBtn.Text = "⏳ Loading..."
	startBattleBtn.BackgroundColor3 = Color3.fromRGB(100,100,100)

	startBattleBGM()

	local StartBattle = Events and Events:FindFirstChild("StartBattle")
	if StartBattle then
		local ok, res = pcall(function()
			return StartBattle:InvokeServer(selectedTeamUUIDs, selectedTeamSize)
		end)
		if ok and res and res.Success then
			teamPanel.Visible = false
		else
			startBattleBtn.Text = "❌ " .. (res and res.Error or "Error!")
			task.delay(2, function()
				startBattleBtn.Text = "⚔️ START BATTLE"
				startBattleBtn.BackgroundColor3 = Color3.fromRGB(46,204,113)
			end)
		end
	end
end)

-- ═══════════════════════════════════════════════════════
--  ZONE BUTTONS PANEL (Attack & Defense)
-- ═══════════════════════════════════════════════════════

local ZONE_DATA = {
	{ id="Head",  icon="🧠", label="HEAD",  color=Color3.fromRGB(235, 75, 75) },
	{ id="Torso", icon="🫁", label="TORSO", color=Color3.fromRGB(240, 180, 40) },
	{ id="Legs",  icon="🦵", label="LEGS",  color=Color3.fromRGB(60, 170, 240) },
}

local zonePanel = Instance.new("Frame")
zonePanel.Size=UDim2.new(0,380,0,90); zonePanel.Position=UDim2.new(0.5,-190,1,-200)
zonePanel.BackgroundColor3=Color3.fromRGB(16, 18, 26); zonePanel.BackgroundTransparency=0.05
zonePanel.Visible=false; zonePanel.Parent=main; corner(zonePanel,12)
stroke(zonePanel, Color3.fromRGB(80, 100, 140), 1.5)

local zoneTitleLbl = Instance.new("TextLabel")
zoneTitleLbl.Size=UDim2.new(1,0,0,24); zoneTitleLbl.BackgroundTransparency=1
zoneTitleLbl.TextSize=13; zoneTitleLbl.Font=Enum.Font.GothamBold; zoneTitleLbl.Parent=zonePanel
zoneTitleLbl.TextColor3=Color3.fromRGB(240, 240, 255); zoneTitleLbl.Text="⚔️ CHOOSE TARGET ZONE"

local selectedZone = nil
local zoneButtons = {}

for i, zd in ipairs(ZONE_DATA) do
	local btn = Instance.new("TextButton")
	btn.Size=UDim2.new(0,110,0,55); btn.Position=UDim2.new(0,10+(i-1)*125,0,28)
	btn.BackgroundColor3=Color3.fromRGB(28, 32, 46); btn.Text=zd.icon.." "..zd.label
	btn.TextColor3=Color3.fromRGB(255, 255, 255) -- Чисто білий чіткий колір тексту!
	btn.TextSize=14; btn.Font=Enum.Font.GothamBlack
	btn.TextStrokeTransparency=0.15 -- Чіткий чорний контур навколо літер для ідеальної читабельності
	btn.TextStrokeColor3=Color3.fromRGB(10, 12, 18)
	btn.Parent=zonePanel; corner(btn,10); stroke(btn, zd.color, 1.5)
	zoneButtons[zd.id] = btn

	btn.MouseButton1Click:Connect(function()
		selectedZone = zd.id
		for id, b in pairs(zoneButtons) do
			b.BackgroundColor3 = Color3.fromRGB(28, 32, 46)
			b.TextColor3 = Color3.fromRGB(255, 255, 255)
		end
		btn.BackgroundColor3 = Color3.fromRGB(60, 35, 45)
		btn.TextColor3 = zd.color
	end)
end

-- ═══════════════════════════════════════════════════════
--  ATTACK QTE PANEL (Mash + Precision)
-- ═══════════════════════════════════════════════════════

local atkPanel = Instance.new("Frame")
atkPanel.Size=UDim2.new(0,450,0,170); atkPanel.Position=UDim2.new(0.5,-225,1,-195)
atkPanel.BackgroundColor3=Color3.fromRGB(12,14,22); atkPanel.BackgroundTransparency=0.1
atkPanel.Visible=false; atkPanel.Parent=main; corner(atkPanel,12)
stroke(atkPanel, Color3.fromRGB(255,150,50), 2)

local atkTitle = Instance.new("TextLabel")
atkTitle.Size=UDim2.new(1,0,0,24); atkTitle.BackgroundTransparency=1
atkTitle.Text="⚡ TAP FAST — GAIN POWER!"; atkTitle.TextColor3=Color3.fromRGB(255,200,80)
atkTitle.TextSize=13; atkTitle.Font=Enum.Font.GothamBold; atkTitle.Parent=atkPanel

-- Power bar
local pwrBg = Instance.new("Frame")
pwrBg.Size=UDim2.new(0,360,0,24); pwrBg.Position=UDim2.new(0.5,-180,0,28)
pwrBg.BackgroundColor3=Color3.fromRGB(25,28,38); pwrBg.Parent=atkPanel; corner(pwrBg,5)
local pwrFill = Instance.new("Frame")
pwrFill.Size=UDim2.new(0,0,1,0); pwrFill.BackgroundColor3=Color3.fromRGB(255,140,0); pwrFill.Parent=pwrBg; corner(pwrFill,5)
local pwrLbl = Instance.new("TextLabel")
pwrLbl.Size=UDim2.new(1,0,1,0); pwrLbl.BackgroundTransparency=1; pwrLbl.Text="x1.0"
pwrLbl.TextColor3=Color3.new(1,1,1); pwrLbl.TextSize=13; pwrLbl.Font=Enum.Font.GothamBold
pwrLbl.ZIndex=2; pwrLbl.Parent=pwrBg

local mashBtn = Instance.new("TextButton")
mashBtn.Size=UDim2.new(0,180,0,44); mashBtn.Position=UDim2.new(0.5,-90,0,58)
mashBtn.BackgroundColor3=Color3.fromRGB(231,76,60); mashBtn.Text="💥 TAP!"
mashBtn.TextColor3=Color3.new(1,1,1); mashBtn.TextSize=18; mashBtn.Font=Enum.Font.GothamBlack
mashBtn.Parent=atkPanel; corner(mashBtn,10)

-- Precision bar
local precBg = Instance.new("Frame")
precBg.Size=UDim2.new(0,360,0,18); precBg.Position=UDim2.new(0.5,-180,0,110)
precBg.BackgroundColor3=Color3.fromRGB(25,28,38); precBg.Parent=atkPanel; corner(precBg,4)
local precGold = Instance.new("Frame")
precGold.Size=UDim2.new(0,40,1,0); precGold.Position=UDim2.new(0.5,-20,0,0)
precGold.BackgroundColor3=Color3.fromRGB(255,215,0); precGold.BackgroundTransparency=0.4; precGold.Parent=precBg
local precNeedle = Instance.new("Frame")
precNeedle.Size=UDim2.new(0,4,1,4); precNeedle.Position=UDim2.new(0,0,0,-2)
precNeedle.BackgroundColor3=Color3.fromRGB(255,80,80); precNeedle.Parent=precBg
local precHint = Instance.new("TextLabel")
precHint.Size=UDim2.new(1,0,0,16); precHint.Position=UDim2.new(0,0,1,2)
precHint.BackgroundTransparency=1; precHint.Text="Press SPACEBAR in the Gold Zone!"
precHint.TextColor3=Color3.fromRGB(180,180,180); precHint.TextSize=10; precHint.Font=Enum.Font.Gotham
precHint.Parent=precBg

-- ═══════════════════════════════════════════════════════
--  DEFENSE QTE PANEL
-- ═══════════════════════════════════════════════════════

local defPanel = Instance.new("Frame")
defPanel.Size=UDim2.new(0,450,0,130); defPanel.Position=UDim2.new(0.5,-225,1,-160)
defPanel.BackgroundColor3=Color3.fromRGB(12,14,22); defPanel.BackgroundTransparency=0.1
defPanel.Visible=false; defPanel.Parent=main; corner(defPanel,12)
stroke(defPanel, Color3.fromRGB(80,160,255), 2)

local defTitle = Instance.new("TextLabel")
defTitle.Size=UDim2.new(1,0,0,24); defTitle.BackgroundTransparency=1
defTitle.Text="🛡️ DEFENSE — Hit the Blue Zone!"; defTitle.TextColor3=Color3.fromRGB(80,180,255)
defTitle.TextSize=13; defTitle.Font=Enum.Font.GothamBold; defTitle.Parent=defPanel

local defBarBg = Instance.new("Frame")
defBarBg.Size=UDim2.new(0,360,0,20); defBarBg.Position=UDim2.new(0.5,-180,0,30)
defBarBg.BackgroundColor3=Color3.fromRGB(25,28,38); defBarBg.Parent=defPanel; corner(defBarBg,4)
local defGold = Instance.new("Frame")
defGold.Size=UDim2.new(0,50,1,0); defGold.Position=UDim2.new(0.5,-25,0,0)
defGold.BackgroundColor3=Color3.fromRGB(80,180,255); defGold.BackgroundTransparency=0.4; defGold.Parent=defBarBg
local defNeedle = Instance.new("Frame")
defNeedle.Size=UDim2.new(0,4,1,4); defNeedle.Position=UDim2.new(0,0,0,-2)
defNeedle.BackgroundColor3=Color3.new(1,1,1); defNeedle.Parent=defBarBg

local defBtn = Instance.new("TextButton")
defBtn.Size=UDim2.new(0,180,0,38); defBtn.Position=UDim2.new(0.5,-90,0,58)
defBtn.BackgroundColor3=Color3.fromRGB(52,152,219); defBtn.Text="🛡️ BLOCK!"
defBtn.TextColor3=Color3.new(1,1,1); defBtn.TextSize=16; defBtn.Font=Enum.Font.GothamBlack
defBtn.Parent=defPanel; corner(defBtn,10)

-- ═══════════════════════════════════════════════════════
--  WAITING PANEL (enemy's turn)
-- ═══════════════════════════════════════════════════════

local waitPanel = Instance.new("Frame")
waitPanel.Size=UDim2.new(0,350,0,60); waitPanel.Position=UDim2.new(0.5,-175,1,-100)
waitPanel.BackgroundColor3=Color3.fromRGB(12,14,22); waitPanel.BackgroundTransparency=0.2
waitPanel.Visible=false; waitPanel.Parent=main; corner(waitPanel,10)
local waitLbl = Instance.new("TextLabel")
waitLbl.Size=UDim2.new(1,0,1,0); waitLbl.BackgroundTransparency=1
waitLbl.Text="⏳ Enemy turn..."; waitLbl.TextColor3=Color3.fromRGB(180,180,200)
waitLbl.TextSize=14; waitLbl.Font=Enum.Font.GothamBold; waitLbl.Parent=waitPanel

-- ═══════════════════════════════════════════════════════
--  RESULT OVERLAY
-- ═══════════════════════════════════════════════════════

local resultOverlay = Instance.new("Frame")
resultOverlay.Size=UDim2.new(1,0,1,0); resultOverlay.BackgroundColor3=Color3.new(0,0,0)
resultOverlay.BackgroundTransparency=1; resultOverlay.Visible=false; resultOverlay.ZIndex=10; resultOverlay.Parent=main
local resultLbl = Instance.new("TextLabel")
resultLbl.Size=UDim2.new(0,600,0,80); resultLbl.Position=UDim2.new(0.5,-300,0.35,0)
resultLbl.BackgroundTransparency=1; resultLbl.TextColor3=Color3.fromRGB(255,215,0)
resultLbl.TextSize=34; resultLbl.Font=Enum.Font.GothamBlack; resultLbl.ZIndex=11; resultLbl.Parent=resultOverlay

-- ═══════════════════════════════════════════════════════
--  3D PARTICLE EMITTER FX (Fire, Smoke, Sparks, Shield)
-- ═══════════════════════════════════════════════════════

local function spawnImpactParticles(pos, isCrit, isBlock)
	local arena = workspace:FindFirstChild("FightClubArena") or workspace
	local part = Instance.new("Part")
	part.Size = Vector3.new(0.5, 0.5, 0.5)
	part.Position = pos
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.Parent = arena

	-- 1. Sparks / Fire Emitter
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxassetid://258121656"
	pe.Rate = 0
	pe.Speed = NumberRange.new(15, isCrit and 35 or 25)
	pe.Lifetime = NumberRange.new(0.2, 0.5)
	pe.SpreadAngle = Vector2.new(180, 180)

	if isBlock then
		pe.Color = ColorSequence.new(Color3.fromRGB(80, 200, 255), Color3.fromRGB(255, 255, 255))
		pe.LightEmission = 0.9
		pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 0)})
	elseif isCrit then
		pe.Color = ColorSequence.new(Color3.fromRGB(255, 215, 0), Color3.fromRGB(255, 50, 0))
		pe.LightEmission = 1.0
		pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 3.0), NumberSequenceKeypoint.new(1, 0)})
	else
		pe.Color = ColorSequence.new(Color3.fromRGB(255, 180, 50), Color3.fromRGB(255, 60, 0))
		pe.LightEmission = 0.7
		pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.8), NumberSequenceKeypoint.new(1, 0)})
	end

	pe.Parent = part
	pe:Emit(isCrit and 40 or isBlock and 25 or 20)

	-- 2. Smoke Puff (for Hits & Crits)
	if not isBlock then
		local smoke = Instance.new("ParticleEmitter")
		smoke.Texture = "rbxassetid://258123012"
		smoke.Rate = 0
		smoke.Speed = NumberRange.new(5, 12)
		smoke.Lifetime = NumberRange.new(0.4, 0.8)
		smoke.SpreadAngle = Vector2.new(180, 180)
		smoke.Color = ColorSequence.new(Color3.fromRGB(80, 80, 80), Color3.fromRGB(30, 30, 30))
		smoke.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1)})
		smoke.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4.0)})
		smoke.Parent = part
		smoke:Emit(15)
	end

	task.delay(1.5, function() part:Destroy() end)
end

-- ═══════════════════════════════════════════════════════
--  3D PHYSICAL MODEL ANIMATIONS (Lunge, Flinch, Death)
-- ═══════════════════════════════════════════════════════

local function animateLungeAttack(attackerSide, defenderSide, onImpactCallback)
	local arena = workspace:FindFirstChild("FightClubArena")
	if not arena then if onImpactCallback then onImpactCallback() end return end

	local atkPad = arena:FindFirstChild(attackerSide .. "_SpawnPad")
	local defPad = arena:FindFirstChild(defenderSide .. "_SpawnPad")
	if not atkPad or not defPad then if onImpactCallback then onImpactCallback() end return end

	-- Знаходимо модельку на паді атакуючого
	local atkModel = nil
	for _, child in ipairs(arena:GetChildren()) do
		if child:IsA("Model") and (child.PrimaryPart and (child.PrimaryPart.Position - atkPad.Position).Magnitude < 12) then
			atkModel = child
			break
		end
	end

	if not atkModel or not atkModel.PrimaryPart then
		if onImpactCallback then onImpactCallback() end
		return
	end

	local origCF = atkModel:GetPivot()
	local lungePos = atkPad.Position:Lerp(defPad.Position, 0.6) + Vector3.new(0, (origCF.Position.Y - atkPad.Position.Y), 0)
	local lungeCF = CFrame.new(lungePos) * (origCF.Rotation)

	playSFX("Swoosh", 0.7, 1.1)

	-- 1. Випад вперед (Lunge)
	local twForward = TweenService:Create(atkModel.PrimaryPart, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = lungeCF
	})

	-- При переміщенні через PivotTo для всієї моделі
	task.spawn(function()
		local step = 0
		while step < 0.2 do
			local dt = task.wait()
			step = step + dt
			local alpha = math.clamp(step / 0.2, 0, 1)
			atkModel:PivotTo(origCF:Lerp(lungeCF, alpha))
		end

		-- Удар досяг цілі!
		if onImpactCallback then onImpactCallback() end

		-- 2. Повернення назад (Snap back)
		task.wait(0.1)
		step = 0
		while step < 0.25 do
			local dt = task.wait()
			step = step + dt
			local alpha = math.clamp(step / 0.25, 0, 1)
			atkModel:PivotTo(lungeCF:Lerp(origCF, alpha))
		end
		atkModel:PivotTo(origCF)
	end)
end

-- ═══════════════════════════════════════════════════════
--  FX FUNCTIONS (Camera Shake, Damage Popups, Screen Flash)
-- ═══════════════════════════════════════════════════════

local function cameraShake(intensity, dur)
	task.spawn(function()
		local orig = Camera.CFrame
		local e = 0
		intensity = intensity or 1.0
		dur = dur or 0.35

		while e < dur do
			local dt = task.wait()
			e = e + dt
			local p = 1 - (e / dur)
			local offsetX = (math.random() - 0.5) * intensity * p * 1.2
			local offsetY = (math.random() - 0.5) * intensity * p * 1.2
			local offsetZ = (math.random() - 0.5) * intensity * p * 0.6
			local rotZ = (math.random() - 0.5) * math.rad(intensity * 3) * p

			Camera.CFrame = orig * CFrame.new(offsetX, offsetY, offsetZ) * CFrame.Angles(0, 0, rotZ)
		end
		Camera.CFrame = orig
	end)
end

local function showDmgNumber(text, col, posX, isCrit)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(0, 220, 0, 60)
	l.Position = UDim2.new(posX, -110, 0.32, 0)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = col
	l.TextSize = isCrit and 42 or 32
	l.Font = Enum.Font.GothamBlack
	l.TextStrokeTransparency = 0.2
	l.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	l.Parent = main

	-- Elastic bounce scaling effect
	l.Size = UDim2.new(0, 10, 0, 10)
	tw(l, {
		Size = UDim2.new(0, isCrit and 240 or 200, 0, isCrit and 70 or 55),
		Position = UDim2.new(posX, isCrit and -120 or -100, 0.22, 0)
	}, 0.35, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)

	task.delay(0.4, function()
		tw(l, {
			Position = UDim2.new(posX, isCrit and -120 or -100, 0.10, 0),
			TextTransparency = 1,
			TextStrokeTransparency = 1
		}, 1.2)
	end)

	task.delay(1.7, function() l:Destroy() end)
end

local function flashScreen(col)
	local f = Instance.new("Frame"); f.Size=UDim2.new(1,0,1,0)
	f.BackgroundColor3=col or Color3.new(1,0,0); f.BackgroundTransparency=0.4; f.ZIndex=20; f.Parent=main
	tw(f, {BackgroundTransparency=1}, 0.5); task.delay(0.6, function() f:Destroy() end)
end

-- ═══════════════════════════════════════════════════════
--  HP UPDATE
-- ═══════════════════════════════════════════════════════

local mySide = "P1"

local function updateHP(data)
	if data.P1_Unit then
		local r = math.clamp(data.P1_Unit.HP / data.P1_Unit.MaxHP, 0, 1)
		tw(p1Fill, {Size=UDim2.new(r,0,1,0)}, 0.4)
		p1HpLbl.Text = data.P1_Unit.HP.."/"..data.P1_Unit.MaxHP
		local classIcon = data.P1_Unit.ClassConfig and data.P1_Unit.ClassConfig.AbilityIcon or ""
		p1Name.Text = "🟢 "..data.P1_Unit.Name .. (classIcon ~= "" and " " .. classIcon or "")
		p1Fill.BackgroundColor3 = r>0.5 and Color3.fromRGB(46,204,113) or r>0.25 and Color3.fromRGB(241,196,15) or Color3.fromRGB(231,76,60)
	end
	if data.P2_Unit then
		local r = math.clamp(data.P2_Unit.HP / data.P2_Unit.MaxHP, 0, 1)
		tw(p2Fill, {Size=UDim2.new(r,0,1,0)}, 0.4)
		p2HpLbl.Text = data.P2_Unit.HP.."/"..data.P2_Unit.MaxHP
		local classIcon = data.P2_Unit.ClassConfig and data.P2_Unit.ClassConfig.AbilityIcon or ""
		p2Name.Text = "🔴 "..data.P2_Unit.Name .. (classIcon ~= "" and " " .. classIcon or "")
	end
	if data.P1_Alive and data.P1_TeamSize then
		local dots = ""
		for i = 1, data.P1_TeamSize do dots = dots .. (i <= data.P1_Alive and "💚" or "💀") end
		p1Dots.Text = dots
	end
	if data.P2_Alive and data.P2_TeamSize then
		local dots = ""
		for i = 1, data.P2_TeamSize do dots = dots .. (i <= data.P2_Alive and "❤️" or "💀") end
		p2Dots.Text = dots
	end
end

-- ═══════════════════════════════════════════════════════
--  STATE VARIABLES
-- ═══════════════════════════════════════════════════════

local mashCount        = 0
local precisionHit     = false
local defenseSuccess   = false
local needleRunning    = false
local currentPhase     = ""
local dataSent         = false

local function hideAllPanels()
	zonePanel.Visible  = false
	atkPanel.Visible   = false
	defPanel.Visible   = false
	waitPanel.Visible  = false
	teamPanel.Visible  = false
end

-- ═══════════════════════════════════════════════════════
--  ATTACK FLOW (3 sub-steps managed client-side)
-- ═══════════════════════════════════════════════════════

local function startAttackFlow(data)
	hideAllPanels()
	dataSent    = false
	selectedZone = nil
	mashCount    = 0
	precisionHit = false

	-- Sub-step 1: Zone selection (3s)
	zoneTitleLbl.Text = "⚔️ CHOOSE ATTACK TARGET"
	zoneTitleLbl.TextColor3 = Color3.fromRGB(255,150,80)
	for _, b in pairs(zoneButtons) do b.BackgroundColor3 = Color3.fromRGB(30,34,48) end
	zonePanel.Visible = true
	phaseLbl.Text = "⚔️ Turn "..data.Turn.." — Attack! Choose target"

	task.delay(3, function()
		if dataSent then return end
		selectedZone = selectedZone or "Torso"
		zonePanel.Visible = false

		-- Sub-step 2: Button Mash (2.5s)
		atkPanel.Visible = true
		mashBtn.Visible  = true
		mashBtn.Text     = "💥 TAP!"
		mashBtn.BackgroundColor3 = Color3.fromRGB(231,76,60)
		mashBtn.TextColor3       = Color3.new(1,1,1)
		pwrFill.Size = UDim2.new(0,0,1,0); pwrLbl.Text = "x1.0"
		phaseLbl.Text = "💥 TAP AS FAST AS YOU CAN!"

		task.delay(2.5, function()
			if dataSent then return end
			-- Sub-step 3: Precision (auto-running needle, 1.5s window)
			mashBtn.Visible = false
			atkTitle.Text = "🎯 PRECISION — Press SPACEBAR!"
			phaseLbl.Text = "🎯 Hit the Gold Zone with SPACEBAR!"

			needleRunning = true
			task.spawn(function()
				local pos, dir = 0, 1
				while needleRunning do
					pos = pos + dir * 8
					if pos >= 356 then dir = -1 end
					if pos <= 0 then dir = 1 end
					precNeedle.Position = UDim2.new(0, pos, 0, -2)
					task.wait(0.015)
				end
			end)

			task.delay(1.5, function()
				needleRunning = false
				atkPanel.Visible = false
				mashBtn.Visible = true
				atkTitle.Text = "⚡ TAP FAST — GAIN POWER!"
				if not dataSent then
					dataSent = true
					if Events then
						Events.QTEResult:FireServer("Attack", {
							zone = selectedZone,
							mashCount = mashCount,
							precisionHit = precisionHit,
						})
					end
				end
			end)
		end)
	end)
end

-- Precision hit handler (SPACEBAR ONLY)
local function triggerPrecisionHit()
	if not atkPanel.Visible or not needleRunning or precisionHit then return end
	local nx = precNeedle.Position.X.Offset
	local gx = 160
	local ge = 200
	precisionHit = (nx >= gx and nx <= ge)
	if precisionHit then
		playSFX("CritHit", 1.0, 1.2)
		cameraShake(1.5, 0.3)
	else
		playSFX("Click", 0.6, 0.8)
	end
	precHint.Text = precisionHit and "🎯 CRITICAL HIT!" or "❌ MISSED"
	precHint.TextColor3 = precisionHit and Color3.fromRGB(255,215,0) or Color3.fromRGB(231,76,60)
end

mashBtn.MouseButton1Click:Connect(function()
	if not atkPanel.Visible or not mashBtn.Visible or needleRunning or dataSent then return end

	-- Mash phase
	mashCount = mashCount + 1
	playSFX("Mash", 0.5, 0.9 + (mashCount * 0.025))
	cameraShake(0.3, 0.1)
	local mult = math.clamp(1 + mashCount/40, 1, 2)
	pwrFill.Size = UDim2.new((mult-1), 0, 1, 0)
	pwrLbl.Text = string.format("x%.1f", mult)
	mashBtn.BackgroundColor3 = Color3.fromRGB(255,120,60)
	task.delay(0.04, function()
		if mashBtn and not needleRunning then
			mashBtn.BackgroundColor3 = Color3.fromRGB(231,76,60)
		end
	end)
end)

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.Space and atkPanel.Visible and needleRunning then
		triggerPrecisionHit()
	end
end)

-- ═══════════════════════════════════════════════════════
--  DEFENSE FLOW (2 sub-steps)
-- ═══════════════════════════════════════════════════════

local function startDefendFlow(data)
	hideAllPanels()
	dataSent       = false
	selectedZone   = nil
	defenseSuccess = false

	-- Sub-step 1: Zone selection (2.5s)
	zoneTitleLbl.Text = "🛡️ CHOOSE DEFENSE TARGET"
	zoneTitleLbl.TextColor3 = Color3.fromRGB(80,180,255)
	for _, b in pairs(zoneButtons) do b.BackgroundColor3 = Color3.fromRGB(30,34,48) end
	zonePanel.Visible = true
	phaseLbl.Text = "🛡️ Turn "..data.Turn.." — Defense! Choose block zone"

	task.delay(2.5, function()
		if dataSent then return end
		selectedZone = selectedZone or "Torso"
		zonePanel.Visible = false

		-- Sub-step 2: Precision timing (2s)
		defPanel.Visible = true
		defBtn.Text = "🛡️ BLOCK!"; defBtn.BackgroundColor3 = Color3.fromRGB(52,152,219)
		phaseLbl.Text = "🛡️ Hit the blue zone for a perfect block!"

		needleRunning = true
		task.spawn(function()
			local pos, dir = 0, 1
			while needleRunning do
				pos = pos + dir * 9
				if pos >= 356 then dir = -1 end
				if pos <= 0 then dir = 1 end
				defNeedle.Position = UDim2.new(0, pos, 0, -2)
				task.wait(0.015)
			end
		end)

		task.delay(2, function()
			needleRunning = false
			defPanel.Visible = false
			if not dataSent then
				dataSent = true
				if Events then
					Events.QTEResult:FireServer("Defend", {
						zone = selectedZone,
						success = defenseSuccess,
					})
				end
			end
		end)
	end)
end

defBtn.MouseButton1Click:Connect(function()
	if not defPanel.Visible or defenseSuccess then return end
	local nx = defNeedle.Position.X.Offset
	local gx = 155
	local ge = 205
	defenseSuccess = (nx >= gx and nx <= ge)
	if defenseSuccess then
		playSFX("Block", 1.0, 1.1)
		cameraShake(1.0, 0.25)
		defBtn.Text = "🛡️ PERFECT BLOCK!"
		defBtn.BackgroundColor3 = Color3.fromRGB(46,204,113)
	else
		playSFX("Click", 0.5, 0.7)
		defBtn.Text = "❌ MISSED!"
		defBtn.BackgroundColor3 = Color3.fromRGB(231,76,60)
	end
end)

-- ═══════════════════════════════════════════════════════
--  EVENT CONNECTIONS
-- ═══════════════════════════════════════════════════════

if Events then
	Events.BattlePhaseUpdate.OnClientEvent:Connect(function(data)
		if not data or not data.Phase then return end
		battleGui.Enabled = true
		mySide = data.YourSide or "P1"
		currentPhase = data.Phase
		updateHP(data)

		startBattleBGM()

		if data.Phase == "Intro" then
			hideAllPanels()
			playSFX("FightVoice", 1.0)
			cameraShake(2.0, 0.5)
			showDmgNumber("⚔️ FIGHT! ⚔️", Color3.fromRGB(255, 50, 50), 0.5, true)
			phaseLbl.Text = string.format("⚔️ BATTLE BEGINS! Turn %d", data.Turn or 1)

			-- 🎬 ЕПІЧНИЙ ПРОЇЗД КАМЕРИ ПО ВБОЛІВАЛЬНИКАХ ТА ТРИБУНАХ СТАДІОНУ
			task.spawn(function()
				local origCamType = Camera.CameraType
				Camera.CameraType = Enum.CameraType.Scriptable

				local ax, az = 200, 0
				local arena = workspace:FindFirstChild("FightClubArena")
				if arena then
					local startCF = CFrame.lookAt(Vector3.new(ax - 42, 14, az - 35), Vector3.new(ax - 30, 5, az))
					local midCF   = CFrame.lookAt(Vector3.new(ax, 16, az + 42), Vector3.new(ax, 4, az))
					local endCF   = CFrame.lookAt(Vector3.new(ax + 38, 12, az - 25), Vector3.new(ax, 3, az))

					local startTime = os.clock()
					while (os.clock() - startTime) < 2.5 do
						local dt = (os.clock() - startTime) / 2.5
						if dt < 0.5 then
							local alpha = dt / 0.5
							Camera.CFrame = startCF:Lerp(midCF, alpha)
						else
							local alpha = (dt - 0.5) / 0.5
							Camera.CFrame = midCF:Lerp(endCF, alpha)
						end
						task.wait(0.016)
					end
				end

				Camera.CameraType = Enum.CameraType.Custom
			end)

		elseif data.Phase == "Attack" then
			if data.Role == "Attacker" then
				startAttackFlow(data)
			else
				hideAllPanels()
				waitPanel.Visible = true
				waitLbl.Text = "⏳ Enemy attacking..."
				phaseLbl.Text = "🔴 Turn "..data.Turn.." — Enemy is attacking, prepare to defend!"
			end

		elseif data.Phase == "Defend" then
			if data.Role == "Defender" then
				startDefendFlow(data)
			else
				hideAllPanels()
				waitPanel.Visible = true
				waitLbl.Text = "⏳ Enemy defending..."
				phaseLbl.Text = "⏳ Awaiting results..."
			end

		elseif data.Phase == "Resolution" then
			hideAllPanels()
			updateHP(data)

			local atkSide = data.AttackerSide or "P1"
			local defSide = (atkSide == "P1") and "P2" or "P1"
			local iMadeAttack = (atkSide == mySide)

			-- Lunge animation
			animateLungeAttack(atkSide, defSide, function()
				local arena = workspace:FindFirstChild("FightClubArena")
				local defPad = arena and arena:FindFirstChild(defSide .. "_SpawnPad")
				local impactPos = defPad and (defPad.Position + Vector3.new(0, 3, 0)) or Vector3.new(200, 5, 0)

				local isBlock = (data.BlockResult == "PERFECT_BLOCK")
				local isCrit = (data.IsCrit == true)

				spawnImpactParticles(impactPos, isCrit, isBlock)

				if isBlock then
					playSFX("Block", 1.0)
				elseif isCrit then
					playSFX("CritHit", 1.0)
				else
					playSFX("Hit", 0.9)
				end

				local shakeIntensity = isCrit and 2.5 or isBlock and 0.8 or 1.4
				cameraShake(shakeIntensity, 0.4)

				if data.DamageDealt and data.DamageDealt > 0 then
					local dmgPos = iMadeAttack and 0.7 or 0.3
					local txt = "-"..data.DamageDealt
					if isCrit then txt = txt .. " CRIT!" end
					showDmgNumber(txt, isCrit and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(255, 80, 80), dmgPos, isCrit)
					if not iMadeAttack then flashScreen(Color3.new(1, 0, 0)) end
				elseif isBlock then
					local pos = iMadeAttack and 0.7 or 0.3
					showDmgNumber("PERFECT BLOCK!", Color3.fromRGB(80, 200, 255), pos, false)
				elseif data.BlockResult == "PARTIAL_BLOCK" then
					local pos = iMadeAttack and 0.7 or 0.3
					showDmgNumber("PARTIAL BLOCK", Color3.fromRGB(241, 196, 15), pos, false)
				end

				if data.CounterDmg and data.CounterDmg > 0 then
					local cPos = iMadeAttack and 0.3 or 0.7
					showDmgNumber("↩️ -"..data.CounterDmg, Color3.fromRGB(255, 200, 80), cPos, false)
				end

				if data.BurnApplied then
					local p = iMadeAttack and 0.7 or 0.3
					showDmgNumber("🔥 BURN!", Color3.fromRGB(255, 120, 0), p, false)
				end
				if data.HealAmount and data.HealAmount > 0 then
					local p = iMadeAttack and 0.3 or 0.7
					showDmgNumber("💎 +"..data.HealAmount.." HP", Color3.fromRGB(0, 255, 255), p, false)
				end
				if data.GlitchApplied then
					local p = iMadeAttack and 0.7 or 0.3
					showDmgNumber("💚 GLITCH!", Color3.fromRGB(0, 255, 100), p, false)
				end
			end)

			local zoneNames = { Head="Head", Torso="Torso", Legs="Legs" }
			phaseLbl.Text = string.format("Attack: %s → %s | %s (x%.1f)",
				zoneNames[data.AttackZone or "?"] or "?",
				zoneNames[data.DefendZone or "?"] or "?",
				data.BlockResult == "PERFECT_BLOCK" and "PARRY!" or data.BlockResult == "PARTIAL_BLOCK" and "-50%" or "FULL HIT!",
				data.PowerMult or 1
			)

		elseif data.Phase == "BurnDot" then
			hideAllPanels()
			updateHP(data)
			local targetSide = data.TargetSide or "P2"
			local targetPos = (targetSide == mySide) and 0.3 or 0.7
			showDmgNumber("🔥 -"..(data.BurnDamage or 0).." BURN", Color3.fromRGB(255, 80, 20), targetPos, false)
			playSFX("Hit", 0.8)

		elseif data.Phase == "UnitSwap" then
			hideAllPanels()
			playSFX("Death", 0.9)
			cameraShake(1.8, 0.45)

			local isMySwap = (data.SwapSide == mySide)
			phaseLbl.Text = string.format("%s 💀 %s defeated! Swapping to: %s",
				isMySwap and "😱" or "🎉",
				data.DeadName or "?",
				data.NewUnit or "?"
			)
			if isMySwap then
				flashScreen(Color3.fromRGB(120, 0, 0))
			end
		end
	end)

	Events.BattleEnd.OnClientEvent:Connect(function(data)
		hideAllPanels()
		stopBattleBGM()
		resultOverlay.Visible = true
		resultOverlay.BackgroundTransparency = 0.4

		local iWon = (data.Result == data.YourSide .. "_Won")
		local isDraw = (data.Result == "Draw")

		if iWon then
			playSFX("Victory", 1.0)
			cameraShake(2.0, 0.6)
			resultLbl.Text = "🏆 VICTORY! +" .. (data.Reward or 0) .. " BrainCells"
			resultLbl.TextColor3 = Color3.fromRGB(255, 215, 0)
		elseif isDraw then
			playSFX("Click", 0.7)
			resultLbl.Text = "🤝 DRAW!"
			resultLbl.TextColor3 = Color3.fromRGB(200, 200, 200)
		else
			playSFX("Defeat", 1.0)
			cameraShake(1.5, 0.5)
			resultLbl.Text = "💀 DEFEAT!"
			resultLbl.TextColor3 = Color3.fromRGB(231, 76, 60)
			flashScreen(Color3.fromRGB(150, 0, 0))
		end

		task.delay(4.5, function()
			tw(resultOverlay, {BackgroundTransparency=1}, 0.5)
			task.delay(0.6, function()
				resultOverlay.Visible = false
				setBattleGuiVisible(false)
				phaseLbl.Text = ""
			end)
		end)
	end)
end

-- ═══════════════════════════════════════════════════════
--  SHOW TEAM SELECT WHEN GUI BECOMES VISIBLE
-- ═══════════════════════════════════════════════════════

local changePropName = battleGui:IsA("ScreenGui") and "Enabled" or "Visible"
battleGui:GetPropertyChangedSignal(changePropName):Connect(function()
	if isBattleGuiVisible() then
		hideAllPanels()
		renderTeamSelect()
		teamPanel.Visible = true
		startBattleBtn.Text = "⚔️ START BATTLE"
		startBattleBtn.BackgroundColor3 = Color3.fromRGB(46,204,113)
	else
		stopBattleBGM()
	end
end)

print("[BattleController] ⚔️ Tactical Combat UI v4.0 готовий!")
