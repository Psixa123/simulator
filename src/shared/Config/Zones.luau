--!nonstrict
-- The six biomes players progress through, plus the hub's look.
-- Cost = Volts to unlock, MinPower = vacuum power needed to enter and catch weather,
-- Value = Volts earned per unit of energy caught in this zone.
-- Hazard = what makes the biome dangerous (rules in Shared/Hazards, run by HazardService on the
-- server and HazardController on the client). Hazards never apply in the hub or the arena.

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- Lighting presets follow docs/STYLE_GUIDE.md ("Lighting"): bright midday, high OutdoorAmbient, soft
-- shadows (MapService), saturation +0.2-0.3, light bloom and a thin tinted atmosphere. Darker biomes are
-- tinted, never gloomy.
local MEADOW_LIGHTING = {
	ClockTime = 13.5,
	Brightness = 3,
	ExposureCompensation = 0,
	Ambient = rgb(140, 142, 168),
	OutdoorAmbient = rgb(188, 190, 210),
	Atmosphere = { Density = 0.24, Offset = 0.25, Color = rgb(205, 228, 255), Decay = rgb(150, 182, 235), Glare = 0.1, Haze = 0.7 },
	ColorCorrection = { Brightness = 0.02, Contrast = 0.05, Saturation = 0.25, TintColor = rgb(255, 253, 248) },
	Clouds = { Cover = 0.45, Density = 0.5, Color = rgb(255, 255, 255) },
	Bloom = { Intensity = 0.35, Size = 24, Threshold = 1.8 },
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
			ClockTime = 14.5,
			Brightness = 2.5,
			ExposureCompensation = 0,
			Ambient = rgb(128, 120, 178),
			OutdoorAmbient = rgb(172, 164, 222),
			Atmosphere = { Density = 0.3, Offset = 0.2, Color = rgb(186, 192, 250), Decay = rgb(120, 112, 210), Glare = 0, Haze = 1.2 },
			ColorCorrection = { Brightness = 0.01, Contrast = 0.08, Saturation = 0.22, TintColor = rgb(244, 242, 255) },
			Clouds = { Cover = 0.75, Density = 0.7, Color = rgb(196, 190, 235) },
			Bloom = { Intensity = 0.5, Size = 28, Threshold = 1.5 },
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
			ClockTime = 13.8,
			Brightness = 3.2,
			ExposureCompensation = 0,
			Ambient = rgb(160, 140, 120),
			OutdoorAmbient = rgb(210, 190, 160),
			Atmosphere = { Density = 0.27, Offset = 0.2, Color = rgb(255, 228, 185), Decay = rgb(240, 180, 120), Glare = 0.3, Haze = 1.1 },
			ColorCorrection = { Brightness = 0.02, Contrast = 0.05, Saturation = 0.24, TintColor = rgb(255, 247, 232) },
			Clouds = { Cover = 0.3, Density = 0.4, Color = rgb(255, 246, 232) },
			Bloom = { Intensity = 0.35, Size = 24, Threshold = 1.8 },
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
			ClockTime = 12.5,
			Brightness = 2.45,
			ExposureCompensation = 0,
			Ambient = rgb(134, 150, 186),
			OutdoorAmbient = rgb(172, 192, 228),
			Atmosphere = { Density = 0.24, Offset = 0.22, Color = rgb(205, 228, 255), Decay = rgb(140, 182, 240), Glare = 0.1, Haze = 0.6 },
			ColorCorrection = { Brightness = 0, Contrast = 0.12, Saturation = 0.26, TintColor = rgb(240, 248, 255) },
			Clouds = { Cover = 0.6, Density = 0.6, Color = rgb(244, 250, 255) },
			Bloom = { Intensity = 0.35, Size = 24, Threshold = 1.8 },
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
			ClockTime = 15.5,
			Brightness = 2.6,
			ExposureCompensation = 0,
			Ambient = rgb(165, 118, 108),
			OutdoorAmbient = rgb(214, 160, 140),
			Atmosphere = { Density = 0.32, Offset = 0.15, Color = rgb(255, 175, 140), Decay = rgb(220, 110, 80), Glare = 0.2, Haze = 1.4 },
			ColorCorrection = { Brightness = 0, Contrast = 0.08, Saturation = 0.26, TintColor = rgb(255, 236, 226) },
			Clouds = { Cover = 0.6, Density = 0.7, Color = rgb(225, 180, 170) },
			Bloom = { Intensity = 0.55, Size = 28, Threshold = 1.4 },
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
			ClockTime = 14,
			Brightness = 2.8,
			ExposureCompensation = 0,
			Ambient = rgb(160, 142, 210),
			OutdoorAmbient = rgb(204, 186, 242),
			Atmosphere = { Density = 0.26, Offset = 0.3, Color = rgb(212, 190, 255), Decay = rgb(160, 128, 240), Glare = 0.2, Haze = 0.9 },
			ColorCorrection = { Brightness = 0.02, Contrast = 0.06, Saturation = 0.3, TintColor = rgb(248, 240, 255) },
			Clouds = { Cover = 0.5, Density = 0.55, Color = rgb(236, 222, 255) },
			Bloom = { Intensity = 0.5, Size = 30, Threshold = 1.5 },
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
