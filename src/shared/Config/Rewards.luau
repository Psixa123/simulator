--!nonstrict
-- Daily login rewards, session gifts and promo codes.
-- Reward kinds:
--   Volts  -> Amount full tanks of energy from your best zone (scales with progress)
--   Boost  -> Boost ("Energy" | "Luck") for Duration seconds
--   Pet    -> a specific pet (Fallback reward if your storage is full or you already own it)
--   FreeHatch -> one free hatch of the best egg you have unlocked

local Rewards = {}

Rewards.DailyCooldown = 20 * 3600 -- you can claim again after 20 hours
Rewards.DailyStreakWindow = 48 * 3600 -- miss this window and the streak restarts

Rewards.Daily = {
	{ Kind = "Volts", Amount = 3, Icon = "⚡" },
	{ Kind = "Boost", Boost = "Energy", Duration = 900, Icon = "⚡" },
	{ Kind = "Volts", Amount = 6, Icon = "💰" },
	{ Kind = "Boost", Boost = "Luck", Duration = 900, Icon = "🍀" },
	{ Kind = "Volts", Amount = 12, Icon = "📦" },
	{ Kind = "FreeHatch", Icon = "🥚" },
	{ Kind = "Pet", Pet = "Sunbeam", Icon = "🌞", Fallback = { Kind = "Volts", Amount = 30, Icon = "🏦" } },
}

-- Session gifts (time played in the current server, in seconds)
Rewards.Gifts = {
	{ Time = 120, Kind = "Volts", Amount = 1, Icon = "⚡" },
	{ Time = 300, Kind = "Boost", Boost = "Energy", Duration = 300, Icon = "⚡" },
	{ Time = 600, Kind = "Volts", Amount = 3, Icon = "💰" },
	{ Time = 900, Kind = "Boost", Boost = "Luck", Duration = 600, Icon = "🍀" },
	{ Time = 1500, Kind = "Volts", Amount = 6, Icon = "📦" },
	{ Time = 2400, Kind = "FreeHatch", Icon = "🥚" },
	{ Time = 3600, Kind = "Volts", Amount = 15, Icon = "🏦" },
	{ Time = 5400, Kind = "Boost", Boost = "Energy", Duration = 1800, Icon = "🌩️" },
}

-- Promo codes (case-insensitive). Add new ones for updates and social media posts!
Rewards.Codes = {
	RELEASE = { Kind = "Volts", Amount = 5 },
	STORMY = { Kind = "Boost", Boost = "Energy", Duration = 900 },
	LUCKY = { Kind = "Boost", Boost = "Luck", Duration = 900 },
	THUNDER = { Kind = "Volts", Amount = 10 },
}

return Rewards
