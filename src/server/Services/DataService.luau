--!nonstrict
-- Loads, replicates and saves player data.
-- Uses UpdateAsync with a session lock so two servers never write the same player's data,
-- autosaves periodically, and saves everyone when the server shuts down.

local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Signal = require(Shared.Util.Signal)
local Remotes = require(Shared.Remotes)

local Net = require(script.Parent.Net)

local DataService = {}
DataService.PlayerLoaded = Signal.new() -- (player, data)
DataService.PlayerLeaving = Signal.new() -- (player, data) fired right before the final save
DataService.Changed = Signal.new() -- (player, key, value)

-- Keys that only exist while the player is in this server
local SESSION_KEYS = { Passes = true, GiftsClaimed = true, SessionStart = true }
-- Keys that are never sent to the client
local PRIVATE_KEYS = { Receipts = true, Codes = true }

local profiles = {} -- [Player] = { Data, Key, CanSave, Released, PlayTimeMark, Saving, UnsavedReceipts }
local releasing = {} -- [UserId] = true while a leaving session's final save is running
local store = nil
local warnedStudio = false

-- Servers ask each other over this topic to release a player's session lock straight away
local RELEASE_TOPIC = "DataRelease"

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
		Stats = { CellsCaught = 0, RareCaught = 0, EggsHatched = 0, MegaStorms = 0, Sells = 0, PlayTime = 0 },
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

-- Asks the server holding a player's lock to save and let go of it now instead of making them wait
local function requestRelease(userId: number, jobId: string)
	task.spawn(function()
		pcall(function()
			MessagingService:PublishAsync(RELEASE_TOPIC, { UserId = userId, JobId = jobId })
		end)
	end)
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
		local lockOwner = nil
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
					-- Only taken over on the last attempt, in case the other server crashed
					lockedElsewhere = true
					lockOwner = lock.JobId
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
		if lockedElsewhere and type(lockOwner) == "string" then
			requestRelease(player.UserId, lockOwner)
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

-- Returns true only when the data was actually written
function DataService.Save(player: Player, release: boolean?): boolean
	local profile = profiles[player]
	-- Once released only the final save may write; a late save would bring back old data and re-lock it
	if not profile or not profile.CanSave or (profile.Released and not release) then
		return false
	end
	local dataStore = getStore()
	if not dataStore then
		return false
	end

	profile.Saving += 1
	local saved = false
	for attempt = 1, 3 do
		if profile.Released and not release then
			break
		end
		-- Serialized on every attempt so a retry never writes older data
		trackPlayTime(profile)
		local payload = serialize(profile.Data)
		if not release then
			payload.SessionLock = { JobId = game.JobId, Time = os.time() }
		end
		local receipts = table.clone(profile.UnsavedReceipts)
		local written, lostLock = false, false

		local ok, err = pcall(function()
			dataStore:UpdateAsync(profile.Key, function(stored)
				written, lostLock = false, false
				if profile.Released and not release then
					return nil
				end
				local lock = type(stored) == "table" and stored.SessionLock
				if lock and lock.JobId ~= game.JobId and os.time() - (lock.Time or 0) < GameConfig.SessionLockTimeout then
					-- Another server took over this player's data; never overwrite it
					lostLock = true
					return nil
				end
				written = true
				return payload
			end)
		end)
		if ok then
			if written then
				for purchaseId in receipts do
					profile.UnsavedReceipts[purchaseId] = nil
				end
			elseif lostLock and profile.CanSave then
				profile.CanSave = false
				warn("[DataService] " .. player.Name .. "'s data was opened in another server; no longer saving it here")
				if not release and player.Parent then
					player:Kick("Your data was opened in another server, please rejoin! ⛈️")
				end
			end
			saved = written
			break
		end
		warn(string.format("[DataService] Save failed for %s (attempt %d): %s", player.Name, attempt, tostring(err)))
		if attempt < 3 then
			task.wait(1.5)
		end
	end
	profile.Saving -= 1
	return saved
end

local function finalSave(player: Player)
	local profile = profiles[player]
	if not profile or profile.Released then
		return
	end
	profile.Released = true
	releasing[player.UserId] = true
	DataService.PlayerLeaving:Fire(player, profile.Data)
	-- Let a save that is already running finish first so it can't land after the release
	local deadline = os.clock() + 10
	while profile.Saving > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
	DataService.Save(player, true)
	profiles[player] = nil
	releasing[player.UserId] = nil
end

local loading = {} -- [Player] = true while their data is being fetched

local function hasPreviousSession(player: Player): boolean
	if releasing[player.UserId] then
		return true
	end
	for other in profiles do
		if other ~= player and other.UserId == player.UserId then
			return true
		end
	end
	return false
end

local function onPlayerAdded(player: Player)
	if loading[player] or profiles[player] then
		return
	end
	loading[player] = true
	-- Rejoining this same server: our own session lock looks free, so wait for the previous
	-- session to finish its final save first or we'd load (and later save over) older data
	local deadline = os.clock() + 30
	while player.Parent and os.clock() < deadline and hasPreviousSession(player) do
		task.wait(0.1)
	end
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
		Saving = 0, -- Save calls in progress
		UnsavedReceipts = {}, -- [purchaseId] = true until a save that includes it succeeds
	}

	if not player.Parent then
		-- Left while we were loading: give the lock back straight away
		finalSave(player)
		return
	end

	DataService.PlayerLoaded:Fire(player, data)
end

-- Another server is loading a player whose lock this server holds
local function onReleaseRequest(message)
	local request = type(message) == "table" and message.Data
	if type(request) ~= "table" or request.JobId ~= game.JobId or type(request.UserId) ~= "number" then
		return
	end
	local player = Players:GetPlayerByUserId(request.UserId)
	if player and loading[player] then
		return
	end
	local profile = player and profiles[player]
	if profile then
		if not profile.Released then
			-- They joined another server, so this session is over: save and hand the data over now
			task.spawn(finalSave, player)
			player:Kick("You joined another server! ⛈️")
		end
		return
	end
	-- No session here any more (our final save failed): drop the lock we left behind
	local dataStore = getStore()
	if not dataStore then
		return
	end
	pcall(function()
		dataStore:UpdateAsync("Player_" .. request.UserId, function(stored)
			local lock = type(stored) == "table" and stored.SessionLock
			if not lock or lock.JobId ~= game.JobId then
				return nil
			end
			stored.SessionLock = nil
			return stored
		end)
	end)
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

-- True once the player's final save has started (they're leaving or the server is closing)
function DataService.IsReleased(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.Released
end

-- Receipts granted in memory stay "unsaved" until a save that includes them succeeds
function DataService.MarkReceiptUnsaved(player: Player, purchaseId: string)
	local profile = profiles[player]
	if profile then
		profile.UnsavedReceipts[purchaseId] = true
	end
end

function DataService.IsReceiptUnsaved(player: Player, purchaseId: string): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.UnsavedReceipts[purchaseId] == true
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

	local waitingForData = {} -- [Player] = true while a GetData call is waiting for their data
	Remotes.GetData.OnServerInvoke = function(player)
		-- The client asks once and retries a second after a nil answer
		if waitingForData[player] or not Net.RateLimit(player, "GetData", 1) then
			return nil
		end
		waitingForData[player] = true
		local data = DataService.WaitForData(player, 45)
		waitingForData[player] = nil
		if not data then
			return nil
		end
		return DataService.Snapshot(player)
	end

	local settingsQueued = {} -- [Player] = true while a throttled Settings update is waiting to be sent
	Remotes.SetSetting.OnServerInvoke = function(player, key, value)
		local data = DataService.Get(player)
		if not data or type(key) ~= "string" or type(value) ~= "boolean" then
			return false
		end
		if GameConfig.DefaultSettings[key] == nil then
			return false
		end
		data.Settings[key] = value
		if Net.RateLimit(player, "SetSetting", 0.2) then
			DataService.Replicate(player, "Settings")
		elseif not settingsQueued[player] then
			-- Spammed toggles still apply, but the client gets one update for the lot
			settingsQueued[player] = true
			task.delay(0.2, function()
				settingsQueued[player] = nil
				DataService.Replicate(player, "Settings")
			end)
		end
		return true
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(finalSave)

	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(RELEASE_TOPIC, onReleaseRequest)
		end)
		if not ok and not RunService:IsStudio() then
			warn("[DataService] Couldn't listen for data release requests: " .. tostring(err))
		end
	end)

	game:BindToClose(function()
		for player in table.clone(profiles) do
			task.spawn(finalSave, player)
		end
		-- Also wait for players still loading: they may hold a lock that needs releasing
		local deadline = os.clock() + 25
		while (next(profiles) ~= nil or next(loading) ~= nil) and os.clock() < deadline do
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
