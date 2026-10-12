--!nonstrict
-- Yes / No confirmation dialog.

local Registry = require(script.Parent.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI)
local Theme = require(script.Parent.Parent.Theme)

local Confirm = {}

local holder: Frame?

local function close()
	if holder then
		local current = holder
		holder = nil
		current:Destroy()
	end
end

-- options: { Title, Text, ConfirmText, Color, OnConfirm }
function Confirm.Show(options)
	close()
	local root = Registry.InterfaceController.OverlayRoot

	local dim = UI.Create("TextButton", {
		Name = "Confirm",
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = Color3.fromRGB(6, 8, 22),
		BackgroundTransparency = 0.4,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		Parent = root,
	})
	holder = dim

	local dialog = UI.Create("Frame", {
		Name = "Dialog",
		Size = UDim2.fromOffset(470, 250),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 51,
		Parent = dim,
		UI.Corner(18),
		UI.Gradient(Theme.Colors.PanelTop, Theme.Colors.PanelBottom, 90),
		UI.Stroke(4),
	})
	UI.Label({ Text = options.Title or "Are you sure?", Size = UDim2.new(1, -40, 0, 40), Position = UDim2.fromOffset(20, 18), ZIndex = 52, MaxTextSize = 32, Parent = dialog })
	UI.Label({
		Text = options.Text or "",
		Font = Theme.BodyFont,
		TextColor3 = Theme.Colors.SubText,
		Size = UDim2.new(1, -50, 0, 80),
		Position = UDim2.fromOffset(25, 66),
		ZIndex = 52,
		MaxTextSize = 20,
		Stroke = 1.5,
		Parent = dialog,
	})
	UI.Button({
		Text = "Cancel",
		Color = "Gray",
		Size = UDim2.fromOffset(180, 56),
		Position = UDim2.new(0.5, -10, 1, -20),
		AnchorPoint = Vector2.new(1, 1),
		ZIndex = 52,
		Parent = dialog,
		OnClick = close,
	})
	UI.Button({
		Text = options.ConfirmText or "Confirm",
		Color = options.Color or "Green",
		Size = UDim2.fromOffset(180, 56),
		Position = UDim2.new(0.5, 10, 1, -20),
		AnchorPoint = Vector2.new(0, 1),
		ZIndex = 52,
		Parent = dialog,
		OnClick = function()
			close()
			if options.OnConfirm then
				options.OnConfirm()
			end
		end,
	})

	local scale = Instance.new("UIScale")
	scale.Scale = 0.8
	scale.Parent = dialog
	UI.Tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
end

return Confirm
