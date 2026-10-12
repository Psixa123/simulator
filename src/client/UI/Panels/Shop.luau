--!nonstrict
-- Shop panel: gamepasses, boosts and Volts packs.

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

local PRODUCT_COLORS = {
	Volts = Color3.fromRGB(255, 214, 64),
	Boost = Color3.fromRGB(110, 220, 255),
	MegaStorm = Color3.fromRGB(190, 150, 255),
}

local function itemCard(parent: Instance, order: number, icon: string, color: Color3, name: string, description: string, onClick: () -> ())
	local card = UI.Card({ Name = name, LayoutOrder = order, Parent = parent })
	UI.Icon({
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
		TextScaled = false,
		TextSize = 14,
		Size = UDim2.new(1, -110, 0, 50),
		Position = UDim2.fromOffset(100, 38),
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
	return card, button, descriptionLabel
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

	local unconfigured = false
	local passButtons = {}
	local voltsDescriptions = {}
	local refresh

	-- Gamepasses
	local passPage = page("Passes")
	for index, pass in Monetization.SortedPasses() do
		local _, button = itemCard(passPage, index, pass.Icon, pass.Color, pass.Name, pass.Description, function()
			Registry.MonetizationController.PromptPass(pass.Key)
		end)
		passButtons[pass.Key] = { Button = button, Price = pass.Price }
		Registry.MonetizationController.GetPrice("Pass", pass.Key, function(price)
			passButtons[pass.Key].Price = price
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
		local _, button, descriptionLabel = itemCard(parent, index, product.Icon, PRODUCT_COLORS[product.Kind], product.Name, description or "", function()
			Registry.MonetizationController.PromptProduct(product.Key)
		end)
		if product.Kind == "Volts" then
			voltsDescriptions[product.Key] = descriptionLabel
			descriptionLabel.TextSize = 20
			descriptionLabel.Font = Theme.Font
			descriptionLabel.TextColor3 = Theme.Colors.Volts
		end
		Registry.MonetizationController.GetPrice("Product", product.Key, function(price)
			UI.SetButtonText(button, "R$ " .. Format.Commas(price))
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

	Registry.DataController.ObserveMany({ "Passes", "Upgrades", "Zone", "Rebirths" }, refresh)

	return {
		Window = window,
		OnOpen = function(tab: string?)
			refresh()
			tabs.Select(tab or tabs.Selected or "Passes")
		end,
	}
end

return Shop
