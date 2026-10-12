--!nonstrict
-- World interactions and ambient animation: proximity prompts that open panels/eggs,
-- spinning and bobbing props, pulsing neon, flickering lights and the forecast boards.

local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Format = require(Shared.Util.Format)

local Registry = require(script.Parent.Parent.Registry)

local WorldController = {}

local spinners = {} -- [Instance] = { Base, Speed, Axis, Bob, Phase }
local bobbers = {} -- [Instance] = { Base, Height, Speed, Phase }
local pulsers = {} -- [BasePart] = { Base }
local flickers = {} -- [BasePart] = true

local function pivotOf(instance: Instance): CFrame
	if instance:IsA("Model") then
		return instance:GetPivot()
	end
	return (instance :: BasePart).CFrame
end

local function setPivot(instance: Instance, cframe: CFrame)
	if instance:IsA("Model") then
		instance:PivotTo(cframe)
	else
		(instance :: BasePart).CFrame = cframe
	end
end

local function addSpinner(instance: Instance)
	spinners[instance] = {
		Base = pivotOf(instance),
		Speed = instance:GetAttribute("SpinSpeed") or 1,
		Axis = instance:GetAttribute("SpinAxis") or "Y",
		Bob = instance:GetAttribute("BobHeight") or 0,
		Phase = math.random() * 10,
	}
end

local function addBobber(instance: Instance)
	bobbers[instance] = {
		Base = pivotOf(instance),
		Height = instance:GetAttribute("BobHeight") or 2,
		Speed = instance:GetAttribute("BobSpeed") or 0.6,
		Phase = math.random() * 10,
	}
end

local function addPulser(instance: Instance)
	if instance:IsA("BasePart") then
		pulsers[instance] = { Base = instance.Transparency, Phase = math.random() * 10 }
	end
end

local function track(tag: string, add: (Instance) -> (), store)
	for _, instance in CollectionService:GetTagged(tag) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
		store[instance] = nil
	end)
end

local function animate()
	local now = os.clock()
	local cameraPosition = Workspace.CurrentCamera.CFrame.Position
	for instance, state in spinners do
		local base = state.Base
		if (base.Position - cameraPosition).Magnitude < 400 then
			local angle = now * state.Speed + state.Phase
			local rotation = if state.Axis == "Z"
				then CFrame.Angles(0, 0, angle)
				elseif state.Axis == "X" then CFrame.Angles(angle, 0, 0)
				else CFrame.Angles(0, angle, 0)
			local bob = if state.Bob > 0 then Vector3.new(0, math.sin(now * 1.5 + state.Phase) * state.Bob, 0) else Vector3.zero
			setPivot(instance, (base + bob) * rotation)
		end
	end
	for instance, state in bobbers do
		local offset = math.sin(now * state.Speed + state.Phase) * state.Height
		setPivot(instance, state.Base + Vector3.new(0, offset, 0))
	end
	for part, state in pulsers do
		part.Transparency = math.clamp(state.Base + (math.sin(now * 3 + state.Phase) + 1) * 0.12, 0, 1)
	end
	for part in flickers do
		if math.random() < 0.04 then
			part.Transparency = if part.Transparency > 0 then 0 else 0.6
		end
	end
end

---------------------------------------------------------------------------
-- Forecast board + arena sign
---------------------------------------------------------------------------
local function updateBoards()
	local state = ReplicatedStorage:FindFirstChild("MegaStormState")
	if not state then
		return
	end
	local phase = state:GetAttribute("Phase") or "Idle"
	local now = Registry.DataController.Now()
	local stormType = GameConfig.MegaStorm.Types[state:GetAttribute("StormIndex") or 1]

	local countdown, label, color
	if phase == "Active" then
		countdown = Format.Time((state:GetAttribute("EndTime") or now) - now)
		label = "MEGA STORM ACTIVE!"
		color = Color3.fromRGB(255, 100, 120)
	elseif phase == "Warning" then
		countdown = Format.Time((state:GetAttribute("NextTime") or now) - now)
		label = "⚠️ INCOMING!"
		color = Color3.fromRGB(255, 160, 60)
	else
		countdown = Format.Time((state:GetAttribute("NextTime") or now) - now)
		label = "NEXT MEGA STORM"
		color = Color3.fromRGB(255, 214, 64)
	end

	for _, gui in CollectionService:GetTagged("ForecastGui") do
		local countdownLabel = gui:FindFirstChild("Countdown")
		local labelLabel = gui:FindFirstChild("Label")
		local nameLabel = gui:FindFirstChild("StormName")
		if countdownLabel then
			countdownLabel.Text = countdown
			countdownLabel.TextColor3 = color
		end
		if labelLabel then
			labelLabel.Text = label
		end
		if nameLabel and stormType then
			nameLabel.Text = "🌪️ " .. stormType.Name
		end
	end

	for _, gui in CollectionService:GetTagged("ArenaGui") do
		local countdownLabel = gui:FindFirstChild("Countdown")
		if countdownLabel then
			countdownLabel.Text = if phase == "Active"
				then "🌪️ " .. stormType.Name .. " • " .. countdown
				elseif phase == "Warning" then "⚠️ Storm arrives in " .. countdown
				else "Next storm in " .. countdown
			countdownLabel.TextColor3 = color
		end
	end

	local pylonColor = if phase == "Active"
		then Color3.fromRGB(255, 80, 100)
		elseif phase == "Warning" then (if math.floor(os.clock() * 4) % 2 == 0 then Color3.fromRGB(255, 160, 60) else Color3.fromRGB(255, 80, 100))
		else Color3.fromRGB(120, 200, 255)
	for _, pylon in CollectionService:GetTagged("ArenaPylon") do
		pylon.Color = pylonColor
	end
end

function WorldController.Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local eggId = prompt:GetAttribute("EggId")
		local panel = prompt:GetAttribute("Panel")
		if eggId then
			Registry.InterfaceController.OpenPanel("Egg", eggId)
		elseif panel then
			Registry.InterfaceController.OpenPanel(panel)
		end
	end)

	track("Spin", addSpinner, spinners)
	track("Bob", addBobber, bobbers)
	track("Pulse", addPulser, pulsers)
	track("Flicker", function(instance)
		if instance:IsA("BasePart") then
			flickers[instance] = true
		end
	end, flickers)

	RunService.RenderStepped:Connect(animate)

	task.spawn(function()
		while true do
			updateBoards()
			task.wait(0.25)
		end
	end)
end

return WorldController
