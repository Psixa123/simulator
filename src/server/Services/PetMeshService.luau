--!nonstrict
-- Puts the uploaded pet mesh pack (README: "Better pet models") in ReplicatedStorage.PetMeshes.
-- tools/roblox/upload_pets.py uploads assets/models/StormlingPets.glb to Roblox and writes the model's
-- asset id into GameConfig.PetMeshAssetId; this service inserts that model at server start. A pack that
-- is already in the place (imported in Studio, or PetMeshes.rbxm built in by Rojo) wins. PetModels uses
-- the pack as soon as it appears and keeps the built-in models until then, or if loading fails.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)

local PetMeshService = {}

local PACK_NAME = "PetMeshes"
local ATTEMPTS = 3
local RETRY_DELAY = 5 -- seconds, times the attempt number

local function studioWarn(message: string)
	if RunService:IsStudio() then
		warn("[PetMeshService] " .. message)
	end
end

local function loadPack(assetId: number): Instance?
	local lastError
	for attempt = 1, ATTEMPTS do
		local ok, result = pcall(InsertService.LoadAsset, InsertService, assetId)
		if ok and result then
			return result
		end
		lastError = result
		if attempt < ATTEMPTS then
			task.wait(RETRY_DELAY * attempt)
		end
	end
	studioWarn(
		`couldn't load pet mesh pack {assetId} ({tostring(lastError)}); pets use their built-in models. `
			.. "The model must belong to the game's owner (the same user or group)."
	)
	return nil
end

function PetMeshService.Start()
	local assetId = tonumber(GameConfig.PetMeshAssetId)
	if not assetId or assetId <= 0 or ReplicatedStorage:FindFirstChild(PACK_NAME) then
		return
	end

	local loaded = loadPack(assetId)
	if not loaded then
		return
	end
	if ReplicatedStorage:FindFirstChild(PACK_NAME) then
		loaded:Destroy() -- a pack turned up while loading
		return
	end

	-- LoadAsset wraps the asset in a Model; keep its contents (PetModels finds the pets at any depth)
	local pack = Instance.new("Folder")
	pack.Name = PACK_NAME
	for _, child in loaded:GetChildren() do
		child.Parent = pack
	end
	loaded:Destroy()
	pack.Parent = ReplicatedStorage
end

return PetMeshService
