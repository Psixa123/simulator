--!nocheck
-- A tiny stand-in for the parts of the Roblox API that PetModels and PetController use, so their
-- logic can run under the plain `luau` command line (see run_mock_tests.py). Not a full emulation:
-- just enough math (Vector3, CFrame, Color3) and Instance behaviour (tree, Clone, attributes,
-- DescendantAdded/Removing) to build pets and check the numbers.

local realTypeof = typeof

------------------------------------------------------------------------ Vector3
local Vector3 = {}
local V3 = {}
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, __kind = "Vector3" }, V3)
end
V3.__index = function(v, key)
	if key == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif key == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return v3(v.X / m, v.Y / m, v.Z / m)
	elseif key == "Dot" then
		return function(a, b)
			return a.X * b.X + a.Y * b.Y + a.Z * b.Z
		end
	elseif key == "Cross" then
		return function(a, b)
			return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
		end
	end
	error("mock: Vector3." .. tostring(key) .. " is not supported", 2)
end
V3.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(v)
	return string.format("(%.3f, %.3f, %.3f)", v.X, v.Y, v.Z)
end
Vector3.new = v3
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)

------------------------------------------------------------------------ CFrame (position + 3x3 rotation)
local CFrame = {}
local CF = {}
local function cf(p, m)
	return setmetatable({ P = p, M = m, __kind = "CFrame" }, CF)
end
local IDENTITY = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
local function mulMM(a, b)
	local r = {}
	for i = 0, 2 do
		for j = 0, 2 do
			r[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
		end
	end
	return r
end
local function mulMV(m, v)
	return v3(m[1] * v.X + m[2] * v.Y + m[3] * v.Z, m[4] * v.X + m[5] * v.Y + m[6] * v.Z, m[7] * v.X + m[8] * v.Y + m[9] * v.Z)
end
local function transpose(m)
	return { m[1], m[4], m[7], m[2], m[5], m[8], m[3], m[6], m[9] }
end
local function inverse(c)
	local t = transpose(c.M)
	return cf(-mulMV(t, c.P), t)
end
CF.__index = function(c, key)
	if key == "Position" then
		return c.P
	elseif key == "Rotation" then
		return cf(Vector3.zero, c.M)
	elseif key == "X" then
		return c.P.X
	elseif key == "Y" then
		return c.P.Y
	elseif key == "Z" then
		return c.P.Z
	elseif key == "LookVector" then
		return v3(-c.M[3], -c.M[6], -c.M[9])
	elseif key == "RightVector" then
		return v3(c.M[1], c.M[4], c.M[7])
	elseif key == "UpVector" then
		return v3(c.M[2], c.M[5], c.M[8])
	elseif key == "Inverse" then
		return inverse
	elseif key == "ToObjectSpace" then
		return function(a, b)
			return inverse(a) * b
		end
	elseif key == "ToWorldSpace" then
		return function(a, b)
			return a * b
		end
	elseif key == "PointToObjectSpace" then
		return function(a, v)
			return mulMV(transpose(a.M), v - a.P)
		end
	elseif key == "PointToWorldSpace" then
		return function(a, v)
			return a.P + mulMV(a.M, v)
		end
	end
	error("mock: CFrame." .. tostring(key) .. " is not supported", 2)
end
CF.__mul = function(a, b)
	if b.__kind == "Vector3" then
		return a.P + mulMV(a.M, b)
	end
	return cf(a.P + mulMV(a.M, b.P), mulMM(a.M, b.M))
end
CF.__add = function(a, v)
	return cf(a.P + v, a.M)
end
CF.__sub = function(a, v)
	return cf(a.P - v, a.M)
end
CF.__tostring = function(c)
	return "CFrame" .. tostring(c.P)
end
function CFrame.new(x, y, z)
	if type(x) == "table" then
		return cf(x, IDENTITY)
	end
	return cf(v3(x or 0, y or 0, z or 0), IDENTITY)
end
function CFrame.Angles(rx, ry, rz)
	local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
	local mx = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
	local my = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
	local mz = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
	return cf(Vector3.zero, mulMM(mulMM(mx, my), mz))
end
function CFrame.lookAt(at, target)
	local look = (target - at).Unit
	local right = look:Cross(v3(0, 1, 0))
	if right.Magnitude < 1e-6 then
		right = v3(1, 0, 0)
	end
	right = right.Unit
	local up = right:Cross(look)
	return cf(at, { right.X, up.X, -look.X, right.Y, up.Y, -look.Y, right.Z, up.Z, -look.Z })
end

------------------------------------------------------------------------ Color3 and friends
local Color3 = {}
local C3 = {}
C3.__index = function(c, key)
	if key == "ToHSV" then
		return function(self)
			local r, g, b = self.R, self.G, self.B
			local max, min = math.max(r, g, b), math.min(r, g, b)
			local h, d = 0, max - min
			if d > 0 then
				if max == r then
					h = ((g - b) / d) % 6
				elseif max == g then
					h = (b - r) / d + 2
				else
					h = (r - g) / d + 4
				end
				h /= 6
			end
			return h, if max > 0 then d / max else 0, max
		end
	elseif key == "ToHex" then
		return function(self)
			return string.format("%02X%02X%02X", math.floor(self.R * 255 + 0.5), math.floor(self.G * 255 + 0.5), math.floor(self.B * 255 + 0.5))
		end
	end
	error("mock: Color3." .. tostring(key) .. " is not supported", 2)
end
C3.__eq = function(a, b)
	return math.abs(a.R - b.R) < 1e-6 and math.abs(a.G - b.G) < 1e-6 and math.abs(a.B - b.B) < 1e-6
end
C3.__tostring = function(c)
	return "#" .. c:ToHex()
end
function Color3.new(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0, __kind = "Color3" }, C3)
end
function Color3.fromRGB(r, g, b)
	return Color3.new(r / 255, g / 255, b / 255)
end
function Color3.fromHex(hex)
	hex = string.gsub(hex, "^#", "")
	assert(#hex == 6, "mock: bad hex " .. hex)
	return Color3.fromRGB(tonumber(string.sub(hex, 1, 2), 16), tonumber(string.sub(hex, 3, 4), 16), tonumber(string.sub(hex, 5, 6), 16))
end
function Color3.fromHSV(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	i %= 6
	if i == 0 then
		return Color3.new(v, t, p)
	elseif i == 1 then
		return Color3.new(q, v, p)
	elseif i == 2 then
		return Color3.new(p, v, t)
	elseif i == 3 then
		return Color3.new(p, q, v)
	elseif i == 4 then
		return Color3.new(t, p, v)
	end
	return Color3.new(v, p, q)
end

local function plain(kind)
	return {
		new = function(...)
			return { __kind = kind, Args = { ... } }
		end,
	}
end
local ColorSequence = plain("ColorSequence")
local ColorSequenceKeypoint = plain("ColorSequenceKeypoint")
local NumberSequence = plain("NumberSequence")
local NumberRange = plain("NumberRange")
local Vector2 = plain("Vector2")

local Enum = setmetatable({}, {
	__index = function(enums, enumName)
		local enum = setmetatable({}, {
			__index = function(items, itemName)
				local item = setmetatable({ Name = itemName, EnumType = enumName, __kind = "EnumItem" }, {
					__tostring = function()
						return "Enum." .. enumName .. "." .. itemName
					end,
				})
				rawset(items, itemName, item)
				return item
			end,
		})
		rawset(enums, enumName, enum)
		return enum
	end,
})

------------------------------------------------------------------------ Signals
local function newSignal()
	local signal = { Handlers = {} }
	function signal:Connect(fn)
		local handler = { Fn = fn }
		table.insert(self.Handlers, handler)
		return {
			Connected = true,
			Disconnect = function(connection)
				connection.Connected = false
				handler.Fn = nil
			end,
		}
	end
	function signal:Fire(...)
		for _, handler in self.Handlers do
			if handler.Fn then
				handler.Fn(...)
			end
		end
	end
	return signal
end

------------------------------------------------------------------------ Instances
local SUPER = {
	Part = "BasePart",
	MeshPart = "BasePart",
	BasePart = "PVInstance",
	Model = "PVInstance",
	PVInstance = "Instance",
	ModuleScript = "LuaSourceContainer",
	LuaSourceContainer = "Instance",
}
local SIGNALS = { DescendantAdded = true, DescendantRemoving = true, ChildAdded = true, ChildRemoved = true, AncestryChanged = true }
local Mock = { CloneCounts = setmetatable({}, { __mode = "k" }), Warnings = {}, Prints = {}, Preloads = {}, IsClient = true, IsStudio = true }

local Instance = {}
local IM = {}
local methods = {}

local function isA(className, target)
	local current = className
	while current do
		if current == target then
			return true
		end
		current = SUPER[current]
	end
	return target == "Instance"
end

function Instance.new(className, parent)
	local props = { Name = className, ClassName = className, Archivable = true }
	if isA(className, "BasePart") then
		props.Size = v3(4, 1, 2)
		props.CFrame = CFrame.new()
		props.Color = Color3.fromRGB(163, 162, 165)
		props.Transparency = 0
		props.Reflectance = 0
		props.Anchored = false
		props.CanCollide = true
		props.CanQuery = true
		props.CanTouch = true
		props.CastShadow = true
		props.Material = Enum.Material.Plastic
		props.MaterialVariant = ""
	end
	if className == "MeshPart" then
		props.MeshId = "rbxassetid://1"
		props.TextureID = ""
	end
	local object = setmetatable({ __kind = "Instance", __props = props, __children = {}, __attributes = {}, __signals = {} }, IM)
	if parent then
		object.Parent = parent
	end
	return object
end

local function forEachDescendant(object, fn)
	for _, child in object.__children do
		fn(child)
		forEachDescendant(child, fn)
	end
end

local function fireAncestors(object, signalName, subject)
	local node = rawget(object, "__parent")
	while node do
		local signal = node.__signals[signalName]
		if signal then
			signal:Fire(subject)
		end
		node = rawget(node, "__parent")
	end
end

local function setParent(object, parent)
	local old = rawget(object, "__parent")
	if old == parent then
		return
	end
	if old then
		fireAncestors(object, "DescendantRemoving", object)
		forEachDescendant(object, function(descendant)
			fireAncestors(object, "DescendantRemoving", descendant)
		end)
		local index = table.find(old.__children, object)
		if index then
			table.remove(old.__children, index)
		end
		if old.__signals.ChildRemoved then
			old.__signals.ChildRemoved:Fire(object)
		end
	end
	rawset(object, "__parent", parent)
	if parent then
		table.insert(parent.__children, object)
		if parent.__signals.ChildAdded then
			parent.__signals.ChildAdded:Fire(object)
		end
		fireAncestors(object, "DescendantAdded", object)
		forEachDescendant(object, function(descendant)
			fireAncestors(object, "DescendantAdded", descendant)
		end)
	end
end

IM.__index = function(self, key)
	if key == "Parent" then
		return rawget(self, "__parent")
	end
	local props = self.__props
	local value = props[key]
	if value ~= nil then
		return value
	end
	if key == "Position" and props.CFrame then
		return props.CFrame.Position
	end
	if methods[key] then
		return methods[key]
	end
	if SIGNALS[key] then
		local signal = self.__signals[key] or newSignal()
		self.__signals[key] = signal
		return signal
	end
	for _, child in self.__children do
		if child.Name == key then
			return child
		end
	end
	if key == "PrimaryPart" then
		return nil
	end
	error(string.format("mock: %s is not a valid member of %s %q", tostring(key), props.ClassName, props.Name), 2)
end

IM.__newindex = function(self, key, value)
	if key == "Parent" then
		setParent(self, value)
		return
	end
	local props = self.__props
	if key == "Position" then
		props.CFrame = props.CFrame.Rotation + value
		return
	end
	if key == "DoubleSided" and props.ClassName == "MeshPart" and not Mock.AllowDoubleSided then
		error("The current thread cannot write 'DoubleSided' (lacking capability Plugin)", 2)
	end
	props[key] = value
end

IM.__tostring = function(self)
	return self.__props.Name
end

function methods.IsA(self, className)
	return isA(self.__props.ClassName, className)
end
function methods.GetChildren(self)
	return table.clone(self.__children)
end
function methods.GetDescendants(self)
	local list = {}
	forEachDescendant(self, function(descendant)
		table.insert(list, descendant)
	end)
	return list
end
function methods.FindFirstChild(self, name)
	for _, child in self.__children do
		if child.Name == name then
			return child
		end
	end
	return nil
end
function methods.WaitForChild(self, name)
	return methods.FindFirstChild(self, name) or error("mock: WaitForChild would hang on " .. name, 2)
end
function methods.FindFirstChildOfClass(self, className)
	for _, child in self.__children do
		if child.ClassName == className then
			return child
		end
	end
	return nil
end
function methods.SetAttribute(self, name, value)
	self.__attributes[name] = value
end
function methods.GetAttribute(self, name)
	return self.__attributes[name]
end
function methods.ClearAllChildren(self)
	for _, child in table.clone(self.__children) do
		child.Parent = nil
	end
end
function methods.Destroy(self)
	self.Parent = nil
	rawset(self, "__destroyed", true)
end
local function clone(self)
	if not self.__props.Archivable or (Mock.BreakMeshClones and self.__props.ClassName == "MeshPart") then
		return nil
	end
	Mock.CloneCounts[self] = (Mock.CloneCounts[self] or 0) + 1
	local copy = setmetatable({ __kind = "Instance", __props = table.clone(self.__props), __children = {}, __attributes = table.clone(self.__attributes), __signals = {} }, IM)
	for _, child in self.__children do
		local childCopy = clone(child)
		if childCopy then
			rawset(childCopy, "__parent", copy)
			table.insert(copy.__children, childCopy)
		end
	end
	return copy
end
methods.Clone = clone
function methods.GetService(self, name)
	local service = methods.FindFirstChild(self, name)
	if not service then
		service = Instance.new(name)
		service.Parent = self
	end
	return service
end
function methods.IsStudio()
	return Mock.IsStudio
end
function methods.IsClient()
	return Mock.IsClient
end
function methods.IsServer()
	return not Mock.IsClient
end
function methods.PreloadAsync(self, list)
	table.insert(Mock.Preloads, list)
end

local game = Instance.new("DataModel")
game.Name = "Game"
local workspace = game:GetService("Workspace")

local function typeof(value)
	if type(value) == "table" and rawget(value, "__kind") then
		return rawget(value, "__kind")
	end
	return realTypeof(value)
end

local function warn(...)
	local parts = {}
	for _, value in { ... } do
		table.insert(parts, tostring(value))
	end
	table.insert(Mock.Warnings, table.concat(parts, " "))
end

local realPrint = print
local function print(...)
	local parts = {}
	for _, value in { ... } do
		table.insert(parts, tostring(value))
	end
	table.insert(Mock.Prints, table.concat(parts, " "))
end

local task = {
	spawn = function(fn, ...)
		fn(...)
	end,
	defer = function(fn, ...)
		fn(...)
	end,
	delay = function(_, fn, ...) -- runs at once; tests that care can swap it out
		fn(...)
	end,
	wait = function()
		return 0
	end,
}

-- ModuleScripts run a loader function(script) once, like require() in Roblox
local moduleResults = {}
local function require(module)
	if moduleResults[module] == nil then
		local loader = module.__props.Loader
		assert(loader, "mock: no loader for module " .. tostring(module))
		moduleResults[module] = loader(module)
	end
	return moduleResults[module]
end
function Mock.Module(name, parent, loader)
	local module = Instance.new("ModuleScript")
	module.Name = name
	module.Loader = loader
	module.Parent = parent
	return module
end
function Mock.Folder(name, parent)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end
Mock.RealPrint = realPrint
