--!nonstrict
-- Stormlings: pets that follow you, catch weather for you and multiply the energy you collect.
-- Bonus is additive: total energy multiplier = 1 + sum of equipped pet bonuses.
-- Look describes how Shared/Models/PetModels builds the pet out of parts.

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local Pets = {}

Pets.Rarities = {
	Common = { Order = 1, Name = "Common", Color = rgb(196, 204, 218), Scale = 0.9 },
	Uncommon = { Order = 2, Name = "Uncommon", Color = rgb(96, 222, 112), Scale = 0.95 },
	Rare = { Order = 3, Name = "Rare", Color = rgb(72, 164, 255), Scale = 1 },
	Epic = { Order = 4, Name = "Epic", Color = rgb(182, 96, 255), Scale = 1.1 },
	Legendary = { Order = 5, Name = "Legendary", Color = rgb(255, 192, 42), Scale = 1.22 },
	Exclusive = { Order = 6, Name = "Exclusive", Color = rgb(255, 84, 156), Scale = 1.35 },
	-- Secret pets: one or more per egg, rolled before the egg's other pets at "1 in Odds" each (Eggs[*].Secrets,
	-- Formulas.HatchChances). Deep cosmic colour; the UI adds a rainbow shimmer (Pets.SecretRainbow).
	Secret = { Order = 7, Name = "Secret", Color = rgb(44, 22, 88), Scale = 1.5 },
}

-- Rainbow colour keys the UI uses on Secret tiles, labels and the secret hatch reveal
Pets.SecretRainbow = {
	rgb(255, 84, 120),
	rgb(255, 176, 54),
	rgb(255, 240, 90),
	rgb(90, 240, 150),
	rgb(70, 200, 255),
	rgb(170, 110, 255),
	rgb(255, 100, 220),
}

-- Bonus = RarityBase * ZoneFactor for egg pets
local RARITY_BASE = { Common = 0.1, Uncommon = 0.18, Rare = 0.35, Epic = 0.7, Legendary = 1.5 }
local ZONE_FACTOR = { 1, 1.6, 2.5, 4, 6.5, 10 }

Pets.Pets = {
	-------------------------------------------------------------------- Plains Cloud Egg
	Puffling = { Name = "Puffling", Rarity = "Common", Zone = 1, Look = { Body = "Cloud", Color = rgb(250, 252, 255), Accent = rgb(180, 215, 255) } },
	Droplet = { Name = "Droplet", Rarity = "Uncommon", Zone = 1, Look = { Body = "Drop", Color = rgb(90, 170, 255), Accent = rgb(190, 230, 255) } },
	Sunny = { Name = "Sunny", Rarity = "Rare", Zone = 1, Look = { Body = "Round", Color = rgb(255, 215, 60), Accent = rgb(255, 150, 40), Features = { "Rays" }, Effect = "Glow" } },
	Prism = { Name = "Prism", Rarity = "Epic", Zone = 1, Look = { Body = "Cloud", Color = rgb(255, 185, 225), Accent = rgb(130, 220, 255), Features = { "Halo" }, Effect = "Rainbow" } },
	BreezeKing = { Name = "Breeze King", Rarity = "Legendary", Zone = 1, Look = { Body = "Cloud", Color = rgb(255, 255, 255), Accent = rgb(255, 205, 60), Features = { "Crown", "Wings" }, Effect = "Sparkle" } },

	-------------------------------------------------------------------- Thunder Cloud Egg
	Static = { Name = "Static", Rarity = "Common", Zone = 2, Look = { Body = "Round", Color = rgb(150, 155, 172), Accent = rgb(255, 230, 80), Features = { "Antenna" } } },
	Zappy = { Name = "Zappy", Rarity = "Uncommon", Zone = 2, Look = { Body = "Bean", Color = rgb(255, 225, 70), Accent = rgb(255, 255, 210), Features = { "BunnyEars", "Bolt" }, Effect = "Zap" } },
	VoltBat = { Name = "Volt Bat", Rarity = "Rare", Zone = 2, Look = { Body = "Round", Color = rgb(92, 62, 142), Accent = rgb(255, 220, 70), Features = { "Wings", "Ears" }, Effect = "Zap" } },
	ThunderPup = { Name = "Thunder Pup", Rarity = "Epic", Zone = 2, Look = { Body = "Round", Color = rgb(82, 122, 205), Accent = rgb(255, 230, 90), Features = { "Ears", "Tail", "Bolt" }, Effect = "Zap" } },
	StormLord = { Name = "Storm Lord", Rarity = "Legendary", Zone = 2, Look = { Body = "Cloud", Color = rgb(62, 62, 88), Accent = rgb(255, 225, 60), Features = { "Horns", "Crown" }, Effect = "Zap", EyeColor = rgb(255, 235, 90) } },

	-------------------------------------------------------------------- Dune Cloud Egg
	Sandy = { Name = "Sandy", Rarity = "Common", Zone = 3, Look = { Body = "Round", Color = rgb(232, 202, 142), Accent = rgb(200, 160, 100) } },
	CactusCub = { Name = "Cactus Cub", Rarity = "Uncommon", Zone = 3, Look = { Body = "Bean", Color = rgb(92, 172, 82), Accent = rgb(255, 120, 170), Features = { "Spikes", "Flower" } } },
	DustBunny = { Name = "Dust Bunny", Rarity = "Rare", Zone = 3, Look = { Body = "Round", Color = rgb(215, 186, 136), Accent = rgb(255, 240, 212), Features = { "BunnyEars", "Tail" }, Effect = "Smoke" } },
	Scarab = { Name = "Scarab", Rarity = "Epic", Zone = 3, Look = { Body = "Bean", Color = rgb(40, 170, 160), Accent = rgb(255, 200, 60), Features = { "Horns", "Wings" }, Effect = "Sparkle" } },
	MirageDjinn = { Name = "Mirage Djinn", Rarity = "Legendary", Zone = 3, Look = { Body = "Drop", Color = rgb(80, 222, 255), Accent = rgb(255, 205, 60), Features = { "Crown", "Halo" }, Effect = "Glow" } },

	-------------------------------------------------------------------- Frost Cloud Egg
	Snowball = { Name = "Snowball", Rarity = "Common", Zone = 4, Look = { Body = "Round", Color = rgb(245, 250, 255), Accent = rgb(150, 200, 255) } },
	Icicle = { Name = "Icicle", Rarity = "Uncommon", Zone = 4, Look = { Body = "Crystal", Color = rgb(170, 225, 255), Accent = rgb(230, 250, 255), Effect = "Snow" } },
	Frostbite = { Name = "Frostbite", Rarity = "Rare", Zone = 4, Look = { Body = "Bean", Color = rgb(42, 46, 62), Accent = rgb(255, 150, 40), Features = { "Beak", "Belly" }, Effect = "Snow" } },
	AuroraFox = { Name = "Aurora Fox", Rarity = "Epic", Zone = 4, Look = { Body = "Round", Color = rgb(240, 245, 255), Accent = rgb(110, 255, 190), Features = { "Ears", "Tail" }, Effect = "Glow" } },
	YetiKing = { Name = "Yeti King", Rarity = "Legendary", Zone = 4, Look = { Body = "Round", Color = rgb(235, 240, 250), Accent = rgb(120, 190, 255), Features = { "Horns", "Crown" }, Effect = "Snow" } },

	-------------------------------------------------------------------- Magma Cloud Egg
	Ember = { Name = "Ember", Rarity = "Common", Zone = 5, Look = { Body = "Round", Color = rgb(255, 120, 40), Accent = rgb(255, 210, 80), Features = { "Flame" } } },
	Coal = { Name = "Coal", Rarity = "Uncommon", Zone = 5, Look = { Body = "Cube", Color = rgb(52, 46, 46), Accent = rgb(255, 110, 30), Features = { "Cracks" } } },
	LavaPup = { Name = "Lava Pup", Rarity = "Rare", Zone = 5, Look = { Body = "Round", Color = rgb(230, 80, 30), Accent = rgb(255, 200, 60), Features = { "Ears", "Tail" }, Effect = "Fire" } },
	PhoenixChick = { Name = "Phoenix Chick", Rarity = "Epic", Zone = 5, Look = { Body = "Round", Color = rgb(255, 90, 50), Accent = rgb(255, 210, 70), Features = { "Wings", "Beak", "Flame" }, Effect = "Fire" } },
	InfernoDrake = { Name = "Inferno Drake", Rarity = "Legendary", Zone = 5, Look = { Body = "Bean", Color = rgb(150, 32, 32), Accent = rgb(255, 150, 40), Features = { "Horns", "Wings", "Tail" }, Effect = "Fire", EyeColor = rgb(255, 200, 60) } },

	-------------------------------------------------------------------- Cosmic Cloud Egg
	Stardust = { Name = "Stardust", Rarity = "Common", Zone = 6, Look = { Body = "Round", Color = rgb(150, 120, 255), Accent = rgb(255, 240, 150), Effect = "Sparkle" } },
	Comet = { Name = "Comet", Rarity = "Uncommon", Zone = 6, Look = { Body = "Drop", Color = rgb(90, 150, 255), Accent = rgb(200, 240, 255), Effect = "Sparkle" } },
	Nebula = { Name = "Nebula", Rarity = "Rare", Zone = 6, Look = { Body = "Cloud", Color = rgb(220, 120, 255), Accent = rgb(120, 200, 255), Features = { "Halo" }, Effect = "Sparkle" } },
	Moonbeam = { Name = "Moonbeam", Rarity = "Epic", Zone = 6, Look = { Body = "Round", Color = rgb(212, 216, 240), Accent = rgb(255, 250, 200), Features = { "Ears", "Halo" }, Effect = "Glow" } },
	GalaxyGuardian = { Name = "Galaxy Guardian", Rarity = "Legendary", Zone = 6, Look = { Body = "Bean", Color = rgb(38, 22, 74), Accent = rgb(255, 120, 240), Features = { "Crown", "Wings", "Halo" }, Effect = "Sparkle", EyeColor = rgb(120, 230, 255) } },

	-------------------------------------------------------------------- Mega Storm exclusives
	TempestTitan = { Name = "Tempest Titan", Rarity = "Exclusive", Bonus = 5, Source = "Mega Storm: Tempest Twister", Look = { Body = "Cloud", Color = rgb(210, 235, 255), Accent = rgb(120, 200, 255), Features = { "Horns", "Wings", "Crown" }, Effect = "Sparkle" } },
	VoltWyrm = { Name = "Volt Wyrm", Rarity = "Exclusive", Bonus = 6.5, Source = "Mega Storm: Thunder Titan", Look = { Body = "Bean", Color = rgb(92, 72, 162), Accent = rgb(255, 230, 80), Features = { "Horns", "Wings", "Bolt" }, Effect = "Zap", EyeColor = rgb(255, 240, 120) } },
	FrostColossus = { Name = "Frost Colossus", Rarity = "Exclusive", Bonus = 8, Source = "Mega Storm: Blizzard Behemoth", Look = { Body = "Cube", Color = rgb(190, 230, 255), Accent = rgb(255, 255, 255), Features = { "Horns", "Crown" }, Effect = "Snow", EyeColor = rgb(90, 200, 255) } },
	CycloneDrake = { Name = "Cyclone Drake", Rarity = "Exclusive", Bonus = 10, Source = "Mega Storm: Inferno Cyclone", Look = { Body = "Bean", Color = rgb(255, 110, 40), Accent = rgb(255, 220, 90), Features = { "Horns", "Wings", "Tail" }, Effect = "Fire", EyeColor = rgb(255, 245, 160) } },
	MaelstromSpirit = { Name = "Maelstrom Spirit", Rarity = "Exclusive", Bonus = 13, Source = "Mega Storm: Cosmic Maelstrom", Look = { Body = "Cloud", Color = rgb(122, 62, 222), Accent = rgb(255, 150, 240), Features = { "Halo", "Wings", "Crown" }, Effect = "Rainbow", EyeColor = rgb(255, 200, 250) } },
	RainbowRoc = { Name = "Rainbow Roc", Rarity = "Exclusive", Bonus = 18, Source = "Mega Storm: Rainbow Hurricane", Look = { Body = "Round", Color = rgb(255, 248, 252), Accent = rgb(255, 120, 200), Features = { "Wings", "Beak", "Crown", "Tail" }, Effect = "Rainbow", EyeColor = rgb(120, 220, 255) } },

	-------------------------------------------------------------------- Rewards
	Sunbeam = { Name = "Sunbeam", Rarity = "Epic", Bonus = 0.9, Source = "Day 7 daily reward", Look = { Body = "Round", Color = rgb(255, 235, 120), Accent = rgb(255, 255, 255), Features = { "Rays", "Halo" }, Effect = "Glow" } },

	-------------------------------------------------------------------- Lobby shop (Robux)
	-- Developer product Monetization.Products.AuroraGryphon (R$2,000, one copy per purchase).
	-- Bonus 6 (+600%): the best pet you can own until about Frostpeak - it beats every egg Legendary up to
	-- the Dune Sea (3.75) and the first Mega Storm exclusive (5), equals the Frostpeak Legendary and sits just
	-- under the second one (Volt Wyrm 6.5); Frost Colossus (8), Magma/Cosmic Legendaries (9.75 / 15),
	-- Cosmic Epics (7) and crafted Golden pets pass it in the late game, so it speeds players up without
	-- replacing progression.
	AuroraGryphon = { Name = "Aurora Gryphon", Rarity = "Exclusive", Bonus = 6, Source = "Lobby shop", Look = { Body = "Round", Color = rgb(74, 98, 214), Accent = rgb(96, 246, 200), Features = { "Ears", "Wings", "Beak", "Tail" }, Effect = "Glow" } },

	-------------------------------------------------------------------- Secret pets (Eggs[*].Secrets)
	-- "OP and very very rare": each one beats everything you can get by the time you reach its egg. The first
	-- egg's secret (20) already beats every Mega Storm exclusive (best: Rainbow Roc, 18) and every egg Legendary
	-- up to the Magma egg; from the Frost egg on they are 5-12x the egg's own Legendary, and the three Cosmic
	-- secrets (110 / 140 / 180) are the best pets in the game, above even a crafted Rainbow Galaxy Guardian (90)
	-- or Rainbow Roc (108). Odds per secret: 1 in 250K (Plains) rising to 1 in 5M (the Cosmic Hypercane).
	EyeOfTheStorm = { Name = "Eye of the Storm", Rarity = "Secret", Zone = 1, Bonus = 20, Look = { Body = "Cloud", Color = rgb(236, 244, 255), Accent = rgb(84, 196, 255), Features = { "Crown", "Halo", "Wings" }, Effect = "Sparkle", EyeColor = rgb(96, 228, 255) } },
	ThunderKirin = { Name = "Thunderclap Kirin", Rarity = "Secret", Zone = 2, Bonus = 25, Look = { Body = "Bean", Color = rgb(44, 40, 104), Accent = rgb(255, 214, 64), Features = { "Horns", "Tail", "Bolt" }, Effect = "Zap", EyeColor = rgb(255, 238, 110) } },
	SandstormSphinx = { Name = "Sandstorm Sphinx", Rarity = "Secret", Zone = 3, Bonus = 32, Look = { Body = "Round", Color = rgb(238, 196, 104), Accent = rgb(38, 86, 196), Features = { "Wings", "Tail", "Halo" }, Effect = "Glow", EyeColor = rgb(80, 255, 226) } },
	BlizzardMonarch = { Name = "Blizzard Monarch", Rarity = "Secret", Zone = 4, Bonus = 45, Look = { Body = "Round", Color = rgb(232, 244, 255), Accent = rgb(110, 190, 255), Features = { "Ears", "Crown", "Wings" }, Effect = "Snow", EyeColor = rgb(130, 230, 255) } },
	TempestPhoenix = { Name = "Tempest Phoenix", Rarity = "Secret", Zone = 5, Bonus = 70, Look = { Body = "Round", Color = rgb(255, 86, 44), Accent = rgb(255, 196, 56), Features = { "Beak", "Flame", "Wings", "Tail" }, Effect = "Fire", EyeColor = rgb(255, 246, 170) } },
	PyroclasmDragon = { Name = "Pyroclasm Dragon", Rarity = "Secret", Zone = 5, Bonus = 95, Look = { Body = "Bean", Color = rgb(44, 34, 40), Accent = rgb(255, 112, 28), Features = { "Cracks", "Horns", "Crown", "Wings", "Tail" }, Effect = "Fire", EyeColor = rgb(255, 206, 64) } },
	VoidLeviathan = { Name = "Void Leviathan", Rarity = "Secret", Zone = 6, Bonus = 110, Look = { Body = "Drop", Color = rgb(26, 18, 62), Accent = rgb(64, 236, 255), Features = { "Halo", "Wings" }, Effect = "Sparkle", EyeColor = rgb(150, 255, 250) } },
	NovaSeraph = { Name = "Nova Seraph", Rarity = "Secret", Zone = 6, Bonus = 140, Look = { Body = "Round", Color = rgb(255, 250, 236), Accent = rgb(255, 196, 72), Features = { "Crown", "Halo", "Wings" }, Effect = "Glow", EyeColor = rgb(255, 170, 240) } },
	Hypercane = { Name = "Hypercane", Rarity = "Secret", Zone = 6, Bonus = 180, Look = { Body = "Cloud", Color = rgb(30, 18, 52), Accent = rgb(255, 84, 220), Features = { "Horns", "Crown", "Halo", "Wings" }, Effect = "Sparkle", EyeColor = rgb(255, 255, 255) } },
}

Pets.Eggs = {
	MeadowEgg = {
		Name = "Plains Cloud Egg",
		Zone = 1,
		Cost = 400,
		Color = rgb(150, 230, 110),
		Accent = rgb(255, 240, 140),
		Pets = {
			{ Id = "Puffling", Chance = 55 },
			{ Id = "Droplet", Chance = 30 },
			{ Id = "Sunny", Chance = 12 },
			{ Id = "Prism", Chance = 2.7 },
			{ Id = "BreezeKing", Chance = 0.3 },
		},
		-- 1 in Odds per hatch each (Formulas.HatchChances; luck helps them only a little)
		Secrets = {
			{ Id = "EyeOfTheStorm", Odds = 250000 },
		},
	},
	ThunderEgg = {
		Name = "Thunder Cloud Egg",
		Zone = 2,
		Cost = 22000,
		Color = rgb(112, 112, 165),
		Accent = rgb(255, 225, 70),
		Pets = {
			{ Id = "Static", Chance = 55 },
			{ Id = "Zappy", Chance = 30 },
			{ Id = "VoltBat", Chance = 12 },
			{ Id = "ThunderPup", Chance = 2.7 },
			{ Id = "StormLord", Chance = 0.3 },
		},
		-- 1 in Odds per hatch each (Formulas.HatchChances; luck helps them only a little)
		Secrets = {
			{ Id = "ThunderKirin", Odds = 400000 },
		},
	},
	DuneEgg = {
		Name = "Dune Cloud Egg",
		Zone = 3,
		Cost = 1.6e6,
		Color = rgb(232, 196, 130),
		Accent = rgb(80, 200, 190),
		Pets = {
			{ Id = "Sandy", Chance = 55 },
			{ Id = "CactusCub", Chance = 30 },
			{ Id = "DustBunny", Chance = 12 },
			{ Id = "Scarab", Chance = 2.7 },
			{ Id = "MirageDjinn", Chance = 0.3 },
		},
		-- 1 in Odds per hatch each (Formulas.HatchChances; luck helps them only a little)
		Secrets = {
			{ Id = "SandstormSphinx", Odds = 500000 },
		},
	},
	FrostEgg = {
		Name = "Frost Cloud Egg",
		Zone = 4,
		Cost = 1.2e8,
		Color = rgb(205, 236, 255),
		Accent = rgb(110, 180, 255),
		Pets = {
			{ Id = "Snowball", Chance = 55 },
			{ Id = "Icicle", Chance = 30 },
			{ Id = "Frostbite", Chance = 12 },
			{ Id = "AuroraFox", Chance = 2.7 },
			{ Id = "YetiKing", Chance = 0.3 },
		},
		-- 1 in Odds per hatch each (Formulas.HatchChances; luck helps them only a little)
		Secrets = {
			{ Id = "BlizzardMonarch", Odds = 800000 },
		},
	},
	MagmaEgg = {
		Name = "Magma Cloud Egg",
		Zone = 5,
		Cost = 5e9,
		Color = rgb(92, 42, 36),
		Accent = rgb(255, 122, 40),
		Pets = {
			{ Id = "Ember", Chance = 55 },
			{ Id = "Coal", Chance = 30 },
			{ Id = "LavaPup", Chance = 12 },
			{ Id = "PhoenixChick", Chance = 2.7 },
			{ Id = "InfernoDrake", Chance = 0.3 },
		},
		-- 1 in Odds per hatch each (Formulas.HatchChances; luck helps them only a little)
		Secrets = {
			{ Id = "TempestPhoenix", Odds = 1000000 },
			{ Id = "PyroclasmDragon", Odds = 2000000 },
		},
	},
	CosmicEgg = {
		Name = "Cosmic Cloud Egg",
		Zone = 6,
		Cost = 3e11,
		Color = rgb(62, 36, 122),
		Accent = rgb(255, 130, 240),
		Pets = {
			{ Id = "Stardust", Chance = 55 },
			{ Id = "Comet", Chance = 30 },
			{ Id = "Nebula", Chance = 12 },
			{ Id = "Moonbeam", Chance = 2.7 },
			{ Id = "GalaxyGuardian", Chance = 0.3 },
		},
		-- 1 in Odds per hatch each (Formulas.HatchChances; luck helps them only a little)
		Secrets = {
			{ Id = "VoidLeviathan", Odds = 2000000 },
			{ Id = "NovaSeraph", Odds = 4000000 },
			{ Id = "Hypercane", Odds = 5000000 },
		},
	},
}

Pets.EggOrder = { "MeadowEgg", "ThunderEgg", "DuneEgg", "FrostEgg", "MagmaEgg", "CosmicEgg" }

-- Fill in derived fields
for id, pet in Pets.Pets do
	pet.Id = id
	if not pet.Bonus then
		pet.Bonus = RARITY_BASE[pet.Rarity] * ZONE_FACTOR[pet.Zone]
	end
	pet.Look.Features = pet.Look.Features or {}
end

for id, egg in Pets.Eggs do
	egg.Id = id
	for _, entry in egg.Pets do
		Pets.Pets[entry.Id].Egg = id
	end
	egg.Secrets = egg.Secrets or {}
	for _, entry in egg.Secrets do
		Pets.Pets[entry.Id].Egg = id
		Pets.Pets[entry.Id].Odds = entry.Odds
	end
end

-- Stable order for the pet index (by egg, then rarity, then exclusives)
Pets.IndexOrder = {}
for _, eggId in Pets.EggOrder do
	for _, entry in Pets.Eggs[eggId].Pets do
		table.insert(Pets.IndexOrder, entry.Id)
	end
	for _, entry in Pets.Eggs[eggId].Secrets do
		table.insert(Pets.IndexOrder, entry.Id)
	end
end
for _, id in { "Sunbeam", "TempestTitan", "VoltWyrm", "FrostColossus", "CycloneDrake", "MaelstromSpirit", "RainbowRoc", "AuroraGryphon" } do
	table.insert(Pets.IndexOrder, id)
end

function Pets.RarityOf(petId: string)
	local pet = Pets.Pets[petId]
	return pet and Pets.Rarities[pet.Rarity]
end

-- Secret pets (very rare egg pets shown as "???" until discovered)
function Pets.IsSecret(petId: string): boolean
	local pet = Pets.Pets[petId]
	return pet ~= nil and pet.Rarity == "Secret"
end

-- Pet tiers: 5 of the same pet craft a Golden one, 5 Golden craft a Rainbow one
-- (requirements and multipliers live in GameConfig.Pets). Saved pets store their tier as
-- Golden = true or Rainbow = true (never both). Code is used in the "EquippedPets" attribute.
Pets.Tiers = {
	Normal = { Order = 1, Name = "Normal", Prefix = "", Icon = "", Code = "0", Color = rgb(255, 255, 255) },
	Golden = { Order = 2, Name = "Golden", Prefix = "Golden ", Icon = "⭐", Code = "1", Color = rgb(255, 214, 64) },
	Rainbow = { Order = 3, Name = "Rainbow", Prefix = "Rainbow ", Icon = "🌈", Code = "2", Color = rgb(255, 150, 230) },
}

Pets.TierCodes = {} -- [code] = tier name
for name, tier in Pets.Tiers do
	Pets.TierCodes[tier.Code] = name
end

-- Tier name of a saved pet ({ Golden, Rainbow }), a tier name, or a legacy "golden" boolean
function Pets.TierOf(value): string
	if type(value) == "table" then
		if value.Rainbow then
			return "Rainbow"
		end
		return if value.Golden then "Golden" else "Normal"
	elseif value == true then
		return "Golden"
	elseif type(value) == "string" and Pets.Tiers[value] then
		return value
	end
	return "Normal"
end

-- "Rainbow Prism", "Golden Puffling", "Puffling"
function Pets.DisplayName(petId: string, tier): string
	local pet = Pets.Pets[petId]
	return Pets.Tiers[Pets.TierOf(tier)].Prefix .. (if pet then pet.Name else petId)
end

return Pets
