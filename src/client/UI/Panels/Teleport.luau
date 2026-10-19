--!nonstrict
-- Teleport panel: travel to the hub, the arena or any unlocked zone, and unlock the next zone.
-- Zone cards also show the biome's hazard.
-- Sky Lab look: one white row per destination with its icon in a well tinted with the zone's colour,
-- and a candy GO / UNLOCK button (a padlock while it's out of reach).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Hazards = require(Shared.Hazards)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI)
local Theme = require(script.Parent.Parent.Theme)
local Icons = require(script.Parent.Parent.Icons)

local Teleport = {}

local WHITE = Color3.new(1, 1, 1)
local WARNING = Theme.Sets.Sunset.Lip

local function travel(target: any)
	local result = Remotes.Teleport:InvokeServer(target)
	if result and result.Ok then
		Registry.InterfaceController.ClosePanel()
	elseif result then
		Registry.InterfaceController.Notify(result.Error, "Error")
	end
end

-- A light colour's darker shade, readable as text on white
local function readable(color: Color3): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, math.min(1, s * 1.1 + 0.1), math.min(v, 0.62))
end

local function row(parent: Instance, order: number, icon: string, color: Color3, name: string, height: number?)
	local holder = UI.Create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height or 74),
		LayoutOrder = order,
		Parent = parent,
	})
	local card = UI.CloudCard({ Name = "Card", Size = UDim2.new(1, -4, 1, -4), Position = UDim2.fromOffset(2, 2), Parent = holder })
	local well = UI.Create("Frame", {
		Name = "Well",
		BackgroundColor3 = WHITE,
		Size = UDim2.fromOffset(56, 56),
		Position = UDim2.fromOffset(7, 7),
		Parent = card,
		UI.Corner(14),
		UI.Gradient(color:Lerp(WHITE, 0.78), color:Lerp(WHITE, 0.45)),
	})
	Icons.New(icon, { Name = "Icon", Size = UDim2.fromOffset(44, 44), Parent = well })
	UI.Text({
		Name = "Title",
		Text = name,
		TextSize = 21,
		Scaled = true,
		MinTextSize = 12,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -250, 0, 24),
		Position = UDim2.fromOffset(76, 9),
		Parent = card,
	})
	local info = UI.Text({
		Name = "Info",
		Text = "",
		Font = Theme.BodyFont,
		TextSize = 13,
		Scaled = true,
		MinTextSize = 9,
		Color = Theme.InkSoft,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -250, 0, 17),
		Position = UDim2.fromOffset(76, 37),
		Parent = card,
	})
	return card, info
end

local function goButton(card: Instance, onClick: () -> ())
	return UI.Button({
		Name = "Go",
		Text = "GO",
		Icon = "Lock", -- shown while the zone is out of reach
		Color = "Sky",
		TextSize = 22,
		Size = UDim2.fromOffset(150, 50),
		Position = UDim2.new(1, -10, 0, 9),
		AnchorPoint = Vector2.new(1, 0),
		Parent = card,
		OnClick = onClick,
	})
end

function Teleport.Build()
	local window = UI.Window({
		Name = "Teleport",
		Title = "Teleport",
		Icon = "🗺️",
		Size = UDim2.fromOffset(640, 560),
		Padding = { 20, 16, 14 },
	})

	local list = UI.Scroll({
		Name = "List",
		Parent = window.Content,
		UI.List(Enum.FillDirection.Vertical, 8),
		UI.Padding(2, 10, 6, 0),
	})

	-- Fixed destinations
	local hubCard, hubInfo = row(list, 1, "Teleport", Zones.Hub.Color, Zones.Hub.Name)
	hubInfo.Text = "Upgrades, Climate Shifts, leaderboards and daily rewards"
	UI.SetButtonIcon(goButton(hubCard, function()
		travel("Hub")
	end), nil)

	local arenaCard, arenaInfo = row(list, 2, "MegaStorm", Theme.Sets.Storm.Top, "Mega Storm Arena")
	arenaInfo.Text = "Team up against the Mega Storm for big rewards"
	UI.SetButtonIcon(goButton(arenaCard, function()
		travel("Arena")
	end), nil)

	local zoneRows = {}
	for zoneId, zone in ipairs(Zones) do
		local card, info = row(list, 2 + zoneId, zone.Icon, zone.Color, zone.Name, if zone.Hazard then 98 else nil)
		local hazardLabel = nil
		if zone.Hazard then
			-- Hazard line: a pale chip in the hazard's colour
			local chip = UI.Create("Frame", {
				Name = "HazardChip",
				BackgroundColor3 = zone.Hazard.Color:Lerp(WHITE, 0.82),
				Size = UDim2.new(1, -86, 0, 24),
				Position = UDim2.fromOffset(74, 64),
				Parent = card,
				UI.Round(),
				UI.Stroke(2, zone.Hazard.Color:Lerp(WHITE, 0.55)),
			})
			hazardLabel = UI.Text({
				Name = "Hazard",
				Text = Hazards.Describe(zone.Hazard, nil),
				Font = Theme.BodyFont,
				TextSize = 13,
				Scaled = true,
				MinTextSize = 9,
				Color = readable(zone.Hazard.Color),
				X = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -20, 1, -6),
				Position = UDim2.new(0, 10, 0.5, 1),
				AnchorPoint = Vector2.new(0, 0.5),
				Parent = chip,
			})
		end
		local button = goButton(card, function()
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
		end)
		zoneRows[zoneId] = { Info = info, Button = button, Hazard = hazardLabel, Card = card }
	end

	local function refresh()
		local data = Registry.DataController.Data
		if not data then
			return
		end
		local power = Formulas.Power(data)
		for zoneId, zoneRow in zoneRows do
			local zone = Zones[zoneId]
			if zoneRow.Hazard then
				zoneRow.Hazard.Text = Hazards.Describe(zone.Hazard, data)
			end
			zoneRow.Card.BackgroundColor3 = if zoneId <= data.Zone + 1 then Theme.Cloud else Theme.Mist
			if zoneId <= data.Zone then
				if power >= zone.MinPower then
					zoneRow.Info.Text = "Unlocked  •  x" .. Format.Number(zone.Value) .. " Volts per energy"
					zoneRow.Info.TextColor3 = Theme.InkSoft
				else
					zoneRow.Info.Text = "Unlocked  •  Needs " .. Format.Number(zone.MinPower) .. " Power to catch here"
					zoneRow.Info.TextColor3 = WARNING
				end
				UI.SetButtonText(zoneRow.Button, "GO")
				UI.SetButtonIcon(zoneRow.Button, nil)
				UI.SetButtonColor(zoneRow.Button, "Sky")
			else
				zoneRow.Info.Text = string.format("Needs %s Volts and %s Power", Format.Number(zone.Cost), Format.Number(zone.MinPower))
				zoneRow.Info.TextColor3 = Theme.InkSoft
				if zoneId == data.Zone + 1 then
					local ready = data.Volts >= zone.Cost and power >= zone.MinPower
					UI.SetButtonText(zoneRow.Button, Format.Number(zone.Cost))
					UI.SetButtonIcon(zoneRow.Button, if ready then "Volts" else "Lock")
					UI.SetButtonColor(zoneRow.Button, if ready then "Leaf" else "Off")
				else
					UI.SetButtonText(zoneRow.Button, "Locked")
					UI.SetButtonIcon(zoneRow.Button, "Lock")
					UI.SetButtonColor(zoneRow.Button, "Off")
				end
			end
		end
	end

	Registry.DataController.ObserveMany({ "Zone", "Volts", "Upgrades" }, refresh)

	return { Window = window, OnOpen = refresh }
end

return Teleport
