--!nocheck
-- Sky Lab component kit, built with plain Roblox instances: a fidelity test for the preview (it should
-- look like docs/ui_components.png) and an example of a --run-file snippet.
--
--   python3 tools/preview_ui.py --blank --run-file tools/ui_preview/examples/skylab_kit.luau \
--       --bg none --no-core --name skylab_kit --compare docs/ui_components.png
--
-- Sizes follow docs/STYLE_GUIDE.md section 2 and the CSS -> Roblox notes at the top of
-- docs/ui_mockup.html (1 CSS px = 1 offset px at 1280x720). Icons are repo paths (assets/ui/*.png),
-- which the preview draws directly; the game itself needs uploaded asset ids for them.

local INK = Color3.fromHex("233066")
local INK_SOFT = Color3.fromHex("5B6A9E")
local CLOUD = Color3.fromHex("FFFFFF")
local MIST = Color3.fromHex("EAF3FF")
local HAZE = Color3.fromHex("D5E5FB")

-- { top, bottom } face gradients (STYLE_GUIDE palette)
local SETS = {
	Sky = { "5CC8FF", "2F86F2" },
	Bolt = { "FFE15A", "FFAA1F" },
	Rain = { "54E0FF", "1E9BEF" },
	Storm = { "A98BFF", "6B4BE6" },
	Leaf = { "7BE36A", "33B24A" },
	Coral = { "FF7A85", "E43A58" },
	Sunset = { "FFB15C", "F2702A" },
	Off = { "E9EFF9", "C9D6EC" },
}

local function shade(color, k)
	return Color3.new(color.R * k, color.G * k, color.B * k)
end

local function new(className, props, children)
	local object = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			object[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = object
	end
	object.Parent = props.Parent
	return object
end

local function corner(radius)
	return new("UICorner", { CornerRadius = if radius then UDim.new(0, radius) else UDim.new(1, 0) })
end

local function stroke(thickness, color, mode)
	return new("UIStroke", {
		Thickness = thickness,
		Color = color or INK,
		ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

local function gradient(top, bottom)
	return new("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = 90 })
end

-- white Fredoka text with a stroke (Ink over the world, the surface's dark shade on buttons)
local function label(props)
	local text = new("TextLabel", {
		Name = props.Name or "Label",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Text = props.Text,
		Font = props.Font or Enum.Font.FredokaOne,
		TextSize = props.TextSize or 22,
		TextColor3 = props.Color or CLOUD,
		TextXAlignment = props.X or Enum.TextXAlignment.Center,
		RichText = props.Rich or false,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	if props.Stroke then
		stroke(props.StrokeThickness or 2, props.Stroke, Enum.ApplyStrokeMode.Contextual).Parent = text
	end
	return text
end

local function icon(path, size, props)
	props = props or {}
	return new("ImageLabel", {
		Name = props.Name or "Icon",
		BackgroundTransparency = 1,
		Image = path,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(size, size),
		Position = props.Position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5),
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
end

-- Candy button: the frame is the lip (face x0.62), the face stops 5 px above the bottom, a white
-- shine covers the top 35 % of the face
local function candy(props)
	local set = SETS[props.Set or "Sky"]
	local top, bottom = Color3.fromHex(set[1]), Color3.fromHex(set[2])
	local radius = if props.Pill then nil else (props.Radius or 14)
	local w, h = props.W or 120, props.H or 48
	local lip = new("TextButton", {
		Name = props.Name or "Candy",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = shade(bottom, 0.62),
		Size = UDim2.fromOffset(w, h),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	}, { corner(radius), stroke(props.Outline or 3) })
	local face = new("Frame", {
		Name = "Face",
		BackgroundColor3 = CLOUD,
		Size = UDim2.new(1, 0, 1, -(props.Lip or 5)),
	}, { corner(if radius then radius - 3 else nil), gradient(top, bottom) })
	face.Parent = lip
	new("Frame", {
		Name = "Shine",
		BackgroundColor3 = CLOUD,
		BackgroundTransparency = 0.75,
		Size = UDim2.new(1, -8, 0.35, 0),
		Position = UDim2.fromOffset(4, 3),
		Parent = face,
	}, { corner() })
	local row = new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = face,
	}, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	if props.Icon then
		icon(props.Icon, props.IconSize or 28, { Parent = row, LayoutOrder = 1 })
	end
	if props.Text then
		local text = label({
			Text = props.Text,
			TextSize = props.TextSize or 22,
			Size = UDim2.new(0, 0, 1, 0),
			Stroke = shade(bottom, 0.55),
			Color = if props.Set == "Off" then Color3.fromHex("F7FAFF") else CLOUD,
			Parent = row,
		})
		text.AutomaticSize = Enum.AutomaticSize.X
		text.LayoutOrder = 2
	end
	return lip
end

-- round "orb": Ink circle -> ring circle inset 3 -> face circle inset 3
local function orb(props)
	local size = props.Size
	local outer = new("Frame", {
		Name = props.Name or "Orb",
		BackgroundColor3 = INK,
		Size = UDim2.fromOffset(size, size),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	}, { corner() })
	local ring = new("Frame", {
		Name = "Ring",
		BackgroundColor3 = props.Ring,
		Size = UDim2.new(1, -6, 1, -6),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = props.ZIndex or 1,
		Parent = outer,
	}, { corner() })
	local inset = props.RingWidth or 3
	new("Frame", {
		Name = "Face",
		BackgroundColor3 = props.Face or CLOUD,
		Size = UDim2.new(1, -2 * inset - 2, 1, -2 * inset - 2),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = props.ZIndex or 1,
		Parent = ring,
	}, { corner(), stroke(1.5, INK) })
	if props.Icon then
		icon(props.Icon, props.IconSize or size * 0.62, { Parent = outer, ZIndex = props.ZIndex or 1 })
	end
	return outer
end

local function badge(text, parent, position)
	local frame = new("Frame", {
		Name = "Badge",
		BackgroundColor3 = CLOUD,
		Size = UDim2.fromOffset(if #text > 1 then 34 else 26, 26),
		Position = position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 3,
		Parent = parent,
	}, { corner(), stroke(2), gradient(Color3.fromHex("FF7A85"), Color3.fromHex("E43A58")) })
	label({ Text = text, TextSize = 17, Stroke = Color3.fromHex("7D2030"), StrokeThickness = 1.5, ZIndex = 3, Parent = frame })
	return frame
end

local function caption(text, x, y)
	label({ Text = text, TextSize = 11, Font = Enum.Font.GothamBold, Color = INK_SOFT, X = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(500, 14), Position = UDim2.fromOffset(x, y), Parent = Kit })
end

---------------------------------------------------------------------------------------------------- the sheet
for _, gui in PlayerGui:GetChildren() do
	if gui:IsA("ScreenGui") then
		gui.Enabled = false
	end
end
local screen = new("ScreenGui", { Name = "SkyLabKit", IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = PlayerGui })
Kit = new("Frame", { Name = "Sheet", BackgroundColor3 = MIST, Size = UDim2.fromScale(1, 1), Parent = screen })

label({ Text = "Sky Lab UI kit", TextSize = 30, Color = INK, X = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(400, 34), Position = UDim2.fromOffset(32, 22), Parent = Kit })
caption("CANDY BUTTON  corner 14 · lip 5 px (face x0.62) · shine over the top 35 % · label stroke x0.55", 32, 86)

-- candy buttons
local x = 96
for _, name in { "Sky", "Bolt", "Rain", "Storm", "Leaf", "Coral", "Sunset" } do
	candy({ Name = name, Set = name, Text = name, W = 86 + (if #name > 4 then 0 else 0), H = 48, Position = UDim2.fromOffset(x, 108), Parent = Kit })
	x += 95
end
candy({ Name = "Buy", Set = "Leaf", Text = "1.23M", Icon = "assets/ui/Volts.png", W = 134, H = 52, TextSize = 24, Position = UDim2.fromOffset(32, 226), Parent = Kit })
candy({ Name = "Max", Set = "Storm", Text = "MAX", W = 62, H = 52, Position = UDim2.fromOffset(184, 226), Parent = Kit })
candy({ Name = "CantAfford", Set = "Off", Text = "6.55M", Icon = "assets/ui/Lock.png", IconSize = 22, W = 136, H = 52, Position = UDim2.fromOffset(264, 226), Parent = Kit })
candy({ Name = "Maxed", Set = "Bolt", Text = "MAXED", W = 110, H = 52, Position = UDim2.fromOffset(416, 226), Parent = Kit })
candy({ Name = "Equip", Set = "Sky", Text = "Equip", Pill = true, W = 108, H = 52, TextSize = 24, Position = UDim2.fromOffset(542, 226), Parent = Kit })
local close = candy({ Name = "Close", Set = "Coral", Pill = true, W = 48, H = 48, Position = UDim2.fromOffset(668, 228), Parent = Kit })
label({ Text = "✕", TextSize = 26, Stroke = Color3.fromHex("7D2030"), Size = UDim2.new(1, 0, 1, -5), Parent = close:FindFirstChild("Face") })
candy({ Name = "Add", Set = "Leaf", Text = "+", W = 30, H = 30, Outline = 2, Radius = 11, Lip = 4, TextSize = 22, Position = UDim2.fromOffset(731, 238), Parent = Kit })

-- tiles with a rarity pedestal
caption("TILE · RARITY PEDESTAL  Cloud, 2 px Haze, corner 18 · pedestal = bottom 30 %", 32, 318)
local Viewport = require(Client.UI.Viewport)
local tiles = {
	{ "Puffling", "Common", "C9D3E6", "9AA7C2" },
	{ "Droplet", "Uncommon", "7BE36A", "33B24A" },
	{ "Sunny", "Rare", "5CC8FF", "2F86F2" },
	{ "Prism", "Epic", "D6B8FF", "A06BF0" },
	{ "BreezeKing", "Legendary", "FFE15A", "FFAA1F" },
}
for index, spec in tiles do
	local tile = new("Frame", {
		Name = spec[1],
		BackgroundColor3 = CLOUD,
		Size = UDim2.fromOffset(110, 138),
		Position = UDim2.fromOffset(32 + (index - 1) * 123, 340),
		Parent = Kit,
	}, { corner(18), stroke(if index == 3 then 3 else 2, if index == 3 then Color3.fromHex("2F86F2") else HAZE) })
	label({ Text = spec[1] == "BreezeKing" and "Breeze King" or spec[1], TextSize = 17, Color = INK, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 8), Parent = tile })
	local pedestal = new("Frame", {
		Name = "Pedestal",
		BackgroundColor3 = CLOUD,
		Size = UDim2.new(1, -20, 0.3, 0),
		Position = UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = tile,
	}, { corner(12), stroke(2), gradient(Color3.fromHex(spec[3]), Color3.fromHex(spec[4])) })
	label({ Text = spec[2], TextSize = 13, Stroke = shade(Color3.fromHex(spec[4]), 0.55), StrokeThickness = 1.5, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -20), Parent = pedestal })
	Viewport.Pet(spec[1], "Normal", { Size = UDim2.fromOffset(84, 84), Position = UDim2.new(0.5, 0, 0, 30), AnchorPoint = Vector2.new(0.5, 0), Parent = tile })
end

-- storm jar
caption("STORM JAR  Haze track, 3 px Ink, Rain liquid, shine stripe", 32, 500)
local track = new("Frame", {
	Name = "Jar",
	BackgroundColor3 = HAZE,
	Size = UDim2.fromOffset(330, 46),
	Position = UDim2.fromOffset(60, 528),
	Parent = Kit,
}, { corner(), stroke(3) })
local liquid = new("Frame", { Name = "Liquid", BackgroundColor3 = CLOUD, Size = UDim2.fromScale(0.55, 1), Parent = track }, { corner(), gradient(Color3.fromHex("54E0FF"), Color3.fromHex("1E9BEF")) })
new("Frame", { Name = "Shine", BackgroundColor3 = CLOUD, BackgroundTransparency = 0.3, Size = UDim2.new(1, -24, 0, 5), Position = UDim2.fromOffset(12, 6), Parent = liquid }, { corner() })
label({ Text = "500 / 1,000", TextSize = 24, Color = INK, Parent = track })
icon("assets/ui/Tank.png", 58, { Position = UDim2.fromOffset(62, 551), Parent = Kit })

-- cloud window header
caption("CLOUD WINDOW · HEADER", 808, 86)
local window = new("Frame", {
	Name = "Window",
	BackgroundColor3 = CLOUD,
	Size = UDim2.fromOffset(400, 130),
	Position = UDim2.fromOffset(828, 140),
	Parent = Kit,
}, { corner(26), stroke(3), gradient(CLOUD, MIST) })
new("Frame", { Name = "Shadow", BackgroundColor3 = INK, BackgroundTransparency = 0.75, ZIndex = 0, Size = UDim2.fromOffset(400, 130), Position = UDim2.fromOffset(828, 146), Parent = Kit }, { corner(26) })
for i, spec in { { 270, 2, 46 }, { 300, -14, 62 }, { 340, 2, 46 } } do
	new("Frame", { Name = "Puff" .. i, BackgroundColor3 = CLOUD, Size = UDim2.fromOffset(spec[3], spec[3]), Position = UDim2.fromOffset(spec[1] - 48, spec[2] - 24), ZIndex = 0, Parent = window }, { corner(), stroke(3) })
end
local band = new("Frame", { Name = "Header", BackgroundColor3 = CLOUD, Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 18), Parent = window }, { gradient(Color3.fromHex("5CC8FF"), Color3.fromHex("2F86F2")), stroke(3) })
label({ Text = "Pets", TextSize = 32, Stroke = INK, StrokeThickness = 3, Size = UDim2.fromScale(1, 1), Parent = band })
local tabs = new("Frame", { Name = "Tabs", BackgroundColor3 = HAZE, Size = UDim2.new(1, -40, 0, 44), Position = UDim2.fromOffset(20, 80), Parent = window }, {
	corner(),
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }),
})
candy({ Name = "Inventory", Set = "Sky", Text = "Inventory", Pill = true, W = 116, H = 34, TextSize = 18, LayoutOrder = 1, Parent = tabs })
for i, name in { "Index", "Craft" } do
	label({ Text = name, TextSize = 18, Color = INK_SOFT, Size = UDim2.fromOffset(116, 34), Parent = tabs }).LayoutOrder = i + 1
end
orb({ Name = "WeatherBadge", Size = 76, Ring = Color3.fromHex("FFC83A"), RingWidth = 4, Icon = "assets/ui/Pets.png", IconSize = 44, Position = UDim2.fromOffset(806, 126), ZIndex = 2, Parent = Kit })
local x2 = candy({ Name = "CloseWindow", Set = "Coral", Pill = true, W = 48, H = 48, Position = UDim2.fromOffset(1198, 128), Parent = Kit })
label({ Text = "✕", TextSize = 26, Stroke = Color3.fromHex("7D2030"), Size = UDim2.new(1, 0, 1, -5), Parent = x2:FindFirstChild("Face") })

-- capsules
caption("CAPSULE  Cloud->Mist pill · 54 px icon over the left end · Fredoka 26", 808, 394)
local capsule = new("Frame", { Name = "Capsule", BackgroundColor3 = CLOUD, Size = UDim2.fromOffset(200, 44), Position = UDim2.fromOffset(834, 416), Parent = Kit }, { corner(), stroke(3), gradient(CLOUD, MIST) })
label({ Text = "12.4M", TextSize = 26, Color = INK, X = Enum.TextXAlignment.Left, Size = UDim2.new(1, -40, 1, 0), Position = UDim2.fromOffset(38, 0), Parent = capsule })
candy({ Name = "Plus", Set = "Leaf", Text = "+", W = 32, H = 32, Outline = 2, Radius = 11, Lip = 4, TextSize = 24, Position = UDim2.new(1, -36, 0, 4), Parent = capsule })
icon("assets/ui/Volts.png", 54, { Position = UDim2.fromOffset(838, 438), Parent = Kit })
local shifts = new("Frame", { Name = "Shifts", BackgroundColor3 = CLOUD, Size = UDim2.fromOffset(126, 44), Position = UDim2.fromOffset(1064, 416), Parent = Kit }, { corner(), stroke(3), gradient(CLOUD, MIST) })
label({ Text = "3", TextSize = 26, Color = INK, X = Enum.TextXAlignment.Left, Size = UDim2.new(1, -40, 1, 0), Position = UDim2.fromOffset(52, 0), Parent = shifts })
icon("assets/ui/ClimateShift.png", 50, { Position = UDim2.fromOffset(1082, 438), Parent = Kit })

-- HUD buttons and badges
caption("HUD BUTTON · BADGE", 808, 492)
for i, spec in { { "Shop", "assets/ui/Shop.png" }, { "Rewards", "assets/ui/Rewards.png" }, { "Teleport", "assets/ui/Teleport.png" } } do
	local button = orb({ Name = spec[1], Size = 68, Ring = Color3.fromHex("5CC8FF"), Icon = spec[2], IconSize = 40, Position = UDim2.fromOffset(814 + (i - 1) * 92, 512), Parent = Kit })
	label({ Text = spec[1], TextSize = 17, Stroke = INK, StrokeThickness = 2, Size = UDim2.fromOffset(90, 20), Position = UDim2.new(0.5, 0, 1, -6), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 2, Parent = button })
	if spec[1] == "Rewards" then
		badge("2", button, UDim2.new(1, -4, 0, 4))
	end
end
badge("!", Kit, UDim2.fromOffset(1196, 526))
badge("3", Kit, UDim2.fromOffset(1232, 526))

-- toasts
caption("TOAST  Cloud pill, 2 px Ink, coloured icon disk on the left", 32, 628)
for i, spec in {
	{ "Hatched <font color=\"#2F86F2\">Sunny</font>!", "7BE36A", "assets/ui/Check.png", 222 },
	{ "+<font color=\"#FFAA1F\">25K</font> Volts", "FFE15A", "assets/ui/Gift.png", 176 },
	{ "Need <font color=\"#E43A58\">6.55M</font> Volts", "FF7A85", "assets/ui/Lock.png", 236 },
} do
	local left = ({ 32, 268, 458 })[i]
	local toast = new("Frame", { Name = "Toast" .. i, BackgroundColor3 = CLOUD, Size = UDim2.fromOffset(spec[4], 50), Position = UDim2.fromOffset(left, 646), Parent = Kit }, { corner(), stroke(2) })
	local disk = new("Frame", { Name = "Disk", BackgroundColor3 = Color3.fromHex(spec[2]), Size = UDim2.fromOffset(36, 36), Position = UDim2.fromOffset(7, 7), Parent = toast }, { corner(), stroke(2) })
	icon(spec[3], 26, { Parent = disk })
	label({ Text = spec[1], Rich = true, TextSize = 20, Color = INK, X = Enum.TextXAlignment.Left, Size = UDim2.new(1, -56, 1, 0), Position = UDim2.fromOffset(52, 0), Parent = toast })
end
