--!nonstrict
-- Automated smoke test (client half). Only included in test.project.json builds.
-- Plays through the core loop like a player would:
-- catch -> sell -> upgrade -> hatch -> pets -> zones -> rebirth -> mega storm -> every panel.
-- Prints "[SHOT] label" at interesting moments so an external tool can screenshot the window.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

if not RunService:IsStudio() then
	return
end

local player = Players.LocalPlayer
local passed, failed = 0, 0

local function log(...)
	print("[HARNESS-C]", ...)
end

local function check(name: string, condition: any, detail: any?)
	if condition then
		passed += 1
		log("PASS", name, if detail ~= nil then tostring(detail) else "")
	else
		failed += 1
		warn("[HARNESS-C] FAIL " .. name .. " " .. (if detail ~= nil then tostring(detail) else ""))
	end
end

local function step(name: string, fn: () -> ())
	log("STEP", name)
	local ok, err = xpcall(fn, function(message)
		return tostring(message) .. "\n" .. debug.traceback()
	end)
	if not ok then
		failed += 1
		warn("[HARNESS-C] ERROR in step " .. name .. ": " .. tostring(err))
	end
end

local Command = ReplicatedStorage:WaitForChild("TestCommand", 60)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local MapLayout = require(Shared.Config.MapLayout)
local Zones = require(Shared.Config.Zones)
local Hazards = require(Shared.Hazards)
local Registry = require(script.Parent:WaitForChild("Client"):WaitForChild("Registry"))

-- Wait for the game client to finish starting
local deadline = os.clock() + 90
repeat
	task.wait(0.5)
	local interface = Registry.InterfaceController
	local ready = Registry.DataController and Registry.DataController.Data and interface and interface.HudGui and interface.HudGui.Enabled
until ready or os.clock() > deadline
check("client started", Registry.DataController and Registry.DataController.Data ~= nil)
if not player.Character then
	player.CharacterAdded:Wait()
end
task.wait(5)

local Interface = Registry.InterfaceController
local Data = Registry.DataController

local function stats()
	return Command:InvokeServer("Stats")
end

local function shot(label: string, hold: number?)
	print("[SHOT] " .. label)
	task.wait(hold or 2.2)
end

-- Screenshot from a fixed camera with the HUD hidden
local function scenic(label: string, from: Vector3, target: Vector3)
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(from, target)
	Interface.HudGui.Enabled = false
	task.wait(1)
	shot(label)
	Interface.HudGui.Enabled = true
	camera.CameraType = Enum.CameraType.Custom
end

-- Deliberate error so we know how script errors appear in the Studio log
task.spawn(function()
	error("HARNESS deliberate error (ignore)")
end)

step("world", function()
	local world = Command:InvokeServer("World")
	for key, value in world do
		log("world", key, tostring(value))
	end
	check("map built", world.MapParts > 1500, world.MapParts)
	check("weather cells", world.Cells >= 90, world.Cells)
	check("vacuum tool", world.Tool)
	check("vacuum equipped", world.ToolEquipped)
	check("tank backpack", world.Tank)
	check("overhead tag", world.Overhead)
	check("leaderstats", world.Leaderstats)
	check("gate prompts", world.GatePrompts == 5, world.GatePrompts)
	check("spawned in hub", world.Position.X < 0 and world.Position.Y > 0 and world.Position.Y < 30, world.Position)
	shot("hub_spawn")
	scenic("hub_overview", Vector3.new(-232, 60, 84), Vector3.new(-100, 4, -6))
	scenic("hub_north_row", Vector3.new(-104, 16, 6), Vector3.new(-104, 8, -80))
	scenic("hub_south_row", Vector3.new(-104, 16, -6), Vector3.new(-104, 8, 80))
	scenic("hub_leaderboards", Vector3.new(-150, 16, 0), Vector3.new(-190, 14, -42))
	scenic("meadows_entrance", Vector3.new(-40, 18, 0), Vector3.new(60, 8, 0))
	scenic("gate_thunder", Vector3.new(262, 14, 16), Vector3.new(320, 14, 0))
end)

step("catch and sell", function()
	local id, origin, typeId = Command:InvokeServer("NearestCell", 1)
	check("found a cell", id ~= nil, typeId)
	Command:InvokeServer("Teleport", Vector3.new(origin.X + 8, 4, origin.Z + 8))
	task.wait(1)
	Remotes.Catch:FireServer("Start", id)
	task.wait(1)
	shot("catching", 1.6)
	local now = stats()
	check("energy collected", now.Energy > 0, now.Energy)
	check("client energy replicated", Data.Data.Energy > 0, Data.Data.Energy)
	task.wait(3)
	Remotes.Catch:FireServer("Stop")
	shot("tank_full")
	local before = stats()
	local pad = MapLayout.SellPad(1)
	Command:InvokeServer("Teleport", pad + Vector3.new(0, 4, 0))
	task.wait(0.5)
	shot("sell_pad", 1.5)
	local after = stats()
	check("sold at pad", after.Energy == 0 and after.Volts > before.Volts, after.Volts)
end)

step("upgrades", function()
	Command:InvokeServer("AddVolts", 5e5)
	task.wait(0.3)
	local result = Remotes.BuyUpgrade:InvokeServer("Power", "One")
	check("buy power", result and result.Ok, result and (result.Level or result.Error))
	task.wait(0.3)
	result = Remotes.BuyUpgrade:InvokeServer("Speed", "One")
	check("buy speed", result and result.Ok, result and (result.Level or result.Error))
	task.wait(0.3)
	result = Remotes.BuyUpgrade:InvokeServer("Range", "One")
	check("buy range", result and result.Ok, result and (result.Level or result.Error))
	task.wait(0.3)
	result = Remotes.BuyUpgrade:InvokeServer("Tank", "Max")
	check("buy tank max", result and result.Ok, result and (result.Level or result.Error))
	task.wait(0.3)
	check("upgrades replicated", Data.Data.Upgrades.Power >= 2 and Data.Data.Upgrades.Tank > 2, Data.Data.Upgrades.Tank)
	Command:InvokeServer("AddVolts", 4200)
end)

step("panels", function()
	for _, name in { "Shop", "Upgrades", "Rebirth", "Rewards", "Settings", "Teleport" } do
		Interface.OpenPanel(name)
		task.wait(0.6)
		check("panel " .. name, Interface.IsOpen(name))
		shot("panel_" .. name, 1.4)
	end
	Interface.OpenPanel("Shop", "Boosts")
	task.wait(0.5)
	shot("panel_Shop_boosts", 1.4)
	Interface.OpenPanel("Shop", "Volts")
	task.wait(0.5)
	shot("panel_Shop_volts", 1.4)
	Interface.OpenPanel("Rewards", "Gifts")
	task.wait(0.5)
	shot("panel_Rewards_gifts", 1.4)
	Interface.OpenPanel("Rewards", "Codes")
	task.wait(0.5)
	shot("panel_Rewards_codes", 1.4)
	Interface.OpenPanel("Pets", "Index")
	task.wait(0.6)
	Interface.ClosePanel()
	task.wait(0.3)
	check("panels closed", not Interface.IsOpen())
end)

step("rewards", function()
	local result = Remotes.ClaimDaily:InvokeServer()
	check("claim daily", result and (result.Ok or string.find(result.Error or "", "Come back")), result and (result.Text or result.Error))
	task.wait(1.6)
	result = Remotes.RedeemCode:InvokeServer("release")
	check("redeem code", result and (result.Ok or string.find(result.Error or "", "already")), result and (result.Text or result.Error))
	task.wait(1.6)
	result = Remotes.RedeemCode:InvokeServer("NOTACODE")
	check("bad code rejected", result and not result.Ok)
	result = Remotes.ClaimGift:InvokeServer(1)
	check("gift not ready rejected", result and not result.Ok, result and result.Error)
	result = Remotes.SetSetting:InvokeServer("LowGraphics", true)
	check("set setting", result == true)
	task.wait(0.3)
	check("setting replicated", Data.Data.Settings.LowGraphics == true)
	Remotes.SetSetting:InvokeServer("LowGraphics", false)
end)

step("eggs and pets", function()
	Command:InvokeServer("AddVolts", 1e5)
	local station = MapLayout.EggStation(1)
	Command:InvokeServer("Teleport", station + Vector3.new(-14, 4, -6))
	task.wait(1.2)
	shot("egg_station", 1.4)
	Interface.OpenPanel("Egg", "MeadowEgg")
	task.wait(0.6)
	check("egg panel", Interface.IsOpen("Egg"))
	shot("panel_Egg", 1.4)
	local result = Remotes.Hatch:InvokeServer("MeadowEgg", 1)
	check("hatch", result and result.Ok, result and (result.Error or result.Results[1].Id))
	if result and result.Ok then
		Interface.ClosePanel(true)
		task.delay(0.5, print, "[SHOT] hatch_egg")
		task.delay(2.2, print, "[SHOT] hatch_reveal")
		Registry.HatchOverlay.Play(result, { Hold = 2.6 })
		check("hatch animation finished", not Registry.HatchOverlay.IsPlaying())
	end
	task.wait(0.5)
	local triple = Remotes.Hatch:InvokeServer("MeadowEgg", 3)
	check("triple hatch needs pass", triple and not triple.Ok, triple and triple.Error)

	local count = Command:InvokeServer("GivePets", "Puffling", 6)
	check("pets given", count >= 6, count)
	task.wait(0.5)
	check("pets replicated", #Data.Data.Pets >= 6, #Data.Data.Pets)
	local action = Remotes.PetAction:InvokeServer("EquipBest")
	check("equip best", action and action.Ok)
	task.wait(0.2)
	action = Remotes.PetAction:InvokeServer("Golden", "Puffling")
	check("craft golden", action and action.Ok, action and (action.Uid or action.Error))
	task.wait(0.2)
	action = Remotes.PetAction:InvokeServer("UnequipAll")
	check("unequip all", action and action.Ok)
	task.wait(0.2)
	Remotes.PetAction:InvokeServer("EquipBest")
	task.wait(0.6)
	local equipped = player:GetAttribute("EquippedPets") or ""
	check("equipped attribute", #equipped > 0, equipped)
	for _, petId in { "Droplet", "Sunny", "Prism", "BreezeKing", "Zappy", "VoltBat", "StormLord", "CactusCub", "Scarab", "Icicle", "Frostbite", "YetiKing", "Coal", "PhoenixChick", "InfernoDrake", "Comet", "GalaxyGuardian", "MaelstromSpirit", "FrostColossus", "Sunbeam" } do
		Command:InvokeServer("GivePets", petId, 1)
	end
	Remotes.PetAction:InvokeServer("EquipBest")
	task.wait(1.2)
	local petFolder = Workspace:FindFirstChild("ClientPets")
	check("pets rendered", petFolder and #petFolder:GetChildren() >= 1, petFolder and #petFolder:GetChildren())
	shot("pets_following")
	Interface.OpenPanel("Pets", "Inventory")
	task.wait(1)
	shot("panel_Pets_inventory", 1.6)
	Interface.OpenPanel("Pets", "Index")
	task.wait(1)
	shot("panel_Pets_index", 1.6)
	Interface.ClosePanel()
	task.delay(2.4, print, "[SHOT] hatch_triple")
	Registry.HatchOverlay.Play({
		Egg = "CosmicEgg",
		Results = { { Id = "GalaxyGuardian", New = true }, { Id = "Comet" }, { Id = "Nebula", Golden = true } },
	}, { Hold = 3 })
	check("triple hatch animation", not Registry.HatchOverlay.IsPlaying())
end)

step("zones", function()
	Command:InvokeServer("Hazards", false) -- no lightning stuns during the catch checks
	Command:InvokeServer("AddVolts", 1e13)
	local buy = Remotes.BuyUpgrade:InvokeServer("Power", "Max")
	check("max power", buy and buy.Ok, buy and (buy.Level or buy.Error))
	task.wait(0.2)
	Remotes.BuyUpgrade:InvokeServer("Tank", "Max")
	for zoneId = 2, #Zones do
		task.wait(0.6)
		local result = Remotes.UnlockZone:InvokeServer(zoneId)
		check("unlock " .. Zones[zoneId].Name, result and result.Ok, result and result.Error)
	end
	task.wait(0.5)
	check("zone replicated", Data.Data.Zone == #Zones, Data.Data.Zone)
	for zoneId = 1, #Zones do
		local result = Remotes.Teleport:InvokeServer(zoneId)
		check("teleport " .. Zones[zoneId].Name, result and result.Ok, result and result.Error)
		task.wait(3.4)
		local x0 = MapLayout.ZoneStart(zoneId)
		shot("zone" .. zoneId .. "_arrive", 1.4)
		scenic("zone" .. zoneId .. "_overview", Vector3.new(x0 + 8, 58, 96), Vector3.new(x0 + 190, 2, -20))
		scenic("zone" .. zoneId .. "_plaza", Vector3.new(x0 + 14, 16, 0), Vector3.new(x0 + 70, 8, 0))
		local id, origin, typeId = Command:InvokeServer("NearestCell", zoneId)
		if id then
			Command:InvokeServer("Teleport", Vector3.new(origin.X + 7, 4, origin.Z + 7))
			task.wait(0.8)
			Remotes.Catch:FireServer("Start", id)
			task.wait(0.7)
			print("[SHOT] zone" .. zoneId .. "_catch")
			task.wait(1.2)
			local now = stats()
			check("catch in " .. Zones[zoneId].Name .. " (" .. tostring(typeId) .. ")", now.Energy > 0, now.Energy)
			Remotes.Catch:FireServer("Stop")
			local sell = Remotes.Sell:InvokeServer()
			check("sell button", sell and sell.Ok, sell and sell.Error)
			task.wait(1.2)
		else
			check("cell exists in zone " .. zoneId, false)
		end
	end
end)

step("hazards", function()
	Command:InvokeServer("Hazards", true)
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	local function zoneField(zoneId: number): Vector3
		return Vector3.new(MapLayout.ZoneStart(zoneId) + 200, 4, 20)
	end

	Remotes.Teleport:InvokeServer("Hub")
	task.wait(1.5)
	local baseSpeed = humanoid.WalkSpeed
	local baseGravity = Workspace.Gravity

	-- Frostpeak: slowed while the Storm Boots are below the required level
	task.wait(1.5)
	Remotes.Teleport:InvokeServer(4)
	task.wait(1.5)
	check("cold slows", humanoid.WalkSpeed < baseSpeed, humanoid.WalkSpeed)
	shot("hazard_cold", 1.4)

	-- Upper Atmosphere: low gravity on the client
	task.wait(0.4)
	Remotes.Teleport:InvokeServer(6)
	task.wait(1.5)
	check("cold lifted", humanoid.WalkSpeed == baseSpeed, humanoid.WalkSpeed)
	check("low gravity", Workspace.Gravity < baseGravity, Workspace.Gravity)
	humanoid.Jump = true
	task.wait(0.5)
	shot("hazard_low_gravity", 1)

	-- Ashfall Volcano: heat damage away from the cooling areas, healing inside them
	Command:InvokeServer("Teleport", zoneField(5))
	task.wait(0.5)
	local healthBefore = humanoid.Health
	task.wait(2.5)
	check("heat damage", humanoid.Health < healthBefore, humanoid.Health)
	shot("hazard_heat", 1)
	Command:InvokeServer("Teleport", MapLayout.SellPad(5) + Vector3.new(6, 4, 6))
	local hurt = humanoid.Health
	task.wait(1.5)
	check("cooling area heals", humanoid.Health > hurt, humanoid.Health)
	shot("hazard_cooling_area", 1)

	-- Dune Sea: forced sandstorm
	Command:InvokeServer("Sandstorm")
	Command:InvokeServer("Teleport", zoneField(3))
	task.wait(3)
	local state = ReplicatedStorage:FindFirstChild(Hazards.StateName)
	check("sandstorm active", state and state:GetAttribute(Hazards.SandstormAttribute(3)) == true)
	shot("hazard_sandstorm", 1.4)

	-- Thunder Valley: standing still gets you stunned by the next strike
	Command:InvokeServer("Teleport", zoneField(2))
	local stunned, waited = false, 0
	while not stunned and waited < 18 do
		task.wait(0.1)
		waited += 0.1
		stunned = player.Character:GetAttribute("Stunned") == true
	end
	check("lightning stun", stunned, waited)
	if stunned then
		task.wait(0.2)
		check("stun freezes", humanoid.WalkSpeed == 0, humanoid.WalkSpeed)
		shot("hazard_stunned", 0.6)
	end

	Remotes.Teleport:InvokeServer("Hub")
	task.wait(2)
	check("gravity restored", Workspace.Gravity == baseGravity, Workspace.Gravity)
	check("speed restored", humanoid.WalkSpeed == baseSpeed, humanoid.WalkSpeed)
	Command:InvokeServer("Hazards", false)
end)

step("rebirth", function()
	Command:InvokeServer("AddVolts", 1e13)
	Interface.OpenPanel("Rebirth")
	task.wait(0.5)
	local result = Remotes.Rebirth:InvokeServer()
	check("rebirth", result and result.Ok, result and (result.Rebirths or result.Error))
	task.wait(0.6)
	check("rebirth replicated", Data.Data.Rebirths >= 1 and Data.Data.Upgrades.Power == 1, Data.Data.Rebirths)
	Interface.ClosePanel()
end)

step("mega storm", function()
	Command:InvokeServer("AddVolts", 1e13)
	Remotes.BuyUpgrade:InvokeServer("Power", "Max")
	Command:InvokeServer("Summon")
	local state = ReplicatedStorage:WaitForChild("MegaStormState")
	task.wait(1)
	check("storm warning", state:GetAttribute("Phase") == "Warning", state:GetAttribute("Phase"))
	task.wait(1)
	local teleport = Remotes.Teleport:InvokeServer("Arena")
	check("teleport arena", teleport and teleport.Ok, teleport and teleport.Error)
	task.wait(2)
	shot("mega_warning", 1.4)
	local waited = 0
	while state:GetAttribute("Phase") ~= "Active" and waited < 40 do
		task.wait(1)
		waited += 1
	end
	check("storm active", state:GetAttribute("Phase") == "Active", waited)
	task.wait(3.5)
	check("storm model", Workspace.MegaStorm:FindFirstChild("MegaStorm") ~= nil)
	shot("mega_active", 1.6)
	scenic("mega_overview", Vector3.new(-228, 46, 70), Vector3.new(-112, 34, 0))
	Remotes.Catch:FireServer("Start", -1)
	task.wait(1.2)
	shot("mega_catching", 1.2)
	check("draining storm", (state:GetAttribute("Health") or 0) < (state:GetAttribute("MaxHealth") or 0), state:GetAttribute("Health"))
	waited = 0
	while state:GetAttribute("Phase") == "Active" and waited < 60 do
		task.wait(1)
		waited += 1
	end
	check("storm ended", state:GetAttribute("Phase") ~= "Active", waited)
	task.wait(1)
	shot("mega_defeated", 2)
	task.wait(3)
end)

step("hub", function()
	Remotes.Teleport:InvokeServer("Hub")
	task.wait(2.6)
	Interface.Notify("Harness notification test", "Reward")
	Interface.Notify("Second notification (error style)", "Error")
	Interface.Hint("Harness hint test")
	Registry.EffectsController.Confetti(40)
	task.wait(0.5)
	shot("notifications", 1.5)
	local world = Command:InvokeServer("World")
	check("tank backpack (end)", world.Tank)
	check("overhead tag (end)", world.Overhead)
end)

local summary = string.format("passed=%d failed=%d", passed, failed)
log("SUMMARY", summary)
Command:InvokeServer("Finish", summary)
