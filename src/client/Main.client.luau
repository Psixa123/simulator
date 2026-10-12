--!nonstrict
-- Storm Catcher Simulator - client entry point.
-- Loads every controller, waits for the player's data, builds the panels and starts everything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Remotes)

local root = script.Parent
local Registry = require(root:WaitForChild("Registry"))
local Controllers = root:WaitForChild("Controllers")
local UIFolder = root:WaitForChild("UI")
local UI = require(UIFolder:WaitForChild("UI"))

local ORDER = {
	"DataController",
	"SoundController",
	"InterfaceController",
	"MonetizationController",
	"HudController",
	"EffectsController",
	"VacuumController",
	"PetController",
	"ZoneController",
	"HazardController",
	"WorldController",
	"MegaStormController",
	"ObjectiveController",
}

local PANELS = { "Shop", "Pets", "Upgrades", "Rebirth", "Rewards", "Settings", "Teleport", "Egg" }

for _, name in ORDER do
	Registry[name] = require(Controllers:WaitForChild(name))
end
Registry.HatchOverlay = require(UIFolder:WaitForChild("Overlays"):WaitForChild("Hatch"))

for _, name in ORDER do
	local controller = Registry[name]
	if controller.Init then
		controller.Init()
	end
end

---------------------------------------------------------------------------
-- Loading screen (shown until the server has sent our data)
---------------------------------------------------------------------------
local Interface = Registry.InterfaceController
Interface.HudGui.Enabled = false

local loading = UI.Create("Frame", {
	Name = "Loading",
	BackgroundColor3 = Color3.new(1, 1, 1),
	Size = UDim2.fromScale(1, 1),
	ZIndex = 100,
	Parent = Interface.OverlayRoot,
	UI.Gradient(Color3.fromRGB(36, 48, 110), Color3.fromRGB(14, 18, 44), 90),
})
UI.Label({
	Text = "⛈️",
	Stroke = false,
	Size = UDim2.fromOffset(150, 150),
	Position = UDim2.new(0.5, 0, 0.5, -150),
	AnchorPoint = Vector2.new(0.5, 0.5),
	ZIndex = 101,
	Parent = loading,
})
UI.Label({
	Text = "STORM CATCHER",
	TextColor3 = Color3.fromRGB(120, 215, 255),
	Size = UDim2.fromOffset(820, 96),
	Position = UDim2.new(0.5, 0, 0.5, -20),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Stroke = 6,
	ZIndex = 101,
	Parent = loading,
})
UI.Label({
	Text = "SIMULATOR",
	TextColor3 = Color3.fromRGB(255, 214, 64),
	Size = UDim2.fromOffset(520, 62),
	Position = UDim2.new(0.5, 0, 0.5, 58),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Stroke = 5,
	ZIndex = 101,
	Parent = loading,
})
local loadingText = UI.Label({
	Text = "Loading your storm data",
	TextColor3 = Color3.fromRGB(190, 205, 245),
	Size = UDim2.fromOffset(520, 30),
	Position = UDim2.new(0.5, 0, 0.5, 130),
	AnchorPoint = Vector2.new(0.5, 0.5),
	ZIndex = 101,
	Parent = loading,
})

local loaded = false
task.spawn(function()
	local dots = 0
	while not loaded do
		dots = dots % 3 + 1
		loadingText.Text = "Loading your storm data" .. string.rep(".", dots)
		task.wait(0.35)
	end
end)

Remotes.Notify.OnClientEvent:Connect(function(text, kind)
	if loaded then
		Interface.Notify(text, kind)
	end
end)

Registry.DataController.Load()

---------------------------------------------------------------------------
-- Panels + controllers
---------------------------------------------------------------------------
local Panels = UIFolder:WaitForChild("Panels")
for _, name in PANELS do
	local panel = require(Panels:WaitForChild(name)).Build()
	Interface.RegisterPanel(name, panel)
end

for _, name in ORDER do
	local controller = Registry[name]
	if controller.Start then
		task.spawn(controller.Start)
	end
end

loaded = true
Interface.HudGui.Enabled = true
for _, descendant in loading:GetDescendants() do
	if descendant:IsA("TextLabel") then
		UI.Tween(descendant, 0.5, { TextTransparency = 1 })
	elseif descendant:IsA("UIStroke") then
		UI.Tween(descendant, 0.5, { Transparency = 1 })
	end
end
UI.Tween(loading, 0.6, { BackgroundTransparency = 1 }).Completed:Once(function()
	loading:Destroy()
end)

---------------------------------------------------------------------------
-- VIP chat tag
---------------------------------------------------------------------------
if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local properties = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		if source then
			local sender = Players:GetPlayerByUserId(source.UserId)
			if sender and sender:GetAttribute("VIP") then
				properties.PrefixText = "<font color='#FFD640'>[👑 VIP]</font> " .. message.PrefixText
			end
		end
		return properties
	end
end

if RunService:IsStudio() then
	print(string.format("⛈️ %s v%s client ready", GameConfig.GameName, GameConfig.Version))
end
