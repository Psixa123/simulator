--!nonstrict
-- Owner-only admin commands, used by the Admin panel (src/client/UI/Panels/Admin.luau).
--
-- Who is an admin is decided here on the server, again for every request; the client is never trusted:
--   * the place owner: game.CreatorId for a user-owned place, or for a group-owned place a member of the
--     owning group with at least GameConfig.Admins.MinGroupRank
--   * every UserId in GameConfig.Admins.UserIds
--   * everyone in Roblox Studio (local testing)
-- Admins get the "IsAdmin" attribute on their Player so their client builds the panel. It only shows or
-- hides the interface: a client that sets it on itself still gets every command refused here.
--
-- One RemoteFunction: Remotes.AdminCommand:InvokeServer(command, args) answers
-- { Ok = true, Message, Info? } or { Ok = false, Error }. Every argument is type and range checked
-- (COMMANDS below; unknown arguments are refused), commands go through the game's own services so changes
-- save and replicate exactly like normal play, and each command is logged to the server output ("[Admin]").
-- args.Target = a player's Name (or DisplayName) in this server picks who a command applies to; it is the
-- admin themself when left out. Targeted commands answer with Info, a summary of the target (Inspect).
--
-- Commands (args):
--   Volts      Mode "Give" | "Set", Amount                   Energy  Mode "Give" | "Set" | "Fill" | "Empty", Amount?
--   Upgrade    Upgrade (id or "All"), Level                  Rebirths  Count (Climate Shifts)
--   Boost      Boost, Minutes (0 clears it)                  Pass    Pass (key or "All"), Owned (this session)
--   Zone       Zone (unlocked up to; 1 relocks the rest)     Teleport  To = 0 (hub) .. #Zones | "Arena"
--   Pets       Pet, Tier?, Count?                            Inspect   (a summary of the target)
--   Goto / Bring  (the admin to the target / the target to the admin)
--   Reset      Confirm = "RESET" (the admin's own data only)
--   MegaStorm  Kind "Summon" (warning now, storm in 20 s) | "Rainbow" (Rainbow Hurricane in 40 s)
--   Weather    Zone, Count?, Type? (needs WeatherService.SpawnCells)
--   Announce   Text (filtered, shown to everyone in the server)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Monetization = require(Shared.Config.Monetization)
local Pets = require(Shared.Config.Pets)
local Zones = require(Shared.Config.Zones)
local Weather = require(Shared.Config.Weather)
local MapLayout = require(Shared.Config.MapLayout)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Registry)
local Net = require(script.Parent.Net)
local CharacterGear = require(script.Parent.CharacterGear)

local AdminService = {}

local MAX_VOLTS = 1e30
local MAX_ENERGY = 1e30
local MAX_SHIFTS = 1000
local MAX_BOOST_MINUTES = 7 * 24 * 60
local MAX_PETS_PER_COMMAND = 50
local PET_LIMIT = GameConfig.Pets.MaxStorage + 90 -- admins can go over storage (to test it), up to here
local MAX_CELLS = 20
local MAX_ANNOUNCE = 150
local RAINBOW_DELAY = GameConfig.MegaStorm.WarningTime + 10 -- the Rainbow Hurricane still gets a full warning
local RATE_LIMIT = 0.15 -- seconds between an admin's commands
local REJECT_LOG_INTERVAL = 30 -- a non-admin's refused calls are logged at most this often

local adminCache = {} -- [Player] = true / false once decided
local rejectLogged = {} -- [Player] = os.clock() of the last logged refusal

---------------------------------------------------------------------------
-- Who is an admin
---------------------------------------------------------------------------
-- Returns isAdmin, decided (false when a group rank lookup failed and should be tried again later)
local function checkAdmin(player: Player): (boolean, boolean)
	if RunService:IsStudio() then
		return true, true
	end
	if table.find(GameConfig.Admins.UserIds, player.UserId) then
		return true, true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return game.CreatorId ~= 0 and player.UserId == game.CreatorId, true
	elseif game.CreatorType == Enum.CreatorType.Group then
		-- (typed as any: the type definitions already point at a newer GroupService API whose result
		-- shape isn't settled; this call is the documented way to read a member's rank)
		local ok, rank = pcall(function()
			return (player :: any):GetRankInGroupAsync(game.CreatorId)
		end)
		if not ok or type(rank) ~= "number" then
			return false, false
		end
		return rank >= GameConfig.Admins.MinGroupRank, true
	end
	return false, true
end

-- Server-side admin check (cached per player; a failed group lookup is retried on the next call)
function AdminService.IsAdmin(player: Player): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	local cached = adminCache[player]
	if cached ~= nil then
		return cached
	end
	local isAdmin, decided = checkAdmin(player)
	if decided and player.Parent then
		adminCache[player] = isAdmin
	end
	return isAdmin
end

-- Tells an admin's client to build the panel. A failed group rank lookup is tried a few more times.
local function markPlayer(player: Player)
	for attempt = 1, 4 do
		if not player.Parent then
			return
		end
		if AdminService.IsAdmin(player) then
			player:SetAttribute("IsAdmin", true)
			return
		elseif adminCache[player] ~= nil then
			return -- decided: not an admin
		end
		task.wait(attempt * 5)
	end
end

---------------------------------------------------------------------------
-- Argument checks: each returns ok, reason
---------------------------------------------------------------------------
local function int(min: number, max: number)
	return function(value)
		if type(value) ~= "number" or value ~= value or value % 1 ~= 0 then
			return false, "must be a whole number"
		end
		if value < min or value > max then
			return false, string.format("must be between %s and %s", Format.Number(min), Format.Number(max))
		end
		return true
	end
end

local function oneOf(list: { string })
	local allowed = {}
	for _, item in list do
		allowed[item] = true
	end
	return function(value)
		if type(value) ~= "string" or not allowed[value] then
			return false, "isn't valid"
		end
		return true
	end
end

local function bool()
	return function(value)
		return type(value) == "boolean", "must be true or false"
	end
end

local function text(maxLength: number)
	return function(value)
		if type(value) ~= "string" then
			return false, "must be text"
		end
		if utf8.len(value) == nil then
			return false, "isn't valid text"
		end
		local length = utf8.len(value)
		if string.match(value, "^%s*$") or length > maxLength then
			return false, "must be 1 to " .. maxLength .. " characters"
		end
		return true
	end
end

-- Teleport destinations: 0 (the hub) .. #Zones, "Hub" or "Arena"
local function destination()
	local zone = int(0, #Zones)
	return function(value)
		if value == "Hub" or value == "Arena" then
			return true
		end
		local ok = zone(value)
		return ok, "must be a zone number, Hub or Arena"
	end
end

local function keysOf(map, extra: string?): { string }
	local list = {}
	for key in map do
		table.insert(list, key)
	end
	table.sort(list)
	if extra then
		table.insert(list, extra)
	end
	return list
end

local maxUpgradeLevel = 1
for _, def in GameConfig.Upgrades do
	maxUpgradeLevel = math.max(maxUpgradeLevel, def.MaxLevel)
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function ok(message: string)
	return { Ok = true, Message = message }
end

local function name(player: Player): string
	return player.DisplayName
end

-- "You" or the target's display name, for messages shown to the admin
local function who(ctx): string
	return if ctx.Target == ctx.Admin then "You" else name(ctx.Target)
end

local function whose(ctx): string
	return if ctx.Target == ctx.Admin then "Your" else name(ctx.Target) .. "'s"
end

local function zoneLabel(zoneId: number): string
	local zone = Zones.Get(zoneId)
	return if zone then zone.Icon .. " " .. zone.Name else "zone " .. zoneId
end

-- Volts per unit of energy at the best zone the player can catch in (what a tank refill is worth)
local function energyValue(data): number
	return Zones[Formulas.BestCatchableZone(data)].Value
end

-- Keeps the tank within its capacity (after an upgrade or pass change), keeping its worth in proportion
local function capEnergy(player: Player, data, wanted: number)
	wanted = math.max(0, wanted)
	if wanted >= data.Energy then
		return
	end
	data.TankValue = if wanted > 0 and data.Energy > 0 then data.TankValue * wanted / data.Energy else 0
	data.Energy = wanted
	Registry.DataService.Replicate(player, "Energy", "TankValue")
end

-- Finds a player in this server by Name, then DisplayName, then the start of a Name (any case)
local function findPlayer(query: string): (Player?, string?)
	local lower = string.lower(query)
	local byDisplay, byPrefix = {}, {}
	for _, other in Players:GetPlayers() do
		local otherName = string.lower(other.Name)
		if otherName == lower then
			return other, nil
		end
		if string.lower(other.DisplayName) == lower then
			table.insert(byDisplay, other)
		end
		if string.sub(otherName, 1, #lower) == lower then
			table.insert(byPrefix, other)
		end
	end
	if #byDisplay == 1 then
		return byDisplay[1], nil
	elseif #byDisplay == 0 and #byPrefix == 1 then
		return byPrefix[1], nil
	elseif #byDisplay > 1 or #byPrefix > 1 then
		return nil, string.format('More than one player matches "%s".', query)
	end
	return nil, string.format('There is no player called "%s" in this server.', query)
end

-- A summary of a player's data for the panel's target card
local function inspect(player: Player, data)
	local now = os.time()
	local boosts = {}
	for boostName, endTime in data.Boosts do
		boosts[boostName] = math.max(0, endTime - now)
	end
	local passes = {}
	for passKey in data.Passes do
		passes[passKey] = true
	end
	return {
		Name = player.Name,
		DisplayName = player.DisplayName,
		UserId = player.UserId,
		Admin = adminCache[player] == true,
		Volts = data.Volts,
		Energy = data.Energy,
		Capacity = Formulas.TankCapacity(data),
		Zone = data.Zone,
		Rebirths = data.Rebirths,
		Upgrades = table.clone(data.Upgrades),
		Pets = #data.Pets,
		Passes = passes,
		Boosts = boosts,
	}
end

-- Roblox requires text typed by a person to be filtered before other players see it
local function filterBroadcast(admin: Player, message: string): (string?, string?)
	local filtered
	local success, err = pcall(function()
		local result = TextService:FilterStringAsync(message, admin.UserId, Enum.TextFilterContext.PublicChat)
		filtered = result:GetNonChatStringForBroadcastAsync()
	end)
	if success and type(filtered) == "string" then
		return filtered, nil
	end
	if RunService:IsStudio() then
		return message, nil -- Studio can't always reach the filter
	end
	warn("[Admin] Couldn't filter an announcement: " .. tostring(err))
	return nil, "The chat filter didn't answer, try again in a moment."
end

local function escapeRichText(value: string): string
	return (string.gsub(value, "[<>&]", { ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;" }))
end

local function teleport(player: Player, cframe: CFrame): boolean
	return Registry.ZoneService.TeleportTo(player, cframe)
end

-- Everything a brand new player starts with; keeps settings, receipts, gamepasses and NextPetId
-- (pet ids are never reused)
local function resetData(player: Player, data)
	Registry.WeatherService.StopCatch(player)
	data.Volts = 0
	data.TotalVolts = 0
	data.Energy = 0
	data.TankValue = 0
	data.Rebirths = 0
	data.Zone = 1
	data.Upgrades = {}
	for upgradeId in GameConfig.Upgrades do
		data.Upgrades[upgradeId] = 1
	end
	data.Pets = {}
	data.Index = {}
	data.Boosts = {}
	for boostName in GameConfig.Boosts do
		data.Boosts[boostName] = 0
	end
	data.Daily = { Streak = 0, LastClaim = 0 }
	data.Codes = {}
	for key in data.Stats do
		data.Stats[key] = 0
	end
	data.GiftsClaimed = {}
	data.SessionStart = os.time()

	local DataService = Registry.DataService
	DataService.Replicate(
		player,
		"Volts",
		"TotalVolts",
		"Energy",
		"TankValue",
		"Rebirths",
		"Zone",
		"Upgrades",
		"Index",
		"Boosts",
		"Daily",
		"Codes",
		"Stats",
		"GiftsClaimed",
		"SessionStart"
	)
	Registry.PetService.Refresh(player, data)
	CharacterGear.DressPlayer(player, 0)
	teleport(player, MapLayout.ZoneSpawn(0))
	task.spawn(DataService.Save, player, false)
end

---------------------------------------------------------------------------
-- Commands. Args: name -> check; Optional: names that may be left out; Target: applies to args.Target
-- (default the admin). Run(ctx) gets { Admin, Target, Data (the target's), Args } and returns a reply.
---------------------------------------------------------------------------
local COMMANDS = {}

COMMANDS.Volts = {
	Args = { Mode = oneOf({ "Give", "Set" }), Amount = int(-MAX_VOLTS, MAX_VOLTS) },
	Target = true,
	Run = function(ctx)
		local data, amount = ctx.Data, ctx.Args.Amount
		local change = amount
		if ctx.Args.Mode == "Set" then
			if amount < 0 then
				return Net.Fail("Volts can't be negative.")
			end
			change = amount - data.Volts
		end
		change = math.max(change, -data.Volts) -- never below 0
		-- Not counted as earned, so leaderboards and lifetime stats stay honest
		Registry.EconomyService.AddVolts(ctx.Target, change, false)
		return ok(string.format("%s now %s ⚡ %s Volts.", who(ctx), if ctx.Target == ctx.Admin then "have" else "has", Format.Number(data.Volts)))
	end,
}

COMMANDS.Energy = {
	Args = { Mode = oneOf({ "Give", "Set", "Fill", "Empty" }), Amount = int(0, MAX_ENERGY) },
	Optional = { Amount = true },
	Target = true,
	Run = function(ctx)
		local player, data, args = ctx.Target, ctx.Data, ctx.Args
		local capacity = Formulas.TankCapacity(data)
		local wanted
		if args.Mode == "Give" or args.Mode == "Set" then
			if args.Amount == nil then
				return Net.Fail("Enter an amount of energy.")
			end
			wanted = if args.Mode == "Give" then data.Energy + args.Amount else args.Amount
		elseif args.Mode == "Fill" then
			wanted = capacity
		else
			wanted = 0
		end
		wanted = math.clamp(wanted, 0, capacity)
		if wanted > data.Energy then
			Registry.EconomyService.AddEnergy(player, wanted - data.Energy, energyValue(data))
		else
			capEnergy(player, data, wanted)
		end
		return ok(string.format("%s tank: %s / %s energy.", whose(ctx), Format.Number(math.floor(data.Energy)), Format.Number(capacity)))
	end,
}

COMMANDS.Upgrade = {
	Args = { Upgrade = oneOf(keysOf(GameConfig.Upgrades, "All")), Level = int(1, maxUpgradeLevel) },
	Target = true,
	Run = function(ctx)
		local data, args = ctx.Data, ctx.Args
		local ids = if args.Upgrade == "All" then GameConfig.UpgradeOrder else { args.Upgrade }
		local parts = {}
		for _, upgradeId in ids do
			local def = GameConfig.Upgrades[upgradeId]
			local level = math.min(args.Level, def.MaxLevel)
			data.Upgrades[upgradeId] = level
			table.insert(parts, string.format("%s %s Lv %d", def.Icon, def.Name, level))
		end
		Registry.DataService.Replicate(ctx.Target, "Upgrades")
		capEnergy(ctx.Target, data, Formulas.TankCapacity(data))
		return ok(string.format("%s upgrades: %s.", whose(ctx), table.concat(parts, ", ")))
	end,
}

COMMANDS.Rebirths = {
	Args = { Count = int(0, MAX_SHIFTS) },
	Target = true,
	Run = function(ctx)
		ctx.Data.Rebirths = ctx.Args.Count
		Registry.DataService.Replicate(ctx.Target, "Rebirths")
		CharacterGear.DressPlayer(ctx.Target, ctx.Args.Count)
		return ok(string.format("%s Climate Shifts: 🌀 %d.", whose(ctx), ctx.Args.Count))
	end,
}

COMMANDS.Boost = {
	Args = { Boost = oneOf(keysOf(GameConfig.Boosts)), Minutes = int(0, MAX_BOOST_MINUTES) },
	Target = true,
	Run = function(ctx)
		local boost = GameConfig.Boosts[ctx.Args.Boost]
		if ctx.Args.Minutes == 0 then
			ctx.Data.Boosts[ctx.Args.Boost] = 0
			Registry.DataService.Replicate(ctx.Target, "Boosts")
			return ok(string.format("Cleared %s %s boost.", whose(ctx), boost.Name))
		end
		-- The target gets the usual "boost active" toast; the admin gets this answer instead of both
		Registry.BoostService.Add(ctx.Target, ctx.Args.Boost, ctx.Args.Minutes * 60, ctx.Target == ctx.Admin)
		local whom = if ctx.Target == ctx.Admin then "" else " for " .. name(ctx.Target)
		return ok(string.format("%s %s boost%s: +%s.", boost.Icon, boost.Name, whom, Format.Duration(ctx.Args.Minutes * 60)))
	end,
}

COMMANDS.Pass = {
	Args = { Pass = oneOf(keysOf(Monetization.Gamepasses, "All")), Owned = bool() },
	Target = true,
	Run = function(ctx)
		local data, args = ctx.Data, ctx.Args
		local keys = if args.Pass == "All" then keysOf(Monetization.Gamepasses) else { args.Pass }
		for _, passKey in keys do
			data.Passes[passKey] = if args.Owned then true else nil
		end
		-- Passes is a session key: Roblox's own ownership check decides again when they rejoin
		Registry.DataService.Replicate(ctx.Target, "Passes")
		Registry.PetService.Refresh(ctx.Target, data) -- +3 Pet Slots changes who is equipped
		capEnergy(ctx.Target, data, Formulas.TankCapacity(data)) -- Mega Tank
		local pass = Monetization.Gamepasses[args.Pass]
		local label = if pass then pass.Icon .. " " .. pass.Name else "every gamepass"
		local whom = if ctx.Target == ctx.Admin then "" elseif args.Owned then " to " .. name(ctx.Target) else " from " .. name(ctx.Target)
		return ok(string.format("%s %s%s for this session.", if args.Owned then "Granted" else "Removed", label, whom))
	end,
}

COMMANDS.Zone = {
	Args = { Zone = int(1, #Zones) },
	Target = true,
	Run = function(ctx)
		ctx.Data.Zone = ctx.Args.Zone
		Registry.DataService.Replicate(ctx.Target, "Zone")
		return ok(string.format("%s zones: unlocked up to %s.", whose(ctx), zoneLabel(ctx.Args.Zone)))
	end,
}

COMMANDS.Teleport = {
	Args = { To = destination() },
	Target = true,
	Run = function(ctx)
		local to = ctx.Args.To
		local cframe
		if to == "Arena" then
			cframe = MapLayout.ArenaSpawn()
		else
			local zoneId = if to == "Hub" then 0 else to
			if zoneId > ctx.Data.Zone then
				return Net.Fail(string.format("%s %s unlocked %s yet (unlock it under Zones first).", who(ctx), if ctx.Target == ctx.Admin then "haven't" else "hasn't", zoneLabel(zoneId)))
			end
			cframe = MapLayout.ZoneSpawn(zoneId)
		end
		if not teleport(ctx.Target, cframe) then
			return Net.Fail(string.format("%s can't be teleported right now (no character).", name(ctx.Target)))
		end
		return ok(string.format("Teleported %s to %s.", if ctx.Target == ctx.Admin then "you" else name(ctx.Target), if to == "Arena" then "🌪️ the Mega Storm Arena" else zoneLabel(if to == "Hub" then 0 else to)))
	end,
}

COMMANDS.Pets = {
	Args = {
		Pet = oneOf(keysOf(Pets.Pets)),
		Tier = oneOf(keysOf(Pets.Tiers)),
		Count = int(1, MAX_PETS_PER_COMMAND),
	},
	Optional = { Tier = true, Count = true },
	Target = true,
	Run = function(ctx)
		local data, args = ctx.Data, ctx.Args
		local room = PET_LIMIT - #data.Pets
		if room <= 0 then
			return Net.Fail(string.format("%s %d pets already (the admin limit is %d).", if ctx.Target == ctx.Admin then "You have" else name(ctx.Target) .. " has", #data.Pets, PET_LIMIT))
		end
		local tier = args.Tier or "Normal"
		local count = math.min(args.Count or 1, room)
		local added = 0
		for _ = 1, count do
			-- force: admin pets may go over MaxStorage (hatching then waits until some are deleted)
			if Registry.PetService.AddPet(ctx.Target, args.Pet, tier, true) then
				added += 1
			end
		end
		Registry.DataService.Replicate(ctx.Target, "Index")
		Registry.PetService.Refresh(ctx.Target, data)
		local message = string.format("Gave %s %dx %s.", if ctx.Target == ctx.Admin then "you" else name(ctx.Target), added, Pets.DisplayName(args.Pet, tier))
		if #data.Pets > GameConfig.Pets.MaxStorage then
			message ..= string.format(" Storage is over %d, so hatching waits until some are deleted.", GameConfig.Pets.MaxStorage)
		end
		return ok(message)
	end,
}

COMMANDS.Inspect = {
	Target = true,
	Run = function(ctx)
		return ok(string.format("%s (@%s): ⚡ %s Volts, %s, 🌀 %d.", name(ctx.Target), ctx.Target.Name, Format.Number(ctx.Data.Volts), zoneLabel(ctx.Data.Zone), ctx.Data.Rebirths))
	end,
}

COMMANDS.Goto = {
	Target = true,
	Run = function(ctx)
		if ctx.Target == ctx.Admin then
			return Net.Fail("Pick another player on the Players tab first.")
		end
		local root = Net.GetRoot(ctx.Target)
		local adminData = Registry.DataService.Get(ctx.Admin)
		if not root then
			return Net.Fail(name(ctx.Target) .. " has no character right now.")
		end
		if adminData and MapLayout.ZoneAt(root.Position) > adminData.Zone then
			return Net.Fail(string.format("%s is in %s, which you haven't unlocked.", name(ctx.Target), zoneLabel(MapLayout.ZoneAt(root.Position))))
		end
		if not teleport(ctx.Admin, root.CFrame * CFrame.new(0, 0, 5)) then
			return Net.Fail("You can't be teleported right now.")
		end
		return ok("Teleported you to " .. name(ctx.Target) .. ".")
	end,
}

COMMANDS.Bring = {
	Target = true,
	Run = function(ctx)
		if ctx.Target == ctx.Admin then
			return Net.Fail("Pick another player on the Players tab first.")
		end
		local root = Net.GetRoot(ctx.Admin)
		if not root then
			return Net.Fail("You have no character right now.")
		end
		if MapLayout.ZoneAt(root.Position) > ctx.Data.Zone then
			return Net.Fail(string.format("%s hasn't unlocked %s.", name(ctx.Target), zoneLabel(MapLayout.ZoneAt(root.Position))))
		end
		if not teleport(ctx.Target, root.CFrame * CFrame.new(0, 0, -5)) then
			return Net.Fail(name(ctx.Target) .. " can't be teleported right now.")
		end
		return ok("Brought " .. name(ctx.Target) .. " to you.")
	end,
}

COMMANDS.Reset = {
	Args = { Confirm = oneOf({ "RESET" }) },
	Target = true, -- only so a Target other than the admin can be refused clearly
	Run = function(ctx)
		if ctx.Target ~= ctx.Admin then
			return Net.Fail("Reset only works on your own data.")
		end
		resetData(ctx.Admin, ctx.Data)
		return ok("Your data was reset to a brand new save (settings, gamepasses and receipts kept).")
	end,
}

COMMANDS.MegaStorm = {
	Args = { Kind = oneOf({ "Summon", "Rainbow" }) },
	Run = function(ctx)
		if ctx.Args.Kind == "Summon" then
			Registry.MegaStormService.Summon(ctx.Admin)
			return ok(string.format("🌪️ Mega Storm summoned! It arrives in %d s (or right after the storm that's on).", GameConfig.MegaStorm.SummonDelay))
		end
		Registry.MegaStormService.ScheduleRainbow(RAINBOW_DELAY)
		return ok(string.format("🌈 The Rainbow Hurricane now strikes in %d s (after the current storm, if one is on).", RAINBOW_DELAY))
	end,
}

local weatherTypes = keysOf(Weather.Types)
COMMANDS.Weather = {
	Args = { Zone = int(1, #Zones), Count = int(1, MAX_CELLS), Type = oneOf(weatherTypes) },
	Optional = { Count = true, Type = true },
	Run = function(ctx)
		local args = ctx.Args
		local zone = Zones[args.Zone]
		if args.Type and not table.find(zone.Weather, args.Type) then
			return Net.Fail(string.format("%s doesn't appear in %s.", Weather.Types[args.Type].Name or args.Type, zoneLabel(args.Zone)))
		end
		local spawnCells = Registry.WeatherService.SpawnCells
		if type(spawnCells) ~= "function" then
			return Net.Fail("Spawning weather needs WeatherService.SpawnCells, which this server doesn't have yet.")
		end
		local spawned = spawnCells(args.Zone, args.Count or 5, args.Type)
		return ok(string.format("Spawned %d weather cell%s in %s.", spawned, if spawned == 1 then "" else "s", zoneLabel(args.Zone)))
	end,
}

COMMANDS.Announce = {
	Args = { Text = text(MAX_ANNOUNCE) },
	Run = function(ctx)
		local message = string.gsub(ctx.Args.Text, "%c", " ")
		message = string.match(message, "^%s*(.-)%s*$")
		local filtered, err = filterBroadcast(ctx.Admin, message)
		if not filtered then
			return Net.Fail(err)
		end
		Net.NotifyAll("📢 " .. escapeRichText(filtered), "Info")
		return ok("Announced to everyone in the server.")
	end,
}

AdminService.Commands = COMMANDS

---------------------------------------------------------------------------
-- Handling a request
---------------------------------------------------------------------------
-- Checks args against a command's spec. Returns the clean args or nil, reason
function AdminService.Validate(spec, args)
	if args == nil then
		args = {}
	end
	if type(args) ~= "table" then
		return nil, "Bad arguments."
	end
	local allowed = spec.Args or {}
	local count = 0
	for key in args do
		count += 1
		if count > 8 or type(key) ~= "string" then
			return nil, "Bad arguments."
		end
		if allowed[key] == nil and key ~= "Target" then
			return nil, if #key <= 24 then "Unknown argument " .. key .. "." else "Bad arguments."
		end
	end
	if args.Target ~= nil and (not spec.Target or type(args.Target) ~= "string" or #args.Target > 40) then
		return nil, "Bad target."
	end
	local clean = { Target = args.Target }
	for argName, check in allowed do
		local value = args[argName]
		if value == nil then
			if not (spec.Optional and spec.Optional[argName]) then
				return nil, argName .. " is missing."
			end
		else
			local valid, reason = check(value)
			if not valid then
				return nil, argName .. " " .. (reason or "isn't valid") .. "."
			end
			clean[argName] = value
		end
	end
	return clean, nil
end

local function describe(args): string
	local parts = {}
	for key, value in args do
		local shown = if type(value) == "string" then string.format("%q", string.sub(value, 1, 60)) else tostring(value)
		table.insert(parts, key .. "=" .. shown)
	end
	table.sort(parts)
	return if #parts > 0 then " {" .. table.concat(parts, ", ") .. "}" else ""
end

local function log(admin: Player, command: string, args, reply)
	local outcome = if reply.Ok then tostring(reply.Message) else "FAILED: " .. tostring(reply.Error)
	print(string.format("[Admin] %s (%d) %s%s -> %s", admin.Name, admin.UserId, command, describe(args), outcome))
end

function AdminService.Handle(admin: Player, command, args)
	if not AdminService.IsAdmin(admin) then
		local now = os.clock()
		if not rejectLogged[admin] or now - rejectLogged[admin] >= REJECT_LOG_INTERVAL then
			rejectLogged[admin] = now
			warn(string.format("[Admin] Refused %s from %s (%d): not an admin", if type(command) == "string" then string.sub(command, 1, 24) else typeof(command), admin.Name, admin.UserId))
		end
		return Net.Fail("Only admins can do that.")
	end
	if admin:GetAttribute("IsAdmin") ~= true then
		admin:SetAttribute("IsAdmin", true) -- e.g. a group rank lookup that only worked now
	end
	local spec = type(command) == "string" and COMMANDS[command]
	if not spec then
		return Net.Fail("Unknown admin command.")
	end
	-- Per command, so the panel's background Inspect never gets a click refused
	if not Net.RateLimit(admin, "Admin" .. command, RATE_LIMIT) then
		return Net.Fail("Slow down!")
	end
	local clean, reason = AdminService.Validate(spec, args)
	if not clean then
		local reply = Net.Fail(reason)
		log(admin, command, {}, reply)
		return reply
	end

	local target = admin
	if spec.Target and clean.Target and clean.Target ~= "" then
		local found, err = findPlayer(clean.Target)
		if not found then
			local reply = Net.Fail(err)
			log(admin, command, clean, reply)
			return reply
		end
		target = found
	end
	local data = Registry.DataService.Get(target)
	if spec.Target and not data then
		local reply = Net.Fail(name(target) .. "'s data hasn't loaded yet.")
		log(admin, command, clean, reply)
		return reply
	end
	clean.Target = nil

	local ctx = { Admin = admin, Target = target, Data = data, Args = clean }
	local success, reply = pcall(spec.Run, ctx)
	if not success then
		warn(string.format("[Admin] %s failed: %s", command, tostring(reply)))
		reply = Net.Fail("That command failed on the server (see the server output).")
	end
	if reply.Ok and spec.Target and data then
		reply.Info = inspect(target, data)
	end
	if target ~= admin then
		clean.Target = target.Name
	end
	log(admin, command, clean, reply)
	return reply
end

function AdminService.Init()
	Remotes.AdminCommand.OnServerInvoke = function(player, command, args)
		return AdminService.Handle(player, command, args)
	end

	Players.PlayerAdded:Connect(markPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(markPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		adminCache[player] = nil
		rejectLogged[player] = nil
	end)
end

return AdminService
