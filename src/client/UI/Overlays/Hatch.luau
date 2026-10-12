--!nonstrict
-- Full-screen egg hatching animation and pet reveal.
--
-- Hatch.Play(result, options) yields until the animation is finished.
--   result  = { Egg = eggId?, Results = { { Id = petId, New = boolean?, Golden = boolean?, Rainbow = boolean? } } }
--   options = { Title = string?, Hold = seconds? }
-- Hatch.Reveal(petId, tier, title) shows a single pet without an egg (rewards, drops).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pets = require(Shared.Config.Pets)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local PetModels = require(Shared.Models.PetModels)

local Registry = require(script.Parent.Parent.Parent.Registry)
local UI = require(script.Parent.Parent.UI)
local Theme = require(script.Parent.Parent.Theme)
local Viewport = require(script.Parent.Parent.Viewport)

local Hatch = {}

local playing = false

local function buildSlot(row: Frame, index: number, entry, eggId: string?)
	local def = Pets.Pets[entry.Id] or Pets.Pets.Puffling
	local rarity = Pets.Rarities[def.Rarity]
	local tier = Pets.TierOf(entry)

	local slot = UI.Create("Frame", {
		Name = "Slot" .. index,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(290, 410),
		LayoutOrder = index,
		ZIndex = 31,
		Parent = row,
	})
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = slot

	local stage = UI.Create("Frame", {
		Name = "Stage",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(280, 280),
		Position = UDim2.new(0.5, 0, 0, 140),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 31,
		Parent = slot,
	})

	local rays = {}
	for rayIndex = 0, 7 do
		local ray = UI.Create("Frame", {
			Name = "Ray",
			BackgroundColor3 = rarity.Color,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(26, 340),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = rayIndex * 22.5,
			Visible = false,
			ZIndex = 31,
			Parent = stage,
		})
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = ray
		table.insert(rays, ray)
	end

	local disc = UI.Create("Frame", {
		Name = "Disc",
		BackgroundColor3 = rarity.Color,
		BackgroundTransparency = 0.72,
		Size = UDim2.fromOffset(210, 210),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 32,
		Parent = stage,
		UI.Round(),
	})

	local eggView = nil
	if eggId then
		eggView = Viewport.Egg(eggId, {
			Size = UDim2.fromOffset(230, 230),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 33,
			Parent = stage,
		})
	end

	local nameLabel = UI.Label({
		Name = "PetName",
		Text = Pets.DisplayName(def.Id, tier),
		TextColor3 = Pets.Tiers[tier].Color,
		Size = UDim2.new(1, 0, 0, 42),
		Position = UDim2.fromOffset(0, 288),
		Stroke = 3.5,
		Visible = false,
		ZIndex = 34,
		Parent = slot,
	})
	if tier == "Rainbow" then
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		UI.Create("UIGradient", { Color = PetModels.RainbowSequence, Parent = nameLabel })
	end
	local rarityLabel = UI.Label({
		Name = "Rarity",
		Text = string.upper(rarity.Name),
		TextColor3 = rarity.Color,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 332),
		Stroke = 3,
		Visible = false,
		ZIndex = 34,
		Parent = slot,
	})
	local bonusLabel = UI.Label({
		Name = "Bonus",
		Text = Format.Bonus(Formulas.PetBonus(entry.Id, tier)) .. " Energy",
		TextColor3 = Theme.Colors.Energy,
		Size = UDim2.new(1, 0, 0, 28),
		Position = UDim2.fromOffset(0, 366),
		Stroke = 3,
		Visible = false,
		ZIndex = 34,
		Parent = slot,
	})
	local newBadge = UI.Create("Frame", {
		Name = "New",
		BackgroundColor3 = Color3.fromRGB(255, 70, 110),
		Size = UDim2.fromOffset(84, 36),
		Position = UDim2.new(1, -20, 0, 20),
		AnchorPoint = Vector2.new(1, 0),
		Rotation = 12,
		Visible = false,
		ZIndex = 35,
		Parent = slot,
		UI.Corner(10),
		UI.Stroke(3),
	})
	UI.Label({ Text = "NEW!", Size = UDim2.fromScale(0.86, 0.74), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 36, Parent = newBadge })

	return {
		Entry = entry,
		Rarity = rarity,
		Frame = slot,
		Stage = stage,
		Scale = scale,
		Rays = rays,
		Disc = disc,
		EggView = eggView,
		PetView = nil,
		Labels = { nameLabel, rarityLabel, bonusLabel },
		NewBadge = newBadge,
	}
end

local function reveal(slot)
	if slot.EggView then
		slot.EggView.Frame:Destroy()
		slot.EggView = nil
	end
	slot.PetView = Viewport.Pet(slot.Entry.Id, Pets.TierOf(slot.Entry), {
		Size = UDim2.fromOffset(250, 250),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 33,
		Zoom = 1.25,
		Parent = slot.Stage,
	})
	for _, ray in slot.Rays do
		ray.Visible = true
	end
	slot.Disc.Visible = true
	for _, label in slot.Labels do
		label.Visible = true
	end
	slot.NewBadge.Visible = slot.Entry.New == true
	slot.Scale.Scale = 1.3
	UI.Tween(slot.Scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
end

function Hatch.IsPlaying(): boolean
	return playing
end

function Hatch.Play(result, options)
	options = options or {}
	while playing do
		task.wait(0.1)
	end
	playing = true

	local root = Registry.InterfaceController.OverlayRoot
	local results = result.Results or {}
	local eggId = result.Egg
	local phase = "Egg"
	local skipped, dismissed = false, false
	local revealedAt = 0

	local backdrop = UI.Create("TextButton", {
		Name = "Hatch",
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = Color3.fromRGB(6, 8, 22),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 30,
		Parent = root,
	})
	UI.Tween(backdrop, 0.2, { BackgroundTransparency = 0.3 })
	backdrop.Activated:Connect(function()
		if phase == "Egg" then
			skipped = true
		elseif os.clock() - revealedAt > 0.45 then
			dismissed = true
		end
	end)

	-- Centred in the space below the Roblox top bar so the title never slides under it on phones
	local shift = Registry.InterfaceController.SafeTop / 2
	local title = options.Title or (eggId and Pets.Eggs[eggId] and Pets.Eggs[eggId].Name) or ""
	UI.Label({
		Name = "Title",
		Text = title,
		TextColor3 = Theme.Colors.Volts,
		Size = UDim2.fromOffset(700, 54),
		Position = UDim2.new(0.5, 0, 0.5, -226 + shift),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Stroke = 4,
		ZIndex = 34,
		Parent = backdrop,
	})

	local row = UI.Create("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(#results * 310, 410),
		Position = UDim2.new(0.5, 0, 0.5, 10 + shift),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 31,
		Parent = backdrop,
		UI.List(Enum.FillDirection.Horizontal, 20, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})

	local slots = {}
	local bestOrder = 1
	for index, entry in results do
		local slot = buildSlot(row, index, entry, eggId)
		slots[index] = slot
		bestOrder = math.max(bestOrder, slot.Rarity.Order)
		UI.Tween(slot.Scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	end

	-- Egg shake
	if eggId then
		local start = os.clock()
		while os.clock() - start < 1.2 and not skipped do
			local elapsed = os.clock() - start
			local angle = math.sin(elapsed * 30) * (0.06 + elapsed * 0.32)
			for _, slot in slots do
				if slot.EggView then
					slot.EggView.SetCFrame(CFrame.Angles(0, 0, angle))
				end
			end
			RunService.RenderStepped:Wait()
		end

		local flash = UI.Create("Frame", {
			Name = "Flash",
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 40,
			Parent = backdrop,
		})
		UI.Tween(flash, 0.4, { BackgroundTransparency = 1 }).Completed:Once(function()
			flash:Destroy()
		end)
		Registry.SoundController.Play("Hatch")
	end

	-- Reveal
	phase = "Reveal"
	revealedAt = os.clock()
	for _, slot in slots do
		reveal(slot)
	end
	Registry.SoundController.Play("Success", 0.9 + bestOrder * 0.06)
	if bestOrder >= 4 then
		Registry.EffectsController.Confetti(40 + bestOrder * 20)
	end

	local hold = options.Hold or (if bestOrder >= 5 then 3.2 else 2)
	while os.clock() - revealedAt < hold and not dismissed do
		local elapsed = os.clock() - revealedAt
		local dt = RunService.RenderStepped:Wait()
		for _, slot in slots do
			if slot.PetView then
				slot.PetView.SetRotation(math.rad(20) + math.sin(elapsed * 2.2) * 0.55)
			end
			for _, ray in slot.Rays do
				ray.Rotation += dt * 45
			end
		end
	end

	backdrop:Destroy()
	playing = false
end

-- tier: "Normal" | "Golden" | "Rainbow" (a boolean still means golden)
function Hatch.Reveal(petId: string, tier, title: string?)
	local tierName = Pets.TierOf(tier)
	task.spawn(Hatch.Play, {
		Results = { { Id = petId, Golden = tierName == "Golden", Rainbow = tierName == "Rainbow", New = false } },
	}, { Title = title or "NEW PET!" })
end

return Hatch
