--!nocheck
-- Mock test for PetMeshService: inserting the uploaded pet mesh pack (GameConfig.PetMeshAssetId) into
-- ReplicatedStorage.PetMeshes, and PetModels using it. Runs after RobloxMock.luau and the module
-- sources in one bundle; see run_mock_tests.py.

local failures, passes = 0, 0
local function check(name, condition, detail)
	if condition then
		passes += 1
	else
		failures += 1
		Mock.RealPrint("FAIL " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
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
local InsertService = game:GetService("InsertService")
local Shared = Mock.Folder("Shared", ReplicatedStorage)
local ConfigFolder = Mock.Folder("Config", Shared)
local ModelsFolder = Mock.Folder("Models", Shared)
local GameConfig = { PetMeshAssetId = 0 }
Mock.Module("GameConfig", ConfigFolder, function()
	return GameConfig
end)
Mock.Module("Pets", ConfigFolder, __sources.Pets)
Mock.Module("PetModels", ModelsFolder, __sources.PetModels)
local Services = Mock.Folder("Services", game:GetService("ServerScriptService"))
Mock.Module("PetMeshService", Services, __sources.PetMeshService)

local PetModels = require(ModelsFolder.PetModels)
local PetMeshService = require(Services.PetMeshService)

------------------------------------------------------------------------ a fake uploaded model
-- What LoadAsset hands back: a "Model" wrapping the asset, the pets a few levels down
local function uploadedModel()
	local wrapper = Instance.new("Model")
	wrapper.Name = "Model"
	local asset = Instance.new("Model")
	asset.Name = "StormlingPets"
	asset.Parent = wrapper
	local inner = Instance.new("Model")
	inner.Name = "PetMeshes"
	inner.Parent = asset
	local pet = Instance.new("Model")
	pet.Name = "Puffling"
	pet.Parent = inner
	for _, spec in {
		{ "Root", "Part", Vector3.new(0, 0, 0), Vector3.new(0.2, 0.2, 0.2) },
		{ "Body", "MeshPart", Vector3.new(0, 0.05, 0), Vector3.new(2.6, 2.2, 2.2) },
		{ "Eye", "MeshPart", Vector3.new(0, 0.15, -0.95), Vector3.new(1, 0.45, 0.2) },
	} do
		local part = Instance.new(spec[2])
		part.Name = spec[1]
		part.CFrame = CFrame.new(spec[3])
		part.Size = spec[4]
		part.Parent = pet
	end
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
		local other = Instance.new("Folder")
		other.Name = "PetMeshes"
		other.Parent = ReplicatedStorage
	end
	return uploadedModel()
end

local function reset(assetId, mode)
	local existing = ReplicatedStorage:FindFirstChild("PetMeshes")
	while existing do
		existing:Destroy()
		existing = ReplicatedStorage:FindFirstChild("PetMeshes")
	end
	table.clear(calls)
	table.clear(Mock.Warnings)
	GameConfig.PetMeshAssetId = assetId
	behaviour = mode or "ok"
end

local function packCount()
	local count = 0
	for _, child in ReplicatedStorage:GetChildren() do
		if child.Name == "PetMeshes" then
			count += 1
		end
	end
	return count
end

------------------------------------------------------------------------ tests
Mock.IsClient = false -- PetMeshService runs on the server

-- No asset id: nothing is loaded
reset(0)
PetMeshService.Start()
check("id 0: no LoadAsset", #calls == 0, #calls)
check("id 0: no pack", packCount() == 0)

-- Bad config values are ignored
reset("not a number")
PetMeshService.Start()
check("bad id: no LoadAsset", #calls == 0)
reset(-5)
PetMeshService.Start()
check("negative id: no LoadAsset", #calls == 0)

-- A pack already in the place wins
reset(123)
local imported = Instance.new("Folder")
imported.Name = "PetMeshes"
imported.Parent = ReplicatedStorage
PetMeshService.Start()
check("existing pack: no LoadAsset", #calls == 0)
check("existing pack: kept", ReplicatedStorage:FindFirstChild("PetMeshes") == imported and packCount() == 1)

-- Loads the asset into ReplicatedStorage.PetMeshes
reset(123)
PetMeshService.Start()
check("loads the configured id", #calls == 1 and calls[1] == 123, calls[1])
local pack = ReplicatedStorage:FindFirstChild("PetMeshes")
check("pack parented", pack ~= nil and packCount() == 1)
check("pack is a folder", pack and pack:IsA("Folder"))
check("wrapper unwrapped", pack and pack:FindFirstChild("StormlingPets") ~= nil and pack:FindFirstChild("Model") == nil)
check("no warnings", #Mock.Warnings == 0, Mock.Warnings[1])

-- PetModels picks the inserted pack up (pets several levels down)
Mock.IsClient = true
check("PetModels uses the inserted pack", PetModels.HasMeshes("Puffling"))
local model = PetModels.Build("Puffling", "Normal")
check("built from meshes", model:GetAttribute("MeshPack") == true)
check("other pets keep built-in models", PetModels.Build("Ember"):GetAttribute("MeshPack") == false)
Mock.IsClient = false

-- A numeric string id works too
reset("456")
PetMeshService.Start()
check("string id loads", #calls == 1 and calls[1] == 456, calls[1])

-- Retries after a failure
reset(123, "fail-once")
PetMeshService.Start()
check("retried once", #calls == 2, #calls)
check("loaded after retry", packCount() == 1)
check("no warning after a successful retry", #Mock.Warnings == 0, Mock.Warnings[1])

-- Gives up after three failures, with a Studio warning and no pack
reset(123, "fail")
PetMeshService.Start()
check("three attempts", #calls == 3, #calls)
check("no pack after failures", packCount() == 0)
check("warned in Studio", hasMessage(Mock.Warnings, "couldn't load pet mesh pack 123") == 1, Mock.Warnings[1])

-- Live servers stay quiet
Mock.IsStudio = false
reset(123, "fail")
PetMeshService.Start()
check("no warning on live servers", #Mock.Warnings == 0)
Mock.IsStudio = true

-- A pack that turns up while loading wins, and the loaded copy is thrown away
reset(123, "race")
PetMeshService.Start()
check("race: one pack", packCount() == 1, packCount())
local winner = ReplicatedStorage:FindFirstChild("PetMeshes")
check("race: the other pack kept", winner and winner:FindFirstChild("StormlingPets") == nil)

Mock.RealPrint(string.format("PetMeshService mock test: %d passed, %d failed", passes, failures))
if failures > 0 then
	error("mock test failed")
end
