--!nonstrict
-- Builds Stormling pet models out of primitives from the Look table in Config/Pets.
-- The model faces -Z (its "front") and is centered on an invisible Root part.
--
-- PetModels.Build(petId, tier, options) -> model, parts
--   tier = "Normal" | "Golden" | "Rainbow" (a boolean still means golden)
--   parts = { { Part = BasePart, Offset = CFrame, Anim = string? } } (offsets relative to Root)
--   options.Effects = false skips particles/lights (used for viewports)
-- Rainbow pets get a pastel hue per tinted part; PetController cycles those hues in the world.

local Config = script.Parent.Parent:WaitForChild("Config")
local Pets = require(Config.Pets)

local PetModels = {}

local GOLD = Color3.fromRGB(255, 202, 58)
local GOLD_ACCENT = Color3.fromRGB(255, 160, 35)
local RAINBOW_LIGHT = Color3.fromRGB(255, 170, 235)
local EYE = Color3.fromRGB(28, 26, 38)
local WHITE = Color3.new(1, 1, 1)
local BLUSH = Color3.fromRGB(255, 140, 170)

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local RAINBOW_SEQUENCE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 110)),
	ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 240, 90)),
	ColorSequenceKeypoint.new(0.66, Color3.fromRGB(100, 200, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 120, 255)),
})
PetModels.RainbowSequence = RAINBOW_SEQUENCE

-- Hue step between tinted parts of a rainbow pet, and the saturation per tint
local RAINBOW_HUE_STEP = 0.11
local RAINBOW_SATURATION = { Body = 0.42, Accent = 0.62 }

-- Where the front surface and the top of each body type are (body radius = 1)
local BODY = {
	Round = { Front = -1, Top = 1, Blush = true },
	Cloud = { Front = -1, Top = 1.3, Blush = true },
	Drop = { Front = -1, Top = 1.9, Blush = true },
	Bean = { Front = -0.92, Top = 1.2, Blush = true },
	Cube = { Front = -1, Top = 1, Blush = false },
	Crystal = { Front = -0.9, Top = 1.3, Blush = false },
}

local BALL = Enum.PartType.Ball
local CYLINDER = Enum.PartType.Cylinder
local SPHERE_MESH = Enum.MeshType.Sphere

local function colorFor(ctx, color: Color3?, tint: string?): Color3
	if ctx.Golden then
		if tint == "Body" then
			return GOLD
		elseif tint == "Accent" then
			return GOLD_ACCENT
		end
	elseif ctx.Rainbow and tint then
		ctx.HueIndex += 1
		local hue = (ctx.HueIndex * RAINBOW_HUE_STEP + (if tint == "Accent" then 0.5 else 0)) % 1
		return Color3.fromHSV(hue, RAINBOW_SATURATION[tint] or 0.5, 1)
	end
	return color or ctx.Look.Color
end

-- props: Name, Shape, Size (unit scale), CFrame (unit scale), Color, Tint ("Body"/"Accent"/nil),
--        Material, Transparency, Mesh, Anim
local function add(ctx, props)
	local part = Instance.new("Part")
	part.Name = props.Name or "Part"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = props.Material or ctx.Material
	if props.Shape then
		part.Shape = props.Shape
	end
	part.Size = props.Size * ctx.Scale

	local offset = props.CFrame or CFrame.new()
	offset = offset.Rotation + offset.Position * ctx.Scale
	part.CFrame = offset

	part.Color = colorFor(ctx, props.Color, props.Tint)
	part.Transparency = props.Transparency or 0
	if ctx.Golden and props.Tint then
		part.Reflectance = 0.2
	elseif ctx.Rainbow and props.Tint then
		part.Reflectance = 0.12
	end
	if props.Tint then
		part:SetAttribute("Tint", props.Tint)
	end
	if props.Mesh then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = props.Mesh
		mesh.Parent = part
	end
	part.Parent = ctx.Model
	table.insert(ctx.Parts, { Part = part, Offset = offset, Anim = props.Anim })
	return part
end

local function body(ctx, look, color)
	local kind = look.Body
	if kind == "Cloud" then
		add(ctx, { Name = "Body", Shape = BALL, Size = Vector3.one * 2, Color = color, Tint = "Body" })
		for _, puff in {
			{ Vector3.new(0.95, -0.25, 0.1), 1.3 },
			{ Vector3.new(-0.95, -0.25, 0.1), 1.3 },
			{ Vector3.new(0.35, 0.75, 0.25), 1.2 },
			{ Vector3.new(-0.4, 0.7, 0.3), 1.1 },
		} do
			add(ctx, { Name = "Puff", Shape = BALL, Size = Vector3.one * puff[2], CFrame = CFrame.new(puff[1]), Color = color, Tint = "Body" })
		end
	elseif kind == "Drop" then
		add(ctx, { Name = "Body", Shape = BALL, Size = Vector3.one * 2, Color = color, Tint = "Body" })
		add(ctx, { Name = "Tip", Shape = BALL, Size = Vector3.one * 1.25, CFrame = CFrame.new(0, 0.95, 0.05), Color = color, Tint = "Body" })
		add(ctx, { Name = "Tip", Shape = BALL, Size = Vector3.one * 0.7, CFrame = CFrame.new(0, 1.55, 0.1), Color = color, Tint = "Body" })
	elseif kind == "Bean" then
		add(ctx, { Name = "Body", Size = Vector3.new(1.85, 2.35, 1.85), CFrame = CFrame.new(0, 0.1, 0), Color = color, Tint = "Body", Mesh = SPHERE_MESH })
	elseif kind == "Cube" then
		add(ctx, { Name = "Body", Size = Vector3.new(2, 2, 2), Color = color, Tint = "Body" })
	elseif kind == "Crystal" then
		add(ctx, {
			Name = "Body",
			Size = Vector3.new(1.45, 1.45, 1.45),
			CFrame = CFrame.Angles(0, math.rad(45), 0) * CFrame.Angles(math.rad(45), 0, 0),
			Color = color,
			Tint = "Body",
			Material = Enum.Material.Ice,
		})
		add(ctx, { Name = "Spire", Size = Vector3.new(0.5, 1.4, 0.5), CFrame = CFrame.new(0, 1.05, 0) * CFrame.Angles(0, math.rad(45), 0), Color = look.Accent, Tint = "Accent", Material = Enum.Material.Ice })
	else
		add(ctx, { Name = "Body", Shape = BALL, Size = Vector3.one * 2, Color = color, Tint = "Body" })
	end
end

local function face(ctx, look, info)
	local z = info.Front + 0.16
	local eyeColor = look.EyeColor or EYE
	local eyeMaterial = if look.EyeColor then Enum.Material.Neon else Enum.Material.SmoothPlastic
	for _, side in { -1, 1 } do
		add(ctx, { Name = "Eye", Shape = BALL, Size = Vector3.one * 0.42, CFrame = CFrame.new(side * 0.36, 0.2, z), Color = eyeColor, Material = eyeMaterial })
		add(ctx, { Name = "Shine", Shape = BALL, Size = Vector3.one * 0.13, CFrame = CFrame.new(side * 0.36 + 0.07, 0.29, z - 0.17), Color = WHITE, Material = Enum.Material.Neon })
		if info.Blush then
			add(ctx, { Name = "Blush", Shape = BALL, Size = Vector3.one * 0.3, CFrame = CFrame.new(side * 0.62, -0.12, z + 0.1), Color = BLUSH, Transparency = 0.35 })
		end
	end
end

local Features = {}

function Features.Ears(ctx, look, info)
	for _, side in { -1, 1 } do
		add(ctx, {
			Name = "Ear",
			Size = Vector3.new(0.38, 0.7, 0.22),
			CFrame = CFrame.new(side * 0.5, info.Top + 0.18, 0.05) * CFrame.Angles(0, 0, -side * 0.32),
			Color = look.Color,
			Tint = "Body",
		})
		add(ctx, {
			Name = "InnerEar",
			Size = Vector3.new(0.22, 0.45, 0.06),
			CFrame = CFrame.new(side * 0.49, info.Top + 0.16, -0.08) * CFrame.Angles(0, 0, -side * 0.32),
			Color = look.Accent,
			Tint = "Accent",
		})
	end
end

function Features.BunnyEars(ctx, look, info)
	for _, side in { -1, 1 } do
		add(ctx, {
			Name = "Ear",
			Size = Vector3.new(0.32, 1.15, 0.22),
			CFrame = CFrame.new(side * 0.32, info.Top + 0.45, 0.05) * CFrame.Angles(0, 0, -side * 0.16),
			Color = look.Color,
			Tint = "Body",
			Mesh = SPHERE_MESH,
		})
		add(ctx, {
			Name = "InnerEar",
			Size = Vector3.new(0.18, 0.8, 0.08),
			CFrame = CFrame.new(side * 0.31, info.Top + 0.45, -0.06) * CFrame.Angles(0, 0, -side * 0.16),
			Color = look.Accent,
			Tint = "Accent",
			Mesh = SPHERE_MESH,
		})
	end
end

function Features.Horns(ctx, look, info)
	for _, side in { -1, 1 } do
		add(ctx, {
			Name = "Horn",
			Size = Vector3.new(0.24, 0.62, 0.24),
			CFrame = CFrame.new(side * 0.45, info.Top + 0.12, 0) * CFrame.Angles(0, 0, -side * 0.45),
			Color = look.Accent,
			Tint = "Accent",
		})
		add(ctx, {
			Name = "HornTip",
			Size = Vector3.new(0.16, 0.3, 0.16),
			CFrame = CFrame.new(side * 0.62, info.Top + 0.44, 0) * CFrame.Angles(0, 0, -side * 0.75),
			Color = look.Accent,
			Tint = "Accent",
		})
	end
end

function Features.Antenna(ctx, look, info)
	add(ctx, {
		Name = "Antenna",
		Shape = CYLINDER,
		Size = Vector3.new(0.7, 0.1, 0.1),
		CFrame = CFrame.new(0, info.Top + 0.28, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(70, 70, 80),
	})
	add(ctx, { Name = "AntennaTip", Shape = BALL, Size = Vector3.one * 0.34, CFrame = CFrame.new(0, info.Top + 0.68, 0), Color = look.Accent, Material = Enum.Material.Neon })
end

function Features.Crown(ctx, look, info)
	local gold = Color3.fromRGB(255, 205, 50)
	add(ctx, {
		Name = "CrownBase",
		Shape = CYLINDER,
		Size = Vector3.new(0.28, 0.95, 0.95),
		CFrame = CFrame.new(0, info.Top + 0.06, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = gold,
	})
	for i = 0, 4 do
		local angle = i * math.pi * 2 / 5
		add(ctx, {
			Name = "CrownSpike",
			Size = Vector3.new(0.14, 0.34, 0.14),
			CFrame = CFrame.new(math.cos(angle) * 0.38, info.Top + 0.32, math.sin(angle) * 0.38) * CFrame.Angles(0, -angle, 0),
			Color = gold,
		})
	end
	add(ctx, { Name = "CrownGem", Shape = BALL, Size = Vector3.one * 0.2, CFrame = CFrame.new(0, info.Top + 0.08, -0.47), Color = Color3.fromRGB(255, 60, 90), Material = Enum.Material.Neon })
end

function Features.Halo(ctx, look, info)
	for i = 0, 9 do
		local angle = i * math.pi * 2 / 10
		add(ctx, {
			Name = "Halo",
			Shape = BALL,
			Size = Vector3.one * 0.17,
			CFrame = CFrame.new(math.cos(angle) * 0.55, info.Top + 0.55, math.sin(angle) * 0.55),
			Color = look.Accent,
			Material = Enum.Material.Neon,
			Anim = "SpinY",
		})
	end
end

function Features.Wings(ctx, look, info)
	for _, side in { -1, 1 } do
		add(ctx, {
			Name = "Wing",
			Size = Vector3.new(0.16, 0.95, 1.3),
			CFrame = CFrame.new(side * 1.05, 0.3, 0.3) * CFrame.Angles(0, 0, -side * 0.5),
			Color = look.Accent,
			Tint = "Accent",
			Mesh = SPHERE_MESH,
			Anim = if side < 0 then "WingL" else "WingR",
		})
	end
end

function Features.Tail(ctx, look, info)
	add(ctx, {
		Name = "Tail",
		Size = Vector3.new(0.5, 0.5, 1.05),
		CFrame = CFrame.new(0, -0.1, 1.05) * CFrame.Angles(math.rad(-30), 0, 0),
		Color = look.Color,
		Tint = "Body",
		Mesh = SPHERE_MESH,
		Anim = "Wag",
	})
	add(ctx, {
		Name = "TailTip",
		Shape = BALL,
		Size = Vector3.one * 0.38,
		CFrame = CFrame.new(0, 0.2, 1.5),
		Color = look.Accent,
		Tint = "Accent",
		Anim = "Wag",
	})
end

function Features.Bolt(ctx, look, info)
	local color = Color3.fromRGB(255, 230, 70)
	add(ctx, { Name = "Bolt", Size = Vector3.new(0.13, 0.4, 0.1), CFrame = CFrame.new(0.07, info.Top + 0.62, 0) * CFrame.Angles(0, 0, -0.45), Color = color, Material = Enum.Material.Neon })
	add(ctx, { Name = "Bolt", Size = Vector3.new(0.34, 0.1, 0.1), CFrame = CFrame.new(0, info.Top + 0.43, 0), Color = color, Material = Enum.Material.Neon })
	add(ctx, { Name = "Bolt", Size = Vector3.new(0.13, 0.4, 0.1), CFrame = CFrame.new(-0.07, info.Top + 0.24, 0) * CFrame.Angles(0, 0, -0.45), Color = color, Material = Enum.Material.Neon })
end

function Features.Spikes(ctx, look, info)
	for _, direction in {
		Vector3.new(1, 0.3, 0.2),
		Vector3.new(-1, 0.25, 0.1),
		Vector3.new(0.6, 0.4, 0.8),
		Vector3.new(-0.6, 0.5, 0.7),
		Vector3.new(0.9, -0.4, 0.4),
		Vector3.new(-0.9, -0.3, 0.5),
	} do
		local unit = direction.Unit
		local position = unit * 1.02
		add(ctx, {
			Name = "Spike",
			Size = Vector3.new(0.1, 0.36, 0.1),
			CFrame = CFrame.lookAt(position, position + unit) * CFrame.Angles(-math.pi / 2, 0, 0),
			Color = Color3.fromRGB(255, 245, 210),
		})
	end
end

function Features.Flower(ctx, look, info)
	add(ctx, { Name = "Flower", Shape = BALL, Size = Vector3.one * 0.5, CFrame = CFrame.new(0.3, info.Top + 0.12, 0), Color = look.Accent, Tint = "Accent" })
	add(ctx, { Name = "FlowerCenter", Shape = BALL, Size = Vector3.one * 0.22, CFrame = CFrame.new(0.3, info.Top + 0.2, -0.18), Color = Color3.fromRGB(255, 225, 80) })
end

function Features.Beak(ctx, look, info)
	add(ctx, { Name = "Beak", Size = Vector3.new(0.34, 0.18, 0.34), CFrame = CFrame.new(0, -0.05, info.Front - 0.08), Color = look.Accent, Tint = "Accent" })
end

function Features.Belly(ctx, look, info)
	add(ctx, { Name = "Belly", Size = Vector3.new(1.3, 1.55, 0.4), CFrame = CFrame.new(0, -0.15, info.Front + 0.2), Color = Color3.fromRGB(245, 245, 250), Mesh = SPHERE_MESH })
end

function Features.Rays(ctx, look, info)
	for i = 0, 7 do
		local angle = i * math.pi * 2 / 8
		add(ctx, {
			Name = "Ray",
			Size = Vector3.new(0.18, 0.5, 0.18),
			CFrame = CFrame.new(math.cos(angle) * 1.35, math.sin(angle) * 1.35, 0.1) * CFrame.Angles(0, 0, angle - math.pi / 2),
			Color = look.Accent,
			Tint = "Accent",
			Anim = "SpinZ",
		})
	end
end

function Features.Flame(ctx, look, info)
	add(ctx, { Name = "Flame", Shape = BALL, Size = Vector3.one * 0.55, CFrame = CFrame.new(0, info.Top + 0.15, 0.05), Color = Color3.fromRGB(255, 140, 40), Material = Enum.Material.Neon })
	add(ctx, { Name = "Flame", Shape = BALL, Size = Vector3.one * 0.32, CFrame = CFrame.new(0, info.Top + 0.5, 0.05), Color = Color3.fromRGB(255, 225, 90), Material = Enum.Material.Neon })
end

function Features.Cracks(ctx, look, info)
	for _, crack in {
		{ Vector3.new(0.75, 0.3, -0.55), Vector3.new(0.3, 0, 0.8) },
		{ Vector3.new(-0.6, -0.2, -0.75), Vector3.new(0, 0.4, -0.6) },
		{ Vector3.new(0.2, 0.85, 0.5), Vector3.new(0.9, 0, 0.2) },
		{ Vector3.new(-0.85, 0.4, 0.4), Vector3.new(0.2, 0.5, 0.3) },
	} do
		add(ctx, {
			Name = "Crack",
			Size = Vector3.new(0.09, 0.7, 0.09),
			CFrame = CFrame.new(crack[1]) * CFrame.Angles(crack[2].X, crack[2].Y, crack[2].Z),
			Color = look.Accent,
			Material = Enum.Material.Neon,
		})
	end
end

local function rainbowSparkles(rate: number, size: number)
	return {
		Texture = SPARKLE,
		Color = RAINBOW_SEQUENCE,
		Size = NumberSequence.new(size, 0),
		Lifetime = NumberRange.new(0.8, 1.2),
		Rate = rate,
		Speed = NumberRange.new(1, 2),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 1,
	}
end

local function addEffects(ctx, look, root)
	local accent = if ctx.Golden then GOLD elseif ctx.Rainbow then RAINBOW_LIGHT else look.Accent
	local effect = look.Effect
	local attachment = Instance.new("Attachment")
	attachment.Name = "FX"
	attachment.Parent = root

	local function particles(props)
		local emitter = Instance.new("ParticleEmitter")
		for key, value in props do
			emitter[key] = value
		end
		emitter.Parent = attachment
		return emitter
	end

	if effect == "Glow" or effect == "Fire" or ctx.Golden or ctx.Rainbow then
		local pointLight = Instance.new("PointLight")
		pointLight.Color = if effect == "Fire" then Color3.fromRGB(255, 140, 50) else accent
		pointLight.Brightness = 1.2
		pointLight.Range = 7
		pointLight.Shadows = false
		pointLight.Parent = root
	end

	if effect == "Sparkle" or effect == "Glow" then
		particles({
			Texture = SPARKLE,
			Color = ColorSequence.new(accent),
			Size = NumberSequence.new(0.35, 0),
			Lifetime = NumberRange.new(0.8, 1.2),
			Rate = 5,
			Speed = NumberRange.new(1, 2),
			SpreadAngle = Vector2.new(180, 180),
			LightEmission = 1,
		})
	elseif effect == "Fire" then
		particles({
			Texture = FIRE,
			Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 70, 30)),
			Size = NumberSequence.new(0.8, 0.1),
			Transparency = NumberSequence.new(0.2, 1),
			Lifetime = NumberRange.new(0.5, 0.8),
			Rate = 14,
			Speed = NumberRange.new(2, 3),
			SpreadAngle = Vector2.new(20, 20),
			EmissionDirection = Enum.NormalId.Top,
			LightEmission = 0.8,
		})
	elseif effect == "Snow" then
		particles({
			Texture = SPARKLE,
			Color = ColorSequence.new(Color3.new(1, 1, 1)),
			Size = NumberSequence.new(0.2),
			Lifetime = NumberRange.new(1.2, 1.8),
			Rate = 6,
			Speed = NumberRange.new(0.5, 1),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, -2, 0),
		})
	elseif effect == "Zap" then
		particles({
			Texture = SPARKLE,
			Color = ColorSequence.new(Color3.fromRGB(255, 235, 90)),
			Size = NumberSequence.new(0.3, 0),
			Lifetime = NumberRange.new(0.15, 0.3),
			Rate = 10,
			Speed = NumberRange.new(5, 7),
			SpreadAngle = Vector2.new(180, 180),
			LightEmission = 1,
		})
	elseif effect == "Smoke" then
		particles({
			Texture = SMOKE,
			Color = ColorSequence.new(look.Color),
			Size = NumberSequence.new(0.6, 1.4),
			Transparency = NumberSequence.new(0.6, 1),
			Lifetime = NumberRange.new(1, 1.4),
			Rate = 4,
			Speed = NumberRange.new(0.5, 1),
			SpreadAngle = Vector2.new(180, 180),
		})
	elseif effect == "Rainbow" and not ctx.Rainbow then
		particles(rainbowSparkles(8, 0.4))
	end

	if ctx.Golden then
		particles({
			Texture = SPARKLE,
			Color = ColorSequence.new(GOLD),
			Size = NumberSequence.new(0.3, 0),
			Lifetime = NumberRange.new(0.6, 1),
			Rate = 4,
			Speed = NumberRange.new(1, 2),
			SpreadAngle = Vector2.new(180, 180),
			LightEmission = 1,
		})
	elseif ctx.Rainbow then
		particles(rainbowSparkles(10, 0.45))
	end
end

-- tier: "Normal" | "Golden" | "Rainbow" (a boolean still means golden)
function PetModels.Scale(petId: string, tier): number
	local rarity = Pets.RarityOf(petId)
	local scale = if rarity then rarity.Scale else 1
	local tierName = Pets.TierOf(tier)
	if tierName == "Golden" then
		scale *= 1.06
	elseif tierName == "Rainbow" then
		scale *= 1.12
	end
	return scale
end

function PetModels.Build(petId: string, tier, options)
	options = options or {}
	local tierName = Pets.TierOf(tier)
	local def = Pets.Pets[petId] or Pets.Pets.Puffling
	local look = def.Look
	local info = BODY[look.Body] or BODY.Round

	local model = Instance.new("Model")
	model.Name = def.Name

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Transparency = 1
	root.Size = Vector3.one * 0.2
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root

	local ctx = {
		Model = model,
		Look = look,
		Scale = (options.Scale or 1) * PetModels.Scale(petId, tierName),
		Golden = tierName == "Golden",
		Rainbow = tierName == "Rainbow",
		HueIndex = 0,
		Material = if tierName ~= "Normal" then Enum.Material.SmoothPlastic else (look.Material or Enum.Material.SmoothPlastic),
		Parts = {},
	}

	body(ctx, look, look.Color)
	face(ctx, look, info)
	for _, feature in look.Features do
		local builder = Features[feature]
		if builder then
			builder(ctx, look, info)
		end
	end

	if options.Effects ~= false then
		addEffects(ctx, look, root)
	end

	-- Rainbow = some tinted parts cycle their hue in the world (rainbow tier or Rainbow effect)
	model:SetAttribute("PetId", petId)
	model:SetAttribute("Tier", tierName)
	model:SetAttribute("Golden", ctx.Golden)
	model:SetAttribute("Rainbow", ctx.Rainbow or (look.Effect == "Rainbow" and not ctx.Golden))
	return model, ctx.Parts
end

return PetModels
