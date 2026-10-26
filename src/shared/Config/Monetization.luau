--!nonstrict
-- Gamepasses and developer products.
--
-- HOW TO SET UP (see README.md for screenshots-free step by step):
--   1. Publish the place, then open https://create.roblox.com/dashboard/creations
--   2. Your experience -> Monetization -> Passes -> "Create a Pass" for every entry below
--      (icons are in assets/gamepasses), then copy each pass ID into `Id`.
--   3. Monetization -> Developer Products -> create every product below and copy its ID.
--
-- While an Id is 0 the item still works inside Roblox Studio (purchases are simulated
-- so you can test everything). In a live server an item with Id 0 shows "Coming soon".

local Monetization = {}

Monetization.Gamepasses = {
	VIP = {
		Id = 0,
		Image = 127403723161922, -- assets/gamepasses/VIP.png
		Order = 1,
		Name = "VIP",
		Icon = "👑",
		Price = 399,
		Color = Color3.fromRGB(255, 196, 40),
		Description = "+25% Volts and energy, a VIP chat tag and a golden crown above your head.",
	},
	DoubleVolts = {
		Id = 0,
		Image = 116165976519745, -- assets/gamepasses/DoubleVolts.png
		Order = 2,
		Name = "2x Volts",
		Icon = "💰",
		Price = 199,
		Color = Color3.fromRGB(255, 214, 64),
		Description = "Earn double Volts every time you sell energy.",
	},
	DoubleEnergy = {
		Id = 0,
		Image = 98414846011193, -- assets/gamepasses/DoubleEnergy.png
		Order = 3,
		Name = "2x Energy",
		Icon = "⚡",
		Price = 249,
		Color = Color3.fromRGB(80, 200, 255),
		Description = "Your vacuum collects double energy from all weather.",
	},
	AutoCatch = {
		Id = 0,
		Image = 119205295981536, -- assets/gamepasses/AutoCatch.png
		Order = 4,
		Name = "Auto Catch",
		Icon = "🤖",
		Price = 299,
		Color = Color3.fromRGB(120, 230, 160),
		Description = "Your vacuum automatically catches the nearest weather. No clicking needed!",
	},
	RemoteSell = {
		Id = 0,
		Image = 103170135392724, -- assets/gamepasses/RemoteSell.png
		Order = 5,
		Name = "Remote Sell",
		Icon = "📡",
		Price = 199,
		Color = Color3.fromRGB(255, 140, 90),
		Description = "Sell from anywhere and automatically sell whenever your tank is full.",
	},
	MegaTank = {
		Id = 0,
		Image = 120754468211847, -- assets/gamepasses/MegaTank.png
		Order = 6,
		Name = "Mega Tank",
		Icon = "🛢️",
		Price = 149,
		Color = Color3.fromRGB(110, 140, 255),
		Description = "Double your Storm Tank capacity forever.",
	},
	-- No tank limit (Formulas.HasInfiniteTank). Rewards and Volts products still count normal full tanks.
	InfiniteTank = {
		Id = 0,
		Image = 125171723070743, -- assets/gamepasses/InfiniteTank.png
		Order = 7,
		Name = "Infinite Tank",
		Icon = "♾️",
		Price = 499,
		Color = Color3.fromRGB(120, 96, 255),
		Description = "Your Storm Tank never fills up: catch weather nonstop and sell whenever you like.",
	},
	LuckyHatcher = {
		Id = 0,
		Image = 73259738950338, -- assets/gamepasses/LuckyHatcher.png
		Order = 8,
		Name = "Lucky Hatcher",
		Icon = "🍀",
		Price = 249,
		Color = Color3.fromRGB(90, 230, 120),
		Description = "+50% luck for Rare, Epic and Legendary pets from every egg.",
	},
	TripleHatch = {
		Id = 0,
		Image = 89960649556054, -- assets/gamepasses/TripleHatch.png
		Order = 9,
		Name = "Triple Hatch",
		Icon = "🥚",
		Price = 149,
		Color = Color3.fromRGB(255, 170, 220),
		Description = "Hatch 3 eggs at once.",
	},
	AutoHatch = {
		Id = 0,
		Image = 99891956329462, -- assets/gamepasses/AutoHatch.png
		Order = 10,
		Name = "Auto Hatch",
		Icon = "🔁",
		Price = 99,
		Color = Color3.fromRGB(190, 140, 255),
		Description = "Keep hatching eggs automatically while you stand next to them.",
	},
	PetSlots = {
		Id = 0,
		Image = 137574833831934, -- assets/gamepasses/PetSlots.png
		Order = 11,
		Name = "+3 Pet Slots",
		Icon = "🐾",
		Price = 249,
		Color = Color3.fromRGB(255, 120, 160),
		Description = "Equip 3 more pets at the same time.",
	},
	StormRadar = {
		Id = 0,
		Image = 124803896997456, -- assets/gamepasses/StormRadar.png
		Order = 12,
		Name = "Storm Radar",
		Icon = "🛰️",
		Price = 149,
		Color = Color3.fromRGB(56, 201, 176),
		Description = "Get alerted whenever rare weather spawns in any zone you've unlocked, with a button that teleports you there.",
	},
}

-- Volts products grant `Amount` full tanks of your best zone's energy, so they stay
-- valuable at every stage of the game (see Formulas.VoltsUnit).
Monetization.Products = {
	VoltsSmall = {
		Id = 0,
		Image = 96350967025071, -- assets/products/VoltsSmall.png
		Order = 1,
		Category = "Volts",
		Name = "Pouch of Volts",
		Icon = "⚡",
		Price = 25,
		Kind = "Volts",
		Amount = 4,
	},
	VoltsMedium = {
		Id = 0,
		Image = 106239033232780, -- assets/products/VoltsMedium.png
		Order = 2,
		Category = "Volts",
		Name = "Bag of Volts",
		Icon = "💰",
		Price = 79,
		Kind = "Volts",
		Amount = 15,
	},
	VoltsLarge = {
		Id = 0,
		Image = 115014003587990, -- assets/products/VoltsLarge.png
		Order = 3,
		Category = "Volts",
		Name = "Crate of Volts",
		Icon = "📦",
		Price = 249,
		Kind = "Volts",
		Amount = 60,
	},
	VoltsHuge = {
		Id = 0,
		Image = 115566008270002, -- assets/products/VoltsHuge.png
		Order = 4,
		Category = "Volts",
		Name = "Vault of Volts",
		Icon = "🏦",
		Price = 699,
		Kind = "Volts",
		Amount = 200,
	},
	EnergyBoost = {
		Id = 0,
		Image = 140236491284484, -- assets/products/EnergyBoost.png
		Order = 5,
		Category = "Boosts",
		Name = "2x Energy (30 min)",
		Icon = "⚡",
		Price = 49,
		Kind = "Boost",
		Boost = "Energy",
		Duration = 1800,
	},
	LuckBoost = {
		Id = 0,
		Image = 86026195694680, -- assets/products/LuckBoost.png
		Order = 6,
		Category = "Boosts",
		Name = "2x Luck (30 min)",
		Icon = "🍀",
		Price = 49,
		Kind = "Boost",
		Boost = "Luck",
		Duration = 1800,
	},
	SummonMegaStorm = {
		Id = 0,
		Image = 85777659133015, -- assets/products/SummonMegaStorm.png
		Order = 7,
		Category = "Boosts",
		Name = "Summon Mega Storm",
		Icon = "🌪️",
		Price = 99,
		Kind = "MegaStorm",
		Description = "Summon a Mega Storm for the whole server! It arrives in 20 seconds, or right after any storm that is already on its way.",
	},
	-- Lobby shop pet (the display stand in the hub and the Shop's featured card). Every purchase gives one
	-- Aurora Gryphon (Pets.Pets.AuroraGryphon, +600%); it is granted even when pet storage is full.
	-- Developer product "Aurora Gryphon" (Creator Dashboard -> Monetization -> Developer Products), R$2,000.
	AuroraGryphon = {
		Id = 3722233930,
		Image = 136949961075464, -- assets/products/AuroraGryphon.png
		Order = 0,
		Category = "Featured",
		Name = "Aurora Gryphon",
		Icon = "Pets", -- Icons.luau key (3D paw); Icons.Emoji("Pets") = "🐾"
		Price = 2000,
		Kind = "Pet",
		PetId = "AuroraGryphon",
		Description = "An exclusive pet with glowing aurora wings: +600% energy. Every purchase adds one more to your team.",
	},
}

-- Fill in keys
for key, pass in Monetization.Gamepasses do
	pass.Key = key
end
for key, product in Monetization.Products do
	product.Key = key
end

function Monetization.SortedPasses()
	local list = {}
	for _, pass in Monetization.Gamepasses do
		table.insert(list, pass)
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end

function Monetization.SortedProducts(category: string?)
	local list = {}
	for _, product in Monetization.Products do
		if category == nil or product.Category == category then
			table.insert(list, product)
		end
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end

return Monetization
