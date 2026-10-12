--!nonstrict
-- Zone unlocking (gate prompts + UI), teleporting and keeping players out of locked zones.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local MapLayout = require(Shared.Config.MapLayout)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Registry)
local Net = require(script.Parent.Net)

local ZoneService = {}

function ZoneService.TeleportTo(player: Player, cframe: CFrame): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	Registry.WeatherService.StopCatch(player)
	character:PivotTo(cframe)
	return true
end

function ZoneService.TryUnlock(player: Player, zoneId: number)
	local data = Registry.DataService.Get(player)
	if not data then
		return Net.Fail("Still loading...")
	end
	local zone = type(zoneId) == "number" and Zones[zoneId]
	if not zone then
		return Net.Fail("Invalid zone.")
	end
	if data.Zone >= zoneId then
		return Net.Fail(zone.Name .. " is already unlocked!")
	end
	if zoneId ~= data.Zone + 1 then
		return Net.Fail("Unlock " .. Zones[data.Zone + 1].Name .. " first!")
	end
	if Formulas.Power(data) < zone.MinPower then
		return Net.Fail(
			string.format("You need 💨 %s Vacuum Power to enter %s!", Format.Number(zone.MinPower), zone.Name)
		)
	end
	if data.Volts < zone.Cost then
		return Net.Fail(string.format("You need ⚡ %s Volts to unlock %s!", Format.Number(zone.Cost), zone.Name))
	end

	data.Volts -= zone.Cost
	data.Zone = zoneId
	Registry.DataService.Replicate(player, "Volts", "Zone")
	Net.Effect(player, "ZoneUnlocked", zoneId)
	if zoneId >= 3 then
		Net.NotifyAll(string.format("🎉 %s unlocked %s %s!", player.DisplayName, zone.Icon, zone.Name), "Success")
	end
	return { Ok = true }
end

local function connectGatePrompt(prompt: ProximityPrompt)
	prompt.Triggered:Connect(function(player)
		if not Net.RateLimit(player, "GatePrompt", 0.5) then
			return
		end
		local zoneId = prompt:GetAttribute("GateZone")
		local result = ZoneService.TryUnlock(player, zoneId)
		if not result.Ok then
			Net.Notify(player, result.Error, "Error")
		end
	end)
end

function ZoneService.Init()
	Remotes.UnlockZone.OnServerInvoke = function(player, zoneId)
		if not Net.RateLimit(player, "UnlockZone", 0.5) then
			return Net.Fail("Slow down!")
		end
		return ZoneService.TryUnlock(player, zoneId)
	end

	Remotes.Teleport.OnServerInvoke = function(player, target)
		if not Net.RateLimit(player, "Teleport", 1.5) then
			return Net.Fail("Please wait a moment before teleporting again.")
		end
		local data = Registry.DataService.Get(player)
		if not data then
			return Net.Fail("Still loading...")
		end
		local destination
		if target == "Hub" or target == 0 then
			destination = MapLayout.ZoneSpawn(0)
		elseif target == "Arena" then
			destination = MapLayout.ArenaSpawn()
		elseif type(target) == "number" and Zones[target] then
			if target > data.Zone then
				return Net.Fail("Unlock " .. Zones[target].Name .. " first!")
			end
			destination = MapLayout.ZoneSpawn(target)
		else
			return Net.Fail("Invalid destination.")
		end
		if not ZoneService.TeleportTo(player, destination) then
			return Net.Fail("You can't teleport right now.")
		end
		return { Ok = true }
	end

	for _, prompt in CollectionService:GetTagged("GatePrompt") do
		connectGatePrompt(prompt)
	end
	CollectionService:GetInstanceAddedSignal("GatePrompt"):Connect(connectGatePrompt)
end

function ZoneService.Start()
	-- Players can't walk through gates they haven't unlocked (the client removes collision
	-- locally once unlocked). This catches anyone who glitches or exploits past a gate.
	while true do
		task.wait(1.5)
		for _, player in Players:GetPlayers() do
			local data = Registry.DataService.Get(player)
			local root = Net.GetRoot(player)
			if data and root then
				local zoneAtPosition = MapLayout.ZoneAt(root.Position - Vector3.new(6, 0, 0))
				local outOfBounds = math.abs(root.Position.Z) > MapLayout.HalfWidth + 30 or root.Position.Y < -60
				if zoneAtPosition > data.Zone or outOfBounds then
					ZoneService.TeleportTo(player, MapLayout.ZoneSpawn(if outOfBounds then 0 else data.Zone))
					if not outOfBounds then
						Net.NotifyThrottled(player, "Trespass", "🔒 You need to unlock this zone first!", "Error", 3)
					end
				end
			end
		end
	end
end

return ZoneService
