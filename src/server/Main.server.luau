--!nonstrict
-- Storm Catcher Simulator - server entry point.
-- Requires every service, registers it, then runs Init (setup, in order) and Start (loops).

local Services = script.Parent:WaitForChild("Services")
local Registry = require(Services.Registry)

local ORDER = {
	"MapService",
	"DataService",
	"MonetizationService",
	"PlayerService",
	"EconomyService",
	"UpgradeService",
	"ZoneService",
	"PetService",
	"PetMeshService",
	"BoostService",
	"RewardService",
	"RebirthService",
	"WeatherService",
	"HazardService",
	"MegaStormService",
	"LeaderboardService",
	"AdminService", -- owner-only admin panel commands (uses the services above)
}

for _, name in ORDER do
	Registry[name] = require(Services:WaitForChild(name))
end

for _, name in ORDER do
	local service = Registry[name]
	if service.Init then
		local ok, err = pcall(service.Init)
		if not ok then
			warn(string.format("[Server] %s failed to initialise: %s", name, tostring(err)))
		end
	end
end

for _, name in ORDER do
	local service = Registry[name]
	if service.Start then
		task.spawn(service.Start)
	end
end

print("⛈️ Storm Catcher Simulator server started")
