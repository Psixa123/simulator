--!nocheck
-- Mock test for the lobby shop pet (Monetization.Products.AuroraGryphon): the product and pet configs, and
-- the real MonetizationService receipt handler granting the pet through the real PetService (saved with the
-- data, in the Index, auto-equipped, replicated), idempotent repeat receipts, a full pet storage (the paid
-- pet is still granted), failed saves (confirmed only once saved, never granted twice), players who left
-- or are leaving, unknown products, and the Studio test purchase (DevGrant) while the product Id is 0.
-- Runs after RobloxMock.luau and the module sources in one bundle; see run_mock_tests.py.

local failures, passes = 0, 0
local function check(name, condition, detail)
	if condition then
		passes += 1
	else
		failures += 1
		Mock.RealPrint("FAIL " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function count(list, pattern)
	local found = 0
	for _, message in list do
		if string.find(message, pattern, 1, true) then
			found += 1
		end
	end
	return found
end

local function signal()
	local handlers = {}
	return {
		Connect = function(_, fn)
			table.insert(handlers, fn)
			return { Disconnect = function() end }
		end,
		Fire = function(_, ...)
			for _, fn in handlers do
				fn(...)
			end
		end,
	}
end

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[key] = deepCopy(item)
	end
	return copy
end

-- RobloxMock has no Random (PetService makes one for its egg rolls): a stand-in on math.random
Random = {
	new = function()
		return {
			NextNumber = function(_, low, high)
				low, high = low or 0, high or 1
				return low + math.random() * (high - low)
			end,
			NextInteger = function(_, low, high)
				return math.random(low, high)
			end,
		}
	end,
}

------------------------------------------------------------------------ game tree
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local PolicyService = game:GetService("PolicyService")
local Shared = Mock.Folder("Shared", ReplicatedStorage)
local Config = Mock.Folder("Config", Shared)
local Util = Mock.Folder("Util", Shared)
Mock.Module("GameConfig", Config, __sources.GameConfig)
Mock.Module("Monetization", Config, __sources.Monetization)
Mock.Module("Pets", Config, __sources.Pets)
Mock.Module("Zones", Config, __sources.Zones)
Mock.Module("Weather", Config, __sources.Weather)
Mock.Module("MapLayout", Config, __sources.MapLayout)
Mock.Module("Formulas", Shared, __sources.Formulas)
Mock.Module("Format", Util, __sources.Format)

local DevGrant = Instance.new("RemoteFunction")
DevGrant.Name = "DevGrant"
local Hatch = Instance.new("RemoteFunction")
Hatch.Name = "Hatch"
local PetAction = Instance.new("RemoteFunction")
PetAction.Name = "PetAction"
Mock.Module("Remotes", Shared, function()
	return { DevGrant = DevGrant, Hatch = Hatch, PetAction = PetAction }
end)

local GameConfig = require(Config.GameConfig)
local Monetization = require(Config.Monetization)
local Pets = require(Config.Pets)
local Formulas = require(Shared.Formulas)

------------------------------------------------------------------------ players
local playerList = {}
Players.GetPlayers = function()
	return table.clone(playerList)
end
Players.GetPlayerByUserId = function(_, userId)
	for _, player in playerList do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end
Players.PlayerAdded = signal()
Players.PlayerRemoving = signal()

local function newPlayer(name, userId)
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	player.Parent = Players
	table.insert(playerList, player)
	return player
end

MarketplaceService.PromptGamePassPurchaseFinished = signal()
MarketplaceService.UserOwnsGamePassAsync = function()
	error("no pass has an Id in this test")
end
PolicyService.GetPolicyInfoForPlayerAsync = function()
	return { ArePaidRandomItemsRestricted = false }
end

------------------------------------------------------------------------ stand-in services
-- DataService keeps one profile per player like the real one: saves can fail, a successful save stores a
-- copy of the data (what the player gets back next session) and clears the unsaved receipts
local profiles = {} -- [Player] = { Data, Unsaved, CanSave, Released, SaveWorks, Saves, Stored }
local replicated = {} -- "Name:Key"
local effects = {} -- "Name|Effect|args"
local notified = {} -- "Name|text|kind" ("*" = everyone)
local calls = {}

local function newData()
	return {
		Volts = 1000,
		TotalVolts = 5000,
		Zone = 1,
		Upgrades = { Power = 1, Tank = 1, Range = 1, Speed = 1 },
		Pets = { { Uid = "p1", Id = "Puffling", Golden = false, Rainbow = false, Equipped = true } },
		NextPetId = 2,
		Index = { Puffling = true },
		Boosts = {},
		Stats = { EggsHatched = 0 },
		Receipts = {},
		Passes = {},
	}
end

local Registry = {}
Registry.DataService = {
	PlayerLoaded = signal(),
	Get = function(player)
		local profile = profiles[player]
		return profile and profile.Data
	end,
	WaitForData = function(player)
		local profile = profiles[player]
		return profile and profile.Data
	end,
	IsReleased = function(player)
		local profile = profiles[player]
		return profile ~= nil and profile.Released
	end,
	CanSave = function(player)
		local profile = profiles[player]
		return profile ~= nil and profile.CanSave
	end,
	MarkReceiptUnsaved = function(player, purchaseId)
		profiles[player].Unsaved[purchaseId] = true
	end,
	IsReceiptUnsaved = function(player, purchaseId)
		local profile = profiles[player]
		return profile ~= nil and profile.Unsaved[purchaseId] == true
	end,
	Save = function(player, release)
		local profile = profiles[player]
		if not profile or not profile.CanSave or (profile.Released and not release) then
			return false
		end
		profile.Saves += 1
		if not profile.SaveWorks then
			return false
		end
		profile.Stored = deepCopy(profile.Data)
		table.clear(profile.Unsaved)
		return true
	end,
	Replicate = function(player, ...)
		for _, key in { ... } do
			table.insert(replicated, player.Name .. ":" .. key)
		end
	end,
}
Registry.EconomyService = {
	AddVolts = function(player, amount)
		profiles[player].Data.Volts += math.floor(amount)
	end,
}
Registry.BoostService = {
	Add = function(player, boost, seconds)
		table.insert(calls, string.format("BoostService.Add %s %s %d", player.Name, boost, seconds))
	end,
}
Registry.MegaStormService = {
	Summon = function(player)
		table.insert(calls, "MegaStormService.Summon " .. player.Name)
	end,
}

local Net = {
	RateLimit = function()
		return true
	end,
	Fail = function(message)
		return { Ok = false, Error = message }
	end,
	Notify = function(player, text, kind)
		table.insert(notified, player.Name .. "|" .. text .. "|" .. tostring(kind))
	end,
	NotifyAll = function(text, kind)
		table.insert(notified, "*|" .. text .. "|" .. tostring(kind))
	end,
	Effect = function(player, name, ...)
		local args = {}
		for _, value in { ... } do
			table.insert(args, tostring(value))
		end
		table.insert(effects, player.Name .. "|" .. name .. "|" .. table.concat(args, ","))
	end,
	EffectAll = function() end,
	GetRoot = function()
		return nil
	end,
}

local Services = Mock.Folder("Services", game:GetService("ServerScriptService"))
Mock.Module("Registry", Services, function()
	return Registry
end)
Mock.Module("Net", Services, function()
	return Net
end)
Mock.Module("PetService", Services, __sources.PetService)
Mock.Module("MonetizationService", Services, __sources.MonetizationService)

local function reset()
	table.clear(replicated)
	table.clear(effects)
	table.clear(notified)
	table.clear(calls)
	table.clear(Mock.Warnings)
end

local function gryphons(pets)
	local found = 0
	for _, pet in pets do
		if pet.Id == "AuroraGryphon" then
			found += 1
		end
	end
	return found
end

------------------------------------------------------------------------ configs
local product = Monetization.Products.AuroraGryphon
check("config: Monetization.Products.AuroraGryphon exists", product ~= nil)
check("config: Id is a number (0 until the product is created)", type(product.Id) == "number" and product.Id >= 0, product.Id)
check("config: R$2,000", product.Price == 2000, product.Price)
check("config: Kind Pet", product.Kind == "Pet", product.Kind)
check("config: PetId AuroraGryphon", product.PetId == "AuroraGryphon", product.PetId)
check("config: Key filled in", product.Key == "AuroraGryphon", product.Key)
for _, field in { "Name", "Description", "Icon", "Category" } do
	check("config: " .. field .. " is text", type(product[field]) == "string" and product[field] ~= "", product[field])
end
check("config: Order set (SortedProducts sorts by it)", type(product.Order) == "number")
local sortedOk, sorted = pcall(Monetization.SortedProducts)
check("config: SortedProducts still sorts every product", sortedOk and table.find(sorted, product) ~= nil, sorted)
local featured = Monetization.SortedProducts(product.Category)
check("config: listed under its own category", #featured == 1 and featured[1] == product, #featured)

local pet = Pets.Pets.AuroraGryphon
check("pet: defined", pet ~= nil)
check("pet: Exclusive rarity", pet.Rarity == "Exclusive", pet.Rarity)
check("pet: not in any egg (only sold)", pet.Egg == nil, pet.Egg)
check("pet: in the Index order", table.find(Pets.IndexOrder, "AuroraGryphon") ~= nil)
check("pet: name matches the product", pet.Name == product.Name, pet.Name)

-- Balance (Pets.luau explains it): better than anything a new player can hatch, but egg Legendaries from
-- Ashfall on, most Mega Storm exclusives and crafted pets pass it
local function eggBest(zone, rarity)
	for _, def in Pets.Pets do
		if def.Egg and Pets.Eggs[def.Egg].Zone == zone and def.Rarity == rarity then
			return def.Bonus
		end
	end
	return 0
end
check("balance: beats the Dune Sea Legendary", pet.Bonus > eggBest(3, "Legendary"), eggBest(3, "Legendary"))
check("balance: beats the first Mega Storm exclusive", pet.Bonus > Pets.Pets.TempestTitan.Bonus)
check("balance: at most the Frostpeak Legendary", pet.Bonus <= eggBest(4, "Legendary"), eggBest(4, "Legendary"))
check("balance: under the Volt Wyrm", pet.Bonus < Pets.Pets.VoltWyrm.Bonus)
check("balance: under the Ashfall Legendary", pet.Bonus < eggBest(5, "Legendary"), eggBest(5, "Legendary"))
check("balance: under a Golden Frostpeak Epic", pet.Bonus < eggBest(4, "Epic") * GameConfig.Pets.GoldenMultiplier)
check("balance: under the Rainbow Roc", pet.Bonus < Pets.Pets.RainbowRoc.Bonus)

------------------------------------------------------------------------ setup: a live server
local PRODUCT_ID, BOOST_ID = 1888000001, 1888000002
-- the receipt tests need real ids (the config ships with 0 until the products are created)
product.Id = PRODUCT_ID
Monetization.Products.EnergyBoost.Id = BOOST_ID
Mock.IsStudio = false

local buyer = newPlayer("Puffball42", 4242)
local hoarder = newPlayer("Hoarder", 5151)
local leaving = newPlayer("Leaving", 6161)
local loading = newPlayer("StillLoading", 7171)
for _, player in { buyer, hoarder, leaving } do
	profiles[player] = { Data = newData(), Unsaved = {}, CanSave = true, Released = false, SaveWorks = true, Saves = 0 }
end
profiles[leaving].Released = true

local PetService = require(Services.PetService)
Registry.PetService = PetService
local MonetizationService = require(Services.MonetizationService)
PetService.Init()
MonetizationService.Init()
check("init: ProcessReceipt set", type(MarketplaceService.ProcessReceipt) == "function")
check("init: DevGrant handled", type(DevGrant.OnServerInvoke) == "function")

local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted
local LATER = Enum.ProductPurchaseDecision.NotProcessedYet
local function receipt(player, purchaseId, productId)
	return MarketplaceService.ProcessReceipt({ PlayerId = player.UserId, ProductId = productId or PRODUCT_ID, PurchaseId = purchaseId, CurrencySpent = 2000 })
end

------------------------------------------------------------------------ receipt -> pet granted
reset()
local data = profiles[buyer].Data
local decision = receipt(buyer, "buy-1")
check("buy: PurchaseGranted", decision == GRANTED, decision)
check("buy: one Aurora Gryphon", gryphons(data.Pets) == 1, gryphons(data.Pets))
local entry = data.Pets[#data.Pets]
check("buy: a Normal pet with a fresh Uid", entry.Id == "AuroraGryphon" and entry.Uid == "p2" and not entry.Golden and not entry.Rainbow, entry.Uid)
check("buy: auto-equipped into a free slot", entry.Equipped == true)
check("buy: counts towards the multiplier", Formulas.PetMultiplier(data) == 1 + Pets.Pets.Puffling.Bonus + pet.Bonus, Formulas.PetMultiplier(data))
check("buy: in the Index", data.Index.AuroraGryphon == true)
check("buy: Pets replicated", count(replicated, "Puffball42:Pets") >= 1, table.concat(replicated, " "))
check("buy: Index replicated", count(replicated, "Puffball42:Index") >= 1, table.concat(replicated, " "))
check("buy: follows the player (EquippedPets)", string.find(buyer:GetAttribute("EquippedPets") or "", "AuroraGryphon:0", 1, true) ~= nil, buyer:GetAttribute("EquippedPets"))
check("buy: receipt recorded", data.Receipts["buy-1"] ~= nil)
check("buy: saved before confirming", profiles[buyer].Saves == 1 and profiles[buyer].Stored ~= nil, profiles[buyer].Saves)
check("buy: the saved data has the pet", gryphons(profiles[buyer].Stored.Pets) == 1 and profiles[buyer].Stored.Index.AuroraGryphon == true)
check("buy: the saved data has the receipt", profiles[buyer].Stored.Receipts["buy-1"] ~= nil)
check("buy: no unsaved receipt left", not Registry.DataService.IsReceiptUnsaved(buyer, "buy-1"))
check("buy: pet reveal", count(effects, "Puffball42|PetReveal|AuroraGryphon,false") == 1, table.concat(effects, " "))
check("buy: purchase confetti", count(effects, "Puffball42|Purchase|Aurora Gryphon") == 1, table.concat(effects, " "))
check("buy: thank-you toast", count(notified, "Puffball42|🐾 The Aurora Gryphon is yours!") == 1, table.concat(notified, " "))
check("buy: server-wide shout-out", count(notified, "*|✨ Puffball42 got the Aurora Gryphon from the lobby shop!") == 1, table.concat(notified, " "))
check("buy: no storage warning", count(notified, "storage") == 0)

-- Roblox repeats a receipt until it hears PurchaseGranted: the same PurchaseId never grants twice
reset()
decision = receipt(buyer, "buy-1")
check("repeat: PurchaseGranted", decision == GRANTED, decision)
check("repeat: still one Aurora Gryphon", gryphons(data.Pets) == 1, gryphons(data.Pets))
check("repeat: no second reveal", #effects == 0, table.concat(effects, " "))
check("repeat: no second toast", #notified == 0, table.concat(notified, " "))
check("repeat: nothing to save again", profiles[buyer].Saves == 1, profiles[buyer].Saves)

-- Every new purchase adds one more
reset()
decision = receipt(buyer, "buy-2")
check("second buy: PurchaseGranted", decision == GRANTED, decision)
check("second buy: two Aurora Gryphons", gryphons(data.Pets) == 2, gryphons(data.Pets))
check("second buy: unique Uid", data.Pets[#data.Pets].Uid == "p3", data.Pets[#data.Pets].Uid)
check("second buy: equipped too (third slot free)", data.Pets[#data.Pets].Equipped == true)
check("second buy: saved", gryphons(profiles[buyer].Stored.Pets) == 2)

------------------------------------------------------------------------ full pet storage
reset()
local full = profiles[hoarder].Data
for _ = #full.Pets + 1, GameConfig.Pets.MaxStorage do
	table.insert(full.Pets, { Uid = "p" .. full.NextPetId, Id = "Puffling", Golden = false, Rainbow = false, Equipped = false })
	full.NextPetId += 1
end
check("full: storage at the limit before buying", #full.Pets == GameConfig.Pets.MaxStorage, #full.Pets)
decision = receipt(hoarder, "full-1")
check("full: PurchaseGranted", decision == GRANTED, decision)
check("full: the paid pet is granted anyway", gryphons(full.Pets) == 1 and #full.Pets == GameConfig.Pets.MaxStorage + 1, #full.Pets)
check("full: in the Index", full.Index.AuroraGryphon == true)
check("full: saved", profiles[hoarder].Stored ~= nil and gryphons(profiles[hoarder].Stored.Pets) == 1)
check("full: told storage is over the limit", count(notified, "Hoarder|🎒 Your pet storage is over the limit") == 1, table.concat(notified, " "))
check("full: hatching stays blocked until pets are deleted", PetService.Hatch(hoarder, "MeadowEgg", 1, true).Ok == false)

------------------------------------------------------------------------ failed saves
reset()
profiles[buyer].SaveWorks = false
local savesBefore = profiles[buyer].Saves
decision = receipt(buyer, "buy-3")
check("save fails: NotProcessedYet (Roblox retries)", decision == LATER, decision)
check("save fails: granted in memory", gryphons(data.Pets) == 3, gryphons(data.Pets))
check("save fails: receipt remembered", data.Receipts["buy-3"] ~= nil and Registry.DataService.IsReceiptUnsaved(buyer, "buy-3"))
check("save fails: a save was attempted", profiles[buyer].Saves == savesBefore + 1, profiles[buyer].Saves)
reset()
decision = receipt(buyer, "buy-3")
check("save still failing: NotProcessedYet again", decision == LATER, decision)
check("save still failing: not granted twice", gryphons(data.Pets) == 3, gryphons(data.Pets))
reset()
profiles[buyer].SaveWorks = true
decision = receipt(buyer, "buy-3")
check("save works again: PurchaseGranted", decision == GRANTED, decision)
check("save works again: still three", gryphons(data.Pets) == 3, gryphons(data.Pets))
check("save works again: saved with the pet", gryphons(profiles[buyer].Stored.Pets) == 3)
check("save works again: no unsaved receipt left", not Registry.DataService.IsReceiptUnsaved(buyer, "buy-3"))

------------------------------------------------------------------------ players who aren't there
reset()
check("left the game: NotProcessedYet", MarketplaceService.ProcessReceipt({ PlayerId = 9999, ProductId = PRODUCT_ID, PurchaseId = "gone-1" }) == LATER)
check("still loading: NotProcessedYet", receipt(loading, "load-1") == LATER)
local leavingPets = #profiles[leaving].Data.Pets
check("leaving (released): NotProcessedYet", receipt(leaving, "leave-1") == LATER)
check("leaving (released): nothing granted", #profiles[leaving].Data.Pets == leavingPets and profiles[leaving].Data.Receipts["leave-1"] == nil)

------------------------------------------------------------------------ unknown product and a broken grant
reset()
local before = #data.Pets
check("unknown product: NotProcessedYet", receipt(buyer, "odd-1", 4040404) == LATER)
check("unknown product: warned", count(Mock.Warnings, "unknown product id") == 1, table.concat(Mock.Warnings, " "))
product.PetId = "NoSuchPet"
reset()
check("broken grant: NotProcessedYet", receipt(buyer, "broken-1") == LATER)
check("broken grant: no pet, no receipt", #data.Pets == before and data.Receipts["broken-1"] == nil, #data.Pets)
check("broken grant: warned", count(Mock.Warnings, "Failed to grant AuroraGryphon") == 1, table.concat(Mock.Warnings, " "))
product.PetId = "AuroraGryphon"

-- The other products still take their own paths
reset()
check("boost product: granted", receipt(buyer, "boost-1", BOOST_ID) == GRANTED)
check("boost product: a boost, not a pet", #calls == 1 and string.find(calls[1], "BoostService.Add Puffball42 Energy", 1, true) ~= nil and #data.Pets == before, table.concat(calls, " "))

------------------------------------------------------------------------ Studio test purchase (Id = 0)
product.Id = 0
reset()
local studioBefore = gryphons(data.Pets)
local reply = DevGrant.OnServerInvoke(buyer, "Product", "AuroraGryphon")
check("live server, Id 0: refused", reply.Ok == false and gryphons(data.Pets) == studioBefore, reply.Error)
Mock.IsStudio = true
reply = DevGrant.OnServerInvoke(buyer, "Product", "AuroraGryphon")
check("Studio, Id 0: simulated purchase works", reply.Ok == true, reply.Error)
check("Studio, Id 0: pet granted", gryphons(data.Pets) == studioBefore + 1, gryphons(data.Pets))
check("Studio, Id 0: reveal shown", count(effects, "Puffball42|PetReveal|AuroraGryphon") == 1, table.concat(effects, " "))
Mock.IsStudio = false

Mock.RealPrint(string.format("Purchase mock test: %d passed, %d failed", passes, failures))
if failures > 0 then
	error("mock test failed")
end
