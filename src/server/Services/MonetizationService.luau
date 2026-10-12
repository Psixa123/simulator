--!nonstrict
-- Gamepass ownership and developer product purchases (ProcessReceipt).
-- Purchases are idempotent: each PurchaseId is stored in the player's data and saved
-- before Roblox is told the purchase was granted.
-- Also reads each player's PolicyService rules so the Shop can hide paid random items where they aren't allowed.
-- In Roblox Studio, items whose Id is still 0 can be "bought" for free so everything is testable.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
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

local PASS_RETRY_DELAYS = { 1, 2, 4, 8 } -- seconds between ownership lookups that errored
local PASS_RECHECK_INTERVAL = 60 -- passes whose lookup kept failing are checked again this often
local passState = {} -- [Player] = { Checking = { [passKey] = true }, Failed = { [passKey] = true } }

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
	if not data or Registry.DataService.IsReleased(player) then
		-- Not loaded or already leaving: Roblox retries when they next join
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receipt.PurchaseId)
	if data.Receipts[purchaseId] then
		-- Granted earlier; only confirm once that grant has actually been saved
		if
			Registry.DataService.IsReceiptUnsaved(player, purchaseId)
			and Registry.DataService.CanSave(player)
			and not Registry.DataService.Save(player, false)
		then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
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
	Registry.DataService.MarkReceiptUnsaved(player, purchaseId)
	trimReceipts(data.Receipts)

	if Registry.DataService.CanSave(player) and not Registry.DataService.Save(player, false) then
		-- Granted in memory; Roblox will retry and we'll recognise the receipt id
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Asks Roblox whether the player owns a pass, retrying with backoff. Returns nil if every attempt errored
local function ownsPass(player: Player, passId: number): boolean?
	for attempt = 1, #PASS_RETRY_DELAYS + 1 do
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
		end)
		if ok then
			return owns == true
		end
		local delay = PASS_RETRY_DELAYS[attempt]
		if not delay or not player.Parent then
			break
		end
		task.wait(delay)
	end
	return nil
end

-- Looks up one pass and grants it if owned; a lookup that keeps failing is tried again later
local function checkPass(player: Player, passKey: string)
	local state = passState[player]
	local pass = Monetization.Gamepasses[passKey]
	if not state or not pass or state.Checking[passKey] then
		return
	end
	local data = Registry.DataService.Get(player)
	if not data or data.Passes[passKey] then
		state.Failed[passKey] = nil
		return
	end
	state.Checking[passKey] = true
	local owns = ownsPass(player, pass.Id)
	state.Checking[passKey] = nil
	state.Failed[passKey] = if owns == nil then true else nil
	if owns and player.Parent then
		grantPass(player, passKey, false)
	end
end

local function checkPasses(player: Player)
	if not player.Parent then
		return
	end
	passState[player] = passState[player] or { Checking = {}, Failed = {} }
	for key, pass in Monetization.Gamepasses do
		if pass.Id and pass.Id > 0 then
			task.spawn(checkPass, player, key)
		end
	end
end

-- PromptGamePassPurchaseFinished says "purchased"; confirm with Roblox before granting anything
local function verifyPurchase(player: Player, passKey: string)
	local pass = Monetization.Gamepasses[passKey]
	for _, delay in { 0, 2, 5, 10 } do
		task.wait(delay)
		if not player.Parent then
			return
		end
		local owns = ownsPass(player, pass.Id)
		if owns then
			grantPass(player, passKey, true)
			return
		elseif owns == nil then
			break
		end
	end
	-- Still unconfirmed: keep checking in the background
	local state = passState[player]
	if state then
		state.Failed[passKey] = true
	end
end

-- Sets the "PaidRandomItemsRestricted" attribute the Shop uses to hide Robux items that end up as random pets
local function checkPolicy(player: Player)
	player:SetAttribute("PaidRandomItemsRestricted", true) -- until Roblox tells us otherwise
	for attempt = 1, 4 do
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		if not player.Parent then
			return
		end
		if ok and type(info) == "table" then
			player:SetAttribute("PaidRandomItemsRestricted", info.ArePaidRandomItemsRestricted ~= false)
			return
		end
		warn(string.format("[Monetization] Policy lookup failed for %s (attempt %d): %s", player.Name, attempt, tostring(info)))
		if attempt < 4 then
			task.wait(attempt * 2)
		end
	end
	-- Couldn't ask Roblox: stay restricted to be safe (Studio testers keep every item)
	player:SetAttribute("PaidRandomItemsRestricted", not RunService:IsStudio())
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
		if not key then
			return
		elseif purchased then
			verifyPurchase(player, key)
		else
			-- Closed the prompt (Roblox also lands here for "you already own this"): look again
			checkPass(player, key)
		end
	end)

	Registry.DataService.PlayerLoaded:Connect(checkPasses)

	Players.PlayerAdded:Connect(checkPolicy)
	for _, player in Players:GetPlayers() do
		task.spawn(checkPolicy, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		passState[player] = nil
	end)

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

function MonetizationService.Start()
	while true do
		task.wait(PASS_RECHECK_INTERVAL)
		for player, state in table.clone(passState) do
			for key in table.clone(state.Failed) do
				task.spawn(checkPass, player, key)
			end
		end
	end
end

return MonetizationService
