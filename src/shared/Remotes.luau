--!nonstrict
-- Typed access to the RemoteEvents / RemoteFunctions defined in default.project.json.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:WaitForChild("Remotes")

local function get(name: string)
	return folder:WaitForChild(name)
end

return {
	-- RemoteFunctions (client -> server, with a response)
	GetData = get("GetData") :: RemoteFunction,
	BuyUpgrade = get("BuyUpgrade") :: RemoteFunction,
	UnlockZone = get("UnlockZone") :: RemoteFunction,
	Teleport = get("Teleport") :: RemoteFunction,
	Rebirth = get("Rebirth") :: RemoteFunction,
	Hatch = get("Hatch") :: RemoteFunction,
	PetAction = get("PetAction") :: RemoteFunction,
	ClaimDaily = get("ClaimDaily") :: RemoteFunction,
	ClaimGift = get("ClaimGift") :: RemoteFunction,
	RedeemCode = get("RedeemCode") :: RemoteFunction,
	SetSetting = get("SetSetting") :: RemoteFunction,
	Sell = get("Sell") :: RemoteFunction,
	DevGrant = get("DevGrant") :: RemoteFunction,

	-- RemoteEvents
	Catch = get("Catch") :: RemoteEvent, -- client -> server
	DataChanged = get("DataChanged") :: RemoteEvent, -- server -> client
	Notify = get("Notify") :: RemoteEvent, -- server -> client
	Effect = get("Effect") :: RemoteEvent, -- server -> client
}
