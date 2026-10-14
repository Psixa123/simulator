--!nocheck
-- Mock test for the imported pet mesh pack (PetModels mesh path + PetController hinge animation).
-- Runs after RobloxMock.luau and the module sources in one bundle; see run_mock_tests.py.

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

------------------------------------------------------------------------ game tree
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = Mock.Folder("Shared", ReplicatedStorage)
local ConfigFolder = Mock.Folder("Config", Shared)
local ModelsFolder = Mock.Folder("Models", Shared)
Mock.Module("Pets", ConfigFolder, __sources.Pets)
Mock.Module("PetModels", ModelsFolder, __sources.PetModels)
local Client = Mock.Folder("Client", game:GetService("StarterPlayer"))
Mock.Module("Registry", Client, function()
	return {}
end)
local Controllers = Mock.Folder("Controllers", Client)
game:GetService("Players").LocalPlayer = Instance.new("Player")
Mock.Module("PetController", Controllers, __sources.PetController)

local Pets = require(ConfigFolder.Pets)
local PetModels = require(ModelsFolder.PetModels)
local PetController = require(Controllers.PetController)

------------------------------------------------------------------------ a fake 3D importer
-- Puffling as designed (studs, Y up, front -Z, centred on the origin), roles per the pack contract
local DESIGN = {
	{ "Root", Vector3.new(0, 0, 0), Vector3.new(0.2, 0.2, 0.2) },
	{ "Body", Vector3.new(0, 0.05, 0), Vector3.new(2.6, 2.2, 2.2) },
	{ "Accent", Vector3.new(0, -0.6, 0.2), Vector3.new(1.8, 0.6, 1.6) },
	{ "Eye", Vector3.new(0, 0.15, -0.95), Vector3.new(1, 0.45, 0.2) },
	{ "Shine", Vector3.new(0.05, 0.25, -1.05), Vector3.new(0.8, 0.15, 0.05) },
	{ "Blush", Vector3.new(0, -0.1, -0.9), Vector3.new(1.4, 0.2, 0.1) },
	{ "Mouth", Vector3.new(0, -0.15, -1), Vector3.new(0.2, 0.08, 0.05) },
	{ "Accent@WingL", Vector3.new(-1.3, 0.3, 0.3), Vector3.new(0.1, 0.9, 1.2) },
	{ "Accent@WingR", Vector3.new(1.3, 0.3, 0.3), Vector3.new(0.1, 0.9, 1.2) },
	{ "Pivot@WingL", Vector3.new(-1, 0.3, 0.3), Vector3.new(0.1, 0.1, 0.1) },
	{ "Pivot@WingR", Vector3.new(1, 0.3, 0.3), Vector3.new(0.1, 0.1, 0.1) },
	{ "Neon_FFE14A@SpinY", Vector3.new(0, 1.6, 0), Vector3.new(1.2, 0.15, 1.2) },
	{ "Color_FFD23C", Vector3.new(0, 1.2, 0), Vector3.new(0.9, 0.4, 0.9) },
	{ "Body@Wag", Vector3.new(0, -0.1, 1.2), Vector3.new(0.4, 0.4, 0.8) },
	{ "Pivot@Wag", Vector3.new(0, -0.1, 0.9), Vector3.new(0.1, 0.1, 0.1) },
}
local VISIBLE = 11 -- DESIGN minus Root and the 3 pivots
local function designOf(role)
	for _, piece in DESIGN do
		if piece[1] == role then
			return piece
		end
	end
	error("no " .. role)
end

-- Imports a design like Studio would: scaled by the importer's unit, moved/turned as a whole.
-- options.Flat names parts "<PetId>.<Role>" in one folder; options.Skip drops roles; options.Bake turns
-- the geometry the way a wrong importer axis setting would (baked into the meshes, so every part,
-- the Root cube included, keeps an unrotated CFrame).
local function import(petId, parent, unit, placement, options)
	options = options or {}
	local container = parent
	if not options.Flat then
		container = Instance.new("Model")
		container.Name = petId
		container.Parent = parent
	end
	local parts = {}
	for _, piece in options.Design or DESIGN do
		local role = piece[1]
		if not (options.Skip and options.Skip[role]) then
			local part = Instance.new("MeshPart")
			part.Name = if options.Flat then petId .. "." .. role else role
			part.Size = piece[3] * (if role == "Root" and options.RootSize then options.RootSize else unit)
			local position = piece[2] * unit
			if options.Bake then
				position = options.Bake * position
			end
			part.CFrame = placement * CFrame.new(position)
			part.Parent = container
			parts[role] = part
		end
	end
	return container, parts
end

local function newPack(className)
	local old = ReplicatedStorage:FindFirstChild("PetMeshes")
	if old then
		old:Destroy()
	end
	local pack = Instance.new(className or "Model")
	pack.Name = "PetMeshes"
	return pack
end

local function partsByName(parts)
	local map = {}
	for _, item in parts do
		local name = item.Part.Name
		map[name] = map[name] or {}
		table.insert(map[name], item)
	end
	return map
end

------------------------------------------------------------------------ 1. no pack: primitives
do
	local model, parts = PetModels.Build("Puffling", "Normal")
	check("no pack: built from primitives", model:GetAttribute("MeshPack") == false)
	check("no pack: has parts", #parts > 5, #parts)
	check("no pack: parts are Parts", parts[1].Part:IsA("Part"))
	check("no pack: HasMeshes false", PetModels.HasMeshes("Puffling") == false)
	for petId in Pets.Pets do
		for _, tier in { "Normal", "Golden", "Rainbow" } do
			local ok, err = pcall(PetModels.Build, petId, tier)
			check("primitives build " .. petId .. " " .. tier, ok, err)
		end
	end
end

------------------------------------------------------------------------ 2. nested pack, metres, moved and turned
local UNIT = 1 / 0.28 -- the importer read the file as metres
local PLACEMENT = CFrame.new(40, 12, -7) * CFrame.Angles(0, 0.6, 0)
local pack = newPack("Model")
local _, source = import("Puffling", pack, UNIT, PLACEMENT, {})
source.Body.TextureID = "rbxassetid://99"
Instance.new("SurfaceAppearance").Parent = source.Body
local junk = Instance.new("MeshPart")
junk.Name = "Thingamajig"
junk.Parent = pack.Puffling
pack.Parent = ReplicatedStorage

local SCALE = PetModels.Scale("Puffling", "Normal")
local look = Pets.Pets.Puffling.Look
do
	local model, parts = PetModels.Build("Puffling", "Normal")
	check("mesh: MeshPack attribute", model:GetAttribute("MeshPack") == true)
	check("mesh: HasMeshes", PetModels.HasMeshes("Puffling"))
	check("mesh: visible piece count", #parts == VISIBLE, #parts)
	check("mesh: Root is PrimaryPart at origin", model.PrimaryPart and model.PrimaryPart.Name == "Root" and near(model.PrimaryPart.CFrame.Position, Vector3.zero))
	check("mesh: no Root/Pivot clones", model:FindFirstChild("Pivot") == nil and #model:GetChildren() == VISIBLE + 1, #model:GetChildren())
	check("mesh: attributes", model:GetAttribute("PetId") == "Puffling" and model:GetAttribute("Tier") == "Normal" and model:GetAttribute("Golden") == false)
	check("mesh: unknown role warned", hasMessage(Mock.Warnings, "Thingamajig") == 1)
	check("mesh: summary printed", hasMessage(Mock.Prints, "mesh models for 1/") == 1, table.concat(Mock.Prints, " | "))
	check("mesh: preloaded on the client", #Mock.Preloads == 1 and Mock.Preloads[1][1] == pack)
	check("mesh: pack turned in Studio is undone (no flip needed)", hasMessage(Mock.Prints, "faces +Z") == 0)

	local byName = partsByName(parts)
	local function role(name)
		local list = byName[name]
		return list and list[1]
	end
	local function expectPlaced(label, name, item)
		local piece = designOf(name)
		item = item or role(name)
		check(label .. " offset", item and near(item.Offset.Position, piece[2] * SCALE), item and tostring(item.Offset.Position))
		check(label .. " size", item and near(item.Part.Size, piece[3] * SCALE), item and tostring(item.Part.Size))
		check(label .. " CFrame = offset", item and near(item.Part.CFrame.Position, item.Offset.Position))
	end
	expectPlaced("body", "Body", nil)
	expectPlaced("eye", "Eye", nil)
	expectPlaced("crown", "Color_FFD23C", role("Color_FFD23C"))

	for _, item in byName.Body do
		check("body tint", item.Part:GetAttribute("Tint") == "Body")
		check("body colour", item.Part.Color == look.Color)
	end
	local body = role("Body")
	check("body template cleaned", body.Part.TextureID == "" and #body.Part:GetChildren() == 0)
	check("body flags", body.Part.Anchored and not body.Part.CanCollide and not body.Part.CanQuery and not body.Part.CanTouch and not body.Part.CastShadow)
	check("body material", body.Part.Material == Enum.Material.SmoothPlastic)
	check("eye colour", role("Eye").Part.Color == Color3.fromRGB(28, 26, 38) and role("Eye").Part.Material == Enum.Material.SmoothPlastic)
	check("shine neon white", role("Shine").Part.Color == Color3.new(1, 1, 1) and role("Shine").Part.Material == Enum.Material.Neon)
	check("blush", role("Blush").Part.Transparency == 0.35)
	check("mouth ink", role("Mouth").Part.Color.R < 0.3 and role("Mouth").Part:GetAttribute("Tint") == nil)
	check("fixed colour", role("Color_FFD23C").Part.Color == Color3.fromRGB(0xFF, 0xD2, 0x3C) and role("Color_FFD23C").Part.Material == Enum.Material.SmoothPlastic)
	local halo = role("Neon_FFE14A")
	check("neon halo", halo and halo.Part.Material == Enum.Material.Neon and halo.Anim == "SpinY" and halo.Pivot == nil)

	local wingL, wingR
	for _, item in byName.Accent do
		if item.Anim == "WingL" then
			wingL = item
		elseif item.Anim == "WingR" then
			wingR = item
		else
			check("accent colour", item.Part.Color == look.Accent and item.Part:GetAttribute("Tint") == "Accent")
		end
	end
	check("wings found", wingL ~= nil and wingR ~= nil)
	check("wing L pivot", wingL and wingL.Pivot and near(wingL.Pivot.Position, designOf("Pivot@WingL")[2] * SCALE))
	check("wing R pivot", wingR and wingR.Pivot and near(wingR.Pivot.Position, designOf("Pivot@WingR")[2] * SCALE))
	local tail
	for _, item in byName.Body do
		if item.Anim == "Wag" then
			tail = item
		end
	end
	check("tail wags around its pivot", tail and tail.Pivot and near(tail.Pivot.Position, designOf("Pivot@Wag")[2] * SCALE))

	-- Hinge animation: the hinge point stays put, the wing tip moves, both wings flap mirrored
	if wingL and wingR then
		local hingeL = wingL.Pivot.Position
		local localHinge = wingL.Offset:PointToObjectSpace(hingeL)
		local tipL = wingL.Offset:PointToObjectSpace(wingL.Offset.Position + Vector3.new(-0.05, 0.45, 0) * SCALE)
		local tipR = wingR.Offset:PointToObjectSpace(wingR.Offset.Position + Vector3.new(0.05, 0.45, 0) * SCALE)
		local moved = false
		for _, time in { 0, 0.05, 0.11, 0.3 } do
			local animatedL = PetController.AnimationOffset(wingL, time)
			local animatedR = PetController.AnimationOffset(wingR, time)
			check("hinge fixed at t=" .. time, near(animatedL:PointToWorldSpace(localHinge), hingeL), tostring(animatedL:PointToWorldSpace(localHinge)))
			local yL = animatedL:PointToWorldSpace(tipL).Y
			local yR = animatedR:PointToWorldSpace(tipR).Y
			check("wings mirrored at t=" .. time, near(yL, yR), yL .. " vs " .. yR)
			moved = moved or not near(yL, (wingL.Offset.Position.Y + 0.45 * SCALE))
		end
		check("wing tip moves", moved)
	end
	-- Primitive parts keep their old animation
	local offset = CFrame.new(1, 2, 3) * CFrame.Angles(0, 0, 0.5)
	local old = offset * CFrame.Angles(0, 0, math.sin(0.3 * 14) * 0.45)
	check("primitive wing unchanged", near(PetController.AnimationOffset({ Offset = offset, Anim = "WingL" }, 0.3).Position, old.Position))
	local spin = CFrame.Angles(0, 0.3 * 2, 0) * offset
	check("primitive spin unchanged", near(PetController.AnimationOffset({ Offset = offset, Anim = "SpinY" }, 0.3).Position, spin.Position))
	check("static part unchanged", PetController.AnimationOffset({ Offset = offset }, 0.3) == offset)

	-- Effects
	check("effects on root", model.PrimaryPart:FindFirstChild("FX") ~= nil)
	local quiet = PetModels.Build("Puffling", "Normal", { Effects = false })
	check("no effects in viewports", quiet.PrimaryPart:FindFirstChild("FX") == nil)
end

------------------------------------------------------------------------ 3. tiers, scale and caching
do
	local golden, goldenParts = PetModels.Build("Puffling", "Golden")
	local gscale = PetModels.Scale("Puffling", "Golden")
	local byName = partsByName(goldenParts)
	check("golden body", byName.Body[1].Part.Color == Color3.fromRGB(255, 202, 58) and byName.Body[1].Part.Reflectance == 0.2)
	check("golden accent", byName.Accent[1].Part.Color == Color3.fromRGB(255, 160, 35))
	check("golden fixed colour kept", byName.Color_FFD23C[1].Part.Color == Color3.fromRGB(0xFF, 0xD2, 0x3C) and byName.Color_FFD23C[1].Part.Reflectance == 0)
	check("golden scale", near(byName.Body[1].Part.Size, designOf("Body")[3] * gscale))
	check("golden attribute", golden:GetAttribute("Golden") == true)

	local rainbow, rainbowParts = PetModels.Build("Puffling", "Rainbow")
	byName = partsByName(rainbowParts)
	local _, saturation = byName.Body[1].Part.Color:ToHSV()
	check("rainbow body pastel", near(saturation, 0.42, 0.01), saturation)
	check("rainbow attribute", rainbow:GetAttribute("Rainbow") == true)
	local hues = {}
	for _, item in byName.Body do
		hues[string.format("%.3f", (item.Part.Color:ToHSV()))] = true
	end
	local distinct = 0
	for _ in hues do
		distinct += 1
	end
	check("rainbow hues differ per piece", distinct == #byName.Body, distinct)

	local _, bigParts = PetModels.Build("Puffling", "Normal", { Scale = 2 })
	byName = partsByName(bigParts)
	check("options.Scale", near(byName.Body[1].Part.Size, designOf("Body")[3] * SCALE * 2))
	for _, item in bigParts do
		if item.Anim == "Wag" then
			check("options.Scale pivot", near(item.Pivot.Position, designOf("Pivot@Wag")[2] * SCALE * 2))
		end
	end

	local bodySource = pack.Puffling.Body
	check("pack parts copied once (templates cached)", Mock.CloneCounts[bodySource] == 1, Mock.CloneCounts[bodySource])
	check("summary printed once", hasMessage(Mock.Prints, "mesh models for") == 1)
end

------------------------------------------------------------------------ 4. broken pets fall back, the rest keep working
do
	local warningsBefore = #Mock.Warnings
	import("Droplet", pack, UNIT, PLACEMENT, { Skip = { Root = true } })
	import("Sunny", pack, UNIT, PLACEMENT, { RootSize = 0.002 }) -- Root cube not scaled with the rest
	import("Prism", pack, UNIT, PLACEMENT, { Bake = CFrame.Angles(-math.pi / 2, 0, 0) }) -- lying on its back
	local _, static = import("Static", pack, UNIT, PLACEMENT, {})
	static.Body.Archivable = false
	import("Zappy", pack, UNIT, PLACEMENT, { Skip = { Body = true, ["Body@Wag"] = true } })

	for _, petId in { "Droplet", "Sunny", "Prism", "Static", "Zappy" } do
		local model, parts = PetModels.Build(petId, "Normal")
		check(petId .. " falls back to primitives", model:GetAttribute("MeshPack") == false and #parts > 0)
		PetModels.Build(petId, "Golden")
	end
	check("Puffling still meshes", PetModels.Build("Puffling"):GetAttribute("MeshPack") == true)
	check("warn: no Root", hasMessage(Mock.Warnings, "Droplet has no Root cube") == 1)
	check("warn: scale", hasMessage(Mock.Warnings, "Sunny has a") == 1)
	check("warn: orientation", hasMessage(Mock.Warnings, "Prism has its eyes off the front") == 1)
	check("warn: archivable", hasMessage(Mock.Warnings, "Static has a \"Body\" mesh that can't be copied") == 1)
	check("warn: no body", hasMessage(Mock.Warnings, "Zappy has no Body mesh") == 1)
	check("warnings only once", #Mock.Warnings - warningsBefore == 5, #Mock.Warnings - warningsBefore)

	-- Fixing a pet in the pack is picked up (the pack is re-read when it changes)
	pack.Droplet:Destroy()
	import("Droplet", pack, UNIT, PLACEMENT, {})
	check("re-read after a change", PetModels.Build("Droplet"):GetAttribute("MeshPack") == true)

	-- No warnings outside Studio
	Mock.IsStudio = false
	local count = #Mock.Warnings
	import("Sandy", pack, UNIT, PLACEMENT, { Skip = { Root = true } })
	PetModels.Build("Sandy")
	check("silent in live games", #Mock.Warnings == count)
	Mock.IsStudio = true
end

------------------------------------------------------------------------ 5. flat names, facing +Z, importer suffixes
do
	local flat = newPack("Folder")
	local turned = CFrame.Angles(0, math.pi, 0) -- exported facing +Z
	local design = {}
	for _, piece in DESIGN do
		local name = piece[1]
		if name == "Body" then
			name = "Body.001"
		elseif name == "Accent@WingL" then
			name = "accent_wingl" -- lost "@", lower case
		end
		table.insert(design, { name, piece[2], piece[3] })
	end
	import("Puffling", flat, 1, CFrame.new(-5, 0, 3), { Flat = true, Design = design, Bake = turned })
	flat["Puffling.Mouth"].Name = "Puffling_Mouth" -- an importer that replaced the dot
	flat.Parent = ReplicatedStorage

	local model, parts = PetModels.Build("Puffling", "Normal")
	check("flat: meshes", model:GetAttribute("MeshPack") == true and #parts == VISIBLE, #parts)
	local byName = partsByName(parts)
	check("flat: suffix parsed", byName.Body ~= nil and #byName.Body == 2)
	check("flat: underscore separator", byName.Mouth ~= nil and #byName.Mouth == 1)
	check("flat: turned to face -Z", byName.Eye and byName.Eye[1].Offset.Position.Z < -0.5, byName.Eye and tostring(byName.Eye[1].Offset.Position))
	check("flat: flip reported", hasMessage(Mock.Prints, "faces +Z") == 1)
	for _, item in byName.Accent do
		if item.Anim == "WingL" then
			check("flat: WingL on the left after the turn", item.Offset.Position.X < 0 and item.Pivot.Position.X < 0)
		elseif item.Anim == "WingR" then
			check("flat: WingR on the right after the turn", item.Offset.Position.X > 0)
		end
	end
	local animated = 0
	for _, item in parts do
		if item.Anim == "WingL" or item.Anim == "WingR" then
			animated += 1
		end
	end
	check("flat: both wings animated", animated == 2, animated)
end

------------------------------------------------------------------------ 6. a full pack, then removing it
do
	local full = newPack("Model")
	for petId in Pets.Pets do
		import(petId, full, 1, CFrame.new(), {})
	end
	full.Parent = ReplicatedStorage
	local all = true
	for petId in Pets.Pets do
		for _, tier in { "Normal", "Golden", "Rainbow" } do
			local ok, model = pcall(PetModels.Build, petId, tier)
			all = all and ok and model:GetAttribute("MeshPack") == true
		end
	end
	check("full pack: every pet and tier", all)
	check("full pack: summary", hasMessage(Mock.Prints, "mesh models for all") == 1)

	-- Building from a template that fails half-way falls back cleanly (and isn't retried)
	Mock.BreakMeshClones = true
	local model, parts = PetModels.Build("Coal", "Normal")
	Mock.BreakMeshClones = false
	local meshParts = 0
	for _, item in parts do
		if item.Part:IsA("MeshPart") then
			meshParts += 1
		end
	end
	check("failed build: primitives", model:GetAttribute("MeshPack") == false and #parts > 0 and meshParts == 0)
	check("failed build: no leftovers", #model:GetChildren() == #parts + 1, #model:GetChildren())
	check("failed build: warned", hasMessage(Mock.Warnings, "Coal can't be built") == 1)
	check("failed build: not retried", PetModels.Build("Coal"):GetAttribute("MeshPack") == false)
	check("other pets unaffected", PetModels.Build("Ember"):GetAttribute("MeshPack") == true)

	full:Destroy()
	check("pack removed: primitives again", PetModels.Build("Puffling"):GetAttribute("MeshPack") == false)
	check("pack removed: HasMeshes false", PetModels.HasMeshes("Puffling") == false)

	-- A pack that isn't a pack at all
	local wrong = newPack("MeshPart")
	wrong.Parent = ReplicatedStorage
	check("unusable pack: primitives", PetModels.Build("Puffling"):GetAttribute("MeshPack") == false)
	check("unusable pack: warned", hasMessage(Mock.Warnings, "no pet meshes this game can use") == 1)
	wrong:Destroy()
end

Mock.RealPrint(string.format("PetMeshes mock test: %d passed, %d failed", passes, failures))
if failures > 0 then
	error("mock test failed")
end
