--!nocheck
-- Mock test for the Infinite Tank gamepass (Monetization.Gamepasses.InfiniteTank): the pass config, the shared
-- tank formulas (Formulas.HasInfiniteTank / IsTankFull / TankSpace / TankFillFraction, with TankCapacity kept
-- finite), the real EconomyService filling the tank past a normal tank and selling it, and every payout that
-- counts "full tanks" (Formulas.VoltsUnit: the Volts developer products through the real MonetizationService,
-- daily / gift / code rewards through the real RewardService) paying exactly the same with and without the pass.
-- Also the Studio test purchase of the pass while its Id is 0. The catch path itself (WeatherService and the
-- client's VacuumController) is played in tests/mock/FullBoot.luau.
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
local function finite(value)
	return type(value) == "number" and value == value and value < math.huge and value > -math.huge
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
Mock.Module("Rewards", Config, __sources.Rewards)
Mock.Module("Formulas", Shared, __sources.Formulas)
Mock.Module("Format", Util, __sources.Format)

local remotes = {}
for _, remoteName in { "DevGrant", "Sell", "ClaimDaily", "ClaimGift", "RedeemCode" } do
	local remote = Instance.new("RemoteFunction")
	remote.Name = remoteName
	remotes[remoteName] = remote
end
Mock.Module("Remotes", Shared, function()
	return remotes
end)

local GameConfig = require(Config.GameConfig)
local Monetization = require(Config.Monetization)
local Rewards = require(Config.Rewards)
local Formulas = require(Shared.Formulas)
local Format = require(Util.Format)

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
local datas = {} -- [Player] = data
local replicated = {} -- "Name:Key"
local effects = {} -- "Name|Effect|args"
local notified = {} -- "Name|text|kind"

-- A mid-game player: Storm Tank Lv 8, Thunder Valley power, two Climate Shifts
local function newData(passes)
	return {
		Volts = 1000,
		TotalVolts = 5000,
		Energy = 0,
		TankValue = 0,
		Rebirths = 2,
		Zone = 3,
		Upgrades = { Power = 30, Tank = 8, Range = 3, Speed = 2 },
		Pets = {},
		NextPetId = 1,
		Index = {},
		Boosts = { Energy = 0, Luck = 0 },
		Stats = { Sells = 0 },
		Receipts = {},
		Passes = passes or {},
	}
end

local Registry = {}
Registry.DataService = {
	PlayerLoaded = signal(),
	Get = function(player)
		return datas[player]
	end,
	WaitForData = function(player)
		return datas[player]
	end,
	IsReleased = function()
		return false
	end,
	CanSave = function()
		return true
	end,
	Save = function()
		return true
	end,
	MarkReceiptUnsaved = function() end,
	IsReceiptUnsaved = function()
		return false
	end,
	Replicate = function(player, ...)
		for _, key in { ... } do
			table.insert(replicated, player.Name .. ":" .. key)
		end
	end,
}
Registry.PetService = {
	Refresh = function() end,
}
Registry.BoostService = {
	Add = function() end,
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
	NotifyThrottled = function(player, key, text, kind)
		table.insert(notified, player.Name .. "|" .. text .. "|" .. tostring(kind))
	end,
	NotifyAll = function() end,
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
Mock.Module("EconomyService", Services, __sources.EconomyService)
Mock.Module("RewardService", Services, __sources.RewardService)
Mock.Module("MonetizationService", Services, __sources.MonetizationService)

local function reset()
	table.clear(replicated)
	table.clear(effects)
	table.clear(notified)
	table.clear(Mock.Warnings)
end

------------------------------------------------------------------------ config
local pass = Monetization.Gamepasses.InfiniteTank
check("config: Monetization.Gamepasses.InfiniteTank exists", pass ~= nil)
check("config: Key filled in", pass.Key == "InfiniteTank", pass.Key)
check("config: name", pass.Name == "Infinite Tank", pass.Name)
check("config: R$499", pass.Price == 499, pass.Price)
check("config: Id is a number (0 until the pass is created)", type(pass.Id) == "number" and pass.Id >= 0, pass.Id)
check("config: a Color", typeof(pass.Color) == "Color3" or type(pass.Color) == "table", typeof(pass.Color))
for _, field in { "Icon", "Description" } do
	check("config: " .. field .. " is text", type(pass[field]) == "string" and pass[field] ~= "", pass[field])
end
check("config: the description says it never fills up", string.find(pass.Description, "never fills up", 1, true) ~= nil, pass.Description)
local sorted = Monetization.SortedPasses()
local megaAt, infiniteAt = table.find(sorted, Monetization.Gamepasses.MegaTank), table.find(sorted, pass)
check("config: listed right after Mega Tank", megaAt ~= nil and infiniteAt == megaAt + 1, tostring(megaAt) .. " / " .. tostring(infiniteAt))
local orders = {}
local uniqueOrders = true
for key, other in Monetization.Gamepasses do
	if orders[other.Order] then
		uniqueOrders = false
	end
	orders[other.Order] = key
end
check("config: every pass has its own Order", uniqueOrders)
check("config: no effect number needed (it isn't a multiplier)", GameConfig.PassEffects.InfiniteTank == nil)

------------------------------------------------------------------------ formulas
local normalData = newData()
local infiniteData = newData({ InfiniteTank = true })
local capacity = Formulas.TankCapacity(normalData)
check("formulas: HasInfiniteTank", Formulas.HasInfiniteTank(infiniteData) and not Formulas.HasInfiniteTank(normalData))
check("formulas: TankCapacity stays finite with the pass", finite(Formulas.TankCapacity(infiniteData)), Formulas.TankCapacity(infiniteData))
check("formulas: TankCapacity is the same normal tank with or without the pass", Formulas.TankCapacity(infiniteData) == capacity, capacity)
check("formulas: VoltsUnit is the same with or without the pass", Formulas.VoltsUnit(infiniteData) == Formulas.VoltsUnit(normalData), Formulas.VoltsUnit(infiniteData))
check("formulas: VoltsUnit stays finite with the pass", finite(Formulas.VoltsUnit(infiniteData)) and Formulas.VoltsUnit(infiniteData) > 0)
local megaBoth = newData({ InfiniteTank = true, MegaTank = true })
check("formulas: Mega Tank + Infinite Tank: VoltsUnit unchanged", Formulas.VoltsUnit(megaBoth) == Formulas.VoltsUnit(normalData))
check("formulas: Mega Tank + Infinite Tank: TankCapacity finite", finite(Formulas.TankCapacity(megaBoth)) and Formulas.TankCapacity(megaBoth) == capacity * GameConfig.PassEffects.MegaTank)
check("formulas: MegaStormReward is the same with or without the pass", Formulas.MegaStormReward(infiniteData, 500, true) == Formulas.MegaStormReward(normalData, 500, true))

normalData.Energy = capacity
check("formulas: a normal tank at capacity is full", Formulas.IsTankFull(normalData))
check("formulas: a normal tank at capacity has no space", Formulas.TankSpace(normalData) == 0)
normalData.Energy = capacity / 4
check("formulas: a normal tank's space", math.abs(Formulas.TankSpace(normalData) - capacity * 3 / 4) < 1e-9, Formulas.TankSpace(normalData))
check("formulas: a normal tank's fill", Formulas.TankFillFraction(normalData) == 0.25, Formulas.TankFillFraction(normalData))
normalData.Energy = capacity * 3
check("formulas: an over-full normal tank shows full, not more", Formulas.TankFillFraction(normalData) == 1)

local everyFillOk, neverFull, neverStepsFull = true, true, true
for _, energy in { 0, 1, capacity / 2, capacity, capacity * 2, capacity * 19, capacity * 1000, 1e15, 1e30, 1e300 } do
	infiniteData.Energy = energy
	local fraction = Formulas.TankFillFraction(infiniteData)
	if not finite(fraction) or fraction < 0 or fraction > 0.95 then
		everyFillOk = false
		Mock.RealPrint(string.format("  fill %s at %s energy", tostring(fraction), tostring(energy)))
	end
	if Formulas.IsTankFull(infiniteData) or Formulas.TankSpace(infiniteData) ~= math.huge then
		neverFull = false
	end
	-- PlayerService.UpdateTank's 5% steps: the backpack must never step up to the "full" colour
	local stepped = if fraction >= 0.999 then 1 else math.floor(fraction * 20 + 0.5) / 20
	if stepped >= 0.999 then
		neverStepsFull = false
	end
end
check("formulas: an Infinite Tank's fill stays a number in 0..0.95 (no NaN / inf)", everyFillOk)
check("formulas: an Infinite Tank is never full and always has space", neverFull)
check("formulas: the backpack never shows an Infinite Tank as full", neverStepsFull)
infiniteData.Energy = 0
check("formulas: an empty Infinite Tank shows empty", Formulas.TankFillFraction(infiniteData) == 0)
infiniteData.Energy = capacity
check("formulas: one normal tank in an Infinite Tank shows half full", Formulas.TankFillFraction(infiniteData) == 0.5, Formulas.TankFillFraction(infiniteData))

check("format: math.huge prints ∞", Format.Number(math.huge) == "∞", Format.Number(math.huge))
check("format: -math.huge prints -∞", Format.Number(-math.huge) == "-∞", Format.Number(-math.huge))
check("format: NaN prints 0", Format.Number(0 / 0) == "0", Format.Number(0 / 0))
local noInf = true
for _, value in { math.huge, -math.huge, 0 / 0, 1e300, -1e300, capacity * 1e6 } do
	local text = string.lower(Format.Number(value))
	if string.find(text, "inf", 1, true) or string.find(text, "nan", 1, true) then
		noInf = false
		Mock.RealPrint("  Format.Number(" .. tostring(value) .. ") = " .. text)
	end
end
check("format: Format.Number never prints inf or nan", noInf)

------------------------------------------------------------------------ the tank (real EconomyService)
local normal = newPlayer("NormalTank", 1001)
local owner = newPlayer("InfiniteOwner", 1002)
datas[normal] = newData()
datas[owner] = newData({ InfiniteTank = true })
local EconomyService = require(Services.EconomyService)
Registry.EconomyService = EconomyService
EconomyService.Init()

local VALUE = 4 -- Volts per energy (a whole number, so sales compare exactly)
reset()
local added = EconomyService.AddEnergy(normal, capacity * 3, VALUE)
check("tank: a normal tank is capped at its capacity", added == capacity and datas[normal].Energy == capacity, added)
check("tank: a normal tank is then full", EconomyService.IsTankFull(datas[normal]))
check("tank: a full normal tank takes nothing more", EconomyService.AddEnergy(normal, 10, VALUE) == 0)

added = EconomyService.AddEnergy(owner, capacity * 3, VALUE)
check("tank: an Infinite Tank takes it all", added == capacity * 3 and datas[owner].Energy == capacity * 3, added)
check("tank: an Infinite Tank past a normal tank is not full", not EconomyService.IsTankFull(datas[owner]))
added = EconomyService.AddEnergy(owner, capacity * 50, VALUE)
check("tank: and keeps filling", added == capacity * 50 and datas[owner].Energy == capacity * 53, datas[owner].Energy)
check("tank: its worth counts every unit", datas[owner].TankValue == capacity * 53 * VALUE, datas[owner].TankValue)
check("tank: energy and worth replicate", count(replicated, "InfiniteOwner:Energy") >= 2 and count(replicated, "InfiniteOwner:TankValue") >= 2)
check("tank: energy and worth stay finite numbers (saved and replicated as is)", finite(datas[owner].Energy) and finite(datas[owner].TankValue))
check("tank: no tank-full message", count(notified, "full") == 0, table.concat(notified, " | "))

-- Selling: one big Infinite Tank pays exactly what the same energy sold a normal tank at a time pays
datas[normal] = newData()
datas[owner] = newData({ InfiniteTank = true })
local normalVolts = 0
for _ = 1, 5 do
	EconomyService.AddEnergy(normal, capacity, VALUE)
	normalVolts += EconomyService.Sell(normal, "Pad")
end
EconomyService.AddEnergy(owner, capacity * 5, VALUE)
local ownerVolts = EconomyService.Sell(owner, "Pad")
check("sell: five normal tanks and one 5x Infinite Tank pay the same", ownerVolts == normalVolts and ownerVolts > 0, ownerVolts .. " vs " .. normalVolts)
check("sell: the Infinite Tank is empty after selling", datas[owner].Energy == 0 and datas[owner].TankValue == 0)
check("sell: the Volts are the tank's worth x the Volts multiplier", ownerVolts == math.floor(capacity * 5 * VALUE * Formulas.VoltsMultiplier(datas[owner])), ownerVolts)

------------------------------------------------------------------------ Volts products and rewards (per full tank)
local RewardService = require(Services.RewardService)
Registry.RewardService = RewardService
local MonetizationService = require(Services.MonetizationService)
MonetizationService.Init()

-- The same mid-game player with and without the pass (and with a tank far past normal, which must not count)
local function pair()
	datas[normal] = newData()
	datas[owner] = newData({ InfiniteTank = true })
	datas[owner].Energy = capacity * 40
	datas[owner].TankValue = capacity * 40 * VALUE
end

Mock.IsStudio = true -- Volts products have Id 0: the Studio test purchase (DevGrant) grants them
local productCount = 0
for _, product in Monetization.SortedProducts() do
	if product.Kind == "Volts" then
		productCount += 1
		pair()
		local unit = Formulas.VoltsUnit(datas[normal])
		local normalReply = remotes.DevGrant.OnServerInvoke(normal, "Product", product.Key)
		local ownerReply = remotes.DevGrant.OnServerInvoke(owner, "Product", product.Key)
		local normalGain = datas[normal].Volts - 1000
		local ownerGain = datas[owner].Volts - 1000
		check("volts product " .. product.Key .. ": granted", normalReply.Ok and ownerReply.Ok, normalReply.Error or ownerReply.Error)
		check("volts product " .. product.Key .. ": the same with Infinite Tank", ownerGain == normalGain, ownerGain .. " vs " .. normalGain)
		check("volts product " .. product.Key .. ": Amount normal full tanks", normalGain == product.Amount * unit and finite(ownerGain), normalGain)
		check("volts product " .. product.Key .. ": doesn't touch the tank", datas[owner].Energy == capacity * 40)
	end
end
check("volts products: all checked", productCount >= 4, productCount)

local rewardCount = 0
local function checkReward(label, reward)
	if reward.Kind ~= "Volts" then
		return
	end
	rewardCount += 1
	pair()
	local normalText = RewardService.Grant(normal, reward)
	local ownerText = RewardService.Grant(owner, reward)
	local normalGain = datas[normal].Volts - 1000
	local ownerGain = datas[owner].Volts - 1000
	check("reward " .. label .. ": the same with Infinite Tank", ownerGain == normalGain and normalGain == reward.Amount * Formulas.VoltsUnit(datas[normal]), ownerGain .. " vs " .. normalGain)
	check("reward " .. label .. ": the same text", ownerText == normalText and not string.find(string.lower(ownerText), "inf", 1, true), ownerText)
end
for day, reward in Rewards.Daily do
	checkReward("daily " .. day, reward)
	if reward.Fallback then
		checkReward("daily " .. day .. " fallback", reward.Fallback)
	end
end
for index, reward in Rewards.Gifts do
	checkReward("gift " .. index, reward)
end
for code, reward in Rewards.Codes do
	checkReward("code " .. code, reward)
end
check("rewards: all checked", rewardCount >= 5, rewardCount)

------------------------------------------------------------------------ buying the pass (Id 0)
datas[normal] = newData()
reset()
Mock.IsStudio = false
local reply = remotes.DevGrant.OnServerInvoke(normal, "Pass", "InfiniteTank")
check("live server, Id 0: refused", reply.Ok == false and datas[normal].Passes.InfiniteTank == nil, reply.Error)
Mock.IsStudio = true
reply = remotes.DevGrant.OnServerInvoke(normal, "Pass", "InfiniteTank")
check("Studio, Id 0: simulated purchase works", reply.Ok == true, reply.Error)
check("Studio, Id 0: pass owned", datas[normal].Passes.InfiniteTank == true and MonetizationService.HasPass(normal, "InfiniteTank"))
check("Studio, Id 0: replicated", count(replicated, "NormalTank:Passes") == 1, table.concat(replicated, " "))
check("Studio, Id 0: thank-you toast", count(notified, "Thanks for buying Infinite Tank") == 1, table.concat(notified, " | "))
check("Studio, Id 0: purchase effect", count(effects, "NormalTank|Purchase|Infinite Tank") == 1, table.concat(effects, " "))
datas[normal].Energy = capacity
check("bought: a tank at the normal capacity is no longer full", not EconomyService.IsTankFull(datas[normal]))
check("bought: and keeps filling", EconomyService.AddEnergy(normal, capacity, VALUE) == capacity and datas[normal].Energy == capacity * 2)
Mock.IsStudio = false

Mock.RealPrint(string.format("InfiniteTank mock test: %d passed, %d failed", passes, failures))
if failures > 0 then
	error("mock test failed")
end
