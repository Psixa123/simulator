--!nonstrict
-- Builds the whole world when the server starts: the "Sky Lab" sky islands of docs/STYLE_GUIDE.md
-- ("World"). The Storm Station hub and the six zones are the flat tops of giant floating islands in a
-- sea of cartoon clouds: per-region ground in the biome colour, raised weather fields with white dashed
-- borders, a paver path along the island, layered cliffs beyond the side boundaries, dense biome
-- decoration, the hub's stations, and every zone's gate, sell pad and egg incubator.
--
-- No Roblox Terrain: everything is SmoothPlastic parts plus the SketchUp prop pack (WorldProps.Place,
-- tools/world/PROPS.md). Whenever a prop isn't in the pack (it's still being modelled, or the place has
-- no pack yet), MapService builds a part-built stand-in with the same origin, front, size and paints, so
-- the world looks right either way.
--
-- Gameplay contracts (other code relies on these names, tags, attributes and positions):
--   Workspace.Map > Boundaries, StormStation, <Zone.Key> folders; SpawnLocation "Spawn" at MapLayout.Spawn
--   SellPad models at MapLayout.SellPad (PadGlow tagged "Pulse"); egg stations at MapLayout.EggStation with
--   a PromptHost > ProximityPrompt (EggId) and the egg model (tag "Spin"); hub prompts with a Panel
--   attribute; gates: Barrier/Door parts and the PromptHost tagged "ZoneBarrier" (Zone attribute), the
--   prompt tagged "GatePrompt" (GateZone attribute; the client draws it as the zone card); the forecast SurfaceGui
--   tagged "ForecastGui", the arena BillboardGui tagged "ArenaGui", pylon caps tagged "ArenaPylon";
--   Ashfall Volcano CoolingArea models at Hazards.CoolingSpots; MapService.Leaderboards[kind].
-- The ground is at y = -0.5 and the weather fields' tops at y = 0 (lightning warnings are drawn at y = 0).
-- tests/mock/MapContracts.luau checks these contracts, that spawns, sell pads, the main path and the fields
-- stay clear, that every gate seals the width, and the 12,000-part budget (with and without the prop pack).

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapLayout = require(Shared.Config.MapLayout)
local Zones = require(Shared.Config.Zones)
local Pets = require(Shared.Config.Pets)
local Format = require(Shared.Util.Format)
local Hazards = require(Shared.Hazards)
local EggModels = require(Shared.Models.EggModels)
local PetModels = require(Shared.Models.PetModels) -- the lobby shop pet on its stand
local Monetization = require(Shared.Config.Monetization) -- the lobby shop pet's product (price on its sign)
local WorldProps = require(script.Parent.WorldProps)

local MapService = {}
MapService.Leaderboards = {} -- [kind] = { Rows = { { Frame, Name, Value } }, Status = TextLabel }
-- What the last build placed: pack props, part-built stand-ins (by prop id) and the map's part count
MapService.Stats = { Props = 0, Built = 0, Missing = {}, Parts = 0 }

local M = Enum.Material
local SMOOTH = M.SmoothPlastic
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

---------------------------------------------------------------------------
-- Layout constants
---------------------------------------------------------------------------
local GROUND_Y = -0.5 -- top of the island ground
local FIELD_Y = 0 -- top of the raised weather fields
local SLAB = 8 -- thickness of the ground slabs
local EDGE = 150 -- the island's half width (the playable strip is MapLayout.HalfWidth either side of z = 0)
local WEST_END = MapLayout.HubStart - 50 -- the hub island reaches past its boundary (the Weather Tower stands there)
local EAST_END = MapLayout.WorldEnd + 30
local PATH_HALF = 8 -- the main path is 16 studs wide
local FIELD_GAP = 10 -- the field pads start this far from the middle of the path
local PAVER = 8 -- paver spacing along the path

---------------------------------------------------------------------------
-- Palette (docs/STYLE_GUIDE.md) and biomes
---------------------------------------------------------------------------
local function hex(code: string): Color3
	return Color3.fromHex(code)
end

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function shade(color: Color3, amount: number): Color3
	return Color3.new(math.clamp(color.R * amount, 0, 1), math.clamp(color.G * amount, 0, 1), math.clamp(color.B * amount, 0, 1))
end

local WHITE = Color3.new(1, 1, 1)
local INK = hex("233066")
local INK_SOFT = hex("5B6A9E")
local BODY = hex("EEF0FF") -- toy building bodies
local SKY = hex("5CC8FF")
local SKY_DEEP = hex("2F86F2")
local BOLT = hex("FFE15A")
local BOLT_DEEP = hex("FFAA1F")
local STORM = hex("A98BFF")
local STORM_DEEP = hex("6B4BE6")
local LEAF = hex("7BE36A")
local CORAL = hex("FF7A85")
local SUNSET = hex("FFB15C")

-- Leaf paints (Primary, Secondary) for round / tall trees and bushes
local LIME = { Primary = hex("5FD35A"), Secondary = hex("A8F08C") }
local PINK = { Primary = hex("FF8FC8"), Secondary = hex("FFC4E1") }
local LILAC = { Primary = hex("B69CFF"), Secondary = hex("DCCEFF") }
local GREEN = { Primary = hex("45C25A"), Secondary = hex("8FE36F") }

-- Per region (0 = hub): ground and field colours, path pavers, the cliff lip and rock bands, and the
-- paints of the props that repeat across biomes
local BIOMES = {
	[0] = {
		Ground = hex("C9D0F7"),
		Field = hex("DDE2FB"),
		Hills = { hex("B9C1F2"), hex("DDE2FB") },
		Pavers = { hex("F7F8FF"), hex("E9ECFC") },
		Lip = hex("C9D0F7"),
		Rock = hex("A99CE3"),
		Band = hex("8C7FD0"),
		Trees = { LIME, PINK, LILAC },
		Bush = GREEN,
		Stone = { Primary = hex("AFB3E4"), Secondary = hex("D2D5F6") },
		Cloud = hex("DCE4FA"),
		Lamp = { Primary = hex("4E5BC6"), Secondary = BOLT },
	},
	[1] = {
		Ground = hex("6EE05A"),
		Field = hex("8BEA5E"),
		Hills = { hex("5FD35A"), hex("8BEA5E") },
		Pavers = { hex("F6F4EA"), hex("E9E6D8") },
		Lip = hex("6EE05A"),
		Rock = hex("D99A62"),
		Band = hex("B8754A"),
		Trees = { PINK, LIME, LILAC },
		Bush = GREEN,
		Stone = { Primary = hex("A9AFC9"), Secondary = hex("CDD1E6") },
		Cloud = hex("DCE6FA"),
		Lamp = { Primary = hex("4E5BC6"), Secondary = BOLT },
	},
	[2] = {
		Ground = hex("7C74E8"),
		Field = hex("9A92F5"),
		Hills = { hex("6A62D8"), hex("9A92F5") },
		Pavers = { hex("DAD6FF"), hex("C8C2FA") },
		Lip = hex("7C74E8"),
		Rock = hex("5A53B8"),
		Band = hex("443C98"),
		Trees = {
			{ Primary = hex("4FA3FF"), Secondary = hex("A6D8FF") },
			{ Primary = hex("37C5E6"), Secondary = hex("A4F0FF") },
			{ Primary = hex("9B7CFF"), Secondary = hex("D2C4FF") },
		},
		Bush = { Primary = hex("4A8CFF"), Secondary = hex("8CC4FF") },
		Stone = { Primary = hex("5D58B2"), Secondary = hex("7F7ACF") },
		Cloud = hex("CFCBF5"),
		Lamp = { Primary = hex("3A3696"), Secondary = BOLT },
	},
	[3] = {
		Ground = hex("FFD27A"),
		Field = hex("FFE19A"),
		Hills = { hex("FFC45C"), hex("FFE19A") },
		Pavers = { hex("FFF5DE"), hex("FBE8C2") },
		Lip = hex("FFD27A"),
		Rock = hex("F0A85E"),
		Band = hex("D9854A"),
		Trees = { { Primary = hex("3FBF6A"), Secondary = hex("7BE36A") } },
		Bush = { Primary = hex("8CCB5E"), Secondary = hex("B8E07A") },
		Stone = { Primary = hex("EFA35C"), Secondary = hex("F7C489") },
		Cloud = hex("FBE9D6"),
		Lamp = { Primary = hex("2FA6A0"), Secondary = BOLT },
	},
	[4] = {
		Ground = hex("EAF6FF"),
		Field = hex("D6EEFF"),
		Hills = { hex("FFFFFF"), hex("D6EEFF") },
		Pavers = { hex("C5DCF4"), hex("B5D0EE") },
		Lip = hex("F4FAFF"),
		Rock = hex("9CC8F0"),
		Band = hex("78A9DE"),
		Trees = {
			{ Primary = hex("2E9E6E"), Secondary = hex("57C08A"), Tertiary = WHITE },
			{ Primary = hex("3BAE8C"), Secondary = hex("6CCFA6"), Tertiary = WHITE },
		},
		Bush = { Primary = hex("BFE3FF"), Secondary = WHITE },
		Stone = { Primary = hex("A6CFF0"), Secondary = hex("D3EBFF") },
		Cloud = hex("E3EEFB"),
		Lamp = { Primary = hex("3F6FC2"), Secondary = hex("9EE8FF") },
	},
	[5] = {
		Ground = hex("8A5A4E"),
		Field = hex("B5705A"),
		Hills = { hex("74463C"), hex("A0634F") },
		Pavers = { hex("E8C9B6"), hex("D9B39C") },
		Lip = hex("8A5A4E"),
		Rock = hex("6A3F37"),
		Band = hex("4E2C29"),
		Trees = { { Primary = hex("FF8A3D"), Secondary = hex("FFB15C") } },
		Bush = { Primary = hex("A35A3F"), Secondary = hex("C9764F") },
		Stone = { Primary = hex("5A3A36"), Secondary = hex("7C4E45") },
		Cloud = hex("F5D9D0"),
		Lamp = { Primary = hex("4A2C2A"), Secondary = hex("FF8A3D") },
	},
	[6] = {
		Ground = hex("C9B8FF"),
		Field = hex("E2D8FF"),
		Hills = { hex("B6A0FF"), hex("E2D8FF") },
		Pavers = { hex("F7F3FF"), hex("EAE2FF") },
		Lip = hex("C9B8FF"),
		Rock = hex("9F86E8"),
		Band = hex("7E64CF"),
		Trees = {
			{ Primary = hex("FF8FD0"), Secondary = hex("FFD1EC") },
			{ Primary = hex("6FDDC2"), Secondary = hex("C8F7EA") },
			{ Primary = hex("6FC4FF"), Secondary = hex("CDEBFF") },
			{ Primary = hex("8E6CF0"), Secondary = hex("CBB8FF") },
		},
		Bush = { Primary = hex("8E6CF0"), Secondary = hex("CBB8FF") },
		Stone = { Primary = hex("9F8BE0"), Secondary = hex("C3B5F2") },
		Cloud = hex("EADFFF"),
		Lamp = { Primary = hex("7E64CF"), Secondary = BOLT },
	},
}

---------------------------------------------------------------------------
-- Instance helpers
---------------------------------------------------------------------------
local function part(props, className: string?)
	local instance = Instance.new(className or "Part")
	instance.Anchored = true
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	instance.Material = SMOOTH
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

-- Walk-through decoration: no collision, queries, touches or shadow unless asked
local function deco(props)
	for key, value in { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false } do
		if props[key] == nil then
			props[key] = value
		end
	end
	return part(props)
end

-- Vertical cylinder: props.Position (centre) or props.CFrame, props.Height, props.Diameter
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

local function outline(parent: Instance, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

-- White Fredoka text with an Ink stroke (STYLE_GUIDE: text over the world)
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
		stroke.Color = INK
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

-- A sign: an invisible board carrying a rounded colour plate (Ink outline) with big white Fredoka text
-- on the given faces. `cframe` is the board's centre; its Front face looks along the cframe's -Z (a board
-- `depth` thick can wrap around something, with plates on its Front and Back faces).
local function signBoard(parent: Instance, name: string, cframe: CFrame, width: number, height: number, text: string, color: Color3, faces, pixels: number?, depth: number?)
	local board = deco({ Name = name, Size = Vector3.new(width, height, depth or 0.3), CFrame = cframe, Transparency = 1, Parent = parent })
	for _, face in faces or { Enum.NormalId.Front } do
		local gui = surfaceGui(board, face, pixels or 24)
		local plate = Instance.new("Frame")
		plate.Name = "Plate"
		plate.BackgroundColor3 = color
		plate.Size = UDim2.new(1, -8, 1, -8)
		plate.Position = UDim2.fromOffset(4, 4)
		plate.Parent = gui
		corner(plate, math.floor(height * (pixels or 24) * 0.3))
		outline(plate, INK, 4)
		textLabel(plate, { Name = "Text", Text = text, Size = UDim2.fromScale(0.92, 0.74), Position = UDim2.fromScale(0.04, 0.13), Stroke = 3 })
	end
	return board
end

-- Rotation whose -Z (a prop's front) points along (dx, 0, dz)
local function facing(dx: number, dz: number): CFrame
	return CFrame.Angles(0, math.atan2(-dx, -dz), 0)
end

---------------------------------------------------------------------------
-- The prop kit: WorldProps.Place, or a part-built stand-in
---------------------------------------------------------------------------
-- Stand-ins share the pack's conventions (origin at the centre of the base, front -Z, studs) and paint
-- names, so a stand-in and the real prop are placed and coloured the same way. Each piece is named
-- "<PropId>.<Paint>" like the pack's MeshParts, so effects can find e.g. the Neon piece of either.
local GLASS_TRANSPARENCY = 0.35
local ROLL = CFrame.Angles(0, 0, math.rad(90)) -- turns a Cylinder part's axis (X) to Y

local function resolvePaint(paint: string, paints)
	local custom = paints and paints[paint]
	local kind, code = string.match(paint, "^(%a+)_(%x%x%x%x%x%x)$")
	if kind == "Neon" then
		return custom or hex(code), M.Neon, 0
	elseif kind == "Glass" then
		return custom or hex(code), M.Glass, GLASS_TRANSPARENCY
	elseif kind == "Color" then
		return custom or hex(code), SMOOTH, 0
	end
	return custom or rgb(200, 200, 210), SMOOTH, 0
end

-- Part builder for one stand-in: offsets and sizes in the prop's own studs, scaled by `scale`
-- (a number, or a Vector3 for boxes; balls and round sections use the mean scale)
local function kit(target: Model, id: string, origin: CFrame, scale, solid: boolean, shadow: boolean, paints)
	local v = if typeof(scale) == "Vector3" then scale else Vector3.one * scale
	local s = (v.X + v.Y + v.Z) / 3
	-- Seed: a stable 0..1 number per placement, for stand-ins that vary a little from copy to copy
	local p = origin.Position
	local k = { Paints = paints, S = s, V = v, Seed = math.abs(math.sin(p.X * 12.9898 + p.Z * 78.233 + p.Y * 3.71) * 43758.5453) % 1 }

	local function make(shape, paint: string, size: Vector3, frame: CFrame): BasePart
		local color, material, transparency = resolvePaint(paint, paints)
		local piece = Instance.new("Part")
		piece.Name = id .. "." .. paint
		piece.Anchored = true
		piece.Shape = shape
		piece.TopSurface = Enum.SurfaceType.Smooth
		piece.BottomSurface = Enum.SurfaceType.Smooth
		piece.Material = material
		piece.Color = color
		piece.Transparency = transparency
		piece.Size = size
		piece.CFrame = frame
		local collide = solid and material == SMOOTH
		piece.CanCollide = collide
		piece.CanQuery = collide
		piece.CanTouch = false
		piece.CastShadow = shadow and transparency == 0
		piece.Parent = target
		return piece
	end
	local function at(offset: Vector3, rotation: CFrame?): CFrame
		return origin * CFrame.new(offset * v) * (rotation or CFrame.identity)
	end

	function k.box(paint: string, offset: Vector3, size: Vector3, rotation: CFrame?)
		return make(Enum.PartType.Block, paint, size * v, at(offset, rotation))
	end
	function k.ball(paint: string, offset: Vector3, diameter: number)
		return make(Enum.PartType.Ball, paint, Vector3.one * diameter * s, at(offset))
	end
	-- upright cylinder (its axis along the prop's Y, or the rotated Y)
	function k.cyl(paint: string, offset: Vector3, height: number, diameter: number, rotation: CFrame?)
		return make(Enum.PartType.Cylinder, paint, Vector3.new(height * v.Y, diameter * s, diameter * s), at(offset, rotation) * ROLL)
	end
	-- cylinder along the prop's X (or the rotated X)
	function k.rod(paint: string, offset: Vector3, length: number, diameter: number, rotation: CFrame?)
		return make(Enum.PartType.Cylinder, paint, Vector3.new(length * s, diameter * s, diameter * s), at(offset, rotation))
	end
	-- a slab along X with a rounded (bullnose) front: a box `depth` deep reaching back (+Z) from the front
	-- face at offset.Z, and a rod as tall as the slab along its front edge
	function k.ledge(paint: string, offset: Vector3, length: number, height: number, depth: number)
		local h = height * v.Y
		make(Enum.PartType.Block, paint, Vector3.new(length * v.X, h, (depth - height / 2) * v.Z), at(offset + Vector3.new(0, 0, (depth + height / 2) / 2)))
		return make(Enum.PartType.Cylinder, paint, Vector3.new(length * v.X, h, h), at(offset + Vector3.new(0, 0, height / 2)))
	end
	-- a box with rounded vertical edges (two crossed boxes and four corner cylinders)
	function k.rbox(paint: string, offset: Vector3, size: Vector3, radius: number)
		local r = radius
		k.box(paint, offset, size - Vector3.new(r * 2, 0, 0))
		k.box(paint, offset, size - Vector3.new(0, 0, r * 2))
		for _, x in { -1, 1 } do
			for _, z in { -1, 1 } do
				k.cyl(paint, offset + Vector3.new(x * (size.X / 2 - r), 0, z * (size.Z / 2 - r)), size.Y, r * 2)
			end
		end
	end
	return k
end

local FALLBACK = {} -- [PropId] = { Size = largest dimension, Solid = bool, Paints = defaults, Build = (k) -> () }
local function fallback(id: string, info, build)
	info.Build = build
	FALLBACK[id] = info
end

local function v3(x, y, z)
	return Vector3.new(x, y, z)
end

-- nature ------------------------------------------------------------------
fallback("TreeRound", { Size = 14, Paints = GREEN }, function(k)
	k.cyl("Color_A8724C", v3(0, 3.5, 0), 7, 1.8)
	k.ball("Primary", v3(0, 9.4, 0), 9)
	k.ball("Primary", v3(2.7, 8.2, 1.3), 6.2)
	k.ball("Secondary", v3(-2.1, 11.2, -1.4), 5.4)
end)

fallback("TreeTall", { Size = 18, Paints = PINK }, function(k)
	k.cyl("Color_A8724C", v3(0, 4.5, 0), 9, 1.3)
	k.ball("Primary", v3(0, 8.8, 0), 8.4)
	k.ball("Secondary", v3(0.3, 12.6, -0.2), 6.8)
	k.ball("Primary", v3(-0.2, 15.6, 0.1), 4.8)
end)

fallback("TreePine", { Size = 17, Paints = { Primary = hex("2E9E6E"), Secondary = hex("57C08A"), Tertiary = hex("2E9E6E") } }, function(k)
	k.cyl("Color_8A5A3C", v3(0, 1.6, 0), 3.2, 1.6)
	k.cyl("Primary", v3(0, 4.8, 0), 3.6, 9)
	k.cyl("Primary", v3(0, 8.2, 0), 3.4, 6.8)
	k.cyl("Primary", v3(0, 11.3, 0), 3, 4.4)
	k.ball("Tertiary", v3(0, 13.6, 0), 2.8)
	local paints = k.Paints
	if paints.Tertiary and paints.Tertiary ~= paints.Primary then
		k.cyl("Tertiary", v3(0, 6.75, 0), 0.5, 7.4)
		k.cyl("Tertiary", v3(0, 10.05, 0), 0.5, 5.4)
	end
end)

fallback("TreePalm", { Size = 16, Paints = { Primary = hex("3FBF6A") } }, function(k)
	k.cyl("Color_C8925A", v3(0.3, 2.3, 0), 4.6, 1.6, CFrame.Angles(0, 0, -0.12))
	k.cyl("Color_C8925A", v3(1.1, 6.5, 0), 4.4, 1.35, CFrame.Angles(0, 0, -0.22))
	k.cyl("Color_C8925A", v3(2.2, 10.5, 0), 4, 1.15, CFrame.Angles(0, 0, -0.32))
	local crown = v3(3, 12.6, 0)
	for index = 0, 4 do
		local yaw = index * math.pi * 2 / 5 + 0.3
		local offset = crown + v3(math.sin(yaw) * 3.1, -0.7, math.cos(yaw) * 3.1)
		k.box("Primary", offset, v3(1.8, 0.5, 6.4), CFrame.Angles(0, yaw, 0) * CFrame.Angles(0.32, 0, 0))
	end
	k.ball("Color_7A4E2E", crown + v3(0, -1, 0), 1.6)
end)

fallback("BushRound", { Size = 6, Paints = GREEN }, function(k)
	k.ball("Primary", v3(0, 1.3, 0), 4)
	k.ball("Primary", v3(1.9, 1.0, 0.5), 3.1)
	k.ball("Secondary", v3(-1.5, 1.3, -0.6), 2.7)
end)

fallback("FlowerPatch", { Size = 6, Paints = { Primary = hex("5FD35A"), Secondary = hex("FF7AA8"), Tertiary = WHITE } }, function(k)
	k.cyl("Primary", v3(0, 0.25, 0), 0.9, 5.6)
	k.ball("Secondary", v3(1.4, 1.1, 1.1), 1.5)
	k.ball("Tertiary", v3(-1.5, 1.1, 0.8), 1.5)
	k.ball("Secondary", v3(-0.6, 1.2, -1.5), 1.5)
	k.ball("Color_FFE15A", v3(1.2, 1.1, -1.2), 1.2)
end)

fallback("Mushroom", { Size = 6, Paints = { Primary = hex("FF5A6E") } }, function(k)
	k.cyl("Color_FFF4E0", v3(0, 1.8, 0), 3.6, 1.4)
	k.ball("Primary", v3(0, 4.3, 0), 4.6)
	k.ball("Color_FFFFFF", v3(-0.9, 5.7, -1.2), 1)
	k.cyl("Color_FFF4E0", v3(1.9, 0.8, -0.9), 1.6, 0.8)
	k.ball("Primary", v3(1.9, 2.0, -0.9), 2.2)
end)

fallback("RockCluster", { Size = 9, Solid = true, Paints = { Primary = hex("A9AFC9"), Secondary = hex("CDD1E6") } }, function(k)
	k.ball("Primary", v3(-0.8, 0.6, 0), 5.8)
	k.ball("Secondary", v3(2.6, 0.2, 0.9), 3.8)
	k.ball("Primary", v3(-3.6, 0, -1.2), 2.8)
end)

fallback("RockTall", { Size = 10, Solid = true, Paints = { Primary = hex("A9AFC9"), Secondary = hex("CDD1E6") } }, function(k)
	k.ball("Primary", v3(0, 2, 0), 6.2)
	k.ball("Secondary", v3(0.3, 5.7, 0.2), 4.8)
	k.ball("Primary", v3(-0.2, 8.5, 0), 3.4)
end)

fallback("CrystalCluster", { Size = 8, Paints = { Primary = hex("7B5CF0"), Secondary = hex("A9A3D9") } }, function(k)
	k.ball("Secondary", v3(0, 0, 0), 4.4)
	k.box("Primary", v3(0, 3.6, 0), v3(1.7, 6.2, 1.7), CFrame.Angles(0, math.rad(45), 0.08))
	k.box("Primary", v3(1.7, 2.4, 0.6), v3(1.3, 4.2, 1.3), CFrame.Angles(0.2, 0.3, -0.45))
	k.box("Primary", v3(-1.6, 2.1, -0.5), v3(1.2, 3.6, 1.2), CFrame.Angles(-0.2, 0.6, 0.5))
end)

fallback("Fence", { Size = 10, Paints = { Primary = hex("FFF6E6"), Secondary = hex("8CCBFF") } }, function(k)
	for _, x in { -4.6, 4.6 } do
		k.cyl("Primary", v3(x, 2.1, 0), 4.2, 0.9)
	end
	k.box("Secondary", v3(0, 1.4, 0), v3(9.2, 0.5, 0.35))
	k.box("Secondary", v3(0, 3.0, 0), v3(9.2, 0.5, 0.35))
	for _, x in { -2.8, -0.9, 0.9, 2.8 } do
		k.box("Primary", v3(x, 2.0, -0.25), v3(1, 3.4, 0.3))
	end
end)

fallback("GrassTuft", { Size = 2, Paints = { Primary = hex("5FD35A") } }, function()
	-- too small to be worth parts: the stand-in is left empty
end)

fallback("LampPost", { Size = 10, Paints = { Primary = hex("4E5BC6"), Secondary = BOLT } }, function(k)
	k.cyl("Primary", v3(0, 0.4, 0), 0.8, 2.2)
	k.cyl("Primary", v3(0, 4.7, 0), 8.6, 0.7)
	k.box("Primary", v3(-1.25, 9.1, 0), v3(2.8, 0.6, 0.6))
	k.cyl("Secondary", v3(-2.6, 8.9, 0), 0.6, 2.2)
	k.ball("Neon_FFF3B0", v3(-2.6, 8.3, 0), 1.6)
end)

-- landmarks -----------------------------------------------------------------
fallback("Windmill", { Size = 30, Solid = true, Paints = { Primary = hex("FF6F7E"), Secondary = hex("FFB15C") } }, function(k)
	k.cyl("Color_FFF4E0", v3(0, 6, 0), 12, 12)
	k.cyl("Secondary", v3(0, 12, 0), 1, 12.6)
	k.cyl("Color_FFF4E0", v3(0, 16.5, 0), 9, 10)
	k.cyl("Primary", v3(0, 21.6, 0), 1.4, 12)
	k.ball("Primary", v3(0, 24.2, 0), 10)
	k.ball("Secondary", v3(0, 29.4, 0), 2)
	k.box("Secondary", v3(0, 2.8, -5.8), v3(3.4, 5.6, 0.8))
	k.ball("Color_8FD3FF", v3(0, 15.5, -4.4), 2.4)
end)

fallback("WindmillBlades", { Size = 22, Paints = { Primary = hex("FFF6E6"), Secondary = hex("FF6F7E") } }, function(k)
	k.rod("Secondary", v3(0, 0, 0), 2, 2.6, CFrame.Angles(0, math.rad(90), 0))
	for index = 0, 3 do
		local angle = index * math.pi / 2 + math.pi / 4
		k.box("Primary", v3(math.sin(angle) * 6.2, math.cos(angle) * 6.2, -0.4), v3(2.8, 9, 0.4), CFrame.Angles(0, 0, -angle))
	end
end)

fallback("HayBale", { Size = 5, Paints = {} }, function(k)
	k.rod("Color_F2C94C", v3(0, 2, 0), 5, 4)
	k.rod("Color_C8963E", v3(-1.5, 2, 0), 0.5, 4.15)
	k.rod("Color_C8963E", v3(1.5, 2, 0), 0.5, 4.15)
end)

fallback("TeslaTower", { Size = 24, Solid = true, Paints = { Primary = hex("4A4FA8"), Secondary = hex("FFB15C") } }, function(k)
	k.cyl("Primary", v3(0, 1.2, 0), 2.4, 8)
	k.cyl("Primary", v3(0, 9.6, 0), 15, 2.6)
	k.cyl("Secondary", v3(0, 6.2, 0), 1, 5.8)
	k.cyl("Secondary", v3(0, 10.2, 0), 1, 5)
	k.cyl("Secondary", v3(0, 14.2, 0), 1, 4.2)
	k.cyl("Primary", v3(0, 17.6, 0), 1.5, 3.4)
	k.ball("Neon_9EE8FF", v3(0, 20.8, 0), 5)
end)

-- origin at the bolt's tip
fallback("StormCloud", { Size = 14, Paints = { Primary = hex("8E87D9"), Secondary = hex("6F68C2") } }, function(k)
	k.ball("Primary", v3(-3.6, 6.2, 0), 6)
	k.ball("Primary", v3(0.6, 6.8, 0), 7)
	k.ball("Primary", v3(4.4, 6, 0.4), 5.4)
	k.ball("Secondary", v3(-0.4, 5.2, 1), 5)
	k.box("Neon_FFE15A", v3(0.5, 3.4, 0), v3(1.3, 2.6, 0.6), CFrame.Angles(0, 0, 0.45))
	k.box("Neon_FFE15A", v3(-0.1, 1.6, 0), v3(1.1, 2.2, 0.6), CFrame.Angles(0, 0, -0.45))
	k.box("Neon_FFE15A", v3(0.3, 0.5, 0), v3(0.8, 1.2, 0.6), CFrame.Angles(0, 0, 0.45))
end)

fallback("LightningRod", { Size = 10, Paints = { Primary = hex("8C93C8") } }, function(k)
	k.cyl("Primary", v3(0, 0.5, 0), 1, 2.6)
	k.cyl("Primary", v3(0, 5, 0), 8, 0.7)
	k.ball("Neon_FFE15A", v3(0, 9.3, 0), 1.6)
end)

fallback("Cactus", { Size = 9, Paints = { Primary = hex("4CB860"), Secondary = hex("FF7AA8") } }, function(k)
	k.cyl("Primary", v3(0, 3.8, 0), 7.6, 2.2)
	k.ball("Primary", v3(0, 7.6, 0), 2.2)
	k.rod("Primary", v3(-1.5, 3.6, 0), 2.2, 1.4)
	k.cyl("Primary", v3(-2.4, 5.1, 0), 3, 1.4)
	k.rod("Primary", v3(1.5, 4.6, 0), 2.2, 1.4)
	k.cyl("Primary", v3(2.4, 5.9, 0), 2.6, 1.4)
	k.ball("Secondary", v3(0, 8.7, 0), 1.3)
end)

fallback("Pyramid", { Size = 30, Solid = true, Paints = { Primary = hex("FFC86B"), Secondary = hex("F2A65A") } }, function(k)
	local widths = { 30, 24, 18, 12, 6.5 }
	for index, width in widths do
		k.box(if index % 2 == 1 then "Primary" else "Secondary", v3(0, 2.2 + (index - 1) * 4.4, 0), v3(width, 4.4, width))
	end
	k.box("Color_FFE15A", v3(0, 23.2, 0), v3(3.6, 3.6, 3.6), CFrame.Angles(0, math.rad(45), 0))
end)

fallback("SandArch", { Size = 22, Solid = true, Paints = { Primary = hex("F2A65A"), Secondary = hex("FFC86B") } }, function(k)
	for _, x in { -7.8, 7.8 } do
		k.cyl("Primary", v3(x, 6, 0), 12, 6.6)
		k.ball("Primary", v3(x, 13.4, 0), 6.8)
	end
	k.box("Secondary", v3(0, 13.6, 0), v3(16, 4.6, 6.2))
end)

fallback("OasisPool", { Size = 16, Paints = { Primary = hex("F2A65A") } }, function(k)
	k.cyl("Primary", v3(0, 0.3, 0), 1, 15)
	k.cyl("Glass_5CC8FF", v3(0, 0.62, 0), 0.4, 12)
end)

fallback("Igloo", { Size = 14, Solid = true, Paints = { Secondary = hex("BFDDF7") } }, function(k)
	k.ball("Color_EAF6FF", v3(0, 0, 0), 14)
	k.cyl("Secondary", v3(0, 2.5, 0), 0.4, 14.3)
	k.rod("Color_EAF6FF", v3(0, 2.2, -6.6), 5, 4.8, CFrame.Angles(0, math.rad(90), 0))
	k.rod("Color_233066", v3(0, 2.0, -9.1), 0.4, 3.4, CFrame.Angles(0, math.rad(90), 0))
end)

fallback("Snowman", { Size = 8, Paints = { Primary = hex("FF5A6E") } }, function(k)
	k.ball("Color_FFFFFF", v3(0, 2, 0), 4.4)
	k.ball("Color_FFFFFF", v3(0, 5, 0), 3.4)
	k.ball("Color_FFFFFF", v3(0, 7.2, 0), 2.6)
	k.cyl("Primary", v3(0, 6.15, 0), 0.6, 2.8)
	k.box("Color_FF9F1C", v3(0, 7.2, -1.6), v3(0.5, 0.5, 1.4))
	k.ball("Color_233066", v3(-0.5, 7.7, -1.15), 0.45)
	k.ball("Color_233066", v3(0.5, 7.7, -1.15), 0.45)
end)

fallback("IceCastleTower", { Size = 32, Solid = true, Paints = { Primary = hex("BFE6FF"), Secondary = hex("7FC4F5") } }, function(k)
	k.cyl("Primary", v3(0, 2, 0), 4, 12)
	k.cyl("Primary", v3(0, 14, 0), 20, 9)
	k.cyl("Secondary", v3(0, 25, 0), 2.4, 11)
	k.cyl("Secondary", v3(0, 27.5, 0), 2.6, 8)
	k.cyl("Secondary", v3(0, 29.8, 0), 2.2, 5.4)
	k.ball("Secondary", v3(0, 31.4, 0), 3)
	k.box("Neon_BDF4FF", v3(0, 11, -4.5), v3(1.6, 2.6, 0.4))
	k.box("Neon_BDF4FF", v3(0, 18, -4.5), v3(1.6, 2.6, 0.4))
end)

fallback("Volcano", { Size = 60, Solid = true, Paints = { Primary = hex("6A3F37"), Secondary = hex("8A5A4E") } }, function(k)
	local layers = { { 60, 8 }, { 50, 8 }, { 40, 8 }, { 30, 8 }, { 22, 6 } }
	local y = 0
	for index, layer in layers do
		k.cyl(if index % 2 == 1 then "Primary" else "Secondary", v3(0, y + layer[2] / 2, 0), layer[2], layer[1])
		y += layer[2]
	end
	k.cyl("Neon_FF7A2E", v3(0, y + 0.1, 0), 1, 15)
	k.box("Neon_FF7A2E", v3(0, 30, -13.5), v3(3.4, 13, 2), CFrame.Angles(0.5, 0, 0))
	k.box("Neon_FF7A2E", v3(11, 26, -8), v3(3, 12, 2), CFrame.Angles(0.45, math.rad(-50), 0))
end)

fallback("LavaSpire", { Size = 14, Solid = true, Paints = { Primary = hex("4E2C29") } }, function(k)
	k.cyl("Primary", v3(0, 2, 0), 4, 5.2)
	k.cyl("Primary", v3(0.2, 6, 0), 4, 3.8)
	k.cyl("Primary", v3(0.3, 9.6, 0), 3.4, 2.6)
	k.ball("Primary", v3(0.3, 11.8, 0), 2.4)
	k.box("Neon_FF7A2E", v3(0.4, 5, -1.9), v3(0.6, 5, 0.5), CFrame.Angles(0, 0, 0.2))
end)

fallback("SteamVent", { Size = 6, Paints = { Primary = hex("5A3A36") } }, function(k)
	k.cyl("Primary", v3(0, 0.5, 0), 1.4, 6)
	k.cyl("Neon_FFB15C", v3(0, 0.6, 0), 1.5, 3.4)
end)

-- origin at the bottom of the rocky cone; the flat top is 10 studs up
fallback("FloatingIsland", { Size = 16, Solid = true, Paints = { Primary = hex("8BEA5E"), Secondary = hex("A99CE3"), Tertiary = hex("8C7FD0") } }, function(k)
	k.cyl("Primary", v3(0, 9, 0), 2, 16)
	k.cyl("Secondary", v3(0, 6.6, 0), 3, 13.6)
	k.cyl("Tertiary", v3(0, 4, 0), 3, 10)
	k.cyl("Secondary", v3(0, 1.8, 0), 2.6, 6)
	k.ball("Tertiary", v3(0, 0.8, 0), 2.6)
end)

fallback("StarLamp", { Size = 10, Paints = { Primary = hex("8E7BE6") } }, function(k)
	k.cyl("Primary", v3(0, 0.4, 0), 0.8, 2.4)
	k.cyl("Primary", v3(0, 4.4, 0), 7.6, 0.6)
	k.ball("Neon_FFE15A", v3(0, 9, 0), 2.4)
end)

fallback("CloudBank", { Size = 24, Paints = { Secondary = hex("E3D9FF") } }, function(k)
	k.ball("Color_FFFFFF", v3(-5, 4.8, 0), 9.6)
	k.ball("Color_FFFFFF", v3(2, 5.6, 1), 11)
	k.ball("Color_FFFFFF", v3(8.4, 4, -1), 7.6)
	k.ball("Secondary", v3(-9.6, 3.4, 1), 6.6)
end)

fallback("CitadelTower", { Size = 34, Solid = true, Paints = { Primary = hex("E2D8FF"), Secondary = hex("A98BFF"), Tertiary = hex("FF8FC8") } }, function(k)
	k.cyl("Secondary", v3(0, 2, 0), 4, 14)
	k.cyl("Primary", v3(0, 15, 0), 22, 10)
	k.cyl("Secondary", v3(0, 26.6, 0), 2.2, 12)
	k.cyl("Tertiary", v3(0, 29, 0), 2.4, 9)
	k.cyl("Tertiary", v3(0, 31.2, 0), 2.2, 6)
	k.ball("Tertiary", v3(0, 33, 0), 3.2)
	k.box("Neon_FFF3B0", v3(0, 12, -5), v3(1.6, 2.8, 0.4))
	k.box("Neon_FFF3B0", v3(0, 20, -5), v3(1.6, 2.8, 0.4))
end)

fallback("AuroraArch", { Size = 26, Paints = {} }, function(k)
	for band, info in { { "Glass_9EF0D8", 1, 0 }, { "Glass_B58CFF", 0.8, 1 } } do
		local rx, ry = 12 * info[2], 17 * info[2]
		local steps = 6
		for index = 0, steps - 1 do
			local t0, t1 = index / steps * math.pi, (index + 1) / steps * math.pi
			local x0, y0 = math.cos(t0) * rx, math.sin(t0) * ry
			local x1, y1 = math.cos(t1) * rx, math.sin(t1) * ry
			local length = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2) + 0.6
			k.box(info[1], v3((x0 + x1) / 2, (y0 + y1) / 2, info[3] - 0.5), v3(length, 3 - band * 0.4, 1.2), CFrame.Angles(0, 0, math.atan2(y1 - y0, x1 - x0)))
		end
	end
end)

-- structures ------------------------------------------------------------------
fallback("WeatherTower", { Size = 60, Solid = true, Paints = { Primary = SKY, Secondary = STORM } }, function(k)
	k.cyl("Secondary", v3(0, 2, 0), 4, 22)
	k.cyl("Color_EEF0FF", v3(0, 12, 0), 16, 17)
	k.cyl("Primary", v3(0, 20.8, 0), 1.6, 20)
	k.cyl("Color_EEF0FF", v3(0, 28.8, 0), 16, 14)
	k.cyl("Primary", v3(0, 36.8, 0), 1.6, 17)
	k.cyl("Color_EEF0FF", v3(0, 41.6, 0), 8, 12)
	k.cyl("Primary", v3(0, 46.2, 0), 1.6, 14.5)
	k.ball("Primary", v3(0, 48.6, 0), 11)
	k.ball("Neon_9EE8FF", v3(0, 42, -5.6), 3.2)
	k.ball("Neon_9EE8FF", v3(0, 29, -6.6), 3.2)
	k.ball("Neon_9EE8FF", v3(0, 13, -8.2), 3.2)
	k.cyl("Color_EEF0FF", v3(0, 55, 0), 4, 0.8)
	k.cyl("Secondary", v3(4.2, 52.6, 0), 0.8, 5.6, CFrame.Angles(0, 0, 0.6))
	k.ball("Secondary", v3(0, 57.4, 0), 1.8)
	k.box("Primary", v3(0, 58.6, 0), v3(4.4, 1.4, 0.4))
end)

-- open front: walls on three sides, a rounded column at every corner, a striped awning over the opening
local function shell(k, width: number, depth: number, height: number)
	local hw, hd = width / 2, depth / 2
	k.box("Color_EEF0FF", v3(0, height / 2 + 0.8, hd - 0.8), v3(width - 2.6, height, 1.6))
	for _, x in { -1, 1 } do
		k.box("Color_EEF0FF", v3(x * (hw - 0.8), height / 2 + 0.8, 0.5), v3(1.6, height, depth - 3.6))
		for _, z in { -1, 1 } do
			k.cyl("Color_EEF0FF", v3(x * (hw - 0.8), height / 2 + 0.8, z * (hd - 1.4)), height + 0.6, 3)
		end
	end
end

local function roof(k, y: number, width: number, depth: number)
	k.box("Primary", v3(0, y, 0), v3(width - 1.6, 1.6, depth))
	k.rod("Primary", v3(-(width / 2 - 0.8), y, 0), depth, 1.6, CFrame.Angles(0, math.rad(90), 0))
	k.rod("Primary", v3(width / 2 - 0.8, y, 0), depth, 1.6, CFrame.Angles(0, math.rad(90), 0))
	k.rod("Primary", v3(0, y, -depth / 2), width - 1.6, 1.6)
end

fallback("StationBooth", { Size = 20, Solid = true, Paints = { Primary = SKY, Secondary = SKY_DEEP } }, function(k)
	k.rbox("Secondary", v3(0, 0.4, 0), v3(20, 0.8, 14), 2)
	shell(k, 20, 14, 11.2)
	k.box("Color_EEF0FF", v3(0, 13, -6.3), v3(17.4, 3.6, 1.4))
	k.box("Secondary", v3(0, 14.9, 0.2), v3(20.4, 0.6, 14.4))
	roof(k, 15.9, 21.6, 15.6)
	k.ball("Secondary", v3(0, 17.3, 0), 2.6)
	-- the awning: six stripes tilting out over the opening
	for index = 0, 5 do
		local x = -7.5 + index * 3
		k.box(if index % 2 == 0 then "Primary" else "Color_FFFFFF", v3(x, 10.4, -8.3), v3(3, 0.5, 3.4), CFrame.Angles(-0.42, 0, 0))
	end
	k.box("Primary", v3(0, 2.4, -4), v3(12, 3.6, 2))
	k.box("Color_FFFFFF", v3(0, 4.5, -4), v3(12.6, 0.6, 2.6))
	k.ball("Neon_FFF3B0", v3(-10.1, 7.4, 0.5), 2.2)
	k.ball("Neon_FFF3B0", v3(10.1, 7.4, 0.5), 2.2)
end)

fallback("WeatherLab", { Size = 22, Solid = true, Paints = { Primary = BOLT, Secondary = BOLT_DEEP } }, function(k)
	k.rbox("Secondary", v3(0, 0.4, 0), v3(22, 0.8, 18), 2.4)
	shell(k, 22, 18, 11.2)
	k.box("Color_EEF0FF", v3(0, 11.2, -8.3), v3(19.4, 2, 1.4))
	roof(k, 13, 23.4, 19.4)
	-- the observatory dome and the radar dish
	k.cyl("Secondary", v3(-3, 14.3, 2), 1.2, 11.4)
	k.ball("Glass_9EE8FF", v3(-3, 15, 2), 10)
	k.cyl("Color_EEF0FF", v3(6.5, 15.4, 3), 3, 1)
	k.cyl("Secondary", v3(6.5, 17.4, 2.6), 0.8, 5.4, CFrame.Angles(-0.6, 0, 0))
	k.ball("Neon_9EE8FF", v3(6.5, 18.6, 1.8), 1.2)
	k.ball("Neon_FFF3B0", v3(-11.1, 7.4, 2), 2.2)
	k.ball("Neon_FFF3B0", v3(11.1, 7.4, 2), 2.2)
end)

fallback("RebirthShrine", { Size = 20, Solid = true, Paints = { Primary = hex("E2D8FF"), Secondary = STORM } }, function(k)
	k.cyl("Primary", v3(0, 0.8, 0), 1.6, 18)
	k.cyl("Secondary", v3(0, 2.1, 0), 1, 13)
	for index = 0, 3 do
		local angle = index * math.pi / 2 + math.pi / 4
		local x, z = math.cos(angle) * 7, math.sin(angle) * 7
		k.cyl("Primary", v3(x, 8.2, z), 12, 1.8)
		k.ball("Secondary", v3(x, 14.6, z), 2.6)
	end
	k.rod("Neon_B58CFF", v3(0, 10.5, 0), 0.5, 9, CFrame.Angles(0, math.rad(90), 0))
	k.rod("Glass_EBDFFF", v3(0, 10.5, 0), 0.7, 7, CFrame.Angles(0, math.rad(90), 0))
end)

fallback("ForecastTower", { Size = 22, Solid = true, Paints = { Primary = SKY, Secondary = SKY_DEEP } }, function(k)
	k.cyl("Secondary", v3(-5, 4, 0), 8, 1.6)
	k.cyl("Secondary", v3(5, 4, 0), 8, 1.6)
	k.box("Color_EEF0FF", v3(0, 14, 0), v3(14, 12, 6))
	k.box("Primary", v3(0, 20.4, 0), v3(14.8, 1.2, 5.6))
	k.box("Primary", v3(0, 7.6, 0), v3(14.8, 1.2, 5.6))
	k.cyl("Secondary", v3(4, 22.4, 0), 3, 0.6)
	k.ball("Primary", v3(4, 24, 0), 1.4)
end)

fallback("EggIncubator", { Size = 12, Solid = true, Paints = { Primary = hex("EEF0FF"), Secondary = SKY } }, function(k)
	k.cyl("Primary", v3(0, 1.5, 0), 3, 12)
	k.cyl("Secondary", v3(0, 3.2, 0), 0.8, 12.6)
	k.ball("Glass_DFF6FF", v3(0, 6.4, 0), 11)
end)

fallback("SellMachine", { Size = 12, Solid = true, Paints = { Primary = LEAF, Secondary = hex("33B24A") } }, function(k)
	local zAxis = CFrame.Angles(0, math.rad(90), 0)
	k.rbox("Secondary", v3(0, 0.8, 0), v3(10, 1.6, 8), 2)
	k.rbox("Primary", v3(0, 4.4, 0), v3(8.6, 5.6, 6.8), 1.8)
	-- the storm jar: glass, glowing rain inside, a fat lid and knob
	k.cyl("Secondary", v3(0, 7.6, 0), 1, 6.6)
	k.cyl("Glass_54E0FF", v3(0, 10, 0), 4.6, 6)
	k.cyl("Neon_54E0FF", v3(0, 9.2, 0), 2.8, 4.6)
	k.cyl("Secondary", v3(0, 12.6, 0), 1.2, 6.8)
	k.ball("Neon_FFE15A", v3(0, 13.6, 0), 2)
	-- a bolt on the front, and the coin chute with a coin in its tray
	k.box("Neon_FFE15A", v3(-1.6, 5.4, -3.45), v3(1.4, 2.4, 0.5), CFrame.Angles(0, 0, -0.45))
	k.box("Neon_FFE15A", v3(-1.2, 3.6, -3.45), v3(1.2, 2.2, 0.5), CFrame.Angles(0, 0, 0.45))
	k.box("Secondary", v3(2.2, 2.6, -3.9), v3(3.2, 1.6, 2))
	k.rod("Color_FFE15A", v3(2.2, 3.9, -3.9), 0.6, 1.8, zAxis)
end)

-- spans X (pillars at x = +-16.5), front -Z; sign area 24 x 5 centred 24 up
fallback("ZoneGate", { Size = 40, Solid = true, Paints = { Primary = BODY, Secondary = SKY, Tertiary = INK_SOFT } }, function(k)
	local zAxis = CFrame.Angles(0, math.rad(90), 0)
	for _, x in { -16.5, 16.5 } do
		k.cyl("Tertiary", v3(x, 1.3, 0), 2.6, 8.4)
		k.cyl("Primary", v3(x, 11.6, 0), 19, 6.6)
		k.cyl("Tertiary", v3(x, 8, 0), 1.3, 7.6)
		k.cyl("Tertiary", v3(x, 15.5, 0), 1.3, 7.6)
		k.ball("Tertiary", v3(x, 29.2, 0), 5)
		-- rounded beam ends over the pillars
		k.rod("Secondary", v3(x, 24.4, 0), 7.2, 7, zAxis)
	end
	k.box("Secondary", v3(0, 24.4, 0), v3(33, 7, 7.2))
	k.rod("Tertiary", v3(0, 21.2, 0), 33, 2)
	-- a little cloud resting on the beam
	k.ball("Color_FFFFFF", v3(-2.4, 29, 0.6), 5)
	k.ball("Color_FFFFFF", v3(1.6, 29.6, 0.6), 6)
	k.ball("Color_FFFFFF", v3(5, 28.6, 0.6), 4)
end)

-- one chunk of island edge: flat top at y = 0 along the playable side (+Z), layered rock down to -30,
-- front (-Z) = the outside
fallback("CliffSegment", { Size = 40, Paints = { Primary = hex("6EE05A"), Secondary = hex("D99A62"), Tertiary = hex("B8754A") } }, function(k)
	local seed = k.Seed
	-- the lip, then rock bands with rounded fronts, each stepping in a little further, then boulders
	k.ledge("Primary", v3(0, -1.4, -9), 40.4, 2.8, 18)
	k.ledge("Secondary", v3(0, -7.2, -7.6), 40, 8.8, 16)
	k.ledge("Tertiary", v3(0, -14.6, -5.2 + seed * 1.5), 38 - seed * 3, 6, 13)
	k.ledge("Secondary", v3(-seed * 3, -20.4, -2.6 - seed), 31 - seed * 5, 5.6, 9)
	k.ball("Tertiary", v3(-8 + seed * 6, -24.5, 2), 9)
	k.ball("Secondary", v3(7 - seed * 5, -25 - seed * 2, 2.4), 8)
end)

fallback("CloudPuff", { Size = 30, Paints = { Secondary = hex("DCE6FA") } }, function(k)
	k.ball("Color_FFFFFF", v3(-7, 4.6, 0), 13)
	k.ball("Color_FFFFFF", v3(4, 6, 0.5), 15)
	k.ball("Secondary", v3(11, 3.4, -0.5), 9)
end)

fallback("Bench", { Size = 6, Solid = true, Paints = { Primary = hex("FFB15C"), Secondary = INK_SOFT } }, function(k)
	k.box("Primary", v3(0, 1.6, 0), v3(6, 0.5, 1.8))
	k.box("Primary", v3(0, 2.7, 0.75), v3(6, 1.4, 0.4))
	k.box("Secondary", v3(-2.4, 0.7, 0), v3(0.6, 1.4, 1.6))
	k.box("Secondary", v3(2.4, 0.7, 0), v3(0.6, 1.4, 1.6))
end)

-- board front 5 x 2.5 centred 6 up
fallback("SignPost", { Size = 8, Paints = { Primary = hex("A8724C"), Secondary = SKY } }, function(k)
	k.cyl("Primary", v3(-2.2, 3.6, 0), 7.2, 0.8)
	k.cyl("Primary", v3(2.2, 3.6, 0), 7.2, 0.8)
	k.box("Secondary", v3(0, 6, 0.15), v3(5.8, 3.2, 0.3))
	k.box("Color_FFFFFF", v3(0, 6, -0.1), v3(5.4, 2.8, 0.4))
end)

fallback("Planter", { Size = 9, Solid = true, Paints = { Primary = hex("FFB15C") } }, function(k)
	k.cyl("Primary", v3(0, 1, 0), 2, 9)
	k.cyl("Color_6B4A35", v3(0, 1.9, 0), 0.4, 7.6)
end)

-- screen 16 x 18 centred 13 up on the front
fallback("LeaderboardFrame", { Size = 24, Solid = true, Paints = { Primary = BOLT, Secondary = INK_SOFT } }, function(k)
	k.box("Secondary", v3(0, 0.8, 0), v3(20, 1.6, 3))
	k.cyl("Primary", v3(-9.2, 11.6, 0.4), 22, 1.6)
	k.cyl("Primary", v3(9.2, 11.6, 0.4), 22, 1.6)
	k.box("Secondary", v3(0, 13, 0), v3(17.6, 19.6, 3))
	k.box("Color_EEF0FF", v3(0, 23.4, 0.4), v3(21, 2.2, 2.6))
end)

-- Places a prop from the pack, or builds its stand-in. options: Scale (number or Vector3), Paints,
-- Collide (nil = the prop's own setting), CastShadow, Anchor (default false: no Root part)
local function place(id: string, parent: Instance, cframe: CFrame, options): Model
	options = options or {}
	local stats = MapService.Stats
	local placed = WorldProps.Place(id, parent, cframe, {
		Scale = options.Scale,
		Paints = options.Paints,
		Collide = options.Collide,
		CastShadow = options.CastShadow,
		Anchor = options.Anchor == true,
	})
	if placed then
		stats.Props += 1
		return placed
	end
	stats.Built += 1
	stats.Missing[id] = (stats.Missing[id] or 0) + 1

	local built = Instance.new("Model")
	built.Name = id
	local info = FALLBACK[id]
	if info then
		local scale = options.Scale or 1
		local largest = info.Size * (if typeof(scale) == "Vector3" then math.max(scale.X, scale.Y, scale.Z) else scale)
		local paints = table.clone(info.Paints)
		for name, color in options.Paints or {} do
			paints[name] = color
		end
		local solid = if options.Collide ~= nil then options.Collide == true else info.Solid == true
		local shadow = if options.CastShadow ~= nil then options.CastShadow == true else largest >= 6
		info.Build(kit(built, id, cframe, scale, solid, shadow, paints))
	end
	built.WorldPivot = cframe
	built.Parent = parent
	return built
end

-- The first piece of a placed prop (pack or stand-in) whose paint starts with `prefix` ("Neon_", "Glass_",
-- "Primary", ...)
local function pieceOf(target: Instance, prefix: string): BasePart?
	for _, child in target:GetChildren() do
		if child:IsA("BasePart") and string.find(child.Name, "." .. prefix, 1, true) then
			return child
		end
	end
	return nil
end

-- The face of `piece` that points most nearly straight up, for particles that should rise from it: a
-- pack mesh stands upright, but a part-built cylinder lies on its side (its Top face points sideways)
local function upFace(piece: BasePart): Enum.NormalId
	local frame = piece.CFrame
	local best, bestY = Enum.NormalId.Top, -math.huge
	for _, face in {
		{ Enum.NormalId.Top, frame.UpVector.Y },
		{ Enum.NormalId.Bottom, -frame.UpVector.Y },
		{ Enum.NormalId.Right, frame.RightVector.Y },
		{ Enum.NormalId.Left, -frame.RightVector.Y },
		{ Enum.NormalId.Front, frame.LookVector.Y },
		{ Enum.NormalId.Back, -frame.LookVector.Y },
	} do
		if face[2] > bestY then
			best, bestY = face[1], face[2]
		end
	end
	return best
end

---------------------------------------------------------------------------
-- Islands: ground, cliffs, the cloud sea, fields and paths
---------------------------------------------------------------------------
local function regionBounds(regionId: number): (number, number)
	if regionId == 0 then
		return MapLayout.HubStart, MapLayout.HubEnd
	end
	return MapLayout.ZoneStart(regionId), MapLayout.ZoneEnd(regionId)
end

-- The island top a region owns (the hub reaches west past its boundary, the last zone east)
local function islandBounds(regionId: number): (number, number)
	local x0, x1 = regionBounds(regionId)
	if regionId == 0 then
		x0 = WEST_END
	end
	if regionId == MapLayout.ZoneCount then
		x1 = EAST_END
	end
	return x0, x1
end

local function regionAt(x: number): number
	if x < MapLayout.HubEnd then
		return 0
	end
	return math.clamp(math.floor(x / MapLayout.ZoneLength) + 1, 1, MapLayout.ZoneCount)
end

local function cliffPaints(biome)
	return { Primary = biome.Lip, Secondary = biome.Rock, Tertiary = biome.Band }
end

local function buildIsland(parent: Instance, regionId: number)
	local biome = BIOMES[regionId]
	local island = folder("Island", parent)
	local x0, x1 = islandBounds(regionId)
	part({
		Name = "Ground",
		Size = Vector3.new(x1 - x0, SLAB, EDGE * 2),
		CFrame = CFrame.new((x0 + x1) / 2, GROUND_Y - SLAB / 2, 0),
		Color = biome.Ground,
		CastShadow = false,
		Parent = island,
	})

	-- Layered cliffs along both sides, beyond the boundaries (and around the ends of the world)
	local rng = Random.new(500 + regionId)
	local cliffs = folder("Cliffs", island)
	local paints = cliffPaints(biome)
	local function cliff(position: Vector3, outward: Vector3, width: number)
		place("CliffSegment", cliffs, CFrame.new(position) * facing(outward.X, outward.Z), {
			Scale = Vector3.new(width / 40 * 1.06, rng:NextNumber(0.95, 1.25), rng:NextNumber(1, 1.2)),
			Paints = paints,
			Collide = false,
			CastShadow = false,
		})
	end
	local y = GROUND_Y - 0.12
	local count = math.max(1, math.floor((x1 - x0) / 40 + 0.5))
	local width = (x1 - x0) / count
	for index = 0, count - 1 do
		local x = x0 + (index + 0.5) * width
		cliff(Vector3.new(x, y, -EDGE), Vector3.new(0, 0, -1), width)
		cliff(Vector3.new(x, y, EDGE), Vector3.new(0, 0, 1), width)
	end
	for _, info in { { WEST_END, -1, 0 }, { EAST_END, 1, MapLayout.ZoneCount } } do
		if regionId == info[3] then
			local endCount = math.floor(EDGE * 2 / 40 + 0.5)
			local endWidth = EDGE * 2 / endCount
			for index = 0, endCount - 1 do
				cliff(Vector3.new(info[1], y, -EDGE + (index + 0.5) * endWidth), Vector3.new(info[2], 0, 0), endWidth)
			end
			for _, side in { -1, 1 } do
				local outward = Vector3.new(info[2], 0, side).Unit
				cliff(Vector3.new(info[1] - info[2] * 6, y, side * (EDGE - 6)), outward, 30)
			end
		end
	end
end

-- The cloud sea under and around the islands, and big clouds on the horizon
local function buildCloudSea(parent: Instance)
	local sea = folder("CloudSea", parent)
	local rng = Random.new(31)
	local floorWidth = (EAST_END - WEST_END + 1200) / 2
	for index = 0, 1 do
		deco({
			Name = "CloudFloor",
			Size = Vector3.new(floorWidth, 2, 2048),
			CFrame = CFrame.new(WEST_END - 600 + floorWidth * (index + 0.5), -64, 0),
			Color = hex("B5DEFF"),
			Parent = sea,
		})
	end
	local function puff(position: Vector3, scale: number)
		local biome = BIOMES[regionAt(math.clamp(position.X, WEST_END, EAST_END))]
		place("CloudPuff", sea, CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5) + (if rng:NextNumber() < 0.5 then 0 else math.pi), 0), {
			Scale = scale,
			Paints = { Secondary = biome.Cloud },
			Collide = false,
			CastShadow = false,
		})
	end
	for x = WEST_END - 90, EAST_END + 90, 62 do
		for _, side in { -1, 1 } do
			puff(Vector3.new(x + rng:NextNumber(-12, 12), rng:NextNumber(-54, -46), side * (EDGE + rng:NextNumber(14, 34))), rng:NextNumber(1.3, 1.9))
			puff(Vector3.new(x + rng:NextNumber(-20, 20), rng:NextNumber(-52, -38), side * (EDGE + rng:NextNumber(80, 140))), rng:NextNumber(1.8, 2.6))
			if rng:NextNumber() < 0.6 then
				puff(Vector3.new(x + rng:NextNumber(-25, 25), rng:NextNumber(-52, -26), side * (EDGE + rng:NextNumber(190, 330))), rng:NextNumber(2.4, 3.6))
			end
		end
	end
	-- around the ends of the world
	for _, info in { { WEST_END, -1 }, { EAST_END, 1 } } do
		for z = -EDGE - 60, EDGE + 60, 50 do
			puff(Vector3.new(info[1] + info[2] * rng:NextNumber(18, 40), rng:NextNumber(-54, -46), z + rng:NextNumber(-10, 10)), rng:NextNumber(1.4, 2))
			puff(Vector3.new(info[1] + info[2] * rng:NextNumber(90, 160), rng:NextNumber(-46, -30), z + rng:NextNumber(-20, 20)), rng:NextNumber(2, 2.8))
		end
	end
	-- big clouds on the horizon, seen above the island edges
	for x = WEST_END - 200, EAST_END + 200, 150 do
		for _, side in { -1, 1 } do
			if rng:NextNumber() < 0.7 then
				puff(Vector3.new(x + rng:NextNumber(-50, 50), rng:NextNumber(0, 50), side * rng:NextNumber(520, 760)), rng:NextNumber(4, 6.5))
			end
		end
	end
end

-- A rounded slab: x0..x1 by z0..z1, top at `top`
local function roundedPad(parent: Instance, name: string, x0: number, x1: number, z0: number, z1: number, top: number, bottom: number, radius: number, color: Color3)
	local height = top - bottom
	local y = (top + bottom) / 2
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	part({ Name = name, Size = Vector3.new(x1 - x0 - radius * 2, height, z1 - z0), CFrame = CFrame.new(cx, y, cz), Color = color, CastShadow = false, Parent = parent })
	part({ Name = name, Size = Vector3.new(x1 - x0, height, z1 - z0 - radius * 2), CFrame = CFrame.new(cx, y, cz), Color = color, CastShadow = false, Parent = parent })
	for _, x in { x0 + radius, x1 - radius } do
		for _, z in { z0 + radius, z1 - radius } do
			cylinder({ Name = name, Position = Vector3.new(x, y, z), Height = height, Diameter = radius * 2, Color = color, CastShadow = false, Parent = parent })
		end
	end
end

-- White dashes around a rectangle, `inset` inside its edge
local function dashedBorder(parent: Instance, x0: number, x1: number, z0: number, z1: number, top: number, inset: number)
	local DASH, GAP, WIDTH = 7, 4, 1.2
	local function line(ax: number, az: number, bx: number, bz: number)
		local dx, dz = bx - ax, bz - az
		local length = math.sqrt(dx * dx + dz * dz)
		local count = math.max(1, math.floor((length + GAP) / (DASH + GAP)))
		local dash = (length - (count - 1) * GAP) / count
		for index = 0, count - 1 do
			local t = (index * (dash + GAP) + dash / 2) / length
			local position = Vector3.new(ax + dx * t, top - 0.07, az + dz * t)
			deco({
				Name = "FieldLine",
				Size = Vector3.new(WIDTH, 0.2, dash),
				CFrame = CFrame.lookAt(position, position + Vector3.new(dx, 0, dz)),
				Color = WHITE,
				Parent = parent,
			})
		end
	end
	local a0, a1, b0, b1 = x0 + inset, x1 - inset, z0 + inset, z1 - inset
	line(a0, b0, a1, b0)
	line(a0, b1, a1, b1)
	line(a0, b0 + 1.6, a0, b1 - 1.6)
	line(a1, b0 + 1.6, a1, b1 - 1.6)
end

-- The weather field (MapLayout.FieldBounds): two raised pads either side of the path, white dashed borders
local function buildField(parent: Instance, zoneId: number)
	local biome = BIOMES[zoneId]
	local field = folder("Field", parent)
	local minX, maxX, minZ, maxZ = MapLayout.FieldBounds(zoneId)
	for _, pad in { { minZ, -FIELD_GAP }, { FIELD_GAP, maxZ } } do
		roundedPad(field, "FieldPad", minX, maxX, pad[1], pad[2], FIELD_Y, GROUND_Y - 0.4, 3, biome.Field)
		dashedBorder(field, minX, maxX, pad[1], pad[2], FIELD_Y, 2.4)
	end
end

-- Pavers in a running bond (rows of two, then one between two halves), two-tone. Along X (or along Z when
-- `alongZ`): from a to b, centred on c across `width`. `skip(x, z)` leaves a paver out.
local function pavers(parent: Instance, biome, a: number, b: number, c: number, width: number, alongZ: boolean?, skip)
	if a > b then
		a, b = b, a
	end
	local count = math.max(1, math.floor((b - a) / PAVER + 0.5))
	local step = (b - a) / count
	local half = width / 2
	for index = 0, count - 1 do
		local along = a + (index + 0.5) * step
		local cuts = if index % 2 == 0 then { -half, 0, half } else { -half, -half / 2, half / 2, half }
		for piece = 1, #cuts - 1 do
			local from, to = cuts[piece], cuts[piece + 1]
			local offset = c + (from + to) / 2
			local across = to - from
			local x, z = along, offset
			if alongZ then
				x, z = offset, along
			end
			if not (skip and skip(x, z)) then
				deco({
					Name = "Paver",
					Size = if alongZ then Vector3.new(across - 0.5, 0.36, step - 0.5) else Vector3.new(step - 0.5, 0.36, across - 0.5),
					CFrame = CFrame.new(x, GROUND_Y + 0.06, z),
					Color = biome.Pavers[(index + piece) % 2 + 1],
					CanCollide = true,
					CanQuery = true,
					Parent = parent,
				})
			end
		end
	end
end

---------------------------------------------------------------------------
-- Shared pieces
---------------------------------------------------------------------------
-- A LampPost on the ground; its arm reaches along its -X, so turn it to hang toward `toward`
local function lamp(parent: Instance, position: Vector3, toward: Vector3, paints, scale: number?)
	local direction = Vector3.new(toward.X - position.X, 0, toward.Z - position.Z)
	local yaw = math.atan2(direction.Z, -direction.X)
	place("LampPost", parent, CFrame.new(position.X, GROUND_Y, position.Z) * CFrame.Angles(0, yaw, 0), { Paints = paints, Scale = scale or 1.15 })
end

-- The sell station's pad. EconomyService sells the whole tank of anyone standing within
-- MapLayout.SellPadRadius of its centre, so the glowing ring (PadGlow, tag "Pulse") is exactly that circle.
-- A low two-step dais (white step, Ink rim: 0.45-stud steps anyone walks up) with the ring, an Ink centre
-- with a neon bolt, rising sparkles, an arrow spinning and bobbing over the middle (above head height), and
-- a "⚡ SELL" sign on two posts at the side, facing the path (+Z). Everything is placed from the pad's own
-- position; there is no BillboardGui: StudsOffsetWorldSpace turns with its adornee, and on the glow cylinder
-- (rolled so its X axis points up) it laid the old label 7 studs to the side, half in the ground.
local SELL_DAIS = MapLayout.SellPadRadius + 2.5 -- outer radius of the dais
local SELL_SIGN = Vector3.new(-16.2, 0, -2.5) -- the sign, from the pad's centre (the sell machine stands at +X)
local SELL_MACHINE = Vector3.new(17.5, 0, -2) -- the SellMachine prop, from the pad's centre

-- A flat triangle a, b, c from two WedgeParts `thickness` thick (split along the altitude onto the longest edge)
local function wedgeTriangle(parent: Instance, a: Vector3, b: Vector3, c: Vector3, thickness: number, props)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	for _, half in { { (a + b) / 2, math.abs(ab:Dot(back)), 1 }, { (a + c) / 2, math.abs(ac:Dot(back)), -1 } } do
		local piece = {}
		for key, value in props do
			piece[key] = value
		end
		piece.Size = Vector3.new(thickness, height, half[2])
		piece.CFrame = CFrame.fromMatrix(half[1], right * half[3], up, back * half[3])
		piece.Parent = parent
		part(piece, "WedgePart")
	end
end

-- A flat neon lightning bolt lying on the pad's centre (`top` = the surface under it), upright as seen from
-- the path: a zig-zag hexagon (u to the right, v toward the back) cut into four triangles
local BOLT_SHAPE = { { 0.1, 1 }, { -0.9, -0.2 }, { 0, -0.2 }, { -0.1, -1 }, { 0.9, 0.2 }, { 0, 0.2 } }
local function sellBolt(parent: Instance, center: Vector3, top: number, color: Color3, scale: number)
	local points = {}
	for index, point in BOLT_SHAPE do
		points[index] = Vector3.new(center.X + point[1] * scale, top + 0.06, center.Z - point[2] * scale)
	end
	local props = { Name = "Bolt", Color = color, Material = M.Neon, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
	for _, triangle in { { 1, 2, 3 }, { 1, 3, 6 }, { 3, 4, 5 }, { 3, 5, 6 } } do
		wedgeTriangle(parent, points[triangle[1]], points[triangle[2]], points[triangle[3]], 0.12, props)
	end
end

-- A down-pointing arrow (two flat ones crossed, so it reads from every side) that spins and bobs (tag "Spin")
local function sellArrow(parent: Instance, center: Vector3, color: Color3)
	local arrow = model("Arrow", parent)
	local headWidth, headHeight, shaftWidth, shaftHeight, thick = 3.4, 2, 1.4, 1.9, 0.75
	local headTop = (headHeight + shaftHeight) / 2 - shaftHeight -- the head's flat top, from the centre
	for _, turn in { 0, math.pi / 2 } do
		local base = CFrame.new(center) * CFrame.Angles(0, turn, 0)
		local ghost = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
		local function piece(name: string, size: Vector3, cframe: CFrame, className: string?)
			local props = { Name = name, Size = size, CFrame = cframe, Color = color, Material = M.Neon, Parent = arrow }
			for key, value in ghost do
				props[key] = value
			end
			return part(props, className)
		end
		piece("Shaft", Vector3.new(shaftWidth, shaftHeight, thick), base * CFrame.new(0, headTop + shaftHeight / 2, 0))
		-- each half of the head is a WedgePart turned so its right angle sits at the top of the middle
		for _, side in { -1, 1 } do
			local position = Vector3.new(side * headWidth / 4, headTop - headHeight / 2, 0)
			local cframe = CFrame.fromMatrix(position, Vector3.new(0, 0, -side), Vector3.new(0, -1, 0), Vector3.new(-side, 0, 0))
			piece("Head", Vector3.new(thick, headHeight, headWidth / 2), base * cframe, "WedgePart")
		end
	end
	arrow.WorldPivot = CFrame.new(center)
	CollectionService:AddTag(arrow, "Spin")
	arrow:SetAttribute("SpinSpeed", 1.4)
	arrow:SetAttribute("BobHeight", 0.6)
	return arrow
end

local function sellPad(parent: Instance, position: Vector3, color: Color3)
	local pad = model("SellPad", parent)
	local radius = MapLayout.SellPadRadius
	local function at(height: number): Vector3
		return Vector3.new(position.X, GROUND_Y + height, position.Z)
	end

	-- the dais: step top +0.45, rim top +0.9, ring top +1, centre top +1.1 (above the ground at GROUND_Y)
	cylinder({ Name = "PadStep", Position = at(-0.05), Height = 1, Diameter = SELL_DAIS * 2, Color = BODY, CastShadow = false, Parent = pad })
	cylinder({ Name = "PadBase", Position = at(0.2), Height = 1.4, Diameter = radius * 2 + 2.4, Color = INK, CastShadow = false, Parent = pad })
	local glow = cylinder({ Name = "PadGlow", Position = at(0.6), Height = 0.8, Diameter = radius * 2, Color = color, Material = M.Neon, Transparency = 0.1, CastShadow = false, Parent = pad, Tags = { "Pulse" } })
	cylinder({ Name = "PadCenter", Position = at(0.7), Height = 0.8, Diameter = radius * 2 - 5.4, Color = INK, CastShadow = false, Parent = pad })
	sellBolt(pad, at(0), GROUND_Y + 1.1, color, 3.6)
	emitter(glow, {
		Texture = SPARKLE,
		Color = ColorSequence.new(color),
		Size = NumberSequence.new(0.6, 0),
		Lifetime = NumberRange.new(1.2, 1.8),
		Rate = 14,
		Speed = NumberRange.new(3, 6),
		EmissionDirection = Enum.NormalId.Right, -- the cylinder's X axis points up
		SpreadAngle = Vector2.new(8, 8),
		LightEmission = 1,
	})
	pointLight(glow, color, 1.5, 18)

	-- the arrow: its tip stays above a player's head on the pad (~GROUND_Y + 6.4)
	local arrow = sellArrow(pad, at(9.6), LEAF)
	pointLight(arrow:FindFirstChild("Shaft") :: BasePart, LEAF, 1, 12)

	-- the sign on two posts, Ink feet and glowing caps
	local sign = at(0) + SELL_SIGN
	local front = CFrame.new(sign) * facing(0, 1)
	for _, side in { -1, 1 } do
		local post = (front * CFrame.new(side * 3.7, 0, 0)).Position
		cylinder({ Name = "SignFoot", Position = post + Vector3.new(0, 0.2, 0), Height = 1.4, Diameter = 2.3, Color = INK, Parent = pad })
		cylinder({ Name = "SignPost", Position = post + Vector3.new(0, 7.2, 0), Height = 12.8, Diameter = 1.15, Color = BODY, Parent = pad })
		ball(post + Vector3.new(0, 13.9, 0), 1.9, color, { Name = "SignCap", Material = M.Neon, CanCollide = false, CastShadow = false, Parent = pad })
	end
	signBoard(pad, "Sign", front * CFrame.new(0, 10.3, -0.75), 10.6, 4, "⚡ SELL", LEAF, { Enum.NormalId.Front }, 30)
	signBoard(pad, "Hint", front * CFrame.new(0, 7.15, -0.75), 9.4, 1.9, "STAND ON THE PAD", INK, { Enum.NormalId.Front }, 30)
	return pad
end

-- The Weather Lab building behind a sell pad, the sell machine beside it and a sign
local function weatherLab(parent: Instance, position: Vector3, scale: number, paints)
	local lab = model("Weather Lab", parent)
	local base = CFrame.new(position.X, GROUND_Y, position.Z) * facing(0, 1) -- the open front faces the path
	place("WeatherLab", lab, base, { Scale = scale, Paints = paints or { Primary = BOLT, Secondary = SKY_DEEP }, Collide = true })
	signBoard(lab, "Sign", base * CFrame.new(0, 15.8 * scale, -9.4 * scale), 15 * scale, 3.4 * scale, "⚡ WEATHER LAB", BOLT_DEEP, { Enum.NormalId.Front }, 26)
	return lab
end

local function sellStation(parent: Instance, zoneId: number, biome)
	local pad = MapLayout.SellPad(zoneId)
	sellPad(parent, pad, BOLT)
	weatherLab(parent, pad + Vector3.new(0, 0, -26), if zoneId == 0 then 1 else 0.92, nil)
	place("SellMachine", parent, CFrame.new(pad.X + SELL_MACHINE.X, GROUND_Y, pad.Z + SELL_MACHINE.Z) * facing(0, 1), { Scale = 1.05, Collide = true })
end

-- The egg's name and price above the incubator: a sign sized in studs on a still anchor (the egg
-- itself spins and bobs) whose bottom edge stays above the glass dome, so the price is never behind it.
local VOLTS_IMAGE = "rbxassetid://124885999776457" -- the Volts coin (Icons.Volts in src/client/UI/Icons.luau)
local EGG_DOME_TOP = 17.6 -- studs above the ground: EggIncubator (12.9 tall) at Scale 1.35
local EGG_SIGN = Vector2.new(15, 5.7) -- studs

local function inkPill(parent: Instance, name: string, position: UDim2, size: UDim2, face: Color3, faceBottom: Color3, inset: Vector2)
	local outline = Instance.new("Frame")
	outline.Name = name
	outline.AnchorPoint = Vector2.new(0.5, 0)
	outline.Position = position
	outline.Size = size
	outline.BackgroundColor3 = INK
	outline.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = outline
	local inner = Instance.new("Frame")
	inner.Name = "Face"
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.fromScale(1 - inset.X * 2, 1 - inset.Y * 2)
	inner.BackgroundColor3 = WHITE
	inner.BorderSizePixel = 0
	corner:Clone().Parent = inner
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(face, faceBottom)
	gradient.Rotation = 90
	gradient.Parent = inner
	inner.Parent = outline
	outline.Parent = parent
	return inner
end

local function eggSign(parent: Instance, position: Vector3, egg)
	local anchor = deco({
		Name = "EggSign",
		Size = Vector3.one,
		CFrame = CFrame.new(position.X, GROUND_Y + EGG_DOME_TOP + 0.6 + EGG_SIGN.Y / 2, position.Z),
		Transparency = 1,
		Parent = parent,
	})
	local gui = Instance.new("BillboardGui")
	gui.Name = "EggSign"
	gui.Size = UDim2.fromScale(EGG_SIGN.X, EGG_SIGN.Y)
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.Adornee = anchor
	gui.Parent = anchor

	-- Name plate: a white pill with an Ink outline (0.18 studs) and the name in Ink
	local nameHeight = 3.1
	local plate = inkPill(gui, "Name", UDim2.fromScale(0.5, 0), UDim2.fromScale(1, nameHeight / EGG_SIGN.Y), WHITE, BODY, Vector2.new(0.18 / EGG_SIGN.X, 0.18 / nameHeight))
	textLabel(plate, {
		Text = egg.Name,
		TextColor3 = INK,
		Size = UDim2.fromScale(0.88, 0.72),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Stroke = false,
	})

	-- Price capsule under it: the Volts coin and the cost on a Bolt-yellow pill
	local priceWidth, priceHeight = 6.8, 2.3
	local price = inkPill(gui, "Price", UDim2.fromScale(0.5, (EGG_SIGN.Y - priceHeight) / EGG_SIGN.Y), UDim2.fromScale(priceWidth / EGG_SIGN.X, priceHeight / EGG_SIGN.Y), BOLT, BOLT_DEEP, Vector2.new(0.16 / priceWidth, 0.16 / priceHeight))
	local coin = Instance.new("ImageLabel")
	coin.Name = "Coin"
	coin.BackgroundTransparency = 1
	coin.Image = VOLTS_IMAGE
	coin.ScaleType = Enum.ScaleType.Fit
	coin.AnchorPoint = Vector2.new(0, 0.5)
	coin.Position = UDim2.fromScale(0.04, 0.5)
	coin.Size = UDim2.fromScale(0.3, 1.25)
	coin.Parent = price
	textLabel(price, {
		Text = Format.Number(egg.Cost),
		Size = UDim2.fromScale(0.6, 0.78),
		Position = UDim2.fromScale(0.36, 0.5),
		AnchorPoint = Vector2.new(0, 0.5),
		Stroke = 2,
	})
end

local function eggStation(parent: Instance, zoneId: number)
	local zone = Zones[zoneId]
	local eggId = zone.Egg
	local egg = Pets.Eggs[eggId]
	local position = MapLayout.EggStation(zoneId)
	local station = model(egg.Name .. " Station", parent)

	place("EggIncubator", station, CFrame.new(position.X, GROUND_Y, position.Z) * facing(0, -1), {
		Scale = 1.35,
		Paints = { Primary = BODY, Secondary = egg.Accent },
		Collide = true,
	})
	cylinder({ Name = "Pad", Position = Vector3.new(position.X, GROUND_Y + 0.05, position.Z), Height = 0.3, Diameter = 22, Color = shade(BIOMES[zoneId].Field, 1.04), CanCollide = false, CastShadow = false, Parent = station })
	for index = 0, 3 do
		local angle = math.rad(45 + index * 90)
		lamp(station, position + Vector3.new(math.cos(angle) * 11.5, 0, math.sin(angle) * 11.5), position, { Primary = INK_SOFT, Secondary = egg.Accent }, 0.85)
	end

	local eggModel = EggModels.Build(eggId, 8)
	eggModel:PivotTo(CFrame.new(position + Vector3.new(0, 8.2, 0)))
	eggModel.Parent = station
	CollectionService:AddTag(eggModel, "Spin")
	eggModel:SetAttribute("SpinSpeed", 0.5)
	eggModel:SetAttribute("BobHeight", 0.6)

	eggSign(station, position, egg)

	local host = promptHost(station, position + Vector3.new(0, 4, 0))
	local instance = prompt(host, "Open Egg", egg.Name, 0, 16)
	instance:SetAttribute("EggId", eggId)
end

-- Translucent blue ring with cool mist: a safe spot from Ashfall Volcano's heat (HazardService)
local function coolingArea(parent: Instance, position: Vector3, radius: number)
	local area = model("CoolingArea", parent)
	local color = rgb(110, 200, 255)
	local ghost = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
	local function props(extra)
		for key, value in ghost do
			extra[key] = value
		end
		extra.Parent = area
		return extra
	end
	local y = GROUND_Y
	local floor = cylinder(props({ Name = "CoolFloor", Position = Vector3.new(position.X, y + 0.14, position.Z), Height = 0.16, Diameter = radius * 2, Color = color, Material = M.Neon, Transparency = 0.86 }))
	local segments = 20
	local length = 2 * radius * math.sin(math.pi / segments) + 0.3
	for index = 1, segments do
		local angle = index / segments * math.pi * 2
		local point = Vector3.new(position.X + math.cos(angle) * radius, y + 0.3, position.Z + math.sin(angle) * radius)
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		part(props({ Name = "CoolRing", Size = Vector3.new(0.8, 0.4, length), CFrame = CFrame.lookAt(point, point + tangent), Color = color, Material = M.Neon, Transparency = 0.2 }))
	end
	emitter(floor, {
		Texture = SMOKE,
		Color = ColorSequence.new(rgb(205, 238, 255)),
		Size = NumberSequence.new(3, 7),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.78), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(3, 4.5),
		Rate = 5,
		Speed = NumberRange.new(1, 2.5),
		EmissionDirection = Enum.NormalId.Right, -- the cylinder's X axis points up
		SpreadAngle = Vector2.new(25, 25),
		RotSpeed = NumberRange.new(-20, 20),
	})
	emitter(floor, {
		Texture = SPARKLE,
		Color = ColorSequence.new(rgb(170, 225, 255)),
		Size = NumberSequence.new(0.45, 0),
		Lifetime = NumberRange.new(1.5, 2.5),
		Rate = 6,
		Speed = NumberRange.new(2, 4),
		EmissionDirection = Enum.NormalId.Right,
		LightEmission = 1,
	})

	-- the label hangs over the ring's edge toward the main path (a station's path), not in its buildings
	-- (at the sell pad, +X is inside the sell machine)
	local side = if math.abs(position.Z) > 1 then Vector3.new(0, 0, -math.sign(position.Z)) else Vector3.xAxis
	local anchor = part(props({ Name = "SignAnchor", Size = Vector3.one, CFrame = CFrame.new(Vector3.new(position.X, 3.5, position.Z) + side * radius), Transparency = 1 }))
	local gui = billboard(anchor, UDim2.fromOffset(170, 36), Vector3.zero, 90)
	textLabel(gui, { Text = "❄️ COOL ZONE", TextColor3 = rgb(170, 225, 255) })
end

-- The ZoneGate arch over the path at x, its sign facing both ways
local function arch(parent: Instance, x: number, title: string, paints): Model
	local gateArch = model("Arch", parent)
	local base = CFrame.new(x, GROUND_Y, 0) * facing(-1, 0) -- the arch spans Z, its front faces the way players come from
	place("ZoneGate", gateArch, base, { Paints = paints, Collide = true })
	signBoard(gateArch, "Sign", base * CFrame.new(0, 24, 0), 25, 5.4, title, paints.Secondary, { Enum.NormalId.Front, Enum.NormalId.Back }, 24, 8.6)
	-- keeps the 2-stud gaps between the gate's force fields and the door closed whatever the pillars' shape
	for _, side in { -1, 1 } do
		part({ Name = "GatePost", Size = Vector3.new(1.5, 28, 3), CFrame = CFrame.new(x, GROUND_Y + 14, side * 17), Transparency = 1, CanQuery = false, CanTouch = false, CastShadow = false, Parent = gateArch })
	end
	return gateArch
end

local function gatePaints(zone)
	return { Primary = BODY, Secondary = zone.Color, Tertiary = shade(zone.Color, 0.7) }
end

local function gate(parent: Instance, zoneId: number)
	local zone = Zones[zoneId]
	local x = MapLayout.ZoneStart(zoneId)
	local gateModel = model("Gate" .. zoneId, parent)
	arch(gateModel, x, zone.Icon .. " " .. string.upper(zone.Name), gatePaints(zone))

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

	part({
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

	-- the price and the Power it needs are on the prompt's zone card (client PromptController), so the
	-- door has no billboard of its own
	local host = promptHost(gateModel, Vector3.new(x - 1.5, 4, 0))
	local instance = prompt(host, "Unlock", zone.Name .. "  •  ⚡" .. Format.Number(zone.Cost), 0.5, 16)
	instance:SetAttribute("GateZone", zoneId)
	CollectionService:AddTag(instance, "GatePrompt")
	CollectionService:AddTag(host, "ZoneBarrier")
	host:SetAttribute("Zone", zoneId)
end

-- A sign post with a big label on its board
local function signPost(parent: Instance, position: Vector3, toward: Vector3, text: string, color: Color3, scale: number?)
	local size = scale or 1.4
	local base = CFrame.new(position.X, GROUND_Y, position.Z) * facing(toward.X, toward.Z)
	place("SignPost", parent, base, { Scale = size, Paints = { Primary = hex("A8724C"), Secondary = color } })
	signBoard(parent, "SignText", base * CFrame.new(0, 6 * size, -0.45 * size), 5.4 * size, 2.8 * size, text, color, { Enum.NormalId.Front }, 30)
end

---------------------------------------------------------------------------
-- Decoration
---------------------------------------------------------------------------
-- Keeps decoration apart and out of the way: `blocks` are rectangles { x0, x1, z0, z1 } and circles
-- { x, z, r } where nothing may stand; placed things keep their radius free
local function dresser(parent: Instance, regionId: number, seed: number, blocks)
	local d = { Parent = parent, Biome = BIOMES[regionId], Rng = Random.new(seed), Taken = {}, Blocks = blocks, Hills = {} }
	local rng = d.Rng

	-- Height of the hills above the ground at (x, z): props there stand on the hill
	function d.Height(x: number, z: number): number
		local best = 0
		for _, hill in d.Hills do
			local distance2 = (x - hill[1]) ^ 2 + (z - hill[3]) ^ 2
			if distance2 < hill[4] ^ 2 then
				best = math.max(best, hill[2] + math.sqrt(hill[4] ^ 2 - distance2) - GROUND_Y)
			end
		end
		return best
	end

	function d.Free(x: number, z: number, radius: number): boolean
		for _, block in blocks do
			if #block == 4 then
				if x > block[1] - radius and x < block[2] + radius and z > block[3] - radius and z < block[4] + radius then
					return false
				end
			elseif (x - block[1]) ^ 2 + (z - block[2]) ^ 2 < (block[3] + radius) ^ 2 then
				return false
			end
		end
		for _, other in d.Taken do
			if (x - other[1]) ^ 2 + (z - other[2]) ^ 2 < (other[3] + radius) ^ 2 then
				return false
			end
		end
		return true
	end

	function d.Take(x: number, z: number, radius: number)
		table.insert(d.Taken, { x, z, radius })
	end

	-- Places `build(position, side)` at random spots in x0..x1 with |z| in zMin..zMax (both sides)
	function d.Scatter(count: number, x0: number, x1: number, zMin: number, zMax: number, radius: number, build)
		local placed, tries = 0, 0
		while placed < count and tries < count * 25 do
			tries += 1
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			local x, z = rng:NextNumber(x0, x1), side * rng:NextNumber(zMin, zMax)
			if d.Free(x, z, radius) then
				d.Take(x, z, radius)
				build(Vector3.new(x, GROUND_Y, z), side)
				placed += 1
			end
		end
	end

	-- A jittered row along x on both sides (the island edges)
	function d.Row(x0: number, x1: number, step: number, zMin: number, zMax: number, radius: number, build)
		for _, side in { -1, 1 } do
			local x = x0 + rng:NextNumber(0, step * 0.5)
			while x < x1 do
				local px = x + rng:NextNumber(-step * 0.2, step * 0.2)
				local z = side * rng:NextNumber(zMin, zMax)
				if d.Free(px, z, radius) then
					d.Take(px, z, radius)
					build(Vector3.new(px, GROUND_Y, z), side)
				end
				x += step * rng:NextNumber(0.85, 1.15)
			end
		end
	end

	-- A prop on the ground (or on a hill), turned toward the middle of the island with a little random yaw
	function d.Prop(id: string, position: Vector3, side: number, options, wobble: number?)
		local turn = (if side < 0 then math.pi else 0) + rng:NextNumber(-1, 1) * (wobble or 0.6)
		local lift = d.Height(position.X, position.Z)
		if lift > 0 then
			position += Vector3.new(0, lift - 0.4, 0)
		end
		return place(id, parent, CFrame.new(position) * CFrame.Angles(0, turn, 0), options)
	end

	function d.Tree(position: Vector3, side: number, scale: number?, collide: boolean?)
		local paints = d.Biome.Trees[rng:NextInteger(1, #d.Biome.Trees)]
		local id = if rng:NextNumber() < 0.55 then "TreeRound" else "TreeTall"
		return d.Prop(id, position, side, { Scale = scale or rng:NextNumber(1.1, 1.6), Paints = paints, Collide = collide or false }, math.pi)
	end

	return d
end

-- The usual keep-out areas of a zone: path, field, gates, spawn, sell station and egg station
local function zoneBlocks(zoneId: number)
	local x0, x1 = MapLayout.ZoneStart(zoneId), MapLayout.ZoneEnd(zoneId)
	local minX, maxX, minZ, maxZ = MapLayout.FieldBounds(zoneId)
	local sell, egg = MapLayout.SellPad(zoneId), MapLayout.EggStation(zoneId)
	return {
		{ x0 - 400, x1 + 400, -PATH_HALF - 3, PATH_HALF + 3 }, -- the main path
		{ minX - 2, maxX + 2, minZ - 2, maxZ + 2 }, -- the weather field
		{ x0 - 24, x0 + 24, -26, 26 }, -- this zone's gate
		{ x1 - 24, x1 + 24, -26, 26 }, -- the next gate
		{ x0 + 26, 0, 14 }, -- spawn
		{ sell.X - 22, sell.X + 26, sell.Z - 42, sell.Z + 12 }, -- sell pad, Weather Lab and sell machine
		{ sell.X - 7, sell.X + 7, sell.Z, 0 }, -- path to the sell pad
		{ egg.X, egg.Z, 16 }, -- egg incubator
		{ egg.X - 7, egg.X + 7, 0, egg.Z }, -- path to the egg incubator
		{ x0 - 400, x1 + 400, -MapLayout.HalfWidth - 3, -MapLayout.HalfWidth + 1 }, -- the boundary lines
		{ x0 - 400, x1 + 400, MapLayout.HalfWidth - 1, MapLayout.HalfWidth + 3 },
	}
end

local BAND_NEAR = MapLayout.HalfWidth + 4 -- beyond the boundary
local BAND_FAR = EDGE - 6

-- Rolling hills (dunes, snowdrifts) just beyond the boundaries: big balls sunk into the ground so only a
-- soft cap shows. Placed before the edge rows, which then fill the gaps between them.
local function hills(d, x0: number, x1: number, step: number)
	local rng = d.Rng
	local biome = d.Biome
	for _, side in { -1, 1 } do
		local x = x0 + rng:NextNumber(4, step)
		while x < x1 - 8 do
			local radius = rng:NextNumber(10.5, 14)
			local height = rng:NextNumber(4.5, 7)
			local foot = math.sqrt(radius ^ 2 - (radius - height) ^ 2)
			local z = side * (MapLayout.HalfWidth + 3 + foot)
			-- the part of the ball under the ground stays behind the cliffs
			if math.abs(z) + radius < EDGE - 1 and d.Free(x, z, 2) then
				local y = GROUND_Y + height - radius
				deco({
					Name = "Hill",
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * radius * 2,
					CFrame = CFrame.new(x, y, z),
					Color = biome.Hills[rng:NextInteger(1, #biome.Hills)],
					CastShadow = true,
					Parent = d.Parent,
				})
				table.insert(d.Hills, { x, y, z, radius })
			end
			x += step * rng:NextNumber(0.8, 1.3)
		end
	end
end

-- Trees, bushes and rocks packed along the island edges beyond the boundaries, plus a looser fringe
-- inside them, so every view is framed
local function edgeGreenery(d, x0: number, x1: number, options)
	options = options or {}
	local rng = d.Rng
	local biome = d.Biome
	hills(d, x0, x1, options.HillStep or 46)
	-- canopies may overlap a little: the rows keep trunks ~8 studs apart
	d.Row(x0, x1, options.FrontStep or 9, BAND_NEAR + 2.5, BAND_NEAR + 9, 3.6, options.Front or function(position, side)
		d.Tree(position, side, rng:NextNumber(1.2, 1.7))
	end)
	d.Row(x0, x1, options.BackStep or 11, BAND_NEAR + 13, BAND_FAR, 4.2, options.Back or function(position, side)
		d.Tree(position, side, rng:NextNumber(1.4, 2))
	end)
	d.Row(x0, x1, 8, BAND_NEAR - 1, BAND_FAR, 2.4, options.Filler or function(position, side)
		d.Prop("BushRound", position, side, { Scale = rng:NextNumber(1.2, 1.8), Paints = biome.Bush, Collide = false }, math.pi)
	end)
end

local function rocks(d, count: number, x0: number, x1: number, zMin: number, zMax: number)
	local rng = d.Rng
	d.Scatter(count, x0, x1, zMin, zMax, 5, function(position, side)
		d.Prop(if rng:NextNumber() < 0.65 then "RockCluster" else "RockTall", position, side, { Scale = rng:NextNumber(0.9, 1.5), Paints = d.Biome.Stone }, math.pi)
	end)
end

local function flowers(d, count: number, x0: number, x1: number, zMin: number, zMax: number, colors)
	local rng = d.Rng
	d.Scatter(count, x0, x1, zMin, zMax, 3.2, function(position, side)
		local petals = colors[rng:NextInteger(1, #colors)]
		d.Prop("FlowerPatch", position, side, { Scale = rng:NextNumber(0.9, 1.3), Paints = { Primary = shade(d.Biome.Ground, 0.92), Secondary = petals[1], Tertiary = petals[2] } }, math.pi)
	end)
end

local function tufts(d, count: number, x0: number, x1: number, zMin: number, zMax: number, color: Color3)
	local rng = d.Rng
	d.Scatter(count, x0, x1, zMin, zMax, 1.2, function(position, side)
		d.Prop("GrassTuft", position, side, { Scale = rng:NextNumber(1.2, 1.8), Paints = { Primary = color } }, math.pi)
	end)
end

-- Soft round patches a shade lighter than the ground in the gaps left between props (placed last, so
-- they only fill empty ground), so the flat biome colour has a little texture from above
local function patches(d, count: number, x0: number, x1: number, zMin: number, zMax: number)
	local rng = d.Rng
	local color = d.Biome.Ground:Lerp(d.Biome.Field, 0.45)
	d.Scatter(count, x0, x1, zMin, zMax, 7.5, function(position)
		local diameter = rng:NextNumber(10, 17)
		cylinder({
			Name = "Patch",
			Position = Vector3.new(position.X, GROUND_Y + 0.02, position.Z),
			Height = 0.08,
			Diameter = diameter,
			Color = color,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = d.Parent,
		})
		cylinder({
			Name = "Patch",
			Position = Vector3.new(position.X + diameter * 0.42, GROUND_Y + 0.02, position.Z + rng:NextNumber(-3, 3)),
			Height = 0.08,
			Diameter = diameter * 0.55,
			Color = color,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = d.Parent,
		})
	end)
end

-- A small floating island drifting over the cloud sea (tag "Bob")
-- `top(island, position)` can put something on its flat top (inside the island model, so it bobs along)
local function floatingIsland(parent: Instance, position: Vector3, scale: number, paints, rng, top)
	local island = place("FloatingIsland", parent, CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), { Scale = scale, Paints = paints, Collide = false, CastShadow = false })
	if top then
		top(island, position + Vector3.new(0, 10 * scale, 0))
	end
	CollectionService:AddTag(island, "Bob")
	island:SetAttribute("BobHeight", rng:NextNumber(1.5, 3))
	island:SetAttribute("BobSpeed", rng:NextNumber(0.35, 0.7))
	return island
end

-- A big island beside the main one carrying a landmark (its flat top at `topY`)
local function satellite(parent: Instance, x: number, z: number, topY: number, diameter: number, biome)
	local scale = diameter / 16
	return place("FloatingIsland", parent, CFrame.new(x, topY - 10 * scale, z), {
		Scale = scale,
		Paints = { Primary = biome.Ground, Secondary = biome.Rock, Tertiary = biome.Band },
		Collide = false,
		CastShadow = false,
	})
end

local function addSteam(target: Instance)
	local vent = pieceOf(target, "Neon_") or target:FindFirstChildWhichIsA("BasePart")
	if vent then
		emitter(vent, {
			Texture = SMOKE,
			Color = ColorSequence.new(rgb(235, 225, 225)),
			Size = NumberSequence.new(2, 7),
			Transparency = NumberSequence.new(0.5, 1),
			Lifetime = NumberRange.new(2, 3),
			Rate = 4,
			Speed = NumberRange.new(5, 8),
			EmissionDirection = upFace(vent),
			SpreadAngle = Vector2.new(12, 12),
			RotSpeed = NumberRange.new(-30, 30),
		})
	end
end

local function lavaPool(parent: Instance, position: Vector3, diameter: number)
	cylinder({ Name = "PoolRim", Position = Vector3.new(position.X, GROUND_Y + 0.15, position.Z), Height = 0.6, Diameter = diameter + 3, Color = hex("4E2C29"), CanCollide = false, CastShadow = false, Parent = parent })
	local lava = cylinder({ Name = "Lava", Position = Vector3.new(position.X, GROUND_Y + 0.3, position.Z), Height = 0.6, Diameter = diameter, Color = hex("FF7A2E"), Material = M.Neon, CanCollide = false, CanQuery = false, CastShadow = false, Parent = parent, Tags = { "Pulse" } })
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

-- Bigger props scattered over each zone's plaza (between the gate and the field)
local PLAZA_FEATURES = {
	Meadows = {
		Count = 10,
		Place = function(d, position, side, rng)
			d.Tree(position, side, rng:NextNumber(1, 1.4))
		end,
	},
	Thunder = {
		Count = 9,
		Place = function(d, position, side, rng)
			if rng:NextNumber() < 0.5 then
				d.Tree(position, side, rng:NextNumber(1, 1.4))
			else
				d.Prop("CrystalCluster", position, side, { Scale = rng:NextNumber(1.3, 1.8), Paints = { Primary = if rng:NextNumber() < 0.5 then STORM else BOLT, Secondary = d.Biome.Rock } }, math.pi)
			end
		end,
	},
	Dunes = {
		Count = 10,
		Place = function(d, position, side, rng)
			if rng:NextNumber() < 0.5 then
				d.Prop("TreePalm", position, side, { Scale = rng:NextNumber(1.1, 1.4), Paints = d.Biome.Trees[1], Collide = false }, math.pi)
			else
				d.Prop("RockTall", position, side, { Scale = rng:NextNumber(1, 1.4), Paints = d.Biome.Stone }, math.pi)
			end
		end,
	},
	Frost = {
		Count = 10,
		Place = function(d, position, side, rng)
			if rng:NextNumber() < 0.6 then
				d.Prop("TreePine", position, side, { Scale = rng:NextNumber(1, 1.4), Paints = d.Biome.Trees[rng:NextInteger(1, #d.Biome.Trees)], Collide = false }, math.pi)
			else
				d.Prop("CrystalCluster", position, side, { Scale = rng:NextNumber(1.3, 1.8), Paints = { Primary = SKY, Secondary = hex("D3EBFF") } }, math.pi)
			end
		end,
	},
	Volcano = {
		Count = 9,
		Place = function(d, position, side, rng)
			if rng:NextNumber() < 0.5 then
				d.Prop("LavaSpire", position, side, { Scale = rng:NextNumber(1, 1.4), Paints = { Primary = d.Biome.Band } }, math.pi)
			else
				d.Prop("CrystalCluster", position, side, { Scale = rng:NextNumber(1.2, 1.7), Paints = { Primary = hex("FF8A3D"), Secondary = d.Biome.Band } }, math.pi)
			end
		end,
	},
	Sky = {
		Count = 9,
		Place = function(d, position, side, rng)
			d.Tree(position, side, rng:NextNumber(1, 1.4), true)
		end,
	},
}

local Decor = {}

function Decor.Meadows(d, zoneId: number)
	local x0, x1 = regionBounds(zoneId)
	local rng = d.Rng
	local parent = d.Parent
	local biome = d.Biome

	-- the windmill farm on the south edge
	local mill = CFrame.new(x0 + 206, GROUND_Y, 136)
	place("Windmill", parent, mill, { Scale = 1.15, Paints = { Primary = CORAL, Secondary = SUNSET }, Collide = true })
	local blades = place("WindmillBlades", parent, mill * CFrame.new(0, 20 * 1.15, -6.4 * 1.15), { Scale = 1.15, Paints = { Primary = hex("FFF6E6"), Secondary = CORAL }, Collide = false })
	CollectionService:AddTag(blades, "Spin")
	blades:SetAttribute("SpinAxis", "Z")
	blades:SetAttribute("SpinSpeed", 0.7)
	d.Take(x0 + 206, 136, 12)
	local mill2 = CFrame.new(x0 + 92, GROUND_Y, -138) * facing(0, 1)
	place("Windmill", parent, mill2, { Scale = 0.9, Paints = { Primary = SKY, Secondary = BOLT }, Collide = true })
	local blades2 = place("WindmillBlades", parent, mill2 * CFrame.new(0, 20 * 0.9, -6.4 * 0.9), { Scale = 0.9, Paints = { Primary = hex("FFF6E6"), Secondary = SKY }, Collide = false })
	CollectionService:AddTag(blades2, "Spin")
	blades2:SetAttribute("SpinAxis", "Z")
	blades2:SetAttribute("SpinSpeed", 0.9)
	d.Take(x0 + 92, -138, 10)
	for _, spot in { { 186, 128, 0.3 }, { 194, 140, 1.2 }, { 228, 130, -0.4 }, { 104, -128, 0.8 }, { 78, -130, 2 } } do
		place("HayBale", parent, CFrame.new(x0 + spot[1], GROUND_Y, spot[2]) * CFrame.Angles(0, spot[3], 0), { Scale = 1.3, Collide = true })
		d.Take(x0 + spot[1], spot[2], 4)
	end
	-- picket fences along the field edges, broken into short runs
	for _, side in { -1, 1 } do
		local x = x0 + 104
		while x < x0 + 296 do
			local run = rng:NextInteger(3, 5)
			for index = 0, run - 1 do
				local fx = x + index * 10.2 + 5
				if fx < x0 + 296 then
					place("Fence", parent, CFrame.new(fx, GROUND_Y, side * 117.5) * facing(0, -side), { Paints = { Primary = hex("FFF6E6"), Secondary = SKY }, Collide = false })
					d.Take(fx, side * 117.5, 5)
				end
			end
			x += run * 10.2 + rng:NextNumber(14, 26)
		end
	end

	edgeGreenery(d, x0, x1)
	rocks(d, 10, x0 + 4, x1 - 4, 60, 116)
	flowers(d, 26, x0 + 4, x1 - 4, 14, 116, { { hex("FF7AA8"), WHITE }, { BOLT, hex("FF9F5A") }, { hex("B69CFF"), WHITE }, { CORAL, hex("FFE6A8") } })
	d.Scatter(10, x0 + 4, x1 - 4, 20, 116, 3, function(position, side)
		d.Prop("Mushroom", position, side, { Scale = rng:NextNumber(0.9, 1.4), Paints = { Primary = if rng:NextNumber() < 0.6 then CORAL else hex("FF9F5A") } }, math.pi)
	end)
	tufts(d, 40, x0 + 4, x1 - 4, 12, 118, hex("4CC94A"))
	d.Scatter(8, x0 + 4, x1 - 4, 30, 116, 4, function(position, side)
		d.Prop("BushRound", position, side, { Scale = rng:NextNumber(1, 1.5), Paints = biome.Bush, Collide = false }, math.pi)
	end)
end

function Decor.Thunder(d, zoneId: number)
	local x0, x1 = regionBounds(zoneId)
	local rng = d.Rng
	local parent = d.Parent
	local biome = d.Biome
	local teslaPaints = { Primary = hex("4A4FA8"), Secondary = SUNSET }
	for _, spot in { { 206, -136, 1.35 }, { 96, 136, 1.1 }, { 300, 138, 1 } } do
		local tower = place("TeslaTower", parent, CFrame.new(x0 + spot[1], GROUND_Y, spot[2]) * facing(0, -math.sign(spot[2])), { Scale = spot[3], Paints = teslaPaints, Collide = true })
		local orb = pieceOf(tower, "Neon_")
		if orb then
			CollectionService:AddTag(orb, "TeslaOrb")
			pointLight(orb, rgb(158, 232, 255), 2.5, 40)
			emitter(orb, {
				Texture = SPARKLE,
				Color = ColorSequence.new(rgb(200, 245, 255)),
				Size = NumberSequence.new(1.2, 0),
				Lifetime = NumberRange.new(0.15, 0.3),
				Rate = 25,
				Speed = NumberRange.new(14, 20),
				SpreadAngle = Vector2.new(180, 180),
				LightEmission = 1,
			})
		end
		d.Take(x0 + spot[1], spot[2], 7 * spot[3])
	end
	-- storm clouds over the island edges, their bolts striking tall lightning rods
	local ROD_SCALE, ROD_HEIGHT = 1.8, 10.3
	for _, spot in { { 40, 134 }, { 150, -134 }, { 250, 132 }, { 282, -136 }, { 118, 138 } } do
		local base = CFrame.new(x0 + spot[1], GROUND_Y, spot[2]) * facing(0, -math.sign(spot[2]))
		local rod = place("LightningRod", parent, base, { Scale = ROD_SCALE, Paints = { Primary = hex("A3A9DE") }, Collide = true })
		local cloud = place("StormCloud", parent, base * CFrame.new(0, ROD_HEIGHT * ROD_SCALE + 0.4, 0), {
			Scale = 2.2,
			Paints = { Primary = hex("8E87D9"), Secondary = hex("6F68C2") },
			Collide = false,
		})
		for _, target in { rod, cloud } do
			local glow = pieceOf(target, "Neon_")
			if glow then
				CollectionService:AddTag(glow, "Flicker")
			end
		end
		d.Take(x0 + spot[1], spot[2], 6)
	end

	edgeGreenery(d, x0, x1, {
		Back = function(position, side)
			if rng:NextNumber() < 0.25 then
				d.Prop("CrystalCluster", position, side, { Scale = rng:NextNumber(1.6, 2.4), Paints = { Primary = STORM, Secondary = biome.Rock } }, math.pi)
			else
				d.Tree(position, side, rng:NextNumber(1.4, 2))
			end
		end,
	})
	d.Scatter(14, x0 + 4, x1 - 4, 30, 118, 4, function(position, side)
		d.Prop("CrystalCluster", position, side, { Scale = rng:NextNumber(1, 1.6), Paints = { Primary = if rng:NextNumber() < 0.6 then STORM else BOLT, Secondary = biome.Rock } }, math.pi)
	end)
	d.Scatter(10, x0 + 30, x1 - 10, 101, 116, 3, function(position, side)
		local rod = d.Prop("LightningRod", position, side, { Scale = 1.3, Paints = { Primary = hex("A3A9DE") } }, math.pi)
		local tip = pieceOf(rod, "Neon_")
		if tip then
			CollectionService:AddTag(tip, "Flicker")
		end
	end)
	rocks(d, 16, x0 + 4, x1 - 4, 20, 118)
	tufts(d, 30, x0 + 4, x1 - 4, 12, 118, hex("6A62D8"))
end

function Decor.Dunes(d, zoneId: number)
	local x0, x1 = regionBounds(zoneId)
	local rng = d.Rng
	local parent = d.Parent
	local biome = d.Biome
	local palm = biome.Trees[1]

	place("Pyramid", parent, CFrame.new(x0 + 196, GROUND_Y, 137) * facing(0, -1), { Scale = 1, Collide = true })
	d.Take(x0 + 196, 137, 20)
	place("Pyramid", parent, CFrame.new(x0 + 232, GROUND_Y, 141) * facing(0, -1), { Scale = 0.6, Paints = { Primary = hex("FFD27A"), Secondary = hex("F2A65A") }, Collide = true })
	d.Take(x0 + 232, 141, 12)
	place("SandArch", parent, CFrame.new(x0 + 128, GROUND_Y, -137) * facing(0, 1), { Scale = 1.15, Collide = true })
	d.Take(x0 + 128, -137, 14)
	place("SandArch", parent, CFrame.new(x0 + 64, GROUND_Y, 136) * facing(0, -1), { Scale = 0.85, Collide = true })
	d.Take(x0 + 64, 136, 11)
	-- an oasis by the field with palms around it
	local oasis = Vector3.new(x0 + 172, GROUND_Y, -109)
	place("OasisPool", parent, CFrame.new(oasis), { Scale = 1, Collide = false })
	d.Take(oasis.X, oasis.Z, 9)
	for index = 0, 4 do
		local angle = index / 5 * math.pi * 2 + 0.4
		local spot = Vector3.new(oasis.X + math.cos(angle) * 11.5, GROUND_Y, oasis.Z + math.sin(angle) * 9)
		if spot.Z > -MapLayout.HalfWidth + 2 and spot.Z < -100 or spot.Z < -MapLayout.HalfWidth - 4 then
			place("TreePalm", parent, CFrame.new(spot) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), { Scale = rng:NextNumber(1.1, 1.4), Paints = palm, Collide = false })
		end
	end

	edgeGreenery(d, x0, x1, {
		HillStep = 34,
		FrontStep = 8,
		Front = function(position, side)
			if rng:NextNumber() < 0.6 then
				d.Prop("TreePalm", position, side, { Scale = rng:NextNumber(1.2, 1.6), Paints = palm, Collide = false }, math.pi)
			else
				d.Prop("Cactus", position, side, { Scale = rng:NextNumber(1.3, 1.8), Collide = false }, math.pi)
			end
		end,
		Back = function(position, side)
			if rng:NextNumber() < 0.3 then
				d.Prop("RockTall", position, side, { Scale = rng:NextNumber(1.4, 2.2), Paints = biome.Stone, Collide = false }, math.pi)
			else
				d.Prop("TreePalm", position, side, { Scale = rng:NextNumber(1.4, 1.9), Paints = palm, Collide = false }, math.pi)
			end
		end,
		Filler = function(position, side)
			d.Prop("RockCluster", position, side, { Scale = rng:NextNumber(0.6, 1), Paints = biome.Stone, Collide = false }, math.pi)
		end,
	})
	d.Scatter(26, x0 + 4, x1 - 4, 22, 117, 3.5, function(position, side)
		d.Prop("Cactus", position, side, { Scale = rng:NextNumber(0.9, 1.4), Paints = { Primary = hex("4CB860"), Secondary = if rng:NextNumber() < 0.5 then hex("FF7AA8") else BOLT } }, math.pi)
	end)
	rocks(d, 14, x0 + 4, x1 - 4, 20, 118)
	tufts(d, 20, x0 + 4, x1 - 4, 14, 118, hex("C9B85A"))
end

function Decor.Frost(d, zoneId: number)
	local x0, x1 = regionBounds(zoneId)
	local rng = d.Rng
	local parent = d.Parent
	local biome = d.Biome
	local ice = { Primary = hex("BFE6FF"), Secondary = hex("7FC4F5") }

	for _, spot in { { 232, -138, 1.25 }, { 252, -142, 0.95 }, { 214, -142, 0.85 }, { 70, 140, 0.9 } } do
		place("IceCastleTower", parent, CFrame.new(x0 + spot[1], GROUND_Y, spot[2]) * facing(0, -math.sign(spot[2])), { Scale = spot[3], Paints = ice, Collide = true })
		d.Take(x0 + spot[1], spot[2], 7 * spot[3])
	end
	place("Igloo", parent, CFrame.new(x0 + 160, GROUND_Y, 133) * facing(-0.3, -1), { Scale = 1.1, Paints = { Secondary = hex("BFDDF7") }, Collide = true })
	d.Take(x0 + 160, 133, 9)
	place("Igloo", parent, CFrame.new(x0 + 288, GROUND_Y, 137) * facing(0.2, -1), { Scale = 0.8, Paints = { Secondary = hex("BFDDF7") }, Collide = true })
	d.Take(x0 + 288, 137, 7)

	edgeGreenery(d, x0, x1, {
		Front = function(position, side)
			d.Prop("TreePine", position, side, { Scale = rng:NextNumber(1.2, 1.7), Paints = biome.Trees[rng:NextInteger(1, #biome.Trees)], Collide = false }, math.pi)
		end,
		Back = function(position, side)
			d.Prop("TreePine", position, side, { Scale = rng:NextNumber(1.5, 2.1), Paints = biome.Trees[rng:NextInteger(1, #biome.Trees)], Collide = false }, math.pi)
		end,
		Filler = function(position, side)
			if rng:NextNumber() < 0.4 then
				d.Prop("CrystalCluster", position, side, { Scale = rng:NextNumber(1, 1.5), Paints = { Primary = hex("9EE8FF"), Secondary = hex("D3EBFF") }, Collide = false }, math.pi)
			else
				d.Prop("BushRound", position, side, { Scale = rng:NextNumber(1.2, 1.8), Paints = biome.Bush, Collide = false }, math.pi)
			end
		end,
	})
	d.Scatter(8, x0 + 6, x1 - 6, 18, 117, 3.5, function(position, side)
		d.Prop("Snowman", position, side, { Scale = rng:NextNumber(1.1, 1.4), Paints = { Primary = if rng:NextNumber() < 0.5 then CORAL else SKY }, Collide = true }, 0.8)
	end)
	d.Scatter(14, x0 + 4, x1 - 4, 22, 118, 4, function(position, side)
		d.Prop("CrystalCluster", position, side, { Scale = rng:NextNumber(1, 1.7), Paints = { Primary = if rng:NextNumber() < 0.6 then SKY else STORM, Secondary = hex("D3EBFF") } }, math.pi)
	end)
	d.Scatter(8, x0 + 100, x1 - 4, 101, 117, 4.5, function(position, side)
		d.Prop("TreePine", position, side, { Scale = rng:NextNumber(0.8, 1.1), Paints = biome.Trees[1] }, math.pi)
	end)
	rocks(d, 10, x0 + 4, x1 - 4, 20, 118)
end

function Decor.Volcano(d, zoneId: number)
	local x0, x1 = regionBounds(zoneId)
	local rng = d.Rng
	local parent = d.Parent
	local biome = d.Biome

	-- the volcano on its own island beside the zone
	local volcanoSpot = Vector3.new(x0 + 212, GROUND_Y - 4, 214)
	satellite(parent, volcanoSpot.X, volcanoSpot.Z, volcanoSpot.Y, 104, biome)
	local volcano = place("Volcano", parent, CFrame.new(volcanoSpot) * facing(0, -1), { Scale = 1.3, Paints = { Primary = hex("6A3F37"), Secondary = hex("8A5A4E") }, Collide = false })
	local crater = pieceOf(volcano, "Neon_")
	if crater then
		pointLight(crater, rgb(255, 120, 40), 4, 60)
		emitter(crater, {
			Texture = SMOKE,
			Color = ColorSequence.new(rgb(120, 100, 100)),
			Size = NumberSequence.new(10, 30),
			Transparency = NumberSequence.new(0.35, 1),
			Lifetime = NumberRange.new(5, 7),
			Rate = 5,
			Speed = NumberRange.new(10, 16),
			EmissionDirection = upFace(crater),
			SpreadAngle = Vector2.new(15, 15),
			RotSpeed = NumberRange.new(-20, 20),
		})
	end
	satellite(parent, x0 + 70, -206, GROUND_Y - 10, 60, biome)
	place("LavaSpire", parent, CFrame.new(x0 + 64, GROUND_Y - 10, -204), { Scale = 2.2, Collide = false })
	place("LavaSpire", parent, CFrame.new(x0 + 80, GROUND_Y - 10, -214), { Scale = 1.5, Collide = false })

	edgeGreenery(d, x0, x1, {
		Front = function(position, side)
			if rng:NextNumber() < 0.55 then
				d.Prop("LavaSpire", position, side, { Scale = rng:NextNumber(1.1, 1.7), Paints = { Primary = biome.Band }, Collide = false }, math.pi)
			else
				d.Prop("RockTall", position, side, { Scale = rng:NextNumber(1.3, 1.9), Paints = biome.Stone, Collide = false }, math.pi)
			end
		end,
		Back = function(position, side)
			local roll = rng:NextNumber()
			if roll < 0.35 then
				d.Prop("CrystalCluster", position, side, { Scale = rng:NextNumber(1.6, 2.3), Paints = { Primary = hex("FF8A3D"), Secondary = biome.Band }, Collide = false }, math.pi)
			elseif roll < 0.7 then
				d.Prop("LavaSpire", position, side, { Scale = rng:NextNumber(1.6, 2.4), Paints = { Primary = biome.Band }, Collide = false }, math.pi)
			else
				d.Tree(position, side, rng:NextNumber(1.3, 1.8))
			end
		end,
		Filler = function(position, side)
			d.Prop("RockCluster", position, side, { Scale = rng:NextNumber(0.8, 1.3), Paints = biome.Stone, Collide = false }, math.pi)
		end,
	})
	d.Scatter(12, x0 + 4, x1 - 4, 20, 117, 7, function(position)
		lavaPool(parent, position, rng:NextNumber(6, 11))
	end)
	d.Scatter(8, x0 + 4, x1 - 4, 20, 117, 4, function(position, side)
		addSteam(d.Prop("SteamVent", position, side, { Scale = 1.2 }, math.pi))
	end)
	d.Scatter(12, x0 + 4, x1 - 4, 22, 118, 4, function(position, side)
		d.Prop("CrystalCluster", position, side, { Scale = rng:NextNumber(1, 1.5), Paints = { Primary = hex("FF8A3D"), Secondary = biome.Band } }, math.pi)
	end)
	rocks(d, 12, x0 + 4, x1 - 4, 20, 118)
end

function Decor.Sky(d, zoneId: number)
	local x0, x1 = regionBounds(zoneId)
	local rng = d.Rng
	local parent = d.Parent
	local biome = d.Biome
	local citadel = { Primary = hex("E2D8FF"), Secondary = STORM, Tertiary = hex("FF8FC8") }

	-- the citadel on its own island beside the zone
	satellite(parent, x0 + 200, -214, GROUND_Y - 6, 96, biome)
	for _, spot in { { 0, 0, 1.4 }, { -20, 10, 1 }, { 18, 12, 0.9 }, { 4, -20, 0.8 } } do
		place("CitadelTower", parent, CFrame.new(x0 + 200 + spot[1], GROUND_Y - 6, -214 + spot[2]) * facing(0, 1), { Scale = spot[3], Paints = citadel, Collide = false })
	end
	-- aurora arches over the path through the field
	for _, x in { x0 + 150, x0 + 250 } do
		place("AuroraArch", parent, CFrame.new(x, FIELD_Y, 0) * facing(-1, 0), { Scale = 1.6, Collide = false })
	end
	-- small floating islands: low ones beside the main island, high ones drifting over the field
	for index = 1, 9 do
		local side = if index % 2 == 0 then -1 else 1
		local outside = index <= 5
		local position = Vector3.new(
			rng:NextNumber(x0 + 20, x1 - 20),
			if outside then rng:NextNumber(14, 44) else rng:NextNumber(58, 78),
			side * (if outside then rng:NextNumber(170, 225) else rng:NextNumber(36, 105))
		)
		floatingIsland(parent, position, rng:NextNumber(0.8, 1.4), { Primary = biome.Field, Secondary = biome.Rock, Tertiary = biome.Band }, rng, function(island, top)
			place("StarLamp", island, CFrame.new(top), { Scale = 0.8, Paints = { Primary = STORM_DEEP } })
		end)
	end
	deco({ Name = "Moon", Shape = Enum.PartType.Ball, Size = Vector3.one * 130, CFrame = CFrame.new(x0 + 160, 260, -620), Color = hex("F4F0FF"), Material = M.Neon, Parent = parent })
	-- a ringed planet, so it reads as one from every zone
	local planet = CFrame.new(x0 + 40, 170, 560) * CFrame.Angles(0.42, 0, 0.32)
	deco({ Name = "Planet", Shape = Enum.PartType.Ball, Size = Vector3.one * 70, CFrame = planet, Color = hex("FF9AD5"), Material = M.Neon, Transparency = 0.1, Parent = parent })
	local segments = 20
	for index = 0, segments - 1 do
		local angle = (index + 0.5) / segments * math.pi * 2
		deco({
			Name = "PlanetRing",
			Size = Vector3.new(12, 1.6, 2 * 60 * math.sin(math.pi / segments) + 0.8),
			CFrame = planet * CFrame.Angles(0, angle, 0) * CFrame.new(60, 0, 0),
			Color = hex("FFE6A8"),
			Material = M.Neon,
			Transparency = 0.15,
			Parent = parent,
		})
	end

	edgeGreenery(d, x0, x1, {
		Front = function(position, side)
			if rng:NextNumber() < 0.3 then
				d.Prop("StarLamp", position, side, { Scale = rng:NextNumber(1.2, 1.6), Paints = { Primary = STORM_DEEP } }, 0.3)
			else
				d.Tree(position, side, rng:NextNumber(1.1, 1.6))
			end
		end,
		Back = function(position, side)
			if rng:NextNumber() < 0.45 then
				d.Prop("CloudBank", position, side, { Scale = rng:NextNumber(0.7, 1.1), Paints = { Secondary = biome.Cloud }, Collide = false }, math.pi)
			else
				d.Tree(position, side, rng:NextNumber(1.4, 2))
			end
		end,
	})
	d.Scatter(14, x0 + 4, x1 - 4, 24, 118, 4, function(position, side)
		d.Prop("CrystalCluster", position, side, { Scale = rng:NextNumber(1, 1.6), Paints = { Primary = if rng:NextNumber() < 0.5 then hex("7FE7FF") else hex("FF9AD5"), Secondary = biome.Rock } }, math.pi)
	end)
	d.Scatter(10, x0 + 30, x1 - 6, 101, 117, 3, function(position, side)
		d.Prop("StarLamp", position, side, { Scale = 1.2, Paints = { Primary = STORM_DEEP } }, 0.3)
	end)
	d.Scatter(16, x0 + 4, x1 - 4, 40, 117, 4, function(position, side)
		d.Tree(position, side, rng:NextNumber(0.9, 1.3), true)
	end)
	d.Scatter(8, x0 + 4, x1 - 4, 30, 117, 6, function(position, side)
		d.Prop("CloudBank", position, side, { Scale = rng:NextNumber(0.45, 0.7), Paints = { Secondary = biome.Cloud }, Collide = false }, math.pi)
	end)
	rocks(d, 8, x0 + 4, x1 - 4, 20, 118)
end

---------------------------------------------------------------------------
-- Hub: Storm Station
---------------------------------------------------------------------------
local function leaderboard(parent: Instance, position: Vector3, facingDir: Vector3, kind: string, title: string, accent: Color3)
	local stand = model(title, parent)
	local scale = 1.25
	local base = CFrame.lookAt(Vector3.new(position.X, GROUND_Y, position.Z), Vector3.new(position.X, GROUND_Y, position.Z) + facingDir)
	place("LeaderboardFrame", stand, base, { Scale = scale, Paints = { Primary = accent, Secondary = INK_SOFT }, Collide = true })
	local board = part({ Name = "Board", Size = Vector3.new(16 * scale, 18 * scale, 0.2), CFrame = base * CFrame.new(0, 13 * scale, -1.5 * scale - 0.15), Color = INK, CanCollide = false, CanQuery = false, Parent = stand })
	local gui = surfaceGui(board, Enum.NormalId.Front, 24)

	local header = Instance.new("Frame")
	header.BackgroundColor3 = accent
	header.Size = UDim2.new(1, -24, 0.13, 0)
	header.Position = UDim2.new(0, 12, 0, 10)
	header.Parent = gui
	corner(header, 14)
	outline(header, WHITE, 3)
	textLabel(header, { Text = title, Size = UDim2.fromScale(0.94, 0.78), Position = UDim2.fromScale(0.03, 0.11), Stroke = 3 })

	local rows = {}
	for rank = 1, 10 do
		local row = Instance.new("Frame")
		row.Name = "Row" .. rank
		row.BackgroundColor3 = if rank % 2 == 0 then hex("33427F") else hex("2A3872")
		row.Size = UDim2.new(1, -24, 0.074, 0)
		row.Position = UDim2.new(0, 12, 0.165 + (rank - 1) * 0.081, 0)
		row.Visible = false
		row.Parent = gui
		corner(row, 10)
		local rankColor = if rank == 1 then BOLT elseif rank == 2 then hex("DDE2FB") elseif rank == 3 then SUNSET else WHITE
		textLabel(row, { Text = "#" .. rank, TextColor3 = rankColor, Size = UDim2.fromScale(0.14, 0.8), Position = UDim2.fromScale(0.02, 0.1) })
		local nameLabel = textLabel(row, { Text = "", TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromScale(0.54, 0.7), Position = UDim2.fromScale(0.18, 0.15) })
		local valueLabel = textLabel(row, { Text = "", TextColor3 = accent, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromScale(0.26, 0.7), Position = UDim2.fromScale(0.72, 0.15) })
		rows[rank] = { Frame = row, Name = nameLabel, Value = valueLabel }
	end

	local status = textLabel(gui, { Text = "Loading leaderboard...", Font = Enum.Font.GothamBold, TextColor3 = hex("C9D0F7"), Size = UDim2.new(0.9, 0, 0.2, 0), Position = UDim2.fromScale(0.05, 0.45), Stroke = 2 })
	MapService.Leaderboards[kind] = { Rows = rows, Status = status }
end

local function forecastBoard(parent: Instance, position: Vector3, facingDir: Vector3)
	local stand = model("ForecastBoard", parent)
	local scale = 1.75
	local base = CFrame.lookAt(Vector3.new(position.X, GROUND_Y, position.Z), Vector3.new(position.X, GROUND_Y, position.Z) + facingDir)
	place("ForecastTower", stand, base, { Scale = scale, Paints = { Primary = SKY, Secondary = SKY_DEEP }, Collide = true })
	local screen = part({ Name = "Screen", Size = Vector3.new(12 * scale, 8 * scale, 0.2), CFrame = base * CFrame.new(0, 14 * scale, -3 * scale - 0.15), Color = INK, CanCollide = false, CanQuery = false, Parent = stand })
	local gui = surfaceGui(screen, Enum.NormalId.Front, 24)
	gui.Name = "ForecastGui"
	CollectionService:AddTag(gui, "ForecastGui")
	-- Texts are filled in live by the client (WorldController)
	textLabel(gui, { Name = "Title", Text = "⛈️ STORM FORECAST", TextColor3 = SKY, Size = UDim2.fromScale(0.9, 0.11), Position = UDim2.fromScale(0.05, 0.03) })
	textLabel(gui, { Name = "Label", Text = "NEXT MEGA STORM", Font = Enum.Font.GothamBold, TextColor3 = hex("C9D0F7"), Size = UDim2.fromScale(0.9, 0.065), Position = UDim2.fromScale(0.05, 0.15), Stroke = 2 })
	textLabel(gui, { Name = "Countdown", Text = "--:--", TextColor3 = BOLT, Size = UDim2.fromScale(0.9, 0.15), Position = UDim2.fromScale(0.05, 0.215) })
	textLabel(gui, { Name = "StormName", Text = "Tempest Twister", Size = UDim2.fromScale(0.9, 0.075), Position = UDim2.fromScale(0.05, 0.37) })
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.BackgroundColor3 = hex("4C5DA8")
	divider.BorderSizePixel = 0
	divider.Size = UDim2.new(0.9, 0, 0, 3)
	divider.Position = UDim2.fromScale(0.05, 0.465)
	divider.Parent = gui
	local rainbowLabel = textLabel(gui, { Name = "Rainbow", Text = "🌈 Rainbow Hurricane", Size = UDim2.fromScale(0.9, 0.085), Position = UDim2.fromScale(0.05, 0.485) })
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, rgb(255, 110, 130)),
		ColorSequenceKeypoint.new(0.25, rgb(255, 200, 90)),
		ColorSequenceKeypoint.new(0.5, rgb(130, 240, 140)),
		ColorSequenceKeypoint.new(0.75, rgb(110, 190, 255)),
		ColorSequenceKeypoint.new(1, rgb(205, 140, 255)),
	})
	gradient.Parent = rainbowLabel
	textLabel(gui, { Name = "UpcomingTitle", Text = "📅 UPCOMING STORMS", Font = Enum.Font.GothamBold, TextColor3 = hex("C9D0F7"), Size = UDim2.fromScale(0.9, 0.055), Position = UDim2.fromScale(0.05, 0.59), Stroke = 2 })
	for index = 1, 3 do
		local row = Instance.new("Frame")
		row.Name = "Upcoming" .. index
		row.BackgroundColor3 = if index % 2 == 0 then hex("33427F") else hex("2A3872")
		row.Size = UDim2.fromScale(0.9, 0.085)
		row.Position = UDim2.fromScale(0.05, 0.655 + (index - 1) * 0.095)
		row.Parent = gui
		corner(row, 10)
		textLabel(row, { Name = "When", Text = "", TextColor3 = BOLT, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromScale(0.27, 0.72), Position = UDim2.fromScale(0.03, 0.14), Stroke = 2 })
		textLabel(row, { Name = "Storm", Text = "", TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromScale(0.47, 0.72), Position = UDim2.fromScale(0.31, 0.14), Stroke = 2 })
		textLabel(row, { Name = "In", Text = "", Font = Enum.Font.GothamBold, TextColor3 = hex("C9D0F7"), TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromScale(0.19, 0.6), Position = UDim2.fromScale(0.79, 0.2), Stroke = 2 })
	end
	textLabel(gui, { Name = "Hint", Text = "Gather at the arena and vacuum it together!", Font = Enum.Font.GothamBold, TextColor3 = hex("C9D0F7"), Size = UDim2.fromScale(0.9, 0.045), Position = UDim2.fromScale(0.05, 0.945), Stroke = 2 })
end

local function arena(parent: Instance)
	local center = MapLayout.ArenaCenter
	local radius = MapLayout.ArenaRadius
	local stage = model("MegaStormArena", parent)
	local y = GROUND_Y
	local function at(height: number): Vector3
		return Vector3.new(center.X, y + height, center.Z)
	end

	cylinder({ Name = "Rim", Position = at(0.35), Height = 0.9, Diameter = radius * 2 + 5, Color = BOLT, Material = M.Neon, Parent = stage })
	cylinder({ Name = "Floor", Position = at(0.5), Height = 1, Diameter = radius * 2, Color = hex("3B4A8C"), Parent = stage })
	cylinder({ Name = "Ring", Position = at(0.62), Height = 1, Diameter = 36, Color = SKY, Material = M.Neon, Parent = stage })
	cylinder({ Name = "Emblem", Position = at(0.7), Height = 1, Diameter = 31, Color = hex("2D3A78"), Parent = stage })
	for index = 0, 5 do
		local angle = index * math.pi / 3
		local spoke = at(1.15) + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 27
		deco({ Name = "Spoke", Shape = Enum.PartType.Ball, Size = Vector3.one * 2.4, CFrame = CFrame.new(spoke), Color = SKY, Material = M.Neon, Parent = stage })
	end

	for index = 0, 7 do
		-- Offset by pi/8 so no pylon stands on the hub walkway (z = 0)
		local angle = index * math.pi / 4 + math.pi / 8
		local position = Vector3.new(center.X + math.cos(angle) * (radius + 5), y, center.Z + math.sin(angle) * (radius + 5))
		cylinder({ Name = "PylonBase", Position = position + Vector3.new(0, 1, 0), Height = 2, Diameter = 5, Color = BODY, Parent = stage })
		cylinder({ Name = "Pylon", Position = position + Vector3.new(0, 7.5, 0), Height = 11, Diameter = 2.2, Color = STORM_DEEP, Parent = stage })
		cylinder({ Name = "PylonCollar", Position = position + Vector3.new(0, 12.9, 0), Height = 1, Diameter = 3.4, Color = BODY, Parent = stage })
		local cap = ball(position + Vector3.new(0, 15.5, 0), 3.4, SKY, { Name = "PylonCap", Material = M.Neon, Parent = stage, Tags = { "ArenaPylon" } })
		pointLight(cap, SKY, 1.5, 16)
	end

	local anchor = part({ Name = "SignAnchor", Size = Vector3.one, CFrame = CFrame.new(center + Vector3.new(0, 52, 0)), Transparency = 1, CanCollide = false, CanQuery = false, Parent = stage })
	local gui = billboard(anchor, UDim2.fromOffset(420, 120), Vector3.zero, 400)
	gui.Name = "ArenaGui"
	CollectionService:AddTag(gui, "ArenaGui")
	textLabel(gui, { Name = "Title", Text = "🌪️ MEGA STORM ARENA", TextColor3 = SKY, Size = UDim2.fromScale(1, 0.5), Stroke = 3 })
	textLabel(gui, { Name = "Countdown", Text = "Next storm in --:--", TextColor3 = BOLT, Size = UDim2.fromScale(1, 0.4), Position = UDim2.fromScale(0, 0.55), Stroke = 3 })
end

local function rebirthShrine(parent: Instance, position: Vector3)
	local shrine = model("RebirthShrine", parent)
	local purple = STORM
	place("RebirthShrine", shrine, CFrame.new(position.X, GROUND_Y, position.Z) * facing(0, -1), { Scale = 1.1, Paints = { Primary = hex("E2D8FF"), Secondary = STORM_DEEP }, Collide = true })
	local crystal = model("Crystal", shrine)
	local corePosition = Vector3.new(position.X, GROUND_Y + 11.5, position.Z)
	local core = part({ Name = "Core", Size = Vector3.new(3.6, 3.6, 3.6), CFrame = CFrame.new(corePosition) * CFrame.Angles(math.rad(45), 0, math.rad(45)), Color = purple, Material = M.Neon, CanCollide = false, Parent = crystal })
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
	crystal.WorldPivot = CFrame.new(corePosition)
	CollectionService:AddTag(crystal, "Spin")
	crystal:SetAttribute("SpinSpeed", 1)
	crystal:SetAttribute("BobHeight", 1)
	local glow = cylinder({ Name = "Glow", Position = Vector3.new(position.X, GROUND_Y + 0.2, position.Z), Height = 0.6, Diameter = 26, Color = purple, Material = M.Neon, Transparency = 0.35, CanCollide = false, CastShadow = false, Parent = shrine, Tags = { "Pulse" } })
	glow.CanQuery = false

	local anchor = part({ Name = "SignAnchor", Size = Vector3.one, CFrame = CFrame.new(position + Vector3.new(0, 17, 0)), Transparency = 1, CanCollide = false, CanQuery = false, Parent = shrine })
	local gui = billboard(anchor, UDim2.fromOffset(260, 90), Vector3.new(0, 4, 0), 120)
	textLabel(gui, { Text = "🌀 CLIMATE SHIFT", TextColor3 = hex("D9C9FF"), Size = UDim2.fromScale(1, 0.6), Stroke = 3 })
	textLabel(gui, { Text = "Permanent Volts bonus + gear looks", Font = Enum.Font.GothamBold, Size = UDim2.fromScale(1, 0.32), Position = UDim2.fromScale(0, 0.64), Stroke = 2 })

	local host = promptHost(shrine, position + Vector3.new(0, 3, 0))
	local instance = prompt(host, "Climate Shift", "Climate Shrine", 0, 16)
	instance:SetAttribute("Panel", "Rebirth")
end

-- Open-front StationBooth recoloured per station, its sign, and the prompt that opens the panel.
-- The booth's front faces `facingDir`.
local function kiosk(parent: Instance, position: Vector3, facingDir: Vector3, title: string, icon: string, color: Color3, panel: string?)
	local booth = model(title, parent)
	local base = CFrame.lookAt(position, position + facingDir)
	local ground = CFrame.lookAt(Vector3.new(position.X, GROUND_Y, position.Z), Vector3.new(position.X, GROUND_Y, position.Z) + facingDir)
	place("StationBooth", booth, ground, { Paints = { Primary = color, Secondary = shade(color, 0.72) }, Collide = true })
	signBoard(booth, "Sign", ground * CFrame.new(0, 13, -7.35), 13, 3.4, icon .. " " .. string.upper(title), color, { Enum.NormalId.Front }, 30)
	if panel then
		local host = promptHost(booth, (base * CFrame.new(0, 4, -4.6)).Position)
		local instance = prompt(host, "Open", title, 0, 14)
		instance:SetAttribute("Panel", panel)
	end
	return booth, base
end

-- Lobby shop pet stand (Monetization.Products.AuroraGryphon): between the Upgrade Workshop and the Storm
-- Shop, facing the arena like them. A tiered pedestal in the gryphon's colours with a pulsing glow, the pet
-- (PetModels: the mesh pack when it is there) spinning and bobbing above it (tag "Spin"), an Aurora Arch
-- behind it carrying the name and price signs, star lamps either side, and a "Buy" prompt (attribute
-- ProductKey) that WorldController turns into MonetizationController.PromptProduct.
local SHOP_PET = { Product = "AuroraGryphon", Position = Vector3.new(-132, 0, -80) }
local stopShopPetRebuild: (() -> ())? = nil -- stops the last build's PetMeshes listener

local function shopPetStand(parent: Instance)
	local product = Monetization.Products[SHOP_PET.Product]
	local def = product and Pets.Pets[product.PetId]
	if not def then
		return
	end
	local mint, violet, blue = hex("60F6C8"), hex("B27CFF"), hex("4A62D6")
	local x, z = SHOP_PET.Position.X, SHOP_PET.Position.Z
	local stand = model("AuroraGryphonStand", parent)
	local function at(height: number, dz: number?): Vector3
		return Vector3.new(x, GROUND_Y + height, z + (dz or 0))
	end

	-- Pedestal: white base with a violet neon trim, a gryphon-blue drum with gold studs, a white cap with
	-- a mint neon rim, and a soft glow on the ground and on the cap (tag "Pulse")
	local glow = cylinder({ Name = "Glow", Position = at(0.08), Height = 0.3, Diameter = 19.5, Color = mint, Material = M.Neon, Transparency = 0.55, CanCollide = false, CastShadow = false, Parent = stand, Tags = { "Pulse" } })
	glow.CanQuery = false
	cylinder({ Name = "Base", Position = at(0.6), Height = 1.2, Diameter = 15, Color = BODY, Parent = stand })
	cylinder({ Name = "BaseTrim", Position = at(1.25), Height = 0.3, Diameter = 14.2, Color = violet, Material = M.Neon, CanCollide = false, CastShadow = false, Parent = stand })
	cylinder({ Name = "Drum", Position = at(2.35), Height = 2.2, Diameter = 11, Color = blue, Parent = stand })
	for index = 0, 7 do
		local angle = index * math.pi / 4 + math.pi / 8
		deco({ Name = "Stud", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.9, CFrame = CFrame.new(at(2.35) + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 5.45), Color = BOLT, Material = M.Neon, Parent = stand })
	end
	cylinder({ Name = "Cap", Position = at(3.85), Height = 0.8, Diameter = 12.4, Color = BODY, Parent = stand })
	cylinder({ Name = "CapRim", Position = at(3.85), Height = 0.5, Diameter = 13, Color = mint, Material = M.Neon, CanCollide = false, CastShadow = false, Parent = stand })
	local halo = cylinder({ Name = "Halo", Position = at(4.3), Height = 0.12, Diameter = 9, Color = mint, Material = M.Neon, Transparency = 0.35, CanCollide = false, CastShadow = false, Parent = stand, Tags = { "Pulse" } })
	halo.CanQuery = false

	-- The pet floats above the cap; its light and sparkles hang on a still part so they don't spin
	local petCenter = at(9)
	local core = deco({ Name = "Core", Size = Vector3.one, CFrame = CFrame.new(petCenter), Transparency = 1, Parent = stand })
	pointLight(core, mint, 2, 20)
	emitter(core, {
		Texture = SPARKLE,
		Color = ColorSequence.new(mint, violet),
		Size = NumberSequence.new(0.9, 0),
		Lifetime = NumberRange.new(1, 1.8),
		Rate = 10,
		Speed = NumberRange.new(1.5, 3),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 1,
	})
	local function showPet()
		local old = stand:FindFirstChild("DisplayPet")
		if old then
			old:Destroy()
		end
		local pet = PetModels.Build(def.Id, "Normal", { Scale = 2.3 })
		pet.Name = "DisplayPet"
		for _, item in pet:GetDescendants() do
			if item:IsA("BasePart") then
				item.Anchored = true
				item.CanCollide = false
				item.CanQuery = false
				item.CanTouch = false
			end
		end
		pet:PivotTo(CFrame.new(petCenter) * facing(0, 1))
		CollectionService:AddTag(pet, "Spin")
		pet:SetAttribute("SpinSpeed", 0.6)
		pet:SetAttribute("BobHeight", 0.7)
		pet.Parent = stand
	end
	showPet()
	-- PetMeshService inserts the uploaded mesh pack after the map is built: swap in the mesh pet then
	if stopShopPetRebuild then
		stopShopPetRebuild()
	end
	stopShopPetRebuild = PetModels.OnPackChanged(function()
		if stand.Parent then
			showPet()
		end
	end)

	-- Aurora Arch behind (its mint and violet glass match the gryphon) with the signs on top, star lamps
	place("AuroraArch", stand, CFrame.new(at(0, -6.5)) * facing(0, 1), { Scale = 0.85, Collide = false })
	local front = CFrame.new(at(0, -5.6)) * facing(0, 1)
	signBoard(stand, "NameSign", front * CFrame.new(0, 18.6, 0), 16, 3.4, "🐾 " .. string.upper(def.Name), STORM_DEEP, { Enum.NormalId.Front }, 30)
	signBoard(stand, "PriceSign", front * CFrame.new(0, 15.9, 0.1), 7.4, 2.4, "R$" .. Format.Commas(product.Price), BOLT_DEEP, { Enum.NormalId.Front }, 30)
	for _, side in { -1, 1 } do
		place("StarLamp", stand, CFrame.new(at(0, 1.5) + Vector3.new(side * 11, 0, 0)) * facing(0, 1), { Paints = { Primary = violet }, Collide = false })
	end

	-- a short paver path from the arena square to the stand
	pavers(stand, BIOMES[0], -60, -70.5, x, 10, true)

	local host = promptHost(stand, at(3.5, 6))
	local instance = prompt(host, "Buy", def.Name, 0, 14)
	instance:SetAttribute("ProductKey", SHOP_PET.Product)
	return stand
end

local function buildHub(parent: Instance)
	local hub = folder("StormStation", parent)
	local biome = BIOMES[0]
	local stations = MapLayout.HubStations
	local spawnAt = MapLayout.Spawn
	local center = MapLayout.ArenaCenter
	local radius = MapLayout.ArenaRadius
	local towerX = WEST_END + 24

	-- Light plaza: the round arena square and the two station rows
	local plaza = folder("Plaza", hub)
	cylinder({ Name = "ArenaSquare", Position = Vector3.new(center.X, GROUND_Y + 0.03, center.Z), Height = 0.2, Diameter = 128, Color = biome.Field, CanCollide = false, CastShadow = false, Parent = plaza })
	for _, side in { -1, 1 } do
		roundedPad(plaza, "StationRow", -186, -22, if side < 0 then -100 else 60, if side < 0 then -60 else 100, GROUND_Y + 0.06, GROUND_Y - 0.2, 6, biome.Field)
	end
	cylinder({ Name = "TowerSquare", Position = Vector3.new(towerX, GROUND_Y + 0.03, 0), Height = 0.2, Diameter = 46, Color = biome.Field, CanCollide = false, CastShadow = false, Parent = plaza })

	-- Paths: the main path (around the spawn and under the arena it stops) and branches to every station
	local paths = folder("Paths", hub)
	pavers(paths, biome, MapLayout.HubStart - 2, MapLayout.HubEnd, 0, PATH_HALF * 2, false, function(x, z)
		return math.abs(x - center.X) < radius + 3 or math.abs(x - spawnAt.X) < 12
	end)
	pavers(paths, biome, -73, -8, -160, 10, true)
	pavers(paths, biome, -46, -73, -104, 10, true)
	pavers(paths, biome, 8, 69, -160, 10, true)
	pavers(paths, biome, 46, 73, -104, 10, true)
	pavers(paths, biome, -46.5, -8, -48, 10, true)
	pavers(paths, biome, 8, 72, -48, 10, true)

	-- Spawn on a round plinth
	cylinder({ Name = "SpawnPlinth", Position = Vector3.new(spawnAt.X, GROUND_Y + 0.25, spawnAt.Z), Height = 0.9, Diameter = 24, Color = BODY, CastShadow = false, Parent = hub })
	cylinder({ Name = "SpawnTrim", Position = Vector3.new(spawnAt.X, GROUND_Y + 0.2, spawnAt.Z), Height = 0.9, Diameter = 25.2, Color = SKY, Material = M.Neon, CanCollide = false, CastShadow = false, Parent = hub })
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.lookAt(spawnAt + Vector3.new(0, 0.5, 0), spawnAt + Vector3.new(10, 0.5, 0))
	spawn.Color = hex("DDE2FB")
	spawn.Material = SMOOTH
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = hub
	cylinder({ Name = "SpawnRing", Position = spawnAt + Vector3.new(0, 0.55, 0), Height = 1.02, Diameter = 12, Color = SKY, Material = M.Neon, Transparency = 0.3, CanCollide = false, Parent = hub })

	-- The Weather Tower rises behind the spawn
	place("WeatherTower", hub, CFrame.new(towerX, GROUND_Y, 0) * facing(1, 0), { Paints = { Primary = SKY, Secondary = STORM }, Collide = true })

	-- Welcome arch over the path
	arch(hub, -172, "⛈️ STORM CATCHER SIMULATOR", { Primary = BODY, Secondary = SKY_DEEP, Tertiary = STORM_DEEP })

	arena(hub)

	kiosk(hub, stations.Upgrades, Vector3.zAxis, "Upgrade Workshop", "⬆️", SKY, "Upgrades")
	kiosk(hub, stations.Shop, Vector3.zAxis, "Storm Shop", "🛒", SUNSET, "Shop")
	shopPetStand(hub)
	kiosk(hub, stations.Rewards, -Vector3.zAxis, "Daily Rewards", "🎁", CORAL, "Rewards")
	weatherLab(hub, stations.WeatherLab, 1, nil)
	sellPad(hub, MapLayout.HubSellPad, BOLT)
	place("SellMachine", hub, CFrame.new(MapLayout.HubSellPad.X + SELL_MACHINE.X, GROUND_Y, MapLayout.HubSellPad.Z + SELL_MACHINE.Z) * facing(0, 1), { Scale = 1.05, Collide = true })
	rebirthShrine(hub, stations.Rebirth)
	forecastBoard(hub, stations.Forecast, -Vector3.zAxis)

	leaderboard(hub, MapLayout.Leaderboards.Volts, Vector3.zAxis, "Volts", "🏆 TOP STORM CATCHERS", BOLT_DEEP)
	leaderboard(hub, MapLayout.Leaderboards.Rebirths, -Vector3.zAxis, "Rebirths", "🌀 MOST CLIMATE SHIFTS", STORM_DEEP)

	-- Lamps along the path, benches and planted trees (all inside the west boundary at HubStart - 2,
	-- where the path ends at a railing: the Weather Tower behind it is scenery)
	local decor = folder("Decor", hub)
	for _, x in { -217, -60, -38, -16 } do
		lamp(decor, Vector3.new(x, 0, -12), Vector3.new(x, 0, 0), biome.Lamp)
		lamp(decor, Vector3.new(x, 0, 12), Vector3.new(x, 0, 0), biome.Lamp)
	end
	for _, z in { -15.3, -5.1, 5.1, 15.3 } do
		place("Fence", decor, CFrame.new(MapLayout.HubStart - 1.4, GROUND_Y, z) * facing(1, 0), { Paints = { Primary = hex("FFF6E6"), Secondary = SKY }, Collide = false })
	end
	for _, spot in { { -214, -24 }, { -214, 24 }, { -204, -20 }, { -204, 20 } } do
		place("Bench", decor, CFrame.new(spot[1], GROUND_Y, spot[2]) * facing(0, -math.sign(spot[2])), { Paints = { Primary = SUNSET, Secondary = INK_SOFT }, Collide = true })
	end
	local rng = Random.new(77)
	local planted = {
		{ -206, -108 }, { -206, 108 }, { -14, -108 }, { -14, 108 }, { -132, -108 }, { -132, 108 }, { -76, -108 }, { -76, 108 },
		{ -168, -50 }, { -168, 50 }, { -24, -36 }, { -24, 36 },
	}
	for index, spot in planted do
		local position = CFrame.new(spot[1], GROUND_Y, spot[2])
		place("Planter", decor, position, { Paints = { Primary = if index % 2 == 0 then SKY else hex("FFB15C") }, Collide = true })
		place(if index % 3 == 0 then "TreeTall" else "TreeRound", decor, position * CFrame.new(0, 2, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), {
			Scale = rng:NextNumber(0.95, 1.15),
			Paints = biome.Trees[index % #biome.Trees + 1],
			Collide = false,
		})
	end
	signPost(decor, Vector3.new(-26, 0, -14), Vector3.new(-1, 0, 0), "🌤️ SUNNY PLAINS →", LEAF, 1.5)

	-- Flowers and bushes in front of the stations, greenery all around the edges
	local d = dresser(decor, 0, 4242, {
		{ WEST_END - 50, MapLayout.HubEnd + 30, -PATH_HALF - 3, PATH_HALF + 3 },
		{ center.X, center.Z, 66 },
		{ -186, -22, -100, -60 },
		{ -186, -22, 60, 100 },
		{ towerX, 0, 26 },
		{ spawnAt.X, spawnAt.Z, 16 },
		{ -200, -180, -48, -36 },
		{ -200, -180, 36, 48 },
		{ -172 - 6, -172 + 6, -24, 24 },
		{ -166, -154, -73, 73 },
		{ -54, -42, -60, 73 },
		{ WEST_END - 50, MapLayout.HubEnd + 30, -MapLayout.HalfWidth - 3, -MapLayout.HalfWidth + 1 },
		{ WEST_END - 50, MapLayout.HubEnd + 30, MapLayout.HalfWidth - 1, MapLayout.HalfWidth + 3 },
	})
	for _, spot in planted do
		d.Take(spot[1], spot[2], 6)
	end
	edgeGreenery(d, WEST_END + 4, MapLayout.HubEnd)
	d.Scatter(18, WEST_END + 6, MapLayout.HubStart - 6, 24, 118, 4.5, function(position, side)
		d.Tree(position, side, d.Rng:NextNumber(1.2, 1.7))
	end)
	d.Scatter(12, WEST_END + 6, MapLayout.HubStart - 6, 24, 118, 2.5, function(position, side)
		d.Prop("BushRound", position, side, { Scale = d.Rng:NextNumber(1.2, 1.7), Paints = biome.Bush, Collide = false }, math.pi)
	end)
	flowers(d, 22, WEST_END + 30, MapLayout.HubEnd - 4, 14, 117, { { hex("FF7AA8"), WHITE }, { BOLT, hex("FF9F5A") }, { hex("B69CFF"), WHITE } })
	d.Scatter(14, WEST_END + 30, MapLayout.HubEnd - 4, 14, 117, 3.5, function(position, side)
		d.Prop("BushRound", position, side, { Scale = d.Rng:NextNumber(1, 1.5), Paints = biome.Bush, Collide = false }, math.pi)
	end)
	tufts(d, 30, WEST_END + 30, MapLayout.HubEnd - 4, 12, 118, hex("9DA8EE"))
end

---------------------------------------------------------------------------
-- Zones
---------------------------------------------------------------------------
local function buildZone(parent: Instance, zoneId: number)
	local zone = Zones[zoneId]
	local biome = BIOMES[zoneId]
	local zoneFolder = folder(zone.Key, parent)
	local x0, x1 = MapLayout.ZoneStart(zoneId), MapLayout.ZoneEnd(zoneId)

	if zoneId == 1 then
		arch(zoneFolder, x0, zone.Icon .. " " .. string.upper(zone.Name), gatePaints(zone))
	else
		gate(zoneFolder, zoneId)
	end

	buildField(zoneFolder, zoneId)
	local paths = folder("Paths", zoneFolder)
	local spawnX = MapLayout.ZoneSpawn(zoneId).Position.X
	pavers(paths, biome, x0, x1, 0, PATH_HALF * 2, false, function(x)
		return math.abs(x - spawnX) < 10
	end)
	local sell, egg = MapLayout.SellPad(zoneId), MapLayout.EggStation(zoneId)
	pavers(paths, biome, -PATH_HALF, sell.Z + MapLayout.SellPadRadius + 0.75, sell.X, 10, true)
	pavers(paths, biome, PATH_HALF, egg.Z - 11, egg.X, 10, true)
	-- the zone spawn: a round paved landing with a ring of the zone's colour
	cylinder({ Name = "SpawnRing", Position = Vector3.new(spawnX, GROUND_Y + 0.1, 0), Height = 0.4, Diameter = 21, Color = zone.Color, CastShadow = false, Parent = paths })
	cylinder({ Name = "SpawnCircle", Position = Vector3.new(spawnX, GROUND_Y + 0.12, 0), Height = 0.4, Diameter = 18.6, Color = biome.Pavers[1], CastShadow = false, Parent = paths })

	sellStation(zoneFolder, zoneId, biome)
	eggStation(zoneFolder, zoneId)
	if zone.Hazard and zone.Hazard.Kind == "Heat" then
		for _, spot in Hazards.CoolingSpots(zoneId) do
			coolingArea(zoneFolder, spot, zone.Hazard.SafeRadius)
		end
	end

	local decorFolder = folder("Decor", zoneFolder)
	if zoneId == MapLayout.ZoneCount then
		for _, x in { x0 + 40, x0 + 90 } do
			for _, side in { -1, 1 } do
				place("StarLamp", decorFolder, CFrame.new(x, GROUND_Y, side * 12.5), { Scale = 1.4, Paints = { Primary = STORM_DEEP } })
			end
		end
	else
		for _, x in { x0 + 40, x0 + 90 } do
			lamp(decorFolder, Vector3.new(x, 0, -12.5), Vector3.new(x, 0, 0), biome.Lamp)
			lamp(decorFolder, Vector3.new(x, 0, 12.5), Vector3.new(x, 0, 0), biome.Lamp)
		end
	end
	signPost(decorFolder, Vector3.new(sell.X + 10, 0, -14.5), Vector3.new(-1, 0, 0.3), "⚡ SELL", BOLT_DEEP, 1.3)
	signPost(decorFolder, Vector3.new(egg.X + 10, 0, 14.5), Vector3.new(-1, 0, -0.3), "🥚 EGGS", zone.Color, 1.3)
	for _, x in { x0 + 33, x0 + 72, x0 + 97 } do
		for _, side in { -1, 1 } do
			if zoneId == 3 then
				place("Cactus", decorFolder, CFrame.new(x, GROUND_Y, side * 12) * CFrame.Angles(0, x, 0), { Scale = 0.75 })
			else
				place("BushRound", decorFolder, CFrame.new(x, GROUND_Y, side * 11.5) * CFrame.Angles(0, x, 0), { Scale = 0.95, Paints = biome.Bush })
			end
		end
	end
	signPost(decorFolder, Vector3.new(x0 + 95, 0, 15), Vector3.new(-1, 0, -0.3), "🌪️ STORM FIELD", SKY_DEEP, 1.3)
	place("Bench", decorFolder, CFrame.new(x0 + 80, GROUND_Y, -16) * facing(0, 1), { Paints = { Primary = SUNSET, Secondary = INK_SOFT }, Collide = true })
	place("Bench", decorFolder, CFrame.new(x0 + 80, GROUND_Y, 16) * facing(0, -1), { Paints = { Primary = SUNSET, Secondary = INK_SOFT }, Collide = true })

	local blocks = zoneBlocks(zoneId)
	table.insert(blocks, { x0 + 80, 16, 5 })
	table.insert(blocks, { x0 + 80, -16, 5 })
	table.insert(blocks, { sell.X + 10, -14.5, 5 })
	table.insert(blocks, { egg.X + 10, 14.5, 5 })
	table.insert(blocks, { x0 + 95, 15, 5 })
	local d = dresser(decorFolder, zoneId, zoneId * 1000 + 7, blocks)
	local decorator = Decor[zone.Key]
	if decorator then
		decorator(d, zoneId)
	end
	-- a few bigger things in the plaza, so the walk from the gate to the field is framed too
	local rng = d.Rng
	local feature = PLAZA_FEATURES[zone.Key]
	if feature then
		d.Scatter(feature.Count, x0 + 8, x0 + 96, 24, 96, 5, function(position, side)
			feature.Place(d, position, side, rng)
		end)
	end
	patches(d, 16, x0 + 8, x1 - 8, 16, 116)
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
	Lighting.ShadowSoftness = 0.75 -- very soft shadows
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.1

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
	sunRays.Intensity = 0.03
	sunRays.Spread = 0.5
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
	MapService.Stats = { Props = 0, Built = 0, Missing = {}, Parts = 0 }

	local map = folder("Map", Workspace)
	buildLighting()
	buildCloudSea(map)
	local walls = folder("Boundaries", map)
	local length = MapLayout.WorldEnd - MapLayout.HubStart
	local centerX = (MapLayout.WorldEnd + MapLayout.HubStart) / 2
	local function wall(cframe: CFrame, size: Vector3)
		part({ Name = "Boundary", CFrame = cframe, Size = size, Transparency = 1, CanQuery = false, CanTouch = false, CastShadow = false, Parent = walls })
	end
	-- The side walls run the whole world (2164 studs), but Roblox cuts every part to 2048 studs per
	-- axis, which left gaps at both ends: they're built from equal pieces that each fit
	local sideLength = length + 24
	local pieces = math.ceil(sideLength / 2000)
	local pieceLength = sideLength / pieces
	for index = 1, pieces do
		local x = centerX - sideLength / 2 + pieceLength * (index - 0.5)
		for _, side in { -1, 1 } do
			wall(CFrame.new(x, 110, side * (MapLayout.HalfWidth + 2)), Vector3.new(pieceLength, 280, 4))
		end
	end
	wall(CFrame.new(MapLayout.HubStart - 4, 110, 0), Vector3.new(4, 280, 260))
	wall(CFrame.new(MapLayout.WorldEnd + 4, 110, 0), Vector3.new(4, 280, 260))

	buildHub(map)
	buildIsland(map.StormStation, 0)
	for zoneId = 1, #Zones do
		buildZone(map, zoneId)
		buildIsland(map[Zones[zoneId].Key], zoneId)
	end

	-- Leftover template spawns (e.g. the Baseplate place's SpawnLocation) would make players
	-- appear at the zone 1 gate instead of the hub spawn
	for _, item in Workspace:GetDescendants() do
		if item:IsA("SpawnLocation") and not item:IsDescendantOf(map) then
			item:Destroy()
		end
	end

	local parts = 0
	for _, item in map:GetDescendants() do
		if item:IsA("BasePart") then
			parts += 1
		end
	end
	MapService.Stats.Parts = parts
end

return MapService
