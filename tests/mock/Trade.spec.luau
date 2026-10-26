--!nocheck
-- Mock test for pet trading (TradeService) with the real PetService: requests (cooldowns, spam, expiry,
-- "Allow trade requests" off, yourself, malformed arguments), the trade itself (offers, Ready, the
-- countdown, the swap on both profiles, new Uids, the Index, saves, the log line) and the duplication
-- attempts a pet simulator has to survive: the same Uid twice, someone else's pet, changing an offer after
-- Ready or during the countdown, a pet deleted / crafted / equipped while offered, a second execution, a
-- player leaving or being saved for the last time mid-countdown, a full storage, data that can't be saved,
-- hatching mid-trade and request spam through the remote. Runs after RobloxMock.luau and the module
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

-- RobloxMock has no Random (PetService makes one for its egg rolls)
Random = {
	new = function()
		return {
			NextNumber = function(_, low, high)
				low, high = low or 0, high or 1
				return low + math.random() * (high - low)
			end,
		}
	end,
}

------------------------------------------------------------------------ clock and task.delay
local clock = 1000
local delayed = {} -- { At, Fn, Args }
task.delay = function(seconds, fn, ...)
	table.insert(delayed, { At = clock + (seconds or 0), Fn = fn, Args = { ... } })
end
-- moves the clock on and runs the delayed functions that are due, in time order
local function advance(seconds)
	clock += seconds
	table.sort(delayed, function(a, b)
		return a.At < b.At
	end)
	local due = {}
	for index = #delayed, 1, -1 do
		if delayed[index].At <= clock then
			table.insert(due, 1, table.remove(delayed, index))
		end
	end
	for _, job in due do
		job.Fn(table.unpack(job.Args))
	end
end

------------------------------------------------------------------------ game tree
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Shared = Mock.Folder("Shared", ReplicatedStorage)
local Config = Mock.Folder("Config", Shared)
local Util = Mock.Folder("Util", Shared)
Mock.Module("GameConfig", Config, __sources.GameConfig)
Mock.Module("Pets", Config, __sources.Pets)
Mock.Module("Zones", Config, __sources.Zones)
Mock.Module("Weather", Config, __sources.Weather)
Mock.Module("MapLayout", Config, __sources.MapLayout)
Mock.Module("Formulas", Shared, __sources.Formulas)
Mock.Module("Format", Util, __sources.Format)

local events = {} -- "Name|kind" per TradeEvent:FireClient
local lastEvent = {} -- [Player] = { Kind, Payload } of the latest event
local function newRemote(name)
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	return remote
end
local TradeAction, Hatch, PetActionRemote = newRemote("TradeAction"), newRemote("Hatch"), newRemote("PetAction")
local TradeEvent = {
	FireClient = function(_, player, kind, payload)
		table.insert(events, player.Name .. "|" .. kind)
		lastEvent[player] = { Kind = kind, Payload = payload }
	end,
}
Mock.Module("Remotes", Shared, function()
	return { TradeAction = TradeAction, TradeEvent = TradeEvent, Hatch = Hatch, PetAction = PetActionRemote }
end)

local GameConfig = require(Config.GameConfig)
local Pets = require(Config.Pets)
local TRADING = GameConfig.Trading

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

------------------------------------------------------------------------ stand-in services
local profiles = {} -- [Player] = { Data, CanSave, Released, Saves, Stored }
local replicated = {} -- "Name:Key"
local notified = {} -- "Name|text|kind"

local function pet(uid, id, extra)
	local entry = { Uid = uid, Id = id, Golden = false, Rainbow = false, Equipped = false }
	for key, value in extra or {} do
		entry[key] = value
	end
	return entry
end

local function newData(pets, nextId)
	return {
		Volts = 1000,
		Zone = 1,
		Pets = pets,
		NextPetId = nextId,
		Index = {},
		Settings = deepCopy(GameConfig.DefaultSettings),
		Stats = { EggsHatched = 0 },
		Passes = {},
	}
end

local Registry = {}
Registry.DataService = {
	PlayerLoaded = signal(),
	PlayerLeaving = signal(),
	Changed = signal(),
	Get = function(player)
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
	Save = function(player, release)
		local profile = profiles[player]
		if not profile or not profile.CanSave or (profile.Released and not release) then
			return false
		end
		profile.Saves += 1
		profile.Stored = deepCopy(profile.Data)
		return true
	end,
	Replicate = function(player, ...)
		for _, key in { ... } do
			table.insert(replicated, player.Name .. ":" .. key)
			Registry.DataService.Changed:Fire(player, key, profiles[player] and profiles[player].Data[key])
		end
	end,
}

local rateLimited = {} -- [Player] = { [key] = clock }
local Net = {
	RateLimit = function(player, key, interval)
		local calls = rateLimited[player] or {}
		rateLimited[player] = calls
		if calls[key] and clock - calls[key] < interval then
			return false
		end
		calls[key] = clock
		return true
	end,
	Fail = function(message)
		return { Ok = false, Error = message }
	end,
	Notify = function(player, text, kind)
		table.insert(notified, player.Name .. "|" .. text .. "|" .. tostring(kind))
	end,
	NotifyAll = function() end,
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
Mock.Module("TradeService", Services, __sources.TradeService)

local PetService = require(Services.PetService)
local TradeService = require(Services.TradeService)
Registry.PetService = PetService
Registry.TradeService = TradeService
TradeService.Clock = function()
	return clock
end
PetService.Init()
TradeService.Init()

------------------------------------------------------------------------ helpers
local function reset()
	table.clear(events)
	table.clear(replicated)
	table.clear(notified)
	table.clear(Mock.Prints)
	table.clear(Mock.Warnings)
end

local function has(list, pattern)
	for _, line in list do
		if string.find(line, pattern, 1, true) then
			return true
		end
	end
	return false
end

local function find(data, uid)
	for _, entry in data.Pets do
		if entry.Uid == uid then
			return entry
		end
	end
	return nil
end

local function countId(data, id)
	local found = 0
	for _, entry in data.Pets do
		if entry.Id == id then
			found += 1
		end
	end
	return found
end

-- Every pet Uid must be unique within a player's data
local function uidsUnique(data)
	local seen = {}
	for _, entry in data.Pets do
		if seen[entry.Uid] then
			return false
		end
		seen[entry.Uid] = true
	end
	return true
end

local function invoke(player, ...)
	clock += 0.2 -- past the remote's rate limit
	return TradeAction.OnServerInvoke(player, ...)
end

local function load(player, pets, nextId)
	profiles[player] = { Data = newData(pets, nextId), CanSave = true, Released = false, Saves = 0 }
	Registry.DataService.PlayerLoaded:Fire(player, profiles[player].Data)
	return profiles[player].Data
end

local function waitOut()
	advance(TRADING.RequestCooldown + TRADING.RequestTimeout + 1)
end

-- Opens a trade between a and b through the remote (request + accept)
local function open(a, b)
	waitOut()
	local sent = invoke(a, "Request", b.UserId)
	assert(sent.Ok, "request failed: " .. tostring(sent.Error))
	local answered = invoke(b, "Respond", a.UserId, true)
	assert(answered.Ok, "accept failed: " .. tostring(answered.Error))
	return TradeService.Get(a)
end

------------------------------------------------------------------------ setup
local alice = newPlayer("Alice", 101)
local bob = newPlayer("Bob", 202)
local carol = newPlayer("Carol", 303)
local aliceData = load(alice, {
	pet("p1", "Puffling", { Equipped = true }),
	pet("p2", "Sunny"),
	pet("p3", "Droplet"),
	pet("p4", "BreezeKing", { Golden = true }),
	pet("p5", "AuroraGryphon"), -- an exclusive: tradeable
}, 6)
local bobData = load(bob, {
	pet("p1", "Static"),
	pet("p2", "Zappy", { Equipped = true }),
	pet("p3", "VoltBat"),
}, 4)
local carolData = load(carol, { pet("p1", "Sandy") }, 2)

check("setup: the remote handler is installed", type(TradeAction.OnServerInvoke) == "function")
check("setup: trade settings default to allowed", GameConfig.DefaultSettings.AllowTrades == true)
check("setup: the settings row exists", (function()
	for _, info in GameConfig.SettingsInfo do
		if info.Key == "AllowTrades" then
			return true
		end
	end
	return false
end)())

------------------------------------------------------------------------ requests
reset()
local reply = invoke(alice, "Request", alice.UserId)
check("request: trading with yourself is refused", reply.Ok == false and string.find(reply.Error, "yourself", 1, true) ~= nil, reply.Error)
for index, bad in { "202", 202.5, 0 / 0, math.huge, {}, true, 999999 } do
	local result = invoke(alice, "Request", bad)
	check("request: malformed / unknown target #" .. index .. " refused", type(result) == "table" and result.Ok == false, result and result.Error)
end
for index, bad in { nil, 5, {}, true, "Explode" } do
	local ok, result = pcall(TradeAction.OnServerInvoke, alice, bad, 1, 2)
	clock += 0.2
	check("remote: malformed action #" .. index .. " answered without an error", ok and type(result) == "table" and result.Ok == false, result)
end
check("request: nothing was sent to anyone", #events == 0, table.concat(events, " "))

-- "Allow trade requests" off
bobData.Settings.AllowTrades = false
reply = invoke(alice, "Request", bob.UserId)
check("settings off: refused", reply.Ok == false and string.find(reply.Error, "isn't accepting", 1, true) ~= nil, reply.Error)
check("settings off: Bob got no card", not has(events, "Bob|Request"), table.concat(events, " "))
Registry.DataService.Replicate(bob, "Settings")
check("settings off: other players see TradesOff", bob:GetAttribute("TradesOff") == true)
bobData.Settings.AllowTrades = true
Registry.DataService.Replicate(bob, "Settings")
check("settings on: TradesOff cleared", bob:GetAttribute("TradesOff") == nil)

reset()
reply = invoke(alice, "Request", bob.UserId)
check("request: sent", reply.Ok == true, reply.Error)
check("request: Bob gets a card", lastEvent[bob] and lastEvent[bob].Kind == "Request" and lastEvent[bob].Payload.From == alice.UserId)
check("request: the card says when it expires", lastEvent[bob].Payload.Expires == TRADING.RequestTimeout)
reply = invoke(alice, "Request", bob.UserId)
check("request: asking again while pending is refused", reply.Ok == false, reply.Error)
reply = invoke(alice, "Request", carol.UserId)
check("request spam: another player right away is refused", reply.Ok == false and reply.Error == "Slow down!", reply.Error)
local state = invoke(bob, "State")
check("state: Bob sees the incoming request", state.Ok and #state.Incoming == 1 and state.Incoming[1].From == alice.UserId)
state = invoke(alice, "State")
check("state: Alice sees her outgoing request", state.Ok and #state.Outgoing == 1 and state.Outgoing[1] == bob.UserId)

-- Carol can't answer a request that isn't hers
reply = invoke(carol, "Respond", alice.UserId, true)
check("respond: someone else's request is refused", reply.Ok == false and not TradeService.IsTrading(alice), reply.Error)
reply = invoke(bob, "Respond", alice.UserId, "yes")
check("respond: a non-boolean answer is refused", reply.Ok == false and not TradeService.IsTrading(alice), reply.Error)

-- Decline, then the cooldown
reset()
reply = invoke(bob, "Respond", alice.UserId, false)
check("decline: ok", reply.Ok == true, reply.Error)
check("decline: Alice is told", has(notified, "Alice|Bob declined your trade request."), table.concat(notified, " / "))
check("decline: no trade", not TradeService.IsTrading(alice) and not TradeService.IsTrading(bob))
advance(TRADING.RequestInterval + 0.5)
reply = invoke(alice, "Request", bob.UserId)
check("cooldown: asking the same player again too soon is refused", reply.Ok == false and string.find(reply.Error, "Wait", 1, true) ~= nil, reply.Error)
advance(TRADING.RequestCooldown)
reply = invoke(alice, "Request", bob.UserId)
check("cooldown: allowed once it has passed", reply.Ok == true, reply.Error)

-- Expiry
reset()
advance(TRADING.RequestTimeout + 0.5)
check("expiry: Bob's card is taken away", lastEvent[bob] and lastEvent[bob].Kind == "RequestGone" and lastEvent[bob].Payload.From == alice.UserId)
reply = invoke(bob, "Respond", alice.UserId, true)
check("expiry: accepting an expired request fails", reply.Ok == false and not TradeService.IsTrading(bob), reply.Error)

-- Too many pending requests for one player
waitOut()
local crowd = {}
for index = 1, TRADING.MaxPendingRequests + 1 do
	local fan = newPlayer("Fan" .. index, 900 + index)
	load(fan, {}, 1)
	crowd[index] = fan
	local result = invoke(fan, "Request", carol.UserId)
	if index <= TRADING.MaxPendingRequests then
		check("crowd: request " .. index .. " accepted", result.Ok == true, result.Error)
	else
		check("crowd: one request too many is refused", result.Ok == false, result.Error)
	end
end
for _, fan in crowd do
	table.remove(playerList, table.find(playerList, fan))
	Players.PlayerRemoving:Fire(fan)
	fan.Parent = nil
	profiles[fan] = nil
end
check("crowd: leaving players take their requests with them", #invoke(carol, "State").Incoming == 0)

-- Asking someone who already asked you starts the trade
waitOut()
reset()
reply = invoke(alice, "Request", carol.UserId)
check("mutual: Alice asks Carol", reply.Ok == true, reply.Error)
advance(TRADING.RequestInterval + 0.5)
reply = invoke(carol, "Request", alice.UserId)
check("mutual: Carol asking back opens the trade", reply.Ok == true and reply.Started == true and TradeService.IsTrading(alice) and TradeService.IsTrading(carol), reply.Error)
reply = invoke(bob, "Request", alice.UserId)
check("busy: requesting someone who is trading is refused", reply.Ok == false and string.find(reply.Error, "already trading", 1, true) ~= nil, reply.Error)
check("busy: the Trading attribute is set", alice:GetAttribute("Trading") == true and carol:GetAttribute("Trading") == true)
reply = invoke(carol, "Cancel")
check("cancel: ok", reply.Ok == true and not TradeService.IsTrading(alice) and not TradeService.IsTrading(carol))
check("cancel: both told", has(notified, "Alice|Trade cancelled: Carol cancelled it.") and has(notified, "Carol|Trade cancelled."), table.concat(notified, " / "))
check("cancel: both windows close", lastEvent[alice].Kind == "Ended" and lastEvent[carol].Kind == "Ended")
check("cancel: Trading attribute cleared", alice:GetAttribute("Trading") == nil and carol:GetAttribute("Trading") == nil)

------------------------------------------------------------------------ offers
reset()
reply = invoke(alice, "Add", "p2")
check("offer: not in a trade is refused", reply.Ok == false, reply.Error)
local trade = open(alice, bob)
check("open: trade started", trade ~= nil and TradeService.Get(bob) == trade)
check("open: both get the window", lastEvent[alice].Kind == "State" and lastEvent[bob].Kind == "State")
check("open: Alice sees Bob as the partner", lastEvent[alice].Payload.Partner.UserId == bob.UserId and lastEvent[alice].Payload.Max == TRADING.MaxPets)

for index, bad in { 5, {}, nil, string.rep("p", 40), "p99" } do
	local result = invoke(alice, "Add", bad)
	check("offer: malformed / unknown uid #" .. index .. " refused", result.Ok == false and #trade.Offers[alice] == 0, result.Error)
end
reply = invoke(alice, "Add", "p3") -- Bob has a p3 too: Uids are per player, Alice's own p3 is offered
check("offer: own pet added", reply.Ok == true and trade.Offers[alice][1] == "p3", reply.Error)
reply = invoke(alice, "Add", "p3")
check("dupe: the same uid twice is refused", reply.Ok == false and #trade.Offers[alice] == 1, reply.Error)
check("offer: Bob sees Alice's pet", #lastEvent[bob].Payload.Theirs.Pets == 1 and lastEvent[bob].Payload.Theirs.Pets[1].Id == "Droplet")

-- someone else's pet: Carol's only Uid doesn't exist in Alice's data under her name... use one only Bob has
bobData.Pets[#bobData.Pets + 1] = pet("p77", "StormLord")
reply = invoke(alice, "Add", "p77")
check("dupe: offering someone else's pet is refused", reply.Ok == false and #trade.Offers[alice] == 1, reply.Error)
table.remove(bobData.Pets)

-- equipped pets are unequipped when offered, and can't be equipped again while offered
reply = invoke(alice, "Add", "p1")
check("offer: an equipped pet is added", reply.Ok == true, reply.Error)
check("offer: ...and unequipped", find(aliceData, "p1").Equipped == false)
reply = PetActionRemote.OnServerInvoke(alice, "Equip", "p1")
clock += 0.2
check("guard: equipping an offered pet is refused", reply.Ok == false and find(aliceData, "p1").Equipped == false, reply.Error)
PetActionRemote.OnServerInvoke(alice, "EquipBest")
clock += 0.2
check("guard: Equip Best skips offered pets", find(aliceData, "p1").Equipped == false and find(aliceData, "p3").Equipped == false)
check("guard: Equip Best still equips the rest", find(aliceData, "p2").Equipped == true)
PetActionRemote.OnServerInvoke(alice, "UnequipAll")
clock += 0.2

-- deleting an offered pet
reply = PetActionRemote.OnServerInvoke(alice, "Delete", "p3")
clock += 0.2
check("guard: deleting an offered pet is refused", reply.Ok == false and find(aliceData, "p3") ~= nil, reply.Error)
reply = PetActionRemote.OnServerInvoke(alice, "DeleteMany", { "p3", "p1" })
clock += 0.2
check("guard: Delete Many keeps offered pets", reply.Ok == false and find(aliceData, "p3") ~= nil and find(aliceData, "p1") ~= nil, reply.Error)

-- crafting with an offered pet: 5 Droplets, one of them (p3) offered
for index = 1, 4 do
	table.insert(aliceData.Pets, pet("d" .. index, "Droplet"))
end
reply = PetActionRemote.OnServerInvoke(alice, "Golden", "Droplet")
clock += 0.2
check("guard: crafting can't use an offered pet", reply.Ok == false and find(aliceData, "p3") ~= nil and countId(aliceData, "Droplet") == 5, reply.Error)
check("guard: the craft error says why", reply.Error and string.find(reply.Error, "trade", 1, true) ~= nil, reply.Error)
table.insert(aliceData.Pets, pet("d5", "Droplet"))
reply = PetActionRemote.OnServerInvoke(alice, "Golden", "Droplet")
clock += 0.2
check("guard: crafting uses the other copies", reply.Ok == true and find(aliceData, "p3") ~= nil, reply.Error)
-- tidy: leave Alice with p1..p5 plus the golden Droplet
local golden = reply.Uid

-- remove + max pets
reply = invoke(alice, "Remove", "p1")
check("offer: remove works", reply.Ok == true and #trade.Offers[alice] == 1, reply.Error)
reply = invoke(alice, "Remove", "p1")
check("offer: removing a pet that isn't offered is refused", reply.Ok == false, reply.Error)
for index = 1, TRADING.MaxPets + 1 do
	table.insert(aliceData.Pets, pet("m" .. index, "Puffling"))
end
local added = 0
for index = 1, TRADING.MaxPets + 1 do
	if invoke(alice, "Add", "m" .. index).Ok then
		added += 1
	end
end
check("offer: at most MaxPets pets", #trade.Offers[alice] == TRADING.MaxPets and added == TRADING.MaxPets - 1, #trade.Offers[alice])
for index = 1, TRADING.MaxPets + 1 do
	invoke(alice, "Remove", "m" .. index)
	local _, position = nil, nil
	for i, entry in aliceData.Pets do
		if entry.Uid == "m" .. index then
			position = i
		end
	end
	if position then
		table.remove(aliceData.Pets, position)
	end
end
check("offer: back to one pet", #trade.Offers[alice] == 1 and trade.Offers[alice][1] == "p3", table.concat(trade.Offers[alice], ","))

------------------------------------------------------------------------ ready + countdown
reset()
reply = invoke(bob, "Add", "p3") -- Volt Bat
check("bob: offers Volt Bat", reply.Ok == true, reply.Error)
reply = invoke(alice, "Ready", "yes")
check("ready: a non-boolean is refused", reply.Ok == false and trade.Ready[alice] == false, reply.Error)
reply = invoke(alice, "Ready", true)
check("ready: Alice ready", reply.Ok == true and trade.Ready[alice] == true, reply.Error)
check("ready: Bob sees it", lastEvent[bob].Payload.Theirs.Ready == true)
-- changing an offer after Ready un-readies both
reply = invoke(bob, "Add", "p1")
check("change after ready: allowed", reply.Ok == true, reply.Error)
check("change after ready: Alice is no longer ready", trade.Ready[alice] == false and trade.State == "Open")
invoke(bob, "Remove", "p1")

invoke(alice, "Ready", true)
local countdownJobs = #delayed
reply = invoke(bob, "Ready", true)
check("countdown: starts when both are ready", reply.Ok == true and trade.State == "Countdown" and #delayed == countdownJobs + 1, trade.State)
check("countdown: both see it", lastEvent[alice].Payload.State == "Countdown" and lastEvent[alice].Payload.Countdown == TRADING.Countdown)
local staleToken = trade.Token
-- a change during the countdown cancels Ready on both sides; the old countdown must not complete
reply = invoke(alice, "Add", "p2")
check("countdown: a change stops it", reply.Ok == true and trade.State == "Open" and trade.Ready[alice] == false and trade.Ready[bob] == false)
advance(TRADING.Countdown + 0.5)
check("countdown: the stopped countdown swapped nothing", find(aliceData, "p3") ~= nil and find(bobData, "p3") ~= nil and TradeService.IsTrading(alice))
check("dupe: a stale token can't execute", TradeService.Execute(trade, staleToken) == false and TradeService.IsTrading(alice))
-- un-ready during the countdown
invoke(alice, "Ready", true)
invoke(bob, "Ready", true)
check("countdown: running again", trade.State == "Countdown")
reply = invoke(bob, "Ready", false)
check("countdown: un-ready stops it for both", reply.Ok == true and trade.State == "Open" and trade.Ready[alice] == false)
advance(TRADING.Countdown + 0.5)
check("countdown: still nothing swapped", find(aliceData, "p3") ~= nil and find(bobData, "p3") ~= nil)

------------------------------------------------------------------------ the happy path
reset()
local aliceBefore, bobBefore = #aliceData.Pets, #bobData.Pets
local aliceSaves, bobSaves = profiles[alice].Saves, profiles[bob].Saves
local aliceNext = aliceData.NextPetId
invoke(alice, "Ready", true)
invoke(bob, "Ready", true)
local liveToken = trade.Token
check("early: executing before the countdown ends does nothing", TradeService.Execute(trade, liveToken) == false and trade.State == "Countdown")
clock += TRADING.Countdown + 0.1 -- the countdown is over, its job hasn't run yet
check("dupe: an older countdown's token can't complete the new one", TradeService.Execute(trade, staleToken) == false and trade.State == "Countdown")
advance(0)
check("swap: the trade is over", not TradeService.IsTrading(alice) and not TradeService.IsTrading(bob))
check("swap: Alice no longer has her Droplet (p3) or Sunny (p2)", find(aliceData, "p3") == nil and find(aliceData, "p2") == nil)
check("swap: Bob no longer has his Volt Bat", find(bobData, "p3") == nil and countId(bobData, "VoltBat") == 0)
check("swap: Alice got the Volt Bat", countId(aliceData, "VoltBat") == 1)
check("swap: Bob got the Droplet and the Sunny", countId(bobData, "Droplet") == 1 and countId(bobData, "Sunny") == 1)
check("swap: pet counts add up", #aliceData.Pets == aliceBefore - 2 + 1 and #bobData.Pets == bobBefore - 1 + 2, #aliceData.Pets .. " / " .. #bobData.Pets)
check("swap: received pets get the receiver's next Uids", aliceData.NextPetId == aliceNext + 1 and bobData.NextPetId == 4 + 2)
check("swap: no duplicate Uids", uidsUnique(aliceData) and uidsUnique(bobData))
check("swap: the Index knows the new pets", aliceData.Index.VoltBat == true and bobData.Index.Droplet == true and bobData.Index.Sunny == true)
check("swap: both replicated", has(replicated, "Alice:Index") and has(replicated, "Alice:Pets") and has(replicated, "Bob:Index") and has(replicated, "Bob:Pets"))
check("swap: both saved right away", profiles[alice].Saves == aliceSaves + 1 and profiles[bob].Saves == bobSaves + 1)
check("swap: the saved data has the new pets", countId(profiles[bob].Stored, "Droplet") == 1 and countId(profiles[alice].Stored, "VoltBat") == 1)
check("swap: logged", has(Mock.Prints, "[Trade] #") and has(Mock.Prints, "Alice (101)") and has(Mock.Prints, "Volt Bat"), table.concat(Mock.Prints, " / "))
check("swap: Trade complete! for both", has(notified, "Alice|Trade complete!") and has(notified, "Bob|Trade complete!"), table.concat(notified, " / "))
check("swap: Ended Completed", lastEvent[alice].Kind == "Ended" and lastEvent[alice].Payload.Reason == "Completed")
check("dupe: executing again does nothing", TradeService.Execute(trade, liveToken) == false and TradeService.Execute(trade, trade.Token) == false and countId(aliceData, "VoltBat") == 1)
check("swap: the received pet fills a free equip slot", (function()
	for _, entry in aliceData.Pets do
		if entry.Id == "VoltBat" then
			return entry.Equipped == true
		end
	end
	return false
end)())

------------------------------------------------------------------------ an exclusive trades too
reset()
trade = open(alice, carol)
reply = invoke(alice, "Add", "p5")
check("exclusive: the Aurora Gryphon can be offered", reply.Ok == true, reply.Error)
invoke(alice, "Ready", true)
invoke(carol, "Ready", true)
advance(TRADING.Countdown + 0.1)
check("exclusive: Carol got it (a gift: nothing back)", countId(carolData, "AuroraGryphon") == 1 and countId(aliceData, "AuroraGryphon") == 0)

-- an empty trade can't be readied
trade = open(alice, carol)
reply = invoke(alice, "Ready", true)
check("empty: Ready with nothing offered is refused", reply.Ok == false, reply.Error)
invoke(alice, "Cancel")

-- locked pets (the game has no lock flag yet; the hook refuses them)
find(aliceData, "p4").Locked = true
trade = open(alice, carol)
reply = invoke(alice, "Add", "p4")
check("locked: a locked pet can't be offered", reply.Ok == false, reply.Error)
find(aliceData, "p4").Locked = nil
invoke(alice, "Cancel")

------------------------------------------------------------------------ pet gone during the countdown
reset()
trade = open(alice, bob)
invoke(alice, "Add", "p4")
invoke(bob, "Add", "p1")
invoke(alice, "Ready", true)
invoke(bob, "Ready", true)
-- something outside the guarded paths takes the pet away (e.g. a future feature, an admin tool)
local stolen
for index, entry in aliceData.Pets do
	if entry.Uid == "p4" then
		stolen = table.remove(aliceData.Pets, index)
		break
	end
end
local bobCount = #bobData.Pets
advance(TRADING.Countdown + 0.1)
check("gone: the trade is cancelled", not TradeService.IsTrading(alice) and lastEvent[alice].Payload.Reason == "Cancelled")
check("gone: Bob kept his pet and got nothing", #bobData.Pets == bobCount and find(bobData, "p1") ~= nil and countId(bobData, "BreezeKing") == 0)
check("gone: both told", has(notified, "Bob|Trade cancelled: Alice no longer has a pet they offered."), table.concat(notified, " / "))
table.insert(aliceData.Pets, stolen)

-- equipped behind the guard during the countdown
reset()
trade = open(alice, bob)
invoke(alice, "Add", "p4")
invoke(alice, "Ready", true)
invoke(bob, "Ready", true)
find(aliceData, "p4").Equipped = true
advance(TRADING.Countdown + 0.1)
check("equipped: aborts", find(aliceData, "p4") ~= nil and countId(bobData, "BreezeKing") == 0 and not TradeService.IsTrading(alice))
find(aliceData, "p4").Equipped = false

------------------------------------------------------------------------ leaving / final save / saving
reset()
trade = open(alice, carol)
invoke(alice, "Add", "p4")
invoke(alice, "Ready", true)
invoke(carol, "Ready", true)
local token = trade.Token
table.remove(playerList, table.find(playerList, carol))
Players.PlayerRemoving:Fire(carol)
carol.Parent = nil
advance(TRADING.Countdown + 0.1)
check("leave: the trade ends", not TradeService.IsTrading(alice))
check("leave: Alice keeps her pet", find(aliceData, "p4") ~= nil and countId(carolData, "BreezeKing") == 0)
check("leave: Alice is told", has(notified, "Alice|Trade cancelled: Carol left."), table.concat(notified, " / "))
check("leave: a late execution does nothing", TradeService.Execute(trade, token) == false)
carol.Parent = Players
table.insert(playerList, carol)

-- the final save started (DataService.PlayerLeaving) while the countdown runs
reset()
trade = open(alice, carol)
invoke(alice, "Add", "p4")
invoke(alice, "Ready", true)
invoke(carol, "Ready", true)
profiles[carol].Released = true
Registry.DataService.PlayerLeaving:Fire(carol, carolData)
advance(TRADING.Countdown + 0.1)
check("final save: the trade ends, nothing moves", not TradeService.IsTrading(alice) and find(aliceData, "p4") ~= nil and countId(carolData, "BreezeKing") == 0)
profiles[carol].Released = false

-- released without the signal (belt and braces: execution checks too)
reset()
trade = open(alice, carol)
invoke(alice, "Add", "p4")
invoke(alice, "Ready", true)
invoke(carol, "Ready", true)
profiles[carol].Released = true
advance(TRADING.Countdown + 0.1)
check("released: execution refuses", find(aliceData, "p4") ~= nil and countId(carolData, "BreezeKing") == 0 and not TradeService.IsTrading(alice))
profiles[carol].Released = false

-- one side's data can't be saved
reset()
trade = open(alice, carol)
invoke(alice, "Add", "p4")
invoke(alice, "Ready", true)
invoke(carol, "Ready", true)
profiles[carol].CanSave = false
advance(TRADING.Countdown + 0.1)
check("unsaved data: refused", find(aliceData, "p4") ~= nil and countId(carolData, "BreezeKing") == 0, table.concat(notified, " / "))
profiles[carol].CanSave = true

------------------------------------------------------------------------ storage
reset()
trade = open(alice, bob)
-- Bob's storage is full; Alice offers two, Bob one back: he'd end up one over
local fill = GameConfig.Pets.MaxStorage - #bobData.Pets
for index = 1, fill do
	table.insert(bobData.Pets, pet("f" .. index, "Puffling"))
end
invoke(alice, "Add", "p4")
invoke(alice, "Add", "p1")
invoke(bob, "Add", "f1")
reply = invoke(bob, "Ready", true)
check("storage: Ready is refused when the receiver can't fit the pets", reply.Ok == false and string.find(reply.Error, "storage is full", 1, true) ~= nil, reply.Error)
invoke(alice, "Remove", "p1")
reply = invoke(bob, "Ready", true)
check("storage: one for one fits", reply.Ok == true, reply.Error)
invoke(alice, "Ready", true)
-- Bob's storage fills up behind the trade's back during the countdown (a Mega Storm drop, an admin gift)
table.insert(bobData.Pets, pet("f999", "Puffling"))
invoke(bob, "Remove", "f1") -- now Bob gives nothing and gets one: over the limit
invoke(alice, "Ready", true)
reply = invoke(bob, "Ready", true)
check("storage: refused again when the swap would overflow", reply.Ok == false, reply.Error)
-- force the countdown state to check that execution itself refuses
trade.Ready[alice], trade.Ready[bob] = true, true
trade.State = "Countdown"
trade.Token += 1
trade.CountdownEnd = clock
trade.Frozen = { [alice] = table.clone(trade.Offers[alice]), [bob] = table.clone(trade.Offers[bob]) }
local before = #bobData.Pets
check("storage: execution refuses an overflow", TradeService.Execute(trade, trade.Token) == false and #bobData.Pets == before and find(aliceData, "p4") ~= nil)
check("storage: the trade ended cleanly", not TradeService.IsTrading(bob) and has(notified, "storage is full"), table.concat(notified, " / "))
for index = #bobData.Pets, 1, -1 do
	if string.sub(bobData.Pets[index].Uid, 1, 1) == "f" then
		table.remove(bobData.Pets, index)
	end
end

------------------------------------------------------------------------ frozen offers can't be swapped in the table behind the server
reset()
trade = open(alice, bob)
invoke(alice, "Add", "p4")
invoke(alice, "Ready", true)
invoke(bob, "Ready", true)
table.insert(trade.Offers[alice], "p1") -- not through AddPet: the frozen snapshot no longer matches
advance(TRADING.Countdown + 0.1)
check("frozen: a changed offer list aborts the swap", find(aliceData, "p4") ~= nil and find(aliceData, "p1") ~= nil and countId(bobData, "BreezeKing") == 0)

------------------------------------------------------------------------ hatching and resets end the trade
reset()
trade = open(alice, bob)
invoke(alice, "Add", "p4")
Hatch.OnServerInvoke(alice, "MeadowEgg", 1)
clock += 0.5
check("hatch: opening hatching ends the trade", not TradeService.IsTrading(alice) and not TradeService.IsTrading(bob))
check("hatch: Bob is told why", has(notified, "Bob|Trade cancelled: Alice started hatching."), table.concat(notified, " / "))

reset()
trade = open(alice, bob)
TradeService.EndFor(bob, "had their data reset")
check("reset: an admin reset ends the trade", not TradeService.IsTrading(alice) and has(notified, "Alice|Trade cancelled: Bob had their data reset."))

------------------------------------------------------------------------ remote rate limit
reset()
trade = open(alice, bob)
clock += 1
local first = TradeAction.OnServerInvoke(alice, "Add", "p4")
local second = TradeAction.OnServerInvoke(alice, "Remove", "p4")
check("rate limit: back-to-back calls are throttled", first.Ok == true and second.Ok == false and second.Error == "Slow down!", second.Error)
invoke(alice, "Cancel")

------------------------------------------------------------------------ conservation over the whole run
local total = 0
for _, entry in aliceData.Pets do
	check("final: Alice's pets are all unequipped-or-valid entries", type(entry.Uid) == "string" and Pets.Pets[entry.Id] ~= nil, entry.Uid)
	total += 1
end
check("final: Uids unique for everyone", uidsUnique(aliceData) and uidsUnique(bobData) and uidsUnique(carolData))
check("final: no trades left open", not TradeService.IsTrading(alice) and not TradeService.IsTrading(bob) and not TradeService.IsTrading(carol))
check("final: no warnings", #Mock.Warnings == 0, table.concat(Mock.Warnings, " / "))
local _ = golden

Mock.RealPrint(string.format("Trade mock test: %d passed, %d failed", passes, failures))
if failures > 0 then
	error("mock test failed")
end
