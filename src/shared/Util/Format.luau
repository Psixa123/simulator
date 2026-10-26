--!nonstrict
-- Number and time formatting used across the whole game (UI, billboards, notifications).

local Format = {}

local SUFFIXES = {
	"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc",
	"Ud", "Dd", "Td", "Qad", "Qid", "Sxd", "Spd", "Ocd", "Nod", "Vg",
}

local function trimZeros(text: string): string
	if string.find(text, ".", 1, true) then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

-- 1234 -> "1.23K", 15500000 -> "15.5M"
function Format.Number(value: number?): string
	local number = tonumber(value) or 0
	if number ~= number then
		return "0"
	end
	if number == math.huge or number == -math.huge then
		return if number > 0 then "∞" else "-∞" -- never "inf"
	end

	local sign = if number < 0 then "-" else ""
	number = math.abs(number)

	if number < 1000 then
		if number >= 100 or number == math.floor(number) then
			return sign .. tostring(math.floor(number))
		end
		return sign .. trimZeros(string.format("%.1f", math.floor(number * 10) / 10))
	end

	local tier = math.floor(math.log10(number) / 3)
	local scaled = number / 10 ^ (tier * 3)
	if scaled >= 1000 then
		tier += 1
		scaled /= 1000
	elseif scaled < 1 then
		tier -= 1
		scaled *= 1000
	end

	if tier >= #SUFFIXES then
		return sign .. string.format("%.2e", number)
	end

	local text
	if scaled >= 100 then
		text = tostring(math.floor(scaled))
	elseif scaled >= 10 then
		text = trimZeros(string.format("%.1f", math.floor(scaled * 10) / 10))
	else
		text = trimZeros(string.format("%.2f", math.floor(scaled * 100) / 100))
	end

	return sign .. text .. SUFFIXES[tier + 1]
end

-- 1234567 -> "1,234,567" (only meant for numbers below ~1e15)
function Format.Commas(value: number): string
	local text = tostring(math.floor(value))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	if string.sub(formatted, 1, 1) == "," then
		formatted = string.sub(formatted, 2)
	end
	return formatted
end

-- 75 -> "1:15", 3725 -> "1:02:05"
function Format.Time(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	local secs = seconds % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, secs)
	end
	return string.format("%d:%02d", minutes, secs)
end

-- 900 -> "15m", 5400 -> "1h 30m", 45 -> "45s"
function Format.Duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds < 60 then
		return seconds .. "s"
	end
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	if hours > 0 then
		if minutes > 0 then
			return string.format("%dh %dm", hours, minutes)
		end
		return hours .. "h"
	end
	return minutes .. "m"
end

-- 0.0035 -> "0.35%", 0.55 -> "55%"
function Format.Chance(fraction: number): string
	local percent = fraction * 100
	if percent >= 10 then
		return trimZeros(string.format("%.1f", percent)) .. "%"
	elseif percent >= 1 then
		return trimZeros(string.format("%.2f", percent)) .. "%"
	end
	return trimZeros(string.format("%.3f", percent)) .. "%"
end

-- Pet bonus (0.35) -> "+35%"
function Format.Bonus(bonus: number): string
	return "+" .. Format.Number(math.floor(bonus * 100 + 0.5)) .. "%"
end

-- Multiplier (2.456) -> "x2.45"
function Format.Multiplier(value: number): string
	if value >= 1000 then
		return "x" .. Format.Number(value)
	end
	return "x" .. trimZeros(string.format("%.2f", math.floor(value * 100) / 100))
end

return Format
