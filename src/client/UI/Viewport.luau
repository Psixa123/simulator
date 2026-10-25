--!nonstrict
-- ViewportFrames that show 3D pets and eggs inside the interface.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetModels = require(Shared.Models.PetModels)
local EggModels = require(Shared.Models.EggModels)

local Viewport = {}

local FIELD_OF_VIEW = 32

local function newViewport(props)
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = props.Name or "Viewport"
	viewport.BackgroundTransparency = 1
	viewport.Size = props.Size or UDim2.fromScale(1, 1)
	viewport.Position = props.Position or UDim2.new()
	viewport.AnchorPoint = props.AnchorPoint or Vector2.zero
	viewport.Ambient = Color3.fromRGB(170, 170, 185)
	viewport.LightColor = Color3.fromRGB(255, 250, 240)
	viewport.LightDirection = Vector3.new(-0.6, -1, -0.8)
	viewport.ZIndex = props.ZIndex or 1
	viewport.LayoutOrder = props.LayoutOrder or 0

	local camera = Instance.new("Camera")
	camera.FieldOfView = FIELD_OF_VIEW
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport, camera
end

local function frame(camera: Camera, model: Model, zoom: number?)
	local _, size = model:GetBoundingBox()
	local radius = math.max(size.X, size.Y, size.Z) * 0.5
	local distance = radius / math.tan(math.rad(FIELD_OF_VIEW / 2)) * (zoom or 1.15)
	local center = model:GetPivot().Position
	camera.CFrame = CFrame.lookAt(center + Vector3.new(0, radius * 0.35, -distance), center)
end

local livePets = {} -- [ViewportFrame] = view, for every pet viewport that hasn't been destroyed

local function buildPet(view)
	local model = PetModels.Build(view.PetId, view.Tier, { Effects = false })
	model:PivotTo(CFrame.Angles(0, view.Angle, 0))
	if view.Silhouette then
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Color = Color3.fromRGB(20, 22, 40)
				descendant.Material = Enum.Material.SmoothPlastic
				descendant.Reflectance = 0
			end
		end
	end
	model.Parent = view.Frame
	return model
end

-- When the mesh pack arrives (or goes) after pets were shown, rebuild them in place
PetModels.OnPackChanged(function()
	for _, view in livePets do
		local old = view.Model
		view.Model = buildPet(view)
		old:Destroy()
	end
end)

-- Shows a pet. tier = "Normal" | "Golden" | "Rainbow" (or a golden boolean).
-- Returns { Frame, Model, SetRotation(angle), Destroy() }
function Viewport.Pet(petId: string, tier, props)
	props = props or {}
	local viewport, camera = newViewport(props)
	local view = {
		Frame = viewport,
		PetId = petId,
		Tier = tier,
		Angle = math.rad(props.Angle or 20),
		Silhouette = props.Silhouette == true,
	}
	view.Model = buildPet(view)
	frame(camera, view.Model, props.Zoom) -- keeps this framing if the model is rebuilt with the pack
	if view.Silhouette then
		viewport.Ambient = Color3.fromRGB(40, 40, 60)
	end

	livePets[viewport] = view
	viewport.Destroying:Connect(function()
		livePets[viewport] = nil
	end)

	if props.Parent then
		viewport.Parent = props.Parent
	end

	function view.SetRotation(angle: number)
		view.Angle = angle
		view.Model:PivotTo(CFrame.Angles(0, angle, 0))
	end
	function view.Destroy()
		viewport:Destroy()
	end
	return view
end

-- Shows an egg. Returns { Frame, Model, SetCFrame(cframe) }
function Viewport.Egg(eggId: string, props)
	props = props or {}
	local viewport, camera = newViewport(props)
	local model = EggModels.Build(eggId, 4)
	model:PivotTo(CFrame.new())
	model.Parent = viewport
	frame(camera, model, props.Zoom or 1.35)

	if props.Parent then
		viewport.Parent = props.Parent
	end

	local view = { Frame = viewport, Model = model }
	function view.SetCFrame(cframe: CFrame)
		model:PivotTo(cframe)
	end

	-- The hatching animation squashes, rocks and heats up the egg in place (the camera stays put).
	-- Every part remembers where it was built; the shape is always computed from that.
	local parts = {}
	local shell = model.PrimaryPart
	local half = if shell then shell.Size.Y / 2 else 2
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(parts, { Part = part, CFrame = part.CFrame, Size = part.Size, Color = part.Color, Shell = part == shell })
		end
	end
	local ambient = viewport.Ambient
	local light = viewport.LightColor

	-- roll: radians around the egg's bottom (positive turns it clockwise as the camera sees it);
	-- sx / sy: width / height factors, squashing towards the bottom; lift: studs up
	function view.SetShape(roll: number, sx: number, sy: number, lift: number?)
		local pivot = CFrame.new(0, -half + (lift or 0), 0) * CFrame.Angles(0, 0, roll)
		local spotScale = (sx + sy) / 2
		for _, entry in parts do
			local position = entry.CFrame.Position
			local moved = Vector3.new(position.X * sx, (position.Y + half) * sy, position.Z * sx)
			entry.Part.CFrame = pivot * CFrame.new(moved) * entry.CFrame.Rotation
			entry.Part.Size = if entry.Shell then entry.Size * Vector3.new(sx, sy, sx) else entry.Size * spotScale
		end
	end

	-- 0 = as built, 1 = glowing white-hot (just before it bursts)
	function view.SetGlow(amount: number)
		local k = math.clamp(amount, 0, 1)
		viewport.Ambient = ambient:Lerp(Color3.new(1, 1, 1), k)
		viewport.LightColor = light:Lerp(Color3.new(1, 1, 1), k)
		for _, entry in parts do
			entry.Part.Color = entry.Color:Lerp(Color3.new(1, 1, 1), k * 0.8)
		end
	end
	return view
end

return Viewport
