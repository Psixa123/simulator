--!nonstrict
-- The always-visible interface: Volts counter, menu buttons (with the Mega Storm tile), the
-- Storm Tank bar with the SELL and AUTO buttons, stat chips, active boosts, the objective
-- tracker and the Mega Storm boss bar with its live leaderboard.
-- Layout keeps clear of the Roblox top bar, the chat (top left) and the player list (top right).

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

local HudController = {}
HudController.MenuButtons = {}

local COLORS = Theme.Colors
local MEDALS = { "🥇", "🥈", "🥉" }
local OFFER_PASSES = { "MegaTank", "RemoteSell" } -- offered once per session when the tank fills up
local OFFER_TIME = 15 -- seconds before the offer card hides itself
local MENU_HEIGHT = 380

local player = Players.LocalPlayer
local root: Frame
local topStack: Frame
local menuFrame: Frame
local voltsLabel: TextLabel
local voltsFrame: Frame
local displayedVolts = 0
local voltsTarget = 0
local tankBar
local worthLabel: TextLabel
local sellButton: TextButton
local autoButton: TextButton
local wasFull = false
local statLabels = {}
local boostHolder: Frame
local boostChips = {}
local objectiveFrame: Frame
local objectiveLabel: TextLabel
local stormWidget
local stormBanner
local leadersRaw = nil
local leaders = {}
local offerCard: Frame? = nil
local offerShown = false

---------------------------------------------------------------------------
-- Builders
---------------------------------------------------------------------------
-- Top centre: Volts, the Mega Storm boss bar and the tank-full offer, stacked (toasts go below)
local function buildTopStack()
	topStack = UI.Create("Frame", {
		Name = "TopCenter",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(400, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = root,
		UI.List(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top),
	})
end

local function buildVolts()
	voltsFrame = UI.Create("Frame", {
		Name = "Volts",
		Size = UDim2.fromOffset(300, 58),
		BackgroundColor3 = Color3.new(1, 1, 1),
		LayoutOrder = 1,
		Parent = topStack,
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
	local addButton = UI.Button({
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
	-- Volts packs aren't sold where paid random items are restricted (the Shop hides them too)
	local function applyPolicy()
		addButton.Visible = not Registry.MonetizationController.IsRestricted("VoltsSmall")
	end
	player:GetAttributeChangedSignal("PaidRandomItemsRestricted"):Connect(applyPolicy)
	applyPolicy()
end

local MENU = {
	{ Key = "Shop", Icon = "🛒", Text = "Shop", Color = "Orange" },
	{ Key = "Pets", Icon = "🐾", Text = "Pets", Color = "Pink" },
	{ Key = "Upgrades", Icon = "⬆️", Text = "Upgrades", Color = "Blue" },
	{ Key = "Rebirth", Icon = "🌀", Text = "Shift", Color = "Purple" }, -- Climate Shift
	{ Key = "Rewards", Icon = "🎁", Text = "Rewards", Color = "Green" },
	{ Key = "Teleport", Icon = "🗺️", Text = "Teleport", Color = "Teal" },
	{ Key = "Settings", Icon = "⚙️", Text = "Settings", Color = "Gray" },
}

local function menuButton(parent: Instance, key: string, icon: string, text: string, color: string, order: number)
	local button = UI.Create("TextButton", {
		Name = key,
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = Color3.new(1, 1, 1),
		LayoutOrder = order,
		Parent = parent,
		UI.Corner(18),
		UI.Stroke(3.5),
	})
	local palette = Theme.Buttons[color]
	local gradient = UI.Gradient(palette[1], palette[2], 90)
	gradient.Parent = button
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
		Text = icon,
		Stroke = false,
		Size = UDim2.fromScale(0.58, 0.58),
		Position = UDim2.fromScale(0.5, 0.4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = button,
	})
	local caption = UI.Label({
		Name = "Caption",
		Text = text,
		Size = UDim2.new(1, -8, 0.24, 0),
		Position = UDim2.new(0.5, 0, 1, -6),
		AnchorPoint = Vector2.new(0.5, 1),
		MaxTextSize = 17,
		Parent = button,
	})
	UI.Badge(button)
	UI.Bounce(button, 1.08)
	return button, caption, gradient
end

local function teleportToArena()
	local result = Remotes.Teleport:InvokeServer("Arena")
	if result and not result.Ok then
		Registry.InterfaceController.Notify(result.Error, "Error")
	end
end

-- How far down (in HUD pixels) the desktop chat window reaches; 0 when there's none to avoid
local function chatBottom(): number
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
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

-- The menu sits a little below the middle of the left edge, and on desktop low enough that the
-- chat window (top left) never covers its top row
local function placeMenu()
	local scale = Registry.InterfaceController.HudScale
	local height = root.AbsoluteSize.Y / scale
	if height <= 0 then
		return
	end
	local top = (height - MENU_HEIGHT) / 2 + 30
	local clear = chatBottom() / scale + 10
	top = math.max(top, math.min(clear, height - MENU_HEIGHT - 12))
	menuFrame.Position = UDim2.fromOffset(14, top)
end

local function buildMenu()
	local menu = UI.Create("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(180, MENU_HEIGHT),
		Position = UDim2.new(0, 14, 0.5, 30 - MENU_HEIGHT / 2), -- placeMenu fine-tunes this
		Parent = root,
		UI.Grid(UDim2.fromOffset(84, 84), UDim2.fromOffset(10, 10)),
	})
	menu.UIGridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	menuFrame = menu

	for index, item in MENU do
		local button = menuButton(menu, item.Key, item.Icon, item.Text, item.Color, index)
		button.Activated:Connect(function()
			Registry.SoundController.Play("Click")
			Registry.InterfaceController.TogglePanel(item.Key)
		end)
		HudController.MenuButtons[item.Key] = button
	end

	-- Mega Storm tile in the free grid slot: countdown, then "GO!" to jump to the arena
	local tile, caption, gradient = menuButton(menu, "MegaStorm", "🌪️", "--:--", "Dark", #MENU + 1)
	caption.TextColor3 = COLORS.Volts
	stormWidget = { Frame = tile, Gradient = gradient, Caption = caption, Badge = tile:FindFirstChild("Badge"), Phase = "Idle", Timer = "" }
	tile.Activated:Connect(function()
		Registry.SoundController.Play("Click")
		if stormWidget.Phase == "Active" or stormWidget.Phase == "Warning" then
			teleportToArena()
		else
			Registry.InterfaceController.Notify("🌪️ Next Mega Storm in " .. stormWidget.Timer .. "! Beat it together for Volts and exclusive pets.", "Info")
		end
	end)
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
	-- Bottom right, above the phone jump button and below where the player list reaches
	boostHolder = UI.Create("Frame", {
		Name = "Boosts",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(190, 100),
		Position = UDim2.new(1, -12, 1, -160),
		AnchorPoint = Vector2.new(1, 1),
		Parent = root,
		UI.List(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom),
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

-- One line just above the Storm Tank (the chat covers the top left on desktop)
local function buildObjective()
	objectiveFrame = UI.Create("Frame", {
		Name = "Objective",
		Size = UDim2.fromOffset(520, 40),
		Position = UDim2.new(0.5, 0, 1, -122),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Color3.fromRGB(20, 26, 58),
		BackgroundTransparency = 0.12,
		Visible = false,
		Parent = root,
		UI.Round(),
		UI.Stroke(2.5, Color3.fromRGB(255, 205, 90)),
	})
	UI.Label({
		Name = "Header",
		Text = "🎯",
		Stroke = false,
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = objectiveFrame,
	})
	objectiveLabel = UI.Label({
		Name = "Text",
		Text = "",
		Size = UDim2.new(1, -96, 0, 26),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 21,
		Parent = objectiveFrame,
	})
end

-- Boss bar under the Volts while a Mega Storm is active: health, your damage and the top 3
local function buildStormBanner()
	local banner = UI.Create("Frame", {
		Name = "MegaStormBanner",
		Size = UDim2.fromOffset(380, 166),
		BackgroundColor3 = Color3.fromRGB(20, 24, 56),
		BackgroundTransparency = 0.08,
		LayoutOrder = 2,
		Visible = false,
		Parent = topStack,
		UI.Corner(16),
		UI.Stroke(3, Color3.fromRGB(255, 100, 120)),
	})
	local name = UI.Label({ Name = "Name", Text = "", Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 6), MaxTextSize = 22, Parent = banner })
	local health = UI.ProgressBar({ Name = "Health", Color = "Red", Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 34), MaxTextSize = 18, Parent = banner })
	local info = UI.Label({ Name = "Info", Text = "", Font = Theme.BodyFont, TextColor3 = COLORS.SubText, Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 66), MaxTextSize = 16, Parent = banner })

	local rows = {}
	for rank = 1, #MEDALS do
		local row = UI.Create("Frame", {
			Name = "Leader" .. rank,
			BackgroundColor3 = COLORS.Inset,
			BackgroundTransparency = 0.35,
			Size = UDim2.new(1, -20, 0, 20),
			Position = UDim2.fromOffset(10, 70 + rank * 24),
			Parent = banner,
			UI.Corner(8),
		})
		local who = UI.Label({
			Name = "Who",
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -100, 1, -2),
			Position = UDim2.fromOffset(8, 1),
			MaxTextSize = 16,
			Parent = row,
		})
		local damage = UI.Label({
			Name = "Damage",
			Text = "",
			TextColor3 = COLORS.Volts,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.new(0, 86, 1, -2),
			Position = UDim2.new(1, -8, 0, 1),
			AnchorPoint = Vector2.new(1, 0),
			MaxTextSize = 16,
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

	local card = UI.Create("Frame", {
		Name = "TankOffer",
		Size = UDim2.fromOffset(400, 108),
		BackgroundColor3 = Color3.fromRGB(20, 26, 58),
		BackgroundTransparency = 0.06,
		LayoutOrder = 3,
		Parent = topStack,
		UI.Corner(16),
		UI.Stroke(3, COLORS.Energy),
	})
	offerCard = card
	UI.Label({
		Name = "Title",
		Text = "🛢️ Tank full! Want more room?",
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -66, 0, 26),
		Position = UDim2.fromOffset(12, 10),
		MaxTextSize = 20,
		Parent = card,
	})
	UI.Button({
		Name = "Close",
		Text = "✕",
		Color = "Gray",
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.new(1, -6, 0, 6),
		AnchorPoint = Vector2.new(1, 0),
		MaxTextSize = 22,
		Parent = card,
		OnClick = hideOffer,
	})
	local width = if #passes == 1 then 240 else 184
	for index, pass in passes do
		local button = UI.Button({
			Name = pass.Key,
			Text = pass.Icon .. " " .. pass.Name,
			Color = if index == 1 then "Blue" else "Orange",
			Size = UDim2.fromOffset(width, 52),
			Position = UDim2.new(0.5, if #passes == 1 then 0 else (index - 1.5) * (width + 10), 1, -8),
			AnchorPoint = Vector2.new(0.5, 1),
			MaxTextSize = 18,
			Parent = card,
			OnClick = function()
				Registry.MonetizationController.PromptPass(pass.Key)
			end,
		})
		-- Name and price on two lines so both stay big enough to read on a phone
		Registry.MonetizationController.GetPrice("Pass", pass.Key, function(price)
			UI.SetButtonText(button, pass.Icon .. " " .. pass.Name .. "\nR$ " .. Format.Commas(price))
		end)
	end
	UI.Pop(card, 0.8)
	task.delay(OFFER_TIME, function()
		if offerCard == card then
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
	tankBar.Set(fraction, (if full then "FULL!  " else "🌪️ ") .. Format.Number(data.Energy) .. " / " .. Format.Number(capacity))
	tankBar.SetColor(if full then "Red" elseif fraction > 0.75 then "Orange" else "Blue")
	local worth = data.TankValue * Formulas.VoltsMultiplier(data)
	worthLabel.Text = if worth > 0 then "Worth ⚡ " .. Format.Number(worth) else ""
	UI.SetButtonColor(sellButton, if data.Energy > 0 then "Yellow" else "Gray")
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
	for name, entry in boostChips do
		local endTime = data.Boosts and data.Boosts[name] or 0
		local remaining = endTime - now
		entry.Frame.Visible = remaining > 0
		if remaining > 0 then
			entry.Timer.Text = Format.Time(remaining)
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
			row.Who.TextColor3 = if entry.UserId == player.UserId then COLORS.Volts else COLORS.Text
			row.Damage.Text = Format.Number(entry.Damage)
		elseif rank == 1 then
			row.Frame.Visible = true
			row.Who.Text = "🌪️ Vacuum the storm to top the leaderboard!"
			row.Who.TextColor3 = COLORS.SubText
			row.Damage.Text = ""
		else
			row.Frame.Visible = false
		end
	end
end

-- Flying volts icons from the tank to the counter
function HudController.PlaySell(volts: number)
	local start = sellButton.AbsolutePosition + sellButton.AbsoluteSize / 2 - root.AbsolutePosition
	local finish = voltsFrame.AbsolutePosition + Vector2.new(30, voltsFrame.AbsoluteSize.Y / 2) - root.AbsolutePosition
	local scale = Registry.InterfaceController.HudScale -- pixels -> HUD units
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
	widget.Phase = state.Phase
	widget.Timer = state.Timer or ""
	if widget.Badge then
		widget.Badge.Visible = state.Phase == "Active" or state.Phase == "Warning"
	end
	if state.Phase == "Active" then
		widget.Caption.Text = "GO!"
		widget.Gradient.Color = ColorSequence.new(Color3.fromRGB(230, 70, 90), Color3.fromRGB(120, 24, 48))
		stormBanner.Frame.Visible = true
		hideOffer()
		stormBanner.Name.Text = "🌪️ " .. string.upper(state.Name)
		stormBanner.Health.Set(state.Health / math.max(state.MaxHealth, 1), Format.Number(state.Health) .. " HP")
		refreshLeaders(widget.Timer, state.Info)
	elseif state.Phase == "Warning" then
		local flash = math.floor(os.clock() * 3) % 2 == 0
		widget.Caption.Text = if flash then "GO!" else widget.Timer
		widget.Gradient.Color = if flash
			then ColorSequence.new(Color3.fromRGB(255, 150, 60), Color3.fromRGB(200, 70, 30))
			else ColorSequence.new(Color3.fromRGB(230, 70, 90), Color3.fromRGB(120, 24, 48))
		stormBanner.Frame.Visible = false
	else
		widget.Caption.Text = widget.Timer
		widget.Gradient.Color = ColorSequence.new(Color3.fromRGB(70, 84, 160), Color3.fromRGB(32, 38, 88))
		stormBanner.Frame.Visible = false
	end
end

function HudController.Init()
	root = Registry.InterfaceController.HudRoot
	buildTopStack()
	buildVolts()
	buildMenu()
	buildTank()
	buildBoosts()
	buildObjective()
	buildStormBanner()
	Registry.InterfaceController.SetNotificationAnchor(topStack)
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeMenu)
	placeMenu()
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
	placeMenu()

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
