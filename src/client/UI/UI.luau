--!nonstrict
-- Small component library used to build the whole interface in code.

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local UI = {}

-- Hook set by the SoundController so every button click plays a sound
UI.ClickHook = nil :: (() -> ())?

local COLORS = Theme.Colors

---------------------------------------------------------------------------
-- Basics
---------------------------------------------------------------------------
local SKIP = { Parent = true, Stroke = true, MaxTextSize = true, MinTextSize = true }

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
	stroke.Thickness = thickness or 3
	stroke.Color = color or COLORS.Stroke
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
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
		stroke.Color = COLORS.Stroke
		stroke.Thickness = props.Stroke or 2
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

function UI.Scroll(props)
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = COLORS.SubText
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Size = UDim2.fromScale(1, 1)
	return apply(scroll, props)
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
local function setGradient(button: GuiObject, colorName: string)
	local palette = Theme.Buttons[colorName] or Theme.Buttons.Green
	local gradient = button:FindFirstChild("Fill")
	if gradient then
		gradient.Color = ColorSequence.new(palette[1], palette[2])
	end
end

function UI.SetButtonColor(button: GuiObject, colorName: string)
	setGradient(button, colorName)
	button:SetAttribute("ButtonColor", colorName)
end

function UI.SetButtonText(button: GuiObject, text: string)
	local label = button:FindFirstChild("Label")
	if label then
		label.Text = text
	end
end

-- Hover / press bounce for any GuiButton (uses a UIScale child)
function UI.Bounce(button: GuiButton, hoverScale: number?)
	local scale = button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = button
	local hover = hoverScale or 1.05
	button.MouseEnter:Connect(function()
		UI.Tween(scale, 0.12, { Scale = hover })
	end)
	button.MouseLeave:Connect(function()
		UI.Tween(scale, 0.12, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		UI.Tween(scale, 0.08, { Scale = 0.93 })
	end)
	button.MouseButton1Up:Connect(function()
		UI.Tween(scale, 0.12, { Scale = hover }, Enum.EasingStyle.Back)
	end)
	return scale
end

-- props: Text, Color, Size, Position, AnchorPoint, LayoutOrder, Parent, MaxTextSize, Image, OnClick, Name, Font
function UI.Button(props)
	local button = Instance.new("TextButton")
	button.Name = props.Name or "Button"
	button.AutoButtonColor = false
	button.Text = ""
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	button.Size = props.Size or UDim2.fromOffset(160, 50)
	button.Position = props.Position or UDim2.new()
	button.AnchorPoint = props.AnchorPoint or Vector2.zero
	button.LayoutOrder = props.LayoutOrder or 0
	button.ZIndex = props.ZIndex or 1

	UI.Corner(props.CornerRadius or 12).Parent = button
	local fill = UI.Gradient(Color3.new(1, 1, 1), Color3.new(1, 1, 1), 90)
	fill.Name = "Fill"
	fill.Parent = button
	UI.Stroke(3).Parent = button
	UI.SetButtonColor(button, props.Color or "Green")

	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.82
	shine.BorderSizePixel = 0
	shine.Size = UDim2.new(1, -10, 0.4, 0)
	shine.Position = UDim2.fromOffset(5, 3)
	shine.ZIndex = button.ZIndex
	UI.Corner((props.CornerRadius or 12) - 3).Parent = shine
	shine.Parent = button

	local labelInset = 0
	if props.Image then
		labelInset = 28
		UI.Create("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Image = props.Image,
			Size = UDim2.fromOffset(22, 22),
			Position = UDim2.new(0, 10, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			ZIndex = button.ZIndex + 1,
			Parent = button,
		})
	end

	UI.Label({
		Name = "Label",
		Text = props.Text or "",
		Font = props.Font or Theme.Font,
		Size = UDim2.new(1, -16 - labelInset, 0.68, 0),
		Position = UDim2.new(0.5, labelInset / 2, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = props.MaxTextSize or 26,
		ZIndex = button.ZIndex + 1,
		Parent = button,
	})

	UI.Bounce(button)
	button.Activated:Connect(function()
		if UI.ClickHook then
			UI.ClickHook()
		end
		if props.OnClick then
			props.OnClick()
		end
	end)

	if props.Parent then
		button.Parent = props.Parent
	end
	return button
end

---------------------------------------------------------------------------
-- Containers
---------------------------------------------------------------------------
function UI.Card(props)
	local card = Instance.new("Frame")
	card.BackgroundColor3 = Color3.new(1, 1, 1)
	card.BorderSizePixel = 0
	UI.Corner(props.CornerRadius or 14).Parent = card
	local gradient = UI.Gradient(props.Top or COLORS.Card, props.Bottom or COLORS.CardDark, 90)
	gradient.Name = "Fill"
	gradient.Parent = card
	local stroke = UI.Stroke(props.StrokeThickness or 2, props.StrokeColor or COLORS.Stroke, props.StrokeTransparency or 0.2)
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

-- Emoji inside a colored circle
function UI.Icon(props)
	local holder = Instance.new("Frame")
	holder.BackgroundColor3 = props.Color or COLORS.Card
	holder.Size = props.Size or UDim2.fromOffset(56, 56)
	holder.Position = props.Position or UDim2.new()
	holder.AnchorPoint = props.AnchorPoint or Vector2.zero
	holder.LayoutOrder = props.LayoutOrder or 0
	UI.Round().Parent = holder
	UI.Stroke(2.5).Parent = holder
	UI.Gradient(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 205), 90).Parent = holder
	UI.Label({
		Name = "Glyph",
		Text = props.Text or "⚡",
		Stroke = false,
		Size = UDim2.fromScale(0.68, 0.68),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = holder,
	})
	if props.Parent then
		holder.Parent = props.Parent
	end
	return holder
end

-- A titled window. Returns { Frame, Content, Title, Close, Scale }
function UI.Window(props)
	local accent = props.Color or "Blue"
	local palette = Theme.Buttons[accent] or Theme.Buttons.Blue

	-- A button (not a Frame) so clicks on empty window space never reach the Dim behind it,
	-- which would close the panel
	local frame = Instance.new("TextButton")
	frame.Name = props.Name or "Window"
	frame.AutoButtonColor = false
	frame.Selectable = false
	frame.Text = ""
	frame.Size = props.Size or UDim2.fromOffset(660, 460)
	frame.Position = UDim2.fromScale(0.5, 0.52)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.Visible = false
	UI.Corner(20).Parent = frame
	UI.Gradient(COLORS.PanelTop, COLORS.PanelBottom, 90).Parent = frame
	UI.Stroke(4).Parent = frame
	local scale = Instance.new("UIScale")
	scale.Parent = frame

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, -20, 0, 56)
	header.Position = UDim2.fromOffset(10, 10)
	header.BackgroundColor3 = Color3.new(1, 1, 1)
	header.Parent = frame
	UI.Corner(14).Parent = header
	UI.Gradient(palette[1], palette[2], 90).Parent = header
	UI.Stroke(3).Parent = header

	local title = UI.Label({
		Name = "Title",
		Text = (props.Icon and (props.Icon .. "  ") or "") .. (props.Title or ""),
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -90, 0.66, 0),
		Position = UDim2.new(0, 18, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Stroke = 3,
		MaxTextSize = 32,
		Parent = header,
	})

	local close = UI.Button({
		Name = "Close",
		Text = "✕",
		Color = "Red",
		Size = UDim2.fromOffset(50, 50),
		Position = UDim2.new(1, 8, 0, -8),
		AnchorPoint = Vector2.new(1, 0),
		MaxTextSize = 30,
		Parent = frame,
	})

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, -28, 1, -84)
	content.Position = UDim2.fromOffset(14, 74)
	content.Parent = frame

	return { Frame = frame, Content = content, Title = title, Close = close, Scale = scale }
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
-- Returns { Frame, Fill, Label, Set(fraction, text) }
function UI.ProgressBar(props)
	local palette = Theme.Buttons[props.Color or "Blue"] or Theme.Buttons.Blue
	local frame = Instance.new("Frame")
	frame.Name = props.Name or "ProgressBar"
	frame.Size = props.Size or UDim2.fromOffset(300, 28)
	frame.Position = props.Position or UDim2.new()
	frame.AnchorPoint = props.AnchorPoint or Vector2.zero
	frame.BackgroundColor3 = COLORS.Inset
	frame.LayoutOrder = props.LayoutOrder or 0
	UI.Round().Parent = frame
	UI.Stroke(props.StrokeThickness or 3).Parent = frame

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	UI.Round().Parent = fill
	local gradient = UI.Gradient(palette[1], palette[2], 90)
	gradient.Parent = fill
	fill.Parent = frame

	local label = UI.Label({
		Name = "Label",
		Text = props.Text or "",
		Size = UDim2.new(1, -16, 0.72, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = props.MaxTextSize or 22,
		ZIndex = 3,
		Parent = frame,
	})

	if props.Parent then
		frame.Parent = props.Parent
	end

	local bar = { Frame = frame, Fill = fill, Label = label, Gradient = gradient }
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
		local colors = Theme.Buttons[colorName] or Theme.Buttons.Blue
		gradient.Color = ColorSequence.new(colors[1], colors[2])
	end
	return bar
end

-- Returns { Frame, Set(value), Value }
function UI.Toggle(props)
	local button = Instance.new("TextButton")
	button.Name = props.Name or "Toggle"
	button.AutoButtonColor = false
	button.Text = ""
	button.Size = props.Size or UDim2.fromOffset(86, 38)
	button.Position = props.Position or UDim2.new()
	button.AnchorPoint = props.AnchorPoint or Vector2.zero
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	UI.Round().Parent = button
	UI.Stroke(3).Parent = button
	local fill = UI.Gradient(Color3.new(1, 1, 1), Color3.new(1, 1, 1), 90)
	fill.Name = "Fill"
	fill.Parent = button

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.Size = UDim2.new(0, 30, 0, 30)
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	UI.Round().Parent = knob
	UI.Stroke(2).Parent = knob
	knob.Parent = button

	local stateLabel = UI.Label({
		Name = "State",
		Text = "",
		Size = UDim2.new(0.5, 0, 0.6, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 18,
		Parent = button,
	})

	local toggle = { Frame = button, Value = props.Value == true }

	function toggle.Set(value: boolean, instant: boolean?)
		toggle.Value = value
		local palette = if value then Theme.Buttons.Green else Theme.Buttons.Gray
		fill.Color = ColorSequence.new(palette[1], palette[2])
		local knobPosition = if value then UDim2.new(1, -34, 0.5, 0) else UDim2.new(0, 4, 0.5, 0)
		if instant then
			knob.Position = knobPosition
		else
			UI.Tween(knob, 0.15, { Position = knobPosition })
		end
		stateLabel.Text = if value then "ON" else "OFF"
		stateLabel.Position = if value then UDim2.fromScale(0.34, 0.5) else UDim2.fromScale(0.66, 0.5)
	end

	button.Activated:Connect(function()
		if UI.ClickHook then
			UI.ClickHook()
		end
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

-- Row of tab buttons. tabs = { { Key, Text } }. Returns { Frame, Select(key), Selected }
function UI.Tabs(props)
	local frame = Instance.new("Frame")
	frame.Name = "Tabs"
	frame.BackgroundTransparency = 1
	frame.Size = props.Size or UDim2.new(1, 0, 0, 42)
	frame.Position = props.Position or UDim2.new()
	UI.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center).Parent = frame

	local tabs = { Frame = frame, Buttons = {}, Selected = nil }

	function tabs.Select(key: string)
		tabs.Selected = key
		for tabKey, button in tabs.Buttons do
			UI.SetButtonColor(button, if tabKey == key then (props.Color or "Blue") else "Dark")
		end
		if props.OnSelect then
			props.OnSelect(key)
		end
	end

	for index, tab in props.Tabs do
		local button = UI.Button({
			Name = tab.Key,
			Text = tab.Text,
			Color = "Dark",
			Size = UDim2.new(0, props.TabWidth or 140, 1, -4),
			LayoutOrder = index,
			MaxTextSize = 20,
			Parent = frame,
			OnClick = function()
				tabs.Select(tab.Key)
			end,
		})
		tabs.Buttons[tab.Key] = button
	end

	if props.Parent then
		frame.Parent = props.Parent
	end
	return tabs
end

-- Small red badge with a number (or "!") in the corner of a button
function UI.Badge(parent: GuiObject)
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.Size = UDim2.fromOffset(26, 26)
	badge.Position = UDim2.new(1, 6, 0, -6)
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.BackgroundColor3 = Color3.fromRGB(255, 70, 90)
	badge.Visible = false
	badge.ZIndex = 5
	UI.Round().Parent = badge
	UI.Stroke(2.5).Parent = badge
	UI.Label({
		Name = "Count",
		Text = "!",
		Size = UDim2.fromScale(0.7, 0.7),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 6,
		Parent = badge,
	})
	badge.Parent = parent
	return badge
end

-- Pops an element (scale bounce)
function UI.Pop(guiObject: GuiObject, amount: number?)
	local scale = guiObject:FindFirstChild("PopScale") or Instance.new("UIScale")
	scale.Name = "PopScale"
	scale.Parent = guiObject
	scale.Scale = amount or 1.15
	UI.Tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

return UI
