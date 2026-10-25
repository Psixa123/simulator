--!nonstrict
-- Full-screen egg opening and pet reveal: a pet-simulator style hatch in the Sky Lab look.
--
-- Hatch.Play(result, options) yields until the animation is finished.
--   result  = { Egg = eggId?, Results = { { Id = petId, New = boolean?, Golden = boolean?, Rainbow = boolean? } } }
--   options = { Title = string?, Hold = seconds?, Ribbon = candy set name?, Quick = boolean?,
--               FreezeAt = seconds? (preview renders only: the animation clock stops there) }
--   A Hold under 1.5 s (auto hatch passes 1.1) plays the quick version, and the dimmed backdrop stays
--   up between back-to-back hatches.
-- Hatch.IsPlaying() -> boolean
-- Hatch.Reveal(petId, tier, title) shows a single pet without an egg (rewards, drops).
--
-- What plays: the world blurs behind a deep ink-blue backdrop (the HUD and proximity prompts hide),
-- a candy ribbon with the egg's name drops in, the egg lands on a glowing lab pad, wobbles three
-- times (tick... tick... TICK) cracking a bit more each time and taking the rarity's colour, puffs up
-- and pops (flash, shell shards, shockwave rings, sparkles), and the pet pops out above its name card.
-- Epic and better: a stamp, screen shake and confetti. A tap skips to the burst, then closes.
-- One RenderStepped loop draws every frame from the animation clock alone, so a skip just moves the
-- clock; the backdrop, blur, HUD and prompts are restored on every way out (end, skip, error, reset).

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pets = require(Shared.Config.Pets)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local PetModels = require(Shared.Models.PetModels)

local Registry = require(script.Parent.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI)
local Theme = require(script.Parent.Parent.Theme)
local Icons = require(script.Parent.Parent.Icons)
local Viewport = require(script.Parent.Parent.Viewport)

local Hatch = {}

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------
local WHITE = Color3.new(1, 1, 1)
local INK = Theme.Ink
local BACKDROP_TOP = Color3.fromRGB(32, 46, 112)
local BACKDROP_BOTTOM = Color3.fromRGB(10, 14, 42)
local VIGNETTE = Color3.fromRGB(4, 6, 24)
local POOL_COLOR = Color3.fromRGB(70, 128, 240) -- the soft light behind the stage
local NEUTRAL_GLOW = Color3.fromRGB(150, 220, 255) -- the pad's glow before the egg shows its rarity
local DIM_TRANSPARENCY = 0.1
local BLUR_SIZE = 18
local GRAVITY = 1500 -- shards and confetti, offset px / s²

-- Slot layout in Overlay units: the stage (rays, pad, egg / pet) with the name card under it
local SLOT_WIDTH = 300
local CARD_TOP = 334
local CARD_HEIGHT = 92
local SLOT_HEIGHT = CARD_TOP + 14 + CARD_HEIGHT + 6
local SLOT_GAP = 16
local RIBBON_HEIGHT = 84 -- the title ribbon above the slots (with its tails and the count chip)

-- Stage geometry (offsets inside the slot)
local CENTER_X = SLOT_WIDTH / 2
local PAD_Y = 262 -- centre of the pad's top face
local PAD_A, PAD_B, PAD_DEPTH = 100, 25, 26 -- top face half width / half height, side height
local EGG_VIEW = 290 -- egg viewport side (room for the wobble)
local EGG_ZOOM = 1.7 -- the egg is EGG_VIEW / EGG_ZOOM tall
local EGG_HEIGHT = EGG_VIEW / EGG_ZOOM
local EGG_WIDTH = EGG_HEIGHT * 0.78
local EGG_Y = PAD_Y + 4 - EGG_HEIGHT / 2 -- egg centre: its bottom rests on the pad
local PET_VIEW = 270
local PET_Y = PAD_Y - 104 -- pet centre (it hovers a little over the pad)
local GLOW_Y = EGG_Y

-- Timelines (seconds). Ticks = { start, length, degrees }; the stagger delays each slot of a
-- multi-hatch. Hold counts from the last pop.
local NORMAL = {
	Intro = 0.35,
	Ribbon = 0.06,
	RibbonTime = 0.5,
	Pad = 0.12,
	Drop = 0.3,
	Land = 0.6,
	Ticks = { { 0.98, 0.3, 6 }, { 1.5, 0.34, 10 }, { 2.04, 0.42, 15 } },
	Puff = 2.5,
	Pop = 2.7,
	Stagger = 0.15,
	Hold = 2.2,
	Outro = 0.25,
	MinHold = 0.45,
}
local QUICK = { -- auto hatch: well under 2 s from start to finish
	Intro = 0.2,
	Ribbon = 0,
	RibbonTime = 0.3,
	Pad = 0,
	Drop = 0.03,
	Land = 0.2,
	Ticks = { { 0.22, 0.16, 11 } },
	Puff = 0.36,
	Pop = 0.48,
	Stagger = 0.05,
	Hold = 1.1,
	Outro = 0.15,
	MinHold = 0.2,
}
local REVEAL = { -- no egg: a ball of light gathers on the pad and bursts
	Intro = 0.35,
	Ribbon = 0.06,
	RibbonTime = 0.5,
	Pad = 0.12,
	Charge = 0.36,
	Pop = 1.1,
	Stagger = 0.15,
	Hold = 2.2,
	Outro = 0.25,
	MinHold = 0.45,
}

-- Cracks on the egg, by stage: polylines in egg units (x: half widths, y: half heights from the
-- centre, down is +); stage 3 is the belt the egg breaks along
local CRACKS = {
	{ 1, { { 0.08, -0.66 }, { 0.22, -0.54 }, { 0.12, -0.42 }, { 0.3, -0.3 } } },
	{ 2, { { 0.08, -0.66 }, { -0.08, -0.56 }, { 0.0, -0.44 }, { -0.18, -0.32 }, { -0.1, -0.2 } } },
	{ 2, { { 0.12, -0.42 }, { 0.0, -0.36 } } },
	{ 3, { { -0.84, 0.0 }, { -0.62, -0.13 }, { -0.42, 0.02 }, { -0.22, -0.12 }, { -0.02, 0.03 }, { 0.2, -0.11 }, { 0.42, 0.03 }, { 0.62, -0.1 }, { 0.84, 0.02 } } },
	{ 3, { { -0.1, -0.2 }, { -0.22, -0.12 } } },
	{ 3, { { 0.3, -0.3 }, { 0.2, -0.11 } } },
}

-- Frames only round into pills, so an ellipse is four overlapping pills: { width, height } factors
local ELLIPSE = { { 0.968, 0.495 }, { 0.871, 0.79 }, { 0.687, 0.927 }, { 0.5, 0.988 } }

local CONFETTI_COLORS = {
	Theme.Sets.Bolt.Top,
	Theme.Sets.Sky.Top,
	Theme.Sets.Coral.Top,
	Theme.Sets.Leaf.Top,
	Theme.Sets.Storm.Top,
	Theme.Sets.Pink.Top,
	Theme.Sets.Rain.Top,
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function lerp(a: number, b: number, k: number): number
	return a + (b - a) * k
end

-- 0..1: how far `t` is through [start, start + length]
local function progress(t: number, start: number, length: number): number
	if length <= 0 then
		return if t >= start then 1 else 0
	end
	return math.clamp((t - start) / length, 0, 1)
end

local function outQuad(x: number): number
	return 1 - (1 - x) * (1 - x)
end

local function inQuad(x: number): number
	return x * x
end

local function outCubic(x: number): number
	return 1 - (1 - x) ^ 3
end

local function outBack(x: number, overshoot: number?): number
	local c = overshoot or 1.70158
	return 1 + (c + 1) * (x - 1) ^ 3 + c * (x - 1) ^ 2
end

-- 0 -> 1 with a ~15 % overshoot and a little settle (the pet popping out)
local function outElastic(x: number): number
	if x >= 1 then
		return 1
	end
	return 1 - math.exp(-6 * x) * math.cos(x * math.pi * 3.2)
end

local function box(props)
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = WHITE
	for key, value in props do
		if type(key) == "number" then
			value.Parent = frame
		elseif key ~= "Parent" then
			frame[key] = value
		end
	end
	frame.Parent = props.Parent
	return frame
end

local function scaler(parent: Instance, scale: number?): UIScale
	local object = Instance.new("UIScale")
	object.Scale = scale or 1
	object.Parent = parent
	return object
end

local function transparencyGradient(rotation: number, points)
	local keypoints = {}
	for _, point in points do
		table.insert(keypoints, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new(keypoints)
	return gradient
end

-- Four pills making an ellipse w x h centred on (x, y). `paint(layer, v0, v1, u0, u1)` colours each
-- pill; v0..v1 / u0..u1 are where its edges sit across the ellipse (0..1), to line gradients up.
local function ellipse(parent: Instance, name: string, x: number, y: number, w: number, h: number, z: number, paint)
	local layers = {}
	for _, spec in ELLIPSE do
		local layer = box({
			Name = name,
			Size = UDim2.fromOffset(w * spec[1], h * spec[2]),
			Position = UDim2.fromOffset(x, y),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = z,
			Parent = parent,
			UI.Round(),
		})
		if paint then
			paint(layer, (1 - spec[2]) / 2, (1 + spec[2]) / 2, (1 - spec[1]) / 2, (1 + spec[1]) / 2)
		end
		table.insert(layers, layer)
	end
	return layers
end

local function solid(color: Color3, transparency: number?)
	return function(layer)
		layer.BackgroundColor3 = color
		layer.BackgroundTransparency = transparency or 0
	end
end

-- A vertical gradient across the whole ellipse (each pill gets its slice)
local function vertical(top: Color3, bottom: Color3)
	return function(layer, v0, v1)
		local gradient = UI.Gradient(top:Lerp(bottom, v0), top:Lerp(bottom, v1))
		gradient.Parent = layer
	end
end

-- A horizontal shading across the whole shape: colorAt(u) for u = 0 (left) .. 1 (right)
local function horizontal(colorAt)
	return function(layer, _, _, u0, u1)
		local keypoints = {}
		for index = 0, 4 do
			local k = index / 4
			table.insert(keypoints, ColorSequenceKeypoint.new(k, colorAt(lerp(u0, u1, k))))
		end
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(keypoints)
		gradient.Parent = layer
	end
end

-- Candy surface: Ink outline, Lip body, gradient face (lip px above its bottom) and a white shine
local function candy(parent: Instance, set, props)
	local z = props.ZIndex or 1
	local radius = props.Radius
	local lip = props.Lip or 5
	local body = box({
		Name = props.Name or "Candy",
		BackgroundColor3 = set.Lip,
		Size = props.Size,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Rotation = props.Rotation or 0,
		ZIndex = z,
		Parent = parent,
		if radius then UI.Corner(radius) else UI.Round(),
		UI.Stroke(props.Outline or Theme.Outline, INK),
	})
	local face = box({
		Name = "Face",
		Size = UDim2.new(1, 0, 1, -lip),
		ZIndex = z,
		Parent = body,
		if radius then UI.Corner(radius) else UI.Round(),
		UI.Gradient(set.Top, set.Bottom),
	})
	box({
		Name = "Shine",
		BackgroundTransparency = 0.72,
		Size = UDim2.new(1, -12, 0.36, 0),
		Position = UDim2.new(0.5, 0, 0, 3),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = z,
		Parent = face,
		if radius then UI.Corner(math.max(radius - 4, 2)) else UI.Round(),
	})
	return body, face
end

-- Four-point sparkle (two crossed rounded bars)
local function sparkle(parent: Instance, size: number, color: Color3, z: number)
	local holder = box({
		Name = "Sparkle",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = z,
		Visible = false,
		Parent = parent,
	})
	for index = 1, 2 do
		box({
			Name = "Bar",
			BackgroundColor3 = color,
			Size = if index == 1 then UDim2.new(0.22, 0, 1, 0) else UDim2.new(1, 0, 0.22, 0),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = z,
			Parent = holder,
			UI.Round(),
		})
	end
	return holder
end

local function textWidth(text: string, size: number): number
	local ok, bounds = pcall(TextService.GetTextSize, TextService, text, size, Theme.Font, Vector2.new(4096, 4096))
	if ok and typeof(bounds) == "Vector2" then
		return bounds.X
	end
	return #text * size * 0.56
end

local function touchScreen(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Everything that can fade inside `root`, with how opaque it is now
local FADE_PROPS = {
	{ "GuiObject", "BackgroundTransparency" },
	{ "TextLabel", "TextTransparency" },
	{ "ImageLabel", "ImageTransparency" },
	{ "ViewportFrame", "ImageTransparency" },
	{ "UIStroke", "Transparency" },
}
local function fadeTargets(root: Instance)
	local targets = {}
	for _, object in root:GetDescendants() do
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

---------------------------------------------------------------------------
-- Session: the backdrop, the blur and the hidden HUD / prompts. It outlives a play while another
-- hatch is queued or auto hatch is running, so they don't flicker between eggs.
---------------------------------------------------------------------------
local playing = false
local waiting = 0
local session = nil
local current = nil -- the play being drawn

local function setHud(hidden: boolean)
	local interface = Registry.InterfaceController
	if interface.SetHudHidden then
		interface.SetHudHidden("Hatch", hidden)
	elseif interface.HudGui then
		interface.HudGui.Enabled = not hidden
	end
end

local function setPrompts(s, hidden: boolean)
	if hidden == s.PromptsHidden then
		return
	end
	s.PromptsHidden = hidden
	if hidden then
		s.PromptsWere = ProximityPromptService.Enabled
		ProximityPromptService.Enabled = false
	else
		ProximityPromptService.Enabled = s.PromptsWere
	end
end

-- The blur lives under the current camera; a new camera (rare) gets a new blur
local function blurOf(s)
	local camera = workspace.CurrentCamera
	if camera and s.Blur.Parent ~= camera then
		s.Blur:Destroy()
		local blur = Instance.new("BlurEffect")
		blur.Name = "HatchBlur"
		blur.Size = 0
		blur.Parent = camera
		s.Blur = blur
	end
	return s.Blur
end

-- How far the backdrop is in: 0 = the world as normal, 1 = blurred, dimmed, HUD and prompts hidden
local function setLevel(s, level: number)
	s.Level = level
	s.Dim.BackgroundTransparency = 1 - (1 - DIM_TRANSPARENCY) * level
	for _, edge in s.Edges do
		edge.BackgroundTransparency = 1 - level
	end
	blurOf(s).Size = BLUR_SIZE * level
	local hidden = level > 0.4
	if hidden ~= s.HudHidden then
		s.HudHidden = hidden
		setHud(hidden)
	end
	setPrompts(s, hidden)
end

local function finishSession(s)
	if session == s then
		session = nil
	end
	for _, connection in s.Connections do
		connection:Disconnect()
	end
	table.clear(s.Connections)
	if s.HudHidden then
		s.HudHidden = false
		setHud(false)
	end
	setPrompts(s, false)
	s.Blur:Destroy()
	s.Root:Destroy()
end

local function openSession()
	local s = session
	if s then
		s.Generation += 1 -- cancels a pending close: this play takes the backdrop over
		return s
	end

	local interface = Registry.InterfaceController
	local root = UI.Create("TextButton", {
		Name = "Hatch",
		AutoButtonColor = false,
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 30,
		Parent = interface.OverlayRoot,
	})
	local dim = box({
		Name = "Dim",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = root,
		UI.Gradient(BACKDROP_TOP, BACKDROP_BOTTOM),
	})
	-- A soft pool of light behind the stage (placed by each play)
	local pool = {}
	for index = 1, 4 do
		table.insert(
			pool,
			box({
				Name = "Light",
				BackgroundColor3 = POOL_COLOR,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				ZIndex = 2,
				Parent = root,
				UI.Round(),
			})
		)
	end
	-- Vignette: the edges darken
	local edges = {}
	local function edge(name: string, size: UDim2, position: UDim2, anchor: Vector2, rotation: number)
		table.insert(
			edges,
			box({
				Name = name,
				BackgroundColor3 = VIGNETTE,
				BackgroundTransparency = 1,
				Size = size,
				Position = position,
				AnchorPoint = anchor,
				ZIndex = 3,
				Parent = root,
				transparencyGradient(rotation, { { 0, 0.2 }, { 0.5, 0.72 }, { 1, 1 } }),
			})
		)
	end
	edge("Top", UDim2.fromScale(1, 0.32), UDim2.fromScale(0, 0), Vector2.zero, 90)
	edge("Bottom", UDim2.fromScale(1, 0.32), UDim2.fromScale(0, 1), Vector2.new(0, 1), -90)
	edge("Left", UDim2.fromScale(0.24, 1), UDim2.fromScale(0, 0), Vector2.zero, 0)
	edge("Right", UDim2.fromScale(0.24, 1), UDim2.fromScale(1, 0), Vector2.new(1, 0), 180)

	local blur = Instance.new("BlurEffect")
	blur.Name = "HatchBlur"
	blur.Size = 0
	blur.Parent = workspace.CurrentCamera

	s = {
		Root = root,
		Dim = dim,
		Pool = pool,
		Edges = edges,
		Blur = blur,
		Level = 0,
		Generation = 0,
		HudHidden = false,
		PromptsHidden = false,
		PromptsWere = true,
		Connections = {},
	}
	-- A panel opening (auto hatch stopped and reopened the Egg panel) ends a lingering backdrop
	table.insert(
		s.Connections,
		interface.PanelOpened:Connect(function()
			if session == s and not playing then
				finishSession(s)
			end
		end)
	)
	-- Dying / resetting ends the hatch at once
	table.insert(
		s.Connections,
		Players.LocalPlayer.CharacterRemoving:Connect(function()
			if current then
				current.Aborted = true
			elseif session == s then
				finishSession(s)
			end
		end)
	)
	session = s
	return s
end

-- Fades the backdrop out after `delay` unless another hatch has taken it over by then
local function closeLater(s, delay: number)
	s.Generation += 1
	local generation = s.Generation
	task.delay(delay, function()
		if session ~= s or s.Generation ~= generation or playing then
			return
		end
		local from = s.Level
		local start = os.clock()
		while true do
			if session ~= s or s.Generation ~= generation then
				return -- reopened: the new play owns it now
			end
			local k = progress(os.clock(), start, 0.25)
			setLevel(s, from * (1 - outQuad(k)))
			if k >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
		finishSession(s)
	end)
end

---------------------------------------------------------------------------
-- Building one play
---------------------------------------------------------------------------
local function buildRibbon(parent: Instance, title: string, setName: string, count: number, maxWidth: number)
	local set = Theme.Set(setName)
	local bandWidth = math.clamp(textWidth(title, 34) + 120, 300, math.max(maxWidth - 96, 220))
	local holder = box({
		Name = "Ribbon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(bandWidth + 96, RIBBON_HEIGHT),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 2,
		Parent = parent,
	})
	local scale = scaler(holder)
	-- Tails folding back behind the band's ends
	for side = -1, 1, 2 do
		local tail = box({
			Name = if side < 0 then "TailLeft" else "TailRight",
			BackgroundColor3 = WHITE,
			Size = UDim2.fromOffset(74, 44),
			Position = UDim2.new(0.5, side * (bandWidth / 2 + 4), 0.5, 13),
			AnchorPoint = Vector2.new(if side < 0 then 1 else 0, 0.5),
			Rotation = side * 7,
			ZIndex = 1,
			Parent = holder,
			UI.Corner(12),
			UI.Stroke(Theme.Outline, INK),
			UI.Gradient(set.Bottom, set.Lip),
		})
		-- the fold: a darker corner where the tail goes behind the band
		box({
			Name = "Fold",
			BackgroundColor3 = set.Stroke,
			Size = UDim2.fromOffset(26, 30),
			Position = UDim2.new(if side < 0 then 1 else 0, side * -2, 0, 1),
			AnchorPoint = Vector2.new(if side < 0 then 1 else 0, 0),
			ZIndex = 1,
			Parent = tail,
			UI.Corner(8),
		})
	end
	local band, face = candy(holder, set, {
		Name = "Band",
		Size = UDim2.fromOffset(bandWidth, 60),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Radius = 18,
		Lip = 6,
		ZIndex = 2,
	})
	UI.Text({
		Name = "Title",
		Text = title,
		TextSize = 34,
		Scaled = true,
		MinTextSize = 16,
		Stroke = set.Stroke,
		StrokeThickness = 3,
		Size = UDim2.new(1, -96, 1, -10),
		Position = UDim2.new(0.5, 0, 0.5, 2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 3,
		Parent = face,
	})
	local stars = {}
	for side = -1, 1, 2 do
		table.insert(
			stars,
			Icons.New("Star", {
				Name = "Star",
				Size = UDim2.fromOffset(34, 34),
				Position = UDim2.new(0.5, side * (bandWidth / 2 - 30), 0.5, -2),
				ZIndex = 3,
				Parent = band,
			})
		)
	end
	-- "x3" chip on the band's corner for a multi-hatch
	local chip, chipScale = nil, nil
	if count > 1 then
		local bolt = Theme.Sets.Bolt
		chip = candy(holder, bolt, {
			Name = "Count",
			Size = UDim2.fromOffset(58, 44),
			Position = UDim2.new(0.5, bandWidth / 2 - 4, 0.5, -26),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = 10,
			Radius = 16,
			Lip = 5,
			ZIndex = 4,
		})
		UI.Text({
			Name = "Text",
			Text = "x" .. count,
			TextSize = 26,
			Stroke = bolt.Stroke,
			StrokeThickness = 2.5,
			Position = UDim2.fromOffset(0, -2),
			ZIndex = 5,
			Parent = chip,
		})
		chipScale = scaler(chip, 0)
	end
	return { Frame = holder, Scale = scale, Stars = stars, Chip = chip, ChipScale = chipScale }
end

-- The lab pad the egg lands on: a short cylinder (Sky side with little lights, Mist top face with
-- a ring that glows in the egg's colour)
local function buildPad(parent: Instance)
	local width, height = 2 * PAD_A + 12, 2 * PAD_B + PAD_DEPTH + 12
	local cx, cy = width / 2, PAD_B + 6
	local pad = box({
		Name = "Pad",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(width, height),
		Position = UDim2.fromOffset(CENTER_X, PAD_Y),
		AnchorPoint = Vector2.new(0.5, cy / height),
		ZIndex = 5,
		Parent = parent,
	})
	local sky = Theme.Sets.Sky
	local outline = Theme.Outline
	local function sideColor(u: number): Color3
		if u < 0.3 then
			return sky.Lip:Lerp(sky.Top, u / 0.3)
		elseif u < 0.65 then
			return sky.Top:Lerp(sky.Bottom, (u - 0.3) / 0.35)
		end
		return sky.Bottom:Lerp(sky.Lip, (u - 0.65) / 0.35)
	end
	-- Ink silhouette (top face + side + bottom rim), then the side, then the top face
	ellipse(pad, "Outline", cx, cy + PAD_DEPTH, 2 * (PAD_A + outline), 2 * (PAD_B + outline), 1, solid(INK))
	box({
		Name = "Outline",
		BackgroundColor3 = INK,
		Size = UDim2.fromOffset(2 * (PAD_A + outline), PAD_DEPTH),
		Position = UDim2.fromOffset(cx, cy),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 1,
		Parent = pad,
	})
	ellipse(pad, "Side", cx, cy + PAD_DEPTH, 2 * PAD_A, 2 * PAD_B, 2, horizontal(sideColor))
	box({
		Name = "Side",
		Size = UDim2.fromOffset(2 * PAD_A, PAD_DEPTH),
		Position = UDim2.fromOffset(cx, cy),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 2,
		Parent = pad,
		UI.Create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, sideColor(0)),
				ColorSequenceKeypoint.new(0.3, sideColor(0.3)),
				ColorSequenceKeypoint.new(0.65, sideColor(0.65)),
				ColorSequenceKeypoint.new(1, sideColor(1)),
			}),
		}),
	})
	-- Lab lights along the side
	local lights = {}
	for index, u in { -0.72, -0.36, 0, 0.36, 0.72 } do
		local front = PAD_B * math.sqrt(1 - u * u)
		local light = box({
			Name = "Light" .. index,
			BackgroundColor3 = Theme.Sets.Bolt.Top,
			Size = UDim2.fromOffset(9, 9),
			Position = UDim2.fromOffset(cx + u * PAD_A, cy + front + PAD_DEPTH / 2),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 3,
			Parent = pad,
			UI.Round(),
			UI.Stroke(1.5, Theme.Sets.Sky.Stroke),
		})
		table.insert(lights, light)
	end
	ellipse(pad, "Rim", cx, cy, 2 * PAD_A, 2 * PAD_B, 4, solid(INK))
	ellipse(pad, "Face", cx, cy, 2 * (PAD_A - outline), 2 * (PAD_B - outline), 5, vertical(Theme.Cloud, Theme.Haze))
	-- The glowing ring on the face (a coloured ellipse with a face-coloured one inside)
	local ring = ellipse(pad, "Ring", cx, cy + 1, 2 * PAD_A * 0.76, 2 * PAD_B * 0.76, 6, solid(NEUTRAL_GLOW))
	ellipse(pad, "RingInside", cx, cy + 1, 2 * PAD_A * 0.64, 2 * PAD_B * 0.64, 7, vertical(Theme.Mist, Theme.Cloud))
	-- Contact shadow of the egg / pet
	local shadow = box({
		Name = "Shadow",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(96, 24),
		Position = UDim2.fromOffset(cx, cy + 3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 8,
		Parent = pad,
	})
	local shadowScale = scaler(shadow)
	ellipse(shadow, "Shade", 48, 12, 96, 24, 1, solid(INK, 0.78))
	return { Frame = pad, Scale = scaler(pad, 0), Lights = lights, Ring = ring, Shadow = shadow, ShadowScale = shadowScale }
end

local function buildCard(slot: Frame, entry, def, rarity, tier: string)
	local holder = box({
		Name = "Card",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(272, CARD_HEIGHT),
		Position = UDim2.fromOffset(CENTER_X, CARD_TOP + 14),
		AnchorPoint = Vector2.new(0.5, 0),
		Visible = false,
		ZIndex = 2,
		Parent = slot,
	})
	local scale = scaler(holder, 0.6)
	box({
		Name = "Shadow",
		BackgroundColor3 = INK,
		BackgroundTransparency = Theme.ShadeTransparency,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, 6),
		ZIndex = 1,
		Parent = holder,
		UI.Corner(22),
	})
	box({
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = holder,
		UI.Corner(22),
		UI.Stroke(Theme.Outline, INK),
		UI.Gradient(Theme.Cloud, Theme.Mist),
	})
	-- Rarity pill on the top edge
	local colors = Theme.Rarity(rarity.Color)
	local pill = box({
		Name = "Rarity",
		BackgroundColor3 = colors.Edge,
		Size = UDim2.fromOffset(156, 34),
		Position = UDim2.new(0.5, 0, 0, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 4,
		Parent = holder,
		UI.Round(),
		UI.Stroke(2.5, INK),
	})
	local pillFace = box({
		Name = "Face",
		Size = UDim2.new(1, 0, 1, -4),
		ZIndex = 4,
		Parent = pill,
		UI.Round(),
		UI.Gradient(colors.Top, colors.Bottom),
	})
	UI.Text({
		Name = "Text",
		Text = string.upper(rarity.Name),
		TextSize = 19,
		Stroke = colors.Edge,
		StrokeThickness = 2,
		Position = UDim2.fromOffset(0, 1),
		ZIndex = 5,
		Parent = pillFace,
	})
	-- Name: Ink on the card; golden / rainbow pets get their tier's gradient with an outline
	local name = UI.Text({
		Name = "PetName",
		Text = Pets.DisplayName(def.Id, tier),
		TextSize = 30,
		Scaled = true,
		MinTextSize = 14,
		Color = if tier == "Normal" then INK else WHITE,
		Stroke = if tier == "Normal" then nil else INK,
		StrokeThickness = 2.5,
		Size = UDim2.new(1, -28, 0, 36),
		Position = UDim2.new(0.5, 0, 0, 20),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 3,
		Parent = holder,
	})
	if tier == "Rainbow" then
		UI.Create("UIGradient", { Color = PetModels.RainbowSequence, Parent = name })
	elseif tier == "Golden" then
		UI.Gradient(Theme.Sets.Bolt.Top, Theme.Sets.Bolt.Bottom).Parent = name
	end
	-- Energy bonus: the raindrop icon and "+35% Energy"
	local bonus = box({
		Name = "Bonus",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 0, 26),
		Position = UDim2.new(0.5, 0, 0, 58),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 3,
		Parent = holder,
		UI.List(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	Icons.New("Energy", { Name = "Icon", Size = UDim2.fromOffset(26, 26), LayoutOrder = 1, ZIndex = 3, Parent = bonus })
	local bonusText = UI.Text({
		Name = "Text",
		Text = '<font color="#1F8F38">' .. Format.Bonus(Formulas.PetBonus(entry.Id, tier)) .. "</font> Energy",
		Rich = true,
		TextSize = 21,
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 2,
		ZIndex = 3,
		Parent = bonus,
	})
	bonusText.AutomaticSize = Enum.AutomaticSize.X
	-- "NEW!" candy tag on the card's corner
	local newTag, newScale = nil, nil
	if entry.New == true then
		local coral = Theme.Sets.Coral
		newTag = candy(holder, coral, {
			Name = "New",
			Size = UDim2.fromOffset(78, 36),
			Position = UDim2.new(1, -8, 0, -6),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = 12,
			Radius = 12,
			Lip = 5,
			Outline = 2.5,
			ZIndex = 6,
		})
		UI.Text({ Name = "Text", Text = "NEW!", TextSize = 21, Stroke = coral.Stroke, StrokeThickness = 2, Position = UDim2.fromOffset(0, -2), ZIndex = 7, Parent = newTag })
		newScale = scaler(newTag, 0)
	end
	return { Frame = holder, Scale = scale, New = newTag, NewScale = newScale }
end

local function buildSlot(row: Frame, index: number, entry, eggId: string?, multi: boolean, rng: Random)
	local def = Pets.Pets[entry.Id] or Pets.Pets.Puffling
	local rarity = Pets.Rarities[def.Rarity] or Pets.Rarities.Common
	local tier = Pets.TierOf(entry)
	local egg = eggId and Pets.Eggs[eggId]

	local frame = box({
		Name = "Slot" .. index,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(SLOT_WIDTH, SLOT_HEIGHT),
		LayoutOrder = index,
		ZIndex = 1,
		Parent = row,
	})
	local stage = box({ Name = "Stage", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = frame })
	local fx = box({ Name = "FX", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = frame })

	-- Soft light rays (alternating wide and narrow, through the centre)
	local rays = {}
	local rayLength = if multi then 330 else 420
	for rayIndex = 1, 8 do
		local ray = box({
			Name = "Ray",
			BackgroundColor3 = NEUTRAL_GLOW,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(if rayIndex % 2 == 1 then 46 else 22, rayLength),
			Position = UDim2.fromOffset(CENTER_X, GLOW_Y),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 1,
			Parent = stage,
			transparencyGradient(90, { { 0, 1 }, { 0.16, 0.8 }, { 0.36, 0.35 }, { 0.5, 0.2 }, { 0.64, 0.35 }, { 0.84, 0.8 }, { 1, 1 } }),
		})
		table.insert(rays, { Frame = ray, Base = (rayIndex - 1) * 22.5, Length = rayLength })
	end

	-- Layered glow around the egg
	local glow = {}
	for glowIndex, spec in { { 330, 0.1 }, { 256, 0.12 }, { 196, 0.14 }, { 146, 0.17 }, { 104, 0.2 } } do
		table.insert(glow, {
			Frame = box({
				Name = "Glow" .. glowIndex,
				BackgroundColor3 = NEUTRAL_GLOW,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(spec[1], spec[1]),
				Position = UDim2.fromOffset(CENTER_X, GLOW_Y),
				AnchorPoint = Vector2.new(0.5, 0.5),
				ZIndex = 2,
				Parent = stage,
				UI.Round(),
			}),
			Alpha = spec[2],
		})
	end
	-- A column of light rising from the pad
	local beam = box({
		Name = "Beam",
		BackgroundColor3 = NEUTRAL_GLOW,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(2 * PAD_A * 0.72, 250),
		Position = UDim2.fromOffset(CENTER_X, PAD_Y + 2),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = 3,
		Parent = stage,
		UI.Corner(60),
		transparencyGradient(90, { { 0, 1 }, { 0.55, 0.7 }, { 1, 0.35 } }),
	})
	-- Light spilling under the pad
	local under = ellipse(stage, "Under", CENTER_X, PAD_Y + PAD_DEPTH + 8, 2 * PAD_A + 70, 2 * PAD_B + 30, 4, solid(NEUTRAL_GLOW, 1))

	local pad = buildPad(stage)

	-- Dust puffs where the egg lands
	local dust = {}
	if egg then
		for side = -1, 1, 2 do
			for puffIndex = 1, 2 do
				local size = if puffIndex == 1 then 30 else 20
				table.insert(dust, {
					Frame = box({
						Name = "Dust",
						BackgroundColor3 = Theme.Cloud,
						BackgroundTransparency = 1,
						Size = UDim2.fromOffset(size, size),
						AnchorPoint = Vector2.new(0.5, 0.5),
						ZIndex = 6,
						Visible = false,
						Parent = stage,
						UI.Round(),
						UI.Stroke(2, Theme.HazeDeep),
					}),
					Side = side,
					Reach = if puffIndex == 1 then 62 else 92,
					Size = size,
				})
			end
		end
	end

	-- The egg (3D) with its cracks and heat glow drawn over it, or the ball of light (no egg)
	local eggHolder = box({
		Name = "EggHolder",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(EGG_VIEW, EGG_VIEW),
		Position = UDim2.fromOffset(CENTER_X, EGG_Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 7,
		Visible = false,
		Parent = stage,
	})
	local eggScale = scaler(eggHolder)
	local eggView, cracks, crackSegments, heat, orb = nil, nil, {}, {}, {}
	if egg then
		eggView = Viewport.Egg(eggId, {
			Name = "Egg",
			Size = UDim2.fromScale(1, 1),
			Zoom = EGG_ZOOM,
			ZIndex = 1,
			Parent = eggHolder,
		})
		-- Centred on the egg's bottom, so it turns with the egg's rocking
		cracks = box({
			Name = "Cracks",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(EGG_VIEW, EGG_VIEW),
			Position = UDim2.new(0.5, 0, 0.5, EGG_HEIGHT / 2),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 2,
			Parent = eggHolder,
		})
		for crackIndex, crack in CRACKS do
			local points = crack[2]
			for pointIndex = 1, #points - 1 do
				local a, b = points[pointIndex], points[pointIndex + 1]
				local ax, ay = a[1] * EGG_WIDTH / 2, a[2] * EGG_HEIGHT / 2 - EGG_HEIGHT / 2
				local bx, by = b[1] * EGG_WIDTH / 2, b[2] * EGG_HEIGHT / 2 - EGG_HEIGHT / 2
				local length = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
				local thickness = if crack[1] == 3 then 5 else 4
				local segment = box({
					Name = "Crack",
					BackgroundColor3 = INK,
					Size = UDim2.fromOffset(length + thickness, thickness),
					Position = UDim2.new(0.5, (ax + bx) / 2, 0.5, (ay + by) / 2),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Rotation = math.deg(math.atan2(by - ay, bx - ax)),
					ZIndex = 1,
					Visible = false,
					Parent = cracks,
					UI.Round(),
				})
				-- light leaking out of the crack
				local core = box({
					Name = "Light",
					BackgroundColor3 = WHITE,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -3, 0, 2),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					ZIndex = 2,
					Parent = segment,
					UI.Round(),
				})
				table.insert(crackSegments, {
					Frame = segment,
					Core = core,
					Stage = crack[1],
					Length = length + thickness,
					Thickness = thickness,
					Delay = (pointIndex - 1) * 0.025 + (crackIndex % 3) * 0.01,
				})
			end
		end
		-- White heat over the egg just before it pops
		heat = ellipse(eggHolder, "Heat", EGG_VIEW / 2, EGG_VIEW / 2 + 4, EGG_WIDTH * 0.92, EGG_HEIGHT * 0.94, 3, solid(WHITE, 1))
	else
		for orbIndex, spec in { { 1, 0.16 }, { 0.72, 0.2 }, { 0.48, 0.32 }, { 0.3, 0.9 } } do
			table.insert(orb, {
				Frame = box({
					Name = "Orb" .. orbIndex,
					BackgroundColor3 = if orbIndex == 4 then WHITE else NEUTRAL_GLOW,
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(0, 0),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					ZIndex = orbIndex,
					Parent = eggHolder,
					UI.Round(),
				}),
				Size = spec[1],
				Alpha = spec[2],
			})
		end
	end

	-- The pet (built now, so nothing has to be built at the moment it pops out)
	local petHolder = box({
		Name = "PetHolder",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(PET_VIEW, PET_VIEW),
		Position = UDim2.fromOffset(CENTER_X, PET_Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 8,
		Visible = false,
		Parent = stage,
	})
	local petScale = scaler(petHolder, 0)
	local petView = Viewport.Pet(entry.Id, tier, {
		Name = "Pet",
		Size = UDim2.fromScale(1, 1),
		Zoom = 1.25,
		ZIndex = 1,
		Parent = petHolder,
	})

	-- Burst: flash, shockwave rings, shell shards, sparkles
	local flash = {}
	for flashIndex, spec in { { 1, 0.3 }, { 0.74, 0.42 }, { 0.5, 0.7 }, { 0.3, 0.95 } } do
		table.insert(flash, {
			Frame = box({
				Name = "Flash" .. flashIndex,
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(CENTER_X, EGG_Y),
				AnchorPoint = Vector2.new(0.5, 0.5),
				ZIndex = 1,
				Visible = false,
				Parent = fx,
				UI.Round(),
			}),
			Size = spec[1],
			Alpha = spec[2],
		})
	end
	local rings = {}
	for ringIndex = 1, 2 do
		local ringFrame = box({
			Name = "Ring" .. ringIndex,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(CENTER_X, EGG_Y),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 2,
			Visible = false,
			Parent = fx,
			UI.Round(),
		})
		local stroke = UI.Stroke(10, WHITE)
		stroke.Parent = ringFrame
		table.insert(rings, { Frame = ringFrame, Stroke = stroke })
	end
	local shards = {}
	if egg then
		local shellTop = egg.Color:Lerp(WHITE, 0.25)
		for shardIndex = 1, 14 do
			local w, h = rng:NextNumber(14, 30), rng:NextNumber(10, 20)
			local shard = box({
				Name = "Shard",
				Size = UDim2.fromOffset(w, h),
				AnchorPoint = Vector2.new(0.5, 0.5),
				ZIndex = 3,
				Visible = false,
				Parent = fx,
				UI.Corner(4),
				UI.Gradient(shellTop, egg.Color),
			})
			local stroke = UI.Stroke(2, INK)
			stroke.Parent = shard
			local spot = nil
			if shardIndex % 3 == 0 then
				spot = box({
					Name = "Spot",
					BackgroundColor3 = egg.Accent,
					Size = UDim2.fromOffset(h * 0.5, h * 0.5),
					Position = UDim2.fromScale(0.55, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					ZIndex = 3,
					Parent = shard,
					UI.Round(),
				})
			end
			-- Thrown up and out, a bit more to the sides than straight up
			local angle = math.rad(rng:NextNumber(-170, -10))
			local speed = rng:NextNumber(330, 640)
			table.insert(shards, {
				Frame = shard,
				Stroke = stroke,
				Spot = spot,
				X = rng:NextNumber(-EGG_WIDTH * 0.3, EGG_WIDTH * 0.3),
				Y = rng:NextNumber(-EGG_HEIGHT * 0.25, EGG_HEIGHT * 0.2),
				VX = math.cos(angle) * speed,
				VY = math.sin(angle) * speed,
				Spin = rng:NextNumber(-720, 720),
				Angle = rng:NextNumber(0, 360),
				Life = rng:NextNumber(0.75, 1.05),
			})
		end
	end
	local sparkles = {}
	for sparkleIndex = 1, 10 do
		local angle = (sparkleIndex - 1) / 10 * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		table.insert(sparkles, {
			Frame = sparkle(fx, rng:NextNumber(18, 30), if sparkleIndex % 3 == 0 then Theme.Sets.Bolt.Top else WHITE, 4),
			Angle = angle,
			Reach = rng:NextNumber(110, 175),
			Spin = rng:NextNumber(-200, 200),
			Delay = rng:NextNumber(0, 0.08),
		})
	end
	-- Twinkling stars around the pet
	local stars = {}
	for starIndex, spec in { { -118, -62, 34 }, { 116, -84, 28 }, { -128, 46, 24 }, { 126, 30, 32 }, { -64, -118, 22 }, { 70, -126, 26 } } do
		local holder = Icons.New("Star", {
			Name = "Star" .. starIndex,
			Size = UDim2.fromOffset(spec[3], spec[3]),
			Position = UDim2.fromOffset(CENTER_X + spec[1], PET_Y + spec[2]),
			ZIndex = 5,
			Visible = false,
			Parent = fx,
		})
		table.insert(stars, { Frame = holder, Size = spec[3], Phase = starIndex * 1.7, Speed = 2.6 + (starIndex % 3) * 0.7 })
	end

	local card = buildCard(frame, entry, def, rarity, tier)

	return {
		Entry = entry,
		Rarity = rarity,
		Tier = tier,
		Color = rarity.Color,
		Rainbow = rarity.Order >= 6 or tier == "Rainbow",
		Frame = frame,
		Scale = scaler(frame),
		Rays = rays,
		Glow = glow,
		Beam = beam,
		Under = under,
		Pad = pad,
		Dust = dust,
		EggHolder = eggHolder,
		EggScale = eggScale,
		Egg = eggView,
		Cracks = cracks,
		CrackSegments = crackSegments,
		Heat = heat,
		HeatLevel = -1,
		Orb = orb,
		PetHolder = petHolder,
		PetScale = petScale,
		Pet = petView,
		Flash = flash,
		Rings = rings,
		Shards = shards,
		Sparkles = sparkles,
		Stars = stars,
		Card = card,
	}
end

-- "LEGENDARY!" stamp for the best pet (Epic and better)
local function buildStamp(parent: Instance, rarity)
	local colors = Theme.Rarity(rarity.Color)
	local text = string.upper(rarity.Name) .. "!"
	local holder = box({
		Name = "Stamp",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(560, 92),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = -6,
		ZIndex = 5,
		Visible = false,
		Parent = parent,
	})
	local scale = scaler(holder)
	-- the Ink copy a few px lower gives the letters depth
	UI.Text({
		Name = "Depth",
		Text = text,
		TextSize = 64,
		Color = INK,
		Stroke = INK,
		StrokeThickness = 6,
		Position = UDim2.fromOffset(0, 6),
		ZIndex = 1,
		Parent = holder,
	})
	local label = UI.Text({
		Name = "Text",
		Text = text,
		TextSize = 64,
		Color = WHITE,
		Stroke = INK,
		StrokeThickness = 6,
		ZIndex = 2,
		Parent = holder,
	})
	if rarity.Order >= 6 then
		UI.Create("UIGradient", { Color = PetModels.RainbowSequence, Parent = label })
	else
		UI.Gradient(colors.Top:Lerp(WHITE, 0.35), colors.Bottom).Parent = label
	end
	local sparkles = {}
	for index, spec in { { -250, -34, 34 }, { 262, -26, 40 }, { -214, 40, 24 }, { 228, 44, 28 } } do
		local star = sparkle(holder, spec[3], if index % 2 == 0 then Theme.Sets.Bolt.Top else WHITE, 3)
		star.Position = UDim2.new(0.5, spec[1], 0.5, spec[2])
		table.insert(sparkles, star)
	end
	return { Frame = holder, Scale = scale, Sparkles = sparkles }
end

local function buildConfetti(parent: Instance, screenWidth: number, rng: Random)
	local pieces = {}
	for index = 1, 56 do
		local square = index % 3 == 0
		local piece = box({
			Name = "Confetti",
			BackgroundColor3 = CONFETTI_COLORS[(index - 1) % #CONFETTI_COLORS + 1],
			Size = if square then UDim2.fromOffset(11, 11) else UDim2.fromOffset(9, 18),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 1,
			Visible = false,
			Parent = parent,
			UI.Corner(3),
		})
		table.insert(pieces, {
			Frame = piece,
			X = rng:NextNumber(0.03, 0.97) * screenWidth,
			Y = rng:NextNumber(-260, -20),
			VY = rng:NextNumber(60, 220),
			Sway = rng:NextNumber(14, 40),
			SwaySpeed = rng:NextNumber(3, 6),
			Spin = rng:NextNumber(-400, 400),
			Delay = rng:NextNumber(0, 0.35),
			Phase = rng:NextNumber(0, math.pi * 2),
		})
	end
	return pieces
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function rainbow(clock: number): Color3
	return Color3.fromHSV((clock * 0.45) % 1, 0.5, 1)
end

local function setVisible(object: GuiObject, visible: boolean)
	if object.Visible ~= visible then
		object.Visible = visible
	end
end

-- Draws one slot at its own time u (the play's clock minus the slot's stagger)
local function drawSlot(slot, T, u: number, clock: number, crackTimes)
	local popped = u >= T.Pop
	local revealColor = if slot.Rainbow then rainbow(clock) else slot.Color
	local glowK, colorK, lightSpeed = 0, 0, 1.2
	local padShadow, padShadowAlpha = 1, 0

	-- The pad pops up
	local padK = progress(u, T.Pad, 0.38)
	setVisible(slot.Pad.Frame, padK > 0)
	slot.Pad.Scale.Scale = math.max(outBack(padK, 2.2), 0.001)
	glowK = 0.25 * padK

	-- Egg: drop, land, three wobbles with cracks, puff
	local egg = slot.Egg
	if egg and not popped then
		local dropK = progress(u, T.Drop, T.Land - T.Drop)
		local y = -300 * (1 - dropK * dropK)
		local roll, sx, sy, heat = 0, 1, 1, 0
		local landed = u - T.Land
		if landed >= 0 then
			local e = math.exp(-8 * landed)
			sy = 1 - 0.26 * e * math.cos(landed * math.pi * 6)
			sx = 1 + (1 - sy) * 0.6
		end
		local stage, pulse = 0, 0
		for index, tick in T.Ticks do
			local k = (u - tick[1]) / tick[2]
			if k >= 0 then
				if k <= 1 then
					local envelope = math.sin(k * math.pi)
					roll = math.rad(tick[3]) * math.sin(k * math.pi * 5) * envelope
					sy *= 1 + 0.05 * envelope
					sx *= 1 - 0.03 * envelope
					if index == #T.Ticks then
						y -= 14 * envelope
					end
				end
				if k >= 0.3 then
					stage = math.floor(index * 3 / #T.Ticks)
				end
				pulse = math.max(pulse, math.exp(-4 * (u - tick[1])))
			end
		end
		local lastTick = T.Ticks[#T.Ticks]
		colorK = progress(u, lastTick[1], lastTick[2] * 0.6)
		heat = 0.06 * stage + 0.22 * pulse
		local puffK = progress(u, T.Puff, T.Pop - T.Puff)
		if puffK > 0 then
			roll += math.rad(3.5) * math.sin(u * 95) * puffK
			heat = lerp(heat, 0.95, puffK)
			sy *= 1 + 0.05 * puffK
		end
		glowK = 0.25 + 0.14 * stage + 0.3 * pulse + 0.55 * puffK
		lightSpeed = 1.2 + stage * 0.8 + puffK * 3

		setVisible(slot.EggHolder, dropK > 0)
		slot.EggHolder.Position = UDim2.fromOffset(CENTER_X, EGG_Y + y)
		slot.EggScale.Scale = 1 + 0.2 * outQuad(puffK)
		egg.Frame.ImageTransparency = 1 - clamp01(dropK * 5)
		egg.SetShape(roll, sx, sy, 0)
		if math.abs(heat - slot.HeatLevel) > 0.01 then
			slot.HeatLevel = heat
			egg.SetGlow(heat)
		end
		slot.Cracks.Rotation = math.deg(roll)
		local leak = colorK * (0.45 + 0.3 * pulse) + puffK
		for _, crack in slot.CrackSegments do
			local k = if stage >= crack.Stage then progress(u, crackTimes[crack.Stage] + crack.Delay, 0.06) else 0
			setVisible(crack.Frame, k > 0)
			if k > 0 then
				crack.Frame.Size = UDim2.fromOffset(crack.Length * k, crack.Thickness)
				crack.Core.BackgroundColor3 = revealColor:Lerp(WHITE, 0.35 + 0.5 * puffK)
				crack.Core.BackgroundTransparency = 1 - clamp01(leak)
			end
		end
		for _, layer in slot.Heat do
			layer.BackgroundTransparency = 1 - 0.28 * puffK
		end
		-- Dust puffs when it lands
		for _, puff in slot.Dust do
			local k = progress(landed, 0, 0.45)
			setVisible(puff.Frame, landed >= 0 and k < 1)
			if landed >= 0 and k < 1 then
				local size = puff.Size * (0.6 + 0.7 * outQuad(k))
				puff.Frame.Size = UDim2.fromOffset(size, size)
				puff.Frame.Position = UDim2.fromOffset(CENTER_X + puff.Side * puff.Reach * outCubic(k), PAD_Y + 2 - 16 * outQuad(k))
				puff.Frame.BackgroundTransparency = lerp(0.05, 1, k)
				puff.Frame:FindFirstChildOfClass("UIStroke").Transparency = lerp(0.2, 1, k)
			end
		end
		-- the shadow grows as the egg comes down
		padShadow = lerp(0.35, 1, dropK * dropK)
		padShadowAlpha = dropK
	elseif not egg and not popped then
		-- No egg: a ball of light gathers on the pad
		local chargeK = progress(u, T.Charge, T.Pop - T.Charge)
		setVisible(slot.EggHolder, chargeK > 0)
		local throb = 1 + 0.08 * math.sin(u * (14 + 20 * chargeK))
		for _, layer in slot.Orb do
			local size = (40 + 170 * outQuad(chargeK)) * layer.Size * throb
			layer.Frame.Size = UDim2.fromOffset(size, size)
			layer.Frame.BackgroundTransparency = 1 - layer.Alpha * clamp01(chargeK * 3)
			if layer.Frame.Name ~= "Orb4" then
				layer.Frame.BackgroundColor3 = NEUTRAL_GLOW:Lerp(revealColor, chargeK)
			end
		end
		glowK = 0.25 + 0.75 * chargeK
		colorK = chargeK
		lightSpeed = 1.2 + 4 * chargeK
		padShadow, padShadowAlpha = 0.6 + 0.4 * chargeK, chargeK * 0.6
	end

	-- Burst and reveal
	local tau = u - T.Pop
	setVisible(slot.PetHolder, popped)
	if popped then
		setVisible(slot.EggHolder, false)
		colorK = 1
		glowK = 0.9 + 0.5 * math.exp(-5 * tau)
		lightSpeed = 1.5
		-- the pet pops out with an elastic overshoot, then hovers and turns slowly
		local petK = progress(tau, 0.02, 0.8)
		slot.PetScale.Scale = math.max(outElastic(petK), 0.001)
		slot.Pet.Frame.ImageTransparency = 1 - clamp01(tau / 0.08)
		slot.PetHolder.Position = UDim2.fromOffset(CENTER_X, PET_Y + math.sin(tau * 2.4) * 4)
		slot.Pet.SetRotation(math.rad(20) + math.sin(tau * 1.25) * 0.5)
		padShadow = 1.15 + 0.05 * math.sin(tau * 2.4)
		padShadowAlpha = 0.8

		local flashK = progress(tau, 0, 0.42)
		for _, layer in slot.Flash do
			setVisible(layer.Frame, flashK < 1)
			if flashK < 1 then
				local size = lerp(120, 430, outCubic(flashK)) * layer.Size
				layer.Frame.Size = UDim2.fromOffset(size, size)
				layer.Frame.BackgroundTransparency = lerp(1 - layer.Alpha, 1, outQuad(flashK))
				layer.Frame.BackgroundColor3 = WHITE:Lerp(revealColor, 0.25 * (1 - layer.Size))
			end
		end
		for index, ring in slot.Rings do
			local k = progress(tau, (index - 1) * 0.08, 0.5)
			setVisible(ring.Frame, k > 0 and k < 1)
			if k > 0 and k < 1 then
				local size = lerp(110, 540, outCubic(k))
				ring.Frame.Size = UDim2.fromOffset(size, size)
				ring.Stroke.Thickness = lerp(14, 2, k)
				ring.Stroke.Transparency = k * k
				ring.Stroke.Color = if index == 1 then WHITE else revealColor
			end
		end
		for _, shard in slot.Shards do
			local visible = tau < shard.Life
			setVisible(shard.Frame, visible)
			if visible then
				local x = shard.X + shard.VX * tau
				local y = shard.Y + shard.VY * tau + 0.5 * GRAVITY * tau * tau
				shard.Frame.Position = UDim2.fromOffset(CENTER_X + x, EGG_Y + y)
				shard.Frame.Rotation = shard.Angle + shard.Spin * tau
				local fade = progress(tau, shard.Life - 0.25, 0.25)
				shard.Frame.BackgroundTransparency = fade
				shard.Stroke.Transparency = fade
				if shard.Spot then
					shard.Spot.BackgroundTransparency = fade
				end
			end
		end
		for _, star in slot.Sparkles do
			local k = progress(tau, star.Delay, 0.7)
			setVisible(star.Frame, k > 0 and k < 1)
			if k > 0 and k < 1 then
				local reach = star.Reach * outCubic(k)
				star.Frame.Position = UDim2.fromOffset(CENTER_X + math.cos(star.Angle) * reach, EGG_Y + math.sin(star.Angle) * reach)
				star.Frame.Rotation = star.Spin * k
				local size = math.sin(k * math.pi)
				local scale = star.Frame:FindFirstChildOfClass("UIScale") or scaler(star.Frame)
				scale.Scale = math.max(size, 0.001)
			end
		end
		for _, star in slot.Stars do
			local wave = math.sin((tau - 0.3) * star.Speed + star.Phase)
			local k = if tau > 0.3 then clamp01(wave) ^ 1.5 * clamp01((tau - 0.3) * 3) else 0
			setVisible(star.Frame, k > 0.03)
			if k > 0.03 then
				local size = star.Size * (0.4 + 0.6 * k)
				star.Frame.Size = UDim2.fromOffset(size, size)
				star.Frame.Rotation = (tau * 40 + star.Phase * 30) % 360
			end
		end
		-- The name card slides up, then the NEW tag pops on
		local cardK = progress(tau, 0.2, 0.42)
		setVisible(slot.Card.Frame, cardK > 0)
		slot.Card.Scale.Scale = lerp(0.6, 1, outBack(cardK, 1.8))
		slot.Card.Frame.Position = UDim2.fromOffset(CENTER_X, CARD_TOP + 14 + 46 * (1 - outCubic(cardK)))
		if slot.Card.New then
			slot.Card.NewScale.Scale = math.max(outBack(progress(tau, 0.55, 0.3), 3), 0.001)
		end
	end

	-- Light: rays, glow, beam, the pad's ring and lights
	local glowColor = NEUTRAL_GLOW:Lerp(revealColor, colorK)
	local rayAlpha = if popped then lerp(0.25, 0.62, clamp01(tau * 3)) else 0.3 * clamp01(glowK)
	local spin = clock * (if popped then 22 else 9)
	for _, ray in slot.Rays do
		ray.Frame.Rotation = ray.Base + spin
		ray.Frame.BackgroundColor3 = glowColor
		ray.Frame.BackgroundTransparency = 1 - rayAlpha
		local length = ray.Length * (if popped then lerp(0.7, 1.08, outBack(clamp01(tau * 2.5))) else 0.75)
		ray.Frame.Size = UDim2.fromOffset(ray.Frame.Size.X.Offset, length)
	end
	for _, layer in slot.Glow do
		layer.Frame.BackgroundColor3 = glowColor
		layer.Frame.BackgroundTransparency = 1 - math.min(layer.Alpha * glowK, 0.95)
	end
	slot.Beam.BackgroundColor3 = glowColor
	slot.Beam.BackgroundTransparency = 1 - clamp01(0.55 * glowK) * padK
	for _, layer in slot.Under do
		layer.BackgroundColor3 = glowColor
		layer.BackgroundTransparency = 1 - 0.09 * clamp01(glowK) * padK
	end
	local ringColor = Theme.Haze:Lerp(glowColor, clamp01(0.45 + glowK * 0.6))
	for _, layer in slot.Pad.Ring do
		layer.BackgroundColor3 = ringColor
	end
	for index, light in slot.Pad.Lights do
		local phase = (clock * lightSpeed - index * 0.2) % 1
		light.BackgroundTransparency = if phase < 0.5 then 0 else 0.55
	end
	setVisible(slot.Pad.Shadow, padShadowAlpha > 0.02)
	slot.Pad.ShadowScale.Scale = math.max(padShadow, 0.001)
	for _, layer in slot.Pad.Shadow:GetChildren() do
		if layer:IsA("Frame") then
			layer.BackgroundTransparency = 1 - 0.22 * padShadowAlpha
		end
	end
	return glowColor, glowK, colorK
end

---------------------------------------------------------------------------
-- One play
---------------------------------------------------------------------------
local function runPlay(play, result, options)
	local results = result.Results or {}
	if #results == 0 then
		return
	end
	local interface = Registry.InterfaceController
	local sounds = Registry.SoundController
	local eggId = if result.Egg and Pets.Eggs[result.Egg] then result.Egg else nil
	local quick = options.Quick == true or (eggId ~= nil and options.Hold ~= nil and options.Hold < 1.5)
	local T = if not eggId then REVEAL elseif quick then QUICK else NORMAL
	local count = #results

	local s = openSession()
	local startLevel = s.Level
	local warm = startLevel > 0.9 -- the backdrop is already up (back-to-back hatches)

	-- Layout: the title and the slots are centred in the space below the Roblox top bar (and above
	-- the hint / the Stop Auto Hatch button), scaled down to fit the screen: side by side, or in a
	-- column on portrait phones when that shows them bigger
	local root = interface.OverlayRoot
	local overlayScale = interface.OverlayScale
	local safeTop = interface.SafeTop
	local screenWidth, screenHeight = 1280, 720
	if root.AbsoluteSize.X > 0 and root.AbsoluteSize.Y > 0 then
		screenWidth, screenHeight = root.AbsoluteSize.X / overlayScale, root.AbsoluteSize.Y / overlayScale
	end
	local bottomSpace = if quick then 112 else 54
	local availableHeight = screenHeight - safeTop - bottomSpace
	local function fit(columns: number, rows: number)
		local width = columns * SLOT_WIDTH + (columns - 1) * SLOT_GAP
		local height = rows * SLOT_HEIGHT + (rows - 1) * SLOT_GAP
		return math.min(1, (screenWidth - 24) / width, (availableHeight - RIBBON_HEIGHT - 12) / height), width, height
	end
	local k, rowWidth, rowHeight = fit(count, 1)
	local vertical = false
	local kColumn, columnWidth, columnHeight = fit(1, count)
	if count > 1 and kColumn > k + 0.05 then
		vertical = true
		k, rowWidth, rowHeight = kColumn, columnWidth, columnHeight
	end
	k = math.max(k, 0.3)
	local groupHeight = RIBBON_HEIGHT + 4 + rowHeight * k
	local groupTop = safeTop + math.max((availableHeight - groupHeight) / 2, 4)
	local ribbonY = groupTop + RIBBON_HEIGHT / 2
	local rowTop = groupTop + RIBBON_HEIGHT + 4

	local frame = box({ Name = "Play", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = s.Root })
	play.Frame = frame
	local shake = box({ Name = "Shake", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = frame })

	local title = options.Title or (eggId and Pets.Eggs[eggId].Name) or "NEW PET!"
	local ribbon = buildRibbon(shake, title, options.Ribbon or (if eggId then "Sky" else "Pink"), count, screenWidth)
	ribbon.Frame.Position = UDim2.fromOffset(screenWidth / 2, ribbonY)
	ribbon.Frame.Visible = false

	local row = box({
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(rowWidth, rowHeight),
		Position = UDim2.fromOffset(screenWidth / 2, rowTop + rowHeight * k / 2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 3,
		Parent = shake,
		UI.List(
			if vertical then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal,
			SLOT_GAP,
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Center
		),
	})
	local rowScale = scaler(row, k)

	local rng = Random.new(os.clock() * 1000)
	local slots = {}
	local best = nil
	for index, entry in results do
		local slot = buildSlot(row, index, entry, eggId, count > 1, rng)
		slot.Delay = (index - 1) * T.Stagger
		slots[index] = slot
		if not best or slot.Rarity.Order > best.Rarity.Order then
			best = slot
		end
	end
	local bestOrder = best.Rarity.Order
	local lastPop = T.Pop + (count - 1) * T.Stagger
	local bestPop = T.Pop + best.Delay

	-- The soft light behind the stage
	local poolCenter = Vector2.new(screenWidth / 2, rowTop + (if vertical then rowHeight * k / 2 else (GLOW_Y + 30) * k))
	local poolSize = if vertical
		then Vector2.new(SLOT_WIDTH * k + 520, rowHeight * k + 260)
		else Vector2.new(rowWidth * k + 460, 560 * k + 120)
	for index, layer in s.Pool do
		local factor = 1 - (index - 1) * 0.2
		layer.Size = UDim2.fromOffset(poolSize.X * factor, poolSize.Y * factor)
		layer.Position = UDim2.fromOffset(poolCenter.X, poolCenter.Y)
	end

	-- Epic and better: the stamp over the ribbon and confetti
	local stamp, confetti = nil, nil
	if bestOrder >= 4 then
		stamp = buildStamp(shake, best.Rarity)
		stamp.Frame.Position = UDim2.fromOffset(screenWidth / 2, ribbonY + 6)
		local stampScale = math.min(1, (screenWidth - 24) / 600)
		stamp.Scale.Scale = stampScale
		stamp.BaseScale = stampScale
		confetti = buildConfetti(box({ Name = "Confetti", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = frame }), screenWidth, rng)
	end
	local stampTime = bestPop + 0.32

	-- "Tap to skip" / "Tap to continue"
	local verb = if touchScreen() then "Tap" else "Click"
	local hint = UI.Text({
		Name = "Hint",
		Text = verb .. " to skip",
		TextSize = 24,
		Stroke = INK,
		StrokeThickness = 3,
		Size = UDim2.fromOffset(420, 32),
		Position = UDim2.new(0.5, 0, 1, -16),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = 3,
		Visible = false,
		Parent = frame,
	})
	local hintStroke = hint:FindFirstChildOfClass("UIStroke")
	local hintScale = scaler(hint)

	-- When the cracks of each stage appear (a stage the quick timeline skips shows with the next one)
	local crackTimes = {}
	if eggId then
		for index, tick in T.Ticks do
			local stage = math.floor(index * 3 / #T.Ticks)
			local at = tick[1] + tick[2] * 0.3
			for fill = stage, 1, -1 do
				if crackTimes[fill] then
					break
				end
				crackTimes[fill] = at
			end
		end
	end

	-- Sounds and one-off moments, in time order
	local events = {}
	local function at(time: number, always: boolean, fn)
		table.insert(events, { Time = time, Always = always, Fn = fn })
	end
	for index, slot in slots do
		if eggId then
			at(T.Land + slot.Delay, false, function()
				sounds.Play("Pop", 0.7, if index == 1 then 0.8 else 0.5)
			end)
		end
		at(T.Pop + slot.Delay, true, function()
			sounds.Play("Hatch", 1 + (index - 1) * 0.06, if index == 1 then 1 else 0.6)
		end)
	end
	if eggId then
		for index, tick in T.Ticks do
			local step = (index - 1) / math.max(#T.Ticks - 1, 1)
			at(tick[1], false, function()
				sounds.Play("Pop", 1 + step * 0.32, 0.55 + step * 0.45)
			end)
		end
	else
		at(T.Charge, false, function()
			sounds.Play("Pop", 0.8, 0.7)
		end)
	end
	at(bestPop + 0.12, true, function()
		sounds.Play("Success", 0.9 + bestOrder * 0.06)
	end)
	if stamp then
		at(stampTime + 0.16, true, function()
			sounds.Play("Thunder", 1.1, 1.4)
		end)
	end
	table.sort(events, function(a, b)
		return a.Time < b.Time
	end)
	local nextEvent = 1

	-- Input: a tap skips to the burst, then (after a moment) closes the reveal
	local clock = 0
	local outroStart = nil
	local dismissed = false
	local skipTo = if eggId then T.Puff - 0.02 else T.Pop - 0.12
	local function tap()
		if outroStart then
			return
		end
		if clock < skipTo and not quick then
			clock = skipTo
		elseif clock >= lastPop + T.MinHold then
			dismissed = true
		end
	end
	play.Connections = {
		s.Root.Activated:Connect(tap),
		UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and (input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.ButtonA) then
				tap()
			end
		end),
	}

	local hold = options.Hold or (if bestOrder >= 5 then T.Hold + 1.4 elseif bestOrder >= 4 then T.Hold + 0.8 else T.Hold)
	local closing = waiting == 0 and not quick -- the backdrop goes with this play (else it lingers)
	local outroLevel, outroFade = 1, nil
	local shakeStarts = {}
	for _, slot in slots do
		table.insert(shakeStarts, { T.Pop + slot.Delay, 5 })
	end
	if stamp then
		table.insert(shakeStarts, { stampTime + 0.16, 14 })
	end

	-- The loop: everything below is a function of `clock`
	while true do
		local dt = RunService.RenderStepped:Wait()
		clock += math.min(dt, 1 / 20)
		if options.FreezeAt then
			clock = math.min(clock, options.FreezeAt)
		end
		if play.Aborted and not outroStart then
			outroStart = clock
		end
		if not outroStart and (dismissed or clock >= lastPop + hold) then
			outroStart = clock
		end

		-- Sounds and moments (ones jumped over by a skip stay quiet)
		while events[nextEvent] and clock >= events[nextEvent].Time do
			local event = events[nextEvent]
			nextEvent += 1
			if event.Always or clock - event.Time < 0.15 then
				event.Fn()
			end
		end

		-- Backdrop
		local outroK = if outroStart then progress(clock, outroStart, if play.Aborted then 0.1 else T.Outro) else 0
		if outroStart then
			if closing or play.Aborted then
				setLevel(s, outroLevel * (1 - outQuad(outroK)))
			end
		else
			local level = math.max(startLevel, outQuad(progress(clock, 0, T.Intro)))
			setLevel(s, level)
			outroLevel = level
		end

		-- Ribbon drops in with a bounce, then the count chip pops on
		local ribbonK = if warm and quick then 1 else progress(clock, T.Ribbon, T.RibbonTime)
		setVisible(ribbon.Frame, ribbonK > 0)
		ribbon.Frame.Position = UDim2.fromOffset(screenWidth / 2, ribbonY - 170 * (1 - outBack(ribbonK, 2.2)))
		ribbon.Frame.Rotation = 5 * math.sin(ribbonK * math.pi * 2) * (1 - ribbonK)
		for index, star in ribbon.Stars do
			star.Rotation = (clock * 50 * (if index == 1 then -1 else 1)) % 360
		end
		if ribbon.ChipScale then
			ribbon.ChipScale.Scale = math.max(outBack(progress(clock, T.Ribbon + T.RibbonTime * 0.7, 0.3), 3), 0.001)
		end

		-- Slots
		local poolColor, poolK = POOL_COLOR, 0
		if not outroStart then
			for _, slot in slots do
				local glowColor, glowK, colorK = drawSlot(slot, T, clock - slot.Delay, clock, crackTimes)
				if slot == best then
					poolColor = POOL_COLOR:Lerp(glowColor, 0.55 * colorK)
					poolK = glowK
				end
			end
			play.PoolColor, play.PoolK = poolColor, poolK
		else
			poolColor, poolK = play.PoolColor or POOL_COLOR, play.PoolK or 0
		end
		for index, layer in s.Pool do
			layer.BackgroundColor3 = poolColor
			layer.BackgroundTransparency = 1 - (0.07 + 0.03 * index) * s.Level * clamp01(0.6 + 0.4 * poolK)
		end

		-- Stamp slams down: big -> a hair too small -> settles
		if stamp then
			local slamK = progress(clock, stampTime, 0.16)
			setVisible(stamp.Frame, slamK > 0)
			if slamK > 0 then
				local settle = progress(clock, stampTime + 0.16, 0.3)
				local size = if slamK < 1 then lerp(2.6, 0.9, inQuad(slamK)) else lerp(0.9, 1, outBack(settle, 3))
				stamp.Scale.Scale = size * stamp.BaseScale
				for index, star in stamp.Sparkles do
					local twinkle = math.sin(clock * 5 + index * 1.9)
					setVisible(star, settle > 0 and twinkle > 0)
					local starScale = star:FindFirstChildOfClass("UIScale") or scaler(star)
					starScale.Scale = math.max(twinkle, 0.001)
					star.Rotation = clock * 60
				end
			end
		end
		if confetti then
			for _, piece in confetti do
				local life = clock - stampTime - 0.16 - piece.Delay
				local y = piece.Y + piece.VY * life + 0.5 * GRAVITY * 0.18 * life * life
				local visible = life > 0 and y < screenHeight + 30
				setVisible(piece.Frame, visible)
				if visible then
					piece.Frame.Position = UDim2.fromOffset(piece.X + math.sin(life * piece.SwaySpeed + piece.Phase) * piece.Sway, y)
					piece.Frame.Rotation = piece.Spin * life
				end
			end
		end

		-- Screen shake (a nudge at each pop, a big one under the stamp)
		local offsetX, offsetY = 0, 0
		for _, entry in shakeStarts do
			local since = clock - entry[1]
			if since >= 0 and since < 0.5 then
				local amplitude = entry[2] * math.exp(-7 * since)
				offsetX += amplitude * math.sin(since * 83)
				offsetY += amplitude * math.cos(since * 71)
			end
		end
		shake.Position = UDim2.fromOffset(offsetX, offsetY)

		-- Hint
		local hintText = nil
		if not quick and not outroStart then
			if clock < skipTo and clock > T.Intro + 0.3 then
				hintText = verb .. " to skip"
			elseif clock >= lastPop + T.MinHold then
				hintText = verb .. " to continue"
			end
		end
		setVisible(hint, hintText ~= nil)
		if hintText then
			hint.Text = hintText
			local pulse = 0.5 + 0.5 * math.sin(clock * 4.2)
			hint.TextTransparency = 0.05 + 0.3 * pulse
			hintStroke.Transparency = 0.2 + 0.35 * pulse
			hintScale.Scale = 1 + 0.04 * (1 - pulse)
		end

		-- Outro: everything shrinks a little and fades
		if outroStart then
			if not outroFade then
				outroFade = fadeTargets(frame)
				if bestOrder >= 4 and not play.Aborted then
					Registry.EffectsController.Confetti(40 + bestOrder * 15) -- keeps celebrating in the world
				end
			end
			local fade = outQuad(outroK)
			for _, target in outroFade do
				target[1][target[2]] = lerp(target[3], 1, fade)
			end
			rowScale.Scale = k * (1 - 0.14 * fade)
			ribbon.Scale.Scale = 1 - 0.14 * fade
			if outroK >= 1 then
				break
			end
		end
	end
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
function Hatch.IsPlaying(): boolean
	return playing
end

function Hatch.Play(result, options)
	options = options or {}
	waiting += 1
	while playing do
		task.wait(0.05)
	end
	waiting -= 1
	playing = true

	local play = { Aborted = false }
	current = play
	local ok, err = xpcall(runPlay, debug.traceback, play, result or {}, options)
	if not ok then
		warn("[Hatch] the hatch animation failed: " .. tostring(err))
	end

	-- Cleanup runs on every way out
	for _, connection in play.Connections or {} do
		connection:Disconnect()
	end
	if play.Frame then
		play.Frame:Destroy()
	end
	current = nil
	local s = session
	if s then
		if not ok or play.Aborted then
			finishSession(s)
		elseif waiting > 0 then
			s.Generation += 1 -- the next hatch takes the backdrop over
		elseif s.Level > 0.01 then
			closeLater(s, 0.9) -- auto hatch: the next egg usually comes before this
		else
			finishSession(s)
		end
	end
	playing = false
end

-- tier: "Normal" | "Golden" | "Rainbow" (a boolean still means golden)
function Hatch.Reveal(petId: string, tier, title: string?)
	local tierName = Pets.TierOf(tier)
	task.spawn(Hatch.Play, {
		Results = { { Id = petId, Golden = tierName == "Golden", Rainbow = tierName == "Rainbow", New = false } },
	}, { Title = title or "NEW PET!" })
end

return Hatch
