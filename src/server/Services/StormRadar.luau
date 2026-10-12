--!nonstrict
-- Storm Radar gamepass (server half): owners hear about every rare weather cell that spawns in
-- a zone they've unlocked, wherever they are. The client (RadarController) shows the alert
-- card, the Teleport button and the world marker that stays on the cell until it pops.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared.Formulas)

local Registry = require(script.Parent.Registry)
local Net = require(script.Parent.Net)

local StormRadar = {}

StormRadar.PassKey = "StormRadar"

-- Sends the radar alert for a freshly spawned rare cell. Returns false when the player
-- doesn't own the radar (or hasn't unlocked the zone) so the caller can fall back to the
-- regular "rare weather nearby" announcement.
function StormRadar.Alert(player: Player, cell): boolean
	local data = Registry.DataService.Get(player)
	-- Only zones they can actually catch in (after a Climate Shift their Power starts over)
	if not data or not Formulas.HasPass(data, StormRadar.PassKey) or cell.Zone > Formulas.BestCatchableZone(data) then
		return false
	end
	Net.Effect(player, "RadarSpawn", cell.Type, cell.Position, cell.Zone, cell.Id)
	return true
end

return StormRadar
