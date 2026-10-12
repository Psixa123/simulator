--!nonstrict
-- Guides new players with a step-by-step objective and a glowing guide beam
-- (catch -> sell -> upgrade -> hatch -> unlock the next zone -> rebirth).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Pets = require(Shared.Config.Pets)
local MapLayout = require(Shared.Config.MapLayout)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local WeatherModels = require(Shared.Models.WeatherModels)

local Registry = require(script.Parent.Parent.Registry)

local ObjectiveController = {}

local player = Players.LocalPlayer
local targetPart: Part
local targetAttachment: Attachment
local beam: Beam
local highlighted: string? = nil

local function currentZone(): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root then MapLayout.ZoneAt(root.Position) else 0
end

local function nearestCell(zoneId: number): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for model in Registry.EffectsController.Cells() do
		if model:GetAttribute("Zone") == zoneId then
			local origin = model:GetAttribute("Origin")
			if origin then
				local distance = (origin - root.Position).Magnitude
				if distance < bestDistance then
					best, bestDistance = origin, distance
				end
			end
		end
	end
	return best
end

-- Returns text, world position to point at (or nil), menu button to highlight (or nil)
local function compute(data)
	local zoneHere = currentZone()
	local catchZone = math.clamp(if zoneHere > 0 and zoneHere <= data.Zone then zoneHere else data.Zone, 1, #Zones)
	local remoteSell = Formulas.HasPass(data, "RemoteSell")

	if data.Energy >= Formulas.TankCapacity(data) - 1e-6 and not remoteSell then
		return "🛢️ Tank full! Sell it at a ⚡ Weather Lab", MapLayout.SellPad(zoneHere), nil
	end
	if data.TotalVolts <= 0 then
		if data.Energy <= 0 then
			return "🌪️ Hold click on a cloud to vacuum it!", nearestCell(1), nil
		end
		return "⚡ Sell your energy at the Weather Lab", MapLayout.SellPad(math.max(zoneHere, 1)), nil
	end
	if (data.Upgrades.Power or 1) < 2 then
		return "⬆️ Open Upgrades and buy Vacuum Power", nil, "Upgrades"
	end
	if #data.Pets == 0 then
		local egg = Pets.Eggs.MeadowEgg
		if data.Volts >= egg.Cost then
			return "🥚 Hatch your first pet at the " .. egg.Name .. "!", MapLayout.EggStation(1), nil
		end
		return "⚡ Earn " .. Format.Number(egg.Cost) .. " Volts for your first pet", nearestCell(catchZone), nil
	end
	if data.Zone < #Zones then
		local nextZone = Zones[data.Zone + 1]
		if Formulas.Power(data) < nextZone.MinPower then
			return "💨 Reach " .. Format.Number(nextZone.MinPower) .. " Power to enter " .. nextZone.Name, nil, "Upgrades"
		end
		if data.Volts < nextZone.Cost then
			local percent = math.floor(data.Volts / nextZone.Cost * 100)
			return string.format("⚡ Save %s Volts for %s (%d%%)", Format.Number(nextZone.Cost), nextZone.Name, percent), nil, nil
		end
		return "🔓 Unlock " .. nextZone.Icon .. " " .. nextZone.Name .. "!", MapLayout.Gate(data.Zone + 1) + Vector3.new(-4, 0, 0), nil
	end
	if data.Volts >= Formulas.RebirthCost(data.Rebirths) then
		return "🔄 Rebirth for a permanent Volts bonus!", nil, "Rebirth"
	end
	return "🏆 Collect every pet in the Pet Index!", nil, nil
end

local function update()
	local data = Registry.DataController.Data
	if not data then
		return
	end
	local text, position, menuKey = compute(data)
	Registry.HudController.SetObjective(text)

	if menuKey ~= highlighted then
		if highlighted then
			Registry.HudController.Highlight(highlighted, false)
		end
		if menuKey then
			Registry.HudController.Highlight(menuKey, true)
		end
		highlighted = menuKey
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local rootAttachment = root and root:FindFirstChild("RootAttachment")
	if position and rootAttachment and (root.Position - position).Magnitude > 16 then
		targetPart.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
		beam.Attachment0 = rootAttachment
		beam.Enabled = true
	else
		beam.Enabled = false
	end
end

function ObjectiveController.Init()
	targetPart = Instance.new("Part")
	targetPart.Name = "ObjectiveTarget"
	targetPart.Anchored = true
	targetPart.CanCollide = false
	targetPart.CanQuery = false
	targetPart.CanTouch = false
	targetPart.Transparency = 1
	targetPart.Size = Vector3.one
	targetPart.Parent = Workspace

	targetAttachment = Instance.new("Attachment")
	targetAttachment.Parent = targetPart

	beam = Instance.new("Beam")
	beam.Name = "GuideBeam"
	beam.Attachment1 = targetAttachment
	beam.Width0 = 0.6
	beam.Width1 = 0.6
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Texture = WeatherModels.Textures.Sparkle
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = 2
	beam.TextureSpeed = 1.5
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90))
	beam.Transparency = NumberSequence.new(0.2, 0.5)
	beam.Segments = 30
	beam.Enabled = false
	beam.Parent = targetPart
end

function ObjectiveController.Start()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.5 then
			accumulator = 0
			update()
		end
	end)
	update()
end

return ObjectiveController
