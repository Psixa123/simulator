--!nonstrict
-- The six biomes players progress through, plus the hub's look.
-- Cost = Volts to unlock, MinPower = vacuum power needed to enter and catch weather,
-- Value = Volts earned per unit of energy caught in this zone.
-- Hazard = what makes the biome dangerous (rules in Shared/Hazards, run by HazardService on the
-- server and HazardController on the client). Hazards never apply in the hub or the arena.

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local MEADOW_LIGHTING = {
	ClockTime = 14.2,
	Brightness = 2.4,
	ExposureCompensation = 0.1,
	Ambient = rgb(100, 104, 120),
	OutdoorAmbient = rgb(150, 150, 165),
	Atmosphere = { Density = 0.28, Offset = 0.2, Color = rgb(199, 222, 255), Decay = rgb(120, 140, 170), Glare = 0.2, Haze = 1.1 },
	ColorCorrection = { Brightness = 0.02, Contrast = 0.08, Saturation = 0.15, TintColor = rgb(255, 253, 245) },
	Clouds = { Cover = 0.5, Density = 0.55, Color = rgb(255, 255, 255) },
	Bloom = { Intensity = 0.45, Size = 24, Threshold = 1.6 },
}

-- Storm Boots (Upgrades.Speed) level that keeps Frostpeak's cold away. Boots Lv 8 -> 9 costs
-- 6.55M Volts (8.7M in total from Lv 1) while Frostpeak itself costs 60M, saved up in the Dune Sea
-- at 40 Volts per energy - so Lv 9 is affordable on the way there (or after a few Frostpeak tanks
-- at 280 Volts per energy) and Boots survive rebirths. Lv 10 would need another 26M: too grindy.
local FROST_BOOTS_LEVEL = 9

local Zones = {
	{
		Id = 1,
		Key = "Meadows",
		Name = "Sunny Plains",
		Icon = "🌤️",
		Description = "Gentle breezes and spring showers. Every storm chaser starts here!",
		Cost = 0,
		MinPower = 0,
		Value = 1,
		BaseHealth = 120,
		CellCount = 16,
		Color = rgb(120, 220, 90),
		Accent = rgb(255, 220, 90),
		Weather = { "Breeze", "RainCloud", "RainbowMist" },
		Egg = "MeadowEgg",
		Lighting = MEADOW_LIGHTING,
		Hazard = nil, -- the starter biome is safe
	},
	{
		Id = 2,
		Key = "Thunder",
		Name = "Thunder Valley",
		Icon = "⛈️",
		Description = "A dark valley where lightning never stops striking.",
		Cost = 5000,
		MinPower = 28,
		Value = 6,
		BaseHealth = 900,
		CellCount = 16,
		Color = rgb(140, 120, 255),
		Accent = rgb(255, 225, 70),
		Weather = { "StormCloud", "LightningOrb", "Thunderhead" },
		Egg = "ThunderEgg",
		Lighting = {
			ClockTime = 16.8,
			Brightness = 1.1,
			ExposureCompensation = 0,
			Ambient = rgb(72, 74, 98),
			OutdoorAmbient = rgb(98, 100, 128),
			Atmosphere = { Density = 0.42, Offset = 0.1, Color = rgb(125, 130, 160), Decay = rgb(60, 62, 85), Glare = 0, Haze = 2.2 },
			ColorCorrection = { Brightness = -0.02, Contrast = 0.15, Saturation = -0.2, TintColor = rgb(220, 228, 255) },
			Clouds = { Cover = 0.88, Density = 0.85, Color = rgb(110, 112, 130) },
			Bloom = { Intensity = 0.8, Size = 30, Threshold = 1.3 },
			Ambience = "Rain",
			Lightning = true,
		},
		Hazard = {
			Kind = "Lightning",
			Name = "Lightning Strikes",
			Icon = "⚡",
			Description = "Lightning stuns you! Dodge the glowing circles.",
			Color = rgb(255, 225, 70),
			Interval = NumberRange.new(5, 9), -- seconds between strikes aimed at each player
			Spread = 7, -- strikes land up to this many studs from their target
			Radius = 9, -- studs: everyone inside the circle is stunned
			WarnTime = 1.3, -- seconds the warning circle shows before the bolt hits
			StunTime = 1.6,
			Grace = 5, -- seconds of safety after entering the zone or respawning
		},
	},
	{
		Id = 3,
		Key = "Dunes",
		Name = "Dune Sea",
		Icon = "🏜️",
		Description = "Scorching sands, whirling dust devils and shimmering mirages.",
		Cost = 8e5,
		MinPower = 120,
		Value = 40,
		BaseHealth = 4500,
		CellCount = 16,
		Color = rgb(240, 190, 100),
		Accent = rgb(90, 220, 210),
		Weather = { "DustDevil", "Sandstorm", "MirageWisp" },
		Egg = "DuneEgg",
		Lighting = {
			ClockTime = 15.2,
			Brightness = 3,
			ExposureCompensation = 0,
			Ambient = rgb(120, 100, 80),
			OutdoorAmbient = rgb(170, 145, 115),
			Atmosphere = { Density = 0.36, Offset = 0.15, Color = rgb(255, 215, 160), Decay = rgb(190, 130, 70), Glare = 0.6, Haze = 2 },
			ColorCorrection = { Brightness = 0.03, Contrast = 0.1, Saturation = 0.1, TintColor = rgb(255, 240, 220) },
			Clouds = { Cover = 0.3, Density = 0.4, Color = rgb(255, 240, 220) },
			Bloom = { Intensity = 0.5, Size = 24, Threshold = 1.5 },
			Ambience = "Sand",
		},
		Hazard = {
			Kind = "Sandstorm",
			Name = "Sandstorms",
			Icon = "🌪️",
			Description = "Sandstorms sweep in and bury the view in dust.",
			Color = rgb(240, 190, 100),
			Calm = NumberRange.new(30, 45), -- seconds between sandstorms (server-wide)
			Duration = 15,
			-- Replace the zone's lighting while a sandstorm rages
			Atmosphere = { Density = 0.64, Offset = 0.02, Color = rgb(222, 176, 108), Decay = rgb(168, 110, 56), Glare = 0, Haze = 3.6 },
			ColorCorrection = { Brightness = -0.03, Contrast = 0.04, Saturation = -0.18, TintColor = rgb(255, 226, 186) },
		},
	},
	{
		Id = 4,
		Key = "Frost",
		Name = "Frostpeak",
		Icon = "🏔️",
		Description = "Frozen peaks where blizzards roar and auroras dance.",
		Cost = 6e7,
		MinPower = 520,
		Value = 280,
		BaseHealth = 20000,
		CellCount = 16,
		Color = rgb(150, 210, 255),
		Accent = rgb(255, 255, 255),
		Weather = { "SnowCloud", "Blizzard", "AuroraSpirit" },
		Egg = "FrostEgg",
		Lighting = {
			ClockTime = 11,
			Brightness = 2.6,
			ExposureCompensation = 0,
			Ambient = rgb(120, 130, 155),
			OutdoorAmbient = rgb(165, 180, 205),
			Atmosphere = { Density = 0.45, Offset = 0.2, Color = rgb(215, 235, 255), Decay = rgb(150, 180, 220), Glare = 0.3, Haze = 1.6 },
			ColorCorrection = { Brightness = 0.04, Contrast = 0.06, Saturation = -0.05, TintColor = rgb(232, 245, 255) },
			Clouds = { Cover = 0.7, Density = 0.7, Color = rgb(240, 248, 255) },
			Bloom = { Intensity = 0.5, Size = 24, Threshold = 1.5 },
			Ambience = "Snow",
		},
		Hazard = {
			Kind = "Cold",
			Name = "Freezing Cold",
			Icon = "🥶",
			Description = string.format("The cold slows you! Storm Boots Lv %d keep you warm.", FROST_BOOTS_LEVEL),
			Color = rgb(150, 210, 255),
			SpeedMultiplier = 0.55,
			BootsLevel = FROST_BOOTS_LEVEL,
		},
	},
	{
		Id = 5,
		Key = "Volcano",
		Name = "Ashfall Volcano",
		Icon = "🌋",
		Description = "Fire tornadoes rage across rivers of lava.",
		Cost = 4e9,
		MinPower = 2400,
		Value = 2000,
		BaseHealth = 90000,
		CellCount = 16,
		Color = rgb(255, 110, 50),
		Accent = rgb(255, 210, 80),
		Weather = { "AshCloud", "FireTornado", "MagmaCore" },
		Egg = "MagmaEgg",
		Lighting = {
			ClockTime = 18.6,
			Brightness = 1.6,
			ExposureCompensation = 0,
			Ambient = rgb(110, 62, 52),
			OutdoorAmbient = rgb(140, 82, 62),
			Atmosphere = { Density = 0.5, Offset = 0.05, Color = rgb(255, 125, 70), Decay = rgb(110, 30, 15), Glare = 0.4, Haze = 2.6 },
			ColorCorrection = { Brightness = 0, Contrast = 0.15, Saturation = 0.1, TintColor = rgb(255, 220, 205) },
			Clouds = { Cover = 0.8, Density = 0.9, Color = rgb(80, 60, 60) },
			Bloom = { Intensity = 0.9, Size = 30, Threshold = 1.2 },
			Ambience = "Embers",
		},
		Hazard = {
			Kind = "Heat",
			Name = "Scorching Heat",
			Icon = "🔥",
			Description = "The heat hurts! Cool off near Weather Labs and eggs.",
			Color = rgb(255, 120, 50),
			Damage = 4, -- HP per second (characters regenerate about 1 HP per second)
			SafeRadius = 20, -- studs around the sell pad, egg station and zone spawn
			CoolHeal = 8, -- HP per second while cooling off
		},
	},
	{
		Id = 6,
		Key = "Sky",
		Name = "Upper Atmosphere",
		Icon = "🌌",
		Description = "Above the clouds: solar flares, auroras and barely any gravity.",
		Cost = 3e11,
		MinPower = 11000,
		Value = 15000,
		BaseHealth = 420000,
		CellCount = 16,
		Color = rgb(170, 110, 255),
		Accent = rgb(255, 140, 240),
		Weather = { "SolarFlare", "CosmicVortex", "Starstorm" },
		Egg = "CosmicEgg",
		Lighting = {
			ClockTime = 0.2,
			Brightness = 1.6,
			ExposureCompensation = 0.2,
			Ambient = rgb(112, 96, 165),
			OutdoorAmbient = rgb(132, 112, 195),
			Atmosphere = { Density = 0.25, Offset = 0.3, Color = rgb(160, 120, 255), Decay = rgb(70, 40, 140), Glare = 0.2, Haze = 0.8 },
			ColorCorrection = { Brightness = 0.04, Contrast = 0.1, Saturation = 0.25, TintColor = rgb(235, 225, 255) },
			Clouds = { Cover = 0.45, Density = 0.5, Color = rgb(190, 150, 255) },
			Bloom = { Intensity = 1, Size = 32, Threshold = 1.1 },
			Ambience = "Stars",
		},
		Hazard = {
			Kind = "LowGravity",
			Name = "Low Gravity",
			Icon = "🪐",
			Description = "Gravity is weak up here. Enjoy the floaty jumps!",
			Color = rgb(190, 140, 255),
			Gravity = 70, -- studs/s² (normal is 196.2)
		},
	},
}

-- The hub uses the meadow look
Zones.Hub = {
	Id = 0,
	Key = "Hub",
	Name = "Storm Station",
	Icon = "🏠",
	Description = "Home base: upgrades, Climate Shifts, leaderboards and the Mega Storm arena.",
	Color = rgb(80, 200, 255),
	Accent = rgb(255, 220, 90),
	Lighting = MEADOW_LIGHTING,
}

function Zones.Get(zoneId: number)
	if zoneId == 0 then
		return Zones.Hub
	end
	return Zones[zoneId]
end

return Zones
