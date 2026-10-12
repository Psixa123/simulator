--!nonstrict
-- Daily login rewards (7 day streak), session gifts and promo codes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Pets = require(Shared.Config.Pets)
local Rewards = require(Shared.Config.Rewards)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Registry)
local Net = require(script.Parent.Net)

local RewardService = {}

-- Grants a reward table. Returns a description and (for free hatches) the hatch result.
function RewardService.Grant(player: Player, reward)
	local data = Registry.DataService.Get(player)
	if not data or not reward then
		return "", nil
	end

	if reward.Kind == "Volts" then
		local amount = reward.Amount * Formulas.VoltsUnit(data)
		Registry.EconomyService.AddVolts(player, amount)
		return "⚡ " .. Format.Number(amount) .. " Volts", nil
	elseif reward.Kind == "Boost" then
		local boost = GameConfig.Boosts[reward.Boost]
		Registry.BoostService.Add(player, reward.Boost, reward.Duration, true)
		return string.format("%s %s (%s)", boost.Icon, boost.Name, Format.Duration(reward.Duration)), nil
	elseif reward.Kind == "Pet" then
		if Registry.PetService.OwnsPet(data, reward.Pet) then
			return RewardService.Grant(player, reward.Fallback)
		end
		local entry = Registry.PetService.GivePet(player, reward.Pet, false)
		if not entry then
			return RewardService.Grant(player, reward.Fallback)
		end
		Net.Effect(player, "PetReveal", reward.Pet, false)
		return "🐾 " .. Pets.Pets[reward.Pet].Name .. " pet", nil
	elseif reward.Kind == "FreeHatch" then
		local eggId = Registry.PetService.BestEgg(data)
		local result = Registry.PetService.Hatch(player, eggId, 1, true)
		if result.Ok then
			return "🥚 Free " .. Pets.Eggs[eggId].Name .. " hatch", result
		end
		-- Storage full: give Volts instead so the reward is never lost
		return RewardService.Grant(player, { Kind = "Volts", Amount = 3 })
	end

	return "", nil
end

local function claimDaily(player: Player)
	local data = Registry.DataService.Get(player)
	if not data then
		return Net.Fail("Still loading...")
	end
	local now = os.time()
	local daily = data.Daily
	local elapsed = now - daily.LastClaim
	if elapsed < Rewards.DailyCooldown then
		return Net.Fail("Come back in " .. Format.Time(Rewards.DailyCooldown - elapsed) .. "!")
	end

	local streak = if elapsed > Rewards.DailyStreakWindow then 0 else daily.Streak
	local day = streak % #Rewards.Daily + 1
	daily.Streak = streak + 1
	daily.LastClaim = now

	local text, hatch = RewardService.Grant(player, Rewards.Daily[day])
	Registry.DataService.Replicate(player, "Daily")
	return { Ok = true, Day = day, Text = text, Hatch = hatch }
end

local function claimGift(player: Player, index: number)
	local data = Registry.DataService.Get(player)
	local gift = type(index) == "number" and Rewards.Gifts[index]
	if not data or not gift then
		return Net.Fail("Invalid gift.")
	end
	local key = tostring(index)
	if data.GiftsClaimed[key] then
		return Net.Fail("You already opened this gift!")
	end
	local remaining = gift.Time - (os.time() - data.SessionStart)
	if remaining > 0 then
		return Net.Fail("This gift unlocks in " .. Format.Time(remaining) .. ".")
	end
	data.GiftsClaimed[key] = true
	local text, hatch = RewardService.Grant(player, gift)
	Registry.DataService.Replicate(player, "GiftsClaimed")
	return { Ok = true, Text = text, Hatch = hatch }
end

local function redeemCode(player: Player, code: string)
	local data = Registry.DataService.Get(player)
	if not data or type(code) ~= "string" or #code > 40 then
		return Net.Fail("Invalid code!")
	end
	local normalized = string.upper((string.gsub(code, "%s", "")))
	local reward = Rewards.Codes[normalized]
	if not reward then
		return Net.Fail("That code doesn't exist (or has expired)!")
	end
	if data.Codes[normalized] then
		return Net.Fail("You already redeemed this code!")
	end
	data.Codes[normalized] = true
	local text = RewardService.Grant(player, reward)
	return { Ok = true, Text = text }
end

function RewardService.Init()
	Remotes.ClaimDaily.OnServerInvoke = function(player)
		if not Net.RateLimit(player, "Daily", 1) then
			return Net.Fail("Slow down!")
		end
		return claimDaily(player)
	end

	Remotes.ClaimGift.OnServerInvoke = function(player, index)
		if not Net.RateLimit(player, "Gift", 0.5) then
			return Net.Fail("Slow down!")
		end
		return claimGift(player, index)
	end

	Remotes.RedeemCode.OnServerInvoke = function(player, code)
		if not Net.RateLimit(player, "Code", 1.5) then
			return Net.Fail("Please wait a moment before trying another code.")
		end
		return redeemCode(player, code)
	end
end

return RewardService
