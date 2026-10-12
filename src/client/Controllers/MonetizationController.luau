--!nonstrict
-- Prompts gamepass / developer product purchases and looks up live prices.
-- Items whose Id is still 0 are granted for free inside Roblox Studio so you can test them.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared.Config.Monetization)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Parent.Registry)

local MonetizationController = {}

local player = Players.LocalPlayer
local prices = {} -- [id] = price

function MonetizationController.Owns(passKey: string): boolean
	local data = Registry.DataController.Data
	return data ~= nil and data.Passes ~= nil and data.Passes[passKey] == true
end

local function testGrant(kind: string, key: string, name: string)
	if RunService:IsStudio() then
		local result = Remotes.DevGrant:InvokeServer(kind, key)
		if result and result.Ok then
			Registry.InterfaceController.Notify("🧪 Studio test purchase: " .. name, "Info")
		else
			Registry.InterfaceController.Notify(result and result.Error or "Purchase failed.", "Error")
		end
	else
		Registry.InterfaceController.Notify(name .. " is coming soon!", "Info")
	end
end

function MonetizationController.PromptPass(passKey: string)
	local pass = Monetization.Gamepasses[passKey]
	if not pass then
		return
	end
	if MonetizationController.Owns(passKey) then
		Registry.InterfaceController.Notify("You already own " .. pass.Name .. "!", "Info")
		return
	end
	if not pass.Id or pass.Id == 0 then
		testGrant("Pass", passKey, pass.Name)
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, pass.Id)
end

function MonetizationController.PromptProduct(productKey: string)
	local product = Monetization.Products[productKey]
	if not product then
		return
	end
	if not product.Id or product.Id == 0 then
		testGrant("Product", productKey, product.Name)
		return
	end
	MarketplaceService:PromptProductPurchase(player, product.Id)
end

local function fetchInfo(id: number, infoType: Enum.InfoType)
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfoAsync(id, infoType)
	end)
	if not ok then
		ok, info = pcall(function()
			return (MarketplaceService :: any):GetProductInfo(id, infoType)
		end)
	end
	return if ok then info else nil
end

-- Calls callback(price) with the configured price right away and again with the live price
function MonetizationController.GetPrice(kind: string, key: string, callback: (number) -> ())
	local item = if kind == "Pass" then Monetization.Gamepasses[key] else Monetization.Products[key]
	if not item then
		return
	end
	callback(prices[item.Id] or item.Price)
	if not item.Id or item.Id == 0 or prices[item.Id] then
		return
	end
	task.spawn(function()
		local info = fetchInfo(item.Id, if kind == "Pass" then Enum.InfoType.GamePass else Enum.InfoType.Product)
		local price = info and info.PriceInRobux
		if type(price) == "number" then
			prices[item.Id] = price
			callback(price)
		end
	end)
end

return MonetizationController
