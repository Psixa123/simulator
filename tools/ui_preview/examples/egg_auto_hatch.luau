--!nocheck
-- Part 2 of tools/ui_preview/examples/egg_auto_open.luau (run that first, see its header): hatching at an
-- incubator closes the Egg panel for the hatch, it isn't reopened during it and comes back afterwards while
-- you're still there (not when you walked off). The render shows the panel back after the hatch.
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
local character = player.Character -- made by egg_auto_open.luau (run it first)
local root = character.HumanoidRootPart
local humanoid = character.Humanoid

local function at(zone: number, dx: number, dz: number?)
	local position = MapLayout.EggStation(zone) + Vector3.new(dx, 3, dz or 0)
	root.Position = position
	root.CFrame = CFrame.new(position)
end
local function far()
	root.Position = Vector3.new(-196, 3, 0) -- the spawn
	root.CFrame = CFrame.new(root.Position)
end

-- hatching: the panel closes for the hatch, isn't reopened during it, comes back after
Remotes.Hatch = {
	InvokeServer = function(_, eggId, count)
		Wait(0.1)
		return { Ok = true, Egg = eggId, Results = { { Id = "Puffling", New = true } } }
	end,
}
check("hatch from the panel", shown() == "MeadowEgg", shown())
Click("Egg/Body/Content/HatchOne")
Wait(1)
check("hatching: panel closed, hatch playing", shown() == "closed" and Registry.HatchOverlay.IsPlaying(), shown())
Wait(8)
check("after the hatch, still there: panel back", shown() == "MeadowEgg" and not Registry.HatchOverlay.IsPlaying(), shown())

Click("Egg/Body/Content/HatchOne")
Wait(1)
at(1, 0, -60) -- walk off during the hatch
Wait(8)
check("walked away during the hatch: stays closed", shown() == "closed", shown())

at(1, 0, -10)
Wait(0.6)
check("came back: opens", shown() == "MeadowEgg", shown())
print(string.format("EGGTEST done: %d failure(s)", failures))
