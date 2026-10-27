--!nocheck
-- Mock test for the Secret pets (Pets.Eggs[*].Secrets): the config (one secret per egg for the first four eggs,
-- several for the last two, odds rising from 1 in 250K, bonuses far above anything else at that point), the
-- hatch chances (summing to 1 at every luck, each secret exactly 1 in Odds, luck helping secrets only a little),
-- the whole-number secret roll (exact boundaries, nothing lost to float rounding), seeded statistical runs, and
-- hatching through the real PetService: the pet index discovers it, the server-wide announcement (Legendary and
-- Exclusive ones unchanged, Commons quiet), Golden / Rainbow crafting, and bulk deletion leaving secrets alone.
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

-- RobloxMock has no Random: a seeded stand-in on math.random (PCG32 in Luau, so runs are reproducible).
-- forced.Ticket / forced.Number make the next draws land exactly where a test wants them.
local forced = { Ticket = nil, Number = nil }
Random = {
	new = function()
		return {
			NextNumber = function(_, low, high)
				low, high = low or 0, high or 1
				if forced.Number then
					local value = forced.Number
					forced.Number = nil
					return low + value * (high - low)
				end
				return low + math.random() * (high - low)
			end,
			NextInteger = function(_, low, high)
				if forced.Ticket then
					local value = forced.Ticket
					forced.Ticket = nil
					return value
				end
				return math.random(low, high)
			end,
		}
	end,
}
-- a Random that always gives these draws (for Formulas.RollHatch directly)
local function fixedRandom(ticket, number)
	return {
		NextInteger = function()
			return ticket
		end,
		NextNumber = function(_, low, high)
			low, high = low or 0, high or 1
			return low + number * (high - low)
		end,
	}
end
local function seededRandom(seed)
	math.randomseed(seed)
	return {
		NextInteger = function(_, low, high)
			return math.random(low, high)
		end,
		NextNumber = function(_, low, high)
			low, high = low or 0, high or 1
			return low + math.random() * (high - low)
		end,
	}
end

------------------------------------------------------------------------ game tree
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
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

local Hatch = Instance.new("RemoteFunction")
Hatch.Name = "Hatch"
local PetAction = Instance.new("RemoteFunction")
PetAction.Name = "PetAction"
Mock.Module("Remotes", Shared, function()
	return { Hatch = Hatch, PetAction = PetAction }
end)

local GameConfig = require(Config.GameConfig)
local Pets = require(Config.Pets)
local Formulas = require(Shared.Formulas)
local Format = require(Util.Format)

local SCALE = GameConfig.Pets.SecretRollScale

------------------------------------------------------------------------ config
local secretCount = 0
local bestOther = 0 -- the best bonus of any pet that isn't a secret (Normal tier)
local bestExclusive = 0
for id, pet in Pets.Pets do
	if pet.Rarity == "Secret" then
		secretCount += 1
	else
		bestOther = math.max(bestOther, pet.Bonus)
		if pet.Rarity == "Exclusive" then
			bestExclusive = math.max(bestExclusive, pet.Bonus)
		end
	end
	check("config: " .. id .. " IsSecret matches its rarity", Pets.IsSecret(id) == (pet.Rarity == "Secret"))
end
check("config: Secret rarity is above Exclusive", Pets.Rarities.Secret.Order == 7 and Pets.Rarities.Secret.Order > Pets.Rarities.Exclusive.Order)
check("config: Secret pets are bigger than Exclusive ones", Pets.Rarities.Secret.Scale > Pets.Rarities.Exclusive.Scale)
check("config: a rainbow for the UI", #Pets.SecretRainbow >= 5)

local listed = 0
local previousBest = 0 -- best secret bonus of the eggs before
local previousOdds = 0
for eggIndex, eggId in Pets.EggOrder do
	local egg = Pets.Eggs[eggId]
	local secrets = egg.Secrets
	local wanted = if eggIndex <= 4 then 1 else 2
	check("config: " .. eggId .. " has its secret pet(s)", type(secrets) == "table" and #secrets >= wanted and (eggIndex > 4 or #secrets == 1), #secrets)
	local legendary = 0
	for _, entry in egg.Pets do
		if Pets.Pets[entry.Id].Rarity == "Legendary" then
			legendary = Pets.Pets[entry.Id].Bonus
		end
	end
	local lowest, highest = math.huge, 0
	for _, entry in secrets do
		listed += 1
		local def = Pets.Pets[entry.Id]
		check("config: " .. entry.Id .. " exists and is Secret", def ~= nil and def.Rarity == "Secret")
		check("config: " .. entry.Id .. " knows its egg and odds", def.Egg == eggId and def.Odds == entry.Odds)
		check("config: " .. entry.Id .. " odds are a whole 1 in N that divides the roll scale (exact)",
			entry.Odds == math.floor(entry.Odds) and SCALE % entry.Odds == 0, entry.Odds)
		check("config: " .. entry.Id .. " is very very rare (1 in 250K or rarer)", entry.Odds >= 250000, entry.Odds)
		check("config: " .. entry.Id .. " is at least 5x its egg's Legendary", def.Bonus >= 5 * legendary, def.Bonus .. " vs " .. legendary)
		check("config: " .. entry.Id .. " beats every Mega Storm exclusive", def.Bonus > bestExclusive, def.Bonus)
		check("config: " .. entry.Id .. " beats every earlier egg's secrets", def.Bonus > previousBest, def.Bonus)
		check("config: " .. entry.Id .. " is in the pet index", table.find(Pets.IndexOrder, entry.Id) ~= nil)
		check("config: " .. entry.Id .. " has a look", def.Look and def.Look.Body and def.Look.Color and def.Look.Accent)
		check("config: " .. entry.Id .. " is no rarer than... odds never get easier for later eggs", entry.Odds >= previousOdds, entry.Odds)
		lowest = math.min(lowest, def.Bonus)
		highest = math.max(highest, def.Bonus)
		-- the index lists it right after its egg's pets
		local position = table.find(Pets.IndexOrder, entry.Id)
		local lastPet = table.find(Pets.IndexOrder, egg.Pets[#egg.Pets].Id)
		check("config: " .. entry.Id .. " follows its egg in the index", position and lastPet and position > lastPet and position <= lastPet + #secrets)
	end
	if eggIndex == #Pets.EggOrder then
		check("config: the last egg's secrets are the best pets in the game", lowest > bestOther * GameConfig.Pets.RainbowMultiplier,
			lowest .. " vs a Rainbow " .. bestOther)
		check("config: the last egg is at least 1 in 2M per secret", secrets[1].Odds >= 2000000, secrets[1].Odds)
	end
	previousBest = highest
	previousOdds = secrets[1].Odds
end
check("config: 1 + 1 + 1 + 1 + 2 + 3 secrets", secretCount == 9 and listed == 9, secretCount)
check("config: first egg 1 in 250K", Pets.Eggs[Pets.EggOrder[1]].Secrets[1].Odds == 250000)
check("config: Format.Odds", Format.Odds(1 / 250000) == "1 in 250K" and Format.Odds(1 / 5000000) == "1 in 5M" and Format.Odds(1 / 1200000) == "1 in 1.2M",
	Format.Odds(1 / 1200000))

------------------------------------------------------------------------ chances
check("luck: no luck, no change", Formulas.SecretLuck(1) == 1)
check("luck: Lucky Hatcher alone x1.25", Formulas.SecretLuck(GameConfig.PassEffects.LuckyHatcher) == 1.25)
check("luck: 2x Luck alone x1.5", Formulas.SecretLuck(GameConfig.Boosts.Luck.Multiplier) == 1.5)
check("luck: both x2", Formulas.SecretLuck(GameConfig.PassEffects.LuckyHatcher * GameConfig.Boosts.Luck.Multiplier) == 2)
check("luck: capped at x2 whatever the luck", Formulas.SecretLuck(1000) == GameConfig.Pets.SecretLuckMax and GameConfig.Pets.SecretLuckMax == 2)

local LUCKS = { 1, 1.5, 2, 3, 50 }
for _, eggId in Pets.EggOrder do
	local egg = Pets.Eggs[eggId]
	for _, luck in LUCKS do
		local chances = Formulas.HatchChances(eggId, luck)
		local total, secretTotal, regularWeights = 0, 0, 0
		for _, entry in chances do
			total += entry.Chance
			check("chances: " .. eggId .. " " .. entry.Id .. " is a probability", entry.Chance > 0 and entry.Chance < 1, entry.Chance)
		end
		check(string.format("chances: %s at luck %g sum to 1", eggId, luck), math.abs(total - 1) < 1e-12, total - 1)
		check("chances: " .. eggId .. " lists every pet once", #chances == #egg.Pets + #egg.Secrets, #chances)
		for _, entry in egg.Pets do
			local weight = entry.Chance * (if Pets.RarityOf(entry.Id).Order >= 3 then luck else 1)
			regularWeights += weight
		end
		for index, entry in chances do
			if entry.Secret then
				secretTotal += entry.Slots
				local configured = egg.Secrets[index - #egg.Pets]
				check("chances: " .. entry.Id .. " is the egg's secret in order", configured and configured.Id == entry.Id)
				local expected = math.floor(SCALE / configured.Odds * Formulas.SecretLuck(luck) + 0.5)
				check(string.format("chances: %s slots at luck %g", entry.Id, luck), entry.Slots == expected, entry.Slots .. " vs " .. expected)
				check("chances: " .. entry.Id .. " chance is its slots out of the scale", entry.Chance == entry.Slots / SCALE)
				if luck == 1 then
					check("chances: " .. entry.Id .. " is exactly 1 in Odds", entry.Slots * configured.Odds == SCALE and entry.Chance == 1 / configured.Odds,
						entry.Chance)
				end
				check(string.format("chances: %s luck %g helps at most x2", entry.Id, luck), entry.Chance <= 2 / configured.Odds + 1e-15)
				check(string.format("chances: %s stays very rare at luck %g", entry.Id, luck), entry.Chance <= 1 / 100000, entry.Chance)
			end
		end
		-- the regular pets keep their relative odds and share what the secrets leave
		local rest = (SCALE - secretTotal) / SCALE
		for index, entry in egg.Pets do
			local weight = entry.Chance * (if Pets.RarityOf(entry.Id).Order >= 3 then luck else 1)
			local expected = weight / regularWeights * rest
			check(string.format("chances: %s %s keeps its share at luck %g", eggId, entry.Id, luck),
				math.abs(chances[index].Chance - expected) < 1e-15, chances[index].Chance - expected)
		end
	end
end
-- the Egg panel still shows the regular odds as before (the secrets take a millionth or less)
check("chances: Puffling still reads 55%", Format.Chance(Formulas.HatchChances("MeadowEgg", 1)[1].Chance) == "55%",
	Format.Chance(Formulas.HatchChances("MeadowEgg", 1)[1].Chance))

------------------------------------------------------------------------ the roll: exact boundaries
for _, eggId in Pets.EggOrder do
	local egg = Pets.Eggs[eggId]
	for _, luck in { 1, 3 } do
		local upTo = 0
		for _, secret in Formulas.SecretSlots(eggId, luck) do
			check("roll: " .. secret.Id .. " first ticket", Formulas.RollHatch(eggId, luck, fixedRandom(upTo + 1, 0.5)) == secret.Id)
			upTo += secret.Slots
			check("roll: " .. secret.Id .. " last ticket", Formulas.RollHatch(eggId, luck, fixedRandom(upTo, 0.5)) == secret.Id)
		end
		local after = Formulas.RollHatch(eggId, luck, fixedRandom(upTo + 1, 0))
		check("roll: " .. eggId .. " one past the secrets is a regular pet", after == egg.Pets[1].Id, after)
		check("roll: " .. eggId .. " the last ticket is a regular pet", not Pets.IsSecret(Formulas.RollHatch(eggId, luck, fixedRandom(SCALE, 0.999999))))
		check("roll: " .. eggId .. " the top of the regular draw is its rarest pet",
			Formulas.RollHatch(eggId, luck, fixedRandom(SCALE, 0.9999999999)) == egg.Pets[#egg.Pets].Id)
	end
end
-- luck widens the slots: a ticket just past the base odds is a secret only with luck
local meadowSlots = SCALE / 250000
check("roll: ticket past 1 in 250K is no secret without luck", not Pets.IsSecret(Formulas.RollHatch("MeadowEgg", 1, fixedRandom(meadowSlots + 1, 0.5))))
check("roll: ...but is one with Lucky Hatcher", Formulas.RollHatch("MeadowEgg", 1.5, fixedRandom(meadowSlots + 1, 0.5)) == "EyeOfTheStorm")
check("roll: ...and the Lucky Hatcher range ends at 1 in 200K", not Pets.IsSecret(Formulas.RollHatch("MeadowEgg", 1.5, fixedRandom(5001, 0.5))))

------------------------------------------------------------------------ seeded statistics
-- 1) the real odds: 2,000,000 hatches of the first egg should give about 8 secrets (Poisson: 0..20 is >99.9 %)
do
	local random = seededRandom(20261027)
	local hits, regular = 0, {}
	local N = 2000000
	for _ = 1, N do
		local id = Formulas.RollHatch("MeadowEgg", 1, random)
		if id == "EyeOfTheStorm" then
			hits += 1
		else
			regular[id] = (regular[id] or 0) + 1
		end
	end
	check("stats: Eye of the Storm about 1 in 250K over 2M hatches", hits >= 1 and hits <= 20, hits)
	for _, entry in Pets.Eggs.MeadowEgg.Pets do
		local p = entry.Chance / 100
		local expected = N * p
		local sd = math.sqrt(N * p * (1 - p))
		local got = regular[entry.Id] or 0
		check("stats: " .. entry.Id .. " within 5 sd of its chance", math.abs(got - expected) <= 5 * sd, string.format("%d vs %.0f", got, expected))
	end
	Mock.RealPrint(string.format("  secret stats: %d Eye of the Storm in %d Plains hatches (expected %.1f)", hits, N, N / 250000))
end
-- 2) the secret branch at a measurable rate: the same code with the Cosmic secrets at 1 in 1000 / 2000 / 5000
do
	local saved = {}
	for index, entry in Pets.Eggs.CosmicEgg.Secrets do
		saved[index] = entry.Odds
		entry.Odds = ({ 1000, 2000, 5000 })[index]
	end
	for _, luck in { 1, 3 } do
		local random = seededRandom(7 + luck)
		local N = 400000
		local hits = {}
		for _ = 1, N do
			local id = Formulas.RollHatch("CosmicEgg", luck, random)
			hits[id] = (hits[id] or 0) + 1
		end
		for _, entry in Formulas.HatchChances("CosmicEgg", luck) do
			local expected = N * entry.Chance
			local sd = math.sqrt(N * entry.Chance * (1 - entry.Chance))
			local got = hits[entry.Id] or 0
			check(string.format("stats: %s at 1 in %d (luck %g) within 5 sd", entry.Id, math.floor(1 / entry.Chance + 0.5), luck),
				math.abs(got - expected) <= 5 * sd, string.format("%d vs %.1f", got, expected))
		end
	end
	for index, entry in Pets.Eggs.CosmicEgg.Secrets do
		entry.Odds = saved[index]
	end
	check("stats: odds restored", Pets.Eggs.CosmicEgg.Secrets[3].Odds == 5000000)
end

------------------------------------------------------------------------ hatching through the real PetService
local playerList = {}
Players.GetPlayers = function()
	return table.clone(playerList)
end

local profiles = {}
local notified = {}
local replicated = {}
local Registry = {}
Registry.DataService = {
	PlayerLoaded = signal(),
	Get = function(player)
		return profiles[player]
	end,
	Replicate = function(player, ...)
		for _, key in { ... } do
			table.insert(replicated, player.Name .. ":" .. key)
		end
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
	Effect = function() end,
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
local PetService = require(Services.PetService)
Registry.PetService = PetService
PetService.Init()

local player = Instance.new("Player")
player.Name = "Lucky"
player.DisplayName = "Lucky"
player.UserId = 4242
player.Parent = Players
table.insert(playerList, player)
profiles[player] = {
	Volts = 0,
	Zone = 6,
	Pets = {},
	NextPetId = 1,
	Index = {},
	Boosts = {},
	Passes = {},
	Stats = { EggsHatched = 0 },
}
local data = profiles[player]

-- a secret hatch: in the index (New), announced to everyone with its odds
forced.Ticket = 1
local result = PetService.Hatch(player, "MeadowEgg", 1, true)
check("hatch: ok", result and result.Ok, result and result.Error)
check("hatch: the secret came out", result.Results[1].Id == "EyeOfTheStorm", result.Results[1].Id)
check("hatch: it is New", result.Results[1].New == true)
check("hatch: discovered in the index", data.Index.EyeOfTheStorm == true)
check("hatch: the index is replicated", table.find(replicated, "Lucky:Index") ~= nil)
check("announce: the whole server hears about the secret", count(notified, "*|🌌 SECRET! Lucky hatched Eye of the Storm (1 in 250K)!|Reward") == 1,
	table.concat(notified, " / "))

-- a second copy is no longer New
forced.Ticket = 1
result = PetService.Hatch(player, "MeadowEgg", 1, true)
check("hatch: second copy not New", result.Results[1].Id == "EyeOfTheStorm" and result.Results[1].New == false)

-- Legendary still announced like before, Commons not at all
table.clear(notified)
forced.Ticket, forced.Number = SCALE, 0.9999999999
result = PetService.Hatch(player, "MeadowEgg", 1, true)
check("announce: Legendary unchanged", result.Results[1].Id == "BreezeKing" and count(notified, "*|🌟 Lucky hatched a Legendary Breeze King!|Reward") == 1,
	table.concat(notified, " / "))
table.clear(notified)
forced.Ticket, forced.Number = SCALE, 0
result = PetService.Hatch(player, "MeadowEgg", 1, true)
check("announce: Commons stay quiet", result.Results[1].Id == "Puffling" and #notified == 0, table.concat(notified, " / "))

-- the last egg's rarest secret (the last of its slots)
table.clear(notified)
local upTo = 0
for _, secret in Formulas.SecretSlots("CosmicEgg", 1) do
	upTo += secret.Slots
end
forced.Ticket = upTo
result = PetService.Hatch(player, "CosmicEgg", 1, true)
check("hatch: Hypercane from the last ticket", result.Results[1].Id == "Hypercane", result.Results[1].Id)
check("announce: 1 in 5M", count(notified, "(1 in 5M)!") == 1, table.concat(notified, " / "))

-- crafting: 5 secrets -> Golden, 5 Golden -> Rainbow
for _ = 1, 3 do
	forced.Ticket = 1
	PetService.Hatch(player, "MeadowEgg", 1, true)
end
local function owned(id, tier)
	local n = 0
	for _, pet in data.Pets do
		if pet.Id == id and Pets.TierOf(pet) == tier then
			n += 1
		end
	end
	return n
end
check("craft: five Eye of the Storm", owned("EyeOfTheStorm", "Normal") == 5, owned("EyeOfTheStorm", "Normal"))
local crafted = PetAction.OnServerInvoke(player, "Golden", "EyeOfTheStorm")
check("craft: Golden secret", crafted and crafted.Ok and owned("EyeOfTheStorm", "Golden") == 1 and owned("EyeOfTheStorm", "Normal") == 0,
	crafted and crafted.Error)
check("craft: Golden secret bonus", Formulas.PetBonus("EyeOfTheStorm", "Golden") == 20 * GameConfig.Pets.GoldenMultiplier)
for _ = 1, 4 do
	for _ = 1, 5 do
		forced.Ticket = 1
		PetService.Hatch(player, "MeadowEgg", 1, true)
	end
	PetAction.OnServerInvoke(player, "Golden", "EyeOfTheStorm")
end
crafted = PetAction.OnServerInvoke(player, "Rainbow", "EyeOfTheStorm")
check("craft: Rainbow secret", crafted and crafted.Ok and owned("EyeOfTheStorm", "Rainbow") == 1, crafted and crafted.Error)

-- bulk delete never takes secrets (one at a time only), but does take the commons picked with them
forced.Ticket = 1
PetService.Hatch(player, "MeadowEgg", 1, true)
local uids = {}
for _, pet in data.Pets do
	pet.Equipped = false
	if pet.Id == "EyeOfTheStorm" or pet.Id == "Puffling" then
		table.insert(uids, pet.Uid)
	end
end
local secretsBefore = owned("EyeOfTheStorm", "Normal") + owned("EyeOfTheStorm", "Rainbow")
local deleted = PetAction.OnServerInvoke(player, "DeleteMany", uids)
check("delete: bulk delete keeps the secrets", deleted and deleted.Ok and owned("EyeOfTheStorm", "Normal") + owned("EyeOfTheStorm", "Rainbow") == secretsBefore,
	deleted and (deleted.Error or deleted.Count))
check("delete: ...and removes the Puffling", owned("Puffling", "Normal") == 0)
local single = nil
for _, pet in data.Pets do
	if pet.Id == "EyeOfTheStorm" and Pets.TierOf(pet) == "Normal" then
		single = pet.Uid
	end
end
check("delete: one at a time works", single and PetAction.OnServerInvoke(player, "Delete", single).Ok and owned("EyeOfTheStorm", "Normal") == secretsBefore - 2)

------------------------------------------------------------------------ done
Mock.RealPrint(string.format("SecretPets mock test: %d passed, %d failed", passes, failures))
if failures > 0 then
	error("mock test failed")
end
