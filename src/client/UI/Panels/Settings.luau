--!nonstrict
-- Settings panel: music, sound effects, other players' pets, performance mode, auto catch, trade requests.
-- Sky Lab look: one white row per setting with its icon in a tinted well and a toggle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI)
local Theme = require(script.Parent.Parent.Theme)
local Icons = require(script.Parent.Parent.Icons)

local Settings = {}

-- Per setting: the well's colour set and the 3D icon (Icons.luau key, else the setting's emoji)
local STYLE = {
	Music = { Set = "Storm" },
	Sfx = { Set = "Sky" },
	OtherPets = { Set = "Pink", Icon = "Pets" },
	LowGraphics = { Set = "Rain", Icon = "Settings" },
	AutoCatch = { Set = "Leaf", Icon = "Power" },
	AllowTrades = { Set = "Sky", Icon = "Trade" },
}

function Settings.Build()
	local window = UI.Window({
		Name = "Settings",
		Title = "Settings",
		Icon = "⚙️",
		Size = UDim2.fromOffset(580, 582),
		Padding = { 20, 16, 18 },
	})

	local list = UI.Create("Frame", {
		Name = "List",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -26),
		Parent = window.Content,
		UI.List(Enum.FillDirection.Vertical, 8),
	})

	local toggles = {}
	local locks = {}
	for index, info in GameConfig.SettingsInfo do
		local style = STYLE[info.Key] or { Set = "Sky" }
		local set = Theme.Set(style.Set)
		local row = UI.Create("Frame", {
			Name = info.Key,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 70),
			LayoutOrder = index,
			Parent = list,
		})
		local card = UI.CloudCard({ Name = "Card", Size = UDim2.new(1, -4, 1, -4), Position = UDim2.fromOffset(2, 2), Parent = row })
		local well = UI.Create("Frame", {
			Name = "Well",
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.fromOffset(52, 52),
			Position = UDim2.new(0, 7, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Parent = card,
			UI.Corner(14),
			UI.Gradient(set.Tint, set.Tint2),
		})
		Icons.New(style.Icon or info.Icon, { Name = "Icon", Size = UDim2.fromOffset(42, 42), Parent = well })
		UI.Text({
			Name = "Title",
			Text = info.Name,
			TextSize = 21,
			Scaled = true,
			MinTextSize = 12,
			X = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -180, 0, 24),
			Position = UDim2.fromOffset(72, 9),
			Parent = card,
		})
		UI.Text({
			Name = "Description",
			Text = info.Description,
			Font = Theme.BodyFont,
			TextSize = 13,
			Scaled = true,
			MinTextSize = 9,
			Color = Theme.InkSoft,
			X = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -180, 0, 18),
			Position = UDim2.fromOffset(72, 36),
			Parent = card,
		})
		toggles[info.Key] = UI.Toggle({
			Name = "Toggle",
			Size = UDim2.fromOffset(90, 40),
			Position = UDim2.new(1, -12, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Parent = card,
			OnChanged = function(value: boolean)
				local data = Registry.DataController.Data
				if info.Key == "AutoCatch" and data and not Formulas.HasPass(data, "AutoCatch") then
					Registry.MonetizationController.PromptPass("AutoCatch")
					return
				end
				Remotes.SetSetting:InvokeServer(info.Key, value)
			end,
		})
		if info.Key == "AutoCatch" then
			-- A padlock next to the toggle while the gamepass isn't owned
			locks[info.Key] = Icons.New("Lock", {
				Name = "Lock",
				Size = UDim2.fromOffset(28, 28),
				Position = UDim2.new(1, -110, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				Visible = false,
				Parent = card,
			})
		end
	end

	UI.Text({
		Name = "Version",
		Text = GameConfig.GameName .. "  •  v" .. GameConfig.Version,
		Font = Theme.BodyFont,
		TextSize = 12,
		Color = Theme.InkSoft,
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 1),
		Parent = window.Content,
	})

	local function refresh()
		local data = Registry.DataController.Data
		if not data then
			return
		end
		for key, toggle in toggles do
			local value = data.Settings[key] == true
			if key == "AutoCatch" and not Formulas.HasPass(data, "AutoCatch") then
				value = false
			end
			toggle.Set(value)
		end
		for key, lock in locks do
			lock.Visible = key == "AutoCatch" and not Formulas.HasPass(data, "AutoCatch")
		end
	end

	Registry.DataController.ObserveMany({ "Settings", "Passes" }, refresh)

	return { Window = window, OnOpen = refresh }
end

return Settings
