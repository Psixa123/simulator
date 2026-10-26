--!nonstrict
-- Spawns weather cells in every zone and runs the authoritative vacuum simulation.
-- Clients ask to start/stop catching a target; the server validates range, zone access,
-- power and tank space every tick, drains the cell and fills the player's tank.
-- Equipped pets also drain weather on their own (the "PetTarget" character attribute).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Zones = require(Shared.Config.Zones)
local Weather = require(Shared.Config.Weather)
local MapLayout = require(Shared.Config.MapLayout)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)
local WeatherModels = require(Shared.Models.WeatherModels)

local Registry = require(script.Parent.Registry)
local Net = require(script.Parent.Net)
local StormRadar = require(script.Parent.StormRadar)

local WeatherService = {}

local MEGA_TARGET = -1 -- target id used for the Mega Storm
WeatherService.MegaTarget = MEGA_TARGET

local cells = {} -- [id] = cell
local zoneCells = {} -- [zoneId] = { [id] = cell }
local catchers = {} -- [Player] = targetId
local petStates = {} -- [Player] = { Target = cellId, NextSearch = os.clock(), Full = boolean }
local nextId = 0
local rng = Random.new()
local folder: Folder

local function setTarget(player: Player, targetId: number)
	local character = player.Character
	if character and character:GetAttribute("CatchTarget") ~= targetId then
		character:SetAttribute("CatchTarget", targetId)
	end
end

function WeatherService.StopCatch(player: Player)
	catchers[player] = nil
	setTarget(player, 0)
end

local function startCatch(player: Player, targetId: number)
	catchers[player] = targetId
	setTarget(player, targetId)
end

local function countCells(zoneId: number): number
	local count = 0
	for _ in zoneCells[zoneId] do
		count += 1
	end
	return count
end

local function pickType(zone): string
	local total = 0
	for _, typeId in zone.Weather do
		total += Weather.Rarities[Weather.Types[typeId].Rarity].Weight
	end
	local roll = rng:NextNumber(0, total)
	for _, typeId in zone.Weather do
		roll -= Weather.Rarities[Weather.Types[typeId].Rarity].Weight
		if roll <= 0 then
			return typeId
		end
	end
	return zone.Weather[1]
end

local function findSpot(zoneId: number): Vector3
	local minX, maxX, minZ, maxZ = MapLayout.FieldBounds(zoneId)
	local candidate = Vector3.zero
	for _ = 1, 25 do
		candidate = Vector3.new(rng:NextNumber(minX, maxX), 0, rng:NextNumber(minZ, maxZ))
		local clear = true
		for _, other in zoneCells[zoneId] do
			local dx, dz = other.Position.X - candidate.X, other.Position.Z - candidate.Z
			if dx * dx + dz * dz < GameConfig.CellSpacing * GameConfig.CellSpacing then
				clear = false
				break
			end
		end
		if clear then
			break
		end
	end
	return candidate
end

-- typeId: a weather type from the zone's list (random by rarity when nil). extra = true spawns even
-- when the zone already has its CellCount (admin spawns; those extra cells don't respawn).
-- Returns true when a cell was spawned.
local function spawnCell(zoneId: number, typeId: string?, extra: boolean?): boolean
	local zone = Zones[zoneId]
	if not extra and countCells(zoneId) >= zone.CellCount then
		return false
	end

	local cellType: string = typeId or pickType(zone)
	local def = Weather.Types[cellType]
	local health = Formulas.CellHealth(cellType, zoneId)
	local position = findSpot(zoneId) + Vector3.new(0, WeatherModels.HoverHeight(cellType), 0)

	nextId += 1
	local id = nextId

	local model = WeatherModels.Build(cellType)
	model.Name = "Cell" .. id
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	model:SetAttribute("CellId", id)
	model:SetAttribute("Type", cellType)
	model:SetAttribute("Zone", zoneId)
	model:SetAttribute("Health", health)
	model:SetAttribute("MaxHealth", health)
	model:SetAttribute("Origin", position)
	model.Parent = folder

	local cell = {
		Id = id,
		Type = cellType,
		Zone = zoneId,
		Health = health,
		MaxHealth = health,
		Model = model,
		Position = position,
		Value = Formulas.CellValue(cellType, zoneId),
		Contributors = {},
	}
	cells[id] = cell
	zoneCells[zoneId][id] = cell

	if Weather.Rarities[def.Rarity].Announce then
		for _, player in Players:GetPlayers() do
			local root = Net.GetRoot(player)
			-- Storm Radar owners get their own alert for every zone they've unlocked
			if not StormRadar.Alert(player, cell) and root and MapLayout.ZoneAt(root.Position) == zoneId then
				Net.Effect(player, "RareSpawn", cellType, position)
			end
		end
	end
	return true
end

-- Admin panel (AdminService "Weather"): spawns up to `count` cells in a zone right away, on top of its
-- usual CellCount. typeId: one of the zone's weather types, random when nil. Returns how many spawned.
function WeatherService.SpawnCells(zoneId: number, count: number, typeId: string?): number
	local zone = Zones[zoneId]
	if not zone or not zoneCells[zoneId] or (typeId ~= nil and not table.find(zone.Weather, typeId)) then
		return 0
	end
	local spawned = 0
	for _ = 1, math.clamp(math.floor(count), 0, 20) do
		if spawnCell(zoneId, typeId, true) then
			spawned += 1
		end
	end
	return spawned
end

local function popCell(cell)
	if not cells[cell.Id] then
		return
	end
	cells[cell.Id] = nil
	zoneCells[cell.Zone][cell.Id] = nil

	local def = Weather.Types[cell.Type]
	for player, contributed in cell.Contributors do
		local data = player.Parent and Registry.DataService.Get(player)
		if data then
			local bonus = Registry.EconomyService.AddEnergy(player, contributed * GameConfig.CompletionBonus, cell.Value)
			data.Stats.CellsCaught += 1
			if def.Rarity == "Rare" then
				data.Stats.RareCaught = (data.Stats.RareCaught or 0) + 1
			end
			Net.Effect(player, "CellCaught", cell.Position, cell.Type, (contributed + bonus) * cell.Value)
		end
	end

	for player, targetId in catchers do
		if targetId == cell.Id then
			WeatherService.StopCatch(player)
		end
	end

	Net.EffectAll("CellPop", cell.Position, def.Color, def.Rarity)
	cell.Model:Destroy()

	local respawn = GameConfig.CellRespawnTime
	task.delay(rng:NextNumber(respawn.Min, respawn.Max), spawnCell, cell.Zone)
end

local function tankFullMessage(player: Player)
	Net.NotifyThrottled(player, "TankFull", "🛢️ Your tank is full! Sell it at a Weather Lab (or press SELL).", "Warning", 6)
end

-- Drains up to `power` from a cell into the player's tank (shared by the vacuum and pets).
-- Returns false when the tank is full and can't be auto-sold, so the caller should stop.
-- An Infinite Tank is never full: only the cell's health and the power limit what it drains.
local function drainCell(player: Player, data, cell, power: number, now: number): boolean
	local remoteSell = Formulas.HasPass(data, "RemoteSell")
	if Formulas.IsTankFull(data) then
		if remoteSell then
			Registry.EconomyService.Sell(player, "Auto")
		else
			return false
		end
	end

	local multiplier = Formulas.EnergyMultiplier(data, now)
	local drained = math.min(cell.Health, power, Formulas.TankSpace(data) / multiplier)
	if drained > 0 then
		cell.Health -= drained
		local added = Registry.EconomyService.AddEnergy(player, drained * multiplier, cell.Value)
		cell.Contributors[player] = (cell.Contributors[player] or 0) + added

		if cell.Health <= 1e-6 then
			popCell(cell)
		else
			cell.Model:SetAttribute("Health", cell.Health)
		end
	end

	if remoteSell and Formulas.IsTankFull(data) then
		Registry.EconomyService.Sell(player, "Auto")
	end
	return true
end

-- Zone unlocked and vacuum strong enough for the cell's zone
local function canCatchCell(data, cell): boolean
	return cell.Zone <= data.Zone and Formulas.Power(data) >= Zones[cell.Zone].MinPower
end

---------------------------------------------------------------------------
-- Pets catch weather for you
---------------------------------------------------------------------------
local function setPetTarget(player: Player, targetId: number)
	local character = player.Character
	if character and character:GetAttribute("PetTarget") ~= targetId then
		character:SetAttribute("PetTarget", targetId)
	end
end

-- Nearest catchable cell within `range` (only the player's zone and its neighbours)
local function findPetCell(data, position: Vector3, range: number)
	local zoneId = MapLayout.ZoneAt(position)
	local best, bestDistance = nil, range
	for id = math.max(1, zoneId - 1), math.min(#Zones, zoneId + 1) do
		for _, cell in zoneCells[id] do
			local distance = (cell.Position - position).Magnitude
			if distance <= bestDistance and canCatchCell(data, cell) then
				best, bestDistance = cell, distance
			end
		end
	end
	return best
end

-- Equipped pets drain the player's vacuum target (cell or Mega Storm), otherwise the nearest
-- cell in pet range. The chosen cell is kept until it pops or goes out of range; when idle
-- we only search again every SearchInterval seconds.
local function petTick(player: Player, now: number)
	local state = petStates[player]
	if not state then
		state = { Target = 0, NextSearch = 0, Full = false }
		petStates[player] = state
	end

	local data = Registry.DataService.Get(player)
	local root = Net.GetRoot(player)
	local power = if data then Formulas.PetCatchPower(data) else 0
	if not data or not root or power <= 0 then
		state.Target = 0
		setPetTarget(player, 0)
		return
	end

	local targetId = catchers[player]
	if targetId == MEGA_TARGET then
		state.Target = 0
		setPetTarget(player, if Registry.MegaStormService.Drain(player, data, root, power) then MEGA_TARGET else 0)
		return
	end

	-- Pets stop when the tank is full (Remote Sell empties it inside drainCell instead)
	if Registry.EconomyService.IsTankFull(data) and not Formulas.HasPass(data, "RemoteSell") then
		if not state.Full and state.Target ~= 0 then
			tankFullMessage(player)
		end
		state.Full = true
		setPetTarget(player, 0)
		return
	end
	state.Full = false

	-- Pets rest while you stand on a sell pad, otherwise the pad would sell for them forever
	-- (a free Remote Sell). Remote Sell owners keep their pets working.
	if not Formulas.HasPass(data, "RemoteSell") and Registry.EconomyService.OnSellPad(root.Position) then
		state.Target = 0
		setPetTarget(player, 0)
		return
	end

	local cell = targetId and cells[targetId]
	if not cell then
		cell = cells[state.Target]
		local range = Formulas.PetRange(data)
		if cell and ((cell.Position - root.Position).Magnitude > range + GameConfig.CatchRangeLeeway or not canCatchCell(data, cell)) then
			cell = nil
		end
		local clock = os.clock()
		if not cell and (state.Target ~= 0 or clock >= state.NextSearch) then
			cell = findPetCell(data, root.Position, range)
			state.NextSearch = clock + GameConfig.Pets.AutoCatch.SearchInterval
		end
	end

	state.Target = if cell then cell.Id else 0
	if cell and drainCell(player, data, cell, power, now) then
		setPetTarget(player, cell.Id)
	else
		setPetTarget(player, 0)
	end
end

-- One vacuum tick for a player catching `targetId`
local function catchTick(player: Player, targetId: number, now: number)
	local data = Registry.DataService.Get(player)
	local root = Net.GetRoot(player)
	local character = player.Character
	if not data or not root or not character or not character:FindFirstChild("StormVacuum") then
		WeatherService.StopCatch(player)
		return
	end

	if targetId == MEGA_TARGET then
		if not Registry.MegaStormService.Drain(player, data, root) then
			WeatherService.StopCatch(player)
		end
		return
	end

	local cell = cells[targetId]
	if not cell then
		WeatherService.StopCatch(player)
		return
	end
	if (root.Position - cell.Position).Magnitude > Formulas.Range(data) + GameConfig.CatchRangeLeeway then
		WeatherService.StopCatch(player)
		return
	end

	if not drainCell(player, data, cell, Formulas.Power(data), now) then
		WeatherService.StopCatch(player)
		tankFullMessage(player)
	end
end

-- Each player is ticked on their own, so an error with one player's state can never stop everyone
-- else's vacuum and pets (each different error is reported once)
local reported = {} -- [Player] = the last error reported for them
local function guarded(player: Player, fn, ...): boolean
	local ok, err = pcall(fn, ...)
	if not ok and reported[player] ~= err then
		reported[player] = err
		warn(string.format("[WeatherService] %s: %s", player.Name, tostring(err)))
	end
	return ok
end

local function tick()
	local now = os.time()
	for player, targetId in catchers do
		if not guarded(player, catchTick, player, targetId, now) then
			WeatherService.StopCatch(player)
		end
	end

	for _, player in Players:GetPlayers() do
		guarded(player, petTick, player, now)
	end
end

local function onCatch(player: Player, action, targetId)
	if action == "Stop" then
		WeatherService.StopCatch(player)
		return
	end
	if action ~= "Start" or type(targetId) ~= "number" then
		return
	end
	if not Net.RateLimit(player, "CatchStart", 0.08) then
		return
	end

	local data = Registry.DataService.Get(player)
	local root = Net.GetRoot(player)
	local character = player.Character
	if not data or not root or not character or not character:FindFirstChild("StormVacuum") then
		return
	end
	if character:GetAttribute("Stunned") then
		return -- zapped by lightning (HazardService)
	end

	if targetId == MEGA_TARGET then
		if Registry.MegaStormService.CanCatch(root) then
			startCatch(player, MEGA_TARGET)
		end
		return
	end

	local cell = cells[targetId]
	if not cell then
		return
	end
	if cell.Zone > data.Zone then
		Net.NotifyThrottled(player, "LockedZone", "🔒 Unlock this zone first!", "Error", 3)
		return
	end
	local zone = Zones[cell.Zone]
	if Formulas.Power(data) < zone.MinPower then
		Net.NotifyThrottled(
			player,
			"TooWeak",
			string.format("💨 Your vacuum is too weak! %s needs %s Power.", zone.Name, Format.Number(zone.MinPower)),
			"Error",
			4
		)
		return
	end
	if (root.Position - cell.Position).Magnitude > Formulas.Range(data) + GameConfig.CatchRangeLeeway then
		return
	end
	if Formulas.IsTankFull(data) and not Formulas.HasPass(data, "RemoteSell") then
		tankFullMessage(player)
		return
	end

	startCatch(player, targetId)
end

function WeatherService.Init()
	folder = Instance.new("Folder")
	folder.Name = "WeatherCells"
	folder.Parent = Workspace

	for zoneId = 1, #Zones do
		zoneCells[zoneId] = {}
	end

	Remotes.Catch.OnServerEvent:Connect(onCatch)

	Players.PlayerRemoving:Connect(function(player)
		catchers[player] = nil
		petStates[player] = nil
		reported[player] = nil
	end)
end

function WeatherService.Start()
	for zoneId = 1, #Zones do
		for _ = 1, Zones[zoneId].CellCount do
			spawnCell(zoneId)
		end
	end

	while true do
		task.wait(GameConfig.CatchTickRate)
		local ok, err = pcall(tick)
		if not ok then
			warn("[WeatherService] " .. tostring(err))
		end
	end
end

return WeatherService
