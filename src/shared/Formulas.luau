--!nonstrict
-- Game math shared by the server (authoritative) and the client (for display).
-- Everything takes the player's data table so both sides always agree.

local Config = script.Parent:WaitForChild("Config")
local GameConfig = require(Config.GameConfig)
local Zones = require(Config.Zones)
local Weather = require(Config.Weather)
local Pets = require(Config.Pets)

local Formulas = {}

local function level(data, upgradeId: string): number
	return (data.Upgrades and data.Upgrades[upgradeId]) or 1
end

---------------------------------------------------------------------------
-- Upgrades
---------------------------------------------------------------------------
function Formulas.UpgradeValue(upgradeId: string, upgradeLevel: number): number
	return GameConfig.Upgrades[upgradeId].Value(upgradeLevel)
end

-- Price to go from `upgradeLevel` to `upgradeLevel + 1` (nil when maxed)
function Formulas.UpgradeCost(upgradeId: string, upgradeLevel: number): number?
	local def = GameConfig.Upgrades[upgradeId]
	if upgradeLevel >= def.MaxLevel then
		return nil
	end
	return def.Cost(upgradeLevel)
end

function Formulas.Power(data): number
	return Formulas.UpgradeValue("Power", level(data, "Power"))
end

function Formulas.Range(data): number
	return Formulas.UpgradeValue("Range", level(data, "Range"))
end

function Formulas.WalkSpeed(data): number
	return Formulas.UpgradeValue("Speed", level(data, "Speed"))
end

function Formulas.BaseTank(data): number
	return Formulas.UpgradeValue("Tank", level(data, "Tank"))
end

---------------------------------------------------------------------------
-- Passes & boosts
---------------------------------------------------------------------------
function Formulas.HasPass(data, passKey: string): boolean
	return data.Passes ~= nil and data.Passes[passKey] == true
end

-- Boost end times are stored as server unix time
function Formulas.BoostActive(data, boostName: string, now: number): boolean
	local endTime = data.Boosts and data.Boosts[boostName]
	return endTime ~= nil and endTime > now
end

function Formulas.TankCapacity(data): number
	local capacity = Formulas.BaseTank(data)
	if Formulas.HasPass(data, "MegaTank") then
		capacity *= GameConfig.PassEffects.MegaTank
	end
	return capacity
end

---------------------------------------------------------------------------
-- Pets
---------------------------------------------------------------------------
function Formulas.PetBonus(petId: string, golden: boolean?): number
	local pet = Pets.Pets[petId]
	if not pet then
		return 0
	end
	return pet.Bonus * (if golden then GameConfig.Pets.GoldenMultiplier else 1)
end

function Formulas.PetMultiplier(data): number
	local total = 1
	for _, pet in data.Pets or {} do
		if pet.Equipped then
			total += Formulas.PetBonus(pet.Id, pet.Golden)
		end
	end
	return total
end

function Formulas.EquipSlots(data): number
	local slots = GameConfig.Pets.BaseEquipSlots
	if Formulas.HasPass(data, "PetSlots") then
		slots += GameConfig.Pets.PassEquipSlots
	end
	return slots
end

function Formulas.EquippedCount(data): number
	local count = 0
	for _, pet in data.Pets or {} do
		if pet.Equipped then
			count += 1
		end
	end
	return count
end

---------------------------------------------------------------------------
-- Multipliers
---------------------------------------------------------------------------
-- How much energy goes into the tank for every point of weather drained
function Formulas.EnergyMultiplier(data, now: number): number
	local multiplier = Formulas.PetMultiplier(data)
	if Formulas.HasPass(data, "DoubleEnergy") then
		multiplier *= GameConfig.PassEffects.DoubleEnergy
	end
	if Formulas.HasPass(data, "VIP") then
		multiplier *= 1 + GameConfig.PassEffects.VipBonus
	end
	if Formulas.BoostActive(data, "Energy", now) then
		multiplier *= GameConfig.Boosts.Energy.Multiplier
	end
	return multiplier
end

function Formulas.RebirthMultiplier(rebirths: number): number
	return 1 + rebirths * GameConfig.Rebirth.VoltsBonus
end

-- Applied to the value of the tank when selling
function Formulas.VoltsMultiplier(data): number
	local multiplier = Formulas.RebirthMultiplier(data.Rebirths or 0)
	if Formulas.HasPass(data, "DoubleVolts") then
		multiplier *= GameConfig.PassEffects.DoubleVolts
	end
	if Formulas.HasPass(data, "VIP") then
		multiplier *= 1 + GameConfig.PassEffects.VipBonus
	end
	return multiplier
end

function Formulas.LuckMultiplier(data, now: number): number
	local luck = 1
	if Formulas.HasPass(data, "LuckyHatcher") then
		luck *= GameConfig.PassEffects.LuckyHatcher
	end
	if Formulas.BoostActive(data, "Luck", now) then
		luck *= GameConfig.Boosts.Luck.Multiplier
	end
	return luck
end

---------------------------------------------------------------------------
-- Rebirth
---------------------------------------------------------------------------
function Formulas.RebirthCost(rebirths: number): number
	return GameConfig.Rebirth.BaseCost * GameConfig.Rebirth.CostGrowth ^ rebirths
end

---------------------------------------------------------------------------
-- Rewards: one "unit" is a full base tank of the best unlocked zone's energy
---------------------------------------------------------------------------
function Formulas.VoltsUnit(data): number
	local zone = Zones[math.clamp(data.Zone or 1, 1, #Zones)]
	return math.floor(Formulas.BaseTank(data) * zone.Value * Formulas.RebirthMultiplier(data.Rebirths or 0))
end

---------------------------------------------------------------------------
-- Weather
---------------------------------------------------------------------------
function Formulas.CellHealth(typeId: string, zoneId: number): number
	local def = Weather.Types[typeId]
	return math.floor(Zones[zoneId].BaseHealth * Weather.Rarities[def.Rarity].HealthMult)
end

-- Volts per unit of energy
function Formulas.CellValue(typeId: string, zoneId: number): number
	local def = Weather.Types[typeId]
	return Zones[zoneId].Value * Weather.Rarities[def.Rarity].ValueMult
end

---------------------------------------------------------------------------
-- Eggs
---------------------------------------------------------------------------
-- Returns { { Id, Chance (0..1) } } with luck applied to Rare+ pets
function Formulas.HatchChances(eggId: string, luck: number)
	local egg = Pets.Eggs[eggId]
	local entries = {}
	local total = 0
	for _, entry in egg.Pets do
		local rarity = Pets.RarityOf(entry.Id)
		local weight = entry.Chance
		if rarity.Order >= 3 then
			weight *= luck
		end
		total += weight
		table.insert(entries, { Id = entry.Id, Weight = weight })
	end
	for _, entry in entries do
		entry.Chance = entry.Weight / total
	end
	return entries
end

---------------------------------------------------------------------------
-- Mega Storm
---------------------------------------------------------------------------
function Formulas.MegaStormReward(data, contribution: number, defeated: boolean): number
	local settings = GameConfig.MegaStorm
	local zone = Zones[math.clamp(data.Zone or 1, 1, #Zones)]
	local outcome = if defeated then settings.DefeatBonus else settings.EscapeMultiplier
	return math.floor(contribution * zone.Value * settings.RewardMultiplier * outcome * Formulas.VoltsMultiplier(data))
end

return Formulas
