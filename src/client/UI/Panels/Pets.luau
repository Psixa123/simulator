--!nonstrict
-- Pets panel: inventory (equip, golden/rainbow crafting, delete) and the pet index.
-- Sky Lab look: pets sit on rarity pedestals in white tiles (UI.Tile), the selected pet turns on a
-- pedestal in the detail pane, and every action is a candy button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Pets = require(Shared.Config.Pets)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)
local PetModels = require(Shared.Models.PetModels)

local Registry = require(script.Parent.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI)
local Theme = require(script.Parent.Parent.Theme)
local Icons = require(script.Parent.Parent.Icons)
local Viewport = require(script.Parent.Parent.Viewport)
local Confirm = require(script.Parent.Parent.Overlays.Confirm)

local PetsPanel = {}

local INK = Theme.Ink
local WHITE = Color3.new(1, 1, 1)
local SETS = Theme.Sets
local MAX_MULTI_DELETE = 100 -- the server refuses bigger "DeleteMany" requests

-- Layout (offset px in the window's content box, 640 x 486)
local TOP_BAR = 46 -- tabs + summary
local PAGE_Y = TOP_BAR + 12
local GRID_WIDTH = 420
local DETAIL_WIDTH = 208
local TILE = UDim2.fromOffset(94, 116)
local INDEX_TILE = UDim2.fromOffset(112, 140)

local function petAction(action: string, argument: any?)
	local result = Remotes.PetAction:InvokeServer(action, argument)
	if result and not result.Ok then
		Registry.InterfaceController.Notify(result.Error, "Error")
	end
	return result
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

local function rainbowGradient(parent: Instance): UIGradient
	return UI.Create("UIGradient", { Name = "Rainbow", Color = PetModels.RainbowSequence, Parent = parent })
end

-- A pill in a colour set (or rarity colours) with white text and a darker stroke
local function chip(parent: Instance, name: string, order: number)
	local holder = frame({
		Name = name,
		BackgroundColor3 = INK,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		LayoutOrder = order,
		ZIndex = 3,
		Parent = parent,
		UI.Round(),
		UI.Padding(0, 10, 0, 10),
	})
	local fill = frame({ Name = "Fill", Size = UDim2.new(1, 16, 1, -4), Position = UDim2.new(0, -8, 0, 2), ZIndex = 3, Parent = holder, UI.Round() })
	local gradient = UI.Gradient(WHITE, WHITE)
	gradient.Parent = fill
	local label = UI.Text({ Name = "Text", Text = "", TextSize = 14, Stroke = INK, StrokeThickness = 1.5, Size = UDim2.fromOffset(0, 24), Position = UDim2.fromOffset(0, 1), ZIndex = 4, Parent = holder })
	label.AutomaticSize = Enum.AutomaticSize.X
	local function set(text: string, top: Color3, bottom: Color3, edge: Color3)
		label.Text = text
		holder.BackgroundColor3 = edge
		gradient.Color = ColorSequence.new(top, bottom)
		label.TextStroke.Color = edge
	end
	return holder, set
end

-- Mini stat box (Mist, Haze outline): a small caption over a Fredoka value
local function statBox(parent: Instance, name: string, caption: string, position: UDim2, size: UDim2)
	local box = frame({
		Name = name,
		BackgroundColor3 = Theme.Mist,
		Size = size,
		Position = position,
		ZIndex = 2,
		Parent = parent,
		UI.Corner(12),
		UI.Stroke(2, Theme.Haze),
	})
	UI.Text({
		Name = "Caption",
		Text = caption,
		Font = Theme.BodyFont,
		TextSize = 10,
		Color = Theme.InkSoft,
		Size = UDim2.new(1, -6, 0, 12),
		Position = UDim2.new(0.5, 0, 0, 4),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 3,
		Parent = box,
	})
	local value = UI.Text({
		Name = "Value",
		Text = "",
		TextSize = 20,
		Scaled = true,
		Rich = true,
		Size = UDim2.new(1, -8, 0, 22),
		Position = UDim2.new(0.5, 0, 0, 18),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 3,
		Parent = box,
	})
	return box, value
end

-- A pale info box with an icon on the left and wrapped body text
local function infoBox(parent: Instance, name: string, setName: string, icon: string, position: UDim2, size: UDim2)
	local set = Theme.Set(setName)
	local box = frame({
		Name = name,
		BackgroundColor3 = set.Tint,
		Size = size,
		Position = position,
		ZIndex = 2,
		Parent = parent,
		UI.Corner(14),
		UI.Stroke(2, set.Tint2),
	})
	Icons.New(icon, { Name = "Icon", Size = UDim2.fromOffset(34, 34), Position = UDim2.new(0, 8, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 3, Parent = box })
	local label = UI.Text({
		Name = "Text",
		Text = "",
		Font = Theme.BodyFont,
		TextSize = 13,
		Scaled = true,
		MinTextSize = 9,
		Wrapped = true,
		Color = Theme.InkSoft,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -56, 1, -12),
		Position = UDim2.new(0, 48, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 3,
		Parent = box,
	})
	return box, label
end

function PetsPanel.Build()
	local window = UI.Window({
		Name = "Pets",
		Title = "Pets",
		Icon = "🐾",
		Size = UDim2.fromOffset(680, 580),
		Padding = { 20, 16, 18 },
	})
	local content = window.Content

	local inventoryPage = frame({
		Name = "Inventory",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -PAGE_Y),
		Position = UDim2.fromOffset(0, PAGE_Y),
		Parent = content,
	})
	local indexPage = frame({
		Name = "Index",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -PAGE_Y),
		Position = UDim2.fromOffset(0, PAGE_Y),
		Visible = false,
		Parent = content,
	})

	-- "Equipped 4/4 • Storage 15/60 • x8 Energy" on the right of the tabs
	local summary = UI.Text({
		Name = "Summary",
		Text = "",
		Rich = true,
		TextSize = 17,
		Scaled = true,
		Color = Theme.InkSoft,
		X = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, -300, 0, 24),
		Position = UDim2.new(1, -4, 0, TOP_BAR / 2 + 1),
		AnchorPoint = Vector2.new(1, 0.5),
		Parent = content,
	})

	---------------------------------------------------------------------
	-- Inventory
	---------------------------------------------------------------------
	local grid = UI.Scroll({
		Name = "Grid",
		Size = UDim2.new(0, GRID_WIDTH, 1, -58),
		Parent = inventoryPage,
		UI.Grid(TILE, UDim2.fromOffset(8, 8)),
		UI.Padding(10, 10, 8, 8), -- room for the lifted tile and the badges over its corners
	})
	grid.UIGridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	-- Empty inventory: a faded paw and a hint where the tiles would be
	local emptyHint = frame({
		Name = "Empty",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, GRID_WIDTH - 40, 0, 200),
		Position = UDim2.new(0, GRID_WIDTH / 2, 0.42, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		Parent = inventoryPage,
	})
	Icons.New("Pets", { Name = "Icon", Size = UDim2.fromOffset(84, 84), Position = UDim2.new(0.5, 0, 0, 42), Transparency = 0.35, Parent = emptyHint })
	UI.Text({ Name = "Title", Text = "No pets yet!", TextSize = 26, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 94), Parent = emptyHint })
	UI.Text({
		Name = "Text",
		Text = "Hatch an egg in any zone to get your first Stormling. Pets catch weather for you!",
		Font = Theme.BodyFont,
		TextSize = 15,
		Wrapped = true,
		Color = Theme.InkSoft,
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.fromOffset(0, 130),
		Parent = emptyHint,
	})

	-- Bottom row under the grid
	local function rowButton(props)
		props.Size = UDim2.fromOffset(props.Width, 46)
		props.Position = UDim2.new(0, props.X, 1, 0)
		props.AnchorPoint = Vector2.new(0, 1)
		props.TextSize = 18
		props.Parent = inventoryPage
		return UI.Button(props)
	end
	rowButton({
		Name = "EquipBest",
		Text = "Equip Best",
		Icon = "Star",
		Color = "Leaf",
		Width = 144,
		X = 0,
		OnClick = function()
			petAction("EquipBest")
		end,
	})
	rowButton({
		Name = "UnequipAll",
		Text = "Unequip All",
		Color = "Sky",
		Width = 132,
		X = 152,
		OnClick = function()
			petAction("UnequipAll")
		end,
	})
	local multiButton = rowButton({ Name = "DeleteMany", Text = "Delete Many", Color = "Coral", Width = 128, X = GRID_WIDTH - 128 })

	-- Detail pane
	local detail = UI.CloudCard({
		Name = "Detail",
		Size = UDim2.new(0, DETAIL_WIDTH - 4, 1, -4),
		Position = UDim2.new(1, -2, 0, 2),
		AnchorPoint = Vector2.new(1, 0),
		Parent = inventoryPage,
	})
	local innerWidth = DETAIL_WIDTH - 4

	-- Stage: a soft rarity-tinted backdrop with the pet turning on a pedestal
	local stage = frame({
		Name = "Stage",
		Size = UDim2.new(1, -14, 0, 150),
		Position = UDim2.fromOffset(7, 7),
		ZIndex = 2,
		Parent = detail,
		UI.Corner(14),
	})
	local stageGradient = UI.Gradient(Theme.Mist, Theme.Haze)
	stageGradient.Parent = stage
	local pedestal = frame({
		Name = "Pedestal",
		Size = UDim2.fromOffset(132, 32),
		Position = UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = 3,
		Parent = stage,
		UI.Round(),
	})
	local pedestalFace = frame({ Name = "Face", Size = UDim2.new(1, -4, 1, -4), Position = UDim2.fromOffset(2, 2), ZIndex = 3, Parent = pedestal, UI.Round() })
	local pedestalGradient = UI.Gradient(WHITE, WHITE)
	pedestalGradient.Parent = pedestalFace
	frame({ Name = "Gloss", BackgroundTransparency = 0.5, Size = UDim2.new(1, -30, 0, 9), Position = UDim2.fromOffset(15, 2), ZIndex = 3, Parent = pedestalFace, UI.Round() })
	local viewHolder = frame({
		Name = "View",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(142, 142),
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 4,
		Parent = stage,
	})
	local placeholder = Icons.New("Pets", { Name = "Placeholder", Size = UDim2.fromOffset(70, 70), Position = UDim2.new(0.5, 0, 0, 62), Transparency = 0.45, ZIndex = 4, Parent = stage })

	local nameLabel = UI.Text({
		Name = "PetName",
		Text = "",
		TextSize = 22,
		Scaled = true,
		MinTextSize = 12,
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.fromOffset(8, 163),
		ZIndex = 3,
		Parent = detail,
	})
	local nameStroke = UI.TextStroke(2, INK)
	nameStroke.Parent = nameLabel
	local nameGradient = rainbowGradient(nameLabel)

	local chips = frame({
		Name = "Chips",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -12, 0, 24),
		Position = UDim2.fromOffset(6, 192),
		ZIndex = 3,
		Parent = detail,
		UI.List(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	local _, setRarityChip = chip(chips, "Rarity", 1)
	local tierChip, setTierChip = chip(chips, "Tier", 2)

	local half = math.floor((innerWidth - 14 - 6) / 2)
	local bonusBox, bonusValue = statBox(detail, "Bonus", "ENERGY", UDim2.fromOffset(7, 224), UDim2.fromOffset(half, 46))
	local catchBox, catchValue = statBox(detail, "Catch", "AUTO-CATCH", UDim2.fromOffset(7 + half + 6, 224), UDim2.fromOffset(half, 46))

	local selectHint = UI.Text({
		Name = "SelectHint",
		Text = "Select a pet to see its details",
		TextSize = 19,
		Wrapped = true,
		Size = UDim2.new(1, -24, 0, 50),
		Position = UDim2.fromOffset(12, 196),
		ZIndex = 3,
		Parent = detail,
	})
	local catchTipBox, catchTip = infoBox(detail, "CatchTip", "Sky", "MegaStorm", UDim2.new(0, 9, 1, -9), UDim2.new(1, -18, 0, 84))
	catchTipBox.AnchorPoint = Vector2.new(0, 1)

	-- Multi-delete mode: tap several unequipped pets, then delete them with one confirm
	local multiPanel = frame({
		Name = "Multi",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 2,
		Parent = detail,
	})
	UI.Text({ Name = "Title", Text = "Delete Many", TextSize = 24, Size = UDim2.new(1, -16, 0, 28), Position = UDim2.fromOffset(8, 12), ZIndex = 3, Parent = multiPanel })
	UI.Text({
		Name = "Help",
		Text = "Tap the pets you want to delete. Equipped and exclusive pets are kept safe.",
		Font = Theme.BodyFont,
		TextSize = 13,
		Wrapped = true,
		Color = Theme.InkSoft,
		Size = UDim2.new(1, -24, 0, 54),
		Position = UDim2.fromOffset(12, 44),
		ZIndex = 3,
		Parent = multiPanel,
	})
	local countBox = frame({
		Name = "CountBox",
		BackgroundColor3 = SETS.Coral.Tint,
		Size = UDim2.new(1, -18, 0, 58),
		Position = UDim2.fromOffset(9, 104),
		ZIndex = 3,
		Parent = multiPanel,
		UI.Corner(14),
		UI.Stroke(2, SETS.Coral.Tint2),
	})
	local multiCount = UI.Text({ Name = "Count", Text = "0", TextSize = 30, Color = SETS.Coral.Lip, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 5), ZIndex = 4, Parent = countBox })
	local multiCaption = UI.Text({
		Name = "Caption",
		Text = "pets selected",
		Font = Theme.BodyFont,
		TextSize = 12,
		Color = SETS.Coral.Stroke,
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.fromOffset(0, 36),
		ZIndex = 4,
		Parent = countBox,
	})

	local slots = {} -- [uid] = slot
	local selectedUid: string? = nil
	local detailView = nil
	local detailKey = nil
	local equipButton, goldenButton, rainbowButton, deleteButton
	local topTier
	local multiMode = false
	local marked = {} -- [uid] = true, pets picked for deletion
	local markedCount = 0
	local multiDeleteButton

	local function findPet(uid: string?)
		local data = Registry.DataController.Data
		if not data or not uid then
			return nil
		end
		for _, pet in data.Pets do
			if pet.Uid == uid then
				return pet
			end
		end
		return nil
	end

	-- How many copies of a pet the player owns in one tier ("Normal" / "Golden" / "Rainbow")
	local function countCopies(petId: string, tier: string): number
		local data = Registry.DataController.Data
		local count = 0
		for _, pet in data.Pets do
			if pet.Id == petId and Pets.TierOf(pet) == tier then
				count += 1
			end
		end
		return count
	end

	-- Why a pet can't be picked for multi-delete (nil = it can). Same rule as the server.
	local function keepReason(pet): string?
		if pet.Equipped then
			return "Unequip " .. Pets.DisplayName(pet.Id, Pets.TierOf(pet)) .. " first!"
		end
		local def = Pets.Pets[pet.Id]
		if not def or not def.Egg then
			return "Exclusive pets can only be deleted one at a time."
		end
		return nil
	end

	-- Tile outline / cover for the slot's state (selected, picked for deletion, rainbow shimmer)
	local function paintSlot(slot, selected: boolean, isMarked: boolean)
		slot.Tile.SetSelected(selected or isMarked)
		local outline = slot.Tile.Outline
		if isMarked then
			outline.Color = SETS.Coral.Bottom
		elseif slot.Shimmer and not selected then
			outline.Color = WHITE
			outline.Thickness = 3
		end
		if slot.Shimmer then
			slot.Shimmer.Enabled = not selected and not isMarked
		end
		slot.Mark.Visible = isMarked
	end

	local function refreshDetail()
		local pet = if multiMode then nil else findPet(selectedUid)
		local hasPet = pet ~= nil
		local tier = if pet then Pets.TierOf(pet) else "Normal"
		nameLabel.Visible = hasPet
		chips.Visible = hasPet
		bonusBox.Visible = hasPet
		catchBox.Visible = hasPet
		equipButton.Visible = hasPet
		goldenButton.Visible = hasPet and tier == "Normal"
		rainbowButton.Visible = hasPet and tier == "Golden"
		if topTier then
			topTier.Visible = hasPet and tier == "Rainbow"
		end
		deleteButton.Visible = hasPet
		selectHint.Visible = not hasPet and not multiMode
		catchTipBox.Visible = not hasPet and not multiMode
		stage.Visible = not multiMode
		placeholder.Visible = not hasPet
		pedestal.Visible = hasPet
		multiPanel.Visible = multiMode

		markedCount = 0
		for uid, slot in slots do
			local isMarked = multiMode and marked[uid] == true
			if isMarked then
				markedCount += 1
			end
			paintSlot(slot, not multiMode and uid == selectedUid, isMarked)
		end
		if multiMode then
			multiCount.Text = tostring(markedCount)
			multiCaption.Text = if markedCount == 1 then "pet selected" else "pets selected"
			UI.SetButtonText(multiDeleteButton, "Delete " .. markedCount)
			UI.SetButtonColor(multiDeleteButton, if markedCount > 0 then "Coral" else "Off")
		end

		if not pet then
			stageGradient.Color = ColorSequence.new(Theme.Mist, Theme.Haze)
			if detailView then
				detailView.Destroy()
				detailView = nil
				detailKey = nil
			end
			return
		end

		local def = Pets.Pets[pet.Id]
		local rarity = Pets.Rarities[def.Rarity]
		local colors = Theme.Rarity(rarity.Color)
		local key = pet.Id .. ":" .. tier
		if key ~= detailKey then
			if detailView then
				detailView.Destroy()
			end
			detailView = Viewport.Pet(pet.Id, tier, { Parent = viewHolder, Zoom = 1.2, ZIndex = 4 })
			detailKey = key
		end

		-- Stage and pedestal in the pet's rarity colours
		stageGradient.Color = ColorSequence.new(colors.Top:Lerp(WHITE, 0.75), colors.Top:Lerp(WHITE, 0.35))
		pedestal.BackgroundColor3 = colors.Edge
		pedestalGradient.Color = ColorSequence.new(colors.Top, colors.Bottom)

		nameLabel.Text = Pets.DisplayName(pet.Id, tier)
		nameGradient.Enabled = tier == "Rainbow"
		if tier == "Golden" then
			nameLabel.TextColor3 = SETS.Bolt.Top
			nameStroke.Color = SETS.Bolt.Stroke
			nameStroke.Enabled = true
		elseif tier == "Rainbow" then
			nameLabel.TextColor3 = WHITE
			nameStroke.Color = INK
			nameStroke.Enabled = true
		else
			nameLabel.TextColor3 = INK
			nameStroke.Enabled = false
		end
		setRarityChip(rarity.Name, colors.Top, colors.Bottom, colors.Edge)
		tierChip.Visible = tier ~= "Normal"
		if tier == "Golden" then
			setTierChip("Golden", SETS.Bolt.Top, SETS.Bolt.Bottom, SETS.Bolt.Stroke)
		elseif tier == "Rainbow" then
			setTierChip("Rainbow", SETS.Pink.Top, SETS.Storm.Bottom, SETS.Storm.Stroke)
		end
		bonusValue.Text = Format.Bonus(Formulas.PetBonus(pet.Id, tier))
		bonusValue.TextColor3 = Theme.Up
		catchValue.Text = Format.Chance(Formulas.PetCatchShare(tier)) .. ' <font face="GothamBold" size="11" color="#5B6A9E">Power</font>'

		UI.SetButtonText(equipButton, if pet.Equipped then "Unequip" else "Equip")
		UI.SetButtonColor(equipButton, if pet.Equipped then "Off" else "Leaf")
		UI.SetButtonIcon(equipButton, if pet.Equipped then nil else "Check")

		local copies = countCopies(pet.Id, "Normal")
		local required = GameConfig.Pets.GoldenRequirement
		UI.SetButtonText(goldenButton, string.format("Golden %d/%d", math.min(copies, required), required))
		UI.SetButtonColor(goldenButton, if copies >= required then "Bolt" else "Off")
		UI.SetButtonIcon(goldenButton, if copies >= required then "Star" else "Lock")

		local goldenCopies = countCopies(pet.Id, "Golden")
		local rainbowRequired = GameConfig.Pets.RainbowRequirement
		UI.SetButtonText(rainbowButton, string.format("Rainbow %d/%d", math.min(goldenCopies, rainbowRequired), rainbowRequired))
		UI.SetButtonColor(rainbowButton, if goldenCopies >= rainbowRequired then "Pink" else "Off")
		UI.SetButtonIcon(rainbowButton, if goldenCopies >= rainbowRequired then "Rainbow" else "Lock")
	end

	local function select(uid: string?)
		selectedUid = uid
		refreshDetail()
	end

	local function setMultiMode(enabled: boolean)
		multiMode = enabled
		table.clear(marked)
		UI.SetButtonText(multiButton, if enabled then "Cancel" else "Delete Many")
		UI.SetButtonColor(multiButton, if enabled then "Off" else "Coral")
		refreshDetail()
	end

	local function toggleMark(uid: string)
		if marked[uid] then
			marked[uid] = nil
			refreshDetail()
			return
		end
		local pet = findPet(uid)
		if not pet then
			return
		end
		local reason = keepReason(pet)
		if reason then
			Registry.InterfaceController.Notify(reason, "Error")
			return
		end
		if markedCount >= MAX_MULTI_DELETE then
			Registry.InterfaceController.Notify("You can delete up to " .. MAX_MULTI_DELETE .. " pets at once.", "Error")
			return
		end
		marked[uid] = true
		refreshDetail()
	end

	multiButton.Activated:Connect(function()
		setMultiMode(not multiMode)
	end)

	UI.Button({
		Name = "PickCommons",
		Text = "Pick Commons\n& Uncommons",
		Color = "Sky",
		TextSize = 17,
		Size = UDim2.new(1, -18, 0, 54),
		Position = UDim2.fromOffset(9, 172),
		ZIndex = 3,
		Parent = multiPanel,
		OnClick = function()
			local data = Registry.DataController.Data
			if not data then
				return
			end
			local count, picked = markedCount, 0
			for _, pet in data.Pets do
				local rarity = Pets.RarityOf(pet.Id)
				if count < MAX_MULTI_DELETE and not marked[pet.Uid] and not keepReason(pet) and Pets.TierOf(pet) == "Normal" and rarity and rarity.Order <= 2 then
					marked[pet.Uid] = true
					count += 1
					picked += 1
				end
			end
			if picked == 0 then
				Registry.InterfaceController.Notify("No more unequipped Common or Uncommon pets to pick.", "Info")
			end
			refreshDetail()
		end,
	})
	UI.Button({
		Name = "Clear",
		Text = "Clear Selection",
		Color = "Off",
		TextSize = 17,
		Size = UDim2.new(1, -18, 0, 42),
		Position = UDim2.fromOffset(9, 234),
		ZIndex = 3,
		Parent = multiPanel,
		OnClick = function()
			table.clear(marked)
			refreshDetail()
		end,
	})
	multiDeleteButton = UI.Button({
		Name = "DeleteSelected",
		Text = "Delete 0",
		Color = "Off",
		TextSize = 22,
		Size = UDim2.new(1, -18, 0, 50),
		Position = UDim2.new(0, 9, 1, -9),
		AnchorPoint = Vector2.new(0, 1),
		ZIndex = 3,
		Parent = multiPanel,
		OnClick = function()
			local uids = {}
			for uid in marked do
				table.insert(uids, uid)
			end
			if #uids == 0 then
				Registry.InterfaceController.Notify("Tap the pets you want to delete first!", "Error")
				return
			end
			local amount = #uids .. (if #uids == 1 then " pet" else " pets")
			Confirm.Show({
				Title = "Delete " .. amount .. "?",
				Text = "Delete " .. amount .. " forever?\nThis can't be undone.",
				ConfirmText = "Delete",
				Color = "Red",
				OnConfirm = function()
					local result = petAction("DeleteMany", uids)
					if result and result.Ok then
						Registry.InterfaceController.Notify("🗑️ Deleted " .. (result.Count or #uids) .. (if result.Count == 1 then " pet" else " pets"), "Success")
						setMultiMode(false)
					end
				end,
			})
		end,
	})

	equipButton = UI.Button({
		Name = "Equip",
		Text = "Equip",
		Icon = "Check", -- hidden while it says "Unequip"
		Color = "Leaf",
		TextSize = 22,
		Size = UDim2.new(1, -14, 0, 48),
		Position = UDim2.fromOffset(7, 278),
		ZIndex = 3,
		Parent = detail,
		OnClick = function()
			local pet = findPet(selectedUid)
			if pet then
				petAction(if pet.Equipped then "Unequip" else "Equip", pet.Uid)
			end
		end,
	})
	-- tier = "Golden" (from 5 normal copies) or "Rainbow" (from 5 golden copies)
	local function craft(tier: string)
		local pet = findPet(selectedUid)
		if not pet then
			return
		end
		local def = Pets.Pets[pet.Id]
		local rainbow = tier == "Rainbow"
		local required = if rainbow then GameConfig.Pets.RainbowRequirement else GameConfig.Pets.GoldenRequirement
		if countCopies(pet.Id, if rainbow then "Golden" else "Normal") < required then
			local message = if rainbow then "You need %d Golden %s to craft a rainbow one! 🌈" else "You need %d %s to craft a golden one!"
			Registry.InterfaceController.Notify(string.format(message, required, def.Name), "Error")
			return
		end
		local result = petAction(tier, pet.Id)
		if result and result.Ok then
			selectedUid = result.Uid
			Registry.SoundController.Play("Success", if rainbow then 1.25 else 1.15)
			Registry.EffectsController.Confetti(if rainbow then 110 else 60)
			Registry.InterfaceController.Notify(
				string.format(
					"%s %s created! (%s bonus)",
					Pets.Tiers[tier].Icon,
					Pets.DisplayName(pet.Id, tier),
					Format.Multiplier(Formulas.TierMultiplier(tier))
				),
				"Reward"
			)
			refreshDetail()
		end
	end

	goldenButton = UI.Button({
		Name = "Golden",
		Text = "Golden",
		Icon = "Star",
		Color = "Bolt",
		TextSize = 18,
		Size = UDim2.new(1, -14, 0, 44),
		Position = UDim2.fromOffset(7, 332),
		ZIndex = 3,
		Parent = detail,
		OnClick = function()
			craft("Golden")
		end,
	})
	rainbowButton = UI.Button({
		Name = "Rainbow",
		Text = "Rainbow",
		Icon = "Rainbow",
		Color = "Pink",
		TextSize = 18,
		Size = UDim2.new(1, -14, 0, 44),
		Position = UDim2.fromOffset(7, 332),
		ZIndex = 3,
		Parent = detail,
		OnClick = function()
			craft("Rainbow")
		end,
	})
	-- Rainbow is the top tier: a note where the craft button would be
	topTier = frame({
		Name = "TopTier",
		BackgroundColor3 = SETS.Pink.Tint,
		Size = UDim2.new(1, -14, 0, 44),
		Position = UDim2.fromOffset(7, 332),
		Visible = false,
		ZIndex = 3,
		Parent = detail,
		UI.Corner(14),
		UI.Stroke(2, SETS.Pink.Tint2),
	})
	Icons.New("Rainbow", { Name = "Icon", Size = UDim2.fromOffset(34, 34), Position = UDim2.new(0, 8, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 4, Parent = topTier })
	UI.Text({
		Name = "Text",
		Text = "Top tier reached!",
		TextSize = 16,
		Scaled = true,
		MinTextSize = 10,
		Color = SETS.Pink.Lip,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -56, 1, -8),
		Position = UDim2.new(0, 48, 0.5, 1),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 4,
		Parent = topTier,
	})

	deleteButton = UI.Button({
		Name = "Delete",
		Text = "Delete",
		Color = "Coral",
		Small = true,
		TextSize = 17,
		Size = UDim2.new(1, -14, 0, 36),
		Position = UDim2.new(0, 7, 1, -8),
		AnchorPoint = Vector2.new(0, 1),
		ZIndex = 3,
		Parent = detail,
		OnClick = function()
			local pet = findPet(selectedUid)
			if not pet then
				return
			end
			Confirm.Show({
				Title = "Delete pet?",
				Text = "Delete " .. Pets.DisplayName(pet.Id, Pets.TierOf(pet)) .. " forever?\nThis can't be undone.",
				ConfirmText = "Delete",
				Color = "Red",
				OnConfirm = function()
					petAction("Delete", pet.Uid)
				end,
			})
		end,
	})

	local function createSlot(pet)
		local def = Pets.Pets[pet.Id] or Pets.Pets.Puffling
		local rarity = Pets.Rarities[def.Rarity]
		local tier = Pets.TierOf(pet)
		local tile = UI.Tile({
			Name = pet.Uid,
			Title = def.Name,
			Rarity = rarity,
			RarityText = Format.Bonus(Formulas.PetBonus(pet.Id, tier)),
			Parent = grid,
			OnClick = function()
				if multiMode then
					toggleMark(pet.Uid)
				else
					select(pet.Uid)
				end
			end,
		})
		local z = tile.Frame.ZIndex
		-- a little bigger than the art box, so the pet fills the tile and stands on the pedestal
		Viewport.Pet(pet.Id, tier, {
			Parent = tile.Art,
			Size = UDim2.fromScale(1.22, 1.22),
			Position = UDim2.fromScale(0.5, 0.56),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = z + 3,
		})

		-- Golden pets get a warm tile, rainbow ones a pastel tile with a shimmering rainbow outline
		local shimmer = nil
		if tier == "Golden" then
			UI.Gradient(SETS.Bolt.Tint, SETS.Bolt.Tint2).Parent = tile.Body
		elseif tier == "Rainbow" then
			UI.Gradient(SETS.Storm.Tint, SETS.Pink.Tint2).Parent = tile.Body
			shimmer = rainbowGradient(tile.Outline)
		end
		if tier ~= "Normal" then
			Icons.New(if tier == "Golden" then "Star" else "Rainbow", {
				Name = tier,
				Size = UDim2.fromOffset(26, 26),
				Position = UDim2.new(1, 5, 0, -6),
				AnchorPoint = Vector2.new(1, 0),
				ZIndex = z + 6,
				Parent = tile.Lift,
			})
		end
		local equipped = Icons.New("Check", {
			Name = "Equipped",
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.fromOffset(-7, -7),
			AnchorPoint = Vector2.zero,
			Visible = pet.Equipped,
			ZIndex = z + 6,
			Parent = tile.Lift,
		})
		-- Coral cover while the pet is picked for multi-delete
		local mark = frame({
			Name = "Mark",
			BackgroundColor3 = SETS.Coral.Top,
			BackgroundTransparency = 0.45,
			Size = UDim2.new(1, -4, 1, -4),
			Position = UDim2.fromOffset(2, 2),
			Visible = false,
			ZIndex = z + 7,
			Parent = tile.Lift,
			UI.Corner(16),
		})
		Icons.New("Close", { Name = "Icon", Size = UDim2.fromOffset(40, 40), Position = UDim2.fromScale(0.5, 0.45), ZIndex = z + 8, Parent = mark })

		return { Button = tile.Frame, Tile = tile, Equipped = equipped, Shimmer = shimmer, Mark = mark }
	end

	local function refreshInventory()
		local data = Registry.DataController.Data
		if not data then
			return
		end
		local sorted = table.clone(data.Pets)
		table.sort(sorted, function(a, b)
			if a.Equipped ~= b.Equipped then
				return a.Equipped
			end
			local bonusA = Formulas.PetBonus(a.Id, Pets.TierOf(a))
			local bonusB = Formulas.PetBonus(b.Id, Pets.TierOf(b))
			if bonusA ~= bonusB then
				return bonusA > bonusB
			end
			return a.Uid < b.Uid
		end)

		local seen = {}
		for order, pet in sorted do
			seen[pet.Uid] = true
			local slot = slots[pet.Uid]
			if not slot then
				slot = createSlot(pet)
				slots[pet.Uid] = slot
			end
			slot.Button.LayoutOrder = order
			slot.Equipped.Visible = pet.Equipped
		end
		for uid, slot in slots do
			if not seen[uid] then
				slot.Button:Destroy()
				slots[uid] = nil
			end
		end
		if selectedUid and not seen[selectedUid] then
			selectedUid = nil
		end
		-- Deleted, crafted or newly equipped pets drop out of the multi-delete pick
		for uid in table.clone(marked) do
			local pet = findPet(uid)
			if not pet or keepReason(pet) then
				marked[uid] = nil
			end
		end

		emptyHint.Visible = #sorted == 0
		local function part(label: string, value: string)
			return label .. ' <font color="#233066">' .. value .. "</font>"
		end
		summary.Text = table.concat({
			part("Equipped", Formulas.EquippedCount(data) .. "/" .. Formulas.EquipSlots(data)),
			part("Storage", #data.Pets .. "/" .. GameConfig.Pets.MaxStorage),
			part("Energy", Format.Multiplier(Formulas.PetMultiplier(data))),
		}, "  •  ")
		local catchShare = Formulas.PetCatchPower(data) / math.max(1, Formulas.Power(data))
		catchTip.Text = if catchShare > 0
			then "Your equipped pets catch weather for you with +" .. Format.Chance(catchShare) .. " Power!"
			else "Equip pets and they'll catch weather for you!"
		refreshDetail()
	end

	---------------------------------------------------------------------
	-- Index
	---------------------------------------------------------------------
	local indexCount = UI.ProgressBar({
		Name = "Count",
		Color = "Sky",
		Size = UDim2.new(1, -8, 0, 32),
		Position = UDim2.fromOffset(4, 0),
		MaxTextSize = 18,
		Parent = indexPage,
	})
	local indexGrid = UI.Scroll({
		Name = "Grid",
		Size = UDim2.new(1, 0, 1, -42),
		Position = UDim2.fromOffset(0, 42),
		Parent = indexPage,
		UI.Grid(INDEX_TILE, UDim2.fromOffset(10, 10)),
		UI.Padding(10, 10, 8, 4),
	})
	local indexSlots = {} -- [petId] = { Frame, Discovered }

	-- Tapping a pet in the index says where it comes from
	local function describe(petId: string, discovered: boolean)
		local def = Pets.Pets[petId]
		local rarity = Pets.Rarities[def.Rarity]
		local source = def.Source or (def.Egg and Pets.Eggs[def.Egg] and ("Hatch it from the " .. Pets.Eggs[def.Egg].Name)) or ""
		local name = if discovered then def.Name else "???"
		local parts = { name, rarity.Name }
		if discovered then
			table.insert(parts, Format.Bonus(def.Bonus) .. " Energy")
		end
		if source ~= "" then
			table.insert(parts, source)
		end
		Registry.InterfaceController.Notify(table.concat(parts, "  •  "), "Info")
	end

	local function buildIndexSlot(petId: string, order: number, discovered: boolean)
		local def = Pets.Pets[petId]
		local rarity = Pets.Rarities[def.Rarity]
		local tile = UI.Tile({
			Name = petId,
			Title = if discovered then def.Name else "???",
			Rarity = rarity,
			RarityText = rarity.Name,
			LayoutOrder = order,
			Parent = indexGrid,
			OnClick = function()
				describe(petId, discovered)
			end,
		})
		Viewport.Pet(petId, false, {
			Parent = tile.Art,
			Silhouette = not discovered,
			ZIndex = tile.Frame.ZIndex + 3,
		})
		if not discovered then
			tile.Body.BackgroundColor3 = Theme.Mist
			tile.Title.TextColor3 = Theme.InkSoft
		end
		return tile.Frame
	end

	local function refreshIndex()
		local data = Registry.DataController.Data
		if not data or not indexPage.Visible then
			return
		end
		local discoveredCount = 0
		for order, petId in Pets.IndexOrder do
			local discovered = data.Index[petId] == true
			if discovered then
				discoveredCount += 1
			end
			local slot = indexSlots[petId]
			if not slot or slot.Discovered ~= discovered then
				if slot then
					slot.Frame:Destroy()
				end
				indexSlots[petId] = { Frame = buildIndexSlot(petId, order, discovered), Discovered = discovered }
			end
		end
		indexCount.Set(
			discoveredCount / math.max(1, #Pets.IndexOrder),
			string.format("Discovered %d / %d Stormlings", discoveredCount, #Pets.IndexOrder)
		)
	end

	local tabs = UI.Tabs({
		Tabs = {
			{ Key = "Inventory", Text = "Inventory" },
			{ Key = "Index", Text = "Index" },
		},
		TabWidth = 136,
		Size = UDim2.new(0, 0, 0, TOP_BAR),
		Parent = content,
		OnSelect = function(key)
			inventoryPage.Visible = key == "Inventory"
			indexPage.Visible = key == "Index"
			summary.Visible = key == "Inventory"
			if key == "Index" then
				refreshIndex()
			end
		end,
	})

	Registry.DataController.ObserveMany({ "Pets", "Passes" }, refreshInventory)
	Registry.DataController.Observe("Index", refreshIndex)

	RunService.RenderStepped:Connect(function()
		if detailView and window.Frame.Visible then
			detailView.SetRotation(os.clock() * 0.9)
		end
		if window.Frame.Visible and inventoryPage.Visible then
			local rotation = (os.clock() * 90) % 360
			nameGradient.Rotation = rotation
			for _, slot in slots do
				if slot.Shimmer then
					slot.Shimmer.Rotation = rotation
				end
			end
		end
	end)

	return {
		Window = window,
		OnOpen = function(tab: string?)
			tabs.Select(tab or tabs.Selected or "Inventory")
			refreshInventory()
		end,
		OnClose = function()
			if multiMode then
				setMultiMode(false)
			end
		end,
	}
end

return PetsPanel
