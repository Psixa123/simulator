--!nonstrict
-- Server-wide Mega Storm event in the hub arena.
-- Idle -> Warning (30s countdown) -> Active (everyone vacuums the storm) -> rewards -> Idle.
-- Every 2 hours on the hour (UTC) the Rainbow Hurricane strikes in every server at once: it's
-- announced 5 minutes ahead and regular / summoned storms that would overlap it wait for it.
-- State is published as attributes on ReplicatedStorage.MegaStormState for the clients, plus
-- "Leaders" (JSON list of the top contributors while a storm is Active, "[]" otherwise) and a
-- "MegaDamage" attribute on each contributing Player with their own damage.

local HttpService = game:GetService("HttpService")
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
local LEADER_COUNT = 5
local LEADERS_INTERVAL = 1 -- seconds between "Leaders" / "MegaDamage" updates
local LATE_HEALTH_SHARE = 0.5 -- latecomers add this share of a full player's health (scaled by time left)
local MEDALS = { "🥇", "🥈", "🥉" }
local stateFolder: Configuration
local stormFolder: Folder
local rng = Random.new()

local phase = "Idle"
local nextTime = 0
local regularTime = 0 -- when the next regular storm is due (summoned storms don't move it)
local stormIndex = 1
local stormKey = settings.Types[1].Key -- current / next storm ("Rainbow" for the Rainbow Hurricane)
local rainbowTime = 0 -- next Rainbow Hurricane that hasn't started yet
local rainbowAnnounced = false
local summonNext = false -- the next regular storm is a queued summon
local health = 0
local maxHealth = 0
local endTime = 0
local summoner = ""
local summonQueue = {} -- DisplayNames of buyers whose summoned storms wait for their turn
local contributions = {} -- [Player] = drained
local counted = {} -- [Player] = true once their Power is part of the storm's health
local leadersDirty = false
local leadersAt = 0
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
	stateFolder:SetAttribute("Queued", #summonQueue)
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

local function inArena(position: Vector3): boolean
	local offset = position - MapLayout.ArenaCenter
	return Vector2.new(offset.X, offset.Z).Magnitude <= settings.Range
end

-- Storm health one player is worth: their vacuum + pets' power for HealthSecondsPerPlayer
local function playerHealth(data): number
	local power = Formulas.Power(data) + Formulas.PetCatchPower(data)
	return power / GameConfig.CatchTickRate * settings.HealthSecondsPerPlayer
end

-- Contributors sorted by damage, best first
local function rankContributors()
	local ranking = {}
	for player, amount in contributions do
		if player.Parent then
			table.insert(ranking, { Player = player, Amount = amount })
		end
	end
	table.sort(ranking, function(a, b)
		return a.Amount > b.Amount
	end)
	return ranking
end

-- Live top contributors ("Leaders") and everyone's own damage ("MegaDamage")
local function publishLeaders()
	leadersDirty = false
	leadersAt = os.clock()
	local leaders = {}
	if phase == "Active" then
		for rank, entry in rankContributors() do
			local damage = math.floor(entry.Amount)
			entry.Player:SetAttribute("MegaDamage", damage)
			if rank <= LEADER_COUNT then
				table.insert(leaders, { Name = entry.Player.DisplayName, UserId = entry.Player.UserId, Damage = damage })
			end
		end
	end
	stateFolder:SetAttribute("Leaders", if #leaders > 0 then HttpService:JSONEncode(leaders) else "[]")
end

function MegaStormService.CanCatch(root: BasePart): boolean
	if phase ~= "Active" or health <= 0 then
		return false
	end
	return inArena(root.Position)
end

local endStorm

-- amount defaults to the player's vacuum Power (pets pass their own catch power)
function MegaStormService.Drain(player: Player, data, root: BasePart, amount: number?): boolean
	if not MegaStormService.CanCatch(root) then
		return false
	end
	if not counted[player] then
		-- Latecomers make the storm a bit tougher, less so the later they join, so they
		-- can never push a nearly beaten storm into escaping
		counted[player] = true
		local stormType = currentType()
		local timeLeft = math.clamp((endTime - os.time()) / StormSchedule.Duration(stormType), 0, 1)
		local extra = math.floor(playerHealth(data) * LATE_HEALTH_SHARE * timeLeft * (stormType.HealthMultiplier or 1))
		health += extra
		maxHealth += extra
		stateFolder:SetAttribute("MaxHealth", maxHealth)
	end
	local drained = math.min(health, amount or Formulas.Power(data))
	health -= drained
	contributions[player] = (contributions[player] or 0) + drained
	leadersDirty = true
	stateFolder:SetAttribute("Health", health)
	if health <= 0 then
		task.defer(endStorm, true)
	end
	return true
end

local function beginStorm()
	local stormType = currentType()
	-- Only players at the arena (they had the warning to gather) size the storm;
	-- anyone who joins in later adds a little health in Drain
	local totalHealth = 0
	counted = {}
	for _, player in Players:GetPlayers() do
		player:SetAttribute("MegaDamage", 0)
		local data = Registry.DataService.Get(player)
		local root = Net.GetRoot(player)
		if data and root and inArena(root.Position) then
			totalHealth += playerHealth(data)
			counted[player] = true
		end
	end

	maxHealth = math.max(settings.MinHealth, math.floor(totalHealth))
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
	publishLeaders()
	Net.EffectAll("MegaStart", stormIndex, stormKey)
end

function endStorm(defeated: boolean)
	if phase ~= "Active" then
		return
	end
	phase = "Ending"

	local stormType = currentType()
	local isRainbow = stormType == rainbow
	local wasSummoned = summoner ~= ""
	local ranking = rankContributors()

	for rank, entry in ranking do
		local player = entry.Player
		player:SetAttribute("MegaDamage", math.floor(entry.Amount))
		local data = Registry.DataService.Get(player)
		if data then
			local volts = math.floor(Formulas.MegaStormReward(data, entry.Amount, defeated) * (stormType.RewardMultiplier or 1))
			Registry.EconomyService.AddVolts(player, volts)
			data.Stats.MegaStorms += 1

			local petId = nil
			if defeated and entry.Amount >= maxHealth * settings.MinContribution then
				local chance = settings.ExclusiveChances[rank] or settings.ParticipantChance
				-- A won exclusive is never thrown away, even if pet storage is full
				local overflow = #data.Pets >= GameConfig.Pets.MaxStorage
				if rng:NextNumber() < chance and Registry.PetService.GivePet(player, stormType.Pet, false, true) then
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
					if overflow then
						Net.Notify(
							player,
							"🎒 Your pet storage is over the limit, but your exclusive pet is safe! Delete some pets to keep hatching.",
							"Warning"
						)
					end
				end
			end
			Net.Effect(player, "MegaReward", volts, rank, #ranking, petId, defeated)
		end
	end

	local podium = {}
	for rank = 1, math.min(#MEDALS, #ranking) do
		table.insert(podium, MEDALS[rank] .. " " .. ranking[rank].Player.DisplayName)
	end
	if #podium > 0 then
		Net.NotifyAll("🏆 Top storm catchers: " .. table.concat(podium, "   "), "Reward")
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
	local now = os.time()
	if isRainbow or not wasSummoned then
		-- A regular storm (or the Rainbow Hurricane that took its turn) ran
		regularTime = now + settings.Interval
	end
	summonNext = #summonQueue > 0
	if summonNext then
		summoner = table.remove(summonQueue, 1)
		nextTime = now + StormSchedule.QueueGap
	else
		-- Summoned storms come on top of the regular ones instead of replacing them
		summoner = ""
		nextTime = math.max(regularTime, now + StormSchedule.QueueGap)
	end
	health = 0
	maxHealth = 0
	endTime = 0
	contributions = {}
	counted = {}
	phase = "Idle"
	publish()
	publishLeaders()
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
			table.insert(summonQueue, 1, summoner)
			summonNext = false
		end
		stormKey = rainbow.Key
		nextTime = rainbowTime
		regularTime = rainbowTime -- it takes the regular storm's turn
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
		table.insert(summonQueue, player.DisplayName)
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
			table.insert(summonQueue, 1, summoner)
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
		table.insert(summonQueue, player.DisplayName)
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
		regularTime = os.time() + settings.Interval
		nextTime = regularTime
	end
	publish()
end

function MegaStormService.Init()
	stateFolder = ReplicatedStorage:WaitForChild("MegaStormState")
	stormFolder = Instance.new("Folder")
	stormFolder.Name = "MegaStorm"
	stormFolder.Parent = Workspace

	nextTime = os.time() + settings.FirstDelay
	regularTime = nextTime
	rainbowTime = StormSchedule.NextRainbow(os.time())
	publish()
	publishLeaders()

	Players.PlayerRemoving:Connect(function(player)
		if contributions[player] then
			leadersDirty = true
		end
		contributions[player] = nil
		counted[player] = nil
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
			elseif leadersDirty and os.clock() - leadersAt >= LEADERS_INTERVAL then
				publishLeaders()
			end
		end
	end
end

return MegaStormService
