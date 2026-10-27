--!nonstrict
-- Trade panel: swap pets with another player in this server (the server side is TradeService).
--   lobby   the other players, each with "Send request" (or Accept when they asked you first)
--   trade   both offers side by side (up to GameConfig.Trading.MaxPets pets each), your pets underneath
--           (tap to offer, tap an offered pet to take it back), Cancel and Ready; when both are ready a
--           short countdown runs and any change resets Ready on both sides
-- Incoming requests also show as cards over the HUD (Accept / Decline, they expire), and the HUD's Trade
-- button gets a badge while one is waiting. The server checks everything again; this is only the view.
-- Closing the window (or opening another panel, like an egg) cancels the open trade.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Pets = require(Shared.Config.Pets)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI)
local Theme = require(script.Parent.Parent.Theme)
local Icons = require(script.Parent.Parent.Icons)
local Viewport = require(script.Parent.Parent.Viewport)

local TradePanel = {}

local INK = Theme.Ink
local WHITE = Color3.new(1, 1, 1)
local SETS = Theme.Sets
local CONFIG = GameConfig.Trading
local MAX_CARDS = 3

local localPlayer = Players.LocalPlayer

-- Two layouts: side by side on wide screens, stacked on portrait phones (decided when the panel is built)
local WIDE = {
	Window = Vector2.new(820, 588),
	Box = Vector2.new(387, 278), -- one offer box
	Their = UDim2.fromOffset(399, 0),
	StripY = 288,
	StripHeight = 142,
	Columns = 2, -- lobby rows per line
}
local TALL = {
	Window = Vector2.new(520, 904),
	Box = Vector2.new(486, 278),
	Their = UDim2.fromOffset(0, 288),
	StripY = 576,
	StripHeight = 172,
	Columns = 1,
}
local TILE = Vector2.new(86, 108)
local FOOTER = 58

local function create(className: string, props)
	return UI.Create(className, props)
end

local function frame(props)
	props.BorderSizePixel = 0
	if props.BackgroundColor3 == nil then
		props.BackgroundColor3 = WHITE
	end
	return create("Frame", props)
end

local function notify(text: string, kind: string?)
	Registry.InterfaceController.Notify(text, kind)
end

-- Remotes.TradeAction:InvokeServer, showing the server's refusal as a toast
local function call(action: string, ...)
	local ok, result = pcall(Remotes.TradeAction.InvokeServer, Remotes.TradeAction, action, ...)
	if not ok or type(result) ~= "table" then
		return nil
	end
	if result.Ok == false and type(result.Error) == "string" and action ~= "State" then
		notify(result.Error, "Error")
	end
	return result
end

-- A round avatar: the player's initial on a candy disc, covered by their Roblox headshot (rbxthumb needs
-- no web call; test players with a negative UserId keep the initial). Returns the disc and Set(userId, name).
local function avatar(parent: Instance, size: number, position: UDim2, anchor: Vector2?, z: number?)
	local disc = frame({
		Name = "Avatar",
		Size = UDim2.fromOffset(size, size),
		Position = position,
		AnchorPoint = anchor or Vector2.new(0, 0.5),
		ZIndex = z or 2,
		Parent = parent,
		UI.Round(),
		UI.Gradient(SETS.Storm.Top, SETS.Storm.Bottom),
	})
	local letter = UI.Text({
		Name = "Letter",
		Text = "",
		TextSize = math.floor(size * 0.5),
		Stroke = SETS.Storm.Stroke,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, 1),
		ZIndex = (z or 2) + 1,
		Parent = disc,
	})
	local photo = create("ImageLabel", {
		Name = "Photo",
		BackgroundTransparency = 1,
		Image = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = (z or 2) + 2,
		Parent = disc,
		UI.Round(),
	})
	UI.Stroke(2, INK).Parent = disc
	local function set(userId: number, name: string)
		letter.Text = string.upper(string.sub(name, 1, 1))
		photo.Image = if userId > 0 then string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId) else ""
	end
	return disc, set
end

-- A pill with white text (READY / NOT READY)
local function pill(parent: Instance, props)
	local holder = frame({
		Name = props.Name,
		BackgroundColor3 = INK,
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		ZIndex = 3,
		Parent = parent,
		UI.Round(),
	})
	local face = frame({ Name = "Face", Size = UDim2.new(1, -4, 1, -4), Position = UDim2.fromOffset(2, 2), ZIndex = 3, Parent = holder, UI.Round() })
	local gradient = UI.Gradient(WHITE, WHITE)
	gradient.Parent = face
	local label = UI.Text({ Name = "Text", Text = "", TextSize = 14, Scaled = true, Stroke = INK, StrokeThickness = 1.5, Size = UDim2.new(1, -12, 1, -6), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 4, Parent = holder })
	local function set(text: string, setName: string)
		local colors = SETS[setName] or SETS.Off
		label.Text = text
		gradient.Color = ColorSequence.new(colors.Top, colors.Bottom)
		holder.BackgroundColor3 = if setName == "Off" then colors.Lip else INK
		local stroke = label:FindFirstChild("TextStroke")
		if stroke then
			stroke.Color = colors.Stroke
		end
	end
	return holder, set
end

local function tierOf(pet): string
	return Pets.TierOf(pet)
end

-- A pet tile: name, rarity, the pet on its rarity pedestal with the bonus, the tier badge
local function petTile(pet, props)
	local def = Pets.Pets[pet.Id] or Pets.Pets.Puffling
	local rarity = Pets.Rarities[def.Rarity]
	local tier = tierOf(pet)
	local tile = UI.Tile({
		Name = props.Name or pet.Uid,
		Title = def.Name,
		Rarity = rarity,
		RarityText = Format.Bonus(Formulas.PetBonus(pet.Id, tier)),
		Size = UDim2.fromOffset(TILE.X, TILE.Y),
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 3,
		Parent = props.Parent,
		OnClick = props.OnClick,
	})
	local z = tile.Frame.ZIndex
	tile.Title.Position = UDim2.new(0.5, 0, 0, 7)
	local colors = Theme.Rarity(rarity.Color)
	UI.Text({
		Name = "RarityName",
		Text = rarity.Name,
		Font = Theme.BodyFont,
		TextSize = 10,
		Scaled = true,
		MinTextSize = 7,
		Color = Theme.Shade(colors.Bottom, 0.7),
		Size = UDim2.new(1, -12, 0, 11),
		Position = UDim2.new(0.5, 0, 0, 25),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = z + 4,
		Parent = tile.Lift,
	})
	tile.Art.Position = UDim2.new(0.5, 0, 0, 36)
	tile.Art.Size = UDim2.fromScale(0.7, 0.5)
	local view = Viewport.Pet(pet.Id, tier, {
		Parent = tile.Art,
		Size = UDim2.fromScale(1.2, 1.2),
		Position = UDim2.fromScale(0.5, 0.56),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = z + 3,
	})
	if tier == "Golden" then
		UI.Gradient(SETS.Bolt.Tint, SETS.Bolt.Tint2).Parent = tile.Body
	elseif tier == "Rainbow" then
		UI.Gradient(SETS.Storm.Tint, SETS.Pink.Tint2).Parent = tile.Body
	end
	if tier ~= "Normal" then
		Icons.New(if tier == "Golden" then "Star" else "Rainbow", {
			Name = tier,
			Size = UDim2.fromOffset(24, 24),
			Position = UDim2.new(1, 5, 0, -6),
			AnchorPoint = Vector2.new(1, 0),
			ZIndex = z + 6,
			Parent = tile.Lift,
		})
	end
	tile.View = view
	return tile
end

local function describePet(pet): string
	local tier = tierOf(pet)
	local def = Pets.Pets[pet.Id]
	local rarity = def and Pets.Rarities[def.Rarity]
	return string.format(
		"%s  •  %s%s  •  %s Energy",
		Pets.DisplayName(pet.Id, tier),
		rarity and rarity.Name or "?",
		if tier ~= "Normal" then " " .. tier else "",
		Format.Bonus(Formulas.PetBonus(pet.Id, tier))
	)
end

function TradePanel.Build()
	local interface = Registry.InterfaceController
	local rootSize = interface.PanelRoot and interface.PanelRoot.AbsoluteSize or Vector2.new(1280, 720)
	local L = if rootSize.X > 0 and rootSize.Y > rootSize.X then TALL else WIDE

	local window = UI.Window({
		Name = "Trade",
		Title = "Trade",
		Icon = "🔄",
		Size = UDim2.fromOffset(L.Window.X, L.Window.Y),
		Padding = { 20, 16, 18 },
	})
	local content = window.Content

	local state = {
		Trade = nil, -- the server's view of the open trade (TradeService view())
		CountdownEnd = 0, -- os.clock() when the countdown ends
		Incoming = {}, -- [UserId] = { From, Name, DisplayName, Ends (os.clock) }
		Outgoing = {}, -- [UserId] = os.clock() when our request expires
		ClosingForServer = false,
	}

	---------------------------------------------------------------------
	-- Lobby: the other players
	---------------------------------------------------------------------
	local lobby = frame({ Name = "Lobby", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = content })
	UI.Text({
		Name = "Intro",
		Text = "Pick a player in this server to swap pets with!",
		Font = Theme.BodyFont,
		TextSize = 16,
		Scaled = true,
		MinTextSize = 10,
		Color = Theme.InkSoft,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -8, 0, 22),
		Position = UDim2.fromOffset(4, 0),
		Parent = lobby,
	})
	local list = UI.Scroll({
		Name = "Players",
		Size = UDim2.new(1, 0, 1, -32 - 78),
		Position = UDim2.fromOffset(0, 32),
		Parent = lobby,
		UI.Grid(if L.Columns == 2 then UDim2.new(0.5, -6, 0, 76) else UDim2.new(1, -4, 0, 76), UDim2.fromOffset(8, 8)),
		UI.Padding(4, 6, 4, 2),
	})
	local emptyLobby = frame({
		Name = "Empty",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -40, 0, 190),
		Position = UDim2.new(0.5, 0, 0.4, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		Parent = lobby,
	})
	Icons.New("Trade", { Name = "Icon", Size = UDim2.fromOffset(84, 84), Position = UDim2.new(0.5, 0, 0, 42), Transparency = 0.35, Parent = emptyLobby })
	UI.Text({ Name = "Title", Text = "No one to trade with yet", TextSize = 26, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 94), Parent = emptyLobby })
	UI.Text({
		Name = "Text",
		Text = "Invite your friends to this server and swap pets with them!",
		Font = Theme.BodyFont,
		TextSize = 15,
		Wrapped = true,
		Color = Theme.InkSoft,
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.fromOffset(0, 130),
		Parent = emptyLobby,
	})
	local tip = frame({
		Name = "Tip",
		BackgroundColor3 = SETS.Sky.Tint,
		Size = UDim2.new(1, -4, 0, 68),
		Position = UDim2.new(0, 2, 1, -2),
		AnchorPoint = Vector2.new(0, 1),
		Parent = lobby,
		UI.Corner(14),
		UI.Stroke(2, SETS.Sky.Tint2),
	})
	Icons.New("Lock", { Name = "Icon", Size = UDim2.fromOffset(40, 40), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = tip })
	local tipText = UI.Text({
		Name = "Text",
		Text = string.format(
			"Safe trades: both players press Ready, then the pets swap after a %d-second countdown. Any change resets Ready.",
			CONFIG.Countdown
		),
		Font = Theme.BodyFont,
		TextSize = 14,
		Scaled = true,
		MinTextSize = 9,
		Wrapped = true,
		Color = Theme.InkSoft,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -72, 1, -12),
		Position = UDim2.new(0, 60, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = tip,
	})

	local rows = {} -- [Player] = row
	local respond, sendRequest

	local function rowStatus(other: Player)
		local userId = other.UserId
		if state.Incoming[userId] then
			return "Accept", "Leaf", true
		end
		local outgoing = state.Outgoing[userId]
		if outgoing and outgoing > os.clock() then
			return "Sent!", "Off", false
		end
		if other:GetAttribute("Trading") then
			return "Trading...", "Off", false
		end
		if other:GetAttribute("TradesOff") then
			return "Trades off", "Off", false
		end
		return "Send request", "Sky", true
	end

	local function buildRow(other: Player)
		local holder = frame({ Name = other.Name, BackgroundTransparency = 1, Parent = list })
		local card = UI.CloudCard({ Name = "Card", Size = UDim2.new(1, -4, 1, -4), Position = UDim2.fromOffset(2, 2), Parent = holder })
		local _, setAvatar = avatar(card, 52, UDim2.new(0, 9, 0.5, 0))
		setAvatar(other.UserId, other.DisplayName)
		local nameLabel = UI.Text({
			Name = "Title",
			Text = other.DisplayName,
			TextSize = 20,
			Scaled = true,
			MinTextSize = 11,
			X = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -228, 0, 24),
			Position = UDim2.new(0, 72, 0.5, -20),
			Parent = card,
		})
		UI.Text({
			Name = "Handle",
			Text = "@" .. other.Name,
			Font = Theme.BodyFont,
			TextSize = 13,
			Scaled = true,
			MinTextSize = 9,
			Color = Theme.InkSoft,
			X = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -228, 0, 16),
			Position = UDim2.new(0, 72, 0.5, 6),
			Parent = card,
		})
		local button = UI.Button({
			Name = "Action",
			Text = "Send request",
			Color = "Sky",
			TextSize = 16,
			Small = true,
			Size = UDim2.fromOffset(142, 44),
			Position = UDim2.new(1, -10, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Parent = card,
			OnClick = function()
				local _, _, enabled = rowStatus(other)
				if not enabled then
					return
				end
				if state.Incoming[other.UserId] then
					respond(other.UserId, true)
				else
					sendRequest(other)
				end
			end,
		})
		local row = { Frame = holder, Button = button, Name = nameLabel }
		function row.Refresh()
			local text, color = rowStatus(other)
			UI.SetButtonText(button, text)
			UI.SetButtonColor(button, color)
		end
		row.Refresh()
		return row
	end

	local function refreshLobby()
		local seen = {}
		local others = {}
		for _, other in Players:GetPlayers() do
			if other ~= localPlayer then
				table.insert(others, other)
			end
		end
		-- players asking you first, then by name
		table.sort(others, function(a, b)
			local askA, askB = state.Incoming[a.UserId] ~= nil, state.Incoming[b.UserId] ~= nil
			if askA ~= askB then
				return askA
			end
			return string.lower(a.DisplayName) < string.lower(b.DisplayName)
		end)
		for order, other in others do
			seen[other] = true
			local row = rows[other]
			if not row then
				row = buildRow(other)
				rows[other] = row
			end
			row.Frame.LayoutOrder = order
			row.Refresh()
		end
		for other, row in rows do
			if not seen[other] then
				row.Frame:Destroy()
				rows[other] = nil
			end
		end
		emptyLobby.Visible = #others == 0
		local data = Registry.DataController.Data
		if data and data.Settings and data.Settings.AllowTrades == false then
			tipText.Text = "Your trade requests are off (Settings). You can still send requests."
		else
			tipText.Text = string.format(
				"Safe trades: both players press Ready, then the pets swap after a %d-second countdown. Any change resets Ready.",
				CONFIG.Countdown
			)
		end
	end

	---------------------------------------------------------------------
	-- Trade: the two offers, your pets, Cancel / Ready
	---------------------------------------------------------------------
	local tradePage = frame({ Name = "TradePage", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = content })

	local function offerBox(name: string, position: UDim2)
		local box = UI.CloudCard({
			Name = name,
			Size = UDim2.fromOffset(L.Box.X, L.Box.Y),
			Position = position,
			Top = Theme.Cloud,
			Bottom = Theme.Mist,
			StrokeColor = Theme.HazeDeep,
			Parent = tradePage,
		})
		local _, setAvatar = avatar(box, 32, UDim2.fromOffset(10, 22))
		local title = UI.Text({
			Name = "Title",
			Text = "",
			TextSize = 19,
			Scaled = true,
			MinTextSize = 11,
			X = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -200, 0, 22),
			Position = UDim2.fromOffset(50, 11),
			ZIndex = 2,
			Parent = box,
		})
		local count = UI.Text({
			Name = "Count",
			Text = "",
			Font = Theme.BodyFont,
			TextSize = 13,
			Color = Theme.InkSoft,
			X = Enum.TextXAlignment.Right,
			Size = UDim2.fromOffset(40, 18),
			Position = UDim2.new(1, -128, 0, 14),
			AnchorPoint = Vector2.new(1, 0),
			ZIndex = 2,
			Parent = box,
		})
		local _, setReady = pill(box, { Name = "Ready", Size = UDim2.fromOffset(112, 28), Position = UDim2.new(1, -10, 0, 9), AnchorPoint = Vector2.new(1, 0) })
		local grid = frame({
			Name = "Grid",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(4 * TILE.X + 3 * 8, 2 * TILE.Y + 8),
			Position = UDim2.new(0.5, 0, 0, 48),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = box,
			UI.Grid(UDim2.fromOffset(TILE.X, TILE.Y), UDim2.fromOffset(8, 8)),
		})
		-- empty slots behind the tiles
		local slots = frame({
			Name = "Slots",
			BackgroundTransparency = 1,
			Size = grid.Size,
			Position = grid.Position,
			AnchorPoint = grid.AnchorPoint,
			Parent = box,
			UI.Grid(UDim2.fromOffset(TILE.X, TILE.Y), UDim2.fromOffset(8, 8)),
		})
		for index = 1, CONFIG.MaxPets do
			frame({
				Name = "Slot" .. index,
				BackgroundColor3 = Theme.Mist,
				BackgroundTransparency = 0.1,
				LayoutOrder = index,
				Parent = slots,
				UI.Corner(16),
				UI.Stroke(2, Theme.Haze),
			})
		end
		local hint = UI.Text({
			Name = "Hint",
			Text = "",
			TextSize = 18,
			Wrapped = true,
			Scaled = true,
			MinTextSize = 11,
			Color = Theme.InkSoft,
			Size = UDim2.new(1, -60, 0, 50),
			Position = UDim2.new(0.5, 0, 0, 48 + TILE.Y + 4),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 6,
			Parent = box,
		})
		return { Frame = box, Title = title, Count = count, SetReady = setReady, SetAvatar = setAvatar, Grid = grid, Hint = hint, Tiles = {} }
	end

	local mine = offerBox("Mine", UDim2.fromOffset(0, 0))
	local theirs = offerBox("Theirs", L.Their)

	-- Your pets: a strip you scroll sideways
	local strip = frame({
		Name = "Inventory",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, L.StripHeight),
		Position = UDim2.fromOffset(0, L.StripY),
		Parent = tradePage,
	})
	local stripTitle = UI.Text({
		Name = "Title",
		Text = "Your pets: tap one to offer it",
		TextSize = 17,
		Scaled = true,
		MinTextSize = 11,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -8, 0, 20),
		Position = UDim2.fromOffset(4, 0),
		Parent = strip,
	})
	local stripWell = frame({
		Name = "Well",
		BackgroundColor3 = Theme.Haze,
		BackgroundTransparency = 0.45,
		Size = UDim2.new(1, 0, 1, -24),
		Position = UDim2.fromOffset(0, 24),
		Parent = strip,
		UI.Corner(16),
	})
	local inventory = UI.Scroll({
		Name = "Pets",
		Size = UDim2.new(1, -8, 1, -4),
		Position = UDim2.fromOffset(4, 2),
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		Parent = stripWell,
		UI.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
		UI.Padding(6, 6, 0, 4),
	})
	local noPets = UI.Text({
		Name = "NoPets",
		Text = "You have no pets to trade yet. Hatch some eggs!",
		Font = Theme.BodyFont,
		TextSize = 15,
		Color = Theme.InkSoft,
		Size = UDim2.new(1, -20, 1, 0),
		Visible = false,
		Parent = stripWell,
	})

	-- Footer: Cancel, the status / countdown, Ready
	local footer = frame({
		Name = "Footer",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, FOOTER),
		Position = UDim2.new(0, 0, 1, 0),
		AnchorPoint = Vector2.new(0, 1),
		Parent = tradePage,
	})
	local buttonWidth = if L == TALL then 132 else 160
	UI.Button({
		Name = "Cancel",
		Text = "Cancel",
		Color = "Coral",
		TextSize = 20,
		Size = UDim2.fromOffset(buttonWidth, 54),
		Position = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 1),
		Parent = footer,
		OnClick = function()
			interface.ClosePanel() -- closing the window cancels the trade
		end,
	})
	local status = UI.Text({
		Name = "Status",
		Text = "",
		TextSize = 18,
		Scaled = true,
		MinTextSize = 10,
		Wrapped = true,
		Color = Theme.InkSoft,
		Size = UDim2.new(1, -2 * buttonWidth - 28, 0, 44),
		Position = UDim2.new(0.5, 0, 0.5, -2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = footer,
	})
	local countdownBar = UI.ProgressBar({
		Name = "Countdown",
		Color = "Bolt",
		Size = UDim2.new(1, -2 * buttonWidth - 28, 0, 40),
		Position = UDim2.new(0.5, 0, 0.5, -2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 19,
		Parent = footer,
	})
	countdownBar.Frame.Visible = false
	local readyButton = UI.Button({
		Name = "Ready",
		Text = "Ready",
		Icon = "Check",
		Color = "Leaf",
		TextSize = 20,
		Size = UDim2.fromOffset(buttonWidth, 54),
		Position = UDim2.fromScale(1, 1),
		AnchorPoint = Vector2.new(1, 1),
		Parent = footer,
		OnClick = function()
			local trade = state.Trade
			if trade then
				task.spawn(call, "Ready", not trade.Mine.Ready)
			end
		end,
	})

	local inventoryTiles = {} -- [uid] = { Tile, Key }

	local function offeredSet()
		local set = {}
		local trade = state.Trade
		if trade then
			for _, pet in trade.Mine.Pets do
				set[pet.Uid] = true
			end
		end
		return set
	end

	local function addPet(pet)
		local trade = state.Trade
		if not trade then
			return
		end
		if trade.State == "Countdown" then
			-- allowed (it stops the countdown), but say so
			notify("Changing the trade resets Ready for both of you.", "Warning")
		end
		if #trade.Mine.Pets >= (trade.Max or CONFIG.MaxPets) then
			notify(string.format("You can trade up to %d pets at once.", trade.Max or CONFIG.MaxPets), "Error")
			return
		end
		local wasEquipped = pet.Equipped
		task.spawn(function()
			local result = call("Add", pet.Uid)
			if result and result.Ok and wasEquipped then
				notify(Pets.DisplayName(pet.Id, tierOf(pet)) .. " was unequipped for the trade.", "Info")
			end
		end)
	end

	local function removePet(uid: string)
		local trade = state.Trade
		if trade and trade.State == "Countdown" then
			notify("Changing the trade resets Ready for both of you.", "Warning")
		end
		task.spawn(call, "Remove", uid)
	end

	local function fillOffer(box, pets, isMine: boolean)
		for _, tile in box.Tiles do
			tile.Frame:Destroy()
		end
		table.clear(box.Tiles)
		for order, pet in pets do
			local tile = petTile(pet, {
				Name = pet.Uid,
				LayoutOrder = order,
				Parent = box.Grid,
				OnClick = function()
					if isMine then
						removePet(pet.Uid)
					else
						notify(describePet(pet), "Info")
					end
				end,
			})
			if isMine then
				-- a small ✕ says "tap to take it back"
				Icons.New("Close", {
					Name = "Remove",
					Size = UDim2.fromOffset(22, 22),
					Position = UDim2.fromOffset(-6, -6),
					AnchorPoint = Vector2.zero,
					ZIndex = tile.Frame.ZIndex + 7,
					Parent = tile.Lift,
				})
			end
			table.insert(box.Tiles, tile)
		end
	end

	local function refreshInventory()
		local data = Registry.DataController.Data
		local trade = state.Trade
		if not data or not trade then
			return
		end
		local offered = offeredSet()
		local sorted = table.clone(data.Pets)
		table.sort(sorted, function(a, b)
			local bonusA = Formulas.PetBonus(a.Id, tierOf(a))
			local bonusB = Formulas.PetBonus(b.Id, tierOf(b))
			if bonusA ~= bonusB then
				return bonusA > bonusB
			end
			return a.Uid < b.Uid
		end)
		local seen = {}
		local shown = 0
		for _, pet in sorted do
			if not offered[pet.Uid] then
				shown += 1
				seen[pet.Uid] = true
				local key = pet.Id .. ":" .. tierOf(pet)
				local entry = inventoryTiles[pet.Uid]
				if entry and entry.Key ~= key then
					entry.Tile.Frame:Destroy()
					entry = nil
				end
				if not entry then
					local uid = pet.Uid
					local tile = petTile(pet, {
						Name = uid,
						Parent = inventory,
						OnClick = function()
							local current = Registry.DataController.Data
							for _, candidate in current and current.Pets or {} do
								if candidate.Uid == uid then
									addPet(candidate)
									return
								end
							end
						end,
					})
					local equipped = Icons.New("Check", {
						Name = "Equipped",
						Size = UDim2.fromOffset(24, 24),
						Position = UDim2.fromOffset(-6, -6),
						AnchorPoint = Vector2.zero,
						ZIndex = tile.Frame.ZIndex + 6,
						Parent = tile.Lift,
					})
					entry = { Tile = tile, Key = key, Equipped = equipped }
					inventoryTiles[uid] = entry
				end
				entry.Tile.Frame.LayoutOrder = shown
				entry.Equipped.Visible = pet.Equipped == true
			end
		end
		for uid, entry in inventoryTiles do
			if not seen[uid] then
				entry.Tile.Frame:Destroy()
				inventoryTiles[uid] = nil
			end
		end
		noPets.Visible = shown == 0
		noPets.Text = if #data.Pets == 0 then "You have no pets to trade yet. Hatch some eggs!" else "All your pets are in the trade."
		stripTitle.Text = string.format("Your pets (%d): tap one to offer it", shown)
	end

	local function setStatus(text: string, color: Color3?)
		status.Text = text
		status.TextColor3 = color or Theme.InkSoft
	end

	local function refreshTrade()
		local trade = state.Trade
		if not trade then
			return
		end
		local partner = trade.Partner
		window.SetTitle("Trading with " .. partner.DisplayName)
		mine.Title.Text = "Your offer"
		theirs.Title.Text = partner.DisplayName .. "'s offer"
		mine.SetAvatar(localPlayer.UserId, localPlayer.DisplayName)
		theirs.SetAvatar(partner.UserId, partner.DisplayName)
		local max = trade.Max or CONFIG.MaxPets
		mine.Count.Text = #trade.Mine.Pets .. "/" .. max
		theirs.Count.Text = #trade.Theirs.Pets .. "/" .. max
		mine.SetReady(if trade.Mine.Ready then "READY" else "NOT READY", if trade.Mine.Ready then "Leaf" else "Off")
		theirs.SetReady(if trade.Theirs.Ready then "READY" else "NOT READY", if trade.Theirs.Ready then "Leaf" else "Off")
		mine.Frame.Outline.Color = if trade.Mine.Ready then SETS.Leaf.Bottom else Theme.HazeDeep
		theirs.Frame.Outline.Color = if trade.Theirs.Ready then SETS.Leaf.Bottom else Theme.HazeDeep
		mine.Frame.Outline.Thickness = if trade.Mine.Ready then 3 else 2
		theirs.Frame.Outline.Thickness = if trade.Theirs.Ready then 3 else 2
		fillOffer(mine, trade.Mine.Pets, true)
		fillOffer(theirs, trade.Theirs.Pets, false)
		mine.Hint.Text = if #trade.Mine.Pets == 0 then "Tap your pets below to add them" else ""
		theirs.Hint.Text = if #trade.Theirs.Pets == 0 then "Waiting for " .. partner.DisplayName .. " to add pets..." else ""
		refreshInventory()

		local counting = trade.State == "Countdown"
		countdownBar.Frame.Visible = counting
		status.Visible = not counting
		if counting then
			UI.SetButtonText(readyButton, "Unready")
			UI.SetButtonColor(readyButton, "Sunset")
			UI.SetButtonIcon(readyButton, nil)
		elseif trade.Mine.Ready then
			UI.SetButtonText(readyButton, "Unready")
			UI.SetButtonColor(readyButton, "Off")
			UI.SetButtonIcon(readyButton, nil)
			setStatus("Waiting for " .. partner.DisplayName .. " to press Ready...")
		else
			UI.SetButtonText(readyButton, "Ready")
			UI.SetButtonColor(readyButton, "Leaf")
			UI.SetButtonIcon(readyButton, "Check")
			if trade.Theirs.Ready then
				setStatus(partner.DisplayName .. " is ready! Check the offer, then press Ready.", SETS.Leaf.Lip)
			elseif #trade.Mine.Pets == 0 and #trade.Theirs.Pets == 0 then
				setStatus("Add pets, then both press Ready")
			else
				setStatus("Both press Ready to trade")
			end
		end
	end

	local function stepCountdown()
		local trade = state.Trade
		if not trade or trade.State ~= "Countdown" then
			return
		end
		local total = math.max(CONFIG.Countdown, 0.1)
		local left = math.max(0, state.CountdownEnd - os.clock())
		countdownBar.Set(1 - left / total, if left > 0 then string.format("Trading in %d...", math.ceil(left)) else "Trading...")
	end

	local function showPage()
		local trading = state.Trade ~= nil
		lobby.Visible = not trading
		tradePage.Visible = trading
		if trading then
			refreshTrade()
		else
			window.SetTitle("Trade")
			refreshLobby()
		end
	end

	---------------------------------------------------------------------
	-- Request cards over the HUD
	---------------------------------------------------------------------
	local cardHolder = frame({
		Name = "TradeRequests",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(430, 3 * 132),
		Position = UDim2.new(0.5, 0, 0, 140),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 20,
		Parent = interface.OverlayRoot,
		UI.List(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top),
	})
	local cards = {} -- [UserId] = { Frame, Bar }

	local function placeCards()
		cardHolder.Position = UDim2.new(0.5, 0, 0, (interface.SafeTop or 0) + 132)
	end

	local function updateBadge()
		local count = 0
		for _ in state.Incoming do
			count += 1
		end
		local hud = Registry.HudController
		if hud and hud.SetBadge then
			hud.SetBadge("Trade", count)
		end
	end

	local function removeCard(userId: number)
		local card = cards[userId]
		if card then
			cards[userId] = nil
			card.Frame:Destroy()
		end
	end

	local function addCard(request)
		removeCard(request.From)
		local count = 0
		for _ in cards do
			count += 1
		end
		if count >= MAX_CARDS then
			return -- still listed in the Trade panel and on the badge
		end
		local holder = frame({ Name = "Request" .. request.From, BackgroundTransparency = 1, Size = UDim2.fromOffset(430, 124), ZIndex = 20, Parent = cardHolder })
		-- shadow, Ink edge, Cloud -> Mist face
		frame({ Name = "Shadow", BackgroundColor3 = INK, BackgroundTransparency = Theme.ShadeTransparency, Size = UDim2.new(1, 0, 1, 0), Position = UDim2.fromOffset(0, 6), ZIndex = 20, Parent = holder, UI.Corner(24) })
		local body = frame({
			Name = "Body",
			Size = UDim2.new(1, -6, 1, -6),
			Position = UDim2.fromOffset(3, 3),
			ZIndex = 21,
			Parent = holder,
			UI.Corner(22),
			UI.Gradient(Theme.Cloud, Theme.Mist),
		})
		UI.Stroke(3, INK).Parent = body
		local _, setAvatar = avatar(body, 64, UDim2.new(0, 12, 0, 48), nil, 22)
		setAvatar(request.From, request.DisplayName or "?")
		Icons.New("Trade", { Name = "Icon", Size = UDim2.fromOffset(32, 32), Position = UDim2.fromOffset(62, 66), ZIndex = 26, Parent = body })
		UI.Text({
			Name = "Title",
			Text = (request.DisplayName or "Someone") .. " wants to trade!",
			TextSize = 21,
			Scaled = true,
			MinTextSize = 12,
			X = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -104, 0, 26),
			Position = UDim2.fromOffset(92, 12),
			ZIndex = 22,
			Parent = body,
		})
		UI.Button({
			Name = "Decline",
			Text = "Decline",
			Color = "Coral",
			Small = true,
			TextSize = 17,
			Size = UDim2.fromOffset(136, 44),
			Position = UDim2.fromOffset(92, 44),
			ZIndex = 22,
			Parent = body,
			OnClick = function()
				respond(request.From, false)
			end,
		})
		UI.Button({
			Name = "Accept",
			Text = "Accept",
			Icon = "Check",
			Color = "Leaf",
			Small = true,
			TextSize = 17,
			Size = UDim2.fromOffset(160, 44),
			Position = UDim2.fromOffset(236, 44),
			ZIndex = 22,
			Parent = body,
			OnClick = function()
				respond(request.From, true)
			end,
		})
		-- time left: a thin Sky bar along the bottom
		local track = frame({ Name = "Timer", BackgroundColor3 = Theme.Haze, Size = UDim2.new(1, -28, 0, 8), Position = UDim2.new(0, 14, 1, -14), ZIndex = 22, Parent = body, UI.Round() })
		local fill = frame({ Name = "Fill", Size = UDim2.fromScale(1, 1), ZIndex = 23, Parent = track, UI.Round(), UI.Gradient(SETS.Sky.Top, SETS.Sky.Bottom) })
		cards[request.From] = { Frame = holder, Bar = fill, Request = request }
		UI.Pop(holder, 0.6)
	end

	local function refreshCards()
		local now = os.clock()
		for userId, card in cards do
			local request = state.Incoming[userId]
			if not request then
				removeCard(userId)
			else
				local total = math.max(CONFIG.RequestTimeout, 1)
				card.Bar.Size = UDim2.fromScale(math.clamp((request.Ends - now) / total, 0, 1), 1)
			end
		end
	end

	local function dropIncoming(userId: number)
		state.Incoming[userId] = nil
		removeCard(userId)
		updateBadge()
		if lobby.Visible then
			refreshLobby()
		end
	end

	function respond(userId: number, accept: boolean)
		dropIncoming(userId)
		task.spawn(call, "Respond", userId, accept)
	end

	function sendRequest(other: Player)
		state.Outgoing[other.UserId] = os.clock() + CONFIG.RequestTimeout
		if rows[other] then
			rows[other].Refresh()
		end
		task.spawn(function()
			local result = call("Request", other.UserId)
			if result and result.Ok then
				if not result.Started then
					notify("Trade request sent to " .. other.DisplayName .. "!", "Success")
				end
			else
				state.Outgoing[other.UserId] = nil
			end
			if rows[other] then
				rows[other].Refresh()
			end
		end)
	end

	local function addIncoming(request)
		if type(request) ~= "table" or type(request.From) ~= "number" then
			return
		end
		request.Ends = os.clock() + (tonumber(request.Expires) or CONFIG.RequestTimeout)
		state.Incoming[request.From] = request
		if not state.Trade then
			addCard(request)
		end
		updateBadge()
		if lobby.Visible then
			refreshLobby()
		end
	end

	---------------------------------------------------------------------
	-- Server events
	---------------------------------------------------------------------
	local function setTrade(trade)
		local wasTrading = state.Trade ~= nil
		state.Trade = trade
		if trade then
			state.CountdownEnd = os.clock() + (tonumber(trade.Countdown) or 0)
			table.clear(state.Outgoing)
			for userId in state.Incoming do
				removeCard(userId)
			end
			if not interface.IsOpen("Trade") then
				interface.OpenPanel("Trade")
			end
			if not wasTrading then
				Registry.SoundController.Play("Pop")
			end
		end
		showPage()
		stepCountdown()
	end

	local function endTrade(info)
		state.Trade = nil
		if interface.IsOpen("Trade") then
			state.ClosingForServer = true
			interface.ClosePanel()
			state.ClosingForServer = false
		end
		if type(info) == "table" and info.Reason == "Completed" then
			Registry.SoundController.Play("Success", 1.1)
			local effects = Registry.EffectsController
			if effects and effects.Confetti then
				effects.Confetti(70)
			end
		end
		for _, request in state.Incoming do
			addCard(request)
		end
		showPage()
	end

	Remotes.TradeEvent.OnClientEvent:Connect(function(kind, payload)
		if kind == "Request" then
			addIncoming(payload)
			Registry.SoundController.Play("Pop", 1.2)
		elseif kind == "RequestGone" then
			if type(payload) == "table" and type(payload.From) == "number" then
				dropIncoming(payload.From)
			end
		elseif kind == "State" then
			if type(payload) == "table" and type(payload.Mine) == "table" and type(payload.Theirs) == "table" then
				setTrade(payload)
			end
		elseif kind == "Ended" then
			endTrade(payload)
		end
	end)

	-- Closing the window (X, the dim, another panel such as an egg) cancels the open trade
	interface.PanelClosed:Connect(function(name)
		if name == "Trade" and state.Trade and not state.ClosingForServer then
			task.spawn(call, "Cancel")
		end
	end)

	Players.PlayerAdded:Connect(function()
		if lobby.Visible then
			refreshLobby()
		end
	end)
	Players.PlayerRemoving:Connect(function(other)
		if state.Incoming[other.UserId] then
			dropIncoming(other.UserId)
		end
		state.Outgoing[other.UserId] = nil
		task.defer(function()
			if lobby.Visible then
				refreshLobby()
			end
		end)
	end)
	Registry.DataController.ObserveMany({ "Pets" }, function()
		if state.Trade and tradePage.Visible then
			refreshInventory()
		end
	end)
	Registry.DataController.ObserveMany({ "Settings" }, function()
		if lobby.Visible then
			refreshLobby()
		end
	end)

	local lastTick = 0
	RunService.RenderStepped:Connect(function()
		if next(cards) ~= nil then
			refreshCards()
			placeCards()
		end
		if state.Trade and window.Frame.Visible then
			stepCountdown()
		end
		-- expire requests nobody answered (the server drops them too) and refresh the lobby labels
		local now = os.clock()
		if now - lastTick > 0.5 then
			lastTick = now
			for userId, request in state.Incoming do
				if request.Ends <= now then
					dropIncoming(userId)
				end
			end
			if lobby.Visible and window.Frame.Visible then
				for _, row in rows do
					row.Refresh()
				end
			end
		end
	end)
	placeCards()

	return {
		Window = window,
		OnOpen = function()
			showPage()
			-- catch up with the server (requests that arrived before the panel existed, a trade in progress)
			task.spawn(function()
				local result = call("State")
				if not result or not result.Ok then
					return
				end
				for _, request in result.Incoming or {} do
					if not state.Incoming[request.From] then
						addIncoming(request)
					end
				end
				for _, userId in result.Outgoing or {} do
					state.Outgoing[userId] = state.Outgoing[userId] or (os.clock() + CONFIG.RequestTimeout)
				end
				if result.Trade and not state.Trade then
					setTrade(result.Trade)
				else
					showPage()
				end
			end)
		end,
	}
end

return TradePanel
