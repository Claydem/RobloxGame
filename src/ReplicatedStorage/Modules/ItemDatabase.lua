--[[
	ItemDatabase.lua
	ReplicatedStorage.Modules.ItemDatabase
	
	Розширений конфігураційний модуль:
	- Додано AssetId з Creator Store для 3D завантаження через InsertService
	- Додано каталог товарів Магазину Догляду (Care Shop)
--]]

local ItemDatabase = {}

ItemDatabase.CaseConfig = {
	Price = 50, -- Ціна кейсу в BrainCells
}

-- Шанси випадіння
ItemDatabase.Rarities = {
	Common = {
		Name = "Common",
		Color = Color3.fromRGB(180, 180, 180),
		Weight = 70,
	},
	Rare = {
		Name = "Rare",
		Color = Color3.fromRGB(0, 170, 255),
		Weight = 25,
	},
	Legendary = {
		Name = "Legendary",
		Color = Color3.fromRGB(255, 170, 0),
		Weight = 5,
	},
}

-- Класи (Типи) з мультиплікаторами характеристик та перками
ItemDatabase.Classes = {
	Normal = {
		Name = "Normal",
		Color = Color3.fromRGB(220, 220, 220),
		HPMult = 1.0,
		DMGMult = 1.0,
		GPSMult = 1.0,
		Perk = "Standard: Balanced performance across all stats.",
	},
	Lava = {
		Name = "Lava",
		Color = Color3.fromRGB(255, 85, 0),
		HPMult = 0.9,
		DMGMult = 1.4,
		GPSMult = 1.0,
		Perk = "Explosive Burst: High Damage (+40%), Slightly Lower HP (-10%).",
	},
	Oro = {
		Name = "Oro",
		Color = Color3.fromRGB(255, 215, 0),
		HPMult = 0.8,
		DMGMult = 0.8,
		GPSMult = 2.5,
		Perk = "High Wealth: Huge Passive GPS Income (+150%).",
	},
	Hacker = {
		Name = "Hacker",
		Color = Color3.fromRGB(0, 255, 128),
		HPMult = 1.1,
		DMGMult = 1.2,
		GPSMult = 1.1,
		Perk = "Poison DoT: Corrupts enemy systems (+20% Damage, +10% HP).",
	},
	Galaxia = {
		Name = "Galaxia",
		Color = Color3.fromRGB(170, 0, 255),
		HPMult = 1.35,
		DMGMult = 1.35,
		GPSMult = 1.5,
		Perk = "Critical Strike: Cosmic Power (+35% HP, +35% Damage, +50% GPS).",
	},
	Diamante = {
		Name = "Diamante",
		Color = Color3.fromRGB(0, 220, 255),
		HPMult = 1.25,
		DMGMult = 1.25,
		GPSMult = 0.8,
		Perk = "Vampirism: High Durability & Health (+25% HP, +25% Damage).",
	},
}

-- Розрахунок необхідного XP для рівня L: XPReq(L) = floor(100 * L^1.35)
function ItemDatabase.GetXPRequired(level: number): number
	level = math.max(1, math.floor(level or 1))
	return math.floor(100 * (level ^ 1.35))
end

-- Розрахунок динамічних статів юніта з урахуванням Класу та Рівня
function ItemDatabase.GetUnitStats(unitData: table)
	if not unitData then return nil end
	local itemId = unitData.ItemId or "skibidi_toilet"
	local classKey = unitData.Class or "Normal"
	local level = math.max(1, math.floor(unitData.Level or 1))
	local xp = math.max(0, math.floor(unitData.XP or 0))

	local baseCfg = ItemDatabase.GetItem(itemId)
	local classCfg = ItemDatabase.Classes[classKey] or ItemDatabase.Classes.Normal

	local hpMult = classCfg.HPMult or 1.0
	local dmgMult = classCfg.DMGMult or 1.0
	local gpsMult = classCfg.GPSMult or 1.0

	local levelStatBonus = (level - 1) * 0.12 -- +12% за кожен рівень
	local levelGpsBonus = (level - 1) * 0.05  -- +5% GPS за кожен рівень

	local maxHP = math.max(10, math.floor(baseCfg.MaxHP * hpMult * (1 + levelStatBonus)))
	local damage = math.max(1, math.floor(baseCfg.Damage * dmgMult * (1 + levelStatBonus)))
	local incomeRate = math.max(1, math.floor(baseCfg.IncomeRate * gpsMult * (1 + levelGpsBonus)))
	local maxXP = ItemDatabase.GetXPRequired(level)

	return {
		ItemId = itemId,
		Name = baseCfg.Name,
		Class = classKey,
		ClassConfig = classCfg,
		Level = level,
		XP = xp,
		MaxXP = maxXP,
		MaxHP = maxHP,
		Damage = damage,
		IncomeRate = incomeRate,
		Description = baseCfg.Description,
		Color = classCfg.Color or baseCfg.Color,
	}
end

-- Брандрот юніти з AssetId для 3D завантаження через InsertService
ItemDatabase.Items = {
	["brainrot_67"] = {
		Id = "brainrot_67",
		Name = "67 Brainrot",
		Rarity = "Rare",
		Damage = 67,
		MaxHP = 250,
		IncomeRate = 15,
		Description = "Powerful 67 Brainrot unit from Creator Store!",
		AssetId = 112586636995159,
		Color = Color3.fromRGB(0, 150, 255),
	},
	["skibidi_toilet"] = {
		Id = "skibidi_toilet",
		Name = "Skibidi Toilet",
		Rarity = "Common",
		Damage = 15,
		MaxHP = 100,
		IncomeRate = 2,
		Description = "Classic brainrot unit. Sings his anthem and generates steady income.",
		AssetId = 13958742881, -- Roblox Creator Store Asset ID
		Color = Color3.fromRGB(240, 240, 240),
	},
	["mewing_cat"] = {
		Id = "mewing_cat",
		Name = "Mewing Cat",
		Rarity = "Common",
		Damage = 18,
		MaxHP = 110,
		IncomeRate = 3,
		Description = "Keeps its jawline sharp. Doesn't talk, only mews.",
		AssetId = 14251020478,
		Color = Color3.fromRGB(255, 180, 100),
	},
	["grimace"] = {
		Id = "grimace",
		Name = "Grimace Shake",
		Rarity = "Rare",
		Damage = 35,
		MaxHP = 180,
		IncomeRate = 8,
		Description = "Purple shake with purple power. Dangerous in combat!",
		AssetId = 14006132711,
		Color = Color3.fromRGB(155, 89, 182),
	},
	["sigma_male"] = {
		Id = "sigma_male",
		Name = "Sigma Male",
		Rarity = "Rare",
		Damage = 45,
		MaxHP = 200,
		IncomeRate = 12,
		Description = "Always on his own grindset. Ignores all enemy attacks.",
		AssetId = 14064376510,
		Color = Color3.fromRGB(52, 152, 219),
	},
	["gigachad"] = {
		Id = "gigachad",
		Name = "GigaChad",
		Rarity = "Legendary",
		Damage = 90,
		MaxHP = 400,
		IncomeRate = 30,
		Description = "Ultimate Fight Club legend. Unstoppable aura and crushing power.",
		AssetId = 14081290234,
		Color = Color3.fromRGB(241, 196, 15),
	},
}

-- Care Shop Catalog
ItemDatabase.ShopItems = {
	["regular_food"] = {
		Id = "regular_food",
		Name = "Regular Food",
		Price = 15,
		Type = "Consumable",
		Description = "Restores +25% hunger level for the selected unit.",
		HungerRestored = 25,
		Icon = "🍖",
	},
	["super_food"] = {
		Id = "super_food",
		Name = "Super Food",
		Price = 40,
		Type = "Consumable",
		Description = "Fully restores hunger (100%) + grants x2 Income Boost for 3 minutes!",
		HungerRestored = 100,
		IncomeBuffDuration = 180, -- 3 minutes
		IncomeBuffMultiplier = 2.0,
		Icon = "🌟",
	},
	["strength_elixir"] = {
		Id = "strength_elixir",
		Name = "Strength Elixir",
		Price = 50,
		Type = "Consumable",
		Description = "Increases Fight Club damage by +25% for 5 minutes!",
		DamageBuffDuration = 300, -- 5 minutes
		DamageBuffMultiplier = 1.25,
		Icon = "🧪",
	},
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

function ItemDatabase.ScanAndRegisterModels()
	local searchContainers = { ReplicatedStorage:FindFirstChild("Models"), ReplicatedStorage }
	for _, container in ipairs(searchContainers) do
		if not container then continue end
		for _, child in ipairs(container:GetDescendants()) do
			if (child:IsA("Model") or child:IsA("Tool")) and child.Name ~= "MainGui" and not child:IsDescendantOf(game:GetService("StarterGui")) then
				local id = string.lower(string.gsub(child.Name, "[%s_%-%W]", "_"))
				if string.len(id) > 1 and not ItemDatabase.Items[id] then
					local rarities = { "Common", "Common", "Rare", "Legendary" }
					local rarity = rarities[math.random(1, #rarities)]
					local dmg = (rarity == "Legendary" and 95) or (rarity == "Rare" and 45) or 20
					local inc = (rarity == "Legendary" and 30) or (rarity == "Rare" and 12) or 3

					ItemDatabase.Items[id] = {
						Id = id,
						Name = child.Name,
						Rarity = rarity,
						Damage = dmg,
						MaxHP = dmg * 3,
						IncomeRate = inc,
						Description = child.Name .. " from your 3D pack!",
						Color = Color3.fromRGB(math.random(100, 255), math.random(100, 255), math.random(100, 255)),
					}
				end
			end
		end
	end
end

pcall(function() ItemDatabase.ScanAndRegisterModels() end)

function ItemDatabase.GetItem(itemId: string)
	if not ItemDatabase.Items[itemId] then
		ItemDatabase.ScanAndRegisterModels()
	end
	local item = ItemDatabase.Items[itemId]
	if not item then
		return {
			Id = itemId,
			Name = itemId,
			Rarity = "Common",
			Damage = 25,
			MaxHP = 120,
			IncomeRate = 3,
			Description = itemId .. " from your 3D pack!",
			Color = Color3.fromRGB(200, 200, 200),
		}
	end
	return item
end

function ItemDatabase.GetShopItem(shopItemId: string)
	return ItemDatabase.ShopItems[shopItemId]
end

function ItemDatabase.GetItemsByRarity(rarityName: string)
	ItemDatabase.ScanAndRegisterModels()
	local result = {}
	for id, item in pairs(ItemDatabase.Items) do
		if item.Rarity == rarityName then
			table.insert(result, item)
		end
	end
	return result
end

function ItemDatabase.GetAllItemIds()
	ItemDatabase.ScanAndRegisterModels()
	local ids = {}
	for id, _ in pairs(ItemDatabase.Items) do
		table.insert(ids, id)
	end
	return ids
end

return ItemDatabase
