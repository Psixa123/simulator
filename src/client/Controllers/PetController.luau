--!nonstrict
-- Renders the pets that follow every player. Pets are built locally from the
-- "EquippedPets" attribute the server sets on each player, so they move perfectly smoothly.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetModels = require(Shared.Models.PetModels)

local Registry = require(script.Parent.Parent.Registry)

local PetController = {}

local MAX_DISTANCE = 220
local localPlayer = Players.LocalPlayer
local folder: Folder
local owners = {} -- [Player] = { Signature, Pets = { { Model, Parts, CFrame, Rainbow } } }

local function parse(signature: string)
	local entries = {}
	for entry in string.gmatch(signature or "", "[^;]+") do
		local petId, golden = string.match(entry, "^(.-):(%d)$")
		if petId then
			table.insert(entries, { Id = petId, Golden = golden == "1" })
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

local function rebuild(owner: Player)
	local signature = owner:GetAttribute("EquippedPets") or ""
	if owner ~= localPlayer and not showOtherPets() then
		signature = ""
	end
	local state = owners[owner]
	if state and state.Signature == signature then
		return
	end
	clearOwner(owner)
	state = { Signature = signature, Pets = {} }
	owners[owner] = state

	local character = owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local start = if root then root.CFrame else CFrame.new()

	for _, entry in parse(signature) do
		local model, parts = PetModels.Build(entry.Id, entry.Golden)
		model.Name = owner.Name .. "_" .. entry.Id
		model:PivotTo(start)
		model.Parent = folder
		local partList, rainbowParts = {}, {}
		for _, item in parts do
			table.insert(partList, item.Part)
			if model:GetAttribute("Rainbow") and item.Part:GetAttribute("Tint") == "Body" then
				table.insert(rainbowParts, item.Part)
			end
		end
		table.insert(state.Pets, {
			Model = model,
			Root = model.PrimaryPart,
			Parts = parts,
			PartList = partList,
			RainbowParts = rainbowParts,
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

local function animationOffset(item, time: number): CFrame
	local anim = item.Anim
	local offset = item.Offset
	if anim == "WingL" then
		return offset * CFrame.Angles(0, 0, math.sin(time * 14) * 0.45)
	elseif anim == "WingR" then
		return offset * CFrame.Angles(0, 0, -math.sin(time * 14) * 0.45)
	elseif anim == "SpinY" then
		return CFrame.Angles(0, time * 2, 0) * offset
	elseif anim == "SpinZ" then
		return CFrame.Angles(0, 0, time * 1.5) * offset
	elseif anim == "Wag" then
		return offset * CFrame.Angles(0, math.sin(time * 9) * 0.35, 0)
	end
	return offset
end

local function step(dt: number)
	local now = os.clock()
	local cameraPosition = Workspace.CurrentCamera.CFrame.Position
	local alpha = 1 - math.exp(-dt * 9)
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

				pet.CFrame = pet.CFrame:Lerp(goal, alpha)
				if visible then
					local time = now + pet.Phase
					for _, item in pet.Parts do
						table.insert(bulkParts, item.Part)
						table.insert(bulkCFrames, pet.CFrame * animationOffset(item, time))
					end
					table.insert(bulkParts, pet.Root)
					table.insert(bulkCFrames, pet.CFrame)
					if #pet.RainbowParts > 0 then
						local color = Color3.fromHSV((now * 0.15 + pet.Phase) % 1, 0.4, 1)
						for _, part in pet.RainbowParts do
							part.Color = color
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
