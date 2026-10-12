--!nonstrict
-- Weather cells that spawn in each zone. Players vacuum them up for energy.
-- Health = zone.BaseHealth * rarity.HealthMult, energy value = zone.Value * rarity.ValueMult.

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local Weather = {}

Weather.Rarities = {
	Common = {
		Weight = 70,
		HealthMult = 1,
		ValueMult = 1,
		Scale = 1,
		Color = rgb(225, 232, 245),
	},
	Uncommon = {
		Weight = 25,
		HealthMult = 1.8,
		ValueMult = 1.35,
		Scale = 1.15,
		Color = rgb(110, 230, 120),
	},
	Rare = {
		Weight = 5,
		HealthMult = 4,
		ValueMult = 2.5,
		Scale = 1.35,
		Color = rgb(255, 205, 60),
		Announce = true,
	},
}

-- Style decides which model builder is used (see Shared/Models/WeatherModels)
Weather.Types = {
	-- Sunny Plains
	Breeze = { Name = "Breeze Puff", Rarity = "Common", Style = "Cloud", Color = rgb(255, 255, 255), Accent = rgb(185, 225, 255) },
	RainCloud = { Name = "Rain Cloud", Rarity = "Uncommon", Style = "RainCloud", Color = rgb(160, 170, 190), Accent = rgb(120, 185, 255) },
	RainbowMist = { Name = "Rainbow Mist", Rarity = "Rare", Style = "Rainbow", Color = rgb(255, 210, 235), Accent = rgb(255, 150, 220) },

	-- Thunder Valley
	StormCloud = { Name = "Storm Cloud", Rarity = "Common", Style = "StormCloud", Color = rgb(88, 92, 112), Accent = rgb(255, 230, 80) },
	LightningOrb = { Name = "Lightning Orb", Rarity = "Uncommon", Style = "Orb", Color = rgb(255, 232, 90), Accent = rgb(255, 250, 200) },
	Thunderhead = { Name = "Thunderhead", Rarity = "Rare", Style = "StormCloud", Color = rgb(58, 52, 90), Accent = rgb(185, 130, 255) },

	-- Dune Sea
	DustDevil = { Name = "Dust Devil", Rarity = "Common", Style = "Tornado", Color = rgb(222, 190, 130), Accent = rgb(245, 220, 165) },
	Sandstorm = { Name = "Sandstorm", Rarity = "Uncommon", Style = "DustCloud", Color = rgb(214, 172, 104), Accent = rgb(250, 222, 155) },
	MirageWisp = { Name = "Mirage Wisp", Rarity = "Rare", Style = "Orb", Color = rgb(70, 230, 220), Accent = rgb(200, 255, 250) },

	-- Frostpeak
	SnowCloud = { Name = "Snow Cloud", Rarity = "Common", Style = "SnowCloud", Color = rgb(238, 246, 255), Accent = rgb(170, 215, 255) },
	Blizzard = { Name = "Blizzard", Rarity = "Uncommon", Style = "Tornado", Color = rgb(200, 230, 255), Accent = rgb(250, 252, 255) },
	AuroraSpirit = { Name = "Aurora Spirit", Rarity = "Rare", Style = "Orb", Color = rgb(90, 255, 170), Accent = rgb(190, 120, 255) },

	-- Ashfall Volcano
	AshCloud = { Name = "Ash Cloud", Rarity = "Common", Style = "AshCloud", Color = rgb(72, 64, 62), Accent = rgb(255, 130, 40) },
	FireTornado = { Name = "Fire Tornado", Rarity = "Uncommon", Style = "Tornado", Color = rgb(255, 110, 40), Accent = rgb(255, 210, 80), Fire = true },
	MagmaCore = { Name = "Magma Core", Rarity = "Rare", Style = "Orb", Color = rgb(255, 80, 30), Accent = rgb(255, 200, 60), Fire = true },

	-- Upper Atmosphere
	SolarFlare = { Name = "Solar Flare", Rarity = "Common", Style = "Orb", Color = rgb(255, 170, 60), Accent = rgb(255, 240, 150), Fire = true },
	CosmicVortex = { Name = "Cosmic Vortex", Rarity = "Uncommon", Style = "Tornado", Color = rgb(140, 80, 255), Accent = rgb(255, 130, 240) },
	Starstorm = { Name = "Starstorm", Rarity = "Rare", Style = "Starburst", Color = rgb(255, 240, 140), Accent = rgb(150, 200, 255) },
}

-- How high above the ground each style hovers (before rarity scale)
Weather.HoverHeight = {
	Cloud = 12,
	RainCloud = 12.5,
	Rainbow = 12,
	StormCloud = 13,
	DustCloud = 11,
	SnowCloud = 12.5,
	AshCloud = 12.5,
	Orb = 7.5,
	Tornado = 6.8,
	Starburst = 9,
}

return Weather
