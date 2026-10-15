--!nonstrict
-- The SketchUp world prop kit (docs/STYLE_GUIDE.md "Prop kit") as ready-to-place models, for MapService.
-- Not a Registry service: MapService requires it and calls Place for every prop it puts in the world.
--
-- The meshes come from a pack made from assets/models/StormWorldProps.glb:
--   WorldProps > <PropId> > MeshParts "<PropId>.<Paint>" and "<PropId>.Root", a 1-stud cube on the prop's
--   origin (the centre of its base). Studs, Y up, front -Z. Paint = Primary | Secondary | Tertiary (tinted
--   per biome) | Color_RRGGBB | Neon_RRGGBB (glows) | Glass_RRGGBB (see-through).
-- Where the pack comes from (the first one found):
--   1. ServerStorage.WorldProps or ReplicatedStorage.WorldProps already in the place (imported in Studio,
--      or an .rbxm built in by Rojo)
--   2. GameConfig.WorldPropsAssetId (uploaded with tools/roblox/upload_model.py), inserted once with
--      InsertService into ServerStorage.WorldProps
-- Pieces are found at any depth, named "<PropId>.<Paint>" or "<Paint>" inside a model named after the prop
-- (importers nest, flatten or suffix names: "TreeRound_Primary", "Primary.001" work too). Each prop is
-- normalised by its Root cube into a template at unit scale (without a Root, its bounding box and the
-- Size/Center in WorldPropsData stand in) and turned to face -Z if the importer turned it around. A prop
-- needs an entry in Config/WorldPropsData (generated with the pack) for its default paints and collision.
--
-- WorldProps.Load() -> boolean     finds or inserts the pack and reads it, once (yields while inserting);
--                                  true when any prop can be placed. Has/Ids/Place call it as needed.
-- WorldProps.Has(propId) -> boolean
-- WorldProps.Ids() -> { string }   the props that can be placed (WorldPropsData.Order first)
-- WorldProps.Place(propId, parent, cframe, options?) -> Model?
--   cframe              where the prop's origin (the centre of its base) goes; the front faces its -Z
--   options.Scale       number or Vector3 (default 1)
--   options.Paints      colours by paint name, e.g. { Primary = Color3, Secondary = Color3, Tertiary = Color3 }
--                       (default: WorldPropsData's Paints; fixed Color_/Neon_/Glass_ paints can be overridden too)
--   options.Collide     true = every piece solid, false = none, nil = WorldPropsData's per-piece Collide
--   options.CastShadow  default: only props at least 6 studs big (after scaling) cast shadows
--   options.Anchor      false = no "Root" anchor part (one part fewer per prop; the model's WorldPivot is
--                       still `cframe`)
--   Returns nil when the prop, the pack or WorldPropsData is missing, so MapService can build its
--   part-built prop instead. The model (named <PropId>) holds MeshParts "<PropId>.<Paint>"; its
--   PrimaryPart is an invisible "Root" part at `cframe`.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))

export type PlaceOptions = {
	Scale: (number | Vector3)?,
	Paints: { [string]: Color3 }?,
	Collide: boolean?,
	CastShadow: boolean?,
	Anchor: boolean?,
}

local WorldProps = {}

local PACK_NAME = "WorldProps"
local DATA_NAME = "WorldPropsData"
local ATTEMPTS = 3
local RETRY_DELAY = 1 -- seconds, times the attempt number
local SHADOW_SIZE = 6 -- studs: smaller props (largest dimension) cast no shadow
local GLASS_TRANSPARENCY = 0.35
local ANCHOR_SIZE = Vector3.new(0.2, 0.2, 0.2)
local MAX_PIECES = 64
local MAX_SIZE = 2048 -- studs at unit scale; bigger means a broken scale
local TURN_MIN_ERROR = 0.25 -- studs (RMS) the pieces must be off before the pack is turned around

local KINDS = { color = "Color", neon = "Neon", glass = "Glass" } -- fixed paints, lower-case prefix -> kind
local TINTS = { primary = "Primary", secondary = "Secondary", tertiary = "Tertiary" }
local MATERIALS = {
	Tint = Enum.Material.SmoothPlastic,
	Color = Enum.Material.SmoothPlastic,
	Neon = Enum.Material.Neon,
	Glass = Enum.Material.Glass,
}
local TURNS = { 0, math.pi / 2, math.pi, math.pi * 1.5 } -- about Y; odd entries keep X and Z, even swap them
local TURN_FRAMES = {}
for index, angle in TURNS do
	TURN_FRAMES[index] = CFrame.Angles(0, angle, 0)
end
local NO_OPTIONS = {}

local state = {
	Loaded = false,
	Loading = false,
	Templates = {}, -- [propId] = { Id, Pieces = { { Part, Paint, Offset, Size, Color, Collide, Axes? } }, Size, Largest }
	Ids = {},
}

local function studioWarn(message: string)
	if RunService:IsStudio() then
		warn("[WorldProps] " .. message)
	end
end

local function studioPrint(message: string)
	if RunService:IsStudio() then
		print("[WorldProps] " .. message)
	end
end

-------------------------------------------------------------------------------- reading the pack

-- "Primary" -> "Primary", "Tint"; "Neon_fff3b0.001" -> "Neon_FFF3B0", "Neon", Color3; "Root" -> "Root", "Root".
-- Tolerates importer suffixes (".001", "_2", "Mesh").
local function parsePaint(name: string): (string?, string?, Color3?)
	local prefix, hex = string.match(name, "^(%a+)_(%x%x%x%x%x%x)")
	local kind = prefix and KINDS[string.lower(prefix)]
	if kind then
		hex = string.upper(hex)
		return kind .. "_" .. hex, kind, Color3.fromHex(hex)
	end
	local word = string.match(name, "^(%a+)")
	if not word then
		return nil
	end
	word = string.lower(word)
	if word == "root" then
		return "Root", "Root", nil
	end
	local tint = TINTS[word]
	if tint then
		return tint, "Tint", nil
	end
	return nil
end

-- "TreeRound.Primary" -> "TreeRound", "Primary" (also "TreeRound_Primary"); the longest known prop id wins
local function splitName(name: string, ids): (string?, string?)
	local found, rest
	local start = 1
	while true do
		local at = string.find(name, "[%._]", start)
		if not at then
			return found, rest
		end
		local id = ids[string.lower(string.sub(name, 1, at - 1))]
		if id then
			found, rest = id, string.sub(name, at + 1)
		end
		start = at + 1
	end
end

-- The prop a pack part belongs to and its paint name: "<PropId>.<Paint>", or a part inside a "<PropId>"
-- model (directly or inside a "<Paint>" or "<PropId>.<Paint>" model the importer made for the mesh)
local function locate(part: Instance, source: Instance, ids): (string?, string?)
	local propId, rest = splitName(part.Name, ids)
	if propId then
		return propId, rest
	end
	local name = part.Name
	local node = part.Parent
	while node and node ~= source do
		local nodeName = node.Name
		propId = ids[string.lower(nodeName)]
		if propId then
			return propId, name
		end
		if not parsePaint(name) then
			propId, rest = splitName(nodeName, ids)
			if propId then
				return propId, rest
			end
			name = nodeName
		end
		node = node.Parent
	end
	return nil, nil
end

local function finite(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) + math.abs(v.Y) + math.abs(v.Z) < math.huge
end

local function isVector(value): boolean
	return typeof(value) == "Vector3"
end

-- Size of a box with this rotation and size along the axes of the space its rotation is in
local function extents(cframe: CFrame, size: Vector3): Vector3
	local r, u, l = cframe.RightVector, cframe.UpVector, cframe.LookVector
	return Vector3.new(
		math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z,
		math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z,
		math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z
	)
end

-- Bounding box (min, max) of boxes given as { CFrame, Size } pairs relative to `frame`
local function bounds(boxes, frame: CFrame): (Vector3, Vector3)
	local x0, y0, z0 = math.huge, math.huge, math.huge
	local x1, y1, z1 = -math.huge, -math.huge, -math.huge
	for _, box in boxes do
		local cframe = frame:ToObjectSpace(box[1])
		local half = extents(cframe, box[2]) / 2
		local p = cframe.Position
		x0, y0, z0 = math.min(x0, p.X - half.X), math.min(y0, p.Y - half.Y), math.min(z0, p.Z - half.Z)
		x1, y1, z1 = math.max(x1, p.X + half.X), math.max(y1, p.Y + half.Y), math.max(z1, p.Z + half.Z)
	end
	return Vector3.new(x0, y0, z0), Vector3.new(x1, y1, z1)
end

local function isAxisAligned(cframe: CFrame): boolean
	local r, u = cframe.RightVector, cframe.UpVector
	return math.abs(r.X - 1) < 1e-4 and math.abs(u.Y - 1) < 1e-4
end

-- Adds how far one prop's pieces are from WorldPropsData under each turn in TURNS (sums of squares) to
-- errors; returns how many pieces were compared (pieces sharing a paint can't be told apart, so not those)
local function addTurnErrors(prop, errors): number
	local counts = {}
	for _, piece in prop.Pieces do
		counts[piece.Paint] = (counts[piece.Paint] or 0) + 1
	end
	local matched = 0
	for _, piece in prop.Pieces do
		local data = prop.DataPieces[piece.Paint]
		if data and counts[piece.Paint] == 1 and isVector(data.Center) and isVector(data.Size) then
			matched += 1
			local cframe = prop.Frame:ToObjectSpace(piece.Part.CFrame)
			local position = cframe.Position * prop.Factor
			local size = extents(cframe, piece.Part.Size) * prop.Factor
			local center = data.Center - prop.Reference
			for index, turn in TURN_FRAMES do
				local turnedSize = if index % 2 == 0 then Vector3.new(size.Z, size.Y, size.X) else size
				errors[index] += (turn:PointToObjectSpace(position) - center).Magnitude ^ 2 + (turnedSize - data.Size).Magnitude ^ 2
			end
		end
	end
	return matched
end

-- Which turn about Y (0, 90, 180 or 270 degrees) lines the pack up with WorldPropsData. Some importers
-- turn models around ("World Forward") and bake that into the meshes. An importer turns every prop the
-- same way, so the props vote together (a round prop alone can't tell); kept as it is unless clearly off.
local function findTurn(props): number
	local errors = { 0, 0, 0, 0 }
	local matched = 0
	for _, prop in props do
		matched += addTurnErrors(prop, errors)
	end
	if matched == 0 then
		return 0
	end
	local best = 1
	for index = 2, #TURNS do
		if errors[index] < errors[best] then
			best = index
		end
	end
	if best ~= 1 and math.sqrt(errors[1] / matched) > TURN_MIN_ERROR and errors[best] < errors[1] * 0.25 then
		return TURNS[best]
	end
	return 0
end

-- Sorts one prop's pack parts into pieces and finds its Root cube (or a stand-in). Returns nil, reason
-- if broken.
local function gather(propId: string, list, info, rootSize: number)
	local root
	local pieces = {}
	for _, entry in list do
		local paint, kind, color = parsePaint(entry.Name)
		if not paint then
			studioWarn(
				`ignoring "{entry.Name}" in {propId} (not a paint: Primary, Secondary, Tertiary, `
					.. "Color_RRGGBB, Neon_RRGGBB, Glass_RRGGBB or Root)"
			)
		elseif kind == "Root" then
			if root then
				return nil, "has more than one Root cube"
			end
			root = entry.Part
		else
			table.insert(pieces, { Part = entry.Part, Paint = paint, Kind = kind, Color = color })
		end
	end
	if #pieces == 0 or #pieces > MAX_PIECES then
		return nil, `has {#pieces} pieces`
	end

	local dataPieces = {}
	if type(info.Pieces) == "table" then
		for _, piece in info.Pieces do
			if type(piece) == "table" and type(piece.Paint) == "string" then
				dataPieces[piece.Paint] = piece
			end
		end
	end

	-- frame: the reference point in the pack; factor: pack units -> studs; reference: where that point
	-- is relative to the prop's origin
	local frame, factor, reference
	if root then
		local size = root.Size.X
		if not (size > 1e-4 and size < 1e4) then
			return nil, "has a Root cube with a broken size"
		end
		frame, factor, reference = root.CFrame, rootSize / size, Vector3.zero
	else
		local boxes = {}
		for _, piece in pieces do
			table.insert(boxes, { piece.Part.CFrame, piece.Part.Size })
		end
		local low, high = bounds(boxes, CFrame.new())
		local measured = high - low
		local centre = (low + high) / 2
		if isVector(info.Size) and isVector(info.Center) and measured.Magnitude > 1e-4 then
			frame, factor, reference = CFrame.new(centre), info.Size.Magnitude / measured.Magnitude, info.Center
		else
			frame, factor, reference = CFrame.new(centre.X, low.Y, centre.Z), 1, Vector3.zero
		end
		studioWarn(`{propId} has no Root cube; placing it by its bounding box`)
	end
	return {
		Id = propId,
		Info = info,
		Pieces = pieces,
		DataPieces = dataPieces,
		Frame = frame,
		Factor = factor,
		Reference = reference,
	}
end

-- Turns a gathered prop into a template: cleaned-up copies of the meshes with their offsets and sizes
-- at unit scale around the prop's origin. Returns nil, reason if broken.
local function build(prop, turn: number)
	local info, dataPieces, factor = prop.Info, prop.DataPieces, prop.Factor
	local origin = prop.Frame * CFrame.Angles(0, turn, 0) * CFrame.new(-prop.Reference / factor)

	local template = { Id = prop.Id, Pieces = {} }
	local boxes = {}
	for _, piece in prop.Pieces do
		local part = piece.Part
		local relative = origin:ToObjectSpace(part.CFrame)
		local offset = relative.Rotation + relative.Position * factor
		local size = part.Size * factor
		if not (finite(offset.Position) and finite(size)) or offset.Position.Magnitude > MAX_SIZE or size.Magnitude > MAX_SIZE then
			return nil, `has a broken "{piece.Paint}" piece (is the Root cube scaled like the rest?)`
		end

		local copy = part:Clone()
		if not copy then
			return nil, `has a "{piece.Paint}" piece that can't be copied (Archivable is off)`
		end
		copy.Name = prop.Id .. "." .. piece.Paint -- as in the pack (and its MeshId stays the pack's)
		copy:ClearAllChildren() -- SurfaceAppearances, welds etc. from the importer
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanQuery = false
		copy.CanTouch = false
		copy.CastShadow = false
		copy.Material = MATERIALS[piece.Kind]
		copy.MaterialVariant = ""
		copy.Reflectance = 0
		copy.Transparency = if piece.Kind == "Glass" then GLASS_TRANSPARENCY else 0
		copy.Size = size
		if copy:IsA("MeshPart") then
			pcall(function()
				if copy.TextureID ~= "" then
					copy.TextureID = "" -- a texture would hide the paint colour
				end
			end)
		end

		-- Default colour: a tint from WorldPropsData's Paints (or its piece), else the pack's own colour;
		-- a fixed paint from its name
		local data = dataPieces[piece.Paint]
		local color = piece.Color
		if piece.Kind == "Tint" then
			local paints = info.Paints
			color = (type(paints) == "table" and paints[piece.Paint]) or (data and data.Color) or part.Color
		end
		local collide
		if data and type(data.Collide) == "boolean" then
			collide = data.Collide
		else
			collide = info.Collide == true and piece.Kind ~= "Neon" and piece.Kind ~= "Glass"
		end

		table.insert(template.Pieces, {
			Part = copy,
			Paint = piece.Paint,
			Offset = offset,
			Size = size,
			Color = color,
			Collide = collide,
			-- the piece's axes in prop space when it's rotated (stretching it by a Vector3 scale)
			Axes = if isAxisAligned(offset) then nil else { offset.RightVector, offset.UpVector, offset.LookVector },
		})
		table.insert(boxes, { offset, size })
	end

	local low, high = bounds(boxes, CFrame.new())
	template.Size = high - low
	template.Largest = math.max(template.Size.X, template.Size.Y, template.Size.Z)
	if isVector(info.Size) and info.Size.Magnitude > 0 then
		local ratio = template.Size.Magnitude / info.Size.Magnitude
		if ratio > 1.5 or ratio < 1 / 1.5 then
			studioWarn(
				string.format("%s is %.2f times the size WorldPropsData expects (is the Root cube scaled like the rest?)", prop.Id, ratio)
			)
		end
	end
	return template
end

-- Reads every prop's template from the pack
local function readPack(source: Instance, data)
	local ids = {} -- lower-case id -> id
	for id in data.Props do
		ids[string.lower(id)] = id
	end

	local lists = {}
	for _, descendant in source:GetDescendants() do
		if descendant:IsA("BasePart") then
			local propId, name = locate(descendant, source, ids)
			if propId then
				lists[propId] = lists[propId] or {}
				table.insert(lists[propId], { Part = descendant, Name = name })
			end
		end
	end

	local rootSize = tonumber(data.RootSize) or 1
	local props = {}
	for propId, list in lists do
		local ok, prop, reason = pcall(gather, propId, list, data.Props[propId], rootSize)
		if not ok then
			prop, reason = nil, "can't be read (" .. tostring(prop) .. ")"
		end
		if prop then
			props[propId] = prop
		else
			studioWarn(`{propId} {reason}; the map builds it from parts`)
		end
	end

	local turn = findTurn(props)
	if turn ~= 0 then
		local degrees = math.floor(math.deg(turn) + 0.5)
		studioPrint(`the pack is turned {degrees} degrees (the importer's World Forward?); turning the props back to face -Z`)
	end
	local templates = {}
	for propId, prop in props do
		local ok, template, reason = pcall(build, prop, turn)
		if not ok then
			template, reason = nil, "can't be read (" .. tostring(template) .. ")"
		end
		if template then
			templates[propId] = template
		else
			studioWarn(`{propId} {reason}; the map builds it from parts`)
		end
	end

	-- WorldPropsData.Order first, then the rest by name
	local order, listed = {}, {}
	if type(data.Order) == "table" then
		for _, id in data.Order do
			if templates[id] and not listed[id] then
				listed[id] = true
				table.insert(order, id)
			end
		end
	end
	local rest = {}
	for id in templates do
		if not listed[id] then
			table.insert(rest, id)
		end
	end
	table.sort(rest)
	table.move(rest, 1, #rest, #order + 1, order)

	local missing = {}
	for id in data.Props do
		if not templates[id] then
			table.insert(missing, id)
		end
	end
	table.sort(missing)
	state.Templates = templates
	state.Ids = order
	if #order == 0 then
		studioWarn(`{source.Name} has no props this game can use (expected WorldProps > <PropId> > "<PropId>.<Paint>" meshes)`)
	elseif #missing > 0 then
		studioPrint(`mesh props: {#order}/{#order + #missing}; built from parts: {table.concat(missing, ", ")}`)
	else
		studioPrint(`mesh props: all {#order}`)
	end
end

-------------------------------------------------------------------------------- loading

local function findPack(): Instance?
	return ServerStorage:FindFirstChild(PACK_NAME) or ReplicatedStorage:FindFirstChild(PACK_NAME)
end

-- Config/WorldPropsData, or nil and what's wrong with it
local function loadData()
	local module = Config:FindFirstChild(DATA_NAME)
	if not module then
		return nil, `Config.{DATA_NAME} is missing`
	end
	local ok, data = pcall(require, module)
	if ok and type(data) == "table" and type(data.Props) == "table" then
		return data, nil
	end
	return nil, `Config.{DATA_NAME} can't be read ({if ok then "no Props table" else tostring(data)})`
end

-- Inserts the uploaded pack into ServerStorage.WorldProps (a few tries)
local function insertPack(assetId: number): Instance?
	local lastError
	for attempt = 1, ATTEMPTS do
		local ok, result = pcall(InsertService.LoadAsset, InsertService, assetId)
		if ok and result then
			local existing = findPack()
			if existing then
				result:Destroy() -- a pack turned up while loading
				return existing
			end
			-- LoadAsset wraps the asset in a Model; keep its contents (the props are found at any depth)
			local pack = Instance.new("Folder")
			pack.Name = PACK_NAME
			for _, child in result:GetChildren() do
				child.Parent = pack
			end
			result:Destroy()
			pack.Parent = ServerStorage
			return pack
		end
		lastError = result
		if attempt < ATTEMPTS then
			task.wait(RETRY_DELAY * attempt)
		end
	end
	studioWarn(
		`couldn't load the world prop pack {assetId} ({tostring(lastError)}); the map builds its props from parts. `
			.. "The model must belong to the game's owner (the same user or group)."
	)
	return nil
end

local function loadAll()
	local source = findPack()
	local assetId = tonumber(GameConfig.WorldPropsAssetId)
	if not source and not (assetId and assetId > 0) then
		return -- no pack: the map builds its props from parts
	end
	local data, problem = loadData()
	if not data then
		studioWarn(`{problem}, so the world prop pack isn't used; the map builds its props from parts`)
		return
	end
	if not source then
		source = insertPack(assetId)
	end
	if source then
		readPack(source, data)
	end
end

function WorldProps.Load(): boolean
	while state.Loading do
		task.wait() -- another thread is inserting the pack
	end
	if not state.Loaded then
		state.Loading = true
		local ok, err = pcall(loadAll)
		if not ok then
			state.Templates, state.Ids = {}, {}
			studioWarn(`couldn't read the world prop pack ({tostring(err)}); the map builds its props from parts`)
		end
		state.Loading = false
		state.Loaded = true
	end
	return #state.Ids > 0
end

function WorldProps.Has(propId: string): boolean
	WorldProps.Load()
	return state.Templates[propId] ~= nil
end

function WorldProps.Ids(): { string }
	WorldProps.Load()
	return table.clone(state.Ids)
end

-------------------------------------------------------------------------------- placing

-- A piece's size stretched by a Vector3 scale given in prop space
local function stretch(piece, scale: Vector3): Vector3
	local axes = piece.Axes
	if not axes then
		return piece.Size * scale
	end
	return Vector3.new(
		piece.Size.X * (axes[1] * scale).Magnitude,
		piece.Size.Y * (axes[2] * scale).Magnitude,
		piece.Size.Z * (axes[3] * scale).Magnitude
	)
end

function WorldProps.Place(propId: string, parent: Instance?, cframe: CFrame, options: PlaceOptions?): Model?
	WorldProps.Load()
	local template = state.Templates[propId]
	if not template then
		return nil
	end
	local opts = options or NO_OPTIONS

	-- Scale: a number (uniform) or a Vector3; anything else (or not positive) counts as 1
	local scale, vector = 1, nil
	local given = opts.Scale
	if type(given) == "number" then
		scale = if given > 0 and given < math.huge then given else 1
	elseif isVector(given) and given.X > 0 and given.Y > 0 and given.Z > 0 and finite(given) then
		if given.X == given.Y and given.Y == given.Z then
			scale = given.X
		else
			vector = given
		end
	end

	local largest = if vector
		then math.max(template.Size.X * vector.X, template.Size.Y * vector.Y, template.Size.Z * vector.Z)
		else template.Largest * scale
	local castShadow = if opts.CastShadow ~= nil then opts.CastShadow == true else largest >= SHADOW_SIZE
	local paints = if type(opts.Paints) == "table" then opts.Paints else nil
	local collide = opts.Collide

	local model = Instance.new("Model")
	model.Name = propId
	if opts.Anchor == false then
		model.WorldPivot = cframe
	else
		local anchor = Instance.new("Part")
		anchor.Name = "Root"
		anchor.Size = ANCHOR_SIZE
		anchor.Transparency = 1
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.CastShadow = false
		anchor.CFrame = cframe
		anchor.Parent = model
		model.PrimaryPart = anchor
	end

	for _, piece in template.Pieces do
		local part = piece.Part:Clone()
		local offset = piece.Offset
		if vector then
			part.Size = stretch(piece, vector)
			offset = offset.Rotation + offset.Position * vector
		elseif scale ~= 1 then
			part.Size = piece.Size * scale -- a MeshPart stretches its mesh to its Size
			offset = offset.Rotation + offset.Position * scale
		end
		part.CFrame = cframe * offset
		part.Color = (paints and paints[piece.Paint]) or piece.Color
		local solid = if collide == nil then piece.Collide else collide
		if solid then
			part.CanCollide = true
			part.CanQuery = true
			part.CanTouch = true
		end
		if castShadow then
			part.CastShadow = true
		end
		part.Parent = model
	end

	if parent then
		model.Parent = parent
	end
	return model
end

return WorldProps
