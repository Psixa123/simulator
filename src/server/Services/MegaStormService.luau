--!nonstrict
-- Server-wide Mega Storm event in the hub arena.
-- Idle -> Warning (30s countdown) -> Active (everyone vacuums the storm) -> rewards -> Idle.
-- State is published as attributes on ReplicatedStorage.MegaStormState for the clients.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MapLayout = require(Shared.Config.MapLayout)
local Pets = require(Shared.Config.Pets)
local Formulas = require(Shared.Formulas)
local WeatherModels = require(Shared.Models.WeatherModels)

local Registry = require(script.Parent.Registry)
local Net = require(script.Parent.Net)

local MegaStormService = {}

local settings = GameConfig.MegaStorm
local stateFolder: Configuration
local stormFolder: Folder
local rng = Random.new()

local phase = "Idle"
local nextTime = 0
local stormIndex = 1
local health = 0
local maxHealth = 0
local endTime = 0
local summoner = ""
local queued = 0
local contributions = {} -- [Player] = drained
local stormModel: Model? = nil

local function publish()
	stateFolder:SetAttribute("Phase", phase)
	stateFolder:SetAttribute("NextTime", nextTime)
	stateFolder:SetAttribute("StormIndex", stormIndex)
	stateFolder:SetAttribute("Health", health)
	stateFolder:SetAttribute("MaxHealth", maxHealth)
	stateFolder:SetAttribute("EndTime", endTime)
	stateFolder:SetAttribute("Summoner", summoner)
end

function MegaStormService.CanCatch(root: BasePart): boolean
	if phase ~= "Active" or health <= 0 then
		return false
	end
	local offset = root.Position - MapLayout.ArenaCenter
	return Vector2.new(offset.X, offset.Z).Magnitude <= settings.Range
end

local endStorm

function MegaStormService.Drain(player: Player, data, root: BasePart): boolean
	if not MegaStormService.CanCatch(root) then
		return false
	end
	local drained = math.min(health, Formulas.Power(data))
	health -= drained
	contributions[player] = (contributions[player] or 0) + drained
	stateFolder:SetAttribute("Health", health)
	if health <= 0 then
		task.defer(endStorm, true)
	end
	return true
end

local function beginStorm()
	local stormType = settings.Types[stormIndex]
	local totalPower = 0
	for _, player in Players:GetPlayers() do
		local data = Registry.DataService.Get(player)
		if data then
			totalPower += Formulas.Power(data)
		end
	end

	maxHealth = math.max(settings.MinHealth, math.floor(totalPower / GameConfig.CatchTickRate * settings.HealthSecondsPerPlayer))
	health = maxHealth
	contributions = {}
	endTime = os.time() + settings.Duration

	local model = WeatherModels.BuildMegaStorm(stormType)
	model:PivotTo(CFrame.new(MapLayout.ArenaCenter))
	model.Parent = stormFolder
	stormModel = model

	phase = "Active"
	publish()
	Net.EffectAll("MegaStart", stormIndex)
end

function endStorm(defeated: boolean)
	if phase ~= "Active" then
		return
	end
	phase = "Ending"

	local stormType = settings.Types[stormIndex]
	local ranking = {}
	for player, amount in contributions do
		if player.Parent then
			table.insert(ranking, { Player = player, Amount = amount })
		end
	end
	table.sort(ranking, function(a, b)
		return a.Amount > b.Amount
	end)

	for rank, entry in ranking do
		local player = entry.Player
		local data = Registry.DataService.Get(player)
		if data then
			local volts = Formulas.MegaStormReward(data, entry.Amount, defeated)
			Registry.EconomyService.AddVolts(player, volts)
			data.Stats.MegaStorms += 1

			local petId = nil
			if defeated and entry.Amount >= maxHealth * settings.MinContribution then
				local chance = settings.ExclusiveChances[rank] or settings.ParticipantChance
				if rng:NextNumber() < chance and Registry.PetService.GivePet(player, stormType.Pet, false) then
					petId = stormType.Pet
					Net.NotifyAll(
						string.format("🌪️ %s got the exclusive %s from the Mega Storm!", player.DisplayName, Pets.Pets[petId].Name),
						"Reward"
					)
				end
			end
			Net.Effect(player, "MegaReward", volts, rank, #ranking, petId, defeated)
		end
	end

	Net.EffectAll("MegaEnd", defeated, stormIndex)

	local model = stormModel
	stormModel = nil
	if model then
		task.delay(3, function()
			model:Destroy()
		end)
	end

	stormIndex = stormIndex % #settings.Types + 1
	if queued > 0 then
		queued -= 1
		nextTime = os.time() + settings.WarningTime + 10
	else
		nextTime = os.time() + settings.Interval
	end
	health = 0
	maxHealth = 0
	endTime = 0
	summoner = ""
	contributions = {}
	phase = "Idle"
	publish()
end

-- Called when someone buys the "Summon Mega Storm" product
function MegaStormService.Summon(player: Player)
	if phase == "Idle" then
		nextTime = os.time() + settings.SummonDelay
		summoner = player.DisplayName
		phase = "Warning"
		publish()
		Net.EffectAll("MegaWarning", stormIndex, summoner)
		Net.NotifyAll(
			string.format("🌪️ %s summoned a Mega Storm! It arrives in %d seconds!", player.DisplayName, settings.SummonDelay),
			"Warning"
		)
	else
		queued += 1
		Net.NotifyAll(
			string.format("🌪️ %s summoned another Mega Storm! It will strike right after this one.", player.DisplayName),
			"Warning"
		)
	end
end

function MegaStormService.Init()
	stateFolder = ReplicatedStorage:WaitForChild("MegaStormState")
	stormFolder = Instance.new("Folder")
	stormFolder.Name = "MegaStorm"
	stormFolder.Parent = Workspace

	nextTime = os.time() + settings.FirstDelay
	publish()

	Players.PlayerRemoving:Connect(function(player)
		contributions[player] = nil
	end)
end

function MegaStormService.Start()
	while true do
		task.wait(0.5)
		local now = os.time()
		if phase == "Idle" then
			if now >= nextTime - settings.WarningTime then
				phase = "Warning"
				publish()
				Net.EffectAll("MegaWarning", stormIndex, summoner)
			end
		elseif phase == "Warning" then
			if now >= nextTime then
				beginStorm()
			end
		elseif phase == "Active" then
			if health <= 0 then
				endStorm(true)
			elseif now >= endTime then
				endStorm(false)
			end
		end
	end
end

return MegaStormService
