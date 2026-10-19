--!nonstrict
-- Upgrades panel: Vacuum Power, Storm Tank, Vacuum Range and Storm Boots.
-- Laid out like docs/ui_mockup.png: one row per upgrade with its icon in a tinted well, the name and
-- a level chip, ten level pips, a stat box (now -> next) and the MAX and buy candy buttons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI)
local Theme = require(script.Parent.Parent.Theme)
local Icons = require(script.Parent.Parent.Icons)

local Upgrades = {}

local INK = Theme.Ink
local WHITE = Color3.new(1, 1, 1)
local PIPS = 10

-- Per upgrade: the well's colour set, the stat box caption and a unit shown after the next value
local STYLE = {
	Power = { Set = "Bolt", Caption = "Strength" },
	Tank = { Set = "Rain", Caption = "Capacity" },
	Range = { Set = "Storm", Caption = "Reach", Unit = "studs" },
	Speed = { Set = "Leaf", Caption = "Run speed" },
}

-- Row geometry (offset px inside a row's 2 px Haze outline, docs/ui_mockup.html .ucard)
local ROW_HEIGHT = 70
local STAT_X, STAT_WIDTH = 330, 150
local MAX_WIDTH, BUY_WIDTH, BUTTON_HEIGHT = 64, 136, 50

local function buy(upgradeId: string, mode: string)
	local result = Remotes.BuyUpgrade:InvokeServer(upgradeId, mode)
	if result and not result.Ok then
		Registry.InterfaceController.Notify(result.Error, "Error")
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

-- Chunky green "goes up to" arrow: a shaft and two head bars, each a rounded bar over a darker edge
local function arrow(parent: Instance, order: number, z: number)
	local holder = frame({ Name = "Arrow", BackgroundTransparency = 1, Size = UDim2.fromOffset(18, 16), LayoutOrder = order, ZIndex = z, Parent = parent })
	local leaf = Theme.Sets.Leaf
	-- { centre x, centre y, length, rotation }
	local bars = { { 7.5, 8, 13, 0 }, { 12.6, 4.9, 8.6, 45 }, { 12.6, 11.1, 8.6, -45 } }
	for layer, spec in { { leaf.Stroke, 7.5, z }, { Color3.fromHex("5FD24E"), 3.6, z + 1 } } do
		for _, bar in bars do
			frame({
				Name = if layer == 1 then "Edge" else "Bar",
				BackgroundColor3 = spec[1],
				Size = UDim2.fromOffset(bar[3] + spec[2] - 3.6, spec[2]),
				Position = UDim2.fromOffset(bar[1], bar[2]),
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

-- Text that sizes itself to its contents (for the rows of the stat box and the name line)
local function autoText(props)
	local label = UI.Text(props)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, props.Height or props.TextSize or 20)
	return label
end

local function buildRow(list: Instance, index: number, upgradeId: string)
	local def = GameConfig.Upgrades[upgradeId]
	local style = STYLE[upgradeId] or { Set = "Sky", Caption = def.Name }
	local set = Theme.Set(style.Set)

	-- The holder is the row's outer box; the card sits inside it so its outline stays in the box
	local holder = frame({
		Name = upgradeId,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		LayoutOrder = index,
		Parent = list,
	})
	local card = UI.CloudCard({
		Name = "Card",
		Size = UDim2.new(1, -4, 1, -4),
		Position = UDim2.fromOffset(2, 2),
		Parent = holder,
	})

	-- Icon well
	local well = frame({
		Name = "Well",
		Size = UDim2.fromOffset(54, 54),
		Position = UDim2.fromOffset(6, 6),
		ZIndex = 2,
		Parent = card,
		UI.Corner(14),
		UI.Gradient(set.Tint, set.Tint2),
	})
	Icons.New(upgradeId, { Name = "Icon", Size = UDim2.fromOffset(46, 46), ZIndex = 3, Parent = well })

	-- Name + level chip
	local nameLine = frame({
		Name = "NameLine",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(250, 24),
		Position = UDim2.fromOffset(74, 7),
		ZIndex = 2,
		Parent = card,
		UI.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	autoText({ Name = "Title", Text = def.Name, TextSize = 22, Height = 24, LayoutOrder = 1, ZIndex = 2, Parent = nameLine })
	local chip = frame({
		Name = "Level",
		BackgroundColor3 = Theme.Haze,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 22),
		LayoutOrder = 2,
		ZIndex = 2,
		Parent = nameLine,
		UI.Round(),
		UI.Padding(0, 9, 0, 9),
	})
	local levelLabel = autoText({ Name = "Text", Text = "Lv 1", TextSize = 14, Height = 22, Position = UDim2.fromOffset(0, 1), ZIndex = 3, Parent = chip })

	-- Level pips (each one is a tenth of the way to the max level)
	local pipRow = frame({
		Name = "Pips",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(PIPS * 24, 14),
		Position = UDim2.fromOffset(74, 39),
		ZIndex = 2,
		Parent = card,
		UI.List(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	local pips = {}
	for pip = 1, PIPS do
		local slot = frame({
			Name = "Pip" .. pip,
			BackgroundColor3 = Theme.Haze,
			Size = UDim2.fromOffset(20, 14),
			LayoutOrder = pip,
			ZIndex = 2,
			Parent = pipRow,
			UI.Corner(5),
		})
		local on = frame({
			Name = "On",
			Size = UDim2.new(1, -4, 1, -4),
			Position = UDim2.fromOffset(2, 2),
			Visible = false,
			ZIndex = 3,
			Parent = slot,
			UI.Corner(3),
			UI.Gradient(Theme.Sets.Sky.Top, Theme.Sets.Sky.Bottom),
			UI.Stroke(2, INK),
		})
		frame({
			Name = "Shine",
			BackgroundTransparency = 0.45,
			Size = UDim2.new(1, -6, 0, 3),
			Position = UDim2.fromOffset(3, 1),
			ZIndex = 4,
			Parent = on,
			UI.Round(),
		})
		pips[pip] = on
	end

	-- Stat box: caption, "now -> next" (and a unit)
	local stat = frame({
		Name = "Stat",
		BackgroundColor3 = Theme.Mist,
		Size = UDim2.fromOffset(STAT_WIDTH - 4, 54 - 4),
		Position = UDim2.fromOffset(STAT_X + 2, 8),
		ZIndex = 2,
		Parent = card,
		UI.Corner(12),
		UI.Stroke(2, Theme.Haze),
	})
	UI.Text({
		Name = "Caption",
		Text = string.upper(style.Caption),
		Font = Theme.BodyFont,
		TextSize = 10,
		Color = Theme.InkSoft,
		Size = UDim2.new(1, -8, 0, 12),
		Position = UDim2.new(0.5, 0, 0, 4),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 3,
		Parent = stat,
	})
	local values = frame({
		Name = "Values",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -6, 0, 24),
		Position = UDim2.new(0.5, 0, 0, 19),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 3,
		Parent = stat,
		UI.List(Enum.FillDirection.Horizontal, 5, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	local now = autoText({ Name = "Now", Text = "", TextSize = 22, Height = 24, Color = Theme.InkSoft, LayoutOrder = 1, ZIndex = 3, Parent = values })
	local arrowMark = arrow(values, 2, 3)
	local nextValue = autoText({ Name = "Next", Text = "", TextSize = 22, Height = 24, Color = Theme.Up, LayoutOrder = 3, ZIndex = 3, Parent = values })
	local unit = nil
	if style.Unit then
		unit = autoText({
			Name = "Unit",
			Text = style.Unit,
			Font = Theme.BodyFont,
			TextSize = 11,
			Height = 24,
			Color = Theme.InkSoft,
			Y = Enum.TextYAlignment.Bottom,
			LayoutOrder = 4,
			ZIndex = 3,
			Parent = values,
		})
	end

	local maxButton = UI.Button({
		Name = "Max",
		Text = "MAX",
		Color = "Storm",
		TextSize = 18,
		Size = UDim2.fromOffset(MAX_WIDTH, BUTTON_HEIGHT),
		Position = UDim2.new(1, -(152 + MAX_WIDTH), 0, 8),
		ZIndex = 3,
		Parent = card,
		OnClick = function()
			buy(upgradeId, "Max")
		end,
	})
	local buyButton = UI.Button({
		Name = "Buy",
		Text = "",
		Icon = "Volts",
		IconSize = 28,
		Color = "Leaf",
		TextSize = 22,
		Size = UDim2.fromOffset(BUY_WIDTH, BUTTON_HEIGHT),
		Position = UDim2.new(1, -8, 0, 8),
		AnchorPoint = Vector2.new(1, 0), -- grows to the left when maxed
		ZIndex = 3,
		Parent = card,
		OnClick = function()
			buy(upgradeId, "One")
		end,
	})

	return {
		Level = levelLabel,
		Pips = pips,
		Now = now,
		Arrow = arrowMark,
		Next = nextValue,
		Unit = unit,
		Buy = buyButton,
		Max = maxButton,
	}
end

function Upgrades.Build()
	local window = UI.Window({
		Name = "Upgrades",
		Title = "Upgrades",
		Icon = "⬆️",
		Size = UDim2.fromOffset(760, 412),
		Padding = { 23, 18, 18 },
	})

	local list = frame({
		Name = "List",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = window.Content,
		UI.List(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top),
	})

	local rows = {}
	for index, upgradeId in GameConfig.UpgradeOrder do
		rows[upgradeId] = buildRow(list, index, upgradeId)
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

			row.Level.Text = "Lv " .. Format.Commas(level)
			local lit = if level >= def.MaxLevel then PIPS else math.clamp(math.floor(level / def.MaxLevel * PIPS + 0.5), 0, PIPS - 1)
			for pip, on in row.Pips do
				on.Visible = pip <= lit
			end

			local cost = Formulas.UpgradeCost(upgradeId, level)
			row.Now.Text = Format.Number(current)
			if cost then
				row.Now.TextColor3 = Theme.InkSoft
				row.Arrow.Visible = true
				row.Next.Visible = true
				row.Next.Text = Format.Number(def.Value(level + 1))
				local affordable = data.Volts >= cost
				UI.SetButtonText(row.Buy, Format.Number(cost))
				UI.SetButtonIcon(row.Buy, if affordable then "Volts" else "Lock")
				UI.SetButtonColor(row.Buy, if affordable then "Leaf" else "Off")
				UI.SetButtonColor(row.Max, if affordable then "Storm" else "Off")
				row.Max.Visible = true
				row.Buy.Size = UDim2.fromOffset(BUY_WIDTH, BUTTON_HEIGHT)
			else
				-- Maxed: only the value, and a gold MAXED button across both button spots
				row.Now.TextColor3 = INK
				row.Arrow.Visible = false
				row.Next.Visible = false
				UI.SetButtonText(row.Buy, "MAXED")
				UI.SetButtonIcon(row.Buy, nil)
				UI.SetButtonColor(row.Buy, "Bolt")
				row.Max.Visible = false
				row.Buy.Size = UDim2.fromOffset(BUY_WIDTH + 8 + MAX_WIDTH, BUTTON_HEIGHT)
			end
		end
	end

	Registry.DataController.ObserveMany({ "Volts", "Upgrades" }, refresh)

	return { Window = window, OnOpen = refresh }
end

return Upgrades
