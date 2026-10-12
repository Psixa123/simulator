--!nonstrict
-- Owns the ScreenGuis, scales the interface for every screen size, opens/closes panels
-- and shows notifications, hints and big announcement text.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)

local Registry = require(script.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)

local InterfaceController = {}
InterfaceController.PanelOpened = Signal.new()
InterfaceController.PanelClosed = Signal.new()
InterfaceController.Scale = 1
InterfaceController.HudGui = nil :: any
InterfaceController.HudRoot = nil :: any
InterfaceController.PanelGui = nil :: any
InterfaceController.PanelRoot = nil :: any
InterfaceController.OverlayGui = nil :: any
InterfaceController.OverlayRoot = nil :: any

local player = Players.LocalPlayer
local roots = {}
local panels = {}
local openName: string? = nil
local dim: TextButton
local notificationHolder: Frame
local notificationOrder = 0
local hintLabel: TextLabel
local hintThread = nil
local lastHint = {}

local function makeGui(name: string, displayOrder: number, fullScreen: boolean)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder
	gui.IgnoreGuiInset = fullScreen
	gui.ScreenInsets = if fullScreen then Enum.ScreenInsets.None else Enum.ScreenInsets.CoreUISafeInsets
	gui.Parent = player:WaitForChild("PlayerGui")

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = root

	table.insert(roots, { Gui = gui, Frame = root, Scale = scale })
	return gui, root
end

local function updateScales()
	for _, entry in roots do
		local size = entry.Gui.AbsoluteSize
		if size.X > 0 and size.Y > 0 then
			local scale = math.clamp(math.min(size.X / 1280, size.Y / 740), 0.52, 1.25)
			entry.Scale.Scale = scale
			entry.Frame.Size = UDim2.fromScale(1 / scale, 1 / scale)
			InterfaceController.Scale = scale
		end
	end
end

---------------------------------------------------------------------------
-- Panels
---------------------------------------------------------------------------
-- panel = { Window = UI.Window(...), OnOpen = fn?, OnClose = fn? }
function InterfaceController.RegisterPanel(name: string, panel)
	panels[name] = panel
	panel.Window.Frame.Parent = InterfaceController.PanelRoot
	panel.Window.Close.Activated:Connect(function()
		InterfaceController.ClosePanel()
	end)
end

function InterfaceController.IsOpen(name: string?): boolean
	if name then
		return openName == name
	end
	return openName ~= nil
end

function InterfaceController.OpenPanel(name: string, ...)
	local panel = panels[name]
	if not panel then
		return
	end
	if openName == name then
		if panel.OnOpen then
			task.spawn(panel.OnOpen, ...)
		end
		return
	end
	if openName then
		InterfaceController.ClosePanel(true)
	end

	openName = name
	local window = panel.Window
	window.Frame.Visible = true
	window.Scale.Scale = 0.8
	UI.Tween(window.Scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	dim.Visible = true
	UI.Tween(dim, 0.2, { BackgroundTransparency = 0.45 })

	if panel.OnOpen then
		task.spawn(panel.OnOpen, ...)
	end
	InterfaceController.PanelOpened:Fire(name)
end

function InterfaceController.ClosePanel(instant: boolean?)
	local name = openName
	if not name then
		return
	end
	openName = nil
	local panel = panels[name]
	local window = panel.Window

	if panel.OnClose then
		task.spawn(panel.OnClose)
	end
	if instant then
		window.Frame.Visible = false
	else
		local tween = UI.Tween(window.Scale, 0.14, { Scale = 0.85 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween.Completed:Once(function()
			if openName ~= name then
				window.Frame.Visible = false
			end
		end)
	end
	UI.Tween(dim, 0.15, { BackgroundTransparency = 1 }).Completed:Once(function()
		if not openName then
			dim.Visible = false
		end
	end)
	InterfaceController.PanelClosed:Fire(name)
end

function InterfaceController.TogglePanel(name: string)
	if openName == name then
		InterfaceController.ClosePanel()
	else
		InterfaceController.OpenPanel(name)
	end
end

---------------------------------------------------------------------------
-- Notifications
---------------------------------------------------------------------------
function InterfaceController.Notify(text: string, kind: string?)
	kind = kind or "Info"
	local color = Theme.NotificationColors[kind] or Theme.NotificationColors.Info
	notificationOrder += 1

	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.Size = UDim2.fromOffset(470, 46)
	toast.BackgroundColor3 = Color3.fromRGB(20, 26, 58)
	toast.BackgroundTransparency = 0.06
	toast.LayoutOrder = notificationOrder
	UI.Corner(12).Parent = toast
	local stroke = UI.Stroke(2.5, color)
	stroke.Parent = toast

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Size = UDim2.new(0, 6, 1, -14)
	accent.Position = UDim2.new(0, 8, 0.5, 0)
	accent.AnchorPoint = Vector2.new(0, 0.5)
	accent.BackgroundColor3 = color
	UI.Round().Parent = accent
	accent.Parent = toast

	local label = UI.Label({
		Name = "Text",
		Text = text,
		Size = UDim2.new(1, -36, 0.62, 0),
		Position = UDim2.new(0, 22, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 22,
		Parent = toast,
	})

	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = toast
	toast.Parent = notificationHolder
	UI.Tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)

	if kind == "Error" then
		Registry.SoundController.Play("Error")
	end

	-- Keep at most 4 notifications on screen
	local toasts = {}
	for _, child in notificationHolder:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for index = 1, #toasts - 4 do
		toasts[index]:Destroy()
	end

	task.delay(3.4, function()
		if not toast.Parent then
			return
		end
		UI.Tween(toast, 0.3, { BackgroundTransparency = 1 })
		UI.Tween(stroke, 0.3, { Transparency = 1 })
		UI.Tween(accent, 0.3, { BackgroundTransparency = 1 })
		UI.Tween(label, 0.3, { TextTransparency = 1 })
		local labelStroke = label:FindFirstChildOfClass("UIStroke")
		if labelStroke then
			UI.Tween(labelStroke, 0.3, { Transparency = 1 })
		end
		task.wait(0.32)
		toast:Destroy()
	end)
end

-- Small helper text above the tank bar ("Move closer to weather!")
function InterfaceController.Hint(text: string, key: string?, cooldown: number?)
	local now = os.clock()
	key = key or text
	if lastHint[key] and now - lastHint[key] < (cooldown or 2.5) then
		return
	end
	lastHint[key] = now
	hintLabel.Text = text
	hintLabel.Visible = true
	hintLabel.TextTransparency = 0
	UI.Pop(hintLabel, 1.12)
	if hintThread then
		task.cancel(hintThread)
	end
	hintThread = task.delay(2.2, function()
		UI.Tween(hintLabel, 0.3, { TextTransparency = 1 })
		task.wait(0.3)
		hintLabel.Visible = false
		hintThread = nil
	end)
end

-- Huge announcement text in the middle of the screen
function InterfaceController.BigText(text: string, color: Color3?, subtitle: string?, duration: number?)
	local holder = Instance.new("Frame")
	holder.Name = "BigText"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(900, 150)
	holder.Position = UDim2.fromScale(0.5, 0.3)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Parent = InterfaceController.OverlayRoot

	local title = UI.Label({
		Text = text,
		TextColor3 = color or Theme.Colors.Volts,
		Size = UDim2.fromScale(1, 0.62),
		Stroke = 5,
		Parent = holder,
	})
	local sub
	if subtitle then
		sub = UI.Label({
			Text = subtitle,
			Size = UDim2.fromScale(1, 0.3),
			Position = UDim2.fromScale(0, 0.66),
			Stroke = 3,
			Parent = holder,
		})
	end

	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = holder
	UI.Tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)

	task.delay(duration or 2.4, function()
		UI.Tween(scale, 0.25, { Scale = 1.15 })
		for _, label in { title, sub } do
			if label then
				UI.Tween(label, 0.25, { TextTransparency = 1 })
				local stroke = label:FindFirstChildOfClass("UIStroke")
				if stroke then
					UI.Tween(stroke, 0.25, { Transparency = 1 })
				end
			end
		end
		task.wait(0.3)
		holder:Destroy()
	end)
end

function InterfaceController.Init()
	local hudGui, hudRoot = makeGui("HUD", 1, false)
	local panelGui, panelRoot = makeGui("Panels", 5, true)
	local overlayGui, overlayRoot = makeGui("Overlay", 10, true)
	InterfaceController.HudGui = hudGui
	InterfaceController.HudRoot = hudRoot
	InterfaceController.PanelGui = panelGui
	InterfaceController.PanelRoot = panelRoot
	InterfaceController.OverlayGui = overlayGui
	InterfaceController.OverlayRoot = overlayRoot

	dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.BackgroundColor3 = Color3.fromRGB(6, 8, 22)
	dim.BackgroundTransparency = 1
	dim.Size = UDim2.fromScale(1, 1)
	dim.Visible = false
	dim.ZIndex = 0
	dim.Parent = panelRoot
	dim.Activated:Connect(function()
		InterfaceController.ClosePanel()
	end)

	notificationHolder = UI.Create("Frame", {
		Name = "Notifications",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(480, 260),
		Position = UDim2.new(0.5, 0, 0, 132),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = overlayRoot,
		UI.List(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top),
	})

	hintLabel = UI.Label({
		Name = "Hint",
		Text = "",
		Visible = false,
		TextColor3 = Color3.fromRGB(255, 235, 150),
		Size = UDim2.fromOffset(620, 30),
		Position = UDim2.new(0.5, 0, 1, -150),
		AnchorPoint = Vector2.new(0.5, 1),
		Stroke = 3,
		MaxTextSize = 26,
		Parent = hudRoot,
	})

	for _, entry in roots do
		entry.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScales)
	end
	updateScales()

	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
	end)
end

return InterfaceController
