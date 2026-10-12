--!nonstrict
-- Biome hazards (tuning in Config/Zones, shared rules in Shared/Hazards):
--   Thunder Valley  - lightning aimed near each player: a warning circle, then a strike that stuns
--   Dune Sea        - server-wide sandstorms on a schedule (the client thickens the haze)
--   Frostpeak       - the cold slows players without good Storm Boots (PlayerService.RefreshWalkSpeed)
--   Ashfall Volcano - heat damage over time, except in the cooling areas built by MapService
--   Upper Atmosphere - low gravity, handled entirely by the client (HazardController)
-- Hazards never apply in the hub or the Mega Storm arena.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Hazards = require(Shared.Hazards)

local Registry = require(script.Parent.Registry)
local Net = require(script.Parent.Net)

local HazardService = {}

local TICK = 0.25
local RESPAWN_GRACE = 5 -- seconds before a fresh character can be hit by lightning

local states = {} -- [Player] = { Character, Zone, GraceUntil, NextStrike, StunToken }
local immune = {} -- [Player] = true while hazards are switched off for them
local sandstorms = {} -- [zoneId] = { Hazard, Active, Until }
local stateFolder: Configuration
local rng = Random.new()

local function getState(player: Player)
	local state = states[player]
	if not state then
		state = { Character = nil, Zone = -1, GraceUntil = 0, NextStrike = 0, StunToken = 0 }
		states[player] = state
	end
	return state
end

-- Hazard of the zone the player's current character is standing in (nil when there is none)
function HazardService.CurrentHazard(player: Player)
	local state = states[player]
	if not state or state.Character ~= player.Character then
		return nil
	end
	return Hazards.Get(state.Zone)
end

-- Switches every hazard off for a player (used by the Studio smoke test)
function HazardService.SetImmune(player: Player, enabled: boolean)
	immune[player] = if enabled then true else nil
end

---------------------------------------------------------------------------
-- Lightning (Thunder Valley)
---------------------------------------------------------------------------
local function stun(player: Player, duration: number)
	local state = states[player]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not state or not humanoid or humanoid.Health <= 0 then
		return
	end
	state.StunToken += 1
	local token = state.StunToken

	character:SetAttribute("Stunned", true)
	Registry.WeatherService.StopCatch(player)
	Registry.PlayerService.RefreshWalkSpeed(player)

	task.delay(duration, function()
		if state.StunToken ~= token then
			return -- hit again meanwhile: the newer stun ends it
		end
		if character.Parent then
			character:SetAttribute("Stunned", nil)
		end
		if player.Parent and player.Character == character then
			Registry.PlayerService.RefreshWalkSpeed(player)
		end
	end)
end

-- Height of the ground below `position` so the warning circle sits on the terrain
local function groundAt(position: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	local result = Workspace:Raycast(position + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), params)
	return if result then result.Position else Vector3.new(position.X, 0, position.Z)
end

local function strike(zoneId: number, hazard, around: Vector3)
	local angle = rng:NextNumber(0, math.pi * 2)
	local distance = rng:NextNumber(0, hazard.Spread)
	local position = groundAt(around + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance))

	Net.EffectAll("LightningWarning", position, hazard.Radius, hazard.WarnTime)
	task.delay(hazard.WarnTime, function()
		Net.EffectAll("LightningStrike", position, hazard.Radius)
		local now = os.clock()
		for _, player in Players:GetPlayers() do
			local state = states[player]
			local root = Net.GetRoot(player)
			if state and root and not immune[player] and now >= state.GraceUntil and Hazards.ZoneAt(root.Position) == zoneId then
				local offset = root.Position - position
				if Vector2.new(offset.X, offset.Z).Magnitude <= hazard.Radius and math.abs(offset.Y) <= hazard.Radius + 6 then
					stun(player, hazard.StunTime)
				end
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Heat (Ashfall Volcano)
---------------------------------------------------------------------------
local function applyHeat(player: Player, humanoid: Humanoid, root: BasePart, zoneId: number, hazard, dt: number)
	if Hazards.IsCool(zoneId, root.Position, hazard.SafeRadius) then
		if humanoid.Health < humanoid.MaxHealth then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + hazard.CoolHeal * dt)
		end
		return
	end
	humanoid:TakeDamage(hazard.Damage * dt)
	if humanoid.Health <= 0 then
		Net.Notify(player, "🔥 You overheated! Cool off near a Weather Lab next time.", "Warning")
	end
end

---------------------------------------------------------------------------
-- Sandstorms (Dune Sea)
---------------------------------------------------------------------------
local function setSandstorm(zoneId: number, active: boolean, now: number)
	local storm = sandstorms[zoneId]
	local hazard = storm.Hazard
	storm.Active = active
	storm.Until = now + (if active then hazard.Duration else rng:NextNumber(hazard.Calm.Min, hazard.Calm.Max))
	stateFolder:SetAttribute(Hazards.SandstormAttribute(zoneId), active)
end

-- Starts a sandstorm right now in one zone (or every sandstorm zone)
function HazardService.StartSandstorm(zoneId: number?)
	for id in sandstorms do
		if zoneId == nil or zoneId == id then
			setSandstorm(id, true, os.clock())
		end
	end
end

---------------------------------------------------------------------------
-- Loop
---------------------------------------------------------------------------
local function updatePlayer(player: Player, now: number, dt: number)
	if not Registry.DataService.Get(player) then
		return
	end
	local state = getState(player)
	local character = player.Character
	if character ~= state.Character then
		state.Character = character
		state.Zone = -1 -- re-evaluate everything for the new character
		state.GraceUntil = now + RESPAWN_GRACE
	end

	local root = Net.GetRoot(player)
	local zoneId = if root and not immune[player] then Hazards.ZoneAt(root.Position) else 0
	local hazard = Hazards.Get(zoneId)
	if zoneId ~= state.Zone then
		state.Zone = zoneId
		if hazard and hazard.Kind == "Lightning" then
			state.GraceUntil = math.max(state.GraceUntil, now + hazard.Grace)
			state.NextStrike = math.max(state.GraceUntil, now + rng:NextNumber(hazard.Interval.Min, hazard.Interval.Max))
		end
		Registry.PlayerService.RefreshWalkSpeed(player)
	end
	if not hazard or not root or not character then
		return
	end

	if hazard.Kind == "Lightning" then
		if now >= state.NextStrike then
			state.NextStrike = now + hazard.WarnTime + rng:NextNumber(hazard.Interval.Min, hazard.Interval.Max)
			if now >= state.GraceUntil and not character:GetAttribute("Stunned") then
				strike(zoneId, hazard, root.Position)
			end
		end
	elseif hazard.Kind == "Heat" then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			applyHeat(player, humanoid, root, zoneId, hazard, dt)
		end
	end
end

function HazardService.Init()
	stateFolder = Instance.new("Configuration")
	stateFolder.Name = Hazards.StateName
	stateFolder.Parent = ReplicatedStorage

	local now = os.clock()
	for zoneId, zone in ipairs(Zones) do
		local hazard = zone.Hazard
		if hazard and hazard.Kind == "Sandstorm" then
			sandstorms[zoneId] = { Hazard = hazard, Active = false, Until = 0 }
			setSandstorm(zoneId, false, now)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		immune[player] = nil
	end)
end

function HazardService.Start()
	local last = os.clock()
	while true do
		task.wait(TICK)
		local now = os.clock()
		local dt = math.min(now - last, 1)
		last = now

		for zoneId, storm in sandstorms do
			if now >= storm.Until then
				setSandstorm(zoneId, not storm.Active, now)
			end
		end

		for _, player in Players:GetPlayers() do
			local ok, err = pcall(updatePlayer, player, now, dt)
			if not ok then
				warn("[HazardService] " .. tostring(err))
			end
		end
	end
end

return HazardService
