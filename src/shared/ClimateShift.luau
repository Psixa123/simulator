--!nonstrict
-- Climate Shift (the rebirth system's name in the game) helpers shared by the server and the
-- client: which gear look a number of Climate Shifts unlocks. Looks live in GameConfig.Rebirth.

local Config = script.Parent:WaitForChild("Config")
local GameConfig = require(Config.GameConfig)

local ClimateShift = {}

-- Best look unlocked with `shifts` Climate Shifts and its index in GameConfig.Rebirth.Cosmetics
-- (index 0 = the default look everyone starts with)
function ClimateShift.Cosmetic(shifts: number?)
	local count = shifts or 0
	local best, bestIndex = GameConfig.Rebirth.DefaultCosmetic, 0
	for index, look in GameConfig.Rebirth.Cosmetics do
		if look.Shifts <= count and (bestIndex == 0 or look.Shifts >= best.Shifts) then
			best, bestIndex = look, index
		end
	end
	return best, bestIndex
end

-- The next look to unlock (nil once every look is unlocked)
function ClimateShift.NextCosmetic(shifts: number?)
	local count = shifts or 0
	local nextLook = nil
	for _, look in GameConfig.Rebirth.Cosmetics do
		if look.Shifts > count and (nextLook == nil or look.Shifts < nextLook.Shifts) then
			nextLook = look
		end
	end
	return nextLook
end

-- The look unlocked by reaching exactly `shifts` Climate Shifts, if any
function ClimateShift.UnlockedAt(shifts: number?)
	for _, look in GameConfig.Rebirth.Cosmetics do
		if look.Shifts == shifts then
			return look
		end
	end
	return nil
end

-- How many looks (not counting the default one) are unlocked
function ClimateShift.UnlockedCount(shifts: number?): number
	local count = 0
	for _, look in GameConfig.Rebirth.Cosmetics do
		if look.Shifts <= (shifts or 0) then
			count += 1
		end
	end
	return count
end

return ClimateShift
