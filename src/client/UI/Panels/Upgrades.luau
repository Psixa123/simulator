--!nonstrict
-- Upgrades panel: Vacuum Power, Storm Tank, Vacuum Range and Storm Boots.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI)
local Theme = require(script.Parent.Parent.Theme)

local Upgrades = {}

local ICON_COLORS = {
	Power = Color3.fromRGB(120, 210, 255),
	Tank = Color3.fromRGB(255, 190, 80),
	Range = Color3.fromRGB(170, 130, 255),
	Speed = Color3.fromRGB(110, 230, 140),
}

local function buy(upgradeId: string, mode: string)
	local result = Remotes.BuyUpgrade:InvokeServer(upgradeId, mode)
	if result and not result.Ok then
		Registry.InterfaceController.Notify(result.Error, "Error")
	end
end

function Upgrades.Build()
	local window = UI.Window({
		Name = "Upgrades",
		Title = "Upgrades",
		Icon = "⬆️",
		Color = "Blue",
		Size = UDim2.fromOffset(700, 500),
	})

	local list = UI.Create("Frame", {
		Name = "List",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = window.Content,
		UI.List(Enum.FillDirection.Vertical, 10),
	})

	local rows = {}
	for index, upgradeId in GameConfig.UpgradeOrder do
		local def = GameConfig.Upgrades[upgradeId]
		local card = UI.Card({
			Name = upgradeId,
			Size = UDim2.new(1, -6, 0, 94),
			LayoutOrder = index,
			Parent = list,
		})
		UI.Icon({
			Text = def.Icon,
			Color = ICON_COLORS[upgradeId],
			Size = UDim2.fromOffset(68, 68),
			Position = UDim2.new(0, 12, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Parent = card,
		})
		-- Text column runs up to x 462 and the buttons start at 476, so nothing hides under them
		UI.Label({
			Name = "Title",
			Text = def.Name,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromOffset(370, 26),
			Position = UDim2.fromOffset(92, 8),
			MaxTextSize = 24,
			Parent = card,
		})
		UI.Label({
			Name = "Description",
			Text = def.Description,
			Font = Theme.BodyFont,
			TextColor3 = Theme.Colors.SubText,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromOffset(370, 22),
			Position = UDim2.fromOffset(92, 36),
			MaxTextSize = 17,
			Stroke = 1.5,
			Parent = card,
		})
		local bar = UI.ProgressBar({
			Name = "Level",
			Color = "Blue",
			Size = UDim2.fromOffset(208, 22),
			Position = UDim2.new(0, 92, 1, -10),
			AnchorPoint = Vector2.new(0, 1),
			StrokeThickness = 2.5,
			MaxTextSize = 15,
			Parent = card,
		})
		local value = UI.Label({
			Name = "Value",
			Text = "",
			TextColor3 = ICON_COLORS[upgradeId],
			Size = UDim2.fromOffset(160, 26),
			Position = UDim2.new(0, 308, 1, -8),
			AnchorPoint = Vector2.new(0, 1),
			MaxTextSize = 20,
			Parent = card,
		})
		local buyButton = UI.Button({
			Name = "Buy",
			Text = "",
			Color = "Green",
			Size = UDim2.fromOffset(112, 58),
			Position = UDim2.new(1, -78, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			MaxTextSize = 22,
			Parent = card,
			OnClick = function()
				buy(upgradeId, "One")
			end,
		})
		local maxButton = UI.Button({
			Name = "Max",
			Text = "MAX",
			Color = "Purple",
			Size = UDim2.fromOffset(60, 58),
			Position = UDim2.new(1, -10, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			MaxTextSize = 18,
			Parent = card,
			OnClick = function()
				buy(upgradeId, "Max")
			end,
		})
		rows[upgradeId] = { Bar = bar, Value = value, Buy = buyButton, Max = maxButton }
	end

	local function refresh()
		local data = Registry.DataController.Data
		if not data then
			return
		end
		for upgradeId, row in rows do
			local def = GameConfig.Upgrades[upgradeId]
			local level = data.Upgrades[upgradeId] or 1
			local current = def.Value(level)
			local suffix = def.Suffix or ""
			row.Bar.Set(level / def.MaxLevel, string.format("Level %d / %d", level, def.MaxLevel))

			local cost = Formulas.UpgradeCost(upgradeId, level)
			if cost then
				row.Value.Text = Format.Number(current) .. " ➜ " .. Format.Number(def.Value(level + 1)) .. suffix
				UI.SetButtonText(row.Buy, "⚡ " .. Format.Number(cost))
				local affordable = data.Volts >= cost
				UI.SetButtonColor(row.Buy, if affordable then "Green" else "Gray")
				UI.SetButtonColor(row.Max, if affordable then "Purple" else "Gray")
				row.Max.Visible = true
			else
				row.Value.Text = Format.Number(current) .. suffix
				UI.SetButtonText(row.Buy, "MAXED")
				UI.SetButtonColor(row.Buy, "Yellow")
				row.Max.Visible = false
			end
		end
	end

	Registry.DataController.ObserveMany({ "Volts", "Upgrades" }, refresh)

	return { Window = window, OnOpen = refresh }
end

return Upgrades
