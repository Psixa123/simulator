--!nonstrict
-- Mega Storm schedule shared by the server (MegaStormService) and the clients (forecast board).
-- The Rainbow Hurricane strikes in every server at the same real-world time: on the hour,
-- every GameConfig.MegaStorm.Rainbow.Interval seconds (UTC), derived from os.time().
-- The server publishes the schedule as attributes on ReplicatedStorage.MegaStormState:
--   Phase, NextTime, EndTime, StormIndex, StormKey (current / next storm), RainbowTime
--   (next Rainbow Hurricane that hasn't started yet) and Queued (summoned storms waiting).

local Config = script.Parent:WaitForChild("Config")
local GameConfig = require(Config.GameConfig)

local StormSchedule = {}

local settings = GameConfig.MegaStorm
local rainbow = settings.Rainbow

-- Seconds between a storm ending and the next summoned (queued) storm
StormSchedule.QueueGap = settings.WarningTime + 10

-- First Rainbow Hurricane slot strictly after `time` (unix seconds, UTC)
function StormSchedule.NextRainbow(time: number): number
	return (math.floor(time / rainbow.Interval) + 1) * rainbow.Interval
end

-- Storm definition for a StormKey ("Rainbow" or a regular key) / StormIndex pair
function StormSchedule.TypeFor(key, index)
	if key == rainbow.Key then
		return rainbow
	end
	return settings.Types[index or 1] or settings.Types[1]
end

-- The storm that is running right now, or the next one
function StormSchedule.Current(state: Instance)
	return StormSchedule.TypeFor(state:GetAttribute("StormKey"), state:GetAttribute("StormIndex"))
end

function StormSchedule.IsRainbow(stormType): boolean
	return stormType == rainbow
end

function StormSchedule.Duration(stormType): number
	return stormType.Duration or settings.Duration
end

-- True when a regular storm due at `time` wouldn't be over (plus some clearance) before the
-- Rainbow Hurricane's warning starts, so the Rainbow Hurricane has to go first
function StormSchedule.RainbowFirst(time: number, rainbowTime: number): boolean
	return time + settings.Duration + rainbow.Clearance > rainbowTime - settings.WarningTime
end

-- Predicts the next `count` storms from the published state, following the same rules as
-- the server. Returns { { Time, Type, Exact } }; regular storms after the next one are
-- estimates (Exact = false) because a storm can be defeated before its timer runs out.
function StormSchedule.Upcoming(state: Instance, now: number, count: number)
	local phase = state:GetAttribute("Phase") or "Idle"
	local index = state:GetAttribute("StormIndex") or 1
	local nextTime = state:GetAttribute("NextTime") or now
	local rainbowTime = state:GetAttribute("RainbowTime") or StormSchedule.NextRainbow(now)
	local queued = state:GetAttribute("Queued") or 0
	local current = StormSchedule.Current(state)
	local list = {}

	local finish -- when the current (or next) storm should be over
	if phase == "Active" or phase == "Ending" then
		finish = state:GetAttribute("EndTime") or now
	else
		table.insert(list, { Time = nextTime, Type = current, Exact = true })
		finish = nextTime + StormSchedule.Duration(current)
		if current == rainbow then
			rainbowTime = StormSchedule.NextRainbow(rainbowTime)
		end
	end

	-- The Rainbow Hurricane doesn't use up a storm from the regular rotation
	local regularIndex = if current == rainbow then index else index % #settings.Types + 1
	local function gap(): number
		if queued > 0 then
			queued -= 1
			return StormSchedule.QueueGap
		end
		return settings.Interval
	end

	local cursor = finish + gap()
	while #list < count do
		if StormSchedule.RainbowFirst(cursor, rainbowTime) then
			table.insert(list, { Time = rainbowTime, Type = rainbow, Exact = true })
			cursor = rainbowTime + StormSchedule.Duration(rainbow) + gap()
			rainbowTime = StormSchedule.NextRainbow(rainbowTime)
		else
			table.insert(list, { Time = cursor, Type = settings.Types[regularIndex], Exact = false })
			regularIndex = regularIndex % #settings.Types + 1
			cursor += settings.Duration + gap()
		end
	end
	return list
end

return StormSchedule
