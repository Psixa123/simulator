--!nonstrict
-- Prompts gamepass / developer product purchases and looks up live prices and icons.
-- Items whose Id is still 0 are granted for free inside Roblox Studio so you can test them
-- (live servers show them as "Coming soon"). Paid items that lead to random pets are
-- refused where Roblox's PolicyService doesn't allow them.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared.Config.Monetization)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Parent.Registry)

local MonetizationController = {}

-- Volts buy eggs and these boost or multiply hatches, so they count as paid random items
MonetizationController.RandomItems = {
	VoltsSmall = true,
	VoltsMedium = true,
	VoltsLarge = true,
	VoltsHuge = true,
	LuckBoost = true,
	LuckyHatcher = true,
	TripleHatch = true,
	SummonMegaStorm = true, -- top contributors roll for exclusive pets
}

local player = Players.LocalPlayer
local infos = {} -- ["Pass12345" / "Product12345"] = { Price, Icon } looked up from Roblox

function MonetizationController.Owns(passKey: string): boolean
	local data = Registry.DataController.Data
	return data ~= nil and data.Passes ~= nil and data.Passes[passKey] == true
end

-- True when this pass/product can't be sold to the player. The server sets the attribute;
-- until it has heard back from Roblox (nil) these items stay hidden as well.
function MonetizationController.IsRestricted(key: string): boolean
	return MonetizationController.RandomItems[key] == true and player:GetAttribute("PaidRandomItemsRestricted") ~= false
end

-- An item without an Id can only be "bought" in Studio (simulated); live servers show "Coming soon"
function MonetizationController.IsComingSoon(item): boolean
	return (not item.Id or item.Id == 0) and not RunService:IsStudio()
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

local function refuseRestricted(key: string, name: string): boolean
	if MonetizationController.IsRestricted(key) then
		Registry.InterfaceController.Notify(name .. " isn't available for your account.", "Info")
		return true
	end
	return false
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
	if refuseRestricted(passKey, pass.Name) then
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
	if refuseRestricted(productKey, product.Name) then
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
	return if ok and type(info) == "table" then info else nil
end

-- Calls callback(price, iconId?) with the configured price right away, then again with the live
-- price and the icon uploaded for the item (iconId is nil while unknown: keep showing the emoji)
function MonetizationController.GetPrice(kind: string, key: string, callback: (number, number?) -> ())
	local item = if kind == "Pass" then Monetization.Gamepasses[key] else Monetization.Products[key]
	if not item then
		return
	end
	-- Pass and product ids are separate number ranges, so the cache key includes the kind
	local cacheKey = kind .. tostring(item.Id)
	local cached = infos[cacheKey]
	callback(if cached then cached.Price else item.Price, if cached then cached.Icon else nil)
	if not item.Id or item.Id == 0 or cached then
		return
	end
	task.spawn(function()
		local info = fetchInfo(item.Id, if kind == "Pass" then Enum.InfoType.GamePass else Enum.InfoType.Product)
		if not info then
			return
		end
		local price = if type(info.PriceInRobux) == "number" then info.PriceInRobux else item.Price
		local icon = if type(info.IconImageAssetId) == "number" and info.IconImageAssetId > 0 then info.IconImageAssetId else nil
		infos[cacheKey] = { Price = price, Icon = icon }
		callback(price, icon)
	end)
end

return MonetizationController
