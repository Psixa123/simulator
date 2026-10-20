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
	"RadarController",
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

-- Messages that arrive while loading (e.g. purchases granted on join) are shown once we're in
local pendingNotifications = {}
Remotes.Notify.OnClientEvent:Connect(function(text, kind)
	if type(text) ~= "string" then
		return
	end
	if loaded then
		Interface.Notify(text, kind)
	elseif #pendingNotifications < 8 then
		table.insert(pendingNotifications, { Text = text, Kind = kind })
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
for _, pending in pendingNotifications do
	Interface.Notify(pending.Text, pending.Kind)
end
table.clear(pendingNotifications)

---------------------------------------------------------------------------
-- Admin panel (owner only). Built once the server marks this player as an admin ("IsAdmin", set by
-- AdminService); everyone else never gets the panel, the HUD button or the chat command. The server
-- checks every admin command again, so this only decides whether the interface exists.
---------------------------------------------------------------------------
local localPlayer = Players.LocalPlayer
local adminReady = false

local function toggleAdmin()
	Interface.TogglePanel("Admin")
end

local function enableAdmin()
	if adminReady or localPlayer:GetAttribute("IsAdmin") ~= true then
		return
	end
	adminReady = true
	Interface.RegisterPanel("Admin", require(Panels:WaitForChild("Admin")).Build())
	Registry.HudController.ShowAdminButton(toggleAdmin)

	-- "/admin" in the chat opens it too (a chat problem must never take the panel down with it)
	local ok, err = pcall(function()
		if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
			local command = Instance.new("TextChatCommand")
			command.Name = "AdminPanelCommand"
			command.PrimaryAlias = "/admin"
			command.Triggered:Connect(toggleAdmin)
			command.Parent = TextChatService
		else
			localPlayer.Chatted:Connect(function(message)
				if string.lower(string.match(message, "^%s*(.-)%s*$") or "") == "/admin" then
					toggleAdmin()
				end
			end)
		end
	end)
	if not ok then
		warn("[Admin] Couldn't add the /admin chat command: " .. tostring(err))
	end
end

localPlayer:GetAttributeChangedSignal("IsAdmin"):Connect(enableAdmin)
enableAdmin()

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
