--!nonstrict
-- Zone title card: the Sky Lab banner that names a zone when you walk into it, unlock it or reach one
-- you haven't unlocked yet. The zone's 3D emblem (Icons "Zone_<Key>", assets/ui/icons3d, modelled in
-- SketchUp by tools/icons/sketchup_zone_emblems.py) overlaps the left end of a candy plaque in the
-- zone's colours with a rolled right end; the name is big Fredoka with a white-to-tint fill and an Ink
-- outline over a darker drop; a caption pill ("ZONE 2" chip + the zone's flavour or what it needs) and,
-- in zones with a hazard, a hazard pill hang under it. It slides and scales in with a little overshoot,
-- a shine sweeps across, and it fades out after a few seconds. Titles queue: a newer one cuts the one
-- on screen short (it still shows for MIN_HOLD), so two never overlap.
--
--   ZoneTitle.Show(zoneId, "Enter")     -- ZoneController: you walked into a zone
--   ZoneTitle.Show(zoneId, "Unlocked")  -- EffectsController: you unlocked a zone
--   ZoneTitle.Show(zoneId, "Locked")    -- a zone you haven't unlocked yet: what it needs
--   options = { Caption = string?, Duration = seconds?, Hazard = boolean? (default: Enter shows it),
--               Repeat = true (a zone seen before: shorter) }
--
-- Placement: the card sits under the currency capsules, in the HUD's top stack (HudController's
-- "TopCenter", under the capsules and the Mega Storm bar). An empty spacer the card's height goes in
-- that stack while a title shows, so the stack grows and the toasts (placed under it) slide down
-- below the card; the card itself is drawn on the Overlay gui at the spacer's spot, so it also shows
-- over an open panel (e.g. unlocking a zone from the Teleport panel). Same scale as the HUD, so it
-- scales for phones like the rest of the interface.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Hazards = require(Shared.Hazards)
local Format = require(Shared.Util.Format)

local Registry = require(script.Parent.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI)
local Theme = require(script.Parent.Parent.Theme)
local Icons = require(script.Parent.Parent.Icons)

local ZoneTitle = {}

local INK = Theme.Ink
local WHITE = Color3.new(1, 1, 1)
local Z = 40 -- over the other overlays' content, under dialogs (Confirm uses 50+)

-- Plaque colours (gradient top, bottom) per zone key, matched to the emblems' enamel; any other zone
-- derives its pair from Zone.Color
local PALETTES = {
	Hub = { "5CC8FF", "2F86F2" },
	Meadows = { "7BE36A", "2FAE48" },
	Thunder = { "A98BFF", "6B4BE6" },
	Dunes = { "FFC65C", "EC8A2A" },
	Frost = { "7FD6FF", "3E8CEB" },
	Volcano = { "FF9150", "E2402E" },
	Sky = { "CF8CFF", "8146E8" },
}

local HOLD = { Enter = 2.6, Repeat = 1.9, Unlocked = 3.4, Locked = 2.8 } -- seconds fully shown
local MIN_HOLD = 0.9 -- a title cut short by a newer one still shows this long
local IN_TIME = 0.5
local OUT_TIME = 0.3

-- Layout in HUD units (px at 1280x720)
local MAX_WIDTH = 600
local EMBLEM = 104
local EMBLEM_X = 54 -- emblem centre from the card's left edge
local PLAQUE_X = 44 -- plaque's left edge (hidden under the emblem)
local PLAQUE_H = 62 -- face + lip
local LIP = 6
local CORNER = 18
local NAME_X = 110 -- the name starts right of the emblem (from the card's left edge)
local NAME_PAD = 36 -- room right of the name, for the roll
local NAME_SIZE = 40
local ROLL_W = 24
local ROLL_OUT = 10 -- how far the roll sticks out past the plaque's right end
local KICKER_H = 28
local PILL_H = 30
local PILL_GAP = 6

local queue = {}
local current = nil -- the entry on screen: { ZoneId, Kind, Hurry }
local running = false

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function frame(name: string, props)
	local object = UI.Create("Frame", props)
	object.Name = name
	object.BorderSizePixel = 0
	return object
end

local function textWidth(text: string, size: number, font: Enum.Font): number
	local ok, bounds = pcall(TextService.GetTextSize, TextService, text, size, font, Vector2.new(4096, 4096))
	if ok and typeof(bounds) == "Vector2" then
		return bounds.X
	end
	return (utf8.len(text) or #text) * size * 0.6
end

local function hex(code: string): Color3
	return Color3.fromHex(code)
end

local function palette(zone)
	local pair = PALETTES[zone.Key]
	local top, bottom
	if pair then
		top, bottom = hex(pair[1]), hex(pair[2])
	else
		top, bottom = zone.Color:Lerp(WHITE, 0.15), Theme.Shade(zone.Color, 0.72)
	end
	return {
		Top = top,
		Bottom = bottom,
		Lip = Theme.Shade(bottom, 0.62),
		Dark = Theme.Shade(bottom, 0.5),
		Tint = top:Lerp(WHITE, 0.6),
	}
end

-- Interface units across the screen (the HUD's width / its scale)
local function screenUnits(): number
	local interface = Registry.InterfaceController
	local root = interface and interface.OverlayRoot
	local scale = (interface and interface.OverlayScale) or 1
	if root and root.AbsoluteSize.X > 0 then
		return root.AbsoluteSize.X / math.max(scale, 0.01)
	end
	return 1280
end

local function topStack(): Frame?
	local interface = Registry.InterfaceController
	local hud = interface and interface.HudRoot
	return hud and hud:FindFirstChild("TopCenter")
end

-- A candy pill (lip, gradient face, shine) with white text in an outline of the set's dark colour.
-- Returns the holder (size w x h, the lip included).
local function candyChip(parent: Instance, text: string, top: Color3, bottom: Color3, size: number, z: number)
	local lipColor = Theme.Shade(bottom, 0.62)
	local width = textWidth(text, size, Theme.Font) + 26
	local height = size + 14
	local holder = frame("Chip", { BackgroundTransparency = 1, Size = UDim2.fromOffset(width, height), ZIndex = z, Parent = parent })
	local lip = frame("Lip", {
		BackgroundColor3 = lipColor,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = holder,
		UI.Round(),
		UI.Stroke(2.5, INK),
	})
	local face = frame("Face", {
		BackgroundColor3 = WHITE,
		Size = UDim2.new(1, 0, 1, -4),
		ZIndex = z + 1,
		Parent = lip,
		UI.Round(),
		UI.Gradient(top, bottom),
	})
	frame("Shine", {
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.72,
		Position = UDim2.fromOffset(6, 2),
		Size = UDim2.new(1, -12, 0.36, 0),
		ZIndex = z + 2,
		Parent = face,
		UI.Round(),
	})
	UI.Text({
		Name = "Label",
		Text = text,
		TextSize = size,
		Stroke = Theme.Shade(bottom, 0.5),
		StrokeThickness = 2,
		Size = UDim2.new(1, -8, 1, 0),
		Position = UDim2.fromOffset(4, 0),
		ZIndex = z + 3,
		Parent = face,
	})
	return holder
end

-- A Cloud pill with a coloured chip on the left and Ink text: { Frame, Width }
local function infoPill(parent: Instance, name: string, chipText: string, chipTop: Color3, chipBottom: Color3, text: string, size: number, maxWidth: number, z: number)
	local chipSize = size - 1
	local chipWidth = textWidth(chipText, chipSize, Theme.Font) + 26
	local textSize = size
	local available = maxWidth - chipWidth - 30
	while textWidth(text, textSize, Theme.BodyFont) > available and textSize > 12 do
		textSize -= 1
	end
	local width = math.min(chipWidth + 18 + textWidth(text, textSize, Theme.BodyFont) + 14, maxWidth)
	local height = PILL_H
	local holder = frame(name, { BackgroundTransparency = 1, Size = UDim2.fromOffset(width, height), ZIndex = z, Parent = parent })
	frame("Shadow", {
		BackgroundColor3 = INK,
		BackgroundTransparency = Theme.ShadeTransparency,
		Position = UDim2.fromOffset(0, 3),
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = holder,
		UI.Round(),
	})
	frame("Body", {
		BackgroundColor3 = WHITE,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 1,
		Parent = holder,
		UI.Round(),
		UI.Gradient(Theme.Cloud, Theme.Mist),
		UI.Stroke(2, INK),
	})
	local chip = candyChip(holder, chipText, chipTop, chipBottom, chipSize, z + 2)
	chip.Size = UDim2.fromOffset(chipWidth, height - 8)
	chip.Position = UDim2.fromOffset(4, 4)
	local label = chip:FindFirstChild("Label", true)
	if label then
		label.TextSize = chipSize - 2
	end
	UI.Text({
		Name = "Text",
		Text = text,
		Font = Theme.BodyFont,
		TextSize = textSize,
		Scaled = true,
		MinTextSize = 10,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -(chipWidth + 18), 1, -6),
		Position = UDim2.fromOffset(chipWidth + 12, 3),
		ZIndex = z + 2,
		Parent = holder,
	})
	return holder, width
end

---------------------------------------------------------------------------
-- What a card says
---------------------------------------------------------------------------
local function zoneLabel(zoneId: number): string
	return if zoneId == 0 then "HOME BASE" else "ZONE " .. tostring(zoneId)
end

local function captionFor(zoneId: number, zone, kind: string): string
	if kind == "Unlocked" then
		if (zone.Value or 0) > 1 then
			return "Weather here pays " .. Format.Number(zone.Value) .. "x Volts!"
		end
		return zone.Description
	elseif kind == "Locked" then
		local parts = {}
		if (zone.Cost or 0) > 0 then
			table.insert(parts, "Unlock for " .. Format.Number(zone.Cost) .. " Volts")
		end
		if (zone.MinPower or 0) > 0 then
			table.insert(parts, "needs " .. Format.Number(zone.MinPower) .. " Power")
		end
		return if #parts > 0 then table.concat(parts, "  •  ") else "Locked"
	end
	return zone.Description
end

-- The hazard pill: { Chip, Text, Top, Bottom } or nil
local function hazardFor(zoneId: number)
	local hazard = Hazards.Get(zoneId)
	if not hazard then
		return nil
	end
	local data = Registry.DataController and Registry.DataController.Data
	if hazard.Kind == "Cold" and data and Hazards.ResistsCold(data, hazard) then
		local leaf = Theme.Sets.Leaf
		return { Chip = "WARM", Text = (string.gsub(Hazards.Describe(hazard, data), "^%S+%s+", "")), Top = leaf.Top, Bottom = leaf.Bottom }
	end
	local color = hazard.Color or Theme.Sets.Sunset.Bottom
	return {
		Chip = hazard.Icon .. " " .. string.upper(hazard.Name),
		Text = hazard.Description,
		Top = color:Lerp(WHITE, 0.2),
		Bottom = Theme.Shade(color, 0.78),
	}
end

---------------------------------------------------------------------------
-- The card
---------------------------------------------------------------------------
local function build(zoneId: number, kind: string, options)
	local zone = Zones.Get(zoneId)
	local colors = palette(zone)
	local units = screenUnits()
	local compact = units < 900 -- phones in portrait: a bit bigger small print
	local maxWidth = math.min(MAX_WIDTH, units - 24)

	-- Name: as big as fits
	local name = string.upper(zone.Name)
	local nameSize = NAME_SIZE
	local nameWidth = textWidth(name, nameSize, Theme.Font)
	local plaqueRoom = maxWidth - PLAQUE_X - ROLL_OUT - (NAME_X - PLAQUE_X) - NAME_PAD
	while nameWidth > plaqueRoom and nameSize > 24 do
		nameSize -= 2
		nameWidth = textWidth(name, nameSize, Theme.Font)
	end
	nameWidth = math.min(nameWidth, plaqueRoom)
	local plaqueWidth = math.max((NAME_X - PLAQUE_X) + nameWidth + NAME_PAD, 240)
	local bannerWidth = PLAQUE_X + plaqueWidth + ROLL_OUT

	local kicker = kind == "Unlocked" or kind == "Locked"
	local plaqueY = if kicker then 20 else 8
	local emblemY = plaqueY + (PLAQUE_H - LIP) / 2 + 2

	-- Pills under the plaque
	local pillSize = if compact then 18 else 16
	local captionText = (options and options.Caption) or captionFor(zoneId, zone, kind)
	local showHazard = if options and options.Hazard ~= nil then options.Hazard else kind == "Enter"
	local hazard = showHazard and hazardFor(zoneId) or nil

	local card = frame("ZoneTitle", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(bannerWidth, 0),
		ZIndex = Z,
	})
	card:SetAttribute("ZoneId", zoneId)
	card:SetAttribute("Kind", kind)
	local cardScale = Instance.new("UIScale")
	cardScale.Name = "FitScale"
	cardScale.Parent = card

	-- Everything that slides / scales in together
	local banner = frame("Banner", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = Z, Parent = card })
	local bannerScale = Instance.new("UIScale")
	bannerScale.Parent = banner

	-- Plaque: drop shadow, lip with the Ink outline, the gradient face with a shine
	local plaque = frame("Plaque", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(PLAQUE_X, plaqueY),
		Size = UDim2.fromOffset(plaqueWidth, PLAQUE_H),
		ZIndex = Z,
		Parent = banner,
	})
	frame("Shadow", {
		BackgroundColor3 = INK,
		BackgroundTransparency = Theme.ShadeTransparency,
		Position = UDim2.fromOffset(0, 5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = Z,
		Parent = plaque,
		UI.Corner(CORNER),
	})
	local lip = frame("Lip", {
		BackgroundColor3 = colors.Lip,
		Size = UDim2.fromScale(1, 1),
		ZIndex = Z + 1,
		Parent = plaque,
		UI.Corner(CORNER),
		UI.Stroke(3, INK),
	})
	local face = frame("Face", {
		BackgroundColor3 = WHITE,
		Size = UDim2.new(1, 0, 1, -LIP),
		ZIndex = Z + 2,
		Parent = lip,
		UI.Corner(CORNER),
		UI.Gradient(colors.Top, colors.Bottom),
	})
	frame("Shine", {
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.74,
		Position = UDim2.fromOffset(NAME_X - PLAQUE_X - 8, 4),
		Size = UDim2.new(1, -(NAME_X - PLAQUE_X) - 14, 0.34, 0),
		ZIndex = Z + 3,
		Parent = face,
		UI.Round(),
	})
	-- The shine that sweeps across once it's in (a soft white band moved by the gradient's offset)
	local sweep = frame("Sweep", {
		BackgroundColor3 = WHITE,
		Size = UDim2.fromScale(1, 1),
		ZIndex = Z + 4,
		Parent = face,
		UI.Corner(CORNER),
	})
	local sweepGradient = Instance.new("UIGradient")
	sweepGradient.Rotation = 20
	sweepGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.42, 1),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(0.58, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	sweepGradient.Offset = Vector2.new(-1, 0)
	sweepGradient.Parent = sweep

	-- The rolled right end: a little cylinder in the zone's colours
	local roll = frame("Roll", {
		BackgroundColor3 = WHITE,
		Position = UDim2.fromOffset(PLAQUE_X + plaqueWidth + ROLL_OUT - ROLL_W, plaqueY - 7),
		Size = UDim2.fromOffset(ROLL_W, PLAQUE_H + 12),
		ZIndex = Z + 6,
		Parent = banner,
		UI.Round(),
		UI.Stroke(3, INK),
	})
	local rollFill = Instance.new("UIGradient")
	rollFill.Rotation = 0
	rollFill.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, colors.Lip),
		ColorSequenceKeypoint.new(0.42, colors.Top:Lerp(WHITE, 0.25)),
		ColorSequenceKeypoint.new(1, colors.Bottom),
	})
	rollFill.Parent = roll
	frame("Shine", {
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.55,
		Position = UDim2.new(0.28, 0, 0, 8),
		Size = UDim2.new(0.2, 0, 1, -16),
		ZIndex = Z + 7,
		Parent = roll,
		UI.Round(),
	})

	-- The name: a darker drop under a white-to-tint fill, both outlined in Ink
	local nameBox = UDim2.fromOffset(nameWidth + 8, PLAQUE_H - LIP)
	UI.Text({
		Name = "NameDrop",
		Text = name,
		TextSize = nameSize,
		Scaled = true,
		Color = colors.Dark,
		Stroke = INK,
		StrokeThickness = 3,
		Size = nameBox,
		Position = UDim2.fromOffset(NAME_X - 4, plaqueY + 3),
		ZIndex = Z + 8,
		Parent = banner,
	})
	local nameLabel = UI.Text({
		Name = "Name",
		Text = name,
		TextSize = nameSize,
		Scaled = true,
		Color = WHITE,
		Stroke = INK,
		StrokeThickness = 3,
		Size = nameBox,
		Position = UDim2.fromOffset(NAME_X - 4, plaqueY),
		ZIndex = Z + 9,
		Parent = banner,
	})
	local fill = UI.Gradient(WHITE, colors.Tint)
	fill.Name = "Fill"
	fill.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.5, WHITE),
		ColorSequenceKeypoint.new(1, colors.Tint),
	})
	fill.Parent = nameLabel

	-- The emblem over the plaque's left end (the zone's emoji until its picture is uploaded)
	local emblem = Icons.New("Zone_" .. zone.Key, {
		Name = "Emblem",
		Size = UDim2.fromOffset(EMBLEM, EMBLEM),
		Position = UDim2.fromOffset(EMBLEM_X, emblemY),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = -6,
		ZIndex = Z + 10,
		Parent = banner,
	})
	local emblemScale = Instance.new("UIScale")
	emblemScale.Parent = emblem
	if not Icons.Image("Zone_" .. zone.Key) then
		-- No picture yet: put the emoji on a round badge so it still reads as an emblem
		local badge = frame("Badge", {
			BackgroundColor3 = WHITE,
			Size = UDim2.fromScale(0.86, 0.86),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = Z + 9,
			Parent = emblem,
			UI.Round(),
			UI.Stroke(3, INK),
			UI.Gradient(colors.Top, colors.Bottom),
		})
		badge.ZIndex = Z + 9
		local glyph = emblem:FindFirstChild("Emoji")
		if glyph then
			glyph.Size = UDim2.fromScale(0.56, 0.56)
			glyph.ZIndex = Z + 11
		end
	end
	if kind == "Locked" then
		local image = emblem:FindFirstChild("Image")
		if image then
			image.ImageColor3 = Color3.fromRGB(150, 156, 186)
		end
		Icons.New("Lock", {
			Name = "Lock",
			Size = UDim2.fromOffset(44, 44),
			Position = UDim2.fromScale(0.8, 0.78),
			ZIndex = Z + 12,
			Parent = emblem,
		})
	end

	-- Kicker over the plaque's top edge
	local kickerChip = nil
	if kicker then
		local set = if kind == "Unlocked" then Theme.Sets.Bolt else Theme.Sets.Coral
		local text = if kind == "Unlocked" then "ZONE UNLOCKED!" else "LOCKED"
		kickerChip = candyChip(banner, text, set.Top, set.Bottom, 17, Z + 12)
		kickerChip.Name = "Kicker"
		kickerChip.AnchorPoint = Vector2.new(0.5, 0)
		local centre = NAME_X + nameWidth / 2
		local half = kickerChip.Size.X.Offset / 2
		centre = math.clamp(centre, PLAQUE_X + half + 10, PLAQUE_X + plaqueWidth - half - 10)
		kickerChip.Position = UDim2.fromOffset(centre, plaqueY - KICKER_H / 2 - 4)
		if kind == "Unlocked" then
			for side = -1, 1, 2 do
				Icons.New("Star", {
					Name = if side < 0 then "StarLeft" else "StarRight",
					Size = UDim2.fromOffset(26, 26),
					Position = UDim2.new(0.5, side * (half + 14), 0.5, 0),
					Rotation = side * 14,
					ZIndex = Z + 15,
					Parent = kickerChip,
				})
			end
		end
	end

	-- Pills: centred under the plaque, never wider than the screen
	local pills = {}
	local pillTop = plaqueY + PLAQUE_H + 8
	local plaqueCentre = PLAQUE_X + plaqueWidth / 2
	local caption, captionWidth = infoPill(banner, "Caption", zoneLabel(zoneId), colors.Top, colors.Bottom, captionText, pillSize, maxWidth, Z + 1)
	table.insert(pills, { caption, captionWidth })
	if hazard then
		local pill, width = infoPill(banner, "Hazard", hazard.Chip, hazard.Top, hazard.Bottom, hazard.Text, pillSize - 1, maxWidth, Z + 1)
		table.insert(pills, { pill, width })
	end
	local left, right = 0, bannerWidth
	for index, entry in pills do
		local pill, width = entry[1], entry[2]
		local x = plaqueCentre - width / 2
		pill.Position = UDim2.fromOffset(x, pillTop + (index - 1) * (PILL_H + PILL_GAP))
		left = math.min(left, x)
		right = math.max(right, x + width)
	end
	local height = pillTop + #pills * (PILL_H + PILL_GAP) - PILL_GAP + 6

	-- Shift everything right if a pill sticks out on the left, and size the card to fit
	if left < 0 then
		for _, child in banner:GetChildren() do
			if child:IsA("GuiObject") then
				child.Position += UDim2.fromOffset(-left, 0)
			end
		end
	end
	card.Size = UDim2.fromOffset(right - left, height)
	-- Very narrow screens: shrink the whole card to fit
	local fit = math.min(1, (units - 16) / (right - left))
	cardScale.Scale = fit

	return {
		Card = card,
		Height = height * fit,
		Banner = banner,
		BannerScale = bannerScale,
		Emblem = emblem,
		EmblemScale = emblemScale,
		Kicker = kickerChip,
		Pills = pills,
		Sweep = sweepGradient,
	}
end

---------------------------------------------------------------------------
-- Showing one card
---------------------------------------------------------------------------
-- Keeps the card on the spacer's spot (in Overlay units), every frame while it's shown
local function follow(card: Frame, spacer: Frame?)
	local interface = Registry.InterfaceController
	local root = interface.OverlayRoot
	local function place()
		if not card.Parent then
			return
		end
		local scale = math.max(interface.OverlayScale or 1, 0.01)
		local y
		if spacer and spacer.Parent and spacer.AbsoluteSize.X >= 0 and spacer.AbsolutePosition.Y > 0 then
			y = (spacer.AbsolutePosition.Y - root.AbsolutePosition.Y) / scale
		else
			y = (interface.SafeTop or 0) + 70 -- no HUD (yet): under where the capsules would be
		end
		card.Position = UDim2.new(0.5, 0, 0, y)
	end
	place()
	local connections = {}
	if spacer then
		table.insert(connections, spacer:GetPropertyChangedSignal("AbsolutePosition"):Connect(place))
	end
	table.insert(connections, root:GetPropertyChangedSignal("AbsoluteSize"):Connect(place))
	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
	end
end

local function play(entry)
	local interface = Registry.InterfaceController
	if not interface or not interface.OverlayRoot then
		return
	end
	local parts = build(entry.ZoneId, entry.Kind, entry.Options)
	local card = parts.Card

	-- Room in the HUD's top stack (toasts slide down under it)
	local stack = topStack()
	local spacer = nil
	if stack then
		spacer = frame("ZoneTitleSpace", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(10, 0),
			LayoutOrder = 50,
			Parent = stack,
		})
		UI.Tween(spacer, 0.25, { Size = UDim2.fromOffset(10, parts.Height) })
	end
	card.Parent = interface.OverlayRoot
	local unfollow = follow(card, spacer)

	-- In: drop down + scale up with a little overshoot, the emblem spins in, then the shine sweeps
	local banner = parts.Banner
	banner.Position = UDim2.fromOffset(0, -22)
	parts.BannerScale.Scale = 0.72
	UI.FadeIn(banner, 0.22)
	UI.Tween(banner, IN_TIME, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
	UI.Tween(parts.BannerScale, IN_TIME, { Scale = 1 }, Enum.EasingStyle.Back)
	parts.EmblemScale.Scale = 0.3
	parts.Emblem.Rotation = -40
	task.delay(0.08, function()
		UI.Tween(parts.EmblemScale, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)
		UI.Tween(parts.Emblem, 0.55, { Rotation = -6 }, Enum.EasingStyle.Back)
	end)
	if parts.Kicker then
		task.delay(0.22, function()
			UI.Pop(parts.Kicker, 1.35)
		end)
	end
	task.delay(IN_TIME * 0.8, function()
		parts.Sweep.Offset = Vector2.new(-1, 0)
		UI.Tween(parts.Sweep, 0.7, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	end)

	-- Hold (cut short when a newer title is waiting)
	local hold = (entry.Options and entry.Options.Duration)
		or (if entry.Kind == "Enter" and entry.Options and entry.Options.Repeat then HOLD.Repeat else HOLD[entry.Kind] or HOLD.Enter)
	local shown = 0
	while shown < IN_TIME + hold do
		shown += task.wait(0.05)
		if entry.Hurried and shown >= IN_TIME + MIN_HOLD then
			break
		end
	end

	-- Out: lift, shrink and fade; the stack closes the gap
	UI.Tween(banner, OUT_TIME, { Position = UDim2.fromOffset(0, -14) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	UI.Tween(parts.BannerScale, OUT_TIME, { Scale = 0.88 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	UI.FadeOut(banner, OUT_TIME)
	if spacer then
		UI.Tween(spacer, OUT_TIME, { Size = UDim2.fromOffset(10, 0) })
	end
	task.wait(OUT_TIME + 0.02)
	unfollow()
	card:Destroy()
	if spacer then
		spacer:Destroy()
	end
end

local function run()
	if running then
		return
	end
	running = true
	while #queue > 0 do
		local entry = table.remove(queue, 1)
		current = entry
		local ok, err = pcall(play, entry)
		if not ok then
			warn("ZoneTitle: " .. tostring(err))
		end
		current = nil
	end
	running = false
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
-- Queues a zone title. kind: "Enter" (default), "Unlocked" or "Locked".
function ZoneTitle.Show(zoneId: number, kind: string?, options)
	local zone = type(zoneId) == "number" and Zones.Get(zoneId)
	if not zone then
		return
	end
	local which = kind or "Enter"
	if which ~= "Unlocked" and which ~= "Locked" then
		which = "Enter"
	end
	-- Already on screen (or just announced as unlocked: walking in needs no second card)
	if current and current.ZoneId == zoneId and (current.Kind == which or (which == "Enter" and current.Kind == "Unlocked")) then
		return
	end
	-- A newer "Enter" replaces one still waiting; repeats of the same card are dropped
	for index = #queue, 1, -1 do
		local waiting = queue[index]
		if (waiting.Kind == "Enter" and which == "Enter") or (waiting.ZoneId == zoneId and waiting.Kind == which) then
			table.remove(queue, index)
		end
	end
	table.insert(queue, { ZoneId = zoneId, Kind = which, Options = options })
	if current then
		current.Hurried = true
	end
	if not running then
		task.spawn(run)
	end
end

-- The title on screen ({ ZoneId, Kind }) or nil, and how many wait (for tests)
function ZoneTitle.State()
	return current and { ZoneId = current.ZoneId, Kind = current.Kind } or nil, #queue
end

return ZoneTitle
