--!nonstrict
-- Scene for the game page art (icon and thumbnails), rendered by tools/branding/capture.py through
-- `tools/preview_map.py --script tools/branding/BrandingScene.luau`. Runs in the preview mock only
-- (it is not part of the game).
--
-- Builds the real map with MapService, then fills every zone's weather field with real weather cells
-- (WeatherModels.Build, placed like WeatherService does: inside MapLayout.FieldBounds, at the type's
-- hover height, at least GameConfig.CellSpacing apart) and puts a real Mega Storm
-- (WeatherModels.BuildMegaStorm) in the Storm Station arena. A fixed random seed keeps the shots
-- identical between runs.
--
-- Far above the map it also lines up a "studio": every weather cell, every egg, every Mega Storm and
-- the Storm Vacuum gear (alone, and on a blocky player aiming it, built by the real CharacterGear) each
-- on its own, STUDIO_STEP studs apart from STUDIO_ORIGIN (buildStudio prints the slots), which
-- capture.py cuts out of the scene and renders one by one on a transparent background.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MapService = require(script.Parent.MapService)
local CharacterGear = require(script.Parent.CharacterGear)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local WeatherModels = require(Shared:WaitForChild("Models"):WaitForChild("WeatherModels"))
local EggModels = require(Shared:WaitForChild("Models"):WaitForChild("EggModels"))
local MapLayout = require(Config:WaitForChild("MapLayout"))
local Zones = require(Config:WaitForChild("Zones"))
local Weather = require(Config:WaitForChild("Weather"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Pets = require(Config:WaitForChild("Pets"))

local Scene = {}

local SEED = 2026
-- Cells per zone by rarity. The game rolls 70/25/5 %; the shots show a few more Uncommon and Rare
-- cells so every weather type of a zone is visible at once.
local MIX = { Common = 9, Uncommon = 5, Rare = 2 }
-- Which Mega Storm stands in the arena (GameConfig.MegaStorm.Types index)
local ARENA_STORM = 5 -- Cosmic Maelstrom
-- The studio: slot i (from 0) is centred on STUDIO_ORIGIN + (i * STUDIO_STEP, 0, 0), out of every map shot
local STUDIO_ORIGIN = Vector3.new(0, 3000, 9000)
local STUDIO_STEP = 300
local EGG_HEIGHT = 4 -- studs, like the egg stations' display egg
local AIM = 104 -- degrees the player's vacuum arm is raised from hanging down (90 = level): aiming up at a cloud
local SKIN = Color3.fromRGB(255, 205, 148)
local HAIR = Color3.fromRGB(92, 58, 40)
local SHIRT = Color3.fromRGB(92, 200, 255)
local PANTS = Color3.fromRGB(58, 64, 120)

local function typesByRarity(zone)
	local result = {}
	for _, typeId in zone.Weather do
		local rarity = Weather.Types[typeId].Rarity
		result[rarity] = typeId
	end
	return result
end

local function findSpot(rng, zoneId: number, taken): Vector3
	local minX, maxX, minZ, maxZ = MapLayout.FieldBounds(zoneId)
	local candidate = Vector3.zero
	for _ = 1, 60 do
		candidate = Vector3.new(rng:NextNumber(minX, maxX), 0, rng:NextNumber(minZ, maxZ))
		local clear = true
		for _, other in taken do
			local dx, dz = other.X - candidate.X, other.Z - candidate.Z
			if dx * dx + dz * dz < GameConfig.CellSpacing * GameConfig.CellSpacing * 2.2 then
				clear = false
				break
			end
		end
		if clear then
			break
		end
	end
	return candidate
end

local function fillField(rng, zoneId: number, parent: Instance)
	local zone = Zones[zoneId]
	local byRarity = typesByRarity(zone)
	local taken = {}
	for _, rarity in { "Rare", "Uncommon", "Common" } do
		local typeId = byRarity[rarity]
		for _ = 1, (if typeId then MIX[rarity] else 0) do
			local spot = findSpot(rng, zoneId, taken)
			table.insert(taken, spot)
			local model = WeatherModels.Build(typeId)
			local position = spot + Vector3.new(0, WeatherModels.HoverHeight(typeId), 0)
			model:PivotTo(CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
			model.Parent = parent
		end
	end
end

-- A player who unlocked every zone sees no gate barriers, and during a storm the arena sign's
-- countdown is replaced by the storm's own UI: hide both so they don't fog up the shots (and the
-- leaderboards' placeholder text)
local function clearView()
	local map = Workspace:FindFirstChild("Map")
	for _, item in map:GetDescendants() do
		local isBarrier = item:IsA("BasePart") and item.Material == Enum.Material.ForceField
		if isBarrier or item.Name == "ArenaGui" then
			item:Destroy()
		elseif item:IsA("TextLabel") and item.Text == "Loading leaderboard..." then
			item.Text = "" -- the boards fill in once players join; an empty board reads better than this
		end
	end
end

local function block(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent
	return part
end

-- A blocky R15-shaped player (like tools/world/GearPreview.luau) facing -Z with the HumanoidRootPart at the
-- origin, the right arm raised AIM degrees about the shoulder. Returns the model, its UpperTorso and RightHand.
local function player(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Player"
	model.Parent = parent
	local function limb(name, size, offset, color)
		return block(name, size, offset, color, model)
	end
	local root = limb("HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(), SHIRT)
	root.Transparency = 1
	model.PrimaryPart = root
	limb("LowerTorso", Vector3.new(2, 0.4, 1), CFrame.new(0, -0.8, 0), PANTS)
	local upper = limb("UpperTorso", Vector3.new(2, 1.6, 1), CFrame.new(0, 0.2, 0), SHIRT)
	local back = Instance.new("Attachment")
	back.Name = "BodyBackAttachment"
	back.CFrame = CFrame.new(0, 0.2, 0.5)
	back.Parent = upper
	limb("Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 1.6, 0), SKIN)
	limb("Hair", Vector3.new(1.3, 0.45, 1.3), CFrame.new(0, 2.1, 0.03), HAIR)
	limb("HairBack", Vector3.new(1.3, 0.8, 0.3), CFrame.new(0, 1.75, 0.52), HAIR)
	local shoulder = CFrame.new(1.5, 1.0, 0) * CFrame.Angles(math.rad(AIM), 0, 0) * CFrame.new(-1.5, -1.0, 0)
	limb("RightUpperArm", Vector3.new(1, 1.2, 1), shoulder * CFrame.new(1.5, 0.4, 0), SHIRT)
	limb("RightLowerArm", Vector3.new(1, 1.1, 1), shoulder * CFrame.new(1.5, -0.6, 0), SKIN)
	local hand = limb("RightHand", Vector3.new(0.6, 0.6, 0.6), shoulder * CFrame.new(1.5, -1.1, 0), SKIN)
	local grip = Instance.new("Attachment")
	grip.Name = "RightGripAttachment"
	grip.CFrame = CFrame.new(0, -0.15, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
	grip.Parent = hand
	-- the left arm swings back a little, like running
	local left = CFrame.new(-1.5, 1.0, 0) * CFrame.Angles(math.rad(-20), 0, 0) * CFrame.new(1.5, -1.0, 0)
	limb("LeftUpperArm", Vector3.new(1, 1.2, 1), left * CFrame.new(-1.5, 0.4, 0), SHIRT)
	limb("LeftLowerArm", Vector3.new(1, 1.1, 1), left * CFrame.new(-1.5, -0.6, 0), SKIN)
	limb("LeftHand", Vector3.new(0.6, 0.6, 0.6), left * CFrame.new(-1.5, -1.1, 0), SKIN)
	for _, side in { -1, 1 } do
		limb("Leg", Vector3.new(1, 2.4, 1), CFrame.new(side * 0.5, -2.2, 0), PANTS)
	end
	return model, upper, hand
end

-- Holds the tool's Handle at the hand's RightGripAttachment (what Humanoid:EquipTool does)
local function hold(tool: Tool, hand: BasePart, model: Model)
	local grip = hand:FindFirstChild("RightGripAttachment")
	local target = hand.CFrame * grip.CFrame * tool.Grip:Inverse()
	local base = tool:FindFirstChild("Handle").CFrame
	for _, part in tool:GetDescendants() do
		if part:IsA("BasePart") then
			part.CFrame = target * base:ToObjectSpace(part.CFrame)
		end
	end
	tool.Parent = model
end

-- Every weather type (zone order), every egg, every Mega Storm and the gear, each in its own studio slot.
-- The slot list is printed as "STUDIO <slot> <name>" lines for capture.py.
local function buildStudio()
	local folder = Instance.new("Folder")
	folder.Name = "BrandingStudio"
	folder.Parent = Workspace
	local slot = 0
	local function place(name: string, model: Model)
		model.Name = name
		model:PivotTo(CFrame.new(STUDIO_ORIGIN + Vector3.new(slot * STUDIO_STEP, 0, 0)))
		model.Parent = folder
		print(string.format("STUDIO %d %s", slot, name))
		slot += 1
	end
	for zoneId = 1, #Zones do
		for _, typeId in Zones[zoneId].Weather do
			place("Weather_" .. typeId, WeatherModels.Build(typeId))
		end
	end
	for _, eggId in Pets.EggOrder do
		place("Egg_" .. eggId, EggModels.Build(eggId, EGG_HEIGHT))
	end
	for _, stormType in GameConfig.MegaStorm.Types do
		place("MegaStorm_" .. stormType.Key, WeatherModels.BuildMegaStorm(stormType))
	end

	-- the Storm Vacuum on its own (a Model, so place() can pivot it)
	local vacuum = Instance.new("Model")
	CharacterGear.BuildVacuum().Parent = vacuum
	place("Gear_Vacuum", vacuum)

	-- a player aiming the vacuum, the Storm Tank on their back, the tank 85 % full
	local holder = Instance.new("Model")
	local model, upper, hand = player(holder)
	local tool = CharacterGear.BuildVacuum()
	hold(tool, hand, model)
	local tank = CharacterGear.BuildTank()
	CharacterGear.AttachTank(model, tank, upper:FindFirstChild("BodyBackAttachment"))
	CharacterGear.SetTankFill(tank, 0.85)
	local nozzle = tool:FindFirstChild("Handle"):FindFirstChild("NozzleAttachment")
	print(string.format("NOZZLE %.3f %.3f %.3f", nozzle.WorldPosition.X, nozzle.WorldPosition.Y, nozzle.WorldPosition.Z))
	place("Gear_Player", holder)
end

function Scene.Init()
	MapService.Init()
	clearView()

	local folder = Instance.new("Folder")
	folder.Name = "BrandingWeather"
	folder.Parent = Workspace

	local rng = Random.new(SEED)
	for zoneId = 1, #Zones do
		fillField(rng, zoneId, folder)
	end

	local storm = WeatherModels.BuildMegaStorm(GameConfig.MegaStorm.Types[ARENA_STORM])
	storm:PivotTo(CFrame.new(MapLayout.ArenaCenter))
	storm.Parent = folder

	buildStudio()
end

return Scene
