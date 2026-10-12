--!nonstrict
-- Global leaderboards (OrderedDataStores) shown on the boards in the hub.
-- Volts are stored log-encoded so astronomically large numbers still fit in an integer.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Util.Format)

local Registry = require(script.Parent.Registry)

local LeaderboardService = {}

local REFRESH_INTERVAL = 90
local WRITE_INTERVAL = 120
local ENTRIES = 10

local BOARDS = {
	Volts = {
		StoreName = "LB_TotalVolts_v1",
		Stat = "TotalVolts",
		Encode = function(value: number): number
			return math.floor(math.log10(math.max(0, value) + 1) * 1e10)
		end,
		Decode = function(stored: number): number
			return 10 ^ (stored / 1e10) - 1
		end,
	},
	Rebirths = {
		StoreName = "LB_Rebirths_v1",
		Stat = "Rebirths",
		Encode = function(value: number): number
			return math.floor(value)
		end,
		Decode = function(stored: number): number
			return stored
		end,
	},
}

local stores = {}
local nameCache = {}

local function getName(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.Name
		return player.Name
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and name then
		nameCache[userId] = name
		return name
	end
	return "Player"
end

local function writePlayer(player: Player, data)
	for kind, board in BOARDS do
		local store = stores[kind]
		local value = data[board.Stat] or 0
		if store and value > 0 then
			pcall(function()
				store:SetAsync(tostring(player.UserId), board.Encode(value))
			end)
		end
	end
end

local function setStatus(kind: string, text: string?)
	local gui = Registry.MapService.Leaderboards[kind]
	if gui and gui.Status then
		gui.Status.Text = text or ""
		gui.Status.Visible = text ~= nil
	end
end

local function refreshBoard(kind: string)
	local board = BOARDS[kind]
	local gui = Registry.MapService.Leaderboards[kind]
	local store = stores[kind]
	if not gui then
		return
	end
	if not store then
		setStatus(kind, "Leaderboards need DataStores.\nEnable API access in Game Settings.")
		return
	end

	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, ENTRIES)
	end)
	if not ok then
		setStatus(kind, "Leaderboard unavailable right now.\n(Enable API access when testing in Studio)")
		return
	end

	local entries = pages:GetCurrentPage()
	setStatus(kind, if #entries == 0 then "No storm catchers yet.\nBe the first!" else nil)
	for rank = 1, ENTRIES do
		local row = gui.Rows[rank]
		local entry = entries[rank]
		if row then
			if entry then
				local userId = tonumber(entry.key)
				row.Name.Text = if userId then getName(userId) else "?"
				row.Value.Text = Format.Number(board.Decode(entry.value))
				row.Frame.Visible = true
			else
				row.Frame.Visible = false
			end
		end
	end
end

function LeaderboardService.Init()
	for kind, board in BOARDS do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(board.StoreName)
		end)
		if ok then
			stores[kind] = store
		end
	end

	Registry.DataService.PlayerLeaving:Connect(function(player, data)
		task.spawn(writePlayer, player, data)
	end)
end

function LeaderboardService.Start()
	task.spawn(function()
		while true do
			task.wait(WRITE_INTERVAL)
			for _, player in Players:GetPlayers() do
				local data = Registry.DataService.Get(player)
				if data then
					writePlayer(player, data)
					task.wait(1)
				end
			end
		end
	end)

	task.wait(5)
	while true do
		for kind in BOARDS do
			refreshBoard(kind)
			task.wait(2)
		end
		task.wait(REFRESH_INTERVAL)
	end
end

return LeaderboardService
