--!nonstrict
-- Climate Shift panel (the rebirth system): shows the cost, what resets, the permanent bonus
-- and the gear looks your Climate Shifts unlock for the Storm Tank and Storm Vacuum.
-- Sky Lab look: a Storm-tinted hero card with the swirl badge and the Volts bonus going up, the cost
-- as a glass progress bar, Coral "lose" and Leaf "keep" cards, the gear looks and a Storm candy button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Formulas = require(Shared.Formulas)
local ClimateShift = require(Shared.ClimateShift)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI)
local Theme = require(script.Parent.Parent.Theme)
local Icons = require(script.Parent.Parent.Icons)
local Confirm = require(script.Parent.Parent.Overlays.Confirm)

local Rebirth = {}

local INK = Theme.Ink
local WHITE = Color3.new(1, 1, 1)
local SETS = Theme.Sets

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

local function autoText(props)
	local label = UI.Text(props)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, props.Height or props.TextSize or 20)
	return label
end

-- Chunky green "goes up to" arrow (shaft + two head bars over a darker edge), `size` px wide
local function arrow(parent: Instance, order: number, size: number)
	local k = size / 18
	local holder = frame({ Name = "Arrow", BackgroundTransparency = 1, Size = UDim2.fromOffset(18 * k, 16 * k), LayoutOrder = order, Parent = parent })
	local leaf = SETS.Leaf
	local bars = { { 7.5, 8, 13, 0 }, { 12.6, 4.9, 8.6, 45 }, { 12.6, 11.1, 8.6, -45 } }
	for layer, spec in { { leaf.Stroke, 7.5, 1 }, { Color3.fromHex("5FD24E"), 3.6, 2 } } do
		for _, bar in bars do
			frame({
				Name = if layer == 1 then "Edge" else "Bar",
				BackgroundColor3 = spec[1],
				Size = UDim2.fromOffset((bar[3] + spec[2] - 3.6) * k, spec[2] * k),
				Position = UDim2.fromOffset(bar[1] * k, bar[2] * k),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Rotation = bar[4],
				ZIndex = spec[3],
				Parent = holder,
				UI.Round(),
			})
		end
	end
	return holder
end

-- "You lose" / "You keep" card: a tinted card with a header icon and a list of icon lines
local function listCard(parent: Instance, name: string, setName: string, headerIcon: string, title: string, lines, position: UDim2)
	local set = Theme.Set(setName)
	local card = frame({
		Name = name,
		BackgroundColor3 = set.Tint,
		Size = UDim2.new(0.5, -6, 0, 112),
		Position = position,
		Parent = parent,
		UI.Corner(18),
		UI.Stroke(2, set.Tint2),
	})
	Icons.New(headerIcon, { Name = "Icon", Size = UDim2.fromOffset(26, 26), Position = UDim2.fromOffset(12, 8), AnchorPoint = Vector2.zero, Parent = card })
	UI.Text({ Name = "Title", Text = title, TextSize = 20, Color = set.Lip, X = Enum.TextXAlignment.Left, Size = UDim2.new(1, -56, 0, 26), Position = UDim2.fromOffset(44, 8), Parent = card })
	local list = frame({
		Name = "Lines",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 0, 70),
		Position = UDim2.fromOffset(14, 38),
		Parent = card,
		UI.List(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	})
	for index, line in lines do
		local row = frame({
			Name = "Line" .. index,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 22),
			LayoutOrder = index,
			Parent = list,
		})
		Icons.New(line[1], { Name = "Icon", Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(0, 0), AnchorPoint = Vector2.zero, Parent = row })
		UI.Text({
			Name = "Text",
			Text = line[2],
			Font = Theme.BodyFont,
			TextSize = 14,
			Scaled = true,
			MinTextSize = 9,
			X = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -30, 1, 0),
			Position = UDim2.fromOffset(30, 1),
			Parent = row,
		})
	end
	return card
end

-- Tank colour | vacuum colour split down the middle
local function splitColors(left: Color3, right: Color3): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, left),
		ColorSequenceKeypoint.new(0.5, left),
		ColorSequenceKeypoint.new(0.501, right),
		ColorSequenceKeypoint.new(1, right),
	})
end

-- Colour swatch for a gear look: shell colours, a glowing core and (if any) the trail colour.
-- Returns the frame and a function that paints it with a look.
local function swatch(parent: Instance, position: UDim2)
	local frameObject = frame({
		Name = "Swatch",
		Size = UDim2.fromOffset(62, 62),
		Position = position,
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = parent,
		UI.Corner(16),
		UI.Stroke(3, INK),
	})
	local shell = UI.Gradient(WHITE, WHITE, 0)
	shell.Name = "Shell"
	shell.Parent = frameObject
	frame({ Name = "Shine", BackgroundTransparency = 0.6, Size = UDim2.new(1, -16, 0, 9), Position = UDim2.fromOffset(8, 4), ZIndex = 2, Parent = frameObject, UI.Round() })
	local glow = frame({
		Name = "Glow",
		Size = UDim2.fromScale(0.42, 0.42),
		Position = UDim2.fromScale(0.5, 0.48),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 2,
		Parent = frameObject,
		UI.Round(),
		UI.Stroke(2.5, INK),
	})
	local trail = frame({
		Name = "Trail",
		Size = UDim2.new(1, -16, 0, 7),
		Position = UDim2.new(0.5, 0, 1, -5),
		AnchorPoint = Vector2.new(0.5, 1),
		Visible = false,
		ZIndex = 2,
		Parent = frameObject,
		UI.Round(),
	})
	local trailGradient = UI.Gradient(WHITE, WHITE, 0)
	trailGradient.Parent = trail

	local function paint(look)
		local tank = look.Tank or WHITE
		shell.Color = splitColors(tank, look.Vacuum or tank)
		glow.BackgroundColor3 = look.Glow or WHITE
		trail.Visible = look.Trail ~= nil
		if look.Trail then
			trailGradient.Color = if typeof(look.Trail) == "ColorSequence" then look.Trail else ColorSequence.new(look.Trail)
		end
	end
	return frameObject, paint
end

-- One half of the looks card: swatch + name + a line underneath
local function lookSlot(parent: Instance, x: UDim)
	local frameObject, paint = swatch(parent, UDim2.new(x.Scale, x.Offset + 14, 0, 72))
	local name = UI.Text({
		Name = "LookName",
		Text = "",
		TextSize = 20,
		Scaled = true,
		MinTextSize = 11,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.5, -110, 0, 24),
		Position = UDim2.new(x.Scale, x.Offset + 88, 0, 46),
		Parent = parent,
	})
	local info = UI.Text({
		Name = "LookInfo",
		Text = "",
		Font = Theme.BodyFont,
		TextSize = 14,
		Scaled = true,
		MinTextSize = 9,
		Color = Theme.InkSoft,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.5, -110, 0, 20),
		Position = UDim2.new(x.Scale, x.Offset + 88, 0, 74),
		Parent = parent,
	})
	return { Swatch = frameObject, Paint = paint, Name = name, Info = info }
end

function Rebirth.Build()
	local window = UI.Window({
		Name = "Rebirth",
		Title = "Climate Shift",
		Icon = "🌀",
		Size = UDim2.fromOffset(680, 560),
		Padding = { 20, 16, 18 },
	})
	local content = window.Content

	-- Hero: swirl badge, the count and the Volts bonus going up
	local hero = frame({
		Name = "Hero",
		Size = UDim2.new(1, -4, 0, 94),
		Position = UDim2.fromOffset(2, 2),
		Parent = content,
		UI.Corner(18),
		UI.Gradient(SETS.Storm.Tint, SETS.Storm.Tint2),
		UI.Stroke(2, SETS.Storm.Tint2:Lerp(SETS.Storm.Top, 0.35)),
	})
	UI.Orb({
		Name = "Badge",
		Size = 76,
		Color = "Storm",
		RingWidth = 4,
		Icon = "ClimateShift",
		IconSize = 52,
		Position = UDim2.new(0, 12, 0.5, -2),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 2,
		Parent = hero,
	})
	local countLabel = UI.Text({
		Name = "Count",
		Text = "Climate Shifts: 0",
		TextSize = 22,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.5, -110, 0, 26),
		Position = UDim2.fromOffset(104, 14),
		Parent = hero,
	})
	UI.Text({
		Name = "Hint",
		Text = "Reset for a permanent Volts bonus",
		Font = Theme.BodyFont,
		TextSize = 13,
		Scaled = true,
		MinTextSize = 9,
		Color = Theme.InkSoft,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.5, -110, 0, 16),
		Position = UDim2.fromOffset(104, 44),
		Parent = hero,
	})
	-- Volts bonus box: "VOLTS BONUS", now -> after the next Climate Shift
	local bonusBox = frame({
		Name = "Bonus",
		BackgroundColor3 = Theme.Cloud,
		Size = UDim2.fromOffset(250, 70),
		Position = UDim2.new(1, -12, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Parent = hero,
		UI.Corner(14),
		UI.Stroke(2, SETS.Storm.Tint2),
	})
	UI.Text({
		Name = "Caption",
		Text = "VOLTS BONUS",
		Font = Theme.BodyFont,
		TextSize = 11,
		Color = Theme.InkSoft,
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.fromOffset(0, 8),
		Parent = bonusBox,
	})
	local values = frame({
		Name = "Values",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 0, 36),
		Position = UDim2.fromOffset(4, 26),
		Parent = bonusBox,
		UI.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	local nowLabel = autoText({ Name = "Now", Text = "", TextSize = 32, Height = 36, Color = Theme.InkSoft, LayoutOrder = 1, Parent = values })
	arrow(values, 2, 24)
	local nextLabel = autoText({ Name = "Next", Text = "", TextSize = 32, Height = 36, Color = Theme.Up, LayoutOrder = 3, Parent = values })

	-- Cost: how far your Volts are towards the next Climate Shift
	local progress = UI.ProgressBar({
		Name = "Cost",
		Color = "Storm",
		Size = UDim2.new(1, -24, 0, 36),
		Position = UDim2.fromOffset(20, 108),
		MaxTextSize = 20,
		Parent = content,
	})
	Icons.New("Volts", { Name = "Icon", Size = UDim2.fromOffset(46, 46), Position = UDim2.new(0, -20, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 5, Parent = progress.Frame })

	listCard(content, "Lose", "Coral", "Close", "You lose", {
		{ "Volts", "All your Volts" },
		{ "Power", "Vacuum Power levels" },
		{ "Tank", "Storm Tank levels" },
	}, UDim2.fromOffset(2, 158))
	listCard(content, "Keep", "Leaf", "Check", "You keep", {
		{ "Pets", "Pets and zones" },
		{ "Range", "Range and Storm Boots" },
		{ "Shop", "Gamepasses and boosts" },
	}, UDim2.new(0.5, 4, 0, 158))

	-- Gear looks: what you wear now and what the next Climate Shifts unlock
	local looks = UI.CloudCard({
		Name = "Looks",
		Size = UDim2.new(1, -4, 0, 108),
		Position = UDim2.fromOffset(2, 284),
		Parent = content,
	})
	UI.Text({
		Name = "Title",
		Text = "Gear Looks",
		TextSize = 18,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.5, -14, 0, 22),
		Position = UDim2.fromOffset(14, 8),
		Parent = looks,
	})
	local looksCount = UI.Text({
		Name = "Unlocked",
		Text = "",
		Font = Theme.BodyFont,
		TextSize = 13,
		Color = Theme.InkSoft,
		X = Enum.TextXAlignment.Right,
		Size = UDim2.new(0.5, -14, 0, 20),
		Position = UDim2.new(0.5, 0, 0, 9),
		Parent = looks,
	})
	local looksArrow = arrow(looks, 0, 22)
	looksArrow.Position = UDim2.new(0.5, -10, 0, 64)
	local currentSlot = lookSlot(looks, UDim.new(0, 0))
	local nextSlot = lookSlot(looks, UDim.new(0.5, 12))

	local button
	button = UI.Button({
		Name = "Rebirth",
		Text = "Climate Shift",
		Icon = "ClimateShift",
		Color = "Storm",
		TextSize = 28,
		Size = UDim2.fromOffset(330, 62),
		Position = UDim2.new(0.5, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = content,
		OnClick = function()
			local data = Registry.DataController.Data
			if not data then
				return
			end
			local cost = Formulas.RebirthCost(data.Rebirths)
			if data.Volts < cost then
				Registry.InterfaceController.Notify("You need ⚡ " .. Format.Number(cost) .. " Volts for a Climate Shift!", "Error")
				return
			end
			local text = "Your Volts, Vacuum Power and Storm Tank reset.\nYou gain a permanent "
				.. Format.Multiplier(Formulas.RebirthMultiplier(data.Rebirths + 1))
				.. " Volts bonus!"
			local unlock = ClimateShift.UnlockedAt(data.Rebirths + 1)
			if unlock then
				text ..= "\n🎨 Unlocks the " .. unlock.Icon .. " " .. unlock.Name .. " gear look!"
			end
			Confirm.Show({
				Title = "Climate Shift now?",
				Text = text,
				ConfirmText = "Climate Shift!",
				Color = "Purple",
				OnConfirm = function()
					local result = Remotes.Rebirth:InvokeServer()
					if result and result.Ok then
						Registry.InterfaceController.ClosePanel()
					elseif result then
						Registry.InterfaceController.Notify(result.Error, "Error")
					end
				end,
			})
		end,
	})

	local function refreshLooks(shifts: number)
		local current = ClimateShift.Cosmetic(shifts)
		currentSlot.Paint(current)
		currentSlot.Name.Text = current.Name
		currentSlot.Info.Text = "Wearing now"
		currentSlot.Info.TextColor3 = Theme.Up
		looksCount.Text = string.format("%d / %d unlocked", ClimateShift.UnlockedCount(shifts), #GameConfig.Rebirth.Cosmetics)

		local nextLook = ClimateShift.NextCosmetic(shifts)
		nextSlot.Swatch.Visible = nextLook ~= nil
		looksArrow.Visible = nextLook ~= nil
		if nextLook then
			local soon = nextLook.Shifts == shifts + 1
			nextSlot.Paint(nextLook)
			nextSlot.Name.Text = nextLook.Name
			nextSlot.Info.Text = if soon then "Unlocks next Climate Shift!" else "At " .. nextLook.Shifts .. " Climate Shifts"
			nextSlot.Info.TextColor3 = if soon then SETS.Storm.Bottom else Theme.InkSoft
		else
			nextSlot.Name.Text = "Every look unlocked!"
			nextSlot.Info.Text = "You're a true climate master"
			nextSlot.Info.TextColor3 = SETS.Storm.Bottom
		end
	end

	local function refresh()
		local data = Registry.DataController.Data
		if not data then
			return
		end
		local rebirths = data.Rebirths or 0
		local cost = Formulas.RebirthCost(rebirths)
		countLabel.Text = "Climate Shifts: " .. Format.Commas(rebirths)
		nowLabel.Text = Format.Multiplier(Formulas.RebirthMultiplier(rebirths))
		nextLabel.Text = Format.Multiplier(Formulas.RebirthMultiplier(rebirths + 1))
		progress.Set(data.Volts / cost, Format.Number(data.Volts) .. " / " .. Format.Number(cost) .. " Volts")
		local affordable = data.Volts >= cost
		UI.SetButtonColor(button, if affordable then "Storm" else "Off")
		UI.SetButtonText(button, if affordable then "Climate Shift" else "Need " .. Format.Number(cost))
		UI.SetButtonIcon(button, if affordable then "ClimateShift" else "Lock")
		refreshLooks(rebirths)
	end

	Registry.DataController.ObserveMany({ "Volts", "Rebirths" }, refresh)

	return { Window = window, OnOpen = refresh }
end

return Rebirth
