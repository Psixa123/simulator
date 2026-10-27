--!nonstrict
-- Look of Secret pets in the interface (Egg panel, Pet Index, inventory): deep cosmic tiles with a rainbow
-- rim and pedestal, "???" silhouettes until the pet is discovered, and their "1 in N" odds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pets = require(Shared.Config.Pets)
local Format = require(Shared.Util.Format)

local Secret = {}

Secret.Top = Color3.fromRGB(64, 32, 128) -- tile / card gradient
Secret.Bottom = Color3.fromRGB(16, 8, 38)
Secret.Edge = Color3.fromRGB(196, 140, 255)
Secret.Text = Color3.fromRGB(255, 236, 140) -- odds

-- Pets.SecretRainbow as an evenly spaced ColorSequence
function Secret.Rainbow(): ColorSequence
	local colors = Pets.SecretRainbow
	local keys = {}
	for index, color in colors do
		table.insert(keys, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(keys)
end

function Secret.Gradient(rotation: number?): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = Secret.Rainbow()
	gradient.Rotation = rotation or 0
	return gradient
end

-- A tiny sparkle glyph (decor on secret tiles and cards)
function Secret.Sparkle(parent: Instance, position: UDim2, size: number, color: Color3?, zIndex: number?)
	local label = Instance.new("TextLabel")
	label.Name = "Sparkle"
	label.BackgroundTransparency = 1
	label.Text = "✦"
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.Size = UDim2.fromOffset(size, size)
	label.Position = position
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.ZIndex = zIndex or 1
	label.Parent = parent
	return label
end

-- Restyles a UI.Tile as a Secret tile: dark cosmic body, rainbow rim and pedestal, white title, sparkles
-- (label: the pedestal text, "SECRET" by default)
function Secret.StyleTile(tile, discovered: boolean, label: string?)
	local body = tile.Body
	body.BackgroundColor3 = Color3.new(1, 1, 1)
	local shade = Instance.new("UIGradient")
	shade.Name = "SecretShade"
	shade.Color = ColorSequence.new(Secret.Top, Secret.Bottom)
	shade.Rotation = 90
	shade.Parent = body
	tile.Outline.Color = Secret.Edge
	local rim = Secret.Gradient(45)
	rim.Name = "SecretRim"
	rim.Parent = tile.Outline
	local face = tile.Pedestal:FindFirstChild("Face")
	local pedestalGradient = face and face:FindFirstChildOfClass("UIGradient")
	if pedestalGradient then
		pedestalGradient.Color = Secret.Rainbow()
		pedestalGradient.Rotation = 0
	end
	tile.Pedestal.BackgroundColor3 = Color3.fromRGB(30, 14, 60)
	tile.Title.TextColor3 = if discovered then Color3.new(1, 1, 1) else Color3.fromRGB(200, 180, 255)
	tile.RarityLabel.Text = label or "SECRET"
	local stroke = tile.RarityLabel:FindFirstChild("TextStroke")
	if stroke then
		stroke.Color = Color3.fromRGB(30, 14, 60)
	end
	local z = tile.Title.ZIndex
	Secret.Sparkle(tile.Lift, UDim2.new(0, 14, 0, 30), 12, Color3.fromRGB(255, 236, 140), z)
	Secret.Sparkle(tile.Lift, UDim2.new(1, -14, 0, 44), 9, Color3.fromRGB(150, 220, 255), z)
	Secret.Sparkle(tile.Lift, UDim2.new(0, 18, 0.62, 0), 8, Color3.fromRGB(255, 150, 230), z)
end

-- "1 in 250K": a secret pet's odds per hatch (chance: its Formulas.HatchChances chance, else the base odds)
function Secret.OddsText(petId: string, chance: number?): string
	local def = Pets.Pets[petId]
	return Format.Odds(chance or (if def and def.Odds then 1 / def.Odds else 0))
end

return Secret
