--[[
	ItemDatabase.lua
	ReplicatedStorage.Modules.ItemDatabase
	
	v2.0 — 87 видів × 6 класів = 522 комбінації
	Дворівнева система рідкості:
	  - Клас (Normal, Lava, Oro, Hacker, Galaxia, Diamante) зі своїми вагами
	  - Вид (87 брейнротів) з рідкістю Common → Legendary
	Фінальні стати = BaseStat × ClassMult × LevelBonus
--]]

local ItemDatabase = {}

-- ═══════════════════════════════════════════════════════
--  CASE CONFIG
-- ═══════════════════════════════════════════════════════

ItemDatabase.CaseConfig = {
	Price = 50,
}

-- ═══════════════════════════════════════════════════════
--  RARITY TIERS (для видів)
-- ═══════════════════════════════════════════════════════

ItemDatabase.Rarities = {
	Common = {
		Name = "Common",
		Color = Color3.fromRGB(180, 180, 180),
		Weight = 50,
		Icon = "⚪",
		Order = 1,
	},
	Uncommon = {
		Name = "Uncommon",
		Color = Color3.fromRGB(46, 204, 113),
		Weight = 28,
		Icon = "🟢",
		Order = 2,
	},
	Rare = {
		Name = "Rare",
		Color = Color3.fromRGB(52, 152, 219),
		Weight = 15,
		Icon = "🔵",
		Order = 3,
	},
	Epic = {
		Name = "Epic",
		Color = Color3.fromRGB(155, 89, 182),
		Weight = 5.5,
		Icon = "🟣",
		Order = 4,
	},
	Legendary = {
		Name = "Legendary",
		Color = Color3.fromRGB(255, 170, 0),
		Weight = 1.5,
		Icon = "🟡",
		Order = 5,
	},
}

-- ═══════════════════════════════════════════════════════
--  CLASSES (типи) з бойовими перками
-- ═══════════════════════════════════════════════════════

ItemDatabase.Classes = {
	Normal = {
		Name = "Normal",
		Color = Color3.fromRGB(220, 220, 220),
		HPMult = 1.0,
		DMGMult = 1.0,
		GPSMult = 1.0,
		Weight = 35,
		NamePrefix = "",
		Ability = "None",
		AbilityIcon = "",
		Perk = "Balanced: no special effects, solid all-around performance.",
	},
	Lava = {
		Name = "Lava",
		Color = Color3.fromRGB(255, 85, 0),
		HPMult = 0.9,
		DMGMult = 1.4,
		GPSMult = 1.0,
		Weight = 18,
		NamePrefix = "Lava",
		Ability = "Burn",
		AbilityIcon = "🔥",
		Perk = "Burn DoT: after attacking, enemy takes +15% DMG next turn.",
	},
	Oro = {
		Name = "Oro",
		Color = Color3.fromRGB(255, 215, 0),
		HPMult = 0.8,
		DMGMult = 0.8,
		GPSMult = 2.5,
		Weight = 10,
		NamePrefix = "Gold",
		Ability = "DoubleReward",
		AbilityIcon = "💰",
		Perk = "Double Reward: x2 BrainCells on victory. Lower combat stats.",
	},
	Hacker = {
		Name = "Hacker",
		Color = Color3.fromRGB(0, 255, 128),
		HPMult = 1.1,
		DMGMult = 1.2,
		GPSMult = 1.1,
		Weight = 18,
		NamePrefix = "Hacker",
		Ability = "Glitch",
		AbilityIcon = "💚",
		Perk = "Glitch: 20% chance to break enemy block (Perfect→Partial, Partial→Miss).",
	},
	Galaxia = {
		Name = "Galaxia",
		Color = Color3.fromRGB(170, 0, 255),
		HPMult = 1.35,
		DMGMult = 1.35,
		GPSMult = 1.5,
		Weight = 15,
		NamePrefix = "Galaxia",
		Ability = "CritBoost",
		AbilityIcon = "🌌",
		Perk = "Crit Boost: 50% crit chance (vs 25%), x1.75 crit DMG (vs x1.5).",
	},
	Diamante = {
		Name = "Diamante",
		Color = Color3.fromRGB(0, 220, 255),
		HPMult = 1.25,
		DMGMult = 1.25,
		GPSMult = 0.8,
		Weight = 12,
		NamePrefix = "Diamante",
		Ability = "Vampirism",
		AbilityIcon = "💎",
		Perk = "Vampirism: heals 20% of damage dealt on each attack.",
	},
}

-- ═══════════════════════════════════════════════════════
--  87 BASE SPECIES
-- ═══════════════════════════════════════════════════════

ItemDatabase.BaseSpecies = {
	-- ══════════ LEGENDARY (2) ══════════
	["bombardiro_crocodilo"] = { Name = "Bombardiro Crocodilo", Rarity = "Legendary", Damage = 100, MaxHP = 500, IncomeRate = 35 },
	["1x1x1x1"]             = { Name = "1x1x1x1",             Rarity = "Legendary", Damage = 95,  MaxHP = 450, IncomeRate = 30 },

	-- ══════════ EPIC (7) ══════════
	["tralalero_tralala"]          = { Name = "Tralalero Tralala",          Rarity = "Epic", Damage = 75, MaxHP = 400, IncomeRate = 25 },
	["cappuccino_assassino"]       = { Name = "Cappuccino Assassino",       Rarity = "Epic", Damage = 72, MaxHP = 380, IncomeRate = 22 },
	["la_grande_combinasion"]      = { Name = "La Grande Combinasion",      Rarity = "Epic", Damage = 70, MaxHP = 390, IncomeRate = 24 },
	["dragon_cannelloni"]          = { Name = "Dragon Cannelloni",          Rarity = "Epic", Damage = 68, MaxHP = 370, IncomeRate = 20 },
	["illuminato_triangolo"]       = { Name = "Illuminato Triangolo",       Rarity = "Epic", Damage = 65, MaxHP = 360, IncomeRate = 23 },
	["glorbo_fruttodrillo"]        = { Name = "Glorbo Fruttodrillo",        Rarity = "Epic", Damage = 63, MaxHP = 350, IncomeRate = 19 },
	["trippi_troppi_troppa_trippa"] = { Name = "Trippi Troppi Troppa Trippa", Rarity = "Epic", Damage = 60, MaxHP = 320, IncomeRate = 18 },

	-- ══════════ RARE (13) ══════════
	["brr_brr_patapim"]         = { Name = "Brr Brr Patapim",         Rarity = "Rare", Damage = 50, MaxHP = 280, IncomeRate = 14 },
	["svinina_bombardino"]      = { Name = "Svinina Bombardino",      Rarity = "Rare", Damage = 48, MaxHP = 270, IncomeRate = 13 },
	["gorillo_watermelondrillo"] = { Name = "Gorillo Watermelondrillo", Rarity = "Rare", Damage = 47, MaxHP = 265, IncomeRate = 13 },
	["cocofanto_elefanto"]      = { Name = "Cocofanto Elefanto",      Rarity = "Rare", Damage = 46, MaxHP = 260, IncomeRate = 12 },
	["ganganzelli_trulala"]     = { Name = "Ganganzelli Trulala",     Rarity = "Rare", Damage = 45, MaxHP = 255, IncomeRate = 12 },
	["quesadilla_crocodila"]    = { Name = "Quesadilla Crocodila",    Rarity = "Rare", Damage = 44, MaxHP = 250, IncomeRate = 12 },
	["tigroligre_frutonni"]     = { Name = "Tigroligre Frutonni",     Rarity = "Rare", Damage = 43, MaxHP = 245, IncomeRate = 11 },
	["bobrito_bandito"]         = { Name = "Bobrito Bandito",         Rarity = "Rare", Damage = 42, MaxHP = 240, IncomeRate = 11 },
	["lirili_larila"]           = { Name = "Lirili Larila",           Rarity = "Rare", Damage = 40, MaxHP = 230, IncomeRate = 11 },
	["rhino_toasterino"]        = { Name = "Rhino Toasterino",        Rarity = "Rare", Damage = 39, MaxHP = 225, IncomeRate = 10 },
	["tric_trac_barabum"]       = { Name = "Tric Trac Barabum",       Rarity = "Rare", Damage = 38, MaxHP = 220, IncomeRate = 10 },
	["cavallo_virtuoso"]        = { Name = "Cavallo Virtuoso",        Rarity = "Rare", Damage = 37, MaxHP = 215, IncomeRate = 10 },
	["trulimero_trulicina"]     = { Name = "Trulimero Trulicina",     Rarity = "Rare", Damage = 35, MaxHP = 200, IncomeRate = 10 },

	-- ══════════ UNCOMMON (25) ══════════
	["lionel_cactuseli"]          = { Name = "Lionel Cactuseli",          Rarity = "Uncommon", Damage = 30, MaxHP = 180, IncomeRate = 7 },
	["orangutini_ananassini"]     = { Name = "Orangutini Ananassini",     Rarity = "Uncommon", Damage = 29, MaxHP = 178, IncomeRate = 7 },
	["chimpanzini_bananini"]      = { Name = "Chimpanzini Bananini",      Rarity = "Uncommon", Damage = 28, MaxHP = 175, IncomeRate = 7 },
	["chef_crabracadabra"]        = { Name = "Chef Crabracadabra",        Rarity = "Uncommon", Damage = 28, MaxHP = 172, IncomeRate = 6 },
	["strawberrelli_flamingelli"] = { Name = "Strawberrelli Flamingelli", Rarity = "Uncommon", Damage = 27, MaxHP = 170, IncomeRate = 6 },
	["smurfo_gatto"]              = { Name = "Smurfo Gatto",              Rarity = "Uncommon", Damage = 27, MaxHP = 168, IncomeRate = 6 },
	["nyannini_cattalini"]        = { Name = "Nyannini Cattalini",        Rarity = "Uncommon", Damage = 26, MaxHP = 165, IncomeRate = 6 },
	["orcalero_orcala"]           = { Name = "Orcalero Orcala",           Rarity = "Uncommon", Damage = 26, MaxHP = 162, IncomeRate = 6 },
	["pandaccini_bananini"]       = { Name = "Pandaccini Bananini",       Rarity = "Uncommon", Damage = 25, MaxHP = 160, IncomeRate = 6 },
	["ballerina_cappuccina"]      = { Name = "Ballerina Cappuccina",      Rarity = "Uncommon", Damage = 25, MaxHP = 158, IncomeRate = 5 },
	["bombombini_gusini"]         = { Name = "Bombombini Gusini",         Rarity = "Uncommon", Damage = 25, MaxHP = 155, IncomeRate = 5 },
	["brri_brri_bicus_dicus"]     = { Name = "Brri Brri Bicus Dicus",     Rarity = "Uncommon", Damage = 24, MaxHP = 152, IncomeRate = 5 },
	["boneca_ambalabu"]           = { Name = "Boneca Ambalabu",           Rarity = "Uncommon", Damage = 24, MaxHP = 150, IncomeRate = 5 },
	["burbaloni_luliloli"]        = { Name = "Burbaloni Luliloli",        Rarity = "Uncommon", Damage = 24, MaxHP = 148, IncomeRate = 5 },
	["bananini_kittini"]          = { Name = "Bananini Kittini",          Rarity = "Uncommon", Damage = 23, MaxHP = 148, IncomeRate = 5 },
	["bananita_dolphinita"]       = { Name = "Bananita Dolphinita",       Rarity = "Uncommon", Damage = 23, MaxHP = 145, IncomeRate = 5 },
	["blueberrinni_octopusini"]   = { Name = "Blueberrinni Octopusini",   Rarity = "Uncommon", Damage = 23, MaxHP = 145, IncomeRate = 5 },
	["agarrini_la_pallini"]       = { Name = "Agarrini La Pallini",       Rarity = "Uncommon", Damage = 22, MaxHP = 142, IncomeRate = 5 },
	["avocadini_guffo"]           = { Name = "Avocadini Guffo",           Rarity = "Uncommon", Damage = 22, MaxHP = 142, IncomeRate = 5 },
	["cachorrito_melonito"]        = { Name = "Cachorrito Melonito",        Rarity = "Uncommon", Damage = 22, MaxHP = 140, IncomeRate = 5 },
	["chicleteira_bicicleteira"]  = { Name = "Chicleteira Bicicleteira",  Rarity = "Uncommon", Damage = 22, MaxHP = 140, IncomeRate = 5 },
	["espresso_signora"]          = { Name = "Espresso Signora",          Rarity = "Uncommon", Damage = 22, MaxHP = 140, IncomeRate = 5 },
	["girafa_celeste"]            = { Name = "Girafa Celeste",            Rarity = "Uncommon", Damage = 22, MaxHP = 140, IncomeRate = 5 },
	["strawberry_elephant"]       = { Name = "Strawberry Elephant",       Rarity = "Uncommon", Damage = 22, MaxHP = 140, IncomeRate = 5 },
	["torrtuginni_dragonfrutini"] = { Name = "Torrtuginni Dragonfrutini", Rarity = "Uncommon", Damage = 22, MaxHP = 140, IncomeRate = 5 },

	-- ══════════ COMMON (40) ══════════
	["talpa_di_fero"]                = { Name = "Talpa Di Fero",                Rarity = "Common", Damage = 18, MaxHP = 120, IncomeRate = 3 },
	["fluri_flura"]                  = { Name = "Fluri Flura",                  Rarity = "Common", Damage = 18, MaxHP = 118, IncomeRate = 3 },
	["trippi_troppi"]                = { Name = "Trippi Troppi",                Rarity = "Common", Damage = 17, MaxHP = 115, IncomeRate = 3 },
	["tralaledon"]                   = { Name = "Tralaledon",                   Rarity = "Common", Damage = 17, MaxHP = 115, IncomeRate = 3 },
	["tralalita_tralala"]            = { Name = "Tralalita Tralala",            Rarity = "Common", Damage = 17, MaxHP = 112, IncomeRate = 3 },
	["triplito_tralaleritos"]        = { Name = "Triplito Tralaleritos",        Rarity = "Common", Damage = 16, MaxHP = 110, IncomeRate = 3 },
	["los_tralaleritos"]             = { Name = "Los Tralaleritos",             Rarity = "Common", Damage = 16, MaxHP = 110, IncomeRate = 3 },
	["ballerino_lololo"]             = { Name = "Ballerino Lololo",             Rarity = "Common", Damage = 16, MaxHP = 108, IncomeRate = 3 },
	["bambini_crostini"]             = { Name = "Bambini Crostini",             Rarity = "Common", Damage = 16, MaxHP = 108, IncomeRate = 3 },
	["banana_dancana"]               = { Name = "Banana Dancana",               Rarity = "Common", Damage = 15, MaxHP = 105, IncomeRate = 2 },
	["cacto_hipopotamo"]             = { Name = "Cacto Hipopotamo",             Rarity = "Common", Damage = 15, MaxHP = 105, IncomeRate = 2 },
	["chillin_chili"]                = { Name = "Chillin Chili",                Rarity = "Common", Damage = 15, MaxHP = 105, IncomeRate = 2 },
	["frigo_camelo"]                 = { Name = "Frigo Camelo",                 Rarity = "Common", Damage = 15, MaxHP = 105, IncomeRate = 2 },
	["gangster_footera"]             = { Name = "Gangster Footera",             Rarity = "Common", Damage = 15, MaxHP = 102, IncomeRate = 2 },
	["garamararam"]                  = { Name = "Garamararam",                  Rarity = "Common", Damage = 15, MaxHP = 102, IncomeRate = 2 },
	["swag_soda"]                    = { Name = "Swag Soda",                    Rarity = "Common", Damage = 15, MaxHP = 100, IncomeRate = 2 },
	["meowl"]                        = { Name = "Meowl",                        Rarity = "Common", Damage = 14, MaxHP = 100, IncomeRate = 2 },
	["matteo"]                       = { Name = "Matteo",                       Rarity = "Common", Damage = 14, MaxHP = 100, IncomeRate = 2 },
	["madudung"]                     = { Name = "Madudung",                     Rarity = "Common", Damage = 14, MaxHP = 98,  IncomeRate = 2 },
	["zibra_zubra_zibralini"]        = { Name = "Zibra Zubra Zibralini",        Rarity = "Common", Damage = 14, MaxHP = 98,  IncomeRate = 2 },
	["lerulerulerule"]               = { Name = "Lerulerulerule",               Rarity = "Common", Damage = 14, MaxHP = 95,  IncomeRate = 2 },
	["la_vacca_saturno_saturnita"]   = { Name = "La Vacca Saturno Saturnita",   Rarity = "Common", Damage = 14, MaxHP = 95,  IncomeRate = 2 },
	["chicleteirina_bicicleteirina"] = { Name = "Chicleteirina Bicicleteirina", Rarity = "Common", Damage = 13, MaxHP = 95,  IncomeRate = 2 },
	["esok_sekolah"]                 = { Name = "Esok Sekolah",                 Rarity = "Common", Damage = 13, MaxHP = 92,  IncomeRate = 2 },
	["job_job_job_sahur"]            = { Name = "Job Job Job Sahur",            Rarity = "Common", Damage = 13, MaxHP = 92,  IncomeRate = 2 },
	["karkerkar_kurkur"]             = { Name = "Karkerkar Kurkur",             Rarity = "Common", Damage = 13, MaxHP = 90,  IncomeRate = 2 },
	["noo_my_examen"]                = { Name = "Noo My Examen",                Rarity = "Common", Damage = 13, MaxHP = 90,  IncomeRate = 2 },
	["yess_my_examen"]               = { Name = "Yess My Examen",               Rarity = "Common", Damage = 13, MaxHP = 90,  IncomeRate = 2 },
	["odin_din_din_dun"]             = { Name = "Odin Din Din Dun",             Rarity = "Common", Damage = 12, MaxHP = 88,  IncomeRate = 2 },
	["pakrahmatmamat"]               = { Name = "Pakrahmatmamat",               Rarity = "Common", Damage = 12, MaxHP = 88,  IncomeRate = 2 },
	["pakrahmatmatina"]              = { Name = "Pakrahmatmatina",              Rarity = "Common", Damage = 12, MaxHP = 85,  IncomeRate = 2 },
	["pipi_kiwi"]                    = { Name = "Pipi Kiwi",                    Rarity = "Common", Damage = 12, MaxHP = 85,  IncomeRate = 2 },
	["pipi_potato"]                  = { Name = "Pipi Potato",                  Rarity = "Common", Damage = 12, MaxHP = 85,  IncomeRate = 2 },
	["pot_hotspot"]                  = { Name = "Pot Hotspot",                  Rarity = "Common", Damage = 12, MaxHP = 82,  IncomeRate = 2 },
	["six_seven"]                    = { Name = "Six Seven",                    Rarity = "Common", Damage = 12, MaxHP = 82,  IncomeRate = 2 },
	["ta_ta_ta_ta_sahur"]            = { Name = "Ta Ta Ta Ta Sahur",            Rarity = "Common", Damage = 12, MaxHP = 80,  IncomeRate = 2 },
	["tim_cheese"]                   = { Name = "Tim Cheese",                   Rarity = "Common", Damage = 12, MaxHP = 80,  IncomeRate = 2 },
	["tirilikalika_tirilikalako"]    = { Name = "Tirilikalika Tirilikalako",    Rarity = "Common", Damage = 12, MaxHP = 80,  IncomeRate = 2 },
	["tung_sahur"]                   = { Name = "Tung Sahur",                   Rarity = "Common", Damage = 12, MaxHP = 80,  IncomeRate = 2 },
	["w_or_l"]                       = { Name = "W Or L",                       Rarity = "Common", Damage = 12, MaxHP = 80,  IncomeRate = 2 },
}

-- ═══════════════════════════════════════════════════════
--  CARE SHOP
-- ═══════════════════════════════════════════════════════

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
		IncomeBuffDuration = 180,
		IncomeBuffMultiplier = 2.0,
		Icon = "🌟",
	},
	["strength_elixir"] = {
		Id = "strength_elixir",
		Name = "Strength Elixir",
		Price = 50,
		Type = "Consumable",
		Description = "Increases Fight Club damage by +25% for 5 minutes!",
		DamageBuffDuration = 300,
		DamageBuffMultiplier = 1.25,
		Icon = "🧪",
	},
}

-- ═══════════════════════════════════════════════════════
--  XP & LEVEL FORMULAS
-- ═══════════════════════════════════════════════════════

function ItemDatabase.GetXPRequired(level: number): number
	level = math.max(1, math.floor(level or 1))
	return math.floor(100 * (level ^ 1.35))
end

-- ═══════════════════════════════════════════════════════
--  WEIGHTED RANDOM ROLL HELPERS
-- ═══════════════════════════════════════════════════════

local function weightedRoll(weightTable)
	local totalWeight = 0
	for _, entry in ipairs(weightTable) do
		totalWeight = totalWeight + entry.Weight
	end
	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, entry in ipairs(weightTable) do
		cumulative = cumulative + entry.Weight
		if roll <= cumulative then
			return entry.Key
		end
	end
	return weightTable[#weightTable].Key
end

function ItemDatabase.RollRandomClass(): string
	local wt = {}
	for key, cls in pairs(ItemDatabase.Classes) do
		table.insert(wt, { Key = key, Weight = cls.Weight })
	end
	return weightedRoll(wt)
end

function ItemDatabase.RollRandomRarity(): string
	local wt = {}
	for key, rar in pairs(ItemDatabase.Rarities) do
		table.insert(wt, { Key = key, Weight = rar.Weight })
	end
	return weightedRoll(wt)
end

function ItemDatabase.RollRandomSpecies()
	local rarityKey = ItemDatabase.RollRandomRarity()
	local pool = ItemDatabase.GetSpeciesByRarity(rarityKey)
	if #pool == 0 then
		-- Fallback: pick from Common
		pool = ItemDatabase.GetSpeciesByRarity("Common")
	end
	local chosen = pool[math.random(1, #pool)]
	return chosen.Id, rarityKey
end

-- ═══════════════════════════════════════════════════════
--  LOOKUP FUNCTIONS
-- ═══════════════════════════════════════════════════════

function ItemDatabase.GetSpeciesByRarity(rarityName: string)
	local result = {}
	for id, species in pairs(ItemDatabase.BaseSpecies) do
		if species.Rarity == rarityName then
			local entry = {}
			for k, v in pairs(species) do entry[k] = v end
			entry.Id = id
			table.insert(result, entry)
		end
	end
	return result
end

function ItemDatabase.GetItem(itemId: string)
	local species = ItemDatabase.BaseSpecies[itemId]
	if species then
		return {
			Id = itemId,
			Name = species.Name,
			Rarity = species.Rarity,
			Damage = species.Damage,
			MaxHP = species.MaxHP,
			IncomeRate = species.IncomeRate,
			Description = species.Name .. " — " .. species.Rarity .. " Brainrot!",
			Color = ItemDatabase.Rarities[species.Rarity] and ItemDatabase.Rarities[species.Rarity].Color or Color3.fromRGB(200, 200, 200),
		}
	end
	-- Fallback for unknown items
	return {
		Id = itemId,
		Name = itemId,
		Rarity = "Common",
		Damage = 12,
		MaxHP = 80,
		IncomeRate = 2,
		Description = itemId .. " — unknown brainrot!",
		Color = Color3.fromRGB(200, 200, 200),
	}
end

function ItemDatabase.GetUnitStats(unitData: any)
	if not unitData then return nil end
	local itemId = unitData.ItemId or "tralalero_tralala"
	local classKey = unitData.Class or "Normal"
	local level = math.max(1, math.floor(unitData.Level or 1))
	local xp = math.max(0, math.floor(unitData.XP or 0))

	local baseCfg = ItemDatabase.GetItem(itemId)
	local classCfg = ItemDatabase.Classes[classKey] or ItemDatabase.Classes.Normal

	local hpMult = classCfg.HPMult or 1.0
	local dmgMult = classCfg.DMGMult or 1.0
	local gpsMult = classCfg.GPSMult or 1.0

	local levelStatBonus = (level - 1) * 0.12
	local levelGpsBonus = (level - 1) * 0.05

	local maxHP = math.max(10, math.floor(baseCfg.MaxHP * hpMult * (1 + levelStatBonus)))
	local damage = math.max(1, math.floor(baseCfg.Damage * dmgMult * (1 + levelStatBonus)))
	local incomeRate = math.max(1, math.floor(baseCfg.IncomeRate * gpsMult * (1 + levelGpsBonus)))
	local maxXP = ItemDatabase.GetXPRequired(level)

	-- Build display name with class prefix
	local displayName = baseCfg.Name
	if classCfg.NamePrefix and classCfg.NamePrefix ~= "" then
		displayName = classCfg.NamePrefix .. " " .. baseCfg.Name
	end

	return {
		ItemId = itemId,
		Name = displayName,
		BaseName = baseCfg.Name,
		Class = classKey,
		ClassConfig = classCfg,
		Rarity = baseCfg.Rarity,
		RarityConfig = ItemDatabase.Rarities[baseCfg.Rarity],
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

function ItemDatabase.GetShopItem(shopItemId: string)
	return ItemDatabase.ShopItems[shopItemId]
end

function ItemDatabase.GetAllSpeciesIds()
	local ids = {}
	for id, _ in pairs(ItemDatabase.BaseSpecies) do
		table.insert(ids, id)
	end
	return ids
end

-- Backward compat aliases
ItemDatabase.GetAllItemIds = ItemDatabase.GetAllSpeciesIds
ItemDatabase.Items = ItemDatabase.BaseSpecies

function ItemDatabase.GetItemsByRarity(rarityName: string)
	return ItemDatabase.GetSpeciesByRarity(rarityName)
end

return ItemDatabase
