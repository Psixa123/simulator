--!nonstrict
-- Pets panel: inventory (equip, golden/rainbow crafting, delete) and the pet index.

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
local Viewport = require(script.Parent.Parent.Viewport)
local Confirm = require(script.Parent.Parent.Overlays.Confirm)

local PetsPanel = {}

local COLORS = Theme.Colors
local RAINBOW_CARD = Color3.fromRGB(96, 66, 150)

local function rainbowGradient(parent: Instance): UIGradient
	return UI.Create("UIGradient", { Name = "Rainbow", Color = PetModels.RainbowSequence, Parent = parent })
end

local function petAction(action: string, argument: any?)
	local result = Remotes.PetAction:InvokeServer(action, argument)
	if result and not result.Ok then
		Registry.InterfaceController.Notify(result.Error, "Error")
	end
	return result
end

function PetsPanel.Build()
	local window = UI.Window({
		Name = "Pets",
		Title = "Pets",
		Icon = "🐾",
		Color = "Pink",
		Size = UDim2.fromOffset(850, 570),
	})
	local content = window.Content

	local inventoryPage = UI.Create("Frame", {
		Name = "Inventory",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -52),
		Position = UDim2.fromOffset(0, 52),
		Parent = content,
	})
	local indexPage = UI.Create("Frame", {
		Name = "Index",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -52),
		Position = UDim2.fromOffset(0, 52),
		Visible = false,
		Parent = content,
	})

	local summary = UI.Label({
		Name = "Summary",
		Text = "",
		TextColor3 = COLORS.SubText,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, -330, 0, 24),
		Position = UDim2.new(1, -4, 0, 9),
		AnchorPoint = Vector2.new(1, 0),
		MaxTextSize = 18,
		Parent = content,
	})

	---------------------------------------------------------------------
	-- Inventory
	---------------------------------------------------------------------
	local grid = UI.Scroll({
		Name = "Grid",
		Size = UDim2.new(1, -264, 1, -56),
		Parent = inventoryPage,
		UI.Grid(UDim2.fromOffset(98, 118), UDim2.fromOffset(8, 8)),
		UI.Padding(4, 8, 8, 4),
	})
	grid.UIGridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	local emptyHint = UI.Label({
		Name = "Empty",
		Text = "You don't have any pets yet!\nHatch an egg in any zone to get your first Stormling. Pets catch weather for you! 🌪️",
		Font = Theme.BodyFont,
		TextColor3 = COLORS.SubText,
		Size = UDim2.new(1, -330, 0, 60),
		Position = UDim2.new(0, 30, 0.4, 0),
		MaxTextSize = 20,
		Stroke = 1.5,
		Visible = false,
		Parent = inventoryPage,
	})

	UI.Button({
		Name = "EquipBest",
		Text = "⭐ Equip Best",
		Color = "Green",
		Size = UDim2.fromOffset(180, 46),
		Position = UDim2.new(0, 2, 1, 0),
		AnchorPoint = Vector2.new(0, 1),
		MaxTextSize = 20,
		Parent = inventoryPage,
		OnClick = function()
			petAction("EquipBest")
		end,
	})
	UI.Button({
		Name = "UnequipAll",
		Text = "Unequip All",
		Color = "Gray",
		Size = UDim2.fromOffset(160, 46),
		Position = UDim2.new(0, 192, 1, 0),
		AnchorPoint = Vector2.new(0, 1),
		MaxTextSize = 20,
		Parent = inventoryPage,
		OnClick = function()
			petAction("UnequipAll")
		end,
	})
	local catchTip = UI.Label({
		Name = "CatchTip",
		Text = "",
		Font = Theme.BodyFont,
		TextColor3 = COLORS.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -630, 0, 46),
		Position = UDim2.new(0, 362, 1, 0),
		AnchorPoint = Vector2.new(0, 1),
		MaxTextSize = 15,
		Stroke = 1.5,
		Parent = inventoryPage,
	})

	local detail = UI.Card({
		Name = "Detail",
		Size = UDim2.new(0, 252, 1, 0),
		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Parent = inventoryPage,
	})
	local viewHolder = UI.Create("Frame", {
		Name = "View",
		BackgroundColor3 = COLORS.Inset,
		Size = UDim2.new(1, -20, 0, 148),
		Position = UDim2.fromOffset(10, 10),
		Parent = detail,
		UI.Corner(12),
	})
	local nameLabel = UI.Label({ Name = "PetName", Text = "", Size = UDim2.new(1, -16, 0, 30), Position = UDim2.fromOffset(8, 164), MaxTextSize = 24, Parent = detail })
	local nameGradient = rainbowGradient(nameLabel)
	local rarityLabel = UI.Label({ Name = "Rarity", Text = "", Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(8, 194), MaxTextSize = 18, Parent = detail })
	local bonusLabel = UI.Label({ Name = "Bonus", Text = "", TextColor3 = COLORS.Energy, Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(8, 218), MaxTextSize = 20, Parent = detail })
	local catchLabel = UI.Label({
		Name = "Catch",
		Text = "",
		Font = Theme.BodyFont,
		TextColor3 = COLORS.Power,
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.fromOffset(8, 244),
		MaxTextSize = 15,
		Stroke = 1.5,
		Parent = detail,
	})
	local selectHint = UI.Label({
		Name = "SelectHint",
		Text = "Select a pet to see its details",
		Font = Theme.BodyFont,
		TextColor3 = COLORS.SubText,
		Size = UDim2.new(1, -30, 0, 50),
		Position = UDim2.new(0, 15, 0, 200),
		MaxTextSize = 18,
		Stroke = 1.5,
		Parent = detail,
	})

	local slots = {} -- [uid] = slot
	local selectedUid: string? = nil
	local detailView = nil
	local detailKey = nil
	local equipButton, goldenButton, rainbowButton, deleteButton

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

	local function refreshDetail()
		local pet = findPet(selectedUid)
		local hasPet = pet ~= nil
		local tier = if pet then Pets.TierOf(pet) else "Normal"
		nameLabel.Visible = hasPet
		rarityLabel.Visible = hasPet
		bonusLabel.Visible = hasPet
		catchLabel.Visible = hasPet
		equipButton.Visible = hasPet
		goldenButton.Visible = hasPet and tier == "Normal"
		rainbowButton.Visible = hasPet and tier == "Golden"
		deleteButton.Visible = hasPet
		selectHint.Visible = not hasPet

		for uid, slot in slots do
			local selected = uid == selectedUid
			slot.Stroke.Thickness = if selected then 5 else 3
			slot.Stroke.Color = if selected then Color3.new(1, 1, 1) else slot.RarityColor
		end

		if not pet then
			if detailView then
				detailView.Destroy()
				detailView = nil
				detailKey = nil
			end
			return
		end

		local def = Pets.Pets[pet.Id]
		local rarity = Pets.Rarities[def.Rarity]
		local key = pet.Id .. ":" .. tier
		if key ~= detailKey then
			if detailView then
				detailView.Destroy()
			end
			detailView = Viewport.Pet(pet.Id, tier, { Parent = viewHolder, Zoom = 1.2 })
			detailKey = key
		end

		nameLabel.Text = Pets.DisplayName(pet.Id, tier)
		nameLabel.TextColor3 = if tier == "Golden" then COLORS.Volts elseif tier == "Rainbow" then Color3.new(1, 1, 1) else COLORS.Text
		nameGradient.Enabled = tier == "Rainbow"
		rarityLabel.Text = rarity.Name
		rarityLabel.TextColor3 = rarity.Color
		bonusLabel.Text = Format.Bonus(Formulas.PetBonus(pet.Id, tier)) .. " Energy"
		catchLabel.Text = "🌪️ Auto-catches with " .. Format.Chance(Formulas.PetCatchShare(tier)) .. " of your Power"

		UI.SetButtonText(equipButton, if pet.Equipped then "Unequip" else "Equip")
		UI.SetButtonColor(equipButton, if pet.Equipped then "Gray" else "Green")

		local copies = countCopies(pet.Id, "Normal")
		local required = GameConfig.Pets.GoldenRequirement
		UI.SetButtonText(goldenButton, string.format("⭐ Make Golden (%d/%d)", math.min(copies, required), required))
		UI.SetButtonColor(goldenButton, if copies >= required then "Yellow" else "Gray")

		local goldenCopies = countCopies(pet.Id, "Golden")
		local rainbowRequired = GameConfig.Pets.RainbowRequirement
		UI.SetButtonText(rainbowButton, string.format("🌈 Make Rainbow (%d/%d)", math.min(goldenCopies, rainbowRequired), rainbowRequired))
		UI.SetButtonColor(rainbowButton, if goldenCopies >= rainbowRequired then "Pink" else "Gray")
	end

	local function select(uid: string?)
		selectedUid = uid
		refreshDetail()
	end

	equipButton = UI.Button({
		Name = "Equip",
		Text = "Equip",
		Color = "Green",
		Size = UDim2.new(1, -20, 0, 46),
		Position = UDim2.fromOffset(10, 272),
		MaxTextSize = 22,
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
		Text = "⭐ Make Golden",
		Color = "Yellow",
		Size = UDim2.new(1, -20, 0, 46),
		Position = UDim2.fromOffset(10, 324),
		MaxTextSize = 18,
		Parent = detail,
		OnClick = function()
			craft("Golden")
		end,
	})
	rainbowButton = UI.Button({
		Name = "Rainbow",
		Text = "🌈 Make Rainbow",
		Color = "Pink",
		Size = UDim2.new(1, -20, 0, 46),
		Position = UDim2.fromOffset(10, 324),
		MaxTextSize = 18,
		Parent = detail,
		OnClick = function()
			craft("Rainbow")
		end,
	})
	deleteButton = UI.Button({
		Name = "Delete",
		Text = "🗑️ Delete",
		Color = "Red",
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.fromOffset(10, 376),
		MaxTextSize = 18,
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
		local rainbow = tier == "Rainbow"
		local button = UI.Create("TextButton", {
			Name = pet.Uid,
			AutoButtonColor = false,
			Text = "",
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = grid,
			UI.Corner(14),
			UI.Gradient(if rainbow then RAINBOW_CARD else COLORS.Card, COLORS.CardDark, 90),
		})
		-- Rainbow cards get a shimmering rainbow outline (the stroke color tints the gradient)
		local strokeColor = if rainbow then Color3.new(1, 1, 1) else rarity.Color
		local stroke = UI.Stroke(3, strokeColor)
		stroke.Parent = button
		local shimmer = if rainbow then rainbowGradient(stroke) else nil

		Viewport.Pet(pet.Id, tier, {
			Size = UDim2.new(1, -8, 1, -30),
			Position = UDim2.fromOffset(4, 2),
			Parent = button,
		})
		UI.Label({
			Name = "Bonus",
			Text = Format.Bonus(Formulas.PetBonus(pet.Id, tier)),
			TextColor3 = COLORS.Energy,
			Size = UDim2.new(1, -8, 0, 22),
			Position = UDim2.new(0, 4, 1, -4),
			AnchorPoint = Vector2.new(0, 1),
			MaxTextSize = 17,
			ZIndex = 3,
			Parent = button,
		})
		local equipped = UI.Create("Frame", {
			Name = "Equipped",
			BackgroundColor3 = COLORS.Success,
			Size = UDim2.fromOffset(26, 26),
			Position = UDim2.fromOffset(4, 4),
			Visible = pet.Equipped,
			ZIndex = 3,
			Parent = button,
			UI.Round(),
			UI.Stroke(2.5),
		})
		UI.Label({ Text = "✓", Size = UDim2.fromScale(0.72, 0.72), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 4, Parent = equipped })
		if tier ~= "Normal" then
			UI.Label({ Name = tier, Text = Pets.Tiers[tier].Icon, Stroke = false, Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -4, 0, 4), AnchorPoint = Vector2.new(1, 0), ZIndex = 3, Parent = button })
		end

		UI.Bounce(button, 1.04)
		button.Activated:Connect(function()
			Registry.SoundController.Play("Click")
			select(pet.Uid)
		end)

		return { Button = button, Stroke = stroke, RarityColor = strokeColor, Equipped = equipped, Shimmer = shimmer }
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

		emptyHint.Visible = #sorted == 0
		summary.Text = string.format(
			"Equipped %d/%d   •   Storage %d/%d   •   %s Energy",
			Formulas.EquippedCount(data),
			Formulas.EquipSlots(data),
			#data.Pets,
			GameConfig.Pets.MaxStorage,
			Format.Multiplier(Formulas.PetMultiplier(data))
		)
		local catchShare = Formulas.PetCatchPower(data) / math.max(1, Formulas.Power(data))
		catchTip.Text = if catchShare > 0
			then "🌪️ Your equipped pets catch weather for you with +" .. Format.Chance(catchShare) .. " Power!"
			else "🌪️ Equip pets and they'll catch weather for you!"
		refreshDetail()
	end

	---------------------------------------------------------------------
	-- Index
	---------------------------------------------------------------------
	local indexCount = UI.Label({
		Name = "Count",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -10, 0, 24),
		Position = UDim2.fromOffset(6, 0),
		MaxTextSize = 20,
		Parent = indexPage,
	})
	local indexGrid = UI.Scroll({
		Name = "Grid",
		Size = UDim2.new(1, 0, 1, -30),
		Position = UDim2.fromOffset(0, 30),
		Parent = indexPage,
		UI.Grid(UDim2.fromOffset(124, 150), UDim2.fromOffset(10, 10)),
		UI.Padding(4, 8, 8, 4),
	})
	local indexSlots = {} -- [petId] = { Frame, Discovered }

	local function buildIndexSlot(petId: string, order: number, discovered: boolean)
		local def = Pets.Pets[petId]
		local rarity = Pets.Rarities[def.Rarity]
		local card = UI.Card({
			Name = petId,
			LayoutOrder = order,
			StrokeColor = if discovered then rarity.Color else COLORS.Stroke,
			StrokeThickness = 3,
			StrokeTransparency = 0,
			Parent = indexGrid,
		})
		Viewport.Pet(petId, false, {
			Size = UDim2.new(1, -8, 0, 88),
			Position = UDim2.fromOffset(4, 2),
			Silhouette = not discovered,
			Parent = card,
		})
		UI.Label({
			Text = if discovered then def.Name else "???",
			Size = UDim2.new(1, -8, 0, 20),
			Position = UDim2.fromOffset(4, 90),
			MaxTextSize = 16,
			ZIndex = 3,
			Parent = card,
		})
		UI.Label({
			Text = rarity.Name,
			TextColor3 = rarity.Color,
			Size = UDim2.new(1, -8, 0, 17),
			Position = UDim2.fromOffset(4, 110),
			MaxTextSize = 14,
			ZIndex = 3,
			Parent = card,
		})
		UI.Label({
			Text = if discovered then Format.Bonus(def.Bonus) else (def.Source or (def.Egg and Pets.Eggs[def.Egg].Name) or ""),
			Font = if discovered then Theme.Font else Theme.BodyFont,
			TextColor3 = if discovered then COLORS.Energy else COLORS.Muted,
			Size = UDim2.new(1, -8, 0, 16),
			Position = UDim2.fromOffset(4, 128),
			MaxTextSize = 13,
			Stroke = 1.5,
			ZIndex = 3,
			Parent = card,
		})
		return card
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
		indexCount.Text = string.format("📖 Discovered %d / %d Stormlings", discoveredCount, #Pets.IndexOrder)
	end

	local tabs = UI.Tabs({
		Tabs = {
			{ Key = "Inventory", Text = "🎒 Inventory" },
			{ Key = "Index", Text = "📖 Index" },
		},
		Color = "Pink",
		TabWidth = 150,
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
	}
end

return PetsPanel
