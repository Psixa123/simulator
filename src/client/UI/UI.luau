--!nonstrict
-- The interface component library ("Sky Lab", docs/STYLE_GUIDE.md section 2). Everything is built
-- in code from these pieces:
--   basics      Create, Tween, Corner, Round, Stroke, Gradient, Padding, List, Grid, Label, Text, Scroll
--   candy       Button (lip, shine, press / hover), CloseButton, SetButtonColor / Text / Icon
--   containers  Window (cloud window), Card, CloudCard, Tile (rarity pedestal), Capsule
--   widgets     ProgressBar, Jar (storm jar), Toggle, Tabs, Badge, Orb, HudButton, Timer, Toast, Icon
--   motion      Bounce, Pop, FadeIn, FadeOut
-- Sizes are offset px at 1280x720 (the HUD scale there is 1). Outlines are drawn inside the given
-- size (UIStroke draws outside a frame, so bodies are inset by the outline), so a 48 px button
-- looks 48 px tall like in docs/ui_mockup.html.

local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local UI = {}
UI.Theme = Theme
UI.Icons = Icons

-- Hook set by the SoundController so every button click plays a sound
UI.ClickHook = nil :: (() -> ())?

local COLORS = Theme.Colors
local SIZES = Theme.Sizes
local INK = Theme.Ink
local WHITE = Color3.new(1, 1, 1)
local SHADE = Theme.ShadeTransparency

---------------------------------------------------------------------------
-- Basics
---------------------------------------------------------------------------
local SKIP = { Parent = true, Stroke = true, StrokeColor = true, MaxTextSize = true, MinTextSize = true }

local function apply(instance: Instance, props)
	for key, value in props do
		if type(key) == "number" then
			value.Parent = instance
		elseif not SKIP[key] then
			instance[key] = value
		end
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

-- UI.Create("Frame", { Size = ..., UI.Corner(8) }) -- array entries become children
function UI.Create(className: string, props)
	return apply(Instance.new(className), props or {})
end

function UI.Tween(instance: Instance, duration: number, props, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	tween:Play()
	return tween
end

function UI.Corner(radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 12)
	return corner
end

function UI.Round()
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	return corner
end

function UI.Stroke(thickness: number?, color: Color3?, transparency: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or Theme.Outline
	stroke.Color = color or INK
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	return stroke
end

-- Outline for text (white text on colour or over the world)
function UI.TextStroke(thickness: number?, color: Color3?)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "TextStroke"
	stroke.Thickness = thickness or 2
	stroke.Color = color or INK
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	return stroke
end

function UI.Gradient(top: Color3, bottom: Color3, rotation: number?)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = rotation or 90
	return gradient
end

function UI.Padding(top: number, right: number?, bottom: number?, left: number?)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, top)
	padding.PaddingRight = UDim.new(0, right or top)
	padding.PaddingBottom = UDim.new(0, bottom or top)
	padding.PaddingLeft = UDim.new(0, left or right or top)
	return padding
end

function UI.List(direction: Enum.FillDirection?, padding: number?, horizontal: Enum.HorizontalAlignment?, vertical: Enum.VerticalAlignment?)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction or Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, padding or 8)
	layout.HorizontalAlignment = horizontal or Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = vertical or Enum.VerticalAlignment.Top
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	return layout
end

function UI.Grid(cellSize: UDim2, padding: UDim2?)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = cellSize
	grid.CellPadding = padding or UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	return grid
end

-- Scaled white text with an Ink outline (the older label style; over the world and on colour).
-- props: any TextLabel property, Stroke (thickness, or false for none), StrokeColor, MaxTextSize, MinTextSize
function UI.Label(props)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Theme.Font
	label.TextColor3 = COLORS.Text
	label.TextScaled = true
	label.Text = ""
	label.Size = UDim2.fromScale(1, 1)
	label.TextWrapped = true
	if props.Stroke ~= false then
		local stroke = Instance.new("UIStroke")
		stroke.Color = props.StrokeColor or COLORS.Stroke
		stroke.Thickness = props.Stroke or 2
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Parent = label
	end
	if props.MaxTextSize then
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MaxTextSize = props.MaxTextSize
		constraint.MinTextSize = props.MinTextSize or 1
		constraint.Parent = label
	end
	return apply(label, props)
end

-- Sky Lab text: Ink Fredoka on light surfaces, or white with an outline when Stroke is a colour.
-- props: Text, TextSize (fixed; with Scaled = true it's the largest size), Color, Font, Stroke (Color3),
-- StrokeThickness, X / Y (alignment), Rich, Wrapped, Size, Position, AnchorPoint, ZIndex, LayoutOrder, Name, Parent
function UI.Text(props)
	local label = Instance.new("TextLabel")
	label.Name = props.Name or "Text"
	label.BackgroundTransparency = 1
	label.Font = props.Font or Theme.Font
	label.Text = props.Text or ""
	label.TextColor3 = props.Color or (if props.Stroke then WHITE else INK)
	label.TextXAlignment = props.X or Enum.TextXAlignment.Center
	label.TextYAlignment = props.Y or Enum.TextYAlignment.Center
	label.RichText = props.Rich == true
	label.TextWrapped = props.Wrapped == true
	label.Size = props.Size or UDim2.fromScale(1, 1)
	label.Position = props.Position or UDim2.new()
	label.AnchorPoint = props.AnchorPoint or Vector2.zero
	label.ZIndex = props.ZIndex or 1
	label.LayoutOrder = props.LayoutOrder or 0
	if props.Visible == false then
		label.Visible = false
	end
	local size = props.TextSize or 20
	if props.Scaled then
		label.TextScaled = true
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MaxTextSize = size
		constraint.MinTextSize = props.MinTextSize or 8
		constraint.Parent = label
	else
		label.TextSize = size
	end
	if props.Stroke then
		UI.TextStroke(props.StrokeThickness or 2, props.Stroke).Parent = label
	end
	if props.Parent then
		label.Parent = props.Parent
	end
	return label
end

function UI.Scroll(props)
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Theme.InkSoft
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Size = UDim2.fromScale(1, 1)
	return apply(scroll, props)
end

function UI.Shade(color: Color3, k: number): Color3
	return Theme.Shade(color, k)
end

---------------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------------
local function corner(radius: number?)
	return if radius then UI.Corner(math.max(radius, 0)) else UI.Round()
end

local function frame(name: string, props)
	local object = Instance.new("Frame")
	object.Name = name
	object.BorderSizePixel = 0
	object.BackgroundColor3 = WHITE
	return apply(object, props)
end

-- A copy of a shape a few px lower in Ink at 75 % transparency (the drop shadow)
local function shadow(parent: Instance, radius: number?, offset: number, z: number, inset: number?)
	local pad: number = inset or 0
	return frame("Shadow", {
		BackgroundColor3 = INK,
		BackgroundTransparency = SHADE,
		Position = UDim2.fromOffset(pad, pad + offset),
		Size = UDim2.new(1, -2 * pad, 1, -2 * pad),
		ZIndex = z,
		Parent = parent,
		corner(radius),
	})
end

-- Total UIScale above an object (AbsoluteSize / scale = size in offset px)
local function scaleOf(object: Instance): number
	local k = 1
	local current = object
	while current and not current:IsA("LayerCollector") do
		local scale = current:FindFirstChildOfClass("UIScale")
		if scale then
			k *= scale.Scale
		end
		current = current.Parent
	end
	return if k > 0.001 then k else 1
end

local function measure(text: string, size: number, font: Enum.Font): Vector2
	local ok, bounds = pcall(TextService.GetTextSize, TextService, text, size, font, Vector2.new(4096, 4096))
	if ok and typeof(bounds) == "Vector2" then
		return bounds
	end
	return Vector2.new(utf8.len(text) or #text, 1) * size * 0.56
end

local function plain(text: string): string
	return (string.gsub(text, "<[^>]+>", ""))
end

local function lineCount(text: string): number
	local _, count = string.gsub(text, "\n", "")
	return count + 1
end

local function clickSound()
	if UI.ClickHook then
		UI.ClickHook()
	end
end

local function touchInput(): boolean
	local ok, last = pcall(function()
		return UserInputService:GetLastInputType()
	end)
	return ok and last == Enum.UserInputType.Touch
end

-- Ink circle -> coloured ring -> white face, the round "weather badge" look.
-- Returns outline, ring, face. `size` is the outer diameter.
local function orbLayers(parent: Instance, set, ringWidth: number, z: number)
	local outline = frame("Outline", {
		BackgroundColor3 = INK,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = parent,
		UI.Round(),
	})
	local ring = frame("Ring", {
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.new(1, -6, 1, -6),
		ZIndex = z + 1,
		Parent = outline,
		UI.Round(),
	})
	local ringGradient = UI.Gradient(set.Top, set.Bottom)
	ringGradient.Name = "Fill"
	ringGradient.Parent = ring
	local face = frame("Face", {
		Position = UDim2.fromOffset(ringWidth, ringWidth),
		Size = UDim2.new(1, -2 * ringWidth, 1, -2 * ringWidth),
		ZIndex = z + 2,
		Parent = ring,
		UI.Round(),
		UI.Create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Theme.Cloud),
				ColorSequenceKeypoint.new(0.45, Theme.Cloud),
				ColorSequenceKeypoint.new(1, Theme.Mist),
			}),
			Rotation = 90,
		}),
	})
	return outline, ring, face
end

---------------------------------------------------------------------------
-- Motion
---------------------------------------------------------------------------
-- Hover / press bounce for any GuiButton (uses a UIScale child)
function UI.Bounce(button: GuiButton, hoverScale: number?, pressScale: number?)
	local scale = button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = button
	local hover = hoverScale or 1.04
	local press = pressScale or 0.94
	button.MouseEnter:Connect(function()
		if not touchInput() then
			UI.Tween(scale, 0.12, { Scale = hover })
		end
	end)
	button.MouseLeave:Connect(function()
		UI.Tween(scale, 0.12, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		UI.Tween(scale, 0.08, { Scale = press })
	end)
	button.MouseButton1Up:Connect(function()
		-- Touch screens never send MouseLeave, so a tap ends at rest size
		UI.Tween(scale, 0.14, { Scale = if touchInput() then 1 else hover }, Enum.EasingStyle.Back)
	end)
	return scale
end

-- Pops an element (scale bounce)
function UI.Pop(guiObject: GuiObject, amount: number?)
	local scale = guiObject:FindFirstChild("PopScale") or guiObject:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	if not scale.Parent then
		scale.Name = "PopScale"
		scale.Parent = guiObject
	end
	scale.Scale = amount or 1.15
	UI.Tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

local FADE_PROPS = {
	{ "GuiObject", "BackgroundTransparency" },
	{ "TextLabel", "TextTransparency" },
	{ "TextButton", "TextTransparency" },
	{ "TextBox", "TextTransparency" },
	{ "ImageLabel", "ImageTransparency" },
	{ "ImageButton", "ImageTransparency" },
	{ "UIStroke", "Transparency" },
}

local function fadeTargets(root: Instance)
	local targets = {}
	local list = root:GetDescendants()
	table.insert(list, root)
	for _, object in list do
		for _, entry in FADE_PROPS do
			if object:IsA(entry[1]) then
				local value = object[entry[2]]
				if value < 1 then
					table.insert(targets, { object, entry[2], value })
				end
			end
		end
	end
	return targets
end

-- Fades everything in `root` out (backgrounds, text, images, strokes); returns the last tween
function UI.FadeOut(root: Instance, duration: number?)
	local last
	for _, target in fadeTargets(root) do
		last = UI.Tween(target[1], duration or 0.3, { [target[2]] = 1 })
	end
	return last
end

-- Fades everything in `root` in from invisible to how it looks now
function UI.FadeIn(root: Instance, duration: number?)
	for _, target in fadeTargets(root) do
		target[1][target[2]] = 1
		UI.Tween(target[1], duration or 0.2, { [target[2]] = target[3] })
	end
end

---------------------------------------------------------------------------
-- Candy button
---------------------------------------------------------------------------
-- Lip (face x0.62) with the Ink outline, the gradient face 5 px above its bottom and a white shine
-- over the top 35 % of the face. Built inside `parent`, filling it. Returns lip, face.
local function candyBody(parent: Instance, set, opts)
	local z = opts.ZIndex or 1
	local t = opts.Outline or Theme.Outline
	local lipHeight = opts.Lip or SIZES.ButtonLip
	local radius = if opts.Pill then nil else math.max((opts.Radius or SIZES.ButtonCorner) - t, 2)
	local lip = frame("Lip", {
		BackgroundColor3 = set.Lip,
		Position = UDim2.fromOffset(t, t),
		Size = UDim2.new(1, -2 * t, 1, -2 * t),
		ZIndex = z,
		Parent = parent,
		corner(radius),
	})
	local outline = UI.Stroke(t, INK)
	outline.Name = "Outline"
	outline.Parent = lip
	local face = frame("Face", {
		Size = UDim2.new(1, 0, 1, -lipHeight),
		ZIndex = z + 1,
		Parent = lip,
		corner(radius),
	})
	local fill = UI.Gradient(set.Top, set.Bottom)
	fill.Name = "Fill"
	fill.Parent = face
	frame("Shine", {
		BackgroundTransparency = 0.75,
		Position = if opts.Round then UDim2.new(0.2, 0, 0, 5) else UDim2.fromOffset(4, 3),
		Size = if opts.Round then UDim2.new(0.6, 0, 0.3, 0) else UDim2.new(1, -8, 0.35, 0),
		ZIndex = z + 2,
		Parent = face,
		UI.Round(),
	})
	return lip, face
end

local fitters = setmetatable({}, { __mode = "k" }) -- [button] = refit function

local function findPart(button: Instance, name: string)
	return button:FindFirstChild(name, true)
end

-- props: Text, Color (Sky Lab set or older name), Size, Position, AnchorPoint, LayoutOrder, Parent,
-- ZIndex, MaxTextSize / TextSize (largest label size, default 22), Font, Icon (Icons key or emoji),
-- Image (asset id string), IconSize, Pill, Round, CornerRadius, Small (2 px outline, 4 px lip),
-- Outline, Lip, Name, Visible, OnClick
function UI.Button(props)
	local set = Theme.Set(props.Color or "Leaf")
	local z = props.ZIndex or 1
	local small = props.Small == true
	local outlineWidth = props.Outline or (if small then Theme.OutlineSmall else Theme.Outline)
	local lipHeight = props.Lip or (if small then 4 else SIZES.ButtonLip)

	local button = Instance.new("TextButton")
	button.Name = props.Name or "Button"
	button.AutoButtonColor = false
	button.Text = ""
	button.BackgroundTransparency = 1
	button.Size = props.Size or UDim2.fromOffset(160, 50)
	button.Position = props.Position or UDim2.new()
	button.AnchorPoint = props.AnchorPoint or Vector2.zero
	button.LayoutOrder = props.LayoutOrder or 0
	button.ZIndex = z
	if props.Visible == false then
		button.Visible = false
	end
	button:SetAttribute("ButtonColor", props.Color or "Leaf")

	local lip, face = candyBody(button, set, {
		ZIndex = z,
		Outline = outlineWidth,
		Lip = lipHeight,
		Pill = props.Pill or props.Round,
		Round = props.Round,
		Radius = props.CornerRadius or (if small then 11 else SIZES.ButtonCorner),
	})

	local content = frame("Content", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 3,
		Parent = face,
		UI.List(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})

	local icon = nil
	if props.Icon or props.Image then
		icon = Icons.New(props.Icon, { Name = "Icon", LayoutOrder = 1, ZIndex = z + 3, Parent = content })
		if props.Image then
			icon.Image.Image = props.Image
			icon.Image.Visible = true
			icon.Emoji.Visible = false
		end
	end

	local font = props.Font or Theme.Font
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Font = font
	label.Text = props.Text or ""
	label.TextColor3 = set.Text
	label.TextSize = props.TextSize or props.MaxTextSize or SIZES.ButtonText
	label.LayoutOrder = 2
	label.ZIndex = z + 3
	label.Size = UDim2.fromOffset(0, 0)
	label.Parent = content
	local labelStroke = UI.TextStroke(2, set.Stroke)
	labelStroke.Name = "LabelStroke"
	labelStroke.Parent = label

	-- Size the label (and icon) to the button: the largest text size that fits on one line
	local maxText = props.TextSize or props.MaxTextSize or SIZES.ButtonText
	local fixedIcon = props.IconSize
	local last = ""
	local function fit()
		local absolute = face.AbsoluteSize
		if absolute.X <= 1 or absolute.Y <= 1 then
			return
		end
		local k = scaleOf(face)
		local width, height = absolute.X / k, absolute.Y / k
		local text = label.Text
		local key = string.format("%d|%d|%s|%s", math.floor(width + 0.5), math.floor(height + 0.5), text, tostring(icon and icon.Visible))
		if key == last then
			return
		end
		last = key
		local iconWidth = 0
		if icon and icon.Visible then
			local size = fixedIcon or math.floor(height * 0.72)
			icon.Size = UDim2.fromOffset(size, size)
			iconWidth = size + (if text ~= "" then 6 else 0)
		end
		if text == "" then
			label.Size = UDim2.fromOffset(0, height)
			label.Visible = false
			return
		end
		label.Visible = true
		local lines = lineCount(text)
		local size = if props.TextSize
			then math.min(props.TextSize, math.floor(height * 1.15 / lines))
			else math.min(maxText, math.floor((height - 4) * (if lines > 1 then 0.86 else 0.64) / lines))
		local padding = math.clamp(height * 0.18, 5, 12)
		local available = width - 2 * padding - iconWidth
		local bounds = measure(text, size, font)
		if bounds.X > available and available > 0 then
			size = math.max(7, math.floor(size * available / bounds.X))
			bounds = measure(text, size, font)
		end
		label.TextSize = size
		labelStroke.Thickness = if size >= 16 then 2 else 1.5
		label.Size = UDim2.fromOffset(math.ceil(math.min(bounds.X, math.max(available, 0))) + 4, height)
	end
	fitters[button] = fit
	face:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	label:GetPropertyChangedSignal("Text"):Connect(fit)
	if icon then
		icon:GetPropertyChangedSignal("Visible"):Connect(fit)
	end

	-- Press: the face goes down onto the lip; hover: a little bigger
	local pressed = false
	local function setPressed(state: boolean)
		if pressed == state then
			return
		end
		pressed = state
		local t = outlineWidth
		if state then
			lip.Position = UDim2.fromOffset(t, t + 3)
			lip.Size = UDim2.new(1, -2 * t, 1, -2 * t - 3)
			face.Size = UDim2.new(1, 0, 1, -math.max(lipHeight - 3, 1))
		else
			lip.Position = UDim2.fromOffset(t, t)
			lip.Size = UDim2.new(1, -2 * t, 1, -2 * t)
			face.Size = UDim2.new(1, 0, 1, -lipHeight)
		end
	end
	local scale = Instance.new("UIScale")
	scale.Name = "HoverScale"
	scale.Parent = button
	button.MouseEnter:Connect(function()
		if not touchInput() then
			UI.Tween(scale, 0.12, { Scale = 1.04 })
		end
	end)
	button.MouseLeave:Connect(function()
		setPressed(false)
		UI.Tween(scale, 0.12, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		setPressed(true)
	end)
	button.MouseButton1Up:Connect(function()
		setPressed(false)
		if touchInput() then
			UI.Tween(scale, 0.12, { Scale = 1 })
		end
	end)

	button.Activated:Connect(function()
		clickSound()
		if props.OnClick then
			props.OnClick()
		end
	end)

	if props.Parent then
		button.Parent = props.Parent
	end
	fit()
	return button
end

-- Recolours a candy button (a Sky Lab set name or an older colour name)
function UI.SetButtonColor(button: GuiObject, colorName: string)
	if button:GetAttribute("ButtonColor") == colorName then
		return
	end
	button:SetAttribute("ButtonColor", colorName)
	local set = Theme.Set(colorName)
	local lip = button:FindFirstChild("Lip")
	if lip then
		lip.BackgroundColor3 = set.Lip
		local face = lip:FindFirstChild("Face")
		local fill = face and face:FindFirstChild("Fill")
		if fill then
			fill.Color = ColorSequence.new(set.Top, set.Bottom)
		end
	end
	local label = findPart(button, "Label")
	if label and label:IsA("TextLabel") then
		label.TextColor3 = set.Text
		local stroke = label:FindFirstChild("LabelStroke")
		if stroke then
			stroke.Color = set.Stroke
		end
	end
end

function UI.SetButtonText(button: GuiObject, text: string)
	local label = findPart(button, "Label")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
	local fit = fitters[button]
	if fit then
		fit()
	end
end

-- Shows an icon (Icons key or emoji; nil hides it) on the left of a candy button's label
function UI.SetButtonIcon(button: GuiObject, key: string?)
	local icon = findPart(button, "Icon")
	if not icon then
		if not key then
			return
		end
		local content = findPart(button, "Content")
		if not content then
			return
		end
		local z = content.ZIndex
		icon = Icons.New(key, { Name = "Icon", LayoutOrder = 1, ZIndex = z, Size = UDim2.fromOffset(0, 0), Parent = content })
		icon:GetPropertyChangedSignal("Visible"):Connect(function()
			local fit = fitters[button]
			if fit then
				fit()
			end
		end)
	end
	if key then
		Icons.Set(icon, key)
	end
	icon.Visible = key ~= nil
	local fit = fitters[button]
	if fit then
		fit()
	end
end

-- White ✕ with a dark-coral outline (two rounded bars each way)
local function crossMark(parent: Instance, size: number, z: number, strokeColor: Color3)
	local holder = frame("Cross", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = z,
		Parent = parent,
	})
	local long = size * 1.05
	for index, spec in { { strokeColor, long + 4, size * 0.4 + 0.5, z }, { WHITE, long, size * 0.23, z + 1 } } do
		for _, angle in { 45, -45 } do
			frame(if index == 1 then "Edge" else "Bar", {
				BackgroundColor3 = spec[1],
				Size = UDim2.fromOffset(spec[2], spec[3]),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Rotation = angle,
				ZIndex = spec[4],
				Parent = holder,
				UI.Round(),
			})
		end
	end
	return holder
end

-- Round Coral close button with a white ✕. props: Size (default 48), Position, AnchorPoint, ZIndex, Parent, OnClick, Name
function UI.CloseButton(props)
	local size = props.Diameter or SIZES.WindowClose
	local button = UI.Button({
		Name = props.Name or "Close",
		Text = "",
		Color = props.Color or "Coral",
		Round = true,
		Size = props.Size or UDim2.fromOffset(size, size),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		OnClick = props.OnClick,
	})
	local face = findPart(button, "Face")
	local set = Theme.Set(props.Color or "Coral")
	crossMark(face, math.floor(size * 0.4), (props.ZIndex or 1) + 4, set.Stroke)
	if props.Parent then
		button.Parent = props.Parent
	end
	return button
end

---------------------------------------------------------------------------
-- Round pieces: orb, badge, HUD button, timer
---------------------------------------------------------------------------
-- The round weather badge: Ink outline, a coloured ring, a white face and an icon.
-- props: Size (diameter, default 68), Color (ring set, default Sky), RingWidth (3), Icon, IconSize,
-- Shadow (default true), Position, AnchorPoint, ZIndex, Name, Parent, LayoutOrder
function UI.Orb(props)
	local diameter = props.Size or SIZES.HudButton
	local z = props.ZIndex or 1
	local holder = frame(props.Name or "Orb", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(diameter, diameter),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = z,
	})
	if props.Shadow ~= false then
		shadow(holder, nil, 4, z)
	end
	local _, _, face = orbLayers(holder, Theme.Set(props.Color or "Sky"), props.RingWidth or 3, z + 1)
	local iconSize = props.IconSize or math.floor(diameter * 0.66)
	Icons.New(props.Icon, {
		Name = "Icon",
		Size = UDim2.fromOffset(iconSize, iconSize),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = z + 4,
		Parent = holder,
	})
	if props.Parent then
		holder.Parent = props.Parent
	end
	return holder, face
end

-- Small Coral badge with a number or "!" in the corner of a button (hidden until UI.SetBadge)
function UI.Badge(parent: GuiObject, position: UDim2?)
	local set = Theme.Sets.Coral
	local z = (parent.ZIndex or 1) + 6
	local badge = frame("Badge", {
		BackgroundColor3 = INK,
		Size = UDim2.fromOffset(SIZES.BadgeSize, SIZES.BadgeSize),
		Position = position or UDim2.new(1, 6, 0, -6),
		AnchorPoint = Vector2.new(1, 0),
		Visible = false,
		ZIndex = z,
		Parent = parent,
		UI.Round(),
	})
	frame("Fill", {
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		ZIndex = z + 1,
		Parent = badge,
		UI.Round(),
		UI.Gradient(set.Top, set.Bottom),
	})
	UI.Text({
		Name = "Count",
		Text = "!",
		TextSize = 16,
		Stroke = set.Stroke,
		StrokeThickness = 1.5,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.fromOffset(0, 1),
		ZIndex = z + 2,
		Parent = badge,
	})
	return badge
end

-- Shows a badge with a count (0 / nil hides it, true or 1 shows "!", text shows as is); pops when it appears
function UI.SetBadge(badge: GuiObject, value: any)
	local text
	if value == nil or value == false or value == 0 then
		badge.Visible = false
		return
	elseif value == true or value == 1 then
		text = "!"
	elseif type(value) == "number" then
		text = if value > 99 then "99+" else tostring(value)
	else
		text = tostring(value)
	end
	local label = badge:FindFirstChild("Count")
	if label then
		label.Text = text
	end
	local length = utf8.len(text) or #text
	badge.Size = UDim2.fromOffset(if length <= 1 then SIZES.BadgeSize else 14 + length * 9, SIZES.BadgeSize)
	if not badge.Visible then
		badge.Visible = true
		UI.Pop(badge, 1.5)
	end
end

-- Round HUD button: a 68 px weather badge with a Sky ring, the icon and a white label underneath.
-- props: Name, Icon, Text, Color (ring set), Size, Position, LayoutOrder, ZIndex, Parent, OnClick
-- Children: Orb, Caption, Badge.
function UI.HudButton(props)
	local diameter = props.Diameter or SIZES.HudButton
	local z = props.ZIndex or 1
	local button = Instance.new("TextButton")
	button.Name = props.Name or "HudButton"
	button.AutoButtonColor = false
	button.Text = ""
	button.BackgroundTransparency = 1
	button.Size = props.Size or UDim2.fromOffset(diameter, diameter)
	button.Position = props.Position or UDim2.new()
	button.AnchorPoint = props.AnchorPoint or Vector2.zero
	button.LayoutOrder = props.LayoutOrder or 0
	button.ZIndex = z

	UI.Orb({
		Name = "Orb",
		Size = diameter,
		Color = props.Color or "Sky",
		Icon = props.Icon,
		IconSize = props.IconSize or math.floor(diameter * 0.64),
		Position = UDim2.new(0.5, 0, 0, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = z,
		Parent = button,
	})
	UI.Text({
		Name = "Caption",
		Text = props.Text or "",
		TextSize = props.TextSize or SIZES.HudLabel,
		Stroke = INK,
		Size = UDim2.fromOffset(diameter + 40, 20),
		Position = UDim2.new(0.5, 0, 0, diameter - 5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = z + 6,
		Parent = button,
	})
	UI.Badge(button, UDim2.new(0.5, diameter / 2 + 8, 0, -6))
	UI.Bounce(button, 1.06, 0.92)
	button.Activated:Connect(function()
		clickSound()
		if props.OnClick then
			props.OnClick()
		end
	end)
	if props.Parent then
		button.Parent = props.Parent
	end
	return button
end

-- Round timer (boosts, the Mega Storm countdown): a progress ring in the set's colour around a
-- white face with an icon, a chip (e.g. "x2") and the time underneath.
-- props: Name, Icon, Color (set, default Sunset), Chip, Text, Size (diameter, 68), Position,
-- AnchorPoint, LayoutOrder, ZIndex, Parent, OnClick (makes it a button).
-- Returns { Frame, SetProgress(0..1), SetText(text), SetChip(text?), SetColor(set), SetIcon(key), Badge }
function UI.Timer(props)
	local diameter = props.Diameter or SIZES.HudButton
	local z = props.ZIndex or 1
	local root = Instance.new(if props.OnClick then "TextButton" else "Frame")
	root.Name = props.Name or "Timer"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(diameter, diameter)
	root.Position = props.Position or UDim2.new()
	root.AnchorPoint = props.AnchorPoint or Vector2.zero
	root.LayoutOrder = props.LayoutOrder or 0
	root.ZIndex = z
	if root:IsA("TextButton") then
		root.Text = ""
		root.AutoButtonColor = false
	end

	shadow(root, nil, 4, z)
	local outline = frame("Outline", { BackgroundColor3 = INK, Size = UDim2.fromScale(1, 1), ZIndex = z + 1, Parent = root, UI.Round() })
	local track = frame("Track", {
		BackgroundColor3 = Theme.Haze,
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.new(1, -6, 1, -6),
		ZIndex = z + 2,
		Parent = outline,
		UI.Round(),
	})
	-- Pie: two half-discs, each a full disc with a hard-edged gradient, clipped to one side
	local step = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.5001, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	local halves = {}
	for index, side in { "Right", "Left" } do
		local clip = frame(side .. "Half", {
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Position = UDim2.fromScale(if index == 1 then 0.5 else 0, 0),
			Size = UDim2.fromScale(0.5, 1),
			ZIndex = z + 3,
			Parent = track,
		})
		local disc = frame("Disc", {
			Position = UDim2.fromScale(if index == 1 then -1 else 0, 0),
			Size = UDim2.fromScale(2, 1),
			ZIndex = z + 3,
			Parent = clip,
			UI.Round(),
		})
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = step
		gradient.Parent = disc
		halves[index] = { Disc = disc, Gradient = gradient }
	end
	local ringWidth = 6
	local face = frame("Face", {
		Position = UDim2.fromOffset(ringWidth, ringWidth),
		Size = UDim2.new(1, -2 * ringWidth, 1, -2 * ringWidth),
		ZIndex = z + 4,
		Parent = track,
		UI.Round(),
		UI.Gradient(Theme.Cloud, Theme.Mist),
	})
	UI.Stroke(2, INK).Parent = face
	local icon = Icons.New(props.Icon, {
		Name = "Icon",
		Size = UDim2.fromOffset(math.floor(diameter * 0.59), math.floor(diameter * 0.59)),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = z + 5,
		Parent = root,
	})
	local caption = UI.Text({
		Name = "Caption",
		Text = props.Text or "",
		TextSize = 18,
		Stroke = INK,
		Size = UDim2.fromOffset(diameter + 40, 20),
		Position = UDim2.new(0.5, 0, 0, diameter - 4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = z + 7,
		Parent = root,
	})
	local chip = frame("Chip", {
		BackgroundColor3 = INK,
		Size = UDim2.fromOffset(38, 26),
		Position = UDim2.new(1, 12, 0, -8),
		AnchorPoint = Vector2.new(1, 0),
		Visible = false,
		ZIndex = z + 6,
		Parent = root,
		UI.Round(),
	})
	local chipFill = frame("Fill", {
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		ZIndex = z + 6,
		Parent = chip,
		UI.Round(),
	})
	local chipGradient = UI.Gradient(WHITE, WHITE)
	chipGradient.Parent = chipFill
	local chipText = UI.Text({ Name = "Text", Text = "", TextSize = 16, Stroke = INK, StrokeThickness = 1.5, Position = UDim2.fromOffset(0, 1), ZIndex = z + 7, Parent = chip })
	local badge = UI.Badge(root, UDim2.new(1, 8, 0, -6))

	local timer = { Frame = root, Caption = caption, Icon = icon, Badge = badge, Progress = 1 }
	local currentSet

	function timer.SetProgress(fraction: number)
		fraction = math.clamp(fraction, 0, 1)
		timer.Progress = fraction
		local angle = fraction * 360
		local right, left = halves[1], halves[2]
		right.Disc.Visible = angle > 0.5
		right.Gradient.Rotation = math.min(angle, 180)
		left.Disc.Visible = angle > 180
		left.Gradient.Rotation = math.max(angle, 180)
	end
	function timer.SetText(text: string)
		caption.Text = text
	end
	function timer.SetChip(text: string?)
		chip.Visible = text ~= nil and text ~= ""
		if text then
			chipText.Text = text
			chip.Size = UDim2.fromOffset(16 + (utf8.len(text) or #text) * 10, 26)
		end
	end
	function timer.SetColor(setName: string)
		local set = Theme.Set(setName)
		if currentSet == set then
			return
		end
		currentSet = set
		for _, half in halves do
			half.Disc.BackgroundColor3 = set.Bottom
		end
		chipGradient.Color = ColorSequence.new(set.Top, set.Bottom)
		local stroke = chipText:FindFirstChild("TextStroke")
		if stroke then
			stroke.Color = set.Stroke
		end
	end
	function timer.SetIcon(key: string)
		Icons.Set(icon, key)
	end

	timer.SetColor(props.Color or "Sunset")
	timer.SetChip(props.Chip)
	timer.SetProgress(props.Progress or 1)
	if root:IsA("TextButton") then
		UI.Bounce(root, 1.06, 0.92)
		root.Activated:Connect(function()
			clickSound()
			props.OnClick()
		end)
	end
	if props.Parent then
		root.Parent = props.Parent
	end
	return timer
end

---------------------------------------------------------------------------
-- Containers
---------------------------------------------------------------------------
-- A card with the older look (gradient, outline). props: CornerRadius, Top, Bottom, StrokeThickness,
-- StrokeColor, StrokeTransparency + any Frame property. Children: Fill (UIGradient), Outline (UIStroke).
function UI.Card(props)
	local card = Instance.new("Frame")
	card.BackgroundColor3 = Color3.new(1, 1, 1)
	card.BorderSizePixel = 0
	UI.Corner(props.CornerRadius or 14).Parent = card
	local gradient = UI.Gradient(props.Top or COLORS.Card, props.Bottom or COLORS.CardDark, 90)
	gradient.Name = "Fill"
	gradient.Parent = card
	local stroke = UI.Stroke(props.StrokeThickness or 2, props.StrokeColor or COLORS.Stroke, props.StrokeTransparency or 0)
	stroke.Name = "Outline"
	stroke.Parent = card
	props.CornerRadius = nil
	props.Top = nil
	props.Bottom = nil
	props.StrokeThickness = nil
	props.StrokeColor = nil
	props.StrokeTransparency = nil
	return apply(card, props)
end

-- Sky Lab card: Cloud fill, 2 px Haze outline, corner 18 (rows, list items, info boxes).
-- props: any Frame property, CornerRadius, StrokeColor, Fill (Color3), Top / Bottom (a gradient instead).
-- Children: Fill (UIGradient, when Top / Bottom given), Outline (UIStroke).
function UI.CloudCard(props)
	local card = Instance.new("Frame")
	card.BorderSizePixel = 0
	card.BackgroundColor3 = props.Fill or Theme.Cloud
	UI.Corner(props.CornerRadius or SIZES.TileCorner).Parent = card
	if props.Top or props.Bottom then
		local gradient = UI.Gradient(props.Top or Theme.Cloud, props.Bottom or Theme.Mist)
		gradient.Name = "Fill"
		gradient.Parent = card
	end
	local stroke = UI.Stroke(props.StrokeThickness or Theme.OutlineSmall, props.StrokeColor or Theme.Haze)
	stroke.Name = "Outline"
	stroke.Parent = card
	for _, key in { "Fill", "CornerRadius", "Top", "Bottom", "StrokeThickness", "StrokeColor" } do
		props[key] = nil
	end
	return apply(card, props)
end

-- Emoji (or an Icons key's image) on a coloured disc with an Ink outline.
-- props: Text (emoji), Key (Icons key: its image once uploaded, else its emoji), Color, Size,
-- Position, AnchorPoint, LayoutOrder, ZIndex, Parent. Children: Glyph (the emoji), Image (once shown).
function UI.Icon(props)
	local color = props.Color or Theme.Sets.Sky.Top
	local z = props.ZIndex or 1
	local holder = Instance.new("Frame")
	holder.Name = props.Name or "Icon"
	holder.BackgroundColor3 = WHITE
	holder.Size = props.Size or UDim2.fromOffset(56, 56)
	holder.Position = props.Position or UDim2.new()
	holder.AnchorPoint = props.AnchorPoint or Vector2.zero
	holder.LayoutOrder = props.LayoutOrder or 0
	holder.ZIndex = z
	UI.Round().Parent = holder
	UI.Stroke(2.5).Parent = holder
	UI.Gradient(color:Lerp(WHITE, 0.45), color, 90).Parent = holder
	frame("Shine", {
		BackgroundTransparency = 0.7,
		Size = UDim2.fromScale(0.56, 0.24),
		Position = UDim2.fromScale(0.22, 0.08),
		ZIndex = z,
		Parent = holder,
		UI.Round(),
	})
	local glyph = UI.Label({
		Name = "Glyph",
		Text = if props.Key then Icons.Emoji(props.Key) else (props.Text or "⚡"),
		Stroke = false,
		Size = UDim2.fromScale(0.66, 0.66),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = z + 1,
		Parent = holder,
	})
	local picture = props.Key and Icons.Image(props.Key)
	if picture then
		glyph.Visible = false
		UI.Create("ImageLabel", {
			Name = "Image",
			BackgroundTransparency = 1,
			Image = picture,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(0.86, 0.86),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = z + 1,
			Parent = holder,
		})
	end
	if props.Parent then
		holder.Parent = props.Parent
	end
	return holder
end

-- Weather badge spots and puffs (measured from the window's right edge: centre x, centre y, diameter)
local PUFFS = { { 188, 6, 64 }, { 134, 0, 88 }, { 82, 6, 56 } }

-- The cloud window. props: Name, Title, IconKey / Icon (Icons key or emoji; the window Name is tried
-- as a key before Icon), Size, Padding ({ sides, below the band, bottom } in px; default { 14, 14, 10 }).
-- Returns { Frame, Body, Header, Content, Title, Close, Badge, Scale, SetTitle(text), SetIcon(key) }.
-- Frame is a button (never a Frame) so clicks on the window never reach the Dim behind it.
function UI.Window(props)
	local t = Theme.Outline
	local root = Instance.new("TextButton")
	root.Name = props.Name or "Window"
	root.AutoButtonColor = false
	root.Selectable = false
	root.Text = ""
	root.BackgroundTransparency = 1
	root.Size = props.Size or UDim2.fromOffset(660, 460)
	root.Position = UDim2.fromScale(0.5, 0.52)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Visible = false
	local scale = Instance.new("UIScale")
	scale.Parent = root

	local radius = SIZES.WindowCorner
	shadow(root, radius, 6, 1)

	-- Three cloud puffs over the right half of the header: Ink discs, white discs on top, both behind the body
	local puffs = frame("Puffs", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = root })
	local puffScale = math.clamp((root.Size.X.Offset > 0 and root.Size.X.Offset or 660) / 700, 0.85, 1)
	for index, spec in PUFFS do
		local d = math.floor(spec[3] * puffScale)
		local cx, cy = spec[1] * puffScale, spec[2]
		frame("PuffEdge" .. index, {
			BackgroundColor3 = INK,
			Size = UDim2.fromOffset(d, d),
			Position = UDim2.new(1, -cx - d / 2, 0, cy - d / 2),
			ZIndex = 2,
			Parent = puffs,
			UI.Round(),
		})
		frame("Puff" .. index, {
			Size = UDim2.fromOffset(d - 2 * t, d - 2 * t),
			Position = UDim2.new(1, -cx - d / 2 + t, 0, cy - d / 2 + t),
			ZIndex = 3,
			Parent = puffs,
			UI.Round(),
		})
	end

	-- Body: Cloud -> Mist with the Ink outline
	local body = frame("Body", {
		Position = UDim2.fromOffset(t, t),
		Size = UDim2.new(1, -2 * t, 1, -2 * t),
		ZIndex = 4,
		Parent = root,
		UI.Corner(radius - t),
		UI.Gradient(Theme.Cloud, Theme.Mist),
	})
	UI.Stroke(t, INK).Parent = body

	-- Sky header band (rounded top, square bottom, an Ink line under it)
	local sky = Theme.Sets.Sky
	local bandHeight = SIZES.WindowBand - 2 * t
	local header = frame("Header", {
		Size = UDim2.new(1, 0, 0, bandHeight),
		ZIndex = 5,
		Parent = body,
		UI.Corner(radius - t),
		UI.Gradient(sky.Top, sky.Bottom),
	})
	local middle = sky.Top:Lerp(sky.Bottom, 0.5)
	frame("HeaderBase", {
		Position = UDim2.new(0, 0, 0, bandHeight / 2),
		Size = UDim2.new(1, 0, 0, bandHeight / 2),
		ZIndex = 5,
		Parent = body,
		UI.Gradient(middle, sky.Bottom),
	})
	frame("HeaderShine", {
		BackgroundTransparency = 0.75,
		Position = UDim2.fromOffset(9, 2),
		Size = UDim2.new(1, -18, 0, 16),
		ZIndex = 6,
		Parent = body,
		UI.Round(),
	})
	frame("HeaderLine", {
		BackgroundColor3 = INK,
		Position = UDim2.fromOffset(0, bandHeight),
		Size = UDim2.new(1, 0, 0, t),
		ZIndex = 6,
		Parent = body,
	})
	local title = UI.Text({
		Name = "Title",
		Text = props.Title or "",
		TextSize = SIZES.TitleText,
		Scaled = true,
		MinTextSize = 16,
		Stroke = INK,
		StrokeThickness = 3,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -79 - 64, 0, bandHeight - 12),
		Position = UDim2.fromOffset(79, 8),
		ZIndex = 7,
		Parent = body,
	})

	-- { sides, below the band, bottom }. The default keeps the content box the panels were laid out
	-- for (W - 28 x H - 84 at 14, 74); the mockup's spacing is { 20, 18, 18 }.
	local padding = props.Padding or { 14, 14, 10 }
	local content = frame("Content", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(padding[1] - t, SIZES.WindowBand - t + padding[2]),
		Size = UDim2.new(1, -2 * (padding[1] - t), 1, -(SIZES.WindowBand - t + padding[2]) - (padding[3] - t)),
		ZIndex = 5,
		Parent = body,
	})

	-- Weather badge over the top-left corner: white face, 4 px Bolt ring, the panel's icon
	local iconKey = if Icons.Has(props.IconKey) then props.IconKey elseif Icons.Has(props.Name) then props.Name else props.Icon
	local badge = UI.Orb({
		Name = "Badge",
		Size = SIZES.WindowBadge,
		Color = "Bolt",
		RingWidth = 4,
		Icon = iconKey,
		IconSize = 50,
		Position = UDim2.fromOffset(-18, -18),
		ZIndex = 8,
		Parent = root,
	})

	local close = UI.CloseButton({
		Name = "Close",
		Position = UDim2.new(1, 16, 0, -16),
		AnchorPoint = Vector2.new(1, 0),
		ZIndex = 9,
		Parent = root,
	})

	local window = { Frame = root, Body = body, Header = header, Content = content, Title = title, Close = close, Badge = badge, Scale = scale }
	function window.SetTitle(text: string)
		title.Text = text
	end
	function window.SetIcon(key: string)
		local icon = badge:FindFirstChild("Icon")
		if icon then
			Icons.Set(icon, key)
		end
	end
	return window
end

-- Item tile with a rarity pedestal. props: Name, Title, Rarity (a Config/Pets rarity, or a Color3),
-- RarityText, Size (112 x 140), Position, LayoutOrder, ZIndex, Parent, OnClick.
-- Returns { Frame, Art (put the picture here), Title, Pedestal, RarityLabel, Body, Outline, Lift,
-- SetSelected(bool), SetRarity(color, text) }
function UI.Tile(props)
	local z = props.ZIndex or 1
	local button = Instance.new("TextButton")
	button.Name = props.Name or "Tile"
	button.AutoButtonColor = false
	button.Text = ""
	button.BackgroundTransparency = 1
	button.Size = props.Size or UDim2.fromOffset(112, 140)
	button.Position = props.Position or UDim2.new()
	button.AnchorPoint = props.AnchorPoint or Vector2.zero
	button.LayoutOrder = props.LayoutOrder or 0
	button.ZIndex = z

	local lifted = shadow(button, SIZES.TileCorner, 1, z)
	lifted.Visible = false
	local lift = frame("Lift", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = z + 1, Parent = button })
	local t = Theme.OutlineSmall
	local body = frame("Body", {
		BackgroundColor3 = Theme.Cloud,
		Position = UDim2.fromOffset(t, t),
		Size = UDim2.new(1, -2 * t, 1, -2 * t),
		ZIndex = z + 1,
		Parent = lift,
		UI.Corner(SIZES.TileCorner - t),
	})
	local outline = UI.Stroke(t, Theme.Haze)
	outline.Name = "Outline"
	outline.Parent = body

	local titleLabel = UI.Text({
		Name = "Title",
		Text = props.Title or "",
		TextSize = 16,
		Scaled = true,
		Size = UDim2.new(1, -12, 0, 18),
		Position = UDim2.new(0.5, 0, 0, 9),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = z + 4,
		Parent = lift,
	})
	local pedestal = frame("Pedestal", {
		BackgroundColor3 = INK,
		Size = UDim2.new(1, -16, 0.27, 0),
		Position = UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = z + 2,
		Parent = lift,
		UI.Corner(14),
	})
	local pedestalFace = frame("Face", {
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		ZIndex = z + 2,
		Parent = pedestal,
		UI.Corner(12),
	})
	local pedestalGradient = UI.Gradient(WHITE, WHITE)
	pedestalGradient.Parent = pedestalFace
	frame("Gloss", {
		BackgroundTransparency = 0.5,
		Size = UDim2.new(1, -16, 0, 10),
		Position = UDim2.fromOffset(6, 1),
		ZIndex = z + 2,
		Parent = pedestalFace,
		UI.Round(),
	})
	-- The pedestal's label sits over the art (the pet stands on the pedestal and may overlap it)
	local rarityLabel = UI.Text({
		Name = "Rarity",
		Text = props.RarityText or "",
		TextSize = 13,
		Scaled = true,
		Stroke = INK,
		StrokeThickness = 1.5,
		Size = UDim2.new(1, -24, 0, 15),
		Position = UDim2.new(0.5, 0, 1, -12),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = z + 5,
		Parent = lift,
	})
	local art = frame("Art", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.72, 0.58),
		Position = UDim2.new(0.5, 0, 0, 27),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = z + 3,
		Parent = lift,
	})
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = art

	local tile = {
		Frame = button,
		Art = art,
		Title = titleLabel,
		Pedestal = pedestal,
		RarityLabel = rarityLabel,
		Body = body, -- Cloud face (a panel can tint it, e.g. golden pets)
		Outline = outline, -- its UIStroke (SetSelected recolours it)
		Lift = lift, -- everything that lifts when selected (badges go here)
		Selected = false,
	}
	function tile.SetRarity(rarity, text: string?)
		local color = if typeof(rarity) == "Color3" then rarity elseif type(rarity) == "table" then rarity.Color else Theme.Sets.Off.Bottom
		local colors = Theme.Rarity(color)
		pedestal.BackgroundColor3 = colors.Edge
		pedestalGradient.Color = ColorSequence.new(colors.Top, colors.Bottom)
		local stroke = rarityLabel:FindFirstChild("TextStroke")
		if stroke then
			stroke.Color = colors.Edge
		end
		if text then
			rarityLabel.Text = text
		elseif type(rarity) == "table" and rarity.Name then
			rarityLabel.Text = rarity.Name
		end
	end
	function tile.SetSelected(selected: boolean)
		tile.Selected = selected
		outline.Color = if selected then Theme.Sets.Sky.Bottom else Theme.Haze
		outline.Thickness = if selected then 3 else t
		lift.Position = if selected then UDim2.fromOffset(0, -4) else UDim2.new()
		lifted.Visible = selected
	end
	tile.SetRarity(props.Rarity, props.RarityText)
	tile.SetSelected(props.Selected == true)
	UI.Bounce(button, 1.04, 0.96)
	button.Activated:Connect(function()
		clickSound()
		if props.OnClick then
			props.OnClick()
		end
	end)
	if props.Parent then
		button.Parent = props.Parent
	end
	return tile
end

-- Currency capsule: Cloud -> Mist pill, a big icon over its left end, the value in Ink and an
-- optional Leaf "+" button. props: Name, Icon, Text, Size (W x 44), Plus (callback), Position,
-- AnchorPoint, LayoutOrder, ZIndex, Parent, OnClick (the whole capsule).
-- Returns { Frame, Label, Icon, Plus, Set(text) }
function UI.Capsule(props)
	local z = props.ZIndex or 1
	local root = Instance.new(if props.OnClick then "TextButton" else "Frame")
	root.Name = props.Name or "Capsule"
	root.BackgroundTransparency = 1
	root.Size = props.Size or UDim2.fromOffset(200, SIZES.CapsuleHeight)
	root.Position = props.Position or UDim2.new()
	root.AnchorPoint = props.AnchorPoint or Vector2.zero
	root.LayoutOrder = props.LayoutOrder or 0
	root.ZIndex = z
	if root:IsA("TextButton") then
		root.Text = ""
		root.AutoButtonColor = false
	end
	local t = Theme.Outline
	shadow(root, nil, 4, z)
	local body = frame("Body", {
		Position = UDim2.fromOffset(t, t),
		Size = UDim2.new(1, -2 * t, 1, -2 * t),
		ZIndex = z + 1,
		Parent = root,
		UI.Round(),
		UI.Gradient(Theme.Cloud, Theme.Mist),
	})
	UI.Stroke(t, INK).Parent = body
	local label = UI.Text({
		Name = "Amount",
		Text = props.Text or "",
		TextSize = SIZES.CapsuleText,
		Scaled = true,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -(42 + (if props.Plus then 44 else 16)), 0, 30),
		Position = UDim2.new(0, 42, 0.5, 1),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = z + 2,
		Parent = root,
	})
	local iconSize = props.IconSize or SIZES.CapsuleIcon
	local icon = Icons.New(props.Icon, {
		Name = "Icon",
		Size = UDim2.fromOffset(iconSize, iconSize),
		Position = UDim2.new(0, -18 + iconSize / 2, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = z + 3,
		Parent = root,
	})
	local plus = nil
	if props.Plus then
		plus = UI.Button({
			Name = "Add",
			Text = "+",
			Color = "Leaf",
			Small = true,
			TextSize = 26,
			Size = UDim2.fromOffset(32, 32),
			Position = UDim2.new(1, -6, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			ZIndex = z + 3,
			Parent = root,
			OnClick = props.Plus,
		})
	end
	if root:IsA("TextButton") then
		UI.Bounce(root, 1.03, 0.97)
		root.Activated:Connect(function()
			clickSound()
			props.OnClick()
		end)
	end
	if props.Parent then
		root.Parent = props.Parent
	end
	local capsule = { Frame = root, Label = label, Icon = icon, Plus = plus }
	function capsule.Set(text: string)
		label.Text = text
	end
	return capsule
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
-- Glass progress bar: Haze track with an Ink outline, a gradient fill with a shine stripe, Ink text.
-- props: Name, Color (set), Size, Position, AnchorPoint, LayoutOrder, Parent, Text, MaxTextSize,
-- StrokeThickness, ZIndex. Returns { Frame, Fill, Label, Gradient, Set(fraction, text?, animate?), SetColor(name) }
function UI.ProgressBar(props)
	local set = Theme.Set(props.Color or "Rain")
	local z = props.ZIndex or 1
	local t = props.StrokeThickness or Theme.Outline
	local root = frame(props.Name or "ProgressBar", {
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromOffset(300, 28),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = z,
	})
	local track = frame("Track", {
		BackgroundColor3 = Theme.Haze,
		Position = UDim2.fromOffset(t, t),
		Size = UDim2.new(1, -2 * t, 1, -2 * t),
		ZIndex = z,
		Parent = root,
		UI.Round(),
	})
	UI.Stroke(t, INK).Parent = track
	local fill = frame("Fill", {
		Size = UDim2.fromScale(0, 1),
		ZIndex = z + 1,
		Parent = track,
		UI.Round(),
	})
	local gradient = UI.Gradient(set.Top, set.Bottom, 90)
	gradient.Parent = fill
	frame("Shine", {
		BackgroundTransparency = 0.45,
		Position = UDim2.new(0, 6, 0.16, 0),
		Size = UDim2.new(1, -12, 0.18, 0),
		ZIndex = z + 2,
		Parent = fill,
		UI.Round(),
	})
	local label = UI.Text({
		Name = "Label",
		Text = props.Text or "",
		TextSize = props.MaxTextSize or 22,
		Scaled = true,
		Size = UDim2.new(1, -16, 0.74, 0),
		Position = UDim2.new(0.5, 0, 0.5, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = z + 3,
		Parent = root,
	})
	if props.Parent then
		root.Parent = props.Parent
	end

	local bar = { Frame = root, Fill = fill, Label = label, Gradient = gradient, Track = track }
	function bar.Set(fraction: number, text: string?, animate: boolean?)
		fraction = math.clamp(fraction, 0, 1)
		local size = UDim2.fromScale(fraction, 1)
		if animate then
			UI.Tween(fill, 0.25, { Size = size })
		else
			fill.Size = size
		end
		fill.Visible = fraction > 0.005
		if text then
			label.Text = text
		end
	end
	function bar.SetColor(colorName: string)
		local colors = Theme.Set(colorName)
		gradient.Color = ColorSequence.new(colors.Top, colors.Bottom)
	end
	return bar
end

-- Storm jar (the tank): a glass capsule with Rain liquid, a shine stripe, bubbles drifting up, the
-- jar icon on the left and the amount in Ink. When full it glows, wobbles and shows a FULL badge.
-- props: Name, Size (W x 52), Icon (default Tank), Position, AnchorPoint, LayoutOrder, ZIndex, Parent, TextSize.
-- Returns { Frame, Track, Liquid, Label, Set(fraction, text, animate?), SetFull(bool), Step(dt) (call every frame) }
function UI.Jar(props)
	local z = props.ZIndex or 1
	local t = Theme.Outline
	local rain = Theme.Sets.Rain
	local root = frame(props.Name or "Jar", {
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromOffset(440, SIZES.JarHeight),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = z,
	})
	local glow = frame("Glow", {
		BackgroundColor3 = rain.Top,
		BackgroundTransparency = 0.5,
		Position = UDim2.fromOffset(-7, -7),
		Size = UDim2.new(1, 14, 1, 14),
		Visible = false,
		ZIndex = z,
		Parent = root,
		UI.Round(),
	})
	local haze = frame("Halo", {
		BackgroundColor3 = rain.Top,
		BackgroundTransparency = 0.75,
		Position = UDim2.fromOffset(-11, -11),
		Size = UDim2.new(1, 22, 1, 22),
		ZIndex = z,
		Parent = glow,
		UI.Round(),
	})
	shadow(root, nil, 4, z)
	local track = frame("Track", {
		BackgroundColor3 = Theme.Haze,
		Position = UDim2.fromOffset(t, t),
		Size = UDim2.new(1, -2 * t, 1, -2 * t),
		ZIndex = z + 1,
		Parent = root,
		UI.Round(),
	})
	UI.Stroke(t, INK).Parent = track
	local liquid = frame("Liquid", {
		Size = UDim2.fromScale(0, 1),
		ZIndex = z + 2,
		Parent = track,
		UI.Round(),
		UI.Gradient(rain.Top, rain.Bottom),
	})
	frame("Edge", {
		BackgroundTransparency = 0.45,
		Size = UDim2.new(0, 3, 1, -12),
		Position = UDim2.new(1, -5, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = z + 3,
		Parent = liquid,
		UI.Round(),
	})
	frame("Shine", {
		BackgroundTransparency = 0.35,
		Position = UDim2.fromOffset(35, 3),
		Size = UDim2.new(1, -49, 0, 6),
		ZIndex = z + 3,
		Parent = liquid,
		UI.Round(),
	})
	-- Bubbles: rings and dots that drift up through the liquid
	local BUBBLES = {
		{ X = 46, Size = 12, Ring = true, Speed = 0.55, Phase = 0.1 },
		{ X = 70, Size = 6, Ring = false, Speed = 0.8, Phase = 0.55 },
		{ X = 96, Size = 9, Ring = true, Speed = 0.65, Phase = 0.35 },
		{ X = 122, Size = 5, Ring = false, Speed = 0.9, Phase = 0.8 },
		{ X = 142, Size = 7, Ring = true, Speed = 0.7, Phase = 0.15 },
		{ X = 0.62, Size = 6, Ring = false, Speed = 0.75, Phase = 0.45 },
		{ X = 0.8, Size = 9, Ring = true, Speed = 0.6, Phase = 0.7 },
	}
	local bubbles = {}
	for index, spec in BUBBLES do
		local bubble = frame("Bubble" .. index, {
			BackgroundTransparency = if spec.Ring then 1 else 0.2,
			Size = UDim2.fromOffset(spec.Size, spec.Size),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = z + 3,
			Parent = liquid,
			UI.Round(),
		})
		if spec.Ring then
			UI.Stroke(2, WHITE, 0.15).Parent = bubble
		end
		table.insert(bubbles, { Frame = bubble, Spec = spec })
	end
	-- Glass glint over everything, top right
	for index, spec in { { 0.72, 0.16 }, { 0.91, 0.03 } } do
		frame("Glint" .. index, {
			BackgroundTransparency = 0.1,
			Position = UDim2.new(spec[1], 11 - 28 * spec[1], 0, 2),
			Size = UDim2.new(spec[2], -28 * spec[2], 0, 7),
			ZIndex = z + 4,
			Parent = track,
			UI.Round(),
		})
	end
	local label = UI.Text({
		Name = "Label",
		Text = "",
		TextSize = props.TextSize or 24,
		Scaled = true,
		Size = UDim2.new(1, -60, 0, 30),
		Position = UDim2.new(0.5, 15, 0.5, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = z + 5,
		Parent = root,
	})
	local iconSize = props.IconSize or 64
	local icon = Icons.New(props.Icon or "Tank", {
		Name = "Icon",
		Size = UDim2.fromOffset(iconSize, iconSize),
		Position = UDim2.new(0, -24 + iconSize / 2, 0.5, -2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = z + 6,
		Parent = root,
	})
	local fullBadge = UI.Badge(root, UDim2.new(1, 10, 0, -12))
	fullBadge.Name = "FullBadge"

	-- The icon hides the jar's left end, so the liquid fills the part to its right (a little energy
	-- still shows); `cover` px of liquid sit under the icon
	local cover = math.max(0, iconSize - 24 - t - 6) -- the icon's right edge, less its rounded side
	local jar = { Frame = root, Track = track, Liquid = liquid, Label = label, Icon = icon, Fraction = 0, Full = false }
	function jar.Set(fraction: number, text: string?, animate: boolean?)
		fraction = math.clamp(fraction, 0, 1)
		jar.Fraction = fraction
		local size = UDim2.new(fraction, (1 - fraction) * cover, 1, 0)
		if animate then
			UI.Tween(liquid, 0.25, { Size = size })
		else
			liquid.Size = size
		end
		liquid.Visible = fraction > 0.004
		if text then
			label.Text = text
		end
	end
	function jar.SetFull(full: boolean)
		if jar.Full == full then
			return
		end
		jar.Full = full
		glow.Visible = full
		if full then
			UI.SetBadge(fullBadge, "FULL")
		else
			fullBadge.Visible = false
			root.Rotation = 0
		end
	end
	-- Bubbles drift up; when full the jar wobbles and the glow pulses
	local clock = 0
	function jar.Step(dt: number)
		clock += dt
		local width = liquid.AbsoluteSize.X / scaleOf(liquid)
		for _, bubble in bubbles do
			local spec = bubble.Spec
			local x = if spec.X < 1 then spec.X * width else spec.X
			local visible = width > x + spec.Size and liquid.Visible
			bubble.Frame.Visible = visible
			if visible then
				local p = (clock * spec.Speed + spec.Phase) % 1
				local wobble = math.sin((clock + spec.Phase * 6) * 3) * 2
				bubble.Frame.Position = UDim2.new(0, x + wobble, 0.85 - p * 0.7, 0)
			end
		end
		if jar.Full then
			root.Rotation = math.sin(clock * 9) * 1.2
			local pulse = (math.sin(clock * 4) + 1) / 2
			glow.BackgroundTransparency = 0.3 + pulse * 0.25
			haze.BackgroundTransparency = 0.62 + pulse * 0.2
		end
	end
	jar.Set(0)
	jar.Step(0)
	if props.Parent then
		root.Parent = props.Parent
	end
	return jar
end

-- Returns { Frame, Set(value), Value }
function UI.Toggle(props)
	local t = Theme.OutlineSmall + 0.5
	local button = Instance.new("TextButton")
	button.Name = props.Name or "Toggle"
	button.AutoButtonColor = false
	button.Text = ""
	button.BackgroundTransparency = 1
	button.Size = props.Size or UDim2.fromOffset(86, 38)
	button.Position = props.Position or UDim2.new()
	button.AnchorPoint = props.AnchorPoint or Vector2.zero
	local track = frame("Track", {
		Position = UDim2.fromOffset(t, t),
		Size = UDim2.new(1, -2 * t, 1, -2 * t),
		Parent = button,
		UI.Round(),
	})
	UI.Stroke(t, INK).Parent = track
	local fill = UI.Gradient(WHITE, WHITE, 90)
	fill.Name = "Fill"
	fill.Parent = track

	local knob = frame("Knob", {
		Size = UDim2.new(1, -8, 1, -8),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 2,
		Parent = track,
		UI.Round(),
		UI.Gradient(Theme.Cloud, Theme.Mist),
	})
	UI.Stroke(2, INK).Parent = knob
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = knob

	local stateLabel = UI.Text({
		Name = "State",
		Text = "",
		TextSize = 18,
		Scaled = true,
		Size = UDim2.new(0.5, 0, 0.6, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 2,
		Parent = track,
	})

	local toggle = { Frame = button, Value = props.Value == true }

	function toggle.Set(value: boolean, instant: boolean?)
		toggle.Value = value
		local set = if value then Theme.Sets.Leaf else Theme.Sets.Off
		fill.Color = ColorSequence.new(if value then set.Top else Theme.Haze, if value then set.Bottom else Theme.HazeDeep)
		local knobPosition = if value then UDim2.new(1, -4, 0.5, 0) else UDim2.new(0, 4, 0.5, 0)
		knob.AnchorPoint = if value then Vector2.new(1, 0.5) else Vector2.new(0, 0.5)
		if instant then
			knob.Position = knobPosition
		else
			UI.Tween(knob, 0.15, { Position = knobPosition })
		end
		stateLabel.Text = if value then "ON" else "OFF"
		stateLabel.TextColor3 = if value then WHITE else Theme.InkSoft
		local stroke = stateLabel:FindFirstChild("TextStroke")
		if value and not stroke then
			UI.TextStroke(1.5, Theme.Sets.Leaf.Stroke).Parent = stateLabel
		elseif stroke then
			stroke.Enabled = value
		end
		stateLabel.Position = if value then UDim2.fromScale(0.34, 0.5) else UDim2.fromScale(0.66, 0.5)
	end

	button.Activated:Connect(function()
		clickSound()
		if props.OnChanged then
			props.OnChanged(not toggle.Value)
		end
	end)

	toggle.Set(toggle.Value, true)
	if props.Parent then
		button.Parent = props.Parent
	end
	return toggle
end

-- Pills inside a Haze track; the active tab is a Sky candy pill. tabs = { { Key, Text } }.
-- props: Tabs, Size (the track's height; X is sized to the tabs), TabWidth, Position, AnchorPoint,
-- ActiveColor, Parent, OnSelect. Returns { Frame, Buttons, Select(key), Selected }
function UI.Tabs(props)
	local height = props.Size and props.Size.Y or UDim.new(0, 48)
	local track = frame("Tabs", {
		BackgroundColor3 = Theme.Haze,
		Size = UDim2.new(UDim.new(0, 0), height),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Parent = props.Parent,
		UI.Round(),
		UI.List(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
		UI.Padding(4, 4, 4, 4),
	})
	local active = Theme.Set(props.ActiveColor or "Sky")
	local tabs = { Frame = track, Buttons = {}, Selected = nil }
	local parts = {}

	function tabs.Select(key: string)
		tabs.Selected = key
		for tabKey, part in parts do
			local on = tabKey == key
			part.Lip.Visible = on
			part.Label.TextColor3 = if on then WHITE else Theme.InkSoft
			part.Stroke.Enabled = on
		end
		if props.OnSelect then
			props.OnSelect(key)
		end
	end

	for index, tab in props.Tabs do
		local button = Instance.new("TextButton")
		button.Name = tab.Key
		button.AutoButtonColor = false
		button.Text = ""
		button.BackgroundTransparency = 1
		button.Size = UDim2.new(0, props.TabWidth or 140, 1, 0)
		button.LayoutOrder = index
		button.Parent = track
		local lip = candyBody(button, active, { Pill = true, Outline = Theme.Outline, Lip = 4, ZIndex = 1 })
		local label = UI.Text({
			Name = "Label",
			Text = tab.Text,
			TextSize = props.TextSize or 18,
			Scaled = true,
			Color = Theme.InkSoft,
			Size = UDim2.new(1, -16, 1, -16),
			Position = UDim2.new(0.5, 0, 0.5, -1),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 5,
			Parent = button,
		})
		local stroke = UI.TextStroke(2, active.Stroke)
		stroke.Parent = label
		parts[tab.Key] = { Lip = lip, Label = label, Stroke = stroke }
		button.Activated:Connect(function()
			clickSound()
			tabs.Select(tab.Key)
		end)
		tabs.Buttons[tab.Key] = button
	end
	for _, part in parts do
		part.Lip.Visible = false
		part.Stroke.Enabled = false
	end
	return tabs
end

-- Toast: a Cloud pill with a 2 px Ink outline and a coloured icon disk on the left; it slides down
-- and bounces once. props: Text (rich text allowed), Kind (Info, Success, Error, Warning, Reward),
-- Set / Icon (override the kind's), MaxWidth (520), LayoutOrder, Parent.
-- Returns { Frame (the slot in a list), Body, Label, Hide() }
function UI.Toast(props)
	local kind = Theme.Notifications[props.Kind or "Info"] or Theme.Notifications.Info
	local set = Theme.Set(props.Set or kind.Set)
	local iconKey = props.Icon or kind.Icon
	local text = props.Text or ""
	local t = Theme.OutlineSmall
	local height = SIZES.ToastHeight
	local textSize = SIZES.ToastText
	local maxWidth = props.MaxWidth or 520
	local textWidth = measure(plain(text), textSize, Theme.Font).X
	local wrapped = false
	local available = maxWidth - 54 - 22
	if textWidth > available then
		-- Two lines, a little smaller
		wrapped = true
		textSize = 17
		height = 64
		textWidth = math.min(available, measure(plain(text), textSize, Theme.Font).X / 1.8 + 24)
	end
	local width = math.floor(math.min(maxWidth, 54 + textWidth + 22))

	local slot = frame("Toast", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(width, height + 4),
		LayoutOrder = props.LayoutOrder or 0,
	})
	local body = frame("Body", { BackgroundTransparency = 1, Size = UDim2.fromOffset(width, height), Parent = slot })
	shadow(body, nil, 4, 1)
	local pill = frame("Pill", {
		Position = UDim2.fromOffset(t, t),
		Size = UDim2.new(1, -2 * t, 1, -2 * t),
		ZIndex = 2,
		Parent = body,
		UI.Round(),
		UI.Gradient(Theme.Cloud, Theme.Mist),
	})
	UI.Stroke(t, INK).Parent = pill
	local diskSize = 40
	local disk = frame("Disk", {
		BackgroundColor3 = INK,
		Size = UDim2.fromOffset(diskSize, diskSize),
		Position = UDim2.new(0, 4, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 3,
		Parent = body,
		UI.Round(),
	})
	frame("Fill", {
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		ZIndex = 3,
		Parent = disk,
		UI.Round(),
		UI.Gradient(set.Top, set.Bottom),
	})
	Icons.New(iconKey, { Name = "Icon", Size = UDim2.fromOffset(28, 28), ZIndex = 4, Parent = disk })
	local label = UI.Text({
		Name = "Text",
		Text = text,
		Rich = true,
		TextSize = textSize,
		Scaled = true,
		MinTextSize = 10,
		Wrapped = wrapped,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -54 - 16, 1, -10),
		Position = UDim2.new(0, 54, 0.5, 1),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 4,
		Parent = body,
	})

	-- Slide down from above and bounce once
	body.Position = UDim2.fromOffset(0, -28)
	UI.FadeIn(body, 0.15)
	UI.Tween(body, 0.42, { Position = UDim2.new() }, Enum.EasingStyle.Back)
	if props.Parent then
		slot.Parent = props.Parent
	end

	local toast = { Frame = slot, Body = body, Label = label }
	function toast.Hide(duration: number?)
		UI.Tween(body, duration or 0.3, { Position = UDim2.fromOffset(0, -10) })
		return UI.FadeOut(body, duration or 0.3)
	end
	return toast
end

return UI
