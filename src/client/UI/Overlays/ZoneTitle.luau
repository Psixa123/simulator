--!nonstrict
-- Zone title card: the Sky Lab banner that names a zone when you walk into it, unlock it or bump into
-- one you haven't unlocked yet.
--
--   ZONE 2                    <- kicker chip over the plaque ("ZONE 2 UNLOCKED!", "ZONE 2 • LOCKED")
--   (emblem)[ THUNDER VALLEY ]) <- plaque in the zone's colours with a rolled right end; the zone's 3D
--      [ A dark valley ... ]     emblem (Icons "Zone_<Key>", tools/icons/sketchup_zone_emblems.py) over
--      [ HAZARD  Lightning ...]  its left end; the name in big Fredoka with a white-to-tint fill and an
--                                Ink outline over a darker drop
--   ... and a Cloud caption card hanging under the plaque: the zone's flavour line, its hazard, or what
--   it pays / needs. It drops and scales in with a little overshoot, the emblem spins in, the caption
--   card slides out from under the plaque, a shine sweeps across, and it fades out after a few seconds.
--   Titles queue: a newer one cuts the one on screen short (it still shows for MIN_HOLD), so two
--   never overlap.
--
--   ZoneTitle.Show(zoneId, "Enter")     -- ZoneController: you walked into a zone
--   ZoneTitle.Show(zoneId, "Unlocked")  -- EffectsController: you unlocked a zone
--   ZoneTitle.Show(zoneId, "Locked")    -- ZoneController: you bumped into a zone's locked gate
--   options = { Caption = string? (instead of the flavour line), Duration = seconds?,
--               Hazard = boolean? (default: Enter shows it), Repeat = true (a zone seen before: just the
--               name and its hazard, shown shorter) }
--
-- Placement: under the currency capsules, in the HUD's top stack (HudController's "TopCenter", under
-- the capsules and the Mega Storm bar). An empty spacer the card's height goes in that stack while a
-- title shows, so the stack grows and the toasts (placed under it) slide down below the card; the card
-- itself is drawn on the Overlay gui at the spacer's spot, so it also shows over an open panel (e.g.
-- unlocking a zone from the Teleport panel). Same scale as the HUD, with the small print kept at least
-- ~12 px tall on phones.

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

-- Hazard chip colours by hazard kind (Shared/Hazards)
local HAZARD_SETS = {
	Lightning = "Bolt",
	Sandstorm = "Sunset",
	Cold = "Rain",
	Heat = "Coral",
	LowGravity = "Storm",
}

local HOLD = { Enter = 2.6, Repeat = 1.8, Unlocked = 3.4, Locked = 2.6 } -- seconds fully shown
local MIN_HOLD = 0.9 -- a title cut short by a newer one still shows this long
local IN_TIME = 0.5
local OUT_TIME = 0.3

-- Layout in HUD units (px at 1280x720)
-- Widest card: on desktop it stays narrow so only the emblem's edge reaches the chat window; phones
-- (smaller scale, bigger small print, no chat window) allow more, landscape phones the most
local MAX_WIDTH = 560
local PHONE_WIDTH = 640
local WIDE_WIDTH = 720 -- landscape phones
local EMBLEM = 112
local EMBLEM_X = 58 -- emblem centre from the card's left edge
local PLAQUE_X = 50 -- the plaque's left edge (under the emblem)
local PLAQUE_H = 64 -- face + lip
local LIP = 6
local CORNER = 18
local NAME_X = 120 -- the name area starts right of the emblem
local NAME_PAD = 42 -- room right of the name area, for the roll
local NAME_SIZE = 42
local MIN_AREA = 220
local ROLL_W = 24
local ROLL_OUT = 10 -- how far the roll sticks out past the plaque's right end
local CARD_INSET_L = 26 -- the caption card starts this far left of the name area (under the emblem)
local CARD_INSET_R = 16 -- and ends this far inside the plaque's right end
local CARD_TUCK = 12 -- how far its top hides under the plaque
local CARD_PAD = 14
local ROW_GAP = 14 -- between rows (a divider line sits in the middle)
local SMALL_PX = 12.5 -- the small print is at least this many screen px tall

local queue = {}
local current = nil -- the entry on screen: { ZoneId, Kind, Hurried }
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

-- Text bounds (wrapped at `width` when given)
local function measure(text: string, size: number, font: Enum.Font, width: number?): Vector2
	local ok, bounds = pcall(TextService.GetTextSize, TextService, text, size, font, Vector2.new(width or 4096, 4096))
	if ok and typeof(bounds) == "Vector2" then
		return bounds
	end
	local natural = (utf8.len(text) or #text) * size * 0.58
	if width and natural > width then
		return Vector2.new(width, math.ceil(natural / width) * size * 1.2)
	end
	return Vector2.new(natural, size * 1.2)
end

local function textWidth(text: string, size: number, font: Enum.Font): number
	return measure(text, size, font).X
end

-- A width for `text` no wider than `maxWidth` whose lines come out about equally long (no lone word
-- on the last line). Returns width, height.
local function balancedWrap(text: string, size: number, font: Enum.Font, maxWidth: number): (number, number)
	local natural = textWidth(text, size, font)
	if natural <= maxWidth then
		return math.ceil(natural) + 2, measure(text, size, font).Y
	end
	local lines = math.ceil(natural / maxWidth)
	local lineHeight = measure("Ag", size, font).Y
	local width = math.min(maxWidth, math.ceil(natural / lines + size))
	local height = measure(text, size, font, width).Y
	-- Word breaks can push a word onto an extra line: widen until it fits in `lines`
	while height > lineHeight * lines + 1 and width < maxWidth do
		width = math.min(maxWidth, width + size)
		height = measure(text, size, font, width).Y
	end
	return width, height
end

local function palette(zone, locked: boolean)
	local pair = PALETTES[zone.Key]
	local top, bottom
	if pair then
		top, bottom = Color3.fromHex(pair[1]), Color3.fromHex(pair[2])
	else
		top, bottom = zone.Color:Lerp(WHITE, 0.15), Theme.Shade(zone.Color, 0.72)
	end
	if locked then
		-- A locked zone keeps its colours, a little dimmer
		top = top:Lerp(Theme.Sets.Ink.Top, 0.18)
		bottom = bottom:Lerp(Theme.Sets.Ink.Bottom, 0.18)
	end
	return {
		Top = top,
		Bottom = bottom,
		Lip = Theme.Shade(bottom, 0.62),
		Dark = Theme.Shade(bottom, 0.5),
		Tint = top:Lerp(WHITE, 0.6),
	}
end

-- Interface units across the screen (the Overlay's width / its scale) and that scale
local function screenUnits(): (number, number)
	local interface = Registry.InterfaceController
	local root = interface and interface.OverlayRoot
	local scale = math.max((interface and interface.OverlayScale) or 1, 0.01)
	if root and root.AbsoluteSize.X > 0 then
		return root.AbsoluteSize.X / scale, scale
	end
	return 1280, scale
end

local function topStack(): Frame?
	local interface = Registry.InterfaceController
	local hud = interface and interface.HudRoot
	return hud and hud:FindFirstChild("TopCenter")
end

-- A small candy chip (Ink outline, lip, gradient face, shine) with white text outlined in the set's
-- dark colour - or, with cloud = true, a Cloud chip with text in `ink`. Returns the holder (w x h).
local function chip(parent: Instance, text: string, top: Color3, bottom: Color3, size: number, z: number, cloud: boolean?, ink: Color3?)
	local height = size + 14
	local width = math.ceil(textWidth(text, size, Theme.Font) + size * 1.4)
	local holder = frame("Chip", { BackgroundTransparency = 1, Size = UDim2.fromOffset(width, height), ZIndex = z, Parent = parent })
	local t = 2.5
	frame("Shadow", {
		BackgroundColor3 = INK,
		BackgroundTransparency = Theme.ShadeTransparency,
		Position = UDim2.fromOffset(0, 3),
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = holder,
		UI.Round(),
	})
	local lip = frame("Lip", {
		BackgroundColor3 = if cloud then Theme.HazeDeep else Theme.Shade(bottom, 0.62),
		Position = UDim2.fromOffset(t, t),
		Size = UDim2.new(1, -2 * t, 1, -2 * t),
		ZIndex = z + 1,
		Parent = holder,
		UI.Round(),
		UI.Stroke(t, INK),
	})
	local face = frame("Face", {
		BackgroundColor3 = WHITE,
		Size = UDim2.new(1, 0, 1, -3),
		ZIndex = z + 2,
		Parent = lip,
		UI.Round(),
		if cloud then UI.Gradient(Theme.Cloud, Theme.Mist) else UI.Gradient(top, bottom),
	})
	if not cloud then
		frame("Shine", {
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.72,
			Position = UDim2.fromOffset(5, 2),
			Size = UDim2.new(1, -10, 0.36, 0),
			ZIndex = z + 3,
			Parent = face,
			UI.Round(),
		})
	end
	UI.Text({
		Name = "Label",
		Text = text,
		TextSize = size,
		Color = if cloud then (ink or INK) else WHITE,
		Stroke = if cloud then nil else Theme.Shade(bottom, 0.5),
		StrokeThickness = 2,
		Size = UDim2.new(1, 0, 1, 1),
		ZIndex = z + 4,
		Parent = face,
	})
	return holder
end

---------------------------------------------------------------------------
-- What a card says
---------------------------------------------------------------------------
local function zoneLabel(zoneId: number): string
	return if zoneId == 0 then "HOME BASE" else "ZONE " .. tostring(zoneId)
end

-- The hazard row: { Kind = "Hazard", Chip, Text, Set } or nil
local function hazardRow(zoneId: number)
	local hazard = Hazards.Get(zoneId)
	if not hazard then
		return nil
	end
	local data = Registry.DataController and Registry.DataController.Data
	if hazard.Kind == "Cold" and data and Hazards.ResistsCold(data, hazard) then
		return { Kind = "Hazard", Chip = "WARM BOOTS", Text = "Your Storm Boots keep the cold away!", Set = Theme.Sets.Leaf }
	end
	return {
		Kind = "Hazard",
		Chip = string.upper(hazard.Name),
		Text = hazard.Description,
		Set = Theme.Sets[HAZARD_SETS[hazard.Kind] or "Sunset"],
	}
end

-- Kicker chip text + style, and the caption card's rows
local function contentFor(zoneId: number, zone, kind: string, options)
	options = options or {}
	local kicker
	if kind == "Unlocked" then
		kicker = { Text = zoneLabel(zoneId) .. " UNLOCKED!", Set = Theme.Sets.Bolt }
	elseif kind == "Locked" then
		kicker = { Text = zoneLabel(zoneId) .. "  •  LOCKED", Set = Theme.Sets.Coral }
	else
		kicker = { Text = zoneLabel(zoneId), Cloud = true }
	end

	local rows = {}
	local flavour = options.Caption
	if not flavour and kind ~= "Locked" and not (kind == "Enter" and options.Repeat) then
		-- (the hub's "Home base: ..." without the words the kicker already says)
		flavour = string.gsub(zone.Description or "", "^[Hh]ome base:%s*(%a)", string.upper)
	end
	if flavour and flavour ~= "" then
		table.insert(rows, { Kind = "Text", Text = flavour })
	end
	if kind == "Unlocked" and (zone.Value or 0) > 1 then
		table.insert(rows, { Kind = "Stats", Items = { { Icon = "Volts", Text = "Weather here pays " .. Format.Number(zone.Value) .. "x Volts!" } } })
	elseif kind == "Locked" then
		local items = {}
		if (zone.Cost or 0) > 0 then
			table.insert(items, { Icon = "Volts", Text = Format.Number(zone.Cost) .. " Volts" })
		end
		if (zone.MinPower or 0) > 0 then
			table.insert(items, { Icon = "Power", Text = Format.Number(zone.MinPower) .. " Power" })
		end
		if #items > 0 then
			table.insert(rows, { Kind = "Stats", Label = "Unlock with", Items = items })
		end
	end
	local showHazard = if options.Hazard ~= nil then options.Hazard else kind == "Enter"
	local hazard = showHazard and hazardRow(zoneId) or nil
	if hazard then
		table.insert(rows, hazard)
	end
	return kicker, rows
end

---------------------------------------------------------------------------
-- Caption card rows: measure (natural width; height at a width) and build
---------------------------------------------------------------------------
local function rowNatural(row, size: number): number
	if row.Kind == "Text" then
		return textWidth(row.Text, size, Theme.BodyFont)
	elseif row.Kind == "Stats" then
		local width = if row.Label then textWidth(row.Label, size, Theme.BodyFont) + 12 else 0
		for index, item in row.Items do
			width += (size + 12) + 6 + textWidth(item.Text, size + 1, Theme.Font) + (if index > 1 then 22 else 0)
		end
		return width
	else
		local chipWidth = textWidth(row.Chip, size - 2, Theme.Font) + (size - 2) * 1.4
		return chipWidth + 10 + textWidth(row.Text, size - 1, Theme.BodyFont)
	end
end

-- Lays a row out in `width`: returns its height and a build function(parent, y, z)
local function layoutRow(row, size: number, width: number)
	if row.Kind == "Text" then
		local textSize = size
		local w, h = balancedWrap(row.Text, textSize, Theme.BodyFont, width)
		while h > textSize * 2.6 and textSize > size - 3 do -- three lines: a little smaller first
			textSize -= 1
			w, h = balancedWrap(row.Text, textSize, Theme.BodyFont, width)
		end
		return h, function(parent, y, z)
			UI.Text({
				Name = "Flavour",
				Text = row.Text,
				Font = Theme.BodyFont,
				TextSize = textSize,
				Wrapped = true,
				Color = Theme.InkSoft,
				Size = UDim2.fromOffset(w + 2, h + 2),
				Position = UDim2.new(0.5, 0, 0, y - 1),
				AnchorPoint = Vector2.new(0.5, 0),
				ZIndex = z,
				Parent = parent,
			})
		end
	elseif row.Kind == "Stats" then
		local textSize = size + 1
		while rowNatural(row, textSize - 1) > width and textSize > 11 do
			textSize -= 1
		end
		local icon = textSize + 11
		local total = rowNatural(row, textSize - 1)
		return icon, function(parent, y, z)
			local holder = frame("Stats", {
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(total, icon),
				Position = UDim2.new(0.5, 0, 0, y),
				AnchorPoint = Vector2.new(0.5, 0),
				ZIndex = z,
				Parent = parent,
			})
			local x = 0
			if row.Label then
				local w = textWidth(row.Label, textSize - 1, Theme.BodyFont)
				UI.Text({
					Name = "Label",
					Text = row.Label,
					Font = Theme.BodyFont,
					TextSize = textSize - 1,
					Color = Theme.InkSoft,
					Size = UDim2.fromOffset(w + 2, icon),
					Position = UDim2.fromOffset(x, 0),
					ZIndex = z,
					Parent = holder,
				})
				x += w + 12
			end
			for index, item in row.Items do
				if index > 1 then
					x += 22
				end
				Icons.New(item.Icon, {
					Name = "Icon" .. index,
					Size = UDim2.fromOffset(icon, icon),
					Position = UDim2.fromOffset(x, 0),
					AnchorPoint = Vector2.zero,
					ZIndex = z + 1,
					Parent = holder,
				})
				x += icon + 6
				local w = textWidth(item.Text, textSize, Theme.Font)
				UI.Text({
					Name = "Text" .. index,
					Text = item.Text,
					TextSize = textSize,
					Color = INK,
					X = Enum.TextXAlignment.Left,
					Size = UDim2.fromOffset(w + 4, icon),
					Position = UDim2.fromOffset(x, 1),
					ZIndex = z,
					Parent = holder,
				})
				x += w
			end
		end
	end

	-- Hazard: [CHIP] text on one line; else the chip left of the text in two lines; else the chip over
	-- the text
	local chipSize = size - 2
	local textSize = size - 1
	local chipWidth = math.ceil(textWidth(row.Chip, chipSize, Theme.Font) + chipSize * 1.4)
	local chipHeight = chipSize + 14
	local natural = textWidth(row.Text, textSize, Theme.BodyFont)
	local lineHeight = measure("Ag", textSize, Theme.BodyFont).Y
	local mode, textW, textH = "Inline", math.ceil(natural) + 2, lineHeight
	if chipWidth + 10 + natural > width then
		local room = width - chipWidth - 10
		local w, h = balancedWrap(row.Text, textSize, Theme.BodyFont, room)
		if room >= width * 0.45 and h <= lineHeight * 2 + 1 then
			mode, textW, textH = "Side", w, h
		else
			mode = "Stacked"
			textW, textH = balancedWrap(row.Text, textSize, Theme.BodyFont, width)
		end
	end
	local stacked = mode == "Stacked"
	local height = if stacked then chipHeight + 5 + textH else math.max(chipHeight, textH)
	return height, function(parent, y, z)
		local set = row.Set
		local total = if stacked then width else chipWidth + 10 + textW
		local holder = frame("Hazard", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(total, height),
			Position = UDim2.new(0.5, 0, 0, y),
			AnchorPoint = Vector2.new(0.5, 0),
			ZIndex = z,
			Parent = parent,
		})
		holder:SetAttribute("Layout", mode)
		local tag = chip(holder, row.Chip, set.Top, set.Bottom, chipSize, z)
		tag.Name = "Tag"
		if stacked then
			tag.AnchorPoint = Vector2.new(0.5, 0)
			tag.Position = UDim2.new(0.5, 0, 0, 0)
		else
			tag.Position = UDim2.fromOffset(0, math.floor((height - chipHeight) / 2))
		end
		UI.Text({
			Name = "Text",
			Text = row.Text,
			Font = Theme.BodyFont,
			TextSize = textSize,
			Wrapped = mode ~= "Inline",
			Color = INK,
			X = if stacked then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left,
			Size = UDim2.fromOffset(textW + 2, textH + 2),
			Position = if stacked
				then UDim2.new(0.5, 0, 0, chipHeight + 4)
				else UDim2.fromOffset(chipWidth + 10, math.floor((height - textH) / 2) - 1),
			AnchorPoint = if stacked then Vector2.new(0.5, 0) else Vector2.zero,
			ZIndex = z,
			Parent = holder,
		})
	end
end

---------------------------------------------------------------------------
-- The card
---------------------------------------------------------------------------
local function build(zoneId: number, kind: string, options)
	local zone = Zones.Get(zoneId)
	local locked = kind == "Locked"
	local colors = palette(zone, locked)
	local units, scale = screenUnits()
	local phone = scale < 0.8
	-- Phones show no chat window: a landscape phone (wide, short) gets a wider, flatter card
	local widest = if not phone then MAX_WIDTH elseif units >= 1000 then WIDE_WIDTH else PHONE_WIDTH
	local maxWidth = math.min(widest, units - 24)
	local small = math.max(16, math.ceil(SMALL_PX / scale)) -- caption text size
	local kickerSize = math.max(16, math.ceil((SMALL_PX - 0.5) / scale))
	local kicker, rows = contentFor(zoneId, zone, kind, options)

	-- Name: as big as fits; the name area grows for the caption (up to the widest card)
	local areaMax = maxWidth - NAME_X - NAME_PAD - ROLL_OUT
	local name = string.upper(zone.Name)
	local nameSize = NAME_SIZE
	local nameWidth = textWidth(name, nameSize, Theme.Font)
	while nameWidth > areaMax - 8 and nameSize > 24 do
		nameSize -= 2
		nameWidth = textWidth(name, nameSize, Theme.Font)
	end
	local cardExtra = CARD_INSET_L + NAME_PAD - CARD_INSET_R - 2 * CARD_PAD -- inner width - area width
	local wanted = 0
	for _, row in rows do
		wanted = math.max(wanted, rowNatural(row, small))
	end
	local areaW = math.clamp(math.max(nameWidth + 8, MIN_AREA, wanted - cardExtra), 0, areaMax)
	local plaqueW = (NAME_X - PLAQUE_X) + areaW + NAME_PAD
	local bannerWidth = PLAQUE_X + plaqueW + ROLL_OUT

	local kickerH = kickerSize + 14
	local plaqueY = math.floor(kickerH / 2) + 3
	local emblemY = plaqueY + (PLAQUE_H - LIP) / 2 + 2

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

	-- Everything that drops / scales in together
	local banner = frame("Banner", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = Z, Parent = card })
	local bannerScale = Instance.new("UIScale")
	bannerScale.Parent = banner

	-- Caption card (behind the plaque, its top tucked under it)
	local captionHolder = nil
	local captionY = plaqueY + PLAQUE_H - CARD_TUCK
	local height = emblemY + EMBLEM / 2
	if #rows > 0 then
		local cardX = NAME_X - CARD_INSET_L
		local cardW = PLAQUE_X + plaqueW - CARD_INSET_R - cardX
		local inner = cardW - 2 * CARD_PAD
		local laid = {}
		local y = CARD_TUCK + 8
		for index, row in rows do
			if index > 1 then
				y += ROW_GAP
			end
			local rowHeight, make = layoutRow(row, small, inner)
			table.insert(laid, { Y = y, Make = make })
			y += rowHeight
		end
		local cardH = y + 10
		captionHolder = frame("Caption", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(cardX, captionY),
			Size = UDim2.fromOffset(cardW, cardH),
			ZIndex = Z,
			Parent = banner,
		})
		frame("Shadow", {
			BackgroundColor3 = INK,
			BackgroundTransparency = Theme.ShadeTransparency,
			Position = UDim2.fromOffset(0, 4),
			Size = UDim2.fromScale(1, 1),
			ZIndex = Z,
			Parent = captionHolder,
			UI.Corner(16),
		})
		local body = frame("Body", {
			BackgroundColor3 = WHITE,
			Position = UDim2.fromOffset(1, 1),
			Size = UDim2.new(1, -2, 1, -2),
			ZIndex = Z + 1,
			Parent = captionHolder,
			UI.Corner(15),
			UI.Gradient(Theme.Cloud, Theme.Mist),
			UI.Stroke(2.5, INK),
		})
		for index, entry in laid do
			if index > 1 then
				frame("Divider", {
					BackgroundColor3 = Theme.Haze,
					Position = UDim2.new(0, 18, 0, entry.Y - ROW_GAP / 2 - 1),
					Size = UDim2.new(1, -36, 0, 2),
					ZIndex = Z + 2,
					Parent = body,
				})
			end
			entry.Make(body, entry.Y - 1, Z + 3)
		end
		height = math.max(height, captionY + cardH + 4)
	end

	-- Plaque: drop shadow, lip with the Ink outline, the gradient face with a shine
	local plaque = frame("Plaque", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(PLAQUE_X, plaqueY),
		Size = UDim2.fromOffset(plaqueW, PLAQUE_H),
		ZIndex = Z + 5,
		Parent = banner,
	})
	frame("Shadow", {
		BackgroundColor3 = INK,
		BackgroundTransparency = Theme.ShadeTransparency,
		Position = UDim2.fromOffset(0, 5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = Z + 5,
		Parent = plaque,
		UI.Corner(CORNER),
	})
	local lip = frame("Lip", {
		BackgroundColor3 = colors.Lip,
		Size = UDim2.fromScale(1, 1),
		ZIndex = Z + 6,
		Parent = plaque,
		UI.Corner(CORNER),
		UI.Stroke(3, INK),
	})
	local face = frame("Face", {
		BackgroundColor3 = WHITE,
		Size = UDim2.new(1, 0, 1, -LIP),
		ZIndex = Z + 7,
		Parent = lip,
		UI.Corner(CORNER),
		UI.Gradient(colors.Top, colors.Bottom),
	})
	frame("Shine", {
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.74,
		Position = UDim2.fromOffset(NAME_X - PLAQUE_X - 8, 4),
		Size = UDim2.new(1, -(NAME_X - PLAQUE_X) - 14, 0.34, 0),
		ZIndex = Z + 8,
		Parent = face,
		UI.Round(),
	})
	-- The shine that sweeps across once it's in (a soft white band moved by the gradient's offset)
	local sweep = frame("Sweep", {
		BackgroundColor3 = WHITE,
		Size = UDim2.fromScale(1, 1),
		ZIndex = Z + 9,
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
		Position = UDim2.fromOffset(PLAQUE_X + plaqueW + ROLL_OUT - ROLL_W, plaqueY - 6),
		Size = UDim2.fromOffset(ROLL_W, PLAQUE_H + 10),
		ZIndex = Z + 10,
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
		ZIndex = Z + 11,
		Parent = roll,
		UI.Round(),
	})

	-- The name, centred in its area: a darker drop under a white-to-tint fill, both outlined in Ink
	local nameBox = UDim2.fromOffset(areaW + 8, PLAQUE_H - LIP)
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
		ZIndex = Z + 12,
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
		ZIndex = Z + 13,
		Parent = banner,
	})
	local fill = UI.Gradient(WHITE, colors.Tint)
	fill.Name = "Fill"
	fill.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.45, WHITE),
		ColorSequenceKeypoint.new(1, colors.Tint),
	})
	fill.Parent = nameLabel

	-- The emblem over the plaque's left end (the zone's emoji on a badge until its picture is uploaded)
	local emblem = Icons.New("Zone_" .. zone.Key, {
		Name = "Emblem",
		Size = UDim2.fromOffset(EMBLEM, EMBLEM),
		Position = UDim2.fromOffset(EMBLEM_X, emblemY),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = -6,
		ZIndex = Z + 15,
		Parent = banner,
	})
	local emblemScale = Instance.new("UIScale")
	emblemScale.Parent = emblem
	if not Icons.Image("Zone_" .. zone.Key) then
		frame("Badge", {
			BackgroundColor3 = WHITE,
			Size = UDim2.fromScale(0.86, 0.86),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = Z + 14,
			Parent = emblem,
			UI.Round(),
			UI.Stroke(4, Theme.Sets.Bolt.Bottom),
			UI.Gradient(colors.Top, colors.Bottom),
		})
		local glyph = emblem:FindFirstChild("Emoji")
		if glyph then
			glyph.Size = UDim2.fromScale(0.54, 0.54)
			glyph.ZIndex = Z + 16
		end
	end
	if locked then
		local image = emblem:FindFirstChild("Image")
		if image then
			image.ImageColor3 = Color3.fromRGB(165, 172, 200)
		end
		-- on the emblem's lower left, clear of the caption card
		Icons.New("Lock", {
			Name = "Lock",
			Size = UDim2.fromOffset(48, 48),
			Position = UDim2.fromScale(0.2, 0.8),
			Rotation = -8,
			ZIndex = Z + 17,
			Parent = emblem,
		})
	end

	-- Kicker over the plaque's top edge, centred on the name
	local kickerChip = chip(banner, kicker.Text, (kicker.Set or Theme.Sets.Sky).Top, (kicker.Set or Theme.Sets.Sky).Bottom, kickerSize, Z + 18, kicker.Cloud, colors.Dark)
	kickerChip.Name = "Kicker"
	kickerChip.AnchorPoint = Vector2.new(0.5, 0)
	local half = kickerChip.Size.X.Offset / 2
	local centre = math.clamp(NAME_X + areaW / 2, PLAQUE_X + half + 24, PLAQUE_X + plaqueW - half - 10)
	kickerChip.Position = UDim2.fromOffset(centre, plaqueY - kickerH + 10)
	if kind == "Unlocked" then
		for side = -1, 1, 2 do
			Icons.New("Star", {
				Name = if side < 0 then "StarLeft" else "StarRight",
				Size = UDim2.fromOffset(28, 28),
				Position = UDim2.new(0.5, side * (half + 14), 0.5, -1),
				Rotation = side * 14,
				ZIndex = Z + 24,
				Parent = kickerChip,
			})
		end
	end

	card.Size = UDim2.fromOffset(bannerWidth, height)
	-- Narrow screens: shrink the whole card to fit
	local fit = math.min(1, (units - 16) / bannerWidth)
	cardScale.Scale = fit

	return {
		Card = card,
		Height = height * fit,
		Banner = banner,
		BannerScale = bannerScale,
		Emblem = emblem,
		EmblemScale = emblemScale,
		Kicker = kickerChip,
		Caption = captionHolder,
		CaptionY = captionY,
		Sweep = sweepGradient,
	}
end

---------------------------------------------------------------------------
-- Showing one card
---------------------------------------------------------------------------
-- Keeps the card on the spacer's spot (in Overlay units) while it's shown
local function follow(card: Frame, spacer: Frame?)
	local interface = Registry.InterfaceController
	local root = interface.OverlayRoot
	local function place()
		if not card.Parent then
			return
		end
		local scale = math.max(interface.OverlayScale or 1, 0.01)
		local y
		if spacer and spacer.Parent and spacer.AbsolutePosition.Y > 0 then
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

	-- In: drop down + scale up with a little overshoot, the emblem spins in, the caption card slides
	-- out from under the plaque, then the shine sweeps
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
	if parts.Caption then
		local x = parts.Caption.Position.X.Offset
		parts.Caption.Position = UDim2.fromOffset(x, parts.CaptionY - 26)
		task.delay(0.16, function()
			UI.Tween(parts.Caption, 0.4, { Position = UDim2.fromOffset(x, parts.CaptionY) }, Enum.EasingStyle.Back)
		end)
	end
	task.delay(0.22, function()
		UI.Pop(parts.Kicker, 1.3)
	end)
	task.delay(IN_TIME * 0.8, function()
		parts.Sweep.Offset = Vector2.new(-1, 0)
		UI.Tween(parts.Sweep, 0.7, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	end)

	-- Hold (cut short when a newer title is waiting)
	local options = entry.Options or {}
	local hold = options.Duration or (if entry.Kind == "Enter" and options.Repeat then HOLD.Repeat else HOLD[entry.Kind] or HOLD.Enter)
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
	-- Already on screen or waiting (an "Unlocked" card names the zone too: walking in needs no second one)
	local function covers(entry): boolean
		return entry.ZoneId == zoneId and (entry.Kind == which or (which == "Enter" and entry.Kind == "Unlocked"))
	end
	if current and covers(current) then
		return
	end
	for _, waiting in queue do
		if covers(waiting) then
			return
		end
	end
	-- A newer "Enter" replaces one still waiting (only the zone you're in now matters)
	if which == "Enter" then
		for index = #queue, 1, -1 do
			if queue[index].Kind == "Enter" then
				table.remove(queue, index)
			end
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
