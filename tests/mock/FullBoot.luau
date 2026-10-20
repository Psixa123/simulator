--!nocheck
-- Full-boot simulation: boots every server service the way src/server/Main.server.luau does (the real
-- script when tests/mock/run_mock_tests.py injects it as ServerScriptService.Server.MainBoot, otherwise
-- the copy of its ORDER below), with the real MapService and WorldProps (with or without the prop pack),
-- then plays a player through the mock's Player / Humanoid / remote stand-ins (tools/preview/MapMock.luau,
-- "players, characters, remotes, data stores"):
--   * the player joins, DataService loads their data, PlayerService spawns the character on the hub spawn
--     and puts the Storm Vacuum in their hand
--   * the character walks (no physics: step by step over the solid parts' boxes, climbing at most
--     MAX_STEP studs, never through anything solid, never off the edge) from the spawn to a zone 1 cell
--   * the server path: Remotes.Catch "Start" <cell id> -> CatchTarget, the cell drains, energy rises
--   * the client path: the real DataController, EffectsController and VacuumController run as the
--     player's client (stand-ins for the rest of the UI); Tool:Activate() with the mouse over the cell
--     (desktop) and without a mouse (phone: nearest cell) -> VacuumController.update -> Catch request
--   * the character dies, PlayerService respawns it (CharacterAutoLoads is off) and the vacuum works again
--   * the boundaries: from the hub spawn, walking sideways and west ends at a boundary wall, not the edge
-- Results are printed as "BOOTTEST ..." lines, read by tests/mock/run_mock_tests.py (it runs this through
-- tools/preview_map.py --script with the client modules bundled, with and without the prop pack).
-- Standalone (server checks only): python3 tools/preview_map.py --script tests/mock/FullBoot.luau
--   --dump-only --keep-going --sim-seconds 240

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapLayout = require(Shared.Config.MapLayout)
local Zones = require(Shared.Config.Zones)
local GameConfig = require(Shared.Config.GameConfig)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Registry)
local MockTest = MockTest -- the mock's test API (tools/preview/MapMock.luau); nil in Roblox

local FullBoot = {}

-- src/server/Main.server.luau's ORDER, used when the real script isn't injected
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
}

local MAX_STEP = 2.2 -- studs a character climbs without jumping
local BODY = 5 -- studs of body above the feet that must be free
local RADIUS = 1 -- half the character's width
local FRAME = 1 / 20

local passes, failures = 0, 0
local function check(name: string, condition: any, detail: any?)
	if condition then
		passes += 1
	else
		failures += 1
		print("BOOTTEST FAIL " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
	return condition
end
local function note(text: string)
	print("BOOTTEST NOTE " .. text)
end

local function waitUntil(condition: () -> any, timeout: number, step: number?): any
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local value = condition()
		if value then
			return value
		end
		task.wait(step or 0.1)
	end
	return condition()
end

local function warningsMatching(pattern: string)
	local list = {}
	for _, message in MockTest.Warnings do
		if string.find(message, pattern) then
			table.insert(list, message)
		end
	end
	return list
end

---------------------------------------------------------------------------------------------------- world geometry
-- Boxes of every solid part (world-axis bounds), bucketed on a 32-stud grid for the walk
local GRID = 32
local solids = {}
local buckets = {}

local function bounds(part: BasePart): (Vector3, Vector3)
	local c = part.CFrame
	local half = part.Size / 2
	local r, u, l = c.RightVector, c.UpVector, c.LookVector
	local extent = Vector3.new(
		math.abs(r.X) * half.X + math.abs(u.X) * half.Y + math.abs(l.X) * half.Z,
		math.abs(r.Y) * half.X + math.abs(u.Y) * half.Y + math.abs(l.Y) * half.Z,
		math.abs(r.Z) * half.X + math.abs(u.Z) * half.Y + math.abs(l.Z) * half.Z
	)
	return c.Position - extent, c.Position + extent
end

local function isCharacterPart(part: Instance): boolean
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then
			return true
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return false
end

local function collectSolids()
	table.clear(solids)
	table.clear(buckets)
	for _, item in Workspace:GetDescendants() do
		if item:IsA("BasePart") and item.CanCollide and item.ClassName ~= "Terrain" and not isCharacterPart(item) then
			local low, high = bounds(item)
			local solid = { Part = item, Low = low, High = high }
			table.insert(solids, solid)
			for gx = math.floor(low.X / GRID), math.floor(high.X / GRID) do
				for gz = math.floor(low.Z / GRID), math.floor(high.Z / GRID) do
					local key = gx * 100000 + gz
					buckets[key] = buckets[key] or {}
					table.insert(buckets[key], solid)
				end
			end
		end
	end
end

local function solidsNear(x: number, z: number)
	return buckets[math.floor(x / GRID) * 100000 + math.floor(z / GRID)] or {}
end

-- The highest walkable top under (x, z) that a character with its feet at `feet` can stand on
local function groundAt(x: number, z: number, feet: number): (number?, BasePart?)
	local best, bestPart = nil, nil
	for _, solid in solidsNear(x, z) do
		local low, high = solid.Low, solid.High
		if x >= low.X and x <= high.X and z >= low.Z and z <= high.Z and high.Y <= feet + MAX_STEP then
			if not best or high.Y > best then
				best, bestPart = high.Y, solid.Part
			end
		end
	end
	return best, bestPart
end

-- The first solid part in the space a character standing at (x, feet, z) fills
local function blockerAt(x: number, z: number, feet: number): BasePart?
	for _, solid in solidsNear(x, z) do
		local low, high = solid.Low, solid.High
		if
			high.Y > feet + 0.05
			and low.Y < feet + BODY
			and low.X < x + RADIUS
			and high.X > x - RADIUS
			and low.Z < z + RADIUS
			and high.Z > z - RADIUS
		then
			-- a step low enough to climb is ground, not a blocker
			if high.Y > feet + MAX_STEP then
				return solid.Part
			end
		end
	end
	return nil
end

-- Walks the character in a straight line to (x, z), one stud at a time at its WalkSpeed. Returns
-- "ok", "blocked" (with the part) or "fell" (with the spot); stops at the first problem.
local function walkTo(character: Model, x: number, z: number, label: string)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local start = root.Position
	local feet = start.Y - 3
	local dx, dz = x - start.X, z - start.Z
	local distance = math.sqrt(dx * dx + dz * dz)
	local steps = math.max(1, math.ceil(distance))
	local facing = if distance > 0.01 then Vector3.new(dx, 0, dz).Unit else Vector3.xAxis
	local elapsed = 0
	for index = 1, steps do
		local px, pz = start.X + dx * index / steps, start.Z + dz * index / steps
		local ground, groundPart = groundAt(px, pz, feet)
		if not ground or ground < -40 then
			return "fell", Vector3.new(px, feet, pz)
		end
		local blocker = blockerAt(px, pz, ground)
		if blocker then
			return "blocked", blocker, Vector3.new(px, ground, pz)
		end
		feet = ground
		local position = Vector3.new(px, feet + 3, pz)
		character:PivotTo(CFrame.lookAt(position, position + facing))
		elapsed += distance / steps / math.max(humanoid.WalkSpeed, 1)
		if elapsed >= 0.25 then
			task.wait(elapsed)
			elapsed = 0
		end
		local _ = groundPart
	end
	return "ok"
end

---------------------------------------------------------------------------------------------------- the client
local client = { Hints = {}, Running = false }

-- The player's client: the real DataController, EffectsController and VacuumController, stand-ins for
-- the controllers that only draw interface. Returns false when the client modules aren't bundled.
local function startClient(player: Player): boolean
	local scripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	local folder = scripts and scripts:FindFirstChild("Client")
	if not folder then
		return false
	end
	MockTest.SetLocalPlayer(player) -- client modules read Players.LocalPlayer when they load
	local ok, err = pcall(function()
		local clientRegistry = require(folder.Registry)
		client.Registry = clientRegistry
		clientRegistry.DataController = require(folder.Controllers.DataController)
		clientRegistry.SoundController = { Play = function() end, PlayAt = function() end, SetVacuum = function(on)
			client.VacuumSound = on
		end }
		clientRegistry.InterfaceController = {
			Hint = function(text)
				table.insert(client.Hints, text)
			end,
			Notify = function() end,
			BigText = function() end,
		}
		clientRegistry.HudController = { PlaySell = function() end }
		clientRegistry.MegaStormController = { IsActive = function()
			return false
		end, HandleEffect = function() end }
		clientRegistry.HatchOverlay = { Reveal = function() end }
		clientRegistry.EffectsController = require(folder.Controllers.EffectsController)
		clientRegistry.VacuumController = require(folder.Controllers.VacuumController)
	end)
	if not ok then
		note("client modules not runnable here (" .. tostring(err) .. "); run tests/mock/run_mock_tests.py for the client checks")
		return false
	end
	local registry = client.Registry
	registry.DataController.Init()
	registry.EffectsController.Init()
	task.spawn(function()
		registry.DataController.Load()
		client.Loaded = true
		task.spawn(registry.EffectsController.Start)
		task.spawn(registry.VacuumController.Start)
	end)
	-- frames, with Roblox's default camera: behind and above the character, looking where it faces
	client.Running = true
	task.spawn(function()
		while client.Running do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local camera = Workspace.CurrentCamera
			if root and not client.CameraFixed then
				local back = root.CFrame.LookVector
				local eye = root.Position - back * 12 + Vector3.new(0, 6, 0)
				camera.CFrame = CFrame.lookAt(eye, root.Position + back * 10 + Vector3.new(0, 2, 0))
			end
			MockTest.Frame(FRAME)
			task.wait(FRAME)
		end
	end)
	return true
end

---------------------------------------------------------------------------------------------------- boot
function FullBoot.Init()
	if not MockTest then
		error("FullBoot runs in the mock runtime (tools/preview/MapMock.luau), not in Roblox")
	end
	local server = script.Parent.Parent
	local main = server:FindFirstChild("MainBoot")
	if main then
		require(main) -- the real src/server/Main.server.luau: requires, Init in order (pcall), Start spawned
	else
		note("booting with FullBoot's copy of Main.server.luau's ORDER")
		local Services = script.Parent
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
			if Registry[name].Start then
				task.spawn(Registry[name].Start)
			end
		end
	end
end

local function zoneOneCells()
	local folder = Workspace:FindFirstChild("WeatherCells")
	local list = {}
	if folder then
		for _, model in folder:GetChildren() do
			if model:GetAttribute("Zone") == 1 then
				table.insert(list, model)
			end
		end
	end
	return list
end

local function catchTarget(character: Model?): number
	return character and character:GetAttribute("CatchTarget") or 0
end

-- The zone 1 cell nearest the main path, and the spot on the path's side to catch it from
local function pickCell()
	local best, bestScore = nil, math.huge
	for _, model in zoneOneCells() do
		local origin = model:GetAttribute("Origin")
		local score = math.abs(origin.Z) + origin.X * 0.05
		if score < bestScore then
			best, bestScore = model, score
		end
	end
	return best
end

local function runScenario()
	------------------------------------------------------------------ server boot
	local initFailures = warningsMatching("failed to initialise")
	check("every service initialised", #initFailures == 0, table.concat(initFailures, " | "))
	for _, name in ORDER do
		check("Registry." .. name .. " registered", Registry[name] ~= nil)
	end
	local map = Workspace:FindFirstChild("Map")
	check("Workspace.Map built", map ~= nil)
	local stats = Registry.MapService and Registry.MapService.Stats
	if stats then
		note(string.format("map: %d parts, %d pack props, %d part-built props", stats.Parts or -1, stats.Props or -1, stats.Built or -1))
	end
	local cellFolder = Workspace:FindFirstChild("WeatherCells")
	check("Workspace.WeatherCells exists", cellFolder ~= nil)
	waitUntil(function()
		return #zoneOneCells() >= Zones[1].CellCount
	end, 5)
	check("zone 1 has its weather cells", #zoneOneCells() == Zones[1].CellCount, #zoneOneCells())
	collectSolids()

	-- every zone's cells: in the field, not inside anything solid, with ground under them a player can
	-- stand on within vacuum range
	for _, model in (cellFolder and cellFolder:GetChildren() or {}) do
		local origin = model:GetAttribute("Origin")
		local zoneId = model:GetAttribute("Zone")
		local minX, maxX, minZ, maxZ = MapLayout.FieldBounds(zoneId)
		local id = "cell " .. tostring(model:GetAttribute("CellId")) .. " (zone " .. zoneId .. ")"
		check(id .. " is over its field", origin.X >= minX and origin.X <= maxX and origin.Z >= minZ and origin.Z <= maxZ, origin)
		local ground = groundAt(origin.X, origin.Z, origin.Y)
		check(id .. " has ground under it", ground ~= nil, origin)
		if ground then
			check(id .. " is in vacuum range from the ground under it", origin.Y - (ground + 3) <= Formulas.Range({ Upgrades = { Range = 1 } }) - 4, origin.Y - ground)
			check(id .. " leaves standing room under it", blockerAt(origin.X, origin.Z, ground) == nil, origin)
		end
	end

	------------------------------------------------------------------ the player joins
	local player = MockTest.AddPlayer("StormChaser", 4242)
	local hasClient = startClient(player)
	local character = waitUntil(function()
		return player.Character
	end, 15)
	check("the character spawns (CharacterAutoLoads off, PlayerService loads it)", character ~= nil)
	if not character then
		return
	end
	local data = Registry.DataService.Get(player)
	check("DataService loaded the player's data", data ~= nil)
	local root = character:WaitForChild("HumanoidRootPart")
	check("the character spawns at the hub spawn", Vector2.new(root.Position.X - MapLayout.Spawn.X, root.Position.Z - MapLayout.Spawn.Z).Magnitude < 8, root.Position)
	local feet = root.Position.Y - 3
	local ground = groundAt(root.Position.X, root.Position.Z, feet + 0.01)
	check("the character stands on something", ground ~= nil and math.abs(ground - feet) < 0.6, ground)
	check("nothing solid inside the spawned character", blockerAt(root.Position.X, root.Position.Z, feet) == nil)
	local vacuum = waitUntil(function()
		return character:FindFirstChild("StormVacuum")
	end, 5)
	check("the Storm Vacuum is in the character's hand", vacuum ~= nil and vacuum:IsA("Tool"))
	check("the vacuum has a Handle (RequiresHandle)", vacuum and vacuum:FindFirstChild("Handle") ~= nil)
	check("the Storm Tank is on the character's back", waitUntil(function()
		return character:FindFirstChild("StormTank")
	end, 5) ~= nil)
	if hasClient then
		check("the client loaded the player's data", waitUntil(function()
			return client.Loaded
		end, 10))
	end

	------------------------------------------------------------------ the boundaries around the hub
	local spawnAt = root.Position
	local function describe(result, what, where)
		return result .. " " .. (if typeof(what) == "Instance" then what:GetFullName() else tostring(what)) .. (if where then " " .. tostring(where) else "")
	end
	-- straight out sideways from lanes around the spawn (and the hub's ends): a wall stops every walk
	for _, side in { -1, 1 } do
		local reachedWall, fell = 0, {}
		for _, x in { spawnAt.X, spawnAt.X - 10, spawnAt.X + 10, MapLayout.HubStart + 4, -150, -20, 20 } do
			character:PivotTo(CFrame.new(x, spawnAt.Y, 0))
			local result, what, where = walkTo(character, x, side * (MapLayout.HalfWidth + 40), "side")
			if result == "fell" then
				table.insert(fell, string.format("x=%d %s", x, describe(result, what, where)))
			elseif result == "blocked" and what.Name == "Boundary" then
				reachedWall += 1
			end
		end
		local name = if side < 0 then "north" else "south"
		check("walking " .. name .. " from the hub never leaves the island", #fell == 0, table.concat(fell, "; "))
		check("walking " .. name .. " from the hub ends at a boundary wall", reachedWall > 0)
	end
	for _, z in { 0, -30, 30, -100, 100 } do
		character:PivotTo(CFrame.new(spawnAt.X, spawnAt.Y, z))
		local westResult, westWhat, westWhere = walkTo(character, MapLayout.HubStart - 120, z, "west")
		check("walking west from the hub (z = " .. z .. ") ends at something solid, not the edge", westResult == "blocked", describe(westResult, westWhat, westWhere))
		if z == 0 and westResult == "blocked" then
			note("walking west along the path stops at " .. westWhat:GetFullName() .. string.format(" (x = %.1f)", root.Position.X))
		end
	end
	-- the hub's benches and lamps stand where players can get to them
	local walls = map and map:FindFirstChild("Boundaries")
	local westWall = -math.huge
	for _, wall in (walls and walls:GetChildren() or {}) do
		if wall:IsA("BasePart") and wall.Size.Z > wall.Size.X and wall.Position.X < 0 then
			westWall = math.max(westWall, wall.Position.X + wall.Size.X / 2)
		end
	end
	local hub = map and map:FindFirstChild("StormStation")
	local decor = hub and hub:FindFirstChild("Decor")
	for _, item in (decor and decor:GetChildren() or {}) do
		if item:IsA("Model") and (item.Name == "Bench" or item.Name == "LampPost") then
			local pivot = item:GetPivot().Position
			check("hub " .. item.Name .. " inside the west wall", pivot.X - 3 > westWall, string.format("x = %.1f, wall face at %.1f", pivot.X, westWall))
		end
	end
	character:PivotTo(CFrame.lookAt(spawnAt, spawnAt + Vector3.xAxis))
	task.wait(0.5)

	------------------------------------------------------------------ walk to zone 1 weather
	local cell = pickCell()
	check("picked a zone 1 cell", cell ~= nil)
	if not cell then
		return
	end
	local cellId = cell:GetAttribute("CellId")
	local origin = cell:GetAttribute("Origin")
	note(string.format("walking to cell %d (%s) at %.0f, %.0f, %.0f", cellId, tostring(cell:GetAttribute("Type")), origin.X, origin.Y, origin.Z))
	local result, what, where = walkTo(character, origin.X - 8, 0, "path")
	check("walking the main path from the hub spawn to zone 1", result == "ok", result .. " " .. (if typeof(what) == "Instance" then what:GetFullName() else tostring(what)) .. " " .. tostring(where))
	result, what, where = walkTo(character, origin.X - 8, origin.Z, "field")
	check("walking into zone 1's field", result == "ok", result .. " " .. (if typeof(what) == "Instance" then what:GetFullName() else tostring(what)) .. " " .. tostring(where))
	local range = Formulas.Range(data)
	local distance = (root.Position - origin).Magnitude
	check("the cell is in vacuum range", distance <= range, string.format("%.1f > %d", distance, range))

	------------------------------------------------------------------ the server path: Catch "Start" <id>
	local function drained(label: string, targetId: number, seconds: number)
		local energy = data.Energy
		local healthBefore = cell.Parent and cell:GetAttribute("Health")
		task.wait(seconds)
		check(label .. ": CatchTarget is the cell", catchTarget(player.Character) == targetId, catchTarget(player.Character))
		check(label .. ": the player's energy rises", data.Energy > energy, string.format("%.1f -> %.1f", energy, data.Energy))
		if cell.Parent and healthBefore then
			check(label .. ": the cell drains", cell:GetAttribute("Health") < healthBefore, string.format("%.1f -> %.1f", healthBefore, cell:GetAttribute("Health")))
		end
	end
	if hasClient then
		Remotes.Catch:FireServer("Start", cellId) -- what VacuumController.request sends
		drained("server path", cellId, 1)
		Remotes.Catch:FireServer("Stop")
		task.wait(0.4)
		check("server path: Stop clears CatchTarget", catchTarget(character) == 0, catchTarget(character))
	else
		-- no client in this run: fire the remote's server event directly
		Remotes.Catch.OnServerEvent:Fire(player, "Start", cellId)
		drained("server path", cellId, 1)
		Remotes.Catch.OnServerEvent:Fire(player, "Stop")
		task.wait(0.4)
	end

	if not hasClient then
		return
	end
	local registry = client.Registry
	check("the client sees the cells (EffectsController)", registry.EffectsController.GetCell(cellId) ~= nil)

	------------------------------------------------------------------ the client path, desktop: mouse over the cell
	local tool = character:FindFirstChild("StormVacuum")
	client.CameraFixed = true
	local eye = root.Position + Vector3.new(-10, 5, 0)
	Workspace.CurrentCamera.CFrame = CFrame.lookAt(eye, cell:GetPivot().Position)
	MockTest.SetMouse(nil) -- the middle of the screen, on the cell
	table.clear(client.Hints)
	tool:Activate()
	check("desktop: VacuumController is holding", registry.VacuumController.IsHolding())
	drained("desktop click", cellId, 1.5)
	tool:Deactivate()
	task.wait(0.5)
	check("desktop: releasing stops the vacuum", catchTarget(character) == 0, catchTarget(character))
	check("desktop: no hint while catching", #client.Hints == 0, table.concat(client.Hints, " | "))
	client.CameraFixed = false

	------------------------------------------------------------------ the client path, phone: no mouse, nearest cell
	UserInputService.MouseEnabled = false
	UserInputService.TouchEnabled = true
	UserInputService.KeyboardEnabled = false
	local caught = data.Stats.CellsCaught
	tool:Activate()
	drained("phone tap", cellId, 1.5)
	local popped = waitUntil(function()
		return cell.Parent == nil or data.Energy >= Formulas.TankCapacity(data) - 1e-6
	end, 40, 0.2)
	check("phone: holding catches the cell completely", popped and cell.Parent == nil, cell.Parent and cell:GetAttribute("Health"))
	check("phone: CellsCaught goes up", data.Stats.CellsCaught > caught, data.Stats.CellsCaught)
	local sawCaught = false
	for _, event in MockTest.ClientEvents do
		if event.Remote == "Effect" and event.Args[1] == "CellCaught" and event.Player == player then
			sawCaught = true
		end
	end
	check("phone: the client got the CellCaught effect", sawCaught)
	tool:Deactivate()
	task.wait(0.3)
	UserInputService.MouseEnabled = true
	UserInputService.TouchEnabled = false
	UserInputService.KeyboardEnabled = true
	note(string.format("energy %.0f / %d, cells caught %d", data.Energy, Formulas.TankCapacity(data), data.Stats.CellsCaught))

	------------------------------------------------------------------ dying and respawning
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	humanoid.Health = 0
	local newCharacter = waitUntil(function()
		return player.Character ~= character and player.Character
	end, Players.RespawnTime + 6)
	check("the character respawns after dying", newCharacter ~= nil)
	if not newCharacter then
		return
	end
	local newTool = waitUntil(function()
		return newCharacter:FindFirstChild("StormVacuum")
	end, 5)
	check("the respawned character holds the vacuum", newTool ~= nil)
	collectSolids()
	local next = pickCell()
	if newTool and next then
		local nextOrigin = next:GetAttribute("Origin")
		local nextId = next:GetAttribute("CellId")
		newCharacter:PivotTo(CFrame.new(nextOrigin.X - 8, 3, nextOrigin.Z))
		task.wait(0.3)
		cell = next
		local sold = data.Energy
		if data.Energy >= Formulas.TankCapacity(data) - 1e-6 then
			Registry.EconomyService.Sell(player, "Pad")
			note(string.format("sold a full tank (%.0f energy) before the respawn check", sold))
		end
		newTool:Activate()
		drained("after respawn", nextId, 1.5)
		newTool:Deactivate()
	end
end

function FullBoot.Start()
	local ok, err = pcall(runScenario)
	check("the scenario ran to the end", ok, err)
	client.Running = false
	local seen = {}
	for _, error in MockTest.Errors do
		local first = string.gsub(error, "\n.*", "")
		if not seen[first] then
			seen[first] = true
			check("no script errors", false, first)
		end
	end
	for _, gap in MockTest.Gaps do
		if not gap.Maybe then
			check("no mock gaps", false, gap.Message .. " at " .. tostring(gap.Where))
		end
	end
	for _, kick in MockTest.Kicks do
		check("nobody was kicked", false, kick.Player .. ": " .. tostring(kick.Message))
	end
	print(string.format("BOOTTEST DONE %d passed, %d failed", passes, failures))
end

return FullBoot
