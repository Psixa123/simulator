--!nocheck
-- Mock test for the server's WorldProps module: finding or inserting the world prop pack
-- (GameConfig.WorldPropsAssetId), reading it whatever the importer did with the names, normalising
-- every prop by its Root cube, and placing painted, scaled props. Runs after RobloxMock.luau and the
-- module sources in one bundle; see run_mock_tests.py.

local failures, passes = 0, 0
local function check(name, condition, detail)
	if condition then
		passes += 1
	else
		failures += 1
		Mock.RealPrint("FAIL " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function near(a, b, epsilon)
	epsilon = epsilon or 1e-4
	if type(a) == "number" then
		return math.abs(a - b) <= epsilon
	end
	return (a - b).Magnitude <= epsilon
end
local function hasMessage(list, pattern)
	local count = 0
	for _, message in list do
		if string.find(message, pattern, 1, true) then
			count += 1
		end
	end
	return count
end
local function sameList(a, b)
	if #a ~= #b then
		return false
	end
	for index, value in a do
		if b[index] ~= value then
			return false
		end
	end
	return true
end

------------------------------------------------------------------------ game tree
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local InsertService = game:GetService("InsertService")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = Mock.Folder("Shared", ReplicatedStorage)
local ConfigFolder = Mock.Folder("Config", Shared)
local GameConfig = { WorldPropsAssetId = 0 }
Mock.Module("GameConfig", ConfigFolder, function()
	return GameConfig
end)

local GREEN = Color3.fromRGB(76, 197, 82)
local LIGHT_GREEN = Color3.fromRGB(142, 227, 107)
local BLUE = Color3.fromRGB(83, 97, 201)
local GREY = Color3.fromRGB(149, 158, 203)
local PACK_COLOR = Color3.fromRGB(200, 100, 50) -- what the importer leaves on every part
local RED = Color3.fromRGB(255, 0, 0)

-- A WorldPropsData like build_world_pack.py writes. Hut is in the data but not in the pack.
local Data = {
	RootSize = 1,
	Order = { "Tree", "Lamp", "Hut", "Rock" },
	Props = {
		Tree = {
			Size = Vector3.new(8, 12, 8),
			Center = Vector3.new(0, 6, 0),
			Footprint = 4,
			Collide = true,
			Paints = { Primary = GREEN, Secondary = LIGHT_GREEN },
			Pieces = {
				{ Name = "Tree.Primary", Paint = "Primary", Kind = "Tint", Color = GREEN, Center = Vector3.new(0, 8, 0), Size = Vector3.new(8, 8, 8), Collide = false },
				{ Name = "Tree.Color_8B5A2B", Paint = "Color_8B5A2B", Kind = "Color", Color = Color3.fromHex("8B5A2B"), Center = Vector3.new(0, 2, 0), Size = Vector3.new(2, 4, 2), Collide = true },
			},
		},
		Lamp = {
			Size = Vector3.new(2.75, 8.75, 1.5),
			Center = Vector3.new(-0.875, 4.375, 0),
			Footprint = 2,
			Collide = false,
			Paints = { Primary = BLUE },
			Pieces = {
				{ Name = "Lamp.Primary", Paint = "Primary", Kind = "Tint", Color = BLUE, Center = Vector3.new(0, 4, 0), Size = Vector3.new(1, 8, 1), Collide = false },
				{ Name = "Lamp.Neon_FFF3B0", Paint = "Neon_FFF3B0", Kind = "Neon", Color = Color3.fromHex("FFF3B0"), Center = Vector3.new(-1.5, 8, 0), Size = Vector3.new(1, 1, 1), Collide = false },
				{ Name = "Lamp.Glass_BDEBFF", Paint = "Glass_BDEBFF", Kind = "Glass", Color = Color3.fromHex("BDEBFF"), Center = Vector3.new(-1.5, 8, 0), Size = Vector3.new(1.5, 1.5, 1.5), Collide = false },
			},
		},
		Rock = {
			Size = Vector3.new(3, 2, 2.5),
			Center = Vector3.new(0, 1, 0),
			Footprint = 1.5,
			Collide = true,
			Paints = { Primary = GREY },
			Pieces = {
				{ Name = "Rock.Primary", Paint = "Primary", Kind = "Tint", Color = GREY, Center = Vector3.new(0, 1, 0), Size = Vector3.new(3, 2, 2.5), Collide = true },
			},
		},
		Hut = {
			Size = Vector3.new(10, 10, 10),
			Center = Vector3.new(0, 5, 0),
			Footprint = 6,
			Collide = true,
			Paints = { Primary = GREY },
			Pieces = {},
		},
	},
}
local dataModule
local function setData(loader)
	if dataModule then
		dataModule:Destroy()
		dataModule = nil
	end
	if loader then
		dataModule = Mock.Module("WorldPropsData", ConfigFolder, loader)
	end
end
setData(function()
	return Data
end)

-- WorldProps reads the pack once, so every scenario requires a fresh copy of the module
local generation = 0
local function fresh()
	generation += 1
	local folder = Mock.Folder("Services" .. generation, ServerScriptService)
	return require(Mock.Module("WorldProps", folder, __sources.WorldProps))
end

------------------------------------------------------------------------ a fake 3D importer
-- The props as designed (studs, Y up, front -Z, origin at the centre of the base). Rock.Tertiary is in
-- the pack but not in the data (a newer pack): it gets the pack's colour and the prop's collision.
local DESIGN = {
	Tree = {
		{ "Primary", Vector3.new(0, 8, 0), Vector3.new(8, 8, 8) },
		{ "Color_8B5A2B", Vector3.new(0, 2, 0), Vector3.new(2, 4, 2) },
	},
	Lamp = {
		{ "Primary", Vector3.new(0, 4, 0), Vector3.new(1, 8, 1) },
		{ "Neon_FFF3B0", Vector3.new(-1.5, 8, 0), Vector3.new(1, 1, 1) },
		{ "Glass_BDEBFF", Vector3.new(-1.5, 8, 0), Vector3.new(1.5, 1.5, 1.5) },
	},
	Rock = {
		{ "Primary", Vector3.new(0, 1, 0), Vector3.new(3, 2, 2.5) },
		{ "Tertiary", Vector3.new(0.5, 1.5, 0), Vector3.new(1, 1, 1) },
	},
}
local GRID = { Tree = Vector3.new(40, 0, 0), Lamp = Vector3.new(0, 0, 40), Rock = Vector3.new(-40, 3, -40) }
local packParts = {} -- every part of the last pack made

-- Builds a pack the way an importer might hand it over:
--   Layout "nested"  WorldProps > Tree > "Tree.Primary", "Tree.Root"   (the GLB's own names)
--          "flat"    WorldProps > "Tree_Primary", "Tree_Root"          (prop nodes dropped, "." replaced)
--          "roles"   WorldProps > Tree > "primary.001", "color_8b5a2b", "Root"
--          "deep"    WorldProps > Tree > Model "Tree.Primary" > "Mesh", Model "Color_8B5A2B" > "Trunk"
--   Scale    the importer's unit (the Root cube comes out this big)
--   Turn     the importer turned every prop this much about Y, baking the turn into the meshes (parts
--            keep an unrotated CFrame, sizes swap on a quarter turn)
--   NoRoot   { [propId] = true } props without a Root cube
local function makePack(options)
	options = options or {}
	local layout = options.Layout or "nested"
	local scale = options.Scale or 1
	local turn = CFrame.Angles(0, options.Turn or 0, 0)
	local quarter = math.abs(math.sin(options.Turn or 0)) > 0.5
	table.clear(packParts)
	local pack = Instance.new("Model")
	pack.Name = "WorldProps"
	for propId, pieces in DESIGN do
		local holder = pack
		if layout ~= "flat" then
			holder = Instance.new("Model")
			holder.Name = propId
			holder.Parent = pack
		end
		local function add(paint, center, size)
			local part = Instance.new("MeshPart")
			local parent = holder
			if layout == "nested" then
				part.Name = propId .. "." .. paint
			elseif layout == "flat" then
				part.Name = propId .. "_" .. paint
			elseif layout == "roles" then
				part.Name = if paint == "Root" then "Root" elseif string.find(paint, "_") then string.lower(paint) else paint .. ".001"
			elseif layout == "deep" then
				if paint == "Root" then
					part.Name = propId .. ".Root"
				else
					local wrapper = Instance.new("Model")
					wrapper.Name = if paint == "Primary" then propId .. "." .. paint else paint
					wrapper.Parent = holder
					parent = wrapper
					part.Name = if paint == "Primary" then "Mesh" else "Trunk"
				end
			end
			part.CFrame = CFrame.new((GRID[propId] + turn * center) * scale)
			part.Size = (if quarter then Vector3.new(size.Z, size.Y, size.X) else size) * scale
			part.Color = PACK_COLOR
			part.Anchored = false -- the cloud importer leaves parts unanchored
			part.Parent = parent
			table.insert(packParts, part)
			return part
		end
		if not (options.NoRoot and options.NoRoot[propId]) then
			add("Root", Vector3.zero, Vector3.one)
		end
		for _, piece in pieces do
			add(piece[1], piece[2], piece[3])
		end
	end
	return pack
end

-- What InsertService:LoadAsset hands back: a "Model" around the uploaded package around the pack
local function uploadedModel()
	local wrapper = Instance.new("Model")
	wrapper.Name = "Model"
	local asset = Instance.new("Model")
	asset.Name = "StormWorldProps"
	asset.Parent = wrapper
	Instance.new("PackageLink").Parent = asset
	makePack().Parent = asset
	return wrapper
end

local calls = {}
local behaviour = "ok"
InsertService.LoadAsset = function(self, assetId)
	assert(self == InsertService, "LoadAsset called without self")
	table.insert(calls, assetId)
	if behaviour == "fail" or (behaviour == "fail-once" and #calls == 1) then
		error("HTTP 403 (Forbidden)")
	end
	if behaviour == "race" then
		local other = makePack()
		other.Name = "WorldProps"
		other.Parent = ReplicatedStorage
	end
	return uploadedModel()
end

local function packCount()
	local count = 0
	for _, service in { ServerStorage, ReplicatedStorage } do
		for _, child in service:GetChildren() do
			if child.Name == "WorldProps" then
				count += 1
			end
		end
	end
	return count
end

local function reset(assetId, mode)
	for _, service in { ServerStorage, ReplicatedStorage } do
		local existing = service:FindFirstChild("WorldProps")
		while existing do
			existing:Destroy()
			existing = service:FindFirstChild("WorldProps")
		end
	end
	for _, child in Workspace:GetChildren() do
		child:Destroy()
	end
	table.clear(calls)
	table.clear(Mock.Warnings)
	table.clear(Mock.Prints)
	GameConfig.WorldPropsAssetId = assetId or 0
	behaviour = mode or "ok"
end

-- Puts a pack in the place (ServerStorage unless told otherwise) and returns a fresh WorldProps
local function withPack(options, service)
	reset(0)
	makePack(options).Parent = service or ServerStorage
	return fresh()
end

-- A placed piece by its paint (placed pieces are named "<PropId>.<Paint>" like in the pack)
local function piece(model, paint)
	return model and model:FindFirstChild(model.Name .. "." .. paint)
end
local function pieceCount(model)
	return model and (#model:GetChildren() - 1) or -1 -- minus the Root anchor
end
-- World-space size of a part's box along X, Y, Z
local function extentsOf(part)
	local c, s = part.CFrame, part.Size
	local r, u, l = c.RightVector, c.UpVector, c.LookVector
	return Vector3.new(
		math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z,
		math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z,
		math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z
	)
end
-- Every piece of a placed prop where the design says (relative to `at`, at scale 1)
local function matchesDesign(model, propId, at)
	at = at or CFrame.new()
	if pieceCount(model) ~= #DESIGN[propId] then
		return false, `{pieceCount(model)} pieces`
	end
	for _, spec in DESIGN[propId] do
		local part = piece(model, spec[1])
		if not part then
			return false, "no " .. spec[1]
		end
		local position = at:PointToObjectSpace(part.Position)
		if not near(position, spec[2], 1e-3) then
			return false, `{spec[1]} at {position}`
		end
		if not near(extentsOf(part), spec[3], 1e-3) then
			return false, `{spec[1]} is {extentsOf(part)}`
		end
	end
	return true
end

Mock.IsClient = false -- WorldProps runs on the server

------------------------------------------------------------------------ no pack
reset(0)
local WorldProps = fresh()
check("no pack: Load is false", WorldProps.Load() == false)
check("no pack: Has false", WorldProps.Has("Tree") == false)
check("no pack: no ids", #WorldProps.Ids() == 0)
check("no pack: Place is nil", WorldProps.Place("Tree", Workspace, CFrame.new()) == nil)
check("no pack: no LoadAsset", #calls == 0)
check("no pack: nothing created", packCount() == 0 and #Workspace:GetChildren() == 0)
check("no pack: quiet", #Mock.Warnings == 0, Mock.Warnings[1])

-- Bad asset ids are ignored
for _, bad in { "not a number", -5 } do
	reset(bad)
	WorldProps = fresh()
	check(`bad id {bad}: no LoadAsset`, WorldProps.Load() == false and #calls == 0)
end

------------------------------------------------------------------------ a pack already in the place
WorldProps = withPack({ Scale = 0.5 })
GameConfig.WorldPropsAssetId = 999 -- the pack in the place wins
check("existing pack: Load is true", WorldProps.Load() == true)
check("existing pack: no LoadAsset", #calls == 0)
check("existing pack: kept as it was", packCount() == 1 and ServerStorage.WorldProps:IsA("Model"))
check("existing pack: ids in data order, only props in the pack", sameList(WorldProps.Ids(), { "Tree", "Lamp", "Rock" }), table.concat(WorldProps.Ids(), ","))
check("existing pack: Has", WorldProps.Has("Tree") and WorldProps.Has("Lamp") and WorldProps.Has("Rock"))
check("existing pack: prop missing from the pack", WorldProps.Has("Hut") == false and WorldProps.Place("Hut", Workspace, CFrame.new()) == nil)
check("existing pack: unknown prop", WorldProps.Has("Nope") == false and WorldProps.Place("Nope", Workspace, CFrame.new()) == nil)
check("existing pack: summary in Studio", hasMessage(Mock.Prints, "mesh props: 3/4; built from parts: Hut") == 1, Mock.Prints[1])
check("existing pack: no warnings", #Mock.Warnings == 0, Mock.Warnings[1])
local ids = WorldProps.Ids()
table.clear(ids)
check("Ids returns a copy", #WorldProps.Ids() == 3)

-- Placing: normalised by the Root cube (the pack is at half scale and spread over a grid)
local at = CFrame.new(10, 2, 20)
local tree = WorldProps.Place("Tree", Workspace, at)
check("place: a model", tree ~= nil and tree:IsA("Model") and tree.Name == "Tree")
check("place: parented", tree and tree.Parent == Workspace)
local anchor = tree and tree.PrimaryPart
check("place: PrimaryPart is the Root anchor", anchor ~= nil and anchor.Name == "Root" and anchor.Parent == tree)
check("place: anchor at the origin", anchor and near(anchor.Position, at.Position))
check("place: anchor invisible and inert", anchor and anchor.Transparency == 1 and anchor.Anchored and not anchor.CanCollide and not anchor.CanQuery and not anchor.CanTouch and not anchor.CastShadow)
check("place: pieces at unit scale around the origin", matchesDesign(tree, "Tree", at))
check("place: no pack Root cube in the model", tree and tree:FindFirstChild("Tree.Root") == nil and pieceCount(tree) == 2)
check("place: pieces named like the pack", tree and tree:FindFirstChild("Tree.Primary") ~= nil and tree:FindFirstChild("Tree.Color_8B5A2B") ~= nil)
local canopy, trunk = piece(tree, "Primary"), piece(tree, "Color_8B5A2B")
check("place: canopy size", canopy and near(canopy.Size, Vector3.new(8, 8, 8)), canopy and canopy.Size)
check("place: trunk position", trunk and near(trunk.Position, Vector3.new(10, 4, 20)), trunk and trunk.Position)
check("place: anchored", canopy and canopy.Anchored and trunk.Anchored)
check("place: pack left alone", ServerStorage.WorldProps:FindFirstChild("Tree") ~= nil and not packParts[1].Anchored)

-- Paints and materials
check("paint: tint from WorldPropsData", canopy and canopy.Color == GREEN, canopy and canopy.Color)
check("paint: fixed colour from its name", trunk and trunk.Color == Color3.fromHex("8B5A2B"), trunk and trunk.Color)
check("paint: SmoothPlastic", canopy and canopy.Material == Enum.Material.SmoothPlastic and trunk.Material == Enum.Material.SmoothPlastic)
check("paint: opaque", canopy and canopy.Transparency == 0 and trunk.Transparency == 0)
local lamp = WorldProps.Place("Lamp", Workspace, CFrame.new())
check("lamp: matches the design", matchesDesign(lamp, "Lamp"))
local post, bulb, shade = piece(lamp, "Primary"), piece(lamp, "Neon_FFF3B0"), piece(lamp, "Glass_BDEBFF")
check("lamp: post tinted", post and post.Color == BLUE and post.Material == Enum.Material.SmoothPlastic)
check("lamp: neon glows", bulb and bulb.Material == Enum.Material.Neon and bulb.Color == Color3.fromHex("FFF3B0") and bulb.Transparency == 0)
check("lamp: glass see-through", shade and shade.Material == Enum.Material.Glass and shade.Transparency == 0.35 and shade.Color == Color3.fromHex("BDEBFF"))
local painted = WorldProps.Place("Tree", Workspace, CFrame.new(), { Paints = { Primary = RED, Color_8B5A2B = BLUE } })
check("paint: options.Paints", piece(painted, "Primary").Color == RED)
check("paint: fixed paints can be overridden", piece(painted, "Color_8B5A2B").Color == BLUE)
painted = WorldProps.Place("Tree", Workspace, CFrame.new(), { Paints = { Secondary = RED } })
check("paint: unused paints ignored, defaults kept", piece(painted, "Primary").Color == GREEN)
local rock = WorldProps.Place("Rock", Workspace, CFrame.new())
check("paint: a paint the data doesn't know keeps the pack's colour", piece(rock, "Tertiary") and piece(rock, "Tertiary").Color == PACK_COLOR)
check("paint: a tint the data knows", piece(rock, "Primary").Color == GREY)

-- Collision: WorldPropsData per piece unless options.Collide says otherwise
local function flags(part)
	return { part.CanCollide, part.CanQuery, part.CanTouch }
end
check("collide: solid trunk", sameList(flags(trunk), { true, true, true }))
check("collide: canopy not solid", sameList(flags(canopy), { false, false, false }))
check("collide: lamp not solid", not post.CanCollide and not bulb.CanCollide and not shade.CanCollide and not post.CanQuery and not shade.CanTouch)
check("collide: piece missing from the data follows the prop", piece(rock, "Tertiary").CanCollide == true and piece(rock, "Primary").CanCollide == true)
local ghost = WorldProps.Place("Tree", Workspace, CFrame.new(), { Collide = false })
check("collide: options.Collide = false", sameList(flags(piece(ghost, "Color_8B5A2B")), { false, false, false }) and not piece(ghost, "Primary").CanCollide)
local solid = WorldProps.Place("Lamp", Workspace, CFrame.new(), { Collide = true })
check("collide: options.Collide = true", sameList(flags(piece(solid, "Primary")), { true, true, true }) and piece(solid, "Neon_FFF3B0").CanCollide)

-- Shadows: only props at least 6 studs big (after scaling)
check("shadow: big prop casts", canopy.CastShadow and trunk.CastShadow)
check("shadow: small prop doesn't", not piece(rock, "Primary").CastShadow and not piece(rock, "Tertiary").CastShadow)
local bigRock = WorldProps.Place("Rock", Workspace, CFrame.new(), { Scale = 2 })
check("shadow: scaled to 6 studs casts", piece(bigRock, "Primary").CastShadow)
local tallRock = WorldProps.Place("Rock", Workspace, CFrame.new(), { Scale = Vector3.new(1, 3.5, 1) })
check("shadow: Vector3 scale counts", piece(tallRock, "Primary").CastShadow)
local tinyTree = WorldProps.Place("Tree", Workspace, CFrame.new(), { Scale = 0.4 })
check("shadow: shrunk below 6 studs doesn't", not piece(tinyTree, "Primary").CastShadow)
local forced = WorldProps.Place("Rock", Workspace, CFrame.new(), { CastShadow = true })
check("shadow: options.CastShadow = true", piece(forced, "Primary").CastShadow)
forced = WorldProps.Place("Tree", Workspace, CFrame.new(), { CastShadow = false })
check("shadow: options.CastShadow = false", not piece(forced, "Primary").CastShadow)

-- Scaling and placement
local big = WorldProps.Place("Tree", Workspace, CFrame.new(0, 0, 0), { Scale = 2 })
check("scale 2: sizes", near(piece(big, "Primary").Size, Vector3.new(16, 16, 16)) and near(piece(big, "Color_8B5A2B").Size, Vector3.new(4, 8, 4)))
check("scale 2: positions", near(piece(big, "Primary").Position, Vector3.new(0, 16, 0)) and near(piece(big, "Color_8B5A2B").Position, Vector3.new(0, 4, 0)))
check("scale 2: anchor stays at the origin", near(big.PrimaryPart.Position, Vector3.zero))
local stretched = WorldProps.Place("Lamp", Workspace, CFrame.new(), { Scale = Vector3.new(2, 1, 3) })
check("Vector3 scale: sizes", near(piece(stretched, "Primary").Size, Vector3.new(2, 8, 3)), piece(stretched, "Primary").Size)
check("Vector3 scale: positions", near(piece(stretched, "Neon_FFF3B0").Position, Vector3.new(-3, 8, 0)), piece(stretched, "Neon_FFF3B0").Position)
local even = WorldProps.Place("Tree", Workspace, CFrame.new(), { Scale = Vector3.new(1.5, 1.5, 1.5) })
check("uniform Vector3 scale", near(piece(even, "Primary").Size, Vector3.new(12, 12, 12)))
local broken = WorldProps.Place("Tree", Workspace, CFrame.new(), { Scale = 0 })
check("bad scale counts as 1", near(piece(broken, "Primary").Size, Vector3.new(8, 8, 8)))
local turned = WorldProps.Place("Lamp", Workspace, CFrame.new(5, 0, 5) * CFrame.Angles(0, math.pi / 2, 0))
check("turned placement: bulb follows", near(piece(turned, "Neon_FFF3B0").Position, Vector3.new(5, 8, 6.5)), piece(turned, "Neon_FFF3B0").Position)
check("turned placement: pieces turned", near(piece(turned, "Primary").CFrame.LookVector, Vector3.new(-1, 0, 0)))
local loose = WorldProps.Place("Rock", nil, CFrame.new())
check("no parent: unparented model", loose ~= nil and loose.Parent == nil)
local bare = WorldProps.Place("Lamp", Workspace, CFrame.new(3, 0, 4), { Anchor = false })
check("no anchor: no Root part", bare and bare:FindFirstChild("Root") == nil and #bare:GetChildren() == 3 and bare.PrimaryPart == nil)
check("no anchor: pivot at the origin", bare and near(bare.WorldPivot.Position, Vector3.new(3, 0, 4)))
check("no anchor: pieces placed", bare and near(piece(bare, "Neon_FFF3B0").Position, Vector3.new(1.5, 8, 4)))

-- Templates are copied from the pack once, not per placement
local most = 0
for _, part in packParts do
	most = math.max(most, Mock.CloneCounts[part] or 0)
end
check("pack parts cloned once", most == 1, most)

------------------------------------------------------------------------ naming and layouts
for _, layout in { "flat", "roles", "deep" } do
	WorldProps = withPack({ Layout = layout, Scale = 0.3048 })
	check(layout .. ": all props", sameList(WorldProps.Ids(), { "Tree", "Lamp", "Rock" }), table.concat(WorldProps.Ids(), ","))
	for propId in DESIGN do
		local ok, detail = matchesDesign(WorldProps.Place(propId, Workspace, CFrame.new()), propId)
		check(`{layout}: {propId} matches the design`, ok, detail)
	end
	check(layout .. ": no warnings", #Mock.Warnings == 0, Mock.Warnings[1])
end

-- A pack in ReplicatedStorage works too
WorldProps = withPack({ Layout = "roles" }, ReplicatedStorage)
check("ReplicatedStorage pack", WorldProps.Has("Lamp") and matchesDesign(WorldProps.Place("Lamp", Workspace, CFrame.new()), "Lamp"))

------------------------------------------------------------------------ Root cube and orientation
-- Without a Root cube, the bounding box and WorldPropsData's Size/Center place the prop
WorldProps = withPack({ Scale = 2, NoRoot = { Lamp = true, Tree = true } })
check("no Root: still placed", WorldProps.Has("Lamp") and WorldProps.Has("Tree"))
local ok, detail = matchesDesign(WorldProps.Place("Lamp", Workspace, CFrame.new()), "Lamp")
check("no Root: lamp (off-centre) where designed", ok, detail)
ok, detail = matchesDesign(WorldProps.Place("Tree", Workspace, CFrame.new()), "Tree")
check("no Root: tree where designed", ok, detail)
check("no Root: warned in Studio", hasMessage(Mock.Warnings, "Lamp has no Root cube") == 1, Mock.Warnings[1])

-- ... and without those either, by the bottom centre of the box at the pack's scale
local rockSize, rockCenter = Data.Props.Rock.Size, Data.Props.Rock.Center
Data.Props.Rock.Size, Data.Props.Rock.Center = nil, nil
WorldProps = withPack({ NoRoot = { Rock = true } })
local rootless = WorldProps.Place("Rock", Workspace, CFrame.new())
-- the box spans x -1.5..1.5, y 0..2, z -1.25..1.25, so its bottom centre is the designed origin
ok, detail = matchesDesign(rootless, "Rock")
check("no Root, no Size: bottom centre", ok, detail)
Data.Props.Rock.Size, Data.Props.Rock.Center = rockSize, rockCenter

-- An importer that turned the props around (baked into the meshes) is undone
for _, degrees in { 180, 90, 270 } do
	WorldProps = withPack({ Turn = math.rad(degrees), Scale = 0.5 })
	local turnedLamp = WorldProps.Place("Lamp", Workspace, CFrame.new())
	ok, detail = matchesDesign(turnedLamp, "Lamp")
	check(`turned {degrees}: lamp faces -Z again`, ok, detail)
	check(`turned {degrees}: reported`, hasMessage(Mock.Prints, `the pack is turned {degrees} degrees`) == 1, Mock.Prints[1])
	-- the rock is round (and Rock.Tertiary isn't in the data): it turns with the rest of the pack
	ok, detail = matchesDesign(WorldProps.Place("Rock", Workspace, CFrame.new()), "Rock")
	check(`turned {degrees}: rock turns with the pack`, ok, detail)
	ok, detail = matchesDesign(WorldProps.Place("Tree", Workspace, CFrame.new()), "Tree")
	check(`turned {degrees}: tree`, ok, detail)
end

-- Broken props are skipped (the map builds them from parts); the others still work
reset(0)
local pack = makePack()
local extraRoot = Instance.new("MeshPart")
extraRoot.Name = "Tree.Root"
extraRoot.Parent = pack.Tree
pack.Lamp["Lamp.Root"].Size = Vector3.new(0, 0, 0)
local stray = Instance.new("MeshPart")
stray.Name = "Rock.Leaves"
stray.Parent = pack.Rock
pack.Parent = ServerStorage
WorldProps = fresh()
check("two Root cubes: skipped", WorldProps.Has("Tree") == false and hasMessage(Mock.Warnings, "Tree has more than one Root cube") == 1)
check("broken Root: skipped", WorldProps.Has("Lamp") == false and hasMessage(Mock.Warnings, "Lamp has a Root cube with a broken size") == 1)
check("unknown piece: ignored", WorldProps.Has("Rock") and pieceCount(WorldProps.Place("Rock", Workspace, CFrame.new())) == 2)
check("unknown piece: warned", hasMessage(Mock.Warnings, `ignoring "Leaves" in Rock`) == 1, Mock.Warnings[1])
check("broken props: listed", sameList(WorldProps.Ids(), { "Rock" }))

reset(0)
pack = makePack()
pack.Tree["Tree.Primary"].Archivable = false
pack.Parent = ServerStorage
WorldProps = fresh()
check("piece that can't be copied: prop skipped", WorldProps.Has("Tree") == false and WorldProps.Has("Lamp"))
check("piece that can't be copied: warned", hasMessage(Mock.Warnings, "can't be copied") == 1, Mock.Warnings[1])

-- Nothing usable in the pack
reset(0)
Mock.Folder("WorldProps", ServerStorage)
WorldProps = fresh()
check("empty pack: Load is false", WorldProps.Load() == false and WorldProps.Place("Tree", Workspace, CFrame.new()) == nil)
check("empty pack: warned", hasMessage(Mock.Warnings, "has no props this game can use") == 1, Mock.Warnings[1])

------------------------------------------------------------------------ WorldPropsData missing or broken
setData(nil)
WorldProps = withPack()
check("no data: Has false", WorldProps.Has("Tree") == false)
check("no data: Place nil", WorldProps.Place("Tree", Workspace, CFrame.new()) == nil)
check("no data: warned", hasMessage(Mock.Warnings, "WorldPropsData is missing") == 1, Mock.Warnings[1])
reset(777)
WorldProps = fresh()
check("no data: the pack isn't even loaded", WorldProps.Load() == false and #calls == 0)
setData(function()
	error("syntax error somewhere")
end)
WorldProps = withPack()
check("broken data: Has false", WorldProps.Has("Tree") == false)
check("broken data: warned once", #Mock.Warnings == 1 and hasMessage(Mock.Warnings, "WorldPropsData can't be read") == 1, Mock.Warnings[1])
setData(function()
	return Data
end)

------------------------------------------------------------------------ uploaded pack (GameConfig.WorldPropsAssetId)
reset(777)
WorldProps = fresh()
check("asset: Load is true", WorldProps.Load() == true)
check("asset: LoadAsset once with the id", #calls == 1 and calls[1] == 777, calls[1])
local inserted = ServerStorage:FindFirstChild("WorldProps")
check("asset: in ServerStorage.WorldProps", inserted ~= nil and inserted:IsA("Folder") and packCount() == 1)
check("asset: wrapper unwrapped", inserted and inserted:FindFirstChild("StormWorldProps") ~= nil and inserted:FindFirstChild("Model") == nil)
check("asset: props usable", WorldProps.Has("Tree") and matchesDesign(WorldProps.Place("Tree", Workspace, CFrame.new()), "Tree"))
WorldProps.Load()
WorldProps.Has("Lamp")
WorldProps.Ids()
check("asset: loaded only once", #calls == 1, #calls)
check("asset: no warnings", #Mock.Warnings == 0, Mock.Warnings[1])

-- A numeric string id works too
reset("778")
WorldProps = fresh()
check("asset: string id", WorldProps.Has("Rock") and calls[1] == 778, calls[1])

-- Retries after a failure
reset(777, "fail-once")
local waits = {}
local realWait = task.wait
task.wait = function(seconds)
	table.insert(waits, seconds or 0)
	return seconds or 0
end
WorldProps = fresh()
check("retry: loaded on the second try", WorldProps.Has("Tree") and #calls == 2, #calls)
check("retry: short wait", #waits == 1 and waits[1] > 0 and waits[1] <= 2, waits[1])
check("retry: no warning", #Mock.Warnings == 0, Mock.Warnings[1])

-- Gives up after three failures, with a Studio warning
reset(777, "fail")
table.clear(waits)
WorldProps = fresh()
check("fail: Has false", WorldProps.Has("Tree") == false)
check("fail: three attempts", #calls == 3, #calls)
check("fail: no pack", packCount() == 0)
check("fail: waits stay short", #waits == 2 and waits[1] + waits[2] <= 5)
check("fail: warned in Studio", hasMessage(Mock.Warnings, "couldn't load the world prop pack 777") == 1, Mock.Warnings[1])
check("fail: Place nil", WorldProps.Place("Tree", Workspace, CFrame.new()) == nil)
WorldProps.Load()
check("fail: not retried on every call", #calls == 3, #calls)
task.wait = realWait

-- Live servers stay quiet
Mock.IsStudio = false
reset(777, "fail")
WorldProps = fresh()
WorldProps.Load()
check("live server: no warning", #Mock.Warnings == 0)
reset(0)
makePack({ NoRoot = { Lamp = true } }).Parent = ServerStorage
WorldProps = fresh()
check("live server: no messages", WorldProps.Load() and #Mock.Warnings == 0 and #Mock.Prints == 0)
Mock.IsStudio = true

-- A pack that turns up while loading wins; the loaded copy is thrown away
reset(777, "race")
WorldProps = fresh()
check("race: props usable", WorldProps.Has("Tree"))
check("race: one pack", packCount() == 1, packCount())
check("race: the other pack kept", ReplicatedStorage:FindFirstChild("WorldProps") ~= nil and ServerStorage:FindFirstChild("WorldProps") == nil)

------------------------------------------------------------------------ many props
WorldProps = withPack({ Scale = 0.5 })
local started = os.clock()
local placed = 0
local folder = Mock.Folder("Props", Workspace)
local kinds = { "Tree", "Lamp", "Rock" }
for index = 1, 1500 do
	local propId = kinds[index % 3 + 1]
	local model = WorldProps.Place(propId, folder, CFrame.new(index, 0, 0) * CFrame.Angles(0, index, 0), {
		Scale = 0.8 + (index % 5) * 0.1,
		Paints = { Primary = Color3.fromHSV((index % 7) / 7, 0.5, 1) },
	})
	if model then
		placed += 1
	end
end
local elapsed = os.clock() - started
check("1500 props placed", placed == 1500 and #folder:GetChildren() == 1500, placed)
most = 0
for _, part in packParts do
	most = math.max(most, Mock.CloneCounts[part] or 0)
end
check("1500 props: pack parts still cloned once", most == 1, most)
Mock.RealPrint(string.format("WorldProps: placed 1500 props in %.0f ms (mock runtime)", elapsed * 1000))

------------------------------------------------------------------------ the generated WorldPropsData
-- The real module (tools/world/build_world_pack.py) with a pack made from its own piece list
if __sources.WorldPropsData then
	setData(__sources.WorldPropsData)
	local RealData = require(ConfigFolder.WorldPropsData)
	reset(0)
	local realPack = Instance.new("Folder")
	realPack.Name = "WorldProps"
	local column = 0
	for propId, prop in RealData.Props do
		column += 1
		local holder = Instance.new("Model")
		holder.Name = propId
		holder.Parent = realPack
		local offset = Vector3.new(column * 30, 0, 0)
		local root = Instance.new("MeshPart")
		root.Name = propId .. ".Root"
		root.Size = Vector3.one * RealData.RootSize
		root.CFrame = CFrame.new(offset)
		root.Parent = holder
		for _, entry in prop.Pieces do
			local part = Instance.new("MeshPart")
			part.Name = entry.Name
			part.Size = entry.Size
			part.CFrame = CFrame.new(offset + entry.Center)
			part.Parent = holder
		end
	end
	realPack.Parent = ServerStorage
	WorldProps = fresh()
	local expected = {}
	for _, id in RealData.Order do
		if RealData.Props[id] then
			table.insert(expected, id)
		end
	end
	check("real data: every prop", sameList(WorldProps.Ids(), expected), table.concat(WorldProps.Ids(), ","))
	check("real data: no warnings", #Mock.Warnings == 0, Mock.Warnings[1])
	Mock.RealPrint(`WorldProps: checked against the generated WorldPropsData ({#expected} props)`)
	for propId, prop in RealData.Props do
		local model = WorldProps.Place(propId, Workspace, CFrame.new())
		local good = model ~= nil and pieceCount(model) == #prop.Pieces
		for _, entry in prop.Pieces do
			local part = model and model:FindFirstChild(entry.Name)
			good = good
				and part ~= nil
				and near(part.Position, entry.Center, 1e-3)
				and near(part.Size, entry.Size, 1e-3)
				and part.CanCollide == entry.Collide
				and part.Color == (if entry.Kind == "Tint" then prop.Paints[entry.Paint] or entry.Color else entry.Color)
		end
		check(`real data: {propId} placed as listed`, good)
		local largest = math.max(prop.Size.X, prop.Size.Y, prop.Size.Z)
		check(`real data: {propId} shadow`, model and model:FindFirstChildOfClass("MeshPart").CastShadow == (largest >= 6))
	end
	setData(function()
		return Data
	end)
end

Mock.RealPrint(string.format("WorldProps mock test: %d passed, %d failed", passes, failures))
if failures > 0 then
	error("mock test failed")
end
