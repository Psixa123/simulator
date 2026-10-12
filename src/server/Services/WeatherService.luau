--!nonstrict
-- Spawns weather cells in every zone and runs the authoritative vacuum simulation.
-- Clients ask to start/stop catching a target; the server validates range, zone access,
-- power and tank space every tick, drains the cell and fills the player's tank.

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

local WeatherService = {}

local MEGA_TARGET = -1 -- target id used for the Mega Storm
WeatherService.MegaTarget = MEGA_TARGET

local cells = {} -- [id] = cell
local zoneCells = {} -- [zoneId] = { [id] = cell }
local catchers = {} -- [Player] = targetId
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

local function spawnCell(zoneId: number)
	local zone = Zones[zoneId]
	if countCells(zoneId) >= zone.CellCount then
		return
	end

	local typeId = pickType(zone)
	local def = Weather.Types[typeId]
	local health = Formulas.CellHealth(typeId, zoneId)
	local position = findSpot(zoneId) + Vector3.new(0, WeatherModels.HoverHeight(typeId), 0)

	nextId += 1
	local id = nextId

	local model = WeatherModels.Build(typeId)
	model.Name = "Cell" .. id
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	model:SetAttribute("CellId", id)
	model:SetAttribute("Type", typeId)
	model:SetAttribute("Zone", zoneId)
	model:SetAttribute("Health", health)
	model:SetAttribute("MaxHealth", health)
	model:SetAttribute("Origin", position)
	model.Parent = folder

	local cell = {
		Id = id,
		Type = typeId,
		Zone = zoneId,
		Health = health,
		MaxHealth = health,
		Model = model,
		Position = position,
		Value = Formulas.CellValue(typeId, zoneId),
		Contributors = {},
	}
	cells[id] = cell
	zoneCells[zoneId][id] = cell

	if Weather.Rarities[def.Rarity].Announce then
		for _, player in Players:GetPlayers() do
			local root = Net.GetRoot(player)
			if root and MapLayout.ZoneAt(root.Position) == zoneId then
				Net.Effect(player, "RareSpawn", typeId, position)
			end
		end
	end
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

local function tick()
	local now = os.time()
	for player, targetId in catchers do
		local data = Registry.DataService.Get(player)
		local root = Net.GetRoot(player)
		local character = player.Character
		if not data or not root or not character or not character:FindFirstChild("StormVacuum") then
			WeatherService.StopCatch(player)
			continue
		end

		if targetId == MEGA_TARGET then
			if not Registry.MegaStormService.Drain(player, data, root) then
				WeatherService.StopCatch(player)
			end
			continue
		end

		local cell = cells[targetId]
		if not cell then
			WeatherService.StopCatch(player)
			continue
		end
		if (root.Position - cell.Position).Magnitude > Formulas.Range(data) + GameConfig.CatchRangeLeeway then
			WeatherService.StopCatch(player)
			continue
		end

		local remoteSell = Formulas.HasPass(data, "RemoteSell")
		local capacity = Formulas.TankCapacity(data)
		if data.Energy >= capacity - 1e-6 then
			if remoteSell then
				Registry.EconomyService.Sell(player, "Auto")
			else
				WeatherService.StopCatch(player)
				tankFullMessage(player)
				continue
			end
		end

		local multiplier = Formulas.EnergyMultiplier(data, now)
		local space = capacity - data.Energy
		local drained = math.min(cell.Health, Formulas.Power(data), space / multiplier)
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

		if remoteSell and data.Energy >= capacity - 1e-6 then
			Registry.EconomyService.Sell(player, "Auto")
		end
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
	if data.Energy >= Formulas.TankCapacity(data) - 1e-6 and not Formulas.HasPass(data, "RemoteSell") then
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
