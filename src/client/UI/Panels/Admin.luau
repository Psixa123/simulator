--!nonstrict
-- Admin panel (owner only): change Volts, energy, upgrades, Climate Shifts, boosts, gamepasses, pets and
-- zones, teleport, start the Mega Storm, spawn weather, announce, and pick another player to do it to.
-- Main.client.luau only builds it once the server has marked the player as an admin (the "IsAdmin"
-- attribute set by AdminService); the server checks every command again, so this is only the interface.
-- Every button calls Remotes.AdminCommand(command, args) and shows the server's answer as a toast.
-- Sky Lab look: a cloud window with tabs (Me / Pets / World / Players), white rows with an icon well,
-- number fields (they take 1.5M, 2b, 1e12...) and small candy buttons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Monetization = require(Shared.Config.Monetization)
local Pets = require(Shared.Config.Pets)
local Zones = require(Shared.Config.Zones)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI)
local Theme = require(script.Parent.Parent.Theme)
local Icons = require(script.Parent.Parent.Icons)
local Viewport = require(script.Parent.Parent.Viewport)
local Confirm = require(script.Parent.Parent.Overlays.Confirm)

local Admin = {}

local INK = Theme.Ink
local WHITE = Color3.new(1, 1, 1)
local SETS = Theme.Sets
local ROW_HEIGHT = 66
local BUTTON_HEIGHT = 40
local TITLE_WIDTH = 170 -- the title / info column of a row
local localPlayer = Players.LocalPlayer

-- Number suffixes the fields understand (as Format.Number writes them)
local SUFFIXES = {
	k = 1e3, m = 1e6, b = 1e9, t = 1e12, qa = 1e15, qi = 1e18, sx = 1e21, sp = 1e24, oc = 1e27, no = 1e30,
}

-- "1.5M" -> 1500000, "2b" -> 2e9, "1e12", "12,400" -> numbers (nil when it isn't one)
function Admin.ParseNumber(text: string): number?
	local clean = string.lower((string.gsub(text or "", "[%s,_]", "")))
	if clean == "" then
		return nil
	end
	local value = tonumber(clean)
	if not value then
		local number, suffix = string.match(clean, "^([%-%+]?%d*%.?%d+)(%a+)$")
		local multiplier = suffix and SUFFIXES[suffix]
		value = if number and multiplier then tonumber(number) * multiplier else nil
	end
	if not value or value ~= value or math.abs(value) == math.huge then
		return nil
	end
	return math.floor(value + 0.5)
end

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------
local function notify(text: string, kind: string)
	Registry.InterfaceController.Notify(text, kind)
end

-- A white field with the Ink outline (like the Codes box) holding a TextBox
local function field(props)
	local holder = UI.Create("Frame", {
		Name = props.Name or "Field",
		BackgroundColor3 = Theme.Cloud,
		Size = props.Size or UDim2.fromOffset(130, BUTTON_HEIGHT - 2),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
		UI.Corner(12),
		UI.Gradient(Theme.Mist, Theme.Cloud),
		UI.Stroke(Theme.OutlineSmall, INK),
	})
	return UI.Create("TextBox", {
		Name = "Box",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -14, 1, 0),
		Position = UDim2.fromOffset(7, 1),
		Font = Theme.Font,
		PlaceholderText = props.Placeholder or "0",
		PlaceholderColor3 = Theme.InkSoft:Lerp(WHITE, 0.45), -- lighter than a typed value
		Text = props.Text or "",
		TextColor3 = INK,
		TextSize = props.TextSize or 18,
		TextXAlignment = props.X or Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ClearTextOnFocus = false,
		Parent = holder,
	})
end

local function button(props)
	return UI.Button({
		Name = props.Name or props.Text,
		Text = props.Text,
		Icon = props.Icon,
		Color = props.Color or "Sky",
		Small = true,
		TextSize = props.TextSize or 16,
		Size = props.Size or UDim2.fromOffset(props.Width or 76, BUTTON_HEIGHT),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
		OnClick = props.OnClick,
	})
end

-- A tinted well with an icon (an Icons key or an emoji)
local function well(parent: Instance, icon: string, color: Color3, size: number, position: UDim2, anchor: Vector2?)
	local holder = UI.Create("Frame", {
		Name = "Well",
		BackgroundColor3 = WHITE,
		Size = UDim2.fromOffset(size, size),
		Position = position,
		AnchorPoint = anchor or Vector2.new(0, 0.5),
		Parent = parent,
		UI.Corner(math.floor(size * 0.27)),
		UI.Gradient(color:Lerp(WHITE, 0.8), color:Lerp(WHITE, 0.5)),
	})
	Icons.New(icon, { Name = "Icon", Size = UDim2.fromOffset(math.floor(size * 0.8), math.floor(size * 0.8)), Parent = holder })
	return holder
end

-- A round avatar: the player's initial on a candy disc, covered by their Roblox headshot once it has
-- loaded (rbxthumb needs no web call; a test player without a picture keeps the initial).
-- Returns { Frame, Set(player, colorName) }
local function avatar(parent: Instance, size: number, position: UDim2, anchor: Vector2?)
	local disc = UI.Create("Frame", {
		Name = "Avatar",
		BackgroundColor3 = WHITE,
		Size = UDim2.fromOffset(size, size),
		Position = position,
		AnchorPoint = anchor or Vector2.new(0, 0.5),
		Parent = parent,
		UI.Round(),
		UI.Gradient(SETS.Storm.Top, SETS.Storm.Bottom),
	})
	local gradient = disc:FindFirstChildOfClass("UIGradient")
	local letter = UI.Text({
		Name = "Letter",
		Text = "",
		TextSize = math.floor(size * 0.52),
		Stroke = SETS.Storm.Stroke,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, 1),
		Parent = disc,
	})
	local photo = UI.Create("ImageLabel", {
		Name = "Photo",
		BackgroundTransparency = 1,
		Image = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = disc,
		UI.Round(),
	})
	local ring = UI.Stroke(2, INK)
	ring.Parent = disc

	local api = { Frame = disc }
	function api.Set(player: Player, colorName: string?)
		local set = SETS[colorName or "Storm"] or SETS.Storm
		gradient.Color = ColorSequence.new(set.Top, set.Bottom)
		local stroke = letter:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = set.Stroke
		end
		letter.Text = string.upper(string.sub(player.DisplayName, 1, 1))
		photo.Image = if player.UserId > 0
			then string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", player.UserId)
			else ""
	end
	return api
end

-- Players whose Name or DisplayName contains the text (any case); an exact Name wins outright
local function matchPlayers(query: string): { Player }
	local lower = string.lower(query)
	local found = {}
	for _, player in Players:GetPlayers() do
		local name = string.lower(player.Name)
		if name == lower then
			return { player }
		end
		if string.find(name, lower, 1, true) or string.find(string.lower(player.DisplayName), lower, 1, true) then
			table.insert(found, player)
		end
	end
	return found
end

-- A white row: icon well (or props.Player's avatar), title + info on the left, controls (right aligned)
-- on the right. Returns { Frame, Card, Title, Info, Controls, Avatar? }
local function row(parent: Instance, order: number, props)
	local height = props.Height or ROW_HEIGHT
	local holder = UI.Create("Frame", {
		Name = props.Name,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height),
		LayoutOrder = order,
		Parent = parent,
	})
	local card = UI.CloudCard({ Name = "Card", Size = UDim2.new(1, -4, 1, -4), Position = UDim2.fromOffset(2, 2), Parent = holder })
	local face
	if props.Player then
		face = avatar(card, 46, UDim2.new(0, 8, 0, (height - 4) / 2))
		face.Set(props.Player, props.AvatarColor)
	else
		well(card, props.Icon, props.Color or SETS.Sky.Top, 46, UDim2.new(0, 8, 0, (height - 4) / 2))
	end
	local titleWidth = props.TitleWidth or TITLE_WIDTH
	local title = UI.Text({
		Name = "Title",
		Text = props.Title,
		TextSize = 19,
		Scaled = true,
		MinTextSize = 11,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(titleWidth, 22),
		Position = UDim2.new(0, 64, 0.5, -19),
		Parent = card,
	})
	local info = UI.Text({
		Name = "Info",
		Text = props.Info or "",
		Font = Theme.BodyFont,
		TextSize = 13,
		Scaled = true,
		MinTextSize = 9,
		Color = Theme.InkSoft,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(titleWidth, 17),
		Position = UDim2.new(0, 64, 0.5, 5),
		Parent = card,
	})
	local controls = UI.Create("Frame", {
		Name = "Controls",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -(64 + titleWidth + 10), 1, 0),
		Position = UDim2.new(1, -10, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		Parent = card,
		UI.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center),
	})
	return { Frame = holder, Card = card, Title = title, Info = info, Controls = controls, Avatar = face }
end

-- A section heading inside a scrolling page
local function heading(parent: Instance, order: number, text: string)
	return UI.Text({
		Name = "Heading",
		Text = text,
		TextSize = 17,
		Color = Theme.InkSoft,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -8, 0, 26),
		Position = UDim2.fromOffset(4, 0),
		LayoutOrder = order,
		Parent = parent,
	})
end

local function page(parent: Instance, name: string)
	return UI.Scroll({
		Name = name,
		Size = UDim2.new(1, 0, 1, -58),
		Position = UDim2.fromOffset(0, 58),
		Visible = false,
		Parent = parent,
		UI.List(Enum.FillDirection.Vertical, 6),
		UI.Padding(2, 12, 8, 2),
	})
end

-- "4:29 left" style time
local function timeLeft(seconds: number): string
	return Format.Time(math.max(0, math.floor(seconds))) .. " left"
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
function Admin.Build()
	local window = UI.Window({
		Name = "Admin",
		Title = "Admin Panel",
		Icon = "🛠️",
		Size = UDim2.fromOffset(740, 560),
		Padding = { 18, 14, 14 },
	})
	local content = window.Content

	local target: Player? = nil -- nil = the admin themself
	local targetInfo = nil -- the server's summary of the target (Inspect), with ReceivedAt
	local refresh -- set below

	-- What the panel shows for the target: live data for yourself, the server's last answer for others
	local function summary()
		if not target then
			local data = Registry.DataController.Data
			if not data then
				return nil
			end
			local now = Registry.DataController.Now()
			local boosts = {}
			for boostName, endTime in data.Boosts or {} do
				boosts[boostName] = math.max(0, endTime - now)
			end
			return {
				Name = localPlayer.Name,
				DisplayName = localPlayer.DisplayName,
				Volts = data.Volts,
				Energy = data.Energy,
				Capacity = Formulas.TankCapacity(data),
				Zone = data.Zone,
				Rebirths = data.Rebirths,
				Upgrades = data.Upgrades,
				Pets = #data.Pets,
				Passes = data.Passes or {},
				Boosts = boosts,
			}
		end
		if not targetInfo then
			return nil
		end
		local elapsed = os.clock() - targetInfo.ReceivedAt
		local boosts = {}
		for boostName, remaining in targetInfo.Boosts or {} do
			boosts[boostName] = math.max(0, remaining - elapsed)
		end
		local copy = table.clone(targetInfo)
		copy.Boosts = boosts
		return copy
	end

	local function targetName(): string
		return if target then target.DisplayName else "You"
	end

	-- Sends a command; targeted commands go to the picked player (or options.Player). Shows the
	-- server's answer as a toast; options.Quiet hides a success, options.Silent any answer.
	local TARGETED = {
		Volts = true, Energy = true, Upgrade = true, Rebirths = true, Boost = true, Pass = true,
		Zone = true, Teleport = true, Pets = true, Inspect = true, Goto = true, Bring = true,
	}
	local function run(command: string, args, options)
		args = args or {}
		options = options or {}
		local subject = options.Player or target
		if TARGETED[command] and subject then
			args.Target = subject.Name
		end
		local success, reply = pcall(function()
			return Remotes.AdminCommand:InvokeServer(command, args)
		end)
		if not success or type(reply) ~= "table" then
			if not options.Silent then
				notify("The server didn't answer that admin command.", "Error")
			end
			return nil
		end
		if reply.Ok then
			if type(reply.Info) == "table" and target and reply.Info.Name == target.Name then
				targetInfo = reply.Info
				targetInfo.ReceivedAt = os.clock()
			end
			if not options.Quiet and not options.Silent and type(reply.Message) == "string" then
				notify(reply.Message, "Success")
			end
		elseif not options.Silent then
			notify(tostring(reply.Error or "That didn't work."), "Error")
		end
		refresh()
		return reply
	end

	-- Reads a number field; complains and returns nil when it isn't a number
	local function readNumber(box: TextBox, label: string): number?
		local value = Admin.ParseNumber(box.Text)
		if value == nil then
			notify("Enter " .. label .. " (e.g. 250, 1.5M, 2B).", "Error")
		end
		return value
	end

	---------------------------------------------------------------------
	-- Header: tabs and the target chip
	---------------------------------------------------------------------
	local pages = {}
	local tabs -- UI.Tabs, below
	local chip = UI.Create("TextButton", {
		Name = "Target",
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = WHITE,
		Size = UDim2.fromOffset(226, 46),
		Position = UDim2.new(1, -2, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		Parent = content,
		UI.Round(),
		UI.Gradient(Theme.Cloud, Theme.Mist),
		UI.Stroke(Theme.OutlineSmall, INK),
	})
	local chipStroke = chip:FindFirstChildOfClass("UIStroke")
	local chipAvatar = avatar(chip, 34, UDim2.new(0, 6, 0.5, 0))
	UI.Text({
		Name = "Caption",
		Text = "TARGET",
		Font = Theme.BodyFont,
		TextSize = 10,
		Color = Theme.InkSoft,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -96, 0, 12),
		Position = UDim2.fromOffset(48, 7),
		Parent = chip,
	})
	local chipName = UI.Text({
		Name = "Name",
		Text = "You",
		TextSize = 18,
		Scaled = true,
		MinTextSize = 10,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -128, 0, 22),
		Position = UDim2.fromOffset(48, 18),
		Parent = chip,
	})
	-- "Change" pill on the right: the chip opens the Players tab
	local changePill = UI.Create("Frame", {
		Name = "ChangePill",
		BackgroundColor3 = SETS.Sky.Tint,
		Size = UDim2.fromOffset(70, 26),
		Position = UDim2.new(1, -9, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Parent = chip,
		UI.Round(),
		UI.Stroke(2, SETS.Sky.Tint2),
	})
	UI.Text({
		Name = "Change",
		Text = "Change",
		Font = Theme.BodyFont,
		TextSize = 12,
		Color = SETS.Sky.Bottom,
		Size = UDim2.fromScale(1, 1),
		Parent = changePill,
	})
	chip.Activated:Connect(function()
		tabs.Select("Players")
	end)

	local function paintChip()
		local other = target ~= nil
		local set = if other then SETS.Sunset else SETS.Storm
		local who = target or localPlayer
		chipName.Text = if other then who.DisplayName else "You"
		chipAvatar.Set(who, if other then "Sunset" else "Storm")
		chip.BackgroundColor3 = if other then set.Tint else WHITE
		if chipStroke then
			chipStroke.Color = if other then set.Bottom else INK
		end
	end

	---------------------------------------------------------------------
	-- Me: Volts, energy, Climate Shifts, upgrades, boosts, gamepasses, reset
	---------------------------------------------------------------------
	local me = page(content, "Me")
	pages.Me = me
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	heading(me, nextOrder(), "Currency")
	local voltsRow = row(me, nextOrder(), { Name = "Volts", Icon = "Volts", Color = SETS.Bolt.Top, Title = "Volts" })
	local voltsBox = field({ Name = "Amount", Placeholder = "e.g. 1.5M", Size = UDim2.fromOffset(150, BUTTON_HEIGHT - 2), LayoutOrder = 1, Parent = voltsRow.Controls })
	button({ Text = "Give", Color = "Leaf", LayoutOrder = 2, Parent = voltsRow.Controls, OnClick = function()
		local amount = readNumber(voltsBox, "an amount of Volts")
		if amount then
			run("Volts", { Mode = "Give", Amount = amount })
		end
	end })
	button({ Text = "Set", Color = "Sky", LayoutOrder = 3, Parent = voltsRow.Controls, OnClick = function()
		local amount = readNumber(voltsBox, "an amount of Volts")
		if amount then
			run("Volts", { Mode = "Set", Amount = amount })
		end
	end })

	local energyRow = row(me, nextOrder(), { Name = "Energy", Icon = "Tank", Color = SETS.Rain.Top, Title = "Storm Tank" })
	local energyBox = field({ Name = "Amount", Placeholder = "energy", Size = UDim2.fromOffset(110, BUTTON_HEIGHT - 2), LayoutOrder = 1, Parent = energyRow.Controls })
	button({ Text = "Give", Color = "Leaf", Width = 64, LayoutOrder = 2, Parent = energyRow.Controls, OnClick = function()
		local amount = readNumber(energyBox, "an amount of energy")
		if amount then
			run("Energy", { Mode = "Give", Amount = math.max(0, amount) })
		end
	end })
	button({ Text = "Set", Color = "Sky", Width = 60, LayoutOrder = 3, Parent = energyRow.Controls, OnClick = function()
		local amount = readNumber(energyBox, "an amount of energy")
		if amount then
			run("Energy", { Mode = "Set", Amount = math.max(0, amount) })
		end
	end })
	button({ Text = "Fill", Color = "Rain", Width = 60, LayoutOrder = 4, Parent = energyRow.Controls, OnClick = function()
		run("Energy", { Mode = "Fill" })
	end })
	button({ Text = "Empty", Color = "Ink", Width = 74, LayoutOrder = 5, Parent = energyRow.Controls, OnClick = function()
		run("Energy", { Mode = "Empty" })
	end })

	local shiftsRow = row(me, nextOrder(), { Name = "Shifts", Icon = "ClimateShift", Color = SETS.Storm.Top, Title = "Climate Shifts" })
	local shiftsBox = field({ Name = "Count", Placeholder = "0 or more", Size = UDim2.fromOffset(150, BUTTON_HEIGHT - 2), LayoutOrder = 1, Parent = shiftsRow.Controls })
	button({ Text = "Set", Color = "Storm", LayoutOrder = 2, Parent = shiftsRow.Controls, OnClick = function()
		local count = readNumber(shiftsBox, "a number of Climate Shifts")
		if count then
			run("Rebirths", { Count = count })
		end
	end })

	heading(me, nextOrder(), "Upgrades")
	local upgradeRows = {}
	for _, upgradeId in GameConfig.UpgradeOrder do
		local def = GameConfig.Upgrades[upgradeId]
		local upgradeRow = row(me, nextOrder(), { Name = upgradeId, Icon = upgradeId, Color = SETS.Sky.Top, Title = def.Name })
		local levelBox = field({ Name = "Level", Placeholder = "Lv 1-" .. def.MaxLevel, Size = UDim2.fromOffset(110, BUTTON_HEIGHT - 2), LayoutOrder = 1, Parent = upgradeRow.Controls })
		button({ Text = "Set", Color = "Sky", Width = 64, LayoutOrder = 2, Parent = upgradeRow.Controls, OnClick = function()
			local level = readNumber(levelBox, "a level")
			if level then
				run("Upgrade", { Upgrade = upgradeId, Level = math.clamp(level, 1, def.MaxLevel) })
			end
		end })
		button({ Text = "Lv 1", Color = "Ink", Width = 64, LayoutOrder = 3, Parent = upgradeRow.Controls, OnClick = function()
			run("Upgrade", { Upgrade = upgradeId, Level = 1 })
		end })
		button({ Text = "Max", Color = "Storm", Width = 64, LayoutOrder = 4, Parent = upgradeRow.Controls, OnClick = function()
			run("Upgrade", { Upgrade = upgradeId, Level = def.MaxLevel })
		end })
		upgradeRows[upgradeId] = upgradeRow
	end
	local allRow = row(me, nextOrder(), { Name = "AllUpgrades", Icon = "Upgrades", Color = SETS.Leaf.Top, Title = "Every upgrade", Info = "All four at once", TitleWidth = 290 })
	local maxLevel = 1
	for _, def in GameConfig.Upgrades do
		maxLevel = math.max(maxLevel, def.MaxLevel)
	end
	button({ Text = "All Lv 1", Color = "Ink", Width = 100, LayoutOrder = 1, Parent = allRow.Controls, OnClick = function()
		run("Upgrade", { Upgrade = "All", Level = 1 })
	end })
	button({ Text = "Max All", Color = "Storm", Width = 100, LayoutOrder = 2, Parent = allRow.Controls, OnClick = function()
		run("Upgrade", { Upgrade = "All", Level = maxLevel })
	end })

	heading(me, nextOrder(), "Boosts")
	local boostRows = {}
	for _, boostName in { "Energy", "Luck" } do
		local boost = GameConfig.Boosts[boostName]
		local boostRow = row(me, nextOrder(), {
			Name = boostName .. "Boost",
			Icon = boostName, -- the HUD's boost timer icons (Energy, Luck)
			Color = boost.Color,
			Title = boost.Name,
		})
		local minutesBox = field({ Name = "Minutes", Placeholder = "minutes", Text = "30", Size = UDim2.fromOffset(110, BUTTON_HEIGHT - 2), LayoutOrder = 1, Parent = boostRow.Controls })
		button({ Text = "Give", Color = "Sunset", LayoutOrder = 2, Parent = boostRow.Controls, OnClick = function()
			local minutes = readNumber(minutesBox, "how many minutes")
			if minutes then
				run("Boost", { Boost = boostName, Minutes = math.max(1, minutes) })
			end
		end })
		button({ Text = "Clear", Color = "Ink", LayoutOrder = 3, Parent = boostRow.Controls, OnClick = function()
			run("Boost", { Boost = boostName, Minutes = 0 })
		end })
		boostRows[boostName] = boostRow
	end

	heading(me, nextOrder(), "Gamepasses (green = owned, for this session only)")
	local passKeys = {}
	for key in Monetization.Gamepasses do
		table.insert(passKeys, key)
	end
	table.sort(passKeys, function(a, b)
		return Monetization.Gamepasses[a].Order < Monetization.Gamepasses[b].Order
	end)
	local passHolder = UI.Create("Frame", {
		Name = "Passes",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = nextOrder(),
		Parent = me,
	})
	local passCard = UI.CloudCard({
		Name = "Card",
		Size = UDim2.new(1, -4, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromOffset(2, 2),
		Parent = passHolder,
		UI.Padding(10, 10, 10, 10),
		UI.Grid(UDim2.new(0.25, -6, 0, BUTTON_HEIGHT), UDim2.fromOffset(8, 8)), -- four across, filling the card
	})
	local passButtons = {}
	local function passOwned(key: string): boolean
		local info = summary()
		return info ~= nil and info.Passes ~= nil and info.Passes[key] == true
	end
	for index, key in passKeys do
		local pass = Monetization.Gamepasses[key]
		passButtons[key] = button({
			Name = key,
			Text = pass.Name,
			Icon = pass.Icon,
			Color = "Ink",
			TextSize = 15,
			LayoutOrder = index,
			Parent = passCard,
			OnClick = function()
				run("Pass", { Pass = key, Owned = not passOwned(key) })
			end,
		})
	end
	-- keep a gap under the card's outline
	UI.Create("Frame", { Name = "Gap", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 4), Position = UDim2.new(0, 0, 1, 0), Parent = passHolder })
	local allPassesRow = row(me, nextOrder(), {
		Name = "AllPasses",
		Icon = "Shop",
		Color = SETS.Leaf.Top,
		Title = "Every gamepass",
		Info = "Grant or remove them all at once",
		TitleWidth = 290,
	})
	button({ Name = "AllOff", Text = "All off", Color = "Coral", Width = 100, LayoutOrder = 1, Parent = allPassesRow.Controls, OnClick = function()
		run("Pass", { Pass = "All", Owned = false })
	end })
	button({ Name = "AllOn", Text = "All on", Color = "Leaf", Width = 100, LayoutOrder = 2, Parent = allPassesRow.Controls, OnClick = function()
		run("Pass", { Pass = "All", Owned = true })
	end })

	heading(me, nextOrder(), "Danger zone")
	local resetRow = row(me, nextOrder(), {
		Name = "Reset",
		Icon = "Close",
		Color = SETS.Coral.Top,
		Title = "Reset my data",
		Info = "Always your own save, never the target's",
		TitleWidth = 300,
	})
	button({ Text = "Reset my data", Color = "Coral", Width = 170, LayoutOrder = 1, Parent = resetRow.Controls, OnClick = function()
		Confirm.Show({
			Title = "Reset your data?",
			Text = "Volts, pets, zones, upgrades, Shifts and\nboosts start over like a brand new save.\nSettings and gamepasses stay.\nThis can't be undone.",
			ConfirmText = "Reset",
			Color = "Coral",
			Icon = "Close",
			OnConfirm = function()
				run("Reset", { Confirm = "RESET" })
			end,
		})
	end })

	---------------------------------------------------------------------
	-- Pets: every pet, a tier and how many
	---------------------------------------------------------------------
	local petsPage = UI.Create("Frame", {
		Name = "Pets",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -58),
		Position = UDim2.fromOffset(0, 58),
		Visible = false,
		Parent = content,
	})
	pages.Pets = petsPage
	local SIDE = 236
	local grid = UI.Scroll({
		Name = "Grid",
		Size = UDim2.new(1, -(SIDE + 12), 1, 0),
		Parent = petsPage,
		UI.Grid(UDim2.fromOffset(104, 128), UDim2.fromOffset(8, 8)),
		UI.Padding(4, 10, 8, 4),
	})
	local side = UI.CloudCard({
		Name = "Side",
		Size = UDim2.new(0, SIDE, 1, -4),
		Position = UDim2.new(1, -2, 0, 2),
		AnchorPoint = Vector2.new(1, 0),
		Parent = petsPage,
	})
	local preview = UI.Create("Frame", {
		Name = "Preview",
		BackgroundColor3 = WHITE,
		Size = UDim2.new(1, -20, 0, 150),
		Position = UDim2.fromOffset(10, 10),
		Parent = side,
		UI.Corner(14),
		UI.Gradient(SETS.Pink.Tint, SETS.Pink.Tint2),
	})
	local previewGradient = preview:FindFirstChildOfClass("UIGradient")
	local petName = UI.Text({
		Name = "PetName",
		Text = "",
		TextSize = 20,
		Scaled = true,
		MinTextSize = 11,
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.fromOffset(10, 166),
		Parent = side,
	})
	local petRarity = UI.Text({
		Name = "Rarity",
		Text = "",
		Font = Theme.BodyFont,
		TextSize = 13,
		Scaled = true,
		MinTextSize = 9,
		Size = UDim2.new(1, -20, 0, 16),
		Position = UDim2.fromOffset(10, 192),
		Parent = side,
	})
	local tierRow = UI.Create("Frame", {
		Name = "Tiers",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 0, 36),
		Position = UDim2.fromOffset(10, 216),
		Parent = side,
		UI.List(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	UI.Text({
		Name = "CountLabel",
		Text = "How many",
		Font = Theme.BodyFont,
		TextSize = 13,
		Color = Theme.InkSoft,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(80, 38),
		Position = UDim2.fromOffset(12, 262),
		Parent = side,
	})
	local countBox = field({ Name = "Count", Placeholder = "1-50", Text = "1", Size = UDim2.new(1, -104, 0, BUTTON_HEIGHT - 2), Position = UDim2.new(1, -10, 0, 262), AnchorPoint = Vector2.new(1, 0), Parent = side })
	local petCountInfo = UI.Text({
		Name = "Owned",
		Text = "",
		Font = Theme.BodyFont,
		TextSize = 12,
		Scaled = true,
		MinTextSize = 8,
		Color = Theme.InkSoft,
		Size = UDim2.new(1, -20, 0, 16),
		Position = UDim2.new(0, 10, 1, -72),
		Parent = side,
	})
	local giveButton = button({
		Name = "Give",
		Text = "Give Pets",
		Icon = "Pets",
		Color = "Leaf",
		TextSize = 19,
		Size = UDim2.new(1, -20, 0, 48),
		Position = UDim2.new(0, 10, 1, -10),
		AnchorPoint = Vector2.new(0, 1),
		Parent = side,
	})

	local selectedPet = Pets.IndexOrder[1]
	local selectedTier = "Normal"
	local tierButtons = {}
	local TIER_COLORS = { Normal = "Sky", Golden = "Bolt", Rainbow = "Pink" }
	local previewView = nil
	local tiles = {}
	local gridBuilt = false

	local function paintPetSide()
		local def = Pets.Pets[selectedPet]
		local rarity = Pets.Rarities[def.Rarity]
		petName.Text = Pets.DisplayName(selectedPet, selectedTier)
		petRarity.Text = rarity.Name .. "  •  " .. (def.Source or (def.Egg and Pets.Eggs[def.Egg].Name) or "")
			.. (if def.Odds then "  •  " .. Format.Odds(1 / def.Odds) else "")
		petRarity.TextColor3 = Theme.Shade(rarity.Color, 0.7)
		previewGradient.Color = ColorSequence.new(rarity.Color:Lerp(WHITE, 0.82), rarity.Color:Lerp(WHITE, 0.55))
		for tierName, tierButton in tierButtons do
			UI.SetButtonColor(tierButton, if tierName == selectedTier then TIER_COLORS[tierName] else "Off")
		end
		for petId, tile in tiles do
			tile.SetSelected(petId == selectedPet)
		end
		if previewView then
			previewView.Destroy()
		end
		previewView = Viewport.Pet(selectedPet, selectedTier, { Parent = preview, Zoom = 1.1, ZIndex = preview.ZIndex + 1 })
	end

	for index, tierName in { "Normal", "Golden", "Rainbow" } do
		tierButtons[tierName] = button({
			Name = tierName,
			Text = tierName,
			Color = "Off",
			TextSize = 14,
			Width = 68,
			Size = UDim2.fromOffset(68, 34),
			LayoutOrder = index,
			Parent = tierRow,
			OnClick = function()
				selectedTier = tierName
				paintPetSide()
			end,
		})
	end

	local function buildGrid()
		if gridBuilt then
			return
		end
		gridBuilt = true
		for index, petId in Pets.IndexOrder do
			local def = Pets.Pets[petId]
			local rarity = Pets.Rarities[def.Rarity]
			local tile = UI.Tile({
				Name = petId,
				Title = def.Name,
				Rarity = rarity,
				RarityText = rarity.Name,
				LayoutOrder = index,
				Parent = grid,
				OnClick = function()
					selectedPet = petId
					paintPetSide()
				end,
			})
			Viewport.Pet(petId, false, { Parent = tile.Art, ZIndex = tile.Frame.ZIndex + 3 })
			tiles[petId] = tile
		end
		paintPetSide()
	end

	giveButton.Activated:Connect(function()
		local count = readNumber(countBox, "how many pets")
		if count then
			run("Pets", { Pet = selectedPet, Tier = selectedTier, Count = math.clamp(count, 1, 50) })
		end
	end)

	---------------------------------------------------------------------
	-- World: zones, teleports, weather, the Mega Storm, announcements
	---------------------------------------------------------------------
	local world = page(content, "World")
	pages.World = world
	order = 0

	heading(world, nextOrder(), "Zones")
	local allZonesRow = row(world, nextOrder(), {
		Name = "AllZones",
		Icon = "Lock",
		Color = SETS.Leaf.Top,
		Title = "Every zone",
		Info = "Unlock them all, or lock all but the first",
		TitleWidth = 290,
	})
	button({ Text = "Lock all", Color = "Sunset", Width = 110, LayoutOrder = 1, Parent = allZonesRow.Controls, OnClick = function()
		run("Zone", { Zone = 1 })
	end })
	button({ Text = "Unlock all", Color = "Leaf", Width = 120, LayoutOrder = 2, Parent = allZonesRow.Controls, OnClick = function()
		run("Zone", { Zone = #Zones })
	end })
	local cellsRow = row(world, nextOrder(), {
		Name = "Cells",
		Icon = "🌦️",
		Color = SETS.Rain.Top,
		Title = "Weather cells",
		Info = "How many each Weather button spawns (1-20)",
		TitleWidth = 330,
	})
	local cellsBox = field({ Name = "Count", Placeholder = "1-20", Text = "5", Size = UDim2.fromOffset(110, BUTTON_HEIGHT - 2), LayoutOrder = 1, Parent = cellsRow.Controls })

	local zoneRows = {}
	local goButtons = {} -- "Go" for yourself, "Send" when another player is the target
	local hubRow = row(world, nextOrder(), { Name = "Hub", Icon = "Teleport", Color = Zones.Hub.Color, Title = Zones.Hub.Name, Info = "The hub, where everyone starts", TitleWidth = 330 })
	table.insert(goButtons, button({ Name = "Go", Text = "Go", Color = "Sky", Width = 84, LayoutOrder = 3, Parent = hubRow.Controls, OnClick = function()
		run("Teleport", { To = "Hub" })
	end }))
	local arenaRow = row(world, nextOrder(), { Name = "Arena", Icon = "MegaStorm", Color = SETS.Storm.Top, Title = "Mega Storm Arena", Info = "Where the Mega Storm strikes", TitleWidth = 330 })
	table.insert(goButtons, button({ Name = "Go", Text = "Go", Color = "Sky", Width = 84, LayoutOrder = 3, Parent = arenaRow.Controls, OnClick = function()
		run("Teleport", { To = "Arena" })
	end }))
	for zoneId, zone in ipairs(Zones) do
		local zoneRow = row(world, nextOrder(), { Name = "Zone" .. zoneId, Icon = zone.Icon, Color = zone.Color, Title = zone.Name })
		-- Unlock = unlocked up to this zone; Relock = this zone and the ones after it lock again
		zoneRow.Unlock = button({ Name = "Unlock", Text = "Unlock", Color = "Leaf", Width = 100, LayoutOrder = 1, Parent = zoneRow.Controls, OnClick = function()
			local info = summary()
			local unlocked = info and info.Zone or 1
			if zoneId > unlocked then
				run("Zone", { Zone = zoneId })
			elseif zoneId > 1 then
				run("Zone", { Zone = zoneId - 1 })
			else
				notify(zone.Name .. " is always unlocked.", "Info")
			end
		end })
		zoneRow.Weather = button({ Name = "Weather", Text = "Weather", Color = "Rain", Width = 100, LayoutOrder = 2, Parent = zoneRow.Controls, OnClick = function()
			local cells = readNumber(cellsBox, "how many weather cells")
			if cells then
				run("Weather", { Zone = zoneId, Count = math.clamp(cells, 1, 20) })
			end
		end })
		zoneRow.Go = button({ Name = "Go", Text = "Go", Color = "Sky", Width = 84, LayoutOrder = 3, Parent = zoneRow.Controls, OnClick = function()
			run("Teleport", { To = zoneId })
		end })
		table.insert(goButtons, zoneRow.Go)
		zoneRows[zoneId] = zoneRow
	end

	heading(world, nextOrder(), "Mega Storm")
	local stormRow = row(world, nextOrder(), {
		Name = "MegaStorm",
		Icon = "MegaStorm",
		Color = SETS.Storm.Top,
		Title = "Start a storm",
		Info = "For the whole server",
		TitleWidth = 150,
	})
	button({ Text = "Mega Storm", Icon = "MegaStorm", Color = "Storm", Width = 170, LayoutOrder = 1, Parent = stormRow.Controls, OnClick = function()
		run("MegaStorm", { Kind = "Summon" })
	end })
	button({ Text = "Rainbow Hurricane", Icon = "Rainbow", Color = "Pink", Width = 214, LayoutOrder = 2, Parent = stormRow.Controls, OnClick = function()
		run("MegaStorm", { Kind = "Rainbow" })
	end })

	heading(world, nextOrder(), "Announcement")
	local announceRow = row(world, nextOrder(), {
		Name = "Announce",
		Icon = "📢",
		Color = SETS.Sunset.Top,
		Title = "Tell everyone",
		Info = "A toast for the whole server",
		TitleWidth = 190,
	})
	local announceBox = field({
		Name = "Text",
		Placeholder = "Message (chat filtered)",
		Size = UDim2.fromOffset(250, BUTTON_HEIGHT - 2),
		X = Enum.TextXAlignment.Left,
		TextSize = 16,
		LayoutOrder = 1,
		Parent = announceRow.Controls,
	})
	button({ Text = "Send", Color = "Sunset", Width = 80, LayoutOrder = 2, Parent = announceRow.Controls, OnClick = function()
		local message = string.match(announceBox.Text, "^%s*(.-)%s*$") or ""
		if message == "" then
			notify("Type a message to announce first.", "Error")
			return
		end
		local reply = run("Announce", { Text = string.sub(message, 1, 150) })
		if reply and reply.Ok then
			announceBox.Text = ""
		end
	end })

	---------------------------------------------------------------------
	-- Players: pick the target, go to / bring
	---------------------------------------------------------------------
	local playersPage = UI.Create("Frame", {
		Name = "Players",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -58),
		Position = UDim2.fromOffset(0, 58),
		Visible = false,
		Parent = content,
	})
	pages.Players = playersPage
	-- The target's summary (the server's answer for another player, live data for yourself)
	local infoCard = UI.CloudCard({
		Name = "Info",
		Size = UDim2.new(1, -16, 0, 74),
		Position = UDim2.fromOffset(2, 2),
		Top = SETS.Sky.Tint,
		Bottom = SETS.Sky.Tint2,
		StrokeColor = SETS.Sky.Tint2,
		Parent = playersPage,
	})
	local infoAvatar = avatar(infoCard, 50, UDim2.new(0, 10, 0.5, 0))
	local infoTitle = UI.Text({
		Name = "Title",
		Text = "",
		TextSize = 19,
		Scaled = true,
		MinTextSize = 11,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -206, 0, 24),
		Position = UDim2.fromOffset(72, 11),
		Parent = infoCard,
	})
	local infoText = UI.Text({
		Name = "Stats",
		Text = "",
		Font = Theme.BodyFont,
		TextSize = 13,
		Scaled = true,
		MinTextSize = 9,
		Color = Theme.InkSoft,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -206, 0, 34),
		Position = UDim2.fromOffset(72, 34),
		Wrapped = true,
		Parent = infoCard,
	})
	button({
		Name = "Refresh",
		Text = "Refresh",
		Color = "Sky",
		Width = 110,
		Position = UDim2.new(1, -12, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Parent = infoCard,
		OnClick = function()
			run("Inspect", nil, { Quiet = true })
		end,
	})

	-- Find a player by name: typing filters the list, Enter / Pick targets the only match
	local findBox = field({
		Name = "Find",
		Placeholder = "Find a player: name or display name",
		X = Enum.TextXAlignment.Left,
		TextSize = 16,
		Size = UDim2.new(1, -144, 0, BUTTON_HEIGHT),
		Position = UDim2.fromOffset(2, 86),
		Parent = playersPage,
	})
	local findButton = button({
		Name = "FindTarget",
		Text = "Pick",
		Color = "Leaf",
		Width = 116,
		Position = UDim2.new(1, -14, 0, 86),
		AnchorPoint = Vector2.new(1, 0),
		Parent = playersPage,
	})

	local playerList = UI.Scroll({
		Name = "List",
		Size = UDim2.new(1, 0, 1, -134),
		Position = UDim2.fromOffset(0, 134),
		Parent = playersPage,
		UI.List(Enum.FillDirection.Vertical, 6),
		UI.Padding(2, 12, 8, 2),
	})
	local emptyNote = UI.Text({
		Name = "Empty",
		Text = "",
		Font = Theme.BodyFont,
		TextSize = 15,
		Color = Theme.InkSoft,
		Size = UDim2.new(1, -8, 0, 44),
		Wrapped = true,
		LayoutOrder = 9,
		Parent = playerList,
	})
	local playerRows = {} -- [Player] = row

	local function selectTarget(player: Player?)
		if player == localPlayer then
			player = nil
		end
		target = player
		targetInfo = nil
		paintChip()
		refresh()
		if player then
			run("Inspect", nil, { Quiet = true })
		end
	end

	-- Shows the rows matching the find box, and a note when nobody (else) is listed
	local function applyFilter()
		local query = string.match(findBox.Text, "^%s*(.-)%s*$") or ""
		local shown, others = 0, 0
		local matching = {}
		if query ~= "" then
			for _, player in matchPlayers(query) do
				matching[player] = true
			end
		end
		for player, playerRow in playerRows do
			local visible = query == "" or matching[player] == true
			playerRow.Frame.Visible = visible
			if visible then
				shown += 1
			end
			if player ~= localPlayer then
				others += 1
			end
		end
		if shown == 0 then
			emptyNote.Text = string.format('Nobody here matches "%s".', query)
		elseif query == "" and others == 0 then
			emptyNote.Text = "You're the only one in this server. Other players show up here when they join."
		else
			emptyNote.Text = ""
		end
		emptyNote.Visible = emptyNote.Text ~= ""
	end

	local function pickFromBox()
		local query = string.match(findBox.Text, "^%s*(.-)%s*$") or ""
		if query == "" then
			notify("Type a player's name first.", "Error")
			return
		end
		local found = matchPlayers(query)
		if #found == 1 then
			findBox.Text = ""
			selectTarget(found[1])
			notify("Target: " .. (if found[1] == localPlayer then "you" else found[1].DisplayName) .. ".", "Info")
		elseif #found == 0 then
			notify(string.format('There is no player called "%s" in this server.', query), "Error")
		else
			notify(string.format('%d players match "%s"; type a bit more.', #found, query), "Error")
		end
	end
	findButton.Activated:Connect(pickFromBox)
	findBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			pickFromBox()
		end
	end)
	findBox:GetPropertyChangedSignal("Text"):Connect(applyFilter)

	local function addPlayerRow(player: Player)
		if playerRows[player] then
			return
		end
		local isMe = player == localPlayer
		local playerRow = row(playerList, if isMe then 0 else 1, {
			Name = player.Name,
			Player = player,
			AvatarColor = if isMe then "Storm" else "Sunset",
			Title = player.DisplayName .. (if isMe then " (you)" else ""),
			Info = "@" .. player.Name,
			TitleWidth = 220,
		})
		playerRow.Select = button({ Name = "Select", Text = "Select", Color = "Sky", Width = 96, LayoutOrder = 1, Parent = playerRow.Controls, OnClick = function()
			selectTarget(player)
		end })
		if not isMe then
			button({ Name = "Goto", Text = "Go to", Color = "Rain", Width = 82, LayoutOrder = 2, Parent = playerRow.Controls, OnClick = function()
				run("Goto", nil, { Player = player })
			end })
			button({ Name = "Bring", Text = "Bring", Color = "Sunset", Width = 82, LayoutOrder = 3, Parent = playerRow.Controls, OnClick = function()
				run("Bring", nil, { Player = player })
			end })
		end
		playerRows[player] = playerRow
	end

	for _, player in Players:GetPlayers() do
		addPlayerRow(player)
	end
	applyFilter()
	Players.PlayerAdded:Connect(function(player)
		addPlayerRow(player)
		applyFilter()
		refresh()
	end)
	Players.PlayerRemoving:Connect(function(player)
		local playerRow = playerRows[player]
		playerRows[player] = nil
		if playerRow then
			playerRow.Frame:Destroy()
		end
		applyFilter()
		if target == player then
			notify(player.DisplayName .. " left; the admin panel targets you again.", "Info")
			selectTarget(nil)
		end
	end)

	---------------------------------------------------------------------
	-- Tabs and refresh
	---------------------------------------------------------------------
	tabs = UI.Tabs({
		Tabs = {
			{ Key = "Me", Text = "Me" },
			{ Key = "Pets", Text = "Pets" },
			{ Key = "World", Text = "World" },
			{ Key = "Players", Text = "Players" },
		},
		TabWidth = 104,
		Size = UDim2.new(0, 0, 0, 46),
		Parent = content,
		OnSelect = function(key)
			for pageKey, pageFrame in pages do
				pageFrame.Visible = pageKey == key
			end
			if key == "Pets" then
				buildGrid()
			end
			if refresh then
				refresh()
			end
		end,
	})

	function refresh()
		local info = summary()
		local who = targetName()
		paintChip()

		-- Me
		if info then
			voltsRow.Info.Text = "Now: " .. Format.Number(info.Volts or 0)
			local capacity = if Formulas.HasInfiniteTank(info) then "∞" else Format.Number(info.Capacity or 0)
			energyRow.Info.Text = string.format("%s / %s energy", Format.Number(math.floor(info.Energy or 0)), capacity)
			shiftsRow.Info.Text = "Now: " .. tostring(info.Rebirths or 0)
			for upgradeId, upgradeRow in upgradeRows do
				local level = info.Upgrades and info.Upgrades[upgradeId] or 1
				upgradeRow.Info.Text = string.format("Lv %d / %d", level, GameConfig.Upgrades[upgradeId].MaxLevel)
			end
			for boostName, boostRow in boostRows do
				local remaining = info.Boosts and info.Boosts[boostName] or 0
				boostRow.Info.Text = if remaining > 0 then timeLeft(remaining) else "Off"
				boostRow.Info.TextColor3 = if remaining > 0 then Theme.Up else Theme.InkSoft
			end
		else
			for _, label in { voltsRow.Info, energyRow.Info, shiftsRow.Info } do
				label.Text = "Loading..."
			end
		end
		for key, passButton in passButtons do
			UI.SetButtonColor(passButton, if passOwned(key) then "Leaf" else "Ink")
		end

		-- Pets
		if info then
			petCountInfo.Text = string.format("%s %s %d / %d pets", who, if target then "has" else "have", info.Pets or 0, GameConfig.Pets.MaxStorage)
		end
		UI.SetButtonText(giveButton, if target then "Give to " .. target.DisplayName else "Give Pets")

		-- World
		local unlocked = info and info.Zone or 1
		for zoneId, zoneRow in zoneRows do
			local zone = Zones[zoneId]
			local open = zoneId <= unlocked
			zoneRow.Info.Text = (if open then "Unlocked" else "Locked") .. "  •  " .. Format.Number(zone.MinPower) .. " Power"
			zoneRow.Info.TextColor3 = if open then Theme.Up else Theme.InkSoft
			zoneRow.Card.BackgroundColor3 = if open then Theme.Cloud else Theme.Mist
			if zoneId > unlocked then
				UI.SetButtonText(zoneRow.Unlock, "Unlock")
				UI.SetButtonColor(zoneRow.Unlock, "Leaf")
			elseif zoneId > 1 then
				UI.SetButtonText(zoneRow.Unlock, "Relock")
				UI.SetButtonColor(zoneRow.Unlock, "Sunset")
			else
				UI.SetButtonText(zoneRow.Unlock, "Always")
				UI.SetButtonColor(zoneRow.Unlock, "Off")
			end
			UI.SetButtonColor(zoneRow.Go, if open then "Sky" else "Off")
		end
		for _, goButton in goButtons do
			UI.SetButtonText(goButton, if target then "Send" else "Go")
		end

		-- Players
		local subject = target or localPlayer
		infoAvatar.Set(subject, if target then "Sunset" else "Storm")
		infoTitle.Text = subject.DisplayName .. "  (@" .. subject.Name .. ")" .. (if target then "" else "  •  you")
		if info then
			local zone = Zones.Get(info.Zone or 1)
			local passCount = 0
			for _ in info.Passes or {} do
				passCount += 1
			end
			local shifts, pets = info.Rebirths or 0, info.Pets or 0
			infoText.Text = string.format(
				"⚡ %s Volts   •   🌀 %d Shift%s   •   🐾 %d pet%s\n%s %s   •   %d gamepass%s",
				Format.Number(info.Volts or 0),
				shifts,
				if shifts == 1 then "" else "s",
				pets,
				if pets == 1 then "" else "s",
				zone and zone.Icon or "",
				zone and zone.Name or "?",
				passCount,
				if passCount == 1 then "" else "es"
			)
		else
			infoText.Text = "Asking the server..."
		end
		for player, playerRow in playerRows do
			local selected = player == subject
			UI.SetButtonText(playerRow.Select, if selected then "Target" else "Select")
			UI.SetButtonColor(playerRow.Select, if selected then "Leaf" else "Sky")
			playerRow.Card.BackgroundColor3 = if selected then SETS.Leaf.Tint else Theme.Cloud
		end
	end

	paintChip()
	tabs.Select("Me")
	Registry.DataController.ObserveMany({ "Volts", "Energy", "TankValue", "Upgrades", "Rebirths", "Zone", "Pets", "Passes", "Boosts" }, function()
		if not target then
			refresh()
		end
	end)
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(1)
			tick += 1
			if window.Frame.Visible then
				if target and tick % 6 == 0 then
					run("Inspect", nil, { Silent = true }) -- another player's numbers come from the server
				else
					refresh() -- boost timers
				end
			end
		end
	end)

	return {
		Window = window,
		OnOpen = function(tab: string?)
			if type(tab) == "string" and pages[tab] then
				tabs.Select(tab)
			end
			refresh()
		end,
	}
end

return Admin
