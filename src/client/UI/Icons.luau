--!nonstrict
-- Every interface icon by key: the uploaded image's asset id (the glossy 3D icons rendered from
-- SketchUp, assets/ui/icons3d/<Key>.png, falling back to assets/ui/<Key>.png) and an emoji shown
-- until that image is uploaded. Upload an icon, put its id here, and every place that shows the
-- key switches to the picture.
--
--   Icons.New("Volts", { Size = UDim2.fromOffset(40, 40), Parent = frame })   -- image or emoji
--   Icons.Set(holder, "Lock")                                                 -- swap a shown icon
--   Icons.Image("Volts") -> "rbxassetid://..." or nil, Icons.Emoji("Volts") -> "⚡"
--
-- Keep one entry per line, key first: tools/preview_ui.py reads these lines to draw uploaded ids
-- with the matching picture in assets/ui. In the preview, --before can point an icon at a repo
-- picture: require(Client.UI.Icons).Volts.Image = "assets/ui/Volts.png".

local Icons = {
	Volts = { Id = 0, Emoji = "⚡" }, -- volt coin
	Energy = { Id = 0, Emoji = "💧" }, -- raindrop
	Pets = { Id = 0, Emoji = "🐾" }, -- paw
	Eggs = { Id = 0, Emoji = "🥚" }, -- spotted egg
	Shop = { Id = 0, Emoji = "🛍️" }, -- shopping bag
	Upgrades = { Id = 0, Emoji = "⬆️" }, -- green arrow
	Rewards = { Id = 0, Emoji = "🎁" }, -- gift box
	Teleport = { Id = 0, Emoji = "📍" }, -- map with pin
	ClimateShift = { Id = 0, Emoji = "🌀" }, -- swirl orb
	Settings = { Id = 0, Emoji = "⚙️" }, -- gear
	Index = { Id = 0, Emoji = "📖" }, -- book
	Radar = { Id = 0, Emoji = "📡" }, -- radar dish
	Lock = { Id = 0, Emoji = "🔒" }, -- padlock
	Check = { Id = 0, Emoji = "✅" }, -- check mark
	Star = { Id = 0, Emoji = "⭐" }, -- star
	Rainbow = { Id = 0, Emoji = "🌈" }, -- rainbow
	Luck = { Id = 0, Emoji = "🍀" }, -- clover
	Tank = { Id = 0, Emoji = "🛢️" }, -- storm jar
	Power = { Id = 0, Emoji = "💨" }, -- vacuum
	Range = { Id = 0, Emoji = "🎯" }, -- target
	Speed = { Id = 0, Emoji = "👟" }, -- winged boot
	Codes = { Id = 0, Emoji = "🎟️" }, -- ticket
	Daily = { Id = 0, Emoji = "📅" }, -- calendar
	MegaStorm = { Id = 0, Emoji = "🌪️" }, -- thundercloud / twister
	Sell = { Id = 0, Emoji = "💰" }, -- coin bag
	Gift = { Id = 0, Emoji = "🎁" }, -- small gift
	Boost = { Id = 0, Emoji = "🚀" }, -- rocket
	Close = { Id = 0, Emoji = "✖️" }, -- cross
}

-- Other names that mean the same icon (panel and menu keys, config names)
local ALIASES = {
	Egg = "Eggs",
	Rebirth = "ClimateShift",
	Shift = "ClimateShift",
	Shifts = "ClimateShift",
	Pet = "Pets",
	Boosts = "Boost",
	Gifts = "Gift",
	Coins = "Volts",
	Upgrade = "Upgrades",
	Vacuum = "Power",
	StormTank = "Tank",
	Storm = "MegaStorm",
	Zone = "Teleport",
}

local function entry(key: string?)
	if type(key) ~= "string" then
		return nil
	end
	local found = rawget(Icons, key)
	if type(found) ~= "table" then
		found = rawget(Icons, ALIASES[key] or "")
	end
	return if type(found) == "table" and found.Emoji then found else nil
end

-- The entry for a key (or alias), nil when it isn't an icon key
function Icons.Get(key: string?)
	return entry(key)
end

function Icons.Has(key: string?): boolean
	return entry(key) ~= nil
end

-- The image to show for a key: an uploaded asset id, or a preview override; nil = use the emoji
function Icons.Image(key: string?): string?
	local found = entry(key)
	if not found then
		return nil
	end
	if type(found.Image) == "string" and found.Image ~= "" then
		return found.Image
	end
	if type(found.Id) == "number" and found.Id > 0 then
		return "rbxassetid://" .. tostring(found.Id)
	end
	return nil
end

-- The emoji for a key; anything that isn't a key is taken as the emoji itself
function Icons.Emoji(key: string?): string
	local found = entry(key)
	if found then
		return found.Emoji
	end
	return if type(key) == "string" then key else ""
end

-- Shows a key (or a plain emoji) in a holder made by Icons.New
function Icons.Set(holder: GuiObject, key: string?)
	local image = holder:FindFirstChild("Image")
	local glyph = holder:FindFirstChild("Emoji")
	local picture = Icons.Image(key)
	if image then
		image.Image = picture or ""
		image.Visible = picture ~= nil
	end
	if glyph then
		glyph.Text = if picture then "" else Icons.Emoji(key)
		glyph.Visible = picture == nil
	end
	holder:SetAttribute("IconKey", key or "")
end

-- A square icon: the uploaded image when there is one, the emoji otherwise.
-- props: Size, Position, AnchorPoint, LayoutOrder, ZIndex, Name, Parent, Visible, Rotation,
-- EmojiScale (emoji size as a fraction of the box, default 0.84), ImageColor3, Transparency
function Icons.New(key: string?, props)
	props = props or {}
	local z = props.ZIndex or 1
	local holder = Instance.new("Frame")
	holder.Name = props.Name or "Icon"
	holder.BackgroundTransparency = 1
	holder.Size = props.Size or UDim2.fromOffset(40, 40)
	holder.Position = props.Position or UDim2.fromScale(0.5, 0.5)
	holder.AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5)
	holder.LayoutOrder = props.LayoutOrder or 0
	holder.Rotation = props.Rotation or 0
	holder.ZIndex = z
	if props.Visible == false then
		holder.Visible = false
	end
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = holder

	local image = Instance.new("ImageLabel")
	image.Name = "Image"
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.Size = UDim2.fromScale(1, 1)
	image.ZIndex = z
	image.ImageTransparency = props.Transparency or 0
	if props.ImageColor3 then
		image.ImageColor3 = props.ImageColor3
	end
	image.Parent = holder

	local scale = props.EmojiScale or 0.84
	local glyph = Instance.new("TextLabel")
	glyph.Name = "Emoji"
	glyph.BackgroundTransparency = 1
	glyph.Font = Enum.Font.FredokaOne
	glyph.TextScaled = true
	glyph.TextColor3 = Color3.new(1, 1, 1)
	glyph.TextTransparency = props.Transparency or 0
	glyph.Size = UDim2.fromScale(scale, scale)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.ZIndex = z
	glyph.Parent = holder

	Icons.Set(holder, key)
	if props.Parent then
		holder.Parent = props.Parent
	end
	return holder
end

-- Every icon key (for tools and tests)
function Icons.Keys(): { string }
	local keys = {}
	for key, value in Icons do
		if type(value) == "table" and value.Emoji then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	return keys
end

return Icons
