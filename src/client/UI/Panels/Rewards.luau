--!nonstrict
-- Rewards panel: daily login streak, session gifts and promo codes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Pets = require(Shared.Config.Pets)
local RewardsConfig = require(Shared.Config.Rewards)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI)
local Theme = require(script.Parent.Parent.Theme)

local Rewards = {}

local COLORS = Theme.Colors

-- The reward the player will really get: a pet reward turns into its Fallback when they already
-- own that pet or their storage is full (same rule as RewardService.Grant)
local function actualReward(reward, data)
	if reward.Kind == "Pet" and reward.Fallback then
		if #data.Pets >= GameConfig.Pets.MaxStorage then
			return reward.Fallback
		end
		for _, pet in data.Pets do
			if pet.Id == reward.Pet then
				return reward.Fallback
			end
		end
	end
	return reward
end

local function rewardText(reward, data): string
	reward = actualReward(reward, data)
	if reward.Kind == "Volts" then
		return "⚡ " .. Format.Number(reward.Amount * Formulas.VoltsUnit(data))
	elseif reward.Kind == "Boost" then
		return GameConfig.Boosts[reward.Boost].Name .. "\n" .. Format.Duration(reward.Duration)
	elseif reward.Kind == "FreeHatch" then
		return "Free Egg\nHatch"
	elseif reward.Kind == "Pet" then
		return Pets.Pets[reward.Pet].Name .. "\nPet"
	end
	return ""
end

-- Returns: next day to claim (1-7), whether it is ready, seconds until ready
local function dailyState(data, now: number)
	local daily = data.Daily
	local elapsed = now - daily.LastClaim
	local streak = if elapsed > RewardsConfig.DailyStreakWindow then 0 else daily.Streak
	local nextDay = streak % #RewardsConfig.Daily + 1
	return nextDay, elapsed >= RewardsConfig.DailyCooldown, RewardsConfig.DailyCooldown - elapsed
end

local function afterClaim(result, title: string)
	if not result then
		return
	end
	if not result.Ok then
		Registry.InterfaceController.Notify(result.Error, "Error")
		return
	end
	Registry.SoundController.Play("Success")
	Registry.EffectsController.Confetti(60)
	Registry.InterfaceController.Notify("🎁 " .. title .. ": " .. string.gsub(result.Text or "", "\n", " "), "Reward")
	if result.Hatch and result.Hatch.Ok then
		Registry.InterfaceController.ClosePanel(true)
		task.spawn(Registry.HatchOverlay.Play, result.Hatch)
	end
end

local function rewardCard(parent: Instance, order: number, header: string, icon: string)
	local card = UI.Card({ Name = "Reward" .. order, LayoutOrder = order, Parent = parent })
	local headerLabel = UI.Label({
		Name = "Header",
		Text = header,
		Size = UDim2.new(1, -8, 0, 20),
		Position = UDim2.fromOffset(4, 6),
		MaxTextSize = 17,
		Parent = card,
	})
	local iconLabel = UI.Label({
		Name = "Icon",
		Text = icon,
		Stroke = false,
		Size = UDim2.new(1, -30, 0, 44),
		Position = UDim2.fromOffset(15, 28),
		Parent = card,
	})
	local text = UI.Label({
		Name = "Text",
		Text = "",
		TextColor3 = COLORS.Volts,
		Size = UDim2.new(1, -8, 0, 36),
		Position = UDim2.fromOffset(4, 74),
		MaxTextSize = 16,
		Parent = card,
	})
	local status = UI.Label({
		Name = "Status",
		Text = "",
		TextColor3 = COLORS.SubText,
		Size = UDim2.new(1, -8, 0, 20),
		Position = UDim2.new(0, 4, 1, -6),
		AnchorPoint = Vector2.new(0, 1),
		MaxTextSize = 15,
		Parent = card,
	})
	return { Card = card, Header = headerLabel, Icon = iconLabel, Text = text, Status = status, Outline = card:FindFirstChild("Outline") }
end

function Rewards.Build()
	local window = UI.Window({
		Name = "Rewards",
		Title = "Rewards",
		Icon = "🎁",
		Color = "Green",
		Size = UDim2.fromOffset(780, 480),
	})
	local content = window.Content
	local pages = {}

	local function page(key: string)
		local frame = UI.Create("Frame", {
			Name = key,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -52),
			Position = UDim2.fromOffset(0, 52),
			Visible = false,
			Parent = content,
		})
		pages[key] = frame
		return frame
	end

	---------------------------------------------------------------------
	-- Daily
	---------------------------------------------------------------------
	local dailyPage = page("Daily")
	local dailyGrid = UI.Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 150),
		Position = UDim2.fromOffset(0, 26),
		Parent = dailyPage,
		UI.Grid(UDim2.fromOffset(98, 150), UDim2.fromOffset(8, 8)),
	})
	UI.Label({
		Text = "Come back every day! Day 7 gives an exclusive pet (or a Volt vault once you own it).",
		Font = Theme.BodyFont,
		TextColor3 = COLORS.SubText,
		Size = UDim2.new(1, 0, 0, 20),
		MaxTextSize = 16,
		Stroke = 1.5,
		Parent = dailyPage,
	})
	local dailyCards = {}
	for day, reward in RewardsConfig.Daily do
		dailyCards[day] = rewardCard(dailyGrid, day, "Day " .. day, reward.Icon or "🎁")
	end
	local dailyTimer = UI.Label({
		Name = "Timer",
		Text = "",
		TextColor3 = COLORS.SubText,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 190),
		MaxTextSize = 20,
		Parent = dailyPage,
	})
	local claimButton = UI.Button({
		Name = "Claim",
		Text = "CLAIM REWARD",
		Color = "Green",
		Size = UDim2.fromOffset(300, 62),
		Position = UDim2.new(0.5, 0, 0, 226),
		AnchorPoint = Vector2.new(0.5, 0),
		MaxTextSize = 26,
		Parent = dailyPage,
		OnClick = function()
			local result = Remotes.ClaimDaily:InvokeServer()
			afterClaim(result, "Daily reward")
		end,
	})

	---------------------------------------------------------------------
	-- Gifts
	---------------------------------------------------------------------
	local giftsPage = page("Gifts")
	UI.Label({
		Text = "Keep playing to unlock free gifts! They reset every time you join.",
		Font = Theme.BodyFont,
		TextColor3 = COLORS.SubText,
		Size = UDim2.new(1, 0, 0, 20),
		MaxTextSize = 16,
		Stroke = 1.5,
		Parent = giftsPage,
	})
	local giftGrid = UI.Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -26),
		Position = UDim2.fromOffset(0, 26),
		Parent = giftsPage,
		UI.Grid(UDim2.fromOffset(176, 150), UDim2.fromOffset(10, 10)),
	})
	local giftCards = {}
	for index, gift in RewardsConfig.Gifts do
		local card = rewardCard(giftGrid, index, "Gift " .. index, gift.Icon or "🎁")
		local button = UI.Create("TextButton", {
			Name = "Hit",
			BackgroundTransparency = 1,
			Text = "",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
			Parent = card.Card,
		})
		button.Activated:Connect(function()
			local data = Registry.DataController.Data
			if not data or data.GiftsClaimed[tostring(index)] then
				return
			end
			if Registry.DataController.Now() - data.SessionStart < gift.Time then
				Registry.InterfaceController.Notify("This gift isn't ready yet!", "Error")
				return
			end
			Registry.SoundController.Play("Click")
			afterClaim(Remotes.ClaimGift:InvokeServer(index), "Gift " .. index)
		end)
		giftCards[index] = card
	end

	---------------------------------------------------------------------
	-- Codes
	---------------------------------------------------------------------
	local codesPage = page("Codes")
	UI.Label({
		Text = "🏷️ Redeem a code",
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 30),
		MaxTextSize = 28,
		Parent = codesPage,
	})
	local box = UI.Create("TextBox", {
		Name = "CodeBox",
		BackgroundColor3 = COLORS.Inset,
		Size = UDim2.fromOffset(380, 58),
		Position = UDim2.new(0.5, -75, 0, 90),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = Theme.Font,
		PlaceholderText = "Enter code here...",
		PlaceholderColor3 = COLORS.Muted,
		Text = "",
		TextColor3 = COLORS.Text,
		TextSize = 26,
		ClearTextOnFocus = false,
		Parent = codesPage,
		UI.Corner(14),
		UI.Stroke(3),
	})
	local codeStatus = UI.Label({
		Name = "Status",
		Text = "",
		Size = UDim2.new(1, -40, 0, 28),
		Position = UDim2.fromOffset(20, 164),
		MaxTextSize = 20,
		Parent = codesPage,
	})
	UI.Button({
		Name = "Redeem",
		Text = "REDEEM",
		Color = "Green",
		Size = UDim2.fromOffset(140, 58),
		Position = UDim2.new(0.5, 195, 0, 90),
		AnchorPoint = Vector2.new(0.5, 0),
		MaxTextSize = 22,
		Parent = codesPage,
		OnClick = function()
			if box.Text == "" then
				return
			end
			local result = Remotes.RedeemCode:InvokeServer(box.Text)
			if result and result.Ok then
				codeStatus.Text = "✅ Redeemed: " .. (result.Text or "")
				codeStatus.TextColor3 = COLORS.Success
				box.Text = ""
				Registry.SoundController.Play("Success")
				Registry.EffectsController.Confetti(60)
			else
				codeStatus.Text = "❌ " .. (result and result.Error or "Something went wrong.")
				codeStatus.TextColor3 = COLORS.Danger
				Registry.SoundController.Play("Error")
			end
		end,
	})
	UI.Label({
		Text = "Codes are released with updates and milestones.\nLike the game and join the group so you never miss one!",
		Font = Theme.BodyFont,
		TextColor3 = COLORS.SubText,
		Size = UDim2.new(1, -60, 0, 50),
		Position = UDim2.fromOffset(30, 220),
		MaxTextSize = 17,
		Stroke = 1.5,
		Parent = codesPage,
	})

	local tabs = UI.Tabs({
		Tabs = {
			{ Key = "Daily", Text = "📅 Daily" },
			{ Key = "Gifts", Text = "🎁 Gifts" },
			{ Key = "Codes", Text = "🏷️ Codes" },
		},
		Color = "Green",
		TabWidth = 150,
		Parent = content,
		OnSelect = function(key)
			for pageKey, frame in pages do
				frame.Visible = pageKey == key
			end
		end,
	})

	---------------------------------------------------------------------
	-- Refresh (also drives the badge on the menu button)
	---------------------------------------------------------------------
	local function refresh()
		local data = Registry.DataController.Data
		if not data then
			return
		end
		local now = Registry.DataController.Now()
		local nextDay, ready, remaining = dailyState(data, now)
		local available = if ready then 1 else 0

		local elapsed = now - data.SessionStart
		local readyGifts = {}
		for index, gift in RewardsConfig.Gifts do
			local claimed = data.GiftsClaimed[tostring(index)] == true
			readyGifts[index] = not claimed and elapsed >= gift.Time
			if readyGifts[index] then
				available += 1
			end
		end
		Registry.HudController.SetBadge("Rewards", available)

		if not window.Frame.Visible then
			return
		end

		for day, card in dailyCards do
			local reward = RewardsConfig.Daily[day]
			card.Text.Text = rewardText(reward, data)
			card.Icon.Text = actualReward(reward, data).Icon or reward.Icon or "🎁"
			if day < nextDay then
				card.Status.Text = "✓ Claimed"
				card.Status.TextColor3 = COLORS.Success
				card.Outline.Color = COLORS.Success
				card.Outline.Thickness = 2
			elseif day == nextDay then
				card.Status.Text = if ready then "READY!" else "Next"
				card.Status.TextColor3 = COLORS.Volts
				card.Outline.Color = COLORS.Volts
				card.Outline.Thickness = if ready then 3 + (math.sin(os.clock() * 6) + 1) else 3
			else
				card.Status.Text = "🔒"
				card.Status.TextColor3 = COLORS.Muted
				card.Outline.Color = COLORS.Stroke
				card.Outline.Thickness = 2
			end
			card.Outline.Transparency = 0
		end
		if ready then
			dailyTimer.Text = "Your Day " .. nextDay .. " reward is ready!"
			UI.SetButtonColor(claimButton, "Green")
			UI.SetButtonText(claimButton, "CLAIM REWARD")
		else
			dailyTimer.Text = "Next reward in " .. Format.Time(remaining)
			UI.SetButtonColor(claimButton, "Gray")
			UI.SetButtonText(claimButton, "COME BACK LATER")
		end

		for index, card in giftCards do
			local gift = RewardsConfig.Gifts[index]
			card.Text.Text = rewardText(gift, data)
			card.Outline.Transparency = 0
			if data.GiftsClaimed[tostring(index)] then
				card.Status.Text = "✓ Opened"
				card.Status.TextColor3 = COLORS.Success
				card.Outline.Color = COLORS.Success
				card.Outline.Thickness = 2
			elseif readyGifts[index] then
				card.Status.Text = "TAP TO OPEN!"
				card.Status.TextColor3 = COLORS.Volts
				card.Outline.Color = COLORS.Volts
				card.Outline.Thickness = 3 + (math.sin(os.clock() * 6) + 1)
			else
				card.Status.Text = "⏱ " .. Format.Time(gift.Time - elapsed)
				card.Status.TextColor3 = COLORS.SubText
				card.Outline.Color = COLORS.Stroke
				card.Outline.Thickness = 2
			end
		end
	end

	task.spawn(function()
		while true do
			refresh()
			task.wait(if window.Frame.Visible then 0.25 else 1)
		end
	end)

	return {
		Window = window,
		OnOpen = function(tab: string?)
			tabs.Select(tab or tabs.Selected or "Daily")
			refresh()
		end,
	}
end

return Rewards
