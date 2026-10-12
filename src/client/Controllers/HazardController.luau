--!nonstrict
-- Client side of the biome hazards (rules in Shared/Hazards, tuning in Config/Zones):
-- lightning warning circles, strikes, dizzy stars and camera shake in Thunder Valley, sandstorm
-- haze and blowing sand in the Dune Sea, frost and heat vignettes with hints, low gravity in the
-- Upper Atmosphere, and the hazard line shown under the zone banner.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Hazards = require(Shared.Hazards)
local Remotes = require(Shared.Remotes)
local WeatherModels = require(Shared.Models.WeatherModels)

local Registry = require(script.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI.UI)

local HazardController = {}

local TEXTURES = WeatherModels.Textures
local UPDATE_INTERVAL = 0.15
local SHAKE_BINDING = "HazardStunShake"
local WARNING_COLOR = Color3.fromRGB(255, 225, 70)
local WARNING_FILL = Color3.fromRGB(255, 120, 50)
local BOLT_COLOR = Color3.fromRGB(235, 238, 255)

local player = Players.LocalPlayer
local fxFolder: Folder
local overlay: ScreenGui
local vignettes = {} -- [name] = { Edges, Max, Pulse, Level, Target, Applied }
local flash: ColorCorrectionEffect? = nil
local sandPart: Part
local sandPuffs: ParticleEmitter
local sandGrit: ParticleEmitter
local hazardState: Instance? = nil
local originalGravity = 196.2
local currentZone = 0
local sandActive = false
local shaking = false
local stars = {} -- [Model] = { Gui, Labels }
local banner: Frame? = nil
local accumulator = 0

local function lowGraphics(): boolean
	local settings = Registry.DataController.Get("Settings")
	return settings ~= nil and settings.LowGraphics == true
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

-- Flat neon disc lying on the ground
local function disc(position: Vector3, diameter: number, color: Color3, transparency: number): Part
	local part = Instance.new("Part")
	part.Name = "HazardFX"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	part.Size = Vector3.new(0.2, diameter, diameter)
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	part.Parent = fxFolder
	return part
end

local function emitter(parent: Instance, props)
	local particles = Instance.new("ParticleEmitter")
	for key, value in props do
		particles[key] = value
	end
	particles.Enabled = false
	particles.Parent = parent
	return particles
end

---------------------------------------------------------------------------
-- Screen effects
---------------------------------------------------------------------------
local EDGES = {
	{ Size = UDim2.fromScale(1, 0.32), Position = UDim2.fromScale(0, 0), Rotation = 90 },
	{ Size = UDim2.fromScale(1, 0.32), Position = UDim2.fromScale(0, 0.68), Rotation = -90 },
	{ Size = UDim2.fromScale(0.24, 1), Position = UDim2.fromScale(0, 0), Rotation = 0 },
	{ Size = UDim2.fromScale(0.24, 1), Position = UDim2.fromScale(0.76, 0), Rotation = 180 },
}
local EDGE_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.45, 0.65),
	NumberSequenceKeypoint.new(1, 1),
})

-- Colored glow creeping in from the screen edges
local function buildVignette(name: string, color: Color3, strength: number, pulse: boolean)
	local edges = {}
	for _, edge in EDGES do
		local frame = UI.Create("Frame", {
			Name = name,
			BackgroundColor3 = color,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = edge.Size,
			Position = edge.Position,
			Visible = false,
			Parent = overlay,
		})
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = edge.Rotation
		gradient.Transparency = EDGE_FADE
		gradient.Parent = frame
		table.insert(edges, frame)
	end
	vignettes[name] = { Edges = edges, Max = strength, Pulse = pulse, Level = 0, Target = 0, Applied = 1 }
end

local function updateVignettes(dt: number)
	local now = os.clock()
	for _, vignette in vignettes do
		local level = vignette.Level + (vignette.Target - vignette.Level) * math.min(1, dt * 3)
		if math.abs(vignette.Target - level) < 0.01 then
			level = vignette.Target
		end
		vignette.Level = level
		local opacity = level * vignette.Max
		if vignette.Pulse and opacity > 0 then
			opacity *= 0.75 + 0.25 * math.sin(now * 5)
		end
		local transparency = 1 - opacity
		if math.abs(transparency - vignette.Applied) > 0.002 then
			vignette.Applied = transparency
			for _, edge in vignette.Edges do
				edge.BackgroundTransparency = transparency
				edge.Visible = transparency < 0.999
			end
		end
	end
end

local function flashScreen(brightness: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local effect = flash
	if not effect or effect.Parent ~= camera then
		if effect then
			effect:Destroy()
		end
		-- Lives under the camera so ZoneController's Lighting effects are left alone
		effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "LightningFlash"
		effect.Parent = camera
		flash = effect
	end
	effect.Brightness = brightness
	TweenService:Create(effect, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()
end

-- Runs right after the camera scripts, so the offset never builds up
local function shakeCamera()
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CFrame += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 0.3
	end
end

local function setShaking(enabled: boolean)
	if enabled == shaking then
		return
	end
	shaking = enabled
	if enabled then
		RunService:BindToRenderStep(SHAKE_BINDING, Enum.RenderPriority.Camera.Value + 1, shakeCamera)
	else
		RunService:UnbindFromRenderStep(SHAKE_BINDING)
	end
end

---------------------------------------------------------------------------
-- Lightning (Thunder Valley)
---------------------------------------------------------------------------
local function onLightningWarning(position, radius, warnTime)
	if typeof(position) ~= "Vector3" or type(radius) ~= "number" or type(warnTime) ~= "number" then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera or (camera.CFrame.Position - position).Magnitude > 350 then
		return
	end
	radius = math.clamp(radius, 1, 40)
	warnTime = math.clamp(warnTime, 0.1, 5)

	local ground = position + Vector3.new(0, 0.12, 0)
	local ring = disc(ground, radius * 2, WARNING_COLOR, 0.6)
	local fill = disc(ground + Vector3.new(0, 0.03, 0), 0.5, WARNING_FILL, 0.35)
	TweenService:Create(fill, TweenInfo.new(warnTime, Enum.EasingStyle.Linear), { Size = Vector3.new(0.2, radius * 2, radius * 2) }):Play()
	TweenService:Create(ring, TweenInfo.new(0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.15 }):Play()
	Debris:AddItem(ring, warnTime + 0.1)
	Debris:AddItem(fill, warnTime + 0.1)

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and flatDistance(root.Position, position) <= radius + 2 then
		Registry.InterfaceController.Hint("⚠️ Lightning incoming! Get out of the circle!", "LightningWarning", 1)
	end
end

local function onLightningStrike(position, radius)
	if typeof(position) ~= "Vector3" or type(radius) ~= "number" then
		return
	end
	local camera = Workspace.CurrentCamera
	local distance = if camera then (camera.CFrame.Position - position).Magnitude else 0
	if distance > 450 then
		return
	end
	radius = math.clamp(radius, 1, 40)

	local effects = Registry.EffectsController
	local top = position + Vector3.new(math.random(-12, 12), 150, math.random(-12, 12))
	effects.LightningBolt(top, position, BOLT_COLOR, 1.8)
	effects.LightningBolt(top + Vector3.new(math.random(-8, 8), -30, math.random(-8, 8)), position, WARNING_COLOR, 0.7)

	local shock = disc(position + Vector3.new(0, 0.2, 0), radius * 0.5, BOLT_COLOR, 0.15)
	TweenService:Create(shock, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {
		Size = Vector3.new(0.2, radius * 2.6, radius * 2.6),
		Transparency = 1,
	}):Play()
	Debris:AddItem(shock, 0.5)
	if not lowGraphics() then
		effects.Burst(position + Vector3.new(0, 1.5, 0), WARNING_COLOR, true)
	end
	if distance < 220 then
		flashScreen(if distance < 90 then 0.45 else 0.2)
	end
	Registry.SoundController.PlayAt("Thunder", position, 0.9 + math.random() * 0.25)
end

local function buildStars(head: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "DizzyStars"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(110, 56)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	local labels = {}
	for index, glyph in { "💫", "⭐", "💫" } do
		table.insert(labels, UI.Label({
			Name = "Star" .. index,
			Text = glyph,
			Stroke = false,
			Size = UDim2.fromOffset(28, 28),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = gui,
		}))
	end
	gui.Parent = fxFolder
	return { Gui = gui, Labels = labels }
end

-- Dizzy stars circling the head of everyone stunned by lightning
local function updateStars()
	local now = os.clock()
	local stunned = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local head = character and character:GetAttribute("Stunned") and character:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			stunned[character] = true
			if not stars[character] then
				stars[character] = buildStars(head)
			end
		end
	end
	for character, entry in stars do
		if not stunned[character] then
			entry.Gui:Destroy()
			stars[character] = nil
		else
			for index, label in entry.Labels do
				local angle = now * 5 + index * math.pi * 2 / #entry.Labels
				label.Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.36, 0.5 + math.sin(angle) * 0.22)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Sandstorms (Dune Sea)
---------------------------------------------------------------------------
local function sandstormActive(zoneId: number): boolean
	return hazardState ~= nil and hazardState:GetAttribute(Hazards.SandstormAttribute(zoneId)) == true
end

-- ZoneController.LightingFilter: thick dusty haze while a sandstorm rages
local function filterLighting(zoneId: number, preset)
	local hazard = Hazards.Get(zoneId)
	if not hazard or hazard.Kind ~= "Sandstorm" or not sandstormActive(zoneId) then
		return preset
	end
	local stormy = table.clone(preset)
	stormy.Atmosphere = hazard.Atmosphere
	stormy.ColorCorrection = hazard.ColorCorrection or preset.ColorCorrection
	return stormy
end

local function onSandstormChanged(zoneId: number, hazard)
	if Registry.ZoneController.Current == zoneId then
		Registry.ZoneController.RefreshLighting()
	end
	if currentZone ~= zoneId then
		return
	end
	if sandstormActive(zoneId) then
		Registry.InterfaceController.BigText(hazard.Icon .. " SANDSTORM!", hazard.Color, "Visibility drops! Stay close to your weather.", 2.4)
	else
		Registry.InterfaceController.Hint("☀️ The sandstorm is passing. Skies are clearing!", "SandstormEnd", 3)
	end
end

---------------------------------------------------------------------------
-- Zone banner
---------------------------------------------------------------------------
-- Hazard line under the big zone title (called by ZoneController when entering a zone)
function HazardController.ShowZoneHazard(zoneId: number)
	if banner then
		banner:Destroy()
		banner = nil
	end
	local hazard = Hazards.Get(zoneId)
	if not hazard then
		return
	end
	local frame = UI.Create("Frame", {
		Name = "HazardBanner",
		BackgroundColor3 = Color3.fromRGB(20, 26, 58),
		BackgroundTransparency = 0.12,
		Size = UDim2.fromOffset(640, 46),
		Position = UDim2.new(0.5, 0, 0.3, 98),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = Registry.InterfaceController.OverlayRoot,
		UI.Round(),
		UI.Stroke(3, hazard.Color),
	})
	UI.Label({
		Name = "Text",
		Text = Hazards.Describe(hazard, Registry.DataController.Data),
		Size = UDim2.new(1, -32, 0.64, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 24,
		Parent = frame,
	})
	UI.Pop(frame, 0.6)
	banner = frame

	task.delay(3.4, function()
		if banner ~= frame then
			return -- replaced (and destroyed) by a newer banner
		end
		banner = nil
		UI.Tween(frame, 0.3, { BackgroundTransparency = 1 })
		for _, item in frame:GetDescendants() do
			if item:IsA("UIStroke") then
				UI.Tween(item, 0.3, { Transparency = 1 })
			elseif item:IsA("TextLabel") then
				UI.Tween(item, 0.3, { TextTransparency = 1 })
			end
		end
		task.wait(0.32)
		frame:Destroy()
	end)
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------
local function applyGravity(hazard)
	local gravity = if hazard and hazard.Kind == "LowGravity" then hazard.Gravity else originalGravity
	if Workspace.Gravity ~= gravity then
		Workspace.Gravity = gravity
	end
end

local function updateHazards()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local alive = humanoid ~= nil and root ~= nil and humanoid.Health > 0
	local zoneId = if alive then Hazards.ZoneAt(root.Position) else 0
	local hazard = Hazards.Get(zoneId)
	if zoneId ~= currentZone then
		currentZone = zoneId
		applyGravity(hazard)
	end

	local kind = hazard and hazard.Kind
	local data = Registry.DataController.Data
	local interface = Registry.InterfaceController

	-- The server applies the slowdown/damage; these only show what's going on
	local cold = kind == "Cold" and data ~= nil and not Hazards.ResistsCold(data, hazard)
	local hot = kind == "Heat" and not Hazards.IsCool(zoneId, root.Position, hazard.SafeRadius)
	vignettes.Frost.Target = if cold then 1 else 0
	vignettes.Heat.Target = if hot then 1 else 0
	if cold then
		interface.Hint(string.format("🥶 Brrr! Upgrade Storm Boots to Lv %d to resist the cold", hazard.BootsLevel), "HazardCold", 7)
	elseif hot then
		interface.Hint("🔥 Too hot! Cool off near a Weather Lab", "HazardHeat", 6)
	end

	local stunned = alive and character:GetAttribute("Stunned") == true
	if stunned and not shaking then
		interface.Hint("💫 Zapped! You're stunned for a moment...", "Stunned", 2)
	end
	setShaking(stunned)

	sandActive = kind == "Sandstorm" and sandstormActive(zoneId)
	local low = lowGraphics()
	sandPuffs.Rate = if low then 12 else 45
	sandPuffs.Enabled = sandActive
	sandGrit.Enabled = sandActive and not low
end

---------------------------------------------------------------------------
function HazardController.Init()
	originalGravity = Workspace.Gravity

	fxFolder = Instance.new("Folder")
	fxFolder.Name = "HazardFX"
	fxFolder.Parent = Workspace

	overlay = Instance.new("ScreenGui")
	overlay.Name = "HazardOverlay"
	overlay.ResetOnSpawn = false
	overlay.IgnoreGuiInset = true
	overlay.ScreenInsets = Enum.ScreenInsets.None
	overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	overlay.DisplayOrder = 0 -- below the HUD
	overlay.Parent = player:WaitForChild("PlayerGui")
	buildVignette("Frost", Color3.fromRGB(196, 232, 255), 0.75, false)
	buildVignette("Heat", Color3.fromRGB(255, 90, 30), 0.6, true)

	sandPart = Instance.new("Part")
	sandPart.Name = "SandstormFX"
	sandPart.Anchored = true
	sandPart.CanCollide = false
	sandPart.CanQuery = false
	sandPart.CanTouch = false
	sandPart.Transparency = 1
	sandPart.Size = Vector3.new(90, 26, 90)
	sandPart.Parent = fxFolder
	sandPuffs = emitter(sandPart, {
		Texture = TEXTURES.Smoke,
		Color = ColorSequence.new(Color3.fromRGB(232, 196, 132), Color3.fromRGB(200, 150, 90)),
		Size = NumberSequence.new(7, 15),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(2.5, 3.5),
		Rate = 45,
		Speed = NumberRange.new(30, 45),
		EmissionDirection = Enum.NormalId.Right,
		Acceleration = Vector3.new(6, -2, 3),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-40, 40),
	})
	sandGrit = emitter(sandPart, {
		Texture = TEXTURES.Square,
		Color = ColorSequence.new(Color3.fromRGB(245, 215, 160)),
		Size = NumberSequence.new(0.12),
		Transparency = NumberSequence.new(0.3, 1),
		Lifetime = NumberRange.new(1, 1.6),
		Rate = 160,
		Speed = NumberRange.new(55, 75),
		EmissionDirection = Enum.NormalId.Right,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = NumberSequence.new(2.5),
		Acceleration = Vector3.new(0, -4, 0),
	})

	Registry.ZoneController.LightingFilter = filterLighting

	Remotes.Effect.OnClientEvent:Connect(function(name, ...)
		if name == "LightningWarning" then
			onLightningWarning(...)
		elseif name == "LightningStrike" then
			onLightningStrike(...)
		end
	end)
end

function HazardController.Start()
	task.spawn(function()
		local state = ReplicatedStorage:WaitForChild(Hazards.StateName, 60)
		if not state then
			return
		end
		hazardState = state
		for zoneId, zone in ipairs(Zones) do
			local hazard = zone.Hazard
			if hazard and hazard.Kind == "Sandstorm" then
				state:GetAttributeChangedSignal(Hazards.SandstormAttribute(zoneId)):Connect(function()
					onSandstormChanged(zoneId, hazard)
				end)
				if Registry.ZoneController.Current == zoneId then
					Registry.ZoneController.RefreshLighting()
				end
			end
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		updateVignettes(dt)
		updateStars()
		if sandActive then
			local camera = Workspace.CurrentCamera
			if camera then
				-- Upwind of the camera so the dust streams past it
				sandPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(-30, 4, 0))
			end
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= UPDATE_INTERVAL then
			accumulator = 0
			updateHazards()
		end
	end)
end

return HazardController
