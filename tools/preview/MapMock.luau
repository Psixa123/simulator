--!nocheck
-- MapMock: a stand-in for the parts of the Roblox engine that MapService uses, so the real map builder
-- runs under the plain `luau` command line and its world can be dumped as JSON and rendered
-- (tools/preview_map.py bundles this file + the game's modules + a short runner and runs it).
--
-- Not a full emulation: datatypes with real math (Vector3, CFrame, Color3, UDim2, ...), an Instance
-- tree with typed properties, services, Terrain fill recording, a deterministic task scheduler on a
-- simulated clock, and a JSON dump of Workspace (parts, terrain fills, lighting, gui text).
--
-- Unknown classes, properties, methods, services and badly typed values FAIL LOUDLY with a message that
-- names the member, so gaps are easy to spot and fix: add the property to CLASSES below (with its
-- default value) or the method to the class's method table.

local Mock = {
	Warnings = {},
	Prints = {},
	Errors = {},
	Fills = {},
	MaterialColors = {},
	Now = 0, -- simulated seconds since the server started
	ClockBase = 1700000000,
	Pack = nil, -- WorldProps mesh pack (built from assets/models/StormWorldProps.glb by preview_map.py)
	Stats = { Instances = 0 },
}

local realTypeof = typeof
local realPrint = print
local realClock = os.clock
local fmt = string.format

-- Game code can pcall around a mock gap (WorldProps does), which would hide it, so every failure that
-- names something the mock lacks is also recorded in Mock.Gaps (with the game-code line that hit it) and
-- preview_map.py reports it even when the game caught the error. "x is not a valid member" can also be
-- a missing child (a real Roblox error), so those are recorded as Maybe.
Mock.Gaps = {}
local gapSeen = {}
local function recordGap(message)
	local maybe = string.find(message, "is not a valid member", 1, true) ~= nil
	local gap = maybe
		or string.find(message, "MapMock.luau", 1, true) ~= nil
		or string.find(message, "not supported", 1, true) ~= nil
		or string.find(message, "is not a valid property", 1, true) ~= nil
	if not gap then
		return
	end
	local where = nil
	for line in string.gmatch(debug.traceback(), "[^\n]+") do
		local source = string.match(line, "^%s*(.-:%d+)")
		if source and not string.find(source, "preview_bundle.luau", 1, true) then
			where = source
			break
		end
	end
	local key = message .. "|" .. tostring(where)
	if gapSeen[key] then
		return
	end
	gapSeen[key] = true
	table.insert(Mock.Gaps, { Message = "mock: " .. message, Where = where, Maybe = maybe })
end

local function fail(message, level)
	recordGap(message)
	error("mock: " .. message, (level or 1) + 1)
end

local function kindOf(value)
	if type(value) == "table" then
		local kind = rawget(value, "__kind")
		if kind then
			return kind
		end
	end
	return realTypeof(value)
end

local function freezeType(name, methods, getters)
	-- __index for immutable datatypes: methods, then computed getters, else a loud failure
	return function(self, key)
		local method = methods[key]
		if method ~= nil then
			return method
		end
		local getter = getters and getters[key]
		if getter then
			return getter(self)
		end
		fail(fmt("%s.%s is not supported (add it to tools/preview/MapMock.luau)", name, tostring(key)), 2)
	end
end

local function noAssign(name)
	return function(_, key)
		fail(fmt("cannot assign to %s.%s (datatypes are immutable)", name, tostring(key)), 2)
	end
end

---------------------------------------------------------------------------------------------------- Vector3
local Vector3 = {}
local V3 = { __kind = "Vector3" }
local V3methods = {}
local function v3(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z, __kind = "Vector3" }, V3)
end
local function isV3(value)
	return getmetatable(value) == V3
end
local V3getters = {
	Magnitude = function(v)
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	end,
	Unit = function(v)
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		if m == 0 then
			return v3(0 / 0, 0 / 0, 0 / 0)
		end
		return v3(v.X / m, v.Y / m, v.Z / m)
	end,
}
function V3methods.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3methods.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3methods.Lerp(a, b, t)
	return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
end
function V3methods.Abs(a)
	return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end
function V3methods.Floor(a)
	return v3(math.floor(a.X), math.floor(a.Y), math.floor(a.Z))
end
function V3methods.Ceil(a)
	return v3(math.ceil(a.X), math.ceil(a.Y), math.ceil(a.Z))
end
function V3methods.Sign(a)
	return v3(math.sign(a.X), math.sign(a.Y), math.sign(a.Z))
end
function V3methods.Min(a, ...)
	local x, y, z = a.X, a.Y, a.Z
	for _, b in { ... } do
		x, y, z = math.min(x, b.X), math.min(y, b.Y), math.min(z, b.Z)
	end
	return v3(x, y, z)
end
function V3methods.Max(a, ...)
	local x, y, z = a.X, a.Y, a.Z
	for _, b in { ... } do
		x, y, z = math.max(x, b.X), math.max(y, b.Y), math.max(z, b.Z)
	end
	return v3(x, y, z)
end
function V3methods.FuzzyEq(a, b, epsilon)
	epsilon = epsilon or 1e-5
	return math.abs(a.X - b.X) <= epsilon and math.abs(a.Y - b.Y) <= epsilon and math.abs(a.Z - b.Z) <= epsilon
end
function V3methods.Angle(a, b, axis)
	local cross = V3methods.Cross(a, b)
	local angle = math.atan2(V3getters.Magnitude(cross), V3methods.Dot(a, b))
	if axis and V3methods.Dot(cross, axis) < 0 then
		angle = -angle
	end
	return angle
end
V3.__index = freezeType("Vector3", V3methods, V3getters)
V3.__newindex = noAssign("Vector3")
V3.__add = function(a, b)
	if not (isV3(a) and isV3(b)) then
		fail(fmt("attempt to add %s and %s", kindOf(a), kindOf(b)), 2)
	end
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	if not (isV3(a) and isV3(b)) then
		fail(fmt("attempt to subtract %s and %s", kindOf(a), kindOf(b)), 2)
	end
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
	elseif isV3(a) and isV3(b) then
		return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
	end
	fail(fmt("attempt to multiply %s and %s", kindOf(a), kindOf(b)), 2)
end
V3.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	elseif type(a) == "number" then
		return v3(a / b.X, a / b.Y, a / b.Z)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__idiv = function(a, b)
	if type(b) == "number" then
		return v3(a.X // b, a.Y // b, a.Z // b)
	end
	return v3(a.X // b.X, a.Y // b.Y, a.Z // b.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(v)
	return fmt("%g, %g, %g", v.X, v.Y, v.Z)
end
Vector3.new = function(x, y, z)
	return v3(x or 0, y or 0, z or 0)
end
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)
local NORMALS = {
	Right = v3(1, 0, 0),
	Left = v3(-1, 0, 0),
	Top = v3(0, 1, 0),
	Bottom = v3(0, -1, 0),
	Back = v3(0, 0, 1),
	Front = v3(0, 0, -1),
}
Vector3.FromNormalId = function(normal)
	return NORMALS[normal.Name] or fail("Vector3.FromNormalId: bad NormalId " .. tostring(normal), 2)
end
Vector3.FromAxis = function(axis)
	local name = axis.Name
	return if name == "X" then Vector3.xAxis elseif name == "Y" then Vector3.yAxis else Vector3.zAxis
end
setmetatable(Vector3, { __index = freezeType("Vector3 (library)", {}) })

---------------------------------------------------------------------------------------------------- Vector2
local Vector2 = {}
local V2 = { __kind = "Vector2" }
local function v2(x, y)
	return setmetatable({ X = x, Y = y, __kind = "Vector2" }, V2)
end
local V2methods = {}
local V2getters = {
	Magnitude = function(v)
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	end,
	Unit = function(v)
		local m = math.sqrt(v.X * v.X + v.Y * v.Y)
		return v2(v.X / m, v.Y / m)
	end,
}
function V2methods.Dot(a, b)
	return a.X * b.X + a.Y * b.Y
end
function V2methods.Cross(a, b)
	return a.X * b.Y - a.Y * b.X
end
function V2methods.Lerp(a, b, t)
	return v2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t)
end
function V2methods.Abs(a)
	return v2(math.abs(a.X), math.abs(a.Y))
end
function V2methods.Min(a, b)
	return v2(math.min(a.X, b.X), math.min(a.Y, b.Y))
end
function V2methods.Max(a, b)
	return v2(math.max(a.X, b.X), math.max(a.Y, b.Y))
end
function V2methods.Floor(a)
	return v2(math.floor(a.X), math.floor(a.Y))
end
function V2methods.Ceil(a)
	return v2(math.ceil(a.X), math.ceil(a.Y))
end
function V2methods.Sign(a)
	return v2(math.sign(a.X), math.sign(a.Y))
end
function V2methods.FuzzyEq(a, b, epsilon)
	epsilon = epsilon or 1e-5
	return math.abs(a.X - b.X) <= epsilon and math.abs(a.Y - b.Y) <= epsilon
end
function V2methods.Angle(a, b, isSigned)
	local angle = math.atan2(V2methods.Cross(a, b), V2methods.Dot(a, b))
	return if isSigned then angle else math.abs(angle)
end
V2.__index = freezeType("Vector2", V2methods, V2getters)
V2.__newindex = noAssign("Vector2")
V2.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
V2.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
V2.__unm = function(a)
	return v2(-a.X, -a.Y)
end
V2.__mul = function(a, b)
	if type(a) == "number" then
		return v2(a * b.X, a * b.Y)
	elseif type(b) == "number" then
		return v2(a.X * b, a.Y * b)
	end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2.__div = function(a, b)
	if type(b) == "number" then
		return v2(a.X / b, a.Y / b)
	end
	return v2(a.X / b.X, a.Y / b.Y)
end
V2.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
V2.__tostring = function(v)
	return fmt("%g, %g", v.X, v.Y)
end
Vector2.new = function(x, y)
	return v2(x or 0, y or 0)
end
Vector2.zero = v2(0, 0)
Vector2.one = v2(1, 1)
Vector2.xAxis = v2(1, 0)
Vector2.yAxis = v2(0, 1)

---------------------------------------------------------------------------------------------------- CFrame
-- Stored as 12 numbers: position x, y, z and the rotation matrix R00 R01 R02 R10 R11 R12 R20 R21 R22
-- (columns are RightVector, UpVector and -LookVector, like Roblox's GetComponents()).
local CFrame = {}
local CF = { __kind = "CFrame" }
local function cf(x, y, z, a, b, c, d, e, f, g, h, i)
	return setmetatable({ x, y, z, a, b, c, d, e, f, g, h, i, __kind = "CFrame" }, CF)
end
local function isCF(value)
	return getmetatable(value) == CF
end
local function mulCF(A, B)
	local a, b, c, d, e, f, g, h, i = A[4], A[5], A[6], A[7], A[8], A[9], A[10], A[11], A[12]
	local x, y, z = B[1], B[2], B[3]
	local A_, B_, C_, D_, E_, F_, G_, H_, I_ = B[4], B[5], B[6], B[7], B[8], B[9], B[10], B[11], B[12]
	return cf(
		A[1] + a * x + b * y + c * z,
		A[2] + d * x + e * y + f * z,
		A[3] + g * x + h * y + i * z,
		a * A_ + b * D_ + c * G_,
		a * B_ + b * E_ + c * H_,
		a * C_ + b * F_ + c * I_,
		d * A_ + e * D_ + f * G_,
		d * B_ + e * E_ + f * H_,
		d * C_ + e * F_ + f * I_,
		g * A_ + h * D_ + i * G_,
		g * B_ + h * E_ + i * H_,
		g * C_ + h * F_ + i * I_
	)
end
local function pointToWorld(A, v)
	return v3(
		A[1] + A[4] * v.X + A[5] * v.Y + A[6] * v.Z,
		A[2] + A[7] * v.X + A[8] * v.Y + A[9] * v.Z,
		A[3] + A[10] * v.X + A[11] * v.Y + A[12] * v.Z
	)
end
local function vectorToWorld(A, v)
	return v3(A[4] * v.X + A[5] * v.Y + A[6] * v.Z, A[7] * v.X + A[8] * v.Y + A[9] * v.Z, A[10] * v.X + A[11] * v.Y + A[12] * v.Z)
end
local function vectorToObject(A, v)
	return v3(A[4] * v.X + A[7] * v.Y + A[10] * v.Z, A[5] * v.X + A[8] * v.Y + A[11] * v.Z, A[6] * v.X + A[9] * v.Y + A[12] * v.Z)
end
local function inverseCF(A)
	local px, py, pz = A[1], A[2], A[3]
	-- transpose of the rotation, position = -R^T p
	return cf(
		-(A[4] * px + A[7] * py + A[10] * pz),
		-(A[5] * px + A[8] * py + A[11] * pz),
		-(A[6] * px + A[9] * py + A[12] * pz),
		A[4], A[7], A[10],
		A[5], A[8], A[11],
		A[6], A[9], A[12]
	)
end
local function fromRotation(x, y, z, m)
	return cf(x, y, z, m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9])
end
local function matMul(a, b)
	local r = table.create(9)
	for row = 0, 2 do
		for col = 0, 2 do
			r[row * 3 + col + 1] = a[row * 3 + 1] * b[col + 1] + a[row * 3 + 2] * b[3 + col + 1] + a[row * 3 + 3] * b[6 + col + 1]
		end
	end
	return r
end
local function rotX(t)
	local c, s = math.cos(t), math.sin(t)
	return { 1, 0, 0, 0, c, -s, 0, s, c }
end
local function rotY(t)
	local c, s = math.cos(t), math.sin(t)
	return { c, 0, s, 0, 1, 0, -s, 0, c }
end
local function rotZ(t)
	local c, s = math.cos(t), math.sin(t)
	return { c, -s, 0, s, c, 0, 0, 0, 1 }
end
local function toQuaternion(A)
	local m00, m01, m02, m10, m11, m12, m20, m21, m22 = A[4], A[5], A[6], A[7], A[8], A[9], A[10], A[11], A[12]
	local trace = m00 + m11 + m22
	local qw, qx, qy, qz
	if trace > 0 then
		local s = math.sqrt(trace + 1) * 2
		qw, qx, qy, qz = s / 4, (m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s
	elseif m00 > m11 and m00 > m22 then
		local s = math.sqrt(1 + m00 - m11 - m22) * 2
		qw, qx, qy, qz = (m21 - m12) / s, s / 4, (m01 + m10) / s, (m02 + m20) / s
	elseif m11 > m22 then
		local s = math.sqrt(1 + m11 - m00 - m22) * 2
		qw, qx, qy, qz = (m02 - m20) / s, (m01 + m10) / s, s / 4, (m12 + m21) / s
	else
		local s = math.sqrt(1 + m22 - m00 - m11) * 2
		qw, qx, qy, qz = (m10 - m01) / s, (m02 + m20) / s, (m12 + m21) / s, s / 4
	end
	return qx, qy, qz, qw
end
local function fromQuaternion(x, y, z, qx, qy, qz, qw)
	local n = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
	if n == 0 then
		return cf(x, y, z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	qx, qy, qz, qw = qx / n, qy / n, qz / n, qw / n
	return cf(
		x, y, z,
		1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy - qz * qw), 2 * (qx * qz + qy * qw),
		2 * (qx * qy + qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz - qx * qw),
		2 * (qx * qz - qy * qw), 2 * (qy * qz + qx * qw), 1 - 2 * (qx * qx + qy * qy)
	)
end
local function lookAt(at, target, up)
	up = up or Vector3.yAxis
	local look = target - at
	local m = math.sqrt(look.X * look.X + look.Y * look.Y + look.Z * look.Z)
	if m < 1e-9 then
		return cf(at.X, at.Y, at.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	look = look / m
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		-- looking straight along `up`: pick any perpendicular right vector (Roblox does similar)
		right = look:Cross(Vector3.zAxis)
		if right.Magnitude < 1e-6 then
			right = look:Cross(Vector3.xAxis)
		end
	end
	right = right.Unit
	local up2 = right:Cross(look)
	return cf(at.X, at.Y, at.Z, right.X, up2.X, -look.X, right.Y, up2.Y, -look.Y, right.Z, up2.Z, -look.Z)
end

local CFmethods = {}
local CFgetters = {
	Position = function(c)
		return v3(c[1], c[2], c[3])
	end,
	p = function(c)
		return v3(c[1], c[2], c[3])
	end,
	X = function(c)
		return c[1]
	end,
	Y = function(c)
		return c[2]
	end,
	Z = function(c)
		return c[3]
	end,
	Rotation = function(c)
		return cf(0, 0, 0, c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
	end,
	LookVector = function(c)
		return v3(-c[6], -c[9], -c[12])
	end,
	RightVector = function(c)
		return v3(c[4], c[7], c[10])
	end,
	UpVector = function(c)
		return v3(c[5], c[8], c[11])
	end,
	XVector = function(c)
		return v3(c[4], c[7], c[10])
	end,
	YVector = function(c)
		return v3(c[5], c[8], c[11])
	end,
	ZVector = function(c)
		return v3(c[6], c[9], c[12])
	end,
}
function CFmethods.Inverse(c)
	return inverseCF(c)
end
function CFmethods.ToWorldSpace(c, ...)
	local results = {}
	for index, other in { ... } do
		results[index] = mulCF(c, other)
	end
	return table.unpack(results)
end
function CFmethods.ToObjectSpace(c, ...)
	local inverse = inverseCF(c)
	local results = {}
	for index, other in { ... } do
		results[index] = mulCF(inverse, other)
	end
	return table.unpack(results)
end
function CFmethods.PointToWorldSpace(c, ...)
	local results = {}
	for index, v in { ... } do
		results[index] = pointToWorld(c, v)
	end
	return table.unpack(results)
end
function CFmethods.PointToObjectSpace(c, ...)
	local results = {}
	for index, v in { ... } do
		results[index] = vectorToObject(c, v3(v.X - c[1], v.Y - c[2], v.Z - c[3]))
	end
	return table.unpack(results)
end
function CFmethods.VectorToWorldSpace(c, ...)
	local results = {}
	for index, v in { ... } do
		results[index] = vectorToWorld(c, v)
	end
	return table.unpack(results)
end
function CFmethods.VectorToObjectSpace(c, ...)
	local results = {}
	for index, v in { ... } do
		results[index] = vectorToObject(c, v)
	end
	return table.unpack(results)
end
function CFmethods.GetComponents(c)
	return c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12]
end
CFmethods.components = CFmethods.GetComponents
function CFmethods.ToEulerAnglesXYZ(c)
	local ry = math.asin(math.clamp(c[6], -1, 1))
	local rx, rz
	if math.abs(c[6]) < 0.9999999 then
		rx = math.atan2(-c[9], c[12])
		rz = math.atan2(-c[5], c[4])
	else
		rx = math.atan2(c[11], c[8])
		rz = 0
	end
	return rx, ry, rz
end
function CFmethods.ToEulerAnglesYXZ(c)
	local rx = math.asin(math.clamp(-c[9], -1, 1))
	local ry, rz
	if math.abs(c[9]) < 0.9999999 then
		ry = math.atan2(c[6], c[12])
		rz = math.atan2(c[7], c[8])
	else
		ry = math.atan2(-c[10], c[4])
		rz = 0
	end
	return rx, ry, rz
end
CFmethods.ToOrientation = CFmethods.ToEulerAnglesYXZ
function CFmethods.ToAxisAngle(c)
	local qx, qy, qz, qw = toQuaternion(c)
	local angle = 2 * math.acos(math.clamp(qw, -1, 1))
	local s = math.sqrt(math.max(1 - qw * qw, 0))
	if s < 1e-9 then
		return Vector3.xAxis, 0
	end
	return v3(qx / s, qy / s, qz / s), angle
end
function CFmethods.Lerp(a, b, t)
	local ax, ay, az, aw = toQuaternion(a)
	local bx, by, bz, bw = toQuaternion(b)
	local dot = ax * bx + ay * by + az * bz + aw * bw
	if dot < 0 then
		bx, by, bz, bw, dot = -bx, -by, -bz, -bw, -dot
	end
	local wa, wb
	if dot > 0.9995 then
		wa, wb = 1 - t, t
	else
		local theta = math.acos(dot)
		local s = math.sin(theta)
		wa, wb = math.sin((1 - t) * theta) / s, math.sin(t * theta) / s
	end
	return fromQuaternion(
		a[1] + (b[1] - a[1]) * t,
		a[2] + (b[2] - a[2]) * t,
		a[3] + (b[3] - a[3]) * t,
		ax * wa + bx * wb, ay * wa + by * wb, az * wa + bz * wb, aw * wa + bw * wb
	)
end
function CFmethods.Orthonormalize(c)
	local right = v3(c[4], c[7], c[10]).Unit
	local up = v3(c[5], c[8], c[11])
	local back = right:Cross(up).Unit
	up = back:Cross(right)
	return cf(c[1], c[2], c[3], right.X, up.X, back.X, right.Y, up.Y, back.Y, right.Z, up.Z, back.Z)
end
function CFmethods.FuzzyEq(a, b, epsilon)
	epsilon = epsilon or 1e-5
	for index = 1, 12 do
		if math.abs(a[index] - b[index]) > epsilon then
			return false
		end
	end
	return true
end
CF.__index = freezeType("CFrame", CFmethods, CFgetters)
CF.__newindex = noAssign("CFrame")
CF.__mul = function(a, b)
	if not isCF(a) then
		fail(fmt("attempt to multiply %s and CFrame", kindOf(a)), 2)
	end
	if isCF(b) then
		return mulCF(a, b)
	elseif isV3(b) then
		return pointToWorld(a, b)
	end
	fail(fmt("attempt to multiply CFrame and %s", kindOf(b)), 2)
end
CF.__add = function(a, b)
	if not (isCF(a) and isV3(b)) then
		fail(fmt("attempt to add %s and %s (only CFrame + Vector3)", kindOf(a), kindOf(b)), 2)
	end
	return cf(a[1] + b.X, a[2] + b.Y, a[3] + b.Z, a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12])
end
CF.__sub = function(a, b)
	if not (isCF(a) and isV3(b)) then
		fail(fmt("attempt to subtract %s and %s (only CFrame - Vector3)", kindOf(a), kindOf(b)), 2)
	end
	return cf(a[1] - b.X, a[2] - b.Y, a[3] - b.Z, a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12])
end
CF.__eq = function(a, b)
	for index = 1, 12 do
		if a[index] ~= b[index] then
			return false
		end
	end
	return true
end
CF.__tostring = function(c)
	return fmt("%g, %g, %g, %g, %g, %g, %g, %g, %g, %g, %g, %g", table.unpack(c, 1, 12))
end

function CFrame.new(...)
	local count = select("#", ...)
	if count == 0 then
		return cf(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	local a, b = ...
	if isV3(a) then
		if b ~= nil then
			return lookAt(a, b) -- deprecated CFrame.new(position, lookAt)
		end
		return cf(a.X, a.Y, a.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	if count == 3 then
		local x, y, z = ...
		return cf(x, y, z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	elseif count == 7 then
		local x, y, z, qx, qy, qz, qw = ...
		return fromQuaternion(x, y, z, qx, qy, qz, qw)
	elseif count == 12 then
		return cf(...)
	end
	fail(fmt("CFrame.new with %d arguments is not supported", count), 2)
end
CFrame.identity = cf(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
CFrame.lookAt = lookAt
function CFrame.lookAlong(at, direction, up)
	return lookAt(at, at + direction, up)
end
function CFrame.Angles(rx, ry, rz)
	return fromRotation(0, 0, 0, matMul(matMul(rotX(rx or 0), rotY(ry or 0)), rotZ(rz or 0)))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.fromEulerAnglesYXZ(rx, ry, rz)
	return fromRotation(0, 0, 0, matMul(matMul(rotY(ry or 0), rotX(rx or 0)), rotZ(rz or 0)))
end
CFrame.fromOrientation = CFrame.fromEulerAnglesYXZ
function CFrame.fromEulerAngles(rx, ry, rz, order)
	if order == nil or order.Name == "XYZ" then
		return CFrame.Angles(rx, ry, rz)
	elseif order.Name == "YXZ" then
		return CFrame.fromEulerAnglesYXZ(rx, ry, rz)
	end
	fail("CFrame.fromEulerAngles: rotation order " .. tostring(order) .. " is not supported", 2)
end
function CFrame.fromAxisAngle(axis, angle)
	local u = axis.Unit
	local half = angle / 2
	local s = math.sin(half)
	return fromQuaternion(0, 0, 0, u.X * s, u.Y * s, u.Z * s, math.cos(half))
end
function CFrame.fromMatrix(position, vx, vy, vz)
	vz = vz or vx:Cross(vy).Unit
	return cf(position.X, position.Y, position.Z, vx.X, vy.X, vz.X, vx.Y, vy.Y, vz.Y, vx.Z, vy.Z, vz.Z)
end
CFrame.fromQuaternion = function(qx, qy, qz, qw)
	return fromQuaternion(0, 0, 0, qx, qy, qz, qw)
end

---------------------------------------------------------------------------------------------------- Color3
local Color3 = {}
local C3 = { __kind = "Color3" }
local function c3(r, g, b)
	return setmetatable({ R = r, G = g, B = b, __kind = "Color3" }, C3)
end
local C3methods = {}
function C3methods.Lerp(a, b, t)
	return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
function C3methods.ToHSV(c)
	local r, g, b = c.R, c.G, c.B
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
local function byte(value)
	return math.clamp(math.floor(value * 255 + 0.5), 0, 255)
end
function C3methods.ToHex(c)
	return fmt("%02X%02X%02X", byte(c.R), byte(c.G), byte(c.B))
end
C3.__index = freezeType("Color3", C3methods)
C3.__newindex = noAssign("Color3")
C3.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
C3.__tostring = function(c)
	return fmt("%g, %g, %g", c.R, c.G, c.B)
end
function Color3.new(r, g, b)
	return c3(r or 0, g or 0, b or 0)
end
function Color3.fromRGB(r, g, b)
	return c3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function Color3.fromHex(hex)
	hex = string.gsub(hex, "^#", "")
	if #hex == 3 then
		hex = string.gsub(hex, "(.)", "%1%1")
	end
	if not string.match(hex, "^%x%x%x%x%x%x$") then
		fail("Color3.fromHex: bad hex " .. hex, 2)
	end
	return Color3.fromRGB(tonumber(string.sub(hex, 1, 2), 16), tonumber(string.sub(hex, 3, 4), 16), tonumber(string.sub(hex, 5, 6), 16))
end
function Color3.fromHSV(h, s, v)
	h = h % 1
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	i %= 6
	if i == 0 then
		return c3(v, t, p)
	elseif i == 1 then
		return c3(q, v, p)
	elseif i == 2 then
		return c3(p, v, t)
	elseif i == 3 then
		return c3(p, q, v)
	elseif i == 4 then
		return c3(t, p, v)
	end
	return c3(v, p, q)
end
function Color3.toHSV(c)
	return C3methods.ToHSV(c)
end

---------------------------------------------------------------------------------------------------- UDim, UDim2, Rect
local UDim = {}
local UD = { __kind = "UDim" }
local function udim(scale, offset)
	return setmetatable({ Scale = scale or 0, Offset = offset or 0, __kind = "UDim" }, UD)
end
UD.__index = freezeType("UDim", {})
UD.__newindex = noAssign("UDim")
UD.__add = function(a, b)
	return udim(a.Scale + b.Scale, a.Offset + b.Offset)
end
UD.__sub = function(a, b)
	return udim(a.Scale - b.Scale, a.Offset - b.Offset)
end
UD.__unm = function(a)
	return udim(-a.Scale, -a.Offset)
end
UD.__eq = function(a, b)
	return a.Scale == b.Scale and a.Offset == b.Offset
end
UD.__tostring = function(u)
	return fmt("%g, %g", u.Scale, u.Offset)
end
UDim.new = udim

local UDim2 = {}
local UD2 = { __kind = "UDim2" }
local function udim2(x, y)
	return setmetatable({ X = x, Y = y, __kind = "UDim2" }, UD2)
end
local UD2methods = {}
function UD2methods.Lerp(a, b, t)
	return udim2(
		udim(a.X.Scale + (b.X.Scale - a.X.Scale) * t, a.X.Offset + (b.X.Offset - a.X.Offset) * t),
		udim(a.Y.Scale + (b.Y.Scale - a.Y.Scale) * t, a.Y.Offset + (b.Y.Offset - a.Y.Offset) * t)
	)
end
UD2.__index = freezeType("UDim2", UD2methods, {
	Width = function(u)
		return u.X
	end,
	Height = function(u)
		return u.Y
	end,
})
UD2.__newindex = noAssign("UDim2")
UD2.__add = function(a, b)
	return udim2(a.X + b.X, a.Y + b.Y)
end
UD2.__sub = function(a, b)
	return udim2(a.X - b.X, a.Y - b.Y)
end
UD2.__unm = function(a)
	return udim2(-a.X, -a.Y)
end
UD2.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
UD2.__tostring = function(u)
	return fmt("{%s}, {%s}", tostring(u.X), tostring(u.Y))
end
function UDim2.new(a, b, c, d)
	if kindOf(a) == "UDim" then
		return udim2(a, b)
	end
	return udim2(udim(a or 0, b or 0), udim(c or 0, d or 0))
end
function UDim2.fromScale(x, y)
	return udim2(udim(x or 0, 0), udim(y or 0, 0))
end
function UDim2.fromOffset(x, y)
	return udim2(udim(0, x or 0), udim(0, y or 0))
end

local Rect = {}
local RC = { __kind = "Rect" }
RC.__index = freezeType("Rect", {}, {
	Width = function(r)
		return r.Max.X - r.Min.X
	end,
	Height = function(r)
		return r.Max.Y - r.Min.Y
	end,
})
RC.__newindex = noAssign("Rect")
function Rect.new(a, b, c, d)
	if kindOf(a) == "Vector2" then
		return setmetatable({ Min = a, Max = b, __kind = "Rect" }, RC)
	end
	return setmetatable({ Min = v2(a or 0, b or 0), Max = v2(c or 0, d or 0), __kind = "Rect" }, RC)
end

---------------------------------------------------------------------------------------------------- sequences, ranges & misc datatypes
local function simpleType(kind, fields)
	local meta = { __kind = kind }
	meta.__index = freezeType(kind, {})
	meta.__newindex = noAssign(kind)
	meta.__tostring = function(value)
		local parts = {}
		for _, field in fields do
			table.insert(parts, tostring(rawget(value, field)))
		end
		return kind .. "(" .. table.concat(parts, ", ") .. ")"
	end
	return function(values)
		values.__kind = kind
		return setmetatable(values, meta)
	end
end

local makeNumberKeypoint = simpleType("NumberSequenceKeypoint", { "Time", "Value", "Envelope" })
local NumberSequenceKeypoint = {
	new = function(time, value, envelope)
		return makeNumberKeypoint({ Time = time, Value = value, Envelope = envelope or 0 })
	end,
}
local makeNumberSequence = simpleType("NumberSequence", { "Keypoints" })
local NumberSequence = {
	new = function(a, b)
		if type(a) == "table" and kindOf(a) == "table" then
			return makeNumberSequence({ Keypoints = a })
		end
		if type(a) ~= "number" then
			fail("NumberSequence.new: expected numbers or a keypoint list, got " .. kindOf(a), 2)
		end
		return makeNumberSequence({ Keypoints = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) } })
	end,
}
local makeColorKeypoint = simpleType("ColorSequenceKeypoint", { "Time", "Value" })
local ColorSequenceKeypoint = {
	new = function(time, value)
		return makeColorKeypoint({ Time = time, Value = value })
	end,
}
local makeColorSequence = simpleType("ColorSequence", { "Keypoints" })
local ColorSequence = {
	new = function(a, b)
		if kindOf(a) == "table" then
			return makeColorSequence({ Keypoints = a })
		end
		if kindOf(a) ~= "Color3" then
			fail("ColorSequence.new: expected Color3 values or a keypoint list, got " .. kindOf(a), 2)
		end
		return makeColorSequence({ Keypoints = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) } })
	end,
}
local makeNumberRange = simpleType("NumberRange", { "Min", "Max" })
local NumberRange = {
	new = function(min, max)
		return makeNumberRange({ Min = min, Max = max or min })
	end,
}
local makePhysical = simpleType("PhysicalProperties", { "Density", "Friction", "Elasticity" })
local PhysicalProperties = {
	new = function(density, friction, elasticity, frictionWeight, elasticityWeight)
		if kindOf(density) == "EnumItem" then
			return makePhysical({ Density = 0.7, Friction = 0.3, Elasticity = 0.5, FrictionWeight = 1, ElasticityWeight = 1, Material = density })
		end
		return makePhysical({ Density = density, Friction = friction, Elasticity = elasticity, FrictionWeight = frictionWeight or 1, ElasticityWeight = elasticityWeight or 1 })
	end,
}
local makeTweenInfo = simpleType("TweenInfo", { "Time" })
local TweenInfo = {
	new = function(time, style, direction, repeatCount, reverses, delayTime)
		return makeTweenInfo({ Time = time or 1, EasingStyle = style, EasingDirection = direction, RepeatCount = repeatCount or 0, Reverses = reverses or false, DelayTime = delayTime or 0 })
	end,
}
local makeRay = simpleType("Ray", { "Origin", "Direction" })
local Ray = {
	new = function(origin, direction)
		return makeRay({ Origin = origin, Direction = direction, Unit = nil })
	end,
}
local makeRegion3 = simpleType("Region3", { "CFrame", "Size" })
local Region3 = {
	new = function(min, max)
		return makeRegion3({ CFrame = CFrame.new((min + max) / 2), Size = max - min })
	end,
}
local makeFont = simpleType("Font", { "Family" })
local Font = {}
function Font.new(family, weight, style)
	return makeFont({ Family = family, Weight = weight, Style = style, Bold = false })
end
function Font.fromEnum(font)
	return makeFont({ Family = "rbxasset://fonts/families/" .. font.Name .. ".json", Weight = nil, Style = nil, Bold = false, EnumName = font.Name })
end
function Font.fromName(name, weight, style)
	return makeFont({ Family = "rbxasset://fonts/families/" .. name .. ".json", Weight = weight, Style = style, Bold = false, EnumName = name })
end
function Font.fromId(id, weight, style)
	return makeFont({ Family = "rbxassetid://" .. tostring(id), Weight = weight, Style = style, Bold = false })
end

-- Plain parameter bags (RaycastParams, OverlapParams): any field may be set
local function bag(kind)
	return {
		new = function()
			return { __kind = kind, FilterDescendantsInstances = {}, FilterType = nil, IgnoreWater = false, CollisionGroup = "Default", RespectCanCollide = false, MaxParts = 0 }
		end,
	}
end
local RaycastParams = bag("RaycastParams")
local OverlapParams = bag("OverlapParams")

local DateTime = {}
local function makeDateTime(millis)
	return {
		__kind = "DateTime",
		UnixTimestamp = math.floor(millis / 1000),
		UnixTimestampMillis = millis,
		ToIsoDate = function()
			return os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(millis / 1000))
		end,
		ToUniversalTime = function()
			local t = os.date("!*t", math.floor(millis / 1000))
			return { Year = t.year, Month = t.month, Day = t.day, Hour = t.hour, Minute = t.min, Second = t.sec, Millisecond = millis % 1000 }
		end,
	}
end
function DateTime.now()
	return makeDateTime(math.floor((Mock.ClockBase + Mock.Now) * 1000))
end
function DateTime.fromUnixTimestamp(seconds)
	return makeDateTime(seconds * 1000)
end
function DateTime.fromUnixTimestampMillis(millis)
	return makeDateTime(millis)
end

---------------------------------------------------------------------------------------------------- BrickColor
local BRICK_COLORS = {
	["White"] = { 242, 243, 243, 1 },
	["Institutional white"] = { 248, 248, 248, 1001 },
	["Medium stone grey"] = { 163, 162, 165, 194 },
	["Dark stone grey"] = { 99, 95, 98, 199 },
	["Black"] = { 27, 42, 53, 26 },
	["Really black"] = { 17, 17, 17, 1003 },
	["Bright red"] = { 196, 40, 28, 21 },
	["Really red"] = { 255, 0, 0, 1004 },
	["Bright blue"] = { 13, 105, 172, 23 },
	["Really blue"] = { 0, 0, 255, 1010 },
	["Bright green"] = { 75, 151, 75, 37 },
	["Lime green"] = { 0, 255, 0, 1020 },
	["Bright yellow"] = { 245, 205, 48, 24 },
	["New Yeller"] = { 255, 255, 0, 1009 },
	["Bright orange"] = { 218, 133, 65, 106 },
	["Bright violet"] = { 107, 50, 124, 104 },
	["Hot pink"] = { 255, 0, 191, 1032 },
	["Cyan"] = { 4, 175, 236, 1019 },
	["Toothpaste"] = { 0, 255, 255, 1019 },
	["Reddish brown"] = { 105, 64, 40, 192 },
	["Brown"] = { 124, 92, 70, 217 },
	["Sand green"] = { 120, 144, 130, 151 },
	["Pastel blue"] = { 128, 187, 219, 1024 },
	["Light blue"] = { 180, 210, 228, 45 },
}
local BrickColor = {}
local BC = { __kind = "BrickColor" }
BC.__index = freezeType("BrickColor", {}, {
	r = function(b)
		return b.Color.R
	end,
	g = function(b)
		return b.Color.G
	end,
	b = function(b)
		return b.Color.B
	end,
})
BC.__newindex = noAssign("BrickColor")
BC.__eq = function(a, b)
	return a.Name == b.Name
end
BC.__tostring = function(b)
	return b.Name
end
local function brick(name, color, number)
	return setmetatable({ Name = name, Color = color, Number = number, __kind = "BrickColor" }, BC)
end
function BrickColor.new(value, g, b)
	if type(value) == "string" then
		local entry = BRICK_COLORS[value]
		if not entry then
			fail(fmt("BrickColor.new(%q): unknown BrickColor name (add it to BRICK_COLORS in MapMock.luau)", value), 2)
		end
		return brick(value, Color3.fromRGB(entry[1], entry[2], entry[3]), entry[4])
	end
	local color = value
	if type(value) == "number" and g then
		color = c3(value, g, b)
	elseif type(value) == "number" then
		for name, entry in BRICK_COLORS do
			if entry[4] == value then
				return brick(name, Color3.fromRGB(entry[1], entry[2], entry[3]), value)
			end
		end
		fail(fmt("BrickColor.new(%d): unknown BrickColor number", value), 2)
	end
	-- nearest palette entry to a Color3
	local best, bestDistance = "Medium stone grey", math.huge
	for name, entry in BRICK_COLORS do
		local dr, dg, db = entry[1] / 255 - color.R, entry[2] / 255 - color.G, entry[3] / 255 - color.B
		local distance = dr * dr + dg * dg + db * db
		if distance < bestDistance then
			best, bestDistance = name, distance
		end
	end
	return BrickColor.new(best)
end
function BrickColor.White()
	return BrickColor.new("White")
end
function BrickColor.Black()
	return BrickColor.new("Black")
end
function BrickColor.Gray()
	return BrickColor.new("Medium stone grey")
end
function BrickColor.Red()
	return BrickColor.new("Bright red")
end
function BrickColor.Blue()
	return BrickColor.new("Bright blue")
end
function BrickColor.Green()
	return BrickColor.new("Bright green")
end
function BrickColor.Yellow()
	return BrickColor.new("Bright yellow")
end
function BrickColor.random()
	return BrickColor.new("Medium stone grey")
end

---------------------------------------------------------------------------------------------------- Random (deterministic)
-- Not Roblox's exact generator (so scattered props land in different spots than in the real game), but
-- deterministic for a seed, so previews are stable between runs.
local Random = {}
local RandomMeta = { __kind = "Random" }
local RandomMethods = {}
local function imul(a, b)
	local ah, al = bit32.rshift(a, 16), bit32.band(a, 0xFFFF)
	local bh, bl = bit32.rshift(b, 16), bit32.band(b, 0xFFFF)
	return bit32.band(al * bl + bit32.lshift(bit32.band(ah * bl + al * bh, 0xFFFF), 16), 0xFFFFFFFF)
end
local function nextUint(self)
	-- mulberry32
	self.State = bit32.band(self.State + 0x6D2B79F5, 0xFFFFFFFF)
	local t = self.State
	t = imul(bit32.bxor(t, bit32.rshift(t, 15)), bit32.bor(t, 1))
	t = bit32.bxor(t, t + imul(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(t, 61)))
	t = bit32.band(t, 0xFFFFFFFF)
	return bit32.bxor(t, bit32.rshift(t, 14))
end
local function nextFloat(self)
	local hi = nextUint(self)
	local lo = nextUint(self)
	return (hi * 2097152 + bit32.rshift(lo, 11)) / 9007199254740992
end
function RandomMethods.NextNumber(self, min, max)
	if min == nil then
		return nextFloat(self)
	end
	return min + (max - min) * nextFloat(self)
end
function RandomMethods.NextInteger(self, min, max)
	if max < min then
		fail(fmt("Random:NextInteger(%d, %d): max must be >= min", min, max), 2)
	end
	return min + math.floor(nextFloat(self) * (max - min + 1))
end
function RandomMethods.NextUnitVector(self)
	local z = 2 * nextFloat(self) - 1
	local angle = 2 * math.pi * nextFloat(self)
	local r = math.sqrt(1 - z * z)
	return v3(r * math.cos(angle), r * math.sin(angle), z)
end
function RandomMethods.Shuffle(self, list)
	for index = #list, 2, -1 do
		local other = RandomMethods.NextInteger(self, 1, index)
		list[index], list[other] = list[other], list[index]
	end
end
function RandomMethods.Clone(self)
	return setmetatable({ State = self.State, __kind = "Random" }, RandomMeta)
end
RandomMeta.__index = freezeType("Random", RandomMethods)
function Random.new(seed)
	local state = math.floor(math.abs(seed or 0)) % 4294967296
	local rng = setmetatable({ State = bit32.bxor(state, 0x9E3779B9), __kind = "Random" }, RandomMeta)
	for _ = 1, 4 do
		nextUint(rng)
	end
	return rng
end

---------------------------------------------------------------------------------------------------- Enum
-- Any Enum.X.Y works (items are created on first use). Enums listed in ENUM_ITEMS also know their
-- item list (GetEnumItems) and real values, and reject unknown item names.
local ENUM_ITEMS = {
	Material = {
		Plastic = 256, SmoothPlastic = 272, Neon = 288, Wood = 512, WoodPlanks = 528, Marble = 784, Basalt = 788,
		Slate = 800, CrackedLava = 804, Concrete = 816, Limestone = 820, Granite = 832, Pavement = 836, Brick = 848,
		Pebble = 864, Cobblestone = 880, Rock = 896, Sandstone = 912, CorrodedMetal = 1040, DiamondPlate = 1056,
		Foil = 1072, Metal = 1088, Grass = 1280, LeafyGrass = 1284, Sand = 1296, Fabric = 1312, Snow = 1328,
		Mud = 1344, Ground = 1360, Asphalt = 1376, Salt = 1392, Ice = 1536, Glacier = 1552, Glass = 1568,
		ForceField = 1584, Air = 1792, Water = 2048, Cardboard = 2304, Carpet = 2305, CeramicTiles = 2306,
		ClayRoofTiles = 2307, RoofShingles = 2308, Leather = 2309, Plaster = 2310, Rubber = 2311,
	},
	NormalId = { Right = 0, Top = 1, Back = 2, Left = 3, Bottom = 4, Front = 5 },
	PartType = { Ball = 0, Block = 1, Cylinder = 2, Wedge = 3, CornerWedge = 4 },
	SurfaceType = { Smooth = 0, Glue = 1, Weld = 2, Studs = 3, Inlet = 4, Universal = 5, Hinge = 6, Motor = 7, SteppingMotor = 8, SmoothNoOutlines = 10 },
	SurfaceGuiSizingMode = { FixedSize = 0, PixelsPerStud = 1 },
	MeshType = { Head = 0, Torso = 1, Wedge = 2, Prism = 3, Pyramid = 4, ParallelRamp = 5, RightAngleRamp = 6, CornerWedge = 7, Brick = 8, Sphere = 9, Cylinder = 10, FileMesh = 11 },
	TextXAlignment = { Left = 0, Right = 1, Center = 2 },
	TextYAlignment = { Top = 0, Center = 1, Bottom = 2 },
	ApplyStrokeMode = { Contextual = 0, Border = 1 },
	EasingStyle = { Linear = 0, Sine = 1, Back = 2, Quad = 3, Quart = 4, Quint = 5, Bounce = 6, Elastic = 7, Exponential = 8, Circular = 9, Cubic = 10 },
	EasingDirection = { In = 0, Out = 1, InOut = 2 },
	Axis = { X = 0, Y = 1, Z = 2 },
}
local Enum = {}
local enumTypes = {}
local function enumType(enumName)
	local existing = enumTypes[enumName]
	if existing then
		return existing
	end
	local known = ENUM_ITEMS[enumName]
	local items = {}
	local nextValue = 0
	local function makeItem(itemName)
		local value = known and known[itemName]
		if value == nil then
			if known then
				fail(fmt("Enum.%s.%s is not a valid EnumItem (known: see ENUM_ITEMS in MapMock.luau)", enumName, tostring(itemName)), 3)
			end
			value = nextValue
			nextValue += 1
		end
		local item = setmetatable({ Name = itemName, Value = value, EnumType = nil, __kind = "EnumItem" }, {
			__tostring = function()
				return "Enum." .. enumName .. "." .. itemName
			end,
			__index = function(_, key)
				if key == "IsA" then
					return function(_, name)
						return name == enumName
					end
				end
				fail(fmt("EnumItem.%s is not supported", tostring(key)), 2)
			end,
		})
		return item
	end
	local enum = setmetatable({}, {
		__index = function(self, itemName)
			if itemName == "GetEnumItems" then
				return function()
					if not known then
						fail("Enum." .. enumName .. ":GetEnumItems() needs the item list in ENUM_ITEMS (MapMock.luau)", 2)
					end
					local list = {}
					for name in known do
						table.insert(list, self[name])
					end
					table.sort(list, function(a, b)
						return a.Value < b.Value
					end)
					return list
				end
			elseif itemName == "FromName" then
				return function(_, name)
					return self[name]
				end
			elseif itemName == "FromValue" then
				return function(_, value)
					if known then
						for name, itemValue in known do
							if itemValue == value then
								return self[name]
							end
						end
					end
					return nil
				end
			end
			local item = makeItem(itemName)
			rawset(item, "EnumType", self)
			rawset(items, itemName, item)
			rawset(self, itemName, item)
			return item
		end,
		__tostring = function()
			return enumName
		end,
	})
	enumTypes[enumName] = enum
	return enum
end
setmetatable(Enum, {
	__index = function(_, enumName)
		return enumType(enumName)
	end,
})
local function enumName(item)
	return tostring(rawget(item, "EnumType"))
end

---------------------------------------------------------------------------------------------------- scheduler
local WAIT = {} -- yield token
local Scheduler = { Queue = {}, Sequence = 0, Waiting = {} }

local function report(thread, err)
	local trace = debug.traceback(thread)
	table.insert(Mock.Errors, tostring(err) .. "\n" .. trace)
end

local function resume(thread, ...)
	if coroutine.status(thread) ~= "suspended" then
		return
	end
	local ok, token, wake = coroutine.resume(thread, ...)
	if not ok then
		report(thread, token)
		return
	end
	if coroutine.status(thread) == "dead" then
		return
	end
	if token == WAIT then
		Scheduler.Sequence += 1
		table.insert(Scheduler.Queue, { Time = wake, Seq = Scheduler.Sequence, Thread = thread, Started = Mock.Now })
	end
	-- other yields (signals, WaitForChild) park the thread until something resumes it
end

local function schedule(time, thread, ...)
	Scheduler.Sequence += 1
	table.insert(Scheduler.Queue, { Time = time, Seq = Scheduler.Sequence, Thread = thread, Args = table.pack(...), Started = Mock.Now })
end

local function currentThreadCanYield()
	local thread, isMain = coroutine.running()
	return thread and not isMain and coroutine.isyieldable()
end

local function waitFor(seconds)
	seconds = math.max(seconds or 0, 0.015)
	if not currentThreadCanYield() then
		fail("task.wait called where the mock can't yield", 3)
	end
	local start = Mock.Now
	coroutine.yield(WAIT, Mock.Now + seconds)
	return Mock.Now - start
end

local task = {}
function task.wait(seconds)
	return waitFor(seconds)
end
function task.spawn(fn, ...)
	local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
	resume(thread, ...)
	return thread
end
function task.defer(fn, ...)
	local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
	schedule(Mock.Now, thread, ...)
	return thread
end
function task.delay(seconds, fn, ...)
	local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
	schedule(Mock.Now + (seconds or 0), thread, ...)
	return thread
end
function task.cancel(thread)
	for index = #Scheduler.Queue, 1, -1 do
		if Scheduler.Queue[index].Thread == thread then
			table.remove(Scheduler.Queue, index)
		end
	end
	pcall(coroutine.close, thread)
end
function task.synchronize() end
function task.desynchronize() end

function Scheduler.Run(maxSeconds, maxSteps)
	local steps = 0
	while #Scheduler.Queue > 0 and steps < maxSteps do
		table.sort(Scheduler.Queue, function(a, b)
			if a.Time == b.Time then
				return a.Seq < b.Seq
			end
			return a.Time < b.Time
		end)
		local entry = table.remove(Scheduler.Queue, 1)
		if entry.Time > maxSeconds then
			table.insert(Scheduler.Queue, 1, entry)
			break
		end
		Mock.Now = math.max(Mock.Now, entry.Time)
		steps += 1
		if entry.Args then
			resume(entry.Thread, table.unpack(entry.Args, 1, entry.Args.n))
		else
			resume(entry.Thread, Mock.Now - entry.Started, Mock.Now)
		end
	end
	return steps
end

---------------------------------------------------------------------------------------------------- signals
local function newSignal(name)
	local signal = { __kind = "RBXScriptSignal", Name = name, Handlers = {}, Waiting = {} }
	local function connect(self, fn, once)
		if type(fn) ~= "function" then
			fail("Connect expects a function", 3)
		end
		local handler = { Fn = fn, Once = once }
		table.insert(self.Handlers, handler)
		return {
			__kind = "RBXScriptConnection",
			Connected = true,
			Disconnect = function(connection)
				connection.Connected = false
				handler.Fn = nil
			end,
		}
	end
	function signal:Connect(fn)
		return connect(self, fn, false)
	end
	signal.ConnectParallel = signal.Connect
	function signal:Once(fn)
		return connect(self, fn, true)
	end
	function signal:Wait()
		if not currentThreadCanYield() then
			fail("Signal:Wait() called where the mock can't yield", 2)
		end
		table.insert(self.Waiting, (coroutine.running()))
		return coroutine.yield()
	end
	function signal:Fire(...)
		for _, handler in table.clone(self.Handlers) do
			local fn = handler.Fn
			if fn then
				if handler.Once then
					handler.Fn = nil
				end
				task.spawn(fn, ...)
			end
		end
		local waiting = self.Waiting
		self.Waiting = {}
		for _, thread in waiting do
			resume(thread, ...)
		end
	end
	return signal
end

---------------------------------------------------------------------------------------------------- class definitions
-- CLASSES[name] = { Super, Props = { name = default }, Events = { name = true }, Methods = {...} }
-- NIL marks a property whose default is nil (references, optional values): any value can be stored.
local NIL = setmetatable({}, {
	__tostring = function()
		return "nil"
	end,
})
local CLASSES = {}
local function class(name, super, props, extra)
	extra = extra or {}
	CLASSES[name] = {
		Name = name,
		Super = super,
		Props = props or {},
		Events = extra.Events or {},
		Methods = extra.Methods or {},
		Service = extra.Service,
		Abstract = extra.Abstract,
		Getters = extra.Getters or {},
		Setters = extra.Setters or {},
	}
end
local function events(list)
	local set = {}
	for _, name in list do
		set[name] = true
	end
	return set
end

local E = Enum
local WHITE = c3(1, 1, 1)
local BLACK = c3(0, 0, 0)
local GREY = Color3.fromRGB(163, 162, 165)

class("Instance", nil, { Name = "Instance", Archivable = true }, {
	Abstract = true,
	Events = events({ "Changed", "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "AncestryChanged", "AttributeChanged", "Destroying" }),
})
class("PVInstance", "Instance", {}, { Abstract = true })
class("BasePart", "PVInstance", {
	Anchored = false,
	AudioCanCollide = true,
	CanCollide = true,
	CanQuery = true,
	CanTouch = true,
	CastShadow = true,
	CFrame = CFrame.identity,
	Color = GREY,
	CollisionGroup = "Default",
	CollisionGroupId = 0,
	CustomPhysicalProperties = NIL,
	EnableFluidForces = true,
	LocalTransparencyModifier = 0,
	Locked = false,
	Massless = false,
	Material = E.Material.Plastic,
	MaterialVariant = "",
	PivotOffset = CFrame.identity,
	Reflectance = 0,
	RootPriority = 0,
	Size = v3(4, 1, 2),
	Transparency = 0,
	AssemblyLinearVelocity = Vector3.zero,
	AssemblyAngularVelocity = Vector3.zero,
	Velocity = Vector3.zero,
	RotVelocity = Vector3.zero,
	TopSurface = E.SurfaceType.Smooth,
	BottomSurface = E.SurfaceType.Smooth,
	FrontSurface = E.SurfaceType.Smooth,
	BackSurface = E.SurfaceType.Smooth,
	LeftSurface = E.SurfaceType.Smooth,
	RightSurface = E.SurfaceType.Smooth,
}, { Abstract = true, Events = events({ "Touched", "TouchEnded" }) })
class("FormFactorPart", "BasePart", {}, { Abstract = true })
class("Part", "FormFactorPart", { Shape = E.PartType.Block })
class("WedgePart", "FormFactorPart", {})
class("CornerWedgePart", "BasePart", {})
class("TrussPart", "BasePart", { Style = E.Style.AlternatingSupports })
class("SpawnLocation", "Part", { AllowTeamChangeOnTouch = false, Duration = 10, Enabled = true, Neutral = true, TeamColor = BrickColor.new("Medium stone grey") })
class("Seat", "Part", { Disabled = false, Occupant = NIL })
class("MeshPart", "BasePart", {
	MeshId = "",
	TextureID = "",
	DoubleSided = false,
	RenderFidelity = E.RenderFidelity.Automatic,
	CollisionFidelity = E.CollisionFidelity.Default,
	MeshSize = Vector3.one,
	HasSkinnedMesh = false,
	FluidFidelity = E.FluidFidelity.Automatic,
})
class("PartOperation", "BasePart", { UsePartColor = false, RenderFidelity = E.RenderFidelity.Automatic, CollisionFidelity = E.CollisionFidelity.Default, SmoothingAngle = 0 }, { Abstract = true })
class("UnionOperation", "PartOperation", {})
class("NegateOperation", "PartOperation", {})
class("Terrain", "BasePart", {
	Decoration = false,
	GrassLength = 0.7,
	WaterColor = Color3.fromRGB(12, 84, 92),
	WaterReflectance = 1,
	WaterTransparency = 0.3,
	WaterWaveSize = 0.15,
	WaterWaveSpeed = 10,
	MaxExtents = NIL,
}, {})
class("Model", "PVInstance", { PrimaryPart = NIL, LevelOfDetail = E.ModelLevelOfDetail.Automatic, ModelStreamingMode = E.ModelStreamingMode.Default })
class("WorldRoot", "Model", {}, { Abstract = true })
class("Workspace", "WorldRoot", {
	AirDensity = 0.0012,
	AllowThirdPartySales = false,
	CurrentCamera = NIL,
	DistributedGameTime = 0,
	FallenPartsDestroyHeight = -500,
	GlobalWind = Vector3.zero,
	Gravity = 196.2,
	StreamingEnabled = false,
	StreamingMinRadius = 64,
	StreamingTargetRadius = 1024,
	StreamOutBehavior = E.StreamOutBehavior.Default,
	ModelStreamingBehavior = E.ModelStreamingBehavior.Default,
	SignalBehavior = E.SignalBehavior.Default,
	TouchesUseCollisionGroups = false,
}, { Service = true })
class("Folder", "Instance", {})
class("Configuration", "Instance", {})
class("Actor", "Model", {})
class("Camera", "PVInstance", { CFrame = CFrame.identity, Focus = CFrame.identity, FieldOfView = 70, CameraType = E.CameraType.Custom, CameraSubject = NIL, ViewportSize = v2(1920, 1080), HeadLocked = true, HeadScale = 1 })

class("Attachment", "Instance", { CFrame = CFrame.identity, Visible = false })
class("Bone", "Attachment", { Transform = CFrame.identity })
class("JointInstance", "Instance", { Part0 = NIL, Part1 = NIL, C0 = CFrame.identity, C1 = CFrame.identity, Enabled = true }, { Abstract = true })
class("Weld", "JointInstance", {})
class("Snap", "JointInstance", {})
class("Motor6D", "JointInstance", { CurrentAngle = 0, DesiredAngle = 0, MaxVelocity = 0, Transform = CFrame.identity })
class("WeldConstraint", "Instance", { Part0 = NIL, Part1 = NIL, Enabled = true })
class("NoCollisionConstraint", "Instance", { Part0 = NIL, Part1 = NIL, Enabled = true })
class("Constraint", "Instance", { Attachment0 = NIL, Attachment1 = NIL, Color = BrickColor.new("Medium stone grey"), Enabled = true, Visible = false }, { Abstract = true })
class("RopeConstraint", "Constraint", { Length = 5, Restitution = 0, Thickness = 0.1, WinchEnabled = false, WinchForce = 0, WinchResponsiveness = 45, WinchSpeed = 2, WinchTarget = 0 })
class("RodConstraint", "Constraint", { Length = 5, Thickness = 0.1, LimitsEnabled = false, LimitAngle0 = 90, LimitAngle1 = 90 })
class("SpringConstraint", "Constraint", { Coils = 3, Damping = 0, FreeLength = 1, LimitsEnabled = false, MaxForce = math.huge, MaxLength = 5, MinLength = 0, Radius = 0.4, Stiffness = 0, Thickness = 0.1 })
class("BallSocketConstraint", "Constraint", { LimitsEnabled = false, Radius = 0.15, Restitution = 0, TwistLimitsEnabled = false, UpperAngle = 45 })
class("HingeConstraint", "Constraint", { ActuatorType = E.ActuatorType.None, AngularSpeed = 0, AngularVelocity = 0, LimitsEnabled = false, MotorMaxTorque = 0, Radius = 0.15, ServoMaxTorque = 0, TargetAngle = 0 })
class("AlignPosition", "Constraint", { Mode = E.PositionAlignmentMode.TwoAttachment, MaxForce = 10000, MaxVelocity = math.huge, Position = Vector3.zero, Responsiveness = 10, RigidityEnabled = false, ApplyAtCenterOfMass = false, ReactionForceEnabled = false })
class("AlignOrientation", "Constraint", { Mode = E.OrientationAlignmentMode.TwoAttachment, MaxTorque = 10000, MaxAngularVelocity = math.huge, CFrame = CFrame.identity, Responsiveness = 10, RigidityEnabled = false, PrimaryAxisOnly = false, ReactionTorqueEnabled = false })
class("LinearVelocity", "Constraint", { MaxForce = 1000, VectorVelocity = Vector3.zero, VelocityConstraintMode = E.VelocityConstraintMode.Vector, RelativeTo = E.ActuatorRelativeTo.World })
class("AngularVelocity", "Constraint", { MaxTorque = 1000, AngularVelocity = Vector3.zero, RelativeTo = E.ActuatorRelativeTo.World })

class("Light", "Instance", { Brightness = 1, Color = WHITE, Enabled = true, Shadows = false }, { Abstract = true })
class("PointLight", "Light", { Range = 8 })
class("SpotLight", "Light", { Range = 16, Angle = 90, Face = E.NormalId.Front })
class("SurfaceLight", "Light", { Range = 16, Angle = 90, Face = E.NormalId.Front })

class("ParticleEmitter", "Instance", {
	Acceleration = Vector3.zero,
	Brightness = 1,
	Color = ColorSequence.new(WHITE),
	Drag = 0,
	EmissionDirection = E.NormalId.Top,
	Enabled = true,
	FlipbookFramerate = NumberRange.new(1),
	FlipbookIncompatible = "",
	FlipbookLayout = E.ParticleFlipbookLayout.None,
	FlipbookMode = E.ParticleFlipbookMode.Loop,
	FlipbookStartRandom = false,
	Lifetime = NumberRange.new(5, 10),
	LightEmission = 0,
	LightInfluence = 0,
	LockedToPart = false,
	Orientation = E.ParticleOrientation.FacingCamera,
	Rate = 20,
	RotSpeed = NumberRange.new(0),
	Rotation = NumberRange.new(0),
	Shape = E.ParticleEmitterShape.Box,
	ShapeInOut = E.ParticleEmitterShapeInOut.Outward,
	ShapePartial = 1,
	ShapeStyle = E.ParticleEmitterShapeStyle.Volume,
	Size = NumberSequence.new(1),
	Speed = NumberRange.new(5),
	SpreadAngle = Vector2.zero,
	Squash = NumberSequence.new(0),
	Texture = "rbxasset://textures/particles/sparkles_main.dds",
	TimeScale = 1,
	Transparency = NumberSequence.new(0),
	VelocityInheritance = 0,
	VelocitySpread = 0,
	WindAffectsDrag = false,
	ZOffset = 0,
}, {
	Methods = {
		Emit = function() end,
		Clear = function() end,
	},
})
class("Trail", "Instance", {
	Attachment0 = NIL,
	Attachment1 = NIL,
	Brightness = 1,
	Color = ColorSequence.new(WHITE),
	Enabled = true,
	FaceCamera = false,
	Lifetime = 2,
	LightEmission = 0,
	LightInfluence = 0,
	MaxLength = 0,
	MinLength = 0.1,
	Texture = "",
	TextureLength = 1,
	TextureMode = E.TextureMode.Stretch,
	Transparency = NumberSequence.new(0.5),
	WidthScale = NumberSequence.new(1),
}, { Methods = { Clear = function() end } })
class("Beam", "Instance", {
	Attachment0 = NIL,
	Attachment1 = NIL,
	Brightness = 1,
	Color = ColorSequence.new(WHITE),
	CurveSize0 = 0,
	CurveSize1 = 0,
	Enabled = true,
	FaceCamera = false,
	LightEmission = 0,
	LightInfluence = 0,
	Segments = 10,
	Texture = "",
	TextureLength = 1,
	TextureMode = E.TextureMode.Stretch,
	TextureSpeed = 1,
	Transparency = NumberSequence.new(0.5),
	Width0 = 1,
	Width1 = 1,
	ZOffset = 0,
}, { Methods = { SetTextureOffset = function() end } })
class("Fire", "Instance", { Color = Color3.fromRGB(236, 139, 70), Enabled = true, Heat = 9, SecondaryColor = Color3.fromRGB(139, 80, 55), Size = 5, TimeScale = 1 })
class("Smoke", "Instance", { Color = WHITE, Enabled = true, Opacity = 0.5, RiseVelocity = 1, Size = 1, TimeScale = 1 })
class("Sparkles", "Instance", { SparkleColor = Color3.fromRGB(144, 25, 255), Enabled = true, TimeScale = 1 })
class("Highlight", "Instance", { Adornee = NIL, DepthMode = E.HighlightDepthMode.AlwaysOnTop, Enabled = true, FillColor = Color3.fromRGB(255, 0, 0), FillTransparency = 0.5, OutlineColor = WHITE, OutlineTransparency = 0 })
class("SelectionBox", "Instance", { Adornee = NIL, Color3 = Color3.fromRGB(13, 105, 172), LineThickness = 0.15, SurfaceColor3 = Color3.fromRGB(13, 105, 172), SurfaceTransparency = 1, Transparency = 0, Visible = true })

class("FaceInstance", "Instance", { Face = E.NormalId.Front }, { Abstract = true })
class("Decal", "FaceInstance", { Color3 = WHITE, LocalTransparencyModifier = 0, Texture = "", Transparency = 0, ZIndex = 1 })
class("Texture", "Decal", { OffsetStudsU = 0, OffsetStudsV = 0, StudsPerTileU = 2, StudsPerTileV = 2 })

class("DataModelMesh", "Instance", { Offset = Vector3.zero, Scale = Vector3.one, VertexColor = Vector3.one }, { Abstract = true })
class("SpecialMesh", "DataModelMesh", { MeshType = E.MeshType.Head, MeshId = "", TextureId = "" })
class("BlockMesh", "DataModelMesh", {})
class("CylinderMesh", "DataModelMesh", {})

class("ProximityPrompt", "Instance", {
	ActionText = "Interact",
	AutoLocalize = true,
	ClickablePrompt = true,
	Enabled = true,
	Exclusivity = E.ProximityPromptExclusivity.OnePerButton,
	GamepadKeyCode = E.KeyCode.ButtonX,
	HoldDuration = 0,
	KeyboardKeyCode = E.KeyCode.E,
	MaxActivationDistance = 10,
	MaxIndicatorDistance = 0,
	ObjectText = "",
	RequiresLineOfSight = true,
	RootLocalizationTable = NIL,
	Style = E.ProximityPromptStyle.Default,
	UIOffset = Vector2.zero,
}, {
	Events = events({ "Triggered", "TriggerEnded", "PromptShown", "PromptHidden", "PromptButtonHoldBegan", "PromptButtonHoldEnded" }),
	Methods = { InputHoldBegin = function() end, InputHoldEnd = function() end },
})
class("ClickDetector", "Instance", { CursorIcon = "", MaxActivationDistance = 32 }, {
	Events = events({ "MouseClick", "RightMouseClick", "MouseHoverEnter", "MouseHoverLeave" }),
})
class("Sound", "Instance", {
	Looped = false,
	PlaybackSpeed = 1,
	Playing = false,
	PlayOnRemove = false,
	RollOffMaxDistance = 10000,
	RollOffMinDistance = 10,
	RollOffMode = E.RollOffMode.InverseTapered,
	SoundGroup = NIL,
	SoundId = "",
	TimePosition = 0,
	Volume = 0.5,
	IsLoaded = true,
	IsPlaying = false,
	TimeLength = 0,
	PlaybackLoudness = 0,
}, {
	Events = events({ "Ended", "Played", "Loaded", "Paused", "Resumed", "Stopped", "DidLoop" }),
	Methods = {
		Play = function(self)
			self.Playing = true
		end,
		Stop = function(self)
			self.Playing = false
		end,
		Pause = function(self)
			self.Playing = false
		end,
		Resume = function(self)
			self.Playing = true
		end,
	},
})
class("SoundGroup", "Instance", { Volume = 0.5 })
class("SoundEffect", "Instance", { Enabled = true, Priority = 0 }, { Abstract = true })
class("ReverbSoundEffect", "SoundEffect", { DecayTime = 1.5, Density = 1, Diffusion = 1, DryLevel = -6, WetLevel = 0 })
class("EqualizerSoundEffect", "SoundEffect", { HighGain = 0, LowGain = -20, MidGain = -10 })

-- GUI
class("GuiBase2d", "Instance", { AutoLocalize = true, RootLocalizationTable = NIL, SelectionBehaviorDown = E.SelectionBehavior.Escape, SelectionBehaviorLeft = E.SelectionBehavior.Escape, SelectionBehaviorRight = E.SelectionBehavior.Escape, SelectionBehaviorUp = E.SelectionBehavior.Escape, SelectionGroup = false }, {
	Abstract = true,
	Getters = {
		AbsoluteSize = function()
			return v2(100, 100)
		end,
		AbsolutePosition = function()
			return v2(0, 0)
		end,
		AbsoluteRotation = function()
			return 0
		end,
	},
})
class("LayerCollector", "GuiBase2d", { Enabled = true, ResetOnSpawn = true, ZIndexBehavior = E.ZIndexBehavior.Global }, { Abstract = true })
class("SurfaceGuiBase", "LayerCollector", { Active = true, Adornee = NIL, Face = E.NormalId.Front }, { Abstract = true })
class("SurfaceGui", "SurfaceGuiBase", {
	AlwaysOnTop = false,
	Brightness = 1,
	CanvasSize = v2(800, 600),
	ClipsDescendants = true,
	LightInfluence = 1,
	MaxDistance = 1000,
	PixelsPerStud = 50,
	SizingMode = E.SurfaceGuiSizingMode.FixedSize,
	ToolPunchThroughDistance = 0,
	ZOffset = 0,
})
class("BillboardGui", "LayerCollector", {
	Active = false,
	Adornee = NIL,
	AlwaysOnTop = false,
	Brightness = 1,
	ClipsDescendants = false,
	DistanceLowerLimit = 0,
	DistanceStep = 0,
	DistanceUpperLimit = -1,
	ExtentsOffset = Vector3.zero,
	ExtentsOffsetWorldSpace = Vector3.zero,
	LightInfluence = 1,
	MaxDistance = math.huge,
	PlayerToHideFrom = NIL,
	Size = UDim2.new(0, 0, 0, 0),
	SizeOffset = Vector2.zero,
	StudsOffset = Vector3.zero,
	StudsOffsetWorldSpace = Vector3.zero,
})
class("ScreenGui", "LayerCollector", { DisplayOrder = 0, IgnoreGuiInset = false, ClipToDeviceSafeArea = true, SafeAreaCompatibility = E.SafeAreaCompatibility.FullscreenExtension, ScreenInsets = E.ScreenInsets.CoreUISafeInsets })
class("GuiObject", "GuiBase2d", {
	Active = false,
	AnchorPoint = Vector2.zero,
	AutomaticSize = E.AutomaticSize.None,
	BackgroundColor3 = GREY,
	BackgroundTransparency = 0,
	BorderColor3 = Color3.fromRGB(27, 42, 53),
	BorderMode = E.BorderMode.Outline,
	BorderSizePixel = 1,
	ClipsDescendants = false,
	Interactable = true,
	LayoutOrder = 0,
	NextSelectionDown = NIL,
	NextSelectionLeft = NIL,
	NextSelectionRight = NIL,
	NextSelectionUp = NIL,
	Position = UDim2.new(),
	Rotation = 0,
	Selectable = false,
	SelectionImageObject = NIL,
	SelectionOrder = 0,
	Size = UDim2.new(),
	SizeConstraint = E.SizeConstraint.RelativeXY,
	Visible = true,
	ZIndex = 1,
}, {
	Abstract = true,
	Events = events({ "InputBegan", "InputChanged", "InputEnded", "MouseEnter", "MouseLeave", "MouseMoved", "TouchTap" }),
	Methods = {
		TweenPosition = function()
			return true
		end,
		TweenSize = function()
			return true
		end,
		TweenSizeAndPosition = function()
			return true
		end,
	},
})
class("Frame", "GuiObject", { Style = E.FrameStyle.Custom })
class("CanvasGroup", "GuiObject", { GroupColor3 = WHITE, GroupTransparency = 0 })
class("ScrollingFrame", "GuiObject", { AutomaticCanvasSize = E.AutomaticSize.None, CanvasPosition = Vector2.zero, CanvasSize = UDim2.new(0, 0, 2, 0), ScrollBarImageColor3 = WHITE, ScrollBarThickness = 12, ScrollingDirection = E.ScrollingDirection.XY, ScrollingEnabled = true, ElasticBehavior = E.ElasticBehavior.WhenScrollable, VerticalScrollBarInset = E.ScrollBarInset.None, HorizontalScrollBarInset = E.ScrollBarInset.None })
local TEXT_PROPS = {
	Font = E.Font.Legacy,
	FontFace = Font.fromEnum(E.Font.Legacy),
	LineHeight = 1,
	MaxVisibleGraphemes = -1,
	RichText = false,
	Text = "Label",
	TextColor3 = Color3.fromRGB(27, 42, 53),
	TextDirection = E.TextDirection.Auto,
	TextScaled = false,
	TextSize = 8,
	TextStrokeColor3 = BLACK,
	TextStrokeTransparency = 1,
	TextTransparency = 0,
	TextTruncate = E.TextTruncate.None,
	TextWrapped = false,
	TextXAlignment = E.TextXAlignment.Center,
	TextYAlignment = E.TextYAlignment.Center,
	ContentText = "",
	TextBounds = Vector2.zero,
	TextFits = true,
}
local function withText(extra)
	local props = table.clone(TEXT_PROPS)
	for key, value in extra do
		props[key] = value
	end
	return props
end
class("TextLabel", "GuiObject", withText({}))
class("TextButton", "GuiObject", withText({ AutoButtonColor = true, Modal = false, Selected = false, Style = E.ButtonStyle.Custom, Text = "Button" }), {
	Events = events({ "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseButton2Click" }),
})
class("TextBox", "GuiObject", withText({ ClearTextOnFocus = true, MultiLine = false, PlaceholderColor3 = Color3.fromRGB(178, 178, 178), PlaceholderText = "", TextEditable = true }), {
	Events = events({ "FocusLost", "Focused" }),
})
local IMAGE_PROPS = {
	Image = "",
	ImageColor3 = WHITE,
	ImageRectOffset = Vector2.zero,
	ImageRectSize = Vector2.zero,
	ImageTransparency = 0,
	ResampleMode = E.ResamplerMode.Default,
	ScaleType = E.ScaleType.Stretch,
	SliceCenter = Rect.new(0, 0, 0, 0),
	SliceScale = 1,
	TileSize = UDim2.fromScale(1, 1),
}
class("ImageLabel", "GuiObject", table.clone(IMAGE_PROPS))
local imageButtonProps = table.clone(IMAGE_PROPS)
imageButtonProps.AutoButtonColor = true
imageButtonProps.HoverImage = ""
imageButtonProps.PressedImage = ""
imageButtonProps.Modal = false
imageButtonProps.Selected = false
class("ImageButton", "GuiObject", imageButtonProps, { Events = events({ "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up" }) })
class("ViewportFrame", "GuiObject", { Ambient = Color3.fromRGB(200, 200, 200), CurrentCamera = NIL, ImageColor3 = WHITE, ImageTransparency = 0, LightColor = Color3.fromRGB(140, 140, 140), LightDirection = v3(-1, -1, -1) })
class("UIComponent", "Instance", {}, { Abstract = true })
class("UICorner", "UIComponent", { CornerRadius = udim(0, 8) })
class("UIStroke", "UIComponent", { ApplyStrokeMode = E.ApplyStrokeMode.Contextual, Color = BLACK, Enabled = true, LineJoinMode = E.LineJoinMode.Round, Thickness = 1, Transparency = 0 })
class("UIGradient", "UIComponent", { Color = ColorSequence.new(WHITE), Enabled = true, Offset = Vector2.zero, Rotation = 0, Transparency = NumberSequence.new(0) })
class("UIPadding", "UIComponent", { PaddingBottom = udim(0, 0), PaddingLeft = udim(0, 0), PaddingRight = udim(0, 0), PaddingTop = udim(0, 0) })
class("UIScale", "UIComponent", { Scale = 1 })
class("UIAspectRatioConstraint", "UIComponent", { AspectRatio = 1, AspectType = E.AspectType.FitWithinMaxSize, DominantAxis = E.DominantAxis.Width })
class("UISizeConstraint", "UIComponent", { MaxSize = v2(math.huge, math.huge), MinSize = Vector2.zero })
class("UITextSizeConstraint", "UIComponent", { MaxTextSize = 100, MinTextSize = 1 })
class("UIListLayout", "UIComponent", { FillDirection = E.FillDirection.Vertical, HorizontalAlignment = E.HorizontalAlignment.Left, HorizontalFlex = E.UIFlexAlignment.None, ItemLineAlignment = E.ItemLineAlignment.Automatic, Padding = udim(0, 0), SortOrder = E.SortOrder.LayoutOrder, VerticalAlignment = E.VerticalAlignment.Top, VerticalFlex = E.UIFlexAlignment.None, Wraps = false })
class("UIGridLayout", "UIComponent", { CellPadding = UDim2.fromOffset(5, 5), CellSize = UDim2.fromOffset(100, 100), FillDirection = E.FillDirection.Horizontal, FillDirectionMaxCells = 0, HorizontalAlignment = E.HorizontalAlignment.Left, SortOrder = E.SortOrder.LayoutOrder, StartCorner = E.StartCorner.TopLeft, VerticalAlignment = E.VerticalAlignment.Top })
class("UIFlexItem", "UIComponent", { FlexMode = E.UIFlexMode.None, GrowRatio = 0, ShrinkRatio = 0, ItemLineAlignment = E.ItemLineAlignment.Automatic })

-- values, remotes, scripts
for _, info in {
	{ "StringValue", "" },
	{ "NumberValue", 0 },
	{ "IntValue", 0 },
	{ "BoolValue", false },
	{ "ObjectValue", NIL },
	{ "Vector3Value", Vector3.zero },
	{ "CFrameValue", CFrame.identity },
	{ "Color3Value", BLACK },
	{ "BrickColorValue", BrickColor.new("Medium stone grey") },
} do
	class(info[1], "Instance", { Value = info[2] })
end
local function noop() end
class("RemoteEvent", "Instance", {}, {
	Events = events({ "OnServerEvent", "OnClientEvent" }),
	Methods = { FireClient = noop, FireAllClients = noop, FireServer = noop },
})
class("UnreliableRemoteEvent", "RemoteEvent", {})
class("RemoteFunction", "Instance", { OnServerInvoke = NIL, OnClientInvoke = NIL }, { Methods = { InvokeClient = noop, InvokeServer = noop } })
class("BindableEvent", "Instance", {}, {
	Events = events({ "Event" }),
	Methods = {
		Fire = function(self, ...)
			self.Event:Fire(...)
		end,
	},
})
class("BindableFunction", "Instance", { OnInvoke = NIL }, {
	Methods = {
		Invoke = function(self, ...)
			local callback = self.OnInvoke
			if callback then
				return callback(...)
			end
			fail("BindableFunction:Invoke with no OnInvoke", 2)
		end,
	},
})
class("LuaSourceContainer", "Instance", {}, { Abstract = true })
class("ModuleScript", "LuaSourceContainer", { Source = "", LinkedSource = "" })
class("Script", "LuaSourceContainer", { Disabled = false, Enabled = true, RunContext = E.RunContext.Legacy, Source = "" })
class("LocalScript", "Script", {})
class("Tool", "Model", { CanBeDropped = true, Enabled = true, Grip = CFrame.identity, ManualActivationOnly = false, RequiresHandle = true, ToolTip = "", TextureId = "" }, {
	Events = events({ "Activated", "Deactivated", "Equipped", "Unequipped" }),
})
class("Team", "Instance", { AutoAssignable = true, TeamColor = BrickColor.new("White") })
class("Tween", "Instance", { Instance = NIL, PlaybackState = E.PlaybackState.Begin, TweenInfo = NIL }, {
	Events = events({ "Completed" }),
	Methods = {
		Play = function(self)
			self.PlaybackState = Enum.PlaybackState.Playing
		end,
		Pause = function(self)
			self.PlaybackState = Enum.PlaybackState.Paused
		end,
		Cancel = function(self)
			self.PlaybackState = Enum.PlaybackState.Cancelled
		end,
	},
})

-- lighting
class("Atmosphere", "Instance", { Color = Color3.fromRGB(199, 199, 199), Decay = Color3.fromRGB(106, 112, 125), Density = 0.395, Glare = 0, Haze = 0, Offset = 0 })
class("Sky", "Instance", {
	CelestialBodiesShown = true,
	MoonAngularSize = 11,
	MoonTextureId = "rbxasset://sky/moon.jpg",
	SkyboxBk = "rbxasset://textures/sky/sky512_bk.tex",
	SkyboxDn = "rbxasset://textures/sky/sky512_dn.tex",
	SkyboxFt = "rbxasset://textures/sky/sky512_ft.tex",
	SkyboxLf = "rbxasset://textures/sky/sky512_lf.tex",
	SkyboxRt = "rbxasset://textures/sky/sky512_rt.tex",
	SkyboxUp = "rbxasset://textures/sky/sky512_up.tex",
	SkyboxOrientation = Vector3.zero,
	StarCount = 3000,
	SunAngularSize = 21,
	SunTextureId = "rbxasset://sky/sun.jpg",
})
class("Clouds", "Instance", { Color = WHITE, Cover = 0.5, Density = 0.7, Enabled = true })
class("PostEffect", "Instance", { Enabled = true }, { Abstract = true })
class("BloomEffect", "PostEffect", { Intensity = 1, Size = 24, Threshold = 2 })
class("BlurEffect", "PostEffect", { Size = 24 })
class("ColorCorrectionEffect", "PostEffect", { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = WHITE })
class("ColorGradingEffect", "PostEffect", { TonemapperPreset = E.TonemapperPreset.Default })
class("DepthOfFieldEffect", "PostEffect", { FarIntensity = 0.75, FocusDistance = 0.05, InFocusRadius = 10, NearIntensity = 0.75 })
class("SunRaysEffect", "PostEffect", { Intensity = 0.25, Spread = 1 })
class("Lighting", "Instance", {
	Ambient = BLACK,
	Brightness = 2,
	ClockTime = 14,
	ColorShift_Bottom = BLACK,
	ColorShift_Top = BLACK,
	EnvironmentDiffuseScale = 0,
	EnvironmentSpecularScale = 0,
	ExposureCompensation = 0,
	FogColor = Color3.fromRGB(192, 192, 192),
	FogEnd = 100000,
	FogStart = 0,
	GeographicLatitude = 41.733,
	GlobalShadows = true,
	LightingStyle = E.LightingStyle.Realistic,
	OutdoorAmbient = Color3.fromRGB(128, 128, 128),
	PrioritizeLightingQuality = true,
	ShadowSoftness = 0.2,
	Technology = E.Technology.ShadowMap,
}, { Service = true, Events = events({ "LightingChanged" }) })

-- services (most only need to exist)
for _, name in {
	"ReplicatedStorage", "ReplicatedFirst", "ServerStorage", "ServerScriptService", "StarterGui", "StarterPack",
	"StarterPlayer", "SoundService", "Chat", "TextChatService", "LocalizationService", "MaterialService",
	"Teams", "Debris", "PhysicsService", "ContentProvider", "TextService", "HttpService", "CollectionService",
	"InsertService", "TweenService", "RunService", "Players", "ProximityPromptService", "AssetService",
	"GuiService", "MarketplaceService", "BadgeService", "PathfindingService", "UserInputService", "Selection",
	"ServerScriptService", "TestService", "VoiceChatService",
} do
	if not CLASSES[name] then
		class(name, "Instance", {}, { Service = true })
	end
end
CLASSES.StarterPlayer.Props = {
	CameraMaxZoomDistance = 128, CameraMinZoomDistance = 0.5, CharacterWalkSpeed = 16, CharacterJumpPower = 50,
	CharacterJumpHeight = 7.2, CharacterUseJumpPower = false, AutoJumpEnabled = true, HealthDisplayDistance = 100,
	NameDisplayDistance = 100, LoadCharacterAppearance = true, CameraMode = E.CameraMode.Classic,
	DevComputerMovementMode = E.DevComputerMovementMode.UserChoice, DevTouchMovementMode = E.DevTouchMovementMode.UserChoice,
	EnableMouseLockOption = true, CharacterMaxSlopeAngle = 89,
}
class("StarterPlayerScripts", "Instance", {})
class("StarterCharacterScripts", "StarterPlayerScripts", {})
CLASSES.Players.Props = { CharacterAutoLoads = true, MaxPlayers = 30, PreferredPlayers = 30, RespawnTime = 5, BubbleChat = true, ClassicChat = false, LocalPlayer = NIL }
CLASSES.Players.Events = events({ "PlayerAdded", "PlayerRemoving", "PlayerMembershipChanged" })
CLASSES.SoundService.Props = { RespectFilteringEnabled = true, AmbientReverb = E.ReverbType.NoReverb, DistanceFactor = 3.33, DopplerScale = 1, RolloffScale = 1 }
CLASSES.ProximityPromptService.Props = { Enabled = true, MaxPromptsVisible = 16 }
CLASSES.ProximityPromptService.Events = events({ "PromptTriggered", "PromptShown", "PromptHidden" })
CLASSES.StarterGui.Props = { ResetPlayerGuiOnSpawn = true, ScreenOrientation = E.ScreenOrientation.LandscapeSensor, ShowDevelopmentGui = true }
CLASSES.RunService.Events = events({ "Heartbeat", "Stepped", "RenderStepped", "PreSimulation", "PostSimulation", "PreRender", "PreAnimation" })
CLASSES.MarketplaceService.Events = events({ "PromptProductPurchaseFinished", "PromptGamePassPurchaseFinished", "PromptPurchaseFinished" })
CLASSES.UserInputService.Props = { TouchEnabled = false, KeyboardEnabled = true, MouseEnabled = true, GamepadEnabled = false, MouseBehavior = E.MouseBehavior.Default, MouseIconEnabled = true }
CLASSES.UserInputService.Events = events({ "InputBegan", "InputChanged", "InputEnded", "JumpRequest", "LastInputTypeChanged" })
CLASSES.DataModel = { Name = "DataModel", Super = "Instance", Props = { PlaceId = 0, GameId = 0, JobId = "", CreatorId = 0, PlaceVersion = 0 }, Events = events({ "Close" }), Methods = {}, Getters = {}, Setters = {} }

---------------------------------------------------------------------------------------------------- property lookup
-- Returns the property's default (NIL for nil defaults, which may be `false` for booleans) or nil when
-- the class has no such property.
local NOT_FOUND = {}
local propCache = {}
local function findProp(className, key)
	local cache = propCache[className]
	if not cache then
		cache = {}
		propCache[className] = cache
	end
	local hit = cache[key]
	if hit ~= nil then
		if hit == NOT_FOUND then
			return nil
		end
		return hit
	end
	local current = className
	while current do
		local def = CLASSES[current]
		local value = def.Props[key]
		if value ~= nil then
			cache[key] = value
			return value
		end
		current = def.Super
	end
	cache[key] = NOT_FOUND
	return nil
end
local function findIn(className, field, key)
	local current = className
	while current do
		local def = CLASSES[current]
		local value = def[field][key]
		if value ~= nil then
			return value
		end
		current = def.Super
	end
	return nil
end
local function isA(className, target)
	local current = className
	while current do
		if current == target then
			return true
		end
		current = CLASSES[current].Super
	end
	return false
end

---------------------------------------------------------------------------------------------------- instances
local Instance = {}
local IM = { __kind = "Instance" }
local methods = {} -- shared Instance methods
local allInstances = setmetatable({}, { __mode = "k" })

local function fullName(object)
	local names = {}
	local node = object
	while node and node.__class ~= "DataModel" do
		table.insert(names, 1, node.__props.Name)
		node = rawget(node, "__parent")
	end
	return table.concat(names, ".")
end

local function describe(object)
	return fmt("%s %q", object.__class, fullName(object))
end

local function newObject(className)
	local object = setmetatable({
		__kind = "Instance",
		__class = className,
		__props = { Name = className },
		__children = {},
		__attributes = {},
		__tags = {},
		__signals = {},
	}, IM)
	allInstances[object] = true
	Mock.Stats.Instances += 1
	return object
end

function Instance.new(className, parent)
	if type(className) ~= "string" then
		fail("Instance.new expects a class name", 2)
	end
	local def = CLASSES[className]
	if not def then
		fail(fmt("Instance.new(%q): unknown class (add it to CLASSES in tools/preview/MapMock.luau)", className), 2)
	end
	if def.Abstract or def.Service then
		fail(fmt("Instance.new(%q): class can't be created", className), 2)
	end
	local object = newObject(className)
	if className == "Model" then
		rawset(object, "__pivotSet", false)
	end
	if parent then
		object.Parent = parent
	end
	return object
end

local function getSignal(object, key)
	local signal = object.__signals[key]
	if not signal then
		signal = newSignal(key)
		object.__signals[key] = signal
	end
	return signal
end

local function forEachDescendant(object, fn)
	for _, child in object.__children do
		fn(child)
		forEachDescendant(child, fn)
	end
end

local function fireUp(object, signalName, subject)
	local node = rawget(object, "__parent")
	while node do
		local signal = node.__signals[signalName]
		if signal then
			signal:Fire(subject)
		end
		node = rawget(node, "__parent")
	end
end

local function isDescendantOf(object, ancestor)
	local node = rawget(object, "__parent")
	while node do
		if node == ancestor then
			return true
		end
		node = rawget(node, "__parent")
	end
	return false
end

local function setParent(object, parent)
	if rawget(object, "__destroyed") then
		fail(fmt("The Parent property of %s is locked (it was destroyed)", describe(object)), 3)
	end
	if parent ~= nil and kindOf(parent) ~= "Instance" then
		fail(fmt("bad Parent for %s: expected Instance, got %s", describe(object), kindOf(parent)), 3)
	end
	if parent == object or (parent and isDescendantOf(parent, object)) then
		fail(fmt("can't parent %s to itself or a descendant", describe(object)), 3)
	end
	local old = rawget(object, "__parent")
	if old == parent then
		return
	end
	if old then
		fireUp(object, "DescendantRemoving", object)
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
		fireUp(object, "DescendantAdded", object)
		local hasListeners = false
		local node = parent
		while node do
			if node.__signals.DescendantAdded then
				hasListeners = true
				break
			end
			node = rawget(node, "__parent")
		end
		if hasListeners then
			forEachDescendant(object, function(descendant)
				fireUp(object, "DescendantAdded", descendant)
			end)
		end
	end
	if object.__signals.AncestryChanged then
		object.__signals.AncestryChanged:Fire(object, parent)
	end
	-- wake threads waiting for this child
	local waiting = parent and rawget(parent, "__waiting")
	if waiting then
		local name = object.__props.Name
		local list = waiting[name]
		if list then
			waiting[name] = nil
			for _, thread in list do
				schedule(Mock.Now, thread, object)
			end
		end
	end
end

-- Values that can be stored in a property whose default is `default`; returns the (coerced) value or fails
local function coerce(object, key, default, value)
	if default == NIL then
		return value
	end
	local want = kindOf(default)
	local got = kindOf(value)
	if want == got then
		if want == "EnumItem" and rawget(value, "EnumType") ~= rawget(default, "EnumType") then
			fail(fmt("bad value for %s.%s: expected Enum.%s, got %s", object.__class, key, enumName(default), tostring(value)), 4)
		end
		return value
	end
	if want == "EnumItem" and (got == "string" or got == "number") then
		local enum = rawget(default, "EnumType")
		if got == "string" then
			return enum[value]
		end
		local item = enum:FromValue(value)
		if item then
			return item
		end
	elseif want == "string" and got == "number" then
		return tostring(value)
	elseif want == "number" and got == "string" and tonumber(value) then
		return tonumber(value)
	elseif want == "Font" and got == "EnumItem" then
		return Font.fromEnum(value)
	end
	if value == nil and (want == "string") then
		fail(fmt("bad value for %s.%s: nil", object.__class, key), 4)
	end
	fail(fmt("bad value for %s.%s: expected %s, got %s", object.__class, key, want, got), 4)
end

-- computed properties ------------------------------------------------------------------------------
local function partGet(object, key)
	local props = object.__props
	if key == "Position" then
		local c = props.CFrame or CFrame.identity
		return v3(c[1], c[2], c[3])
	elseif key == "Orientation" then
		local rx, ry, rz = CFmethods.ToOrientation(props.CFrame or CFrame.identity)
		return v3(math.deg(rx), math.deg(ry), math.deg(rz))
	elseif key == "Rotation" then
		local rx, ry, rz = CFmethods.ToEulerAnglesXYZ(props.CFrame or CFrame.identity)
		return v3(math.deg(rx), math.deg(ry), math.deg(rz))
	elseif key == "BrickColor" then
		return BrickColor.new(props.Color or GREY)
	elseif key == "AssemblyMass" or key == "Mass" then
		local size = props.Size or v3(4, 1, 2)
		return size.X * size.Y * size.Z * 0.7
	elseif key == "ExtentsSize" then
		return props.Size or v3(4, 1, 2)
	elseif key == "ExtentsCFrame" then
		return props.CFrame or CFrame.identity
	elseif key == "AssemblyRootPart" then
		return object
	elseif key == "ResizeIncrement" then
		return 1
	end
	return nil
end
local function partSet(object, key, value)
	local props = object.__props
	if key == "Position" then
		local c = props.CFrame or CFrame.identity
		props.CFrame = cf(value.X, value.Y, value.Z, c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
		return true
	elseif key == "Orientation" then
		local c = props.CFrame or CFrame.identity
		props.CFrame = CFrame.new(c[1], c[2], c[3]) * CFrame.fromOrientation(math.rad(value.X), math.rad(value.Y), math.rad(value.Z))
		return true
	elseif key == "Rotation" then
		local c = props.CFrame or CFrame.identity
		props.CFrame = CFrame.new(c[1], c[2], c[3]) * CFrame.Angles(math.rad(value.X), math.rad(value.Y), math.rad(value.Z))
		return true
	elseif key == "BrickColor" then
		if kindOf(value) ~= "BrickColor" then
			fail(fmt("bad value for %s.BrickColor: expected BrickColor, got %s", object.__class, kindOf(value)), 4)
		end
		props.Color = value.Color
		return true
	end
	return false
end

local function attachmentParentCFrame(object)
	local parent = rawget(object, "__parent")
	if parent and isA(parent.__class, "BasePart") then
		return parent.__props.CFrame or CFrame.identity
	elseif parent and isA(parent.__class, "Attachment") then
		return mulCF(attachmentParentCFrame(parent), parent.__props.CFrame or CFrame.identity)
	end
	return CFrame.identity
end
local function attachmentGet(object, key)
	local c = object.__props.CFrame or CFrame.identity
	if key == "Position" then
		return v3(c[1], c[2], c[3])
	elseif key == "Orientation" then
		local rx, ry, rz = CFmethods.ToOrientation(c)
		return v3(math.deg(rx), math.deg(ry), math.deg(rz))
	elseif key == "WorldCFrame" then
		return mulCF(attachmentParentCFrame(object), c)
	elseif key == "WorldPosition" then
		return mulCF(attachmentParentCFrame(object), c).Position
	elseif key == "WorldOrientation" then
		local rx, ry, rz = CFmethods.ToOrientation(mulCF(attachmentParentCFrame(object), c))
		return v3(math.deg(rx), math.deg(ry), math.deg(rz))
	elseif key == "Axis" then
		return v3(c[4], c[7], c[10])
	elseif key == "SecondaryAxis" then
		return v3(c[5], c[8], c[11])
	end
	return nil
end
local function attachmentSet(object, key, value)
	local props = object.__props
	local c = props.CFrame or CFrame.identity
	if key == "Position" then
		props.CFrame = cf(value.X, value.Y, value.Z, c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
		return true
	elseif key == "Orientation" then
		props.CFrame = CFrame.new(c[1], c[2], c[3]) * CFrame.fromOrientation(math.rad(value.X), math.rad(value.Y), math.rad(value.Z))
		return true
	elseif key == "WorldCFrame" then
		props.CFrame = mulCF(inverseCF(attachmentParentCFrame(object)), value)
		return true
	elseif key == "WorldPosition" then
		local local_ = pointToWorld(inverseCF(attachmentParentCFrame(object)), value)
		props.CFrame = cf(local_.X, local_.Y, local_.Z, c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
		return true
	elseif key == "Axis" or key == "SecondaryAxis" then
		local axis = if key == "Axis" then value.Unit else v3(c[4], c[7], c[10])
		local secondary = if key == "SecondaryAxis" then value.Unit else v3(c[5], c[8], c[11])
		props.CFrame = CFrame.fromMatrix(v3(c[1], c[2], c[3]), axis, secondary)
		return true
	end
	return false
end

local modelPivot -- forward declarations (Model helpers below)
local modelSetPivot

IM.__index = function(self, key)
	if key == "Parent" then
		return rawget(self, "__parent")
	elseif key == "ClassName" then
		return self.__class
	end
	local className = self.__class
	local props = self.__props
	local value = props[key]
	if value ~= nil then
		return value
	end
	local default = findProp(className, key)
	if default ~= nil then
		if default == NIL then
			return nil
		end
		return default
	end
	local method = methods[key] or findIn(className, "Methods", key)
	if method then
		return method
	end
	if isA(className, "BasePart") then
		local computed = partGet(self, key)
		if computed ~= nil then
			return computed
		end
	elseif className == "Attachment" or className == "Bone" then
		local computed = attachmentGet(self, key)
		if computed ~= nil then
			return computed
		end
	elseif isA(className, "Model") and key == "WorldPivot" then
		return modelPivot(self)
	elseif isA(className, "GuiObject") and key == "Transparency" then
		return props.BackgroundTransparency or 0
	end
	local getter = findIn(className, "Getters", key)
	if getter then
		return getter(self)
	end
	if findIn(className, "Events", key) then
		return getSignal(self, key)
	end
	for _, child in self.__children do
		if child.__props.Name == key then
			return child
		end
	end
	fail(fmt("%q is not a valid member of %s (if the game really uses it, add it to tools/preview/MapMock.luau)", tostring(key), describe(self)), 2)
end

IM.__newindex = function(self, key, value)
	if key == "Parent" then
		setParent(self, value)
		return
	end
	local className = self.__class
	local props = self.__props
	if key == "Name" then
		if type(value) ~= "string" then
			if type(value) == "number" then
				value = tostring(value)
			else
				fail(fmt("bad value for %s.Name: expected string, got %s", className, kindOf(value)), 2)
			end
		end
		props.Name = value
		return
	elseif key == "ClassName" then
		fail("ClassName is read-only", 2)
	end
	local default = findProp(className, key)
	if default ~= nil then
		if key == "DoubleSided" and className == "MeshPart" then
			fail("The current thread cannot write 'DoubleSided' (lacking capability Plugin) - Roblox scripts can't set MeshPart.DoubleSided either", 2)
		elseif key == "MeshSize" or key == "TextBounds" or key == "TextFits" or key == "IsPlaying" or key == "TimeLength" then
			fail(fmt("%s.%s is read-only", className, key), 2)
		end
		value = coerce(self, key, default, value)
		if isA(className, "Model") and key == "PrimaryPart" and value ~= nil then
			if not (kindOf(value) == "Instance" and isA(value.__class, "BasePart")) then
				fail(fmt("bad value for %s.PrimaryPart: expected a BasePart", describe(self)), 2)
			end
		end
		if className == "Part" and key == "Shape" and value == Enum.PartType.Ball then
			local size = props.Size or v3(4, 1, 2)
			local d = math.min(size.X, size.Y, size.Z)
			props.Size = v3(d, d, d)
		end
		if key == "Size" and isA(className, "BasePart") then
			value = v3(math.max(value.X, 0.001), math.max(value.Y, 0.001), math.max(value.Z, 0.001))
			if className == "Part" and props.Shape == Enum.PartType.Ball then
				-- Roblox keeps balls round: all three axes take the axis that changed (approximated as the min)
				local d = math.min(value.X, value.Y, value.Z)
				value = v3(d, d, d)
			end
		end
		props[key] = value
	elseif isA(className, "BasePart") and partSet(self, key, value) then
		-- computed property written
	elseif (className == "Attachment" or className == "Bone") and attachmentSet(self, key, value) then
		-- computed property written
	elseif isA(className, "Model") and key == "WorldPivot" then
		if kindOf(value) ~= "CFrame" then
			fail(fmt("bad value for %s.WorldPivot: expected CFrame, got %s", describe(self), kindOf(value)), 2)
		end
		modelSetPivot(self, value)
	elseif isA(className, "GuiObject") and key == "Transparency" then
		props.BackgroundTransparency = value
	elseif findIn(className, "Setters", key) then
		findIn(className, "Setters", key)(self, value)
	else
		fail(fmt("%q is not a valid property of %s (if the game really uses it, add it to CLASSES in tools/preview/MapMock.luau)", tostring(key), describe(self)), 2)
	end
	local signals = self.__signals
	local changed = signals["Changed:" .. key]
	if changed then
		changed:Fire()
	end
	if signals.Changed then
		signals.Changed:Fire(key)
	end
end

IM.__tostring = function(self)
	return self.__props.Name
end

-- Instance methods ---------------------------------------------------------------------------------
local function checkSelf(self, name)
	if kindOf(self) ~= "Instance" then
		fail(fmt("%s must be called with ':' (got %s as self)", name, kindOf(self)), 3)
	end
end

function methods.IsA(self, className)
	checkSelf(self, "IsA")
	if not CLASSES[className] and className ~= "Instance" then
		return false
	end
	return isA(self.__class, className)
end
function methods.GetChildren(self)
	checkSelf(self, "GetChildren")
	return table.clone(self.__children)
end
function methods.GetDescendants(self)
	checkSelf(self, "GetDescendants")
	local list = {}
	forEachDescendant(self, function(descendant)
		table.insert(list, descendant)
	end)
	return list
end
function methods.FindFirstChild(self, name, recursive)
	checkSelf(self, "FindFirstChild")
	for _, child in self.__children do
		if child.__props.Name == name then
			return child
		end
	end
	if recursive then
		for _, child in self.__children do
			local found = methods.FindFirstChild(child, name, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function methods.FindFirstDescendant(self, name)
	return methods.FindFirstChild(self, name, true)
end
function methods.FindFirstChildOfClass(self, className)
	checkSelf(self, "FindFirstChildOfClass")
	for _, child in self.__children do
		if child.__class == className then
			return child
		end
	end
	return nil
end
function methods.FindFirstChildWhichIsA(self, className, recursive)
	checkSelf(self, "FindFirstChildWhichIsA")
	for _, child in self.__children do
		if isA(child.__class, className) then
			return child
		end
	end
	if recursive then
		for _, child in self.__children do
			local found = methods.FindFirstChildWhichIsA(child, className, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function methods.FindFirstAncestor(self, name)
	local node = rawget(self, "__parent")
	while node do
		if node.__props.Name == name then
			return node
		end
		node = rawget(node, "__parent")
	end
	return nil
end
function methods.FindFirstAncestorOfClass(self, className)
	local node = rawget(self, "__parent")
	while node do
		if node.__class == className then
			return node
		end
		node = rawget(node, "__parent")
	end
	return nil
end
function methods.FindFirstAncestorWhichIsA(self, className)
	local node = rawget(self, "__parent")
	while node do
		if isA(node.__class, className) then
			return node
		end
		node = rawget(node, "__parent")
	end
	return nil
end
function methods.WaitForChild(self, name, timeout)
	checkSelf(self, "WaitForChild")
	local child = methods.FindFirstChild(self, name)
	if child then
		return child
	end
	if not currentThreadCanYield() then
		fail(fmt("WaitForChild(%q) on %s would yield forever", name, describe(self)), 2)
	end
	local thread = coroutine.running()
	local waiting = rawget(self, "__waiting")
	if not waiting then
		waiting = {}
		rawset(self, "__waiting", waiting)
	end
	waiting[name] = waiting[name] or {}
	table.insert(waiting[name], thread)
	if timeout then
		schedule(Mock.Now + timeout, thread, nil)
	else
		table.insert(Scheduler.Waiting, { Thread = thread, What = fmt("%s:WaitForChild(%q)", fullName(self), name) })
	end
	local found = coroutine.yield()
	return found
end
function methods.IsDescendantOf(self, ancestor)
	return isDescendantOf(self, ancestor)
end
function methods.IsAncestorOf(self, descendant)
	return isDescendantOf(descendant, self)
end
function methods.GetFullName(self)
	return fullName(self)
end
function methods.GetDebugId(self)
	return tostring(self.__props.Name)
end
local ATTRIBUTE_TYPES = {
	string = true, number = true, boolean = true, Vector3 = true, Vector2 = true, Color3 = true, CFrame = true,
	UDim = true, UDim2 = true, BrickColor = true, NumberSequence = true, ColorSequence = true, NumberRange = true,
	Rect = true, EnumItem = true, Font = true,
}
function methods.SetAttribute(self, name, value)
	checkSelf(self, "SetAttribute")
	if type(name) ~= "string" then
		fail("SetAttribute: name must be a string", 2)
	end
	if value ~= nil and not ATTRIBUTE_TYPES[kindOf(value)] then
		fail(fmt("SetAttribute(%q): %s is not a supported attribute type", name, kindOf(value)), 2)
	end
	self.__attributes[name] = value
	local signal = self.__signals["Attr:" .. name]
	if signal then
		signal:Fire()
	end
	if self.__signals.AttributeChanged then
		self.__signals.AttributeChanged:Fire(name)
	end
end
function methods.GetAttribute(self, name)
	checkSelf(self, "GetAttribute")
	return self.__attributes[name]
end
function methods.GetAttributes(self)
	return table.clone(self.__attributes)
end
function methods.GetAttributeChangedSignal(self, name)
	return getSignal(self, "Attr:" .. name)
end
function methods.GetPropertyChangedSignal(self, name)
	return getSignal(self, "Changed:" .. name)
end
function methods.ClearAllChildren(self)
	for _, child in table.clone(self.__children) do
		methods.Destroy(child)
	end
end
function methods.Destroy(self)
	checkSelf(self, "Destroy")
	if rawget(self, "__destroyed") then
		return
	end
	if self.__signals.Destroying then
		self.__signals.Destroying:Fire()
	end
	for _, child in table.clone(self.__children) do
		methods.Destroy(child)
	end
	setParent(self, nil)
	rawset(self, "__destroyed", true)
end
methods.Remove = function(self)
	setParent(self, nil)
end
function methods.AddTag(self, tag)
	self.__tags[tag] = true
end
function methods.RemoveTag(self, tag)
	self.__tags[tag] = nil
end
function methods.HasTag(self, tag)
	return self.__tags[tag] == true
end
function methods.GetTags(self)
	local list = {}
	for tag in self.__tags do
		table.insert(list, tag)
	end
	table.sort(list)
	return list
end
function methods.GetActor()
	return nil
end
function methods.GetStyled(self, name)
	return self[name]
end

local function cloneTree(object, map)
	if object.__props.Archivable == false then -- __props only holds values that were set (default true)
		return nil
	end
	local copy = newObject(object.__class)
	copy.__props = table.clone(object.__props)
	copy.__attributes = table.clone(object.__attributes)
	copy.__tags = table.clone(object.__tags)
	rawset(copy, "__pivot", rawget(object, "__pivot"))
	rawset(copy, "__pivotSet", rawget(object, "__pivotSet"))
	rawset(copy, "__scale", rawget(object, "__scale"))
	map[object] = copy
	for _, child in object.__children do
		local childCopy = cloneTree(child, map)
		if childCopy then
			rawset(childCopy, "__parent", copy)
			table.insert(copy.__children, childCopy)
		end
	end
	return copy
end
function methods.Clone(self)
	checkSelf(self, "Clone")
	local map = {}
	local copy = cloneTree(self, map)
	if not copy then
		return nil
	end
	-- references inside the cloned tree point at the clones (PrimaryPart, Part0, Adornee, Attachment0...)
	for _, clone in map do
		for key, value in clone.__props do
			if type(value) == "table" and rawget(value, "__kind") == "Instance" and map[value] then
				clone.__props[key] = map[value]
			end
		end
	end
	return copy
end

-- PVInstance: pivots, bounding boxes, scaling --------------------------------------------------------
local function eachPart(object, fn)
	if isA(object.__class, "BasePart") then
		fn(object)
	end
	forEachDescendant(object, function(descendant)
		if isA(descendant.__class, "BasePart") and descendant.__class ~= "Terrain" then
			fn(descendant)
		end
	end)
end

local function boundingBox(model, orientation)
	orientation = orientation or CFrame.identity
	local inverse = inverseCF(orientation)
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local any = false
	eachPart(model, function(part)
		if part == model then
			return
		end
		any = true
		local c = mulCF(inverse, part.__props.CFrame or CFrame.identity)
		local size = part.__props.Size or v3(4, 1, 2)
		local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
		-- extent of the rotated box along each axis
		local ex = math.abs(c[4]) * hx + math.abs(c[5]) * hy + math.abs(c[6]) * hz
		local ey = math.abs(c[7]) * hx + math.abs(c[8]) * hy + math.abs(c[9]) * hz
		local ez = math.abs(c[10]) * hx + math.abs(c[11]) * hy + math.abs(c[12]) * hz
		minX, maxX = math.min(minX, c[1] - ex), math.max(maxX, c[1] + ex)
		minY, maxY = math.min(minY, c[2] - ey), math.max(maxY, c[2] + ey)
		minZ, maxZ = math.min(minZ, c[3] - ez), math.max(maxZ, c[3] + ez)
	end)
	if not any then
		return orientation, Vector3.zero
	end
	local center = pointToWorld(orientation, v3((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2))
	local rot = orientation
	return cf(center.X, center.Y, center.Z, rot[4], rot[5], rot[6], rot[7], rot[8], rot[9], rot[10], rot[11], rot[12]), v3(maxX - minX, maxY - minY, maxZ - minZ)
end

function modelPivot(model)
	local primary = model.__props.PrimaryPart
	if primary and not rawget(primary, "__destroyed") then
		return mulCF(primary.__props.CFrame or CFrame.identity, primary.__props.PivotOffset or CFrame.identity)
	end
	if rawget(model, "__pivotSet") then
		return rawget(model, "__pivot")
	end
	-- never set: Roblox uses the centre of the parts' bounding box
	local box = boundingBox(model, CFrame.identity)
	return cf(box[1], box[2], box[3], 1, 0, 0, 0, 1, 0, 0, 0, 1)
end

function modelSetPivot(model, value)
	local primary = model.__props.PrimaryPart
	if primary then
		-- WorldPivot on a model with a PrimaryPart sets the part's PivotOffset
		primary.__props.PivotOffset = mulCF(inverseCF(primary.__props.CFrame or CFrame.identity), value)
	else
		rawset(model, "__pivot", value)
		rawset(model, "__pivotSet", true)
	end
end

local function moveTree(object, delta)
	eachPart(object, function(part)
		part.__props.CFrame = mulCF(delta, part.__props.CFrame or CFrame.identity)
	end)
	local function movePivots(node)
		if isA(node.__class, "Model") and rawget(node, "__pivotSet") and not node.__props.PrimaryPart then
			rawset(node, "__pivot", mulCF(delta, rawget(node, "__pivot")))
		end
	end
	movePivots(object)
	forEachDescendant(object, movePivots)
end

function methods.GetPivot(self)
	checkSelf(self, "GetPivot")
	if isA(self.__class, "Model") then
		return modelPivot(self)
	elseif isA(self.__class, "BasePart") then
		return mulCF(self.__props.CFrame or CFrame.identity, self.__props.PivotOffset or CFrame.identity)
	end
	fail("GetPivot is not a valid member of " .. describe(self), 2)
end
function methods.PivotTo(self, target)
	checkSelf(self, "PivotTo")
	if kindOf(target) ~= "CFrame" then
		fail("PivotTo expects a CFrame, got " .. kindOf(target), 2)
	end
	if isA(self.__class, "Model") then
		local current = modelPivot(self)
		local delta = mulCF(target, inverseCF(current))
		moveTree(self, delta)
		if not self.__props.PrimaryPart then
			rawset(self, "__pivot", target)
			rawset(self, "__pivotSet", true)
		end
	elseif isA(self.__class, "BasePart") then
		local offset = self.__props.PivotOffset or CFrame.identity
		self.__props.CFrame = mulCF(target, inverseCF(offset))
	else
		fail("PivotTo is not a valid member of " .. describe(self), 2)
	end
end
function methods.GetBoundingBox(self)
	if not isA(self.__class, "Model") then
		fail("GetBoundingBox is not a valid member of " .. describe(self), 2)
	end
	local pivot = modelPivot(self)
	return boundingBox(self, cf(0, 0, 0, pivot[4], pivot[5], pivot[6], pivot[7], pivot[8], pivot[9], pivot[10], pivot[11], pivot[12]))
end
function methods.GetExtentsSize(self)
	local _, size = methods.GetBoundingBox(self)
	return size
end
function methods.MoveTo(self, position)
	local pivot = methods.GetPivot(self)
	methods.PivotTo(self, pivot - pivot.Position + position)
end
function methods.TranslateBy(self, offset)
	methods.PivotTo(self, methods.GetPivot(self) + offset)
end
function methods.SetPrimaryPartCFrame(self, value)
	if not self.__props.PrimaryPart then
		fail("SetPrimaryPartCFrame: " .. describe(self) .. " has no PrimaryPart", 2)
	end
	local primary = self.__props.PrimaryPart
	moveTree(self, mulCF(value, inverseCF(primary.__props.CFrame or CFrame.identity)))
end
function methods.GetPrimaryPartCFrame(self)
	local primary = self.__props.PrimaryPart
	return primary and primary.__props.CFrame or fail("GetPrimaryPartCFrame: no PrimaryPart", 2)
end
function methods.GetScale(self)
	return rawget(self, "__scale") or 1
end
function methods.ScaleTo(self, scale)
	if not isA(self.__class, "Model") then
		fail("ScaleTo is not a valid member of " .. describe(self), 2)
	end
	if type(scale) ~= "number" or scale <= 0 then
		fail("ScaleTo expects a positive number", 2)
	end
	local factor = scale / (rawget(self, "__scale") or 1)
	local pivot = modelPivot(self)
	local inverse = inverseCF(pivot)
	eachPart(self, function(part)
		local rel = mulCF(inverse, part.__props.CFrame or CFrame.identity)
		rel = cf(rel[1] * factor, rel[2] * factor, rel[3] * factor, rel[4], rel[5], rel[6], rel[7], rel[8], rel[9], rel[10], rel[11], rel[12])
		part.__props.CFrame = mulCF(pivot, rel)
		part.__props.Size = (part.__props.Size or v3(4, 1, 2)) * factor
		local offset = part.__props.PivotOffset
		if offset then
			part.__props.PivotOffset = cf(offset[1] * factor, offset[2] * factor, offset[3] * factor, offset[4], offset[5], offset[6], offset[7], offset[8], offset[9], offset[10], offset[11], offset[12])
		end
	end)
	forEachDescendant(self, function(node)
		if node.__class == "Attachment" then
			local c = node.__props.CFrame or CFrame.identity
			node.__props.CFrame = cf(c[1] * factor, c[2] * factor, c[3] * factor, c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
		elseif node.__class == "SpecialMesh" and node.__props.MeshType == Enum.MeshType.FileMesh then
			node.__props.Scale = (node.__props.Scale or Vector3.one) * factor
		end
	end)
	rawset(self, "__scale", scale)
end
function methods.GetMass(self)
	return partGet(self, "Mass")
end
function methods.GetConnectedParts()
	return {}
end
function methods.GetJoints()
	return {}
end
function methods.GetTouchingParts()
	return {}
end
function methods.SetNetworkOwner() end
function methods.SetNetworkOwnershipAuto() end
function methods.CanSetNetworkOwner()
	return true
end
function methods.GetNetworkOwner()
	return nil
end
function methods.ApplyImpulse() end
function methods.ApplyAngularImpulse() end
function methods.BreakJoints() end
function methods.MakeJoints() end

---------------------------------------------------------------------------------------------------- the DataModel and services
local game = newObject("DataModel")
game.__props.Name = "Game"

local SERVICE_ALIASES = {}
local function getService(name)
	local existing = methods.FindFirstChildOfClass(game, name)
	if existing then
		return existing
	end
	local def = CLASSES[name]
	if not (def and def.Service) then
		fail(fmt("game:GetService(%q): unknown service (add it to tools/preview/MapMock.luau)", tostring(name)), 3)
	end
	local service = newObject(name)
	service.__props.Name = SERVICE_ALIASES[name] or name
	setParent(service, game)
	return service
end
local gameMethods = {}
function gameMethods.GetService(_, name)
	return getService(name)
end
function gameMethods.FindService(_, name)
	return methods.FindFirstChildOfClass(game, name)
end
function gameMethods.IsLoaded()
	return true
end
function gameMethods.BindToClose() end
CLASSES.DataModel.Methods = gameMethods
CLASSES.DataModel.Events = events({ "Close", "Loaded" })

local Workspace = getService("Workspace")
local Lighting = getService("Lighting")
local terrain = newObject("Terrain")
terrain.__props.Name = "Terrain"
terrain.__props.Anchored = true
setParent(terrain, Workspace)
local camera = newObject("Camera")
camera.__props.Name = "Camera"
setParent(camera, Workspace)
Workspace.__props.CurrentCamera = camera
for _, name in { "ReplicatedStorage", "ServerStorage", "ServerScriptService", "Players", "StarterGui", "StarterPlayer", "SoundService", "RunService" } do
	getService(name)
end

-- Workspace
CLASSES.Workspace.Methods = {
	Raycast = function()
		return nil
	end,
	Blockcast = function()
		return nil
	end,
	Spherecast = function()
		return nil
	end,
	Shapecast = function()
		return nil
	end,
	GetPartBoundsInBox = function()
		return {}
	end,
	GetPartBoundsInRadius = function()
		return {}
	end,
	GetPartsInPart = function()
		return {}
	end,
	GetServerTimeNow = function()
		return Mock.ClockBase + Mock.Now
	end,
	GetRealPhysicsFPS = function()
		return 60
	end,
	BulkMoveTo = function(_, parts, cframes)
		for index, part in parts do
			part.CFrame = cframes[index]
		end
	end,
}
CLASSES.Workspace.Getters = {
	DistributedGameTime = function()
		return Mock.Now
	end,
}

-- Terrain: fills are recorded (and dumped) rather than voxelised
local TERRAIN_DEFAULT_COLORS = {
	Asphalt = "737B6B", Basalt = "1E1E25", Brick = "8A5641", Cobblestone = "847B5A", Concrete = "7F6656",
	CrackedLava = "E89C4A", Glacier = "65B0EA", Grass = "6A7F3F", Ground = "665C3B", Ice = "81C2E0",
	LeafyGrass = "73843E", Limestone = "CEAD94", Mud = "3A2E24", Pavement = "94948C", Rock = "666C6F",
	Salt = "C6BDB5", Sand = "8F7E5F", Sandstone = "89573E", Slate = "3F7F6B", Snow = "C3C7DA",
	WoodPlanks = "8B6D4F", Water = "0C545C",
}
local function terrainMaterial(material)
	if kindOf(material) ~= "EnumItem" or enumName(material) ~= "Material" then
		fail("Terrain: expected an Enum.Material, got " .. tostring(material), 3)
	end
	if material.Name ~= "Air" and material.Name ~= "Water" and not TERRAIN_DEFAULT_COLORS[material.Name] then
		fail("Terrain: " .. tostring(material) .. " is not a terrain material", 3)
	end
	return material.Name
end
local function cfList(c)
	return { c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12] }
end
CLASSES.Terrain.Methods = {
	Clear = function()
		table.clear(Mock.Fills)
	end,
	FillBlock = function(_, cframe, size, material)
		table.insert(Mock.Fills, { Kind = "Block", CFrame = cfList(cframe), Size = { size.X, size.Y, size.Z }, Material = terrainMaterial(material) })
	end,
	FillBall = function(_, center, radius, material)
		table.insert(Mock.Fills, { Kind = "Ball", Center = { center.X, center.Y, center.Z }, Radius = radius, Material = terrainMaterial(material) })
	end,
	FillCylinder = function(_, cframe, height, radius, material)
		table.insert(Mock.Fills, { Kind = "Cylinder", CFrame = cfList(cframe), Height = height, Radius = radius, Material = terrainMaterial(material) })
	end,
	FillWedge = function(_, cframe, size, material)
		table.insert(Mock.Fills, { Kind = "Wedge", CFrame = cfList(cframe), Size = { size.X, size.Y, size.Z }, Material = terrainMaterial(material) })
	end,
	FillRegion = function(_, region, resolution, material)
		local c = region.CFrame
		table.insert(Mock.Fills, { Kind = "Block", CFrame = cfList(c), Size = { region.Size.X, region.Size.Y, region.Size.Z }, Material = terrainMaterial(material) })
	end,
	SetMaterialColor = function(_, material, color)
		Mock.MaterialColors[terrainMaterial(material)] = C3methods.ToHex(color)
	end,
	GetMaterialColor = function(_, material)
		local hex = Mock.MaterialColors[material.Name] or TERRAIN_DEFAULT_COLORS[material.Name] or "808080"
		return Color3.fromHex(hex)
	end,
	ReplaceMaterial = function(_, region, resolution, source, target)
		table.insert(Mock.Warnings, "mock: Terrain:ReplaceMaterial is ignored by the preview")
	end,
	WriteVoxels = function()
		table.insert(Mock.Warnings, "mock: Terrain:WriteVoxels is ignored by the preview (only Fill* calls are drawn)")
	end,
	ReadVoxels = function(_, region)
		fail("Terrain:ReadVoxels is not supported by the preview", 2)
	end,
	CellCenterToWorld = function(_, x, y, z)
		return v3(x * 4 + 2, y * 4 + 2, z * 4 + 2)
	end,
	WorldToCellPreferSolid = function(_, position)
		return v3(math.floor(position.X / 4), math.floor(position.Y / 4), math.floor(position.Z / 4))
	end,
	WorldToCell = function(_, position)
		return v3(math.floor(position.X / 4), math.floor(position.Y / 4), math.floor(position.Z / 4))
	end,
}

-- Lighting
CLASSES.Lighting.Methods = {
	GetMinutesAfterMidnight = function(self)
		return self.ClockTime * 60
	end,
	SetMinutesAfterMidnight = function(self, minutes)
		self.ClockTime = (minutes / 60) % 24
	end,
	GetSunDirection = function(self)
		local angle = (self.ClockTime - 6) / 12 * math.pi
		return v3(math.cos(angle) * 0.5, math.sin(angle), -math.cos(angle) * 0.3).Unit
	end,
	GetMoonDirection = function(self)
		local angle = (self.ClockTime - 18) / 12 * math.pi
		return v3(math.cos(angle) * 0.5, math.sin(angle), -math.cos(angle) * 0.3).Unit
	end,
}
CLASSES.Lighting.Getters = {
	TimeOfDay = function(self)
		local t = self.ClockTime
		local hours = math.floor(t)
		local minutes = math.floor((t - hours) * 60)
		local seconds = math.floor(((t - hours) * 60 - minutes) * 60)
		return fmt("%02d:%02d:%02d", hours, minutes, seconds)
	end,
}
CLASSES.Lighting.Setters = {
	TimeOfDay = function(self, value)
		local h, m, s = string.match(value, "^(%d+):?(%d*):?(%d*)$")
		self.ClockTime = (tonumber(h) or 0) + (tonumber(m) or 0) / 60 + (tonumber(s) or 0) / 3600
	end,
}

-- RunService
CLASSES.RunService.Methods = {
	IsStudio = function()
		return true
	end,
	IsServer = function()
		return true
	end,
	IsClient = function()
		return false
	end,
	IsRunning = function()
		return true
	end,
	IsRunMode = function()
		return false
	end,
	IsEdit = function()
		return false
	end,
	BindToRenderStep = function() end,
	UnbindFromRenderStep = function() end,
}

-- Players
CLASSES.Players.Methods = {
	GetPlayers = function()
		return {}
	end,
	GetPlayerFromCharacter = function()
		return nil
	end,
	GetPlayerByUserId = function()
		return nil
	end,
	GetUserIdFromNameAsync = function()
		return 1
	end,
	GetNameFromUserIdAsync = function()
		return "Player"
	end,
	GetUserThumbnailAsync = function()
		return "rbxasset://textures/ui/GuiImagePlaceholder.png", true
	end,
}

-- CollectionService
local function taggedList(tag)
	local list = {}
	local function visit(node)
		if node.__tags[tag] then
			table.insert(list, node)
		end
		for _, child in node.__children do
			visit(child)
		end
	end
	visit(game)
	return list
end
CLASSES.CollectionService.Methods = {
	AddTag = function(_, instance, tag)
		instance.__tags[tag] = true
	end,
	RemoveTag = function(_, instance, tag)
		instance.__tags[tag] = nil
	end,
	HasTag = function(_, instance, tag)
		return instance.__tags[tag] == true
	end,
	GetTags = function(_, instance)
		return methods.GetTags(instance)
	end,
	GetTagged = function(_, tag)
		return taggedList(tag)
	end,
	GetAllTags = function()
		local set, list = {}, {}
		for object in allInstances do
			for tag in object.__tags do
				if not set[tag] then
					set[tag] = true
					table.insert(list, tag)
				end
			end
		end
		return list
	end,
	GetInstanceAddedSignal = function(self, tag)
		return getSignal(self, "TagAdded:" .. tag)
	end,
	GetInstanceRemovedSignal = function(self, tag)
		return getSignal(self, "TagRemoved:" .. tag)
	end,
}

-- TweenService: tweens are created and "played" but never move anything (the preview shows the start state)
CLASSES.TweenService.Methods = {
	Create = function(_, instance, info, goals)
		if kindOf(instance) ~= "Instance" then
			fail("TweenService:Create expects an Instance", 2)
		end
		for key, value in goals do
			local _ = instance[key] -- fail loudly on bad property names
			local _ = value
		end
		local tween = Instance.new("Tween")
		tween.__props.Instance = instance
		tween.__props.TweenInfo = info
		return tween
	end,
	GetValue = function(_, alpha)
		return alpha
	end,
	SmoothDamp = function(_, current)
		return current, Vector3.zero
	end,
}

-- InsertService: LoadAsset returns the world prop pack (when preview_map.py found the GLB)
local buildPack -- set below
CLASSES.InsertService.Methods = {
	LoadAsset = function(_, assetId)
		if type(assetId) ~= "number" then
			fail("InsertService:LoadAsset expects a number", 2)
		end
		local pack = buildPack and buildPack()
		if not pack then
			error(fmt("mock: InsertService:LoadAsset(%d) failed - no assets/models/StormWorldProps.glb to stand in for it", assetId), 2)
		end
		local wrapper = Instance.new("Model")
		wrapper.Name = "Model"
		pack.Parent = wrapper
		table.insert(Mock.Warnings, fmt("mock: InsertService:LoadAsset(%d) returned the local StormWorldProps.glb pack", assetId))
		return wrapper
	end,
	LoadAssetVersion = function(self, versionId)
		return self:LoadAsset(versionId)
	end,
}

-- Debris, PhysicsService, ContentProvider, TextService, HttpService
CLASSES.Debris.Methods = {
	AddItem = function(_, item, lifetime)
		task.delay(lifetime or 10, function()
			if not rawget(item, "__destroyed") then
				methods.Destroy(item)
			end
		end)
	end,
}
CLASSES.PhysicsService.Methods = {
	RegisterCollisionGroup = noop,
	UnregisterCollisionGroup = noop,
	CollisionGroupSetCollidable = noop,
	CollisionGroupsAreCollidable = function()
		return true
	end,
	IsCollisionGroupRegistered = function()
		return true
	end,
	GetMaxCollisionGroups = function()
		return 32
	end,
	SetPartCollisionGroup = function(_, part, group)
		part.CollisionGroup = group
	end,
}
CLASSES.ContentProvider.Methods = { PreloadAsync = noop }
CLASSES.TextService.Methods = {
	GetTextSize = function(_, text, size)
		return v2(#text * size * 0.55, size)
	end,
}
local guidCounter = 0
local function jsonEncode(value) -- forward-declared JSON writer is below; this one is for game code
	return Mock.Json(value)
end
CLASSES.HttpService.Methods = {
	GenerateGUID = function(_, wrap)
		guidCounter += 1
		local id = fmt("00000000-0000-4000-8000-%012d", guidCounter)
		return if wrap == false then id else "{" .. id .. "}"
	end,
	JSONEncode = function(_, value)
		return jsonEncode(value)
	end,
	JSONDecode = function()
		fail("HttpService:JSONDecode is not supported by the preview mock", 2)
	end,
	UrlEncode = function(_, text)
		return (string.gsub(text, "[^%w%-_%.~]", function(char)
			return fmt("%%%02X", string.byte(char))
		end))
	end,
}
CLASSES.MarketplaceService.Methods = {
	GetProductInfo = function()
		return { Name = "Product", PriceInRobux = 0, IconImageAssetId = 0 }
	end,
	UserOwnsGamePassAsync = function()
		return false
	end,
}

---------------------------------------------------------------------------------------------------- globals: typeof, warn, print, time, require
local function typeof(value)
	return kindOf(value)
end

local function joinArgs(...)
	local parts = {}
	for index = 1, select("#", ...) do
		parts[index] = tostring((select(index, ...)))
	end
	return table.concat(parts, " ")
end
local function warn(...)
	table.insert(Mock.Warnings, joinArgs(...))
end
local function print(...)
	table.insert(Mock.Prints, joinArgs(...))
end
local function tick()
	return Mock.ClockBase + Mock.Now
end
local function time()
	return Mock.Now
end

local moduleResults = {}
local moduleLoading = {}
local function require(module)
	if type(module) == "number" then
		fail(fmt("require(%d): requiring assets by id is not supported by the preview", module), 2)
	end
	if kindOf(module) ~= "Instance" or module.__class ~= "ModuleScript" then
		fail("require expects a ModuleScript, got " .. (if kindOf(module) == "Instance" then describe(module) else kindOf(module)), 2)
	end
	local result = moduleResults[module]
	if result ~= nil then
		return result
	end
	if moduleLoading[module] then
		fail("circular require of " .. fullName(module), 2)
	end
	local loader = rawget(module, "__loader")
	if not loader then
		fail("require(" .. fullName(module) .. "): no source for this module in the preview bundle", 2)
	end
	moduleLoading[module] = true
	result = loader(module)
	moduleLoading[module] = nil
	if result == nil then
		fail("module " .. fullName(module) .. " did not return a value", 2)
	end
	moduleResults[module] = result
	return result
end

---------------------------------------------------------------------------------------------------- tree building helpers used by the generated bundle
local function nodeAt(path, className)
	local node = game
	local segments = string.split(path, "/")
	for index, segment in segments do
		local child = methods.FindFirstChild(node, segment)
		if not child then
			if node == game then
				child = getService(segment)
			else
				local wanted = if index == #segments then className or "Folder" else "Folder"
				child = Instance.new(wanted)
				child.__props.Name = segment
				setParent(child, node)
			end
		end
		node = child
	end
	return node
end

function Mock.Node(path, className)
	return nodeAt(path, className)
end

function Mock.Module(path, chunkName, source)
	local segments = string.split(path, "/")
	local name = table.remove(segments)
	local parent = nodeAt(table.concat(segments, "/"))
	local module = methods.FindFirstChild(parent, name)
	if module and module.__class ~= "ModuleScript" then
		-- a folder made earlier for this path (init.luau style): turn it into a ModuleScript in place
		module.__class = "ModuleScript"
	elseif not module then
		module = Instance.new("ModuleScript")
		module.__props.Name = name
		setParent(module, parent)
	end
	module.__props.Source = ""
	rawset(module, "__loader", function(script)
		local fn, err = loadstring("local script = ...; " .. source, "=" .. chunkName)
		if not fn then
			error("mock: syntax error in " .. tostring(err), 0)
		end
		return fn(script)
	end)
	return module
end

-- Sets project-file properties ($properties in default.project.json), skipping ones the mock doesn't know
function Mock.SetProps(path, props)
	local node = nodeAt(path)
	for key, value in props do
		local default = findProp(node.__class, key)
		if default == nil then
			table.insert(Mock.Warnings, fmt("mock: project property %s.%s ignored (unknown to the mock)", node.__class, key))
			continue
		end
		local want = kindOf(default)
		if type(value) == "table" and want == "Color3" then
			value = c3(value[1], value[2], value[3])
		elseif type(value) == "table" and want == "Vector3" then
			value = v3(value[1], value[2], value[3])
		elseif type(value) == "table" and want == "Vector2" then
			value = v2(value[1], value[2])
		end
		local ok, err = pcall(function()
			node[key] = value
		end)
		if not ok then
			table.insert(Mock.Warnings, "mock: project property " .. key .. ": " .. tostring(err))
		end
	end
end

-- The WorldProps pack: WorldProps (Model) -> <PropId> (Model) -> MeshParts "<PropId>.<Paint>" and
-- "<PropId>.Root", laid out like the GLB (each prop at its slot, pieces at their bounding-box centres).
local packData = nil
function Mock.SetPack(data)
	packData = data
end
buildPack = function()
	if not packData then
		return nil
	end
	local pack = Instance.new("Model")
	pack.Name = "WorldProps"
	for _, prop in packData do
		local model = Instance.new("Model")
		model.Name = prop.Id
		local slot = v3(prop.Slot[1], prop.Slot[2], prop.Slot[3])
		for _, piece in prop.Pieces do
			local part = Instance.new("MeshPart")
			part.Name = piece.Name
			local props = part.__props
			props.MeshId = "rbxassetid://mock/" .. piece.Name
			props.Size = v3(piece.Size[1], piece.Size[2], piece.Size[3])
			props.MeshSize = props.Size
			props.CFrame = CFrame.new(slot + v3(piece.Center[1], piece.Center[2], piece.Center[3]))
			props.Color = Color3.fromHex(piece.Color)
			props.Material = if piece.Kind == "Neon" then Enum.Material.Neon elseif piece.Kind == "Glass" then Enum.Material.Glass else Enum.Material.SmoothPlastic
			props.Transparency = piece.Transparency or 0
			props.CanCollide = piece.Collide == true
			props.Anchored = false
			part:SetAttribute("Paint", piece.Paint)
			setParent(part, model)
		end
		model.WorldPivot = CFrame.new(slot)
		setParent(model, pack)
	end
	return pack
end
function Mock.PlacePack(path)
	local pack = buildPack()
	if not pack then
		return
	end
	local segments = string.split(path, "/")
	pack.Name = table.remove(segments)
	pack.Parent = nodeAt(table.concat(segments, "/"))
end

---------------------------------------------------------------------------------------------------- JSON
local function jnum(n)
	if n ~= n or n == math.huge or n == -math.huge then
		return if n ~= n then "null" elseif n > 0 then "1e30" else "-1e30"
	end
	if n == math.floor(n) and math.abs(n) < 1e15 then
		return fmt("%d", n)
	end
	local s = fmt("%.4f", n)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	if s == "-0" then
		s = "0"
	end
	return s
end
local function jrot(n)
	local s = fmt("%.5f", n)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	if s == "-0" then
		s = "0"
	end
	return s
end
local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function jstr(s)
	return '"' .. string.gsub(s, '[%c"\\]', function(char)
		return ESCAPES[char] or fmt("\\u%04x", string.byte(char))
	end) .. '"'
end
local function encode(value, out)
	local kind = kindOf(value)
	if value == nil then
		table.insert(out, "null")
	elseif kind == "number" then
		table.insert(out, jnum(value))
	elseif kind == "boolean" then
		table.insert(out, if value then "true" else "false")
	elseif kind == "string" then
		table.insert(out, jstr(value))
	elseif kind == "Vector3" then
		table.insert(out, "[" .. jnum(value.X) .. "," .. jnum(value.Y) .. "," .. jnum(value.Z) .. "]")
	elseif kind == "Vector2" then
		table.insert(out, "[" .. jnum(value.X) .. "," .. jnum(value.Y) .. "]")
	elseif kind == "Color3" then
		table.insert(out, jstr(C3methods.ToHex(value)))
	elseif kind == "CFrame" then
		local parts = { jnum(value[1]), jnum(value[2]), jnum(value[3]) }
		for index = 4, 12 do
			parts[index] = jrot(value[index])
		end
		table.insert(out, "[" .. table.concat(parts, ",") .. "]")
	elseif kind == "UDim" then
		table.insert(out, "[" .. jnum(value.Scale) .. "," .. jnum(value.Offset) .. "]")
	elseif kind == "UDim2" then
		table.insert(out, "[" .. jnum(value.X.Scale) .. "," .. jnum(value.X.Offset) .. "," .. jnum(value.Y.Scale) .. "," .. jnum(value.Y.Offset) .. "]")
	elseif kind == "EnumItem" then
		table.insert(out, jstr(value.Name))
	elseif kind == "BrickColor" then
		table.insert(out, jstr(C3methods.ToHex(value.Color)))
	elseif kind == "ColorSequence" or kind == "NumberSequence" then
		local points = {}
		for _, point in value.Keypoints do
			local v = point.Value
			table.insert(points, "[" .. jnum(point.Time) .. "," .. (if kindOf(v) == "Color3" then jstr(C3methods.ToHex(v)) else jnum(v)) .. "]")
		end
		table.insert(out, "[" .. table.concat(points, ",") .. "]")
	elseif kind == "NumberRange" then
		table.insert(out, "[" .. jnum(value.Min) .. "," .. jnum(value.Max) .. "]")
	elseif kind == "Font" then
		table.insert(out, jstr(rawget(value, "EnumName") or tostring(value.Family)))
	elseif kind == "Instance" then
		table.insert(out, jstr(fullName(value)))
	elseif kind == "table" then
		if next(value) == nil then
			table.insert(out, "[]")
		elseif #value > 0 then
			table.insert(out, "[")
			for index, item in ipairs(value) do
				if index > 1 then
					table.insert(out, ",")
				end
				encode(item, out)
			end
			table.insert(out, "]")
		else
			local keys = {}
			for key in value do
				if type(key) == "string" then
					table.insert(keys, key)
				end
			end
			table.sort(keys)
			table.insert(out, "{")
			for index, key in keys do
				if index > 1 then
					table.insert(out, ",")
				end
				table.insert(out, jstr(key) .. ":")
				encode(value[key], out)
			end
			table.insert(out, "}")
		end
	else
		table.insert(out, jstr(tostring(value)))
	end
end
function Mock.Json(value)
	local out = {}
	encode(value, out)
	return table.concat(out)
end

---------------------------------------------------------------------------------------------------- world dump
local function propsOf(object)
	-- every known property of an instance (defaults included), for lighting & effects
	local result = {}
	local current = object.__class
	while current do
		for key in CLASSES[current].Props do
			if result[key] == nil and key ~= "Name" and key ~= "Archivable" then
				local value = object[key]
				if kindOf(value) ~= "Instance" then
					result[key] = value
				end
			end
		end
		current = CLASSES[current].Super
	end
	return result
end

local GUI_FIELDS = {
	"Name", "Visible", "Position", "Size", "AnchorPoint", "BackgroundColor3", "BackgroundTransparency", "Rotation",
	"ZIndex", "LayoutOrder", "Text", "TextColor3", "TextTransparency", "TextScaled", "TextSize", "TextWrapped",
	"TextXAlignment", "TextYAlignment", "TextStrokeColor3", "TextStrokeTransparency", "Font", "RichText",
	"Image", "ImageColor3", "ImageTransparency", "BorderSizePixel", "BorderColor3", "LineHeight",
}
local function dumpGuiObject(object)
	local node = { Class = object.__class }
	for _, field in GUI_FIELDS do
		if findProp(object.__class, field) ~= nil then
			node[field] = object[field]
		end
	end
	if node.Font == nil and findProp(object.__class, "FontFace") ~= nil then
		node.Font = object.FontFace
	end
	local children = {}
	for _, child in object.__children do
		local class = child.__class
		if class == "UICorner" then
			node.Corner = child.CornerRadius
		elseif class == "UIStroke" then
			if child.Enabled then
				node.Stroke = { Color = child.Color, Thickness = child.Thickness, Transparency = child.Transparency, Mode = child.ApplyStrokeMode }
			end
		elseif class == "UIGradient" then
			if child.Enabled then
				node.Gradient = { Color = child.Color, Transparency = child.Transparency, Rotation = child.Rotation, Offset = child.Offset }
			end
		elseif class == "UIPadding" then
			node.Padding = { child.PaddingLeft, child.PaddingRight, child.PaddingTop, child.PaddingBottom }
		elseif class == "UITextSizeConstraint" then
			node.MaxTextSize = child.MaxTextSize
		elseif isA(class, "GuiObject") then
			table.insert(children, dumpGuiObject(child))
		end
	end
	node.Children = children
	return node
end

local function dumpWorld()
	local parts, guis, lights, beams = {}, {}, {}, {}
	local partIndex = {}
	local counts = {}
	-- parts held by a weld (an unanchored part welded to something doesn't fall on its own)
	local welded = {}
	for object in allInstances do
		local class = object.__class
		if (class == "WeldConstraint" or isA(class, "JointInstance")) and not rawget(object, "__destroyed") then
			local part0, part1 = object.__props.Part0, object.__props.Part1
			if part0 and part0 ~= NIL and part1 and part1 ~= NIL then
				welded[part0] = true
				welded[part1] = true
			end
		end
	end
	local function visit(node, path)
		local class = node.__class
		counts[class] = (counts[class] or 0) + 1
		if isA(class, "BasePart") and class ~= "Terrain" then
			local props = node.__props
			local record = {
				Class = class,
				Name = props.Name,
				Path = path,
				Size = node.Size,
				CFrame = node.CFrame,
				Color = node.Color,
				Material = node.Material,
				Transparency = node.Transparency,
				CastShadow = node.CastShadow,
				Anchored = node.Anchored,
				Welded = if welded[node] then true else nil,
			}
			if class == "Part" or class == "SpawnLocation" or class == "Seat" then
				record.Shape = node.Shape
			end
			if class == "MeshPart" then
				record.MeshId = node.MeshId
				record.Paint = node:GetAttribute("Paint")
			end
			for _, child in node.__children do
				local childClass = child.__class
				if childClass == "SpecialMesh" or childClass == "BlockMesh" or childClass == "CylinderMesh" then
					record.Mesh = {
						Type = if childClass == "SpecialMesh" then child.MeshType elseif childClass == "BlockMesh" then "Brick" else "Cylinder",
						Scale = child.Scale,
						Offset = child.Offset,
					}
				end
			end
			table.insert(parts, record)
			partIndex[node] = #parts
		elseif isA(class, "Light") and node.Enabled then
			local parent = rawget(node, "__parent")
			local position = nil
			if parent and isA(parent.__class, "BasePart") then
				position = parent.Position
			elseif parent and parent.__class == "Attachment" then
				position = parent.WorldPosition
			end
			if position then
				table.insert(lights, { Class = class, Position = position, Color = node.Color, Brightness = node.Brightness, Range = node.Range })
			end
		elseif class == "Beam" and node.Enabled and node.Attachment0 and node.Attachment1 then
			table.insert(beams, {
				A0 = node.Attachment0.WorldPosition,
				A1 = node.Attachment1.WorldPosition,
				Color = node.Color,
				Transparency = node.Transparency,
				Width0 = node.Width0,
				Width1 = node.Width1,
				LightEmission = node.LightEmission,
				FaceCamera = node.FaceCamera,
			})
		end
		for _, child in node.__children do
			visit(child, path .. "/" .. child.__props.Name)
		end
	end
	for _, child in Workspace.__children do
		visit(child, child.__props.Name)
	end

	-- gui text on parts (SurfaceGui) and above them (BillboardGui), wherever the gui object lives
	for object in allInstances do
		local class = object.__class
		if (class == "SurfaceGui" or class == "BillboardGui") and not rawget(object, "__destroyed") and object.Enabled then
			local adornee = object.Adornee
			local parent = rawget(object, "__parent")
			if not adornee and parent and (isA(parent.__class, "BasePart") or parent.__class == "Attachment") then
				adornee = parent
			end
			if adornee and (adornee == Workspace or isDescendantOf(adornee, Workspace)) then
				local gui = { Class = class, Children = {} }
				if isA(adornee.__class, "BasePart") then
					gui.Part = partIndex[adornee]
					gui.Position = adornee.Position
				elseif adornee.__class == "Attachment" then
					gui.Position = adornee.WorldPosition
				end
				if class == "SurfaceGui" then
					gui.Face = object.Face
					gui.SizingMode = object.SizingMode
					gui.PixelsPerStud = object.PixelsPerStud
					gui.CanvasSize = object.CanvasSize
					gui.LightInfluence = object.LightInfluence
					gui.Brightness = object.Brightness
					gui.AlwaysOnTop = object.AlwaysOnTop
				else
					gui.Size = object.Size
					gui.StudsOffset = object.StudsOffset
					gui.StudsOffsetWorldSpace = object.StudsOffsetWorldSpace
					gui.ExtentsOffset = object.ExtentsOffset
					gui.ExtentsOffsetWorldSpace = object.ExtentsOffsetWorldSpace
					gui.SizeOffset = object.SizeOffset
					gui.MaxDistance = object.MaxDistance
					gui.AlwaysOnTop = object.AlwaysOnTop
					gui.LightInfluence = object.LightInfluence
					gui.Brightness = object.Brightness
				end
				gui.Name = fullName(object)
				for _, child in object.__children do
					if isA(child.__class, "GuiObject") then
						table.insert(gui.Children, dumpGuiObject(child))
					end
				end
				table.insert(guis, gui)
			end
		end
	end
	table.sort(guis, function(a, b)
		return a.Name < b.Name
	end)

	local lighting = { Properties = propsOf(Lighting), Effects = {} }
	for _, child in Lighting.__children do
		table.insert(lighting.Effects, { Class = child.__class, Name = child.__props.Name, Properties = propsOf(child) })
	end
	local clouds = methods.FindFirstChildOfClass(terrain, "Clouds")
	if clouds then
		lighting.Clouds = propsOf(clouds)
	end

	local materialColors = table.clone(TERRAIN_DEFAULT_COLORS)
	for name, hex in Mock.MaterialColors do
		materialColors[name] = hex
	end

	return {
		Parts = parts,
		Guis = guis,
		Lights = lights,
		Beams = beams,
		Terrain = {
			Fills = Mock.Fills,
			MaterialColors = materialColors,
			Water = { Color = terrain.WaterColor, Transparency = terrain.WaterTransparency },
		},
		Lighting = lighting,
		Counts = counts,
		Warnings = Mock.Warnings,
		Prints = Mock.Prints,
		Errors = Mock.Errors,
		Gaps = Mock.Gaps,
		SimulatedSeconds = Mock.Now,
	}
end

---------------------------------------------------------------------------------------------------- runner
-- Regions (hub + zones), their x ranges and spawns, read from the game's MapLayout/Zones modules
local function layoutInfo(config)
	local ok, info = pcall(function()
		local MapLayout = require(nodeAt(config.Layout))
		local okZones, Zones = pcall(require, nodeAt(config.Zones))
		Zones = if okZones then Zones else nil
		local function preset(id)
			local zone = if Zones and type(Zones.Get) == "function" then Zones.Get(id) elseif Zones then (if id == 0 then Zones.Hub else Zones[id]) else nil
			return zone and zone.Lighting
		end
		local regions = {
			{ Id = 0, Key = "Hub", Name = "Storm Station", X0 = MapLayout.HubStart, X1 = MapLayout.HubEnd, Spawn = MapLayout.ZoneSpawn(0), Lighting = preset(0) },
		}
		for id = 1, MapLayout.ZoneCount do
			local zone = Zones and Zones[id]
			table.insert(regions, {
				Id = id,
				Key = zone and zone.Key or ("Zone" .. id),
				Name = zone and zone.Name or ("Zone " .. id),
				X0 = MapLayout.ZoneStart(id),
				X1 = MapLayout.ZoneEnd(id),
				Spawn = MapLayout.ZoneSpawn(id),
				Field = { MapLayout.FieldBounds(id) },
				Color = zone and zone.Color,
				Lighting = preset(id),
			})
		end
		return { HalfWidth = MapLayout.HalfWidth, Regions = regions }
	end)
	return if ok then info else { Error = tostring(info) }
end

-- config: { Service = "ServerScriptService/Server/Services/MapService", Start = true, SimSeconds = 5,
--           Layout = ".../Config/MapLayout", Zones = ".../Config/Zones" }
function Mock.Run(config)
	local started = realClock()
	local thread = coroutine.create(function()
		local module = nodeAt(config.Service)
		local service = require(module)
		if type(service) ~= "table" then
			fail(config.Service .. " did not return a table")
		end
		if service.Init then
			service.Init()
		end
		if config.Start and service.Start then
			task.spawn(service.Start)
		end
	end)
	resume(thread)
	local steps = Scheduler.Run(config.SimSeconds or 5, config.MaxSteps or 200000)
	for _, entry in Scheduler.Waiting do
		if coroutine.status(entry.Thread) == "suspended" then
			table.insert(Mock.Warnings, "mock: a thread is still waiting on " .. entry.What .. " (it would hang forever in Roblox)")
		end
	end
	local world = dumpWorld()
	world.SchedulerSteps = steps
	if config.Layout then
		world.Layout = layoutInfo(config)
	end
	world.MockSeconds = realClock() - started
	realPrint("@@WORLD@@" .. Mock.Json(world))
	return #Mock.Errors == 0
end

Mock.Globals = {
	Vector3 = Vector3,
	Vector2 = Vector2,
	CFrame = CFrame,
	Color3 = Color3,
	UDim = UDim,
	UDim2 = UDim2,
	Rect = Rect,
	NumberSequence = NumberSequence,
	NumberSequenceKeypoint = NumberSequenceKeypoint,
	ColorSequence = ColorSequence,
	ColorSequenceKeypoint = ColorSequenceKeypoint,
	NumberRange = NumberRange,
	PhysicalProperties = PhysicalProperties,
	TweenInfo = TweenInfo,
	Ray = Ray,
	Region3 = Region3,
	RaycastParams = RaycastParams,
	OverlapParams = OverlapParams,
	BrickColor = BrickColor,
	Font = Font,
	DateTime = DateTime,
	Random = Random,
	Enum = Enum,
	Instance = Instance,
	game = game,
	workspace = Workspace,
	Workspace = Workspace,
	task = task,
	typeof = typeof,
	warn = warn,
	print = print,
	tick = tick,
	time = time,
	elapsedTime = time,
	require = require,
	wait = task.wait,
	spawn = function(fn, ...)
		return task.defer(fn, ...)
	end,
	delay = task.delay,
	settings = function()
		fail("settings() is not supported by the preview mock", 2)
	end,
	UserSettings = function()
		fail("UserSettings() is not supported by the preview mock", 2)
	end,
	plugin = nil,
	shared = {},
}

-- install the globals (the CLI's _G and libraries are read-only, so they go into the script environment,
-- which loadstring'd modules share); os.clock/os.time follow the simulated clock
local env = getfenv(1)
for name, value in Mock.Globals do
	env[name] = value
end
local realOs = os
env.os = setmetatable({
	clock = function()
		return Mock.Now
	end,
	time = function(t)
		if t then
			return realOs.time(t)
		end
		return math.floor(Mock.ClockBase + Mock.Now)
	end,
}, { __index = realOs })
math.randomseed(1)

return Mock
