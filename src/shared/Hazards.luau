--!nonstrict
-- Biome hazard rules shared by the server (HazardService, PlayerService, MapService) and the
-- client (HazardController, Teleport panel) so both always agree on where a hazard applies.
-- Tuning lives in each zone's `Hazard` table in Config/Zones.

local Config = script.Parent:WaitForChild("Config")
local Zones = require(Config.Zones)
local MapLayout = require(Config.MapLayout)

local Hazards = {}

-- Configuration in ReplicatedStorage (created by HazardService) holding server-wide hazard state
Hazards.StateName = "HazardState"

-- Studs around the Mega Storm arena where hazards never apply
local ARENA_MARGIN = 12

-- Zone whose hazard applies at `position`: 0 (none) in the hub and the Mega Storm arena
function Hazards.ZoneAt(position: Vector3): number
	local offset = position - MapLayout.ArenaCenter
	if Vector2.new(offset.X, offset.Z).Magnitude <= MapLayout.ArenaRadius + ARENA_MARGIN then
		return 0
	end
	return MapLayout.ZoneAt(position)
end

function Hazards.Get(zoneId: number?)
	local zone = zoneId and zoneId > 0 and Zones[zoneId]
	return if zone then zone.Hazard else nil
end

-- Attribute on the HazardState folder that is true while a zone's sandstorm rages
function Hazards.SandstormAttribute(zoneId: number): string
	return "Sandstorm" .. zoneId
end

---------------------------------------------------------------------------
-- Cold
---------------------------------------------------------------------------
function Hazards.ResistsCold(data, hazard): boolean
	return ((data.Upgrades and data.Upgrades.Speed) or 1) >= hazard.BootsLevel
end

-- Applied on top of the Storm Boots walk speed
function Hazards.SpeedMultiplier(data, hazard): number
	if hazard and hazard.Kind == "Cold" and not Hazards.ResistsCold(data, hazard) then
		return hazard.SpeedMultiplier
	end
	return 1
end

---------------------------------------------------------------------------
-- Heat
---------------------------------------------------------------------------
-- Spots that are safe from the heat: the sell pad (Weather Lab), the egg station and the zone spawn
function Hazards.CoolingSpots(zoneId: number): { Vector3 }
	local spawn = MapLayout.ZoneSpawn(zoneId).Position
	return {
		MapLayout.SellPad(zoneId),
		MapLayout.EggStation(zoneId),
		Vector3.new(spawn.X, 0, spawn.Z),
	}
end

function Hazards.IsCool(zoneId: number, position: Vector3, radius: number): boolean
	for _, spot in Hazards.CoolingSpots(zoneId) do
		local dx, dz = position.X - spot.X, position.Z - spot.Z
		if dx * dx + dz * dz <= radius * radius then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
-- One line for the zone banner and the Teleport panel ("⚡ Lightning stuns you! ...")
function Hazards.Describe(hazard, data): string
	if hazard.Kind == "Cold" and data and Hazards.ResistsCold(data, hazard) then
		return "👟 Your Storm Boots keep the cold away!"
	end
	return hazard.Icon .. " " .. hazard.Description
end

return Hazards
