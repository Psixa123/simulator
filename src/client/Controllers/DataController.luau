--!nonstrict
-- Client-side replica of the player's data. The server sends a snapshot on join and
-- then pushes changed keys through the DataChanged remote.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Remotes = require(Shared.Remotes)

local DataController = {}
DataController.Data = nil
DataController.Changed = Signal.new() -- (key, value)

local keySignals = {}

local function signalFor(key: string)
	local signal = keySignals[key]
	if not signal then
		signal = Signal.new()
		keySignals[key] = signal
	end
	return signal
end

function DataController.Get(key: string)
	return DataController.Data and DataController.Data[key]
end

-- Calls `callback(value)` now (if loaded) and every time `key` changes
function DataController.Observe(key: string, callback: (any) -> ())
	if DataController.Data then
		task.spawn(callback, DataController.Data[key])
	end
	return signalFor(key):Connect(callback)
end

-- Calls `callback()` now and whenever any of `keys` changes
function DataController.ObserveMany(keys: { string }, callback: () -> ())
	if DataController.Data then
		task.spawn(callback)
	end
	local connections = {}
	for _, key in keys do
		table.insert(connections, signalFor(key):Connect(callback))
	end
	return connections
end

-- Server unix time (synced)
function DataController.Now(): number
	return Workspace:GetServerTimeNow()
end

function DataController.Init()
	Remotes.DataChanged.OnClientEvent:Connect(function(changes)
		local data = DataController.Data
		if not data then
			-- Anything sent before our snapshot is older than it; ignore it
			return
		end
		for key, value in changes do
			data[key] = value
		end
		for key, value in changes do
			DataController.Changed:Fire(key, value)
			local signal = keySignals[key]
			if signal then
				signal:Fire(value)
			end
		end
	end)
end

-- Blocks until the server has sent our data
function DataController.Load()
	while not DataController.Data do
		local ok, result = pcall(function()
			return Remotes.GetData:InvokeServer()
		end)
		if ok and type(result) == "table" then
			DataController.Data = result
		else
			task.wait(1)
		end
	end
	return DataController.Data
end

return DataController
