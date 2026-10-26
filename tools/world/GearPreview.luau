--!nonstrict
-- Gear preview for tools/preview_map.py --script (tools/world/README.md, "Gear props"): R15-shaped characters
-- holding the Storm Vacuum (right arm raised like Roblox's tool-hold pose) and wearing the Storm Tank, built by
-- the real CharacterGear (pack meshes when the pack has them), in a few Climate Shift looks and tank fills.
-- Characters stand at x = 0, 8, 16, 24 facing -Z. Runs in the preview mock only (it is not part of the game).

local Workspace = game:GetService("Workspace")

local CharacterGear = require(script.Parent.CharacterGear)

local Preview = {}

local SKIN = Color3.fromRGB(255, 205, 148)
local SHIRT = Color3.fromRGB(92, 200, 255)
local PANTS = Color3.fromRGB(58, 64, 120)

local function block(name, size, cframe, color, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function attach(part, name, cframe)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cframe
	a.Parent = part
	return a
end

-- A blocky R15 rig like the mock's (HumanoidRootPart 3 studs above the feet), right arm raised forward
local function rig(origin: CFrame, parent)
	local model = Instance.new("Model")
	model.Name = "Dummy"
	model.Parent = parent
	local function limb(name, size, offset, color)
		return block(name, size, origin * offset, color, model)
	end
	local root = limb("HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(), SHIRT)
	root.Transparency = 1
	limb("LowerTorso", Vector3.new(2, 0.4, 1), CFrame.new(0, -0.8, 0), PANTS)
	local upper = limb("UpperTorso", Vector3.new(2, 1.6, 1), CFrame.new(0, 0.2, 0), SHIRT)
	attach(upper, "BodyBackAttachment", CFrame.new(0, 0.2, 0.5))
	limb("Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 1.6, 0), SKIN)
	-- arms: the right one turned 90 degrees forward about the shoulder (tool hold), the left one down
	local shoulder = CFrame.new(1.5, 1.0, 0) * CFrame.Angles(math.rad(90), 0, 0) * CFrame.new(-1.5, -1.0, 0)
	limb("RightUpperArm", Vector3.new(1, 1.2, 1), shoulder * CFrame.new(1.5, 0.4, 0), SHIRT)
	limb("RightLowerArm", Vector3.new(1, 1.1, 1), shoulder * CFrame.new(1.5, -0.6, 0), SKIN)
	local hand = limb("RightHand", Vector3.new(0.6, 0.6, 0.6), shoulder * CFrame.new(1.5, -1.1, 0), SKIN)
	attach(hand, "RightGripAttachment", CFrame.new(0, -0.15, 0) * CFrame.Angles(-math.pi / 2, 0, 0))
	limb("LeftUpperArm", Vector3.new(1, 1.2, 1), CFrame.new(-1.5, 0.4, 0), SHIRT)
	limb("LeftLowerArm", Vector3.new(1, 1.1, 1), CFrame.new(-1.5, -0.6, 0), SKIN)
	limb("LeftHand", Vector3.new(0.6, 0.6, 0.6), CFrame.new(-1.5, -1.1, 0), SKIN)
	for _, side in { -1, 1 } do
		limb("Leg", Vector3.new(1, 2.4, 1), CFrame.new(side * 0.5, -2.2, 0), PANTS)
	end
	model.PrimaryPart = root
	return model, upper, hand
end

-- Holds the tool's Handle at the hand's RightGripAttachment (what Humanoid:EquipTool does)
local function hold(tool: Tool, hand: BasePart, model: Model)
	local grip = hand:FindFirstChild("RightGripAttachment")
	local target = hand.CFrame * grip.CFrame * tool.Grip:Inverse()
	local handle = tool:FindFirstChild("Handle")
	local base = handle.CFrame
	for _, part in tool:GetDescendants() do
		if part:IsA("BasePart") then
			part.CFrame = target * base:ToObjectSpace(part.CFrame)
		end
	end
	tool.Parent = model
end

function Preview.Init()
	local folder = Instance.new("Folder")
	folder.Name = "Map"
	folder.Parent = Workspace
	block("Pad", Vector3.new(60, 1, 30), CFrame.new(12, -0.5, 0), Color3.fromRGB(201, 208, 247), folder)
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(4, 0.2, 4)
	spawn.CFrame = CFrame.new(40, 0.1, 10)
	spawn.Parent = folder

	-- shifts (look), tank fill
	local cases = { { 0, 0.6 }, { 2, 1 }, { 8, 0.3 }, { 12, 0.85 } }
	for index, case in cases do
		local model, upper, hand = rig(CFrame.new((index - 1) * 8, 3, 0), folder)
		local tool = CharacterGear.BuildVacuum()
		hold(tool, hand, model)
		local tank = CharacterGear.BuildTank()
		CharacterGear.AttachTank(model, tank, upper:FindFirstChild("BodyBackAttachment"))
		CharacterGear.ApplyCosmetic(tool, case[1])
		CharacterGear.ApplyCosmetic(tank, case[1])
		CharacterGear.SetTankFill(tank, case[2])
		print(`gear {index}: vacuum mesh {tostring(tool:GetAttribute("GearMesh"))}, tank mesh {tostring(tank:GetAttribute("GearMesh"))}`)
	end
end

function Preview.Start() end

return Preview
