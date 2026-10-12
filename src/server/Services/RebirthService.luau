--!nonstrict
-- Rebirthing: trade your Volts and Power/Tank upgrades for a permanent Volts multiplier.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Registry)
local Net = require(script.Parent.Net)

local RebirthService = {}

function RebirthService.Rebirth(player: Player)
	local data = Registry.DataService.Get(player)
	if not data then
		return Net.Fail("Still loading...")
	end
	local cost = Formulas.RebirthCost(data.Rebirths)
	if data.Volts < cost then
		return Net.Fail("You need ⚡ " .. Format.Number(cost) .. " Volts to rebirth!")
	end

	Registry.WeatherService.StopCatch(player)
	data.Volts = 0
	data.Energy = 0
	data.TankValue = 0
	data.Upgrades.Power = 1
	data.Upgrades.Tank = 1
	data.Rebirths += 1

	Registry.DataService.Replicate(player, "Volts", "Energy", "TankValue", "Upgrades", "Rebirths")
	Net.Effect(player, "Rebirth", data.Rebirths)
	Net.NotifyAll(string.format("🔄 %s just reached Rebirth %d!", player.DisplayName, data.Rebirths), "Success")
	return { Ok = true, Rebirths = data.Rebirths }
end

function RebirthService.Init()
	Remotes.Rebirth.OnServerInvoke = function(player)
		if not Net.RateLimit(player, "Rebirth", 1.5) then
			return Net.Fail("Slow down!")
		end
		return RebirthService.Rebirth(player)
	end
end

return RebirthService
