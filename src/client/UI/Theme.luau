--!nonstrict
-- Visual identity for the interface: fonts, colors and button palettes.

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local Theme = {}

Theme.Font = Enum.Font.FredokaOne
Theme.BodyFont = Enum.Font.GothamBold
Theme.LightFont = Enum.Font.GothamMedium

Theme.Colors = {
	PanelTop = rgb(44, 56, 112),
	PanelBottom = rgb(24, 30, 68),
	Card = rgb(48, 60, 120),
	CardDark = rgb(34, 43, 90),
	Inset = rgb(20, 26, 58),
	Stroke = rgb(10, 13, 34),
	Text = rgb(255, 255, 255),
	SubText = rgb(178, 194, 238),
	Muted = rgb(122, 136, 180),
	Volts = rgb(255, 214, 64),
	Energy = rgb(84, 204, 255),
	Power = rgb(150, 224, 255),
	Success = rgb(84, 222, 120),
	Danger = rgb(255, 88, 106),
	Warning = rgb(255, 176, 60),
	Info = rgb(110, 180, 255),
	Reward = rgb(255, 120, 210),
}

-- { top, bottom } gradient colors for buttons
Theme.Buttons = {
	Green = { rgb(96, 230, 120), rgb(38, 168, 78) },
	Blue = { rgb(96, 182, 255), rgb(44, 112, 226) },
	Yellow = { rgb(255, 222, 92), rgb(236, 158, 26) },
	Orange = { rgb(255, 174, 84), rgb(228, 104, 34) },
	Red = { rgb(255, 112, 126), rgb(206, 44, 68) },
	Purple = { rgb(186, 136, 255), rgb(116, 64, 226) },
	Pink = { rgb(255, 146, 210), rgb(214, 70, 154) },
	Teal = { rgb(92, 232, 214), rgb(28, 164, 154) },
	Gray = { rgb(136, 146, 176), rgb(82, 90, 118) },
	Dark = { rgb(64, 78, 140), rgb(40, 50, 100) },
}

Theme.NotificationColors = {
	Info = rgb(110, 180, 255),
	Success = rgb(84, 222, 120),
	Error = rgb(255, 88, 106),
	Warning = rgb(255, 176, 60),
	Reward = rgb(255, 120, 210),
}

return Theme
