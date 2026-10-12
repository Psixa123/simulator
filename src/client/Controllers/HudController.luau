--!nonstrict
-- The always-visible interface: Volts counter, menu buttons, the Storm Tank bar with the
-- SELL and AUTO buttons, stat chips, active boosts, the objective tracker and the
-- Mega Storm widget.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)

local HudController = {}
HudController.MenuButtons = {}

local COLORS = Theme.Colors

local root: Frame
local voltsLabel: TextLabel
local voltsFrame: Frame
local displayedVolts = 0
local voltsTarget = 0
local tankBar
local worthLabel: TextLabel
local sellButton: TextButton
local autoButton: TextButton
local statLabels = {}
local boostHolder: Frame
local boostChips = {}
local objectiveFrame: Frame
local objectiveLabel: TextLabel
local stormWidget
local stormBanner

---------------------------------------------------------------------------
-- Builders
---------------------------------------------------------------------------
local function buildVolts()
	voltsFrame = UI.Create("Frame", {
		Name = "Volts",
		Size = UDim2.fromOffset(300, 58),
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = root,
		UI.Corner(16),
		UI.Gradient(Color3.fromRGB(46, 58, 118), Color3.fromRGB(24, 30, 70), 90),
		UI.Stroke(3.5),
	})
	UI.Icon({
		Text = "⚡",
		Color = COLORS.Volts,
		Size = UDim2.fromOffset(66, 66),
		Position = UDim2.new(0, -14, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = voltsFrame,
	})
	voltsLabel = UI.Label({
		Name = "Amount",
		Text = "0",
		TextColor3 = COLORS.Volts,
		Size = UDim2.new(1, -120, 0.7, 0),
		Position = UDim2.new(0, 60, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Stroke = 3,
		MaxTextSize = 38,
		Parent = voltsFrame,
	})
	UI.Button({
		Name = "Add",
		Text = "+",
		Color = "Green",
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.new(1, -8, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		MaxTextSize = 34,
		Parent = voltsFrame,
		OnClick = function()
			Registry.InterfaceController.OpenPanel("Shop", "Volts")
		end,
	})
end

local MENU = {
	{ Key = "Shop", Icon = "🛒", Text = "Shop", Color = "Orange" },
	{ Key = "Pets", Icon = "🐾", Text = "Pets", Color = "Pink" },
	{ Key = "Upgrades", Icon = "⬆️", Text = "Upgrades", Color = "Blue" },
	{ Key = "Rebirth", Icon = "🔄", Text = "Rebirth", Color = "Purple" },
	{ Key = "Rewards", Icon = "🎁", Text = "Rewards", Color = "Green" },
	{ Key = "Teleport", Icon = "🗺️", Text = "Teleport", Color = "Teal" },
	{ Key = "Settings", Icon = "⚙️", Text = "Settings", Color = "Gray" },
}

local function buildMenu()
	local menu = UI.Create("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(180, 380),
		Position = UDim2.new(0, 14, 0.5, 10),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = root,
		UI.Grid(UDim2.fromOffset(84, 84), UDim2.fromOffset(10, 10)),
	})
	menu.UIGridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	for index, item in MENU do
		local button = UI.Create("TextButton", {
			Name = item.Key,
			AutoButtonColor = false,
			Text = "",
			BackgroundColor3 = Color3.new(1, 1, 1),
			LayoutOrder = index,
			Parent = menu,
			UI.Corner(18),
			UI.Stroke(3.5),
		})
		local palette = Theme.Buttons[item.Color]
		UI.Gradient(palette[1], palette[2], 90).Parent = button
		UI.Create("Frame", {
			Name = "Shine",
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.82,
			Size = UDim2.new(1, -10, 0.38, 0),
			Position = UDim2.fromOffset(5, 4),
			Parent = button,
			UI.Corner(14),
		})
		UI.Label({
			Name = "Icon",
			Text = item.Icon,
			Stroke = false,
			Size = UDim2.fromScale(0.58, 0.58),
			Position = UDim2.fromScale(0.5, 0.4),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = button,
		})
		UI.Label({
			Name = "Caption",
			Text = item.Text,
			Size = UDim2.new(1, -8, 0.24, 0),
			Position = UDim2.new(0.5, 0, 1, -6),
			AnchorPoint = Vector2.new(0.5, 1),
			MaxTextSize = 17,
			Parent = button,
		})
		UI.Badge(button)
		UI.Bounce(button, 1.08)
		button.Activated:Connect(function()
			Registry.SoundController.Play("Click")
			Registry.InterfaceController.TogglePanel(item.Key)
		end)
		HudController.MenuButtons[item.Key] = button
	end
end

local function chip(parent: Instance, name: string, order: number, color: Color3)
	local frame = UI.Create("Frame", {
		Name = name,
		Size = UDim2.fromOffset(150, 28),
		BackgroundColor3 = Color3.fromRGB(20, 26, 58),
		BackgroundTransparency = 0.15,
		LayoutOrder = order,
		Parent = parent,
		UI.Round(),
		UI.Stroke(2),
	})
	local label = UI.Label({
		Name = "Text",
		Text = "",
		TextColor3 = color,
		Size = UDim2.new(1, -14, 0.72, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 18,
		Parent = frame,
	})
	return label
end

local function buildTank()
	local holder = UI.Create("Frame", {
		Name = "Tank",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(560, 104),
		Position = UDim2.new(0.5, 0, 1, -10),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = root,
	})

	local stats = UI.Create("Frame", {
		Name = "Stats",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 28),
		Parent = holder,
		UI.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	statLabels.Power = chip(stats, "Power", 1, COLORS.Power)
	statLabels.Pets = chip(stats, "Pets", 2, Color3.fromRGB(255, 160, 220))
	statLabels.Volts = chip(stats, "VoltsMultiplier", 3, COLORS.Volts)

	autoButton = UI.Button({
		Name = "Auto",
		Text = "🤖 AUTO",
		Color = "Gray",
		Size = UDim2.fromOffset(104, 58),
		Position = UDim2.new(0, 0, 1, 0),
		AnchorPoint = Vector2.new(0, 1),
		MaxTextSize = 20,
		Parent = holder,
		OnClick = function()
			local data = Registry.DataController.Data
			if not data then
				return
			end
			if not Formulas.HasPass(data, "AutoCatch") then
				Registry.MonetizationController.PromptPass("AutoCatch")
				return
			end
			Remotes.SetSetting:InvokeServer("AutoCatch", not data.Settings.AutoCatch)
		end,
	})

	tankBar = UI.ProgressBar({
		Name = "TankBar",
		Color = "Blue",
		Size = UDim2.new(1, -244, 0, 50),
		Position = UDim2.new(0.5, -6, 1, -4),
		AnchorPoint = Vector2.new(0.5, 1),
		StrokeThickness = 3.5,
		MaxTextSize = 24,
		Parent = holder,
	})
	worthLabel = UI.Label({
		Name = "Worth",
		Text = "",
		TextColor3 = COLORS.Volts,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, -244, 0, 20),
		Position = UDim2.new(0.5, -6, 1, -58),
		AnchorPoint = Vector2.new(0.5, 1),
		MaxTextSize = 18,
		Parent = holder,
	})

	sellButton = UI.Button({
		Name = "Sell",
		Text = "⚡ SELL",
		Color = "Yellow",
		Size = UDim2.fromOffset(118, 58),
		Position = UDim2.new(1, 0, 1, 0),
		AnchorPoint = Vector2.new(1, 1),
		MaxTextSize = 24,
		Parent = holder,
		OnClick = function()
			local result = Remotes.Sell:InvokeServer()
			if result and not result.Ok then
				Registry.InterfaceController.Notify(result.Error, "Error")
			end
		end,
	})
end

local function buildBoosts()
	boostHolder = UI.Create("Frame", {
		Name = "Boosts",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(190, 200),
		Position = UDim2.new(1, -12, 0.5, 40),
		AnchorPoint = Vector2.new(1, 0.5),
		Parent = root,
		UI.List(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center),
	})
	for index, name in { "Energy", "Luck" } do
		local boost = GameConfig.Boosts[name]
		local frame = UI.Create("Frame", {
			Name = name,
			Size = UDim2.fromOffset(186, 46),
			BackgroundColor3 = Color3.fromRGB(20, 26, 58),
			BackgroundTransparency = 0.1,
			LayoutOrder = index,
			Visible = false,
			Parent = boostHolder,
			UI.Corner(14),
			UI.Stroke(2.5, boost.Color),
		})
		UI.Icon({ Text = boost.Icon, Color = boost.Color, Size = UDim2.fromOffset(38, 38), Position = UDim2.new(0, 4, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = frame })
		UI.Label({ Name = "Name", Text = boost.Name, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -54, 0.45, 0), Position = UDim2.fromOffset(48, 4), MaxTextSize = 18, Parent = frame })
		local timer = UI.Label({ Name = "Timer", Text = "", TextColor3 = boost.Color, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -54, 0.42, 0), Position = UDim2.new(0, 48, 1, -4), AnchorPoint = Vector2.new(0, 1), MaxTextSize = 18, Parent = frame })
		boostChips[name] = { Frame = frame, Timer = timer }
	end
end

local function buildObjective()
	objectiveFrame = UI.Create("Frame", {
		Name = "Objective",
		Size = UDim2.fromOffset(330, 66),
		Position = UDim2.fromOffset(12, 8),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = false,
		Parent = root,
		UI.Corner(14),
		UI.Gradient(Color3.fromRGB(46, 58, 118), Color3.fromRGB(26, 32, 74), 90),
		UI.Stroke(3),
	})
	UI.Label({
		Name = "Header",
		Text = "🎯 OBJECTIVE",
		TextColor3 = Color3.fromRGB(255, 205, 90),
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.fromOffset(12, 6),
		MaxTextSize = 17,
		Parent = objectiveFrame,
	})
	objectiveLabel = UI.Label({
		Name = "Text",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.fromOffset(12, 28),
		MaxTextSize = 20,
		Parent = objectiveFrame,
	})
end

local function buildStormWidget()
	local frame = UI.Create("Frame", {
		Name = "MegaStorm",
		Size = UDim2.fromOffset(290, 64),
		Position = UDim2.new(1, -12, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = root,
		UI.Corner(16),
		UI.Stroke(3.5),
	})
	local gradient = UI.Gradient(Color3.fromRGB(70, 84, 160), Color3.fromRGB(32, 38, 88), 90)
	gradient.Parent = frame
	UI.Icon({ Text = "🌪️", Color = Color3.fromRGB(150, 205, 255), Size = UDim2.fromOffset(50, 50), Position = UDim2.new(0, 8, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = frame })
	local title = UI.Label({ Name = "Title", Text = "MEGA STORM", TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -140, 0, 24), Position = UDim2.fromOffset(66, 8), MaxTextSize = 20, Parent = frame })
	local timer = UI.Label({ Name = "Timer", Text = "--:--", TextColor3 = COLORS.Volts, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -140, 0, 24), Position = UDim2.fromOffset(66, 32), MaxTextSize = 20, Parent = frame })
	local go = UI.Button({
		Name = "Go",
		Text = "GO!",
		Color = "Red",
		Size = UDim2.fromOffset(62, 46),
		Position = UDim2.new(1, -8, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		MaxTextSize = 22,
		Parent = frame,
		OnClick = function()
			local result = Remotes.Teleport:InvokeServer("Arena")
			if result and not result.Ok then
				Registry.InterfaceController.Notify(result.Error, "Error")
			end
		end,
	})
	stormWidget = { Frame = frame, Gradient = gradient, Title = title, Timer = timer, Go = go }

	local banner = UI.Create("Frame", {
		Name = "MegaStormBanner",
		Size = UDim2.fromOffset(340, 92),
		Position = UDim2.new(1, -12, 0, 80),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.fromRGB(20, 24, 56),
		BackgroundTransparency = 0.08,
		Visible = false,
		Parent = root,
		UI.Corner(16),
		UI.Stroke(3, Color3.fromRGB(255, 100, 120)),
	})
	local name = UI.Label({ Name = "Name", Text = "", Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 6), MaxTextSize = 22, Parent = banner })
	local health = UI.ProgressBar({ Name = "Health", Color = "Red", Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 34), MaxTextSize = 18, Parent = banner })
	local info = UI.Label({ Name = "Info", Text = "", Font = Theme.BodyFont, TextColor3 = COLORS.SubText, Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 66), MaxTextSize = 16, Parent = banner })
	stormBanner = { Frame = banner, Name = name, Health = health, Info = info }
end

---------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------
local function refreshTank()
	local data = Registry.DataController.Data
	if not data then
		return
	end
	local capacity = Formulas.TankCapacity(data)
	local fraction = data.Energy / capacity
	local full = fraction >= 0.999
	tankBar.Set(fraction, (if full then "FULL!  " else "🌪️ ") .. Format.Number(data.Energy) .. " / " .. Format.Number(capacity))
	tankBar.SetColor(if full then "Red" elseif fraction > 0.75 then "Orange" else "Blue")
	local worth = data.TankValue * Formulas.VoltsMultiplier(data)
	worthLabel.Text = if worth > 0 then "Worth ⚡ " .. Format.Number(worth) else ""
	UI.SetButtonColor(sellButton, if data.Energy > 0 then "Yellow" else "Gray")
	sellButton:SetAttribute("Full", full)
end

local function refreshStats()
	local data = Registry.DataController.Data
	if not data then
		return
	end
	statLabels.Power.Text = "💨 " .. Format.Number(Formulas.Power(data)) .. " Power"
	statLabels.Pets.Text = "🐾 " .. Format.Multiplier(Formulas.PetMultiplier(data)) .. " Energy"
	statLabels.Volts.Text = "💰 " .. Format.Multiplier(Formulas.VoltsMultiplier(data)) .. " Volts"
end

local function refreshAuto()
	local data = Registry.DataController.Data
	if not data then
		return
	end
	if not Formulas.HasPass(data, "AutoCatch") then
		UI.SetButtonColor(autoButton, "Gray")
		UI.SetButtonText(autoButton, "🔒 AUTO")
	elseif data.Settings.AutoCatch then
		UI.SetButtonColor(autoButton, "Teal")
		UI.SetButtonText(autoButton, "🤖 ON")
	else
		UI.SetButtonColor(autoButton, "Gray")
		UI.SetButtonText(autoButton, "🤖 OFF")
	end
end

local function refreshBoosts()
	local data = Registry.DataController.Data
	if not data then
		return
	end
	local now = Registry.DataController.Now()
	for name, entry in boostChips do
		local endTime = data.Boosts and data.Boosts[name] or 0
		local remaining = endTime - now
		entry.Frame.Visible = remaining > 0
		if remaining > 0 then
			entry.Timer.Text = Format.Time(remaining)
		end
	end
end

-- Flying volts icons from the tank to the counter
function HudController.PlaySell(volts: number)
	local start = sellButton.AbsolutePosition + sellButton.AbsoluteSize / 2 - root.AbsolutePosition
	local finish = voltsFrame.AbsolutePosition + Vector2.new(30, voltsFrame.AbsoluteSize.Y / 2) - root.AbsolutePosition
	local scale = Registry.InterfaceController.Scale
	for index = 1, 8 do
		local icon = UI.Label({
			Text = "⚡",
			Stroke = false,
			Size = UDim2.fromOffset(34, 34),
			Position = UDim2.fromOffset(start.X / scale, start.Y / scale),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 10,
			Parent = root,
		})
		local spread = Vector2.new(math.random(-90, 90), math.random(-80, -20))
		task.delay(index * 0.03, function()
			local mid = (start / scale) + spread
			UI.Tween(icon, 0.22, { Position = UDim2.fromOffset(mid.X, mid.Y) }).Completed:Wait()
			UI.Tween(icon, 0.35, { Position = UDim2.fromOffset(finish.X / scale, finish.Y / scale), Size = UDim2.fromOffset(18, 18) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Wait()
			icon:Destroy()
			if index == 8 then
				UI.Pop(voltsFrame, 1.12)
			end
		end)
	end

	local popup = UI.Label({
		Text = "+⚡ " .. Format.Number(volts),
		TextColor3 = COLORS.Volts,
		Size = UDim2.fromOffset(260, 36),
		Position = UDim2.new(0.5, 0, 0, 70),
		AnchorPoint = Vector2.new(0.5, 0),
		Stroke = 3,
		ZIndex = 10,
		Parent = root,
	})
	UI.Pop(popup, 1.4)
	UI.Tween(popup, 1.2, { Position = UDim2.new(0.5, 0, 0, 100) })
	task.delay(0.9, function()
		UI.Tween(popup, 0.35, { TextTransparency = 1 })
		local stroke = popup:FindFirstChildOfClass("UIStroke")
		if stroke then
			UI.Tween(stroke, 0.35, { Transparency = 1 })
		end
		task.wait(0.4)
		popup:Destroy()
	end)
end

function HudController.SetObjective(text: string?)
	if not text then
		objectiveFrame.Visible = false
		return
	end
	if objectiveLabel.Text ~= text then
		objectiveLabel.Text = text
		if objectiveFrame.Visible then
			UI.Pop(objectiveFrame, 1.06)
		end
	end
	objectiveFrame.Visible = true
end

local highlightedButtons = {}

-- Makes a menu button glow (used by the objective tracker)
function HudController.Highlight(menuKey: string, enabled: boolean)
	local button = HudController.MenuButtons[menuKey]
	if not button then
		return
	end
	highlightedButtons[button] = if enabled then true else nil
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke and not enabled then
		stroke.Color = COLORS.Stroke
		stroke.Thickness = 3.5
	end
end

function HudController.SetBadge(menuKey: string, count: number?)
	local button = HudController.MenuButtons[menuKey]
	local badge = button and button:FindFirstChild("Badge")
	if not badge then
		return
	end
	badge.Visible = (count or 0) > 0
	local label = badge:FindFirstChild("Count")
	if label then
		label.Text = if count and count > 1 then tostring(count) else "!"
	end
end

-- state = { Phase, Name, Timer, Health, MaxHealth, Info }
function HudController.SetStorm(state)
	local widget = stormWidget
	if state.Phase == "Active" then
		widget.Title.Text = "MEGA STORM!"
		widget.Timer.Text = state.Timer
		widget.Gradient.Color = ColorSequence.new(Color3.fromRGB(230, 70, 90), Color3.fromRGB(120, 24, 48))
		widget.Go.Visible = true
		stormBanner.Frame.Visible = true
		stormBanner.Name.Text = "🌪️ " .. string.upper(state.Name)
		stormBanner.Health.Set(state.Health / math.max(state.MaxHealth, 1), Format.Number(state.Health) .. " HP")
		stormBanner.Info.Text = state.Info or ""
	elseif state.Phase == "Warning" then
		widget.Title.Text = "⚠️ STORM INCOMING"
		widget.Timer.Text = state.Timer
		local flash = math.floor(os.clock() * 3) % 2 == 0
		widget.Gradient.Color = if flash
			then ColorSequence.new(Color3.fromRGB(255, 150, 60), Color3.fromRGB(200, 70, 30))
			else ColorSequence.new(Color3.fromRGB(230, 70, 90), Color3.fromRGB(120, 24, 48))
		widget.Go.Visible = true
		stormBanner.Frame.Visible = false
	else
		widget.Title.Text = "MEGA STORM"
		widget.Timer.Text = "in " .. state.Timer
		widget.Gradient.Color = ColorSequence.new(Color3.fromRGB(70, 84, 160), Color3.fromRGB(32, 38, 88))
		widget.Go.Visible = false
		stormBanner.Frame.Visible = false
	end
end

function HudController.Init()
	root = Registry.InterfaceController.HudRoot
	buildVolts()
	buildMenu()
	buildTank()
	buildBoosts()
	buildObjective()
	buildStormWidget()
end

function HudController.Start()
	local DataController = Registry.DataController

	DataController.Observe("Volts", function(volts)
		voltsTarget = volts or 0
		if voltsTarget < displayedVolts then
			displayedVolts = voltsTarget
		end
	end)
	DataController.ObserveMany({ "Energy", "TankValue", "Upgrades", "Passes", "Rebirths" }, refreshTank)
	DataController.ObserveMany({ "Upgrades", "Pets", "Passes", "Rebirths", "Boosts" }, refreshStats)
	DataController.ObserveMany({ "Passes", "Settings" }, refreshAuto)

	-- Smooth Volts counter
	RunService.RenderStepped:Connect(function(dt)
		if displayedVolts ~= voltsTarget then
			local difference = voltsTarget - displayedVolts
			if math.abs(difference) < 1 then
				displayedVolts = voltsTarget
			else
				displayedVolts += difference * math.min(1, dt * 9)
			end
			voltsLabel.Text = Format.Number(math.floor(displayedVolts + 0.5))
		end
		-- Pulse the sell button while the tank is full
		if sellButton:GetAttribute("Full") then
			local scale = sellButton:FindFirstChildOfClass("UIScale")
			if scale then
				scale.Scale = 1 + math.abs(math.sin(os.clock() * 5)) * 0.08
			end
		end
		-- Glow on menu buttons the objective points at
		for button in highlightedButtons do
			local stroke = button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = Color3.fromRGB(255, 220, 70)
				stroke.Thickness = 3.5 + (math.sin(os.clock() * 6) + 1) * 1.6
			end
		end
	end)
	voltsLabel.Text = Format.Number(voltsTarget)
	displayedVolts = voltsTarget

	task.spawn(function()
		while true do
			refreshBoosts()
			task.wait(1)
		end
	end)
end

return HudController
