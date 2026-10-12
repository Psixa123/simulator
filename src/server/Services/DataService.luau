--!nonstrict
-- Loads, replicates and saves player data.
-- Uses UpdateAsync with a session lock so two servers never write the same player's data,
-- autosaves periodically, and saves everyone when the server shuts down.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Signal = require(Shared.Util.Signal)
local Remotes = require(Shared.Remotes)

local DataService = {}
DataService.PlayerLoaded = Signal.new() -- (player, data)
DataService.PlayerLeaving = Signal.new() -- (player, data) fired right before the final save
DataService.Changed = Signal.new() -- (player, key, value)

-- Keys that only exist while the player is in this server
local SESSION_KEYS = { Passes = true, GiftsClaimed = true, SessionStart = true }
-- Keys that are never sent to the client
local PRIVATE_KEYS = { Receipts = true, Codes = true }

local profiles = {} -- [Player] = { Data, Key, CanSave, Released, PlayTimeMark }
local store = nil
local warnedStudio = false

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[key] = deepCopy(item)
	end
	return copy
end

local function template()
	return {
		DataVersion = 1,
		Volts = 0,
		TotalVolts = 0,
		Energy = 0,
		TankValue = 0,
		Rebirths = 0,
		Zone = 1,
		Upgrades = { Power = 1, Tank = 1, Range = 1, Speed = 1 },
		Pets = {},
		NextPetId = 1,
		Index = {},
		Boosts = { Energy = 0, Luck = 0 },
		Daily = { Streak = 0, LastClaim = 0 },
		Codes = {},
		Settings = deepCopy(GameConfig.DefaultSettings),
		Stats = { CellsCaught = 0, EggsHatched = 0, MegaStorms = 0, Sells = 0, PlayTime = 0 },
		Receipts = {},
	}
end

-- Adds any keys that are missing (new features) without touching existing values
local function reconcile(target, defaults)
	for key, value in defaults do
		if target[key] == nil then
			target[key] = deepCopy(value)
		elseif type(value) == "table" and type(target[key]) == "table" and next(value) ~= nil and #value == 0 then
			reconcile(target[key], value)
		end
	end
end

local function getStore()
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStoreName)
	end)
	if ok then
		store = result
	end
	return store
end

local function loadFromStore(player: Player)
	local dataStore = getStore()
	if not dataStore then
		return nil, "DataStore unavailable"
	end

	local key = "Player_" .. player.UserId
	local lastError = "Unknown error"

	for attempt = 1, 6 do
		local lockedElsewhere = false
		local ok, result = pcall(function()
			return dataStore:UpdateAsync(key, function(stored)
				lockedElsewhere = false
				local lock = type(stored) == "table" and stored.SessionLock
				if
					lock
					and lock.JobId ~= game.JobId
					and os.time() - (lock.Time or 0) < GameConfig.SessionLockTimeout
					and attempt < 6
				then
					lockedElsewhere = true
					return nil
				end
				local value = if type(stored) == "table" then stored else template()
				value.SessionLock = { JobId = game.JobId, Time = os.time() }
				return value
			end)
		end)

		if ok and not lockedElsewhere and type(result) == "table" then
			return result
		end

		lastError = if ok then "Your data is still open in another server" else tostring(result)
		if not player.Parent then
			return nil, "Player left"
		end
		if not ok and RunService:IsStudio() then
			-- Studio without API access fails instantly; don't keep the tester waiting
			return nil, lastError
		end
		task.wait(if lockedElsewhere then 5 else 2)
	end

	return nil, lastError
end

local function serialize(data)
	local out = {}
	for key, value in data do
		if not SESSION_KEYS[key] then
			out[key] = deepCopy(value)
		end
	end
	-- Boosts are stored as remaining seconds so they pause while offline
	local now = os.time()
	out.Boosts = {}
	for name, endTime in data.Boosts do
		out.Boosts[name] = math.max(0, math.floor(endTime - now))
	end
	return out
end

local function trackPlayTime(profile)
	local now = os.time()
	profile.Data.Stats.PlayTime += now - profile.PlayTimeMark
	profile.PlayTimeMark = now
end

function DataService.Save(player: Player, release: boolean?): boolean
	local profile = profiles[player]
	if not profile or not profile.CanSave then
		return false
	end
	local dataStore = getStore()
	if not dataStore then
		return false
	end

	trackPlayTime(profile)
	local payload = serialize(profile.Data)
	if not release then
		payload.SessionLock = { JobId = game.JobId, Time = os.time() }
	end

	for attempt = 1, 3 do
		local ok, err = pcall(function()
			dataStore:UpdateAsync(profile.Key, function(stored)
				local lock = type(stored) == "table" and stored.SessionLock
				if lock and lock.JobId ~= game.JobId and os.time() - (lock.Time or 0) < GameConfig.SessionLockTimeout then
					-- Another server took over this player's data; never overwrite it
					return nil
				end
				return payload
			end)
		end)
		if ok then
			return true
		end
		warn(string.format("[DataService] Save failed for %s (attempt %d): %s", player.Name, attempt, tostring(err)))
		task.wait(1.5)
	end
	return false
end

local function finalSave(player: Player)
	local profile = profiles[player]
	if not profile or profile.Released then
		return
	end
	profile.Released = true
	DataService.PlayerLeaving:Fire(player, profile.Data)
	DataService.Save(player, true)
	profiles[player] = nil
end

local loading = {} -- [Player] = true while their data is being fetched

local function onPlayerAdded(player: Player)
	if loading[player] or profiles[player] then
		return
	end
	loading[player] = true
	local data, err = loadFromStore(player)
	loading[player] = nil
	local canSave = data ~= nil

	if not data then
		if not player.Parent then
			return
		end
		if RunService:IsStudio() then
			if not warnedStudio then
				warnedStudio = true
				warn(
					"[DataService] Using temporary data because DataStores are unavailable ("
						.. tostring(err)
						.. "). Turn on Game Settings > Security > 'Enable Studio Access to API Services' to test saving."
				)
			end
			data = template()
		else
			player:Kick("We couldn't load your data, please rejoin in a moment! (" .. tostring(err) .. ")")
			return
		end
	end

	data.SessionLock = nil
	reconcile(data, template())

	local now = os.time()
	for name, remaining in data.Boosts do
		data.Boosts[name] = if remaining > 0 then now + remaining else 0
	end
	data.Passes = {}
	data.GiftsClaimed = {}
	data.SessionStart = now

	profiles[player] = {
		Data = data,
		Key = "Player_" .. player.UserId,
		CanSave = canSave,
		Released = false,
		PlayTimeMark = now,
	}

	if not player.Parent then
		-- Left while we were loading: give the lock back straight away
		finalSave(player)
		return
	end

	DataService.PlayerLoaded:Fire(player, data)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
function DataService.Get(player: Player)
	local profile = profiles[player]
	return profile and profile.Data
end

function DataService.CanSave(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.CanSave
end

function DataService.WaitForData(player: Player, timeout: number?)
	local deadline = os.clock() + (timeout or 30)
	while player.Parent and os.clock() < deadline do
		local profile = profiles[player]
		if profile then
			return profile.Data
		end
		task.wait(0.1)
	end
	local profile = profiles[player]
	return profile and profile.Data
end

-- Sends the current value of the given keys to the client and fires Changed
function DataService.Replicate(player: Player, ...: string)
	local profile = profiles[player]
	if not profile then
		return
	end
	local changes = {}
	local hasChanges = false
	for _, key in { ... } do
		local value = profile.Data[key]
		if not PRIVATE_KEYS[key] then
			changes[key] = value
			hasChanges = true
		end
		DataService.Changed:Fire(player, key, value)
	end
	if hasChanges then
		Remotes.DataChanged:FireClient(player, changes)
	end
end

function DataService.Set(player: Player, key: string, value: any)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Data[key] = value
	DataService.Replicate(player, key)
end

function DataService.Snapshot(player: Player)
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local snapshot = {}
	for key, value in profile.Data do
		if not PRIVATE_KEYS[key] then
			snapshot[key] = value
		end
	end
	return snapshot
end

function DataService.Init()
	getStore()

	Remotes.GetData.OnServerInvoke = function(player)
		local data = DataService.WaitForData(player, 45)
		if not data then
			return nil
		end
		return DataService.Snapshot(player)
	end

	Remotes.SetSetting.OnServerInvoke = function(player, key, value)
		local data = DataService.Get(player)
		if not data or type(key) ~= "string" or type(value) ~= "boolean" then
			return false
		end
		if GameConfig.DefaultSettings[key] == nil then
			return false
		end
		data.Settings[key] = value
		DataService.Replicate(player, "Settings")
		return true
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(finalSave)

	game:BindToClose(function()
		for player in table.clone(profiles) do
			task.spawn(finalSave, player)
		end
		local deadline = os.clock() + 25
		while next(profiles) ~= nil and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

function DataService.Start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	while true do
		task.wait(GameConfig.AutosaveInterval)
		for player, profile in table.clone(profiles) do
			if not profile.Released and profile.CanSave and player.Parent then
				task.spawn(DataService.Save, player, false)
				task.wait(0.5)
			end
		end
	end
end

return DataService
