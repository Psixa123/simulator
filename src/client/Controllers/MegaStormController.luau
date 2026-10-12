--!nonstrict
-- Client side of the Mega Storm event: HUD widget/banner, storm animation, lightning,
-- camera shake, announcements and reward popups.

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
local Format = require(Shared.Util.Format)

local Registry = require(script.Parent.Parent.Registry)

local MegaStormController = {}

local player = Players.LocalPlayer
local state: Configuration
local contribution = 0
local storm = nil -- { Model, Pivot, Spin = {}, Debris = {}, Collapsing }
local lightningTimer = 0

local function stormType()
	return GameConfig.MegaStorm.Types[state:GetAttribute("StormIndex") or 1] or GameConfig.MegaStorm.Types[1]
end

function MegaStormController.IsActive(): boolean
	return state ~= nil and state:GetAttribute("Phase") == "Active"
end

local function updateHud()
	local phase = state:GetAttribute("Phase") or "Idle"
	local now = Registry.DataController.Now()
	local info = { Phase = phase, Name = stormType().Name }
	if phase == "Active" then
		local remaining = (state:GetAttribute("EndTime") or now) - now
		info.Timer = Format.Time(remaining)
		info.Health = state:GetAttribute("Health") or 0
		info.MaxHealth = state:GetAttribute("MaxHealth") or 1
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
	local entry = { Model = model, Pivot = pivot, Spin = {}, Debris = {}, Collapsing = false, Fade = 0 }
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

local function animateStorm(dt: number)
	if not storm then
		return
	end
	if not storm.Model.Parent then
		storm = nil
		return
	end
	local now = os.clock()
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

	if MegaStormController.IsActive() then
		lightningTimer -= dt
		if lightningTimer <= 0 then
			lightningTimer = 0.5 + math.random() * 0.9
			local angle = math.random() * math.pi * 2
			local radius = math.random(10, 40)
			local top = storm.Pivot.Position + Vector3.new(math.cos(angle) * radius, math.random(40, 80), math.sin(angle) * radius)
			local bottom = storm.Pivot.Position + Vector3.new(math.cos(angle) * (radius + 12), 0, math.sin(angle) * (radius + 12))
			Registry.EffectsController.LightningBolt(top, bottom, stormType().Accent, 1.2)
		end
	end

	-- Camera shake when close to the storm
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root then
		local distance = (root.Position - storm.Pivot.Position).Magnitude
		if MegaStormController.IsActive() and distance < 110 then
			local strength = (1 - distance / 110) * 0.35
			humanoid.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * strength
		else
			humanoid.CameraOffset = Vector3.zero
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
		local subtitle = stormType().Name .. "  •  Head to the arena in the Storm Station!"
		if summoner and summoner ~= "" then
			subtitle = "Summoned by " .. summoner .. "!"
		end
		Registry.SoundController.Play("Alarm")
		Registry.InterfaceController.BigText("⚠️ MEGA STORM INCOMING!", Color3.fromRGB(255, 150, 60), subtitle, 3.2)
	elseif name == "MegaStart" then
		contribution = 0
		Registry.SoundController.Play("Alarm", 0.85)
		Registry.InterfaceController.BigText("🌪️ " .. string.upper(stormType().Name) .. "!", stormType().Color, "Vacuum it together before it escapes!", 3)
	elseif name == "MegaEnd" then
		local defeated = args[1]
		collapse()
		if defeated then
			Registry.SoundController.Play("Success", 0.8)
			Registry.InterfaceController.BigText("STORM DEFEATED!", Color3.fromRGB(110, 230, 140), "Rewards sent to every storm catcher who helped!", 3)
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
