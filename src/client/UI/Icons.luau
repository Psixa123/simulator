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
	Volts = { Id = 124885999776457, Emoji = "⚡" }, -- volt coin
	Energy = { Id = 93164191801686, Emoji = "💧" }, -- raindrop
	Pets = { Id = 108195676300187, Emoji = "🐾" }, -- paw
	Eggs = { Id = 76752882488209, Emoji = "🥚" }, -- spotted egg
	Shop = { Id = 140528433367615, Emoji = "🛍️" }, -- shopping bag
	Upgrades = { Id = 107463561239039, Emoji = "⬆️" }, -- green arrow
	Rewards = { Id = 121830471915641, Emoji = "🎁" }, -- gift box
	Teleport = { Id = 81050004043307, Emoji = "📍" }, -- map with pin
	ClimateShift = { Id = 119245140810178, Emoji = "🌀" }, -- swirl orb
	Settings = { Id = 91818865654166, Emoji = "⚙️" }, -- gear
	Index = { Id = 87920753461445, Emoji = "📖" }, -- book
	Radar = { Id = 99222235630116, Emoji = "📡" }, -- radar dish
	Lock = { Id = 119190543918004, Emoji = "🔒" }, -- padlock
	Check = { Id = 104893568367190, Emoji = "✅" }, -- check mark
	Star = { Id = 87166089920157, Emoji = "⭐" }, -- star
	Rainbow = { Id = 129501797577068, Emoji = "🌈" }, -- rainbow
	Luck = { Id = 130879040393802, Emoji = "🍀" }, -- clover
	Tank = { Id = 111774116838157, Emoji = "🛢️" }, -- storm jar
	Power = { Id = 120941314241479, Emoji = "💨" }, -- vacuum
	Range = { Id = 71229855299748, Emoji = "🎯" }, -- target
	Speed = { Id = 101080847056668, Emoji = "👟" }, -- winged boot
	Codes = { Id = 99495361265124, Emoji = "🎟️" }, -- ticket
	Daily = { Id = 84002661292585, Emoji = "📅" }, -- calendar
	MegaStorm = { Id = 79806772234669, Emoji = "🌪️" }, -- thundercloud / twister
	Sell = { Id = 121516565619665, Emoji = "💰" }, -- coin bag
	Gift = { Id = 126027840891767, Emoji = "🎁" }, -- small gift
	Boost = { Id = 75840590772147, Emoji = "🚀" }, -- rocket
	Close = { Id = 87698644308982, Emoji = "✖️" }, -- cross
	-- Zone emblems (Zone_<Zones key>, assets/ui/icons3d/Zone_*.png): the medallions on the zone title card
	Zone_Hub = { Id = 133610062922415, Emoji = "🏠" }, -- domed lab on a cloud, assets/ui/icons3d/Zone_Hub.png
	Zone_Meadows = { Id = 116632794687034, Emoji = "🌤️" }, -- sun over clover hills, assets/ui/icons3d/Zone_Meadows.png
	Zone_Thunder = { Id = 134290172168455, Emoji = "⛈️" }, -- thundercloud and bolt, assets/ui/icons3d/Zone_Thunder.png
	Zone_Dunes = { Id = 120624641542430, Emoji = "🏜️" }, -- dunes, sun and cactus, assets/ui/icons3d/Zone_Dunes.png
	Zone_Frost = { Id = 119712892235288, Emoji = "🏔️" }, -- snowy peak and snowflake, assets/ui/icons3d/Zone_Frost.png
	Zone_Volcano = { Id = 89497526966054, Emoji = "🌋" }, -- volcano, assets/ui/icons3d/Zone_Volcano.png
	Zone_Sky = { Id = 84996680465372, Emoji = "🌌" }, -- ringed planet, assets/ui/icons3d/Zone_Sky.png
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
