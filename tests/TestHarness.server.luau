--!nonstrict
-- Automated smoke test (server half). Only included in test.project.json builds.
-- Gives the client harness a few privileged commands and reports server-side state.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

-- Studio only, and never in a published place: the test grants huge balances that would
-- otherwise be saved to real player data and the live leaderboards
if not RunService:IsStudio() or game.PlaceId ~= 0 then
	return
end

local Registry = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Services"):WaitForChild("Registry"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapLayout = require(Shared.Config.MapLayout)
local Formulas = require(Shared.Formulas)
local ClimateShift = require(Shared.ClimateShift)

local function log(...)
	print("[HARNESS-S]", ...)
end

local command = Instance.new("RemoteFunction")
command.Name = "TestCommand"
command.Parent = ReplicatedStorage

local handlers = {}

function handlers.AddVolts(player, amount)
	Registry.EconomyService.AddVolts(player, amount)
	return Registry.DataService.Get(player).Volts
end

function handlers.Teleport(player, position)
	player.Character:PivotTo(CFrame.new(position))
	return true
end

function handlers.NearestCell(player, zoneId)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local best, bestDistance
	for _, model in Workspace.WeatherCells:GetChildren() do
		if model:GetAttribute("Zone") == zoneId then
			local origin = model:GetAttribute("Origin")
			local distance = (origin - root.Position).Magnitude
			if not bestDistance or distance < bestDistance then
				best, bestDistance = model, distance
			end
		end
	end
	if not best then
		return nil
	end
	return best:GetAttribute("CellId"), best:GetAttribute("Origin"), best:GetAttribute("Type")
end

function handlers.Stats(player)
	local data = Registry.DataService.Get(player)
	return {
		Volts = data.Volts,
		Energy = data.Energy,
		TankValue = data.TankValue,
		Zone = data.Zone,
		Rebirths = data.Rebirths,
		Pets = #data.Pets,
		Power = Formulas.Power(data),
		Capacity = Formulas.TankCapacity(data),
	}
end

function handlers.GivePets(player, petId, count)
	for _ = 1, count do
		Registry.PetService.GivePet(player, petId, false)
	end
	return #Registry.DataService.Get(player).Pets
end

function handlers.Summon(player)
	-- Keep the Rainbow Hurricane out of the way so the summon starts right away
	Registry.MegaStormService.ScheduleRainbow(3600)
	Registry.MegaStormService.Summon(player)
	return true
end

-- enabled = false makes the player immune to biome hazards (keeps catch checks deterministic)
function handlers.Hazards(player, enabled)
	Registry.HazardService.SetImmune(player, not enabled)
	return true
end

function handlers.Sandstorm(player)
	Registry.HazardService.StartSandstorm()
	return true
end

function handlers.World(player)
	local parts = 0
	for _, descendant in Workspace.Map:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts += 1
		end
	end
	local character = player.Character
	local head = character:FindFirstChild("Head")
	return {
		MapParts = parts,
		Cells = #Workspace.WeatherCells:GetChildren(),
		Tool = character:FindFirstChild("StormVacuum") ~= nil or player.Backpack:FindFirstChild("StormVacuum") ~= nil,
		ToolEquipped = character:FindFirstChild("StormVacuum") ~= nil,
		Tank = character:FindFirstChild("StormTank") ~= nil,
		Overhead = head ~= nil and head:FindFirstChild("Overhead") ~= nil,
		Leaderstats = player:FindFirstChild("leaderstats") ~= nil,
		WalkSpeed = character:FindFirstChildOfClass("Humanoid").WalkSpeed,
		Position = character:GetPivot().Position,
		GatePrompts = #CollectionService:GetTagged("GatePrompt"),
		Barriers = #CollectionService:GetTagged("ZoneBarrier"),
	}
end

-- Climate Shift look worn by the tank and vacuum, and the look the player should be wearing
function handlers.Gear(player)
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	local tank = character and character:FindFirstChild("StormTank")
	local vacuum = (character and character:FindFirstChild("StormVacuum")) or (backpack and backpack:FindFirstChild("StormVacuum"))
	local _, expected = ClimateShift.Cosmetic(Registry.DataService.Get(player).Rebirths)
	return {
		Expected = expected,
		Tank = tank and tank:GetAttribute("CosmeticTier"),
		Vacuum = vacuum and vacuum:GetAttribute("CosmeticTier"),
	}
end

function handlers.Finish(player, summary)
	log("FINISHED:", summary)
	task.delay(1, function()
		pcall(function()
			game:GetService("StudioTestService"):EndTest(summary)
		end)
	end)
	return true
end

command.OnServerInvoke = function(player, name, ...)
	local handler = handlers[name]
	if not handler then
		return nil
	end
	local results = table.pack(pcall(handler, player, ...))
	if not results[1] then
		log("command", name, "FAILED:", results[2])
		return nil
	end
	return table.unpack(results, 2, results.n)
end

Players.PlayerAdded:Connect(function(player)
	log("player added", player.Name)
end)
log("server harness ready; sell pads:", #MapLayout.AllSellPads())
