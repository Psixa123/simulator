--!nocheck
-- Egg incubators open / close the Egg panel by proximity (Controllers/PromptController.luau): a scripted run
-- of the real client, walking a character around the incubators. Part 2 (egg_auto_hatch.luau) hatches.
--
--   python3 tools/preview_ui.py --run-file tools/ui_preview/examples/egg_auto_open.luau \
--       --run-file tools/ui_preview/examples/egg_auto_hatch.luau --name egg_auto --keep-going
--
-- Prints "EGGTEST ok|FAIL <what>" lines (each --run-file may take up to 30 simulated seconds, hence two).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local MapLayout = require(ReplicatedStorage.Shared.Config.MapLayout)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Interface = Registry.InterfaceController
local Prompts = Registry.PromptController
local Egg = require(Client.UI.Panels.Egg)
local Confirm = require(Client.UI.Overlays.Confirm)

local failures = 0
local function check(name, condition, detail)
	if not condition then
		failures += 1
	end
	print(string.format("EGGTEST %s %s%s", if condition then "ok" else "FAIL", name, if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
end

local function shown(): string
	if Interface.IsOpen("Egg") then
		return Egg.CurrentEgg() or "?"
	end
	return if Interface.IsOpen() then "other" else "closed"
end

-- a character to walk around with
local player = Players.LocalPlayer
local character = Instance.new("Model")
character.Name = player.Name
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Parent = character
local humanoid = Instance.new("Humanoid")
humanoid.Parent = character
character.PrimaryPart = root
character.Parent = Workspace
player.Character = character

local function at(zone: number, dx: number, dz: number?)
	local position = MapLayout.EggStation(zone) + Vector3.new(dx, 3, dz or 0)
	root.Position = position
	root.CFrame = CFrame.new(position)
end
local function far()
	root.Position = Vector3.new(-196, 3, 0) -- the spawn
	root.CFrame = CFrame.new(root.Position)
end

check("controller is running", Prompts ~= nil and Prompts.EggStep ~= nil)
check("panel module shared with the controller", Egg.CurrentEgg ~= nil)

far()
Wait(0.5)
check("far away: nothing opens", shown() == "closed", shown())

at(1, 0, -20)
Wait(0.5)
check("20 studs: not yet (opens at 16)", shown() == "closed", shown())

at(1, 0, -12)
Wait(0.4)
check("12 studs: Meadow egg opens", shown() == "MeadowEgg", shown())

at(1, 0, -19)
Wait(0.5)
check("19 studs: stays open (closes past 21)", shown() == "MeadowEgg", shown())

at(1, 0, -24)
Wait(0.5)
check("24 studs: closes", shown() == "closed", shown())

at(1, 8, -8)
Wait(0.4)
check("back at the incubator: opens again", shown() == "MeadowEgg", shown())

Interface.ClosePanel() -- the X button / the dim
Wait(1)
check("closed with X while there: stays shut", shown() == "closed", shown())
at(1, 5, -5)
Wait(0.5)
check("... still shut moving around at the incubator", shown() == "closed", shown())
at(1, 0, -30)
Wait(0.4)
at(1, 0, -10)
Wait(0.4)
check("left and came back: opens again", shown() == "MeadowEgg", shown())

at(2, 0, -10)
Wait(0.4)
check("straight to the next incubator: switches to Thunder", shown() == "ThunderEgg", shown())
at(2, 0, -40)
Wait(0.4)
check("walked away from Thunder: closes", shown() == "closed", shown())

-- HUD Eggs button from far away
far()
Wait(0.3)
Interface.OpenPanel("Egg", "MeadowEgg")
Wait(1)
check("HUD-opened far away: stays open", shown() == "MeadowEgg", shown())
at(1, 0, -50)
Wait(0.5)
check("HUD-opened, walking around far away: stays open", shown() == "MeadowEgg", shown())
at(1, 0, -10)
Wait(0.4)
check("HUD-opened, walked up to it: still open", shown() == "MeadowEgg", shown())
at(1, 0, -40)
Wait(0.4)
check("HUD-opened, been there and left: closes", shown() == "closed", shown())

far()
Wait(0.3)
Interface.OpenPanel("Egg", "MeadowEgg")
Wait(0.3)
at(3, 0, -10)
Wait(0.4)
check("HUD-opened Meadow, walked up to Dune: switches", shown() == "DuneEgg", shown())
at(3, 0, -40)
Wait(0.4)

-- another panel open
far()
Interface.OpenPanel("Shop")
Wait(0.3)
at(1, 0, -10)
Wait(0.6)
check("Shop open while walking up: egg doesn't open over it", shown() == "other", shown())
Interface.ClosePanel()
Wait(0.4)
check("Shop closed at the incubator: egg opens", shown() == "MeadowEgg", shown())
Interface.OpenPanel("Pets")
Wait(0.3)
Interface.ClosePanel()
Wait(0.6)
check("switched to Pets and closed it there: egg stays shut", shown() == "closed", shown())
at(1, 0, -40)
Wait(0.4)

-- a dialog
Confirm.Show({ Title = "Test", Text = "A dialog", OnConfirm = function() end })
at(1, 0, -10)
Wait(0.6)
check("dialog open: egg doesn't open", shown() == "closed", shown())
local dialog = Interface.OverlayRoot:FindFirstChild("Confirm")
if dialog then
	dialog:Destroy()
end
Wait(0.4)
check("dialog gone: egg opens", shown() == "MeadowEgg", shown())
at(1, 0, -40)
Wait(0.4)

-- dead
humanoid.Health = 0
at(1, 0, -10)
Wait(0.5)
check("dead: nothing opens", shown() == "closed", shown())
humanoid.Health = 100
Wait(0.4)
check("respawned there: opens", shown() == "MeadowEgg", shown())

print(string.format("EGGTEST part 1 done: %d failure(s)", failures))
