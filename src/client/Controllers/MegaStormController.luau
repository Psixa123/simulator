--!nonstrict
-- Client side of the Mega Storm event: the HUD's storm timer and side card (HudController.SetStorm), storm animation, lightning,
-- a gentle camera sway, announcements and reward popups. The Rainbow Hurricane cycles its colours.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MapLayout = require(Shared.Config.MapLayout)
local Pets = require(Shared.Config.Pets)
local Formulas = require(Shared.Formulas)
local StormSchedule = require(Shared.StormSchedule)
local Format = require(Shared.Util.Format)

local Registry = require(script.Parent.Parent.Registry)

local MegaStormController = {}

local ANIMATE_RANGE = 400 -- the storm isn't animated while the camera is further away than this
local SWAY_RANGE = 110 -- the camera sways gently within this distance of an active storm
local SWAY_STRENGTH = 0.3 -- studs of sway at the storm's centre
local SWAY_SPEED = 0.7

local player = Players.LocalPlayer
local state: Configuration
local contribution = 0
local storm = nil -- { Model, Pivot, Spin = {}, Debris = {}, Collapsing, Rainbow = { bands } or nil }
local lightningTimer = 0
local swaySeed = math.random() * 1000
local swaying = false

local function stormType()
	return StormSchedule.Current(state)
end

local function lowGraphics(): boolean
	local settings = Registry.DataController.Get("Settings")
	return settings ~= nil and settings.LowGraphics == true
end

local function rainbowColor(offset: number): Color3
	return Color3.fromHSV((os.clock() * 0.2 + offset) % 1, 0.55, 1)
end

function MegaStormController.IsActive(): boolean
	return state ~= nil and state:GetAttribute("Phase") == "Active"
end

local function updateHud()
	local phase = state:GetAttribute("Phase") or "Idle"
	local now = Registry.DataController.Now()
	local current = stormType()
	local info = { Phase = phase, Name = current.Name, Pet = current.Pet }
	if phase == "Active" then
		local remaining = math.max(0, (state:GetAttribute("EndTime") or now) - now)
		info.Timer = Format.Time(remaining)
		info.Health = state:GetAttribute("Health") or 0
		info.MaxHealth = state:GetAttribute("MaxHealth") or 1
		info.Damage = contribution -- our own estimate (the HUD prefers the server's MegaDamage attribute)
		info.Info = "⏱ " .. Format.Time(remaining) .. "   •   Your damage: " .. Format.Number(contribution)
	else
		info.Timer = Format.Time((state:GetAttribute("NextTime") or now) - now)
	end
	Registry.HudController.SetStorm(info)
end

---------------------------------------------------------------------------
-- Storm model animation
---------------------------------------------------------------------------
local function registerStorm(model: Model)
	local pivot = model:GetPivot()
	local entry = { Model = model, Pivot = pivot, Spin = {}, Debris = {}, Collapsing = false, Fade = 0, Rainbow = nil }
	if model:GetAttribute("Rainbow") then
		-- Rainbow Hurricane: remember each band's hue so the colours can flow up the storm
		entry.Rainbow = {}
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") and (part.Name == "Layer" or part.Name == "Streak" or part.Name == "Eye") then
				local hue, saturation = part.Color:ToHSV()
				table.insert(entry.Rainbow, { Part = part, Hue = hue, Saturation = saturation })
			end
		end
	end
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			local speed = part:GetAttribute("SpinSpeed")
			if speed then
				table.insert(entry.Spin, { Part = part, Speed = speed, Offset = pivot:ToObjectSpace(part.CFrame) })
			elseif part:GetAttribute("OrbitRadius") then
				table.insert(entry.Debris, {
					Part = part,
					Radius = part:GetAttribute("OrbitRadius"),
					Height = part:GetAttribute("OrbitHeight"),
					Speed = part:GetAttribute("OrbitSpeed"),
					Phase = part:GetAttribute("OrbitPhase"),
				})
			end
		end
	end
	storm = entry
end

-- Smooth, low-amplitude camera sway near the active storm (none in Performance Mode)
local function updateSway(now: number)
	if not storm and not swaying then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return
	end
	local distance = if storm then (root.Position - storm.Pivot.Position).Magnitude else math.huge
	if distance < SWAY_RANGE and not storm.Collapsing and MegaStormController.IsActive() and not lowGraphics() then
		local strength = (1 - distance / SWAY_RANGE) * SWAY_STRENGTH
		local t = now * SWAY_SPEED
		humanoid.CameraOffset = Vector3.new(math.noise(t, swaySeed), math.noise(t, swaySeed + 17.3) * 0.5, math.noise(t, swaySeed + 41.7)) * strength
		swaying = true
	elseif swaying then
		humanoid.CameraOffset = Vector3.zero
		swaying = false
	end
end

local function animateStorm(dt: number)
	local now = os.clock()
	if storm and not storm.Model.Parent then
		storm = nil
	end
	updateSway(now)
	if not storm then
		return
	end
	if (Workspace.CurrentCamera.CFrame.Position - storm.Pivot.Position).Magnitude > ANIMATE_RANGE then
		return -- too far away to see the storm move
	end
	local speedBoost = if storm.Collapsing then 3 else 1
	for _, item in storm.Spin do
		item.Part.CFrame = storm.Pivot * CFrame.Angles(0, now * item.Speed * speedBoost, 0) * item.Offset
	end
	for _, item in storm.Debris do
		local angle = item.Phase + now * item.Speed * speedBoost
		item.Part.CFrame = storm.Pivot
			* CFrame.new(math.cos(angle) * item.Radius, item.Height + math.sin(now + item.Phase) * 3, math.sin(angle) * item.Radius)
			* CFrame.Angles(now, now * 0.7, 0)
	end

	if storm.Rainbow and not storm.Collapsing and not lowGraphics() then
		local shift = now * 0.2
		for _, band in storm.Rainbow do
			band.Part.Color = Color3.fromHSV((band.Hue + shift) % 1, band.Saturation, 1)
		end
	end

	if MegaStormController.IsActive() then
		lightningTimer -= dt
		if lightningTimer <= 0 then
			lightningTimer = 0.5 + math.random() * 0.9
			local angle = math.random() * math.pi * 2
			local radius = math.random(10, 40)
			local top = storm.Pivot.Position + Vector3.new(math.cos(angle) * radius, math.random(40, 80), math.sin(angle) * radius)
			local bottom = storm.Pivot.Position + Vector3.new(math.cos(angle) * (radius + 12), 0, math.sin(angle) * (radius + 12))
			local boltColor = if storm.Rainbow then rainbowColor(math.random()) else stormType().Accent
			Registry.EffectsController.LightningBolt(top, bottom, boltColor, 1.2)
		end
	end
end

local function collapse()
	if not storm then
		return
	end
	storm.Collapsing = true
	for _, part in storm.Model:GetDescendants() do
		if part:IsA("BasePart") then
			TweenService:Create(part, TweenInfo.new(2.4), { Transparency = 1 }):Play()
		elseif part:IsA("ParticleEmitter") then
			part.Enabled = false
		end
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.CameraOffset = Vector3.zero
	end
end

---------------------------------------------------------------------------
-- Effects from the server
---------------------------------------------------------------------------
function MegaStormController.HandleEffect(name: string, ...)
	local args = { ... }
	if name == "MegaWarning" then
		local summoner = args[2]
		local current = StormSchedule.TypeFor(args[3], args[1])
		local subtitle = current.Name .. "  •  Head to the arena in the Storm Station!"
		if summoner and summoner ~= "" then
			subtitle = "Summoned by " .. summoner .. "!"
		end
		Registry.SoundController.Play("Alarm")
		if StormSchedule.IsRainbow(current) then
			local pet = Pets.Pets[current.Pet]
			subtitle = "Head to the arena for a shot at the exclusive " .. (if pet then pet.Name else "pet") .. "!"
			Registry.InterfaceController.BigText("🌈 RAINBOW HURRICANE INCOMING!", current.Color, subtitle, 3.6)
		else
			Registry.InterfaceController.BigText("⚠️ MEGA STORM INCOMING!", Color3.fromRGB(255, 150, 60), subtitle, 3.2)
		end
	elseif name == "MegaStart" then
		local current = StormSchedule.TypeFor(args[2], args[1])
		contribution = 0
		Registry.SoundController.Play("Alarm", 0.85)
		Registry.InterfaceController.BigText((current.Icon or "🌪️") .. " " .. string.upper(current.Name) .. "!", current.Color, "Vacuum it together before it escapes!", 3)
	elseif name == "MegaRainbowSoon" then
		local rainbow = GameConfig.MegaStorm.Rainbow
		local now = Registry.DataController.Now()
		local minutes = math.max(1, math.round(((args[1] or now) - now) / 60))
		local pet = Pets.Pets[rainbow.Pet]
		Registry.SoundController.Play("Alarm", 1.15)
		Registry.InterfaceController.BigText(
			string.format("🌈 %s IN %d MINUTE%s!", string.upper(rainbow.Name), minutes, if minutes == 1 then "" else "S"),
			rainbow.Color,
			"Gather at the Mega Storm Arena for the exclusive " .. (if pet then pet.Name else "pet") .. "!",
			4
		)
	elseif name == "MegaEnd" then
		local defeated = args[1]
		local current = StormSchedule.TypeFor(args[3], args[2])
		collapse()
		if defeated then
			Registry.SoundController.Play("Success", 0.8)
			Registry.InterfaceController.BigText(
				if StormSchedule.IsRainbow(current) then "🌈 RAINBOW HURRICANE DEFEATED!" else "STORM DEFEATED!",
				Color3.fromRGB(110, 230, 140),
				"Rewards sent to every storm catcher who helped!",
				3
			)
		else
			Registry.InterfaceController.BigText("THE STORM ESCAPED!", Color3.fromRGB(255, 120, 120), "Everyone who helped still earns a reward.", 3)
		end
	elseif name == "MegaReward" then
		local volts, rank, total, petId = args[1], args[2], args[3], args[4]
		Registry.InterfaceController.Notify(
			string.format("🏆 You placed #%d of %d  •  +⚡ %s Volts", rank, total, Format.Number(volts)),
			"Reward"
		)
		Registry.EffectsController.Confetti(70)
		if petId and Pets.Pets[petId] then
			task.delay(1.5, function()
				Registry.HatchOverlay.Reveal(petId, false, "EXCLUSIVE PET!")
			end)
		end
	end
end

function MegaStormController.Init()
	state = ReplicatedStorage:WaitForChild("MegaStormState")
end

function MegaStormController.Start()
	local folder = Workspace:WaitForChild("MegaStorm")
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.wait()
			registerStorm(child)
		end
	end)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			registerStorm(child)
		end
	end

	-- Estimate our own contribution (power per server tick while vacuuming the storm)
	task.spawn(function()
		while true do
			task.wait(GameConfig.CatchTickRate)
			local character = player.Character
			local data = Registry.DataController.Data
			if data and character and character:GetAttribute("CatchTarget") == -1 and MegaStormController.IsActive() then
				contribution += Formulas.Power(data)
				if character:GetAttribute("PetTarget") == -1 then
					contribution += Formulas.PetCatchPower(data)
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			updateHud()
			task.wait(0.2)
		end
	end)

	RunService.RenderStepped:Connect(animateStorm)

	-- Keep the arena centre handy for other systems
	MegaStormController.Center = MapLayout.ArenaCenter
end

return MegaStormController
