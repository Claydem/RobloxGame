--[[
	MapManager.lua  v3.0
	ServerScriptService.Modules.MapManager

	Генерує повну 3D-архітектуру карти:
	  1. Central Hub  — спавн, Gacha Station, навігація
	  2. Pet Care Zone — парк з майданчиками, годувальницями, лавочками
	  3. Fight Club Arena — ринг, трибуни, Matchmaking Pad

	Усі зони з'єднані телепорт-падами (Touched + ProximityPrompt).
	Код працює повністю через Rojo live-sync.
--]]

local Workspace      = game:GetService("Workspace")
local Lighting       = game:GetService("Lighting")

local MapManager = {}

-- ════════════════════════════════════════════════════════
--  UTILITY FUNCTIONS
-- ════════════════════════════════════════════════════════

local function part(name, size, pos, color, mat, parent)
	local p = Instance.new("Part")
	p.Name     = name
	p.Size     = size
	p.Position = pos
	p.Color    = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.Parent   = parent
	return p
end

local function wedge(name, size, cf, color, mat, parent)
	local w = Instance.new("WedgePart")
	w.Name     = name
	w.Size     = size
	w.CFrame   = cf
	w.Color    = color
	w.Material = mat or Enum.Material.SmoothPlastic
	w.Anchored = true
	w.Parent   = parent
	return w
end

local function cylinder(name, size, cf, color, mat, parent)
	local p = Instance.new("Part")
	p.Name     = name
	p.Shape    = Enum.PartType.Cylinder
	p.Size     = size
	p.CFrame   = cf
	p.Color    = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.Parent   = parent
	return p
end

local function ball(name, radius, pos, color, mat, parent)
	local p = Instance.new("Part")
	p.Name     = name
	p.Shape    = Enum.PartType.Ball
	p.Size     = Vector3.new(radius*2, radius*2, radius*2)
	p.Position = pos
	p.Color    = color
	p.Material = mat or Enum.Material.Neon
	p.Anchored = true
	p.Parent   = parent
	return p
end

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

local function pointLight(parent, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color      = color
	l.Range      = range or 20
	l.Brightness = brightness or 1.5
	l.Parent     = parent
	return l
end

local function spotLight(parent, color, range, angle, brightness)
	local l = Instance.new("SpotLight")
	l.Color      = color
	l.Range      = range or 30
	l.Angle      = angle or 45
	l.Brightness = brightness or 2
	l.Face       = Enum.NormalId.Bottom
	l.Parent     = parent
	return l
end

local function particles(parent, color, rate, speed, size, lifetime)
	local pe = Instance.new("ParticleEmitter")
	pe.Color       = ColorSequence.new(color)
	pe.Size        = NumberSequence.new(size or 0.3, 0)
	pe.Lifetime    = NumberRange.new(lifetime or 1, (lifetime or 1) + 1)
	pe.Rate        = rate or 15
	pe.Speed       = NumberRange.new(speed or 2, (speed or 2) + 2)
	pe.SpreadAngle = Vector2.new(60, 60)
	pe.Parent      = parent
	return pe
end

local function sign3D(text, parent, offset, textSize, textColor, maxDist)
	local bb = Instance.new("BillboardGui")
	bb.Size         = UDim2.new(0, 220, 0, 42)
	bb.StudsOffset  = offset or Vector3.new(0, 3.5, 0)
	bb.AlwaysOnTop  = false
	bb.MaxDistance  = maxDist or 30
	bb.Parent       = parent

	local bg = Instance.new("Frame")
	bg.Size                 = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3     = Color3.fromRGB(15, 18, 26)
	bg.BackgroundTransparency = 0.25
	bg.Parent               = bb
	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius   = UDim.new(0, 8)
	bgCorner.Parent         = bg

	local stroke = Instance.new("UIStroke")
	stroke.Color     = textColor or Color3.fromRGB(255, 215, 0)
	stroke.Thickness = 1.5
	stroke.Parent    = bg

	local label = Instance.new("TextLabel")
	label.Size                  = UDim2.new(1, -10, 1, 0)
	label.Position              = UDim2.new(0, 5, 0, 0)
	label.BackgroundTransparency = 1
	label.Text       = text
	label.TextColor3 = textColor or Color3.fromRGB(255, 255, 255)
	label.TextSize   = textSize or 13
	label.Font       = Enum.Font.GothamBold
	label.TextWrapped = true
	label.Parent     = bg
end

local function teleportPad(name, position, color, labelText, parent)
	-- Зовнішнє декоративне кільце
	local ring = part(name.."_Ring", Vector3.new(14, 0.3, 14), position - Vector3.new(0, 0.35, 0),
		Color3.fromRGB(15, 15, 25), Enum.Material.SmoothPlastic, parent)
	ring.CanCollide = false

	-- Основна платформа
	local pad = part(name, Vector3.new(10, 1, 10), position, color, Enum.Material.Neon, parent)

	-- Внутрішнє сяйво
	local glow = part(name.."_Glow", Vector3.new(8, 0.2, 8), position + Vector3.new(0, 0.6, 0),
		color, Enum.Material.Neon, parent)
	glow.Transparency = 0.5
	glow.CanCollide = false

	-- Частинки
	particles(pad, color, 20, 3, 0.4, 1.5)

	-- Точкове світло
	pointLight(pad, color, 25, 2)

	-- Підпис (видно тільки зблизька)
	sign3D(labelText, pad, Vector3.new(0, 3.5, 0), 12, Color3.fromRGB(255, 255, 255), 20)

	-- ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText             = "Телепорт"
	prompt.ObjectText             = labelText
	prompt.MaxActivationDistance   = 12
	prompt.HoldDuration           = 0.4
	prompt.Parent                 = pad

	return pad
end

-- ════════════════════════════════════════════════════════
--  LIGHTING UPGRADE
-- ════════════════════════════════════════════════════════

local function setupLighting()
	-- Technology вже налаштована через default.project.json (Roblox не дозволяє змінювати зі скрипта)
	local function safeSet(obj, prop, val)
		pcall(function() obj[prop] = val end)
	end

	safeSet(Lighting, "Ambient", Color3.fromRGB(38, 38, 46))
	safeSet(Lighting, "OutdoorAmbient", Color3.fromRGB(65, 65, 78))
	safeSet(Lighting, "Brightness", 2.8)
	safeSet(Lighting, "ClockTime", 14.5)
	safeSet(Lighting, "GeographicLatitude", 35)
	safeSet(Lighting, "EnvironmentDiffuseScale", 0.6)
	safeSet(Lighting, "EnvironmentSpecularScale", 0.6)
	safeSet(Lighting, "GlobalShadows", true)
	safeSet(Lighting, "ExposureCompensation", 0.1)

	-- Atmosphere
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atm then atm = Instance.new("Atmosphere"); atm.Parent = Lighting end
	safeSet(atm, "Density", 0.28)
	safeSet(atm, "Offset", 0.15)
	safeSet(atm, "Color", Color3.fromRGB(170, 190, 230))
	safeSet(atm, "Decay", Color3.fromRGB(218, 218, 230))
	safeSet(atm, "Glare", 0.15)
	safeSet(atm, "Haze", 1.2)

	-- Bloom
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if not bloom then bloom = Instance.new("BloomEffect"); bloom.Parent = Lighting end
	safeSet(bloom, "Intensity", 0.45)
	safeSet(bloom, "Size", 36)
	safeSet(bloom, "Threshold", 1.1)

	-- Color Correction
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if not cc then cc = Instance.new("ColorCorrectionEffect"); cc.Parent = Lighting end
	safeSet(cc, "Brightness", 0.04)
	safeSet(cc, "Contrast", 0.18)
	safeSet(cc, "Saturation", 0.3)
	safeSet(cc, "TintColor", Color3.fromRGB(255, 252, 248))

	-- Sun Rays
	local sr = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if not sr then sr = Instance.new("SunRaysEffect"); sr.Parent = Lighting end
	safeSet(sr, "Intensity", 0.14)
	safeSet(sr, "Spread", 0.85)

	-- Depth of Field (subtle)
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if not dof then dof = Instance.new("DepthOfFieldEffect"); dof.Parent = Lighting end
	safeSet(dof, "FarIntensity", 0.08)
	safeSet(dof, "FocusDistance", 100)
	safeSet(dof, "InFocusRadius", 50)
	safeSet(dof, "NearIntensity", 0)

	print("[MapManager] ✨ Lighting налаштовано!")
end

-- ════════════════════════════════════════════════════════
--  ZONE 1:  CENTRAL HUB  (origin 0,0,0)
-- ════════════════════════════════════════════════════════

local function buildHub()
	if Workspace:FindFirstChild("Hub") then return end

	local hub = Instance.new("Folder")
	hub.Name = "Hub"
	hub.Parent = Workspace

	-- ── Підлога ──────────────────────────────────────────
	local floor = part("HubFloor", Vector3.new(120, 4, 120), Vector3.new(0, -2, 0),
		Color3.fromRGB(35, 38, 48), Enum.Material.SmoothPlastic, hub)

	-- Центральний неоновий коло (малюнок підлоги)
	part("HubCenterRing1", Vector3.new(30, 0.3, 30), Vector3.new(0, 0.15, 0),
		Color3.fromRGB(0, 140, 255), Enum.Material.Neon, hub).CanCollide = false
	part("HubCenterRing2", Vector3.new(26, 0.35, 26), Vector3.new(0, 0.18, 0),
		Color3.fromRGB(25, 30, 42), Enum.Material.SmoothPlastic, hub).CanCollide = false
	part("HubCenterCore", Vector3.new(10, 0.4, 10), Vector3.new(0, 0.2, 0),
		Color3.fromRGB(255, 200, 0), Enum.Material.Neon, hub).CanCollide = false

	-- ── Спавн ───────────────────────────────────────────
	local spawn = Instance.new("SpawnLocation")
	spawn.Name     = "SpawnLocation"
	spawn.Size     = Vector3.new(14, 1, 14)
	spawn.Position = Vector3.new(0, 0.5, 20)
	spawn.Color    = Color3.fromRGB(46, 204, 113)
	spawn.Material = Enum.Material.Neon
	spawn.Anchored = true
	spawn.Duration = 0
	spawn.Transparency = 0.3
	spawn.Parent   = hub

	-- ── Головна Арка з вивіскою ─────────────────────────
	local archL = part("ArchL", Vector3.new(3, 16, 3), Vector3.new(-12, 8, -10),
		Color3.fromRGB(25, 28, 38), Enum.Material.SmoothPlastic, hub)
	local archR = part("ArchR", Vector3.new(3, 16, 3), Vector3.new(12, 8, -10),
		Color3.fromRGB(25, 28, 38), Enum.Material.SmoothPlastic, hub)
	local archTop = part("ArchTop", Vector3.new(27, 2, 4), Vector3.new(0, 17, -10),
		Color3.fromRGB(20, 22, 32), Enum.Material.SmoothPlastic, hub)

	-- Неонові акценти на арці
	part("ArchNeonL", Vector3.new(1, 14, 1), Vector3.new(-12, 8, -8.5),
		Color3.fromRGB(255, 215, 0), Enum.Material.Neon, hub)
	part("ArchNeonR", Vector3.new(1, 14, 1), Vector3.new(12, 8, -8.5),
		Color3.fromRGB(255, 215, 0), Enum.Material.Neon, hub)
	part("ArchNeonTop", Vector3.new(25, 0.6, 1), Vector3.new(0, 18.3, -8.5),
		Color3.fromRGB(0, 180, 255), Enum.Material.Neon, hub)

	sign3D("🧠 BRAINROT CASE & FIGHT CLUB", archTop, Vector3.new(0, 3, 0), 28,
		Color3.fromRGB(255, 215, 0))

	-- ── GACHA STATION (Зона відкриття кейсів) ───────────
	local gachaStation = Instance.new("Folder")
	gachaStation.Name = "GachaStation"
	gachaStation.Parent = hub

	-- Платформа
	part("GachaFloor", Vector3.new(30, 1, 20), Vector3.new(0, 0.5, -30),
		Color3.fromRGB(28, 32, 42), Enum.Material.SmoothPlastic, gachaStation)
	part("GachaFloorGlow", Vector3.new(28, 0.3, 18), Vector3.new(0, 1.15, -30),
		Color3.fromRGB(255, 170, 0), Enum.Material.Neon, gachaStation).CanCollide = false

	-- Кейс-п'єдестал (центральний)
	local pedestal = part("CasePedestal", Vector3.new(6, 4, 6), Vector3.new(0, 3, -30),
		Color3.fromRGB(22, 25, 35), Enum.Material.SmoothPlastic, gachaStation)
	part("CasePedestalGlow", Vector3.new(5, 0.5, 5), Vector3.new(0, 5.25, -30),
		Color3.fromRGB(255, 200, 0), Enum.Material.Neon, gachaStation)
	ball("CaseOrb", 1.5, Vector3.new(0, 7.5, -30),
		Color3.fromRGB(255, 215, 0), Enum.Material.Neon, gachaStation)
	pointLight(pedestal, Color3.fromRGB(255, 200, 50), 30, 2.5)

	-- Частинки навколо кейс-орба
	local orbPart = gachaStation:FindFirstChild("CaseOrb")
	if orbPart then
		particles(orbPart, Color3.fromRGB(255, 215, 0), 25, 1, 0.2, 2)
	end

	sign3D("📦 GACHA CASE STATION", pedestal, Vector3.new(0, 6, 0), 20,
		Color3.fromRGB(255, 200, 0))

	-- П'єдестали для показу вибитих брейнротів (по боках)
	for i, offset in ipairs({-10, -5, 5, 10}) do
		local showPed = part("ShowPedestal_"..i, Vector3.new(4, 2, 4),
			Vector3.new(offset, 2, -30), Color3.fromRGB(30, 35, 48), Enum.Material.SmoothPlastic, gachaStation)
		part("ShowPedGlow_"..i, Vector3.new(3.5, 0.3, 3.5),
			Vector3.new(offset, 3.15, -30), Color3.fromRGB(0, 200, 255), Enum.Material.Neon, gachaStation).CanCollide = false
		spotLight(showPed, Color3.fromRGB(200, 220, 255), 15, 35, 1.5)
	end

	-- ── Navigation Posts ───────────────────────────────
	-- Left (to Care Zone)
	local navL = part("NavPostCare", Vector3.new(2, 6, 2), Vector3.new(-25, 3, 0),
		Color3.fromRGB(30, 35, 45), Enum.Material.SmoothPlastic, hub)
	part("NavPostCareNeon", Vector3.new(0.6, 5, 0.6), Vector3.new(-25, 3, 1.5),
		Color3.fromRGB(46, 204, 113), Enum.Material.Neon, hub)
	sign3D("🏡 ← CARE ZONE", navL, Vector3.new(0, 5, 0), 16,
		Color3.fromRGB(46, 204, 113))

	-- Right (to Arena)
	local navR = part("NavPostArena", Vector3.new(2, 6, 2), Vector3.new(25, 3, 0),
		Color3.fromRGB(30, 35, 45), Enum.Material.SmoothPlastic, hub)
	part("NavPostArenaNeon", Vector3.new(0.6, 5, 0.6), Vector3.new(25, 3, 1.5),
		Color3.fromRGB(231, 76, 60), Enum.Material.Neon, hub)
	sign3D("FIGHT CLUB → ⚔️", navR, Vector3.new(0, 5, 0), 16,
		Color3.fromRGB(231, 76, 60))

	-- ── Corner Light Pillars ───────────────────────
	local pillarPositions = {
		Vector3.new(-55, 6, -55), Vector3.new(55, 6, -55),
		Vector3.new(-55, 6, 55),  Vector3.new(55, 6, 55),
		Vector3.new(-55, 6, 0),   Vector3.new(55, 6, 0),
	}
	for i, pos in ipairs(pillarPositions) do
		local pillar = part("Pillar_"..i, Vector3.new(3, 12, 3), pos,
			Color3.fromRGB(22, 25, 35), Enum.Material.SmoothPlastic, hub)
		part("PillarCap_"..i, Vector3.new(4, 0.5, 4), pos + Vector3.new(0, 6.25, 0),
			Color3.fromRGB(0, 140, 255), Enum.Material.Neon, hub)
		pointLight(pillar, Color3.fromRGB(80, 140, 255), 28, 1.8)
	end

	-- ── Walls ──────────────
	part("WallN", Vector3.new(120, 3, 2), Vector3.new(0, 1.5, -59),
		Color3.fromRGB(28, 32, 42), Enum.Material.SmoothPlastic, hub)
	part("WallS", Vector3.new(120, 3, 2), Vector3.new(0, 1.5, 59),
		Color3.fromRGB(28, 32, 42), Enum.Material.SmoothPlastic, hub)
	part("WallW", Vector3.new(2, 3, 120), Vector3.new(-59, 1.5, 0),
		Color3.fromRGB(28, 32, 42), Enum.Material.SmoothPlastic, hub)
	part("WallE", Vector3.new(2, 3, 120), Vector3.new(59, 1.5, 0),
		Color3.fromRGB(28, 32, 42), Enum.Material.SmoothPlastic, hub)

	-- Neon lines
	part("WallNeonN", Vector3.new(118, 0.4, 0.5), Vector3.new(0, 3.2, -58.5),
		Color3.fromRGB(0, 180, 255), Enum.Material.Neon, hub).CanCollide = false
	part("WallNeonS", Vector3.new(118, 0.4, 0.5), Vector3.new(0, 3.2, 58.5),
		Color3.fromRGB(0, 180, 255), Enum.Material.Neon, hub).CanCollide = false

	-- ── Teleports ────────────────────────────────────────
	teleportPad("TP_ToCare", Vector3.new(-30, 0.5, -15),
		Color3.fromRGB(46, 204, 113), "🏡 To Care Zone", hub)

	teleportPad("TP_ToArena", Vector3.new(30, 0.5, -15),
		Color3.fromRGB(231, 76, 60), "⚔️ To Fight Club", hub)

	print("[MapManager] ✅ Hub побудовано!")
end

-- ════════════════════════════════════════════════════════
--  ZONE 2:  PET CARE ZONE  (origin -200,0,0)
-- ════════════════════════════════════════════════════════

local function buildCareZone()
	if Workspace:FindFirstChild("PetCareZone") then return end

	local care = Instance.new("Folder")
	care.Name = "PetCareZone"
	care.Parent = Workspace

	local cx, cz = -200, 0 -- центр зони

	-- ── Основна травʼяна платформа ──────────────────────
	part("CareGround", Vector3.new(120, 3, 90), Vector3.new(cx, -1.5, cz),
		Color3.fromRGB(46, 125, 50), Enum.Material.Grass, care)

	-- Підрівняна доріжка по центру
	part("PathCenter", Vector3.new(4, 0.2, 70), Vector3.new(cx, 0.1, cz),
		Color3.fromRGB(190, 170, 130), Enum.Material.Cobblestone, care)
	part("PathCross", Vector3.new(80, 0.2, 4), Vector3.new(cx, 0.1, cz),
		Color3.fromRGB(190, 170, 130), Enum.Material.Cobblestone, care)

	-- ── Дерев'яна огорожа з запахом деревини ────────────
	local fenceColor = Color3.fromRGB(120, 85, 45)
	part("FenceN", Vector3.new(120, 4, 1.5), Vector3.new(cx, 2, cz - 44),
		fenceColor, Enum.Material.Wood, care)
	part("FenceS", Vector3.new(120, 4, 1.5), Vector3.new(cx, 2, cz + 44),
		fenceColor, Enum.Material.Wood, care)
	part("FenceW", Vector3.new(1.5, 4, 90), Vector3.new(cx - 59, 2, cz),
		fenceColor, Enum.Material.Wood, care)
	part("FenceE", Vector3.new(1.5, 4, 90), Vector3.new(cx + 59, 2, cz),
		fenceColor, Enum.Material.Wood, care)

	-- Стовпчики огорожі (кожні 15 studs)
	for x = -55, 55, 15 do
		part("FencePost", Vector3.new(2, 5.5, 2), Vector3.new(cx + x, 2.75, cz - 44),
			Color3.fromRGB(90, 65, 35), Enum.Material.Wood, care)
		part("FencePost", Vector3.new(2, 5.5, 2), Vector3.new(cx + x, 2.75, cz + 44),
			Color3.fromRGB(90, 65, 35), Enum.Material.Wood, care)
	end

	-- ── Entry Arch Sign ──────────────────────────
	local entryL = part("CareEntryL", Vector3.new(2, 10, 2), Vector3.new(cx - 6, 5, cz - 42),
		Color3.fromRGB(90, 65, 35), Enum.Material.Wood, care)
	local entryR = part("CareEntryR", Vector3.new(2, 10, 2), Vector3.new(cx + 6, 5, cz - 42),
		Color3.fromRGB(90, 65, 35), Enum.Material.Wood, care)
	local entryTop = part("CareEntryTop", Vector3.new(16, 2, 3), Vector3.new(cx, 11, cz - 42),
		Color3.fromRGB(80, 55, 30), Enum.Material.Wood, care)
	sign3D("🏡 CARE & PET ZONE", entryTop, Vector3.new(0, 3, 0), 22,
		Color3.fromRGB(46, 204, 113))

	-- ── Street Lamps ────────────────────────────────
	for _, xOff in ipairs({-45, -25, -5, 15, 35}) do
		local lampBase = part("LampPost", Vector3.new(1.2, 10, 1.2), Vector3.new(cx + xOff, 5, cz - 30),
			Color3.fromRGB(55, 55, 60), Enum.Material.SmoothPlastic, care)
		local lampHead = part("LampHead", Vector3.new(3, 1, 3), Vector3.new(cx + xOff, 10.5, cz - 30),
			Color3.fromRGB(255, 230, 160), Enum.Material.Neon, care)
		pointLight(lampHead, Color3.fromRGB(255, 230, 180), 35, 1.5)

		local lampBase2 = part("LampPost", Vector3.new(1.2, 10, 1.2), Vector3.new(cx + xOff, 5, cz + 30),
			Color3.fromRGB(55, 55, 60), Enum.Material.SmoothPlastic, care)
		local lampHead2 = part("LampHead", Vector3.new(3, 1, 3), Vector3.new(cx + xOff, 10.5, cz + 30),
			Color3.fromRGB(255, 230, 160), Enum.Material.Neon, care)
		pointLight(lampHead2, Color3.fromRGB(255, 230, 180), 35, 1.5)
	end

	-- ── Benches ─────────────────────────────────────────
	for i = 1, 4 do
		local bx = cx - 35 + (i - 1) * 22
		part("BenchSeat_"..i, Vector3.new(8, 0.8, 3), Vector3.new(bx, 1.4, cz + 22),
			Color3.fromRGB(140, 95, 50), Enum.Material.Wood, care)
		part("BenchLegL_"..i, Vector3.new(1, 1, 2.5), Vector3.new(bx - 3, 0.5, cz + 22),
			Color3.fromRGB(60, 60, 65), Enum.Material.SmoothPlastic, care)
		part("BenchLegR_"..i, Vector3.new(1, 1, 2.5), Vector3.new(bx + 3, 0.5, cz + 22),
			Color3.fromRGB(60, 60, 65), Enum.Material.SmoothPlastic, care)
		part("BenchBack_"..i, Vector3.new(8, 2, 0.5), Vector3.new(bx, 2.8, cz + 23.2),
			Color3.fromRGB(130, 85, 40), Enum.Material.Wood, care)
	end

	-- ── Pond ───────────────────────────────
	local pond = part("Pond", Vector3.new(16, 0.3, 12), Vector3.new(cx + 35, 0.15, cz + 10),
		Color3.fromRGB(50, 130, 200), Enum.Material.Glass, care)
	pond.Transparency = 0.4
	pond.CanCollide = false
	particles(pond, Color3.fromRGB(100, 180, 255), 8, 0.5, 0.15, 3)

	-- ── Feeding Station ──────────────────────────────
	local feedStation = part("FeedStation", Vector3.new(8, 3, 6), Vector3.new(cx - 40, 1.5, cz + 10),
		Color3.fromRGB(35, 40, 52), Enum.Material.SmoothPlastic, care)
	part("FeedBowl", Vector3.new(4, 0.8, 4), Vector3.new(cx - 40, 3.4, cz + 10),
		Color3.fromRGB(200, 160, 80), Enum.Material.SmoothPlastic, care)
	sign3D("🍗 FEEDING STATION", feedStation, Vector3.new(0, 4, 0), 16,
		Color3.fromRGB(255, 200, 100))

	-- ── Pet Pads Grid ─
	local pads = Instance.new("Folder")
	pads.Name = "PetPads"
	pads.Parent = care
	local idx = 1
	for r = 0, 2 do
		for c = 1, 5 do
			local px = cx - 40 + (c - 1) * 16
			local pz = cz - 20 + r * 16
			local padPart = part("PetPad_"..idx, Vector3.new(10, 0.5, 10), Vector3.new(px, 0.25, pz),
				Color3.fromRGB(75, 155, 85), Enum.Material.SmoothPlastic, pads)
			part("PetPadBorder_"..idx, Vector3.new(11, 0.3, 11), Vector3.new(px, 0.15, pz),
				Color3.fromRGB(50, 100, 60), Enum.Material.SmoothPlastic, pads).CanCollide = false
			idx = idx + 1
		end
	end

	-- ── Flowers ──────────────────────────────────
	for _, pos in ipairs({
		Vector3.new(cx - 50, 0.4, cz - 35), Vector3.new(cx + 50, 0.4, cz - 35),
		Vector3.new(cx - 50, 0.4, cz + 35), Vector3.new(cx + 50, 0.4, cz + 35),
	}) do
		local flower = ball("Flower", 2, pos, Color3.fromRGB(
			math.random(180, 255), math.random(80, 180), math.random(100, 200)
		), Enum.Material.Neon, care)
		flower.CanCollide = false
		particles(flower, Color3.fromRGB(255, 200, 150), 5, 0.3, 0.1, 3)
	end

	-- ── Teleport Back to Hub ──────────────────────────
	teleportPad("TP_ToHub_FromCare", Vector3.new(cx + 55, 0.5, cz),
		Color3.fromRGB(0, 170, 255), "🔙 Return to Hub", care)

	print("[MapManager] ✅ Pet Care Zone built!")
end

-- ════════════════════════════════════════════════════════
--  ZONE 3:  FIGHT CLUB ARENA  (origin +200,0,0) — ENCLOSED STADIUM WITH 360° CROWD
-- ════════════════════════════════════════════════════════

local function createSpectatorNPC(name, pos, color, parent)
	local npc = Instance.new("Model")
	npc.Name = "Spectator_" .. name
	npc.Parent = parent

	local torso = part("Torso", Vector3.new(2, 2, 1), pos + Vector3.new(0, 1.5, 0), color, Enum.Material.SmoothPlastic, npc)
	npc.PrimaryPart = torso
	local head = part("Head", Vector3.new(1.2, 1.2, 1.2), pos + Vector3.new(0, 3.1, 0), Color3.fromRGB(255, 205, 160), Enum.Material.SmoothPlastic, npc)
	local lArm = part("LArm", Vector3.new(0.8, 2, 0.8), pos + Vector3.new(-1.4, 1.5, 0), color, Enum.Material.SmoothPlastic, npc)
	local rArm = part("RArm", Vector3.new(0.8, 2, 0.8), pos + Vector3.new(1.4, 1.5, 0), color, Enum.Material.SmoothPlastic, npc)
	local legs = part("Legs", Vector3.new(1.8, 1.5, 0.9), pos + Vector3.new(0, 0.75, 0), Color3.fromRGB(30, 35, 50), Enum.Material.SmoothPlastic, npc)

	-- Join parts
	lArm.CanCollide = false; rArm.CanCollide = false; head.CanCollide = false
	return { model = npc, torso = torso, lArm = lArm, rArm = rArm, basePos = pos }
end

local function buildArena()
	if Workspace:FindFirstChild("FightClubArena") then return end

	local arena = Instance.new("Folder")
	arena.Name = "FightClubArena"
	arena.Parent = Workspace

	local ax, az = 200, 0

	-- ── 1. ЗАКРИТА ОСНОВА ТА СТІНИ СТАДІОНУ (Enclosed Stadium Base) ───────────────────────────
	part("ArenaFloor", Vector3.new(120, 4, 120), Vector3.new(ax, -2, az),
		Color3.fromRGB(18, 20, 28), Enum.Material.DiamondPlate, arena)

	-- 4 Високі закриті стіни з гартованого скла та сталі (Повний захист від випадіння)
	local glassCol = Color3.fromRGB(40, 50, 70)
	local wallN = part("EnclosedWallN", Vector3.new(120, 25, 3), Vector3.new(ax, 12.5, az - 58.5), Color3.fromRGB(25, 28, 38), Enum.Material.SmoothPlastic, arena)
	local wallS = part("EnclosedWallS", Vector3.new(120, 25, 3), Vector3.new(ax, 12.5, az + 58.5), Color3.fromRGB(25, 28, 38), Enum.Material.SmoothPlastic, arena)
	local wallW = part("EnclosedWallW", Vector3.new(3, 25, 120), Vector3.new(ax - 58.5, 12.5, az), Color3.fromRGB(25, 28, 38), Enum.Material.SmoothPlastic, arena)
	local wallE = part("EnclosedWallE", Vector3.new(3, 25, 120), Vector3.new(ax + 58.5, 12.5, az), Color3.fromRGB(25, 28, 38), Enum.Material.SmoothPlastic, arena)

	-- Захисне скло з неоновою рамкою
	local glassN = part("GlassN", Vector3.new(114, 18, 1), Vector3.new(ax, 14, az - 57), glassCol, Enum.Material.Glass, arena)
	glassN.Transparency = 0.5
	local glassS = part("GlassS", Vector3.new(114, 18, 1), Vector3.new(ax, 14, az + 57), glassCol, Enum.Material.Glass, arena)
	glassS.Transparency = 0.5

	-- Дах стадіону (Купол)
	part("ArenaRoofBeam1", Vector3.new(120, 3, 4), Vector3.new(ax, 26, az), Color3.fromRGB(35, 40, 55), Enum.Material.SmoothPlastic, arena)
	part("ArenaRoofBeam2", Vector3.new(4, 3, 120), Vector3.new(ax, 26, az), Color3.fromRGB(35, 40, 55), Enum.Material.SmoothPlastic, arena)

	-- ── 2. РИНГУВАННЯ ТА КАНИ ─────────────────────────────────
	part("RingBase", Vector3.new(46, 2, 46), Vector3.new(ax, 1, az), Color3.fromRGB(30, 15, 15), Enum.Material.SmoothPlastic, arena)
	part("RingTop", Vector3.new(42, 0.5, 42), Vector3.new(ax, 2.25, az), Color3.fromRGB(50, 25, 25), Enum.Material.Fabric, arena)

	for height = 3.5, 5.5, 1 do
		part("RopeN_"..height, Vector3.new(44, 0.3, 0.3), Vector3.new(ax, height, az - 21), Color3.fromRGB(255, 50, 50), Enum.Material.SmoothPlastic, arena)
		part("RopeS_"..height, Vector3.new(44, 0.3, 0.3), Vector3.new(ax, height, az + 21), Color3.fromRGB(255, 50, 50), Enum.Material.SmoothPlastic, arena)
		part("RopeW_"..height, Vector3.new(0.3, 0.3, 44), Vector3.new(ax - 21, height, az), Color3.fromRGB(255, 50, 50), Enum.Material.SmoothPlastic, arena)
		part("RopeE_"..height, Vector3.new(0.3, 0.3, 44), Vector3.new(ax + 21, height, az), Color3.fromRGB(255, 50, 50), Enum.Material.SmoothPlastic, arena)
	end

	local ringCorners = { Vector3.new(ax - 21, 4, az - 21), Vector3.new(ax + 21, 4, az - 21), Vector3.new(ax - 21, 4, az + 21), Vector3.new(ax + 21, 4, az + 21) }
	for i, pos in ipairs(ringCorners) do
		local post = part("RingPost_"..i, Vector3.new(2.5, 8, 2.5), pos, Color3.fromRGB(200, 30, 30), Enum.Material.Neon, arena)
		pointLight(post, Color3.fromRGB(255, 40, 40), 20, 2.5)
		ball("PostCap_"..i, 1.5, pos + Vector3.new(0, 4.5, 0), Color3.fromRGB(255, 80, 30), Enum.Material.Neon, arena)
	end

	-- ── 3. СПАВН ПЛАТФОРМИ ───────────────────────────
	local p1Pad = part("P1_SpawnPad", Vector3.new(8, 0.6, 8), Vector3.new(ax - 10, 2.8, az), Color3.fromRGB(46, 204, 113), Enum.Material.Neon, arena)
	sign3D("🟢 PLAYER", p1Pad, Vector3.new(0, 3, 0), 14, Color3.fromRGB(46, 204, 113))

	local p2Pad = part("P2_SpawnPad", Vector3.new(8, 0.6, 8), Vector3.new(ax + 10, 2.8, az), Color3.fromRGB(231, 76, 60), Enum.Material.Neon, arena)
	sign3D("🔴 OPPONENT", p2Pad, Vector3.new(0, 3, 0), 14, Color3.fromRGB(231, 76, 60))

	-- ── 4. ТРИБУНИ ПО КОЛУ (360° CIRCULAR TRIBUNES) ──────────────────
	local crowdFolder = Instance.new("Folder")
	crowdFolder.Name = "SpectatorCrowd"
	crowdFolder.Parent = arena

	local spectatorDataList = {}
	local fanColors = { Color3.fromRGB(231, 76, 60), Color3.fromRGB(52, 152, 219), Color3.fromRGB(241, 196, 15), Color3.fromRGB(155, 89, 182), Color3.fromRGB(46, 204, 113) }

	-- 4 Сторони трибун (Захід, Схід, Північ, Південь)
	for i = 0, 3 do
		-- West Tribunes
		part("TribW_"..i, Vector3.new(6, 2.5 + i * 0.8, 70), Vector3.new(ax - 35 - i * 3, 1.25 + i * 1.5, az), Color3.fromRGB(35 + i * 5, 38 + i * 5, 50), Enum.Material.SmoothPlastic, arena)
		-- East Tribunes
		part("TribE_"..i, Vector3.new(6, 2.5 + i * 0.8, 70), Vector3.new(ax + 35 + i * 3, 1.25 + i * 1.5, az), Color3.fromRGB(35 + i * 5, 38 + i * 5, 50), Enum.Material.SmoothPlastic, arena)
		-- North Tribunes
		part("TribN_"..i, Vector3.new(70, 2.5 + i * 0.8, 6), Vector3.new(ax, 1.25 + i * 1.5, az - 35 - i * 3), Color3.fromRGB(35 + i * 5, 38 + i * 5, 50), Enum.Material.SmoothPlastic, arena)
		-- South Tribunes
		part("TribS_"..i, Vector3.new(70, 2.5 + i * 0.8, 6), Vector3.new(ax, 1.25 + i * 1.5, az + 35 + i * 3), Color3.fromRGB(35 + i * 5, 38 + i * 5, 50), Enum.Material.SmoothPlastic, arena)
	end

	-- ── 5. СПАВН 24 АНІМОВАНИХ ВБОЛІВАЛЬНИКІВ (SPECTATOR CROWD NPCs) ───────────
	local npcIdx = 1
	-- Західна сторона
	for z = -25, 25, 10 do
		local pos = Vector3.new(ax - 38, 3.5, az + z)
		local npcData = createSpectatorNPC("Fan_W_"..npcIdx, pos, fanColors[math.random(1, #fanColors)], crowdFolder)
		table.insert(spectatorDataList, npcData)
		npcIdx = npcIdx + 1
	end
	-- Східна сторона
	for z = -25, 25, 10 do
		local pos = Vector3.new(ax + 38, 3.5, az + z)
		local npcData = createSpectatorNPC("Fan_E_"..npcIdx, pos, fanColors[math.random(1, #fanColors)], crowdFolder)
		table.insert(spectatorDataList, npcData)
		npcIdx = npcIdx + 1
	end
	-- Північна сторона
	for x = -25, 25, 10 do
		local pos = Vector3.new(ax + x, 3.5, az - 38)
		local npcData = createSpectatorNPC("Fan_N_"..npcIdx, pos, fanColors[math.random(1, #fanColors)], crowdFolder)
		table.insert(spectatorDataList, npcData)
		npcIdx = npcIdx + 1
	end
	-- Південна сторона
	for x = -25, 25, 10 do
		local pos = Vector3.new(ax + x, 3.5, az + 38)
		local npcData = createSpectatorNPC("Fan_S_"..npcIdx, pos, fanColors[math.random(1, #fanColors)], crowdFolder)
		table.insert(spectatorDataList, npcData)
		npcIdx = npcIdx + 1
	end

	-- 🌀 ТРИВАЛИЙ ЦИКЛ АНІМАЦІЇ НАВТОВПУ ВБОЛІВАЛЬНИКІВ (Підстрибування, Махання руками)
	task.spawn(function()
		while arena and arena.Parent do
			local t = os.clock()
			for _, npc in ipairs(spectatorDataList) do
				if npc.model and npc.model.Parent and npc.torso and npc.torso.Parent then
					local jumpOffset = math.abs(math.sin(t * 6 + (npc.basePos.X % 5))) * 0.8
					local waveAngle = math.sin(t * 8 + (npc.basePos.Z % 7)) * 0.6

					npc.torso.CFrame = CFrame.new(npc.basePos + Vector3.new(0, 1.5 + jumpOffset, 0))
					if npc.lArm and npc.lArm.Parent then
						npc.lArm.CFrame = CFrame.new(npc.basePos + Vector3.new(-1.4, 2.2 + jumpOffset, 0)) * CFrame.Angles(math.rad(140) + waveAngle, 0, 0)
					end
					if npc.rArm and npc.rArm.Parent then
						npc.rArm.CFrame = CFrame.new(npc.basePos + Vector3.new(1.4, 2.2 + jumpOffset, 0)) * CFrame.Angles(math.rad(140) - waveAngle, 0, 0)
					end
				end
			end
			task.wait(0.03)
		end
	end)

	-- ── 6. ПРОЖЕКТОРИ ТА ВИВІСКА ──────────────────────────
	local spotPositions = { Vector3.new(ax - 20, 24, az - 20), Vector3.new(ax + 20, 24, az - 20), Vector3.new(ax - 20, 24, az + 20), Vector3.new(ax + 20, 24, az + 20) }
	for i, pos in ipairs(spotPositions) do
		local spotMount = part("SpotMount_"..i, Vector3.new(3, 2, 3), pos, Color3.fromRGB(40, 40, 50), Enum.Material.SmoothPlastic, arena)
		spotLight(spotMount, Color3.fromRGB(255, 240, 220), 45, 55, 3)
	end

	local arenaSignPost = part("ArenaSignPost", Vector3.new(3, 12, 3), Vector3.new(ax, 6, az - 47), Color3.fromRGB(180, 25, 25), Enum.Material.SmoothPlastic, arena)
	sign3D("⚔️ FIGHT CLUB ARENA", arenaSignPost, Vector3.new(0, 8, 0), 28, Color3.fromRGB(255, 215, 0))

	-- ── 7. MATCHMAKING PAD ─────────────────────────────────
	local mmPad = part("MatchmakingPad", Vector3.new(12, 1, 12), Vector3.new(ax, 0.5, az + 35), Color3.fromRGB(155, 89, 182), Enum.Material.Neon, arena)
	part("MatchmakingPadRing", Vector3.new(15, 0.3, 15), Vector3.new(ax, 0.15, az + 35), Color3.fromRGB(15, 15, 25), Enum.Material.SmoothPlastic, arena).CanCollide = false
	particles(mmPad, Color3.fromRGB(155, 89, 182), 30, 4, 0.5, 2)
	pointLight(mmPad, Color3.fromRGB(155, 89, 182), 30, 2)

	local mmPrompt = Instance.new("ProximityPrompt")
	mmPrompt.ActionText           = "Find Opponent"
	mmPrompt.ObjectText           = "⚔️ Matchmaking"
	mmPrompt.MaxActivationDistance = 14
	mmPrompt.HoldDuration         = 1
	mmPrompt.Parent               = mmPad

	sign3D("⚔️ STEP HERE TO FIGHT", mmPad, Vector3.new(0, 5, 0), 18, Color3.fromRGB(200, 150, 255))

	-- ── Teleport Back to Hub ──────────────────────────
	teleportPad("TP_ToHub_FromArena", Vector3.new(ax, 0.5, az - 35), Color3.fromRGB(0, 170, 255), "🔙 Return to Hub", arena)

	print("[MapManager] ✅ Enclosed Fight Club Arena built with 360° Spectator Crowd!")
end

-- ════════════════════════════════════════════════════════
--  PUBLIC API
-- ════════════════════════════════════════════════════════

function MapManager.InitializeMap()
	print("══════════════════════════════════════════════")
	print("[MapManager] 🗺️ Побудова повної карти...")
	print("══════════════════════════════════════════════")

	local ok1, err1 = pcall(setupLighting)
	if not ok1 then warn("[MapManager] ❌ Lighting ПОМИЛКА: " .. tostring(err1)) end

	local ok2, err2 = pcall(buildHub)
	if not ok2 then warn("[MapManager] ❌ Hub ПОМИЛКА: " .. tostring(err2)) end

	local ok3, err3 = pcall(buildCareZone)
	if not ok3 then warn("[MapManager] ❌ CareZone ПОМИЛКА: " .. tostring(err3)) end

	local ok4, err4 = pcall(buildArena)
	if not ok4 then warn("[MapManager] ❌ Arena ПОМИЛКА: " .. tostring(err4)) end

	-- Аварійний спавн якщо Hub не створився
	if not Workspace:FindFirstChild("Hub") then
		warn("[MapManager] ⚠️ Hub не створено! Створюю аварійний спавн...")
		local emergencyFloor = Instance.new("Part")
		emergencyFloor.Name = "EmergencyFloor"
		emergencyFloor.Size = Vector3.new(100, 4, 100)
		emergencyFloor.Position = Vector3.new(0, -2, 0)
		emergencyFloor.Color = Color3.fromRGB(80, 80, 80)
		emergencyFloor.Anchored = true
		emergencyFloor.Parent = Workspace

		local emergencySpawn = Instance.new("SpawnLocation")
		emergencySpawn.Name = "SpawnLocation"
		emergencySpawn.Size = Vector3.new(12, 1, 12)
		emergencySpawn.Position = Vector3.new(0, 0.5, 0)
		emergencySpawn.Anchored = true
		emergencySpawn.Duration = 0
		emergencySpawn.Parent = Workspace
	end

	print("══════════════════════════════════════════════")
	print("[MapManager] 🎉 Ініціалізація карти завершена!")
	print("══════════════════════════════════════════════")
end

MapManager.InitializeMap()
return MapManager
