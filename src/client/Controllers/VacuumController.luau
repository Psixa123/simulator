--!nonstrict
-- Player input for the Storm Vacuum. Hold click, the screen or R2 (or use Auto Catch) to vacuum
-- the weather under your mouse or the nearest one in range. The server validates everything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Zones = require(Shared.Config.Zones)
local MapLayout = require(Shared.Config.MapLayout)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Parent.Registry)

local VacuumController = {}

local MEGA_TARGET = -1
local UPDATE_INTERVAL = 0.12

local player = Players.LocalPlayer
local holding = false
local requested = 0 -- target we last asked the server for
local requestedAt = 0
local rejected = {} -- [targetId] = os.clock() until which we skip it
local accumulator = 0
local toolConnections = {}

local function autoCatch(): boolean
	local data = Registry.DataController.Data
	return data ~= nil and Formulas.HasPass(data, "AutoCatch") and data.Settings.AutoCatch == true
end

local function canCatchZone(data, zoneId: number): boolean
	return zoneId <= data.Zone and Formulas.Power(data) >= Zones[zoneId].MinPower
end

local function stop()
	if requested ~= 0 then
		requested = 0
		Remotes.Catch:FireServer("Stop")
	end
end

local function request(targetId: number)
	requested = targetId
	requestedAt = os.clock()
	Remotes.Catch:FireServer("Start", targetId)
end

local function hoveredCell(): Model?
	if not UserInputService.MouseEnabled then
		return nil
	end
	local folder = Workspace:FindFirstChild("WeatherCells")
	if not folder then
		return nil
	end
	local location = UserInputService:GetMouseLocation()
	local ray = Workspace.CurrentCamera:ViewportPointToRay(location.X, location.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 600, params)
	if not result then
		return nil
	end
	local instance: Instance? = result.Instance
	while instance and instance.Parent ~= folder do
		instance = instance.Parent
	end
	return instance :: Model?
end

local function inMegaRange(root: BasePart): boolean
	if not Registry.MegaStormController.IsActive() then
		return false
	end
	local offset = root.Position - MapLayout.ArenaCenter
	return Vector2.new(offset.X, offset.Z).Magnitude <= GameConfig.MegaStorm.Range - 2
end

local function validCell(model: Model?, data, root: BasePart, range: number): boolean
	if not model or not model.Parent then
		return false
	end
	local origin = model:GetAttribute("Origin")
	local zoneId = model:GetAttribute("Zone")
	local health = model:GetAttribute("Health")
	if not origin or not zoneId or not health or health <= 0 then
		return false
	end
	return (origin - root.Position).Magnitude <= range and canCatchZone(data, zoneId)
end

-- Returns the best target id (0 = none) and, if relevant, a zone we're too weak for
local function findTarget(data, root: BasePart)
	if inMegaRange(root) then
		return MEGA_TARGET, nil
	end
	local range = Formulas.Range(data)
	local now = os.clock()

	local hovered = hoveredCell()
	if hovered and validCell(hovered, data, root, range) then
		local id = hovered:GetAttribute("CellId")
		if not rejected[id] or rejected[id] < now then
			return id, nil
		end
	end

	local best, bestDistance, weakZone = 0, math.huge, nil
	for model in Registry.EffectsController.Cells() do
		local origin = model:GetAttribute("Origin")
		local zoneId = model:GetAttribute("Zone")
		local id = model:GetAttribute("CellId")
		if origin and zoneId and id and (not rejected[id] or rejected[id] < now) then
			local distance = (origin - root.Position).Magnitude
			if distance <= range then
				if canCatchZone(data, zoneId) then
					if distance < bestDistance then
						best, bestDistance = id, distance
					end
				else
					weakZone = zoneId
				end
			end
		end
	end
	return best, weakZone
end

local function stillValid(targetId: number, data, root: BasePart): boolean
	if targetId == MEGA_TARGET then
		return inMegaRange(root)
	end
	return validCell(Registry.EffectsController.GetCell(targetId), data, root, Formulas.Range(data))
end

local function update(force: boolean?)
	local data = Registry.DataController.Data
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local tool = character and character:FindFirstChild("StormVacuum")
	-- Stunned by lightning (HazardService): the server rejects catching until it wears off
	local active = tool ~= nil and (holding or autoCatch()) and not character:GetAttribute("Stunned")

	if not data or not root or not active then
		stop()
		return
	end

	-- A full tank only blocks regular weather: the Mega Storm pays out Volts, not energy.
	-- Same rule as the server (WeatherService): an Infinite Tank is never full.
	local remoteSell = Formulas.HasPass(data, "RemoteSell")
	local tankFull = Formulas.IsTankFull(data) and not remoteSell
	if tankFull and not inMegaRange(root) then
		stop()
		if holding then
			Registry.InterfaceController.Hint("🛢️ Tank full! Press SELL or visit a Weather Lab.", "Full", 3)
		end
		return
	end
	if tankFull and requested ~= MEGA_TARGET then
		force = true -- drop any regular cell and switch to the storm
	end

	local serverTarget = character:GetAttribute("CatchTarget") or 0
	local now = os.clock()

	-- The server didn't accept our request: skip that target for a moment
	if requested ~= 0 and serverTarget ~= requested and now - requestedAt > 0.6 then
		rejected[requested] = now + 3
		requested = 0
	end

	if not force and requested ~= 0 and serverTarget == requested and stillValid(requested, data, root) then
		return
	end
	if not force and requested ~= 0 and serverTarget ~= requested and now - requestedAt <= 0.6 then
		return -- waiting for the server to confirm
	end

	local target, weakZone = findTarget(data, root)
	if target ~= 0 then
		if target ~= requested or serverTarget ~= target then
			request(target)
		end
	else
		stop()
		if holding then
			if weakZone then
				local zone = Zones[weakZone]
				Registry.InterfaceController.Hint(
					string.format("💨 You need %s Vacuum Power to catch %s weather!", Format.Number(zone.MinPower), zone.Name),
					"Weak",
					3
				)
			else
				Registry.InterfaceController.Hint("🌪️ Get closer to some weather to catch it!", "Closer", 3)
			end
		end
	end
end

local function connectTool(tool: Tool)
	for _, connection in toolConnections do
		connection:Disconnect()
	end
	table.clear(toolConnections)
	table.insert(toolConnections, tool.Activated:Connect(function()
		holding = true
		update(true)
	end))
	table.insert(toolConnections, tool.Deactivated:Connect(function()
		holding = false
		if not autoCatch() then
			stop()
		end
	end))
	table.insert(toolConnections, tool.Unequipped:Connect(function()
		holding = false
		stop()
	end))
end

local function onCharacter(character: Model)
	holding = false
	requested = 0
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child.Name == "StormVacuum" then
			connectTool(child)
		end
	end)
	local existing = character:FindFirstChild("StormVacuum")
	if existing then
		connectTool(existing)
	end
end

function VacuumController.IsHolding(): boolean
	return holding
end

-- True while the Mega Storm is active and we're close enough to vacuum it
function VacuumController.InMegaRange(): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and inMegaRange(root)
end

function VacuumController.Start()
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end

	-- Gamepad: hold R2 to vacuum (same as holding click / the screen with the Tool equipped)
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.ButtonR2 and not processed and not holding then
			holding = true
			update(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.ButtonR2 and holding then
			holding = false
			if not autoCatch() then
				stop()
			end
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= UPDATE_INTERVAL then
			accumulator = 0
			update(false)
		end
	end)
end

return VacuumController
