--!nonstrict
-- World prompts in the Sky Lab look (docs/STYLE_GUIDE.md section 2), and the egg incubators.
--
-- 1. Prompt cards. Every ProximityPrompt is switched to Style = Custom on this client (the ones in the
--    world now and any added later) and drawn as our own card, in a BillboardGui over the prompt's part,
--    whenever Roblox says it should show (ProximityPromptService.PromptShown / PromptHidden):
--
--        ( E )  Storm Shop    (bag)    a Cloud pill with an Ink outline: a round key cap (the keyboard
--               Open                   key, the gamepad button, or TAP on touch screens), the ObjectText
--                                      small and the ActionText in bold Fredoka, and the place's 3D icon
--                                      over the right end (attribute PromptIcon, a ProductKey's product
--                                      icon, or the Panel it opens)
--
--    Holding a hold prompt fills the pill, pressing pushes the cap down and pops the card, and tapping or
--    clicking the card works like the key (InputHoldBegin / InputHoldEnd), so phones and mice can use it.
--    Cards fade in and out, keep the same size on screen at any distance (scaled like the HUD), always
--    draw on top, and sit above the prompt's part so they never cover the player in front of it.
--
--    Zone gates (tag "GatePrompt", attribute GateZone) get the zone card instead: the zone's 3D emblem
--    (Icons "Zone_<Key>") and name, its price in a Volts capsule (green when you can pay, grey with a
--    padlock when you can't) and the Power it needs (coral until you have it), over a candy "Unlock" bar
--    that fills while you hold. It replaced the gate's old "LockInfo" billboard.
--
--    A prompt keeps Roblox's own look when it has the attribute DefaultPromptStyle = true, or if its card
--    fails to build (then it goes back to the default style, so it can always be used).
--
-- 2. Egg incubators have no prompt to press. Walking up to one (EggOpenDistance, flat, from
--    MapLayout.EggStation) opens the Egg panel for its egg, walking away (EggCloseDistance, a few studs
--    further so it doesn't flicker at the edge) closes it again. It never opens over another panel, a
--    dialog or the Roblox menu, or while an egg is hatching (Hatch overlay, hatching / auto hatching).
--    Closing it yourself (X, the dim, another panel) next to the incubator keeps it shut until you
--    leave and come back. Walking from one incubator to another switches the panel to the new egg. A
--    panel opened from the HUD's Eggs button (from anywhere) is only closed by walking away once you
--    have been at that incubator with it open. After a hatch the Egg panel reopens itself while you're
--    still at the incubator (Panels/Egg asks PromptController.IsNearEgg). The incubators' old "Open Egg"
--    prompts (attribute EggId) are switched off here, so no E box shows.
--    PromptController.EggStep is the decision logic on its own (no Roblox state), for tests.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Pets = require(Shared.Config.Pets)
local MapLayout = require(Shared.Config.MapLayout)
local Monetization = require(Shared.Config.Monetization)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)

local Registry = require(script.Parent.Parent.Registry)
local UIFolder = script.Parent.Parent.UI
local UI = require(UIFolder.UI)
local Theme = require(UIFolder.Theme)
local Icons = require(UIFolder.Icons)

local PromptController = {}

PromptController.EggOpenDistance = 16 -- studs (flat) from an incubator: its Egg panel opens
PromptController.EggCloseDistance = 21 -- ... and closes again past this
PromptController.EggTick = 0.12 -- seconds between checks (~8 Hz)

local INK = Theme.Ink
local WHITE = Color3.new(1, 1, 1)
local SETS = Theme.Sets
local T = Theme.Outline -- 3 px Ink outline
local SHADOW = 5 -- drop shadow offset
local LIFT = 3 -- studs between the prompt's part and the card's bottom edge (above a player's head)

local player = Players.LocalPlayer

---------------------------------------------------------------------------
-- Small builders
---------------------------------------------------------------------------
local function frame(name: string, props)
	local object = Instance.new("Frame")
	object.Name = name
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

local function textWidth(text: string, size: number, font: Enum.Font): number
	if text == "" then
		return 0
	end
	local ok, bounds = pcall(TextService.GetTextSize, TextService, text, size, font, Vector2.new(4096, 4096))
	if ok and typeof(bounds) == "Vector2" then
		return math.ceil(bounds.X)
	end
	return math.ceil((utf8.len(text) or #text) * size * 0.56)
end

local function shadowOf(parent: Instance, radius: number?, z: number)
	return frame("Shadow", {
		BackgroundColor3 = INK,
		BackgroundTransparency = Theme.ShadeTransparency,
		Position = UDim2.fromOffset(0, SHADOW),
		Size = UDim2.new(1, 0, 1, -SHADOW),
		ZIndex = z,
		Parent = parent,
		if radius then UI.Corner(radius) else UI.Round(),
	})
end

-- Cloud -> Mist body with the Ink outline drawn inside `parent`'s box (minus the shadow)
local function cloudBody(parent: Instance, radius: number?, z: number)
	local body = frame("Body", {
		Position = UDim2.fromOffset(T, T),
		Size = UDim2.new(1, -2 * T, 1, -2 * T - SHADOW),
		ZIndex = z,
		Parent = parent,
		if radius then UI.Corner(math.max(radius - T, 2)) else UI.Round(),
		UI.Gradient(Theme.Cloud, Theme.Mist),
	})
	local outline = UI.Stroke(T, INK)
	outline.Name = "Outline"
	outline.Parent = body
	return body
end

---------------------------------------------------------------------------
-- The key cap: what to press, for the input the prompt is shown for
---------------------------------------------------------------------------
local GAMEPAD_LABELS = {
	ButtonA = { "A", SETS.Leaf.Bottom },
	ButtonB = { "B", SETS.Coral.Bottom },
	ButtonX = { "X", SETS.Sky.Bottom },
	ButtonY = { "Y", Color3.fromHex("E09A00") },
	ButtonL1 = { "LB" },
	ButtonR1 = { "RB" },
	ButtonL2 = { "LT" },
	ButtonR2 = { "RT" },
	ButtonL3 = { "L3" },
	ButtonR3 = { "R3" },
	DPadUp = { "↑" },
	DPadDown = { "↓" },
	DPadLeft = { "←" },
	DPadRight = { "→" },
}

-- { Text, Color, TextSize, Image } for a prompt's key on this input
function PromptController.KeyFor(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType?)
	if inputType == Enum.ProximityPromptInputType.Touch then
		return { Text = "TAP", TextSize = 14 }
	end
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		local code = prompt.GamepadKeyCode
		-- the console's own button picture (Xbox / PlayStation) when Roblox has one
		local ok, image = pcall(UserInputService.GetImageForKeyCode, UserInputService, code)
		local known = GAMEPAD_LABELS[code.Name]
		if ok and type(image) == "string" and image ~= "" then
			return { Text = if known then known[1] else "", Image = image, Color = known and known[2] }
		end
		if known then
			return { Text = known[1], Color = known[2], TextSize = if #known[1] > 1 then 18 else 24 }
		end
		return { Text = (string.gsub(code.Name, "^Button", "")), TextSize = 16 }
	end
	local code = prompt.KeyboardKeyCode
	local ok, text = pcall(UserInputService.GetStringForKeyCode, UserInputService, code)
	if not ok or type(text) ~= "string" or text == "" then
		text = code.Name
	end
	text = string.upper(text)
	if #text > 3 then
		text = string.sub(text, 1, 3) -- a long key name (LeftShift): its start fits the cap
	end
	local size = if utf8.len(text) == 1 then 24 elseif #text <= 3 then 17 else 12
	return { Text = text, TextSize = size }
end

-- Round key cap: an Ink outline around a Haze lip with a white face on it, the key in Ink Fredoka.
-- Returns { Frame, Press(down) }.
local function keyCap(parent: Instance, size: number, key, z: number, position: UDim2, anchor: Vector2?)
	local holder = frame("KeyCap", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Position = position,
		AnchorPoint = anchor or Vector2.new(0, 0.5),
		ZIndex = z,
		Parent = parent,
	})
	local lipHeight = math.max(3, math.floor(size * 0.09 + 0.5))
	local lip = frame("Lip", {
		BackgroundColor3 = Theme.HazeDeep,
		Position = UDim2.fromOffset(T, T),
		Size = UDim2.new(1, -2 * T, 1, -2 * T),
		ZIndex = z,
		Parent = holder,
		UI.Round(),
	})
	local outline = UI.Stroke(T, INK)
	outline.Name = "Outline"
	outline.Parent = lip
	local face = frame("Face", {
		Size = UDim2.new(1, 0, 1, -lipHeight),
		ZIndex = z + 1,
		Parent = lip,
		UI.Round(),
		UI.Gradient(Theme.Cloud, Theme.Mist),
	})
	local label = UI.Text({
		Name = "Key",
		Text = key.Text,
		TextSize = key.TextSize or 24,
		Color = key.Color or INK,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, 1),
		ZIndex = z + 2,
		Parent = face,
	})
	if key.Image then
		label.Visible = false
		UI.Create("ImageLabel", {
			Name = "Button",
			BackgroundTransparency = 1,
			Image = key.Image,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(0.72, 0.72),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = z + 2,
			Parent = face,
		})
	end
	local cap = { Frame = holder }
	function cap.Press(down: boolean)
		local push = if down then lipHeight - 1 else 0
		lip.Position = UDim2.fromOffset(T, T + push)
		lip.Size = UDim2.new(1, -2 * T, 1, -2 * T - push)
		face.Size = UDim2.new(1, 0, 1, -(lipHeight - push))
	end
	return cap
end

---------------------------------------------------------------------------
-- Cards
---------------------------------------------------------------------------
-- An icon for a prompt's card: attribute PromptIcon, the product a ProductKey sells, or the Panel it opens
function PromptController.IconFor(prompt: Instance): string?
	local key = prompt:GetAttribute("PromptIcon")
	if type(key) == "string" and Icons.Has(key) then
		return key
	end
	local productKey = prompt:GetAttribute("ProductKey")
	local product = type(productKey) == "string" and Monetization.Products[productKey]
	if product and type(product.Icon) == "string" and Icons.Has(product.Icon) then
		return product.Icon
	end
	local panel = prompt:GetAttribute("Panel")
	if type(panel) == "string" and Icons.Has(panel) then
		return panel
	end
	return nil
end

local function data()
	local controller = Registry.DataController
	return controller and controller.Data
end

-- What a zone gate needs from the player right now
function PromptController.GateState(zoneId: number)
	local zone = Zones[zoneId]
	local current = data()
	local volts = current and current.Volts or 0
	local power = if current then Formulas.Power(current) else 0
	local unlocked = current and current.Zone or 1
	return {
		Zone = zone,
		Affordable = zone ~= nil and volts >= zone.Cost,
		PowerMet = zone ~= nil and power >= zone.MinPower,
		Next = zoneId <= unlocked + 1, -- the gate after the last zone you unlocked
		Previous = Zones[unlocked + 1], -- the zone to unlock first when this gate isn't the next one
	}
end

-- Generic card: [cap] ObjectText / ActionText (icon). Returns the card table (see buildCard).
local CARD_HEIGHT = 60 -- body + outline (the shadow comes on top of this)
local CAP = 46
local ICON = 50
local MIN_WIDTH, MAX_WIDTH = 150, 330

local function genericCard(prompt: ProximityPrompt, key, root: Frame)
	local action = prompt.ActionText
	local object = prompt.ObjectText
	local icon = PromptController.IconFor(prompt)
	local hasObject = object ~= ""
	local actionSize = if hasObject then 23 else 25
	local left = T + 6 + CAP + 10 -- text column start (from the card's left edge)
	local right = if icon then ICON - 8 else 18
	local textW = math.max(textWidth(action, actionSize, Theme.Font), textWidth(object, 14, Theme.BodyFont))
	local bodyWidth = math.clamp(left + textW + right, MIN_WIDTH, MAX_WIDTH)
	local overhang = if icon then math.floor(ICON / 2) - 4 else 0
	local width, height = bodyWidth + overhang, CARD_HEIGHT + SHADOW
	root.Size = UDim2.fromOffset(width, height)

	local pill = frame("Pill", { BackgroundTransparency = 1, Size = UDim2.fromOffset(bodyWidth, height), ZIndex = 1, Parent = root })
	shadowOf(pill, nil, 1)
	local body = cloudBody(pill, nil, 2)

	-- hold fill: a Leaf pill growing from under the key cap
	local capRight = 6 + CAP - T
	local fill = frame("HoldFill", {
		BackgroundColor3 = SETS.Leaf.Tint2,
		Size = UDim2.new(0, capRight, 1, 0),
		Visible = prompt.HoldDuration > 0,
		ZIndex = 3,
		Parent = body,
		UI.Round(),
		UI.Gradient(SETS.Leaf.Tint, SETS.Leaf.Tint2),
	})

	local cap = keyCap(pill, CAP, key, 6, UDim2.new(0, T + 6, 0.5, -math.floor(SHADOW / 2)))

	local textRight = bodyWidth - right
	local textBox = UDim2.fromOffset(textRight - left, 0)
	local objectLabel = UI.Text({
		Name = "ObjectText",
		Text = object,
		Font = Theme.BodyFont,
		TextSize = 14,
		Color = Theme.InkSoft,
		X = Enum.TextXAlignment.Left,
		Size = textBox + UDim2.fromOffset(0, 16),
		Position = UDim2.fromOffset(left, 11),
		Visible = hasObject,
		ZIndex = 5,
		Parent = pill,
	})
	objectLabel.TextTruncate = Enum.TextTruncate.AtEnd
	local actionLabel = UI.Text({
		Name = "ActionText",
		Text = action,
		TextSize = actionSize,
		X = Enum.TextXAlignment.Left,
		Size = textBox + UDim2.fromOffset(0, 28),
		Position = if hasObject then UDim2.fromOffset(left, 26) else UDim2.new(0, left, 0.5, -math.floor(SHADOW / 2)),
		AnchorPoint = if hasObject then Vector2.zero else Vector2.new(0, 0.5),
		ZIndex = 5,
		Parent = pill,
	})
	actionLabel.TextTruncate = Enum.TextTruncate.AtEnd

	if icon then
		Icons.New(icon, {
			Name = "PlaceIcon",
			Size = UDim2.fromOffset(ICON, ICON),
			Position = UDim2.new(0, bodyWidth - 8, 0.5, -math.floor(SHADOW / 2)),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 6,
			Parent = root,
		})
	end

	local fullWidth = bodyWidth - 2 * T
	return {
		Cap = cap,
		Fill = fill,
		FillFrom = capRight,
		FillTo = fullWidth,
		Width = width,
		Height = height,
	}
end

-- Zone gate card
local GATE_EMBLEM = 88
local GATE_WIDTH_MIN = 300

local function gateCard(prompt: ProximityPrompt, key, root: Frame)
	local zoneId = prompt:GetAttribute("GateZone")
	local zone = Zones[zoneId]
	local state = PromptController.GateState(zoneId)
	local priceText = Format.Number(zone.Cost)
	local powerText = "Needs " .. Format.Number(zone.MinPower) .. " Power"
	local requirement = if state.Next or not state.Previous then powerText else "Unlock " .. state.Previous.Name .. " first"

	-- Layout (px): the emblem overlaps the body's left edge, the ZONE chip sits on its top edge
	local bodyX, bodyY = 30, 12 -- body's top-left in the card
	local emblemX = bodyX - 24
	local columnX = emblemX + GATE_EMBLEM + 6 -- text column, right of the emblem
	local nameSize = 26
	local nameW = textWidth(zone.Name, nameSize, Theme.Font)
	local priceW = 30 + textWidth(priceText, 20, Theme.Font) + 14
	local requirementW = 24 + 4 + textWidth(requirement, 14, Theme.BodyFont)
	local rowW = priceW + 12 + requirementW
	local bodyWidth = math.max(GATE_WIDTH_MIN, columnX - bodyX + math.max(nameW, rowW) + 16)
	local bodyHeight = 136
	local width, height = bodyX + bodyWidth, bodyY + bodyHeight + SHADOW
	root.Size = UDim2.fromOffset(width, height)

	local card = frame("Gate", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(bodyWidth, bodyHeight + SHADOW),
		Position = UDim2.fromOffset(bodyX, bodyY),
		ZIndex = 1,
		Parent = root,
	})
	shadowOf(card, 22, 1)
	cloudBody(card, 22, 2)

	-- the zone's 3D emblem (a medallion of its own) over the left edge, with a soft shadow
	local emblemKey = "Zone_" .. tostring(zone.Key)
	local emblem = frame("Emblem", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(GATE_EMBLEM, GATE_EMBLEM),
		Position = UDim2.fromOffset(emblemX, bodyY - 8),
		ZIndex = 7,
		Parent = root,
	})
	frame("Shadow", {
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.82,
		Size = UDim2.new(1, -10, 1, -10),
		Position = UDim2.new(0.5, 0, 0.5, 5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 7,
		Parent = emblem,
		UI.Round(),
	})
	if Icons.Has(emblemKey) then
		Icons.New(emblemKey, { Name = "Icon", Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = emblem })
	else
		-- no emblem for this zone: its emoji on a disc in the zone's colour
		UI.Icon({ Text = zone.Icon, Color = zone.Color, Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4), ZIndex = 8, Parent = emblem })
	end

	-- ZONE n chip on the top edge
	local chipText = "ZONE " .. tostring(zoneId)
	local chipW = textWidth(chipText, 14, Theme.Font) + 22
	local chip = frame("Chip", {
		BackgroundColor3 = INK,
		Size = UDim2.fromOffset(chipW, 24),
		Position = UDim2.fromOffset(columnX, bodyY - 11),
		ZIndex = 6,
		Parent = root,
		UI.Round(),
	})
	frame("Fill", {
		BackgroundColor3 = zone.Color,
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		ZIndex = 6,
		Parent = chip,
		UI.Round(),
		UI.Gradient(zone.Color:Lerp(WHITE, 0.25), Theme.Shade(zone.Color, 0.85)),
	})
	UI.Text({
		Name = "Text",
		Text = chipText,
		TextSize = 14,
		Stroke = Theme.Shade(zone.Color, 0.45),
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, 1),
		ZIndex = 7,
		Parent = chip,
	})

	local x = columnX - bodyX -- inside `card`
	UI.Text({
		Name = "ZoneName",
		Text = zone.Name,
		TextSize = nameSize,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(bodyWidth - x - 14, 30),
		Position = UDim2.fromOffset(x, 18),
		ZIndex = 5,
		Parent = card,
	})

	-- price capsule: Volts icon over its left end; Leaf when you can pay, grey with a padlock when not
	local price = frame("Price", {
		BackgroundColor3 = INK,
		Size = UDim2.fromOffset(priceW, 30),
		Position = UDim2.fromOffset(x + 4, 54),
		ZIndex = 5,
		Parent = card,
		UI.Round(),
	})
	local priceFill = frame("Fill", {
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		ZIndex = 5,
		Parent = price,
		UI.Round(),
	})
	local priceGradient = UI.Gradient(SETS.Leaf.Top, SETS.Leaf.Bottom)
	priceGradient.Parent = priceFill
	local priceIcon = Icons.New("Volts", {
		Name = "Icon",
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.new(0, -8, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 7,
		Parent = price,
	})
	local priceLabel = UI.Text({
		Name = "Amount",
		Text = priceText,
		TextSize = 20,
		Stroke = SETS.Leaf.Stroke,
		Size = UDim2.new(1, -30, 1, 0),
		Position = UDim2.fromOffset(26, 1),
		ZIndex = 6,
		Parent = price,
	})
	local priceStroke = priceLabel:FindFirstChildOfClass("UIStroke")

	-- Power it needs
	local need = frame("Requirement", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(requirementW, 30),
		Position = UDim2.fromOffset(x + 4 + priceW + 12, 54),
		ZIndex = 5,
		Parent = card,
	})
	local needIcon = Icons.New("Power", {
		Name = "Icon",
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(0, -1, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 6,
		Parent = need,
	})
	local needLabel = UI.Text({
		Name = "Text",
		Text = requirement,
		Font = Theme.BodyFont,
		TextSize = 14,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -28, 1, 0),
		Position = UDim2.fromOffset(28, 0),
		ZIndex = 6,
		Parent = need,
	})

	-- action bar: a candy pill with the key cap at its left; fills while you hold
	local barY = 92
	local bar = frame("Action", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 0, 40),
		Position = UDim2.fromOffset(12, barY - 2),
		ZIndex = 4,
		Parent = card,
	})
	local barLip = frame("Lip", {
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		ZIndex = 4,
		Parent = bar,
		UI.Round(),
	})
	local barOutline = UI.Stroke(2.5, INK)
	barOutline.Parent = barLip
	local barFace = frame("Face", {
		Size = UDim2.new(1, 0, 1, -4),
		ZIndex = 5,
		Parent = barLip,
		UI.Round(),
	})
	local barGradient = UI.Gradient(SETS.Leaf.Top, SETS.Leaf.Bottom)
	barGradient.Parent = barFace
	frame("Shine", {
		BackgroundTransparency = 0.75,
		Position = UDim2.fromOffset(46, 3),
		Size = UDim2.new(1, -60, 0.32, 0),
		ZIndex = 6,
		Parent = barFace,
		UI.Round(),
	})
	local barWidth = bodyWidth - 24 - 4 -- the bar face (the card less its margins and the outline)
	local fill = frame("HoldFill", {
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.4,
		Size = UDim2.new(0, 34, 1, 0),
		Visible = prompt.HoldDuration > 0,
		ZIndex = 6,
		Parent = barFace,
		UI.Round(),
	})
	local actionLabel = UI.Text({
		Name = "ActionText",
		Text = prompt.ActionText,
		TextSize = 21,
		Stroke = SETS.Leaf.Stroke,
		Size = UDim2.new(1, -44, 1, 0),
		Position = UDim2.fromOffset(40, 1),
		ZIndex = 7,
		Parent = barFace,
	})
	local actionStroke = actionLabel:FindFirstChildOfClass("UIStroke")
	local cap = keyCap(bar, 40, { Text = key.Text, TextSize = math.min(key.TextSize or 22, 22), Color = key.Color, Image = key.Image }, 8, UDim2.new(0, -6, 0.5, -1))

	local function refresh()
		local now = PromptController.GateState(zoneId)
		local ready = now.Affordable and now.PowerMet and now.Next
		local priceSet = if now.Affordable then SETS.Leaf else SETS.Off
		priceGradient.Color = ColorSequence.new(priceSet.Top, priceSet.Bottom)
		Icons.Set(priceIcon, if now.Affordable then "Volts" else "Lock")
		if priceStroke then
			priceStroke.Color = priceSet.Stroke
		end
		local requirementText = if now.Next or not now.Previous then powerText else "Unlock " .. now.Previous.Name .. " first"
		needLabel.Text = requirementText
		local met = now.PowerMet and now.Next
		needLabel.TextColor3 = if met then Theme.Up else SETS.Coral.Bottom
		Icons.Set(needIcon, if met then "Check" else (if now.Next then "Power" else "Lock"))
		local barSet = if ready then SETS.Leaf else SETS.Off
		barGradient.Color = ColorSequence.new(barSet.Top, barSet.Bottom)
		barLip.BackgroundColor3 = barSet.Lip
		if actionStroke then
			actionStroke.Color = barSet.Stroke
		end
	end
	refresh()

	return {
		Cap = cap,
		Fill = fill,
		FillFrom = 34,
		FillTo = barWidth,
		Width = width,
		Height = height,
		Refresh = refresh,
		Gate = true,
	}
end

-- Builds a prompt's card inside `parent` (a GuiObject or a BillboardGui) at `scale`.
-- Returns { Frame, Width, Height (px at scale 1), Press(down), Pop(), SetHold(fraction, seconds?), Refresh() }
function PromptController.BuildCard(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType?, parent: Instance, scale: number?)
	local k = scale or 1
	local holder = frame("Card", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(100, 60),
		ZIndex = 1,
		Parent = parent,
	})
	local fit = Instance.new("UIScale")
	fit.Name = "Fit"
	fit.Scale = k
	fit.Parent = holder
	local root = frame("Root", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 1,
		Parent = holder,
	})
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = root

	local key = PromptController.KeyFor(prompt, inputType)
	local gateZone = prompt:GetAttribute("GateZone")
	local isGate = CollectionService:HasTag(prompt, "GatePrompt") and type(gateZone) == "number" and Zones[gateZone] ~= nil
	local parts = if isGate then gateCard(prompt, key, root) else genericCard(prompt, key, root)
	holder.Size = UDim2.fromOffset(parts.Width, parts.Height)
	root.Size = UDim2.fromScale(1, 1)

	local card = { Frame = holder, Width = parts.Width, Height = parts.Height, Gate = parts.Gate == true }
	local holdTween = nil
	function card.Press(down: boolean)
		parts.Cap.Press(down)
	end
	function card.Pop()
		pop.Scale = 1.08
		UI.Tween(pop, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	-- fraction 0..1 of the hold, reached over `seconds` (instantly without)
	function card.SetHold(fraction: number, seconds: number?)
		local fill = parts.Fill
		if not fill.Parent then
			return
		end
		if holdTween then
			holdTween:Cancel()
			holdTween = nil
		end
		local goal = UDim2.new(0, parts.FillFrom + (parts.FillTo - parts.FillFrom) * math.clamp(fraction, 0, 1), 1, 0)
		if seconds and seconds > 0 then
			holdTween = UI.Tween(fill, seconds, { Size = goal }, Enum.EasingStyle.Linear)
		else
			fill.Size = goal
		end
	end
	function card.Refresh()
		if parts.Refresh then
			parts.Refresh()
		end
	end
	return card
end

---------------------------------------------------------------------------
-- Showing cards for prompts
---------------------------------------------------------------------------
local cardGui: ScreenGui? = nil
local shown = {} -- [prompt] = { Billboard, Card, Connections, Input }

local function cardScale(): number
	local interface = Registry.InterfaceController
	local hud = interface and interface.HudScale or 1
	return math.clamp(hud, 0.82, 1.1)
end

local function adorneeOf(prompt: ProximityPrompt): Instance?
	local parent = prompt.Parent
	if parent and (parent:IsA("BasePart") or parent:IsA("Attachment")) then
		return parent
	end
	if parent and parent:IsA("Model") then
		return parent.PrimaryPart
	end
	return nil
end

local function hide(prompt: ProximityPrompt, instant: boolean?)
	local entry = shown[prompt]
	if not entry then
		return
	end
	shown[prompt] = nil
	for _, connection in entry.Connections do
		connection:Disconnect()
	end
	local billboard = entry.Billboard
	if instant then
		billboard:Destroy()
		return
	end
	local pop = entry.Card.Frame:FindFirstChild("Pop", true)
	if pop then
		UI.Tween(pop, 0.16, { Scale = 0.85 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	UI.FadeOut(billboard, 0.16)
	task.delay(0.2, function()
		billboard:Destroy()
	end)
end

local function show(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	hide(prompt, true)
	local adornee = adorneeOf(prompt)
	if not adornee or not cardGui then
		return
	end
	local scale = cardScale()
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PromptCard"
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	billboard.Adornee = adornee
	-- the card's bottom edge LIFT studs over the part (StudsOffsetWorldSpace + SizeOffset), so it sits
	-- above the player standing in front of it
	local lift = prompt:GetAttribute("CardLift")
	billboard.StudsOffsetWorldSpace = Vector3.new(0, if type(lift) == "number" then lift else LIFT, 0)
	billboard.SizeOffset = Vector2.new(0, 0.5)

	local card = PromptController.BuildCard(prompt, inputType, billboard, scale)
	billboard.Size = UDim2.fromOffset(math.ceil(card.Width * scale), math.ceil(card.Height * scale))

	local connections = {}
	local entry = { Billboard = billboard, Card = card, Connections = connections }

	-- tap / click on the card = the key (InputHoldBegin / InputHoldEnd)
	if inputType == Enum.ProximityPromptInputType.Touch or prompt.ClickablePrompt then
		local button = Instance.new("TextButton")
		button.Name = "Hit"
		button.BackgroundTransparency = 1
		button.Text = ""
		button.Size = UDim2.fromScale(1, 1)
		button.ZIndex = 50
		button.Parent = billboard
		local down = false
		table.insert(connections, button.InputBegan:Connect(function(input)
			local kind = input.UserInputType
			if (kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1) and input.UserInputState ~= Enum.UserInputState.Change then
				down = true
				card.Press(true)
				prompt:InputHoldBegin()
			end
		end))
		table.insert(connections, button.InputEnded:Connect(function(input)
			local kind = input.UserInputType
			if (kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1) and down then
				down = false
				card.Press(false)
				prompt:InputHoldEnd()
			end
		end))
		billboard.Active = true
	end

	table.insert(connections, prompt.PromptButtonHoldBegan:Connect(function()
		card.Press(true)
		card.SetHold(1, prompt.HoldDuration)
	end))
	table.insert(connections, prompt.PromptButtonHoldEnded:Connect(function()
		card.Press(false)
		card.SetHold(0, 0.15)
	end))
	table.insert(connections, prompt.Triggered:Connect(function()
		card.Press(true)
		card.Pop()
		if UI.ClickHook then
			UI.ClickHook()
		end
	end))
	table.insert(connections, prompt.TriggerEnded:Connect(function()
		card.Press(false)
		card.SetHold(0, 0.15)
	end))
	-- new texts: draw it again
	for _, property in { "ActionText", "ObjectText", "HoldDuration", "KeyboardKeyCode", "GamepadKeyCode" } do
		table.insert(connections, prompt:GetPropertyChangedSignal(property):Connect(function()
			if shown[prompt] == entry then
				show(prompt, inputType)
			end
		end))
	end

	shown[prompt] = entry
	billboard.Parent = cardGui
	UI.FadeIn(billboard, 0.14)
	local pop = card.Frame:FindFirstChild("Pop", true)
	if pop then
		pop.Scale = 0.7
		UI.Tween(pop, 0.24, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end

-- Our look for a prompt (or none, for the incubators); Roblox's look for DefaultPromptStyle prompts
local function adopt(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	if prompt:GetAttribute("EggId") ~= nil then
		prompt.Enabled = false -- incubators open the Egg panel when you walk up (below)
		return
	end
	if prompt:GetAttribute("DefaultPromptStyle") == true then
		return
	end
	prompt.Style = Enum.ProximityPromptStyle.Custom
end

---------------------------------------------------------------------------
-- Egg incubators: the Egg panel opens when you walk up, closes when you walk away
---------------------------------------------------------------------------
local eggState = { Near = nil, Armed = nil, Dismissed = nil }
local closingEgg = false
local EggPanel = nil -- Panels/Egg (CurrentEgg, IsBusy)

-- One step of the incubator logic. `state` = { Near, Armed, Dismissed } (kept between steps):
--   Near      the incubator the player is at (entered within EggOpenDistance, left past EggCloseDistance)
--   Armed     the Egg panel is open for the incubator the player was at: leaving it closes the panel
--   Dismissed the player closed the panel at this incubator: it stays shut until they leave
-- `input` = { Nearest = eggId?, Distance = studs, PanelEgg = the egg the open Egg panel shows (nil when
-- it isn't open), OtherPanel = another panel is open, Hold = a dialog / the Roblox menu is open,
-- Busy = an egg is hatching }. Returns "Open", eggId / "Close", eggId / nil.
function PromptController.EggStep(state, input)
	local near = nil
	if input.Nearest then
		local reach = if input.Nearest == state.Near then PromptController.EggCloseDistance else PromptController.EggOpenDistance
		if input.Distance <= reach then
			near = input.Nearest
		end
	end
	if near ~= state.Near then
		state.Near = near
		if state.Dismissed ~= near then
			state.Dismissed = nil -- left the incubator they closed it at
		end
	end
	local panelEgg = input.PanelEgg
	if not panelEgg then
		state.Armed = nil
	end
	if input.Busy or input.Hold then
		return nil
	end
	if panelEgg and panelEgg == near then
		state.Armed = near
		return nil
	end
	if panelEgg and panelEgg == state.Armed then
		-- walked away from the incubator the panel is open for: on to another one, or closed
		state.Armed = nil
		if near and state.Dismissed ~= near then
			state.Armed = near
			return "Open", near
		end
		return "Close", panelEgg
	end
	if near and state.Dismissed ~= near and (panelEgg ~= nil or not input.OtherPanel) then
		state.Armed = near
		return "Open", near
	end
	return nil
end

-- Flat distance from the player to an egg's incubator (math.huge without a living character)
local function eggDistance(eggId: string): number
	local egg = Pets.Eggs[eggId]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not egg or not root or not humanoid or humanoid.Health <= 0 then
		return math.huge
	end
	local offset = root.Position - MapLayout.EggStation(egg.Zone)
	if math.abs(offset.Y) > 40 then
		return math.huge
	end
	return Vector3.new(offset.X, 0, offset.Z).Magnitude
end

-- Is the player at this egg's incubator (the same rule that opens and closes its panel)?
function PromptController.IsNearEgg(eggId: string): boolean
	local reach = if eggState.Near == eggId then PromptController.EggCloseDistance else PromptController.EggOpenDistance
	return eggDistance(eggId) <= reach
end

local function dialogOpen(): boolean
	local interface = Registry.InterfaceController
	local overlay = interface and interface.OverlayRoot
	if overlay and overlay:FindFirstChild("Confirm") then
		return true
	end
	local ok, menuOpen = pcall(function()
		return GuiService.MenuIsOpen
	end)
	return ok and menuOpen == true
end

local function eggInput()
	local nearest, distance = nil, math.huge
	for _, eggId in Pets.EggOrder do
		local d = eggDistance(eggId)
		if d < distance then
			nearest, distance = eggId, d
		end
	end
	local interface = Registry.InterfaceController
	local hatch = Registry.HatchOverlay
	local eggOpen = interface.IsOpen("Egg")
	return {
		Nearest = nearest,
		Distance = distance,
		PanelEgg = if eggOpen then EggPanel.CurrentEgg() else nil,
		OtherPanel = interface.IsOpen() and not eggOpen,
		-- a dialog, the Roblox menu, or a full-screen moment that hides the HUD (the egg opening)
		Hold = dialogOpen() or (interface.IsHudHidden ~= nil and interface.IsHudHidden()),
		Busy = EggPanel.IsBusy() or (hatch ~= nil and hatch.IsPlaying()),
	}
end

local function eggTick()
	local interface = Registry.InterfaceController
	if not EggPanel or not interface or not Registry.DataController.Data then
		return
	end
	local action, eggId = PromptController.EggStep(eggState, eggInput())
	if action == "Open" then
		interface.OpenPanel("Egg", eggId)
	elseif action == "Close" then
		closingEgg = true
		interface.ClosePanel()
		closingEgg = false
	end
end

local function startEggs()
	local ok, module = pcall(function()
		return require(UIFolder:WaitForChild("Panels"):WaitForChild("Egg"))
	end)
	if not ok or type(module) ~= "table" or not module.CurrentEgg then
		warn("[PromptController] no Egg panel; incubators won't open it: " .. tostring(module))
		return
	end
	EggPanel = module
	local interface = Registry.InterfaceController
	interface.PanelClosed:Connect(function(name)
		if name ~= "Egg" or closingEgg or EggPanel.IsBusy() then
			return -- our own close, or closed for the hatch
		end
		-- closed by the player (X, the dim, another panel): not again until they leave this incubator
		eggState.Armed = nil
		if eggState.Near then
			eggState.Dismissed = eggState.Near
		end
	end)
	task.spawn(function()
		while true do
			local stepped, err = pcall(eggTick)
			if not stepped then
				warn("[PromptController] egg incubator check failed: " .. tostring(err))
				task.wait(2)
			end
			task.wait(PromptController.EggTick)
		end
	end)
end

---------------------------------------------------------------------------
function PromptController.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "PromptCards"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	cardGui = gui
end

function PromptController.Start()
	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style ~= Enum.ProximityPromptStyle.Custom then
			return
		end
		local ok, err = pcall(show, prompt, inputType)
		if not ok then
			-- never leave a prompt invisible: Roblox's own look for this one
			warn("[PromptController] card failed for " .. prompt:GetFullName() .. ": " .. tostring(err))
			hide(prompt, true)
			prompt.Style = Enum.ProximityPromptStyle.Default
		end
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		hide(prompt)
	end)

	-- gate cards follow your Volts, Power and zones
	Registry.DataController.Changed:Connect(function(key)
		if key == "Volts" or key == "Upgrades" or key == "Zone" then
			for _, entry in shown do
				if entry.Card.Gate then
					entry.Card.Refresh()
				end
			end
		end
	end)

	-- our cards only once the handlers above are listening
	for _, descendant in Workspace:GetDescendants() do
		adopt(descendant)
	end
	Workspace.DescendantAdded:Connect(adopt)

	startEggs()
end

return PromptController
