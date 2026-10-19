--!nonstrict
-- Visual identity for the interface: the "Sky Lab" look (docs/STYLE_GUIDE.md, section 2).
-- Tokens for colours, candy colour sets, rarity pedestals, fonts and sizes. UI.luau builds the
-- components from these; nothing else should hard-code a colour that has a token here.

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function shade(color: Color3, k: number): Color3
	return Color3.new(color.R * k, color.G * k, color.B * k)
end

local WHITE = Color3.new(1, 1, 1)

local Theme = {}

Theme.Font = Enum.Font.FredokaOne -- titles, numbers, buttons
Theme.BodyFont = Enum.Font.GothamBold -- body text
Theme.LightFont = Enum.Font.GothamMedium

---------------------------------------------------------------------------
-- Palette
---------------------------------------------------------------------------
Theme.Ink = hex("233066") -- outlines (2-3 px) and text on light surfaces
Theme.InkSoft = hex("5B6A9E") -- secondary text
Theme.Cloud = hex("FFFFFF") -- window / card body top
Theme.Mist = hex("EAF3FF") -- window / card body bottom
Theme.Haze = hex("D5E5FB") -- insets, tracks, empty slots
Theme.HazeDeep = hex("B4C8EA") -- pressed tracks, dividers
Theme.Up = hex("1F8F38") -- "after" numbers (a stat going up)
Theme.ShadeTransparency = 0.75 -- drop shadows: Ink at 75 % transparency, a few px lower

Theme.Outline = 3 -- Ink outline on windows, buttons, capsules
Theme.OutlineSmall = 2 -- small parts: tiles, toasts, badges

-- Candy colour sets: Top / Bottom face gradient, Lip = Bottom x0.62 (the 3D edge under a button),
-- Stroke = Bottom x0.55 (outline of white text on the surface), Tint / Tint2 = pale wells
local function candySet(top: string, bottom: string, tint: string, tint2: string)
	local bottomColor = hex(bottom)
	return {
		Top = hex(top),
		Bottom = bottomColor,
		Lip = shade(bottomColor, 0.62),
		Stroke = shade(bottomColor, 0.55),
		Tint = hex(tint),
		Tint2 = hex(tint2),
		Text = WHITE,
	}
end

Theme.Sets = {
	Sky = candySet("5CC8FF", "2F86F2", "E3F5FF", "BFE3FF"), -- primary accent: header bands, active tabs
	Bolt = candySet("FFE15A", "FFAA1F", "FFF8D9", "FFE7AC"), -- Volts, highlights, "new"
	Rain = candySet("54E0FF", "1E9BEF", "E0F9FF", "B3E8FB"), -- energy, the storm jar's liquid
	Storm = candySet("A98BFF", "6B4BE6", "F1ECFF", "D9CCFD"), -- premium, Climate Shift, rare things
	Leaf = candySet("7BE36A", "33B24A", "E8FAE4", "C2EDC4"), -- buy, confirm, sell
	Coral = candySet("FF7A85", "E43A58", "FFE4E7", "FBC3CB"), -- close, delete, danger, badges
	Sunset = candySet("FFB15C", "F2702A", "FFF0DE", "FDD3B2"), -- warnings, boosts
	Pink = candySet("FF9BD3", "EA539F", "FFE6F3", "FBC6E2"), -- pets
	Ink = candySet("7A8AC8", "45539A", "E6EAF7", "C9D0EA"), -- neutral dark
	Off = {
		Top = hex("E9EFF9"),
		Bottom = hex("C9D6EC"),
		Lip = hex("8D9BBA"),
		Stroke = hex("7684A8"),
		Tint = hex("F2F5FB"),
		Tint2 = hex("DCE3F0"),
		Text = hex("F7FAFF"),
	}, -- disabled / can't afford
}

-- Older colour names (still used by the panels) -> sets
Theme.SetAliases = {
	Green = "Leaf",
	Blue = "Sky",
	Yellow = "Bolt",
	Gold = "Bolt",
	Orange = "Sunset",
	Red = "Coral",
	Purple = "Storm",
	Teal = "Rain",
	Cyan = "Rain",
	Gray = "Off",
	Grey = "Off",
	Disabled = "Off",
	Dark = "Ink",
}

-- A candy set by name (a Sky Lab name or an older one); Sky when unknown
function Theme.Set(name: string?)
	if name then
		return Theme.Sets[name] or Theme.Sets[Theme.SetAliases[name] or ""] or Theme.Sets.Sky
	end
	return Theme.Sets.Sky
end

function Theme.Shade(color: Color3, k: number): Color3
	return shade(color, k)
end

-- Rarity pedestal colours from a rarity colour (Config/Pets.luau): light top, the colour, dark edge
function Theme.Rarity(color: Color3)
	return { Top = color:Lerp(WHITE, 0.5), Bottom = color, Edge = shade(color, 0.55) }
end

---------------------------------------------------------------------------
-- Sizes (offset px at 1280x720, where the HUD scale is 1)
---------------------------------------------------------------------------
Theme.Sizes = {
	WindowCorner = 26,
	WindowBand = 60, -- Sky header band
	WindowBadge = 76, -- round weather badge over the top-left corner
	WindowClose = 48,
	TitleText = 32,
	ButtonCorner = 14,
	ButtonLip = 5,
	ButtonText = 22,
	TileCorner = 18,
	CapsuleHeight = 44,
	CapsuleIcon = 54,
	CapsuleText = 26,
	HudButton = 68,
	HudLabel = 17,
	JarHeight = 52,
	ToastHeight = 48,
	ToastText = 19,
	BadgeSize = 26,
}

---------------------------------------------------------------------------
-- Older tokens, kept so code written for the previous look still runs. New code should use the
-- palette above.
---------------------------------------------------------------------------
Theme.Colors = {
	PanelTop = rgb(44, 56, 112),
	PanelBottom = rgb(24, 30, 68),
	Card = rgb(56, 70, 138),
	CardDark = rgb(38, 49, 104),
	Inset = rgb(28, 37, 84),
	Stroke = Theme.Ink,
	Text = WHITE,
	SubText = rgb(196, 210, 246),
	Muted = rgb(122, 136, 180),
	Volts = rgb(255, 214, 64),
	Energy = rgb(84, 214, 255),
	Power = rgb(150, 224, 255),
	Success = rgb(96, 222, 110),
	Danger = rgb(255, 98, 116),
	Warning = rgb(255, 176, 60),
	Info = rgb(110, 190, 255),
	Reward = rgb(255, 120, 210),
	-- Sky Lab names
	Ink = Theme.Ink,
	InkSoft = Theme.InkSoft,
	Cloud = Theme.Cloud,
	Mist = Theme.Mist,
	Haze = Theme.Haze,
	HazeDeep = Theme.HazeDeep,
	Up = Theme.Up,
}

-- { top, bottom } gradient colours by the older button colour names
Theme.Buttons = {}
for _, name in { "Green", "Blue", "Yellow", "Orange", "Red", "Purple", "Pink", "Teal", "Gray", "Dark" } do
	local set = Theme.Set(name)
	Theme.Buttons[name] = { set.Top, set.Bottom }
end
for name, set in Theme.Sets do
	Theme.Buttons[name] = { set.Top, set.Bottom }
end

-- Toast kinds: the icon disk's colour set and icon (Icons.luau key)
Theme.Notifications = {
	Info = { Set = "Sky", Icon = "Star" },
	Success = { Set = "Leaf", Icon = "Check" },
	Error = { Set = "Coral", Icon = "Lock" },
	Warning = { Set = "Sunset", Icon = "MegaStorm" },
	Reward = { Set = "Bolt", Icon = "Gift" },
}

Theme.NotificationColors = {}
for kind, info in Theme.Notifications do
	Theme.NotificationColors[kind] = Theme.Set(info.Set).Bottom
end

return Theme
