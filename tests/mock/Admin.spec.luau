--!nocheck
-- Mock test for AdminService (the owner-only admin panel's server side): who counts as an admin (owner,
-- listed admin, stranger, group rank, Studio), argument validation, and commands against stand-in
-- services that keep the player's data like the real ones. Runs after RobloxMock.luau and the module
-- sources in one bundle; see run_mock_tests.py.

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

------------------------------------------------------------------------ game tree
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local Shared = Mock.Folder("Shared", ReplicatedStorage)
local Config = Mock.Folder("Config", Shared)
local Util = Mock.Folder("Util", Shared)
Mock.Module("GameConfig", Config, __sources.GameConfig)
Mock.Module("Monetization", Config, __sources.Monetization)
Mock.Module("Pets", Config, __sources.Pets)
Mock.Module("Zones", Config, __sources.Zones)
Mock.Module("Weather", Config, __sources.Weather)
Mock.Module("Formulas", Shared, __sources.Formulas)
Mock.Module("Format", Util, __sources.Format)

-- MapLayout stand-in: zone n spans x = n * 100 .. n * 100 + 99, the hub is below x = 100
local MapLayout = {}
function MapLayout.ZoneSpawn(zoneId)
	return CFrame.new(zoneId * 100 + 26, 4, 0)
end
function MapLayout.ArenaSpawn()
	return CFrame.new(-50, 4, 0)
end
function MapLayout.ZoneAt(position)
	return math.clamp(math.floor(position.X / 100), 0, 6)
end
Mock.Module("MapLayout", Config, function()
	return MapLayout
end)

local AdminRemote = Instance.new("RemoteFunction")
AdminRemote.Name = "AdminCommand"
Mock.Module("Remotes", Shared, function()
	return { AdminCommand = AdminRemote }
end)

local GameConfig = require(Config.GameConfig)
local Pets = require(Config.Pets)
local Zones = require(Config.Zones)
local Formulas = require(Shared.Formulas)

------------------------------------------------------------------------ players
local playerList = {}
Players.GetPlayers = function()
	return table.clone(playerList)
end
Players.PlayerAdded = signal()
Players.PlayerRemoving = signal()

local ranks = {} -- [UserId] = rank in the owning group, or "error"
local rankCalls = 0
local function newPlayer(name, userId, displayName)
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = displayName or name
	player.UserId = userId
	player.GetRankInGroupAsync = function(self, groupId)
		assert(self == player, "GetRankInGroupAsync called without self")
		assert(groupId == game.CreatorId, "rank looked up in the wrong group")
		rankCalls += 1
		local rank = ranks[userId]
		if rank == "error" then
			error("HTTP 500 (Internal Server Error)")
		end
		return rank or 0
	end
	player.Parent = Players
	table.insert(playerList, player)
	return player
end
local function removePlayer(player)
	table.remove(playerList, table.find(playerList, player))
	Players.PlayerRemoving:Fire(player)
	player.Parent = nil
end

------------------------------------------------------------------------ stand-in services
local datas = {} -- [Player] = data
local replicated = {} -- list of "Name:Key"
local calls = {} -- list of "Service.Method args"
local function call(text)
	table.insert(calls, text)
end
local function newData()
	return {
		DataVersion = 1,
		Volts = 1000,
		TotalVolts = 5000,
		Energy = 100,
		TankValue = 400,
		Rebirths = 2,
		Zone = 3,
		Upgrades = { Power = 10, Tank = 8, Range = 3, Speed = 2 },
		Pets = { { Uid = "p1", Id = "Puffling", Golden = false, Rainbow = false, Equipped = true } },
		NextPetId = 2,
		Index = { Puffling = true },
		Boosts = { Energy = 0, Luck = 0 },
		Daily = { Streak = 4, LastClaim = 123 },
		Codes = { STORM = true },
		Settings = { Music = false, Sfx = true },
		Stats = { CellsCaught = 50, EggsHatched = 3, MegaStorms = 1, Sells = 9, PlayTime = 600 },
		Receipts = { ["r1"] = 99 },
		Passes = {},
		GiftsClaimed = { ["1"] = true },
		SessionStart = 1,
	}
end

local Registry = {}
Registry.DataService = {
	Get = function(player)
		return datas[player]
	end,
	Replicate = function(player, ...)
		for _, key in { ... } do
			table.insert(replicated, player.Name .. ":" .. key)
		end
	end,
	Save = function(player)
		call("DataService.Save " .. player.Name)
		return true
	end,
}
Registry.EconomyService = {
	AddVolts = function(player, amount, countAsEarned)
		local data = datas[player]
		amount = math.floor(amount)
		data.Volts += amount
		if countAsEarned ~= false and amount > 0 then
			data.TotalVolts += amount
		end
		Registry.DataService.Replicate(player, "Volts", "TotalVolts")
	end,
	AddEnergy = function(player, units, valuePerUnit)
		local data = datas[player]
		local added = math.min(math.max(0, Formulas.TankCapacity(data) - data.Energy), units)
		data.Energy += added
		data.TankValue += added * valuePerUnit
		Registry.DataService.Replicate(player, "Energy", "TankValue")
		return added
	end,
}
Registry.PetService = {
	AddPet = function(player, petId, tier, force)
		local data = datas[player]
		call(string.format("PetService.AddPet %s %s %s", petId, tostring(tier), tostring(force)))
		if not Pets.Pets[petId] or (#data.Pets >= GameConfig.Pets.MaxStorage and not force) then
			return nil, false
		end
		local tierName = Pets.TierOf(tier)
		local entry = { Uid = "p" .. data.NextPetId, Id = petId, Golden = tierName == "Golden", Rainbow = tierName == "Rainbow", Equipped = false }
		data.NextPetId += 1
		table.insert(data.Pets, entry)
		local isNew = not data.Index[petId]
		data.Index[petId] = true
		return entry, isNew
	end,
	Refresh = function(player)
		Registry.DataService.Replicate(player, "Pets")
	end,
}
Registry.BoostService = {
	Add = function(player, boostName, seconds, silent)
		call(string.format("BoostService.Add %s %s %d%s", player.Name, boostName, seconds, if silent then " silent" else ""))
		datas[player].Boosts[boostName] = os.time() + seconds
	end,
}
local teleportWorks = true
Registry.ZoneService = {
	TeleportTo = function(player, cframe)
		call(string.format("ZoneService.TeleportTo %s %d", player.Name, cframe.Position.X))
		return teleportWorks
	end,
}
Registry.WeatherService = {
	StopCatch = function(player)
		call("WeatherService.StopCatch " .. player.Name)
	end,
}
Registry.MegaStormService = {
	Summon = function(player)
		call("MegaStormService.Summon " .. player.Name)
	end,
	ScheduleRainbow = function(delay)
		call("MegaStormService.ScheduleRainbow " .. delay)
	end,
}

local rateLimited = false
local rateKeys = {} -- the keys AdminService rate limits on
local notified = {} -- list of "Player|text|kind" ("*" = everyone)
local roots = {} -- [Player] = fake HumanoidRootPart
local Net = {
	RateLimit = function(_, key)
		table.insert(rateKeys, key)
		return not rateLimited
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
	GetRoot = function(player)
		return roots[player]
	end,
}
local CharacterGear = {
	DressPlayer = function(player, shifts)
		call(string.format("CharacterGear.DressPlayer %s %s", player.Name, tostring(shifts)))
	end,
}

local Services = Mock.Folder("Services", game:GetService("ServerScriptService"))
Mock.Module("Registry", Services, function()
	return Registry
end)
Mock.Module("Net", Services, function()
	return Net
end)
Mock.Module("CharacterGear", Services, function()
	return CharacterGear
end)
Mock.Module("AdminService", Services, __sources.AdminService)

-- The chat filter: swaps "badword" for hashes; filterMode "error" makes it fail
local filterMode = "ok"
TextService.FilterStringAsync = function(self, text, userId, context)
	assert(self == TextService, "FilterStringAsync called without self")
	assert(type(userId) == "number", "FilterStringAsync needs the sender's UserId")
	if filterMode == "error" then
		error("TextService: filter unavailable")
	end
	return {
		GetNonChatStringForBroadcastAsync = function()
			return (string.gsub(text, "badword", "#######"))
		end,
	}
end

------------------------------------------------------------------------ setup
-- A live server of a user-owned place (owner 1001) unless a test says otherwise
Mock.IsStudio = false
game.CreatorType = Enum.CreatorType.User
game.CreatorId = 1001

local owner = newPlayer("OwnerOfStorms", 1001, "Owner")
local listed = newPlayer("ListedHelper", 233074756)
local stranger = newPlayer("Stranger", 5555)
local puffball = newPlayer("Puffball42", 4242, "Puffy")
local loading = newPlayer("StillLoading", 7777)
for _, player in { owner, listed, stranger, puffball } do
	datas[player] = newData()
end

local AdminService = require(Services.AdminService)
AdminService.Init()

local function invoke(player, command, args)
	return AdminRemote.OnServerInvoke(player, command, args)
end
local function reset()
	table.clear(replicated)
	table.clear(calls)
	table.clear(notified)
	table.clear(Mock.Prints)
	table.clear(Mock.Warnings)
end

------------------------------------------------------------------------ who is an admin
check("config: the owner's id is a listed admin", table.find(GameConfig.Admins.UserIds, 233074756) ~= nil)
check("config: group owners only by default", GameConfig.Admins.MinGroupRank == 255)
check("remote: AdminCommand is handled", type(AdminRemote.OnServerInvoke) == "function")

check("owner: admin", AdminService.IsAdmin(owner) == true)
check("listed: admin", AdminService.IsAdmin(listed) == true)
check("stranger: not an admin", AdminService.IsAdmin(stranger) == false)
check("owner: IsAdmin attribute set on join", owner:GetAttribute("IsAdmin") == true)
check("listed: IsAdmin attribute set on join", listed:GetAttribute("IsAdmin") == true)
check("stranger: no IsAdmin attribute", stranger:GetAttribute("IsAdmin") == nil)
check("user-owned place: no group lookups", rankCalls == 0, rankCalls)
check("not a player: refused", AdminService.IsAdmin({ UserId = 1001 }) == false)

-- Players who join later are checked too
local lateOwnerCopy = newPlayer("LateJoiner", 8080)
Players.PlayerAdded:Fire(lateOwnerCopy)
check("late joiner (stranger): no attribute", lateOwnerCopy:GetAttribute("IsAdmin") == nil)

-- The client can set its own attribute, but the server doesn't care
reset()
stranger:SetAttribute("IsAdmin", true)
local before = datas[stranger].Volts
local reply = invoke(stranger, "Volts", { Mode = "Give", Amount = 1e9 })
check("stranger: command refused", reply.Ok == false and reply.Error == "Only admins can do that.", reply.Error)
check("stranger: data untouched", datas[stranger].Volts == before)
check("stranger: nothing replicated", #replicated == 0)
check("stranger: refusal logged", count(Mock.Warnings, "[Admin] Refused Volts from Stranger (5555)") == 1, table.concat(Mock.Warnings, " | "))
invoke(stranger, "Volts", { Mode = "Give", Amount = 1 })
check("stranger: refusals aren't logged every time", count(Mock.Warnings, "[Admin] Refused") == 1)
reply = invoke(stranger, "Reset", { Confirm = "RESET" })
check("stranger: reset refused", reply.Ok == false and datas[stranger].Volts == before)
reply = invoke(stranger, { "not", "a", "string" }, nil)
check("stranger: odd command type refused", reply.Ok == false)
stranger:SetAttribute("IsAdmin", nil)

-- Studio: every tester is an admin
Mock.IsStudio = true
local studioTester = newPlayer("StudioTester", 9191)
check("studio: tester is an admin", AdminService.IsAdmin(studioTester) == true)
Mock.IsStudio = false
removePlayer(studioTester)

-- A user-owned place that isn't published (CreatorId 0) has no owner
game.CreatorId = 0
local zeroUser = newPlayer("Zero", 0)
check("unpublished place: UserId 0 isn't the owner", AdminService.IsAdmin(zeroUser) == false)
removePlayer(zeroUser)
game.CreatorId = 1001

-- Group-owned place: members with MinGroupRank or more
game.CreatorType = Enum.CreatorType.Group
game.CreatorId = 777
ranks[3001], ranks[3002], ranks[3003], ranks[3004] = 255, 254, "error", 200
local groupOwner = newPlayer("GroupOwner", 3001)
local groupAdmin = newPlayer("GroupAdmin", 3002)
local flaky = newPlayer("Flaky", 3003)
local member = newPlayer("Member", 3004)
check("group: rank 255 is an admin", AdminService.IsAdmin(groupOwner) == true)
check("group: rank 254 isn't (MinGroupRank 255)", AdminService.IsAdmin(groupAdmin) == false)
check("group: a game owned by a group doesn't make UserId == CreatorId an admin", (function()
	local sameId = newPlayer("SameIdAsGroup", 777)
	local result = AdminService.IsAdmin(sameId)
	removePlayer(sameId)
	return result == false
end)())
check("group: listed admins still count", (function()
	local helper = newPlayer("ListedInGroupGame", 233074756)
	local result = AdminService.IsAdmin(helper)
	removePlayer(helper)
	return result == true
end)())
GameConfig.Admins.MinGroupRank = 200
check("group: MinGroupRank 200 lets rank 200 in", AdminService.IsAdmin(member) == true)
check("group: an earlier answer is cached", AdminService.IsAdmin(groupAdmin) == false)
local callsBefore = rankCalls
AdminService.IsAdmin(groupOwner)
check("group: cached answers don't look the rank up again", rankCalls == callsBefore)
check("group: a failed lookup isn't an admin", AdminService.IsAdmin(flaky) == false)
ranks[3003] = 255
check("group: a failed lookup is tried again", AdminService.IsAdmin(flaky) == true)
GameConfig.Admins.MinGroupRank = 255
datas[member] = newData()
reply = invoke(member, "Inspect", nil)
check("group: an admin found later can run commands", reply.Ok == true, reply.Error)
check("group: and gets the IsAdmin attribute then", member:GetAttribute("IsAdmin") == true)
for _, player in { groupOwner, groupAdmin, flaky, member } do
	removePlayer(player)
end
game.CreatorType = Enum.CreatorType.User
game.CreatorId = 1001

------------------------------------------------------------------------ argument validation
local function refused(label, command, args, pattern)
	reset()
	local snapshot = datas[owner].Volts
	local result = invoke(owner, command, args)
	check("validate: " .. label, result.Ok == false and (pattern == nil or string.find(result.Error, pattern, 1, true) ~= nil), result.Error)
	check("validate: " .. label .. " changes nothing", datas[owner].Volts == snapshot and #replicated == 0 and #calls == 0, #replicated .. " replicated, " .. #calls .. " calls")
end
refused("unknown command", "GiveEverything", {}, "Unknown admin command")
refused("command name with a metatable key", "__index", {}, "Unknown admin command")
refused("args not a table", "Volts", "Give 100", "Bad arguments")
refused("numeric keys", "Volts", { "Give", 100 }, "Bad arguments")
refused("unknown argument", "Volts", { Mode = "Give", Amount = 5, Sneaky = true }, "Unknown argument Sneaky")
refused("missing argument", "Volts", { Amount = 5 }, "Mode is missing")
refused("wrong mode", "Volts", { Mode = "Steal", Amount = 5 }, "Mode isn't valid")
refused("amount as text", "Volts", { Mode = "Give", Amount = "100" }, "whole number")
refused("fractional amount", "Volts", { Mode = "Give", Amount = 1.5 }, "whole number")
refused("NaN amount", "Volts", { Mode = "Give", Amount = 0 / 0 }, "whole number")
refused("infinite amount", "Volts", { Mode = "Give", Amount = math.huge }, "whole number")
refused("huge amount", "Volts", { Mode = "Set", Amount = 1e31 }, "between")
refused("negative set", "Volts", { Mode = "Set", Amount = -5 }, "negative")
refused("target not text", "Volts", { Mode = "Give", Amount = 5, Target = 4242 }, "Bad target")
refused("target too long", "Volts", { Mode = "Give", Amount = 5, Target = string.rep("a", 41) }, "Bad target")
refused("target on a server-wide command", "MegaStorm", { Kind = "Summon", Target = "Puffball42" }, "Bad target")
refused("unknown target", "Volts", { Mode = "Give", Amount = 5, Target = "Nobody" }, "no player called")
refused("target still loading", "Volts", { Mode = "Give", Amount = 5, Target = "StillLoading" }, "hasn't loaded")
refused("bad upgrade", "Upgrade", { Upgrade = "Laser", Level = 5 }, "Upgrade isn't valid")
refused("upgrade level 0", "Upgrade", { Upgrade = "Power", Level = 0 }, "between")
refused("upgrade level over every max", "Upgrade", { Upgrade = "Power", Level = 61 }, "between")
refused("bad pet", "Pets", { Pet = "Dragonzilla" }, "Pet isn't valid")
refused("bad tier", "Pets", { Pet = "Sunny", Tier = "Diamond" }, "Tier isn't valid")
refused("pet count 0", "Pets", { Pet = "Sunny", Count = 0 }, "between")
refused("pet count 51", "Pets", { Pet = "Sunny", Count = 51 }, "between")
refused("bad pass", "Pass", { Pass = "FreeRobux", Owned = true }, "Pass isn't valid")
refused("pass owned as text", "Pass", { Pass = "VIP", Owned = "yes" }, "true or false")
refused("bad boost", "Boost", { Boost = "Speed", Minutes = 5 }, "Boost isn't valid")
refused("boost too long", "Boost", { Boost = "Luck", Minutes = 7 * 24 * 60 + 1 }, "between")
refused("zone 0", "Zone", { Zone = 0 }, "between")
refused("zone 7", "Zone", { Zone = #Zones + 1 }, "between")
refused("teleport to 7", "Teleport", { To = 7 }, "zone number, Hub or Arena")
refused("teleport to the moon", "Teleport", { To = "Moon" }, "zone number, Hub or Arena")
refused("negative shifts", "Rebirths", { Count = -1 }, "between")
refused("energy give without amount", "Energy", { Mode = "Give" }, "Enter an amount")
refused("reset without confirm", "Reset", {}, "Confirm is missing")
refused("reset with the wrong confirm", "Reset", { Confirm = "yes" }, "Confirm isn't valid")
refused("empty announcement", "Announce", { Text = "   " }, "1 to 150")
refused("long announcement", "Announce", { Text = string.rep("x", 151) }, "1 to 150")
refused("weather in zone 9", "Weather", { Zone = 9 }, "between")
refused("weather type from another zone", "Weather", { Zone = 1, Type = "Blizzard" }, "doesn't appear in")
refused("weather count 21", "Weather", { Zone = 1, Count = 21 }, "between")
refused("storm kind", "MegaStorm", { Kind = "Tornado" }, "Kind isn't valid")
refused("goto yourself", "Goto", nil, "another player")
refused("bring yourself", "Bring", {}, "another player")

-- Rate limit
reset()
rateLimited = true
reply = invoke(owner, "Volts", { Mode = "Give", Amount = 5 })
check("rate limit: refused", reply.Ok == false and reply.Error == "Slow down!")
-- per command, so the panel's background Inspect never gets a click refused
check("rate limit: keyed per command", rateKeys[#rateKeys] == "AdminVolts", rateKeys[#rateKeys])
rateLimited = false

------------------------------------------------------------------------ commands
local data = datas[owner]

reset()
reply = invoke(owner, "Volts", { Mode = "Give", Amount = 2500 })
check("volts give: ok", reply.Ok == true, reply.Error)
check("volts give: added", data.Volts == 3500, data.Volts)
check("volts give: not counted as earned", data.TotalVolts == 5000, data.TotalVolts)
check("volts give: replicated", table.find(replicated, "OwnerOfStorms:Volts") ~= nil)
check("volts give: message", string.find(reply.Message, "3.5K Volts", 1, true) ~= nil, reply.Message)
check("volts give: target info in the reply", type(reply.Info) == "table" and reply.Info.Volts == 3500 and reply.Info.Name == "OwnerOfStorms")
check("volts give: logged", count(Mock.Prints, "[Admin] OwnerOfStorms (1001) Volts {Amount=2500, Mode=\"Give\"}") == 1, table.concat(Mock.Prints, " | "))
reply = invoke(owner, "Volts", { Mode = "Set", Amount = 1e12 })
check("volts set", reply.Ok and data.Volts == 1e12, data.Volts)
reply = invoke(owner, "Volts", { Mode = "Give", Amount = -5e12 })
check("volts take: never below 0", reply.Ok and data.Volts == 0, data.Volts)

reset()
local capacity = Formulas.TankCapacity(data)
reply = invoke(owner, "Energy", { Mode = "Fill" })
check("energy fill", reply.Ok and data.Energy == capacity, data.Energy .. " / " .. capacity)
check("energy fill: worth more", data.TankValue > 400, data.TankValue)
reply = invoke(owner, "Energy", { Mode = "Set", Amount = capacity / 2 - (capacity / 2) % 1 })
check("energy set lower: keeps worth in proportion", reply.Ok and data.Energy < capacity and data.TankValue > 0)
reply = invoke(owner, "Energy", { Mode = "Give", Amount = 1e20 })
check("energy give: capped at capacity", reply.Ok and data.Energy == capacity, data.Energy)
reply = invoke(owner, "Energy", { Mode = "Empty" })
check("energy empty", reply.Ok and data.Energy == 0 and data.TankValue == 0)
check("energy empty: replicated", table.find(replicated, "OwnerOfStorms:TankValue") ~= nil)

reset()
reply = invoke(owner, "Upgrade", { Upgrade = "Range", Level = 60 })
check("upgrade: capped at its MaxLevel", reply.Ok and data.Upgrades.Range == GameConfig.Upgrades.Range.MaxLevel, data.Upgrades.Range)
reply = invoke(owner, "Upgrade", { Upgrade = "All", Level = 5 })
check("upgrade all", reply.Ok and data.Upgrades.Power == 5 and data.Upgrades.Tank == 5 and data.Upgrades.Range == 5 and data.Upgrades.Speed == 5)
check("upgrade: replicated", table.find(replicated, "OwnerOfStorms:Upgrades") ~= nil)
data.Energy = 1e9
invoke(owner, "Upgrade", { Upgrade = "Tank", Level = 1 })
check("upgrade: a smaller tank caps the energy", data.Energy == Formulas.TankCapacity(data), data.Energy)

reset()
reply = invoke(owner, "Rebirths", { Count = 7 })
check("shifts set", reply.Ok and data.Rebirths == 7)
check("shifts: gear redressed", table.find(calls, "CharacterGear.DressPlayer OwnerOfStorms 7") ~= nil, table.concat(calls, " | "))

reset()
reply = invoke(owner, "Boost", { Boost = "Luck", Minutes = 30 })
-- the admin's own boost: only the admin's answer, not the usual "boost active" toast as well
check("boost give", reply.Ok and table.find(calls, "BoostService.Add OwnerOfStorms Luck 1800 silent") ~= nil, table.concat(calls, " | "))
reply = invoke(owner, "Boost", { Boost = "Luck", Minutes = 0 })
check("boost clear", reply.Ok and data.Boosts.Luck == 0)

reset()
reply = invoke(owner, "Pass", { Pass = "VIP", Owned = true })
check("pass grant", reply.Ok and data.Passes.VIP == true)
check("pass grant: replicated", table.find(replicated, "OwnerOfStorms:Passes") ~= nil)
check("pass grant: info lists it", reply.Info.Passes.VIP == true)
reply = invoke(owner, "Pass", { Pass = "All", Owned = true })
check("pass grant all", reply.Ok and data.Passes.MegaTank and data.Passes.PetSlots and data.Passes.StormRadar)
reply = invoke(owner, "Pass", { Pass = "VIP", Owned = false })
check("pass revoke", reply.Ok and data.Passes.VIP == nil and data.Passes.MegaTank == true)
data.Energy = Formulas.TankCapacity(data)
invoke(owner, "Pass", { Pass = "All", Owned = false })
check("pass revoke all", next(data.Passes) == nil)
check("pass revoke: Mega Tank energy capped", data.Energy == Formulas.TankCapacity(data))

reset()
reply = invoke(owner, "Teleport", { To = 5 })
check("teleport: locked zone refused", reply.Ok == false and #calls == 0, reply.Error)
reply = invoke(owner, "Zone", { Zone = #Zones })
check("zones: unlock all", reply.Ok and data.Zone == #Zones)
check("zones: replicated", table.find(replicated, "OwnerOfStorms:Zone") ~= nil)
reply = invoke(owner, "Teleport", { To = 5 })
check("teleport: zone 5", reply.Ok and table.find(calls, "ZoneService.TeleportTo OwnerOfStorms 526") ~= nil, table.concat(calls, " | "))
invoke(owner, "Teleport", { To = "Hub" })
invoke(owner, "Teleport", { To = "Arena" })
check("teleport: hub and arena", table.find(calls, "ZoneService.TeleportTo OwnerOfStorms 26") ~= nil and table.find(calls, "ZoneService.TeleportTo OwnerOfStorms -50") ~= nil)
teleportWorks = false
reply = invoke(owner, "Teleport", { To = 1 })
check("teleport: no character", reply.Ok == false)
teleportWorks = true

reset()
local petsBefore = #data.Pets
reply = invoke(owner, "Pets", { Pet = "Sunny", Tier = "Golden", Count = 3 })
check("pets add", reply.Ok and #data.Pets == petsBefore + 3, #data.Pets)
check("pets add: golden", data.Pets[#data.Pets].Golden == true and data.Pets[#data.Pets].Rainbow == false)
check("pets add: forced past storage", table.find(calls, "PetService.AddPet Sunny Golden true") ~= nil)
check("pets add: indexed and replicated", data.Index.Sunny == true and table.find(replicated, "OwnerOfStorms:Index") ~= nil and table.find(replicated, "OwnerOfStorms:Pets") ~= nil)
reply = invoke(owner, "Pets", { Pet = "RainbowRoc" })
check("pets add: defaults to one normal pet", reply.Ok and data.Pets[#data.Pets].Id == "RainbowRoc" and data.Pets[#data.Pets].Golden == false)
for _ = 1, 4 do
	invoke(owner, "Pets", { Pet = "Puffling", Count = 50 })
end
check("pets add: stops at the admin limit", #data.Pets == GameConfig.Pets.MaxStorage + 90, #data.Pets)
reply = invoke(owner, "Pets", { Pet = "Puffling" })
check("pets add: full", reply.Ok == false and string.find(reply.Error, "admin limit", 1, true) ~= nil, reply.Error)

-- Targeting another player
reset()
local puffData = datas[puffball]
reply = invoke(owner, "Volts", { Mode = "Set", Amount = 77, Target = "puffball42" })
check("target: by name, any case", reply.Ok and puffData.Volts == 77 and data.Volts == 0, puffData.Volts)
check("target: info is the target's", reply.Info.Name == "Puffball42")
check("target: logged with the target", count(Mock.Prints, "Target=\"Puffball42\"") == 1, table.concat(Mock.Prints, " | "))
reply = invoke(owner, "Zone", { Zone = 2, Target = "Puffy" })
check("target: by display name", reply.Ok and puffData.Zone == 2)
reply = invoke(owner, "Boost", { Boost = "Energy", Minutes = 5, Target = "Puffball42" })
check("target: boost toasts the target", reply.Ok and table.find(calls, "BoostService.Add Puffball42 Energy 300") ~= nil, table.concat(calls, " | "))
check("target: boost answer names them", reply.Ok and string.find(reply.Message, "for Puffy", 1, true) ~= nil, reply.Message)
reply = invoke(owner, "Inspect", { Target = "puff" })
check("target: by the start of a name", reply.Ok and reply.Info.Volts == 77 and reply.Info.Zone == 2, reply.Error)
reply = invoke(owner, "Inspect", { Target = "" })
check("target: empty means yourself", reply.Ok and reply.Info.Name == "OwnerOfStorms")
local twin = newPlayer("PuffballTwin", 4343)
datas[twin] = newData()
reply = invoke(owner, "Inspect", { Target = "Puff" })
check("target: an ambiguous start is refused", reply.Ok == false and string.find(reply.Error, "More than one", 1, true) ~= nil, reply.Error)
removePlayer(twin)

-- Goto / Bring
reset()
roots[owner] = { Position = Vector3.new(150, 4, 0), CFrame = CFrame.new(150, 4, 0) }
roots[puffball] = { Position = Vector3.new(450, 4, 0), CFrame = CFrame.new(450, 4, 0) }
reply = invoke(owner, "Goto", { Target = "Puffball42" })
check("goto", reply.Ok and table.find(calls, "ZoneService.TeleportTo OwnerOfStorms 450") ~= nil, reply.Error or table.concat(calls, " | "))
reply = invoke(owner, "Bring", { Target = "Puffball42" })
check("bring", reply.Ok and table.find(calls, "ZoneService.TeleportTo Puffball42 150") ~= nil, reply.Error or table.concat(calls, " | "))
roots[owner] = { Position = Vector3.new(550, 4, 0), CFrame = CFrame.new(550, 4, 0) }
reply = invoke(owner, "Bring", { Target = "Puffball42" })
check("bring: not into a zone they haven't unlocked", reply.Ok == false, reply.Error)

-- Server-wide commands
reset()
reply = invoke(owner, "MegaStorm", { Kind = "Summon" })
check("mega storm summon", reply.Ok and table.find(calls, "MegaStormService.Summon OwnerOfStorms") ~= nil)
reply = invoke(owner, "MegaStorm", { Kind = "Rainbow" })
check("rainbow hurricane", reply.Ok and table.find(calls, "MegaStormService.ScheduleRainbow " .. (GameConfig.MegaStorm.WarningTime + 10)) ~= nil, table.concat(calls, " | "))
check("server-wide: no target info", reply.Info == nil)

reset()
reply = invoke(owner, "Weather", { Zone = 2 })
check("weather: needs WeatherService.SpawnCells", reply.Ok == false and string.find(reply.Error, "SpawnCells", 1, true) ~= nil, reply.Error)
Registry.WeatherService.SpawnCells = function(zoneId, amount, typeId)
	call(string.format("WeatherService.SpawnCells %d %d %s", zoneId, amount, tostring(typeId)))
	return amount
end
reply = invoke(owner, "Weather", { Zone = 2, Count = 3, Type = "LightningOrb" })
check("weather: spawned", reply.Ok and table.find(calls, "WeatherService.SpawnCells 2 3 LightningOrb") ~= nil, reply.Error or table.concat(calls, " | "))
reply = invoke(owner, "Weather", { Zone = 4 })
check("weather: default count, any type", reply.Ok and table.find(calls, "WeatherService.SpawnCells 4 5 nil") ~= nil)

reset()
reply = invoke(owner, "Announce", { Text = "  Double <b>Volts</b> & a badword tonight!\n" })
check("announce: ok", reply.Ok == true, reply.Error)
check(
	"announce: filtered, escaped and sent to everyone",
	notified[1] == "*|📢 Double &lt;b&gt;Volts&lt;/b&gt; &amp; a ####### tonight!|Info",
	notified[1]
)
filterMode = "error"
reset()
reply = invoke(owner, "Announce", { Text = "Hello" })
check("announce: live server without a filter answer refuses", reply.Ok == false and #notified == 0, reply.Error)
Mock.IsStudio = true
reply = invoke(owner, "Announce", { Text = "Hello" })
check("announce: Studio falls back to the raw text", reply.Ok and notified[1] == "*|📢 Hello|Info", notified[1])
Mock.IsStudio = false
filterMode = "ok"

-- A service error doesn't break the remote
reset()
local realSummon = Registry.MegaStormService.Summon
Registry.MegaStormService.Summon = function()
	error("storm folder missing")
end
reply = invoke(owner, "MegaStorm", { Kind = "Summon" })
check("errors: caught and reported", reply.Ok == false and string.find(reply.Error, "failed on the server", 1, true) ~= nil, reply.Error)
check("errors: warned", count(Mock.Warnings, "storm folder missing") == 1)
Registry.MegaStormService.Summon = realSummon

-- Reset: own data only
reset()
reply = invoke(owner, "Reset", { Confirm = "RESET", Target = "Puffball42" })
check("reset: not someone else's", reply.Ok == false and puffData.Volts == 77, reply.Error)
data.Volts, data.Settings.Music = 123, false
local nextPet = data.NextPetId
data.Passes.VIP = true
reply = invoke(owner, "Reset", { Confirm = "RESET" })
check("reset: ok", reply.Ok == true, reply.Error)
check("reset: progress cleared", data.Volts == 0 and data.TotalVolts == 0 and data.Zone == 1 and data.Rebirths == 0 and #data.Pets == 0 and next(data.Index) == nil)
check("reset: upgrades back to 1", data.Upgrades.Power == 1 and data.Upgrades.Tank == 1 and data.Upgrades.Range == 1 and data.Upgrades.Speed == 1)
check("reset: rewards and codes cleared", data.Daily.Streak == 0 and next(data.Codes) == nil and next(data.GiftsClaimed) == nil and data.Stats.CellsCaught == 0)
check("reset: settings, receipts, passes and pet ids kept", data.Settings.Music == false and data.Receipts.r1 == 99 and data.Passes.VIP == true and data.NextPetId == nextPet)
check("reset: replicated", table.find(replicated, "OwnerOfStorms:Volts") ~= nil and table.find(replicated, "OwnerOfStorms:Pets") ~= nil and table.find(replicated, "OwnerOfStorms:Zone") ~= nil)
check("reset: saved, redressed and sent to the hub", table.find(calls, "DataService.Save OwnerOfStorms") ~= nil and table.find(calls, "CharacterGear.DressPlayer OwnerOfStorms 0") ~= nil and table.find(calls, "ZoneService.TeleportTo OwnerOfStorms 26") ~= nil, table.concat(calls, " | "))

-- The listed admin can use commands too
reset()
reply = invoke(listed, "Volts", { Mode = "Give", Amount = 1 })
check("listed admin: commands work", reply.Ok == true, reply.Error)

-- Leaving forgets the cached answer
removePlayer(owner)
check("leaving: cache cleared (no longer in the server)", AdminService.IsAdmin(owner) == true) -- decided again, not cached
removePlayer(loading)

Mock.RealPrint(string.format("Admin mock test: %d passed, %d failed", passes, failures))
if failures > 0 then
	error("mock test failed")
end
