--!nonstrict
-- Shop panel: gamepasses, boosts and Volts packs.
-- Shows each item's uploaded icon once Roblox returns it, "Coming soon" for items without an Id
-- in live servers, and hides paid random items where they aren't allowed.

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

local Shop = {}

local player = Players.LocalPlayer

local PRODUCT_COLORS = {
	Volts = Color3.fromRGB(255, 214, 64),
	Boost = Color3.fromRGB(110, 220, 255),
	MegaStorm = Color3.fromRGB(190, 150, 255),
}

local function itemCard(parent: Instance, order: number, icon: string, color: Color3, name: string, description: string, onClick: () -> ())
	local card = UI.Card({ Name = name, LayoutOrder = order, Parent = parent })
	local iconHolder = UI.Icon({
		Text = icon,
		Color = color,
		Size = UDim2.fromOffset(76, 76),
		Position = UDim2.fromOffset(12, 12),
		Parent = card,
	})
	UI.Label({
		Name = "Title",
		Text = name,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -110, 0, 26),
		Position = UDim2.fromOffset(100, 10),
		MaxTextSize = 22,
		Parent = card,
	})
	local descriptionLabel = UI.Label({
		Name = "Description",
		Text = description,
		Font = Theme.BodyFont,
		TextColor3 = Theme.Colors.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -110, 0, 44),
		Position = UDim2.fromOffset(100, 38),
		MaxTextSize = 17,
		Stroke = 1.5,
		Parent = card,
	})
	local button = UI.Button({
		Name = "Buy",
		Text = "",
		Color = "Green",
		Size = UDim2.fromOffset(150, 40),
		Position = UDim2.new(1, -10, 1, -8),
		AnchorPoint = Vector2.new(1, 1),
		MaxTextSize = 20,
		Parent = card,
		OnClick = onClick,
	})
	return card, button, descriptionLabel, iconHolder
end

-- Swaps the emoji for the icon uploaded to Roblox once we know its asset id
local function setIcon(holder: Frame, iconId: number?)
	if not iconId or holder:FindFirstChild("Image") then
		return
	end
	UI.Create("ImageLabel", {
		Name = "Image",
		BackgroundTransparency = 1,
		Image = "rbxassetid://" .. iconId,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = holder,
		UI.Round(),
	})
	local glyph = holder:FindFirstChild("Glyph")
	if glyph then
		glyph.Visible = false
	end
end

-- Disabled button for an item that has no Id yet (live servers only; the Id can't change mid-game)
local function showComingSoon(button: GuiButton)
	UI.SetButtonText(button, "Coming soon")
	UI.SetButtonColor(button, "Gray")
	button.Active = false
end

function Shop.Build()
	local window = UI.Window({
		Name = "Shop",
		Title = "Storm Shop",
		Icon = "🛒",
		Color = "Orange",
		Size = UDim2.fromOffset(790, 540),
	})
	local content = window.Content
	local pages = {}

	local function page(key: string)
		local scroll = UI.Scroll({
			Name = key,
			Size = UDim2.new(1, 0, 1, -52),
			Position = UDim2.fromOffset(0, 52),
			Visible = false,
			Parent = content,
			UI.Grid(UDim2.fromOffset(366, 132), UDim2.fromOffset(12, 12)),
			UI.Padding(4, 8, 8, 4),
		})
		pages[key] = scroll
		return scroll
	end

	local tabs = UI.Tabs({
		Tabs = {
			{ Key = "Passes", Text = "🎟️ Passes" },
			{ Key = "Boosts", Text = "🚀 Boosts" },
			{ Key = "Volts", Text = "⚡ Volts" },
		},
		Color = "Orange",
		TabWidth = 150,
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
		local card, button, _, iconHolder = itemCard(passPage, index, pass.Icon, pass.Color, pass.Name, pass.Description, function()
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
			description = "Doubles your " .. string.lower(product.Boost) .. " for " .. Format.Duration(product.Duration) .. ". Stacks with gamepasses and pauses while you're offline."
		end
		local card, button, descriptionLabel, iconHolder = itemCard(parent, index, product.Icon, PRODUCT_COLORS[product.Kind], product.Name, description or "", function()
			if not Monetize.IsComingSoon(product) then
				Monetize.PromptProduct(product.Key)
			end
		end)
		cards[product.Key] = card
		if product.Kind == "Volts" then
			voltsDescriptions[product.Key] = descriptionLabel
			descriptionLabel.Font = Theme.Font
			descriptionLabel.TextColor3 = Theme.Colors.Volts
			descriptionLabel:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize = 22
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
		UI.Label({
			Name = "StudioNote",
			Text = "🧪 Studio test mode: items without an ID are free",
			Font = Theme.BodyFont,
			TextColor3 = Theme.Colors.Warning,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.new(1, -490, 0, 20),
			Position = UDim2.new(1, -4, 0, 12),
			AnchorPoint = Vector2.new(1, 0),
			MaxTextSize = 14,
			Stroke = 1.5,
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
				UI.SetButtonText(entry.Button, "OWNED ✓")
				UI.SetButtonColor(entry.Button, "Teal")
			elseif Monetize.IsComingSoon(entry.Pass) then
				showComingSoon(entry.Button)
			else
				UI.SetButtonText(entry.Button, "R$ " .. Format.Commas(entry.Price))
				UI.SetButtonColor(entry.Button, "Green")
			end
		end
		local unit = Formulas.VoltsUnit(data)
		for productKey, label in voltsDescriptions do
			label.Text = "+⚡ " .. Format.Number(Monetization.Products[productKey].Amount * unit) .. " Volts"
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
