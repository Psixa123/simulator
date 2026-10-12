--!nonstrict
-- Builds egg models (world egg stations and the hatching animation).

local Config = script.Parent.Parent:WaitForChild("Config")
local Pets = require(Config.Pets)

local EggModels = {}

-- Spots on the shell: angle around, elevation, size
local SPOTS = {
	{ 0.3, 0.35, 1.0 },
	{ 1.9, 0.55, 0.8 },
	{ 3.4, 0.25, 1.1 },
	{ 4.6, 0.6, 0.7 },
	{ 5.5, -0.35, 0.9 },
	{ 1.0, -0.4, 0.85 },
	{ 2.7, -0.5, 0.75 },
	{ 4.0, -0.15, 0.8 },
}

local function newPart(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Parent = model
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- `height` is the egg's height in studs; the model is centered on the origin
function EggModels.Build(eggId: string, height: number): Model
	local egg = Pets.Eggs[eggId]
	local model = Instance.new("Model")
	model.Name = egg and egg.Name or "Egg"

	local width = height * 0.78
	local color = egg and egg.Color or Color3.new(1, 1, 1)
	local accent = egg and egg.Accent or Color3.new(0.8, 0.8, 0.8)

	local shell = newPart(model, "Shell", Vector3.new(width, height, width), CFrame.new(), color)
	shell.CastShadow = true
	model.PrimaryPart = shell

	for _, spot in SPOTS do
		local theta, phi, size = spot[1], spot[2], spot[3]
		local position = Vector3.new(
			width / 2 * math.cos(phi) * math.cos(theta),
			height / 2 * math.sin(phi),
			width / 2 * math.cos(phi) * math.sin(theta)
		) * 0.94
		local spotSize = width * 0.26 * size
		newPart(
			model,
			"Spot",
			Vector3.new(spotSize, spotSize, spotSize * 0.4),
			CFrame.lookAt(position, position * 2),
			accent
		)
	end

	return model
end

return EggModels
