--!nonstrict
-- Eggs, hatching, and managing pets (equip, unequip, equip best, delete one or many, golden/rainbow crafting).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Pets = require(Shared.Config.Pets)
local Zones = require(Shared.Config.Zones)
local MapLayout = require(Shared.Config.MapLayout)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Registry)
local Net = require(script.Parent.Net)

local PetService = {}

local rng = Random.new()
local MAX_BULK_DELETE = 100 -- pets per "DeleteMany" request

-- Only the pets that actually count (up to the slot limit) follow you around
local function equippedString(data): string
	local entries = {}
	for _, pet in Formulas.ActivePets(data) do
		table.insert(entries, pet.Id .. ":" .. Pets.Tiers[Pets.TierOf(pet)].Code)
	end
	return table.concat(entries, ";")
end

-- Replicates pets to the owner and updates the attribute other clients use to render them
local function refresh(player: Player, data)
	player:SetAttribute("EquippedPets", equippedString(data))
	Registry.DataService.Replicate(player, "Pets")
end
PetService.Refresh = refresh

local function findPet(data, uid: string)
	for index, pet in data.Pets do
		if pet.Uid == uid then
			return pet, index
		end
	end
	return nil, nil
end

local function roll(eggId: string, luck: number): string
	local chances = Formulas.HatchChances(eggId, luck)
	local pick = rng:NextNumber()
	local cumulative = 0
	for _, entry in chances do
		cumulative += entry.Chance
		if pick <= cumulative then
			return entry.Id
		end
	end
	return chances[#chances].Id
end

local function equipBest(data)
	local sorted = table.clone(data.Pets)
	table.sort(sorted, function(a, b)
		return Formulas.PetBonus(a.Id, Pets.TierOf(a)) > Formulas.PetBonus(b.Id, Pets.TierOf(b))
	end)
	local slots = Formulas.EquipSlots(data)
	for index, pet in sorted do
		pet.Equipped = index <= slots
	end
end

-- Adds a pet without replicating (callers batch their updates). Returns entry, isNew.
-- tier: "Normal" | "Golden" | "Rainbow" (true still means Golden)
-- force = true ignores MaxStorage (won Mega Storm exclusives are never thrown away; going over
-- the limit only blocks hatching until the player deletes some pets)
function PetService.AddPet(player: Player, petId: string, tier, force: boolean?)
	local data = Registry.DataService.Get(player)
	if not data or not Pets.Pets[petId] or (#data.Pets >= GameConfig.Pets.MaxStorage and not force) then
		return nil, false
	end
	local tierName = Pets.TierOf(tier)
	local entry = {
		Uid = "p" .. data.NextPetId,
		Id = petId,
		Golden = tierName == "Golden",
		Rainbow = tierName == "Rainbow",
		Equipped = false,
	}
	data.NextPetId += 1
	table.insert(data.Pets, entry)

	local isNew = not data.Index[petId]
	data.Index[petId] = true

	if Formulas.EquippedCount(data) < Formulas.EquipSlots(data) then
		entry.Equipped = true
	end
	return entry, isNew
end

-- Gives a pet and replicates right away (rewards, Mega Storm drops)
function PetService.GivePet(player: Player, petId: string, tier, force: boolean?)
	local data = Registry.DataService.Get(player)
	local entry, isNew = PetService.AddPet(player, petId, tier, force)
	if entry and data then
		Registry.DataService.Replicate(player, "Index")
		refresh(player, data)
	end
	return entry, isNew
end

function PetService.OwnsPet(data, petId: string): boolean
	for _, pet in data.Pets do
		if pet.Id == petId then
			return true
		end
	end
	return false
end

function PetService.BestEgg(data): string
	local best = Pets.EggOrder[1]
	for _, eggId in Pets.EggOrder do
		if Pets.Eggs[eggId].Zone <= data.Zone then
			best = eggId
		end
	end
	return best
end

-- free = true skips the price and the distance check (daily rewards, gifts)
function PetService.Hatch(player: Player, eggId: string, count: number?, free: boolean?)
	local data = Registry.DataService.Get(player)
	local egg = type(eggId) == "string" and Pets.Eggs[eggId]
	if not data or not egg then
		return Net.Fail("Invalid egg.")
	end
	local amount = if count == 3 then 3 else 1

	if amount == 3 and not Formulas.HasPass(data, "TripleHatch") then
		return Net.Fail("You need the 🥚 Triple Hatch gamepass!")
	end
	if egg.Zone > data.Zone then
		return Net.Fail("Unlock " .. Zones[egg.Zone].Name .. " to hatch the " .. egg.Name .. "!")
	end
	if not free then
		local root = Net.GetRoot(player)
		if not root or (root.Position - MapLayout.EggStation(egg.Zone)).Magnitude > GameConfig.Pets.HatchDistance + 14 then
			return Net.Fail("Move closer to the egg!")
		end
	end
	if #data.Pets + amount > GameConfig.Pets.MaxStorage then
		return Net.Fail("Your pet storage is full! Delete some pets first.")
	end

	local cost = if free then 0 else egg.Cost * amount
	if data.Volts < cost then
		return Net.Fail("You need ⚡ " .. Format.Number(cost) .. " Volts!")
	end
	data.Volts -= cost

	local luck = Formulas.LuckMultiplier(data, os.time())
	local results = {}
	for _ = 1, amount do
		local petId = roll(eggId, luck)
		local entry, isNew = PetService.AddPet(player, petId, false)
		table.insert(results, { Id = petId, Uid = entry and entry.Uid, New = isNew })

		-- Only Legendary and Exclusive hatches are announced to the whole server
		local rarity = Pets.RarityOf(petId)
		if rarity.Name == "Legendary" or rarity.Name == "Exclusive" then
			Net.NotifyAll(
				string.format("🌟 %s hatched a %s %s!", player.DisplayName, rarity.Name, Pets.Pets[petId].Name),
				"Reward"
			)
		end
	end
	data.Stats.EggsHatched += amount

	Registry.DataService.Replicate(player, "Volts", "Index")
	refresh(player, data)
	return { Ok = true, Egg = eggId, Results = results }
end

-- What each crafted tier is made from (5 Normal -> Golden, 5 Golden -> Rainbow)
local RECIPES = {
	Golden = { From = "Normal", Requirement = GameConfig.Pets.GoldenRequirement, Message = "You need %d %s to craft a golden one!" },
	Rainbow = { From = "Golden", Requirement = GameConfig.Pets.RainbowRequirement, Message = "You need %d Golden %s to craft a rainbow one! 🌈" },
}

-- Turns `Requirement` copies of a pet in the recipe's From tier into one pet of `tier`.
-- Unequipped copies are used first; the new pet stays equipped if any used copy was.
local function craft(player: Player, data, petId, tier: string)
	local recipe = RECIPES[tier]
	local def = type(petId) == "string" and Pets.Pets[petId]
	if not recipe or not def then
		return Net.Fail("Invalid pet.")
	end
	local required = recipe.Requirement
	local candidates = {}
	for _, pet in data.Pets do
		if pet.Id == petId and Pets.TierOf(pet) == recipe.From then
			table.insert(candidates, pet)
		end
	end
	if #candidates < required then
		return Net.Fail(string.format(recipe.Message, required, def.Name))
	end
	table.sort(candidates, function(a, b)
		return (if a.Equipped then 1 else 0) < (if b.Equipped then 1 else 0)
	end)
	local remove = {}
	local wasEquipped = false
	for index = 1, required do
		remove[candidates[index]] = true
		wasEquipped = wasEquipped or candidates[index].Equipped
	end
	local kept = {}
	for _, pet in data.Pets do
		if not remove[pet] then
			table.insert(kept, pet)
		end
	end
	data.Pets = kept
	local entry = {
		Uid = "p" .. data.NextPetId,
		Id = petId,
		Golden = tier == "Golden",
		Rainbow = tier == "Rainbow",
		Equipped = wasEquipped,
	}
	data.NextPetId += 1
	table.insert(data.Pets, entry)
	refresh(player, data)
	return { Ok = true, Uid = entry.Uid }
end

local function petAction(player: Player, action: string, argument)
	local data = Registry.DataService.Get(player)
	if not data then
		return Net.Fail("Still loading...")
	end

	if action == "Equip" then
		local pet = findPet(data, argument)
		if not pet then
			return Net.Fail("Pet not found.")
		end
		if not pet.Equipped then
			if Formulas.EquippedCount(data) >= Formulas.EquipSlots(data) then
				return Net.Fail("All pet slots are full! Unequip a pet or get the 🐾 +3 Pet Slots pass.")
			end
			pet.Equipped = true
		end
	elseif action == "Unequip" then
		local pet = findPet(data, argument)
		if not pet then
			return Net.Fail("Pet not found.")
		end
		pet.Equipped = false
	elseif action == "Delete" then
		local pet, index = findPet(data, argument)
		if not pet then
			return Net.Fail("Pet not found.")
		end
		table.remove(data.Pets, index)
	elseif action == "DeleteMany" then
		-- Multi-delete from the Pets panel: a list of pet Uids. Equipped pets and exclusives
		-- (pets no egg can hatch) are never bulk-deleted; those go one at a time.
		if type(argument) ~= "table" then
			return Net.Fail("Invalid pets.")
		end
		local wanted, count = {}, 0
		for key, uid in argument do
			if type(key) ~= "number" or type(uid) ~= "string" or #uid > 32 then
				return Net.Fail("Invalid pets.")
			end
			count += 1
			if count > MAX_BULK_DELETE then
				return Net.Fail("You can delete up to " .. MAX_BULK_DELETE .. " pets at once.")
			end
			wanted[uid] = true
		end
		local kept, removed = {}, 0
		for _, pet in data.Pets do
			local def = Pets.Pets[pet.Id]
			if wanted[pet.Uid] and not pet.Equipped and def and def.Egg then
				removed += 1
			else
				table.insert(kept, pet)
			end
		end
		if removed == 0 then
			return Net.Fail("None of those pets can be deleted.")
		end
		data.Pets = kept
		refresh(player, data)
		return { Ok = true, Count = removed }
	elseif action == "EquipBest" then
		equipBest(data)
	elseif action == "UnequipAll" then
		for _, pet in data.Pets do
			pet.Equipped = false
		end
	elseif action == "Golden" or action == "Rainbow" then
		return craft(player, data, argument, action)
	else
		return Net.Fail("Unknown action.")
	end

	refresh(player, data)
	return { Ok = true }
end

function PetService.Init()
	Remotes.Hatch.OnServerInvoke = function(player, eggId, count)
		if not Net.RateLimit(player, "Hatch", 0.45) then
			return Net.Fail("Slow down!")
		end
		return PetService.Hatch(player, eggId, count, false)
	end

	Remotes.PetAction.OnServerInvoke = function(player, action, argument)
		if type(action) ~= "string" or not Net.RateLimit(player, "PetAction", 0.08) then
			return Net.Fail("Slow down!")
		end
		return petAction(player, action, argument)
	end

	Registry.DataService.PlayerLoaded:Connect(function(player, data)
		player:SetAttribute("EquippedPets", equippedString(data))
	end)
end

return PetService
