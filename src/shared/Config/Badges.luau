--!nonstrict
-- Roblox badges (achievements). Each badge is created by hand on the Creator Dashboard with the icon
-- assets/badges/<Key>.png and its Name / Description from here (docs/BADGES.md); then paste the badge's id
-- into Id. A badge with Id = 0 is never awarded (Studio prints what it would have awarded).
--
-- Rule says when a player has earned it, judged from their saved data only, so AchievementService can
-- award it the moment the data changes and also to players whose old saves already qualify:
--   Join                      - joining the game
--   Stat     Stat, Min        - data.Stats[Stat] >= Min
--   Field    Field, Min       - data[Field] >= Min (Zone, Rebirths, TotalVolts)
--   Indexed  Rarity / Source  - the pet index holds a pet of that rarity / whose Source starts with Source
--   Tier     Tier             - owns a pet of that tier or better (Golden, Rainbow)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pets = require(Shared.Config.Pets)

local Badges = {}

Badges.List = {
	{
		Key = "Welcome",
		Name = "Welcome, Storm Chaser!",
		Description = "Joined Storm Catcher Simulator. Grab your vacuum and catch the weather!",
		Id = 0,
		Rule = { Kind = "Join" },
	},
	{
		Key = "FirstCatch",
		Name = "First Catch",
		Description = "Vacuumed up your very first weather cell.",
		Id = 0,
		Rule = { Kind = "Stat", Stat = "CellsCaught", Min = 1 },
	},
	{
		Key = "RareCatch",
		Name = "Rare Weather",
		Description = "Caught a rare weather cell, like a Rainbow Mist or a Thunderhead.",
		Id = 0,
		Rule = { Kind = "Stat", Stat = "RareCaught", Min = 1 },
	},
	{
		Key = "StormChaser",
		Name = "Storm Chaser",
		Description = "Caught 1,000 weather cells.",
		Id = 0,
		Rule = { Kind = "Stat", Stat = "CellsCaught", Min = 1000 },
	},
	{
		Key = "Zone_Thunder",
		Name = "Thunder Valley",
		Description = "Unlocked Thunder Valley, where lightning never stops striking.",
		Id = 0,
		Rule = { Kind = "Field", Field = "Zone", Min = 2 },
	},
	{
		Key = "Zone_Dunes",
		Name = "Dune Sea",
		Description = "Unlocked the Dune Sea and its whirling dust devils.",
		Id = 0,
		Rule = { Kind = "Field", Field = "Zone", Min = 3 },
	},
	{
		Key = "Zone_Frost",
		Name = "Frostpeak",
		Description = "Unlocked Frostpeak, home of blizzards and aurora spirits.",
		Id = 0,
		Rule = { Kind = "Field", Field = "Zone", Min = 4 },
	},
	{
		Key = "Zone_Volcano",
		Name = "Ashfall Volcano",
		Description = "Unlocked Ashfall Volcano and its fire tornadoes.",
		Id = 0,
		Rule = { Kind = "Field", Field = "Zone", Min = 5 },
	},
	{
		Key = "Zone_Sky",
		Name = "Upper Atmosphere",
		Description = "Reached the Upper Atmosphere, the last zone above the clouds.",
		Id = 0,
		Rule = { Kind = "Field", Field = "Zone", Min = 6 },
	},
	{
		Key = "FirstHatch",
		Name = "First Hatch",
		Description = "Hatched your first Stormling from a cloud egg.",
		Id = 0,
		Rule = { Kind = "Stat", Stat = "EggsHatched", Min = 1 },
	},
	{
		Key = "LegendaryPet",
		Name = "Legendary Luck",
		Description = "Hatched a Legendary Stormling.",
		Id = 0,
		Rule = { Kind = "Indexed", Rarity = "Legendary" },
	},
	{
		Key = "GoldenPet",
		Name = "Solid Gold",
		Description = "Crafted a Golden pet from 5 of the same pet.",
		Id = 0,
		Rule = { Kind = "Tier", Tier = "Golden" },
	},
	{
		Key = "RainbowPet",
		Name = "Over the Rainbow",
		Description = "Crafted a Rainbow pet from 5 Golden pets.",
		Id = 0,
		Rule = { Kind = "Tier", Tier = "Rainbow" },
	},
	{
		Key = "ClimateShift",
		Name = "Climate Shift",
		Description = "Did your first Climate Shift (rebirth).",
		Id = 0,
		Rule = { Kind = "Field", Field = "Rebirths", Min = 1 },
	},
	{
		Key = "MegaStorm",
		Name = "Mega Storm Survivor",
		Description = "Helped take on a Mega Storm in the arena.",
		Id = 0,
		Rule = { Kind = "Stat", Stat = "MegaStorms", Min = 1 },
	},
	{
		Key = "StormChampion",
		Name = "Storm Champion",
		Description = "Won an exclusive pet from a Mega Storm.",
		Id = 0,
		Rule = { Kind = "Indexed", Source = "Mega Storm" },
	},
	{
		Key = "Millionaire",
		Name = "Millionaire",
		Description = "Earned 1,000,000 Volts.",
		Id = 0,
		Rule = { Kind = "Field", Field = "TotalVolts", Min = 1e6 },
	},
	{
		Key = "SecretPet",
		Name = "Secret Discovered",
		Description = "Hatched a Secret Stormling, one of the rarest pets in the game!",
		Id = 0,
		Rule = { Kind = "Indexed", Rarity = "Secret" },
	},
}

Badges.ByKey = {}
for index, badge in Badges.List do
	badge.Order = index
	badge.Icon = "assets/badges/" .. badge.Key .. ".png"
	Badges.ByKey[badge.Key] = badge
end

local function indexed(data, rule): boolean
	if type(data.Index) ~= "table" then
		return false
	end
	for petId in data.Index do
		local pet = Pets.Pets[petId]
		if pet then
			if rule.Rarity and pet.Rarity == rule.Rarity then
				return true
			end
			if rule.Source and type(pet.Source) == "string" and string.sub(pet.Source, 1, #rule.Source) == rule.Source then
				return true
			end
		end
	end
	return false
end

local function ownsTier(data, tierName: string): boolean
	local wanted = Pets.Tiers[tierName].Order
	if type(data.Pets) ~= "table" then
		return false
	end
	for _, pet in data.Pets do
		if Pets.Tiers[Pets.TierOf(pet)].Order >= wanted then
			return true
		end
	end
	return false
end

-- True when the player's data has earned the badge
function Badges.Qualifies(badge, data): boolean
	if type(data) ~= "table" then
		return false
	end
	local rule = badge.Rule
	if rule.Kind == "Join" then
		return true
	elseif rule.Kind == "Stat" then
		local value = type(data.Stats) == "table" and data.Stats[rule.Stat]
		return type(value) == "number" and value >= rule.Min
	elseif rule.Kind == "Field" then
		local value = data[rule.Field]
		return type(value) == "number" and value >= rule.Min
	elseif rule.Kind == "Indexed" then
		return indexed(data, rule)
	elseif rule.Kind == "Tier" then
		return ownsTier(data, rule.Tier)
	end
	return false
end

return Badges
