--!nocheck
-- The world prompt cards (Controllers/PromptController.luau) on one sheet: zone gate cards (can pay / can't,
-- out of order, last zone), station, sell, lobby pet, rebirth and hold cards, on keyboard, gamepad and touch,
-- and at the phone scale. BillboardGuis aren't drawn by the preview, so the cards are built into frames.
--
--   python3 tools/preview_ui.py --blank --run-file tools/ui_preview/examples/prompt_cards.luau --no-core --name prompt_cards
local CollectionService = game:GetService("CollectionService")
local Registry = require(Client.Registry)
local PromptController = require(Client.Controllers.PromptController)

local SCALE = rawget(_G, "CARD_SCALE") or 1

local rich = { Volts = 12400, Zone = 1, Upgrades = { Power = 8 } }
local poor = { Volts = 1200, Zone = 1, Upgrades = { Power = 4 } }
Registry.DataController = { Data = rich }

local gui = Instance.new("ScreenGui")
gui.Name = "Sheet"
gui.IgnoreGuiInset = true
gui.Parent = PlayerGui

local function prompt(props)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = props.Action or "Open"
	p.ObjectText = props.Object or ""
	p.HoldDuration = props.Hold or 0
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.ClickablePrompt = true
	p.MaxActivationDistance = 14
	for key, value in props.Attributes or {} do
		p:SetAttribute(key, value)
	end
	if props.Gate then
		p:SetAttribute("GateZone", props.Gate)
		CollectionService:AddTag(p, "GatePrompt")
	end
	return p
end

local function caption(text, x, y)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.fromOffset(380, 16)
	label.Position = UDim2.fromOffset(x, y)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromHex("233066")
	stroke.Thickness = 2
	stroke.Parent = label
	label.Parent = gui
end

local function place(p, input, x, y, text, data, after, scale)
	Registry.DataController.Data = data or rich
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(420, 200)
	holder.Position = UDim2.fromOffset(x, y + 18)
	holder.Parent = gui
	local card = PromptController.BuildCard(p, input, holder, scale or SCALE)
	caption(text, x, y)
	if after then
		after(card)
	end
	return card
end

local K = Enum.ProximityPromptInputType.Keyboard
local G = Enum.ProximityPromptInputType.Gamepad
local T = Enum.ProximityPromptInputType.Touch

-- column 1: gates
place(prompt({ Action = "Unlock", Object = "Thunder Valley  •  ⚡5K", Hold = 0.5, Gate = 2 }), K, 30, 20, "gate: affordable, power met (keyboard, holding 60%)", rich, function(card)
	card.SetHold(0.6)
	card.Press(true)
end)
place(prompt({ Action = "Unlock", Object = "Thunder Valley  •  ⚡5K", Hold = 0.5, Gate = 2 }), T, 30, 200, "gate: can't afford, power too low (touch)", poor)
place(prompt({ Action = "Unlock", Object = "Frostpeak", Hold = 0.5, Gate = 4 }), G, 30, 380, "gate: out of order (gamepad)", rich)
place(prompt({ Action = "Unlock", Object = "Upper Atmosphere", Hold = 0.5, Gate = 6 }), K, 30, 540, "gate: last zone, rich player", { Volts = 9e12, Zone = 5, Upgrades = { Power = 60 } })

-- column 2: generic
place(prompt({ Action = "Open", Object = "Storm Shop", Attributes = { Panel = "Shop" } }), K, 460, 20, "station (keyboard)")
place(prompt({ Action = "Sell", Object = "Weather Lab", Attributes = { PromptIcon = "Sell" } }), K, 460, 120, "sell (keyboard, pressed)", nil, function(card)
	card.Press(true)
end)
place(prompt({ Action = "Buy", Object = "Aurora Gryphon", Attributes = { ProductKey = "AuroraGryphon" } }), T, 460, 220, "lobby pet (touch)")
place(prompt({ Action = "Climate Shift", Object = "Climate Shrine", Attributes = { Panel = "Rebirth" } }), G, 460, 320, "rebirth (gamepad)")
place(prompt({ Action = "Open", Object = "Upgrade Workshop", Attributes = { Panel = "Upgrades" } }), K, 460, 420, "station (keyboard)")
place(prompt({ Action = "Claim", Object = "", Hold = 1 }), K, 460, 520, "no object text, hold 1 s at 40%", nil, function(card)
	card.SetHold(0.4)
end)
place(prompt({ Action = "Open", Object = "Daily Rewards", Attributes = { Panel = "Rewards" } }), T, 460, 610, "station (touch)")

-- column 3: small scale (phones)
place(prompt({ Action = "Unlock", Object = "Dune Sea", Hold = 0.5, Gate = 3 }), T, 860, 20, "gate at phone scale 0.82 (touch)", { Volts = 2e6, Zone = 2, Upgrades = { Power = 12 } }, nil, 0.82)
place(prompt({ Action = "Open", Object = "Storm Shop", Attributes = { Panel = "Shop" } }), T, 860, 160, "station at phone scale 0.82 (touch)", nil, nil, 0.82)
place(prompt({ Action = "Buy", Object = "Aurora Gryphon", Attributes = { ProductKey = "AuroraGryphon" } }), T, 860, 240, "lobby pet at 0.82 (touch, pressed)", nil, function(card) card.Press(true) end, 0.82)
