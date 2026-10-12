--!nonstrict
-- Buying upgrades (Vacuum Power, Storm Tank, Vacuum Range, Storm Boots).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Registry)
local Net = require(script.Parent.Net)

local UpgradeService = {}

-- mode: "One" buys a single level, "Max" buys as many as you can afford
function UpgradeService.Buy(player: Player, upgradeId: string, mode: string?)
	local data = Registry.DataService.Get(player)
	local def = type(upgradeId) == "string" and GameConfig.Upgrades[upgradeId]
	if not data or not def then
		return Net.Fail("Invalid upgrade.")
	end

	local level = data.Upgrades[upgradeId] or 1
	if level >= def.MaxLevel then
		return Net.Fail(def.Name .. " is already maxed!")
	end

	local bought = 0
	repeat
		local cost = def.Cost(level)
		if data.Volts < cost then
			break
		end
		data.Volts -= cost
		level += 1
		bought += 1
	until mode ~= "Max" or level >= def.MaxLevel or bought >= 100

	if bought == 0 then
		return Net.Fail("Not enough Volts!")
	end

	data.Upgrades[upgradeId] = level
	Registry.DataService.Replicate(player, "Volts", "Upgrades")
	Net.Effect(player, "Upgrade", upgradeId, level)
	return { Ok = true, Level = level, Bought = bought }
end

function UpgradeService.Init()
	Remotes.BuyUpgrade.OnServerInvoke = function(player, upgradeId, mode)
		if not Net.RateLimit(player, "Upgrade", 0.12) then
			return Net.Fail("Slow down!")
		end
		return UpgradeService.Buy(player, upgradeId, mode)
	end
end

return UpgradeService
