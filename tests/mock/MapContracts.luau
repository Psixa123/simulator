--!nocheck
-- Map contract test: builds the world with the real MapService (src/server/Services/MapService.luau) in
-- the preview tool's mock Roblox runtime (tools/preview/MapMock.luau) and checks every name, tag,
-- attribute and position that other code relies on, that nothing solid stands where players spawn,
-- sell, walk the main path or chase weather, that each gate's force fields seal the whole width, and the
-- part budget (docs/STYLE_GUIDE.md "Performance").
--
-- tests/mock/run_mock_tests.py runs it through `tools/preview_map.py --script` (the module goes next to
-- MapService and runs like a service) with and without the prop pack, and reads the results from the
-- printed "MAPTEST ..." lines.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapLayout = require(Shared.Config.MapLayout)
local Zones = require(Shared.Config.Zones)
local Pets = require(Shared.Config.Pets)
local Hazards = require(Shared.Hazards)
local MapService = require(script.Parent.MapService)

local MapContracts = {}

local PART_BUDGET = 12000
local BODY_BOTTOM, BODY_TOP = 1.05, 6 -- the space a standing player fills above the walkable surfaces

local passes, failures = 0, 0
local function check(name: string, condition: boolean, detail: any?)
	if condition then
		passes += 1
	else
		failures += 1
		print("MAPTEST FAIL " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local function flat(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

local function near(a: number, b: number, epsilon: number?): boolean
	return math.abs(a - b) <= (epsilon or 0.05)
end

local function descendants(root: Instance, className: string)
	local list = {}
	for _, item in root:GetDescendants() do
		if item:IsA(className) then
			table.insert(list, item)
		end
	end
	return list
end

-- World-space bounding box of a part (its oriented box)
local function bounds(part: BasePart): (Vector3, Vector3)
	local half = part.Size / 2
	local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				local corner = part.CFrame * Vector3.new(half.X * x, half.Y * y, half.Z * z)
				low = low:Min(corner)
				high = high:Max(corner)
			end
		end
	end
	return low, high
end

local function inside(part: BasePart, point: Vector3): boolean
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	return math.abs(localPoint.X) <= half.X + 1e-3 and math.abs(localPoint.Y) <= half.Y + 1e-3 and math.abs(localPoint.Z) <= half.Z + 1e-3
end

-- The preview mock resolves CollectionService:AddTag(instance, tag) to the generic Instance:AddTag (the
-- service itself gets "tagged"), so record tags here: raw fields on the service object win over the mock's
-- method lookup. Only in the mock: a real service is userdata.
local function recordTags()
	if type(CollectionService) ~= "table" then
		return
	end
	local tags = setmetatable({}, { __mode = "k" })
	rawset(CollectionService, "AddTag", function(_, instance, tag)
		tags[instance] = tags[instance] or {}
		tags[instance][tag] = true
	end)
	rawset(CollectionService, "HasTag", function(_, instance, tag)
		return tags[instance] ~= nil and tags[instance][tag] == true
	end)
end

function MapContracts.Init()
	recordTags()
	MapService.Init()

	local map = Workspace:FindFirstChild("Map")
	check("Workspace.Map exists", map ~= nil)
	if not map then
		print(string.format("MAPTEST DONE %d passed, %d failed", passes, failures))
		return
	end

	------------------------------------------------------------------ folders
	local hub = map:FindFirstChild("StormStation")
	check("Map.StormStation folder", hub ~= nil and hub:IsA("Folder"))
	local walls = map:FindFirstChild("Boundaries")
	check("Map.Boundaries folder", walls ~= nil and walls:IsA("Folder"))
	local regionFolders = { [0] = hub }
	for zoneId, zone in Zones do
		if type(zoneId) == "number" then
			local zoneFolder = map:FindFirstChild(zone.Key)
			check("Map." .. zone.Key .. " folder", zoneFolder ~= nil and zoneFolder:IsA("Folder"))
			regionFolders[zoneId] = zoneFolder
		end
	end
	if walls then
		local boundaries = descendants(walls, "BasePart")
		check("boundary walls exist", #boundaries >= 4, #boundaries)
		-- covered[side] = x ranges the side walls block (-1 = north, 1 = south); ends = x of the end walls
		local covered, ends = { [-1] = {}, [1] = {} }, {}
		for _, wall in boundaries do
			check("boundary walls are invisible and solid", wall.Transparency == 1 and wall.CanCollide, wall.Name)
			-- Roblox cuts a part to 2048 studs per axis: a longer wall would leave gaps
			local size = wall.Size
			check("boundary walls fit Roblox's 2048-stud part limit", math.max(size.X, size.Y, size.Z) <= 2048, size)
			local low, high = bounds(wall)
			if size.X > size.Z then
				local side = if wall.Position.Z < 0 then -1 else 1
				check("side walls stand just outside the playable strip", math.abs(math.abs(wall.Position.Z) - (MapLayout.HalfWidth + 2)) < 0.5, wall.Position)
				table.insert(covered[side], { low.X, high.X })
			else
				table.insert(ends, wall.Position.X)
				check("end walls span the playable strip", high.Z >= MapLayout.HalfWidth and low.Z <= -MapLayout.HalfWidth, size)
			end
		end
		table.sort(ends)
		check("a wall at each end of the world", #ends == 2 and ends[1] < MapLayout.HubStart and ends[2] > MapLayout.WorldEnd, table.concat(ends, ", "))
		for side, ranges in covered do
			-- no gap from the west wall to the east wall
			table.sort(ranges, function(a, b)
				return a[1] < b[1]
			end)
			local reach = (ends[1] or MapLayout.HubStart) + 2
			for _, range in ranges do
				if range[1] <= reach + 0.01 then
					reach = math.max(reach, range[2])
				end
			end
			check((if side < 0 then "north" else "south") .. " side walls run end to end without gaps", reach >= (ends[2] or MapLayout.WorldEnd) - 2, reach)
		end
	end

	-- Solid parts, for the "nothing stands in the way" checks
	local solids = {}
	for _, item in map:GetDescendants() do
		if item:IsA("BasePart") and item.CanCollide then
			local low, high = bounds(item)
			table.insert(solids, { Part = item, Low = low, High = high })
		end
	end
	-- The first solid part (other than `allowed` ones) in the column a player fills at (x, z)
	local function blocker(position: Vector3, radius: number, allowed): BasePart?
		for _, solid in solids do
			local low, high = solid.Low, solid.High
			if
				high.Y > BODY_BOTTOM
				and low.Y < BODY_TOP
				and low.X < position.X + radius
				and high.X > position.X - radius
				and low.Z < position.Z + radius
				and high.Z > position.Z - radius
				and not (allowed and allowed(solid.Part))
			then
				return solid.Part
			end
		end
		return nil
	end
	local function clear(name: string, position: Vector3, radius: number, allowed)
		local part = blocker(position, radius, allowed)
		check(name, part == nil, part and part:GetFullName())
	end

	------------------------------------------------------------------ spawn
	local spawns = descendants(Workspace, "SpawnLocation")
	check("exactly one SpawnLocation", #spawns == 1, #spawns)
	local spawn = hub and hub:FindFirstChild("Spawn")
	check("StormStation.Spawn is the SpawnLocation", spawn ~= nil and spawn:IsA("SpawnLocation"))
	if spawn then
		check("spawn at MapLayout.Spawn", flat(spawn.Position, MapLayout.Spawn) < 0.05, spawn.Position)
		check("spawn stands on the ground", spawn.Position.Y > -1 and spawn.Position.Y < 1.5, spawn.Position.Y)
		check("spawn faces +X", spawn.CFrame.LookVector:Dot(Vector3.xAxis) > 0.99, spawn.CFrame.LookVector)
		check("spawn is neutral, no force field", spawn.Neutral == true and spawn.Duration == 0)
	end
	clear("nothing solid on the hub spawn", MapLayout.Spawn, 6, function(part)
		return part == spawn
	end)
	for zoneId = 1, MapLayout.ZoneCount do
		clear("nothing solid at zone " .. zoneId .. "'s spawn", MapLayout.ZoneSpawn(zoneId).Position, 4)
	end
	clear("nothing solid at the arena spawn", MapLayout.ArenaSpawn().Position, 3)

	------------------------------------------------------------------ main path
	-- Players walk the middle of the island from the hub spawn to the end of the world; only the gates'
	-- force-field doors (which open when a zone is unlocked) may stand on it
	local function isDoor(part: BasePart): boolean
		return part.Name == "Door" and CollectionService:HasTag(part, "ZoneBarrier")
	end
	local blocked = {}
	for x = MapLayout.Spawn.X + 8, MapLayout.WorldEnd - 4, 3 do
		local part = blocker(Vector3.new(x, 0, 0), 2.5, isDoor)
		if part then
			table.insert(blocked, string.format("x=%d %s", x, part:GetFullName()))
		end
	end
	check("the main path is clear", #blocked == 0, table.concat(blocked, "; ", 1, math.min(#blocked, 4)))

	------------------------------------------------------------------ sell pads
	local pads = {}
	for _, item in map:GetDescendants() do
		if item:IsA("Model") and item.Name == "SellPad" then
			table.insert(pads, item)
		end
	end
	check("seven sell pads", #pads == 1 + MapLayout.ZoneCount, #pads)
	for zoneId = 0, MapLayout.ZoneCount do
		local at = MapLayout.SellPad(zoneId)
		local found = nil
		for _, pad in pads do
			local glow = pad:FindFirstChild("PadGlow")
			if glow and flat(glow.Position, at) < 0.1 then
				found = pad
				check("PadGlow tagged Pulse (region " .. zoneId .. ")", CollectionService:HasTag(glow, "Pulse"))
				check("PadGlow at ground level (region " .. zoneId .. ")", glow.Position.Y > -1 and glow.Position.Y < 1.5, glow.Position.Y)
			end
		end
		check("sell pad at MapLayout.SellPad(" .. zoneId .. ")", found ~= nil)
		if found then
			check("sell pad " .. zoneId .. " in its region folder", regionFolders[zoneId] ~= nil and found:IsDescendantOf(regionFolders[zoneId]))
		end
		clear("nothing solid on sell pad " .. zoneId, at, MapLayout.SellPadRadius - 1, function(part)
			return found ~= nil and part:IsDescendantOf(found)
		end)
	end

	------------------------------------------------------------------ prompts
	local prompts = descendants(map, "ProximityPrompt")
	local function promptsWith(attribute: string, value)
		local list = {}
		for _, prompt in prompts do
			if prompt:GetAttribute(attribute) == value then
				table.insert(list, prompt)
			end
		end
		return list
	end
	for _, prompt in prompts do
		check("prompt hosts are parts", prompt.Parent ~= nil and prompt.Parent:IsA("BasePart"), prompt:GetFullName())
	end

	-- egg stations
	for zoneId = 1, MapLayout.ZoneCount do
		local eggId = Zones[zoneId].Egg
		check("zone " .. zoneId .. "'s egg exists", Pets.Eggs[eggId] ~= nil, eggId)
		local list = promptsWith("EggId", eggId)
		check("one egg prompt for " .. eggId, #list == 1, #list)
		local prompt = list[1]
		if prompt then
			local station = MapLayout.EggStation(zoneId)
			check("egg prompt host over MapLayout.EggStation(" .. zoneId .. ")", flat(prompt.Parent.Position, station) < 1, prompt.Parent.Position)
			check("egg prompt in zone " .. zoneId .. "'s folder", prompt:IsDescendantOf(regionFolders[zoneId]))
			check("egg prompt reach", prompt.MaxActivationDistance >= 14, prompt.MaxActivationDistance)
			local spinner = nil
			for _, item in prompt.Parent.Parent:GetDescendants() do
				if item:IsA("Model") and CollectionService:HasTag(item, "Spin") then
					spinner = item
				end
			end
			check("egg model spins at station " .. zoneId, spinner ~= nil)
			-- players come from the path: the ground between the path and the incubator is free
			clear("the way to egg station " .. zoneId .. " is clear", Vector3.new(station.X, 0, station.Z - 12), 2)
		end
	end

	-- hub panels
	local stations = MapLayout.HubStations
	for panel, station in { Upgrades = stations.Upgrades, Shop = stations.Shop, Rewards = stations.Rewards, Rebirth = stations.Rebirth } do
		local list = promptsWith("Panel", panel)
		check("one " .. panel .. " prompt", #list == 1, #list)
		if list[1] then
			check(panel .. " prompt at its station", flat(list[1].Parent.Position, station) < 8, list[1].Parent.Position)
			check(panel .. " prompt in the hub", list[1]:IsDescendantOf(hub))
		end
	end

	------------------------------------------------------------------ gates
	for zoneId = 2, MapLayout.ZoneCount do
		local zoneFolder = regionFolders[zoneId]
		local gate = zoneFolder and zoneFolder:FindFirstChild("Gate" .. zoneId)
		check("Gate" .. zoneId .. " model", gate ~= nil and gate:IsA("Model"))
		if gate then
			local x = MapLayout.ZoneStart(zoneId)
			local barriers, door, host = 0, nil, nil
			for _, item in gate:GetDescendants() do
				if item:IsA("BasePart") and CollectionService:HasTag(item, "ZoneBarrier") then
					check("ZoneBarrier part has Zone=" .. zoneId, item:GetAttribute("Zone") == zoneId, item.Name)
					if item.Name == "Barrier" then
						barriers += 1
					elseif item.Name == "Door" then
						door = item
					elseif item.Name == "PromptHost" then
						host = item
					end
				end
			end
			check("Gate" .. zoneId .. " has two barriers", barriers == 2, barriers)
			check("Gate" .. zoneId .. " has a door", door ~= nil)
			check("Gate" .. zoneId .. " prompt host tagged ZoneBarrier", host ~= nil)
			if door then
				check("Gate" .. zoneId .. " door on the path at ZoneStart", near(door.Position.X, x, 0.1) and math.abs(door.Position.Z) < 0.1, door.Position)
				local info = door:FindFirstChild("LockInfo")
				check("Gate" .. zoneId .. " door has the LockInfo billboard", info ~= nil and info:IsA("BillboardGui"))
			end
			local list = promptsWith("GateZone", zoneId)
			check("one GateZone=" .. zoneId .. " prompt", #list == 1, #list)
			if list[1] then
				check("gate prompt tagged GatePrompt", CollectionService:HasTag(list[1], "GatePrompt"))
				check("gate prompt in front of the door", flat(list[1].Parent.Position, Vector3.new(x, 0, 0)) < 4)
			end
			-- the force fields (and the arch between them) seal the whole width at the gate
			local gaps = {}
			for z = -MapLayout.HalfWidth + 1, MapLayout.HalfWidth - 1, 1 do
				local point = Vector3.new(x, 3, z)
				local sealed = false
				for _, item in gate:GetDescendants() do
					if item:IsA("BasePart") and item.CanCollide and inside(item, point) then
						sealed = true
						break
					end
				end
				if not sealed then
					table.insert(gaps, z)
				end
			end
			check("Gate" .. zoneId .. " seals the whole width", #gaps == 0, table.concat(gaps, ",", 1, math.min(#gaps, 8)))
		end
	end
	check("no gate before the first zone", regionFolders[1] == nil or regionFolders[1]:FindFirstChild("Gate1") == nil)

	------------------------------------------------------------------ boards and the arena
	local forecast = {}
	local arenaGuis = {}
	for _, item in map:GetDescendants() do
		if item:IsA("SurfaceGui") and CollectionService:HasTag(item, "ForecastGui") then
			table.insert(forecast, item)
		elseif item:IsA("BillboardGui") and CollectionService:HasTag(item, "ArenaGui") then
			table.insert(arenaGuis, item)
		end
	end
	check("one ForecastGui", #forecast == 1, #forecast)
	if forecast[1] then
		local gui = forecast[1]
		check("ForecastGui in the hub", gui:IsDescendantOf(hub))
		for _, name in { "Title", "Label", "Countdown", "StormName", "Rainbow", "UpcomingTitle", "Hint" } do
			local label = gui:FindFirstChild(name)
			check("ForecastGui." .. name .. " TextLabel", label ~= nil and label:IsA("TextLabel"))
		end
		for index = 1, 3 do
			local row = gui:FindFirstChild("Upcoming" .. index)
			check("ForecastGui.Upcoming" .. index, row ~= nil)
			for _, name in { "When", "Storm", "In" } do
				local label = row and row:FindFirstChild(name)
				check("ForecastGui.Upcoming" .. index .. "." .. name, label ~= nil and label:IsA("TextLabel"))
			end
		end
	end
	check("one ArenaGui", #arenaGuis == 1, #arenaGuis)
	if arenaGuis[1] then
		local gui = arenaGuis[1]
		check("ArenaGui.Title and Countdown", gui:FindFirstChild("Title") ~= nil and gui:FindFirstChild("Countdown") ~= nil)
		local anchor = gui.Adornee or gui.Parent
		check("ArenaGui over the arena", anchor ~= nil and flat(anchor.Position, MapLayout.ArenaCenter) < 1)
	end
	local pylons = 0
	for _, item in map:GetDescendants() do
		if item:IsA("BasePart") and CollectionService:HasTag(item, "ArenaPylon") then
			pylons += 1
			check("pylon around the arena", flat(item.Position, MapLayout.ArenaCenter) < MapLayout.ArenaRadius + 10, item.Position)
		end
	end
	check("eight arena pylons", pylons == 8, pylons)

	for kind, position in MapLayout.Leaderboards do
		local board = MapService.Leaderboards[kind]
		check("leaderboard " .. kind, board ~= nil)
		if board then
			check(kind .. " board has ten rows", #board.Rows == 10, #board.Rows)
			local row = board.Rows[1]
			check(kind .. " rows have Frame, Name and Value", row ~= nil and row.Frame:IsA("Frame") and row.Name:IsA("TextLabel") and row.Value:IsA("TextLabel"))
			check(kind .. " board has a status label", board.Status ~= nil and board.Status:IsA("TextLabel"))
			local gui = row and row.Frame:FindFirstAncestorWhichIsA("SurfaceGui")
			local screen = gui and gui.Parent
			check(kind .. " board stands at its spot", screen ~= nil and screen:IsA("BasePart") and flat(screen.Position, position) < 6, screen and screen.Position)
		end
	end

	------------------------------------------------------------------ hazards
	for zoneId = 1, MapLayout.ZoneCount do
		local zone = Zones[zoneId]
		if zone.Hazard and zone.Hazard.Kind == "Heat" then
			local spots = Hazards.CoolingSpots(zoneId)
			local areas = {}
			for _, item in regionFolders[zoneId]:GetChildren() do
				if item:IsA("Model") and item.Name == "CoolingArea" then
					table.insert(areas, item)
				end
			end
			check("a cooling area per cooling spot in zone " .. zoneId, #areas == #spots, #areas)
			for _, spot in spots do
				local found = false
				for _, area in areas do
					local floor = area:FindFirstChild("CoolFloor")
					if floor and flat(floor.Position, spot) < 0.5 then
						found = true
					end
				end
				check("cooling area at " .. tostring(spot), found)
			end
		end
	end

	------------------------------------------------------------------ weather fields
	for zoneId = 1, MapLayout.ZoneCount do
		local minX, maxX, minZ, maxZ = MapLayout.FieldBounds(zoneId)
		local field = regionFolders[zoneId] and regionFolders[zoneId]:FindFirstChild("Field")
		check("zone " .. zoneId .. " has a Field folder", field ~= nil)
		if field then
			local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
			local lines = 0
			for _, item in field:GetDescendants() do
				if item:IsA("BasePart") and item.Name == "FieldPad" then
					local a, b = bounds(item)
					low, high = low:Min(a), high:Max(b)
				elseif item:IsA("BasePart") and item.Name == "FieldLine" then
					lines += 1
				end
			end
			check(
				"zone " .. zoneId .. "'s field pads cover exactly MapLayout.FieldBounds",
				near(low.X, minX) and near(high.X, maxX) and near(low.Z, minZ) and near(high.Z, maxZ),
				string.format("%.2f..%.2f x %.2f..%.2f", low.X, high.X, low.Z, high.Z)
			)
			check("zone " .. zoneId .. "'s field top at y = 0", near(high.Y, 0), high.Y)
			check("zone " .. zoneId .. "'s field has its dashed border", lines >= 40, lines)
			-- the field is open ground for chasing weather
			local inField = {}
			for x = minX + 4, maxX - 4, 8 do
				for z = minZ + 4, maxZ - 4, 8 do
					local part = blocker(Vector3.new(x, 0, z), 1)
					if part then
						table.insert(inField, string.format("(%d,%d) %s", x, z, part:GetFullName()))
					end
				end
			end
			check("zone " .. zoneId .. "'s field is clear", #inField == 0, table.concat(inField, "; ", 1, math.min(#inField, 4)))
		end
	end

	------------------------------------------------------------------ decoration and budget
	local spinningBlades = 0
	for _, item in map:GetDescendants() do
		if item:IsA("Model") and item.Name == "WindmillBlades" and CollectionService:HasTag(item, "Spin") and item:GetAttribute("SpinAxis") == "Z" then
			spinningBlades += 1
		end
	end
	check("windmill blades spin", spinningBlades >= 1, spinningBlades)

	-- Directed particles (steam, smoke, sparkles) rise: their face points up on the part that emits them,
	-- whichever way the part is turned (a part-built cylinder's Top face points sideways)
	local FACES = {
		[Enum.NormalId.Top] = function(c)
			return c.UpVector
		end,
		[Enum.NormalId.Bottom] = function(c)
			return -c.UpVector
		end,
		[Enum.NormalId.Right] = function(c)
			return c.RightVector
		end,
		[Enum.NormalId.Left] = function(c)
			return -c.RightVector
		end,
		[Enum.NormalId.Front] = function(c)
			return c.LookVector
		end,
		[Enum.NormalId.Back] = function(c)
			return -c.LookVector
		end,
	}
	local directed = 0
	for _, emitter in descendants(map, "ParticleEmitter") do
		local host = emitter.Parent
		if host:IsA("BasePart") and emitter.SpreadAngle.X < 90 and emitter.SpreadAngle.Y < 90 then
			directed += 1
			local direction = FACES[emitter.EmissionDirection](host.CFrame)
			check("directed particles rise", direction.Y > 0.9, host:GetFullName() .. " emits along " .. tostring(direction))
		end
	end
	check("there are rising particles", directed > 0, directed)

	local parts = #descendants(map, "BasePart")
	check("part budget", parts <= PART_BUDGET, parts)
	print(string.format("MAPTEST PARTS %d", parts))
	print(string.format("MAPTEST DONE %d passed, %d failed", passes, failures))
end

return MapContracts
