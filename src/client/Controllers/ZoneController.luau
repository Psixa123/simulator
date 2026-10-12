--!nonstrict
-- Tracks which zone the player is in: blends lighting/atmosphere per biome, shows the zone
-- title, runs ambient weather (rain, sand, snow, embers, stars), lightning in Thunder Valley,
-- and opens the gates the player has unlocked.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local MapLayout = require(Shared.Config.MapLayout)
local WeatherModels = require(Shared.Models.WeatherModels)

local Registry = require(script.Parent.Parent.Registry)

local ZoneController = {}
ZoneController.Current = -1

local TEXTURES = WeatherModels.Textures
local BLEND = TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local player = Players.LocalPlayer
local clouds: Clouds
local ambiencePart: Part
local ambience = {} -- [name] = ParticleEmitter
local lightningThread = nil
local seenZones = {}

local function blend(instance: Instance?, props)
	if instance then
		TweenService:Create(instance, BLEND, props):Play()
	end
end

local function lowGraphics(): boolean
	local settings = Registry.DataController.Get("Settings")
	return settings ~= nil and settings.LowGraphics == true
end

local function applyLighting(preset)
	blend(Lighting, {
		ClockTime = preset.ClockTime,
		Brightness = preset.Brightness,
		ExposureCompensation = preset.ExposureCompensation or 0,
		Ambient = preset.Ambient,
		OutdoorAmbient = preset.OutdoorAmbient,
	})
	blend(Lighting:FindFirstChildOfClass("Atmosphere"), preset.Atmosphere)
	blend(Lighting:FindFirstChildOfClass("ColorCorrectionEffect"), preset.ColorCorrection)
	if preset.Bloom then
		blend(Lighting:FindFirstChildOfClass("BloomEffect"), preset.Bloom)
	end
	if clouds and preset.Clouds then
		blend(clouds, preset.Clouds)
	end
end

local function setAmbience(name: string?)
	for key, particles in ambience do
		particles.Enabled = key == name and not lowGraphics()
	end
end

local function strike()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local position = root.Position + Vector3.new(math.random(-90, 90), 0, math.random(-90, 90))
	Registry.EffectsController.LightningBolt(position + Vector3.new(0, 140, 0), position, Color3.fromRGB(220, 220, 255), 1.1)

	local correction = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if correction then
		local base = correction.Brightness
		correction.Brightness = base + 0.35
		TweenService:Create(correction, TweenInfo.new(0.35), { Brightness = base }):Play()
	end
	task.delay(math.random() * 0.6 + 0.2, function()
		Registry.SoundController.Play("Thunder", 0.85 + math.random() * 0.3)
	end)
end

local function startLightning(zoneId: number)
	if lightningThread then
		task.cancel(lightningThread)
		lightningThread = nil
	end
	local zone = Zones[zoneId]
	if not zone or not zone.Lighting.Lightning then
		return
	end
	lightningThread = task.spawn(function()
		while true do
			task.wait(math.random(5, 11))
			if not lowGraphics() then
				strike()
			end
		end
	end)
end

local function enterZone(zoneId: number)
	ZoneController.Current = zoneId
	local zone = Zones.Get(zoneId)
	applyLighting(zone.Lighting)
	setAmbience(zone.Lighting.Ambience)
	startLightning(zoneId)

	local subtitle = zone.Description
	if not seenZones[zoneId] then
		seenZones[zoneId] = true
	else
		subtitle = nil
	end
	Registry.InterfaceController.BigText(zone.Icon .. " " .. string.upper(zone.Name), zone.Color, subtitle, if subtitle then 3 else 1.8)
end

---------------------------------------------------------------------------
-- Gates
---------------------------------------------------------------------------
local function applyBarrier(instance: Instance)
	local data = Registry.DataController.Data
	local zoneId = instance:GetAttribute("Zone")
	if not data or not zoneId or not instance:IsA("BasePart") then
		return
	end
	local unlocked = data.Zone >= zoneId
	local isHost = instance.Name == "PromptHost"
	if not isHost then
		instance.CanCollide = not unlocked
		instance.Transparency = if unlocked then 1 else 0
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			descendant.Enabled = not unlocked
		elseif descendant:IsA("BillboardGui") then
			descendant.Enabled = not unlocked
		end
	end
end

local function refreshBarriers()
	for _, instance in CollectionService:GetTagged("ZoneBarrier") do
		applyBarrier(instance)
	end
end

---------------------------------------------------------------------------
function ZoneController.Init()
	clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.5
	clouds.Density = 0.55
	clouds.Parent = Workspace.Terrain

	ambiencePart = Instance.new("Part")
	ambiencePart.Name = "Ambience"
	ambiencePart.Anchored = true
	ambiencePart.CanCollide = false
	ambiencePart.CanQuery = false
	ambiencePart.CanTouch = false
	ambiencePart.Transparency = 1
	ambiencePart.Size = Vector3.new(120, 1, 120)
	ambiencePart.Parent = Workspace

	local function particles(name: string, props)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = name
		emitter.Enabled = false
		emitter.Shape = Enum.ParticleEmitterShape.Box
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		emitter.EmissionDirection = Enum.NormalId.Bottom
		for key, value in props do
			emitter[key] = value
		end
		emitter.Parent = ambiencePart
		ambience[name] = emitter
	end

	particles("Rain", {
		Texture = TEXTURES.Square,
		Color = ColorSequence.new(Color3.fromRGB(170, 190, 230)),
		Size = NumberSequence.new(0.12),
		Transparency = NumberSequence.new(0.35),
		Lifetime = NumberRange.new(0.8, 1),
		Rate = 260,
		Speed = NumberRange.new(70, 80),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = NumberSequence.new(3),
		Acceleration = Vector3.new(4, 0, 0),
	})
	particles("Snow", {
		Texture = TEXTURES.Sparkle,
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Size = NumberSequence.new(0.35),
		Lifetime = NumberRange.new(5, 7),
		Rate = 90,
		Speed = NumberRange.new(6, 9),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
		Acceleration = Vector3.new(2, 0, 1),
	})
	particles("Sand", {
		Texture = TEXTURES.Smoke,
		Color = ColorSequence.new(Color3.fromRGB(240, 205, 140)),
		Size = NumberSequence.new(4, 9),
		Transparency = NumberSequence.new(0.75, 1),
		Lifetime = NumberRange.new(4, 6),
		Rate = 14,
		Speed = NumberRange.new(4, 8),
		EmissionDirection = Enum.NormalId.Right,
		Acceleration = Vector3.new(10, -1, 0),
		RotSpeed = NumberRange.new(-30, 30),
	})
	particles("Embers", {
		Texture = TEXTURES.Spark,
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 80, 20)),
		Size = NumberSequence.new(0.35, 0),
		Lifetime = NumberRange.new(4, 6),
		Rate = 40,
		Speed = NumberRange.new(2, 5),
		Acceleration = Vector3.new(1, 3, 0),
		LightEmission = 1,
	})
	particles("Stars", {
		Texture = TEXTURES.Sparkle,
		Color = ColorSequence.new(Color3.fromRGB(200, 180, 255), Color3.fromRGB(150, 230, 255)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.6), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(2, 4),
		Rate = 30,
		Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 1,
	})
end

function ZoneController.Start()
	Registry.DataController.Observe("Zone", refreshBarriers)
	CollectionService:GetInstanceAddedSignal("ZoneBarrier"):Connect(applyBarrier)
	refreshBarriers()

	Registry.DataController.Observe("Settings", function()
		local zone = Zones.Get(math.max(ZoneController.Current, 0))
		if zone then
			setAmbience(zone.Lighting.Ambience)
		end
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		ambiencePart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 30, 0))

		accumulator += dt
		if accumulator < 0.3 then
			return
		end
		accumulator = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local zoneId = MapLayout.ZoneAt(root.Position)
			if zoneId ~= ZoneController.Current then
				enterZone(zoneId)
			end
		end
	end)
end

return ZoneController
