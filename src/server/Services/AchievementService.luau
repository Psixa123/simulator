--!nonstrict
-- Awards the Roblox badges of Shared/Config/Badges.luau (named AchievementService so it isn't confused with
-- Roblox's own BadgeService, which it calls).
--
-- It never hooks into game logic: it watches the player's data instead. Every DataService change (and
-- loading the data, and a slow sweep) queues a check that runs a moment later, after the code that changed
-- the data has finished, and awards each badge whose rule the data now meets. Loading the data counts too,
-- so players whose saves already qualify (zones, rebirths, pets...) get the badges when they join.
--
-- Roblox calls run in their own thread inside pcall: UserHasBadgeAsync once per badge per session (cached),
-- then AwardBadgeAsync. A failed call is retried later with a growing delay, a few times at most. Badges whose
-- Id is still 0 are skipped (Studio prints what would have been awarded).

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Badges = require(Shared.Config.Badges)

local Registry = require(script.Parent.Registry)

local AchievementService = {}

local CHECK_GAP = 0.5 -- seconds between two checks of the same player
local SWEEP_INTERVAL = 20 -- seconds between checks of everyone (catches changes nobody replicated)
local RETRY_BASE = 15 -- seconds before the first retry of a failed Roblox call; doubles every failure
local RETRY_MAX = 300
local MAX_FAILURES = 5 -- per badge per session; after that it waits for the next session

-- [Player] = { Done = {[key]=true}, Has = {[key]=bool}, Busy = {[key]=true}, Failures = {[key]=n},
--              RetryAt = {[key]=clock}, Queued = bool, LastCheck = clock }
local states = {}

-- Swappable in the mock test
AchievementService.Badges = Badges.List
AchievementService.RobloxBadges = BadgeService
AchievementService.Clock = os.clock

local function stateOf(player: Player)
	local state = states[player]
	if not state then
		state = { Done = {}, Has = {}, Busy = {}, Failures = {}, RetryAt = {}, Queued = false, LastCheck = -math.huge }
		states[player] = state
	end
	return state
end

local queueCheck -- (player) forward declaration

local function failed(player: Player, state, badge, reason: string)
	local count = (state.Failures[badge.Key] or 0) + 1
	state.Failures[badge.Key] = count
	if count >= MAX_FAILURES then
		state.Done[badge.Key] = true -- give up for this session; the next join tries again
		warn(string.format("[Achievements] Giving up on '%s' for %s this session: %s", badge.Key, player.Name, reason))
		return
	end
	local delay = math.min(RETRY_MAX, RETRY_BASE * 2 ^ (count - 1))
	state.RetryAt[badge.Key] = AchievementService.Clock() + delay
	task.delay(delay, function()
		if states[player] == state and player.Parent then
			queueCheck(player)
		end
	end)
end

-- Runs in its own thread: the Roblox calls yield
local function award(player: Player, state, badge)
	local robloxBadges = AchievementService.RobloxBadges
	local has = state.Has[badge.Key]
	if has == nil then
		local ok, result = pcall(function()
			return robloxBadges:UserHasBadgeAsync(player.UserId, badge.Id)
		end)
		if not ok then
			failed(player, state, badge, tostring(result))
			return
		end
		has = result == true
		state.Has[badge.Key] = has
	end
	if has then
		state.Done[badge.Key] = true
		return
	end
	if not player.Parent then
		return
	end
	local ok, result = pcall(function()
		return robloxBadges:AwardBadgeAsync(player.UserId, badge.Id)
	end)
	if ok and result then
		state.Done[badge.Key] = true
		state.Has[badge.Key] = true
		print(string.format("[Achievements] %s earned the '%s' badge", player.Name, badge.Name))
	else
		failed(player, state, badge, if ok then "AwardBadgeAsync returned false" else tostring(result))
	end
end

-- Awards every badge the player's data has earned and that isn't done or in flight. Never yields.
function AchievementService.Check(player: Player)
	local data = Registry.DataService.Get(player)
	if not data or not player.Parent then
		return
	end
	local state = stateOf(player)
	local now = AchievementService.Clock()
	state.LastCheck = now
	for _, badge in AchievementService.Badges do
		local key = badge.Key
		if state.Done[key] or state.Busy[key] or now < (state.RetryAt[key] or 0) then
			continue
		end
		local ok, qualifies = pcall(Badges.Qualifies, badge, data)
		if not ok or not qualifies then
			continue
		end
		if type(badge.Id) ~= "number" or badge.Id <= 0 then
			state.Done[key] = true
			if RunService:IsStudio() then
				print(string.format("[Achievements] %s would earn '%s' (no badge Id yet)", player.Name, badge.Name))
			end
			continue
		end
		state.Busy[key] = true
		task.spawn(function()
			local done, err = pcall(award, player, state, badge)
			if not done then
				failed(player, state, badge, tostring(err))
			end
			state.Busy[key] = nil
		end)
	end
end

-- Checks the player a moment from now (at most once every CHECK_GAP seconds), after the current code is done
function queueCheck(player: Player)
	if not player.Parent then
		return
	end
	local state = stateOf(player)
	if state.Queued then
		return
	end
	state.Queued = true
	local wait = math.max(0, state.LastCheck + CHECK_GAP - AchievementService.Clock())
	task.delay(wait, function()
		state.Queued = false
		if states[player] == state then
			AchievementService.Check(player)
		end
	end)
end
AchievementService.QueueCheck = queueCheck

function AchievementService.Init()
	local DataService = Registry.DataService
	DataService.PlayerLoaded:Connect(function(player)
		queueCheck(player)
	end)
	DataService.Changed:Connect(function(player)
		queueCheck(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

function AchievementService.Start()
	while true do
		for _, player in Players:GetPlayers() do
			if Registry.DataService.Get(player) then
				queueCheck(player)
			end
		end
		task.wait(SWEEP_INTERVAL)
	end
end

return AchievementService
