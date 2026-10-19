--!nocheck
-- UI preview boot: sets up the local player, a fake server and the player's data, then runs the real
-- client entry point (src/client/Main.client.luau) on the simulated clock, performs the actions asked
-- for on the command line (open a panel, click buttons, run Luau), and prints the drawn interface as
-- one JSON line ("@@UI@@{...}") for preview_ui.py.
--
-- Controllers that only drive the 3D world (effects, vacuum, pets, zones, hazards, world props) are
-- replaced with stand-ins by default (Config.Stubs); everything that builds interface runs for real.

local M = ...
local Config = M.Config
local fmt = string.format
local task = M.task
local Instance = M.Instance
local Scheduler = M.Scheduler

M.Screen = Config.Screen
M.InstallGlobals()

local game = M.game
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local function noop() end

---------------------------------------------------------------------------------------------------- the local player
local player = Instance.new("Player")
player.Name = Config.PlayerName or "StormChaser"
player.DisplayName = Config.PlayerName or "StormChaser"
player.UserId = 1
player.Parent = Players
rawget(Players, "__props").LocalPlayer = player
local playerGui = Instance.new("PlayerGui")
playerGui.Name = "PlayerGui"
playerGui.Parent = player
M.PlayerGui = playerGui
for _, name in { "Backpack", "PlayerScripts" } do
	local folder = Instance.new(name)
	folder.Name = name
	folder.Parent = player
end
-- the server sets this once Roblox's PolicyService answered (false: Volts packs are on sale)
player:SetAttribute("PaidRandomItemsRestricted", Config.Restricted == true)

-- world folders the client waits for
for _, name in { "WeatherCells", "MegaStorm" } do
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = Workspace
end

---------------------------------------------------------------------------------------------------- shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = M.require(Shared.Config.GameConfig)
local Pets = M.require(Shared.Config.Pets)
local Zones = M.require(Shared.Config.Zones)
local Formulas = M.require(Shared.Formulas)
local Rewards = M.require(Shared.Config.Rewards)

local function now()
	return M.ClockBase + M.Now
end

local function deepCopy(value)
	if type(value) ~= "table" or M.KindOf(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

---------------------------------------------------------------------------------------------------- player data
-- Same shape as DataService's template() (src/server/Services/DataService.luau) plus the session keys
local function template()
	return {
		DataVersion = 1,
		Volts = 0,
		TotalVolts = 0,
		Energy = 0,
		TankValue = 0,
		Rebirths = 0,
		Zone = 1,
		Upgrades = { Power = 1, Tank = 1, Range = 1, Speed = 1 },
		Pets = {},
		NextPetId = 1,
		Index = {},
		Boosts = { Energy = 0, Luck = 0 },
		Daily = { Streak = 0, LastClaim = 0 },
		Settings = deepCopy(GameConfig.DefaultSettings),
		Stats = { CellsCaught = 0, EggsHatched = 0, MegaStorms = 0, Sells = 0, PlayTime = 0 },
		Passes = {},
		GiftsClaimed = {},
		SessionStart = now(),
	}
end

local function addPet(data, petId, tier, equipped)
	local entry = {
		Uid = "p" .. data.NextPetId,
		Id = petId,
		Golden = tier == "Golden",
		Rainbow = tier == "Rainbow",
		Equipped = equipped == true,
	}
	data.NextPetId += 1
	table.insert(data.Pets, entry)
	data.Index[petId] = true
	return entry
end

local function fillTank(data, fraction)
	data.Energy = math.floor(Formulas.TankCapacity(data) * fraction)
	data.TankValue = data.Energy * (Zones[data.Zone] and Zones[data.Zone].Value or 1)
end

local SCENARIOS = {}

-- A fresh player: what DataService gives on the first join
function SCENARIOS.new()
	return template()
end

-- Mid game (the default): Dune Sea unlocked, three Climate Shifts, a dozen pets, an active boost,
-- a daily reward and a gift ready
function SCENARIOS.mid()
	local data = template()
	data.Volts = 12_400_000
	data.TotalVolts = 96_500_000
	data.Rebirths = 3
	data.Zone = 3
	data.Upgrades = { Power = 24, Tank = 22, Range = 6, Speed = 8 }
	data.Passes = { AutoCatch = true }
	for _, spec in {
		{ "BreezeKing", "Normal", true }, { "VoltBat", "Golden", true }, { "MirageDjinn", "Normal", true },
		{ "Scarab", "Normal", true }, { "ThunderPup", "Normal" }, { "Sunny", "Rainbow" }, { "DustBunny", "Normal" },
		{ "Zappy", "Normal" }, { "CactusCub", "Normal" }, { "Droplet", "Golden" }, { "Sandy", "Normal" },
		{ "Static", "Normal" }, { "Puffling", "Normal" }, { "Puffling", "Normal" }, { "Sandy", "Normal" },
	} do
		addPet(data, spec[1], spec[2], spec[3])
	end
	for _, eggId in { "MeadowEgg", "ThunderEgg", "DuneEgg" } do
		for index, entry in Pets.Eggs[eggId].Pets do
			if index <= 4 then
				data.Index[entry.Id] = true
			end
		end
	end
	data.Index.Sunbeam = true
	data.Boosts = { Energy = now() + 272, Luck = 0 }
	data.Daily = { Streak = 2, LastClaim = now() - 26 * 3600 }
	data.GiftsClaimed = { ["1"] = true, ["2"] = true }
	data.SessionStart = now() - 11 * 60
	data.Stats = { CellsCaught = 18_420, EggsHatched = 96, MegaStorms = 7, Sells = 840, PlayTime = 52_000 }
	fillTank(data, 0.62)
	return data
end

-- Late game: every zone, maxed upgrades, all passes, a full collection with golden and rainbow pets
function SCENARIOS.late()
	local data = template()
	data.Volts = 4.2e12
	data.TotalVolts = 9.8e13
	data.Rebirths = 24
	data.Zone = #Zones
	data.Upgrades = { Power = 60, Tank = 60, Range = 10, Speed = 10 }
	for key in M.require(Shared.Config.Monetization).Gamepasses do
		data.Passes[key] = true
	end
	local count = 0
	for _, petId in Pets.IndexOrder do
		count += 1
		local tier = if count % 5 == 0 then "Rainbow" elseif count % 3 == 0 then "Golden" else "Normal"
		addPet(data, petId, tier, count > #Pets.IndexOrder - Formulas.EquipSlots(data))
	end
	data.Boosts = { Energy = now() + 1800, Luck = now() + 900 }
	data.Daily = { Streak = 6, LastClaim = now() - 3 * 3600 }
	for index in Rewards.Gifts do
		data.GiftsClaimed[tostring(index)] = true
	end
	data.SessionStart = now() - 3 * 3600
	fillTank(data, 1)
	return data
end

local function merge(target, source)
	for key, value in source do
		if type(value) == "table" and type(target[key]) == "table" and #value == 0 and next(value) ~= nil then
			merge(target[key], value)
		else
			target[key] = value
		end
	end
end

local function makeData()
	local scenario = SCENARIOS[Config.Data or "mid"]
	if not scenario then
		error("unknown --data scenario " .. tostring(Config.Data), 0)
	end
	local data = scenario()
	if Config.DataJson then
		local overrides = M.JsonDecode(Config.DataJson)
		-- times in the JSON may be relative: { "Boosts": { "Energy": "+300" } } = now + 300 s
		local function relative(t)
			for k, v in t do
				if type(v) == "string" and string.match(v, "^[%+%-]%d+%.?%d*$") then
					t[k] = now() + tonumber(v)
				elseif type(v) == "table" then
					relative(v)
				end
			end
		end
		relative(overrides)
		merge(data, overrides)
	end
	return data
end

local serverData = makeData()
M.ServerData = serverData

---------------------------------------------------------------------------------------------------- the fake server
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local NO_SERVER = "The preview has no server."

local function replicate(keys)
	local changes = {}
	for _, key in keys do
		changes[key] = deepCopy(serverData[key])
	end
	M.Fire(M.GetSignal(Remotes.DataChanged, "OnClientEvent"), changes)
end
M.Replicate = replicate

local handlers = {}
function handlers.GetData()
	if Config.DataDelay and M.Now < Config.DataDelay then
		return nil
	end
	return deepCopy(serverData)
end
function handlers.SetSetting(key, value)
	if type(key) ~= "string" or type(value) ~= "boolean" or GameConfig.DefaultSettings[key] == nil then
		return false
	end
	serverData.Settings[key] = value
	replicate({ "Settings" })
	return true
end
function handlers.PetAction(action, argument)
	if action == "Equip" or action == "Unequip" then
		for _, pet in serverData.Pets do
			if pet.Uid == argument then
				pet.Equipped = action == "Equip"
				replicate({ "Pets" })
				return { Ok = true }
			end
		end
		return { Ok = false, Error = "Pet not found." }
	end
	return { Ok = false, Error = NO_SERVER }
end

M.Server = {
	Invoke = function(name, ...)
		local handler = handlers[name]
		if handler then
			return handler(...)
		end
		M.Note("server: " .. name .. " answered " .. NO_SERVER)
		return { Ok = false, Error = NO_SERVER }
	end,
	Event = function(name)
		M.Note("server: FireServer(" .. name .. ") ignored")
	end,
}

-- Mega Storm schedule state (the server publishes these attributes)
local stormState = ReplicatedStorage:FindFirstChild("MegaStormState")
if stormState then
	stormState:SetAttribute("Phase", Config.StormPhase or "Idle")
	stormState:SetAttribute("StormIndex", 1)
	stormState:SetAttribute("NextTime", now() + 105)
	stormState:SetAttribute("RegularTime", now() + 105)
	stormState:SetAttribute("RainbowTime", now() + 3 * 3600)
end

---------------------------------------------------------------------------------------------------- controller stand-ins
local client = M.NodeAt(Config.ClientPath)
local controllers = client:WaitForChild("Controllers")

local STANDINS = {
	EffectsController = function()
		local cells = {}
		return {
			Cells = function()
				return cells
			end,
			GetCell = function()
				return nil
			end,
			Burst = noop,
			FloatText = noop,
			Confetti = noop,
			LightningBolt = noop,
		}
	end,
	VacuumController = function()
		return {
			IsHolding = function()
				return false
			end,
			InMegaRange = function()
				return false
			end,
		}
	end,
	ZoneController = function()
		return { Current = Config.ZoneHere or serverData.Zone, RefreshLighting = noop }
	end,
	HazardController = function()
		return { ShowZoneHazard = noop }
	end,
	PetController = function()
		return {}
	end,
	WorldController = function()
		return {}
	end,
}

for _, name in Config.Stubs or {} do
	local module = controllers:FindFirstChild(name)
	if module then
		local make = STANDINS[name]
		local fields = if make then make() else {}
		fields.Init = fields.Init or noop
		fields.Start = fields.Start or noop
		M.ReplaceModule(module, M.Stub(name, fields))
	else
		table.insert(M.Warnings, "--stub " .. name .. ": no such controller")
	end
end

---------------------------------------------------------------------------------------------------- viewports: which pet / egg they show (page.js draws the pet's picture)
local eggByName = {}
for id, egg in Pets.Eggs do
	eggByName[egg.Name] = id
end
local SILHOUETTE = M.Color3.fromRGB(20, 22, 40)

-- How Viewport.luau framed the model: camera distance = radius / tan(fov / 2) * zoom, so the model's
-- largest side fills 1 / zoom of the view's height
local function framingZoom(viewport, model)
	local camera = viewport.CurrentCamera
	if not camera then
		return nil
	end
	local ok, zoom = pcall(function()
		local _, size = model:GetBoundingBox()
		local radius = math.max(size.X, size.Y, size.Z) / 2
		local offset = camera.CFrame.Position - model:GetPivot().Position
		local along = math.sqrt(math.max(0, offset.Magnitude ^ 2 - (radius * 0.35) ^ 2))
		return along * math.tan(math.rad(camera.FieldOfView / 2)) / radius
	end)
	return if ok and zoom == zoom and zoom > 0.2 and zoom < 10 then math.floor(zoom * 1000 + 0.5) / 1000 else nil
end

function M.DescribeViewport(viewport)
	for _, child in rawget(viewport, "__children") do
		if child:IsA("Model") then
			local petId = child:GetAttribute("PetId")
			if petId and Pets.Pets[petId] then
				local def = Pets.Pets[petId]
				local silhouette = false
				for _, part in child:GetDescendants() do
					if part:IsA("BasePart") and part.Transparency < 1 then
						silhouette = part.Color == SILHOUETTE
						break
					end
				end
				local rarity = Pets.Rarities[def.Rarity]
				return {
					Kind = "Pet",
					Pet = petId,
					Tier = child:GetAttribute("Tier") or "Normal",
					Silhouette = silhouette or nil,
					Body = def.Look.Color:ToHex(),
					Accent = def.Look.Accent:ToHex(),
					Rarity = rarity and rarity.Color:ToHex(),
					Name = def.Name,
					Zoom = framingZoom(viewport, child),
				}
			end
			local eggId = eggByName[child.Name]
			if eggId then
				local egg = Pets.Eggs[eggId]
				return { Kind = "Egg", Egg = eggId, Body = egg.Color:ToHex(), Accent = egg.Accent:ToHex(), Zoom = framingZoom(viewport, child) }
			end
			return { Kind = "Model", Name = child.Name }
		end
	end
	return { Kind = "Empty" }
end

---------------------------------------------------------------------------------------------------- actions
local Registry -- set once the client has loaded it

local function guiPath(object)
	local parts = {}
	local current = object
	while current and current ~= playerGui do
		table.insert(parts, 1, rawget(current, "__props").Name)
		current = rawget(current, "__parent")
	end
	return table.concat(parts, "/")
end
M.GuiPath = guiPath

local function shown(object)
	local current = object
	while current and current ~= playerGui do
		local props = rawget(current, "__props")
		if props.Visible == false or (rawget(current, "__class") == "ScreenGui" and not props.Enabled) then
			return false
		end
		current = rawget(current, "__parent")
	end
	return current == playerGui
end

-- Finds a GuiButton whose path ends with `path` ("Close", "Shop/Close", "Pets/Content/Tabs/Index"),
-- preferring buttons that are on screen
local function findButton(path)
	path = string.gsub(path, "%.", "/")
	local best = nil
	for _, object in playerGui:GetDescendants() do
		if object:IsA("GuiButton") then
			local full = guiPath(object)
			if full == path or string.sub(full, -(#path + 1)) == "/" .. path then
				if shown(object) then
					return object
				end
				best = best or object
			end
		end
	end
	return best
end

local function click(path)
	local button = findButton(path)
	if not button then
		error(fmt("--click %s: no button with that path (see the tree in the .json dump)", path), 0)
	end
	local input = M.Stub("InputObject", { UserInputType = Enum.UserInputType.MouseButton1, UserInputState = Enum.UserInputState.Begin, Position = M.v3(0, 0, 0), KeyCode = Enum.KeyCode.Unknown })
	for _, name in { "MouseButton1Down", "InputBegan", "MouseButton1Up", "InputEnded", "MouseButton1Click", "Activated" } do
		local signal = rawget(button, "__signals")[name]
		if signal then
			if name == "Activated" or name == "InputBegan" or name == "InputEnded" then
				M.Fire(signal, input, 1)
			else
				M.Fire(signal, 0, 0)
			end
		end
	end
	return guiPath(button)
end

local function snippetEnv()
	local env = setmetatable({}, { __index = getfenv(1) })
	env.Registry = Registry
	env.Client = client
	env.UI = M.require(client.UI.UI)
	env.Theme = M.require(client.UI.Theme)
	env.Data = Registry and Registry.DataController.Data
	env.ServerData = serverData
	env.PlayerGui = playerGui
	env.Open = function(name, ...)
		Registry.InterfaceController.OpenPanel(name, ...)
	end
	env.Click = click
	env.Wait = function(seconds)
		task.wait(seconds or 0)
	end
	-- server -> client events: FireClient("Notify", "Hi!", "Success"), FireClient("Effect", "MegaWarning", ...)
	env.FireClient = function(remote, ...)
		M.Fire(M.GetSignal(Remotes:WaitForChild(remote), "OnClientEvent"), ...)
	end
	-- changes the player's data on the server and replicates it like DataService does
	env.SetData = function(key, value)
		serverData[key] = value
		replicate({ key })
	end
	env.require = M.require
	return env
end

local actionLog = {}
local function runAction(action)
	if action.Kind == "panel" then
		Registry.InterfaceController.OpenPanel(action.Name, table.unpack(action.Args or {}))
		table.insert(actionLog, "opened panel " .. action.Name)
	elseif action.Kind == "click" then
		table.insert(actionLog, "clicked " .. click(action.Path))
	elseif action.Kind == "run" then
		local fn, err = loadstring(action.Code, "=" .. (action.Name or "--run"))
		if not fn then
			error("--run: " .. tostring(err), 0)
		end
		setfenv(fn, snippetEnv())
		fn()
		table.insert(actionLog, "ran " .. (action.Name or "a --run snippet"))
	elseif action.Kind == "notify" then
		Registry.InterfaceController.Notify(action.Text, action.Type)
	elseif action.Kind == "wait" then
		task.wait(action.Seconds)
	end
end

---------------------------------------------------------------------------------------------------- run
local function runThread(fn, limit)
	local done = false
	local thread = coroutine.create(function()
		fn()
		done = true
	end)
	M.Resume(thread)
	local waited = 0
	while not done and coroutine.status(thread) ~= "dead" and waited < limit do
		Scheduler.Run(0.1)
		waited += 0.1
	end
	return done
end

local mainScript = M.NodeAt(Config.MainPath)
local mainThread = coroutine.create(function()
	M.RunScript(mainScript)
end)
M.Resume(mainThread)
Scheduler.Run(Config.BootSeconds or 2)
Registry = M.require(client.Registry)
if coroutine.status(mainThread) ~= "dead" and not (Config.DataDelay and Config.DataDelay > 0) then
	table.insert(M.Warnings, "Main.client.luau has not finished after " .. tostring(Config.BootSeconds) .. " simulated seconds (still waiting on something)")
end

for _, action in Config.Actions or {} do
	local finished = runThread(function()
		local ok, err = pcall(runAction, action)
		if not ok then
			table.insert(M.Errors, { Message = tostring(err), Trace = "" })
		end
	end, action.Limit or 30)
	if not finished and action.Kind ~= "wait" then
		table.insert(M.Warnings, "action " .. tostring(action.Kind) .. " was still running after " .. tostring(action.Limit or 30) .. " simulated seconds")
	end
	Scheduler.Run(action.After or 0.05)
end
Scheduler.Run(Config.SettleSeconds or 1)

---------------------------------------------------------------------------------------------------- dump
local notes = {}
for text, count in M.Notes do
	table.insert(notes, { Text = text, Count = count })
end
table.sort(notes, function(a, b)
	return a.Text < b.Text
end)
local errors = {}
for _, err in M.Errors do
	table.insert(errors, err.Message .. (if err.Trace ~= "" then "\n" .. err.Trace else ""))
end

local items = M.Layout.DrawList()
local images, pets = {}, {}
for _, item in items do
	if item.Image then
		images[item.Image.Src] = true
	end
	if item.View and item.View.Pet then
		pets[item.View.Pet .. ":" .. (item.View.Tier or "Normal")] = true
	end
end
local imageList, petList = {}, {}
for src in images do
	table.insert(imageList, src)
end
for key in pets do
	table.insert(petList, key)
end
table.sort(imageList)
table.sort(petList)

local count = 0
for _ in playerGui:GetDescendants() do
	count += 1
end

local Format = M.require(Shared.Util.Format)
local dump = {
	Screen = M.Screen,
	-- leaderstats (PlayerService): what Roblox's player list shows
	Player = { Name = player.DisplayName, Volts = Format.Number(serverData.Volts), Shifts = serverData.Rebirths },
	Items = items,
	Tree = if Config.Tree ~= false then M.Layout.Tree() else nil,
	Images = imageList,
	Pets = petList,
	Actions = actionLog,
	Warnings = M.Warnings,
	Prints = M.Prints,
	Errors = errors,
	Gaps = M.Gaps,
	Notes = notes,
	Stats = { Instances = count, Layouts = M.Layout.Count(), SimSeconds = M.Now, Drawn = #items },
	CoreGui = M.CoreGui,
}
M.RealPrint("@@UI@@" .. M.Json(dump))
