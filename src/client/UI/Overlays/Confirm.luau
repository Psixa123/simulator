--!nonstrict
-- Yes / No confirmation dialog: a small cloud window over a dim.

local Registry = require(script.Parent.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI)
local Theme = require(script.Parent.Parent.Theme)
local Icons = require(script.Parent.Parent.Icons)

local Confirm = {}

local holder: Frame?

local function close()
	if holder then
		local current = holder
		holder = nil
		current:Destroy()
	end
end

-- The weather badge icon for a dialog by its confirm colour
local ICON_BY_COLOR = {
	Coral = "Close",
	Storm = "ClimateShift",
	Leaf = "Check",
}

-- options: { Title, Text, ConfirmText, Color, Icon (Icons key), OnConfirm }
function Confirm.Show(options)
	close()
	local root = Registry.InterfaceController.OverlayRoot

	local dim = UI.Create("TextButton", {
		Name = "Confirm",
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = Color3.fromRGB(16, 22, 52),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		Parent = root,
	})
	holder = dim
	dim.Activated:Connect(close)

	local color = options.Color or "Green"
	local setName = Theme.SetAliases[color] or color
	local window = UI.Window({
		Name = "Dialog",
		Title = options.Title or "Are you sure?",
		Icon = if Icons.Has(options.Icon) then options.Icon else (ICON_BY_COLOR[setName] or "Check"),
		Size = UDim2.fromOffset(480, 270),
		Padding = { 22, 16, 18 },
	})
	local dialog = window.Frame
	dialog.Position = UDim2.new(0.5, 0, 0.5, 20 + Registry.InterfaceController.SafeTop / 2)
	dialog.ZIndex = 51
	dialog.Visible = true
	dialog.Parent = dim
	window.Close.Activated:Connect(close)

	UI.Text({
		Name = "Message",
		Text = options.Text or "",
		Font = Theme.BodyFont,
		TextSize = 19,
		Scaled = true,
		Wrapped = true,
		Color = Theme.InkSoft,
		Size = UDim2.new(1, 0, 1, -72),
		ZIndex = 2,
		Parent = window.Content,
	})
	UI.Button({
		Name = "Cancel",
		Text = "Cancel",
		Color = "Gray",
		TextSize = 22,
		Size = UDim2.new(0.5, -8, 0, 58),
		Position = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 1),
		ZIndex = 2,
		Parent = window.Content,
		OnClick = close,
	})
	UI.Button({
		Name = "Confirm",
		Text = options.ConfirmText or "Confirm",
		Color = color,
		TextSize = 22,
		Size = UDim2.new(0.5, -8, 0, 58),
		Position = UDim2.fromScale(1, 1),
		AnchorPoint = Vector2.new(1, 1),
		ZIndex = 2,
		Parent = window.Content,
		OnClick = function()
			close()
			if options.OnConfirm then
				options.OnConfirm()
			end
		end,
	})

	window.Scale.Scale = 0.8
	UI.Tween(window.Scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
end

return Confirm
