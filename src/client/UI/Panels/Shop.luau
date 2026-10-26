--!nonstrict
-- Shop panel: the featured lobby pet, gamepasses, boosts and Volts packs, drawn like the store badges
-- (assets/gamepasses, assets/products, rendered from assets/source/badge.html): every item is a big card
-- whose art is its badge (sunburst rays in the item's colour, a cel-shaded illustration with thick ink
-- outlines and a candy ribbon), with candy tags and a green price button carrying the Robux glyph.
-- A badge shows once its Monetization `Image` id is set (tools/roblox/upload_store_icons.py) and Roblox has
-- approved the picture; until then the card draws the same sunburst with the item's 3D icon on it.
-- Behaviour: owned passes say "Owned", items without an Id show "Coming soon" in live servers (Studio
-- simulates the purchase), live prices replace the configured ones, and paid random items are hidden where
-- they aren't allowed. The window takes a portrait shape (two columns) on tall screens.

local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared.Config.Monetization)
local Pets = require(Shared.Config.Pets)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)

local Registry = require(script.Parent.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI)
local Theme = require(script.Parent.Parent.Theme)
local Icons = require(script.Parent.Parent.Icons)
local Viewport = require(script.Parent.Parent.Viewport)

local Shop = {}

-- Card art uploaded by tools/roblox/upload_store_icons.py (assets/ui/shop, rendered by tools/render_art.py).
-- One entry per line, key first: the upload script writes the ids here.
local ART = {
	ShopRays = 80987168665019, -- assets/ui/shop/ShopRays.png
	Robux = 136714126841033, -- assets/ui/shop/Robux.png
}

local WHITE = Color3.new(1, 1, 1)
local INK = Theme.Ink
local player = Players.LocalPlayer

local function asset(id: number?): string?
	return if type(id) == "number" and id > 0 then "rbxassetid://" .. tostring(id) else nil
end

local RAYS = asset(ART.ShopRays) -- white sunburst rays + centre glow, 1024 x 1024
local RAYS_SIZE = 1024
local ROBUX = asset(ART.Robux) -- the Robux glyph in white; "R$" text when it isn't there (see Shop.Build)

-- The 3D icon (Icons.luau key) drawn on a card until its badge is there
local ITEM_ICONS = {
	VIP = "Star",
	DoubleVolts = "Sell",
	DoubleEnergy = "Energy",
	AutoCatch = "Power",
	RemoteSell = "Radar",
	MegaTank = "Tank",
	InfiniteTank = "Tank",
	LuckyHatcher = "Luck",
	TripleHatch = "Eggs",
	AutoHatch = "Eggs",
	PetSlots = "Pets",
	StormRadar = "Radar",
	VoltsSmall = "Volts",
	VoltsMedium = "Sell",
	VoltsLarge = "Gift",
	VoltsHuge = "Rewards",
	EnergyBoost = "Boost",
	LuckBoost = "Luck",
	SummonMegaStorm = "MegaStorm",
}

-- Sunburst colour of the products (passes have their own Color): the badges' background colours
local PRODUCT_COLORS = {
	Volts = Color3.fromHex("FFB42A"),
	EnergyBoost = Color3.fromHex("3AB8F5"),
	LuckBoost = Color3.fromHex("62D45A"),
	MegaStorm = Color3.fromHex("7C3AED"),
	Pet = Color3.fromHex("FF72C6"),
}

-- Candy ribbons on a few cards
local TAGS = {
	AutoCatch = { Text = "POPULAR", Set = "Coral" },
	VoltsHuge = { Text = "BEST VALUE", Set = "Bolt" },
}

-- The featured card's aurora backdrop (the Aurora Gryphon badge's pinks and violets)
local AURORA_TOP = Color3.fromHex("FF8AD8")
local AURORA_BOTTOM = Color3.fromHex("8A5CF0")

---------------------------------------------------------------------------
-- Layouts: Wide (landscape screens) and Tall (portrait); sizes in offset px of the window
---------------------------------------------------------------------------
local GAP = 12
local SCROLL_PAD = { Top = 20, Right = 14, Bottom = 12, Left = 8 } -- room for tags above the first row

local LAYOUTS = {
	Wide = { Window = Vector2.new(680, 590), Columns = { Passes = 3, Boosts = 3, Volts = 4 }, Featured = 228, TabWidth = 132 },
	Tall = { Window = Vector2.new(590, 1000), Columns = { Passes = 2, Boosts = 2, Volts = 2 }, Featured = 262, TabWidth = 128, Tall = true },
}

-- Portrait screens (a phone held upright, a narrow desktop window) get the Tall layout. The size is
-- measured in the panels' own units (the screen divided by the interface scale), when the shop is built.
local function chooseLayout()
	local interface = Registry.InterfaceController
	local gui = interface and interface.PanelGui
	local root = interface and interface.PanelRoot
	local size = gui and gui.AbsoluteSize
	if not size or size.X < 2 or size.Y < 2 then
		local camera = Workspace.CurrentCamera
		size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	end
	local uiScale = root and root:FindFirstChildOfClass("UIScale")
	local scale = if uiScale and uiScale.Scale > 0 then uiScale.Scale else 1
	local ok, inset = pcall(function()
		return GuiService:GetGuiInset()
	end)
	local topBar = if ok and typeof(inset) == "Vector2" then inset.Y else 58
	local width = size.X / scale
	local height = (size.Y - topBar) / scale -- below the Roblox top bar
	local layout = table.clone(if width < 900 and height > width * 1.2 then LAYOUTS.Tall else LAYOUTS.Wide)
	-- As tall as the screen allows at full size (InterfaceController fits a window with its cloud puffs and
	-- shadow, 50 px, plus a 16 px margin): a landscape phone gets a shorter window instead of a smaller one
	local tallest = math.floor(height - 66)
	layout.Window = Vector2.new(layout.Window.X, math.clamp(tallest - (if layout.Tall then 90 else 0), 470, layout.Window.Y))
	return layout
end

-- Card measurements for a card `width` px wide. Info = "Description" (3-4 lines) or "Volts" (an amount)
local function cardMetrics(width: number, info: string)
	local big = width >= 240
	local inner = width - 6 -- inside the 3 px outline
	local artWidth = inner - 14
	local m = {
		Width = width,
		Inner = inner,
		ArtX = 7,
		ArtWidth = artWidth,
		ArtHeight = math.floor(artWidth * 0.9 + 0.5), -- the badge cropped a little at the top and bottom
		Name = if big then 26 elseif width < 170 then 20 else 23,
		NameSize = if big then 25 elseif width < 170 then 19 else 21,
		Button = if big then 54 elseif width < 170 then 42 else 46,
		Info = info,
	}
	if info == "Volts" then
		m.InfoSize = if big then 26 elseif width < 170 then 20 else 22
		m.InfoHeight = m.InfoSize + 6
		m.SubSize = if big then 15 else 12
		m.SubHeight = m.SubSize + 4
	else
		m.InfoSize = if big then 17 else 14
		m.InfoHeight = (m.InfoSize + 2) * 4
		m.SubHeight = 0
	end
	m.NameY = m.ArtX + m.ArtHeight + 7
	m.InfoY = m.NameY + m.Name + 2
	m.ButtonY = m.InfoY + m.InfoHeight + m.SubHeight + 8
	m.InnerHeight = m.ButtonY + m.Button + 9
	m.Height = m.InnerHeight + 6 + 5 -- the outline and the drop shadow
	return m
end

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------
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

local function image(props)
	local label = Instance.new("ImageLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	for key, value in props do
		if type(key) == "number" then
			value.Parent = label
		elseif key ~= "Parent" then
			label[key] = value
		end
	end
	label.Parent = props.Parent
	return label
end

-- The part of a square picture (`size` px) with the aspect of a `width` x `height` box, its centre at
-- (focusX, focusY) of the box (fractions; the picture's centre goes there as far as the picture allows)
local function imageRect(size: number, width: number, height: number, focusX: number?, focusY: number?)
	local fx, fy = focusX or 0.5, focusY or 0.5
	local rectWidth = math.min(size, size / 2 / math.max(fx, 1 - fx), size / 2 / math.max(fy, 1 - fy) * width / height)
	local rectHeight = rectWidth * height / width
	local x = math.clamp(size / 2 - rectWidth * fx, 0, size - rectWidth)
	local y = math.clamp(size / 2 - rectHeight * fy, 0, size - rectHeight)
	return Vector2.new(math.floor(x), math.floor(y)), Vector2.new(math.floor(rectWidth), math.floor(rectHeight))
end

-- Sunburst in `color`: the colour's gradient with the white rays and glow on top (no rays until uploaded)
local function sunburst(parent: GuiObject, color: Color3, radius: number, z: number, focusX: number?)
	local base = frame({
		Name = "Sunburst",
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = parent,
		UI.Corner(radius),
		UI.Gradient(color:Lerp(WHITE, 0.3), Theme.Shade(color, 0.72)),
	})
	if RAYS then
		local box = parent.AbsoluteSize
		local width = if box.X > 1 then box.X else parent.Size.X.Offset
		local height = if box.Y > 1 then box.Y else parent.Size.Y.Offset
		local offset, size = imageRect(RAYS_SIZE, math.max(width, 1), math.max(height, 1), focusX, 0.5)
		image({
			Name = "Rays",
			Image = RAYS,
			ImageRectOffset = offset,
			ImageRectSize = size,
			Size = UDim2.fromScale(1, 1),
			ZIndex = z + 1,
			Parent = base,
			UI.Corner(radius),
		})
	end
	return base
end

-- Candy ribbon tag (badge.html's ribbon): a tilted pill with a gradient, an ink outline, a dark drop,
-- a white shine and a white label with an outline
local function ribbon(props)
	local set = Theme.Set(props.Set)
	local z = props.ZIndex or 1
	local height = props.Size.Y.Offset
	local holder = frame({
		Name = props.Name or "Tag",
		BackgroundTransparency = 1,
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Rotation = props.Rotation or -4,
		ZIndex = z,
		Parent = props.Parent,
	})
	frame({
		Name = "Drop",
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.15,
		Position = UDim2.fromOffset(0, 3),
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = holder,
		UI.Corner(math.floor(height * 0.32)),
	})
	local body = frame({
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 1,
		Parent = holder,
		UI.Corner(math.floor(height * 0.32)),
		UI.Gradient(set.Top, set.Bottom),
		UI.Stroke(2.5, INK),
	})
	frame({
		Name = "Shine",
		BackgroundTransparency = 0.72,
		Position = UDim2.fromOffset(5, 3),
		Size = UDim2.new(1, -10, 0.32, 0),
		ZIndex = z + 2,
		Parent = body,
		UI.Round(),
	})
	UI.Text({
		Name = "Label",
		Text = props.Text,
		TextSize = props.TextSize or math.floor(height * 0.62),
		Scaled = true,
		MinTextSize = 9,
		Stroke = INK,
		StrokeThickness = 2,
		Size = UDim2.new(1, -12, 1, -6),
		Position = UDim2.new(0.5, 0, 0.5, -1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = z + 3,
		Parent = body,
	})
	return holder
end

-- Shows `picture` (an image id) as a candy button's icon, or hides the icon
local function setButtonImage(button: GuiObject, picture: string?)
	if not picture then
		UI.SetButtonIcon(button, nil)
		return
	end
	UI.SetButtonIcon(button, "Check") -- makes sure the icon holder is there and shown
	local icon = button:FindFirstChild("Icon", true)
	local glyph = icon and icon:FindFirstChild("Image")
	if glyph then
		glyph.Image = picture
		glyph.Visible = true
		glyph.ImageColor3 = WHITE
	end
	local emoji = icon and icon:FindFirstChild("Emoji")
	if emoji then
		emoji.Visible = false
	end
end

local priced = setmetatable({}, { __mode = "k" }) -- [button showing a price] = price

local function showPrice(button: GuiButton, price: number)
	priced[button] = price
	UI.SetButtonColor(button, "Leaf")
	button.Active = true
	if ROBUX then
		setButtonImage(button, ROBUX)
		UI.SetButtonText(button, Format.Commas(price))
	else
		setButtonImage(button, nil)
		UI.SetButtonText(button, "R$ " .. Format.Commas(price))
	end
end

-- Disabled button for an item that has no Id yet (live servers only; the Id can't change mid-game)
local function showComingSoon(button: GuiButton)
	priced[button] = nil
	UI.SetButtonText(button, "Coming soon")
	setButtonImage(button, nil)
	UI.SetButtonColor(button, "Off")
	button.Active = false
end

local function showOwned(button: GuiButton)
	priced[button] = nil
	UI.SetButtonText(button, "Owned")
	UI.SetButtonIcon(button, "Check")
	UI.SetButtonColor(button, "Sky")
	button.Active = true -- clicking says "You already own ..."
end

---------------------------------------------------------------------------
-- Item card: the badge art in a thick ink frame, the name, a description (or the Volts amount) and the
-- price button. spec: Key, Name, Color, Icon, Image (asset id), Description, Tag
---------------------------------------------------------------------------
local function itemCard(parent: Instance, order: number, m, spec, onClick: () -> ())
	local cell = frame({ Name = spec.Key, BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
	frame({
		Name = "Shadow",
		BackgroundColor3 = INK,
		BackgroundTransparency = Theme.ShadeTransparency,
		Position = UDim2.fromOffset(0, 5),
		Size = UDim2.new(1, 0, 1, -5),
		ZIndex = 1,
		Parent = cell,
		UI.Corner(20),
	})
	local body = frame({
		Name = "Body",
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.new(1, -6, 1, -11),
		ZIndex = 2,
		Parent = cell,
		UI.Corner(17),
		UI.Gradient(Theme.Cloud, Theme.Mist),
		UI.Stroke(3, INK),
	})

	-- Art: the sunburst + 3D icon, covered by the badge once it's there
	local art = frame({
		Name = "Art",
		BackgroundColor3 = spec.Color,
		Position = UDim2.fromOffset(m.ArtX, m.ArtX),
		Size = UDim2.fromOffset(m.ArtWidth, m.ArtHeight),
		ZIndex = 3,
		Parent = body,
		UI.Corner(13),
		UI.Stroke(3, INK),
	})
	sunburst(art, spec.Color, 13, 3)
	local iconSize = math.floor(m.ArtHeight * 0.62)
	Icons.New(spec.Icon, {
		Name = "Icon",
		Size = UDim2.fromOffset(iconSize, iconSize),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 6,
		Parent = art,
	})
	local offset, size = imageRect(512, m.ArtWidth, m.ArtHeight, 0.5, 0.48)
	local badge = image({
		Name = "Badge",
		ImageRectOffset = offset,
		ImageRectSize = size,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 7,
		Parent = art,
		UI.Corner(13),
	})
	local function setArt(picture: string?)
		if picture then
			badge.Image = picture
			badge.Visible = true
		end
	end
	setArt(asset(spec.Image))

	UI.Text({
		Name = "Title",
		Text = spec.Name,
		TextSize = m.NameSize,
		Scaled = true,
		MinTextSize = 12,
		Size = UDim2.new(1, -16, 0, m.Name),
		Position = UDim2.fromOffset(8, m.NameY),
		ZIndex = 3,
		Parent = body,
	})
	local info, sub
	if m.Info == "Volts" then
		info = UI.Text({
			Name = "Amount",
			Text = "",
			TextSize = m.InfoSize,
			Scaled = true,
			MinTextSize = 11,
			Rich = true,
			Size = UDim2.new(1, -12, 0, m.InfoHeight),
			Position = UDim2.fromOffset(6, m.InfoY),
			ZIndex = 3,
			Parent = body,
		})
		sub = UI.Text({
			Name = "Worth",
			Text = "",
			Font = Theme.BodyFont,
			TextSize = m.SubSize,
			Scaled = true,
			MinTextSize = 9,
			Color = Theme.InkSoft,
			Size = UDim2.new(1, -12, 0, m.SubHeight),
			Position = UDim2.fromOffset(6, m.InfoY + m.InfoHeight),
			ZIndex = 3,
			Parent = body,
		})
	else
		info = UI.Text({
			Name = "Description",
			Text = spec.Description or "",
			Font = Theme.BodyFont,
			TextSize = m.InfoSize,
			Scaled = true,
			MinTextSize = 10,
			Wrapped = true,
			Color = Theme.InkSoft,
			Y = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, -18, 0, m.InfoHeight),
			Position = UDim2.fromOffset(9, m.InfoY),
			ZIndex = 3,
			Parent = body,
		})
	end

	local button = UI.Button({
		Name = "Buy",
		Text = "",
		Image = ROBUX,
		Icon = if ROBUX then nil else "Check",
		IconSize = math.floor(m.Button * 0.46),
		Color = "Leaf",
		TextSize = math.floor(m.Button * 0.5),
		Size = UDim2.new(1, -16, 0, m.Button),
		Position = UDim2.fromOffset(8, m.ButtonY),
		ZIndex = 3,
		Parent = body,
		OnClick = onClick,
	})
	setButtonImage(button, ROBUX)

	if spec.Tag then
		ribbon({
			Name = "Tag",
			Text = spec.Tag.Text,
			Set = spec.Tag.Set,
			Size = UDim2.fromOffset(math.clamp(math.floor(m.Width * 0.62), 112, 150), if m.Width >= 240 then 34 else 30),
			Position = UDim2.fromOffset(-2, -9),
			Rotation = -5,
			ZIndex = 8,
			Parent = cell,
		})
	end
	-- A check medallion on the art of owned passes
	local ownedMark = Icons.New("Check", {
		Name = "OwnedMark",
		Size = UDim2.fromOffset(46, 46),
		Position = UDim2.fromOffset(m.ArtX + m.ArtWidth + 1, m.ArtX + 4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 9,
		Parent = cell,
	})
	return { Frame = cell, Button = button, Info = info, Sub = sub, SetArt = setArt, Owned = ownedMark }
end

---------------------------------------------------------------------------
-- Featured card: the lobby pet on an aurora sunburst stage
---------------------------------------------------------------------------
local function featuredCard(parent: Instance, width: number, height: number, product, onClick: () -> ())
	local pet = Pets.Pets[product.PetId]
	local cell = frame({
		Name = "Featured",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(width, height),
		LayoutOrder = 0,
		Parent = parent,
	})
	frame({
		Name = "Shadow",
		BackgroundColor3 = INK,
		BackgroundTransparency = Theme.ShadeTransparency,
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 1, -6),
		ZIndex = 1,
		Parent = cell,
		UI.Corner(22),
	})
	local inner = Vector2.new(width - 6, height - 12)
	local body = frame({
		Name = "Body",
		BackgroundColor3 = WHITE,
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.fromOffset(inner.X, inner.Y),
		ZIndex = 2,
		Parent = cell,
		UI.Corner(19),
		UI.Stroke(3, INK),
	})
	-- Stage on the left: rays centred on the pet
	local stage = math.min(math.floor(inner.Y * 0.96), math.floor(inner.X * 0.38))
	local stageX = math.floor(stage / 2 + 18)
	local backdrop = frame({
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = body,
		UI.Corner(19),
		UI.Gradient(AURORA_TOP, AURORA_BOTTOM, 35),
	})
	if RAYS then
		local offset, size = imageRect(RAYS_SIZE, inner.X, inner.Y, stageX / inner.X, 0.5)
		image({
			Name = "Rays",
			Image = RAYS,
			ImageRectOffset = offset,
			ImageRectSize = size,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
			Parent = backdrop,
			UI.Corner(19),
		})
	end
	local view = Viewport.Pet(product.PetId, "Normal", {
		Name = "Pet",
		Size = UDim2.fromOffset(stage, stage),
		Position = UDim2.fromOffset(stageX, math.floor(inner.Y * 0.47)),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 5,
		Zoom = 1.02,
		Angle = 24,
		Parent = body,
	})

	-- Text on the right
	local left = stageX + math.floor(stage / 2) + 8
	local textWidth = inner.X - left - 16
	local tall = height >= 240
	local titleSize = if tall then 34 else 32
	local y = if tall then 20 else 16
	UI.Text({
		Name = "Title",
		Text = product.Name,
		TextSize = titleSize,
		Scaled = true,
		MinTextSize = 18,
		Stroke = INK,
		StrokeThickness = 3,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(textWidth, titleSize + 4),
		Position = UDim2.fromOffset(left, y),
		ZIndex = 6,
		Parent = body,
	})
	y += titleSize + 10
	-- the pet's bonus in a white capsule
	local capsuleHeight = if tall then 36 else 34
	local capsule = frame({
		Name = "Bonus",
		Size = UDim2.fromOffset(math.min(textWidth, 230), capsuleHeight),
		Position = UDim2.fromOffset(left, y),
		ZIndex = 6,
		Parent = body,
		UI.Round(),
		UI.Gradient(WHITE, Theme.Mist),
		UI.Stroke(2.5, INK),
	})
	Icons.New("Energy", {
		Name = "Icon",
		Size = UDim2.fromOffset(capsuleHeight + 8, capsuleHeight + 8),
		Position = UDim2.fromOffset(capsuleHeight / 2 - 2, capsuleHeight / 2),
		ZIndex = 7,
		Parent = capsule,
	})
	UI.Text({
		Name = "Value",
		Text = '<font color="#1F8F38">' .. Format.Bonus(pet and pet.Bonus or 0) .. "</font> Energy",
		Rich = true,
		TextSize = if tall then 22 else 21,
		Scaled = true,
		MinTextSize = 12,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -capsuleHeight - 16, 1, -6),
		Position = UDim2.new(0, capsuleHeight + 6, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 7,
		Parent = capsule,
	})
	y += capsuleHeight + 8
	local buttonHeight = if tall then 54 else 50
	local descriptionHeight = inner.Y - y - buttonHeight - 22
	UI.Text({
		Name = "Description",
		Text = product.Description or "",
		Font = Theme.BodyFont,
		TextSize = if tall then 16 else 15,
		Scaled = true,
		MinTextSize = 10,
		Wrapped = true,
		Stroke = INK,
		StrokeThickness = 1.25,
		X = Enum.TextXAlignment.Left,
		Y = Enum.TextYAlignment.Top,
		Size = UDim2.fromOffset(textWidth, descriptionHeight),
		Position = UDim2.fromOffset(left, y),
		ZIndex = 6,
		Parent = body,
	})
	local button = UI.Button({
		Name = "Buy",
		Text = "",
		Image = ROBUX,
		Icon = if ROBUX then nil else "Check",
		IconSize = math.floor(buttonHeight * 0.46),
		Color = "Leaf",
		TextSize = math.floor(buttonHeight * 0.52),
		Size = UDim2.fromOffset(math.min(textWidth, 210), buttonHeight),
		Position = UDim2.fromOffset(inner.X - 14, inner.Y - 12),
		AnchorPoint = Vector2.new(1, 1),
		ZIndex = 6,
		Parent = body,
		OnClick = onClick,
	})
	setButtonImage(button, ROBUX)
	ribbon({
		Name = "Tag",
		Text = "EXCLUSIVE",
		Set = "Storm",
		Size = UDim2.fromOffset(if tall then 150 else 140, if tall then 36 else 32),
		Position = UDim2.fromOffset(-3, -10),
		Rotation = -5,
		ZIndex = 8,
		Parent = cell,
	})
	return { Frame = cell, Button = button, View = view }
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
function Shop.Build()
	local layout = chooseLayout()
	local window = UI.Window({
		Name = "Shop",
		Title = "Storm Shop",
		Icon = "🛒",
		Size = UDim2.fromOffset(layout.Window.X, layout.Window.Y),
		Padding = { 20, 16, 18 },
	})
	local content = window.Content
	-- The content box in offset px (Window: sides 20, 16 under the band, 18 at the bottom; 3 px outline)
	local contentWidth = layout.Window.X - 2 * (20 - 3)
	local listWidth = contentWidth - SCROLL_PAD.Left - SCROLL_PAD.Right
	local tabsHeight = 46
	local pages = {}

	local function page(key: string)
		local scroll = UI.Scroll({
			Name = key,
			Size = UDim2.new(1, 0, 1, -(tabsHeight + 10)),
			Position = UDim2.fromOffset(0, tabsHeight + 10),
			Visible = false,
			Parent = content,
			UI.List(Enum.FillDirection.Vertical, 16, Enum.HorizontalAlignment.Center),
			UI.Padding(SCROLL_PAD.Top, SCROLL_PAD.Right, SCROLL_PAD.Bottom, SCROLL_PAD.Left),
		})
		local columns = layout.Columns[key]
		local cardWidth = math.floor((listWidth - (columns - 1) * GAP) / columns)
		local m = cardMetrics(cardWidth, if key == "Volts" then "Volts" else "Description")
		local grid = frame({
			Name = "Grid",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(columns * cardWidth + (columns - 1) * GAP, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			Parent = scroll,
			UI.Grid(UDim2.fromOffset(cardWidth, m.Height), UDim2.fromOffset(GAP, GAP + 4)),
		})
		local entry = { Scroll = scroll, Grid = grid, Metrics = m, Width = columns * cardWidth + (columns - 1) * GAP }
		pages[key] = entry
		return entry
	end

	local tabs = UI.Tabs({
		Tabs = {
			{ Key = "Passes", Text = "Passes" },
			{ Key = "Boosts", Text = "Boosts" },
			{ Key = "Volts", Text = "Volts" },
		},
		TabWidth = layout.TabWidth,
		Size = UDim2.new(0, 0, 0, tabsHeight),
		Parent = content,
		OnSelect = function(key)
			for pageKey, entry in pages do
				entry.Scroll.Visible = pageKey == key
			end
		end,
	})

	local Monetize = Registry.MonetizationController
	local unconfigured = false
	local passCards = {} -- [pass key] = { Card, Price, Pass }
	local voltsCards = {} -- [product key] = card
	local cards = {} -- [item key] = cell (hidden while the item is restricted)
	local refresh

	-- Featured: the lobby pet (Kind = "Pet") on top of the Passes page
	local passPage = page("Passes")
	local featured
	for _, product in Monetization.SortedProducts() do
		if product.Kind == "Pet" and product.PetId and Pets.Pets[product.PetId] and not featured then
			featured = featuredCard(passPage.Scroll, passPage.Width, layout.Featured, product, function()
				if not Monetize.IsComingSoon(product) then
					Monetize.PromptProduct(product.Key)
				end
			end)
			cards[product.Key] = featured.Frame
			local comingSoon = Monetize.IsComingSoon(product)
			Monetize.GetPrice("Product", product.Key, function(price)
				if comingSoon then
					showComingSoon(featured.Button)
				else
					showPrice(featured.Button, price)
				end
			end)
			if product.Id == 0 then
				unconfigured = true
			end
		end
	end

	-- Gamepasses
	for index, pass in Monetization.SortedPasses() do
		local card = itemCard(passPage.Grid, index, passPage.Metrics, {
			Key = pass.Key,
			Name = pass.Name,
			Color = pass.Color,
			Icon = ITEM_ICONS[pass.Key] or pass.Icon,
			Image = pass.Image,
			Description = pass.Description,
			Tag = TAGS[pass.Key],
		}, function()
			if not Monetize.IsComingSoon(pass) then
				Monetize.PromptPass(pass.Key)
			end
		end)
		cards[pass.Key] = card.Frame
		passCards[pass.Key] = { Card = card, Price = pass.Price, Pass = pass }
		Monetize.GetPrice("Pass", pass.Key, function(price, icon)
			passCards[pass.Key].Price = price
			if not asset(pass.Image) and icon then
				card.SetArt("rbxassetid://" .. tostring(icon)) -- the pass's own icon on Roblox
			end
			if refresh then
				refresh()
			end
		end)
		if pass.Id == 0 then
			unconfigured = true
		end
	end

	-- Developer products (the lobby pet is the featured card)
	local boostPage = page("Boosts")
	local voltsPage = page("Volts")
	for index, product in Monetization.SortedProducts() do
		if product.Kind == "Pet" then
			continue
		end
		local target = if product.Category == "Volts" then voltsPage else boostPage
		local description = product.Description
		if product.Kind == "Boost" then
			description = "Doubles your "
				.. string.lower(product.Boost)
				.. " for "
				.. Format.Duration(product.Duration)
				.. ". Stacks with gamepasses and pauses while you're offline."
		end
		local card = itemCard(target.Grid, index, target.Metrics, {
			Key = product.Key,
			Name = product.Name,
			Color = PRODUCT_COLORS[product.Key] or PRODUCT_COLORS[product.Kind] or Theme.Sets.Sky.Top,
			Icon = ITEM_ICONS[product.Key] or product.Icon,
			Image = product.Image,
			Description = description,
			Tag = TAGS[product.Key],
		}, function()
			if not Monetize.IsComingSoon(product) then
				Monetize.PromptProduct(product.Key)
			end
		end)
		cards[product.Key] = card.Frame
		if product.Kind == "Volts" then
			voltsCards[product.Key] = card
		end
		local comingSoon = Monetize.IsComingSoon(product)
		Monetize.GetPrice("Product", product.Key, function(price, icon)
			if not asset(product.Image) and icon then
				card.SetArt("rbxassetid://" .. tostring(icon))
			end
			if comingSoon then
				showComingSoon(card.Button)
			else
				showPrice(card.Button, price)
			end
		end)
		if product.Id == 0 then
			unconfigured = true
		end
	end

	if unconfigured and RunService:IsStudio() then
		local tabsWidth = 3 * layout.TabWidth + 2 * 4 + 8
		UI.Text({
			Name = "StudioNote",
			Text = "Studio test mode: items without an ID are free",
			Font = Theme.BodyFont,
			TextSize = 13,
			Scaled = true,
			Wrapped = true,
			Color = Theme.Sets.Sunset.Lip,
			X = Enum.TextXAlignment.Right,
			Size = UDim2.new(1, -tabsWidth - 12, 0, 36),
			Position = UDim2.new(1, -4, 0, tabsHeight / 2),
			AnchorPoint = Vector2.new(1, 0.5),
			Parent = content,
		})
	end

	refresh = function()
		local data = Registry.DataController.Data
		if not data then
			return
		end
		for passKey, entry in passCards do
			local owned = Formulas.HasPass(data, passKey)
			entry.Card.Owned.Visible = owned
			if owned then
				showOwned(entry.Card.Button)
			elseif Monetize.IsComingSoon(entry.Pass) then
				showComingSoon(entry.Card.Button)
			else
				showPrice(entry.Card.Button, entry.Price)
			end
		end
		local unit = Formulas.VoltsUnit(data)
		for productKey, card in voltsCards do
			local amount = Monetization.Products[productKey].Amount
			card.Info.Text = '<font color="#1F8F38">+' .. Format.Number(amount * unit) .. "</font> Volts"
			if card.Sub then
				card.Sub.Text = "Worth " .. amount .. " full tanks"
			end
		end
	end

	-- Paid random items (Volts packs, luck and hatch boosters) are hidden where they aren't allowed
	local function applyPolicy()
		for key, cell in cards do
			cell.Visible = not Monetize.IsRestricted(key)
		end
		local voltsOnSale = false
		for _, cell in cards do
			if cell.Parent == voltsPage.Grid and cell.Visible then
				voltsOnSale = true
			end
		end
		tabs.Buttons.Volts.Visible = voltsOnSale
		if tabs.Selected == "Volts" and not voltsOnSale then
			tabs.Select("Passes")
		end
	end
	player:GetAttributeChangedSignal("PaidRandomItemsRestricted"):Connect(applyPolicy)
	applyPolicy()

	Registry.DataController.ObserveMany({ "Passes", "Upgrades", "Zone", "Rebirths" }, refresh)

	-- If Roblox can't serve the Robux glyph (still in review, or refused), prices go back to "R$ 299"
	if ROBUX then
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync({ ROBUX }, function(_, status)
					if status == Enum.AssetFetchStatus.Failure and ROBUX then
						ROBUX = nil
						for button, price in priced do
							showPrice(button, price)
						end
					end
				end)
			end)
		end)
	end

	-- The featured pet sways gently while the shop is open
	if featured then
		local clock = 0
		RunService.Heartbeat:Connect(function(dt)
			if window.Frame.Visible and passPage.Scroll.Visible then
				clock += dt
				featured.View.SetRotation(math.rad(24 + math.sin(clock * 1.3) * 22))
			end
		end)
	end

	return {
		Window = window,
		OnOpen = function(tab: string?)
			refresh()
			applyPolicy()
			local tabButton = tab and tabs.Buttons[tab]
			if tab and not (tabButton and tabButton.Visible) then
				tab = "Passes" -- e.g. the HUD's "+" asked for Volts packs that are hidden here
			end
			tabs.Select(tab or tabs.Selected or "Passes")
		end,
	}
end

return Shop
