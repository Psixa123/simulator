--!nonstrict
-- Builds the gear every storm catcher carries: the Storm Vacuum tool, the Storm Tank
-- backpack (its glowing fill shows how full your tank is) and the overhead name tag,
-- and paints the tank and vacuum in the look the player's Climate Shifts unlock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClimateShift = require(Shared.ClimateShift)

local CharacterGear = {}

local ACCENT = Color3.fromRGB(70, 200, 255)
local FULL = Color3.fromRGB(255, 196, 60)
local METAL = Color3.fromRGB(58, 64, 82)
local LIGHT_METAL = Color3.fromRGB(160, 170, 192)
local GLASS = Color3.fromRGB(210, 240, 255)

local ALONG_Z = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis along Z
local VERTICAL = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis along Y

local TANK_INNER_HEIGHT = 1.8
local TANK_OFFSET_Z = 0.72

local function gearPart(props)
	local part = Instance.new("Part")
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
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

---------------------------------------------------------------------------
-- Storm Vacuum (Tool). Handle is the grip; the barrel points along -Z.
---------------------------------------------------------------------------
function CharacterGear.BuildVacuum(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "StormVacuum"
	tool.ToolTip = "Hold to vacuum up weather!"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = CFrame.new(0, 0, 0)

	local handle = gearPart({
		Name = "Handle",
		Size = Vector3.new(0.45, 1, 0.55),
		CFrame = CFrame.new(),
		Color = METAL,
		Parent = tool,
	})

	local function piece(props)
		props.Parent = tool
		local part = gearPart(props)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = part
		return part
	end

	piece({ Name = "Body", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.6, 1, 1), CFrame = CFrame.new(0, 0.62, -0.55) * ALONG_Z, Color = LIGHT_METAL })
	piece({ Name = "BackCap", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.12, 1.12), CFrame = CFrame.new(0, 0.62, 0.78) * ALONG_Z, Color = METAL })
	piece({ Name = "Ring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.14, 1.08, 1.08), CFrame = CFrame.new(0, 0.62, -0.95) * ALONG_Z, Color = ACCENT, Material = Enum.Material.Neon })
	piece({ Name = "Ring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.14, 1.08, 1.08), CFrame = CFrame.new(0, 0.62, -1.4) * ALONG_Z, Color = ACCENT, Material = Enum.Material.Neon })
	piece({ Name = "Nozzle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 1.45, 1.45), CFrame = CFrame.new(0, 0.62, -2.25) * ALONG_Z, Color = METAL })
	local glow = piece({ Name = "NozzleGlow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 1.15, 1.15), CFrame = CFrame.new(0, 0.62, -2.72) * ALONG_Z, Color = ACCENT, Material = Enum.Material.Neon })
	piece({ Name = "Canister", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.95, CFrame = CFrame.new(0, 1.35, -0.1), Color = GLASS, Material = Enum.Material.Glass, Transparency = 0.35 })
	piece({ Name = "CanisterCore", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.6, CFrame = CFrame.new(0, 1.35, -0.1), Color = ACCENT, Material = Enum.Material.Neon })
	piece({ Name = "Trigger", Size = Vector3.new(0.18, 0.35, 0.25), CFrame = CFrame.new(0, 0.2, -0.38), Color = FULL })

	local nozzle = Instance.new("Attachment")
	nozzle.Name = "NozzleAttachment"
	nozzle.Position = Vector3.new(0, 0.62, -2.85)
	nozzle.Parent = handle

	local light = Instance.new("PointLight")
	light.Name = "NozzleLight"
	light.Color = ACCENT
	light.Brightness = 1
	light.Range = 6
	light.Shadows = false
	light.Parent = glow

	return tool
end

---------------------------------------------------------------------------
-- Storm Tank backpack
---------------------------------------------------------------------------
local function attachPiece(model: Model, plate: BasePart, props, offset: CFrame)
	props.Parent = model
	local part = gearPart(props)
	part.CFrame = plate.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Name = "Weld"
	weld.Part0 = plate
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
	return part, weld
end

function CharacterGear.BuildTank(): Model
	local model = Instance.new("Model")
	model.Name = "StormTank"

	local plate = gearPart({
		Name = "Plate",
		Size = Vector3.new(1.5, 1.9, 0.3),
		CFrame = CFrame.new(),
		Color = METAL,
		Parent = model,
	})
	model.PrimaryPart = plate

	attachPiece(model, plate, { Name = "Glass", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 1.25, 1.25), Color = GLASS, Material = Enum.Material.Glass, Transparency = 0.5 }, CFrame.new(0, 0, TANK_OFFSET_Z) * VERTICAL)
	attachPiece(model, plate, { Name = "CapTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.24, 1.42, 1.42), Color = LIGHT_METAL }, CFrame.new(0, 1.08, TANK_OFFSET_Z) * VERTICAL)
	attachPiece(model, plate, { Name = "CapBottom", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.24, 1.42, 1.42), Color = LIGHT_METAL }, CFrame.new(0, -1.08, TANK_OFFSET_Z) * VERTICAL)
	attachPiece(model, plate, { Name = "Band", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 1.32, 1.32), Color = ACCENT, Material = Enum.Material.Neon }, CFrame.new(0, 0.55, TANK_OFFSET_Z) * VERTICAL)
	attachPiece(model, plate, { Name = "Valve", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35, 0.35, 0.35), Color = FULL }, CFrame.new(0, 1.3, TANK_OFFSET_Z) * VERTICAL)

	local fill, fillWeld = attachPiece(model, plate, {
		Name = "Fill",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.05, 1.05, 1.05),
		Color = ACCENT,
		Material = Enum.Material.Neon,
		Transparency = 1,
	}, CFrame.new(0, -TANK_INNER_HEIGHT / 2, TANK_OFFSET_Z) * VERTICAL)
	fillWeld.Name = "FillWeld"
	fill:SetAttribute("Fraction", 0)

	return model
end

function CharacterGear.AttachTank(character: Model, tank: Model, attachment: Attachment): Weld
	local torso = attachment.Parent :: BasePart
	local plate = tank.PrimaryPart
	local offset = attachment.CFrame * CFrame.new(0, 0, 0.2)
	tank:PivotTo(torso.CFrame * offset)
	local weld = Instance.new("Weld")
	weld.Name = "TankWeld"
	weld.Part0 = torso
	weld.Part1 = plate
	weld.C0 = offset
	weld.Parent = plate
	tank.Parent = character
	return weld
end

function CharacterGear.SetTankFill(tank: Model, fraction: number)
	local fill = tank:FindFirstChild("Fill")
	local weld = fill and fill:FindFirstChild("FillWeld")
	if not fill or not weld then
		return
	end
	local height = math.max(0.05, fraction * TANK_INNER_HEIGHT)
	fill.Size = Vector3.new(height, 1.05, 1.05)
	weld.C0 = CFrame.new(0, -TANK_INNER_HEIGHT / 2 + height / 2, TANK_OFFSET_Z) * VERTICAL
	fill.Transparency = if fraction <= 0.001 then 1 else 0
	fill.Color = if fraction >= 0.999 then FULL else (tank:GetAttribute("GlowColor") or ACCENT)
	fill:SetAttribute("Fraction", fraction)
end

---------------------------------------------------------------------------
-- Climate Shift looks (GameConfig.Rebirth.Cosmetics)
---------------------------------------------------------------------------
-- Part name -> which colour of the look it takes
local VACUUM_SLOTS = {
	Handle = "Trim",
	BackCap = "Trim",
	Nozzle = "Trim",
	Body = "Vacuum",
	Ring = "Glow",
	NozzleGlow = "Glow",
	CanisterCore = "Glow",
}
local TANK_SLOTS = {
	Plate = "Trim",
	CapTop = "Tank",
	CapBottom = "Tank",
	Band = "Glow",
}

local function lookColors(look)
	return {
		Tank = look.Tank or LIGHT_METAL,
		Vacuum = look.Vacuum or look.Tank or LIGHT_METAL,
		Glow = look.Glow or ACCENT,
		Trim = look.Trim or METAL,
	}
end

-- Streak behind the tank while running (only looks with a Trail colour have one)
local function setTrail(tank: Model, color)
	local plate = tank.PrimaryPart
	if not plate then
		return
	end
	local trail = plate:FindFirstChild("LookTrail")
	if not color then
		for _, name in { "LookTrail", "TrailTop", "TrailBottom" } do
			local child = plate:FindFirstChild(name)
			if child then
				child:Destroy()
			end
		end
		return
	end
	if not trail then
		local top = Instance.new("Attachment")
		top.Name = "TrailTop"
		top.Position = Vector3.new(0, 0.9, TANK_OFFSET_Z)
		top.Parent = plate
		local bottom = Instance.new("Attachment")
		bottom.Name = "TrailBottom"
		bottom.Position = Vector3.new(0, -0.9, TANK_OFFSET_Z)
		bottom.Parent = plate

		trail = Instance.new("Trail")
		trail.Name = "LookTrail"
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.Lifetime = 0.35
		trail.MinLength = 0.05
		trail.FaceCamera = true
		trail.LightEmission = 0.7
		trail.Transparency = NumberSequence.new(0.3, 1)
		trail.WidthScale = NumberSequence.new(1, 0.3)
		trail.Parent = plate
	end
	trail.Color = if typeof(color) == "ColorSequence" then color else ColorSequence.new(color)
end

-- Paints a Storm Tank or Storm Vacuum in the best look `shifts` Climate Shifts unlock.
-- Cheap to call again and again: gear that already wears that look is skipped.
function CharacterGear.ApplyCosmetic(gear: Instance, shifts: number)
	local look, tier = ClimateShift.Cosmetic(shifts)
	if gear:GetAttribute("CosmeticTier") == tier then
		return
	end
	local colors = lookColors(look)
	local isVacuum = gear:IsA("Tool")
	local slots = if isVacuum then VACUUM_SLOTS else TANK_SLOTS
	for _, descendant in gear:GetDescendants() do
		if descendant:IsA("BasePart") then
			local slot = slots[descendant.Name]
			if slot then
				descendant.Color = colors[slot]
			end
		elseif descendant:IsA("PointLight") then
			descendant.Color = colors.Glow
		end
	end
	gear:SetAttribute("CosmeticTier", tier)
	gear:SetAttribute("GlowColor", colors.Glow)

	if not isVacuum and gear:IsA("Model") then
		local fill = gear:FindFirstChild("Fill")
		if fill and fill:IsA("BasePart") then
			fill.Color = if (fill:GetAttribute("Fraction") or 0) >= 0.999 then FULL else colors.Glow
		end
		setTrail(gear, look.Trail)
	end
end

-- Dresses the player's current tank and vacuum (equipped or in the backpack) in their best look.
-- `shifts` defaults to the player's "Rebirths" attribute (kept up to date by PlayerService).
function CharacterGear.DressPlayer(player: Player, shifts: number?)
	local count = shifts or player:GetAttribute("Rebirths") or 0
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	local tank = character and character:FindFirstChild("StormTank")
	local vacuum = (character and character:FindFirstChild("StormVacuum"))
		or (backpack and backpack:FindFirstChild("StormVacuum"))
	if tank then
		CharacterGear.ApplyCosmetic(tank, count)
	end
	if vacuum then
		CharacterGear.ApplyCosmetic(vacuum, count)
	end
end

---------------------------------------------------------------------------
-- Overhead tag (VIP crown + Climate Shift count)
---------------------------------------------------------------------------
local function tagLabel(name: string, color: Color3, order: number, parent: Instance)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0.5, 0)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.LayoutOrder = order
	label.Visible = false
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(15, 18, 40)
	stroke.Parent = label
	label.Parent = parent
	return label
end

function CharacterGear.BuildOverhead(): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "Overhead"
	gui.Size = UDim2.fromOffset(180, 46)
	gui.StudsOffset = Vector3.new(0, 2.7, 0)
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = gui

	tagLabel("Vip", Color3.fromRGB(255, 214, 64), 1, gui)
	tagLabel("Rebirth", Color3.fromRGB(110, 220, 255), 2, gui)
	return gui
end

function CharacterGear.UpdateOverhead(gui: BillboardGui, isVip: boolean, rebirths: number)
	local vip = gui:FindFirstChild("Vip")
	local rebirth = gui:FindFirstChild("Rebirth")
	if vip then
		vip.Visible = isVip
		vip.Text = "👑 VIP"
	end
	if rebirth then
		rebirth.Visible = rebirths > 0
		rebirth.Text = "🌀 Climate Shift " .. rebirths
		rebirth.TextColor3 = ClimateShift.Cosmetic(rebirths).Glow
	end
	gui.Enabled = isVip or rebirths > 0
end

return CharacterGear
