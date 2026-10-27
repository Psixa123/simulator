--!nonstrict
-- Builds Stormling pet models from the Look table in Config/Pets: from the imported mesh pack
-- (ReplicatedStorage.PetMeshes, see "Mesh pack" below) when it has a valid template for the pet,
-- otherwise out of primitives. The model faces -Z (its "front") and is centered on an invisible Root part.
--
-- PetModels.Build(petId, tier, options) -> model, parts
--   tier = "Normal" | "Golden" | "Rainbow" (a boolean still means golden)
--   parts = { { Part = BasePart, Offset = CFrame, Anim = string?, Pivot = CFrame? } } (relative to Root;
--   Pivot is the hinge an animated mesh piece turns around)
--   options.Effects = false skips particles/lights (used for viewports)
-- Rainbow pets get a pastel hue per tinted part; PetController cycles those hues in the world.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

-- Colour of a pet piece; tinted ("Body"/"Accent") pieces follow the tier and get a Tint attribute
local function paint(ctx, part: BasePart, color: Color3?, tint: string?)
	part.Color = colorFor(ctx, color, tint)
	if ctx.Golden and tint then
		part.Reflectance = 0.2
	elseif ctx.Rainbow and tint then
		part.Reflectance = 0.12
	end
	if tint then
		part:SetAttribute("Tint", tint)
	end
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

	part.Transparency = props.Transparency or 0
	paint(ctx, part, props.Color, props.Tint)
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

	-- Secret pets: a cosmic aura on top of everything - a rainbow sparkle swirl, slow deep-violet motes and a
	-- soft glow in the pet's accent colour
	if ctx.Secret then
		particles(rainbowSparkles(9, 0.5))
		particles({
			Texture = SPARKLE,
			Color = ColorSequence.new(Color3.fromRGB(150, 90, 255), Color3.fromRGB(40, 20, 90)),
			Size = NumberSequence.new(0.6, 0),
			Transparency = NumberSequence.new(0.2, 1),
			Lifetime = NumberRange.new(1.4, 2),
			Rate = 4,
			Speed = NumberRange.new(0.3, 0.8),
			SpreadAngle = Vector2.new(180, 180),
			LightEmission = 0.6,
		})
		local glow = Instance.new("PointLight")
		glow.Name = "SecretGlow"
		glow.Color = accent
		glow.Brightness = 1.6
		glow.Range = 9
		glow.Shadows = false
		glow.Parent = root
	end
end

-------------------------------------------------------------------------------- Mesh pack
-- An optional pack of imported meshes (README: "Better pet models") replaces the primitives above.
-- It lives in ReplicatedStorage.PetMeshes, as a model per pet (PetMeshes > Puffling > Body, ...) or as
-- parts named "<PetId>.<Role>" (any depth). Every piece is named by its role and coloured here:
--   Body, Accent                           look.Color / look.Accent, recoloured by Golden/Rainbow tiers
--   Eye, Shine, Blush, Mouth               the face
--   Color_RRGGBB, Neon_RRGGBB, Ice_RRGGBB  a fixed colour in SmoothPlastic / Neon / Ice
--   <Role>@<Anim>                          animated (WingL, WingR, Wag, SpinY, SpinZ), turning around
--                                          its "Pivot@<Anim>" marker (a tiny cube on the hinge) if any
--   Root                                   a 0.2 stud cube on the pet's centre: the origin and scale
-- The pack is read once (again when it changes) and each pet's template is checked. A pet with a
-- missing or broken template is built from primitives (with a warning in Studio), so a bad import
-- never breaks the game.

local MOUTH = Color3.fromRGB(52, 32, 46)
local MESH_ROOT_SIZE = 0.2
local MESH_MAX_DISTANCE = 8 -- studs from the centre at unit scale; further away means a broken scale
local MESH_MAX_PIECES = 150

local MESH_ROLES = {} -- lower-case name -> role
for _, role in { "Body", "Accent", "Eye", "Shine", "Blush", "Mouth", "Root", "Pivot" } do
	MESH_ROLES[string.lower(role)] = role
end
local MESH_FIXED = { color = Enum.Material.SmoothPlastic, neon = Enum.Material.Neon, ice = Enum.Material.Ice }
local MESH_ANIMS = {} -- lower-case name -> PetController animation
for _, anim in { "WingL", "WingR", "Wag", "SpinY", "SpinZ" } do
	MESH_ANIMS[string.lower(anim)] = anim
end
local PET_IDS = {} -- lower-case id or name ("BreezeKing", "Breeze King") -> pet id
for id, pet in Pets.Pets do
	PET_IDS[string.lower(id)] = id
	PET_IDS[string.lower(pet.Name)] = id
end

local pack = {
	Source = nil, -- the PetMeshes instance the templates were read from
	Dirty = true,
	Templates = {}, -- [petId] = { Pieces = { { Part, Role, Color?, Material?, Anim?, Offset, Size, Pivot? } } }
	Connections = {},
}
local reported = {}

local function report(key: string, message: string, isWarning: boolean?)
	if reported[key] or not RunService:IsStudio() then
		return
	end
	reported[key] = true
	if isWarning == false then
		print("[PetModels] " .. message)
	else
		warn("[PetModels] " .. message)
	end
end

-- "Accent@WingL" -> { Role = "Accent", Anim = "WingL" }, "Neon_FFE14A" -> { Role = "Fixed", Color, Material }.
-- Tolerates importer suffixes ("Body.001", "Body_2") and a lost "@" ("Accent_WingL").
local function parseRole(name: string)
	local info, rest
	local prefix, hex, after = string.match(name, "^(%a+)_(%x%x%x%x%x%x)(.*)$")
	local material = prefix and MESH_FIXED[string.lower(prefix)]
	if material then
		info = { Role = "Fixed", Name = prefix .. "_" .. string.upper(hex), Color = Color3.fromHex(hex), Material = material }
		rest = after
	else
		local word, tail = string.match(name, "^(%a+)(.*)$")
		local role = word and MESH_ROLES[string.lower(word)]
		if not role then
			return nil
		end
		info = { Role = role, Name = role }
		rest = tail
	end
	local anim = string.match(rest, "@(%a+)") or string.match(rest, "^[_%-%s]+(%a+)")
	info.Anim = anim and MESH_ANIMS[string.lower(anim)]
	return info
end

-- The pet a pack part belongs to and its role name ("<PetId>.<Role>", or a part inside a "<PetId>" model).
-- "<PetId>_<Role>" is accepted too, in case an importer replaces the dot.
local function locate(part: Instance, source: Instance): (string?, string)
	local prefix, rest = string.match(part.Name, "^(.-)[%._](.+)$")
	local petId = prefix and PET_IDS[string.lower(prefix)]
	if petId then
		return petId, rest
	end
	local name = part.Name
	local node = part.Parent
	while node and node ~= source do
		petId = PET_IDS[string.lower(node.Name)]
		if petId then
			return petId, name
		end
		if not parseRole(name) then
			name = node.Name -- e.g. a "Body" model around a part the importer named after its mesh
		end
		node = node.Parent
	end
	return nil, name
end

local function finite(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) + math.abs(v.Y) + math.abs(v.Z) < math.huge
end

-- Checks one pet's pack parts and turns them into a template: cleaned-up copies of the meshes
-- with their offsets and sizes at unit scale around the Root cube. Returns nil, reason if broken.
local function prepare(petId: string, list)
	local root
	local pieces, pivots = {}, {}
	for _, entry in list do
		local info = parseRole(entry.Name)
		if not info then
			report(petId .. "/" .. entry.Name, `PetMeshes: ignoring "{entry.Name}" in {petId} (unknown role)`)
		elseif info.Role == "Root" then
			if root then
				return nil, "has more than one Root cube"
			end
			root = entry.Part
		elseif info.Role == "Pivot" then
			if info.Anim then
				pivots[info.Anim] = entry.Part
			end
		else
			info.Part = entry.Part
			table.insert(pieces, info)
		end
	end
	if not root then
		return nil, "has no Root cube"
	end
	local rootSize = root.Size.X
	if not (rootSize > 1e-4 and rootSize < 1e4) then
		return nil, "has a Root cube with a broken size"
	end
	if #pieces == 0 or #pieces > MESH_MAX_PIECES then
		return nil, `has {#pieces} meshes`
	end
	local factor = MESH_ROOT_SIZE / rootSize
	local origin = root.CFrame

	-- The face must be on the front (-Z). A pack that faces +Z (another exporter or importer "World
	-- Forward" convention) is turned around; any other orientation is rejected.
	local hasBody = false
	local eyes, eyeCount = Vector3.zero, 0
	for _, piece in pieces do
		hasBody = hasBody or piece.Role == "Body"
		if piece.Role == "Eye" then
			eyes += origin:PointToObjectSpace(piece.Part.Position) * factor
			eyeCount += 1
		end
	end
	if not hasBody then
		return nil, "has no Body mesh"
	end
	if eyeCount > 0 then
		eyes /= eyeCount
		if eyes.Z > 0 then
			origin *= CFrame.Angles(0, math.pi, 0)
			eyes = Vector3.new(-eyes.X, eyes.Y, -eyes.Z)
			report("flipped", "PetMeshes faces +Z; turning the pets around to face -Z", false)
		end
		if not (-eyes.Z > 0.25 and -eyes.Z > math.abs(eyes.Y)) then
			return nil, "has its eyes off the front (-Z) of the pet (check the importer's World Up / World Forward)"
		end
	end

	local template = { Pieces = {} }
	for _, piece in pieces do
		local part = piece.Part
		local relative = origin:ToObjectSpace(part.CFrame)
		local position = relative.Position * factor
		local size = part.Size * factor
		if not (finite(position) and finite(size)) or position.Magnitude > MESH_MAX_DISTANCE or size.Magnitude > MESH_MAX_DISTANCE * 2 then
			return nil, `has a "{piece.Name}" mesh far from its Root cube (is the Root cube scaled like the rest?)`
		end

		local anim = piece.Anim
		local pivotPart = anim and pivots[anim]
		local pivot = if pivotPart then origin:PointToObjectSpace(pivotPart.Position) * factor else nil
		if pivot and not (finite(pivot) and pivot.Magnitude <= MESH_MAX_DISTANCE) then
			pivot = nil
		end
		-- Wings flap mirrored, so trust the side a wing is on over its name (mirrored/turned packs)
		local side = (pivot or position).X
		if anim == "WingL" and side > 0.05 then
			anim = "WingR"
		elseif anim == "WingR" and side < -0.05 then
			anim = "WingL"
		end

		local copy = part:Clone()
		if not copy then
			return nil, `has a "{piece.Name}" mesh that can't be copied (Archivable is off)`
		end
		copy.Name = piece.Name
		copy:ClearAllChildren() -- SurfaceAppearances etc. would hide the role colours
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanQuery = false
		copy.CanTouch = false
		copy.CastShadow = false
		copy.Reflectance = 0
		copy.MaterialVariant = ""
		if copy:IsA("MeshPart") then
			-- A texture would hide the role colour. Thin pieces (wings, inner ears) should show both
			-- faces; scripts may not be allowed to set that, then the importer's "Double Sided" counts.
			local thin = math.min(size.X, size.Y, size.Z) < math.max(size.X, size.Y, size.Z) * 0.15
			pcall(function()
				if copy.TextureID ~= "" then
					copy.TextureID = ""
				end
				if thin or anim == "WingL" or anim == "WingR" then
					copy.DoubleSided = true
				end
			end)
		end

		table.insert(template.Pieces, {
			Part = copy,
			Role = piece.Role,
			Color = piece.Color,
			Material = piece.Material,
			Anim = anim,
			Offset = relative.Rotation + position,
			Size = size,
			Pivot = pivot,
		})
	end
	return template
end

-- Reads every pet's template from the pack
local function loadPack(source: Instance)
	local lists = {}
	for _, descendant in source:GetDescendants() do
		if descendant:IsA("BasePart") then
			local petId, name = locate(descendant, source)
			if petId then
				lists[petId] = lists[petId] or {}
				table.insert(lists[petId], { Part = descendant, Name = name })
			end
		end
	end

	local templates, fallback = {}, {}
	local count, total = 0, 0
	for petId in Pets.Pets do
		total += 1
		local list = lists[petId]
		local ok, template, reason = false, nil, nil
		if list then
			ok, template, reason = pcall(prepare, petId, list)
			if not ok then
				reason = "can't be read (" .. tostring(template) .. ")"
				template = nil
			end
		end
		if template then
			templates[petId] = template
			count += 1
		else
			table.insert(fallback, petId)
			if reason then
				report(petId .. "/" .. reason, `PetMeshes: {petId} {reason}; using its built-in model`)
			end
		end
	end
	pack.Templates = templates

	table.sort(fallback)
	if count == 0 then
		report(
			"empty",
			"ReplicatedStorage.PetMeshes has no pet meshes this game can use (expected PetMeshes > <PetId> > <Role> "
				.. "or parts named <PetId>.<Role>); every pet uses its built-in model"
		)
	elseif #fallback > 0 then
		report(`count{count}`, `PetMeshes: mesh models for {count}/{total} pets; built-in models for {table.concat(fallback, ", ")}`, false)
	else
		report(`count{count}`, `PetMeshes: mesh models for all {total} pets`, false)
	end

	-- Download the meshes now so pets don't pop in on their first hatch or equip
	if count > 0 and RunService:IsClient() then
		task.spawn(function()
			pcall(ContentProvider.PreloadAsync, ContentProvider, { source })
		end)
	end
end

-- The usable templates of the current pack ({} without one). Cached until the pack changes.
local function currentTemplates()
	local source = ReplicatedStorage:FindFirstChild("PetMeshes")
	if source ~= pack.Source then
		for _, connection in pack.Connections do
			connection:Disconnect()
		end
		pack.Source = source
		pack.Connections = {}
		pack.Templates = {}
		pack.Dirty = true
		if source then
			local function changed()
				pack.Dirty = true
			end
			pack.Connections = { source.DescendantAdded:Connect(changed), source.DescendantRemoving:Connect(changed) }
		end
	end
	if source and pack.Dirty then
		pack.Dirty = false
		loadPack(source)
	end
	return pack.Templates
end

-- Calls callback() (once things settle) whenever ReplicatedStorage.PetMeshes appears or goes away, e.g.
-- when the server's PetMeshService inserts an uploaded pack after the first pets were built, so code
-- holding built pets can rebuild them. Returns a function that stops the callbacks.
local PACK_SETTLE = 1 -- seconds for a new pack to finish replicating
local packListeners = {}
local packWatched = false
local packChanges = 0

function PetModels.OnPackChanged(callback: () -> ()): () -> ()
	table.insert(packListeners, callback)
	if not packWatched then
		packWatched = true
		local function changed(child: Instance)
			if child.Name ~= "PetMeshes" then
				return
			end
			packChanges += 1
			local change = packChanges
			task.delay(PACK_SETTLE, function()
				if change ~= packChanges then
					return -- a later change will notify
				end
				for _, listener in table.clone(packListeners) do
					task.spawn(listener)
				end
			end)
		end
		ReplicatedStorage.ChildAdded:Connect(changed)
		ReplicatedStorage.ChildRemoved:Connect(changed)
	end
	return function()
		local index = table.find(packListeners, callback)
		if index then
			table.remove(packListeners, index)
		end
	end
end

local function addMeshes(ctx, look, template)
	local eyeColor = look.EyeColor or EYE
	local eyeMaterial = if look.EyeColor then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local tintMaterial = if look.Body == "Crystal" then Enum.Material.Ice else ctx.Material
	for _, piece in template.Pieces do
		local role = piece.Role
		local color, tint, material, transparency = piece.Color, nil, piece.Material, 0
		if role == "Body" or role == "Accent" then
			color = if role == "Body" then look.Color else look.Accent
			tint, material = role, tintMaterial
		elseif role == "Eye" then
			color, material = eyeColor, eyeMaterial
		elseif role == "Shine" then
			color, material = WHITE, Enum.Material.Neon
		elseif role == "Blush" then
			color, material, transparency = BLUSH, Enum.Material.SmoothPlastic, 0.35
		elseif role == "Mouth" then
			color, material = MOUTH, Enum.Material.SmoothPlastic
		end

		local part = piece.Part:Clone()
		part.Material = material or Enum.Material.SmoothPlastic
		part.Transparency = transparency
		paint(ctx, part, color, tint)
		part.Size = piece.Size * ctx.Scale -- a MeshPart stretches its mesh to its Size
		local offset = piece.Offset.Rotation + piece.Offset.Position * ctx.Scale
		part.CFrame = offset
		part.Parent = ctx.Model
		table.insert(ctx.Parts, {
			Part = part,
			Offset = offset,
			Anim = piece.Anim,
			Pivot = if piece.Pivot then CFrame.new(piece.Pivot * ctx.Scale) else nil,
		})
	end
end

-- Whether the pet is built from the imported mesh pack
function PetModels.HasMeshes(petId: string): boolean
	local ok, templates = pcall(currentTemplates)
	return ok and templates[petId] ~= nil
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
		Secret = def.Rarity == "Secret",
		HueIndex = 0,
		Material = if tierName ~= "Normal" then Enum.Material.SmoothPlastic else (look.Material or Enum.Material.SmoothPlastic),
		Parts = {},
	}

	-- The imported mesh pack when it has this pet, else primitives (also if building the meshes fails)
	local ok, templates = pcall(currentTemplates)
	local template = ok and templates[def.Id]
	local meshes = false
	if template then
		local built, problem = pcall(addMeshes, ctx, look, template)
		if built then
			meshes = true
		else
			for _, item in ctx.Parts do
				item.Part:Destroy()
			end
			table.clear(ctx.Parts)
			ctx.HueIndex = 0
			templates[def.Id] = nil
			report(def.Id .. "/build", `PetMeshes: {def.Id} can't be built ({problem}); using its built-in model`)
		end
	end
	if not meshes then
		body(ctx, look, look.Color)
		face(ctx, look, info)
		for _, feature in look.Features do
			local builder = Features[feature]
			if builder then
				builder(ctx, look, info)
			end
		end
	end

	if options.Effects ~= false then
		addEffects(ctx, look, root)
	end

	-- Rainbow = some tinted parts cycle their hue in the world (rainbow tier or Rainbow effect)
	model:SetAttribute("PetId", petId)
	model:SetAttribute("Tier", tierName)
	model:SetAttribute("MeshPack", meshes)
	model:SetAttribute("Golden", ctx.Golden)
	model:SetAttribute("Rainbow", ctx.Rainbow or (look.Effect == "Rainbow" and not ctx.Golden))
	return model, ctx.Parts
end

return PetModels
