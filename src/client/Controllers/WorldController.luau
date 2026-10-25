--!nonstrict
-- World interactions and ambient animation: proximity prompts that open panels/eggs,
-- spinning and bobbing props, pulsing neon, flickering lights and the forecast boards.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Format = require(Shared.Util.Format)
local StormSchedule = require(Shared.StormSchedule)

local Registry = require(script.Parent.Parent.Registry)

local WorldController = {}

local spinners = {} -- [Instance] = { Base, Speed, Axis, Bob, Phase }
local bobbers = {} -- [Instance] = { Base, Height, Speed, Phase }
local pulsers = {} -- [BasePart] = { Base, Phase, Position }
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
		pulsers[instance] = { Base = instance.Transparency, Phase = math.random() * 10, Position = instance.Position }
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
	-- Far-away props stay still (too far to notice, and it saves frame time on phones)
	for instance, state in bobbers do
		if (state.Base.Position - cameraPosition).Magnitude < 500 then
			local offset = math.sin(now * state.Speed + state.Phase) * state.Height
			setPivot(instance, state.Base + Vector3.new(0, offset, 0))
		end
	end
	for part, state in pulsers do
		if (state.Position - cameraPosition).Magnitude < 400 then
			part.Transparency = math.clamp(state.Base + (math.sin(now * 3 + state.Phase) + 1) * 0.12, 0, 1)
		end
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
local RAINBOW = GameConfig.MegaStorm.Rainbow
local UPCOMING_ROWS = 3

-- Unix time -> "2:40 PM" in the viewer's own time zone
local function clockTime(time: number): string
	local ok, text = pcall(function()
		return DateTime.fromUnixTimestamp(math.floor(time)):FormatLocalTime("LT", Players.LocalPlayer.LocaleId)
	end)
	if ok and type(text) == "string" then
		return text
	end
	local date = os.date("*t", math.floor(time))
	return string.format("%d:%02d", date.hour, date.min)
end

local function stormLabel(stormType): string
	return (stormType.Icon or "🌪️") .. " " .. stormType.Name
end

-- Rainbow Hurricane line + the upcoming storms list
local function updateForecast(gui: Instance, state: Instance, stormType, phase: string, now, upcoming)
	local rainbowLabel = gui:FindFirstChild("Rainbow")
	if rainbowLabel then
		local untilRainbow = (state:GetAttribute("RainbowTime") or now) - now
		if StormSchedule.IsRainbow(stormType) and phase == "Active" then
			rainbowLabel.Text = "🌈 RAINBOW HURRICANE IS HERE! " .. Format.Time((state:GetAttribute("EndTime") or now) - now)
		elseif StormSchedule.IsRainbow(stormType) and phase == "Warning" then
			rainbowLabel.Text = "🌈 Rainbow Hurricane in " .. Format.Time((state:GetAttribute("NextTime") or now) - now) .. "!"
		elseif untilRainbow < 600 then
			rainbowLabel.Text = "🌈 Rainbow Hurricane in " .. Format.Time(untilRainbow)
		else
			rainbowLabel.Text = "🌈 Rainbow Hurricane in " .. Format.Duration(untilRainbow)
		end
	end

	for index = 1, UPCOMING_ROWS do
		local row = gui:FindFirstChild("Upcoming" .. index)
		local entry = upcoming[index]
		if row and entry then
			local whenLabel, nameLabel, inLabel = row:FindFirstChild("When"), row:FindFirstChild("Storm"), row:FindFirstChild("In")
			local prefix = if entry.Exact then "" else "~"
			if whenLabel then
				whenLabel.Text = prefix .. clockTime(entry.Time)
			end
			if nameLabel then
				nameLabel.Text = stormLabel(entry.Type)
				nameLabel.TextColor3 = if StormSchedule.IsRainbow(entry.Type) then RAINBOW.Color else Color3.new(1, 1, 1)
			end
			if inLabel then
				inLabel.Text = "in " .. prefix .. Format.Duration(entry.Time - now)
			end
		end
	end
end

local function updateBoards()
	local state = ReplicatedStorage:FindFirstChild("MegaStormState")
	if not state then
		return
	end
	local phase = state:GetAttribute("Phase") or "Idle"
	local now = Registry.DataController.Now()
	local stormType = StormSchedule.Current(state)
	local rainbowStorm = StormSchedule.IsRainbow(stormType) and phase ~= "Idle"
	local upcoming = StormSchedule.Upcoming(state, now, UPCOMING_ROWS + 1)

	-- The board's main countdown always follows the regular storms (the rainbow has its own line)
	local nextRegular = upcoming[1]
	for _, entry in upcoming do
		if not StormSchedule.IsRainbow(entry.Type) then
			nextRegular = entry
			break
		end
	end

	local countdown, label, color
	if StormSchedule.IsRainbow(stormType) then
		countdown = (if nextRegular.Exact then "" else "~") .. Format.Time(nextRegular.Time - now)
		label = "NEXT MEGA STORM"
		color = Color3.fromRGB(255, 214, 64)
	elseif phase == "Active" then
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

	local boardType = if StormSchedule.IsRainbow(stormType) then nextRegular.Type else stormType
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
		if nameLabel and boardType then
			nameLabel.Text = stormLabel(boardType)
		end
		updateForecast(gui, state, stormType, phase, now, upcoming)
	end

	for _, gui in CollectionService:GetTagged("ArenaGui") do
		local countdownLabel = gui:FindFirstChild("Countdown")
		if countdownLabel then
			local arenaCountdown = Format.Time((state:GetAttribute(if phase == "Active" then "EndTime" else "NextTime") or now) - now)
			countdownLabel.Text = if phase == "Active"
				then stormLabel(stormType) .. " • " .. arenaCountdown
				elseif phase == "Warning" then "⚠️ " .. (if rainbowStorm then stormType.Name else "Storm") .. " arrives in " .. arenaCountdown
				elseif StormSchedule.IsRainbow(stormType) then "🌈 Rainbow Hurricane in " .. arenaCountdown
				else "Next storm in " .. arenaCountdown
			countdownLabel.TextColor3 = if rainbowStorm then RAINBOW.Color else color
		end
	end

	local pylonColor = if phase == "Active"
		then Color3.fromRGB(255, 80, 100)
		elseif phase == "Warning" then (if math.floor(os.clock() * 4) % 2 == 0 then Color3.fromRGB(255, 160, 60) else Color3.fromRGB(255, 80, 100))
		else Color3.fromRGB(120, 200, 255)
	for index, pylon in CollectionService:GetTagged("ArenaPylon") do
		pylon.Color = if rainbowStorm then Color3.fromHSV((os.clock() * 0.3 + index / 8) % 1, 0.6, 1) else pylonColor
	end
end

function WorldController.Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local eggId = prompt:GetAttribute("EggId")
		local panel = prompt:GetAttribute("Panel")
		local productKey = prompt:GetAttribute("ProductKey") -- lobby shop stands (e.g. the Aurora Gryphon)
		if eggId then
			Registry.InterfaceController.OpenPanel("Egg", eggId)
		elseif productKey then
			Registry.MonetizationController.PromptProduct(productKey)
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
