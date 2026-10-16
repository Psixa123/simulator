--!nonstrict
-- Prop showcase for tools/preview_map.py --showcase: places every prop of the world prop pack with the
-- game's own WorldProps.Place on a lavender pad, so the pack, WorldProps and the renderer can be checked
-- without a map that uses them. Runs in the preview mock only (it is not part of the game).
--
--   row 1 (front, z = 0)   every prop with its default paints (WorldPropsData), a name sign in front
--   row 2 (z = +ROW)       the same props tinted with a biome palette (options.Paints), one biome each
--   row 3 (z = +2 ROW)     scaled: uniform 1.6 and a stretched Vector3 (options.Scale), alternating
--
-- Props face -Z, so the showcase shots look at the rows from the -Z side.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WorldProps = require(script.Parent.WorldProps)
local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local WorldPropsData = require(Config:WaitForChild("WorldPropsData"))

local Showcase = {}

local GAP = 6 -- studs between props in a row
local ROW = 30 -- studs between rows
local INK = Color3.fromHex("233066")
local PAD = Color3.fromHex("C9D0F7")
local PAD_LIGHT = Color3.fromHex("DDE2FB")

-- STYLE_GUIDE biome palettes: Primary = ground colour, Secondary = field colour, Tertiary = darker
local BIOMES = {
	{ Name = "Sunny Plains", Primary = "6EE05A", Secondary = "8BEA5E", Tertiary = "33B24A" },
	{ Name = "Thunder Valley", Primary = "7C74E8", Secondary = "9A92F5", Tertiary = "4B44B0" },
	{ Name = "Dune Sea", Primary = "FFD27A", Secondary = "FFE19A", Tertiary = "D9A048" },
	{ Name = "Frostpeak", Primary = "EAF6FF", Secondary = "D6EEFF", Tertiary = "9CCBEF" },
	{ Name = "Ashfall Volcano", Primary = "8A5A4E", Secondary = "B5705A", Tertiary = "5A3A34" },
	{ Name = "Upper Atmosphere", Primary = "C9B8FF", Secondary = "E2D8FF", Tertiary = "9C84E8" },
}

local function block(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Parent = parent
	return part
end

local function sign(text: string, position: Vector3, width: number, parent: Instance)
	local board = block("Sign", Vector3.new(width, 2.2, 0.4), CFrame.new(position), Color3.new(1, 1, 1), parent)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front -- -Z, towards the camera
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = INK
	label.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = label
end

local function setLighting()
	-- STYLE_GUIDE "Lighting": bright midday, high OutdoorAmbient, light bloom
	Lighting.ClockTime = 13.5
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(120, 124, 150)
	Lighting.OutdoorAmbient = Color3.fromRGB(170, 170, 190)
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.25
	atmosphere.Color = Color3.fromRGB(199, 222, 255)
	atmosphere.Parent = Lighting
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Saturation = 0.2
	grade.Contrast = 0.06
	grade.Parent = Lighting
end

function Showcase.Init()
	setLighting()
	if not WorldProps.Load() then
		error("WorldProps.Load() found no usable props (see the warnings above): is assets/models/StormWorldProps.glb there?", 0)
	end
	local ids = WorldProps.Ids()
	local root = Instance.new("Folder")
	root.Name = "PropShowcase"
	root.Parent = Workspace

	-- slot widths from WorldPropsData (falls back to 10 studs)
	local widths, total = {}, 0
	for index, id in ids do
		local info = WorldPropsData.Props[id]
		local size = info and info.Size or Vector3.new(10, 10, 10)
		widths[index] = math.max(size.X, size.Z, 4) * 1.6 + GAP -- room for the scaled row
		total += widths[index]
	end

	local x = -total / 2
	local placed = 0
	for index, id in ids do
		local width = widths[index]
		local cx = x + width / 2
		x += width
		local info = WorldPropsData.Props[id]
		local depth = info and info.Size and info.Size.Z or 8

		-- row 1: default paints
		if WorldProps.Place(id, root, CFrame.new(cx, 0, 0)) then
			placed += 1
		end
		sign(id, Vector3.new(cx, 1.1, -depth * 0.5 - 3), math.min(width - 1, math.max(8, #id * 1.1)), root)

		-- row 2: a biome palette
		local biome = BIOMES[(index - 1) % #BIOMES + 1]
		WorldProps.Place(id, root, CFrame.new(cx, 0, ROW) * CFrame.Angles(0, math.rad(20), 0), {
			Paints = {
				Primary = Color3.fromHex(biome.Primary),
				Secondary = Color3.fromHex(biome.Secondary),
				Tertiary = Color3.fromHex(biome.Tertiary),
			},
		})

		-- row 3: scaled
		local scale = if index % 2 == 1 then 1.6 else Vector3.new(1.4, 0.8, 1.4)
		WorldProps.Place(id, root, CFrame.new(cx, 0, ROW * 2), { Scale = scale })
	end

	-- the pad under the rows (a lighter strip under each row)
	local length = total + 16
	block("Pad", Vector3.new(length, 1, ROW * 3 + 16), CFrame.new(0, -0.5, ROW), PAD, root)
	for row = 0, 2 do
		block("Strip", Vector3.new(length - 8, 0.2, ROW - 10), CFrame.new(0, 0.05, row * ROW), PAD_LIGHT, root)
	end
	print(`[PropShowcase] placed {placed} of {#ids} props: {table.concat(ids, ", ")}`)
end

return Showcase
