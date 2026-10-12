--!nonstrict
-- Visual effects: weather cell animation + health bars, vacuum beams for every player,
-- pop bursts, floating reward text, confetti, lightning bolts and server effect events.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Weather = require(Shared.Config.Weather)
local GameConfig = require(Shared.Config.GameConfig)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)
local WeatherModels = require(Shared.Models.WeatherModels)

local Registry = require(script.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI.UI)

local EffectsController = {}

local TEXTURES = WeatherModels.Textures
local ANIMATE_RANGE = 200 -- cells further from the camera than this stay still
local STRIKE_FADE = 0.3 -- seconds a storm cloud's lightning flash takes to fade
local STRIKE_GAP = 0.35 -- at most ~3 storm-cloud flashes per second across the whole screen
local player = Players.LocalPlayer

local fxFolder: Folder
local cellFolder: Folder
local cells = {} -- [Model] = entry
local cellsById = {} -- [id] = Model
local beams = {} -- [Player] = { Target, Beams, Suction }
local nextCloudStrike = 0

local function lowGraphics(): boolean
	local settings = Registry.DataController.Get("Settings")
	return settings ~= nil and settings.LowGraphics == true
end

local function fxPart(position: Vector3, size: number?): Part
	local part = Instance.new("Part")
	part.Name = "FX"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * (size or 1)
	part.CFrame = CFrame.new(position)
	part.Parent = fxFolder
	return part
end

local function emitter(parent: Instance, props)
	local particles = Instance.new("ParticleEmitter")
	particles.Rate = 0
	for key, value in props do
		particles[key] = value
	end
	particles.Parent = parent
	return particles
end

---------------------------------------------------------------------------
-- Weather cells
---------------------------------------------------------------------------
local function updateLock(entry)
	local data = Registry.DataController.Data
	if not data then
		return
	end
	local zoneId = entry.Model:GetAttribute("Zone") or 1
	local zone = Zones[zoneId]
	if zoneId > data.Zone then
		entry.Lock.Text = "🔒 Locked zone"
		entry.Lock.Visible = true
	elseif Formulas.Power(data) < zone.MinPower then
		entry.Lock.Text = "💨 Need " .. Format.Number(zone.MinPower) .. " Power"
		entry.Lock.Visible = true
	else
		entry.Lock.Visible = false
	end
end

local function updateHealth(entry)
	local model = entry.Model
	local health = model:GetAttribute("Health") or 0
	local maxHealth = model:GetAttribute("MaxHealth") or 1
	local fraction = math.clamp(health / maxHealth, 0, 1)
	entry.Fill.Size = UDim2.fromScale(fraction, 1)
	entry.TargetScale = 0.45 + 0.55 * fraction
end

local function registerCell(model: Model)
	if cells[model] then
		return
	end
	local root = model:WaitForChild("Root", 5)
	local typeId = model:GetAttribute("Type")
	local def = typeId and Weather.Types[typeId]
	if not root or not def or not model.Parent then
		return
	end
	local rarity = Weather.Rarities[def.Rarity]

	local gui = Instance.new("BillboardGui")
	gui.Name = "CellInfo"
	gui.Adornee = root
	gui.Size = UDim2.fromOffset(180, 58)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 6.5 * rarity.Scale, 0)
	gui.MaxDistance = 75
	gui.LightInfluence = 0
	UI.Label({
		Name = "Title",
		Text = def.Name,
		TextColor3 = if def.Rarity == "Common" then Color3.new(1, 1, 1) else rarity.Color,
		Size = UDim2.new(1, 0, 0.42, 0),
		Stroke = 2.5,
		Parent = gui,
	})
	local bar = UI.Create("Frame", {
		Name = "Bar",
		BackgroundColor3 = Color3.fromRGB(20, 24, 50),
		Size = UDim2.new(1, -30, 0.26, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = gui,
		UI.Round(),
		UI.Stroke(2),
	})
	local fill = UI.Create("Frame", {
		Name = "Fill",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromScale(1, 1),
		Parent = bar,
		UI.Round(),
		UI.Gradient(Color3.fromRGB(120, 230, 255), Color3.fromRGB(50, 140, 255), 90),
	})
	local lock = UI.Label({
		Name = "Lock",
		Text = "",
		TextColor3 = Color3.fromRGB(255, 120, 130),
		Size = UDim2.new(1, 0, 0.3, 0),
		Position = UDim2.fromScale(0, 0.68),
		Visible = false,
		Parent = gui,
	})
	gui.Parent = root

	local bolts = {}
	for _, child in model:GetChildren() do
		if child.Name == "Bolt" and child:IsA("BasePart") then
			table.insert(bolts, child)
		end
	end

	local entry = {
		Model = model,
		Root = root,
		Style = def.Style,
		Origin = model:GetAttribute("Origin") or root.Position,
		Phase = math.random() * math.pi * 2,
		Scale = 1,
		AppliedScale = 1,
		TargetScale = 1,
		Fill = fill,
		Lock = lock,
		Flash = root:FindFirstChild("Flash"),
		Bolts = bolts,
		NextStrike = os.clock() + math.random() * 5,
		StrikeAt = -math.huge,
		Glow = -1, -- forces the first frame to set the resting flash/bolt look
	}
	cells[model] = entry
	local id = model:GetAttribute("CellId")
	if id then
		cellsById[id] = model
	end

	model:GetAttributeChangedSignal("Health"):Connect(function()
		updateHealth(entry)
	end)
	updateHealth(entry)
	updateLock(entry)
end

local function unregisterCell(model: Instance)
	local entry = cells[model]
	if not entry then
		return
	end
	cells[model] = nil
	local id = model:GetAttribute("CellId")
	if id and cellsById[id] == model then
		cellsById[id] = nil
	end
end

function EffectsController.GetCell(id: number): Model?
	return cellsById[id]
end

function EffectsController.Cells()
	return cells
end

local function animateCells(dt: number)
	local now = os.clock()
	local cameraFrame = Workspace.CurrentCamera.CFrame
	local cameraPosition, cameraLook = cameraFrame.Position, cameraFrame.LookVector
	local low = lowGraphics()
	for model, entry in cells do
		local origin = entry.Origin
		local offset = origin - cameraPosition
		-- Only cells near the camera and not behind it are animated
		if offset.Magnitude < ANIMATE_RANGE and offset:Dot(cameraLook) > -20 then
			if math.abs(entry.Scale - entry.TargetScale) > 0.002 then
				entry.Scale += (entry.TargetScale - entry.Scale) * math.min(1, dt * 6)
				if math.abs(entry.AppliedScale - entry.Scale) > 0.015 then
					entry.AppliedScale = entry.Scale
					model:ScaleTo(entry.Scale)
				end
			end

			-- Performance Mode keeps cells still (they still shrink as they're drained)
			if not low then
				local phase = entry.Phase
				local yaw, bob
				local style = entry.Style
				if style == "Tornado" then
					yaw, bob = now * 4 + phase, 0
				elseif style == "Orb" then
					yaw, bob = now * 1.2 + phase, math.sin(now * 1.6 + phase) * 0.7
				elseif style == "Starburst" then
					yaw, bob = now * 0.9 + phase, math.sin(now * 1.3 + phase) * 0.6
				else
					yaw, bob = phase + math.sin(now * 0.3 + phase) * 0.35, math.sin(now * 1.1 + phase) * 0.6
				end
				model:PivotTo(CFrame.new(origin + Vector3.new(0, bob, 0)) * CFrame.Angles(0, yaw, 0))
			end

			-- Storm clouds strike every few seconds: a bright flash that fades smoothly (no strobing)
			if entry.Flash then
				if not low and now >= entry.NextStrike and now >= nextCloudStrike then
					entry.StrikeAt = now
					entry.NextStrike = now + 3 + math.random() * 4
					nextCloudStrike = now + STRIKE_GAP
				end
				local glow = math.clamp(1 - (now - entry.StrikeAt) / STRIKE_FADE, 0, 1)
				if glow ~= entry.Glow then
					entry.Glow = glow
					entry.Flash.Brightness = 1.2 + 3.8 * glow * glow
					local transparency = 0.7 * (1 - glow)
					for _, bolt in entry.Bolts do
						bolt.Transparency = transparency
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Vacuum beams
---------------------------------------------------------------------------
local function targetInfo(targetId: number)
	if targetId == -1 then
		local folder = Workspace:FindFirstChild("MegaStorm")
		local storm = folder and folder:FindFirstChild("MegaStorm")
		local root = storm and storm:FindFirstChild("Root")
		return root and root:FindFirstChild("Target"), Color3.fromRGB(255, 120, 140), 14
	end
	local model = cellsById[targetId]
	local root = model and model:FindFirstChild("Root")
	local typeId = model and model:GetAttribute("Type")
	local def = typeId and Weather.Types[typeId]
	return root and root:FindFirstChild("Target"), def and def.Accent or Color3.new(1, 1, 1), 6
end

local function destroyBeam(owner: Player)
	local state = beams[owner]
	if not state then
		return
	end
	for _, beam in state.Beams do
		beam:Destroy()
	end
	if state.Suction then
		state.Suction:Destroy()
	end
	beams[owner] = nil
end

local function createBeam(owner: Player, nozzle: Attachment, targetId: number)
	local target, color, radius = targetInfo(targetId)
	if not target then
		return
	end

	local core = Instance.new("Beam")
	core.Name = "VacuumBeam"
	core.Attachment0 = nozzle
	core.Attachment1 = target
	core.Width0 = 0.6
	core.Width1 = if targetId == -1 then 10 else 4
	core.FaceCamera = true
	core.LightEmission = 1
	core.LightInfluence = 0
	core.Segments = 24
	core.Texture = TEXTURES.Sparkle
	core.TextureMode = Enum.TextureMode.Wrap
	core.TextureLength = 3
	core.TextureSpeed = -2.5
	core.Color = ColorSequence.new(Color3.fromRGB(170, 235, 255), color)
	core.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.8, 0.3),
		NumberSequenceKeypoint.new(1, 0.85),
	})
	core.Parent = nozzle.Parent

	local swirl = core:Clone()
	swirl.Name = "VacuumSwirl"
	swirl.Width0 = 1.4
	swirl.Width1 = core.Width1 * 1.6
	swirl.Texture = TEXTURES.Smoke
	swirl.TextureLength = 5
	swirl.TextureSpeed = -1.6
	swirl.Transparency = NumberSequence.new(0.45, 0.95)
	swirl.Parent = nozzle.Parent

	local suction = nil
	if not lowGraphics() then
		suction = fxPart(target.WorldPosition, radius * 2)
		suction.Name = "Suction"
		emitter(suction, {
			Texture = TEXTURES.Sparkle,
			Color = ColorSequence.new(color),
			Size = NumberSequence.new(0.6, 0),
			Lifetime = NumberRange.new(0.5, 0.7),
			Rate = 28,
			Speed = NumberRange.new(radius * 1.2, radius * 1.6),
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
			LightEmission = 1,
		})
	end

	beams[owner] = { Target = targetId, Beams = { core, swirl }, Suction = suction, TargetAttachment = target, Nozzle = nozzle }
end

local function updateBeams()
	local now = os.clock()
	for _, owner in Players:GetPlayers() do
		local character = owner.Character
		local targetId = character and character:GetAttribute("CatchTarget") or 0
		local tool = character and character:FindFirstChild("StormVacuum")
		local handle = tool and tool:FindFirstChild("Handle")
		local nozzle = handle and handle:FindFirstChild("NozzleAttachment")
		local state = beams[owner]

		if targetId == 0 or not nozzle then
			if state then
				destroyBeam(owner)
			end
		else
			if state and (state.Target ~= targetId or state.Nozzle ~= nozzle or not state.TargetAttachment.Parent) then
				destroyBeam(owner)
				state = nil
			end
			if not state then
				createBeam(owner, nozzle, targetId)
				state = beams[owner]
			end
			if state then
				for index, beam in state.Beams do
					beam.CurveSize0 = math.sin(now * 7 + index) * 1.2
					beam.CurveSize1 = math.cos(now * 5 + index * 2) * 2
				end
				if state.Suction then
					state.Suction.CFrame = CFrame.new(state.TargetAttachment.WorldPosition)
				end
			end
		end
	end

	local ownCharacter = player.Character
	local ownTarget = ownCharacter and ownCharacter:GetAttribute("CatchTarget") or 0
	Registry.SoundController.SetVacuum(ownTarget ~= 0)
end

---------------------------------------------------------------------------
-- One-shot effects
---------------------------------------------------------------------------
function EffectsController.Burst(position: Vector3, color: Color3, big: boolean?)
	local scale = if big then 1.8 else 1
	local part = fxPart(position)
	local amount = if lowGraphics() then 0.4 else 1
	local sparkles = emitter(part, {
		Texture = TEXTURES.Sparkle,
		Color = ColorSequence.new(color, Color3.new(1, 1, 1)),
		Size = NumberSequence.new(1.3 * scale, 0),
		Lifetime = NumberRange.new(0.5, 1),
		Speed = NumberRange.new(18 * scale, 30 * scale),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 3,
		LightEmission = 1,
	})
	sparkles:Emit(math.floor(34 * scale * amount))
	local smoke = emitter(part, {
		Texture = TEXTURES.Smoke,
		Color = ColorSequence.new(color),
		Size = NumberSequence.new(3 * scale, 8 * scale),
		Transparency = NumberSequence.new(0.4, 1),
		Lifetime = NumberRange.new(0.8, 1.2),
		Speed = NumberRange.new(6, 12),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 2,
	})
	smoke:Emit(math.floor(12 * amount))

	local ring = fxPart(position, 2)
	ring.Shape = Enum.PartType.Ball
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.25
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {
		Size = Vector3.one * 18 * scale,
		Transparency = 1,
	}):Play()

	Debris:AddItem(part, 2.5)
	Debris:AddItem(ring, 0.6)
end

function EffectsController.FloatText(position: Vector3, text: string, color: Color3?, size: number?)
	local anchor = fxPart(position)
	local gui = Instance.new("BillboardGui")
	gui.Adornee = anchor
	gui.Size = UDim2.fromOffset(260 * (size or 1), 54 * (size or 1))
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	local label = UI.Label({
		Text = text,
		TextColor3 = color or Color3.fromRGB(255, 220, 80),
		Stroke = 3,
		Parent = gui,
	})
	gui.Parent = anchor
	UI.Pop(label, 1.5)
	TweenService:Create(gui, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { StudsOffsetWorldSpace = Vector3.new(0, 5, 0) }):Play()
	task.delay(0.75, function()
		UI.Tween(label, 0.4, { TextTransparency = 1 })
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			UI.Tween(stroke, 0.4, { Transparency = 1 })
		end
	end)
	Debris:AddItem(anchor, 1.4)
end

function EffectsController.Confetti(amount: number?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local part = fxPart(root.Position + Vector3.new(0, 4, 0))
	local particles = emitter(part, {
		Texture = TEXTURES.Square,
		Color = WeatherModels.RainbowSequence,
		Size = NumberSequence.new(0.35),
		Lifetime = NumberRange.new(1.5, 2.5),
		Speed = NumberRange.new(22, 34),
		SpreadAngle = Vector2.new(55, 55),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -32, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-300, 300),
		Drag = 0.6,
		LightEmission = 0.4,
	})
	particles:Emit(math.floor((amount or 60) * (if lowGraphics() then 0.4 else 1)))
	Debris:AddItem(part, 3)
end

function EffectsController.LightningBolt(from: Vector3, to: Vector3, color: Color3?, width: number?)
	local segments = 8
	local points = {}
	for index = 0, segments do
		local point = from:Lerp(to, index / segments)
		if index > 0 and index < segments then
			point += Vector3.new(math.random(-30, 30) / 10, math.random(-10, 10) / 10, math.random(-30, 30) / 10)
		end
		points[index] = point
	end
	for index = 1, segments do
		local a, b = points[index - 1], points[index]
		local segment = fxPart((a + b) / 2)
		segment.Size = Vector3.new(width or 0.6, width or 0.6, (b - a).Magnitude + 0.3)
		segment.CFrame = CFrame.lookAt((a + b) / 2, b)
		segment.Material = Enum.Material.Neon
		segment.Color = color or Color3.fromRGB(255, 240, 150)
		segment.Transparency = 0
		TweenService:Create(segment, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		Debris:AddItem(segment, 0.35)
	end
end

---------------------------------------------------------------------------
-- Server effects
---------------------------------------------------------------------------
local handlers = {}

function handlers.CellPop(position: Vector3, color: Color3, rarity: string)
	local camera = Workspace.CurrentCamera
	if (camera.CFrame.Position - position).Magnitude > 260 then
		return
	end
	EffectsController.Burst(position, color, rarity == "Rare")
	Registry.SoundController.PlayAt("Pop", position, 0.9 + math.random() * 0.25)
end

function handlers.CellCaught(position: Vector3, typeId: string, value: number)
	local data = Registry.DataController.Data
	local volts = value * (if data then Formulas.VoltsMultiplier(data) else 1)
	EffectsController.FloatText(position + Vector3.new(0, 3, 0), "+⚡ " .. Format.Number(volts))
end

-- Remote Sell's automatic sells can happen several times a second (pets + vacuum), so they
-- are added up and shown as one payout per second instead of a pile of animations
local autoSellTotal = 0
local autoSellPending = false

function handlers.Sell(volts: number, source: string)
	if source == "Rebirth" then
		return -- the tank is cashed in right before a Climate Shift resets Volts; no payout to show
	end
	if source == "Auto" then
		autoSellTotal += volts
		if not autoSellPending then
			autoSellPending = true
			task.delay(1, function()
				local total = autoSellTotal
				autoSellTotal = 0
				autoSellPending = false
				Registry.HudController.PlaySell(total)
				Registry.SoundController.Play("Sell", 1.1)
			end)
		end
		return
	end
	Registry.HudController.PlaySell(volts)
	Registry.SoundController.Play("Sell", 1)
end

function handlers.Upgrade(upgradeId: string, level: number)
	local def = GameConfig.Upgrades[upgradeId]
	Registry.SoundController.Play("Success")
	EffectsController.Confetti(30)
	if def then
		Registry.InterfaceController.Notify(string.format("%s %s upgraded to level %d!", def.Icon, def.Name, level), "Success")
	end
end

function handlers.ZoneUnlocked(zoneId: number)
	local zone = Zones[zoneId]
	Registry.SoundController.Play("Success", 0.9)
	EffectsController.Confetti(90)
	Registry.InterfaceController.BigText("ZONE UNLOCKED!", zone.Color, zone.Icon .. " " .. zone.Name, 2.8)
end

-- Climate Shift. `look` is the gear look this shift unlocked (GameConfig.Rebirth.Cosmetics entry)
function handlers.Rebirth(rebirths: number, look)
	Registry.SoundController.Play("Success", 0.8)
	EffectsController.Confetti(120)
	local subtitle = "Permanent Volts bonus: " .. Format.Multiplier(Formulas.RebirthMultiplier(rebirths))
	if type(look) == "table" and look.Name then
		subtitle ..= "  •  🎨 " .. tostring(look.Icon or "") .. " " .. look.Name .. " look unlocked!"
		Registry.InterfaceController.Notify("🎨 Your tank and vacuum now wear the " .. look.Name .. " look!", "Reward")
	end
	Registry.InterfaceController.BigText("🌀 CLIMATE SHIFT " .. rebirths .. "!", Color3.fromRGB(200, 150, 255), subtitle, 3)
end

function handlers.RareSpawn(typeId: string, position: Vector3)
	local def = Weather.Types[typeId]
	if def then
		Registry.InterfaceController.Notify("✨ A rare " .. def.Name .. " appeared nearby!", "Reward")
		EffectsController.LightningBolt(position + Vector3.new(0, 60, 0), position, Weather.Rarities.Rare.Color, 0.8)
	end
end

function handlers.Purchase(name: string)
	Registry.SoundController.Play("Success")
	EffectsController.Confetti(80)
end

function handlers.PetReveal(petId: string, golden: boolean)
	Registry.HatchOverlay.Reveal(petId, golden)
end

function EffectsController.Init()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "ClientFX"
	fxFolder.Parent = Workspace

	Remotes.Effect.OnClientEvent:Connect(function(name, ...)
		local handler = handlers[name]
		if handler then
			handler(...)
		elseif string.sub(name, 1, 4) == "Mega" then
			Registry.MegaStormController.HandleEffect(name, ...)
		end
	end)
end

function EffectsController.Start()
	cellFolder = Workspace:WaitForChild("WeatherCells")
	for _, model in cellFolder:GetChildren() do
		task.spawn(registerCell, model)
	end
	cellFolder.ChildAdded:Connect(function(model)
		registerCell(model)
	end)
	cellFolder.ChildRemoved:Connect(unregisterCell)

	Registry.DataController.ObserveMany({ "Upgrades", "Zone" }, function()
		for _, entry in cells do
			updateLock(entry)
		end
	end)

	Players.PlayerRemoving:Connect(destroyBeam)

	RunService.RenderStepped:Connect(function(dt)
		animateCells(dt)
		updateBeams()
	end)
end

return EffectsController
