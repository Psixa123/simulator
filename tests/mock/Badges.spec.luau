--!nocheck
-- Mock test for the Roblox badges: Shared/Config/Badges.luau and the real AchievementService watching a
-- stand-in DataService. Every badge's rule awards it exactly once when the data changes (also when the
-- data changes right after the replicate, like WeatherService's catch counter), badges with Id = 0 are
-- skipped (Studio prints them), saves that already qualify are awarded on join, owned badges are looked up
-- once per session, and failing Roblox calls never throw: they are retried later with a growing delay and
-- given up after a few tries.
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

------------------------------------------------------------------------ time: task.delay waits for flush()
local clock = 100
local timers = {} -- { At, Fn, Args }
task.delay = function(seconds, fn, ...)
	table.insert(timers, { At = clock + (seconds or 0), Fn = fn, Args = table.pack(...) })
end
-- Advances the clock and runs every timer that is due (timers added meanwhile too)
local function flush(seconds)
	clock += seconds or 0
	while true do
		local index = nil
		for i, timer in timers do
			if timer.At <= clock and (index == nil or timer.At < timers[index].At) then
				index = i
			end
		end
		if not index then
			return
		end
		local timer = table.remove(timers, index)
		timer.Fn(table.unpack(timer.Args, 1, timer.Args.n))
	end
end

------------------------------------------------------------------------ game tree
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Shared = Mock.Folder("Shared", ReplicatedStorage)
local Config = Mock.Folder("Config", Shared)
Mock.Module("Pets", Config, __sources.Pets)
Mock.Module("Badges", Config, __sources.Badges)
Players.PlayerRemoving = signal()

local Badges = require(Config.Badges)
local Pets = require(Config.Pets)

------------------------------------------------------------------------ stand-in DataService
local profiles = {} -- [Player] = data
local Registry = {}
Registry.DataService = {
	PlayerLoaded = signal(),
	Changed = signal(),
	Get = function(player)
		return profiles[player]
	end,
	Replicate = function(player, ...)
		for _, key in { ... } do
			Registry.DataService.Changed:Fire(player, key, profiles[player] and profiles[player][key])
		end
	end,
}

-- A brand-new save, as DataService's template makes it
local function newData()
	return {
		Volts = 0,
		TotalVolts = 0,
		Rebirths = 0,
		Zone = 1,
		Pets = {},
		NextPetId = 1,
		Index = {},
		Stats = { CellsCaught = 0, RareCaught = 0, EggsHatched = 0, MegaStorms = 0, Sells = 0, PlayTime = 0 },
	}
end

local nextUserId = 1000
local function join(name, data)
	nextUserId += 1
	local player = Instance.new("Player")
	player.Name = name
	player.UserId = nextUserId
	player.Parent = Players
	profiles[player] = data or newData()
	Registry.DataService.PlayerLoaded:Fire(player, profiles[player])
	return player
end
local function leave(player)
	Players.PlayerRemoving:Fire(player)
	player.Parent = nil
	profiles[player] = nil
end

------------------------------------------------------------------------ stand-in Roblox BadgeService
local Roblox = {
	Owned = {}, -- ["userId:badgeId"] = true
	HasCalls = {}, -- "userId:badgeId"
	AwardCalls = {}, -- "userId:badgeId"
	HasError = nil, -- error text for UserHasBadgeAsync
	AwardError = nil, -- error text for AwardBadgeAsync
	AwardResult = true, -- what a working AwardBadgeAsync returns
}
function Roblox:UserHasBadgeAsync(userId, badgeId)
	local key = userId .. ":" .. badgeId
	table.insert(self.HasCalls, key)
	if self.HasError then
		error(self.HasError)
	end
	return self.Owned[key] == true
end
function Roblox:AwardBadgeAsync(userId, badgeId)
	local key = userId .. ":" .. badgeId
	table.insert(self.AwardCalls, key)
	if self.AwardError then
		error(self.AwardError)
	end
	if self.AwardResult then
		self.Owned[key] = true
	end
	return self.AwardResult
end

local Services = Mock.Folder("Services", game:GetService("ServerScriptService"))
Mock.Module("Registry", Services, function()
	return Registry
end)
Mock.Module("AchievementService", Services, __sources.AchievementService)
local AchievementService = require(Services.AchievementService)
AchievementService.RobloxBadges = Roblox
AchievementService.Clock = function()
	return clock
end

-- Live badges: every badge gets a made-up Id (1001, 1002, ...) so the Roblox calls can be counted
local idOf, keyOf = {}, {}
local live = {}
for index, badge in Badges.List do
	local copy = table.clone(badge)
	copy.Id = 1000 + index
	idOf[badge.Key] = copy.Id
	keyOf[copy.Id] = badge.Key
	table.insert(live, copy)
end
AchievementService.Badges = live

-- Badge keys awarded to `player` since the AwardCalls list had `from` entries
local function awardedSince(player, from)
	local keys = {}
	for index = from + 1, #Roblox.AwardCalls do
		local userId, badgeId = string.match(Roblox.AwardCalls[index], "^(%d+):(%d+)$")
		if tonumber(userId) == player.UserId then
			table.insert(keys, keyOf[tonumber(badgeId)])
		end
	end
	table.sort(keys)
	return keys
end
local function reset()
	table.clear(Roblox.Owned)
	table.clear(Roblox.HasCalls)
	table.clear(Roblox.AwardCalls)
	Roblox.HasError, Roblox.AwardError, Roblox.AwardResult = nil, nil, true
	table.clear(Mock.Warnings)
	table.clear(Mock.Prints)
end

AchievementService.Init()

------------------------------------------------------------------------ config
check("config: 18 badges", #Badges.List == 18, #Badges.List)
local seen = {}
for _, badge in Badges.List do
	local key = badge.Key
	check("config: " .. tostring(key) .. " key is unique", type(key) == "string" and not seen[key])
	seen[key] = true
	check("config: " .. key .. " name fits Roblox (1-50 chars)", type(badge.Name) == "string" and #badge.Name >= 1 and #badge.Name <= 50, badge.Name)
	check("config: " .. key .. " has a short description", type(badge.Description) == "string" and #badge.Description >= 10 and #badge.Description <= 120, badge.Description)
	check("config: " .. key .. " Id is a number (0 until created)", type(badge.Id) == "number" and badge.Id >= 0, badge.Id)
	check("config: " .. key .. " icon path", badge.Icon == "assets/badges/" .. key .. ".png", badge.Icon)
	check("config: " .. key .. " ByKey", Badges.ByKey[key] == badge)
end
check("config: Qualifies never throws on junk data", pcall(function()
	for _, badge in Badges.List do
		Badges.Qualifies(badge, nil)
		Badges.Qualifies(badge, { Stats = "x", Index = 5, Pets = "y" })
	end
end))

------------------------------------------------------------------------ every rule, once, in play order
reset()
local player = join("Newbie")
check("join: nothing before the deferred check runs", #Roblox.AwardCalls == 0, #Roblox.AwardCalls)
flush()
check("join: only Welcome", table.concat(awardedSince(player, 0), ",") == "Welcome", table.concat(awardedSince(player, 0), ","))
check("join: owned looked up first", Roblox.HasCalls[1] == player.UserId .. ":" .. idOf.Welcome, Roblox.HasCalls[1])
check("join: the award is printed", count(Mock.Prints, "earned the 'Welcome, Storm Chaser!' badge") == 1, table.concat(Mock.Prints, " | "))

local data = profiles[player]
local STEPS = {
	{ "FirstCatch", function()
		-- like WeatherService: the energy is replicated first, the catch counter goes up right after
		Registry.DataService.Replicate(player, "Energy")
		data.Stats.CellsCaught += 1
	end },
	{ "RareCatch", function()
		Registry.DataService.Replicate(player, "Energy")
		data.Stats.CellsCaught += 1
		data.Stats.RareCaught += 1
	end },
	{ "StormChaser", function()
		data.Stats.CellsCaught = 1000
		Registry.DataService.Replicate(player, "Energy")
	end },
	{ "Zone_Thunder", function()
		data.Zone = 2
		Registry.DataService.Replicate(player, "Volts", "Zone")
	end },
	{ "FirstHatch", function()
		table.insert(data.Pets, { Uid = "p1", Id = "Static", Golden = false, Rainbow = false })
		data.Index.Static = true
		data.Stats.EggsHatched += 1
		Registry.DataService.Replicate(player, "Volts", "Index")
	end },
	{ "Zone_Dunes", function()
		data.Zone = 3
		Registry.DataService.Replicate(player, "Volts", "Zone")
	end },
	{ "LegendaryPet", function()
		table.insert(data.Pets, { Uid = "p2", Id = "MirageDjinn", Golden = false, Rainbow = false })
		data.Index.MirageDjinn = true
		data.Stats.EggsHatched += 1
		Registry.DataService.Replicate(player, "Volts", "Index")
	end },
	{ "Millionaire", function()
		data.TotalVolts = 1e6
		Registry.DataService.Replicate(player, "Volts", "TotalVolts")
	end },
	{ "GoldenPet", function()
		table.insert(data.Pets, { Uid = "p3", Id = "Static", Golden = true, Rainbow = false })
		Registry.DataService.Replicate(player, "Pets")
	end },
	{ "MegaStorm", function()
		-- like MegaStormService: the Volts reward is replicated before the counter goes up
		Registry.DataService.Replicate(player, "Volts", "TotalVolts")
		data.Stats.MegaStorms += 1
	end },
	{ "StormChampion", function()
		Registry.DataService.Replicate(player, "Volts", "TotalVolts")
		data.Stats.MegaStorms += 1
		table.insert(data.Pets, { Uid = "p4", Id = "TempestTitan", Golden = false, Rainbow = false })
		data.Index.TempestTitan = true
		Registry.DataService.Replicate(player, "Index", "Pets")
	end },
	{ "Zone_Frost", function()
		data.Zone = 4
		Registry.DataService.Replicate(player, "Volts", "Zone")
	end },
	{ "RainbowPet", function()
		table.insert(data.Pets, { Uid = "p5", Id = "Static", Golden = false, Rainbow = true })
		Registry.DataService.Replicate(player, "Pets")
	end },
	{ "ClimateShift", function()
		data.Rebirths = 1
		Registry.DataService.Replicate(player, "Volts", "Energy", "TankValue", "Upgrades", "Rebirths")
	end },
	{ "Zone_Volcano", function()
		data.Zone = 5
		Registry.DataService.Replicate(player, "Volts", "Zone")
	end },
	{ "Zone_Sky", function()
		data.Zone = 6
		Registry.DataService.Replicate(player, "Volts", "Zone")
	end },
	{ "SecretPet", function()
		table.insert(data.Pets, { Uid = "p6", Id = "EyeOfTheStorm", Golden = false, Rainbow = false })
		data.Index.EyeOfTheStorm = true
		data.Stats.EggsHatched += 1
		Registry.DataService.Replicate(player, "Volts", "Index")
	end },
}
local covered = { Welcome = true }
for _, step in STEPS do
	local key, change = step[1], step[2]
	local before = #Roblox.AwardCalls
	change()
	flush(1)
	local got = table.concat(awardedSince(player, before), ",")
	check("rule: " .. key .. " awarded once, alone", got == key, got)
	covered[key] = true
end
for _, badge in Badges.List do
	check("rule: " .. badge.Key .. " covered by the test", covered[badge.Key] == true)
end
check("rule: 18 awards in all", #Roblox.AwardCalls == 18, #Roblox.AwardCalls)
check("rule: one ownership lookup per badge", #Roblox.HasCalls == 18, #Roblox.HasCalls)

-- Nothing is awarded twice, however often the data changes
local before = #Roblox.AwardCalls
for _ = 1, 5 do
	Registry.DataService.Replicate(player, "Volts", "Pets", "Index", "Zone")
	flush(1)
end
flush(60)
check("once: no award repeats", #Roblox.AwardCalls == before, #Roblox.AwardCalls - before)
check("once: no lookup repeats", #Roblox.HasCalls == 18, #Roblox.HasCalls)

-- The lobby shop's exclusive (Source "Lobby shop") is not a Mega Storm win; a Legendary-less index is no luck
reset()
local shopper = join("Shopper")
flush()
local shopData = profiles[shopper]
shopData.Index.AuroraGryphon = true
table.insert(shopData.Pets, { Uid = "p1", Id = "AuroraGryphon", Golden = false, Rainbow = false })
shopData.Index.Sunbeam = true
Registry.DataService.Replicate(shopper, "Index", "Pets")
flush(1)
check("rule: shop pet / daily pet win nothing", table.concat(awardedSince(shopper, 0), ",") == "Welcome", table.concat(awardedSince(shopper, 0), ","))
check("rule: Mega Storm exclusives have a 'Mega Storm' Source", Badges.Qualifies(Badges.ByKey.StormChampion, { Index = { RainbowRoc = true } }))
check("rule: Legendary is egg-only", Pets.Pets.BreezeKing.Rarity == "Legendary" and Badges.Qualifies(Badges.ByKey.LegendaryPet, { Index = { BreezeKing = true } }))
leave(shopper)

------------------------------------------------------------------------ bursts are checked once
reset()
local checks = 0
local realCheck = AchievementService.Check
AchievementService.Check = function(...)
	checks += 1
	return realCheck(...)
end
local busy = join("Busy")
flush()
checks = 0
for _ = 1, 50 do
	Registry.DataService.Replicate(busy, "Energy", "TankValue")
end
flush(0)
check("burst: waits half a second after the last check", checks == 0, checks)
flush(0.5)
check("burst: 50 changes in one moment are one check", checks == 1, checks)
for _ = 1, 20 do
	Registry.DataService.Replicate(busy, "Energy")
	flush(0.1)
end
flush(1)
check("burst: at most one check per half second", checks >= 3 and checks <= 6, checks)
AchievementService.Check = realCheck
leave(busy)

------------------------------------------------------------------------ retroactive awards on join
reset()
local veteranData = newData()
veteranData.Zone = 4
veteranData.Rebirths = 3
veteranData.TotalVolts = 5e7
veteranData.Stats.CellsCaught = 2500
veteranData.Stats.EggsHatched = 40
veteranData.Stats.MegaStorms = 2
veteranData.Index = { Puffling = true, BreezeKing = true }
veteranData.Pets = { { Uid = "p1", Id = "Puffling", Golden = true, Rainbow = false } }
local veteran = join("Veteran", veteranData)
local expected = { "ClimateShift", "FirstCatch", "FirstHatch", "GoldenPet", "LegendaryPet", "MegaStorm", "Millionaire", "StormChaser", "Welcome", "Zone_Dunes", "Zone_Frost", "Zone_Thunder" }
table.sort(expected)
flush()
check("retroactive: an old save gets every badge it qualifies for on join", table.concat(awardedSince(veteran, 0), ",") == table.concat(expected, ","), table.concat(awardedSince(veteran, 0), ","))
leave(veteran)

-- Badges the player already owns are looked up once and never awarded again
reset()
local ownerData = newData()
ownerData.Zone = 2
local returning = nil
do
	-- the next join gets UserId nextUserId + 1: they already own Welcome and Thunder Valley
	local userId = nextUserId + 1
	Roblox.Owned[userId .. ":" .. idOf.Welcome] = true
	Roblox.Owned[userId .. ":" .. idOf.Zone_Thunder] = true
end
returning = join("Returning", ownerData)
flush()
check("owned: nothing awarded again", #Roblox.AwardCalls == 0, table.concat(Roblox.AwardCalls, " "))
check("owned: looked up once each", #Roblox.HasCalls == 2, #Roblox.HasCalls)
Registry.DataService.Replicate(returning, "Zone")
flush(30)
check("owned: the answer is cached for the session", #Roblox.HasCalls == 2, #Roblox.HasCalls)
leave(returning)

------------------------------------------------------------------------ Id = 0 is skipped
reset()
AchievementService.Badges = Badges.List -- the real config: every Id is still 0
local zeroOk = true
for _, badge in Badges.List do
	zeroOk = zeroOk and badge.Id == 0
end
Mock.IsStudio = true
local tester = join("Tester", veteranData)
flush()
check("Id 0: no Roblox calls", #Roblox.HasCalls == 0 and #Roblox.AwardCalls == 0, #Roblox.HasCalls + #Roblox.AwardCalls)
if zeroOk then
	check("Id 0, Studio: prints each badge it would award", count(Mock.Prints, "would earn") == #expected, table.concat(Mock.Prints, " | "))
end
check("Id 0, Studio: names the badge", count(Mock.Prints, "Tester would earn 'Welcome, Storm Chaser!' (no badge Id yet)") == 1, table.concat(Mock.Prints, " | "))
Registry.DataService.Replicate(tester, "Zone")
flush(30)
check("Id 0, Studio: printed once per session", count(Mock.Prints, "Tester would earn 'Welcome") == 1, count(Mock.Prints, "Tester would earn 'Welcome"))
leave(tester)
Mock.IsStudio = false
table.clear(Mock.Prints)
local liveTester = join("LiveTester", veteranData)
flush()
check("Id 0, live server: silent and no calls", #Mock.Prints == 0 and #Roblox.HasCalls == 0 and #Roblox.AwardCalls == 0, table.concat(Mock.Prints, " | "))
leave(liveTester)
-- A mixed list: only the badges that have an Id are awarded
local mixed = {}
for _, badge in live do
	local copy = table.clone(badge)
	if copy.Key ~= "Welcome" then
		copy.Id = 0
	end
	table.insert(mixed, copy)
end
AchievementService.Badges = mixed
local mixedPlayer = join("Mixed", veteranData)
flush()
check("Id 0: only badges with an Id reach Roblox", table.concat(awardedSince(mixedPlayer, 0), ",") == "Welcome" and #Roblox.HasCalls == 1, table.concat(Roblox.HasCalls, " "))
leave(mixedPlayer)
AchievementService.Badges = live

------------------------------------------------------------------------ failing Roblox calls never throw
-- UserHasBadgeAsync errors: retried after the backoff, then awarded once it works
reset()
Roblox.HasError = "HTTP 503 (Service Unavailable)"
local unlucky
local ok, err = pcall(function()
	unlucky = join("Unlucky")
	flush()
end)
check("fail: an erroring lookup doesn't throw", ok, err)
check("fail: nothing awarded yet", #Roblox.AwardCalls == 0, #Roblox.AwardCalls)
check("fail: no warning for one failure", #Mock.Warnings == 0, table.concat(Mock.Warnings, " | "))
local lookups = #Roblox.HasCalls
Registry.DataService.Replicate(unlucky, "Volts")
flush(5)
check("fail: no retry before the backoff", #Roblox.HasCalls == lookups, #Roblox.HasCalls)
Roblox.HasError = nil
flush(15)
check("fail: retried after the backoff and awarded", table.concat(awardedSince(unlucky, 0), ",") == "Welcome", table.concat(awardedSince(unlucky, 0), ","))
leave(unlucky)

-- AwardBadgeAsync errors (and returns false): the delay doubles, and after 5 failures it gives up for the session
reset()
Roblox.AwardError = "Badge award limit reached"
local cursed
ok, err = pcall(function()
	cursed = join("Cursed")
	flush()
end)
check("fail: an erroring award doesn't throw", ok, err)
check("fail: one attempt so far", #Roblox.AwardCalls == 1, #Roblox.AwardCalls)
flush(15)
check("fail: second attempt after 15 s", #Roblox.AwardCalls == 2, #Roblox.AwardCalls)
flush(15)
check("fail: the delay doubles (no third attempt at +15 s)", #Roblox.AwardCalls == 2, #Roblox.AwardCalls)
flush(15)
check("fail: third attempt after 30 s", #Roblox.AwardCalls == 3, #Roblox.AwardCalls)
Roblox.AwardError = nil
Roblox.AwardResult = false -- AwardBadgeAsync returning false counts as a failure too
flush(60)
flush(120)
check("fail: five attempts in all", #Roblox.AwardCalls == 5, #Roblox.AwardCalls)
check("fail: gave up with one warning", count(Mock.Warnings, "Giving up on 'Welcome' for Cursed") == 1, table.concat(Mock.Warnings, " | "))
check("fail: the lookup was cached through the retries", #Roblox.HasCalls == 1, #Roblox.HasCalls)
Roblox.AwardResult = true
for _ = 1, 3 do
	Registry.DataService.Replicate(cursed, "Volts")
	flush(400)
end
check("fail: no more attempts this session", #Roblox.AwardCalls == 5, #Roblox.AwardCalls)
leave(cursed)
local back = join("Cursed2")
flush()
check("fail: a new session tries again", table.concat(awardedSince(back, 0), ",") == "Welcome", table.concat(awardedSince(back, 0), ","))
leave(back)

-- A rule that throws is skipped without breaking the other badges
reset()
local broken = table.clone(live)
broken[2] = table.clone(live[2])
broken[2].Rule = { Kind = "Stat", Stat = "CellsCaught" } -- Min missing: comparing with nil errors
AchievementService.Badges = broken
local odd = newData()
odd.Stats.CellsCaught = 5
local oddPlayer
ok, err = pcall(function()
	oddPlayer = join("Odd", odd)
	flush()
end)
check("fail: a broken rule doesn't throw", ok, err)
check("fail: the other badges still work", table.concat(awardedSince(oddPlayer, 0), ",") == "Welcome", table.concat(awardedSince(oddPlayer, 0), ","))
leave(oddPlayer)
AchievementService.Badges = live

------------------------------------------------------------------------ players who leave
reset()
local gone = join("Gone")
leave(gone)
ok, err = pcall(function()
	Registry.DataService.Changed:Fire(gone, "Volts", 0)
	flush(1)
end)
check("leave: a change after leaving is ignored", ok and #Roblox.HasCalls == 0 and #Roblox.AwardCalls == 0, err)
local nodata = Instance.new("Player")
nodata.Name = "Loading"
nodata.UserId = 999
nodata.Parent = Players
ok, err = pcall(function()
	AchievementService.Check(nodata)
	Registry.DataService.Changed:Fire(nodata, "Volts", 0)
	flush(1)
end)
check("leave: no data yet, nothing happens", ok and #Roblox.HasCalls == 0, err)

Mock.RealPrint(string.format("Badges mock test: %d passed, %d failed", passes, failures))
if failures > 0 then
	error("mock test failed")
end
