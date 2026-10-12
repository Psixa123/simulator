--!nonstrict
-- Rebirth panel: shows the cost, what resets and the permanent bonus.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI)
local Theme = require(script.Parent.Parent.Theme)
local Confirm = require(script.Parent.Parent.Overlays.Confirm)

local Rebirth = {}

local function listCard(parent: Instance, title: string, color: Color3, lines: { string }, position: UDim2)
	local card = UI.Card({
		Size = UDim2.new(0.5, -6, 0, 132),
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
		TextScaled = false,
		TextSize = 16,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -20, 1, -42),
		Position = UDim2.fromOffset(10, 36),
		Stroke = 1.5,
		Parent = card,
	})
end

function Rebirth.Build()
	local window = UI.Window({
		Name = "Rebirth",
		Title = "Rebirth",
		Icon = "🔄",
		Color = "Purple",
		Size = UDim2.fromOffset(600, 500),
	})
	local content = window.Content

	local hero = UI.Card({
		Name = "Hero",
		Size = UDim2.new(1, 0, 0, 110),
		Top = Color3.fromRGB(92, 62, 170),
		Bottom = Color3.fromRGB(52, 34, 110),
		Parent = content,
	})
	UI.Icon({
		Text = "🔄",
		Color = Color3.fromRGB(190, 150, 255),
		Size = UDim2.fromOffset(78, 78),
		Position = UDim2.new(0, 14, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = hero,
	})
	local countLabel = UI.Label({
		Text = "Rebirths: 0",
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -120, 0, 30),
		Position = UDim2.fromOffset(106, 14),
		MaxTextSize = 26,
		Parent = hero,
	})
	local bonusLabel = UI.Label({
		Text = "",
		TextColor3 = Theme.Colors.Volts,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -120, 0, 40),
		Position = UDim2.fromOffset(106, 52),
		MaxTextSize = 32,
		Parent = hero,
	})

	local progress = UI.ProgressBar({
		Name = "Cost",
		Color = "Purple",
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, 122),
		MaxTextSize = 20,
		Parent = content,
	})

	listCard(content, "❌ You lose", Theme.Colors.Danger, {
		"⚡ All your Volts",
		"💨 Vacuum Power levels",
		"🛢️ Storm Tank levels",
	}, UDim2.fromOffset(0, 170))
	listCard(content, "✅ You keep", Theme.Colors.Success, {
		"🐾 Pets and 🗺️ zones",
		"📡 Range and 👟 Boots",
		"🎟️ Gamepasses and boosts",
	}, UDim2.new(0.5, 6, 0, 170))

	local button
	button = UI.Button({
		Name = "Rebirth",
		Text = "REBIRTH",
		Color = "Purple",
		Size = UDim2.fromOffset(300, 62),
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
				Registry.InterfaceController.Notify("You need ⚡ " .. Format.Number(cost) .. " Volts to rebirth!", "Error")
				return
			end
			Confirm.Show({
				Title = "Rebirth now?",
				Text = "Your Volts, Vacuum Power and Storm Tank reset.\nYou gain a permanent "
					.. Format.Multiplier(Formulas.RebirthMultiplier(data.Rebirths + 1))
					.. " Volts bonus!",
				ConfirmText = "Rebirth!",
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

	local function refresh()
		local data = Registry.DataController.Data
		if not data then
			return
		end
		local rebirths = data.Rebirths or 0
		local cost = Formulas.RebirthCost(rebirths)
		countLabel.Text = "Rebirths: " .. rebirths
		bonusLabel.Text = string.format(
			"Volts %s  ➜  %s",
			Format.Multiplier(Formulas.RebirthMultiplier(rebirths)),
			Format.Multiplier(Formulas.RebirthMultiplier(rebirths + 1))
		)
		progress.Set(data.Volts / cost, "⚡ " .. Format.Number(data.Volts) .. " / " .. Format.Number(cost))
		local affordable = data.Volts >= cost
		UI.SetButtonColor(button, if affordable then "Purple" else "Gray")
		UI.SetButtonText(button, if affordable then "REBIRTH" else "Need ⚡ " .. Format.Number(cost))
	end

	Registry.DataController.ObserveMany({ "Volts", "Rebirths" }, refresh)

	return { Window = window, OnOpen = refresh }
end

return Rebirth
