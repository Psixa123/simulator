--!nonstrict
-- Pet trading between two players in the same server. Everything is decided here; the client only asks.
--
-- Flow: a player sends a request (Remotes.TradeAction "Request", the target's UserId); the target sees a card
-- and answers ("Respond", sender UserId, accept) within GameConfig.Trading.RequestTimeout seconds. Accepting
-- opens a trade: each player puts up to MaxPets of their own pets in ("Add" / "Remove", a pet Uid), both press
-- Ready ("Ready", true), and after a Countdown of a few seconds the server swaps the pets. Any change to either
-- offer (or un-readying) during the countdown cancels Ready on both sides. "Cancel" ends the trade; so does
-- either player leaving, hatching an egg, or an admin reset of their data.
--
-- Anti-duplication rules:
--   * every offered Uid must belong to the offerer right now, once, and the pet must be tradeable; offering an
--     equipped pet unequips it, and an offered pet can't be equipped, deleted or crafted (PetService asks
--     TradeService.IsOffered)
--   * the countdown runs on the server and only completes with the token it started with: any change bumps
--     the token, so a stale or repeated execution does nothing; the trade is marked Done before the swap
--   * at execution everything is checked again (both players here, data loaded and not being released by a
--     final save, both saving the same way, every pet still owned, unequipped and offered once, storage space)
--     and the swap happens in memory on both profiles with no yield in between: remove from both, then add to
--     both (received pets get new Uids from the receiver's counter). Both players are then saved right away.
--
-- Server -> client (Remotes.TradeEvent): "Request" { From, Name, DisplayName, Expires }, "RequestGone" { From },
-- "State" (the open trade from this player's side, see view()), "Ended" { Reason, Message }.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Pets = require(Shared.Config.Pets)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Registry)
local Net = require(script.Parent.Net)

local TradeService = {}

local CONFIG = GameConfig.Trading
local MAX_UID_LENGTH = 32

-- Seconds for cooldowns, expiry and the countdown (tests swap it for a fake clock)
TradeService.Clock = os.clock

local trades = {} -- [Player] = trade (both players point at the same trade)
local requests = {} -- [target Player] = { [sender Player] = expires (Clock time) }
local lastAsked = {} -- [sender Player] = { [target Player] = Clock time of the last request }
local lastRequest = {} -- [sender Player] = Clock time of their last request to anyone
local nextId = 0

local function now(): number
	return TradeService.Clock()
end

local function displayName(player: Player): string
	return player.DisplayName
end

local function other(trade, player: Player): Player
	return if trade.A == player then trade.B else trade.A
end

local function isPlayer(value): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function present(player: Player): boolean
	return player.Parent == Players
end

-- Loaded, still here and not in the middle of its final save
local function usable(player: Player)
	if not present(player) then
		return nil
	end
	local DataService = Registry.DataService
	local data = DataService.Get(player)
	if not data or DataService.IsReleased(player) then
		return nil
	end
	return data
end

local function findPet(data, uid: string)
	for _, pet in data.Pets do
		if pet.Uid == uid then
			return pet
		end
	end
	return nil
end

-- Hooks for pets that must never change hands: a per-pet Locked flag or an Untradeable pet config.
-- (Nothing in the game sets either today; Mega Storm exclusives and the Aurora Gryphon trade normally.)
local function tradeable(pet): boolean
	local def = Pets.Pets[pet.Id]
	return def ~= nil and pet.Locked ~= true and def.Untradeable ~= true
end

local function petInfo(pet)
	return { Uid = pet.Uid, Id = pet.Id, Golden = pet.Golden == true, Rainbow = pet.Rainbow == true }
end

local function fire(player: Player, kind: string, payload)
	if present(player) then
		Remotes.TradeEvent:FireClient(player, kind, payload)
	end
end

---------------------------------------------------------------------------
-- What each player sees
---------------------------------------------------------------------------
local function offerView(trade, player: Player)
	local data = Registry.DataService.Get(player)
	local list = {}
	for _, uid in trade.Offers[player] do
		local pet = data and findPet(data, uid)
		if pet then
			table.insert(list, petInfo(pet))
		end
	end
	return list
end

local function view(trade, player: Player)
	local partner = other(trade, player)
	return {
		Id = trade.Id,
		State = trade.State, -- "Open" | "Countdown"
		Countdown = if trade.State == "Countdown" then math.max(0, trade.CountdownEnd - now()) else nil,
		Max = CONFIG.MaxPets,
		Partner = { UserId = partner.UserId, Name = partner.Name, DisplayName = displayName(partner) },
		Mine = { Pets = offerView(trade, player), Ready = trade.Ready[player] == true },
		Theirs = { Pets = offerView(trade, partner), Ready = trade.Ready[partner] == true },
	}
end

local function broadcast(trade)
	if trade.State == "Done" then
		return
	end
	fire(trade.A, "State", view(trade, trade.A))
	fire(trade.B, "State", view(trade, trade.B))
end

local function setBusy(player: Player, busy: boolean)
	if present(player) then
		player:SetAttribute("Trading", if busy then true else nil)
	end
end

---------------------------------------------------------------------------
-- Requests
---------------------------------------------------------------------------
local function dropRequest(target: Player, sender: Player, notifyTarget: boolean)
	local pending = requests[target]
	if not pending or pending[sender] == nil then
		return
	end
	pending[sender] = nil
	if next(pending) == nil then
		requests[target] = nil
	end
	if notifyTarget then
		fire(target, "RequestGone", { From = sender.UserId })
	end
end

-- Every request to or from this player
local function dropAllRequests(player: Player)
	for sender in table.clone(requests[player] or {}) do
		dropRequest(player, sender, true)
	end
	for target, pending in table.clone(requests) do
		if pending[player] ~= nil then
			dropRequest(target, player, true)
		end
	end
end

local function pendingRequest(target: Player, sender: Player): boolean
	local pending = requests[target]
	local expires = pending and pending[sender]
	if expires == nil then
		return false
	end
	if now() >= expires then
		dropRequest(target, sender, true)
		return false
	end
	return true
end

---------------------------------------------------------------------------
-- Trades
---------------------------------------------------------------------------
local function startTrade(a: Player, b: Player)
	nextId += 1
	local trade = {
		Id = nextId,
		A = a,
		B = b,
		Offers = { [a] = {}, [b] = {} },
		Ready = { [a] = false, [b] = false },
		State = "Open",
		Token = 0,
		CountdownEnd = 0,
		Frozen = nil,
	}
	trades[a] = trade
	trades[b] = trade
	dropAllRequests(a)
	dropAllRequests(b)
	setBusy(a, true)
	setBusy(b, true)
	broadcast(trade)
	return trade
end

-- Ends a trade for both players. reason: "Completed" | "Cancelled"
local function endTrade(trade, reason: string, messageA: string, messageB: string?)
	if trades[trade.A] == trade then
		trades[trade.A] = nil
	end
	if trades[trade.B] == trade then
		trades[trade.B] = nil
	end
	trade.State = "Done"
	trade.Token += 1
	trade.Frozen = nil
	setBusy(trade.A, false)
	setBusy(trade.B, false)
	local kind = if reason == "Completed" then "Success" else "Info"
	for _, entry in { { trade.A, messageA }, { trade.B, messageB or messageA } } do
		local player, message = entry[1], entry[2]
		if present(player) then
			fire(player, "Ended", { Reason = reason, Message = message })
			Net.Notify(player, message, kind)
		end
	end
end

-- Any change to an offer: nobody is ready any more and a running countdown stops
local function unreadyAll(trade)
	trade.Ready[trade.A] = false
	trade.Ready[trade.B] = false
	trade.State = "Open"
	trade.Token += 1
	trade.Frozen = nil
end

-- Problems with one side's offer right now (nil = fine)
local function checkOffer(trade, player: Player, data, uids): string?
	local seen = {}
	if #uids > CONFIG.MaxPets then
		return "Too many pets in the trade."
	end
	for _, uid in uids do
		if seen[uid] then
			return "A pet was offered twice."
		end
		seen[uid] = true
		local pet = findPet(data, uid)
		if not pet then
			return displayName(player) .. " no longer has a pet they offered."
		end
		if pet.Equipped then
			return displayName(player) .. " equipped a pet they offered."
		end
		if not tradeable(pet) then
			return "One of the pets can't be traded."
		end
	end
	return nil
end

-- Storage check for the receiving side (only when the trade adds pets to them)
local function storageProblem(player: Player, data, giving: number, getting: number): string?
	if getting > giving and #data.Pets - giving + getting > GameConfig.Pets.MaxStorage then
		return displayName(player) .. "'s pet storage is full!"
	end
	return nil
end

-- Moves pets in memory. No yields from here to the end: remove from both, then add to both.
local function swap(trade, dataA, dataB, uidsA, uidsB)
	local function take(data, uids)
		local wanted = {}
		for _, uid in uids do
			wanted[uid] = true
		end
		local kept, taken = {}, {}
		for _, pet in data.Pets do
			if wanted[pet.Uid] then
				taken[pet.Uid] = pet
			else
				table.insert(kept, pet)
			end
		end
		local ordered = {}
		for _, uid in uids do
			table.insert(ordered, taken[uid])
		end
		data.Pets = kept
		return ordered
	end
	local function give(data, list)
		local received = {}
		for _, pet in list do
			local entry = table.clone(pet)
			entry.Uid = "p" .. data.NextPetId
			data.NextPetId += 1
			entry.Equipped = false
			entry.Locked = nil
			table.insert(data.Pets, entry)
			data.Index[entry.Id] = true
			-- like a hatch: fills a free equip slot
			if Formulas.EquippedCount(data) < Formulas.EquipSlots(data) then
				entry.Equipped = true
			end
			table.insert(received, entry)
		end
		return received
	end
	local fromA = take(dataA, uidsA)
	local fromB = take(dataB, uidsB)
	give(dataA, fromB)
	give(dataB, fromA)
	return fromA, fromB
end

local function describePets(list): string
	if #list == 0 then
		return "nothing"
	end
	local names = {}
	for _, pet in list do
		table.insert(names, Pets.DisplayName(pet.Id, Pets.TierOf(pet)) .. " (" .. pet.Uid .. ")")
	end
	return table.concat(names, ", ")
end

-- Runs when the countdown ends. Returns true when the pets were swapped. Only the countdown it started
-- (same token) can complete a trade, and only once.
function TradeService.Execute(trade, token: number): boolean
	if type(trade) ~= "table" or trade.State ~= "Countdown" or trade.Token ~= token then
		return false
	end
	if trades[trade.A] ~= trade or trades[trade.B] ~= trade or now() + 0.05 < trade.CountdownEnd then
		return false
	end
	local a, b = trade.A, trade.B
	local frozen = trade.Frozen
	trade.State = "Done" -- from here on a second call does nothing
	trade.Token += 1

	local DataService = Registry.DataService
	local dataA, dataB = usable(a), usable(b)
	local problem = nil
	if not dataA or not dataB then
		problem = "a player left."
	elseif DataService.CanSave(a) ~= DataService.CanSave(b) then
		-- one side's data wouldn't be saved: the pets would be lost or copied
		problem = "a player's data can't be saved right now."
	elseif not frozen then
		problem = "the offers changed."
	end
	local uidsA, uidsB = frozen and frozen[a], frozen and frozen[b]
	if not problem then
		-- the offers must still be exactly what both players saw when they pressed Ready
		if table.concat(uidsA, ",") ~= table.concat(trade.Offers[a], ",") or table.concat(uidsB, ",") ~= table.concat(trade.Offers[b], ",") then
			problem = "the offers changed."
		end
	end
	problem = problem
		or checkOffer(trade, a, dataA, uidsA)
		or checkOffer(trade, b, dataB, uidsB)
		or storageProblem(a, dataA, #uidsA, #uidsB)
		or storageProblem(b, dataB, #uidsB, #uidsA)
	if problem then
		endTrade(trade, "Cancelled", "Trade cancelled: " .. problem)
		return false
	end

	local fromA, fromB = swap(trade, dataA, dataB, uidsA, uidsB)

	print(string.format(
		"[Trade] #%d %s (%d) gave %s; %s (%d) gave %s",
		trade.Id,
		a.Name,
		a.UserId,
		describePets(fromA),
		b.Name,
		b.UserId,
		describePets(fromB)
	))

	local PetService = Registry.PetService
	for _, entry in { { a, dataA }, { b, dataB } } do
		DataService.Replicate(entry[1], "Index")
		PetService.Refresh(entry[1], entry[2])
	end
	endTrade(trade, "Completed", "Trade complete! 🎉")
	-- save both straight away (DataService's normal path, with its session lock)
	task.spawn(DataService.Save, a, false)
	task.spawn(DataService.Save, b, false)
	return true
end

local function startCountdown(trade)
	trade.State = "Countdown"
	trade.Token += 1
	trade.CountdownEnd = now() + CONFIG.Countdown
	trade.Frozen = { [trade.A] = table.clone(trade.Offers[trade.A]), [trade.B] = table.clone(trade.Offers[trade.B]) }
	local token = trade.Token
	broadcast(trade)
	task.delay(CONFIG.Countdown, function()
		TradeService.Execute(trade, token)
	end)
end

---------------------------------------------------------------------------
-- Public API (each returns { Ok = true } or Net.Fail(message))
---------------------------------------------------------------------------
function TradeService.Get(player: Player)
	return trades[player]
end

function TradeService.IsTrading(player: Player): boolean
	return trades[player] ~= nil
end

-- True while this pet is in its owner's trade offer (PetService refuses to equip, delete or craft it)
function TradeService.IsOffered(player: Player, uid: string): boolean
	local trade = trades[player]
	return trade ~= nil and table.find(trade.Offers[player], uid) ~= nil
end

-- Ends this player's trade and drops their requests (leaving, hatching, an admin reset).
-- reason says what the player did, for their partner: "left", "started hatching"
function TradeService.EndFor(player: Player, reason: string?)
	local trade = trades[player]
	if trade then
		local partnerMessage = "Trade cancelled: " .. displayName(player) .. " " .. (reason or "cancelled it") .. "."
		if trade.A == player then
			endTrade(trade, "Cancelled", "Trade cancelled.", partnerMessage)
		else
			endTrade(trade, "Cancelled", partnerMessage, "Trade cancelled.")
		end
	end
	dropAllRequests(player)
end

function TradeService.Request(sender: Player, target)
	if not isPlayer(target) or not present(target) then
		return Net.Fail("That player isn't in this server.")
	end
	if target == sender then
		return Net.Fail("You can't trade with yourself!")
	end
	local senderData, targetData = usable(sender), usable(target)
	if not senderData then
		return Net.Fail("Still loading...")
	end
	if not targetData then
		return Net.Fail(displayName(target) .. " is still loading.")
	end
	if trades[sender] then
		return Net.Fail("Finish your current trade first!")
	end
	if trades[target] then
		return Net.Fail(displayName(target) .. " is already trading.")
	end
	if targetData.Settings and targetData.Settings.AllowTrades == false then
		return Net.Fail(displayName(target) .. " isn't accepting trade requests.")
	end
	-- They already asked us: that's a yes from both sides
	if pendingRequest(sender, target) then
		dropRequest(sender, target, true)
		startTrade(target, sender)
		return { Ok = true, Started = true }
	end
	if pendingRequest(target, sender) then
		return Net.Fail("You already asked " .. displayName(target) .. "!")
	end
	local time = now()
	local asked = lastAsked[sender] and lastAsked[sender][target]
	if asked and time - asked < CONFIG.RequestCooldown then
		return Net.Fail(string.format("Wait %d s before asking %s again.", math.ceil(CONFIG.RequestCooldown - (time - asked)), displayName(target)))
	end
	if lastRequest[sender] and time - lastRequest[sender] < CONFIG.RequestInterval then
		return Net.Fail("Slow down!")
	end
	local pending = requests[target] or {}
	local count = 0
	for _ in pending do
		count += 1
	end
	if count >= CONFIG.MaxPendingRequests then
		return Net.Fail(displayName(target) .. " has too many trade requests right now.")
	end

	local expires = time + CONFIG.RequestTimeout
	pending[sender] = expires
	requests[target] = pending
	lastAsked[sender] = lastAsked[sender] or {}
	lastAsked[sender][target] = time
	lastRequest[sender] = time
	fire(target, "Request", { From = sender.UserId, Name = sender.Name, DisplayName = displayName(sender), Expires = CONFIG.RequestTimeout })
	task.delay(CONFIG.RequestTimeout, function()
		local current = requests[target]
		if current and current[sender] == expires then
			dropRequest(target, sender, true)
		end
	end)
	return { Ok = true }
end

function TradeService.Respond(target: Player, sender, accept: boolean)
	if not isPlayer(sender) or not pendingRequest(target, sender) then
		return Net.Fail("That trade request has expired.")
	end
	dropRequest(target, sender, false)
	if not accept then
		if present(sender) then
			Net.Notify(sender, displayName(target) .. " declined your trade request.", "Info")
		end
		return { Ok = true }
	end
	if not present(sender) or not usable(sender) then
		return Net.Fail(displayName(sender) .. " left the server.")
	end
	if not usable(target) then
		return Net.Fail("Still loading...")
	end
	if trades[target] then
		return Net.Fail("Finish your current trade first!")
	end
	if trades[sender] then
		return Net.Fail(displayName(sender) .. " is already trading.")
	end
	startTrade(sender, target)
	return { Ok = true }
end

function TradeService.AddPet(player: Player, uid)
	local trade = trades[player]
	if not trade then
		return Net.Fail("You're not trading.")
	end
	local data = usable(player)
	if not data or type(uid) ~= "string" or #uid > MAX_UID_LENGTH then
		return Net.Fail("Pet not found.")
	end
	local offer = trade.Offers[player]
	if table.find(offer, uid) then
		return Net.Fail("That pet is already in the trade.")
	end
	if #offer >= CONFIG.MaxPets then
		return Net.Fail(string.format("You can trade up to %d pets at once.", CONFIG.MaxPets))
	end
	local pet = findPet(data, uid)
	if not pet then
		return Net.Fail("Pet not found.")
	end
	if not tradeable(pet) then
		return Net.Fail("This pet can't be traded.")
	end
	if pet.Equipped then
		-- offered pets stay unequipped until the trade is over
		pet.Equipped = false
		Registry.PetService.Refresh(player, data)
	end
	table.insert(offer, uid)
	unreadyAll(trade)
	broadcast(trade)
	return { Ok = true }
end

function TradeService.RemovePet(player: Player, uid)
	local trade = trades[player]
	if not trade then
		return Net.Fail("You're not trading.")
	end
	local offer = trade.Offers[player]
	local index = type(uid) == "string" and table.find(offer, uid)
	if not index then
		return Net.Fail("That pet isn't in the trade.")
	end
	table.remove(offer, index)
	unreadyAll(trade)
	broadcast(trade)
	return { Ok = true }
end

function TradeService.SetReady(player: Player, ready)
	local trade = trades[player]
	if not trade then
		return Net.Fail("You're not trading.")
	end
	if type(ready) ~= "boolean" then
		return Net.Fail("Invalid request.")
	end
	if not ready then
		if trade.Ready[player] or trade.State == "Countdown" then
			unreadyAll(trade)
			broadcast(trade)
		end
		return { Ok = true }
	end
	if trade.State == "Countdown" or trade.Ready[player] then
		return { Ok = true }
	end
	local partner = other(trade, player)
	if #trade.Offers[player] == 0 and #trade.Offers[partner] == 0 then
		return Net.Fail("Add a pet to the trade first!")
	end
	local myData, theirData = usable(player), usable(partner)
	if not myData or not theirData then
		return Net.Fail("Still loading...")
	end
	-- drop offered pets that are gone (shouldn't happen: PetService protects them) before anyone commits
	local problem = checkOffer(trade, player, myData, trade.Offers[player]) or checkOffer(trade, partner, theirData, trade.Offers[partner])
	if problem then
		return Net.Fail(problem)
	end
	problem = storageProblem(player, myData, #trade.Offers[player], #trade.Offers[partner])
		or storageProblem(partner, theirData, #trade.Offers[partner], #trade.Offers[player])
	if problem then
		return Net.Fail(problem)
	end
	trade.Ready[player] = true
	if trade.Ready[partner] then
		startCountdown(trade)
	else
		broadcast(trade)
	end
	return { Ok = true }
end

function TradeService.Cancel(player: Player)
	local trade = trades[player]
	if not trade then
		return { Ok = true }
	end
	TradeService.EndFor(player, "cancelled it")
	return { Ok = true }
end

-- The player's trade as they see it (the panel asks when it opens), plus who is asking them to trade
function TradeService.State(player: Player)
	local trade = trades[player]
	local incoming = {}
	for sender, expires in requests[player] or {} do
		if present(sender) and expires > now() then
			table.insert(incoming, { From = sender.UserId, Name = sender.Name, DisplayName = displayName(sender), Expires = expires - now() })
		end
	end
	local outgoing = {}
	for target, pending in requests do
		local expires = pending[player]
		if expires and expires > now() then
			table.insert(outgoing, target.UserId)
		end
	end
	return { Ok = true, Trade = trade and view(trade, player), Incoming = incoming, Outgoing = outgoing }
end

local function resolve(userId): Player?
	if type(userId) ~= "number" or userId ~= userId or userId % 1 ~= 0 then
		return nil
	end
	return Players:GetPlayerByUserId(userId)
end

-- Remotes.TradeAction:InvokeServer(action, ...)
function TradeService.Handle(player: Player, action, arg1, arg2)
	if type(action) ~= "string" then
		return Net.Fail("Invalid request.")
	end
	if action == "State" then
		return TradeService.State(player)
	elseif action == "Request" then
		local target = resolve(arg1)
		if not target then
			return Net.Fail("That player isn't in this server.")
		end
		return TradeService.Request(player, target)
	elseif action == "Respond" then
		if type(arg2) ~= "boolean" then
			return Net.Fail("Invalid request.")
		end
		return TradeService.Respond(player, resolve(arg1), arg2)
	elseif action == "Add" then
		return TradeService.AddPet(player, arg1)
	elseif action == "Remove" then
		return TradeService.RemovePet(player, arg1)
	elseif action == "Ready" then
		return TradeService.SetReady(player, arg1)
	elseif action == "Cancel" then
		return TradeService.Cancel(player)
	end
	return Net.Fail("Unknown action.")
end

-- Other players see a "trades off" / "busy" label from these attributes
local function publishSetting(player: Player, data)
	if present(player) and data and data.Settings then
		player:SetAttribute("TradesOff", if data.Settings.AllowTrades == false then true else nil)
	end
end

function TradeService.Init()
	Remotes.TradeAction.OnServerInvoke = function(player, action, arg1, arg2)
		if not Net.RateLimit(player, "TradeAction", 0.1) then
			return Net.Fail("Slow down!")
		end
		local ok, result = pcall(TradeService.Handle, player, action, arg1, arg2)
		if not ok then
			warn("[Trade] " .. player.Name .. " " .. tostring(action) .. " failed: " .. tostring(result))
			return Net.Fail("Something went wrong.")
		end
		return result
	end

	local DataService = Registry.DataService
	DataService.PlayerLoaded:Connect(publishSetting)
	DataService.Changed:Connect(function(player, key, value)
		if key == "Settings" then
			publishSetting(player, DataService.Get(player))
		end
	end)
	-- the final save is starting: the trade must be over before it serializes the data
	DataService.PlayerLeaving:Connect(function(player)
		TradeService.EndFor(player, "left")
	end)
	Players.PlayerRemoving:Connect(function(player)
		TradeService.EndFor(player, "left")
		lastAsked[player] = nil
		lastRequest[player] = nil
		for _, asked in lastAsked do
			asked[player] = nil
		end
	end)
end

return TradeService
