--!nonstrict
-- Volts, the energy tank and selling (sell pads, remote sell and auto sell).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared.Formulas)
local MapLayout = require(Shared.Config.MapLayout)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Registry)
local Net = require(script.Parent.Net)

local EconomyService = {}

function EconomyService.AddVolts(player: Player, amount: number, countAsEarned: boolean?)
	local data = Registry.DataService.Get(player)
	if not data then
		return
	end
	amount = math.floor(amount)
	data.Volts += amount
	if countAsEarned ~= false and amount > 0 then
		data.TotalVolts += amount
	end
	Registry.DataService.Replicate(player, "Volts", "TotalVolts")
end

function EconomyService.SpendVolts(player: Player, amount: number): boolean
	local data = Registry.DataService.Get(player)
	if not data or amount < 0 or data.Volts < amount then
		return false
	end
	data.Volts -= amount
	Registry.DataService.Replicate(player, "Volts")
	return true
end

-- Adds energy to the tank, capped by capacity (no cap with Infinite Tank). Returns how much was actually added.
function EconomyService.AddEnergy(player: Player, units: number, valuePerUnit: number): number
	local data = Registry.DataService.Get(player)
	if not data or units <= 0 then
		return 0
	end
	local added = math.min(Formulas.TankSpace(data), units)
	if added <= 0 then
		return 0
	end
	data.Energy += added
	data.TankValue += added * valuePerUnit
	Registry.DataService.Replicate(player, "Energy", "TankValue")
	return added
end

function EconomyService.IsTankFull(data): boolean
	return Formulas.IsTankFull(data)
end

-- Converts the whole tank into Volts. source: "Pad" | "Remote" | "Auto"
function EconomyService.Sell(player: Player, source: string): number
	local data = Registry.DataService.Get(player)
	if not data or data.Energy <= 0 then
		return 0
	end
	local volts = math.floor(data.TankValue * Formulas.VoltsMultiplier(data))
	data.Energy = 0
	data.TankValue = 0
	data.Volts += volts
	data.TotalVolts += volts
	data.Stats.Sells += 1
	Registry.DataService.Replicate(player, "Energy", "TankValue", "Volts", "TotalVolts")
	Net.Effect(player, "Sell", volts, source)
	return volts
end

function EconomyService.Init()
	Remotes.Sell.OnServerInvoke = function(player)
		if not Net.RateLimit(player, "Sell", 0.6) then
			return Net.Fail("Slow down!")
		end
		local data = Registry.DataService.Get(player)
		if not data then
			return Net.Fail("Still loading...")
		end
		if data.Energy <= 0 then
			return Net.Fail("Your tank is empty! Catch some weather first.")
		end
		if Formulas.HasPass(data, "RemoteSell") then
			return { Ok = true, Sold = EconomyService.Sell(player, "Remote") }
		end
		local root = Net.GetRoot(player)
		if not root then
			return Net.Fail("You can't sell right now.")
		end
		local pad = MapLayout.SellPad(MapLayout.ZoneAt(root.Position))
		Registry.ZoneService.TeleportTo(player, CFrame.new(pad + Vector3.new(0, 4, 0)))
		return { Ok = true, Teleported = true }
	end
end

local sellPads = MapLayout.AllSellPads()

-- True when a position is standing on one of the Weather Lab sell pads
function EconomyService.OnSellPad(position: Vector3): boolean
	local radius = MapLayout.SellPadRadius
	for _, pad in sellPads do
		local dx, dz = position.X - pad.X, position.Z - pad.Z
		if dx * dx + dz * dz <= radius * radius and math.abs(position.Y - pad.Y) < 12 then
			return true
		end
	end
	return false
end

function EconomyService.Start()
	while true do
		task.wait(0.25)
		for _, player in Players:GetPlayers() do
			local data = Registry.DataService.Get(player)
			if data and data.Energy > 0 then
				local root = Net.GetRoot(player)
				if root and EconomyService.OnSellPad(root.Position) then
					EconomyService.Sell(player, "Pad")
				end
			end
		end
	end
end

return EconomyService
