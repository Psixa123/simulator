--!nonstrict
-- Builds the whole world when the server starts: terrain, the Storm Station hub, six themed
-- zones with gates, sell pads and egg stations, decorations, leaderboards and lighting.
-- Everything is generated from code so the place file stays tiny and easy to tweak.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapLayout = require(Shared.Config.MapLayout)
local Zones = require(Shared.Config.Zones)
local Pets = require(Shared.Config.Pets)
local Format = require(Shared.Util.Format)
local EggModels = require(Shared.Models.EggModels)

local MapService = {}
MapService.Leaderboards = {} -- [kind] = { Rows = { { Frame, Name, Value } }, Status = TextLabel }

local terrain = Workspace.Terrain

local WHITE = Color3.new(1, 1, 1)
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function shade(color: Color3, amount: number): Color3
	return Color3.new(
		math.clamp(color.R * amount, 0, 1),
		math.clamp(color.G * amount, 0, 1),
		math.clamp(color.B * amount, 0, 1)
	)
end

---------------------------------------------------------------------------
-- Instance helpers
---------------------------------------------------------------------------
local function part(props, className: string?)
	local instance = Instance.new(className or "Part")
	instance.Anchored = true
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	instance.Material = Enum.Material.SmoothPlastic
	if props.Shape then
		instance.Shape = props.Shape
	end
	for key, value in props do
		if key ~= "Parent" and key ~= "Shape" and key ~= "Tags" and key ~= "Attributes" then
			instance[key] = value
		end
	end
	if props.Tags then
		for _, tag in props.Tags do
			CollectionService:AddTag(instance, tag)
		end
	end
	if props.Attributes then
		for name, value in props.Attributes do
			instance:SetAttribute(name, value)
		end
	end
	instance.Parent = props.Parent
	return instance
end

local function wedge(props)
	return part(props, "WedgePart")
end

-- Vertical cylinder: props.Position (center), props.Height, props.Diameter
local function cylinder(props)
	local base = props.CFrame or CFrame.new(props.Position)
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(props.Height, props.Diameter, props.Diameter)
	props.CFrame = base * CFrame.Angles(0, 0, math.rad(90))
	props.Position = nil
	props.Height = nil
	props.Diameter = nil
	return part(props)
end

local function ball(position: Vector3, diameter: number, color: Color3, props)
	props = props or {}
	props.Shape = Enum.PartType.Ball
	props.Size = Vector3.one * diameter
	props.CFrame = CFrame.new(position)
	props.Color = color
	return part(props)
end

local function folder(name: string, parent: Instance): Folder
	local instance = Instance.new("Folder")
	instance.Name = name
	instance.Parent = parent
	return instance
end

local function model(name: string, parent: Instance): Model
	local instance = Instance.new("Model")
	instance.Name = name
	instance.Parent = parent
	return instance
end

local function emitter(parent: Instance, props)
	local particles = Instance.new("ParticleEmitter")
	for key, value in props do
		particles[key] = value
	end
	particles.Parent = parent
	return particles
end

local function pointLight(parent: Instance, color: Color3, brightness: number, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = parent
	return light
end

local function corner(parent: Instance, radius: number)
	local instance = Instance.new("UICorner")
	instance.CornerRadius = UDim.new(0, radius)
	instance.Parent = parent
end

local function textLabel(parent: Instance, props)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = WHITE
	label.TextScaled = true
	label.Size = UDim2.fromScale(1, 1)
	local strokeThickness = props.Stroke
	for key, value in props do
		if key ~= "Stroke" then
			label[key] = value
		end
	end
	if strokeThickness ~= false then
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = strokeThickness or 2.5
		stroke.Color = rgb(12, 16, 38)
		stroke.Parent = label
	end
	label.Parent = parent
	return label
end

local function surfaceGui(adornee: BasePart, face: Enum.NormalId, pixelsPerStud: number?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud or 30
	gui.LightInfluence = 0
	gui.Brightness = 1.3
	gui.Parent = adornee
	return gui
end

local function billboard(adornee: BasePart, size: UDim2, offset: Vector3, maxDistance: number?): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffsetWorldSpace = offset
	gui.MaxDistance = maxDistance or 180
	gui.LightInfluence = 0
	gui.Adornee = adornee
	gui.Parent = adornee
	return gui
end

local function prompt(parent: Instance, actionText: string, objectText: string, holdDuration: number?, distance: number?)
	local instance = Instance.new("ProximityPrompt")
	instance.ActionText = actionText
	instance.ObjectText = objectText
	instance.HoldDuration = holdDuration or 0
	instance.MaxActivationDistance = distance or 14
	instance.RequiresLineOfSight = false
	instance.KeyboardKeyCode = Enum.KeyCode.E
	instance.Parent = parent
	return instance
end

local function promptHost(parent: Instance, position: Vector3): BasePart
	return part({
		Name = "PromptHost",
		Size = Vector3.one,
		CFrame = CFrame.new(position),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = parent,
	})
end

---------------------------------------------------------------------------
-- Terrain
---------------------------------------------------------------------------
local M = Enum.Material

local TERRAIN_COLORS = {
	[M.Grass] = rgb(108, 190, 82),
	[M.LeafyGrass] = rgb(92, 172, 70),
	[M.Ground] = rgb(124, 100, 78),
	[M.Rock] = rgb(124, 124, 132),
	[M.Slate] = rgb(86, 88, 106),
	[M.Mud] = rgb(88, 74, 70),
	[M.Sand] = rgb(236, 208, 150),
	[M.Sandstone] = rgb(212, 160, 108),
	[M.Snow] = rgb(240, 246, 255),
	[M.Glacier] = rgb(168, 214, 245),
	[M.Ice] = rgb(190, 225, 250),
	[M.Basalt] = rgb(56, 50, 52),
	[M.CrackedLava] = rgb(74, 52, 46),
	[M.Salt] = rgb(232, 226, 255),
	[M.Pavement] = rgb(150, 155, 168),
}

local THEMES = {
	[0] = { Ground = M.Grass, Patches = { M.LeafyGrass }, Path = M.Pavement, Ridge = M.Grass, Peak = M.Rock },
	[1] = { Ground = M.Grass, Patches = { M.LeafyGrass, M.Ground }, Path = M.Ground, Ridge = M.Grass, Peak = M.Rock },
	[2] = { Ground = M.Slate, Patches = { M.Rock, M.Mud }, Path = M.Mud, Ridge = M.Rock, Peak = M.Slate },
	[3] = { Ground = M.Sand, Patches = { M.Sandstone }, Path = M.Sandstone, Ridge = M.Sandstone, Peak = M.Sand },
	[4] = { Ground = M.Snow, Patches = { M.Ice, M.Glacier }, Path = M.Glacier, Ridge = M.Snow, Peak = M.Glacier },
	[5] = { Ground = M.Basalt, Patches = { M.CrackedLava }, Path = M.CrackedLava, Ridge = M.Basalt, Peak = M.Basalt },
	[6] = { Ground = M.Salt, Patches = { M.Glacier }, Path = M.Glacier, Ridge = M.Salt, Peak = M.Salt },
}

local function regionBounds(zoneId: number): (number, number)
	if zoneId == 0 then
		return MapLayout.HubStart, MapLayout.HubEnd
	end
	return MapLayout.ZoneStart(zoneId), MapLayout.ZoneEnd(zoneId)
end

local function buildTerrain()
	terrain:Clear()
	for material, color in TERRAIN_COLORS do
		terrain:SetMaterialColor(material, color)
	end

	local rng = Random.new(2024)
	for zoneId = 0, MapLayout.ZoneCount do
		local theme = THEMES[zoneId]
		local x0, x1 = regionBounds(zoneId)
		local length = x1 - x0
		local centerX = (x0 + x1) / 2

		terrain:FillBlock(CFrame.new(centerX, -10, 0), Vector3.new(length + 2, 20, 380), theme.Ground)

		for _ = 1, 12 do
			local material = theme.Patches[rng:NextInteger(1, #theme.Patches)]
			local position = Vector3.new(rng:NextNumber(x0 + 10, x1 - 10), -1, rng:NextNumber(-100, 100))
			terrain:FillCylinder(CFrame.new(position), 2, rng:NextNumber(8, 18), material)
		end
		terrain:FillBlock(CFrame.new(centerX, -1, 0), Vector3.new(length + 2, 2, 16), theme.Path)

		for x = x0, x1, 16 do
			for _, side in { -1, 1 } do
				local radius = rng:NextNumber(24, 36)
				local center = Vector3.new(x + rng:NextNumber(-5, 5), rng:NextNumber(-6, 6), side * (152 + rng:NextNumber(-6, 6)))
				terrain:FillBall(center, radius, theme.Ridge)
				if rng:NextNumber() < 0.35 then
					terrain:FillBall(
						center + Vector3.new(rng:NextNumber(-8, 8), radius * 0.7, side * 12),
						radius * 0.6,
						theme.Peak
					)
				end
			end
		end
	end

	for z = -180, 180, 16 do
		terrain:FillBall(Vector3.new(MapLayout.HubStart - 32, rng:NextNumber(-4, 10), z), rng:NextNumber(26, 38), M.Rock)
		terrain:FillBall(Vector3.new(MapLayout.WorldEnd + 32, rng:NextNumber(-4, 10), z), rng:NextNumber(26, 38), M.Salt)
	end
end

local function buildBoundaries(parent: Instance)
	local walls = folder("Boundaries", parent)
	local length = MapLayout.WorldEnd - MapLayout.HubStart
	local centerX = (MapLayout.WorldEnd + MapLayout.HubStart) / 2
	local function wall(cframe: CFrame, size: Vector3)
		part({
			Name = "Boundary",
			CFrame = cframe,
			Size = size,
			Transparency = 1,
			CanQuery = false,
			CanTouch = false,
			Parent = walls,
		})
	end
	wall(CFrame.new(centerX, 110, -(MapLayout.HalfWidth + 2)), Vector3.new(length + 24, 280, 4))
	wall(CFrame.new(centerX, 110, MapLayout.HalfWidth + 2), Vector3.new(length + 24, 280, 4))
	wall(CFrame.new(MapLayout.HubStart - 4, 110, 0), Vector3.new(4, 280, 260))
	wall(CFrame.new(MapLayout.WorldEnd + 4, 110, 0), Vector3.new(4, 280, 260))
end

---------------------------------------------------------------------------
-- Generic props
---------------------------------------------------------------------------
local function lamp(parent: Instance, position: Vector3, color: Color3?)
	local glow = color or rgb(255, 232, 170)
	cylinder({ Name = "LampPole", Position = position + Vector3.new(0, 5, 0), Height = 10, Diameter = 0.6, Color = rgb(55, 60, 75), Material = M.Metal, Parent = parent })
	cylinder({ Name = "LampCap", Position = position + Vector3.new(0, 11.7, 0), Height = 0.4, Diameter = 2.2, Color = rgb(55, 60, 75), Material = M.Metal, Parent = parent })
	local bulb = ball(position + Vector3.new(0, 10.7, 0), 1.6, glow, { Name = "LampBulb", Material = M.Neon, Parent = parent })
	pointLight(bulb, glow, 1.2, 18)
end

local function roundTree(parent: Instance, position: Vector3, scale: number, leafColor: Color3)
	local tree = model("Tree", parent)
	cylinder({ Name = "Trunk", Position = position + Vector3.new(0, 4 * scale, 0), Height = 8 * scale, Diameter = 1.6 * scale, Color = rgb(122, 84, 52), Material = M.Wood, Parent = tree })
	local leaves = {
		{ Vector3.new(0, 10, 0), 8 },
		{ Vector3.new(2.4, 8.6, 1.2), 6 },
		{ Vector3.new(-2.4, 8.8, -1), 5.6 },
		{ Vector3.new(0.6, 12.4, -0.6), 5 },
		{ Vector3.new(-1, 9, 2.4), 5 },
	}
	for index, leaf in leaves do
		local leafPart = ball(position + leaf[1] * scale, leaf[2] * scale, shade(leafColor, 0.9 + (index % 3) * 0.07), { Name = "Leaves", Parent = tree })
		leafPart.CastShadow = index <= 2
	end
end

local function pineTree(parent: Instance, position: Vector3, scale: number, snowy: boolean)
	local tree = model("Pine", parent)
	cylinder({ Name = "Trunk", Position = position + Vector3.new(0, 2 * scale, 0), Height = 4 * scale, Diameter = 1.3 * scale, Color = rgb(110, 76, 50), Material = M.Wood, Parent = tree })
	for _, layer in { { 3.6, 9 }, { 6.4, 7.2 }, { 9.2, 5.2 }, { 11.8, 3 } } do
		cylinder({ Name = "Needles", Position = position + Vector3.new(0, layer[1] * scale, 0), Height = 2.6 * scale, Diameter = layer[2] * scale, Color = rgb(46, 112, 78), Parent = tree })
		if snowy then
			cylinder({ Name = "Snow", Position = position + Vector3.new(0, (layer[1] + 1.4) * scale, 0), Height = 0.5 * scale, Diameter = layer[2] * 0.82 * scale, Color = rgb(246, 250, 255), Parent = tree })
		end
	end
end

local function deadTree(parent: Instance, position: Vector3, scale: number, color: Color3)
	local tree = model("DeadTree", parent)
	cylinder({ Name = "Trunk", Position = position + Vector3.new(0, 4.5 * scale, 0), Height = 9 * scale, Diameter = 1.2 * scale, Color = color, Material = M.Wood, Parent = tree })
	for _, branch in {
		{ Vector3.new(1.3, 7, 0), CFrame.Angles(0, 0, -0.75) },
		{ Vector3.new(-1.2, 6, 0.3), CFrame.Angles(0, 0, 0.8) },
		{ Vector3.new(0, 8.6, 1.1), CFrame.Angles(0.7, 0, 0) },
	} do
		part({ Name = "Branch", Size = Vector3.new(0.55, 3.6, 0.55) * scale, CFrame = CFrame.new(position + branch[1] * scale) * branch[2], Color = color, Material = M.Wood, Parent = tree })
	end
end

local function bush(parent: Instance, position: Vector3, scale: number, color: Color3)
	for _, puff in { { Vector3.new(0, 1.2, 0), 3.2 }, { Vector3.new(1.4, 0.9, 0.4), 2.4 }, { Vector3.new(-1.3, 0.8, -0.3), 2.2 } } do
		ball(position + puff[1] * scale, puff[2] * scale, color, { Name = "Bush", Parent = parent })
	end
end

local function rock(parent: Instance, position: Vector3, size: number, color: Color3, material, rng)
	part({
		Name = "Rock",
		Size = Vector3.new(size, size * 0.7, size * 0.9),
		CFrame = CFrame.new(position + Vector3.new(0, size * 0.22, 0))
			* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi), rng:NextNumber(-0.3, 0.3)),
		Color = color,
		Material = material or M.Slate,
		Parent = parent,
	})
end

local FLOWER_COLORS = { rgb(255, 90, 110), rgb(255, 210, 60), rgb(255, 140, 200), rgb(250, 250, 255), rgb(170, 120, 255) }

local function flowerPatch(parent: Instance, position: Vector3, rng)
	for _ = 1, 5 do
		local offset = Vector3.new(rng:NextNumber(-2.5, 2.5), 0, rng:NextNumber(-2.5, 2.5))
		cylinder({ Name = "Stem", Position = position + offset + Vector3.new(0, 0.6, 0), Height = 1.2, Diameter = 0.18, Color = rgb(70, 150, 60), CanCollide = false, Parent = parent })
		ball(position + offset + Vector3.new(0, 1.35, 0), 0.7, FLOWER_COLORS[rng:NextInteger(1, #FLOWER_COLORS)], { Name = "Flower", CanCollide = false, Parent = parent })
	end
end

local function crystalCluster(parent: Instance, position: Vector3, color: Color3, rng, material)
	local cluster = model("Crystals", parent)
	for _ = 1, rng:NextInteger(3, 5) do
		local height = rng:NextNumber(3, 7)
		part({
			Name = "Crystal",
			Size = Vector3.new(1.3, height, 1.3),
			CFrame = CFrame.new(position + Vector3.new(rng:NextNumber(-1.6, 1.6), height / 2 - 0.4, rng:NextNumber(-1.6, 1.6)))
				* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 3), rng:NextNumber(-0.4, 0.4)),
			Color = color,
			Material = material or M.Neon,
			Parent = cluster,
		})
	end
end

-- Scatters props in [x0, x1] with |z| between zMin and zMax, avoiding circles in `avoid`
local function scatter(rng, x0: number, x1: number, count: number, avoid, zMin: number, zMax: number, place)
	local placed, attempts = 0, 0
	while placed < count and attempts < count * 15 do
		attempts += 1
		local z = rng:NextNumber(zMin, zMax) * (if rng:NextNumber() < 0.5 then -1 else 1)
		local position = Vector3.new(rng:NextNumber(x0, x1), 0, z)
		local clear = true
		for _, area in avoid do
			if (Vector3.new(position.X - area[1].X, 0, position.Z - area[1].Z)).Magnitude < area[2] then
				clear = false
				break
			end
		end
		if clear then
			place(position)
			placed += 1
		end
	end
end

---------------------------------------------------------------------------
-- Stations
---------------------------------------------------------------------------
-- Open booth. Local -Z of the booth faces `facing`.
local function kiosk(parent: Instance, position: Vector3, facing: Vector3, title: string, icon: string, color: Color3, panel: string?)
	local booth = model(title, parent)
	local base = CFrame.lookAt(position, position + facing)
	local function at(offset: Vector3): CFrame
		return base * CFrame.new(offset)
	end

	part({ Name = "Floor", Size = Vector3.new(18, 1, 13), CFrame = at(Vector3.new(0, 0.5, 0)), Color = rgb(226, 230, 240), Parent = booth })
	for _, x in { -8, 8 } do
		for _, z in { -5.6, 5.6 } do
			part({ Name = "Pillar", Size = Vector3.new(1.2, 10, 1.2), CFrame = at(Vector3.new(x, 6, z)), Color = rgb(242, 244, 250), Parent = booth })
		end
	end
	part({ Name = "BackWall", Size = Vector3.new(16, 10, 0.8), CFrame = at(Vector3.new(0, 6, 5.6)), Color = rgb(64, 74, 108), Parent = booth })
	part({ Name = "Roof", Size = Vector3.new(19.5, 1.4, 14.5), CFrame = at(Vector3.new(0, 11.7, 0)), Color = color, Parent = booth })
	part({ Name = "RoofTrim", Size = Vector3.new(19.8, 0.35, 14.8), CFrame = at(Vector3.new(0, 10.9, 0)), Color = color:Lerp(WHITE, 0.45), Material = M.Neon, Parent = booth })
	part({ Name = "Counter", Size = Vector3.new(12, 3.4, 2.2), CFrame = at(Vector3.new(0, 2.7, -3.2)), Color = shade(color, 0.65), Parent = booth })
	part({ Name = "CounterTop", Size = Vector3.new(12.6, 0.35, 2.8), CFrame = at(Vector3.new(0, 4.55, -3.2)), Color = rgb(246, 246, 252), Parent = booth })
	part({ Name = "Screen", Size = Vector3.new(9, 4.5, 0.25), CFrame = at(Vector3.new(0, 6.8, 5.1)), Color = color, Material = M.Neon, Transparency = 0.15, Parent = booth })

	local sign = part({ Name = "Sign", Size = Vector3.new(15, 3.6, 0.6), CFrame = at(Vector3.new(0, 14.3, -2)), Color = rgb(26, 32, 64), Parent = booth })
	part({ Name = "SignTrim", Size = Vector3.new(15.4, 4, 0.4), CFrame = at(Vector3.new(0, 14.3, -1.8)), Color = color, Material = M.Neon, Parent = booth })
	local gui = surfaceGui(sign, Enum.NormalId.Front, 40)
	textLabel(gui, { Text = icon .. " " .. string.upper(title), Size = UDim2.fromScale(0.94, 0.78), Position = UDim2.fromScale(0.03, 0.11) })

	if panel then
		local host = promptHost(booth, at(Vector3.new(0, 4, -4.6)).Position)
		local instance = prompt(host, "Open", title, 0, 14)
		instance:SetAttribute("Panel", panel)
	end
	return booth, base
end

local function sellPad(parent: Instance, position: Vector3, color: Color3)
	local pad = model("SellPad", parent)
	cylinder({ Name = "PadBase", Position = position + Vector3.new(0, 0.3, 0), Height = 0.6, Diameter = 19.5, Color = rgb(40, 46, 66), Parent = pad })
	local glow = cylinder({ Name = "PadGlow", Position = position + Vector3.new(0, 0.42, 0), Height = 0.6, Diameter = 15.5, Color = color, Material = M.Neon, Transparency = 0.1, Parent = pad, Tags = { "Pulse" } })
	cylinder({ Name = "PadCenter", Position = position + Vector3.new(0, 0.5, 0), Height = 0.6, Diameter = 9, Color = rgb(40, 46, 66), Parent = pad })
	emitter(glow, {
		Texture = SPARKLE,
		Color = ColorSequence.new(color),
		Size = NumberSequence.new(0.5, 0),
		Lifetime = NumberRange.new(1, 1.6),
		Rate = 10,
		Speed = NumberRange.new(3, 6),
		EmissionDirection = Enum.NormalId.Right, -- the cylinder's X axis points up
		SpreadAngle = Vector2.new(8, 8),
		LightEmission = 1,
	})
	pointLight(glow, color, 1.5, 16)

	local gui = billboard(glow, UDim2.fromOffset(230, 92), Vector3.new(0, 7, 0), 140)
	textLabel(gui, { Text = "⚡ SELL", TextColor3 = rgb(255, 226, 92), Size = UDim2.fromScale(1, 0.62) })
	textLabel(gui, { Text = "Stand here to sell your energy", Font = Enum.Font.GothamBold, Size = UDim2.fromScale(1, 0.3), Position = UDim2.fromScale(0, 0.66), Stroke = 2 })
	return pad
end

local function eggStation(parent: Instance, zoneId: number)
	local zone = Zones[zoneId]
	local eggId = zone.Egg
	local egg = Pets.Eggs[eggId]
	local position = MapLayout.EggStation(zoneId)
	local station = model(egg.Name .. " Station", parent)

	cylinder({ Name = "Pedestal", Position = position + Vector3.new(0, 1.5, 0), Height = 3, Diameter = 14, Color = rgb(50, 56, 84), Parent = station })
	cylinder({ Name = "PedestalTrim", Position = position + Vector3.new(0, 3.05, 0), Height = 0.32, Diameter = 14.6, Color = egg.Accent, Material = M.Neon, Parent = station })
	cylinder({ Name = "PedestalTop", Position = position + Vector3.new(0, 3.35, 0), Height = 0.5, Diameter = 11, Color = rgb(236, 240, 250), Parent = station })
	for index = 0, 3 do
		local angle = math.rad(45 + index * 90)
		local postPosition = position + Vector3.new(math.cos(angle) * 9.5, 0, math.sin(angle) * 9.5)
		cylinder({ Name = "Post", Position = postPosition + Vector3.new(0, 2.5, 0), Height = 5, Diameter = 0.8, Color = rgb(50, 56, 84), Parent = station })
		ball(postPosition + Vector3.new(0, 5.4, 0), 1.3, egg.Accent, { Name = "PostLight", Material = M.Neon, Parent = station })
	end

	local eggModel = EggModels.Build(eggId, 8)
	eggModel:PivotTo(CFrame.new(position + Vector3.new(0, 8.2, 0)))
	eggModel.Parent = station
	CollectionService:AddTag(eggModel, "Spin")
	eggModel:SetAttribute("SpinSpeed", 0.5)
	eggModel:SetAttribute("BobHeight", 0.6)

	local gui = billboard(eggModel.PrimaryPart, UDim2.fromOffset(260, 104), Vector3.new(0, 7.2, 0), 120)
	textLabel(gui, { Text = "🥚 " .. egg.Name, Size = UDim2.fromScale(1, 0.48) })
	textLabel(gui, { Text = "⚡ " .. Format.Number(egg.Cost), TextColor3 = rgb(255, 222, 80), Size = UDim2.fromScale(1, 0.4), Position = UDim2.fromScale(0, 0.52) })

	local host = promptHost(station, position + Vector3.new(0, 4, 0))
	local instance = prompt(host, "Open Egg", egg.Name, 0, 16)
	instance:SetAttribute("EggId", eggId)
end

local function zoneArch(parent: Instance, x: number, title: string, color: Color3)
	local arch = model("Arch", parent)
	for _, side in { -1, 1 } do
		part({ Name = "Pillar", Size = Vector3.new(6, 28, 6), CFrame = CFrame.new(x, 14, side * 19), Color = rgb(40, 44, 66), Parent = arch })
		part({ Name = "PillarGlow", Size = Vector3.new(6.4, 26, 1), CFrame = CFrame.new(x, 14, side * 16.2), Color = color, Material = M.Neon, Parent = arch })
		ball(Vector3.new(x, 30.5, side * 19), 4, color, { Name = "PillarOrb", Material = M.Neon, Parent = arch })
	end
	part({ Name = "Beam", Size = Vector3.new(7, 6, 44), CFrame = CFrame.new(x, 31, 0), Color = rgb(40, 44, 66), Parent = arch })
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		local offset = if face == Enum.NormalId.Left then -3.6 else 3.6
		local sign = part({ Name = "Sign", Size = Vector3.new(0.4, 4.6, 36), CFrame = CFrame.new(x + offset, 31, 0), Color = rgb(24, 30, 62), Parent = arch })
		local gui = surfaceGui(sign, face, 24)
		textLabel(gui, { Text = title, Size = UDim2.fromScale(0.94, 0.8), Position = UDim2.fromScale(0.03, 0.1) })
	end
	return arch
end

local function gate(parent: Instance, zoneId: number)
	local zone = Zones[zoneId]
	local x = MapLayout.ZoneStart(zoneId)
	local gateModel = model("Gate" .. zoneId, parent)
	zoneArch(gateModel, x, zone.Icon .. " " .. string.upper(zone.Name), zone.Color)

	for _, side in { -1, 1 } do
		part({
			Name = "Barrier",
			Size = Vector3.new(1.5, 90, 104),
			CFrame = CFrame.new(x, 45, side * 70),
			Color = zone.Color,
			Material = M.ForceField,
			CanQuery = false,
			Parent = gateModel,
			Tags = { "ZoneBarrier" },
			Attributes = { Zone = zoneId },
		})
	end

	local door = part({
		Name = "Door",
		Size = Vector3.new(1.5, 28, 32),
		CFrame = CFrame.new(x, 14, 0),
		Color = zone.Color,
		Material = M.ForceField,
		CanQuery = false,
		Parent = gateModel,
		Tags = { "ZoneBarrier" },
		Attributes = { Zone = zoneId },
	})

	local gui = billboard(door, UDim2.fromOffset(300, 140), Vector3.new(-2, -2, 0), 110)
	gui.Name = "LockInfo"
	textLabel(gui, { Text = "🔒 " .. zone.Name, Size = UDim2.fromScale(1, 0.36) })
	textLabel(gui, { Text = "⚡ " .. Format.Number(zone.Cost) .. " Volts", TextColor3 = rgb(255, 222, 80), Size = UDim2.fromScale(1, 0.3), Position = UDim2.fromScale(0, 0.38) })
	textLabel(gui, { Text = "💨 Needs " .. Format.Number(zone.MinPower) .. " Power", TextColor3 = rgb(140, 220, 255), Size = UDim2.fromScale(1, 0.26), Position = UDim2.fromScale(0, 0.7) })

	local host = promptHost(gateModel, Vector3.new(x - 1.5, 4, 0))
	local instance = prompt(host, "Unlock", zone.Name .. "  •  ⚡" .. Format.Number(zone.Cost), 0.5, 16)
	instance:SetAttribute("GateZone", zoneId)
	CollectionService:AddTag(instance, "GatePrompt")
	CollectionService:AddTag(host, "ZoneBarrier")
	host:SetAttribute("Zone", zoneId)
end

---------------------------------------------------------------------------
-- Landmarks
---------------------------------------------------------------------------
local function windmill(parent: Instance, position: Vector3)
	local mill = model("Windmill", parent)
	local cream = rgb(246, 240, 228)
	part({ Name = "Base", Size = Vector3.new(10, 10, 10), CFrame = CFrame.new(position + Vector3.new(0, 5, 0)), Color = cream, Parent = mill })
	part({ Name = "Middle", Size = Vector3.new(8, 10, 8), CFrame = CFrame.new(position + Vector3.new(0, 15, 0)), Color = cream, Parent = mill })
	part({ Name = "Top", Size = Vector3.new(6.5, 8, 6.5), CFrame = CFrame.new(position + Vector3.new(0, 24, 0)), Color = cream, Parent = mill })
	local roof = CFrame.new(position + Vector3.new(0, 30.5, 0))
	wedge({ Name = "Roof", Size = Vector3.new(7.5, 5, 3.75), CFrame = roof * CFrame.new(0, 0, -1.875), Color = rgb(206, 72, 62), Parent = mill })
	wedge({ Name = "Roof", Size = Vector3.new(7.5, 5, 3.75), CFrame = roof * CFrame.new(0, 0, 1.875) * CFrame.Angles(0, math.pi, 0), Color = rgb(206, 72, 62), Parent = mill })
	part({ Name = "Door", Size = Vector3.new(3.2, 5.5, 0.3), CFrame = CFrame.new(position + Vector3.new(0, 2.75, -5.1)), Color = rgb(122, 82, 52), Parent = mill })
	part({ Name = "Window", Size = Vector3.new(2, 2, 0.3), CFrame = CFrame.new(position + Vector3.new(0, 16, -4.1)), Color = rgb(120, 190, 255), Material = M.Glass, Parent = mill })

	local hub = position + Vector3.new(0, 24, -3.8)
	local blades = model("Blades", mill)
	part({ Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 2.4, 2.4), CFrame = CFrame.new(hub) * CFrame.Angles(0, math.rad(90), 0), Color = rgb(90, 70, 60), Parent = blades })
	for index = 0, 3 do
		local spin = CFrame.new(hub) * CFrame.Angles(0, 0, index * math.pi / 2)
		part({ Name = "Arm", Size = Vector3.new(0.8, 12, 0.4), CFrame = spin * CFrame.new(0, 6.5, -0.3), Color = rgb(120, 86, 60), Material = M.Wood, Parent = blades })
		part({ Name = "Sail", Size = Vector3.new(2.6, 9, 0.2), CFrame = spin * CFrame.new(1.5, 7.5, -0.4), Color = rgb(240, 230, 205), Material = M.Fabric, Parent = blades })
	end
	blades.WorldPivot = CFrame.new(hub)
	CollectionService:AddTag(blades, "Spin")
	blades:SetAttribute("SpinAxis", "Z")
	blades:SetAttribute("SpinSpeed", 0.7)
end

local function teslaTower(parent: Instance, position: Vector3)
	local tower = model("TeslaTower", parent)
	part({ Name = "Base", Size = Vector3.new(12, 4, 12), CFrame = CFrame.new(position + Vector3.new(0, 2, 0)), Color = rgb(52, 54, 70), Material = M.DiamondPlate, Parent = tower })
	cylinder({ Name = "Column", Position = position + Vector3.new(0, 21, 0), Height = 36, Diameter = 3.4, Color = rgb(120, 124, 140), Material = M.Metal, Parent = tower })
	for index = 0, 3 do
		cylinder({ Name = "Coil", Position = position + Vector3.new(0, 10 + index * 7.5, 0), Height = 1, Diameter = 8 - index * 1.3, Color = rgb(205, 125, 60), Material = M.Metal, Parent = tower })
	end
	local orb = ball(position + Vector3.new(0, 42, 0), 7, rgb(255, 232, 90), { Name = "Orb", Material = M.Neon, Parent = tower })
	pointLight(orb, rgb(255, 230, 120), 3, 45)
	emitter(orb, {
		Texture = SPARKLE,
		Color = ColorSequence.new(rgb(255, 240, 140)),
		Size = NumberSequence.new(1.2, 0),
		Lifetime = NumberRange.new(0.15, 0.3),
		Rate = 25,
		Speed = NumberRange.new(14, 20),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 1,
	})
	CollectionService:AddTag(orb, "TeslaOrb")
end

local function lightningRod(parent: Instance, position: Vector3)
	cylinder({ Name = "RodPole", Position = position + Vector3.new(0, 7, 0), Height = 14, Diameter = 0.5, Color = rgb(150, 150, 165), Material = M.Metal, Parent = parent })
	local tip = ball(position + Vector3.new(0, 14.6, 0), 1.2, rgb(255, 232, 90), { Name = "RodTip", Material = M.Neon, Parent = parent })
	CollectionService:AddTag(tip, "Flicker")
end

local function cactus(parent: Instance, position: Vector3, scale: number)
	local plant = model("Cactus", parent)
	local green = rgb(84, 162, 80)
	cylinder({ Name = "Trunk", Position = position + Vector3.new(0, 4.5 * scale, 0), Height = 9 * scale, Diameter = 1.9 * scale, Color = green, Parent = plant })
	ball(position + Vector3.new(0, 9 * scale, 0), 1.9 * scale, green, { Name = "Top", Parent = plant })
	for _, side in { -1, 1 } do
		local height = (if side < 0 then 4 else 5.4) * scale
		part({ Name = "ArmBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.2 * scale, 1.2 * scale, 1.2 * scale), CFrame = CFrame.new(position + Vector3.new(side * 1.5 * scale, height, 0)), Color = green, Parent = plant })
		cylinder({ Name = "Arm", Position = position + Vector3.new(side * 2.5 * scale, height + 1.4 * scale, 0), Height = 2.8 * scale, Diameter = 1.2 * scale, Color = green, Parent = plant })
		ball(position + Vector3.new(side * 2.5 * scale, height + 2.8 * scale, 0), 1.2 * scale, green, { Name = "ArmTop", Parent = plant })
	end
	ball(position + Vector3.new(0, 10 * scale, 0), 0.9 * scale, rgb(255, 120, 170), { Name = "Flower", Parent = plant })
end

local function palm(parent: Instance, position: Vector3, scale: number, rng)
	local tree = model("Palm", parent)
	local lean = rng:NextNumber(-0.25, 0.25)
	for index = 0, 4 do
		cylinder({
			Name = "Trunk",
			CFrame = CFrame.new(position + Vector3.new(lean * index * 1.2 * scale, (1.3 + index * 2.4) * scale, 0)) * CFrame.Angles(0, 0, -lean * 0.4),
			Height = 2.7 * scale,
			Diameter = (1.5 - index * 0.12) * scale,
			Color = rgb(150, 110, 70),
			Material = M.Wood,
			Parent = tree,
		})
	end
	local top = position + Vector3.new(lean * 6 * scale, 12.4 * scale, 0)
	for index = 0, 5 do
		part({
			Name = "Leaf",
			Size = Vector3.new(1.7, 0.3, 7.5) * scale,
			CFrame = CFrame.new(top) * CFrame.Angles(0, index * math.pi / 3, 0) * CFrame.Angles(-0.38, 0, 0) * CFrame.new(0, 0, -3.4 * scale),
			Color = rgb(72, 164, 72),
			Parent = tree,
		})
	end
	for index = 0, 2 do
		local angle = index * 2.1
		ball(top + Vector3.new(math.cos(angle) * 0.8, -0.8, math.sin(angle) * 0.8) * scale, 0.9 * scale, rgb(110, 76, 46), { Name = "Coconut", Parent = tree })
	end
end

local function pyramid(parent: Instance, position: Vector3, size: number)
	local structure = model("Pyramid", parent)
	local layers = 9
	for index = 0, layers - 1 do
		local width = size * (1 - index / (layers + 0.5))
		part({
			Name = "Step",
			Size = Vector3.new(width, size / layers, width),
			CFrame = CFrame.new(position + Vector3.new(0, size / layers / 2 + index * size / layers, 0)),
			Color = shade(rgb(224, 182, 118), 1 - index * 0.015),
			Material = M.Sandstone,
			Parent = structure,
		})
	end
	local capstone = part({ Name = "Capstone", Size = Vector3.new(5, 5, 5), CFrame = CFrame.new(position + Vector3.new(0, size + 2.5, 0)) * CFrame.Angles(0, math.rad(45), 0), Color = rgb(255, 210, 70), Material = M.Neon, Parent = structure })
	pointLight(capstone, rgb(255, 210, 90), 2, 30)
end

local function snowman(parent: Instance, position: Vector3)
	local figure = model("Snowman", parent)
	ball(position + Vector3.new(0, 1.7, 0), 3.8, rgb(250, 252, 255), { Parent = figure })
	ball(position + Vector3.new(0, 4.4, 0), 2.8, rgb(250, 252, 255), { Parent = figure })
	ball(position + Vector3.new(0, 6.4, 0), 2, rgb(250, 252, 255), { Parent = figure })
	for _, side in { -1, 1 } do
		ball(position + Vector3.new(side * 0.35, 6.6, -0.9), 0.3, rgb(30, 30, 40), { Parent = figure })
	end
	part({ Name = "Carrot", Size = Vector3.new(0.3, 0.3, 1.2), CFrame = CFrame.new(position + Vector3.new(0, 6.3, -1.3)), Color = rgb(255, 140, 40), Parent = figure })
	cylinder({ Name = "Hat", Position = position + Vector3.new(0, 7.8, 0), Height = 1.4, Diameter = 1.4, Color = rgb(40, 40, 50), Parent = figure })
	cylinder({ Name = "HatBrim", Position = position + Vector3.new(0, 7.15, 0), Height = 0.2, Diameter = 2.2, Color = rgb(40, 40, 50), Parent = figure })
end

local function igloo(parent: Instance, position: Vector3)
	local house = model("Igloo", parent)
	ball(position, 16, rgb(244, 250, 255), { Name = "Dome", Material = M.Ice, Parent = house })
	part({ Name = "Entrance", Size = Vector3.new(5, 5, 5), CFrame = CFrame.new(position + Vector3.new(0, 2.5, -7.5)), Color = rgb(244, 250, 255), Material = M.Ice, Parent = house })
	part({ Name = "Doorway", Size = Vector3.new(3, 3.8, 0.4), CFrame = CFrame.new(position + Vector3.new(0, 1.9, -10.1)), Color = rgb(40, 60, 90), Parent = house })
end

local function iceCastle(parent: Instance, position: Vector3)
	local castle = model("IceCastle", parent)
	local ice = rgb(190, 228, 255)
	part({ Name = "Keep", Size = Vector3.new(30, 24, 22), CFrame = CFrame.new(position + Vector3.new(0, 12, 0)), Color = ice, Material = M.Ice, Parent = castle })
	for _, offset in { Vector3.new(-17, 0, -12), Vector3.new(17, 0, -12), Vector3.new(-17, 0, 12), Vector3.new(17, 0, 12) } do
		cylinder({ Name = "Tower", Position = position + offset + Vector3.new(0, 17, 0), Height = 34, Diameter = 9, Color = ice, Material = M.Ice, Parent = castle })
		for index = 0, 2 do
			cylinder({ Name = "Spire", Position = position + offset + Vector3.new(0, 35.5 + index * 2.6, 0), Height = 2.6, Diameter = 9 - index * 2.8, Color = rgb(140, 200, 255), Material = M.Glacier, Parent = castle })
		end
		ball(position + offset + Vector3.new(0, 43.5, 0), 2, rgb(160, 230, 255), { Name = "Beacon", Material = M.Neon, Parent = castle })
	end
	cylinder({ Name = "CentralTower", Position = position + Vector3.new(0, 30, 0), Height = 22, Diameter = 10, Color = ice, Material = M.Ice, Parent = castle })
	local beacon = ball(position + Vector3.new(0, 44, 0), 5, rgb(140, 230, 255), { Name = "Crown", Material = M.Neon, Parent = castle })
	pointLight(beacon, rgb(150, 220, 255), 2.5, 40)
end

local function lavaPool(parent: Instance, position: Vector3, diameter: number)
	cylinder({ Name = "PoolRim", Position = position + Vector3.new(0, 0.15, 0), Height = 0.3, Diameter = diameter + 3, Color = rgb(40, 34, 36), Material = M.Basalt, Parent = parent })
	local lava = cylinder({ Name = "Lava", Position = position + Vector3.new(0, 0.25, 0), Height = 0.3, Diameter = diameter, Color = rgb(255, 104, 30), Material = M.Neon, CanCollide = false, Parent = parent, Tags = { "Pulse" } })
	pointLight(lava, rgb(255, 120, 40), 2, diameter + 8)
	emitter(lava, {
		Texture = FIRE,
		Color = ColorSequence.new(rgb(255, 200, 80), rgb(255, 70, 20)),
		Size = NumberSequence.new(1.2, 0),
		Transparency = NumberSequence.new(0.3, 1),
		Lifetime = NumberRange.new(0.5, 0.9),
		Rate = 6,
		Speed = NumberRange.new(2, 4),
		EmissionDirection = Enum.NormalId.Right,
		SpreadAngle = Vector2.new(20, 20),
		LightEmission = 0.9,
	})
end

local function spire(parent: Instance, position: Vector3, height: number, color: Color3, rng)
	part({
		Name = "Spire",
		Size = Vector3.new(height * 0.28, height, height * 0.28),
		CFrame = CFrame.new(position + Vector3.new(0, height / 2 - 1, 0)) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), rng:NextNumber(0, 3), rng:NextNumber(-0.15, 0.15)),
		Color = color,
		Material = M.Basalt,
		Parent = parent,
	})
end

local function steamVent(parent: Instance, position: Vector3)
	local vent = part({ Name = "Vent", Size = Vector3.new(3, 1, 3), CFrame = CFrame.new(position + Vector3.new(0, 0.5, 0)), Color = rgb(60, 50, 50), Material = M.Basalt, Parent = parent })
	emitter(vent, {
		Texture = SMOKE,
		Color = ColorSequence.new(rgb(200, 190, 190)),
		Size = NumberSequence.new(2, 7),
		Transparency = NumberSequence.new(0.5, 1),
		Lifetime = NumberRange.new(2, 3),
		Rate = 4,
		Speed = NumberRange.new(5, 8),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(12, 12),
		RotSpeed = NumberRange.new(-30, 30),
	})
end

local function volcano(parent: Instance, position: Vector3)
	local layers = 20
	for index = 0, layers - 1 do
		local radius = 72 - index * 3
		terrain:FillCylinder(CFrame.new(position + Vector3.new(0, index * 3.5 + 1.75, 0)), 3.5, radius, M.Basalt)
	end
	local top = position + Vector3.new(0, layers * 3.5, 0)
	local lava = cylinder({ Name = "Crater", Position = top + Vector3.new(0, 0.4, 0), Height = 0.8, Diameter = 22, Color = rgb(255, 104, 30), Material = M.Neon, Parent = parent })
	pointLight(lava, rgb(255, 120, 40), 4, 60)
	emitter(lava, {
		Texture = SMOKE,
		Color = ColorSequence.new(rgb(70, 60, 60)),
		Size = NumberSequence.new(10, 30),
		Transparency = NumberSequence.new(0.35, 1),
		Lifetime = NumberRange.new(5, 7),
		Rate = 5,
		Speed = NumberRange.new(10, 16),
		EmissionDirection = Enum.NormalId.Right,
		SpreadAngle = Vector2.new(15, 15),
		RotSpeed = NumberRange.new(-20, 20),
	})
	emitter(lava, {
		Texture = FIRE,
		Color = ColorSequence.new(rgb(255, 210, 90), rgb(255, 60, 20)),
		Size = NumberSequence.new(8, 2),
		Transparency = NumberSequence.new(0.2, 1),
		Lifetime = NumberRange.new(1, 1.6),
		Rate = 14,
		Speed = NumberRange.new(10, 16),
		EmissionDirection = Enum.NormalId.Right,
		SpreadAngle = Vector2.new(25, 25),
		LightEmission = 0.9,
	})
end

local function floatingIsland(parent: Instance, position: Vector3, scale: number, rng, bobHeight: number?)
	local island = model("FloatingIsland", parent)
	cylinder({ Name = "Grass", Position = position, Height = 2 * scale, Diameter = 16 * scale, Color = rgb(150, 236, 200), Parent = island })
	for index, layer in { { 2.6, 14 }, { 5.4, 10 }, { 8.2, 6 }, { 10.6, 2.6 } } do
		cylinder({ Name = "Rock", Position = position - Vector3.new(0, layer[1] * scale, 0), Height = 3 * scale, Diameter = layer[2] * scale, Color = shade(rgb(110, 96, 150), 1 - index * 0.06), Material = M.Slate, Parent = island })
	end
	crystalCluster(island, position + Vector3.new(rng:NextNumber(-3, 3), 1 * scale, rng:NextNumber(-3, 3)), rgb(150, 220, 255), rng)
	island.WorldPivot = CFrame.new(position)
	CollectionService:AddTag(island, "Bob")
	island:SetAttribute("BobHeight", bobHeight or 2)
	island:SetAttribute("BobSpeed", rng:NextNumber(0.4, 0.8))
end

local function starLamp(parent: Instance, position: Vector3, color: Color3)
	cylinder({ Name = "Pole", Position = position + Vector3.new(0, 4.5, 0), Height = 9, Diameter = 0.4, Color = rgb(210, 210, 235), Material = M.Metal, Parent = parent })
	local star = ball(position + Vector3.new(0, 9.6, 0), 2, color, { Name = "Star", Material = M.Neon, Parent = parent })
	pointLight(star, color, 1.5, 18)
end

local function cloudBank(parent: Instance, position: Vector3, scale: number, rng)
	for _ = 1, 5 do
		ball(position + Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(0, 3), rng:NextNumber(-4, 4)) * scale, rng:NextNumber(5, 9) * scale, rgb(245, 242, 255), { Name = "Cloud", CanCollide = false, CastShadow = false, Parent = parent })
	end
end

local function citadel(parent: Instance, position: Vector3)
	local castle = model("SkyCitadel", parent)
	local marble = rgb(214, 206, 255)
	cylinder({ Name = "Platform", Position = position, Height = 6, Diameter = 64, Color = marble, Material = M.Marble, Parent = castle })
	for index, layer in { { 5, 50 }, { 10, 34 }, { 15, 18 } } do
		cylinder({ Name = "Underside", Position = position - Vector3.new(0, layer[1], 0), Height = 5, Diameter = layer[2], Color = shade(rgb(120, 100, 180), 1 - index * 0.08), Material = M.Slate, Parent = castle })
	end
	cylinder({ Name = "Keep", Position = position + Vector3.new(0, 25, 0), Height = 44, Diameter = 14, Color = marble, Material = M.Marble, Parent = castle })
	local crown = ball(position + Vector3.new(0, 50, 0), 9, rgb(255, 140, 240), { Name = "Crown", Material = M.Neon, Parent = castle })
	pointLight(crown, rgb(255, 150, 240), 4, 80)
	for index = 0, 3 do
		local angle = index * math.pi / 2 + math.pi / 4
		local offset = Vector3.new(math.cos(angle) * 21, 0, math.sin(angle) * 21)
		cylinder({ Name = "Tower", Position = position + offset + Vector3.new(0, 16, 0), Height = 28, Diameter = 8, Color = marble, Material = M.Marble, Parent = castle })
		ball(position + offset + Vector3.new(0, 31.5, 0), 6, rgb(150, 110, 255), { Name = "Dome", Material = M.Neon, Parent = castle })
		for level = 0, 2 do
			part({ Name = "Window", Size = Vector3.new(1.4, 2.4, 0.4), CFrame = CFrame.lookAt(position + offset + Vector3.new(0, 8 + level * 7, 0), position + Vector3.new(0, 8 + level * 7, 0)) * CFrame.new(0, 0, -4.1), Color = rgb(255, 230, 140), Material = M.Neon, Parent = castle })
		end
	end
	castle.WorldPivot = CFrame.new(position)
	CollectionService:AddTag(castle, "Bob")
	castle:SetAttribute("BobHeight", 3)
	castle:SetAttribute("BobSpeed", 0.3)
end

---------------------------------------------------------------------------
-- Zone themes
---------------------------------------------------------------------------
local function zoneAvoid(zoneId: number)
	local x0 = MapLayout.ZoneStart(zoneId)
	local sell = MapLayout.SellPad(zoneId)
	local egg = MapLayout.EggStation(zoneId)
	return {
		{ Vector3.new(x0, 0, 0), 30 },
		{ Vector3.new(x0 + 26, 0, 0), 16 },
		{ sell, 18 },
		{ sell + Vector3.new(0, 0, -22), 16 },
		{ egg, 16 },
		{ Vector3.new(MapLayout.ZoneEnd(zoneId), 0, 0), 24 },
	}
end

local Decor = {}

function Decor.Meadows(parent: Instance, zoneId: number, rng)
	local x0, x1 = regionBounds(zoneId)
	local avoid = zoneAvoid(zoneId)
	scatter(rng, x0 + 6, x1 - 6, 28, avoid, 86, 116, function(position)
		roundTree(parent, position, rng:NextNumber(0.9, 1.4), rgb(98, 188, 74))
	end)
	scatter(rng, x0 + 95, x1 - 10, 24, avoid, 14, 86, function(position)
		flowerPatch(parent, position, rng)
	end)
	scatter(rng, x0 + 6, x1 - 6, 16, avoid, 14, 112, function(position)
		bush(parent, position, rng:NextNumber(0.8, 1.3), rgb(86, 170, 66))
	end)
	scatter(rng, x0 + 6, x1 - 6, 10, avoid, 20, 112, function(position)
		rock(parent, position, rng:NextNumber(2.5, 4.5), rgb(150, 150, 158), M.Slate, rng)
	end)
	windmill(parent, Vector3.new(x0 + 210, 0, 110))
end

function Decor.Thunder(parent: Instance, zoneId: number, rng)
	local x0, x1 = regionBounds(zoneId)
	local avoid = zoneAvoid(zoneId)
	scatter(rng, x0 + 6, x1 - 6, 22, avoid, 84, 116, function(position)
		deadTree(parent, position, rng:NextNumber(1, 1.6), rgb(68, 58, 66))
	end)
	scatter(rng, x0 + 6, x1 - 6, 22, avoid, 16, 114, function(position)
		rock(parent, position, rng:NextNumber(3, 7), rgb(78, 80, 98), M.Slate, rng)
	end)
	scatter(rng, x0 + 6, x1 - 6, 12, avoid, 20, 112, function(position)
		crystalCluster(parent, position, if rng:NextNumber() < 0.5 then rgb(180, 120, 255) else rgb(255, 225, 90), rng)
	end)
	scatter(rng, x0 + 6, x1 - 6, 9, avoid, 60, 112, function(position)
		lightningRod(parent, position)
	end)
	teslaTower(parent, Vector3.new(x0 + 200, 0, -112))
end

function Decor.Dunes(parent: Instance, zoneId: number, rng)
	local x0, x1 = regionBounds(zoneId)
	local avoid = zoneAvoid(zoneId)
	scatter(rng, x0 + 6, x1 - 6, 20, avoid, 30, 114, function(position)
		cactus(parent, position, rng:NextNumber(0.8, 1.3))
	end)
	scatter(rng, x0 + 6, x1 - 6, 14, avoid, 88, 116, function(position)
		palm(parent, position, rng:NextNumber(1, 1.4), rng)
	end)
	scatter(rng, x0 + 6, x1 - 6, 16, avoid, 16, 114, function(position)
		rock(parent, position, rng:NextNumber(3, 6), rgb(210, 160, 110), M.Sandstone, rng)
	end)
	pyramid(parent, Vector3.new(x0 + 190, 0, 178), 64)
	pyramid(parent, Vector3.new(x0 + 270, 0, 196), 44)

	local oasis = Vector3.new(x0 + 140, 0, -104)
	cylinder({ Name = "Oasis", Position = oasis + Vector3.new(0, 0.15, 0), Height = 0.3, Diameter = 22, Color = rgb(80, 190, 255), Material = M.Glass, Transparency = 0.15, CanCollide = false, Parent = parent })
	for index = 0, 3 do
		local angle = index * math.pi / 2 + 0.4
		palm(parent, oasis + Vector3.new(math.cos(angle) * 13, 0, math.sin(angle) * 9), 1.2, rng)
	end
end

function Decor.Frost(parent: Instance, zoneId: number, rng)
	local x0, x1 = regionBounds(zoneId)
	local avoid = zoneAvoid(zoneId)
	scatter(rng, x0 + 6, x1 - 6, 30, avoid, 84, 116, function(position)
		pineTree(parent, position, rng:NextNumber(1, 1.6), true)
	end)
	scatter(rng, x0 + 6, x1 - 6, 12, avoid, 18, 112, function(position)
		crystalCluster(parent, position, rgb(170, 225, 255), rng, M.Ice)
	end)
	scatter(rng, x0 + 95, x1 - 10, 6, avoid, 20, 90, function(position)
		snowman(parent, position)
	end)
	igloo(parent, Vector3.new(x0 + 160, 0, 104))
	iceCastle(parent, Vector3.new(x0 + 240, 0, -150))
end

function Decor.Volcano(parent: Instance, zoneId: number, rng)
	local x0, x1 = regionBounds(zoneId)
	local avoid = zoneAvoid(zoneId)
	scatter(rng, x0 + 6, x1 - 6, 14, avoid, 18, 110, function(position)
		lavaPool(parent, position, rng:NextNumber(6, 12))
	end)
	scatter(rng, x0 + 6, x1 - 6, 22, avoid, 70, 116, function(position)
		spire(parent, position, rng:NextNumber(8, 20), rgb(52, 44, 46), rng)
	end)
	scatter(rng, x0 + 6, x1 - 6, 12, avoid, 80, 116, function(position)
		deadTree(parent, position, rng:NextNumber(1, 1.5), rgb(36, 30, 32))
	end)
	scatter(rng, x0 + 6, x1 - 6, 8, avoid, 20, 112, function(position)
		steamVent(parent, position)
	end)
	volcano(parent, Vector3.new(x0 + 220, 0, 186))
end

function Decor.Sky(parent: Instance, zoneId: number, rng)
	local x0, x1 = regionBounds(zoneId)
	local avoid = zoneAvoid(zoneId)
	scatter(rng, x0 + 6, x1 - 6, 16, avoid, 30, 112, function(position)
		local colors = { rgb(255, 230, 120), rgb(140, 220, 255), rgb(255, 150, 240) }
		starLamp(parent, position, colors[rng:NextInteger(1, #colors)])
	end)
	scatter(rng, x0 + 6, x1 - 6, 14, avoid, 18, 112, function(position)
		crystalCluster(parent, position, if rng:NextNumber() < 0.5 then rgb(190, 130, 255) else rgb(120, 230, 255), rng)
	end)
	scatter(rng, x0 + 6, x1 - 6, 14, avoid, 92, 118, function(position)
		cloudBank(parent, position, rng:NextNumber(0.8, 1.3), rng)
	end)
	for index = 1, 7 do
		local position = Vector3.new(rng:NextNumber(x0 + 20, x1 - 20), rng:NextNumber(38, 70), rng:NextNumber(-140, 140))
		floatingIsland(parent, position, rng:NextNumber(0.8, 1.5), rng, 2 + index % 3)
	end
	citadel(parent, Vector3.new(x0 + 210, 70, -190))
	ball(Vector3.new(x0 + 160, 230, -460), 130, rgb(236, 232, 255), { Name = "Moon", Material = M.Neon, CastShadow = false, CanCollide = false, Parent = parent })
	ball(Vector3.new(x0 + 40, 170, 420), 60, rgb(255, 150, 220), { Name = "Planet", Material = M.Neon, Transparency = 0.1, CastShadow = false, CanCollide = false, Parent = parent })
end

---------------------------------------------------------------------------
-- Hub: Storm Station
---------------------------------------------------------------------------
local function leaderboard(parent: Instance, position: Vector3, facing: Vector3, kind: string, title: string, accent: Color3)
	local stand = model(title, parent)
	local base = CFrame.lookAt(position, position + facing)
	for _, x in { -11.5, 11.5 } do
		part({ Name = "Post", Size = Vector3.new(1.6, 30, 1.6), CFrame = base * CFrame.new(x, 15, 0.6), Color = rgb(40, 46, 72), Parent = stand })
	end
	part({ Name = "Frame", Size = Vector3.new(22.5, 27, 0.8), CFrame = base * CFrame.new(0, 17, 0.9), Color = accent, Material = M.Neon, Parent = stand })
	local board = part({ Name = "Board", Size = Vector3.new(21, 25.5, 1), CFrame = base * CFrame.new(0, 17, 0.4), Color = rgb(20, 26, 56), Parent = stand })
	local gui = surfaceGui(board, Enum.NormalId.Front, 24)

	local header = Instance.new("Frame")
	header.BackgroundColor3 = accent
	header.Size = UDim2.new(1, -24, 0.13, 0)
	header.Position = UDim2.new(0, 12, 0, 10)
	header.Parent = gui
	corner(header, 14)
	textLabel(header, { Text = title, Size = UDim2.fromScale(0.94, 0.78), Position = UDim2.fromScale(0.03, 0.11) })

	local rows = {}
	for rank = 1, 10 do
		local row = Instance.new("Frame")
		row.Name = "Row" .. rank
		row.BackgroundColor3 = if rank % 2 == 0 then rgb(32, 40, 78) else rgb(26, 33, 66)
		row.Size = UDim2.new(1, -24, 0.074, 0)
		row.Position = UDim2.new(0, 12, 0.165 + (rank - 1) * 0.081, 0)
		row.Visible = false
		row.Parent = gui
		corner(row, 8)
		local rankColor = if rank == 1 then rgb(255, 214, 64) elseif rank == 2 then rgb(215, 222, 235) elseif rank == 3 then rgb(230, 150, 90) else WHITE
		textLabel(row, { Text = "#" .. rank, TextColor3 = rankColor, Size = UDim2.fromScale(0.14, 0.8), Position = UDim2.fromScale(0.02, 0.1) })
		local nameLabel = textLabel(row, { Text = "", TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromScale(0.54, 0.7), Position = UDim2.fromScale(0.18, 0.15) })
		local valueLabel = textLabel(row, { Text = "", TextColor3 = accent, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromScale(0.26, 0.7), Position = UDim2.fromScale(0.72, 0.15) })
		rows[rank] = { Frame = row, Name = nameLabel, Value = valueLabel }
	end

	local status = textLabel(gui, { Text = "Loading leaderboard...", Font = Enum.Font.GothamBold, TextColor3 = rgb(180, 195, 235), Size = UDim2.new(0.9, 0, 0.2, 0), Position = UDim2.fromScale(0.05, 0.45), Stroke = 2 })
	MapService.Leaderboards[kind] = { Rows = rows, Status = status }
end

local function forecastBoard(parent: Instance, position: Vector3, facing: Vector3)
	local stand = model("ForecastBoard", parent)
	local base = CFrame.lookAt(position, position + facing)
	for _, x in { -12, 12 } do
		part({ Name = "Post", Size = Vector3.new(1.6, 22, 1.6), CFrame = base * CFrame.new(x, 11, 0.8), Color = rgb(40, 46, 72), Parent = stand })
	end
	part({ Name = "Frame", Size = Vector3.new(27, 16, 0.8), CFrame = base * CFrame.new(0, 13.5, 0.9), Color = rgb(110, 200, 255), Material = M.Neon, Parent = stand })
	local screen = part({ Name = "Screen", Size = Vector3.new(26, 15, 1), CFrame = base * CFrame.new(0, 13.5, 0.4), Color = rgb(16, 22, 50), Parent = stand })
	local gui = surfaceGui(screen, Enum.NormalId.Front, 24)
	gui.Name = "ForecastGui"
	CollectionService:AddTag(gui, "ForecastGui")
	textLabel(gui, { Name = "Title", Text = "⛈️ STORM FORECAST", TextColor3 = rgb(110, 210, 255), Size = UDim2.fromScale(0.9, 0.18), Position = UDim2.fromScale(0.05, 0.05) })
	textLabel(gui, { Name = "Label", Text = "NEXT MEGA STORM", Font = Enum.Font.GothamBold, TextColor3 = rgb(180, 195, 235), Size = UDim2.fromScale(0.9, 0.1), Position = UDim2.fromScale(0.05, 0.27), Stroke = 2 })
	textLabel(gui, { Name = "Countdown", Text = "--:--", TextColor3 = rgb(255, 214, 64), Size = UDim2.fromScale(0.9, 0.28), Position = UDim2.fromScale(0.05, 0.38) })
	textLabel(gui, { Name = "StormName", Text = "Tempest Twister", Size = UDim2.fromScale(0.9, 0.13), Position = UDim2.fromScale(0.05, 0.68) })
	textLabel(gui, { Name = "Hint", Text = "Gather at the arena and vacuum it together!", Font = Enum.Font.GothamBold, TextColor3 = rgb(180, 195, 235), Size = UDim2.fromScale(0.9, 0.09), Position = UDim2.fromScale(0.05, 0.85), Stroke = 2 })
end

local function arena(parent: Instance)
	local center = MapLayout.ArenaCenter
	local radius = MapLayout.ArenaRadius
	local stage = model("MegaStormArena", parent)

	cylinder({ Name = "Rim", Position = center + Vector3.new(0, 0.35, 0), Height = 0.5, Diameter = radius * 2 + 4, Color = rgb(255, 205, 60), Material = M.Neon, Parent = stage })
	cylinder({ Name = "Floor", Position = center + Vector3.new(0, 0.5, 0), Height = 0.6, Diameter = radius * 2, Color = rgb(52, 58, 84), Material = M.Slate, Parent = stage })
	cylinder({ Name = "Ring", Position = center + Vector3.new(0, 0.62, 0), Height = 0.6, Diameter = 34, Color = rgb(120, 200, 255), Material = M.Neon, Parent = stage })
	cylinder({ Name = "Emblem", Position = center + Vector3.new(0, 0.7, 0), Height = 0.6, Diameter = 30, Color = rgb(36, 42, 66), Parent = stage })

	for index = 0, 7 do
		local angle = index * math.pi / 4
		local position = center + Vector3.new(math.cos(angle) * (radius + 5), 0, math.sin(angle) * (radius + 5))
		part({ Name = "PylonBase", Size = Vector3.new(4, 2, 4), CFrame = CFrame.new(position + Vector3.new(0, 1, 0)), Color = rgb(40, 46, 70), Parent = stage })
		part({ Name = "Pylon", Size = Vector3.new(2, 12, 2), CFrame = CFrame.new(position + Vector3.new(0, 8, 0)), Color = rgb(70, 78, 110), Material = M.Metal, Parent = stage })
		local cap = ball(position + Vector3.new(0, 15, 0), 2.8, rgb(120, 200, 255), { Name = "PylonCap", Material = M.Neon, Parent = stage, Tags = { "ArenaPylon" } })
		pointLight(cap, rgb(120, 200, 255), 1.5, 16)
	end

	local anchor = part({ Name = "SignAnchor", Size = Vector3.one, CFrame = CFrame.new(center + Vector3.new(0, 52, 0)), Transparency = 1, CanCollide = false, CanQuery = false, Parent = stage })
	local gui = billboard(anchor, UDim2.fromOffset(420, 120), Vector3.zero, 400)
	gui.Name = "ArenaGui"
	CollectionService:AddTag(gui, "ArenaGui")
	textLabel(gui, { Name = "Title", Text = "🌪️ MEGA STORM ARENA", TextColor3 = rgb(110, 210, 255), Size = UDim2.fromScale(1, 0.5) })
	textLabel(gui, { Name = "Countdown", Text = "Next storm in --:--", TextColor3 = rgb(255, 214, 64), Size = UDim2.fromScale(1, 0.4), Position = UDim2.fromScale(0, 0.55) })
end

local function rebirthShrine(parent: Instance, position: Vector3)
	local shrine = model("RebirthShrine", parent)
	local purple = rgb(170, 110, 255)
	cylinder({ Name = "Platform", Position = position + Vector3.new(0, 0.6, 0), Height = 1.2, Diameter = 24, Color = rgb(44, 40, 76), Parent = shrine })
	cylinder({ Name = "Glow", Position = position + Vector3.new(0, 0.75, 0), Height = 1.2, Diameter = 20, Color = purple, Material = M.Neon, Transparency = 0.2, Parent = shrine, Tags = { "Pulse" } })
	cylinder({ Name = "Inner", Position = position + Vector3.new(0, 0.85, 0), Height = 1.2, Diameter = 15, Color = rgb(44, 40, 76), Parent = shrine })
	for index = 0, 3 do
		local angle = index * math.pi / 2 + math.pi / 4
		local pillarPosition = position + Vector3.new(math.cos(angle) * 10, 0, math.sin(angle) * 10)
		part({ Name = "Pillar", Size = Vector3.new(1.8, 14, 1.8), CFrame = CFrame.new(pillarPosition + Vector3.new(0, 8, 0)), Color = rgb(235, 230, 255), Material = M.Marble, Parent = shrine })
		ball(pillarPosition + Vector3.new(0, 15.6, 0), 2.2, purple, { Name = "PillarOrb", Material = M.Neon, Parent = shrine })
	end
	local crystal = model("Crystal", shrine)
	local core = part({ Name = "Core", Size = Vector3.new(4, 4, 4), CFrame = CFrame.new(position + Vector3.new(0, 9, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)), Color = purple, Material = M.Neon, Parent = crystal })
	pointLight(core, purple, 3, 30)
	emitter(core, {
		Texture = SPARKLE,
		Color = ColorSequence.new(rgb(220, 180, 255)),
		Size = NumberSequence.new(1, 0),
		Lifetime = NumberRange.new(1, 1.6),
		Rate = 12,
		Speed = NumberRange.new(2, 4),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 1,
	})
	crystal.WorldPivot = CFrame.new(position + Vector3.new(0, 9, 0))
	CollectionService:AddTag(crystal, "Spin")
	crystal:SetAttribute("SpinSpeed", 1)
	crystal:SetAttribute("BobHeight", 1)

	local anchor = part({ Name = "SignAnchor", Size = Vector3.one, CFrame = CFrame.new(position + Vector3.new(0, 15, 0)), Transparency = 1, CanCollide = false, CanQuery = false, Parent = shrine })
	local gui = billboard(anchor, UDim2.fromOffset(260, 90), Vector3.new(0, 4, 0), 120)
	textLabel(gui, { Text = "🔄 REBIRTH", TextColor3 = rgb(210, 170, 255), Size = UDim2.fromScale(1, 0.6) })
	textLabel(gui, { Text = "Permanent Volts bonus", Font = Enum.Font.GothamBold, Size = UDim2.fromScale(1, 0.32), Position = UDim2.fromScale(0, 0.64), Stroke = 2 })

	local host = promptHost(shrine, position + Vector3.new(0, 3, 0))
	local instance = prompt(host, "Rebirth", "Rebirth Shrine", 0, 16)
	instance:SetAttribute("Panel", "Rebirth")
end

local function buildHub(parent: Instance)
	local hub = folder("StormStation", parent)
	local x0, x1 = MapLayout.HubStart, MapLayout.HubEnd
	local centerX = (x0 + x1) / 2

	part({ Name = "Plaza", Size = Vector3.new(x1 - x0 - 4, 0.4, 212), CFrame = CFrame.new(centerX, 0, 0), Color = rgb(206, 212, 226), Material = M.Concrete, Parent = hub })
	part({ Name = "Walkway", Size = Vector3.new(x1 - x0 - 4, 0.44, 18), CFrame = CFrame.new(centerX, 0.02, 0), Color = rgb(74, 86, 128), Parent = hub })
	for _, z in { -9.5, 9.5 } do
		part({ Name = "WalkwayGlow", Size = Vector3.new(x1 - x0 - 4, 0.46, 0.8), CFrame = CFrame.new(centerX, 0.03, z), Color = rgb(110, 210, 255), Material = M.Neon, Parent = hub })
	end
	for _, z in { -80, 80 } do
		part({ Name = "StationRow", Size = Vector3.new(x1 - x0 - 30, 0.44, 40), CFrame = CFrame.new(centerX, 0.02, z), Color = rgb(190, 198, 216), Material = M.Concrete, Parent = hub })
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.lookAt(MapLayout.Spawn + Vector3.new(0, 0.5, 0), MapLayout.Spawn + Vector3.new(10, 0.5, 0))
	spawn.Color = rgb(60, 70, 110)
	spawn.Material = M.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = hub
	cylinder({ Name = "SpawnRing", Position = MapLayout.Spawn + Vector3.new(0, 0.55, 0), Height = 1.02, Diameter = 12, Color = rgb(110, 210, 255), Material = M.Neon, Transparency = 0.3, CanCollide = false, Parent = hub })

	-- Welcome arch over the walkway
	zoneArch(hub, -172, "⛈️ STORM CATCHER SIMULATOR", rgb(110, 210, 255))

	arena(hub)

	local stations = MapLayout.HubStations
	kiosk(hub, stations.Upgrades, Vector3.zAxis, "Upgrade Workshop", "⬆️", rgb(70, 160, 255), "Upgrades")
	kiosk(hub, stations.Shop, Vector3.zAxis, "Storm Shop", "🛒", rgb(255, 170, 60), "Shop")
	kiosk(hub, stations.WeatherLab, Vector3.zAxis, "Weather Lab", "⚡", rgb(255, 205, 60), nil)
	sellPad(hub, MapLayout.HubSellPad, rgb(255, 214, 64))
	rebirthShrine(hub, stations.Rebirth)
	kiosk(hub, stations.Rewards, -Vector3.zAxis, "Daily Rewards", "🎁", rgb(255, 110, 170), "Rewards")
	forecastBoard(hub, stations.Forecast, -Vector3.zAxis)

	leaderboard(hub, MapLayout.Leaderboards.Volts, Vector3.zAxis, "Volts", "🏆 TOP STORM CATCHERS", rgb(255, 205, 60))
	leaderboard(hub, MapLayout.Leaderboards.Rebirths, -Vector3.zAxis, "Rebirths", "🔄 MOST REBIRTHS", rgb(180, 120, 255))

	for x = -206, -10, 28 do
		if x < -164 or x > -60 then
			lamp(hub, Vector3.new(x, 0, -14))
			lamp(hub, Vector3.new(x, 0, 14))
		end
	end

	local rng = Random.new(77)
	for _, position in {
		Vector3.new(-206, 0, -104), Vector3.new(-206, 0, 104), Vector3.new(-14, 0, -104), Vector3.new(-14, 0, 104),
		Vector3.new(-132, 0, -104), Vector3.new(-132, 0, 104), Vector3.new(-76, 0, -104), Vector3.new(-76, 0, 104),
	} do
		cylinder({ Name = "Planter", Position = position + Vector3.new(0, 1, 0), Height = 2, Diameter = 9, Color = rgb(150, 110, 80), Material = M.Brick, Parent = hub })
		roundTree(hub, position + Vector3.new(0, 2, 0), rng:NextNumber(0.9, 1.15), rgb(100, 192, 78))
	end
	for _, position in { Vector3.new(-200, 0, -22), Vector3.new(-200, 0, 22) } do
		bush(hub, position, 1, rgb(90, 176, 70))
	end
end

---------------------------------------------------------------------------
-- Zones
---------------------------------------------------------------------------
local function buildZone(parent: Instance, zoneId: number)
	local zone = Zones[zoneId]
	local zoneFolder = folder(zone.Key, parent)
	local x0 = MapLayout.ZoneStart(zoneId)

	if zoneId == 1 then
		zoneArch(zoneFolder, x0, zone.Icon .. " " .. string.upper(zone.Name), zone.Color)
	else
		gate(zoneFolder, zoneId)
	end

	local sell = MapLayout.SellPad(zoneId)
	kiosk(zoneFolder, sell + Vector3.new(0, 0, -22), Vector3.zAxis, "Weather Lab", "⚡", zone.Color, nil)
	sellPad(zoneFolder, sell, rgb(255, 214, 64))
	eggStation(zoneFolder, zoneId)

	for x = x0 + 40, x0 + 90, 25 do
		lamp(zoneFolder, Vector3.new(x, 0, -12), zone.Accent)
		lamp(zoneFolder, Vector3.new(x, 0, 12), zone.Accent)
	end

	local decorFolder = folder("Decor", zoneFolder)
	local decorator = Decor[zone.Key]
	if decorator then
		decorator(decorFolder, zoneId, Random.new(zoneId * 1000 + 7))
	end
end

---------------------------------------------------------------------------
-- Lighting
---------------------------------------------------------------------------
local function ensure(className: string, parent: Instance)
	local existing = parent:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local instance = Instance.new(className)
	instance.Parent = parent
	return instance
end

local function buildLighting()
	local preset = Zones.Hub.Lighting
	Lighting.ClockTime = preset.ClockTime
	Lighting.Brightness = preset.Brightness
	Lighting.ExposureCompensation = preset.ExposureCompensation
	Lighting.Ambient = preset.Ambient
	Lighting.OutdoorAmbient = preset.OutdoorAmbient
	Lighting.GlobalShadows = true

	local atmosphere = ensure("Atmosphere", Lighting)
	for key, value in preset.Atmosphere do
		atmosphere[key] = value
	end
	local colorCorrection = ensure("ColorCorrectionEffect", Lighting)
	for key, value in preset.ColorCorrection do
		colorCorrection[key] = value
	end
	local bloom = ensure("BloomEffect", Lighting)
	for key, value in preset.Bloom do
		bloom[key] = value
	end
	local sunRays = ensure("SunRaysEffect", Lighting)
	sunRays.Intensity = 0.04
	sunRays.Spread = 0.6
end

---------------------------------------------------------------------------
function MapService.Init()
	local existing = Workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	local map = folder("Map", Workspace)
	buildLighting()
	buildTerrain()
	buildBoundaries(map)
	buildHub(map)
	for zoneId = 1, #Zones do
		buildZone(map, zoneId)
	end
end

return MapService
