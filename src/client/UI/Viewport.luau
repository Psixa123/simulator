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

-- Shows a pet. Returns { Frame, Model, SetRotation(angle), Destroy() }
function Viewport.Pet(petId: string, golden: boolean?, props)
	props = props or {}
	local viewport, camera = newViewport(props)
	local model = PetModels.Build(petId, golden, { Effects = false })
	model:PivotTo(CFrame.Angles(0, math.rad(props.Angle or 20), 0))
	model.Parent = viewport
	frame(camera, model, props.Zoom)

	if props.Silhouette then
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Color = Color3.fromRGB(20, 22, 40)
				descendant.Material = Enum.Material.SmoothPlastic
				descendant.Reflectance = 0
			end
		end
		viewport.Ambient = Color3.fromRGB(40, 40, 60)
	end

	if props.Parent then
		viewport.Parent = props.Parent
	end

	local view = { Frame = viewport, Model = model }
	function view.SetRotation(angle: number)
		model:PivotTo(CFrame.Angles(0, angle, 0))
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
	return view
end

return Viewport
