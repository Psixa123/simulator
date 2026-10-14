--!nonstrict
-- Renders the pets that follow every player. Pets are built locally from the
-- "EquippedPets" attribute the server sets on each player, so they move perfectly smoothly.
-- While the server has someone's pets catching weather (the "PetTarget" character attribute)
-- they fly over and circle that cell or the Mega Storm with a small beam, then come back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pets = require(Shared.Config.Pets)
local PetModels = require(Shared.Models.PetModels)

local Registry = require(script.Parent.Parent.Registry)

local PetController = {}

local MAX_DISTANCE = 220
local MEGA_TARGET = -1
local CATCH_REACH = 100 -- targets further than this from the owner are ignored (stale attribute)
local TARGET_GRACE = 0.5 -- keep circling a popped cell's spot while the server picks the next one
local ORBIT_SPEED = 1.6
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local BEAM_COLORS = {
	Normal = ColorSequence.new(Color3.fromRGB(190, 240, 255), Color3.fromRGB(110, 200, 255)),
	Golden = ColorSequence.new(Color3.fromRGB(255, 245, 170), Color3.fromRGB(255, 196, 50)),
	Rainbow = PetModels.RainbowSequence,
}

local localPlayer = Players.LocalPlayer
local folder: Folder
local owners = {} -- [Player] = { Signature, Pets = { { Model, Parts, CFrame, RainbowParts, Beam } }, Center }

local function parse(signature: string)
	local entries = {}
	for entry in string.gmatch(signature or "", "[^;]+") do
		local petId, code = string.match(entry, "^(.-):(%d)$")
		if petId then
			table.insert(entries, { Id = petId, Tier = Pets.TierCodes[code] or "Normal" })
		end
	end
	return entries
end

local function clearOwner(owner: Player)
	local state = owners[owner]
	if not state then
		return
	end
	for _, pet in state.Pets do
		pet.Model:Destroy()
	end
	owners[owner] = nil
end

local function showOtherPets(): boolean
	local settings = Registry.DataController.Get("Settings")
	return settings == nil or settings.OtherPets ~= false
end

local function lowGraphics(): boolean
	local settings = Registry.DataController.Get("Settings")
	return settings ~= nil and settings.LowGraphics == true
end

-- Small sparkly beam from the pet to whatever it is catching (hidden until needed)
local function createBeam(root: BasePart, tier: string, parent: Instance): Beam
	local attachment = Instance.new("Attachment")
	attachment.Name = "CatchBeam"
	attachment.Parent = root

	local beam = Instance.new("Beam")
	beam.Name = "CatchBeam"
	beam.Attachment0 = attachment
	beam.Width0 = 0.3
	beam.Width1 = 1.6
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Segments = 10
	beam.Texture = SPARKLE
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = 2
	beam.TextureSpeed = -2
	beam.Color = BEAM_COLORS[tier] or BEAM_COLORS.Normal
	beam.Transparency = NumberSequence.new(0.2, 0.75)
	beam.Enabled = false
	beam.Parent = parent
	return beam
end

local function rebuild(owner: Player)
	local signature = owner:GetAttribute("EquippedPets") or ""
	if owner ~= localPlayer and not showOtherPets() then
		signature = ""
	end
	local low = lowGraphics()
	local key = signature .. (if low then "|low" else "")
	local state = owners[owner]
	if state and state.Signature == key then
		return
	end
	clearOwner(owner)
	state = { Signature = key, Pets = {}, Center = nil, CenterTime = 0, Mega = false }
	owners[owner] = state

	local character = owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local start = if root then root.CFrame else CFrame.new()

	for _, entry in parse(signature) do
		local model, parts = PetModels.Build(entry.Id, entry.Tier, { Effects = not low })
		model.Name = owner.Name .. "_" .. entry.Id
		model:PivotTo(start)
		model.Parent = folder

		-- Rainbow pets cycle the hue of their tinted parts (keeping each part's own offset)
		local cycles = model:GetAttribute("Rainbow") == true
		local rainbowTier = entry.Tier == "Rainbow"
		local partList, rainbowParts = {}, {}
		for _, item in parts do
			table.insert(partList, item.Part)
			local tint = item.Part:GetAttribute("Tint")
			if cycles and (tint == "Body" or (rainbowTier and tint == "Accent")) then
				local hue, saturation = 0, 0.4
				if rainbowTier then
					hue, saturation = item.Part.Color:ToHSV()
				end
				table.insert(rainbowParts, { Part = item.Part, Hue = hue, Saturation = saturation })
			end
		end

		local petRoot = model.PrimaryPart
		table.insert(state.Pets, {
			Model = model,
			Root = petRoot,
			Parts = parts,
			PartList = partList,
			RainbowParts = rainbowParts,
			Light = if rainbowTier then petRoot:FindFirstChildOfClass("PointLight") else nil,
			Beam = if low then nil else createBeam(petRoot, entry.Tier, model),
			BeamTarget = nil,
			CFrame = start,
			Phase = math.random() * 10,
		})
	end
end

local function watch(owner: Player)
	owner:GetAttributeChangedSignal("EquippedPets"):Connect(function()
		rebuild(owner)
	end)
	rebuild(owner)
end

local function animationRotation(anim: string?, time: number): CFrame?
	if anim == "WingL" then
		return CFrame.Angles(0, 0, math.sin(time * 14) * 0.45)
	elseif anim == "WingR" then
		return CFrame.Angles(0, 0, -math.sin(time * 14) * 0.45)
	elseif anim == "SpinY" then
		return CFrame.Angles(0, time * 2, 0)
	elseif anim == "SpinZ" then
		return CFrame.Angles(0, 0, time * 1.5)
	elseif anim == "Wag" then
		return CFrame.Angles(0, math.sin(time * 9) * 0.35, 0)
	end
	return nil
end

-- Where a pet part sits (relative to the pet's root) at this time
local function animationOffset(item, time: number): CFrame
	local rotation = animationRotation(item.Anim, time)
	if not rotation then
		return item.Offset
	elseif item.Pivot then
		-- Mesh pieces turn around their hinge, along the pet's axes
		return item.Pivot * rotation * item.Pivot:Inverse() * item.Offset
	elseif item.Anim == "SpinY" or item.Anim == "SpinZ" then
		return rotation * item.Offset -- around the pet's centre
	end
	return item.Offset * rotation -- primitives turn around their own centre
end
PetController.AnimationOffset = animationOffset -- (for tests)

-- The "Target" attachment of the cell (or Mega Storm) a PetTarget id points at
local function findTarget(targetId: number): Attachment?
	local targetRoot
	if targetId == MEGA_TARGET then
		local stormFolder = Workspace:FindFirstChild("MegaStorm")
		local storm = stormFolder and stormFolder:FindFirstChild("MegaStorm")
		targetRoot = storm and storm:FindFirstChild("Root")
	else
		local model = Registry.EffectsController.GetCell(targetId)
		targetRoot = model and model:FindFirstChild("Root")
	end
	local target = targetRoot and targetRoot:FindFirstChild("Target")
	return if target and target:IsA("Attachment") then target else nil
end

-- Updates where an owner's pets are catching. Returns the attachment to beam at (if any).
local function updateCatchTarget(state, character: Model, root: BasePart, now: number): Attachment?
	local targetId = character:GetAttribute("PetTarget") or 0
	local target = if targetId ~= 0 then findTarget(targetId) else nil
	if target and (target.WorldPosition - root.Position).Magnitude > CATCH_REACH then
		target = nil
	end
	if target then
		state.Center = target.WorldPosition
		state.CenterTime = now
		state.Mega = targetId == MEGA_TARGET
	elseif targetId == 0 or not state.Center or now - state.CenterTime > TARGET_GRACE then
		state.Center = nil
	end
	return target
end

local function setBeam(pet, target: Attachment?)
	local beam = pet.Beam
	if not beam or pet.BeamTarget == target then
		return
	end
	pet.BeamTarget = target
	beam.Attachment1 = target
	beam.Enabled = target ~= nil
end

local function step(dt: number)
	local now = os.clock()
	local cameraPosition = Workspace.CurrentCamera.CFrame.Position
	local alpha = 1 - math.exp(-dt * 9)
	local catchAlpha = 1 - math.exp(-dt * 5)
	local bulkParts, bulkCFrames = {}, {}

	for owner, state in owners do
		local character = owner.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local count = #state.Pets
		if root and count > 0 then
			local visible = (root.Position - cameraPosition).Magnitude < MAX_DISTANCE
			local _, yaw, _ = root.CFrame:ToEulerAnglesYXZ()
			local base = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
			local moving = root.AssemblyLinearVelocity.Magnitude > 2
			local catchTarget = updateCatchTarget(state, character, root, now)
			local center = state.Center

			for index, pet in state.Pets do
				local row = math.floor((index - 1) / 4)
				local column = (index - 1) % 4
				local inRow = math.min(4, count - row * 4)
				local angle = (column - (inRow - 1) / 2) * 0.6
				local distance = 6 + row * 3.5
				local offset = Vector3.new(math.sin(angle) * distance, 0, math.cos(angle) * distance)
				local target = base * CFrame.new(offset)
				local hop = if moving then math.abs(math.sin(now * 9 + pet.Phase)) * 1.1 else math.sin(now * 2.5 + pet.Phase) * 0.35
				local height = root.Position.Y - 1.1 + hop
				local goal = CFrame.new(target.Position.X, height, target.Position.Z) * CFrame.Angles(0, yaw, 0)
				local speed = alpha
				if center then
					-- Circle the weather the pets are catching
					local radius = if state.Mega then 24 else 7 + count * 0.3
					local orbit = now * ORBIT_SPEED + (index - 1) / count * math.pi * 2
					local bob = math.sin(now * 3 + pet.Phase) * 0.6
					local position = center + Vector3.new(math.cos(orbit) * radius, bob - 1, math.sin(orbit) * radius)
					goal = CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z))
					speed = catchAlpha
				end

				pet.CFrame = pet.CFrame:Lerp(goal, speed)
				setBeam(pet, catchTarget)
				if visible then
					local time = now + pet.Phase
					for _, item in pet.Parts do
						table.insert(bulkParts, item.Part)
						table.insert(bulkCFrames, pet.CFrame * animationOffset(item, time))
					end
					table.insert(bulkParts, pet.Root)
					table.insert(bulkCFrames, pet.CFrame)
					if #pet.RainbowParts > 0 then
						local shift = now * 0.15 + pet.Phase
						for _, item in pet.RainbowParts do
							item.Part.Color = Color3.fromHSV((shift + item.Hue) % 1, item.Saturation, 1)
						end
						if pet.Light then
							pet.Light.Color = Color3.fromHSV(shift % 1, 0.45, 1)
						end
					end
				end
			end
		end
	end

	if #bulkParts > 0 then
		Workspace:BulkMoveTo(bulkParts, bulkCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function PetController.Init()
	folder = Instance.new("Folder")
	folder.Name = "ClientPets"
	folder.Parent = Workspace
end

function PetController.Start()
	for _, owner in Players:GetPlayers() do
		watch(owner)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(clearOwner)

	Registry.DataController.Observe("Settings", function()
		for _, owner in Players:GetPlayers() do
			rebuild(owner)
		end
	end)

	RunService.RenderStepped:Connect(step)
end

return PetController
