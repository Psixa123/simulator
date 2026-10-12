--!nonstrict
-- Small helpers for talking to clients: notifications, effects and rate limiting.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Net = {}

local lastCall = {} -- [Player] = { [key] = os.clock() }
local lastNotify = {} -- [Player] = { [key] = os.clock() }

-- Returns false when `key` was used by this player less than `interval` seconds ago
function Net.RateLimit(player: Player, key: string, interval: number): boolean
	local now = os.clock()
	local calls = lastCall[player]
	if not calls then
		calls = {}
		lastCall[player] = calls
	end
	local previous = calls[key]
	if previous and now - previous < interval then
		return false
	end
	calls[key] = now
	return true
end

-- kind: "Info" | "Success" | "Error" | "Warning" | "Reward"
function Net.Notify(player: Player, text: string, kind: string?)
	Remotes.Notify:FireClient(player, text, kind or "Info")
end

-- Same as Notify but drops repeats of `key` within `interval` seconds
function Net.NotifyThrottled(player: Player, key: string, text: string, kind: string?, interval: number?)
	local now = os.clock()
	local sent = lastNotify[player]
	if not sent then
		sent = {}
		lastNotify[player] = sent
	end
	if sent[key] and now - sent[key] < (interval or 3) then
		return
	end
	sent[key] = now
	Net.Notify(player, text, kind)
end

function Net.NotifyAll(text: string, kind: string?)
	Remotes.Notify:FireAllClients(text, kind or "Info")
end

function Net.Effect(player: Player, name: string, ...)
	Remotes.Effect:FireClient(player, name, ...)
end

function Net.EffectAll(name: string, ...)
	Remotes.Effect:FireAllClients(name, ...)
end

function Net.Fail(message: string)
	return { Ok = false, Error = message }
end

function Net.GetRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

Players.PlayerRemoving:Connect(function(player)
	lastCall[player] = nil
	lastNotify[player] = nil
end)

return Net
