--!nonstrict
-- Shop panel: gamepasses, boosts and Volts packs.
-- Shows each item's uploaded icon once Roblox returns it, "Coming soon" for items without an Id
-- in live servers, and hides paid random items where they aren't allowed.
-- Sky Lab look: white item cards with the item's 3D icon in a tinted well and a candy buy button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared.Config.Monetization)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)

local Registry = require(script.Parent.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI)
local Theme = require(script.Parent.Parent.Theme)
local Icons = require(script.Parent.Parent.Icons)

local Shop = {}

local WHITE = Color3.new(1, 1, 1)
local player = Players.LocalPlayer

local CELL = UDim2.fromOffset(306, 136)

-- The 3D icon (Icons.luau key) for each item; anything missing shows the item's own emoji
local ITEM_ICONS = {
	VIP = "Star",
	DoubleVolts = "Sell",
	DoubleEnergy = "Energy",
	AutoCatch = "Power",
	RemoteSell = "Radar",
	MegaTank = "Tank",
	LuckyHatcher = "Luck",
	TripleHatch = "Eggs",
	AutoHatch = "Eggs",
	PetSlots = "Pets",
	StormRadar = "Radar",
	VoltsSmall = "Volts",
	VoltsMedium = "Sell",
	VoltsLarge = "Gift",
	VoltsHuge = "Rewards",
	EnergyBoost = "Boost",
	LuckBoost = "Luck",
	SummonMegaStorm = "MegaStorm",
}

local PRODUCT_COLORS = {
	Volts = Theme.Sets.Bolt.Top,
	Boost = Theme.Sets.Rain.Top,
	MegaStorm = Theme.Sets.Storm.Top,
}

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

local function itemCard(parent: Instance, order: number, key: string, emoji: string, color: Color3, name: string, description: string, onClick: () -> ())
	local cell = frame({ Name = name, BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
	local card = UI.CloudCard({ Name = "Card", Size = UDim2.new(1, -4, 1, -4), Position = UDim2.fromOffset(2, 2), Parent = cell })
	-- Tall tinted well on the left with the item's icon
	local well = frame({
		Name = "Well",
		Size = UDim2.new(0, 80, 1, -16),
		Position = UDim2.fromOffset(8, 8),
		ZIndex = 2,
		Parent = card,
		UI.Corner(14),
		UI.Gradient(color:Lerp(WHITE, 0.82), color:Lerp(WHITE, 0.55)),
	})
	Icons.New(ITEM_ICONS[key] or emoji, { Name = "Icon", Size = UDim2.fromOffset(66, 66), ZIndex = 3, Parent = well })
	UI.Text({
		Name = "Title",
		Text = name,
		TextSize = 20,
		Scaled = true,
		MinTextSize = 12,
		X = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -106, 0, 24),
		Position = UDim2.fromOffset(98, 8),
		ZIndex = 2,
		Parent = card,
	})
	local descriptionLabel = UI.Text({
		Name = "Description",
		Text = description,
		Font = Theme.BodyFont,
		TextSize = 12,
		Scaled = true,
		MinTextSize = 9,
		Wrapped = true,
		Rich = true,
		Color = Theme.InkSoft,
		X = Enum.TextXAlignment.Left,
		Y = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -106, 0, 46),
		Position = UDim2.fromOffset(98, 33),
		ZIndex = 2,
		Parent = card,
	})
	local button = UI.Button({
		Name = "Buy",
		Text = "",
		Icon = "Check", -- shown for owned passes
		Color = "Leaf",
		TextSize = 20,
		Size = UDim2.fromOffset(140, 44),
		Position = UDim2.new(1, -8, 1, -8),
		AnchorPoint = Vector2.new(1, 1),
		ZIndex = 2,
		Parent = card,
		OnClick = onClick,
	})
	UI.SetButtonIcon(button, nil)
	return cell, button, descriptionLabel, well
end

-- Swaps the 3D icon for the icon uploaded to Roblox once we know its asset id
local function setIcon(holder: Frame, iconId: number?)
	if not iconId or holder:FindFirstChild("Image") then
		return
	end
	UI.Create("ImageLabel", {
		Name = "Image",
		BackgroundTransparency = 1,
		Image = "rbxassetid://" .. iconId,
		ScaleType = Enum.ScaleType.Crop,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = holder,
		UI.Corner(14),
	})
	local icon = holder:FindFirstChild("Icon")
	if icon then
		icon.Visible = false
	end
end

-- Disabled button for an item that has no Id yet (live servers only; the Id can't change mid-game)
local function showComingSoon(button: GuiButton)
	UI.SetButtonText(button, "Coming soon")
	UI.SetButtonIcon(button, nil)
	UI.SetButtonColor(button, "Off")
	button.Active = false
end

function Shop.Build()
	local window = UI.Window({
		Name = "Shop",
		Title = "Storm Shop",
		Icon = "🛒",
		Size = UDim2.fromOffset(680, 560),
		Padding = { 20, 16, 18 },
	})
	local content = window.Content
	local pages = {}

	local function page(key: string)
		local scroll = UI.Scroll({
			Name = key,
			Size = UDim2.new(1, 0, 1, -58),
			Position = UDim2.fromOffset(0, 58),
			Visible = false,
			Parent = content,
			UI.Grid(CELL, UDim2.fromOffset(12, 10)),
			UI.Padding(2, 10, 8, 4),
		})
		pages[key] = scroll
		return scroll
	end

	local tabs = UI.Tabs({
		Tabs = {
			{ Key = "Passes", Text = "Passes" },
			{ Key = "Boosts", Text = "Boosts" },
			{ Key = "Volts", Text = "Volts" },
		},
		TabWidth = 132,
		Size = UDim2.new(0, 0, 0, 46),
		Parent = content,
		OnSelect = function(key)
			for pageKey, scroll in pages do
				scroll.Visible = pageKey == key
			end
		end,
	})

	local Monetize = Registry.MonetizationController
	local unconfigured = false
	local passButtons = {}
	local voltsDescriptions = {}
	local cards = {} -- [item key] = card (hidden while the item is restricted)
	local refresh

	-- Gamepasses
	local passPage = page("Passes")
	for index, pass in Monetization.SortedPasses() do
		local card, button, _, iconHolder = itemCard(passPage, index, pass.Key, pass.Icon, pass.Color, pass.Name, pass.Description, function()
			if not Monetize.IsComingSoon(pass) then
				Monetize.PromptPass(pass.Key)
			end
		end)
		cards[pass.Key] = card
		passButtons[pass.Key] = { Button = button, Price = pass.Price, Pass = pass }
		Monetize.GetPrice("Pass", pass.Key, function(price, icon)
			passButtons[pass.Key].Price = price
			setIcon(iconHolder, icon)
			if refresh then
				refresh()
			end
		end)
		if pass.Id == 0 then
			unconfigured = true
		end
	end

	-- Developer products
	local boostPage = page("Boosts")
	local voltsPage = page("Volts")
	for index, product in Monetization.SortedProducts() do
		local parent = if product.Category == "Volts" then voltsPage else boostPage
		local description = product.Description
		if product.Kind == "Boost" then
			description = "Doubles your "
				.. string.lower(product.Boost)
				.. " for "
				.. Format.Duration(product.Duration)
				.. ". Stacks with gamepasses and pauses while you're offline."
		end
		local color = PRODUCT_COLORS[product.Kind] or Theme.Sets.Sky.Top
		local card, button, descriptionLabel, iconHolder = itemCard(parent, index, product.Key, product.Icon, color, product.Name, description or "", function()
			if not Monetize.IsComingSoon(product) then
				Monetize.PromptProduct(product.Key)
			end
		end)
		cards[product.Key] = card
		if product.Kind == "Volts" then
			-- The pack's amount, big, where the description would be
			voltsDescriptions[product.Key] = descriptionLabel
			descriptionLabel.Font = Theme.Font
			descriptionLabel.TextColor3 = Theme.Ink
			descriptionLabel.TextYAlignment = Enum.TextYAlignment.Center
			descriptionLabel.Size = UDim2.new(1, -106, 0, 30)
			descriptionLabel:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize = 24
		end
		local comingSoon = Monetize.IsComingSoon(product)
		Monetize.GetPrice("Product", product.Key, function(price, icon)
			setIcon(iconHolder, icon)
			if comingSoon then
				showComingSoon(button)
			else
				UI.SetButtonText(button, "R$ " .. Format.Commas(price))
			end
		end)
		if product.Id == 0 then
			unconfigured = true
		end
	end

	if unconfigured and RunService:IsStudio() then
		UI.Text({
			Name = "StudioNote",
			Text = "Studio test mode: items without an ID are free",
			Font = Theme.BodyFont,
			TextSize = 13,
			Scaled = true,
			Wrapped = true,
			Color = Theme.Sets.Sunset.Lip,
			X = Enum.TextXAlignment.Right,
			Size = UDim2.new(1, -440, 0, 36),
			Position = UDim2.new(1, -4, 0, 23),
			AnchorPoint = Vector2.new(1, 0.5),
			Parent = content,
		})
	end

	refresh = function()
		local data = Registry.DataController.Data
		if not data then
			return
		end
		for passKey, entry in passButtons do
			if Formulas.HasPass(data, passKey) then
				UI.SetButtonText(entry.Button, "Owned")
				UI.SetButtonIcon(entry.Button, "Check")
				UI.SetButtonColor(entry.Button, "Rain")
			elseif Monetize.IsComingSoon(entry.Pass) then
				showComingSoon(entry.Button)
			else
				UI.SetButtonText(entry.Button, "R$ " .. Format.Commas(entry.Price))
				UI.SetButtonIcon(entry.Button, nil)
				UI.SetButtonColor(entry.Button, "Leaf")
			end
		end
		local unit = Formulas.VoltsUnit(data)
		for productKey, label in voltsDescriptions do
			label.Text = '<font color="#1F8F38">+' .. Format.Number(Monetization.Products[productKey].Amount * unit) .. "</font> Volts"
		end
	end

	-- Paid random items (Volts packs, luck and hatch boosters) are hidden where they aren't allowed
	local function applyPolicy()
		for key, card in cards do
			card.Visible = not Monetize.IsRestricted(key)
		end
		local voltsOnSale = false
		for _, card in cards do
			if card.Parent == voltsPage and card.Visible then
				voltsOnSale = true
			end
		end
		tabs.Buttons.Volts.Visible = voltsOnSale
		if tabs.Selected == "Volts" and not voltsOnSale then
			tabs.Select("Passes")
		end
	end
	player:GetAttributeChangedSignal("PaidRandomItemsRestricted"):Connect(applyPolicy)
	applyPolicy()

	Registry.DataController.ObserveMany({ "Passes", "Upgrades", "Zone", "Rebirths" }, refresh)

	return {
		Window = window,
		OnOpen = function(tab: string?)
			refresh()
			applyPolicy()
			local tabButton = tab and tabs.Buttons[tab]
			if tab and not (tabButton and tabButton.Visible) then
				tab = "Passes" -- e.g. the HUD's "+" asked for Volts packs that are hidden here
			end
			tabs.Select(tab or tabs.Selected or "Passes")
		end,
	}
end

return Shop
