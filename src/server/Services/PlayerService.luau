--!nonstrict
-- Sets up players and their characters: leaderstats, walk speed, the Storm Vacuum tool,
-- the Storm Tank backpack, the overhead tag and player-to-player collisions.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)

local Registry = require(script.Parent.Registry)
local CharacterGear = require(script.Parent.CharacterGear)

local PlayerService = {}

local COLLISION_GROUP = "Players"
local vacuumTemplate: Tool
local tanks = {} -- [Player] = { Model = Model, Fraction = number }

local function spawnCharacter(player: Player)
	local ok = pcall(function()
		player:LoadCharacterAsync()
	end)
	if not ok and player.Parent then
		-- Older engine versions only have the non-Async name
		pcall(function()
			(player :: any):LoadCharacter()
		end)
	end
end

local function setCollisionGroup(instance: Instance)
	if instance:IsA("BasePart") then
		instance.CollisionGroup = COLLISION_GROUP
	end
end

function PlayerService.UpdateTank(player: Player)
	local entry = tanks[player]
	if not entry or not entry.Model.Parent then
		return
	end
	local data = Registry.DataService.Get(player)
	if not data then
		return
	end
	local fraction = math.clamp(data.Energy / Formulas.TankCapacity(data), 0, 1)
	local stepped = if fraction >= 0.999 then 1 else math.floor(fraction * 20 + 0.5) / 20
	if stepped ~= entry.Fraction then
		entry.Fraction = stepped
		CharacterGear.SetTankFill(entry.Model, stepped)
	end
end

local function updateOverhead(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local gui = head and head:FindFirstChild("Overhead")
	local data = Registry.DataService.Get(player)
	if gui and data then
		CharacterGear.UpdateOverhead(gui, Formulas.HasPass(data, "VIP"), data.Rebirths)
	end
end

local function updateWalkSpeed(player: Player)
	local data = Registry.DataService.Get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if data and humanoid then
		humanoid.WalkSpeed = Formulas.WalkSpeed(data)
	end
end

local function giveVacuum(player: Player, character: Model)
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if not backpack then
		return
	end
	if backpack:FindFirstChild("StormVacuum") or character:FindFirstChild("StormVacuum") then
		return
	end
	local tool = vacuumTemplate:Clone()
	tool.Parent = backpack
	task.delay(0.5, function()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and tool.Parent == backpack and character.Parent then
			humanoid:EquipTool(tool)
		end
	end)
end

local function attachTank(player: Player, character: Model)
	local deadline = os.clock() + 8
	local attachment
	repeat
		local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
		attachment = torso and torso:FindFirstChild("BodyBackAttachment")
		if not attachment then
			task.wait(0.25)
		end
	until attachment or os.clock() > deadline or not character.Parent
	if not attachment or not character.Parent or player.Character ~= character then
		return
	end
	local tank = CharacterGear.BuildTank()
	CharacterGear.AttachTank(character, tank, attachment)
	tanks[player] = { Model = tank, Fraction = -1 }
	PlayerService.UpdateTank(player)
end

local function setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid or player.Character ~= character then
		return
	end
	local data = Registry.DataService.Get(player)
	if not data then
		return
	end

	humanoid.WalkSpeed = Formulas.WalkSpeed(data)
	character:SetAttribute("CatchTarget", 0)

	for _, descendant in character:GetDescendants() do
		setCollisionGroup(descendant)
	end
	character.DescendantAdded:Connect(setCollisionGroup)

	giveVacuum(player, character)
	task.spawn(attachTank, player, character)

	local head = character:WaitForChild("Head", 5)
	if head then
		local gui = CharacterGear.BuildOverhead()
		gui.Adornee = head
		gui.Parent = head
		updateOverhead(player)
	end

	humanoid.Died:Connect(function()
		Registry.WeatherService.StopCatch(player)
		-- Characters are loaded manually (after data is ready), so respawn them here
		task.delay(Players.RespawnTime, function()
			if player.Parent and player.Character == character then
				spawnCharacter(player)
			end
		end)
	end)
end

local function createLeaderstats(player: Player, data)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"

	local volts = Instance.new("StringValue")
	volts.Name = "Volts"
	volts.Value = Format.Number(data.Volts)
	volts.Parent = folder

	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Value = data.Rebirths
	rebirths.Parent = folder

	folder.Parent = player
end

local function onPlayerLoaded(player: Player, data)
	createLeaderstats(player, data)
	player:SetAttribute("Rebirths", data.Rebirths)
	player:SetAttribute("VIP", false)

	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)
	if player.Character then
		task.spawn(setupCharacter, player, player.Character)
	else
		-- CharacterAutoLoads is off so nobody spawns before the map and their data are ready
		spawnCharacter(player)
	end
end

local function onDataChanged(player: Player, key: string, value)
	if key == "Volts" then
		local leaderstats = player:FindFirstChild("leaderstats")
		local stat = leaderstats and leaderstats:FindFirstChild("Volts")
		if stat then
			stat.Value = Format.Number(value)
		end
	elseif key == "Rebirths" then
		local leaderstats = player:FindFirstChild("leaderstats")
		local stat = leaderstats and leaderstats:FindFirstChild("Rebirths")
		if stat then
			stat.Value = value
		end
		player:SetAttribute("Rebirths", value)
		updateOverhead(player)
	elseif key == "Upgrades" then
		updateWalkSpeed(player)
	elseif key == "Energy" then
		PlayerService.UpdateTank(player)
	elseif key == "Passes" then
		local data = Registry.DataService.Get(player)
		if data then
			player:SetAttribute("VIP", Formulas.HasPass(data, "VIP"))
		end
		updateOverhead(player)
		PlayerService.UpdateTank(player)
	end
end

function PlayerService.Init()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(COLLISION_GROUP)
	end)
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, COLLISION_GROUP, false)

	vacuumTemplate = CharacterGear.BuildVacuum()
	vacuumTemplate.Parent = ServerStorage

	Registry.DataService.PlayerLoaded:Connect(onPlayerLoaded)
	Registry.DataService.Changed:Connect(onDataChanged)

	Players.PlayerRemoving:Connect(function(player)
		tanks[player] = nil
	end)
end

return PlayerService
