--!nonstrict
-- Timed boosts (2x Energy, 2x Luck). End times are stored as server unix time while
-- the player is online and converted to "seconds remaining" when saved.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Format = require(Shared.Util.Format)

local Registry = require(script.Parent.Registry)
local Net = require(script.Parent.Net)

local BoostService = {}

function BoostService.Add(player: Player, boostName: string, seconds: number, silent: boolean?)
	local data = Registry.DataService.Get(player)
	local boost = GameConfig.Boosts[boostName]
	if not data or not boost then
		return
	end
	local now = os.time()
	data.Boosts[boostName] = math.max(data.Boosts[boostName] or 0, now) + seconds
	Registry.DataService.Replicate(player, "Boosts")
	if not silent then
		Net.Notify(
			player,
			string.format("%s %s boost active for %s!", boost.Icon, boost.Name, Format.Duration(seconds)),
			"Reward"
		)
	end
end

return BoostService
