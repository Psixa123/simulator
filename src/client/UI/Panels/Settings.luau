--!nonstrict
-- Settings panel: music, sound effects, other players' pets, performance mode, auto catch.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI)
local Theme = require(script.Parent.Parent.Theme)

local Settings = {}

function Settings.Build()
	local window = UI.Window({
		Name = "Settings",
		Title = "Settings",
		Icon = "⚙️",
		Color = "Dark",
		Size = UDim2.fromOffset(580, 520),
	})

	local list = UI.Create("Frame", {
		Name = "List",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -28),
		Parent = window.Content,
		UI.List(Enum.FillDirection.Vertical, 8),
	})

	local toggles = {}
	for index, info in GameConfig.SettingsInfo do
		local card = UI.Card({
			Name = info.Key,
			Size = UDim2.new(1, -6, 0, 68),
			LayoutOrder = index,
			Parent = list,
		})
		UI.Icon({
			Text = info.Icon,
			Color = Color3.fromRGB(120, 150, 230),
			Size = UDim2.fromOffset(48, 48),
			Position = UDim2.new(0, 10, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Parent = card,
		})
		UI.Label({
			Text = info.Name,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -190, 0, 26),
			Position = UDim2.fromOffset(70, 10),
			MaxTextSize = 22,
			Parent = card,
		})
		UI.Label({
			Text = info.Description,
			Font = Theme.BodyFont,
			TextColor3 = Theme.Colors.SubText,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -190, 0, 18),
			Position = UDim2.fromOffset(70, 38),
			MaxTextSize = 14,
			Stroke = 1.5,
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
	end

	UI.Label({
		Name = "Version",
		Text = GameConfig.GameName .. "  •  v" .. GameConfig.Version,
		Font = Theme.BodyFont,
		TextColor3 = Theme.Colors.Muted,
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 1),
		MaxTextSize = 14,
		Stroke = false,
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
	end

	Registry.DataController.ObserveMany({ "Settings", "Passes" }, refresh)

	return { Window = window, OnOpen = refresh }
end

return Settings
