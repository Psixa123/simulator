--!nonstrict
-- Egg panel: shows what an egg can hatch (with live chances) and handles
-- single, triple and automatic hatching.
-- Sky Lab look: the egg's pets on rarity pedestals with their chance under each, the cost and luck
-- in pills at the top, and candy hatch buttons with a price tag hanging over their corner.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Pets = require(Shared.Config.Pets)
local MapLayout = require(Shared.Config.MapLayout)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI)
local Theme = require(script.Parent.Parent.Theme)
local Icons = require(script.Parent.Parent.Icons)
local Viewport = require(script.Parent.Parent.Viewport)
local Secret = require(script.Parent.Parent.Secret)

local EggPanel = {}

-- What the PromptController (incubators open this panel when you walk up) reads: the egg shown and
-- whether a hatch (or auto hatching) is running. Build replaces these.
function EggPanel.CurrentEgg(): string?
	return nil
end

function EggPanel.IsBusy(): boolean
	return false
end

local INK = Theme.Ink
local WHITE = Color3.new(1, 1, 1)
local SETS = Theme.Sets
local player = Players.LocalPlayer

local TILE_WIDTH, TILE_HEIGHT = 112, 140
local COLUMN_HEIGHT = 196
local SECRET_HEIGHT = 74 -- the egg's secret pets strip under the regular pets
local SECRET_CARD_WIDTH = 158

-- Still at the egg's incubator (after a hatch the panel comes back): the PromptController's rule, the
-- one that opens and closes the panel as you walk up and away
local function nearEgg(eggId: string): boolean
	local prompts = Registry.PromptController
	if prompts and prompts.IsNearEgg then
		return prompts.IsNearEgg(eggId)
	end
	local egg = Pets.Eggs[eggId]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not egg or not root then
		return false
	end
	return (root.Position - MapLayout.EggStation(egg.Zone)).Magnitude <= GameConfig.Pets.HatchDistance
end

local function frame(props)
	local object = Instance.new("Frame")
	object.BorderSizePixel = 0
	object.BackgroundColor3 = WHITE
	for key, value in props do
		if type(key) == "number" then
			value.Parent = object
		elseif key ~= "Parent" then
			object[key] = value
		end
	end
	object.Parent = props.Parent
	return object
end

-- A white pill with a Haze outline, an icon over its left end and Fredoka text (rich text allowed)
local function infoPill(parent: Instance, name: string, order: number, icon: string)
	local pill = frame({
		Name = name,
		BackgroundColor3 = Theme.Cloud,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 36),
		LayoutOrder = order,
		Parent = parent,
		UI.Round(),
		UI.Stroke(2, Theme.Haze),
		UI.Padding(0, 16, 0, 42),
	})
	Icons.New(icon, { Name = "Icon", Size = UDim2.fromOffset(38, 38), Position = UDim2.new(0, -42 + 1, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 2, Parent = pill })
	local label = UI.Text({ Name = "Text", Text = "", Rich = true, TextSize = 19, Size = UDim2.fromOffset(0, 36), Position = UDim2.fromOffset(0, 1), Parent = pill })
	label.AutomaticSize = Enum.AutomaticSize.X
	return label
end

-- A Bolt price tag (Volts icon + amount) hanging over a button's top-right corner
local function priceTag(button: GuiObject)
	local z = button.ZIndex + 6
	local tag = frame({
		Name = "Price",
		BackgroundColor3 = INK,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 28),
		Position = UDim2.new(1, 8, 0, -14),
		AnchorPoint = Vector2.new(1, 0),
		ZIndex = z,
		Parent = button,
		UI.Round(),
		UI.Padding(0, 10, 0, 30),
	})
	frame({
		Name = "Fill",
		Size = UDim2.new(1, 36, 1, -4),
		Position = UDim2.new(0, -28, 0, 2),
		ZIndex = z,
		Parent = tag,
		UI.Round(),
		UI.Gradient(SETS.Bolt.Top, SETS.Bolt.Bottom),
	})
	Icons.New("Volts", { Name = "Icon", Size = UDim2.fromOffset(26, 26), Position = UDim2.new(0, -28, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = z + 1, Parent = tag })
	local label = UI.Text({ Name = "Text", Text = "", TextSize = 16, Stroke = SETS.Bolt.Stroke, Size = UDim2.fromOffset(0, 28), Position = UDim2.fromOffset(0, 1), ZIndex = z + 1, Parent = tag })
	label.AutomaticSize = Enum.AutomaticSize.X
	return tag, label
end

function EggPanel.Build()
	local window = UI.Window({
		Name = "Egg",
		Title = "Egg",
		IconKey = "Eggs",
		Size = UDim2.fromOffset(680, 474 + SECRET_HEIGHT + 8),
		Padding = { 20, 16, 18 },
	})
	local content = window.Content

	-- Cost and luck pills
	local info = frame({
		Name = "Info",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 38),
		Parent = content,
		UI.List(Enum.FillDirection.Horizontal, 22, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	local costLabel = infoPill(info, "Cost", 1, "Volts")
	local luckLabel = infoPill(info, "Luck", 2, "Luck")

	local grid = frame({
		Name = "Pets",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, COLUMN_HEIGHT),
		Position = UDim2.fromOffset(0, 50),
		Parent = content,
		UI.List(Enum.FillDirection.Horizontal, 14, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top),
	})

	-- Secret pets strip: a dark cosmic bar with a card per secret ("???" silhouette + odds until discovered)
	local secretStrip = frame({
		Name = "Secrets",
		Size = UDim2.new(1, -4, 0, SECRET_HEIGHT),
		Position = UDim2.fromOffset(2, 50 + COLUMN_HEIGHT + 6),
		Parent = content,
		UI.Corner(16),
		UI.Gradient(Secret.Top, Secret.Bottom),
	})
	local stripRim = UI.Stroke(3, Secret.Edge)
	stripRim.Parent = secretStrip
	Secret.Gradient(0).Parent = stripRim
	local secretTitle = UI.Text({
		Name = "Title",
		Text = "SECRET",
		TextSize = 24,
		Stroke = Color3.fromRGB(30, 14, 60),
		Size = UDim2.fromOffset(112, 30),
		Position = UDim2.fromOffset(10, 8),
		Parent = secretStrip,
	})
	Secret.Gradient(0).Parent = secretTitle
	UI.Text({
		Name = "Hint",
		Text = "✦ ultra rare ✦",
		Font = Theme.BodyFont,
		TextSize = 13,
		Color = Color3.fromRGB(210, 190, 255),
		Size = UDim2.fromOffset(112, 18),
		Position = UDim2.fromOffset(10, 40),
		Parent = secretStrip,
	})
	local secretRow = frame({
		Name = "Cards",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -136, 1, -12),
		Position = UDim2.fromOffset(128, 6),
		Parent = secretStrip,
		UI.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})

	local currentEgg: string? = nil
	local cards = {} -- [petId] = { Chance = TextLabel }
	local secretCards = {} -- [petId] = { Odds = TextLabel }
	local secretKey = "" -- which of the egg's secrets were discovered when the cards were built
	local busy = false
	local auto = false
	local hatchOne, hatchThree, autoButton
	local oneTagLabel, threeTag, threeTagLabel
	local stopButton: TextButton? = nil

	function EggPanel.CurrentEgg(): string?
		return currentEgg
	end
	function EggPanel.IsBusy(): boolean
		return busy
	end

	local function setAuto(enabled: boolean)
		auto = enabled
		if enabled and not stopButton then
			stopButton = UI.Button({
				Name = "StopAutoHatch",
				Text = "Stop Auto Hatch",
				Icon = "Close",
				Color = "Coral",
				TextSize = 24,
				Size = UDim2.fromOffset(300, 60),
				Position = UDim2.new(0.5, 0, 1, -40),
				AnchorPoint = Vector2.new(0.5, 1),
				ZIndex = 45,
				Parent = Registry.InterfaceController.OverlayRoot,
				OnClick = function()
					setAuto(false)
				end,
			})
		elseif not enabled and stopButton then
			stopButton:Destroy()
			stopButton = nil
		end
	end

	-- One card per secret pet of the egg: a silhouette and "???" until the player has hatched it
	local function buildSecrets(eggId: string)
		local egg = Pets.Eggs[eggId]
		local data = Registry.DataController.Data
		for _, child in secretRow:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		table.clear(secretCards)
		secretKey = ""
		for index, entry in egg.Secrets do
			local def = Pets.Pets[entry.Id]
			local discovered = data ~= nil and data.Index[entry.Id] == true
			secretKey ..= if discovered then "1" else "0"
			local card = frame({
				Name = entry.Id,
				BackgroundColor3 = Color3.fromRGB(22, 10, 48),
				BackgroundTransparency = 0.15,
				Size = UDim2.fromOffset(SECRET_CARD_WIDTH, SECRET_HEIGHT - 16),
				LayoutOrder = index,
				Parent = secretRow,
				UI.Corner(12),
				UI.Stroke(2, Color3.fromRGB(120, 80, 210)),
			})
			Viewport.Pet(entry.Id, false, {
				Parent = card,
				Silhouette = not discovered,
				Size = UDim2.fromOffset(62, 62),
				Position = UDim2.new(0, 2, 0.5, -3),
				AnchorPoint = Vector2.new(0, 0.5),
				ZIndex = card.ZIndex + 2,
			})
			if not discovered then
				UI.Text({
					Name = "Mystery",
					Text = "?",
					TextSize = 30,
					Stroke = Color3.fromRGB(30, 14, 60),
					Color = Color3.fromRGB(230, 210, 255),
					Size = UDim2.fromOffset(62, 58),
					Position = UDim2.fromOffset(2, 0),
					ZIndex = card.ZIndex + 4,
					Parent = card,
				})
			end
			UI.Text({
				Name = "Name",
				Text = if discovered then def.Name else "???",
				TextSize = 15,
				Scaled = true,
				Color = WHITE,
				X = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -72, 0, 18),
				Position = UDim2.fromOffset(68, 6),
				ZIndex = card.ZIndex + 1,
				Parent = card,
			})
			local odds = UI.Text({
				Name = "Odds",
				Text = Secret.OddsText(entry.Id),
				TextSize = 17,
				Color = Secret.Text,
				X = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -72, 0, 18),
				Position = UDim2.fromOffset(68, 24),
				ZIndex = card.ZIndex + 1,
				Parent = card,
			})
			UI.Text({
				Name = "Bonus",
				Text = Format.Bonus(def.Bonus) .. " Energy",
				Font = Theme.BodyFont,
				TextSize = 12,
				Color = Color3.fromRGB(130, 255, 170),
				X = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -72, 0, 14),
				Position = UDim2.fromOffset(68, 42),
				ZIndex = card.ZIndex + 1,
				Parent = card,
			})
			secretCards[entry.Id] = { Odds = odds }
		end
	end

	local function refresh()
		local data = Registry.DataController.Data
		local eggId = currentEgg
		local egg = eggId and Pets.Eggs[eggId]
		if not data or not eggId or not egg then
			return
		end
		local luck = Formulas.LuckMultiplier(data, Registry.DataController.Now())
		costLabel.Text = Format.Number(egg.Cost) .. ' <font color="#5B6A9E">each</font>'
		luckLabel.Text = '<font color="#5B6A9E">Luck</font> ' .. Format.Multiplier(luck)

		local key = ""
		for _, entry in egg.Secrets do
			key ..= if data.Index[entry.Id] then "1" else "0"
		end
		if key ~= secretKey then
			buildSecrets(eggId)
		end
		for _, entry in Formulas.HatchChances(eggId, luck) do
			local card = cards[entry.Id]
			local secretCard = secretCards[entry.Id]
			if card then
				card.Chance.Text = Format.Chance(entry.Chance)
			elseif secretCard then
				secretCard.Odds.Text = Secret.OddsText(entry.Id, entry.Chance)
			end
		end

		oneTagLabel.Text = Format.Number(egg.Cost)
		UI.SetButtonColor(hatchOne, if data.Volts >= egg.Cost then "Leaf" else "Off")

		if Formulas.HasPass(data, "TripleHatch") then
			threeTag.Visible = true
			threeTagLabel.Text = Format.Number(egg.Cost * 3)
			UI.SetButtonIcon(hatchThree, nil)
			UI.SetButtonColor(hatchThree, if data.Volts >= egg.Cost * 3 then "Sky" else "Off")
		else
			threeTag.Visible = false
			UI.SetButtonIcon(hatchThree, "Lock")
			UI.SetButtonColor(hatchThree, "Off")
		end

		local hasAuto = Formulas.HasPass(data, "AutoHatch")
		UI.SetButtonIcon(autoButton, if hasAuto then nil else "Lock")
		UI.SetButtonColor(autoButton, if hasAuto then "Storm" else "Off")
	end

	local function rebuild(eggId: string)
		local egg = Pets.Eggs[eggId]
		if not egg then
			return
		end
		currentEgg = eggId
		window.SetTitle(egg.Name)
		for _, child in grid:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		table.clear(cards)

		for index, entry in egg.Pets do
			local def = Pets.Pets[entry.Id]
			local rarity = Pets.Rarities[def.Rarity]
			local column = frame({
				Name = entry.Id,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(TILE_WIDTH, COLUMN_HEIGHT),
				LayoutOrder = index,
				Parent = grid,
			})
			local tile = UI.Tile({
				Name = "Tile",
				Title = def.Name,
				Rarity = rarity,
				RarityText = rarity.Name,
				Size = UDim2.fromOffset(TILE_WIDTH, TILE_HEIGHT),
				Parent = column,
			})
			Viewport.Pet(entry.Id, false, {
				Parent = tile.Art,
				Size = UDim2.fromScale(1.1, 1.1),
				Position = UDim2.fromScale(0.5, 0.52),
				AnchorPoint = Vector2.new(0.5, 0.5),
				ZIndex = tile.Frame.ZIndex + 3,
			})
			-- Chance pill and the pet's bonus under the tile
			local pill = frame({
				Name = "ChancePill",
				BackgroundColor3 = Theme.Cloud,
				Size = UDim2.new(1, -4, 0, 30),
				Position = UDim2.fromOffset(2, TILE_HEIGHT + 8),
				Parent = column,
				UI.Round(),
				UI.Stroke(2, Theme.Haze),
			})
			local chance = UI.Text({ Name = "Chance", Text = "", TextSize = 20, Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(0, 1), Parent = pill })
			UI.Text({
				Name = "Bonus",
				Text = Format.Bonus(def.Bonus) .. " Energy",
				Font = Theme.BodyFont,
				TextSize = 12,
				Color = Theme.Up,
				Size = UDim2.new(1, 0, 0, 14),
				Position = UDim2.fromOffset(0, TILE_HEIGHT + 44),
				Parent = column,
			})
			cards[entry.Id] = { Chance = chance }
		end
		buildSecrets(eggId)
		refresh()
	end

	-- Hatches once, or keeps hatching while auto mode is on
	local function hatch(count: number)
		if busy or not currentEgg then
			return
		end
		busy = true
		local eggId = currentEgg
		local failed = false
		repeat
			local result = Remotes.Hatch:InvokeServer(eggId, count)
			if not result or not result.Ok then
				failed = true
				setAuto(false)
				Registry.InterfaceController.Notify(result and result.Error or "The egg didn't hatch. Try again!", "Error")
				break
			end
			Registry.InterfaceController.ClosePanel(true)
			Registry.HatchOverlay.Play(result, { Hold = if auto then 1.1 else nil })
			if auto then
				task.wait(GameConfig.Pets.AutoHatchDelay)
			end
		until not auto
		busy = false
		if not failed and nearEgg(eggId) then
			Registry.InterfaceController.OpenPanel("Egg", eggId)
		end
	end

	-- Tip: crafting tiers
	local tip = frame({
		Name = "Tip",
		BackgroundColor3 = SETS.Bolt.Tint,
		Size = UDim2.new(1, -4, 0, 46),
		Position = UDim2.fromOffset(2, 50 + COLUMN_HEIGHT + SECRET_HEIGHT + 14),
		Parent = content,
		UI.Corner(14),
		UI.Stroke(2, SETS.Bolt.Tint2),
	})
	Icons.New("Star", { Name = "Icon", Size = UDim2.fromOffset(32, 32), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = tip })
	UI.Text({
		Name = "Text",
		Text = "Pets catch weather for you and multiply your energy! Craft 5 of a pet into a Golden one, and 5 Golden into a Rainbow one.",
		Font = Theme.BodyFont,
		TextSize = 13,
		Scaled = true,
		MinTextSize = 9,
		Wrapped = true,
		Color = Theme.InkSoft,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -62, 1, -8),
		Position = UDim2.new(0, 50, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = tip,
	})

	local buttonWidth = UDim2.new(1 / 3, -8, 0, 58)
	hatchOne = UI.Button({
		Name = "HatchOne",
		Text = "Hatch x1",
		Color = "Leaf",
		TextSize = 24,
		Size = buttonWidth,
		Position = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 1),
		Parent = content,
		OnClick = function()
			hatch(1)
		end,
	})
	hatchThree = UI.Button({
		Name = "HatchThree",
		Text = "Hatch x3",
		Icon = "Lock",
		Color = "Sky",
		TextSize = 24,
		Size = buttonWidth,
		Position = UDim2.fromScale(0.5, 1),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = content,
		OnClick = function()
			local data = Registry.DataController.Data
			if data and not Formulas.HasPass(data, "TripleHatch") then
				Registry.MonetizationController.PromptPass("TripleHatch")
				return
			end
			hatch(3)
		end,
	})
	autoButton = UI.Button({
		Name = "Auto",
		Text = "Auto Hatch",
		Icon = "Lock",
		Color = "Storm",
		TextSize = 24,
		Size = buttonWidth,
		Position = UDim2.fromScale(1, 1),
		AnchorPoint = Vector2.new(1, 1),
		Parent = content,
		OnClick = function()
			local data = Registry.DataController.Data
			if not data then
				return
			end
			if not Formulas.HasPass(data, "AutoHatch") then
				Registry.MonetizationController.PromptPass("AutoHatch")
				return
			end
			setAuto(true)
			hatch(if Formulas.HasPass(data, "TripleHatch") then 3 else 1)
		end,
	})
	_, oneTagLabel = priceTag(hatchOne)
	threeTag, threeTagLabel = priceTag(hatchThree)

	Registry.DataController.ObserveMany({ "Volts", "Passes", "Boosts", "Index" }, refresh)

	return {
		Window = window,
		OnOpen = function(eggId: string?)
			if eggId and eggId ~= currentEgg then
				rebuild(eggId)
			elseif not currentEgg then
				rebuild(Pets.EggOrder[1])
			else
				refresh()
			end
		end,
	}
end

return EggPanel
