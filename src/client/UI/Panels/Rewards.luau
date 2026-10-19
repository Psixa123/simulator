--!nonstrict
-- Rewards panel: daily login streak, session gifts and promo codes.
-- Sky Lab look: white reward cards with a 3D icon and a status pill (claimed = Leaf, ready = Bolt
-- with a pulsing outline, next = Sky, locked = a padlock), and candy claim / redeem buttons.

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
local Icons = require(script.Parent.Parent.Icons)
local Viewport = require(script.Parent.Parent.Viewport)

local Rewards = {}

local INK = Theme.Ink
local WHITE = Color3.new(1, 1, 1)
local SETS = Theme.Sets

-- Volts rewards grow with their icon: coin, coin bag, gift, big gift
local VOLTS_ICONS = { ["⚡"] = "Volts", ["💰"] = "Sell", ["📦"] = "Gift", ["🏦"] = "Rewards" }

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
		return Format.Number(reward.Amount * Formulas.VoltsUnit(data)) .. "\nVolts"
	elseif reward.Kind == "Boost" then
		return GameConfig.Boosts[reward.Boost].Name .. "\n" .. Format.Duration(reward.Duration)
	elseif reward.Kind == "FreeHatch" then
		return "Free Egg\nHatch"
	elseif reward.Kind == "Pet" then
		return Pets.Pets[reward.Pet].Name .. "\nPet"
	end
	return ""
end

-- The Icons.luau key for a reward (a pet reward shows the pet itself instead)
local function rewardIcon(reward): string
	if reward.Kind == "Volts" then
		return VOLTS_ICONS[reward.Icon or ""] or "Volts"
	elseif reward.Kind == "Boost" then
		return if reward.Boost == "Luck" then "Luck" else "Boost"
	elseif reward.Kind == "FreeHatch" then
		return "Eggs"
	end
	return reward.Icon or "Gift"
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

local function frame(props)
	local object = Instance.new("Frame")
	object.BorderSizePixel = 0
	object.BackgroundColor3 = WHITE
	for key, value in props do
		if type(key) == "number" then
			value.Parent = object
		elseif key ~= "Parent" then
			object[key] = value
		end
	end
	object.Parent = props.Parent
	return object
end

-- Status pill at the bottom of a card: a candy-coloured pill with white text, or a padlock
local function statusPill(parent: Instance)
	local pill = frame({
		Name = "Status",
		BackgroundColor3 = INK,
		Size = UDim2.new(1, -14, 0, 26),
		Position = UDim2.new(0.5, 0, 1, -7),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = 3,
		Parent = parent,
		UI.Round(),
	})
	local fill = frame({ Name = "Fill", Size = UDim2.new(1, -4, 1, -4), Position = UDim2.fromOffset(2, 2), ZIndex = 3, Parent = pill, UI.Round() })
	local gradient = UI.Gradient(WHITE, WHITE)
	gradient.Parent = fill
	local row = frame({
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = pill,
		UI.List(Enum.FillDirection.Horizontal, 3, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	local icon = Icons.New("Check", { Name = "Icon", Size = UDim2.fromOffset(18, 18), LayoutOrder = 1, ZIndex = 4, Parent = row })
	local label = UI.Text({ Name = "Text", Text = "", TextSize = 14, Stroke = INK, StrokeThickness = 1.5, Size = UDim2.fromOffset(0, 26), LayoutOrder = 2, Position = UDim2.fromOffset(0, 1), ZIndex = 4, Parent = row })
	label.AutomaticSize = Enum.AutomaticSize.X
	local lock = Icons.New("Lock", { Name = "Lock", Size = UDim2.fromOffset(24, 24), Position = UDim2.new(0.5, 0, 1, -20), ZIndex = 4, Parent = parent })

	-- kind: "Claimed" | "Ready" | "Next" | "Locked" | "Wait"
	return function(kind: string, text: string?)
		lock.Visible = kind == "Locked"
		pill.Visible = kind ~= "Locked"
		local set = if kind == "Claimed" then SETS.Leaf elseif kind == "Ready" then SETS.Bolt elseif kind == "Next" then SETS.Sky else SETS.Off
		pill.BackgroundColor3 = if kind == "Wait" then Theme.HazeDeep else INK
		gradient.Color = if kind == "Wait" then ColorSequence.new(Theme.Mist, Theme.Haze) else ColorSequence.new(set.Top, set.Bottom)
		icon.Visible = kind == "Claimed"
		label.Text = text or ""
		label.TextColor3 = if kind == "Wait" then Theme.InkSoft else WHITE
		label.TextStroke.Enabled = kind ~= "Wait"
		label.TextStroke.Color = set.Stroke
	end
end

-- A reward card: header, icon (or the pet), reward text and the status pill
local function rewardCard(parent: Instance, order: number, header: string)
	local card = UI.CloudCard({ Name = "Reward" .. order, LayoutOrder = order, Parent = parent })
	local headerLabel = UI.Text({ Name = "Header", Text = header, TextSize = 16, Size = UDim2.new(1, -8, 0, 20), Position = UDim2.fromOffset(4, 6), ZIndex = 3, Parent = card })
	local iconHolder = Icons.New("Gift", { Name = "Icon", Size = UDim2.fromOffset(50, 50), Position = UDim2.new(0.5, 0, 0, 54), ZIndex = 3, Parent = card })
	local text = UI.Text({
		Name = "Text",
		Text = "",
		TextSize = 15,
		Scaled = true,
		MinTextSize = 9,
		Size = UDim2.new(1, -10, 0, 34),
		Position = UDim2.fromOffset(5, 82),
		ZIndex = 3,
		Parent = card,
	})
	local setStatus = statusPill(card)
	local entry = {
		Card = card,
		Header = headerLabel,
		Icon = iconHolder,
		Text = text,
		SetStatus = setStatus,
		Outline = card:FindFirstChild("Outline"),
		Pet = nil,
		PetId = nil,
	}
	-- Shows the reward's icon, or a turning-free picture of the pet for pet rewards
	function entry.SetReward(reward)
		if reward.Kind == "Pet" and reward.Pet then
			iconHolder.Visible = false
			if entry.PetId ~= reward.Pet then
				if entry.Pet then
					entry.Pet.Destroy()
				end
				entry.Pet = Viewport.Pet(reward.Pet, false, {
					Size = UDim2.fromOffset(62, 62),
					Position = UDim2.new(0.5, 0, 0, 52),
					AnchorPoint = Vector2.new(0.5, 0.5),
					ZIndex = 3,
					Parent = card,
				})
				entry.PetId = reward.Pet
			end
		else
			iconHolder.Visible = true
			Icons.Set(iconHolder, rewardIcon(reward))
			if entry.Pet then
				entry.Pet.Destroy()
				entry.Pet = nil
				entry.PetId = nil
			end
		end
	end
	return entry
end

-- Card colours by state: body fill and outline
local function paintCard(entry, kind: string, pulse: number?)
	local body, outline, thickness = Theme.Cloud, Theme.Haze, 2
	if kind == "Claimed" then
		body, outline = SETS.Leaf.Tint, SETS.Leaf.Tint2
	elseif kind == "Ready" then
		body, outline, thickness = SETS.Bolt.Tint, SETS.Bolt.Bottom, 3 + (pulse or 0)
	elseif kind == "Next" then
		outline, thickness = SETS.Sky.Top, 3
	elseif kind == "Locked" then
		body = Theme.Mist
	end
	entry.Card.BackgroundColor3 = body
	entry.Outline.Color = outline
	entry.Outline.Thickness = thickness
	entry.Text.TextColor3 = if kind == "Locked" then Theme.InkSoft else INK
end

local function subtitle(parent: Instance, text: string)
	return UI.Text({
		Name = "Subtitle",
		Text = text,
		Font = Theme.BodyFont,
		TextSize = 14,
		Scaled = true,
		MinTextSize = 9,
		Color = Theme.InkSoft,
		Size = UDim2.new(1, 0, 0, 18),
		Parent = parent,
	})
end

function Rewards.Build()
	local window = UI.Window({
		Name = "Rewards",
		Title = "Rewards",
		Icon = "🎁",
		Size = UDim2.fromOffset(680, 476),
		Padding = { 20, 16, 18 },
	})
	local content = window.Content
	local pages = {}

	local function page(key: string)
		local pageFrame = frame({
			Name = key,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -58),
			Position = UDim2.fromOffset(0, 58),
			Visible = false,
			Parent = content,
		})
		pages[key] = pageFrame
		return pageFrame
	end

	---------------------------------------------------------------------
	-- Daily
	---------------------------------------------------------------------
	local dailyPage = page("Daily")
	subtitle(dailyPage, "Come back every day! Day 7 gives an exclusive pet (or a Volt vault once you own it).")
	local dailyGrid = frame({
		Name = "Days",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 160),
		Position = UDim2.fromOffset(0, 30),
		Parent = dailyPage,
		UI.Grid(UDim2.fromOffset(84, 156), UDim2.fromOffset(8, 8)),
	})
	local dailyCards = {}
	for day in RewardsConfig.Daily do
		dailyCards[day] = rewardCard(dailyGrid, day, "Day " .. day)
	end
	local dailyTimer = UI.Text({
		Name = "Timer",
		Text = "",
		TextSize = 20,
		Color = Theme.InkSoft,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 202),
		Parent = dailyPage,
	})
	local claimButton = UI.Button({
		Name = "Claim",
		Text = "Claim Reward",
		Icon = "Gift",
		Color = "Leaf",
		TextSize = 26,
		Size = UDim2.fromOffset(300, 62),
		Position = UDim2.new(0.5, 0, 0, 236),
		AnchorPoint = Vector2.new(0.5, 0),
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
	subtitle(giftsPage, "Keep playing to unlock free gifts! They reset every time you join.")
	local giftGrid = frame({
		Name = "Gifts",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -30),
		Position = UDim2.fromOffset(0, 30),
		Parent = giftsPage,
		UI.Grid(UDim2.fromOffset(152, 142), UDim2.fromOffset(10, 10)),
	})
	local giftCards = {}
	for index, gift in RewardsConfig.Gifts do
		local card = rewardCard(giftGrid, index, "Gift " .. index)
		card.Text.Size = UDim2.new(1, -10, 0, 18)
		card.Text.Position = UDim2.fromOffset(5, 84)
		local button = UI.Create("TextButton", {
			Name = "Hit",
			BackgroundTransparency = 1,
			Text = "",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
			Parent = card.Card,
		})
		UI.Bounce(button, 1.04, 0.96)
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
	local codeTitle = frame({
		Name = "Heading",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 56),
		Position = UDim2.fromOffset(0, 14),
		Parent = codesPage,
		UI.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	Icons.New("Codes", { Name = "Icon", Size = UDim2.fromOffset(56, 56), LayoutOrder = 1, Parent = codeTitle })
	local headingText = UI.Text({ Name = "Text", Text = "Redeem a code", TextSize = 30, Size = UDim2.fromOffset(0, 40), LayoutOrder = 2, Parent = codeTitle })
	headingText.AutomaticSize = Enum.AutomaticSize.X

	-- Text field: a white pill with the Ink outline, like the capsules
	local field = frame({
		Name = "Field",
		BackgroundColor3 = Theme.Cloud,
		Size = UDim2.fromOffset(372, 56),
		Position = UDim2.new(0.5, -82, 0, 90),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = codesPage,
		UI.Corner(16),
		UI.Gradient(Theme.Mist, Theme.Cloud),
		UI.Stroke(3, INK),
	})
	local box = UI.Create("TextBox", {
		Name = "CodeBox",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -28, 1, 0),
		Position = UDim2.fromOffset(14, 1),
		Font = Theme.Font,
		PlaceholderText = "Enter code here...",
		PlaceholderColor3 = Theme.InkSoft,
		Text = "",
		TextColor3 = INK,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Parent = field,
	})
	local codeStatus = UI.Text({
		Name = "Status",
		Text = "",
		TextSize = 19,
		Scaled = true,
		MinTextSize = 10,
		Size = UDim2.new(1, -40, 0, 26),
		Position = UDim2.fromOffset(20, 164),
		Parent = codesPage,
	})
	UI.Button({
		Name = "Redeem",
		Text = "Redeem",
		Color = "Leaf",
		TextSize = 24,
		Size = UDim2.fromOffset(150, 56),
		Position = UDim2.new(0.5, 194, 0, 90),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = codesPage,
		OnClick = function()
			if box.Text == "" then
				return
			end
			local result = Remotes.RedeemCode:InvokeServer(box.Text)
			if result and result.Ok then
				codeStatus.Text = "Redeemed: " .. string.gsub(result.Text or "", "\n", " ")
				codeStatus.TextColor3 = Theme.Up
				box.Text = ""
				Registry.SoundController.Play("Success")
				Registry.EffectsController.Confetti(60)
			else
				codeStatus.Text = (result and result.Error or "Something went wrong.")
				codeStatus.TextColor3 = SETS.Coral.Lip
				Registry.SoundController.Play("Error")
			end
		end,
	})
	local note = frame({
		Name = "Note",
		BackgroundColor3 = SETS.Sky.Tint,
		Size = UDim2.new(1, -120, 0, 64),
		Position = UDim2.new(0.5, 0, 0, 206),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = codesPage,
		UI.Corner(16),
		UI.Stroke(2, SETS.Sky.Tint2),
	})
	Icons.New("Star", { Name = "Icon", Size = UDim2.fromOffset(36, 36), Position = UDim2.new(0, 14, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = note })
	UI.Text({
		Name = "Text",
		Text = "Codes are released with updates and milestones. Like the game and join the group so you never miss one!",
		Font = Theme.BodyFont,
		TextSize = 14,
		Scaled = true,
		MinTextSize = 9,
		Wrapped = true,
		Color = Theme.InkSoft,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -76, 1, -14),
		Position = UDim2.new(0, 60, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = note,
	})

	local tabs = UI.Tabs({
		Tabs = {
			{ Key = "Daily", Text = "Daily" },
			{ Key = "Gifts", Text = "Gifts" },
			{ Key = "Codes", Text = "Codes" },
		},
		TabWidth = 132,
		Size = UDim2.new(0, 0, 0, 46),
		Parent = content,
		OnSelect = function(key)
			for pageKey, pageFrame in pages do
				pageFrame.Visible = pageKey == key
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

		local pulse = math.sin(os.clock() * 6) + 1
		for day, card in dailyCards do
			local reward = RewardsConfig.Daily[day]
			card.Text.Text = rewardText(reward, data)
			card.SetReward(actualReward(reward, data))
			local kind
			if day < nextDay then
				kind = "Claimed"
				card.SetStatus(kind, "Claimed")
			elseif day == nextDay then
				kind = if ready then "Ready" else "Next"
				card.SetStatus(kind, if ready then "READY!" else "Next")
			else
				kind = "Locked"
				card.SetStatus(kind)
			end
			paintCard(card, kind, pulse)
		end
		if ready then
			dailyTimer.Text = "Your Day " .. nextDay .. " reward is ready!"
			dailyTimer.TextColor3 = INK
			UI.SetButtonColor(claimButton, "Leaf")
			UI.SetButtonText(claimButton, "Claim Reward")
			UI.SetButtonIcon(claimButton, "Gift")
		else
			dailyTimer.Text = "Next reward in " .. Format.Time(remaining)
			dailyTimer.TextColor3 = Theme.InkSoft
			UI.SetButtonColor(claimButton, "Off")
			UI.SetButtonText(claimButton, "Come Back Later")
			UI.SetButtonIcon(claimButton, nil)
		end

		for index, card in giftCards do
			local gift = RewardsConfig.Gifts[index]
			card.Text.Text = string.gsub(rewardText(gift, data), "\n", " ")
			card.SetReward(gift)
			if data.GiftsClaimed[tostring(index)] then
				card.SetStatus("Claimed", "Opened")
				paintCard(card, "Claimed")
			elseif readyGifts[index] then
				card.SetStatus("Ready", "TAP TO OPEN!")
				paintCard(card, "Ready", pulse)
			else
				card.SetStatus("Wait", Format.Time(gift.Time - elapsed))
				paintCard(card, "Wait")
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
