--!nonstrict
-- Egg panel: shows what an egg can hatch (with live chances) and handles
-- single, triple and automatic hatching.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Pets = require(Shared.Config.Pets)
local MapLayout = require(Shared.Config.MapLayout)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local Registry = require(script.Parent.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI)
local Theme = require(script.Parent.Parent.Theme)
local Viewport = require(script.Parent.Parent.Viewport)

local EggPanel = {}

local COLORS = Theme.Colors
local player = Players.LocalPlayer

local function nearEgg(eggId: string): boolean
	local egg = Pets.Eggs[eggId]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not egg or not root then
		return false
	end
	return (root.Position - MapLayout.EggStation(egg.Zone)).Magnitude <= GameConfig.Pets.HatchDistance
end

function EggPanel.Build()
	local window = UI.Window({
		Name = "Egg",
		Title = "Egg",
		Icon = "🥚",
		Color = "Yellow",
		Size = UDim2.fromOffset(730, 500),
	})
	local content = window.Content

	local infoLabel = UI.Label({
		Name = "Info",
		Text = "",
		Size = UDim2.new(1, 0, 0, 26),
		MaxTextSize = 20,
		Parent = content,
	})
	local grid = UI.Create("Frame", {
		Name = "Pets",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 246),
		Position = UDim2.fromOffset(0, 36),
		Parent = content,
		UI.Grid(UDim2.fromOffset(128, 240), UDim2.fromOffset(10, 10)),
	})

	local currentEgg: string? = nil
	local cards = {} -- [petId] = { Chance = TextLabel }
	local busy = false
	local auto = false
	local hatchOne, hatchThree, autoButton
	local stopButton: TextButton? = nil

	local function setAuto(enabled: boolean)
		auto = enabled
		if enabled and not stopButton then
			stopButton = UI.Button({
				Name = "StopAutoHatch",
				Text = "⏹ STOP AUTO HATCH",
				Color = "Red",
				Size = UDim2.fromOffset(300, 60),
				Position = UDim2.new(0.5, 0, 1, -40),
				AnchorPoint = Vector2.new(0.5, 1),
				ZIndex = 45,
				MaxTextSize = 24,
				Parent = Registry.InterfaceController.OverlayRoot,
				OnClick = function()
					setAuto(false)
				end,
			})
		elseif not enabled and stopButton then
			stopButton:Destroy()
			stopButton = nil
		end
	end

	local function refresh()
		local data = Registry.DataController.Data
		local eggId = currentEgg
		local egg = eggId and Pets.Eggs[eggId]
		if not data or not eggId or not egg then
			return
		end
		local luck = Formulas.LuckMultiplier(data, Registry.DataController.Now())
		infoLabel.Text = string.format("⚡ %s Volts each   •   🍀 Luck %s", Format.Number(egg.Cost), Format.Multiplier(luck))

		for _, entry in Formulas.HatchChances(eggId, luck) do
			local card = cards[entry.Id]
			if card then
				card.Chance.Text = Format.Chance(entry.Chance)
			end
		end

		UI.SetButtonText(hatchOne, "Hatch x1  •  ⚡" .. Format.Number(egg.Cost))
		UI.SetButtonColor(hatchOne, if data.Volts >= egg.Cost then "Green" else "Gray")

		if Formulas.HasPass(data, "TripleHatch") then
			UI.SetButtonText(hatchThree, "Hatch x3  •  ⚡" .. Format.Number(egg.Cost * 3))
			UI.SetButtonColor(hatchThree, if data.Volts >= egg.Cost * 3 then "Blue" else "Gray")
		else
			UI.SetButtonText(hatchThree, "🔒 Hatch x3")
			UI.SetButtonColor(hatchThree, "Gray")
		end

		UI.SetButtonText(autoButton, if Formulas.HasPass(data, "AutoHatch") then "🔁 Auto Hatch" else "🔒 Auto Hatch")
		UI.SetButtonColor(autoButton, if Formulas.HasPass(data, "AutoHatch") then "Purple" else "Gray")
	end

	local function rebuild(eggId: string)
		local egg = Pets.Eggs[eggId]
		if not egg then
			return
		end
		currentEgg = eggId
		window.Title.Text = "🥚  " .. egg.Name
		for _, child in grid:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		table.clear(cards)

		for index, entry in egg.Pets do
			local def = Pets.Pets[entry.Id]
			local rarity = Pets.Rarities[def.Rarity]
			local card = UI.Card({
				Name = entry.Id,
				LayoutOrder = index,
				StrokeColor = rarity.Color,
				StrokeThickness = 3,
				StrokeTransparency = 0,
				Parent = grid,
			})
			Viewport.Pet(entry.Id, false, {
				Size = UDim2.new(1, -8, 0, 118),
				Position = UDim2.fromOffset(4, 4),
				Parent = card,
			})
			UI.Label({ Text = def.Name, Size = UDim2.new(1, -8, 0, 24), Position = UDim2.fromOffset(4, 124), MaxTextSize = 18, ZIndex = 3, Parent = card })
			UI.Label({ Text = rarity.Name, TextColor3 = rarity.Color, Size = UDim2.new(1, -8, 0, 20), Position = UDim2.fromOffset(4, 150), MaxTextSize = 16, ZIndex = 3, Parent = card })
			local chance = UI.Label({ Text = "", TextColor3 = COLORS.Volts, Size = UDim2.new(1, -8, 0, 26), Position = UDim2.fromOffset(4, 174), MaxTextSize = 22, ZIndex = 3, Parent = card })
			UI.Label({ Text = Format.Bonus(def.Bonus) .. " Energy", TextColor3 = COLORS.Energy, Size = UDim2.new(1, -8, 0, 20), Position = UDim2.fromOffset(4, 206), MaxTextSize = 15, ZIndex = 3, Parent = card })
			cards[entry.Id] = { Chance = chance }
		end
		refresh()
	end

	-- Hatches once, or keeps hatching while auto mode is on
	local function hatch(count: number)
		if busy or not currentEgg then
			return
		end
		busy = true
		local eggId = currentEgg
		local failed = false
		repeat
			local result = Remotes.Hatch:InvokeServer(eggId, count)
			if not result or not result.Ok then
				failed = true
				setAuto(false)
				Registry.InterfaceController.Notify(result and result.Error or "The egg didn't hatch. Try again!", "Error")
				break
			end
			Registry.InterfaceController.ClosePanel(true)
			Registry.HatchOverlay.Play(result, { Hold = if auto then 1.1 else nil })
			if auto then
				task.wait(GameConfig.Pets.AutoHatchDelay)
			end
		until not auto
		busy = false
		if not failed and nearEgg(eggId) then
			Registry.InterfaceController.OpenPanel("Egg", eggId)
		end
	end

	hatchOne = UI.Button({
		Name = "HatchOne",
		Text = "Hatch x1",
		Color = "Green",
		Size = UDim2.new(1 / 3, -8, 0, 62),
		Position = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 1),
		MaxTextSize = 20,
		Parent = content,
		OnClick = function()
			hatch(1)
		end,
	})
	hatchThree = UI.Button({
		Name = "HatchThree",
		Text = "Hatch x3",
		Color = "Blue",
		Size = UDim2.new(1 / 3, -8, 0, 62),
		Position = UDim2.fromScale(0.5, 1),
		AnchorPoint = Vector2.new(0.5, 1),
		MaxTextSize = 20,
		Parent = content,
		OnClick = function()
			local data = Registry.DataController.Data
			if data and not Formulas.HasPass(data, "TripleHatch") then
				Registry.MonetizationController.PromptPass("TripleHatch")
				return
			end
			hatch(3)
		end,
	})
	autoButton = UI.Button({
		Name = "Auto",
		Text = "Auto Hatch",
		Color = "Purple",
		Size = UDim2.new(1 / 3, -8, 0, 62),
		Position = UDim2.fromScale(1, 1),
		AnchorPoint = Vector2.new(1, 1),
		MaxTextSize = 20,
		Parent = content,
		OnClick = function()
			local data = Registry.DataController.Data
			if not data then
				return
			end
			if not Formulas.HasPass(data, "AutoHatch") then
				Registry.MonetizationController.PromptPass("AutoHatch")
				return
			end
			setAuto(true)
			hatch(if Formulas.HasPass(data, "TripleHatch") then 3 else 1)
		end,
	})

	UI.Label({
		Name = "Tip",
		Text = "Pets multiply the energy you collect. Craft 5 of the same pet into a Golden one in the Pets menu!",
		Font = Theme.BodyFont,
		TextColor3 = COLORS.SubText,
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.new(0, 0, 1, -72),
		AnchorPoint = Vector2.new(0, 1),
		MaxTextSize = 15,
		Stroke = 1.5,
		Parent = content,
	})

	Registry.DataController.ObserveMany({ "Volts", "Passes", "Boosts" }, refresh)

	return {
		Window = window,
		OnOpen = function(eggId: string?)
			if eggId and eggId ~= currentEgg then
				rebuild(eggId)
			elseif not currentEgg then
				rebuild(Pets.EggOrder[1])
			else
				refresh()
			end
		end,
	}
end

return EggPanel
