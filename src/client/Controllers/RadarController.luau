--!nonstrict
-- Storm Radar gamepass (client): an alert card whenever rare weather spawns in any unlocked
-- zone, with a Teleport button when it's in another zone; the card goes away once the weather
-- is caught. Only radar owners ever see these; the server sends "RadarSpawn" to owners only
-- (see Server/Services/StormRadar). There are no floating markers over the weather itself.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Weather = require(Shared.Config.Weather)
local MapLayout = require(Shared.Config.MapLayout)
local Monetization = require(Shared.Config.Monetization)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)

local RadarController = {}

local PASS_KEY = "StormRadar"
local ALERT_TIME = 9 -- seconds an alert card stays on screen
local MAX_ALERTS = 2

local RARE_COLOR = Weather.Rarities.Rare.Color

local player = Players.LocalPlayer
local pass = Monetization.Gamepasses[PASS_KEY]
local cellFolder: Instance
local holder: Frame
local alerts = {} -- { { Card, Model } } oldest first
local alertOrder = 0
local teleporting = false

local function myPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		return root.Position
	end
	return nil
end

---------------------------------------------------------------------------
-- Alert cards
---------------------------------------------------------------------------
local function dismiss(card: Frame)
	for index, alert in alerts do
		if alert.Card == card then
			table.remove(alerts, index)
			break
		end
	end
	if not card.Parent or card:GetAttribute("Closing") then
		return
	end
	card:SetAttribute("Closing", true)
	local scale = card:FindFirstChild("AlertScale")
	if scale then
		UI.Tween(scale, 0.2, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Once(function()
			card:Destroy()
		end)
	else
		card:Destroy()
	end
end

local function teleport(zoneId: number, card: Frame)
	if teleporting then
		return
	end
	teleporting = true
	local ok, result = pcall(function()
		return Remotes.Teleport:InvokeServer(zoneId)
	end)
	teleporting = false
	if ok and result and result.Ok then
		dismiss(card)
	elseif ok and result then
		Registry.InterfaceController.Notify(result.Error, "Error")
	end
end

local function showAlert(typeId: string, zoneId: number)
	local def = Weather.Types[typeId]
	local zone = Zones[zoneId]
	local position = myPosition()
	local here = position ~= nil and MapLayout.ZoneAt(position) == zoneId
	local textWidth = if here then -84 else -200
	alertOrder -= 1

	local card = UI.CloudCard({
		Name = "RadarAlert",
		Size = UDim2.new(1, 0, 0, 70),
		Top = Theme.Cloud,
		Bottom = Theme.Mist,
		StrokeColor = Theme.Ink,
		CornerRadius = 20,
		LayoutOrder = alertOrder, -- newest on top
	})
	UI.Icon({
		Key = "Radar",
		Text = pass.Icon,
		Color = pass.Color,
		Size = UDim2.fromOffset(50, 50),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = card,
	})
	-- Ink text on the light card (STYLE_GUIDE: no stroke on light surfaces), "Rare" in Storm purple
	UI.Text({
		Name = "Title",
		Text = '<font color="#' .. Theme.Sets.Storm.Bottom:ToHex() .. '">Rare</font> ' .. def.Name .. "!",
		Rich = true,
		TextSize = 20,
		Scaled = true,
		MinTextSize = 10,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, textWidth, 0, 24),
		Position = UDim2.fromOffset(70, 11),
		Parent = card,
	})
	UI.Label({
		Name = "Zone",
		Text = (if here then "📍 Right here in " else "📡 Spotted in ") .. zone.Icon .. " " .. zone.Name,
		Font = Theme.BodyFont,
		TextColor3 = Theme.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, textWidth, 0, 18),
		Position = UDim2.fromOffset(70, 40),
		MaxTextSize = 15,
		Stroke = false,
		Parent = card,
	})
	if not here then
		UI.Button({
			Name = "Teleport",
			Text = "GO",
			Icon = "Teleport",
			Color = "Sky",
			Size = UDim2.fromOffset(120, 46),
			Position = UDim2.new(1, -10, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			MaxTextSize = 18,
			Parent = card,
			OnClick = function()
				teleport(zoneId, card)
			end,
		})
	end

	local scale = Instance.new("UIScale")
	scale.Name = "AlertScale"
	scale.Scale = 0.6
	scale.Parent = card
	card.Parent = holder
	UI.Tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)

	local alert = { Card = card, Model = nil }
	table.insert(alerts, alert)
	while #alerts > MAX_ALERTS do
		dismiss(alerts[1].Card)
	end
	task.delay(ALERT_TIME, dismiss, card)
	return alert
end

---------------------------------------------------------------------------
-- Server events
---------------------------------------------------------------------------
local function onRadarSpawn(typeId: any, position: any, zoneId: any, cellId: any)
	if not Weather.Types[typeId] or type(zoneId) ~= "number" or not Zones[zoneId] or typeof(position) ~= "Vector3" or type(cellId) ~= "number" then
		return
	end
	Registry.SoundController.Play("Success", 1.4, 0.7)
	local camera = Workspace.CurrentCamera
	if camera and (camera.CFrame.Position - position).Magnitude < 400 then
		Registry.EffectsController.LightningBolt(position + Vector3.new(0, 60, 0), position, RARE_COLOR, 0.8)
	end

	local alert = showAlert(typeId, zoneId)
	-- The cell model normally arrives together with the event, but don't count on it
	local model = cellFolder:FindFirstChild("Cell" .. cellId) or cellFolder:WaitForChild("Cell" .. cellId, 3)
	if model and model.Parent then
		alert.Model = model
	end
end

local function update()
	-- Alerts about weather that's already gone aren't useful any more
	for index = #alerts, 1, -1 do
		local alert = alerts[index]
		if alert.Model and not alert.Model.Parent then
			dismiss(alert.Card)
		end
	end
end

function RadarController.Init()
	-- Right side, just above the boost timers: the top right belongs to the Roblox player list
	holder = UI.Create("Frame", {
		Name = "RadarAlerts",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(350, 150),
		Position = UDim2.new(1, -12, 1, -270),
		AnchorPoint = Vector2.new(1, 1),
		Parent = Registry.InterfaceController.HudRoot,
		UI.List(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom),
	})

	-- Sit just above the HUD's timer column (which moves up on tablets) and, on narrow phones, stay
	-- right of the centred notification column (520 wide)
	local hud = Registry.InterfaceController.HudRoot
	local boosts = hud:FindFirstChild("Boosts")
	local function place()
		local bottom = if boosts then -boosts.Position.Y.Offset else 160
		local height = if boosts then boosts.Size.Y.Offset else 100
		local width = hud.AbsoluteSize.X / Registry.InterfaceController.HudScale
		holder.Size = UDim2.fromOffset(math.clamp(width / 2 - 260 - 24, 280, 350), 150)
		holder.Position = UDim2.new(1, -12, 1, -(bottom + height + 12))
	end
	hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	if boosts then
		boosts:GetPropertyChangedSignal("Position"):Connect(place)
		boosts:GetPropertyChangedSignal("Size"):Connect(place)
	end
	place()
end

function RadarController.Start()
	cellFolder = Workspace:WaitForChild("WeatherCells")

	Remotes.Effect.OnClientEvent:Connect(function(name, ...)
		if name == "RadarSpawn" then
			onRadarSpawn(...)
		end
	end)

	while true do
		update()
		task.wait(0.2)
	end
end

return RadarController
