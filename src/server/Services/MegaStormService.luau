--!nonstrict
-- Server-wide Mega Storm event in the hub arena.
-- Idle -> Warning (30s countdown) -> Active (everyone vacuums the storm) -> rewards -> Idle.
-- Every 2 hours on the hour (UTC) the Rainbow Hurricane strikes in every server at once: it's
-- announced 5 minutes ahead and regular / summoned storms that would overlap it wait for it.
-- State is published as attributes on ReplicatedStorage.MegaStormState for the clients.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MapLayout = require(Shared.Config.MapLayout)
local Pets = require(Shared.Config.Pets)
local Formulas = require(Shared.Formulas)
local StormSchedule = require(Shared.StormSchedule)
local WeatherModels = require(Shared.Models.WeatherModels)

local Registry = require(script.Parent.Registry)
local Net = require(script.Parent.Net)

local MegaStormService = {}

local settings = GameConfig.MegaStorm
local rainbow = settings.Rainbow
local stateFolder: Configuration
local stormFolder: Folder
local rng = Random.new()

local phase = "Idle"
local nextTime = 0
local stormIndex = 1
local stormKey = settings.Types[1].Key -- current / next storm ("Rainbow" for the Rainbow Hurricane)
local rainbowTime = 0 -- next Rainbow Hurricane that hasn't started yet
local rainbowAnnounced = false
local summonNext = false -- the next regular storm is a queued summon
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
	stateFolder:SetAttribute("StormKey", stormKey)
	stateFolder:SetAttribute("RainbowTime", rainbowTime)
	stateFolder:SetAttribute("Queued", queued)
end

local function currentType()
	return StormSchedule.TypeFor(stormKey, stormIndex)
end

-- Repaints a freshly built storm in rainbow bands (clients cycle the colours)
local function paintRainbow(model: Model)
	model:SetAttribute("Rainbow", true)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") and (item.Name == "Layer" or item.Name == "Streak" or item.Name == "Eye") then
			item.Color = Color3.fromHSV((item.Position.Y / 84) % 1, if item.Name == "Streak" then 0.7 else 0.5, 1)
		elseif item:IsA("ParticleEmitter") then
			item.Color = WeatherModels.RainbowSequence
		end
	end
end

function MegaStormService.CanCatch(root: BasePart): boolean
	if phase ~= "Active" or health <= 0 then
		return false
	end
	local offset = root.Position - MapLayout.ArenaCenter
	return Vector2.new(offset.X, offset.Z).Magnitude <= settings.Range
end

local endStorm

-- amount defaults to the player's vacuum Power (pets pass their own catch power)
function MegaStormService.Drain(player: Player, data, root: BasePart, amount: number?): boolean
	if not MegaStormService.CanCatch(root) then
		return false
	end
	local drained = math.min(health, amount or Formulas.Power(data))
	health -= drained
	contributions[player] = (contributions[player] or 0) + drained
	stateFolder:SetAttribute("Health", health)
	if health <= 0 then
		task.defer(endStorm, true)
	end
	return true
end

local function beginStorm()
	local stormType = currentType()
	local totalPower = 0
	for _, player in Players:GetPlayers() do
		local data = Registry.DataService.Get(player)
		if data then
			totalPower += Formulas.Power(data) + Formulas.PetCatchPower(data)
		end
	end

	maxHealth = math.max(settings.MinHealth, math.floor(totalPower / GameConfig.CatchTickRate * settings.HealthSecondsPerPlayer))
	maxHealth = math.floor(maxHealth * (stormType.HealthMultiplier or 1))
	health = maxHealth
	contributions = {}
	endTime = os.time() + StormSchedule.Duration(stormType)

	local model = WeatherModels.BuildMegaStorm(stormType)
	if stormType == rainbow then
		paintRainbow(model)
		rainbowTime = StormSchedule.NextRainbow(rainbowTime)
		rainbowAnnounced = false
	end
	model:PivotTo(CFrame.new(MapLayout.ArenaCenter))
	model.Parent = stormFolder
	stormModel = model

	phase = "Active"
	publish()
	Net.EffectAll("MegaStart", stormIndex, stormKey)
end

function endStorm(defeated: boolean)
	if phase ~= "Active" then
		return
	end
	phase = "Ending"

	local stormType = currentType()
	local isRainbow = stormType == rainbow
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
			local volts = math.floor(Formulas.MegaStormReward(data, entry.Amount, defeated) * (stormType.RewardMultiplier or 1))
			Registry.EconomyService.AddVolts(player, volts)
			data.Stats.MegaStorms += 1

			local petId = nil
			if defeated and entry.Amount >= maxHealth * settings.MinContribution then
				local chance = settings.ExclusiveChances[rank] or settings.ParticipantChance
				if rng:NextNumber() < chance and Registry.PetService.GivePet(player, stormType.Pet, false) then
					petId = stormType.Pet
					Net.NotifyAll(
						string.format(
							"%s %s got the exclusive %s from the %s!",
							stormType.Icon or "🌪️",
							player.DisplayName,
							Pets.Pets[petId].Name,
							if isRainbow then stormType.Name else "Mega Storm"
						),
						"Reward"
					)
				end
			end
			Net.Effect(player, "MegaReward", volts, rank, #ranking, petId, defeated)
		end
	end

	Net.EffectAll("MegaEnd", defeated, stormIndex, stormKey)

	local model = stormModel
	stormModel = nil
	if model then
		task.delay(3, function()
			model:Destroy()
		end)
	end

	-- The Rainbow Hurricane doesn't use up a storm from the regular rotation
	if not isRainbow then
		stormIndex = stormIndex % #settings.Types + 1
	end
	stormKey = settings.Types[stormIndex].Key
	summonNext = queued > 0
	if queued > 0 then
		queued -= 1
		nextTime = os.time() + StormSchedule.QueueGap
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

-- Puts the Rainbow Hurricane first whenever the next regular storm would overlap it
local function planRainbow(now: number)
	if stormKey == rainbow.Key then
		return
	end
	if now > rainbowTime + rainbow.LateGrace then
		-- This server was busy at the scheduled time; wait for the next one
		rainbowTime = StormSchedule.NextRainbow(now)
		rainbowAnnounced = false
		publish()
	end
	if StormSchedule.RainbowFirst(nextTime, rainbowTime) then
		if summonNext then
			-- The summoned storm strikes right after the Rainbow Hurricane instead
			queued += 1
			summonNext = false
		end
		stormKey = rainbow.Key
		nextTime = rainbowTime
		summoner = ""
		publish()
	end
end

local function announceRainbow(now: number)
	local minutes = math.max(1, math.round((rainbowTime - now) / 60))
	local pet = Pets.Pets[rainbow.Pet]
	Net.NotifyAll(
		string.format(
			"%s A %s arrives in %d minute%s! Gather at the Mega Storm Arena for the exclusive %s!",
			rainbow.Icon,
			rainbow.Name,
			minutes,
			if minutes == 1 then "" else "s",
			if pet then pet.Name else "pet"
		),
		"Warning"
	)
	Net.EffectAll("MegaRainbowSoon", rainbowTime)
end

-- Called when someone buys the "Summon Mega Storm" product
function MegaStormService.Summon(player: Player)
	local now = os.time()
	if phase == "Idle" then
		planRainbow(now)
	end
	if phase == "Idle" and StormSchedule.RainbowFirst(now + settings.SummonDelay, rainbowTime) then
		-- Too close to the Rainbow Hurricane: it strikes right after it instead
		queued += 1
		publish()
		Net.NotifyAll(
			string.format(
				"🌪️ %s summoned a Mega Storm! It will strike right after the %s %s.",
				player.DisplayName,
				rainbow.Icon,
				rainbow.Name
			),
			"Warning"
		)
	elseif phase == "Idle" then
		if summonNext then
			-- A queued storm was about to start; it now follows this one
			queued += 1
			summonNext = false
		end
		stormKey = settings.Types[stormIndex].Key
		nextTime = now + settings.SummonDelay
		summoner = player.DisplayName
		phase = "Warning"
		publish()
		Net.EffectAll("MegaWarning", stormIndex, summoner, stormKey)
		Net.NotifyAll(
			string.format("🌪️ %s summoned a Mega Storm! It arrives in %d seconds!", player.DisplayName, settings.SummonDelay),
			"Warning"
		)
	else
		queued += 1
		publish()
		Net.NotifyAll(
			string.format("🌪️ %s summoned another Mega Storm! It will strike right after this one.", player.DisplayName),
			"Warning"
		)
	end
end

-- Studio testing helper: bring the Rainbow Hurricane forward to `delay` seconds from now.
-- Server command bar: require(game.ServerScriptService.Server.Services.Registry).MegaStormService.ScheduleRainbow(330)
function MegaStormService.ScheduleRainbow(delay: number)
	rainbowTime = os.time() + delay
	rainbowAnnounced = false
	if phase == "Idle" and stormKey == rainbow.Key then
		stormKey = settings.Types[stormIndex].Key
		nextTime = os.time() + settings.Interval
	end
	publish()
end

function MegaStormService.Init()
	stateFolder = ReplicatedStorage:WaitForChild("MegaStormState")
	stormFolder = Instance.new("Folder")
	stormFolder.Name = "MegaStorm"
	stormFolder.Parent = Workspace

	nextTime = os.time() + settings.FirstDelay
	rainbowTime = StormSchedule.NextRainbow(os.time())
	publish()

	Players.PlayerRemoving:Connect(function(player)
		contributions[player] = nil
	end)
end

function MegaStormService.Start()
	while true do
		task.wait(0.5)
		local now = os.time()
		if not rainbowAnnounced and rainbowTime - now <= rainbow.AnnounceTime then
			rainbowAnnounced = true
			announceRainbow(now)
		end
		if phase == "Idle" then
			planRainbow(now)
			if now >= nextTime - settings.WarningTime then
				if stormKey == rainbow.Key then
					-- Always give a full warning, even if this server is running a little late
					nextTime = math.max(nextTime, now + settings.WarningTime)
				end
				summonNext = false
				phase = "Warning"
				publish()
				Net.EffectAll("MegaWarning", stormIndex, summoner, stormKey)
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
