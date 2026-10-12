--!nonstrict
-- Gamepass ownership and developer product purchases (ProcessReceipt).
-- Purchases are idempotent: each PurchaseId is stored in the player's data and saved
-- before Roblox is told the purchase was granted.
-- In Roblox Studio, items whose Id is still 0 can be "bought" for free so everything is testable.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Monetization = require(Shared.Config.Monetization)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Registry)
local Net = require(script.Parent.Net)

local MonetizationService = {}

local passKeyById = {}
local productKeyById = {}

local function grantPass(player: Player, passKey: string, announce: boolean)
	local data = Registry.DataService.Get(player)
	local pass = Monetization.Gamepasses[passKey]
	if not data or not pass or data.Passes[passKey] then
		return
	end
	data.Passes[passKey] = true
	Registry.DataService.Replicate(player, "Passes")
	if passKey == "PetSlots" then
		Registry.PetService.Refresh(player, data)
	end
	if announce then
		Net.Notify(player, string.format("%s Thanks for buying %s!", pass.Icon, pass.Name), "Success")
		Net.Effect(player, "Purchase", pass.Name)
	end
end

local function grantProduct(player: Player, productKey: string)
	local data = Registry.DataService.Get(player)
	local product = Monetization.Products[productKey]
	if not data or not product then
		error("Unknown product " .. tostring(productKey))
	end

	if product.Kind == "Volts" then
		local amount = product.Amount * Formulas.VoltsUnit(data)
		Registry.EconomyService.AddVolts(player, amount, false)
		Net.Notify(player, string.format("⚡ +%s Volts! Thanks for your support!", Format.Number(amount)), "Success")
	elseif product.Kind == "Boost" then
		Registry.BoostService.Add(player, product.Boost, product.Duration)
	elseif product.Kind == "MegaStorm" then
		Registry.MegaStormService.Summon(player)
	end
	Net.Effect(player, "Purchase", product.Name)
end

local function trimReceipts(receipts)
	local list = {}
	for id, time in receipts do
		table.insert(list, { Id = id, Time = time })
	end
	if #list <= GameConfig.MaxStoredReceipts then
		return
	end
	table.sort(list, function(a, b)
		return a.Time < b.Time
	end)
	for index = 1, #list - GameConfig.MaxStoredReceipts do
		receipts[list[index].Id] = nil
	end
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = Registry.DataService.WaitForData(player, 20)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receipt.PurchaseId)
	if data.Receipts[purchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local productKey = productKeyById[receipt.ProductId]
	if not productKey then
		warn("[Monetization] Received a purchase for an unknown product id: " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, err = pcall(grantProduct, player, productKey)
	if not ok then
		warn("[Monetization] Failed to grant " .. productKey .. ": " .. tostring(err))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	data.Receipts[purchaseId] = os.time()
	trimReceipts(data.Receipts)

	if Registry.DataService.CanSave(player) and not Registry.DataService.Save(player, false) then
		-- Granted in memory; Roblox will retry and we'll recognise the receipt id
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function checkPasses(player: Player)
	for key, pass in Monetization.Gamepasses do
		if pass.Id and pass.Id > 0 then
			task.spawn(function()
				local ok, owns = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
				end)
				if ok and owns and player.Parent then
					grantPass(player, key, false)
				end
			end)
		end
	end
end

function MonetizationService.HasPass(player: Player, passKey: string): boolean
	local data = Registry.DataService.Get(player)
	return data ~= nil and Formulas.HasPass(data, passKey)
end

function MonetizationService.Init()
	for key, pass in Monetization.Gamepasses do
		if pass.Id and pass.Id > 0 then
			passKeyById[pass.Id] = key
		end
	end
	for key, product in Monetization.Products do
		if product.Id and product.Id > 0 then
			productKeyById[product.Id] = key
		end
	end

	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local key = passKeyById[passId]
		if purchased and key then
			grantPass(player, key, true)
		end
	end)

	Registry.DataService.PlayerLoaded:Connect(checkPasses)

	-- Studio-only test purchases for items that don't have an Id yet
	Remotes.DevGrant.OnServerInvoke = function(player, kind, key)
		if not RunService:IsStudio() then
			return Net.Fail("Purchases aren't set up yet. Coming soon!")
		end
		if kind == "Pass" and Monetization.Gamepasses[key] then
			grantPass(player, key, true)
			return { Ok = true }
		elseif kind == "Product" and Monetization.Products[key] then
			local ok, err = pcall(grantProduct, player, key)
			if not ok then
				return Net.Fail(tostring(err))
			end
			return { Ok = true }
		end
		return Net.Fail("Unknown item.")
	end
end

return MonetizationService
