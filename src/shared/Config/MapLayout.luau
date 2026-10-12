--!nonstrict
-- World layout shared by the map builder (server) and gameplay code (server + client).
-- Zones are laid out in a straight line along +X. The hub ("Storm Station") sits west of zone 1.
--
--   X:  -220 ........ 0 ........ 320 ........ 640 ...... 1920
--        [ Storm Station ][ Zone 1 ][ Zone 2 ] ... [ Zone 6 ]

local MapLayout = {}

MapLayout.ZoneLength = 320
MapLayout.ZoneCount = 6
MapLayout.HalfWidth = 120 -- playable half width along Z
MapLayout.HubStart = -220
MapLayout.HubEnd = 0
MapLayout.WorldEnd = MapLayout.ZoneLength * MapLayout.ZoneCount

MapLayout.Spawn = Vector3.new(-196, 0, 0)
MapLayout.ArenaCenter = Vector3.new(-112, 0, 0)
MapLayout.ArenaRadius = 44

MapLayout.SellPadRadius = 9
MapLayout.HubSellPad = Vector3.new(-48, 0, -56)

-- North row (z < 0) faces +Z, south row (z > 0) faces -Z
MapLayout.HubStations = {
	Upgrades = Vector3.new(-160, 0, -80),
	Shop = Vector3.new(-104, 0, -80),
	WeatherLab = Vector3.new(-48, 0, -80),
	Rebirth = Vector3.new(-160, 0, 80),
	Rewards = Vector3.new(-104, 0, 80),
	Forecast = Vector3.new(-48, 0, 80),
}

MapLayout.Leaderboards = {
	Volts = Vector3.new(-190, 0, -42),
	Rebirths = Vector3.new(-190, 0, 42),
}

function MapLayout.ZoneStart(zoneId: number): number
	return (zoneId - 1) * MapLayout.ZoneLength
end

function MapLayout.ZoneEnd(zoneId: number): number
	return zoneId * MapLayout.ZoneLength
end

-- Returns 0 for the hub, otherwise the zone index (1..ZoneCount)
function MapLayout.ZoneAt(position: Vector3): number
	if position.X < 0 then
		return 0
	end
	return math.clamp(math.floor(position.X / MapLayout.ZoneLength) + 1, 1, MapLayout.ZoneCount)
end

-- Where players appear when teleporting to a zone (0 = hub spawn)
function MapLayout.ZoneSpawn(zoneId: number): CFrame
	if zoneId <= 0 then
		local position = MapLayout.Spawn + Vector3.new(0, 4, 0)
		return CFrame.lookAt(position, position + Vector3.xAxis)
	end
	local position = Vector3.new(MapLayout.ZoneStart(zoneId) + 26, 4, 0)
	return CFrame.lookAt(position, position + Vector3.xAxis)
end

function MapLayout.ArenaSpawn(): CFrame
	local position = MapLayout.ArenaCenter + Vector3.new(-MapLayout.ArenaRadius + 6, 4, 0)
	return CFrame.lookAt(position, MapLayout.ArenaCenter + Vector3.new(0, 4, 0))
end

function MapLayout.SellPad(zoneId: number): Vector3
	if zoneId <= 0 then
		return MapLayout.HubSellPad
	end
	return Vector3.new(MapLayout.ZoneStart(zoneId) + 56, 0, -46)
end

function MapLayout.EggStation(zoneId: number): Vector3
	return Vector3.new(MapLayout.ZoneStart(zoneId) + 56, 0, 46)
end

function MapLayout.Gate(zoneId: number): Vector3
	return Vector3.new(MapLayout.ZoneStart(zoneId), 0, 0)
end

-- Area where weather cells spawn: minX, maxX, minZ, maxZ
function MapLayout.FieldBounds(zoneId: number): (number, number, number, number)
	local x0 = MapLayout.ZoneStart(zoneId)
	return x0 + 100, x0 + 300, -98, 98
end

function MapLayout.AllSellPads(): { Vector3 }
	local pads = { MapLayout.HubSellPad }
	for zoneId = 1, MapLayout.ZoneCount do
		table.insert(pads, MapLayout.SellPad(zoneId))
	end
	return pads
end

return MapLayout
