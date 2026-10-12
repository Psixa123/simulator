--!nonstrict
-- Builds the 3D models for weather cells and the Mega Storm out of basic parts.
-- Models are built around the origin (Root at 0,0,0); callers pivot them into place.

local Config = script.Parent.Parent:WaitForChild("Config")
local Weather = require(Config.Weather)

local WeatherModels = {}

local TEXTURES = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Spark = "rbxasset://textures/particles/fire_sparks_main.dds",
	Square = "rbxasset://textures/particles/SquareParticle.png",
}
WeatherModels.Textures = TEXTURES

local RAINBOW = {
	Color3.fromRGB(255, 170, 190),
	Color3.fromRGB(255, 215, 150),
	Color3.fromRGB(255, 250, 170),
	Color3.fromRGB(170, 245, 190),
	Color3.fromRGB(160, 215, 255),
	Color3.fromRGB(205, 175, 255),
}

local RAINBOW_SEQUENCE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 110)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 180, 70)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 240, 90)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(110, 235, 130)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(100, 180, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 120, 255)),
})
WeatherModels.RainbowSequence = RAINBOW_SEQUENCE

local CLOUD_PUFFS = {
	{ Vector3.new(0, 0.4, 0), 5.6 },
	{ Vector3.new(3.1, -0.3, 0.4), 4.4 },
	{ Vector3.new(-3.2, -0.4, -0.3), 4.6 },
	{ Vector3.new(1.2, 1.9, -0.6), 4.0 },
	{ Vector3.new(-1.3, 1.5, 1.0), 3.8 },
	{ Vector3.new(1.5, -0.6, -2.3), 3.6 },
	{ Vector3.new(-1.0, -0.7, 2.4), 3.4 },
	{ Vector3.new(4.9, -0.8, -0.5), 2.8 },
	{ Vector3.new(-5.0, -0.9, 0.6), 2.6 },
}

local STAR_RAYS = {
	CFrame.Angles(0, 0, 0),
	CFrame.Angles(0, math.rad(90), 0),
	CFrame.Angles(math.rad(90), 0, 0),
	CFrame.Angles(0, math.rad(45), 0),
	CFrame.Angles(0, math.rad(-45), 0),
	CFrame.Angles(math.rad(45), 0, 0),
	CFrame.Angles(math.rad(-45), 0, 0),
}

local function newPart(props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then
		part.Shape = props.Shape
	end
	for key, value in props do
		if key ~= "Shape" and key ~= "Parent" then
			part[key] = value
		end
	end
	part.Parent = props.Parent
	return part
end

local function emitter(parent: Instance, props)
	local particles = Instance.new("ParticleEmitter")
	for key, value in props do
		particles[key] = value
	end
	particles.Parent = parent
	return particles
end

local function light(parent: Instance, color: Color3, brightness: number, range: number, name: string?)
	local pointLight = Instance.new("PointLight")
	pointLight.Name = name or "Glow"
	pointLight.Color = color
	pointLight.Brightness = brightness
	pointLight.Range = range
	pointLight.Shadows = false
	pointLight.Parent = parent
	return pointLight
end

local function shade(color: Color3, amount: number): Color3
	return Color3.new(math.clamp(color.R * amount, 0, 1), math.clamp(color.G * amount, 0, 1), math.clamp(color.B * amount, 0, 1))
end

local function seq(a: number, b: number)
	return NumberSequence.new(a, b)
end

-- Invisible part that particle emitters use as their emission volume
local function host(model: Model, size: Vector3, offset: Vector3?)
	return newPart({
		Name = "EmitterHost",
		Size = size,
		CFrame = CFrame.new(offset or Vector3.zero),
		Transparency = 1,
		CanQuery = false,
		Parent = model,
	})
end

local function buildCloud(model: Model, colors, scale: number)
	for index, puff in CLOUD_PUFFS do
		local color = if typeof(colors) == "table" then colors[(index - 1) % #colors + 1] else colors
		if puff[1].Y < 0 then
			color = shade(color, 0.9)
		end
		local part = newPart({
			Name = "Puff",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * puff[2] * scale,
			CFrame = CFrame.new(puff[1] * scale),
			Color = color,
			Parent = model,
		})
		part.CastShadow = index <= 3
	end
	return host(model, Vector3.new(13, 6, 8) * scale)
end

local Builders = {}

function Builders.Cloud(model, def, scale, root)
	local volume = buildCloud(model, def.Color, scale)
	emitter(volume, {
		Texture = TEXTURES.Sparkle,
		Color = ColorSequence.new(def.Accent),
		Size = seq(0.6 * scale, 0),
		Transparency = seq(0.1, 1),
		Lifetime = NumberRange.new(1, 1.6),
		Rate = 5,
		Speed = NumberRange.new(1, 2.5),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 0.8,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
	})
end

function Builders.RainCloud(model, def, scale, root)
	buildCloud(model, def.Color, scale)
	local rain = host(model, Vector3.new(9, 0.2, 6) * scale, Vector3.new(0, -2.4 * scale, 0))
	emitter(rain, {
		Texture = TEXTURES.Square,
		Color = ColorSequence.new(def.Accent),
		Size = NumberSequence.new(0.14),
		Transparency = NumberSequence.new(0.25),
		Lifetime = NumberRange.new(0.4, 0.55),
		Rate = 45,
		Speed = NumberRange.new(26, 32),
		EmissionDirection = Enum.NormalId.Bottom,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = NumberSequence.new(2.5),
		LightEmission = 0.3,
	})
end

function Builders.Rainbow(model, def, scale, root)
	local volume = buildCloud(model, RAINBOW, scale)
	emitter(volume, {
		Texture = TEXTURES.Sparkle,
		Color = RAINBOW_SEQUENCE,
		Size = seq(0.9 * scale, 0),
		Transparency = seq(0, 1),
		Lifetime = NumberRange.new(1, 1.8),
		Rate = 14,
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 1,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
	})
	light(root, def.Accent, 1.5, 18)
end

function Builders.StormCloud(model, def, scale, root)
	local volume = buildCloud(model, def.Color, scale)
	local bolts = {
		{ Vector3.new(0.6, -3.4, 0), 3.0, 0.35 },
		{ Vector3.new(-0.1, -5.7, 0.2), 2.6, -0.5 },
		{ Vector3.new(0.5, -7.6, 0.1), 2.0, 0.3 },
	}
	for _, bolt in bolts do
		newPart({
			Name = "Bolt",
			Size = Vector3.new(0.5, bolt[2], 0.5) * scale,
			CFrame = CFrame.new(bolt[1] * scale) * CFrame.Angles(0, 0, bolt[3]),
			Color = def.Accent,
			Material = Enum.Material.Neon,
			Parent = model,
		})
	end
	light(root, def.Accent, 2, 18, "Flash")
	emitter(volume, {
		Texture = TEXTURES.Sparkle,
		Color = ColorSequence.new(def.Accent),
		Size = seq(0.5 * scale, 0),
		Lifetime = NumberRange.new(0.15, 0.35),
		Rate = 12,
		Speed = NumberRange.new(8, 12),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 1,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
	})
end

function Builders.Orb(model, def, scale, root)
	newPart({
		Name = "Core",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 3.2 * scale,
		Color = def.Color,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	newPart({
		Name = "Shell",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 5.6 * scale,
		Color = def.Accent,
		Material = Enum.Material.ForceField,
		Parent = model,
	})
	for i = 0, 2 do
		local angle = i * math.pi * 2 / 3
		local offset = Vector3.new(math.cos(angle) * 3.8, (i - 1) * 0.8, math.sin(angle) * 3.8) * scale
		newPart({
			Name = "Satellite",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.8 * scale,
			CFrame = CFrame.new(offset),
			Color = def.Accent,
			Material = Enum.Material.Neon,
			Parent = model,
		})
	end
	light(root, def.Color, 2.5, 18)
	emitter(root, {
		Texture = TEXTURES.Sparkle,
		Color = ColorSequence.new(def.Accent),
		Size = seq(0.6 * scale, 0),
		Transparency = seq(0, 1),
		Lifetime = NumberRange.new(0.8, 1.4),
		Rate = 8,
		Speed = NumberRange.new(3, 5),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 1,
	})
	if def.Fire then
		emitter(root, {
			Texture = TEXTURES.Fire,
			Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 70, 20)),
			Size = seq(2.2 * scale, 0.4),
			Transparency = seq(0.2, 1),
			Lifetime = NumberRange.new(0.6, 1),
			Rate = 22,
			Speed = NumberRange.new(3, 5),
			SpreadAngle = Vector2.new(25, 25),
			EmissionDirection = Enum.NormalId.Top,
			LightEmission = 0.9,
			RotSpeed = NumberRange.new(-90, 90),
		})
	end
end

function Builders.Tornado(model, def, scale, root)
	local layers = 7
	local topRadius = 0
	for i = 0, layers - 1 do
		local t = i / (layers - 1)
		local height = 2.1 * scale
		local diameter = (2.2 + i * 1.35) * scale
		local y = (-5.7 + i * 1.9) * scale
		topRadius = diameter / 2
		newPart({
			Name = "Layer",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, diameter, diameter),
			CFrame = CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = def.Color:Lerp(def.Accent, t * 0.7),
			Transparency = 0.12 + t * 0.3,
			Parent = model,
		})
		local angle = i * 0.9
		local radius = diameter / 2
		newPart({
			Name = "Streak",
			Size = Vector3.new(0.35 * scale, height * 0.85, 0.9 * scale),
			CFrame = CFrame.new(math.cos(angle) * radius, y, math.sin(angle) * radius) * CFrame.Angles(0, -angle, 0),
			Color = shade(def.Color, 0.72),
			Parent = model,
		})
	end
	for i = 1, 3 do
		local angle = i * math.pi * 2 / 3
		local radius = topRadius + 1.4 * scale
		local size = (0.6 + i * 0.2) * scale
		newPart({
			Name = "Debris",
			Size = Vector3.new(size, size * 0.8, size),
			CFrame = CFrame.new(math.cos(angle) * radius, (i - 2) * 1.6 * scale, math.sin(angle) * radius)
				* CFrame.Angles(i, i * 2, 0),
			Color = shade(def.Color, 0.55),
			Material = Enum.Material.Slate,
			Parent = model,
		})
	end
	local base = host(model, Vector3.new(3, 0.2, 3) * scale, Vector3.new(0, -6.6 * scale, 0))
	emitter(base, {
		Texture = TEXTURES.Smoke,
		Color = ColorSequence.new(def.Accent),
		Size = seq(2 * scale, 4.5 * scale),
		Transparency = seq(0.45, 1),
		Lifetime = NumberRange.new(1, 1.6),
		Rate = 7,
		Speed = NumberRange.new(3, 5),
		SpreadAngle = Vector2.new(80, 80),
		Acceleration = Vector3.new(0, 2, 0),
		RotSpeed = NumberRange.new(-60, 60),
	})
	if def.Fire then
		local middle = host(model, Vector3.new(4, 6, 4) * scale, Vector3.new(0, -1 * scale, 0))
		emitter(middle, {
			Texture = TEXTURES.Fire,
			Color = ColorSequence.new(Color3.fromRGB(255, 210, 90), Color3.fromRGB(255, 70, 20)),
			Size = seq(2.5 * scale, 0.5),
			Transparency = seq(0.25, 1),
			Lifetime = NumberRange.new(0.5, 0.9),
			Rate = 24,
			Speed = NumberRange.new(3, 6),
			SpreadAngle = Vector2.new(30, 30),
			EmissionDirection = Enum.NormalId.Top,
			LightEmission = 0.9,
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		})
		light(root, def.Accent, 2, 20)
	end
end

function Builders.DustCloud(model, def, scale, root)
	local volume = buildCloud(model, def.Color, scale * 1.05)
	emitter(volume, {
		Texture = TEXTURES.Smoke,
		Color = ColorSequence.new(def.Accent),
		Size = seq(2.5 * scale, 5 * scale),
		Transparency = seq(0.5, 1),
		Lifetime = NumberRange.new(2, 3),
		Rate = 6,
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
		RotSpeed = NumberRange.new(-40, 40),
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
	})
	emitter(volume, {
		Texture = TEXTURES.Sparkle,
		Color = ColorSequence.new(def.Color),
		Size = seq(0.35, 0),
		Lifetime = NumberRange.new(0.6, 1),
		Rate = 15,
		Speed = NumberRange.new(6, 9),
		SpreadAngle = Vector2.new(180, 180),
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
	})
end

function Builders.SnowCloud(model, def, scale, root)
	buildCloud(model, def.Color, scale)
	local snow = host(model, Vector3.new(9, 0.2, 6) * scale, Vector3.new(0, -2.4 * scale, 0))
	emitter(snow, {
		Texture = TEXTURES.Sparkle,
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Size = NumberSequence.new(0.35),
		Transparency = seq(0, 0.4),
		Lifetime = NumberRange.new(2, 3),
		Rate = 16,
		Speed = NumberRange.new(3, 5),
		EmissionDirection = Enum.NormalId.Bottom,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Acceleration = Vector3.new(0.6, 0, 0.3),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
	})
end

function Builders.AshCloud(model, def, scale, root)
	local volume = buildCloud(model, def.Color, scale)
	emitter(volume, {
		Texture = TEXTURES.Spark,
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 80, 20)),
		Size = seq(0.45, 0),
		Lifetime = NumberRange.new(1.2, 2),
		Rate = 14,
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 3, 0),
		LightEmission = 1,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
	})
	emitter(volume, {
		Texture = TEXTURES.Smoke,
		Color = ColorSequence.new(Color3.fromRGB(50, 45, 45)),
		Size = seq(3, 6),
		Transparency = seq(0.55, 1),
		Lifetime = NumberRange.new(2, 3),
		Rate = 3,
		Speed = NumberRange.new(1, 2),
		Acceleration = Vector3.new(0, 1.5, 0),
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
	})
	light(root, def.Accent, 1.2, 14)
end

function Builders.Starburst(model, def, scale, root)
	newPart({
		Name = "Core",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 2.8 * scale,
		Color = Color3.fromRGB(255, 252, 230),
		Material = Enum.Material.Neon,
		Parent = model,
	})
	for index, rotation in STAR_RAYS do
		newPart({
			Name = "Ray",
			Size = Vector3.new(0.6, 0.6, 7.5) * scale,
			CFrame = rotation,
			Color = if index % 2 == 0 then def.Accent else def.Color,
			Material = Enum.Material.Neon,
			Parent = model,
		})
	end
	newPart({
		Name = "Shell",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 4.8 * scale,
		Color = def.Accent,
		Material = Enum.Material.ForceField,
		Parent = model,
	})
	light(root, def.Color, 3, 22)
	emitter(root, {
		Texture = TEXTURES.Sparkle,
		Color = RAINBOW_SEQUENCE,
		Size = seq(0.8 * scale, 0),
		Lifetime = NumberRange.new(0.8, 1.4),
		Rate = 16,
		Speed = NumberRange.new(4, 7),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 1,
	})
end

-- Returns a weather cell model with a Root part (and a "Target" attachment for beams)
function WeatherModels.Build(typeId: string): Model
	local def = Weather.Types[typeId]
	local rarity = Weather.Rarities[def.Rarity]
	local scale = rarity.Scale

	local model = Instance.new("Model")
	model.Name = typeId

	local root = newPart({
		Name = "Root",
		Size = Vector3.one,
		Transparency = 1,
		CanQuery = false,
		Parent = model,
	})
	local target = Instance.new("Attachment")
	target.Name = "Target"
	target.Parent = root
	model.PrimaryPart = root

	local builder = Builders[def.Style] or Builders.Cloud
	builder(model, def, scale, root)

	if rarity.Announce then
		emitter(root, {
			Name = "RareAura",
			Texture = TEXTURES.Sparkle,
			Color = ColorSequence.new(rarity.Color),
			Size = seq(1.1, 0),
			Transparency = seq(0, 1),
			Lifetime = NumberRange.new(1.2, 1.8),
			Rate = 8,
			Speed = NumberRange.new(5, 7),
			SpreadAngle = Vector2.new(180, 180),
			LightEmission = 1,
		})
	end

	return model
end

function WeatherModels.HoverHeight(typeId: string): number
	local def = Weather.Types[typeId]
	return (Weather.HoverHeight[def.Style] or 12) * Weather.Rarities[def.Rarity].Scale
end

-- Giant tornado for the Mega Storm event. Pivot is the ground center.
function WeatherModels.BuildMegaStorm(stormType): Model
	local model = Instance.new("Model")
	model.Name = "MegaStorm"

	local root = newPart({
		Name = "Root",
		Size = Vector3.one * 2,
		CFrame = CFrame.new(0, 24, 0),
		Transparency = 1,
		CanQuery = false,
		Parent = model,
	})
	local target = Instance.new("Attachment")
	target.Name = "Target"
	target.Parent = root

	local layers = 14
	for i = 0, layers - 1 do
		local t = i / (layers - 1)
		local diameter = 10 + i * 6.4
		local y = 3 + i * 5.6
		local spin = 1.6 - t * 0.9
		local layer = newPart({
			Name = "Layer",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(6, diameter, diameter),
			CFrame = CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = stormType.Color:Lerp(stormType.Accent, t * 0.6),
			Transparency = 0.18 + t * 0.32,
			Parent = model,
		})
		layer:SetAttribute("SpinSpeed", spin)
		for s = 0, 1 do
			local angle = i * 0.7 + s * math.pi
			local radius = diameter / 2
			local streak = newPart({
				Name = "Streak",
				Size = Vector3.new(1.2, 5, 3 + t * 4),
				CFrame = CFrame.new(math.cos(angle) * radius, y, math.sin(angle) * radius) * CFrame.Angles(0, -angle, 0),
				Color = shade(stormType.Color, 0.7),
				Transparency = 0.15,
				Parent = model,
			})
			streak:SetAttribute("SpinSpeed", spin)
		end
	end

	local rng = Random.new(7)
	for _ = 1, 16 do
		local size = rng:NextNumber(1.5, 4)
		local radius = rng:NextNumber(26, 58)
		local height = rng:NextNumber(8, 70)
		local phase = rng:NextNumber(0, math.pi * 2)
		local debris = newPart({
			Name = "Debris",
			Size = Vector3.new(size, size * rng:NextNumber(0.5, 1), size * rng:NextNumber(0.6, 1.2)),
			CFrame = CFrame.new(math.cos(phase) * radius, height, math.sin(phase) * radius),
			Color = shade(stormType.Color, 0.55),
			Material = Enum.Material.Slate,
			Parent = model,
		})
		debris:SetAttribute("OrbitRadius", radius)
		debris:SetAttribute("OrbitHeight", height)
		debris:SetAttribute("OrbitSpeed", rng:NextNumber(0.6, 1.4))
		debris:SetAttribute("OrbitPhase", phase)
	end

	local base = newPart({
		Name = "Base",
		Size = Vector3.new(40, 1, 40),
		CFrame = CFrame.new(0, 1, 0),
		Transparency = 1,
		CanQuery = false,
		Parent = model,
	})
	emitter(base, {
		Texture = TEXTURES.Smoke,
		Color = ColorSequence.new(stormType.Accent),
		Size = seq(8, 16),
		Transparency = seq(0.5, 1),
		Lifetime = NumberRange.new(2, 3),
		Rate = 16,
		Speed = NumberRange.new(8, 14),
		SpreadAngle = Vector2.new(80, 80),
		RotSpeed = NumberRange.new(-30, 30),
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	})

	newPart({
		Name = "Eye",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 14,
		CFrame = CFrame.new(0, 82, 0),
		Color = stormType.Accent,
		Material = Enum.Material.Neon,
		Transparency = 0.4,
		CanQuery = false,
		Parent = model,
	})
	light(root, stormType.Accent, 4, 60)
	emitter(root, {
		Texture = TEXTURES.Sparkle,
		Color = ColorSequence.new(stormType.Accent),
		Size = seq(3, 0),
		Lifetime = NumberRange.new(1.5, 2.5),
		Rate = 20,
		Speed = NumberRange.new(15, 25),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 1,
	})

	model.WorldPivot = CFrame.new()
	return model
end

return WeatherModels
