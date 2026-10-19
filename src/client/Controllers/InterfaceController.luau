--!nonstrict
-- Owns the ScreenGuis, scales the interface for every screen size, opens/closes panels
-- and shows notifications, hints and big announcement text.
-- Windows are fitted below the Roblox top bar, and phones get a bigger interface.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)

local Registry = require(script.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)

local InterfaceController = {}
InterfaceController.PanelOpened = Signal.new()
InterfaceController.PanelClosed = Signal.new()
InterfaceController.Scale = 1 -- HUD scale (same as HudScale)
InterfaceController.HudScale = 1
InterfaceController.OverlayScale = 1
InterfaceController.SafeTop = 0 -- top bar height in Overlay units (full-screen overlays keep their content below it)
InterfaceController.HudGui = nil :: any
InterfaceController.HudRoot = nil :: any
InterfaceController.PanelGui = nil :: any
InterfaceController.PanelRoot = nil :: any
InterfaceController.OverlayGui = nil :: any
InterfaceController.OverlayRoot = nil :: any

local player = Players.LocalPlayer
local roots = {} -- [gui name] = { Gui, Frame, Scale }
local panels = {}
local openName: string? = nil
local dim: TextButton
local notificationHolder: Frame
local notificationOrder = 0
local notificationAnchor: GuiObject? = nil
local notificationTop = 0
local bigTextHolder: Frame? = nil
local hintLabel: TextLabel
local hintThread = nil
local hintTweens = {}
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

	roots[name] = { Gui = gui, Frame = root, Scale = scale }
	return gui, root
end

-- Screens are designed for 1280x720 (docs/ui_mockup.png: 1 px there = 1 offset px here, top bar
-- included). `extraHeight` is the top bar height for guis that start below it, so every gui gets the
-- same scale. Phones use a shorter reference and a higher minimum so text stays readable (the HUD
-- still fits at 0.6 on a 640x360 phone).
local function baseScale(size: Vector2, extraHeight: number): number
	local phone = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local referenceHeight = if phone then 698 else 720
	return math.clamp(math.min(size.X / 1280, (size.Y + extraHeight) / referenceHeight), if phone then 0.6 else 0.52, 1.25)
end

-- Height of the Roblox top bar in pixels: how far below the full-screen guis the inset ones start.
-- Measured on the Toasts gui (same insets as the HUD) because the HUD is disabled while loading.
local function topInset(): number
	local toasts, overlay = roots.Toasts, roots.Overlay
	if not toasts or not overlay then
		return 0
	end
	local inset = toasts.Frame.AbsolutePosition.Y - overlay.Frame.AbsolutePosition.Y
	if inset <= 0 then
		-- Not laid out yet: the size difference is close enough (it also counts any bottom inset)
		inset = overlay.Gui.AbsoluteSize.Y - toasts.Gui.AbsoluteSize.Y
	end
	return math.max(0, inset)
end

-- Fits every window inside the safe area (below the top bar, clear of notches) and centres it there
local function fitPanels()
	local entry, safeArea = roots.Panels, roots.Toasts
	if not entry or not safeArea then
		return
	end
	local safe = safeArea.Gui.AbsoluteSize
	local scale = entry.Scale.Scale
	if safe.X <= 0 or safe.Y <= 0 then
		return
	end
	local offset = topInset() / 2 / scale
	for name, panel in panels do
		local frame = panel.Window.Frame
		-- The weather badge (18) and the close button (16) stick out of the sides, the cloud puffs
		-- (44) out of the top and the shadow (6) out of the bottom
		local fit = math.min(1, (safe.X / scale - 24) / (frame.Size.X.Offset + 34), (safe.Y / scale - 16) / (frame.Size.Y.Offset + 50))
		panel.Fit = math.max(fit, 0.3)
		-- a little lower than the centre, so the window and its puffs look centred together
		frame.Position = UDim2.new(0.5, 0, 0.5, offset + 19 * panel.Fit)
		if openName == name then
			panel.Window.Scale.Scale = panel.Fit
		end
	end
end

-- Toasts sit just under the HUD's top-centre stack (Volts, Mega Storm bar) and drop below the
-- big announcement text while one is showing, so neither covers the other
local function placeNotifications()
	local toasts, overlay = roots.Toasts, roots.Overlay
	if not toasts or not notificationHolder then
		return
	end
	local top = 80
	local anchor = notificationAnchor
	local hudRoot = InterfaceController.HudRoot
	if anchor and anchor.Parent and hudRoot then
		-- The Toasts gui has the same insets (so the same size and scale) as the HUD
		top = (anchor.AbsolutePosition.Y + anchor.AbsoluteSize.Y - hudRoot.AbsolutePosition.Y) / InterfaceController.HudScale + 10
	end
	if bigTextHolder and overlay then
		-- Announcements sit at 30% of the screen, with room for the hazard line some show under them
		local bottom = overlay.Gui.AbsoluteSize.Y * 0.3 + 130 * overlay.Scale.Scale
		top = math.max(top, (bottom - topInset()) / toasts.Scale.Scale)
	end
	if math.abs(top - notificationTop) > 1 then
		notificationTop = top
		UI.Tween(notificationHolder, 0.2, { Position = UDim2.new(0.5, 0, 0, top) })
	end
end

local function updateScales()
	local inset = topInset()
	for name, entry in roots do
		local size = entry.Gui.AbsoluteSize
		if size.X > 0 and size.Y > 0 then
			local scale = baseScale(size, if entry.Gui.IgnoreGuiInset then 0 else inset)
			entry.Scale.Scale = scale
			entry.Frame.Size = UDim2.fromScale(1 / scale, 1 / scale)
			if name == "HUD" then
				InterfaceController.HudScale = scale
				InterfaceController.Scale = scale
			elseif name == "Overlay" then
				InterfaceController.OverlayScale = scale
			end
		end
	end
	InterfaceController.SafeTop = topInset() / InterfaceController.OverlayScale
	fitPanels()
	placeNotifications()
end

-- The Roblox hotbar is hidden (it covered the Storm Tank bar) and the vacuum is our only tool,
-- so keep the Storm Vacuum in hand here; without a hotbar an unequipped vacuum couldn't come back
local function equipVacuum()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChildOfClass("Backpack")
	local tool = backpack and backpack:FindFirstChild("StormVacuum")
	if humanoid and humanoid.Health > 0 and tool and tool:IsA("Tool") and not character:FindFirstChildOfClass("Tool") then
		humanoid:EquipTool(tool)
	end
end

---------------------------------------------------------------------------
-- Panels
---------------------------------------------------------------------------
-- panel = { Window = UI.Window(...), OnOpen = fn?, OnClose = fn? }
function InterfaceController.RegisterPanel(name: string, panel)
	panels[name] = panel
	panel.Fit = 1
	panel.Window.Frame.Parent = InterfaceController.PanelRoot
	panel.Window.Close.Activated:Connect(function()
		InterfaceController.ClosePanel()
	end)
	fitPanels()
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
	window.Scale.Scale = panel.Fit * 0.8
	UI.Tween(window.Scale, 0.3, { Scale = panel.Fit }, Enum.EasingStyle.Back)
	dim.Visible = true
	UI.Tween(dim, 0.2, { BackgroundTransparency = 0.8 }) -- a light veil: the world stays bright (docs/ui_mockup.png)

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
		local tween = UI.Tween(window.Scale, 0.14, { Scale = panel.Fit * 0.85 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
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
-- Toasts are placed under the bottom edge of this HUD element (set by the HudController)
function InterfaceController.SetNotificationAnchor(anchor: GuiObject)
	notificationAnchor = anchor
	anchor:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeNotifications)
	anchor:GetPropertyChangedSignal("AbsolutePosition"):Connect(placeNotifications)
	placeNotifications()
end

-- A toast under the currency capsules: a Cloud pill with a coloured icon disk (UI.Toast).
-- kind: Info, Success, Error, Warning, Reward. icon: an Icons key for the disk (the kind's otherwise).
-- The text may use rich text (<font color="#2F86F2">Sunny</font>).
function InterfaceController.Notify(text: string, kind: string?, icon: string?)
	kind = kind or "Info"
	notificationOrder += 1

	local toast = UI.Toast({
		Text = text,
		Kind = kind,
		Icon = icon,
		LayoutOrder = notificationOrder,
		MaxWidth = 520,
		Parent = notificationHolder,
	})

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
		if not toast.Frame.Parent then
			return
		end
		toast.Hide(0.3)
		task.wait(0.32)
		toast.Frame:Destroy()
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
	if hintThread then
		task.cancel(hintThread)
		hintThread = nil
	end
	-- The previous hint's fade would otherwise keep running and hide this one
	for _, tween in hintTweens do
		tween:Cancel()
	end
	table.clear(hintTweens)
	local stroke = hintLabel:FindFirstChildOfClass("UIStroke")
	hintLabel.Text = text
	hintLabel.Visible = true
	hintLabel.TextTransparency = 0
	if stroke then
		stroke.Transparency = 0
	end
	UI.Pop(hintLabel, 1.12)
	hintThread = task.delay(2.2, function()
		table.insert(hintTweens, UI.Tween(hintLabel, 0.3, { TextTransparency = 1 }))
		if stroke then
			table.insert(hintTweens, UI.Tween(stroke, 0.3, { Transparency = 1 }))
		end
		task.wait(0.3)
		hintLabel.Visible = false
		table.clear(hintTweens)
		hintThread = nil
	end)
end

-- Huge announcement text in the middle of the screen (a new one replaces the one showing)
function InterfaceController.BigText(text: string, color: Color3?, subtitle: string?, duration: number?)
	if bigTextHolder then
		bigTextHolder:Destroy()
		bigTextHolder = nil
	end
	-- As wide as fits the screen (the text scales down on narrow phones)
	local overlay = roots.Overlay
	local screenWidth = if overlay and overlay.Gui.AbsoluteSize.X > 0 then overlay.Gui.AbsoluteSize.X / overlay.Scale.Scale else 1280
	local holder = Instance.new("Frame")
	holder.Name = "BigText"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(math.clamp(screenWidth - 40, 300, 900), 150)
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
	bigTextHolder = holder
	placeNotifications()

	task.delay(duration or 2.4, function()
		if bigTextHolder ~= holder then
			return -- replaced (and destroyed) by a newer announcement
		end
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
		if bigTextHolder == holder then
			bigTextHolder = nil
			placeNotifications()
		end
	end)
end

function InterfaceController.Init()
	local hudGui, hudRoot = makeGui("HUD", 1, false)
	local panelGui, panelRoot = makeGui("Panels", 5, true)
	local overlayGui, overlayRoot = makeGui("Overlay", 10, true)
	-- Toasts get their own gui on top, so hatch reveals and dialogs never cover them
	local _, toastRoot = makeGui("Toasts", 11, false)
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
	dim.BackgroundColor3 = Color3.fromRGB(16, 22, 52) -- deep Ink
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
		Size = UDim2.fromOffset(540, 300),
		Position = UDim2.new(0.5, 0, 0, 80),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = toastRoot,
		UI.List(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top),
	})

	hintLabel = UI.Label({
		Name = "Hint",
		Text = "",
		Visible = false,
		TextColor3 = Theme.Sets.Bolt.Top,
		Size = UDim2.fromOffset(620, 30),
		Position = UDim2.new(0.5, 0, 1, -186), -- above the objective, the stats and the Storm Tank
		AnchorPoint = Vector2.new(0.5, 1),
		Stroke = 3,
		MaxTextSize = 26,
		Parent = hudRoot,
	})

	for _, entry in roots do
		entry.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScales)
	end
	-- The top bar can change height without the screen changing size
	roots.Toasts.Frame:GetPropertyChangedSignal("AbsolutePosition"):Connect(updateScales)
	updateScales()

	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			equipVacuum()
		end
	end)
end

return InterfaceController
