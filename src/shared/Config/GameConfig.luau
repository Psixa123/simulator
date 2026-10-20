--!nonstrict
-- Core tuning values for Storm Catcher Simulator.
-- Every number that shapes progression lives here (or in the other Config modules)
-- so the game can be rebalanced without touching gameplay code.

local GameConfig = {}

GameConfig.GameName = "Storm Catcher Simulator"
GameConfig.Version = "1.0.0"

-- Group / social links shown in the UI (leave empty to hide)
GameConfig.GroupName = ""

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
GameConfig.DataStoreName = "StormCatcherData_v1"
GameConfig.AutosaveInterval = 90 -- seconds
GameConfig.SessionLockTimeout = 300 -- seconds before a lock from a crashed server is ignored
GameConfig.MaxStoredReceipts = 40

---------------------------------------------------------------------------
-- Catching
---------------------------------------------------------------------------
GameConfig.CatchTickRate = 0.2 -- seconds between vacuum ticks (5 per second)
GameConfig.CatchRangeLeeway = 8 -- extra studs tolerated server-side (latency)
GameConfig.CompletionBonus = 0.25 -- bonus energy for helping finish a weather cell
GameConfig.CellRespawnTime = NumberRange.new(4, 8)
GameConfig.CellSpacing = 22 -- minimum distance between weather cells

---------------------------------------------------------------------------
-- Upgrades
-- Value(level) -> stat at that level, Cost(level) -> price to go from level to level + 1
---------------------------------------------------------------------------
GameConfig.Upgrades = {
	Power = {
		Order = 1,
		Name = "Vacuum Power",
		Icon = "💨",
		Description = "Drain weather faster and catch stronger storms.",
		MaxLevel = 60,
		ResetsOnRebirth = true,
		Value = function(level: number): number
			return math.floor(10 * 1.16 ^ (level - 1))
		end,
		Cost = function(level: number): number
			return math.floor(25 * 1.6 ^ (level - 1))
		end,
	},
	Tank = {
		Order = 2,
		Name = "Storm Tank",
		Icon = "🛢️",
		Description = "Carry more energy before you need to sell.",
		MaxLevel = 60,
		ResetsOnRebirth = true,
		Value = function(level: number): number
			return math.floor(250 * 1.21 ^ (level - 1))
		end,
		Cost = function(level: number): number
			return math.floor(35 * 1.6 ^ (level - 1))
		end,
	},
	Range = {
		Order = 3,
		Name = "Vacuum Range",
		Icon = "📡",
		Description = "Reach weather from further away.",
		MaxLevel = 10,
		Suffix = " studs",
		Value = function(level: number): number
			return 22 + (level - 1) * 3
		end,
		Cost = function(level: number): number
			return math.floor(500 * 4 ^ (level - 1))
		end,
	},
	Speed = {
		Order = 4,
		Name = "Storm Boots",
		Icon = "👟",
		Description = "Run faster between storms.",
		MaxLevel = 10,
		Suffix = " speed",
		Value = function(level: number): number
			return 16 + (level - 1) * 2
		end,
		Cost = function(level: number): number
			return math.floor(400 * 4 ^ (level - 1))
		end,
	},
}

GameConfig.UpgradeOrder = { "Power", "Tank", "Range", "Speed" }

---------------------------------------------------------------------------
-- Rebirth (players know it as "Climate Shift")
---------------------------------------------------------------------------
GameConfig.Rebirth = {
	BaseCost = 1e7,
	CostGrowth = 5,
	VoltsBonus = 0.5, -- +50% Volts for every rebirth
	Resets = { "Volts", "Power", "Tank" },
	Keeps = { "Pets", "Zones", "Range", "Speed", "Gamepasses" },

	-- Gear looks for the Storm Tank and Storm Vacuum. The best look your Climate Shifts unlock is
	-- worn automatically (see Shared/ClimateShift and CharacterGear.DressPlayer).
	-- Tank / Vacuum = shell colour, Glow = neon rings, tank fill and nozzle light,
	-- Trim (optional) = the dark metal parts, Trail (optional, Color3 or ColorSequence) = a streak
	-- behind the tank while you run.
	DefaultCosmetic = {
		Name = "Storm Standard",
		Icon = "⚙️",
		Tank = Color3.fromRGB(160, 170, 192),
		Vacuum = Color3.fromRGB(160, 170, 192),
		Glow = Color3.fromRGB(70, 200, 255),
	},
	-- Ordered by Shifts (number of Climate Shifts needed)
	Cosmetics = {
		{
			Shifts = 1,
			Name = "Spring Shower",
			Icon = "🌱",
			Tank = Color3.fromRGB(120, 214, 160),
			Vacuum = Color3.fromRGB(140, 226, 176),
			Glow = Color3.fromRGB(110, 255, 170),
		},
		{
			Shifts = 2,
			Name = "Thunderstruck",
			Icon = "⚡",
			Tank = Color3.fromRGB(96, 84, 176),
			Vacuum = Color3.fromRGB(112, 98, 196),
			Glow = Color3.fromRGB(255, 226, 72),
		},
		{
			Shifts = 3,
			Name = "Desert Mirage",
			Icon = "🏜️",
			Tank = Color3.fromRGB(226, 186, 116),
			Vacuum = Color3.fromRGB(238, 200, 132),
			Trim = Color3.fromRGB(120, 84, 52),
			Glow = Color3.fromRGB(64, 228, 214),
		},
		{
			Shifts = 5,
			Name = "Polar Vortex",
			Icon = "❄️",
			Tank = Color3.fromRGB(214, 236, 255),
			Vacuum = Color3.fromRGB(226, 242, 255),
			Trim = Color3.fromRGB(70, 104, 150),
			Glow = Color3.fromRGB(120, 196, 255),
			Trail = Color3.fromRGB(190, 230, 255),
		},
		{
			Shifts = 8,
			Name = "Molten Core",
			Icon = "🌋",
			Tank = Color3.fromRGB(72, 56, 56),
			Vacuum = Color3.fromRGB(86, 64, 60),
			Trim = Color3.fromRGB(36, 28, 28),
			Glow = Color3.fromRGB(255, 112, 40),
			Trail = Color3.fromRGB(255, 150, 60),
		},
		{
			Shifts = 12,
			Name = "Aurora Borealis",
			Icon = "🌌",
			Tank = Color3.fromRGB(70, 52, 140),
			Vacuum = Color3.fromRGB(84, 62, 160),
			Trim = Color3.fromRGB(36, 30, 80),
			Glow = Color3.fromRGB(110, 255, 200),
			Trail = ColorSequence.new(Color3.fromRGB(110, 255, 200), Color3.fromRGB(255, 120, 240)),
		},
		{
			Shifts = 20,
			Name = "Rainbow Tempest",
			Icon = "🌈",
			Tank = Color3.fromRGB(255, 206, 72),
			Vacuum = Color3.fromRGB(255, 218, 96),
			Trim = Color3.fromRGB(130, 86, 24),
			Glow = Color3.fromRGB(255, 250, 220),
			Trail = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 110)),
				ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 200, 70)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(110, 240, 130)),
				ColorSequenceKeypoint.new(0.75, Color3.fromRGB(90, 180, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 120, 255)),
			}),
		},
	},
}

---------------------------------------------------------------------------
-- Pets
---------------------------------------------------------------------------
GameConfig.Pets = {
	MaxStorage = 60,
	BaseEquipSlots = 3,
	PassEquipSlots = 3,
	GoldenRequirement = 5,
	GoldenMultiplier = 2.5,
	RainbowRequirement = 5, -- Golden copies of a pet needed to craft a Rainbow one
	RainbowMultiplier = 6,
	HatchDistance = 26,
	AutoHatchDelay = 0.4,
	-- Equipped pets catch weather near you on their own
	AutoCatch = {
		PowerPerPet = 0.08, -- fraction of your vacuum Power each equipped pet catches with
		TierFactor = { Normal = 1, Golden = 1.6, Rainbow = 2.4 },
		ExtraRange = 10, -- studs pets reach beyond your vacuum range
		SearchInterval = 1, -- seconds between searches for a new cell when idle
	},
}

-- Roblox asset id of the uploaded pet mesh pack (README: "Better pet models"). When the place has no
-- ReplicatedStorage.PetMeshes, the server inserts this model there at startup; 0 = built-in pet models.
-- tools/roblox/upload_pets.py fills it in.
GameConfig.PetMeshAssetId = 111910693508505

-- Roblox asset id of the uploaded world prop pack (assets/models/StormWorldProps.glb, docs/STYLE_GUIDE.md
-- "Prop kit"). When the place has no ServerStorage/ReplicatedStorage.WorldProps, the server's WorldProps
-- module inserts this model into ServerStorage.WorldProps; 0 = the map keeps its part-built props.
-- tools/roblox/upload_model.py --file assets/models/StormWorldProps.glb --config-key WorldPropsAssetId fills it in.
GameConfig.WorldPropsAssetId = 102104549753593

---------------------------------------------------------------------------
-- Gamepass effects & boosts
---------------------------------------------------------------------------
GameConfig.PassEffects = {
	VipBonus = 0.25,
	DoubleVolts = 2,
	DoubleEnergy = 2,
	MegaTank = 2,
	LuckyHatcher = 1.5,
}

GameConfig.Boosts = {
	Energy = {
		Name = "2x Energy",
		Icon = "⚡",
		Multiplier = 2,
		Color = Color3.fromRGB(80, 200, 255),
	},
	Luck = {
		Name = "2x Luck",
		Icon = "🍀",
		Multiplier = 2,
		Color = Color3.fromRGB(90, 230, 120),
	},
}

---------------------------------------------------------------------------
-- Mega Storm (server-wide event in the hub arena)
---------------------------------------------------------------------------
GameConfig.MegaStorm = {
	FirstDelay = 180, -- seconds after a server starts
	Interval = 600, -- seconds between storms
	WarningTime = 30,
	Duration = 120,
	SummonDelay = 20,
	Range = 80, -- studs from the arena center where players can vacuum the storm
	HealthSecondsPerPlayer = 30, -- storm health ~= everyone's combined power for this many seconds
	MinHealth = 2500,
	RewardMultiplier = 4,
	DefeatBonus = 1.5,
	EscapeMultiplier = 0.6,
	MinContribution = 0.02, -- fraction of storm health needed to qualify for pet drops
	ExclusiveChances = { 0.25, 0.15, 0.10 }, -- 1st, 2nd and 3rd place
	ParticipantChance = 0.025,
	Types = {
		{
			Key = "Tempest",
			Name = "Tempest Twister",
			Color = Color3.fromRGB(150, 205, 255),
			Accent = Color3.fromRGB(235, 248, 255),
			Pet = "TempestTitan",
		},
		{
			Key = "Thunder",
			Name = "Thunder Titan",
			Color = Color3.fromRGB(95, 85, 165),
			Accent = Color3.fromRGB(255, 228, 80),
			Pet = "VoltWyrm",
		},
		{
			Key = "Blizzard",
			Name = "Blizzard Behemoth",
			Color = Color3.fromRGB(195, 232, 255),
			Accent = Color3.fromRGB(110, 190, 255),
			Pet = "FrostColossus",
		},
		{
			Key = "Inferno",
			Name = "Inferno Cyclone",
			Color = Color3.fromRGB(255, 115, 45),
			Accent = Color3.fromRGB(255, 215, 90),
			Pet = "CycloneDrake",
		},
		{
			Key = "Cosmic",
			Name = "Cosmic Maelstrom",
			Color = Color3.fromRGB(140, 85, 255),
			Accent = Color3.fromRGB(255, 145, 240),
			Pet = "MaelstromSpirit",
		},
	},
	-- Rare scheduled storm: strikes in every server at the same real-world time
	-- (every `Interval` seconds on the hour, UTC). See Shared/StormSchedule.
	Rainbow = {
		Key = "Rainbow",
		Name = "Rainbow Hurricane",
		Icon = "🌈",
		Color = Color3.fromRGB(255, 120, 200),
		Accent = Color3.fromRGB(255, 240, 120),
		Pet = "RainbowRoc",
		Interval = 7200, -- every 2 hours on the hour (UTC)
		AnnounceTime = 300, -- server-wide heads-up this many seconds before it arrives
		Duration = 180,
		HealthMultiplier = 3,
		RewardMultiplier = 3,
		Clearance = 30, -- seconds kept free before its warning; regular storms that don't fit wait until after it
		LateGrace = 300, -- a server that was busy at the scheduled time may still start it this many seconds late
	},
}

---------------------------------------------------------------------------
-- Admins (the owner-only admin panel: AdminService on the server, UI/Panels/Admin on the client)
-- The place owner is always an admin; for a group-owned place, members of the owning group with at
-- least MinGroupRank are. UserIds adds more admins. Everyone is an admin in Roblox Studio.
-- The server checks this on every admin command; the client only uses it to show the panel.
---------------------------------------------------------------------------
GameConfig.Admins = {
	UserIds = { 233074756 },
	MinGroupRank = 255, -- 255 = the group owner
}

---------------------------------------------------------------------------
-- Defaults
---------------------------------------------------------------------------
GameConfig.DefaultSettings = {
	Music = true,
	Sfx = true,
	OtherPets = true,
	LowGraphics = false,
	AutoCatch = true,
}

GameConfig.SettingsInfo = {
	{ Key = "Music", Name = "Music", Icon = "🎵", Description = "Background music" },
	{ Key = "Sfx", Name = "Sound Effects", Icon = "🔊", Description = "Vacuum, rewards and interface sounds" },
	{ Key = "OtherPets", Name = "Other Players' Pets", Icon = "🐾", Description = "Show pets that follow other players" },
	{ Key = "LowGraphics", Name = "Performance Mode", Icon = "⚙️", Description = "Fewer particles and effects" },
	{ Key = "AutoCatch", Name = "Auto Catch", Icon = "🤖", Description = "Requires the Auto Catch gamepass" },
}

return GameConfig
