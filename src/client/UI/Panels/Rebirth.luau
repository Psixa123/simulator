--!nonstrict
-- Climate Shift panel (the rebirth system): shows the cost, what resets, the permanent bonus
-- and the gear looks your Climate Shifts unlock for the Storm Tank and Storm Vacuum.

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
local Confirm = require(script.Parent.Parent.Overlays.Confirm)

local Rebirth = {}

local WHITE = Color3.new(1, 1, 1)

local function listCard(parent: Instance, title: string, color: Color3, lines: { string }, position: UDim2)
	local card = UI.Card({
		Size = UDim2.new(0.5, -6, 0, 112),
		Position = position,
		Parent = parent,
	})
	UI.Label({
		Text = title,
		TextColor3 = color,
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.fromOffset(10, 8),
		MaxTextSize = 20,
		Parent = card,
	})
	UI.Label({
		Text = table.concat(lines, "\n"),
		Font = Theme.BodyFont,
		TextColor3 = Theme.Colors.SubText,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -20, 1, -40),
		Position = UDim2.fromOffset(10, 34),
		MaxTextSize = 20, -- readable on phones, shrinks only if a line wouldn't fit
		Stroke = 1.5,
		Parent = card,
	})
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
	local frame = UI.Create("Frame", {
		Name = "Swatch",
		BackgroundColor3 = WHITE,
		Size = UDim2.fromOffset(64, 64),
		Position = position,
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = parent,
		UI.Corner(16),
		UI.Stroke(3),
	})
	local shell = UI.Gradient(WHITE, WHITE, 0)
	shell.Name = "Shell"
	shell.Parent = frame
	local glow = UI.Create("Frame", {
		Name = "Glow",
		BackgroundColor3 = WHITE,
		Size = UDim2.fromScale(0.42, 0.42),
		Position = UDim2.fromScale(0.5, 0.46),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = frame,
		UI.Round(),
		UI.Stroke(2.5),
	})
	local trail = UI.Create("Frame", {
		Name = "Trail",
		BackgroundColor3 = WHITE,
		Size = UDim2.new(1, -16, 0, 7),
		Position = UDim2.new(0.5, 0, 1, -5),
		AnchorPoint = Vector2.new(0.5, 1),
		Visible = false,
		Parent = frame,
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
	return frame, paint
end

-- One half of the looks card: swatch + name + a line underneath
local function lookSlot(parent: Instance, x: UDim)
	local frame, paint = swatch(parent, UDim2.new(x.Scale, x.Offset + 12, 0, 78))
	local name = UI.Label({
		Name = "LookName",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.5, -104, 0, 26),
		Position = UDim2.new(x.Scale, x.Offset + 86, 0, 48),
		MaxTextSize = 22,
		Parent = parent,
	})
	local info = UI.Label({
		Name = "LookInfo",
		Text = "",
		Font = Theme.BodyFont,
		TextColor3 = Theme.Colors.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.5, -104, 0, 22),
		Position = UDim2.new(x.Scale, x.Offset + 86, 0, 80),
		MaxTextSize = 17,
		Stroke = 1.5,
		Parent = parent,
	})
	return { Swatch = frame, Paint = paint, Name = name, Info = info }
end

function Rebirth.Build()
	local window = UI.Window({
		Name = "Rebirth",
		Title = "Climate Shift",
		Icon = "🌀",
		Color = "Purple",
		Size = UDim2.fromOffset(680, 570),
	})
	local content = window.Content

	local hero = UI.Card({
		Name = "Hero",
		Size = UDim2.new(1, 0, 0, 100),
		Top = Color3.fromRGB(92, 62, 170),
		Bottom = Color3.fromRGB(52, 34, 110),
		Parent = content,
	})
	UI.Icon({
		Text = "🌀",
		Color = Color3.fromRGB(190, 150, 255),
		Size = UDim2.fromOffset(74, 74),
		Position = UDim2.new(0, 14, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = hero,
	})
	local countLabel = UI.Label({
		Text = "Climate Shifts: 0",
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -120, 0, 30),
		Position = UDim2.fromOffset(104, 12),
		MaxTextSize = 26,
		Parent = hero,
	})
	local bonusLabel = UI.Label({
		Text = "",
		TextColor3 = Theme.Colors.Volts,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -120, 0, 38),
		Position = UDim2.fromOffset(104, 48),
		MaxTextSize = 32,
		Parent = hero,
	})

	local progress = UI.ProgressBar({
		Name = "Cost",
		Color = "Purple",
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 110),
		MaxTextSize = 20,
		Parent = content,
	})

	listCard(content, "❌ You lose", Theme.Colors.Danger, {
		"⚡ All your Volts",
		"💨 Vacuum Power levels",
		"🛢️ Storm Tank levels",
	}, UDim2.fromOffset(0, 154))
	listCard(content, "✅ You keep", Theme.Colors.Success, {
		"🐾 Pets and 🗺️ zones",
		"📡 Range and 👟 Boots",
		"🎟️ Gamepasses and boosts",
	}, UDim2.new(0.5, 6, 0, 154))

	-- Gear looks: what you wear now and what the next Climate Shifts unlock
	local looks = UI.Card({
		Name = "Looks",
		Size = UDim2.new(1, 0, 0, 124),
		Position = UDim2.fromOffset(0, 276),
		Parent = content,
	})
	UI.Label({
		Text = "🎨 Gear Looks",
		TextColor3 = Color3.fromRGB(210, 170, 255),
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.5, -12, 0, 24),
		Position = UDim2.fromOffset(12, 8),
		MaxTextSize = 20,
		Parent = looks,
	})
	local looksCount = UI.Label({
		Text = "",
		Font = Theme.BodyFont,
		TextColor3 = Theme.Colors.SubText,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(0.5, -12, 0, 20),
		Position = UDim2.new(0.5, 0, 0, 10),
		MaxTextSize = 16,
		Stroke = 1.5,
		Parent = looks,
	})
	UI.Label({
		Text = "➜",
		TextColor3 = Theme.Colors.SubText,
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(0.5, 0, 0, 78),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 24,
		Parent = looks,
	})
	local currentSlot = lookSlot(looks, UDim.new(0, 0))
	local nextSlot = lookSlot(looks, UDim.new(0.5, 8))

	local button
	button = UI.Button({
		Name = "Rebirth",
		Text = "CLIMATE SHIFT",
		Color = "Purple",
		Size = UDim2.fromOffset(320, 62),
		Position = UDim2.new(0.5, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		MaxTextSize = 28,
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
		currentSlot.Name.Text = current.Icon .. " " .. current.Name
		currentSlot.Info.Text = "✅ Wearing now"
		currentSlot.Info.TextColor3 = Theme.Colors.Success
		looksCount.Text = string.format("%d / %d unlocked", ClimateShift.UnlockedCount(shifts), #GameConfig.Rebirth.Cosmetics)

		local nextLook = ClimateShift.NextCosmetic(shifts)
		nextSlot.Swatch.Visible = nextLook ~= nil
		if nextLook then
			local soon = nextLook.Shifts == shifts + 1
			nextSlot.Paint(nextLook)
			nextSlot.Name.Text = nextLook.Icon .. " " .. nextLook.Name
			nextSlot.Info.Text = if soon then "🔓 Next Climate Shift!" else "🔒 At " .. nextLook.Shifts .. " Climate Shifts"
			nextSlot.Info.TextColor3 = if soon then Theme.Colors.Volts else Theme.Colors.SubText
		else
			nextSlot.Name.Text = "👑 Every look unlocked!"
			nextSlot.Info.Text = "You're a true climate master"
			nextSlot.Info.TextColor3 = Theme.Colors.Volts
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
		bonusLabel.Text = string.format(
			"Volts %s  ➜  %s",
			Format.Multiplier(Formulas.RebirthMultiplier(rebirths)),
			Format.Multiplier(Formulas.RebirthMultiplier(rebirths + 1))
		)
		progress.Set(data.Volts / cost, "⚡ " .. Format.Number(data.Volts) .. " / " .. Format.Number(cost))
		local affordable = data.Volts >= cost
		UI.SetButtonColor(button, if affordable then "Purple" else "Gray")
		UI.SetButtonText(button, if affordable then "CLIMATE SHIFT" else "Need ⚡ " .. Format.Number(cost))
		refreshLooks(rebirths)
	end

	Registry.DataController.ObserveMany({ "Volts", "Rebirths" }, refresh)

	return { Window = window, OnOpen = refresh }
end

return Rebirth
