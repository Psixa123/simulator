--!nonstrict
-- Teleport panel: travel to the hub, the arena or any unlocked zone, and unlock the next zone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI)
local Theme = require(script.Parent.Parent.Theme)

local Teleport = {}

local COLORS = Theme.Colors

local function travel(target: any)
	local result = Remotes.Teleport:InvokeServer(target)
	if result and result.Ok then
		Registry.InterfaceController.ClosePanel()
	elseif result then
		Registry.InterfaceController.Notify(result.Error, "Error")
	end
end

local function row(parent: Instance, order: number, icon: string, color: Color3, name: string)
	local card = UI.Card({
		Name = name,
		Size = UDim2.new(1, -8, 0, 70),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.Icon({
		Text = icon,
		Color = color,
		Size = UDim2.fromOffset(52, 52),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = card,
	})
	UI.Label({
		Name = "Title",
		Text = name,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -250, 0, 26),
		Position = UDim2.fromOffset(74, 10),
		MaxTextSize = 22,
		Parent = card,
	})
	local info = UI.Label({
		Name = "Info",
		Text = "",
		Font = Theme.BodyFont,
		TextColor3 = COLORS.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -250, 0, 18),
		Position = UDim2.fromOffset(74, 40),
		MaxTextSize = 14,
		Stroke = 1.5,
		Parent = card,
	})
	return card, info
end

function Teleport.Build()
	local window = UI.Window({
		Name = "Teleport",
		Title = "Teleport",
		Icon = "🗺️",
		Color = "Teal",
		Size = UDim2.fromOffset(640, 560),
	})

	local list = UI.Scroll({
		Name = "List",
		Parent = window.Content,
		UI.List(Enum.FillDirection.Vertical, 8),
		UI.Padding(4, 8, 8, 2),
	})

	-- Fixed destinations
	local hubCard, hubInfo = row(list, 1, Zones.Hub.Icon, Zones.Hub.Color, Zones.Hub.Name)
	hubInfo.Text = "Upgrades, rebirths, leaderboards and daily rewards"
	UI.Button({
		Text = "GO",
		Color = "Teal",
		Size = UDim2.fromOffset(150, 48),
		Position = UDim2.new(1, -10, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Parent = hubCard,
		OnClick = function()
			travel("Hub")
		end,
	})

	local arenaCard, arenaInfo = row(list, 2, "🌪️", Color3.fromRGB(150, 205, 255), "Mega Storm Arena")
	arenaInfo.Text = "Team up against the Mega Storm for big rewards"
	UI.Button({
		Text = "GO",
		Color = "Teal",
		Size = UDim2.fromOffset(150, 48),
		Position = UDim2.new(1, -10, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Parent = arenaCard,
		OnClick = function()
			travel("Arena")
		end,
	})

	local zoneRows = {}
	for zoneId, zone in ipairs(Zones) do
		local card, info = row(list, 2 + zoneId, zone.Icon, zone.Color, zone.Name)
		local button
		button = UI.Button({
			Text = "GO",
			Color = "Teal",
			Size = UDim2.fromOffset(150, 48),
			Position = UDim2.new(1, -10, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			MaxTextSize = 20,
			Parent = card,
			OnClick = function()
				local data = Registry.DataController.Data
				if not data then
					return
				end
				if zoneId <= data.Zone then
					travel(zoneId)
				elseif zoneId == data.Zone + 1 then
					local result = Remotes.UnlockZone:InvokeServer(zoneId)
					if result and not result.Ok then
						Registry.InterfaceController.Notify(result.Error, "Error")
					end
				else
					Registry.InterfaceController.Notify("Unlock " .. Zones[data.Zone + 1].Name .. " first!", "Error")
				end
			end,
		})
		zoneRows[zoneId] = { Info = info, Button = button }
	end

	local function refresh()
		local data = Registry.DataController.Data
		if not data then
			return
		end
		local power = Formulas.Power(data)
		for zoneId, zoneRow in zoneRows do
			local zone = Zones[zoneId]
			if zoneId <= data.Zone then
				if power >= zone.MinPower then
					zoneRow.Info.Text = "Unlocked  •  ⚡ x" .. Format.Number(zone.Value) .. " Volts per energy"
					zoneRow.Info.TextColor3 = COLORS.SubText
				else
					zoneRow.Info.Text = "Unlocked  •  Needs 💨 " .. Format.Number(zone.MinPower) .. " Power to catch here"
					zoneRow.Info.TextColor3 = COLORS.Warning
				end
				UI.SetButtonText(zoneRow.Button, "GO")
				UI.SetButtonColor(zoneRow.Button, "Teal")
			else
				zoneRow.Info.Text = string.format("Needs ⚡ %s Volts and 💨 %s Power", Format.Number(zone.Cost), Format.Number(zone.MinPower))
				zoneRow.Info.TextColor3 = COLORS.SubText
				if zoneId == data.Zone + 1 then
					local ready = data.Volts >= zone.Cost and power >= zone.MinPower
					UI.SetButtonText(zoneRow.Button, "UNLOCK ⚡" .. Format.Number(zone.Cost))
					UI.SetButtonColor(zoneRow.Button, if ready then "Green" else "Gray")
				else
					UI.SetButtonText(zoneRow.Button, "🔒 LOCKED")
					UI.SetButtonColor(zoneRow.Button, "Gray")
				end
			end
		end
	end

	Registry.DataController.ObserveMany({ "Zone", "Volts", "Upgrades" }, refresh)

	return { Window = window, OnOpen = refresh }
end

return Teleport
