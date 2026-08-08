--[[
	ItemDatabase.lua
	ReplicatedStorage.Modules.ItemDatabase

	Виправлення:
	- Детермінований хеш-рандом для авто-сканованих моделей (щоб не змінювали раритет кожен запуск)
	- Сканування робиться лише один раз (ліниво, без множинних ресканів)
	- Прибрано небезпечний скан всередині ReplicatedStorage на кожен виклик GetItem
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDatabase = {}

ItemDatabase.CaseConfig = {
	Price = 50,
}

ItemDatabase.Rarities = {
	Common    = { Name = "Common",    Color = Color3.fromRGB(180, 180, 180), Weight = 70 },
	Rare      = { Name = "Rare",      Color = Color3.fromRGB(0, 170, 255),   Weight = 25 },
	Legendary = { Name = "Legendary", Color = Color3.fromRGB(255, 170, 0),   Weight = 5  },
}

ItemDatabase.Classes = {
	Normal  = { Name = "Normal",  Color = Color3.fromRGB(220,220,220), HPMult = 1.0,  DMGMult = 1.0,  GPSMult = 1.0, Perk = "Balanced." },
	Lava    = { Name = "Lava",    Color = Color3.fromRGB(255,85,0),    HPMult = 0.9,  DMGMult = 1.4,  GPSMult = 1.0, Perk = "High damage, low HP." },
	Oro     = { Name = "Oro",     Color = Color3.fromRGB(255,215,0),   HPMult = 0.8,  DMGMult = 0.8,  GPSMult = 2.5, Perk = "High gold income." },
	Hacker  = { Name = "Hacker",  Color = Color3.fromRGB(0,255,128),   HPMult = 1.1,  DMGMult = 1.2,  GPSMult = 1.1, Perk = "Balanced +." },
	Galaxia = { Name = "Galaxia", Color = Color3.fromRGB(170,0,255),   HPMult = 1.35, DMGMult = 1.35, GPSMult = 1.5, Perk = "Cosmic power." },
	Diamante= { Name = "Diamante",Color = Color3.fromRGB(0,220,255),   HPMult = 1.25, DMGMult = 1.25, GPSMult = 0.8, Perk = "Tanky bruiser." },
}

function ItemDatabase.GetXPRequired(level)
	level = math.max(1, math.floor(level or 1))
	return math.floor(100 * (level ^ 1.35))
end

function ItemDatabase.GetUnitStats(unitData)
	if type(unitData) ~= "table" then return nil end
	local itemId = unitData.ItemId or "skibidi_toilet"
	local classKey = unitData.Class or "Normal"
	local level = math.max(1, math.floor(unitData.Level or 1))
	local xp = math.max(0, math.floor(unitData.XP or 0))

	local baseCfg = ItemDatabase.GetItem(itemId)
	local classCfg = ItemDatabase.Classes[classKey] or ItemDatabase.Classes.Normal

	local lvlStat = (level - 1) * 0.12
	local lvlGps  = (level - 1) * 0.05

	local maxHP = math.max(10, math.floor(baseCfg.MaxHP * (classCfg.HPMult or 1) * (1 + lvlStat)))
	local damage = math.max(1, math.floor(baseCfg.Damage * (classCfg.DMGMult or 1) * (1 + lvlStat)))
	local incomeRate = math.max(1, math.floor(baseCfg.IncomeRate * (classCfg.GPSMult or 1) * (1 + lvlGps)))
	local maxXP = ItemDatabase.GetXPRequired(level)

	return {
		ItemId = itemId, Name = baseCfg.Name, Class = classKey,
		ClassConfig = classCfg, Level = level, XP = xp, MaxXP = maxXP,
		MaxHP = maxHP, Damage = damage, IncomeRate = incomeRate,
		Description = baseCfg.Description,
		Color = classCfg.Color or baseCfg.Color,
	}
end

ItemDatabase.Items = {
	["brainrot_67"] = {
		Id = "brainrot_67", Name = "67 Brainrot", Rarity = "Rare",
		Damage = 67, MaxHP = 250, IncomeRate = 15,
		Description = "Powerful 67 Brainrot unit!",
		AssetId = 112586636995159,
		Color = Color3.fromRGB(0,150,255),
	},
	["skibidi_toilet"] = {
		Id = "skibidi_toilet", Name = "Skibidi Toilet", Rarity = "Common",
		Damage = 15, MaxHP = 100, IncomeRate = 2,
		Description = "Classic brainrot unit.",
		AssetId = 13958742881,
		Color = Color3.fromRGB(240,240,240),
	},
	["mewing_cat"] = {
		Id = "mewing_cat", Name = "Mewing Cat", Rarity = "Common",
		Damage = 18, MaxHP = 110, IncomeRate = 3,
		Description = "Keeps its jawline sharp.",
		AssetId = 14251020478,
		Color = Color3.fromRGB(255,180,100),
	},
	["grimace"] = {
		Id = "grimace", Name = "Grimace Shake", Rarity = "Rare",
		Damage = 35, MaxHP = 180, IncomeRate = 8,
		Description = "Purple shake with purple power.",
		AssetId = 14006132711,
		Color = Color3.fromRGB(155,89,182),
	},
	["sigma_male"] = {
		Id = "sigma_male", Name = "Sigma Male", Rarity = "Rare",
		Damage = 45, MaxHP = 200, IncomeRate = 12,
		Description = "On his own grindset.",
		AssetId = 14064376510,
		Color = Color3.fromRGB(52,152,219),
	},
	["gigachad"] = {
		Id = "gigachad", Name = "GigaChad", Rarity = "Legendary",
		Damage = 90, MaxHP = 400, IncomeRate = 30,
		Description = "Ultimate Fight Club legend.",
		AssetId = 14081290234,
		Color = Color3.fromRGB(241,196,15),
	},
}

ItemDatabase.ShopItems = {
	["regular_food"] = {
		Id = "regular_food", Name = "Regular Food", Price = 15, Type = "Consumable",
		Description = "Restores +25 hunger for selected unit.", HungerRestored = 25, Icon = "🍖",
	},
	["super_food"] = {
		Id = "super_food", Name = "Super Food", Price = 40, Type = "Consumable",
		Description = "100% hunger + x2 Income for 3 min.",
		HungerRestored = 100, IncomeBuffDuration = 180, IncomeBuffMultiplier = 2.0, Icon = "🌟",
	},
	["strength_elixir"] = {
		Id = "strength_elixir", Name = "Strength Elixir", Price = 50, Type = "Consumable",
		Description = "+25% Fight Club damage for 5 min.",
		DamageBuffDuration = 300, DamageBuffMultiplier = 1.25, Icon = "🧪",
	},
}

-- ═══════════════════════════════════════════════════════
--  DETERMINISTIC HASH UTIL
-- ═══════════════════════════════════════════════════════

local function hashStr(s)
	local h = 0
	s = tostring(s or "")
	for i = 1, #s do
		h = (h*31 + string.byte(s, i)) % 2147483647
	end
	return h
end
-- [0,1) det
local function seeded01(seed)
	-- xorshift32-ish
	seed = seed ~ 0x6D2B79F5
	seed = (seed ~ (seed << 13)) & 0xFFFFFFFF
	seed = (seed ~ (seed >> 17)) & 0xFFFFFFFF
	seed = (seed ~ (seed << 5)) & 0xFFFFFFFF
	return (seed % 10000) / 10000, seed
end

local scanDone = false
function ItemDatabase.ScanAndRegisterModels()
	if scanDone then return end
	scanDone = true

	local containers = { ReplicatedStorage:FindFirstChild("Models"), ReplicatedStorage }
	local seen = {}

	local function isBad(m)
		if m:IsDescendantOf(game:GetService("StarterGui")) then return true end
		if m:IsDescendantOf(game:GetService("CoreGui")) then return true end
		if m.Name == "MainGui" or m.Name == "BattleGui" then return true end
		return false
	end

	for _, container in ipairs(containers) do
		if container then
			for _, child in ipairs(container:GetDescendants()) do
				if (child:IsA("Model") or child:IsA("Tool")) and not isBad(child) and not seen[child] then
					-- Лише leaf-моделі
					local isLeaf = true
					for _, c in ipairs(child:GetChildren()) do
						if c:IsA("Model") then isLeaf = false; break end
					end
					if isLeaf then
						seen[child] = true
						local id = string.lower(string.gsub(child.Name, "[%s%p%c]", "_"))
						id = string.gsub(id, "_+", "_")
						id = string.gsub(id, "^_+", ""):gsub("_+$", "")
						if #id > 1 and not ItemDatabase.Items[id] then
							local r = seeded01(hashStr(id))
							local rarity
							if r < 0.70 then rarity = "Common"
							elseif r < 0.95 then rarity = "Rare"
							else rarity = "Legendary" end
							local dmg = (rarity == "Legendary" and 95) or (rarity == "Rare" and 45) or 20
							local colR = seeded01(hashStr(id.."r"))
							local colG = seeded01(hashStr(id.."g"))
							local colB = seeded01(hashStr(id.."b"))
							ItemDatabase.Items[id] = {
								Id = id,
								Name = child.Name,
								Rarity = rarity,
								Damage = dmg,
								MaxHP = dmg*3,
								IncomeRate = (rarity == "Legendary" and 30) or (rarity == "Rare" and 12) or 3,
								Description = child.Name .. " (auto)",
								Color = Color3.fromRGB(100 + math.floor(colR*155), 100 + math.floor(colG*155), 100 + math.floor(colB*155)),
							}
						end
					end
				end
			end
		end
	end
end

-- Ініціалізуємо один раз при першому зверненні
setmetatable(ItemDatabase.Items, {
	__index = function(_, key)
		if type(key) ~= "string" then return nil end
		ItemDatabase.ScanAndRegisterModels()
		return rawget(ItemDatabase.Items, key)
	end,
})

pcall(ItemDatabase.ScanAndRegisterModels)

function ItemDatabase.GetItem(itemId)
	if type(itemId) ~= "string" then return nil end
	local it = ItemDatabase.Items[itemId]
	if it then return it end
	-- Повертаємо дефолтний фоллбек (не записуючи в базу, щоб не забруднювати)
	return {
		Id = itemId, Name = itemId, Rarity = "Common",
		Damage = 25, MaxHP = 120, IncomeRate = 3,
		Description = itemId .. " (fallback)",
		Color = Color3.fromRGB(200,200,200),
	}
end

function ItemDatabase.GetShopItem(id)
	return ItemDatabase.ShopItems[id]
end

function ItemDatabase.GetItemsByRarity(rarityName)
	ItemDatabase.ScanAndRegisterModels()
	local out = {}
	for _, item in pairs(ItemDatabase.Items) do
		if item.Rarity == rarityName then table.insert(out, item) end
	end
	return out
end

function ItemDatabase.GetAllItemIds()
	ItemDatabase.ScanAndRegisterModels()
	local ids = {}
	for id in pairs(ItemDatabase.Items) do table.insert(ids, id) end
	return ids
end

return ItemDatabase
