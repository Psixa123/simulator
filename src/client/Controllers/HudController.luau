--!nonstrict
-- The always-visible interface, laid out like docs/ui_mockup.png (STYLE_GUIDE section 2, "HUD layout"):
--   top centre  currency capsules (Volts with a "+", Climate Shifts); the Mega Storm boss bar and the
--               tank-full offer stack under them, and toasts drop in below that
--   left        round weather-badge menu buttons: two columns, one on narrow phones
--   bottom      the objective, stat chips, AUTO, the storm jar (Storm Tank) and the big SELL button
--   right       round timers: active boosts and the Mega Storm countdown (radar alerts sit above them)
-- Nothing goes in the top-left / top-right corners (Roblox chat and player list): the menu moves below
-- the desktop chat window, the timers stay low on the right, and SELL keeps clear of the phone jump button.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Monetization = require(Shared.Config.Monetization)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)
local Icons = require(script.Parent.Parent.UI.Icons)

local HudController = {}
HudController.MenuButtons = {}

local INK = Theme.Ink
local SETS = Theme.Sets
local MEDALS = { "🥇", "🥈", "🥉" }
local OFFER_PASSES = { "MegaTank", "RemoteSell" } -- offered once per session when the tank fills up
local OFFER_TIME = 15 -- seconds before the offer card hides itself

-- Layout (HUD units = offset px at 1280x720)
local BUTTON = 68 -- round menu buttons and timers
local COLUMN_PITCH = 92
local ROW_PITCH = 100
local EDGE = 24 -- distance from the screen sides
local BOTTOM = 16 -- distance of the SELL row from the bottom
local ROW_HEIGHT = 64 -- the SELL row
local STATS_HEIGHT = 30
local OBJECTIVE_HEIGHT = 44
local TIMERS_BOTTOM = 160 -- the right column ends this far above the bottom (clear of the phone jump button)

local MENU = {
	{ Key = "Pets", Icon = "Pets", Text = "Pets" },
	{ Key = "Shop", Icon = "Shop", Text = "Shop" },
	{ Key = "Upgrades", Icon = "Upgrades", Text = "Upgrades" },
	{ Key = "Rewards", Icon = "Rewards", Text = "Rewards" },
	{ Key = "Teleport", Icon = "Teleport", Text = "Teleport" },
	{ Key = "Rebirth", Icon = "ClimateShift", Text = "Shift" }, -- Climate Shift
	{ Key = "Settings", Icon = "Settings", Text = "Settings" },
}

local BOOSTS = {
	Energy = { Icon = "Energy", Order = 2 },
	Luck = { Icon = "Luck", Order = 1 },
}

local player = Players.LocalPlayer
local root: Frame
local topStack: Frame
local menuFrame: Frame
local menuOrder = {} -- buttons in menu order
local voltsCapsule
local voltsLabel: TextLabel
local voltsFrame: GuiObject
local shiftsCapsule
local displayedVolts = 0
local voltsTarget = 0
local tankHolder: Frame
local tankBar -- the storm jar (UI.Jar)
local worthChip: Frame
local worthLabel: TextLabel
local sellButton: TextButton
local autoButton: TextButton
local wasFull = false
local statsRow: Frame
local statChips = {} -- [label] = its chip
local statLabels = {}
local timerColumn: Frame
local boostTimers = {}
local boostLongest = {} -- [boost] = the longest remaining time seen (the timer ring's full length)
local stormTimer
local objectiveFrame: Frame
local objectiveLabel: TextLabel
local objectiveText: string? = nil
local objectiveMaxWidth = 560
local stormWidget
local stormBanner
local leadersRaw = nil
local leaders = {}
local offerCard: Frame? = nil
local offerShown = false

local function hudScale(): number
	return Registry.InterfaceController.HudScale
end

local function isPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function textWidth(text: string, size: number, font: Enum.Font?): number
	local ok, bounds = pcall(function()
		return game:GetService("TextService"):GetTextSize(text, size, font or Theme.Font, Vector2.new(4096, 4096))
	end)
	return if ok then bounds.X else #text * size * 0.56
end

---------------------------------------------------------------------------
-- Builders
---------------------------------------------------------------------------
-- Top centre: the currency capsules, the Mega Storm boss bar and the tank-full offer, stacked
-- (toasts go below)
local function buildTopStack()
	topStack = UI.Create("Frame", {
		Name = "TopCenter",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(400, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = root,
		UI.List(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top),
	})
end

local function buildCurrencies()
	-- 18 px on the left for the Volts icon that sticks out of its capsule, so the pair looks centred
	local row = UI.Create("Frame", {
		Name = "Currencies",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(18 + 208 + 42 + 122, 50),
		LayoutOrder = 1,
		Parent = topStack,
	})
	voltsCapsule = UI.Capsule({
		Name = "Volts",
		Icon = "Volts",
		Text = "0",
		Size = UDim2.fromOffset(208, 44),
		Position = UDim2.fromOffset(18, 0),
		Plus = function()
			Registry.InterfaceController.OpenPanel("Shop", "Volts")
		end,
		Parent = row,
	})
	voltsFrame = voltsCapsule.Frame
	voltsLabel = voltsCapsule.Label
	shiftsCapsule = UI.Capsule({
		Name = "Shifts",
		Icon = "ClimateShift",
		Text = "0",
		Size = UDim2.fromOffset(122, 44),
		Position = UDim2.fromOffset(18 + 208 + 42, 0),
		Parent = row,
		OnClick = function()
			Registry.InterfaceController.TogglePanel("Rebirth")
		end,
	})
	-- Volts packs aren't sold where paid random items are restricted (the Shop hides them too)
	local function applyPolicy()
		voltsCapsule.Plus.Visible = not Registry.MonetizationController.IsRestricted("VoltsSmall")
	end
	player:GetAttributeChangedSignal("PaidRandomItemsRestricted"):Connect(applyPolicy)
	applyPolicy()
end

local function teleportToArena()
	local result = Remotes.Teleport:InvokeServer("Arena")
	if result and not result.Ok then
		Registry.InterfaceController.Notify(result.Error, "Error")
	end
end

-- How far down (in HUD pixels) the desktop chat window reaches; 0 when there's none to avoid
local function chatBottom(): number
	if isPhone() then
		return 0 -- phones and tablets keep the chat closed until it's tapped open
	end
	local config = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	if not config or not config.Enabled then
		return 0
	end
	local ok, bottom = pcall(function()
		return config.AbsolutePosition.Y + config.AbsoluteSize.Y
	end)
	return if ok and type(bottom) == "number" then math.max(0, bottom - root.AbsolutePosition.Y) else 0
end

-- The menu sits a little above the middle of the left edge in two columns; on narrow phones in one
-- column when that fits; on desktop always below the chat window (top left)
local function placeMenu()
	local scale = hudScale()
	local width, height = root.AbsoluteSize.X / scale, root.AbsoluteSize.Y / scale
	if height <= 0 or not menuFrame then
		return
	end
	local count = #menuOrder
	local clear = chatBottom() / scale + 12
	local bottomLimit = height - (BOTTOM + ROW_HEIGHT + 10 + STATS_HEIGHT + 10 + OBJECTIVE_HEIGHT + 16)
	local function blockHeight(columns: number): number
		return math.ceil(count / columns) * ROW_PITCH - ROW_PITCH + BUTTON + 18
	end
	local columns = 2
	if width < 900 and math.max(clear, 70) + blockHeight(1) <= bottomLimit then
		columns = 1
	elseif math.max(clear, 10) + blockHeight(2) > height - 12 then
		columns = 3
	end
	local block = blockHeight(columns)
	local top = math.max((height - block) / 2 - 30, 10)
	top = math.max(top, math.min(clear, height - block - 12))
	menuFrame.Size = UDim2.fromOffset(columns * COLUMN_PITCH - (COLUMN_PITCH - BUTTON), block)
	menuFrame.Position = UDim2.fromOffset(EDGE, top)
	for index, button in menuOrder do
		local column = (index - 1) % columns
		local row = math.floor((index - 1) / columns)
		button.Position = UDim2.fromOffset(column * COLUMN_PITCH - 8, row * ROW_PITCH)
	end
end

local function buildMenu()
	menuFrame = UI.Create("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(2 * COLUMN_PITCH, 4 * ROW_PITCH),
		Position = UDim2.fromOffset(EDGE, 110), -- placeMenu fine-tunes this
		Parent = root,
	})
	for index, item in MENU do
		local button = UI.HudButton({
			Name = item.Key,
			Icon = item.Icon,
			Text = item.Text,
			-- the click area takes in the label and a little around the badge (fingers)
			Size = UDim2.fromOffset(BUTTON + 16, BUTTON + 22),
			LayoutOrder = index,
			Parent = menuFrame,
			OnClick = function()
				Registry.InterfaceController.TogglePanel(item.Key)
			end,
		})
		-- Bolt glow behind the badge for the objective tracker (HudController.Highlight)
		UI.Create("Frame", {
			Name = "Glow",
			BackgroundColor3 = SETS.Bolt.Top,
			BackgroundTransparency = 0.35,
			Size = UDim2.fromOffset(BUTTON + 14, BUTTON + 14),
			Position = UDim2.new(0.5, 0, 0, BUTTON / 2),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Visible = false,
			ZIndex = 0,
			Parent = button,
			UI.Round(),
		})
		HudController.MenuButtons[item.Key] = button
		table.insert(menuOrder, button)
	end
end

-- Small Cloud capsule with an icon: Power, pet multiplier, Volts multiplier
local function statChip(parent: Instance, name: string, icon: string, order: number)
	local chip = UI.Create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(120, STATS_HEIGHT),
		LayoutOrder = order,
		Parent = parent,
	})
	local body = UI.Create("Frame", {
		Name = "Body",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		Parent = chip,
		UI.Round(),
		UI.Gradient(Theme.Cloud, Theme.Mist),
		UI.Stroke(2, INK),
	})
	Icons.New(icon, { Name = "Icon", Size = UDim2.fromOffset(30, 30), Position = UDim2.new(0, 6, 0.5, 0), ZIndex = 2, Parent = chip })
	local label = UI.Text({
		Name = "Text",
		Text = "",
		TextSize = 16,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -30, 1, 0),
		Position = UDim2.fromOffset(26, 1),
		ZIndex = 2,
		Parent = body,
	})
	statChips[label] = chip
	return label
end

local function setStat(label: TextLabel, text: string)
	if label.Text == text then
		return
	end
	label.Text = text
	statChips[label].Size = UDim2.fromOffset(math.ceil(textWidth(text, 16)) + 42, STATS_HEIGHT)
end

local function buildTank()
	tankHolder = UI.Create("Frame", {
		Name = "Tank",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(734, ROW_HEIGHT),
		Position = UDim2.new(0.5, 0, 1, -BOTTOM),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = root,
	})

	statsRow = UI.Create("Frame", {
		Name = "Stats",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(600, STATS_HEIGHT),
		Position = UDim2.new(0.5, 0, 1, -(BOTTOM + ROW_HEIGHT + 10)),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = root,
		UI.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	statLabels.Power = statChip(statsRow, "Power", "Power", 1)
	statLabels.Pets = statChip(statsRow, "Pets", "Pets", 2)
	statLabels.Volts = statChip(statsRow, "VoltsMultiplier", "Volts", 3)

	autoButton = UI.Button({
		Name = "Auto",
		Text = "AUTO",
		Icon = "Lock",
		IconSize = 26,
		Color = "Gray",
		TextSize = 18,
		Size = UDim2.fromOffset(100, 56),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = tankHolder,
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

	tankBar = UI.Jar({
		Name = "TankBar",
		Size = UDim2.fromOffset(440, 52),
		Position = UDim2.new(0, 138, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = tankHolder,
	})

	sellButton = UI.Button({
		Name = "Sell",
		Text = "SELL",
		Icon = "Sell",
		Color = "Leaf",
		TextSize = 30,
		Size = UDim2.fromOffset(136, ROW_HEIGHT),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Parent = tankHolder,
		OnClick = function()
			local result = Remotes.Sell:InvokeServer()
			if result and not result.Ok then
				Registry.InterfaceController.Notify(result.Error, "Error")
			end
		end,
	})

	-- What the tank is worth: a Bolt price tag on top of the SELL button
	worthChip = UI.Create("Frame", {
		Name = "Worth",
		BackgroundColor3 = INK,
		Size = UDim2.fromOffset(96, 26),
		Position = UDim2.new(1, 8, 0, 2),
		AnchorPoint = Vector2.new(1, 0.5),
		Visible = false,
		ZIndex = 8,
		Parent = tankHolder,
		UI.Round(),
	})
	UI.Create("Frame", {
		Name = "Fill",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		ZIndex = 8,
		Parent = worthChip,
		UI.Round(),
		UI.Gradient(SETS.Bolt.Top, SETS.Bolt.Bottom),
	})
	Icons.New("Volts", { Name = "Icon", Size = UDim2.fromOffset(28, 28), Position = UDim2.new(0, 8, 0.5, 0), ZIndex = 9, Parent = worthChip })
	worthLabel = UI.Text({
		Name = "Amount",
		Text = "",
		TextSize = 16,
		Stroke = SETS.Bolt.Stroke,
		StrokeThickness = 1.5,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -28, 1, 0),
		Position = UDim2.fromOffset(25, 1),
		ZIndex = 9,
		Parent = worthChip,
	})
end

-- The SELL row is centred under the screen, the jar shrinks on narrow screens, and on phones the row
-- (with the stats and objective above it) moves left of Roblox's jump button
local function placeBottom()
	local scale = hudScale()
	local width = root.AbsoluteSize.X / scale
	if width <= 0 or not tankHolder then
		return
	end
	local margin = 12
	local right = width - margin
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	if UserInputService.TouchEnabled and math.min(viewport.X, viewport.Y) <= 500 then
		local jumpLeft = viewport.X - 108 -- the jump button's left edge on small screens (px)
		right = math.min(right, (jumpLeft - root.AbsolutePosition.X) / scale - 8)
	end
	-- AUTO, gap, the jar icon sticking out of the jar, the jar, gap, SELL
	local autoWidth, autoGap, overhang, sellGap, sellWidth = 100, 14, 24, 18, 136
	if right - margin < autoWidth + autoGap + overhang + sellGap + sellWidth + 300 then
		autoWidth, autoGap, sellGap, sellWidth = 72, 10, 12, 116 -- narrow phones
	end
	local fixed = autoWidth + autoGap + overhang + sellGap + sellWidth
	local jarWidth = math.clamp(right - margin - fixed, 200, 440)
	local total = fixed + jarWidth
	local left = math.max(margin, math.min((width - total) / 2, right - total))

	tankHolder.AnchorPoint = Vector2.new(0, 1)
	tankHolder.Position = UDim2.new(0, left, 1, -BOTTOM)
	tankHolder.Size = UDim2.fromOffset(total, ROW_HEIGHT)
	autoButton.Size = UDim2.fromOffset(autoWidth, 56)
	sellButton.Size = UDim2.fromOffset(sellWidth, ROW_HEIGHT)
	UI.SetButtonIcon(sellButton, if sellWidth >= 136 then "Sell" else nil) -- narrow: the word only
	tankBar.Frame.Size = UDim2.fromOffset(jarWidth, 52)
	tankBar.Frame.Position = UDim2.new(0, autoWidth + autoGap + overhang, 0.5, 0)

	local centre = left + total / 2
	statsRow.Position = UDim2.new(0, centre, 1, -(BOTTOM + ROW_HEIGHT + 12))
	statsRow.Size = UDim2.fromOffset(total, STATS_HEIGHT)
	objectiveFrame.Position = UDim2.new(0, centre, 1, -(BOTTOM + ROW_HEIGHT + 12 + STATS_HEIGHT + 10))
	objectiveMaxWidth = math.min(560, total)
	HudController.SetObjective(objectiveText)
	-- The hint line (InterfaceController.Hint) sits over the objective, as wide as the row
	local hint = root:FindFirstChild("Hint")
	if hint and hint:IsA("GuiObject") then
		hint.AnchorPoint = Vector2.new(0.5, 1)
		hint.Position = UDim2.new(0, centre, 1, -(BOTTOM + ROW_HEIGHT + 12 + STATS_HEIGHT + 10 + OBJECTIVE_HEIGHT + 10))
		hint.Size = UDim2.fromOffset(math.min(620, total), 30)
	end
end

-- Right column: round timers for active boosts and the Mega Storm countdown, bottom up
local function placeTimers()
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local bottom = TIMERS_BOTTOM
	if UserInputService.TouchEnabled and math.min(viewport.X, viewport.Y) > 500 then
		-- Tablets get Roblox's bigger jump button higher up the screen; keep the timers above it
		bottom = math.max(bottom, 220 / hudScale() + 10)
	end
	timerColumn.Position = UDim2.new(1, -EDGE, 1, -bottom)
end

local function buildTimers()
	-- Named "Boosts": the radar alerts (RadarController) stack above this column
	timerColumn = UI.Create("Frame", {
		Name = "Boosts",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(BUTTON, BUTTON + 16),
		Position = UDim2.new(1, -EDGE, 1, -TIMERS_BOTTOM),
		AnchorPoint = Vector2.new(1, 1),
		Parent = root,
		UI.List(Enum.FillDirection.Vertical, ROW_PITCH - BUTTON, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom),
	})
	local layout = timerColumn:FindFirstChildOfClass("UIListLayout")
	local function resize()
		local count = 0
		for _, child in timerColumn:GetChildren() do
			if child:IsA("GuiObject") and child.Visible then
				count += 1
			end
		end
		-- the time labels hang 16 px under the last circle
		timerColumn.Size = UDim2.fromOffset(BUTTON, math.max(count, 1) * ROW_PITCH - (ROW_PITCH - BUTTON) + 16)
	end
	layout.Padding = UDim.new(0, ROW_PITCH - BUTTON)

	for name, info in BOOSTS do
		local boost = GameConfig.Boosts[name]
		local timer = UI.Timer({
			Name = name,
			Icon = info.Icon,
			Color = "Sunset",
			Chip = "x" .. tostring(boost.Multiplier or 2),
			Text = "",
			LayoutOrder = info.Order,
			Parent = timerColumn,
			OnClick = function()
				Registry.InterfaceController.OpenPanel("Shop", "Boosts")
			end,
		})
		timer.Frame.Visible = false
		timer.Frame:GetPropertyChangedSignal("Visible"):Connect(resize)
		boostTimers[name] = timer
	end

	-- Mega Storm countdown, then "GO!" to jump to the arena
	stormTimer = UI.Timer({
		Name = "MegaStorm",
		Icon = "MegaStorm",
		Color = "Storm",
		Text = "--:--",
		LayoutOrder = 3,
		Parent = timerColumn,
		OnClick = function()
			if stormWidget.Phase == "Active" or stormWidget.Phase == "Warning" then
				teleportToArena()
			else
				Registry.InterfaceController.Notify("Next Mega Storm in " .. stormWidget.Timer .. "! Beat it together for Volts and exclusive pets.", "Info", "MegaStorm")
			end
		end,
	})
	stormWidget = { Frame = stormTimer.Frame, Timer = "", Phase = "Idle", Caption = stormTimer.Caption, Badge = stormTimer.Badge }
	resize()
end

-- One line just above the stats (the chat covers the top left on desktop)
local function buildObjective()
	objectiveFrame = UI.Create("Frame", {
		Name = "Objective",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(520, OBJECTIVE_HEIGHT),
		Position = UDim2.new(0.5, 0, 1, -(BOTTOM + ROW_HEIGHT + 10 + STATS_HEIGHT + 10)),
		AnchorPoint = Vector2.new(0.5, 1),
		Visible = false,
		Parent = root,
	})
	UI.Create("Frame", {
		Name = "Shadow",
		BackgroundColor3 = INK,
		BackgroundTransparency = Theme.ShadeTransparency,
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.fromScale(1, 1),
		Parent = objectiveFrame,
		UI.Round(),
	})
	UI.Create("Frame", {
		Name = "Pill",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		Parent = objectiveFrame,
		UI.Round(),
		UI.Gradient(Theme.Cloud, Theme.Mist),
		UI.Stroke(2, INK),
	})
	local disk = UI.Create("Frame", {
		Name = "Header",
		BackgroundColor3 = INK,
		Size = UDim2.fromOffset(36, 36),
		Position = UDim2.new(0, 4, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 2,
		Parent = objectiveFrame,
		UI.Round(),
	})
	UI.Create("Frame", {
		Name = "Fill",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		ZIndex = 2,
		Parent = disk,
		UI.Round(),
		UI.Gradient(SETS.Coral.Tint, SETS.Coral.Tint2),
	})
	Icons.New("Range", { Name = "Icon", Size = UDim2.fromOffset(28, 28), ZIndex = 3, Parent = disk })
	objectiveLabel = UI.Text({
		Name = "Text",
		Text = "",
		TextSize = 19,
		Scaled = true,
		MinTextSize = 11,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -62, 0, 26),
		Position = UDim2.new(0, 48, 0.5, 1),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 3,
		Parent = objectiveFrame,
	})
end

local function card(name: string, size: UDim2, order: number)
	local holder = UI.Create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = size,
		LayoutOrder = order,
		Visible = false,
		Parent = topStack,
	})
	UI.Create("Frame", {
		Name = "Shadow",
		BackgroundColor3 = INK,
		BackgroundTransparency = Theme.ShadeTransparency,
		Position = UDim2.fromOffset(0, 5),
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
		UI.Corner(20),
	})
	UI.Create("Frame", {
		Name = "Body",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.new(1, -6, 1, -6),
		Parent = holder,
		UI.Corner(17),
		UI.Gradient(Theme.Cloud, Theme.Mist),
		UI.Stroke(3, INK),
	})
	return holder
end

-- Boss bar under the capsules while a Mega Storm is active: health, your damage and the top 3
local function buildStormBanner()
	local banner = card("MegaStormBanner", UDim2.fromOffset(390, 172), 2)
	local name = UI.Text({ Name = "Name", Text = "", TextSize = 22, Scaled = true, Size = UDim2.new(1, -90, 0, 26), Position = UDim2.new(0.5, 0, 0, 10), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 2, Parent = banner })
	Icons.New("MegaStorm", { Name = "Icon", Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(28, 22), ZIndex = 3, Parent = banner })
	local health = UI.ProgressBar({ Name = "Health", Color = "Coral", Size = UDim2.new(1, -28, 0, 28), Position = UDim2.fromOffset(14, 40), MaxTextSize = 17, ZIndex = 2, Parent = banner })
	local info = UI.Text({ Name = "Info", Text = "", Font = Theme.BodyFont, TextSize = 13, Scaled = true, Color = Theme.InkSoft, Size = UDim2.new(1, -28, 0, 16), Position = UDim2.fromOffset(14, 74), ZIndex = 2, Parent = banner })

	local rows = {}
	for rank = 1, #MEDALS do
		local row = UI.Create("Frame", {
			Name = "Leader" .. rank,
			BackgroundColor3 = Theme.Haze,
			Size = UDim2.new(1, -28, 0, 22),
			Position = UDim2.fromOffset(14, 70 + rank * 25),
			ZIndex = 2,
			Parent = banner,
			UI.Round(),
		})
		local who = UI.Text({
			Name = "Who",
			Text = "",
			TextSize = 15,
			Scaled = true,
			X = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -100, 1, -4),
			Position = UDim2.fromOffset(10, 2),
			ZIndex = 3,
			Parent = row,
		})
		local damage = UI.Text({
			Name = "Damage",
			Text = "",
			TextSize = 15,
			Scaled = true,
			Color = SETS.Sunset.Stroke,
			X = Enum.TextXAlignment.Right,
			Size = UDim2.new(0, 86, 1, -4),
			Position = UDim2.new(1, -10, 0, 2),
			AnchorPoint = Vector2.new(1, 0),
			ZIndex = 3,
			Parent = row,
		})
		rows[rank] = { Frame = row, Who = who, Damage = damage }
	end
	stormBanner = { Frame = banner, Name = name, Health = health, Info = info, Rows = rows }
end

---------------------------------------------------------------------------
-- Tank-full offer (once per session, only for passes that can actually be bought)
---------------------------------------------------------------------------
local function hideOffer()
	if offerCard then
		offerCard:Destroy()
		offerCard = nil
	end
end

local function showOffer(data)
	if offerShown or offerCard or stormBanner.Frame.Visible then
		return
	end
	local passes = {}
	for _, key in OFFER_PASSES do
		local pass = Monetization.Gamepasses[key]
		if Formulas.HasPass(data, key) then
			return -- owns one of them already: nothing to offer
		end
		if pass and not Registry.MonetizationController.IsComingSoon(pass) then
			table.insert(passes, pass)
		end
	end
	if #passes == 0 then
		return
	end
	offerShown = true

	local offer = card("TankOffer", UDim2.fromOffset(410, 120), 3)
	offer.Visible = true
	offerCard = offer
	Icons.New("Tank", { Name = "Icon", Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(30, 27), ZIndex = 3, Parent = offer })
	UI.Text({
		Name = "Title",
		Text = "Tank full! Want more room?",
		TextSize = 20,
		Scaled = true,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -110, 0, 24),
		Position = UDim2.fromOffset(50, 15),
		ZIndex = 2,
		Parent = offer,
	})
	UI.CloseButton({
		Name = "Close",
		Diameter = 34,
		Position = UDim2.new(1, -10, 0, 9),
		AnchorPoint = Vector2.new(1, 0),
		ZIndex = 3,
		Parent = offer,
		OnClick = hideOffer,
	})
	local width = if #passes == 1 then 250 else 184
	for index, pass in passes do
		local button = UI.Button({
			Name = pass.Key,
			Text = pass.Icon .. " " .. pass.Name,
			Color = if index == 1 then "Sky" else "Sunset",
			MaxTextSize = 18,
			Size = UDim2.fromOffset(width, 58),
			Position = UDim2.new(0.5, if #passes == 1 then 0 else (index - 1.5) * (width + 12), 1, -12),
			AnchorPoint = Vector2.new(0.5, 1),
			ZIndex = 3,
			Parent = offer,
			OnClick = function()
				Registry.MonetizationController.PromptPass(pass.Key)
			end,
		})
		-- Name and price on two lines so both stay big enough to read on a phone
		Registry.MonetizationController.GetPrice("Pass", pass.Key, function(price)
			UI.SetButtonText(button, pass.Icon .. " " .. pass.Name .. "\nR$ " .. Format.Commas(price))
		end)
	end
	UI.Pop(offer, 0.8)
	task.delay(OFFER_TIME, function()
		if offerCard == offer then
			hideOffer()
		end
	end)
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
	tankBar.Set(fraction, Format.Number(data.Energy) .. " / " .. Format.Number(capacity))
	tankBar.SetFull(full)
	local worth = data.TankValue * Formulas.VoltsMultiplier(data)
	worthChip.Visible = worth > 0
	if worth > 0 then
		local text = Format.Number(worth)
		worthLabel.Text = text
		worthChip.Size = UDim2.fromOffset(math.ceil(textWidth(text, 16)) + 40, 26)
	end
	UI.SetButtonColor(sellButton, if data.Energy > 0 then "Leaf" else "Gray")
	sellButton:SetAttribute("Full", full)
	if wasFull and not full then
		-- Stop the "full" pulse where it is (touch screens never send MouseLeave to reset it)
		local scale = sellButton:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = 1
		end
	elseif full and not wasFull then
		showOffer(data)
	end
	wasFull = full
end

local function refreshShifts()
	local data = Registry.DataController.Data
	if data then
		shiftsCapsule.Set(Format.Number(data.Rebirths or 0))
	end
end

local function refreshStats()
	local data = Registry.DataController.Data
	if not data then
		return
	end
	setStat(statLabels.Power, Format.Number(Formulas.Power(data)) .. " Power")
	setStat(statLabels.Pets, Format.Multiplier(Formulas.PetMultiplier(data)) .. " Energy")
	setStat(statLabels.Volts, Format.Multiplier(Formulas.VoltsMultiplier(data)) .. " Volts")
end

local function refreshAuto()
	local data = Registry.DataController.Data
	if not data then
		return
	end
	if not Formulas.HasPass(data, "AutoCatch") then
		UI.SetButtonColor(autoButton, "Gray")
		UI.SetButtonIcon(autoButton, "Lock")
		UI.SetButtonText(autoButton, "AUTO")
	elseif data.Settings.AutoCatch then
		UI.SetButtonColor(autoButton, "Rain")
		UI.SetButtonIcon(autoButton, nil)
		UI.SetButtonText(autoButton, "🤖 ON")
	else
		UI.SetButtonColor(autoButton, "Gray")
		UI.SetButtonIcon(autoButton, nil)
		UI.SetButtonText(autoButton, "🤖 OFF")
	end
	-- Bought one of the offered passes: the offer has done its job
	if offerCard then
		for _, key in OFFER_PASSES do
			if Formulas.HasPass(data, key) then
				hideOffer()
				break
			end
		end
	end
end

local function refreshBoosts()
	local data = Registry.DataController.Data
	if not data then
		return
	end
	local now = Registry.DataController.Now()
	for name, timer in boostTimers do
		local endTime = data.Boosts and data.Boosts[name] or 0
		local remaining = endTime - now
		timer.Frame.Visible = remaining > 0
		if remaining > 0 then
			-- The ring runs down from the longest time seen since the boost started (or was extended)
			if not boostLongest[name] or remaining > boostLongest[name] then
				boostLongest[name] = remaining
			end
			timer.SetText(Format.Time(remaining))
			timer.SetProgress(remaining / boostLongest[name])
		else
			boostLongest[name] = nil
		end
	end
end

-- Live top contributors published by the server: JSON list of { Name, UserId, Damage }, best first
local function readLeaders()
	local state = ReplicatedStorage:FindFirstChild("MegaStormState")
	local raw = state and state:GetAttribute("Leaders")
	if raw == leadersRaw then
		return leaders
	end
	leadersRaw = raw
	leaders = {}
	if type(raw) == "string" and raw ~= "" then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(decoded) == "table" then
			for _, entry in ipairs(decoded) do
				if type(entry) == "table" and type(entry.Name) == "string" and type(entry.Damage) == "number" then
					table.insert(leaders, entry)
				end
			end
		end
	end
	return leaders
end

local function refreshLeaders(timer: string, fallbackInfo: string?)
	local list = readLeaders()
	local myRank = nil
	for rank, entry in list do
		if entry.UserId == player.UserId then
			myRank = rank
			break
		end
	end

	local damage = player:GetAttribute("MegaDamage")
	if type(damage) == "number" then
		local mine = if myRank then "You: #" .. myRank .. " with " .. Format.Number(damage) .. " damage" else "Your damage: " .. Format.Number(damage)
		stormBanner.Info.Text = "⏱ " .. timer .. "   •   " .. mine
	else
		stormBanner.Info.Text = fallbackInfo or ""
	end

	for rank, row in stormBanner.Rows do
		local entry = list[rank]
		if entry then
			row.Frame.Visible = true
			row.Who.Text = MEDALS[rank] .. " " .. entry.Name
			row.Who.TextColor3 = if entry.UserId == player.UserId then SETS.Sky.Bottom else INK
			row.Damage.Text = Format.Number(entry.Damage)
		elseif rank == 1 then
			row.Frame.Visible = true
			row.Who.Text = "🌪️ Vacuum the storm to top the leaderboard!"
			row.Who.TextColor3 = Theme.InkSoft
			row.Damage.Text = ""
		else
			row.Frame.Visible = false
		end
	end
end

-- Flying Volts from the SELL button to the Volts capsule
function HudController.PlaySell(volts: number)
	local scale = hudScale() -- pixels -> HUD units
	local start = sellButton.AbsolutePosition + sellButton.AbsoluteSize / 2 - root.AbsolutePosition
	local target = voltsCapsule.Icon
	local finish = target.AbsolutePosition + target.AbsoluteSize / 2 - root.AbsolutePosition
	for index = 1, 8 do
		local icon = Icons.New("Volts", {
			Name = "FlyingVolt",
			Size = UDim2.fromOffset(34, 34),
			Position = UDim2.fromOffset(start.X / scale, start.Y / scale),
			ZIndex = 10,
			Parent = root,
		})
		local spread = Vector2.new(math.random(-90, 90), math.random(-80, -20))
		task.delay(index * 0.03, function()
			local mid = (start / scale) + spread
			UI.Tween(icon, 0.22, { Position = UDim2.fromOffset(mid.X, mid.Y) }).Completed:Wait()
			UI.Tween(icon, 0.35, { Position = UDim2.fromOffset(finish.X / scale, finish.Y / scale), Size = UDim2.fromOffset(20, 20) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Wait()
			icon:Destroy()
			if index == 8 then
				UI.Pop(voltsFrame, 1.12)
			end
		end)
	end

	local popup = UI.Text({
		Name = "SellPopup",
		Text = "+" .. Format.Number(volts) .. " Volts",
		TextSize = 30,
		Color = SETS.Bolt.Top,
		Stroke = INK,
		StrokeThickness = 3,
		Size = UDim2.fromOffset(320, 36),
		Position = UDim2.new(0.5, 0, 0, 64),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 10,
		Parent = root,
	})
	UI.Pop(popup, 1.4)
	UI.Tween(popup, 1.2, { Position = UDim2.new(0.5, 0, 0, 92) })
	task.delay(0.9, function()
		UI.FadeOut(popup, 0.35)
		task.wait(0.4)
		popup:Destroy()
	end)
end

-- The objective line above the stats; nil hides it. The pill fits its text.
function HudController.SetObjective(text: string?)
	objectiveText = text
	if not text then
		objectiveFrame.Visible = false
		return
	end
	local width = math.clamp(textWidth(text, 19) + 66, math.min(220, objectiveMaxWidth), objectiveMaxWidth)
	objectiveFrame.Size = UDim2.fromOffset(width, OBJECTIVE_HEIGHT)
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
	local glow = button:FindFirstChild("Glow")
	if glow then
		glow.Visible = enabled
	end
end

function HudController.SetBadge(menuKey: string, count: number?)
	local button = HudController.MenuButtons[menuKey]
	local badge = button and button:FindFirstChild("Badge")
	if not badge then
		return
	end
	if (count or 0) <= 0 then
		UI.SetBadge(badge, nil)
	else
		UI.SetBadge(badge, if count > 1 then count else "!")
	end
end

-- How far along the Mega Storm countdown is (0 right after a storm, 1 when the next one starts)
local function stormProgress(phase: string): number
	local state = ReplicatedStorage:FindFirstChild("MegaStormState")
	local now = Registry.DataController.Now()
	local config = GameConfig.MegaStorm
	if phase == "Warning" then
		local nextTime = state and state:GetAttribute("NextTime")
		return if type(nextTime) == "number" then 1 - math.clamp((nextTime - now) / config.WarningTime, 0, 1) else 1
	end
	local nextTime = state and state:GetAttribute("NextTime")
	if type(nextTime) ~= "number" then
		return 0
	end
	return 1 - math.clamp((nextTime - now) / config.Interval, 0, 1)
end

-- state = { Phase, Name, Timer, Health, MaxHealth, Info }
function HudController.SetStorm(state)
	local widget = stormWidget
	widget.Phase = state.Phase
	widget.Timer = state.Timer or ""
	if state.Phase == "Active" or state.Phase == "Warning" then
		UI.SetBadge(widget.Badge, "!")
	else
		UI.SetBadge(widget.Badge, nil)
	end
	if state.Phase == "Active" then
		stormTimer.SetText("GO!")
		stormTimer.SetColor("Coral")
		stormTimer.SetProgress(state.Health / math.max(state.MaxHealth, 1))
		stormBanner.Frame.Visible = true
		hideOffer()
		stormBanner.Name.Text = string.upper(state.Name)
		stormBanner.Health.Set(state.Health / math.max(state.MaxHealth, 1), Format.Number(state.Health) .. " HP")
		refreshLeaders(widget.Timer, state.Info)
	elseif state.Phase == "Warning" then
		local flash = math.floor(os.clock() * 3) % 2 == 0
		stormTimer.SetText(if flash then "GO!" else widget.Timer)
		stormTimer.SetColor(if flash then "Sunset" else "Coral")
		stormTimer.SetProgress(stormProgress("Warning"))
		stormBanner.Frame.Visible = false
	else
		stormTimer.SetText(widget.Timer)
		stormTimer.SetColor("Storm")
		stormTimer.SetProgress(stormProgress("Idle"))
		stormBanner.Frame.Visible = false
	end
end

local function placeAll()
	placeMenu()
	placeBottom()
	placeTimers()
end

function HudController.Init()
	root = Registry.InterfaceController.HudRoot
	buildTopStack()
	buildCurrencies()
	buildMenu()
	buildObjective()
	buildTank()
	buildTimers()
	buildStormBanner()
	Registry.InterfaceController.SetNotificationAnchor(topStack)
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeAll)
	root:GetPropertyChangedSignal("AbsolutePosition"):Connect(placeBottom)
	placeAll()
end

function HudController.Start()
	local DataController = Registry.DataController

	-- Follow the chat window if the player resizes or moves it
	local chatConfig = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	if chatConfig then
		pcall(function()
			chatConfig:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeMenu)
			chatConfig:GetPropertyChangedSignal("AbsolutePosition"):Connect(placeMenu)
		end)
	end
	placeAll()

	DataController.Observe("Volts", function(volts)
		voltsTarget = volts or 0
		if voltsTarget < displayedVolts then
			-- Spending shows right away (only gains count up)
			displayedVolts = voltsTarget
			voltsLabel.Text = Format.Number(voltsTarget)
		end
	end)
	DataController.ObserveMany({ "Energy", "TankValue", "Upgrades", "Passes", "Rebirths" }, refreshTank)
	DataController.ObserveMany({ "Upgrades", "Pets", "Passes", "Rebirths", "Boosts" }, refreshStats)
	DataController.ObserveMany({ "Passes", "Settings" }, refreshAuto)
	DataController.Observe("Rebirths", refreshShifts)

	RunService.RenderStepped:Connect(function(dt)
		-- Smooth Volts counter
		if displayedVolts ~= voltsTarget then
			local difference = voltsTarget - displayedVolts
			if math.abs(difference) < 1 then
				displayedVolts = voltsTarget
			else
				displayedVolts += difference * math.min(1, dt * 9)
			end
			voltsLabel.Text = Format.Number(math.floor(displayedVolts + 0.5))
		end
		-- Bubbles in the storm jar; it wobbles and glows when full
		tankBar.Step(dt)
		-- Pulse the sell button while the tank is full
		if sellButton:GetAttribute("Full") then
			local scale = sellButton:FindFirstChildOfClass("UIScale")
			if scale then
				scale.Scale = 1 + math.abs(math.sin(os.clock() * 5)) * 0.08
			end
		end
		-- Glow behind the menu buttons the objective points at
		local pulse = (math.sin(os.clock() * 6) + 1) / 2
		for button in highlightedButtons do
			local glow = button:FindFirstChild("Glow")
			if glow then
				local size = BUTTON + 10 + pulse * 12
				glow.Size = UDim2.fromOffset(size, size)
				glow.BackgroundTransparency = 0.2 + pulse * 0.35
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
