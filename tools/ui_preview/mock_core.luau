--!nocheck
-- UI preview mock, part 1 of 4: datatypes, Enum, the simulated clock / task scheduler and signals.
-- tools/preview_ui.py bundles mock_core, mock_instances, mock_layout, mock_services, Boot.luau and the
-- game's modules into one script and runs it with the `luau` command line. Every part receives the
-- shared table M (`local M = ...`) and adds to it.
--
-- Gaps fail loudly: a member the mock doesn't know raises "mock: ..." naming it and the game line
-- that used it, and is also recorded in M.Gaps so preview_ui.py reports it even when game code
-- wrapped the call in a pcall.

local M = ...
local fmt = string.format
local realTypeof = typeof

M.Warnings = {}
M.Prints = {}
M.Errors = {}
M.Gaps = {}
M.Notes = {} -- stub calls and other things worth knowing ("stub: EffectsController.Confetti")
M.Now = 0 -- simulated seconds since the client started
M.ClockBase = 1760000000 -- simulated unix time at M.Now = 0
M.Frame = 0

local function isMockSource(line)
	return string.find(line, "[mock]", 1, true) ~= nil or string.find(line, "preview_bundle", 1, true) ~= nil
end

-- First stack line that belongs to game code (skips the mock's own frames)
function M.Where(level)
	for line in string.gmatch(debug.traceback("", (level or 1) + 1), "[^\n]+") do
		local source = string.match(line, "^%s*(.-:%d+)")
		if source and not isMockSource(source) then
			return source
		end
	end
	return nil
end

local gapSeen = {}
function M.RecordGap(message, maybe)
	local where = M.Where(3)
	local key = message .. "|" .. tostring(where)
	if gapSeen[key] then
		return
	end
	gapSeen[key] = true
	table.insert(M.Gaps, { Message = message, Where = where, Maybe = maybe == true })
end

-- A mock limitation (not a game bug): recorded as a gap, then raised
function M.Gap(message, level)
	M.RecordGap(message, false)
	error("mock: " .. message .. " (add it to tools/ui_preview)", (level or 1) + 1)
end

-- A Roblox error the real engine would raise too (bad member, wrong type): raised, recorded as "maybe"
function M.Fail(message, level)
	M.RecordGap(message, true)
	error(message, (level or 1) + 1)
end

function M.Note(text)
	if not M.Notes[text] then
		M.Notes[text] = 0
	end
	M.Notes[text] += 1
end

local function kindOf(value)
	if type(value) == "table" then
		local kind = rawget(value, "__kind")
		if kind then
			return kind
		end
		local meta = getmetatable(value)
		if type(meta) == "table" and rawget(meta, "__kind") then
			return rawget(meta, "__kind")
		end
	end
	return realTypeof(value)
end
M.KindOf = kindOf

local function immutable(name)
	return function(_, key)
		M.Fail(fmt("%s is not a valid member of %s (datatypes are read-only)", tostring(key), name), 2)
	end
end

local function datatypeIndex(name, methods, getters)
	return function(self, key)
		local method = methods[key]
		if method ~= nil then
			return method
		end
		local getter = getters and getters[key]
		if getter then
			return getter(self)
		end
		M.Gap(fmt("%s.%s is not supported", name, tostring(key)), 2)
	end
end

local function num(v)
	-- compact number for tostring
	if v == math.floor(v) and math.abs(v) < 1e15 then
		return tostring(math.floor(v))
	end
	return tostring(v)
end

---------------------------------------------------------------------------------------------------- Vector2
local Vector2 = {}
local V2 = { __kind = "Vector2" }
local V2m = {}
local function v2(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, V2)
end
M.v2 = v2
local V2g = {
	Magnitude = function(v)
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	end,
	Unit = function(v)
		local m = math.sqrt(v.X * v.X + v.Y * v.Y)
		if m == 0 then
			return v2(0 / 0, 0 / 0)
		end
		return v2(v.X / m, v.Y / m)
	end,
	x = function(v)
		return v.X
	end,
	y = function(v)
		return v.Y
	end,
}
function V2m.Dot(a, b)
	return a.X * b.X + a.Y * b.Y
end
function V2m.Cross(a, b)
	return a.X * b.Y - a.Y * b.X
end
function V2m.Lerp(a, b, t)
	return v2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t)
end
function V2m.Abs(a)
	return v2(math.abs(a.X), math.abs(a.Y))
end
function V2m.Floor(a)
	return v2(math.floor(a.X), math.floor(a.Y))
end
function V2m.Ceil(a)
	return v2(math.ceil(a.X), math.ceil(a.Y))
end
function V2m.Sign(a)
	return v2(math.sign(a.X), math.sign(a.Y))
end
function V2m.Min(a, ...)
	local x, y = a.X, a.Y
	for _, b in { ... } do
		x, y = math.min(x, b.X), math.min(y, b.Y)
	end
	return v2(x, y)
end
function V2m.Max(a, ...)
	local x, y = a.X, a.Y
	for _, b in { ... } do
		x, y = math.max(x, b.X), math.max(y, b.Y)
	end
	return v2(x, y)
end
function V2m.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	return math.abs(a.X - b.X) <= eps and math.abs(a.Y - b.Y) <= eps
end
function V2m.Angle(a, b, signed)
	local angle = math.atan2(V2m.Cross(a, b), V2m.Dot(a, b))
	return if signed then angle else math.abs(angle)
end
V2.__index = datatypeIndex("Vector2", V2m, V2g)
V2.__newindex = immutable("Vector2")
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
	elseif type(a) == "number" then
		return v2(a / b.X, a / b.Y)
	end
	return v2(a.X / b.X, a.Y / b.Y)
end
V2.__idiv = function(a, b)
	if type(b) == "number" then
		return v2(a.X // b, a.Y // b)
	end
	return v2(a.X // b.X, a.Y // b.Y)
end
V2.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
V2.__tostring = function(v)
	return num(v.X) .. ", " .. num(v.Y)
end
function Vector2.new(x, y)
	return v2(x or 0, y or 0)
end
Vector2.zero = v2(0, 0)
Vector2.one = v2(1, 1)
Vector2.xAxis = v2(1, 0)
Vector2.yAxis = v2(0, 1)
M.Vector2 = Vector2

---------------------------------------------------------------------------------------------------- Vector3
local Vector3 = {}
local V3 = { __kind = "Vector3" }
local V3m = {}
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
end
M.v3 = v3
local V3g = {
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
function V3m.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3m.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3m.Lerp(a, b, t)
	return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
end
function V3m.Abs(a)
	return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end
function V3m.Floor(a)
	return v3(math.floor(a.X), math.floor(a.Y), math.floor(a.Z))
end
function V3m.Ceil(a)
	return v3(math.ceil(a.X), math.ceil(a.Y), math.ceil(a.Z))
end
function V3m.Sign(a)
	return v3(math.sign(a.X), math.sign(a.Y), math.sign(a.Z))
end
function V3m.Min(a, ...)
	local x, y, z = a.X, a.Y, a.Z
	for _, b in { ... } do
		x, y, z = math.min(x, b.X), math.min(y, b.Y), math.min(z, b.Z)
	end
	return v3(x, y, z)
end
function V3m.Max(a, ...)
	local x, y, z = a.X, a.Y, a.Z
	for _, b in { ... } do
		x, y, z = math.max(x, b.X), math.max(y, b.Y), math.max(z, b.Z)
	end
	return v3(x, y, z)
end
function V3m.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	return math.abs(a.X - b.X) <= eps and math.abs(a.Y - b.Y) <= eps and math.abs(a.Z - b.Z) <= eps
end
function V3m.Angle(a, b)
	return math.atan2(V3g.Magnitude(V3m.Cross(a, b)), V3m.Dot(a, b))
end
V3.__index = datatypeIndex("Vector3", V3m, V3g)
V3.__newindex = immutable("Vector3")
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
	elseif type(a) == "number" then
		return v3(a / b.X, a / b.Y, a / b.Z)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(v)
	return num(v.X) .. ", " .. num(v.Y) .. ", " .. num(v.Z)
end
function Vector3.new(x, y, z)
	return v3(x or 0, y or 0, z or 0)
end
function Vector3.FromNormalId(normal)
	local map = { Right = v3(1, 0, 0), Left = v3(-1, 0, 0), Top = v3(0, 1, 0), Bottom = v3(0, -1, 0), Back = v3(0, 0, 1), Front = v3(0, 0, -1) }
	return map[normal.Name] or v3(0, 0, -1)
end
function Vector3.FromAxis(axis)
	local map = { X = v3(1, 0, 0), Y = v3(0, 1, 0), Z = v3(0, 0, 1) }
	return map[axis.Name] or v3(1, 0, 0)
end
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)
M.Vector3 = Vector3

---------------------------------------------------------------------------------------------------- CFrame
-- Position + 3x3 rotation (rows). Enough for pivots, lookAt and the odd camera framing.
local CFrame = {}
local CF = { __kind = "CFrame" }
local CFm = {}
local function cf(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	return setmetatable({
		x = x, y = y, z = z,
		r00 = r00 or 1, r01 = r01 or 0, r02 = r02 or 0,
		r10 = r10 or 0, r11 = r11 or 1, r12 = r12 or 0,
		r20 = r20 or 0, r21 = r21 or 0, r22 = r22 or 1,
	}, CF)
end
local function cfMul(a, b)
	return cf(
		a.r00 * b.x + a.r01 * b.y + a.r02 * b.z + a.x,
		a.r10 * b.x + a.r11 * b.y + a.r12 * b.z + a.y,
		a.r20 * b.x + a.r21 * b.y + a.r22 * b.z + a.z,
		a.r00 * b.r00 + a.r01 * b.r10 + a.r02 * b.r20, a.r00 * b.r01 + a.r01 * b.r11 + a.r02 * b.r21, a.r00 * b.r02 + a.r01 * b.r12 + a.r02 * b.r22,
		a.r10 * b.r00 + a.r11 * b.r10 + a.r12 * b.r20, a.r10 * b.r01 + a.r11 * b.r11 + a.r12 * b.r21, a.r10 * b.r02 + a.r11 * b.r12 + a.r12 * b.r22,
		a.r20 * b.r00 + a.r21 * b.r10 + a.r22 * b.r20, a.r20 * b.r01 + a.r21 * b.r11 + a.r22 * b.r21, a.r20 * b.r02 + a.r21 * b.r12 + a.r22 * b.r22
	)
end
local function cfInverse(a)
	-- rotation is orthonormal: inverse = transpose
	local x, y, z = a.x, a.y, a.z
	return cf(
		-(a.r00 * x + a.r10 * y + a.r20 * z), -(a.r01 * x + a.r11 * y + a.r21 * z), -(a.r02 * x + a.r12 * y + a.r22 * z),
		a.r00, a.r10, a.r20, a.r01, a.r11, a.r21, a.r02, a.r12, a.r22
	)
end
local function cfPoint(a, v)
	return v3(a.r00 * v.X + a.r01 * v.Y + a.r02 * v.Z + a.x, a.r10 * v.X + a.r11 * v.Y + a.r12 * v.Z + a.y, a.r20 * v.X + a.r21 * v.Y + a.r22 * v.Z + a.z)
end
local function cfVector(a, v)
	return v3(a.r00 * v.X + a.r01 * v.Y + a.r02 * v.Z, a.r10 * v.X + a.r11 * v.Y + a.r12 * v.Z, a.r20 * v.X + a.r21 * v.Y + a.r22 * v.Z)
end
local function rotX(t)
	local c, s = math.cos(t), math.sin(t)
	return cf(0, 0, 0, 1, 0, 0, 0, c, -s, 0, s, c)
end
local function rotY(t)
	local c, s = math.cos(t), math.sin(t)
	return cf(0, 0, 0, c, 0, s, 0, 1, 0, -s, 0, c)
end
local function rotZ(t)
	local c, s = math.cos(t), math.sin(t)
	return cf(0, 0, 0, c, -s, 0, s, c, 0, 0, 0, 1)
end
local function lookAt(at, target, up)
	up = up or v3(0, 1, 0)
	local f = target - at
	local m = f.Magnitude
	if m < 1e-9 then
		return cf(at.X, at.Y, at.Z)
	end
	f = f / m
	local r = V3m.Cross(f, up)
	if r.Magnitude < 1e-6 then
		r = V3m.Cross(f, v3(0, 0, 1))
	end
	r = r.Unit
	local u = V3m.Cross(r, f)
	return cf(at.X, at.Y, at.Z, r.X, u.X, -f.X, r.Y, u.Y, -f.Y, r.Z, u.Z, -f.Z)
end
local CFg = {
	Position = function(c)
		return v3(c.x, c.y, c.z)
	end,
	p = function(c)
		return v3(c.x, c.y, c.z)
	end,
	X = function(c)
		return c.x
	end,
	Y = function(c)
		return c.y
	end,
	Z = function(c)
		return c.z
	end,
	Rotation = function(c)
		return cf(0, 0, 0, c.r00, c.r01, c.r02, c.r10, c.r11, c.r12, c.r20, c.r21, c.r22)
	end,
	LookVector = function(c)
		return v3(-c.r02, -c.r12, -c.r22)
	end,
	RightVector = function(c)
		return v3(c.r00, c.r10, c.r20)
	end,
	UpVector = function(c)
		return v3(c.r01, c.r11, c.r21)
	end,
	XVector = function(c)
		return v3(c.r00, c.r10, c.r20)
	end,
	YVector = function(c)
		return v3(c.r01, c.r11, c.r21)
	end,
	ZVector = function(c)
		return v3(c.r02, c.r12, c.r22)
	end,
}
function CFm.Inverse(c)
	return cfInverse(c)
end
function CFm.ToWorldSpace(c, ...)
	local out = {}
	for i, other in { ... } do
		out[i] = cfMul(c, other)
	end
	return table.unpack(out)
end
function CFm.ToObjectSpace(c, ...)
	local inv = cfInverse(c)
	local out = {}
	for i, other in { ... } do
		out[i] = cfMul(inv, other)
	end
	return table.unpack(out)
end
function CFm.PointToWorldSpace(c, v)
	return cfPoint(c, v)
end
function CFm.PointToObjectSpace(c, v)
	return cfPoint(cfInverse(c), v)
end
function CFm.VectorToWorldSpace(c, v)
	return cfVector(c, v)
end
function CFm.VectorToObjectSpace(c, v)
	return cfVector(cfInverse(c), v)
end
function CFm.GetComponents(c)
	return c.x, c.y, c.z, c.r00, c.r01, c.r02, c.r10, c.r11, c.r12, c.r20, c.r21, c.r22
end
CFm.components = CFm.GetComponents
function CFm.ToEulerAnglesXYZ(c)
	local y = math.asin(math.clamp(c.r02, -1, 1))
	local x = math.atan2(-c.r12, c.r22)
	local z = math.atan2(-c.r01, c.r00)
	return x, y, z
end
CFm.ToOrientation = CFm.ToEulerAnglesXYZ
CFm.ToEulerAnglesYXZ = CFm.ToEulerAnglesXYZ
function CFm.ToAxisAngle(c)
	return v3(0, 1, 0), 0
end
function CFm.Lerp(a, b, t)
	-- position lerp; rotation snaps to the nearer end (enough for a still picture)
	local r = if t < 0.5 then a else b
	return cf(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t, r.r00, r.r01, r.r02, r.r10, r.r11, r.r12, r.r20, r.r21, r.r22)
end
function CFm.Orthonormalize(c)
	return c
end
function CFm.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	return math.abs(a.x - b.x) < eps and math.abs(a.y - b.y) < eps and math.abs(a.z - b.z) < eps
end
CF.__index = datatypeIndex("CFrame", CFm, CFg)
CF.__newindex = immutable("CFrame")
CF.__mul = function(a, b)
	if getmetatable(b) == V3 then
		return cfPoint(a, b)
	end
	return cfMul(a, b)
end
CF.__add = function(a, v)
	return cf(a.x + v.X, a.y + v.Y, a.z + v.Z, a.r00, a.r01, a.r02, a.r10, a.r11, a.r12, a.r20, a.r21, a.r22)
end
CF.__sub = function(a, v)
	return cf(a.x - v.X, a.y - v.Y, a.z - v.Z, a.r00, a.r01, a.r02, a.r10, a.r11, a.r12, a.r20, a.r21, a.r22)
end
CF.__eq = function(a, b)
	for _, k in { "x", "y", "z", "r00", "r01", "r02", "r10", "r11", "r12", "r20", "r21", "r22" } do
		if a[k] ~= b[k] then
			return false
		end
	end
	return true
end
CF.__tostring = function(c)
	return table.concat({ num(c.x), num(c.y), num(c.z), num(c.r00), num(c.r01), num(c.r02), num(c.r10), num(c.r11), num(c.r12), num(c.r20), num(c.r21), num(c.r22) }, ", ")
end
function CFrame.new(...)
	local n = select("#", ...)
	local a, b = ...
	if n == 0 then
		return cf(0, 0, 0)
	elseif n == 1 then
		return cf(a.X, a.Y, a.Z)
	elseif n == 2 and getmetatable(a) == V3 then
		return lookAt(a, b)
	elseif n == 3 then
		local x, y, z = ...
		return cf(x, y, z)
	elseif n == 7 then
		local x, y, z, qx, qy, qz, qw = ...
		local xx, yy, zz = qx * qx, qy * qy, qz * qz
		return cf(x, y, z,
			1 - 2 * (yy + zz), 2 * (qx * qy - qz * qw), 2 * (qx * qz + qy * qw),
			2 * (qx * qy + qz * qw), 1 - 2 * (xx + zz), 2 * (qy * qz - qx * qw),
			2 * (qx * qz - qy * qw), 2 * (qy * qz + qx * qw), 1 - 2 * (xx + yy))
	end
	return cf(...)
end
function CFrame.lookAt(at, target, up)
	return lookAt(at, target, up)
end
function CFrame.lookAlong(at, direction, up)
	return lookAt(at, at + direction, up)
end
function CFrame.Angles(rx, ry, rz)
	return cfMul(cfMul(rotX(rx or 0), rotY(ry or 0)), rotZ(rz or 0))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.fromEulerAnglesYXZ(rx, ry, rz)
	return cfMul(cfMul(rotY(ry or 0), rotX(rx or 0)), rotZ(rz or 0))
end
CFrame.fromOrientation = CFrame.fromEulerAnglesYXZ
function CFrame.fromEulerAngles(rx, ry, rz)
	return CFrame.Angles(rx, ry, rz)
end
function CFrame.fromAxisAngle(axis, angle)
	local u = axis.Unit
	local c, s = math.cos(angle), math.sin(angle)
	local t = 1 - c
	local x, y, z = u.X, u.Y, u.Z
	return cf(0, 0, 0, t * x * x + c, t * x * y - s * z, t * x * z + s * y, t * x * y + s * z, t * y * y + c, t * y * z - s * x, t * x * z - s * y, t * y * z + s * x, t * z * z + c)
end
function CFrame.fromMatrix(pos, vx, vy, vz)
	vz = vz or V3m.Cross(vx, vy)
	return cf(pos.X, pos.Y, pos.Z, vx.X, vy.X, vz.X, vx.Y, vy.Y, vz.Y, vx.Z, vy.Z, vz.Z)
end
CFrame.identity = cf(0, 0, 0)
M.CFrame = CFrame

---------------------------------------------------------------------------------------------------- Color3
local Color3 = {}
local C3 = { __kind = "Color3" }
local C3m = {}
local function c3(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3)
end
M.c3 = c3
function C3m.Lerp(a, b, t)
	return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
function C3m.ToHSV(c)
	local r, g, b = c.R, c.G, c.B
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local d = max - min
	local h = 0
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
	return h, if max == 0 then 0 else d / max, max
end
function C3m.ToHex(c)
	local function byte(v)
		return math.clamp(math.floor(v * 255 + 0.5), 0, 255)
	end
	return fmt("%02X%02X%02X", byte(c.R), byte(c.G), byte(c.B))
end
C3.__index = datatypeIndex("Color3", C3m, {
	r = function(c)
		return c.R
	end,
	g = function(c)
		return c.G
	end,
	b = function(c)
		return c.B
	end,
})
C3.__newindex = immutable("Color3")
C3.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
C3.__tostring = function(c)
	return num(c.R) .. ", " .. num(c.G) .. ", " .. num(c.B)
end
function Color3.new(r, g, b)
	return c3(r or 0, g or 0, b or 0)
end
function Color3.fromRGB(r, g, b)
	return c3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function Color3.fromHex(hex)
	hex = string.gsub(hex, "#", "")
	if #hex == 3 then
		hex = string.gsub(hex, ".", "%0%0")
	end
	return c3(tonumber(string.sub(hex, 1, 2), 16) / 255, tonumber(string.sub(hex, 3, 4), 16) / 255, tonumber(string.sub(hex, 5, 6), 16) / 255)
end
function Color3.fromHSV(h, s, v)
	h = (h % 1) * 6
	local i = math.floor(h)
	local f = h - i
	local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	local r, g, b
	if i == 0 then
		r, g, b = v, t, p
	elseif i == 1 then
		r, g, b = q, v, p
	elseif i == 2 then
		r, g, b = p, v, t
	elseif i == 3 then
		r, g, b = p, q, v
	elseif i == 4 then
		r, g, b = t, p, v
	else
		r, g, b = v, p, q
	end
	return c3(r, g, b)
end
function Color3.toHSV(c)
	return C3m.ToHSV(c)
end
M.Color3 = Color3

---------------------------------------------------------------------------------------------------- UDim, UDim2, Rect
local UDim = {}
local UD = { __kind = "UDim" }
local function udim(s, o)
	return setmetatable({ Scale = s or 0, Offset = o or 0 }, UD)
end
M.udim = udim
UD.__index = datatypeIndex("UDim", {}, {})
UD.__newindex = immutable("UDim")
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
	return num(u.Scale) .. ", " .. num(u.Offset)
end
function UDim.new(s, o)
	return udim(s or 0, o or 0)
end
M.UDim = UDim

local UDim2 = {}
local UD2 = { __kind = "UDim2" }
local function udim2(x, y)
	return setmetatable({ X = x, Y = y }, UD2)
end
M.udim2 = udim2
UD2.__index = datatypeIndex("UDim2", {
	Lerp = function(a, b, t)
		return udim2(
			udim(a.X.Scale + (b.X.Scale - a.X.Scale) * t, a.X.Offset + (b.X.Offset - a.X.Offset) * t),
			udim(a.Y.Scale + (b.Y.Scale - a.Y.Scale) * t, a.Y.Offset + (b.Y.Offset - a.Y.Offset) * t)
		)
	end,
}, {
	Width = function(u)
		return u.X
	end,
	Height = function(u)
		return u.Y
	end,
})
UD2.__newindex = immutable("UDim2")
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
	return "{" .. tostring(u.X) .. "}, {" .. tostring(u.Y) .. "}"
end
function UDim2.new(a, b, c, d)
	if type(a) == "table" then
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
M.UDim2 = UDim2

local Rect = {}
local RC = { __kind = "Rect" }
local function rect(x0, y0, x1, y1)
	return setmetatable({ Min = v2(x0, y0), Max = v2(x1, y1) }, RC)
end
RC.__index = datatypeIndex("Rect", {}, {
	Width = function(r)
		return r.Max.X - r.Min.X
	end,
	Height = function(r)
		return r.Max.Y - r.Min.Y
	end,
})
RC.__newindex = immutable("Rect")
RC.__eq = function(a, b)
	return a.Min == b.Min and a.Max == b.Max
end
function Rect.new(a, b, c, d)
	if type(a) == "table" then
		return rect(a.X, a.Y, b.X, b.Y)
	end
	return rect(a or 0, b or 0, c or 0, d or 0)
end
M.Rect = Rect

---------------------------------------------------------------------------------------------------- sequences and small datatypes
local function simple(kind, fields, methods)
	local meta = { __kind = kind }
	meta.__index = datatypeIndex(kind, methods or {}, {})
	meta.__newindex = immutable(kind)
	meta.__eq = function(a, b)
		for _, f in fields do
			if a[f] ~= b[f] then
				return false
			end
		end
		return true
	end
	return function(values)
		return setmetatable(values, meta)
	end
end

local makeColorKeypoint = simple("ColorSequenceKeypoint", { "Time", "Value" })
local ColorSequenceKeypoint = {
	new = function(t, c)
		return makeColorKeypoint({ Time = t, Value = c })
	end,
}
local makeColorSequence = simple("ColorSequence", {})
local ColorSequence = {
	new = function(a, b)
		if kindOf(a) == "Color3" then
			b = b or a
			return makeColorSequence({ Keypoints = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b) } })
		end
		if type(a) ~= "table" or #a < 2 then
			M.Fail("ColorSequence.new: expected a Color3 or at least 2 keypoints", 2)
		end
		return makeColorSequence({ Keypoints = table.clone(a) })
	end,
}
local makeNumberKeypoint = simple("NumberSequenceKeypoint", { "Time", "Value", "Envelope" })
local NumberSequenceKeypoint = {
	new = function(t, v, e)
		return makeNumberKeypoint({ Time = t, Value = v, Envelope = e or 0 })
	end,
}
local makeNumberSequence = simple("NumberSequence", {})
local NumberSequence = {
	new = function(a, b)
		if type(a) == "number" then
			b = b or a
			return makeNumberSequence({ Keypoints = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) } })
		end
		if type(a) ~= "table" or #a < 2 then
			M.Fail("NumberSequence.new: expected a number or at least 2 keypoints", 2)
		end
		return makeNumberSequence({ Keypoints = table.clone(a) })
	end,
}
local makeRange = simple("NumberRange", { "Min", "Max" })
local NumberRange = {
	new = function(a, b)
		return makeRange({ Min = a, Max = b or a })
	end,
}
local makeTweenInfo = simple("TweenInfo", { "Time" })
local TweenInfo = {
	new = function(time, style, direction, repeatCount, reverses, delayTime)
		return makeTweenInfo({
			Time = time or 1,
			EasingStyle = style,
			EasingDirection = direction,
			RepeatCount = repeatCount or 0,
			Reverses = reverses == true,
			DelayTime = delayTime or 0,
		})
	end,
}
M.ColorSequence, M.ColorSequenceKeypoint = ColorSequence, ColorSequenceKeypoint
M.NumberSequence, M.NumberSequenceKeypoint = NumberSequence, NumberSequenceKeypoint
M.NumberRange, M.TweenInfo = NumberRange, TweenInfo

local function bag(kind)
	local meta = { __kind = kind }
	return {
		new = function(...)
			return setmetatable({ Args = { ... } }, meta)
		end,
	}
end
M.PhysicalProperties = bag("PhysicalProperties")
M.Ray = bag("Ray")
M.Region3 = bag("Region3")
M.RaycastParams = bag("RaycastParams")
M.OverlapParams = bag("OverlapParams")
M.TextChatMessageProperties = bag("TextChatMessageProperties")

---------------------------------------------------------------------------------------------------- Random, DateTime, BrickColor
local Random = {}
local RandomMeta = { __kind = "Random" }
local RandomMethods = {}
RandomMeta.__index = RandomMethods
local function nextFloat(self)
	-- xorshift32, deterministic per seed
	local s = self.State
	s = bit32.bxor(s, bit32.lshift(s, 13))
	s = bit32.bxor(s, bit32.rshift(s, 17))
	s = bit32.bxor(s, bit32.lshift(s, 5))
	self.State = s
	return s / 4294967296
end
function RandomMethods.NextNumber(self, a, b)
	local f = nextFloat(self)
	if a == nil then
		return f
	end
	return a + (b - a) * f
end
function RandomMethods.NextInteger(self, a, b)
	return a + math.floor(nextFloat(self) * (b - a + 1))
end
function RandomMethods.NextUnitVector(self)
	return v3(nextFloat(self) - 0.5, nextFloat(self) - 0.5, nextFloat(self) - 0.5).Unit
end
function RandomMethods.Shuffle(self, list)
	for i = #list, 2, -1 do
		local j = RandomMethods.NextInteger(self, 1, i)
		list[i], list[j] = list[j], list[i]
	end
end
function RandomMethods.Clone(self)
	return setmetatable({ State = self.State }, RandomMeta)
end
function Random.new(seed)
	local state = math.floor(math.abs(seed or 12345)) % 4294967295
	if state == 0 then
		state = 2463534242
	end
	return setmetatable({ State = state }, RandomMeta)
end
M.Random = Random

local DateTime = {}
local DTMeta = { __kind = "DateTime" }
local DTMethods = {}
DTMeta.__index = function(self, key)
	if key == "UnixTimestamp" then
		return math.floor(self.Millis / 1000)
	elseif key == "UnixTimestampMillis" then
		return self.Millis
	end
	local method = DTMethods[key]
	if method then
		return method
	end
	M.Gap("DateTime." .. tostring(key) .. " is not supported", 2)
end
local function makeDateTime(millis)
	return setmetatable({ Millis = millis }, DTMeta)
end
function DTMethods.ToUniversalTime(self)
	local t = os.date("!*t", math.floor(self.Millis / 1000))
	return { Year = t.year, Month = t.month, Day = t.day, Hour = t.hour, Minute = t.min, Second = t.sec, Millisecond = self.Millis % 1000 }
end
DTMethods.ToLocalTime = DTMethods.ToUniversalTime
function DTMethods.FormatUniversalTime(self, format)
	local t = os.date("!*t", math.floor(self.Millis / 1000))
	if format == "LT" then
		local hour = t.hour % 12
		return fmt("%d:%02d %s", if hour == 0 then 12 else hour, t.min, if t.hour < 12 then "AM" else "PM")
	end
	return fmt("%04d-%02d-%02d %02d:%02d", t.year, t.month, t.day, t.hour, t.min)
end
DTMethods.FormatLocalTime = DTMethods.FormatUniversalTime
function DTMethods.ToIsoDate(self)
	return os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(self.Millis / 1000))
end
function DateTime.now()
	return makeDateTime(math.floor((M.ClockBase + M.Now) * 1000))
end
function DateTime.fromUnixTimestamp(seconds)
	return makeDateTime(math.floor(seconds * 1000))
end
function DateTime.fromUnixTimestampMillis(millis)
	return makeDateTime(millis)
end
M.DateTime = DateTime

local BRICK = {
	["White"] = { 242, 243, 243 }, ["Institutional white"] = { 248, 248, 248 }, ["Black"] = { 27, 42, 53 },
	["Really black"] = { 17, 17, 17 }, ["Medium stone grey"] = { 163, 162, 165 }, ["Dark stone grey"] = { 99, 95, 98 },
	["Bright red"] = { 196, 40, 28 }, ["Really red"] = { 255, 0, 0 }, ["Bright blue"] = { 13, 105, 172 },
	["Really blue"] = { 0, 0, 255 }, ["Bright green"] = { 75, 151, 75 }, ["Lime green"] = { 0, 255, 0 },
	["Bright yellow"] = { 245, 205, 48 }, ["New Yeller"] = { 255, 255, 0 }, ["Bright orange"] = { 218, 133, 65 },
	["Hot pink"] = { 255, 0, 191 }, ["Royal purple"] = { 98, 37, 209 }, ["Cyan"] = { 4, 175, 236 },
}
local BrickColor = {}
local BCMeta = { __kind = "BrickColor" }
BCMeta.__index = function(self, key)
	if key == "Color" then
		return self.__color
	elseif key == "Name" then
		return self.__name
	elseif key == "Number" then
		return 1
	elseif key == "r" or key == "g" or key == "b" then
		return self.__color[string.upper(key)]
	end
	M.Gap("BrickColor." .. tostring(key) .. " is not supported", 2)
end
BCMeta.__eq = function(a, b)
	return a.__name == b.__name
end
BCMeta.__tostring = function(b)
	return b.__name
end
local function brick(name)
	local rgb = BRICK[name] or BRICK["Medium stone grey"]
	return setmetatable({ __name = if BRICK[name] then name else "Medium stone grey", __color = Color3.fromRGB(rgb[1], rgb[2], rgb[3]) }, BCMeta)
end
function BrickColor.new(value, g, b)
	if type(value) == "string" then
		return brick(value)
	elseif kindOf(value) == "Color3" or type(value) == "number" and g then
		return brick("Medium stone grey")
	end
	return brick("Medium stone grey")
end
BrickColor.palette = BrickColor.new
BrickColor.random = function()
	return brick("Bright blue")
end
for _, name in { "White", "Black", "Gray", "Red", "Blue", "Green", "Yellow" } do
	BrickColor[name] = function()
		return brick(({ Gray = "Medium stone grey", Red = "Bright red", Blue = "Bright blue", Green = "Bright green", Yellow = "Bright yellow" })[name] or name)
	end
end
M.BrickColor = BrickColor

---------------------------------------------------------------------------------------------------- Enum
-- Listed enums are strict (a misspelled item fails like in Roblox); any other enum is created on use.
local ENUMS = {
	Font = { "Legacy", "Arial", "ArialBold", "SourceSans", "SourceSansBold", "SourceSansLight", "SourceSansItalic", "Bodoni", "Garamond", "Cartoon", "Code", "Highway", "SciFi", "Arcade", "Fantasy", "Antique", "SourceSansSemibold", "Gotham", "GothamMedium", "GothamBold", "GothamBlack", "AmaticSC", "Bangers", "Creepster", "DenkOne", "Fondamento", "FredokaOne", "GrenzeGotisch", "IndieFlower", "JosefinSans", "Jura", "Kalam", "LuckiestGuy", "Merriweather", "Michroma", "Nunito", "Oswald", "PatrickHand", "PermanentMarker", "Roboto", "RobotoCondensed", "RobotoMono", "Sarpanch", "SpecialElite", "TitilliumWeb", "Ubuntu", "BuilderSans", "BuilderSansMedium", "BuilderSansBold", "BuilderSansExtraBold", "Arimo", "ArimoBold", "Unknown" },
	FontWeight = { Thin = 100, ExtraLight = 200, Light = 300, Regular = 400, Medium = 500, SemiBold = 600, Bold = 700, ExtraBold = 800, Heavy = 900 },
	FontStyle = { "Normal", "Italic" },
	TextXAlignment = { Left = 0, Right = 1, Center = 2 },
	TextYAlignment = { Top = 0, Center = 1, Bottom = 2 },
	TextTruncate = { "None", "AtEnd", "SplitWord" },
	TextDirection = { "Auto", "LeftToRight", "RightToLeft" },
	HorizontalAlignment = { Center = 0, Left = 1, Right = 2 },
	VerticalAlignment = { Center = 0, Top = 1, Bottom = 2 },
	FillDirection = { Horizontal = 0, Vertical = 1 },
	SortOrder = { Name = 0, Custom = 1, LayoutOrder = 2 },
	StartCorner = { "TopLeft", "TopRight", "BottomLeft", "BottomRight" },
	AutomaticSize = { "None", "X", "Y", "XY" },
	ScrollingDirection = { X = 1, Y = 2, XY = 4 },
	ScrollBarInset = { "None", "ScrollBar", "Always" },
	VerticalScrollBarPosition = { "Right", "Left" },
	ElasticBehavior = { "WhenScrollable", "Always", "Never" },
	ZIndexBehavior = { "Global", "Sibling" },
	ScreenInsets = { "None", "DeviceSafeInsets", "CoreUISafeInsets", "TopbarSafeInsets" },
	SafeAreaCompatibility = { "None", "FullscreenExtension" },
	ApplyStrokeMode = { "Contextual", "Border" },
	LineJoinMode = { "Round", "Bevel", "Miter" },
	BorderStrokePosition = { "Outer", "Center", "Inner" },
	StrokeSizingMode = { "FixedSize", "ScaledSize" },
	ScaleType = { "Stretch", "Slice", "Tile", "Fit", "Crop" },
	ResamplerMode = { "Default", "Pixelated" },
	AspectType = { "FitWithinMaxSize", "ScaleWithParentSize" },
	DominantAxis = { "Width", "Height" },
	SizeConstraint = { "RelativeXY", "RelativeXX", "RelativeYY" },
	BorderMode = { "Outline", "Middle", "Inset" },
	FrameStyle = { "Custom", "ChatBlue", "RobloxSquare", "RobloxRound", "ChatGreen", "ChatRed", "DropShadow" },
	ButtonStyle = { "Custom", "RobloxButtonDefault", "RobloxButton", "RobloxRoundButton", "RobloxRoundDefaultButton", "RobloxRoundDropdownButton" },
	EasingStyle = { "Linear", "Sine", "Back", "Quad", "Quart", "Quint", "Bounce", "Elastic", "Exponential", "Circular", "Cubic" },
	EasingDirection = { "In", "Out", "InOut" },
	PlaybackState = { "Begin", "Delayed", "Playing", "Paused", "Completed", "Cancelled" },
	UIFlexMode = { "None", "Grow", "Shrink", "Fill", "Custom" },
	UIFlexAlignment = { "None", "Fill", "SpaceAround", "SpaceBetween", "SpaceEvenly" },
	ItemLineAlignment = { "Automatic", "Start", "Center", "End", "Stretch" },
	SelectionBehavior = { "Escape", "Stop" },
	GuiState = { "Idle", "Hover", "Press", "NonInteractable" },
	CoreGuiType = { "PlayerList", "Health", "Backpack", "Chat", "All", "EmotesMenu", "SelfView", "Captures" },
	InfoType = { Asset = 0, Product = 1, GamePass = 2, Subscription = 3, Bundle = 4 },
	ChatVersion = { "LegacyChatService", "TextChatService" },
	RenderPriority = { First = 0, Input = 100, Camera = 200, Character = 300, Last = 2000 },
	TweenStatus = { "Canceled", "Completed" },
	ScreenOrientation = { "LandscapeLeft", "LandscapeRight", "LandscapeSensor", "Portrait", "Sensor" },
	PreferredInput = { "KeyboardAndMouse", "Gamepad", "Touch" },
	ThumbnailType = { "HeadShot", "AvatarBust", "AvatarThumbnail" },
	ThumbnailSize = { "Size48x48", "Size60x60", "Size100x100", "Size150x150", "Size180x180", "Size352x352", "Size420x420" },
}

local EnumItemMeta = { __kind = "EnumItem" }
local EnumTypeMeta = { __kind = "Enum" }
local enumTypes = {}

EnumItemMeta.__index = function(item, key)
	if key == "IsA" then
		return function(self, typeName)
			return rawget(self, "EnumType").__name == typeName
		end
	end
	M.Fail(fmt("%s is not a valid member of EnumItem", tostring(key)), 2)
end
EnumItemMeta.__tostring = function(item)
	return "Enum." .. rawget(item, "EnumType").__name .. "." .. rawget(item, "Name")
end

local function makeItem(enumType, name, value)
	local item = setmetatable({ Name = name, Value = value, EnumType = enumType }, EnumItemMeta)
	enumType.__items[name] = item
	table.insert(enumType.__list, item)
	return item
end

local function getEnumType(name)
	local existing = enumTypes[name]
	if existing then
		return existing
	end
	local enumType = setmetatable({ __name = name, __items = {}, __list = {}, __strict = ENUMS[name] ~= nil }, EnumTypeMeta)
	enumTypes[name] = enumType
	local spec = ENUMS[name]
	if spec then
		if #spec > 0 then
			for index, itemName in spec do
				makeItem(enumType, itemName, index - 1)
			end
		else
			local names = {}
			for itemName in spec do
				table.insert(names, itemName)
			end
			table.sort(names, function(a, b)
				return spec[a] < spec[b]
			end)
			for _, itemName in names do
				makeItem(enumType, itemName, spec[itemName])
			end
		end
	end
	return enumType
end

EnumTypeMeta.__index = function(enumType, key)
	if key == "GetEnumItems" then
		return function(self)
			return table.clone(rawget(self, "__list"))
		end
	elseif key == "FromName" then
		return function(self, itemName)
			return rawget(self, "__items")[itemName]
		end
	elseif key == "FromValue" then
		return function(self, value)
			for _, item in rawget(self, "__list") do
				if item.Value == value then
					return item
				end
			end
			return nil
		end
	end
	local item = rawget(enumType, "__items")[key]
	if item then
		return item
	end
	if rawget(enumType, "__strict") then
		M.Fail(fmt("%s is not a valid member of \"Enum.%s\"", tostring(key), rawget(enumType, "__name")), 2)
	end
	return makeItem(enumType, key, #rawget(enumType, "__list"))
end
EnumTypeMeta.__newindex = immutable("Enum")
EnumTypeMeta.__tostring = function(enumType)
	return rawget(enumType, "__name")
end

local Enum = setmetatable({}, {
	__kind = "Enums",
	__index = function(_, name)
		if name == "GetEnums" then
			return function()
				local list = {}
				for _, enumType in enumTypes do
					table.insert(list, enumType)
				end
				return list
			end
		end
		return getEnumType(name)
	end,
	__newindex = immutable("Enum"),
})
M.Enum = Enum
function M.EnumTypeOf(item)
	return rawget(item, "EnumType").__name
end
-- Coerces a string / number / EnumItem to an item of `typeName` (nil when it doesn't fit)
function M.CoerceEnum(typeName, value)
	local enumType = getEnumType(typeName)
	local kind = kindOf(value)
	if kind == "EnumItem" then
		return if rawget(value, "EnumType") == enumType then value else nil
	elseif type(value) == "string" then
		return rawget(enumType, "__items")[value]
	elseif type(value) == "number" then
		for _, item in rawget(enumType, "__list") do
			if item.Value == value then
				return item
			end
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------------- Font
local Font = {}
local FontMeta = { __kind = "Font" }
FontMeta.__index = function(self, key)
	if key == "Bold" then
		return rawget(self, "Weight").Value >= 600
	end
	M.Fail(fmt("%s is not a valid member of Font", tostring(key)), 2)
end
FontMeta.__newindex = immutable("Font")
FontMeta.__eq = function(a, b)
	return rawget(a, "Family") == rawget(b, "Family") and rawget(a, "Weight") == rawget(b, "Weight") and rawget(a, "Style") == rawget(b, "Style")
end
FontMeta.__tostring = function(f)
	return fmt("Font { Family = %s, Weight = %s, Style = %s }", rawget(f, "Family"), rawget(f, "Weight").Name, rawget(f, "Style").Name)
end
local function makeFont(family, weight, style)
	return setmetatable({ Family = family, Weight = weight or Enum.FontWeight.Regular, Style = style or Enum.FontStyle.Normal }, FontMeta)
end
-- Enum.Font -> family json + weight (as Roblox maps them)
local FONT_FAMILIES = {
	Legacy = { "LegacyArial", "Regular" }, Arial = { "Arimo", "Regular" }, ArialBold = { "Arimo", "Bold" },
	SourceSans = { "SourceSansPro", "Regular" }, SourceSansBold = { "SourceSansPro", "Bold" },
	SourceSansSemibold = { "SourceSansPro", "SemiBold" }, SourceSansLight = { "SourceSansPro", "Light" },
	SourceSansItalic = { "SourceSansPro", "Regular", "Italic" },
	Gotham = { "GothamSSm", "Regular" }, GothamMedium = { "GothamSSm", "Medium" }, GothamBold = { "GothamSSm", "Bold" },
	GothamBlack = { "GothamSSm", "Heavy" },
	BuilderSans = { "BuilderSans", "Regular" }, BuilderSansMedium = { "BuilderSans", "Medium" },
	BuilderSansBold = { "BuilderSans", "Bold" }, BuilderSansExtraBold = { "BuilderSans", "ExtraBold" },
	Arimo = { "Arimo", "Regular" }, ArimoBold = { "Arimo", "Bold" },
	RobotoCondensed = { "RobotoCondensed", "Regular" }, RobotoMono = { "RobotoMono", "Regular" },
}
function Font.new(family, weight, style)
	return makeFont(family, weight, style)
end
function Font.fromEnum(fontEnum)
	local name = fontEnum.Name
	local spec = FONT_FAMILIES[name] or { name, "Regular" }
	return makeFont("rbxasset://fonts/families/" .. spec[1] .. ".json", Enum.FontWeight[spec[2]], Enum.FontStyle[spec[3] or "Normal"])
end
function Font.fromName(name, weight, style)
	return makeFont("rbxasset://fonts/families/" .. name .. ".json", weight, style)
end
function Font.fromId(id, weight, style)
	return makeFont("rbxassetid://" .. tostring(id), weight, style)
end
-- Font datatype -> the Enum.Font it came from (Unknown when there is none)
function M.EnumFromFont(font)
	local family = string.match(rawget(font, "Family"), "families/(.-)%.json") or ""
	local weight = rawget(font, "Weight").Name
	for name, spec in FONT_FAMILIES do
		if spec[1] == family and spec[2] == weight and (spec[3] or "Normal") == rawget(font, "Style").Name then
			return Enum.Font[name]
		end
	end
	local item = rawget(getEnumType("Font"), "__items")[family]
	if item and weight == "Regular" then
		return item
	end
	return Enum.Font.Unknown
end
M.Font = Font

---------------------------------------------------------------------------------------------------- scheduler
-- Threads wait on a simulated clock. Run(seconds) steps 60 frames per simulated second: due threads
-- resume (task.defer'd ones the same frame), then RenderStepped / Heartbeat fire, then M.AfterFrame
-- (layout + AbsoluteSize/Position change signals).
local Scheduler = { Queue = {}, Seq = 0, Cancelled = {} }
M.Scheduler = Scheduler

local function reportError(thread, err)
	local trace = debug.traceback(thread)
	table.insert(M.Errors, { Message = tostring(err), Trace = trace })
end

local function resume(thread, ...)
	if coroutine.status(thread) ~= "suspended" then
		return
	end
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		reportError(thread, err)
	end
end
M.Resume = resume

local function schedule(time, thread, ...)
	Scheduler.Seq += 1
	table.insert(Scheduler.Queue, { Time = time, Seq = Scheduler.Seq, Thread = thread, Args = table.pack(...) })
end
M.Schedule = schedule

local function currentThread()
	local thread, isMain = coroutine.running()
	if isMain or not coroutine.isyieldable() then
		M.Gap("yielding outside a task (the mock runs game code in coroutines)", 3)
	end
	return thread
end

local task = {}
function task.wait(seconds)
	local thread = currentThread()
	local started = M.Now
	seconds = math.max(tonumber(seconds) or 0, 0)
	schedule(M.Now + math.max(seconds, 1 / 120), thread)
	coroutine.yield()
	return M.Now - started
end
function task.spawn(fn, ...)
	local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
	resume(thread, ...)
	return thread
end
function task.defer(fn, ...)
	local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
	schedule(M.Now, thread, ...)
	return thread
end
function task.delay(seconds, fn, ...)
	local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
	schedule(M.Now + math.max(tonumber(seconds) or 0, 0), thread, ...)
	return thread
end
function task.cancel(thread)
	Scheduler.Cancelled[thread] = true
	if coroutine.status(thread) == "suspended" then
		pcall(coroutine.close, thread)
	end
end
function task.synchronize() end
function task.desynchronize() end
M.task = task

-- Resumes every thread due at the current time (including ones scheduled while doing so)
function Scheduler.Flush()
	local guard = 0
	while true do
		local best, bestIndex = nil, nil
		for index, entry in Scheduler.Queue do
			if entry.Time <= M.Now + 1e-9 and (best == nil or entry.Time < best.Time or (entry.Time == best.Time and entry.Seq < best.Seq)) then
				best, bestIndex = entry, index
			end
		end
		if not best then
			return
		end
		table.remove(Scheduler.Queue, bestIndex)
		if not Scheduler.Cancelled[best.Thread] then
			resume(best.Thread, table.unpack(best.Args, 1, best.Args.n))
		end
		guard += 1
		if guard > 200000 then
			table.insert(M.Errors, { Message = "mock: more than 200000 resumes in one frame (task.defer loop?)", Trace = "" })
			return
		end
	end
end

M.FrameHooks = {} -- functions(dt) run every frame after threads resume (RunService events)
M.AfterFrame = nil -- set by mock_layout: layout + property signals

function Scheduler.Run(seconds)
	local dt = 1 / 60
	local target = M.Now + seconds
	Scheduler.Flush()
	if M.AfterFrame then
		M.AfterFrame()
	end
	while M.Now < target - 1e-9 do
		M.Now += dt
		M.Frame += 1
		Scheduler.Flush()
		for _, hook in M.FrameHooks do
			hook(dt)
		end
		Scheduler.Flush()
		if M.AfterFrame then
			M.AfterFrame()
		end
	end
end

---------------------------------------------------------------------------------------------------- signals
local SignalMeta = { __kind = "RBXScriptSignal" }
local SignalMethods = {}
local ConnectionMeta = { __kind = "RBXScriptConnection" }
ConnectionMeta.__index = function(self, key)
	if key == "Disconnect" then
		return function(conn)
			rawset(conn, "Connected", false)
		end
	end
	return nil
end

SignalMeta.__index = function(self, key)
	local method = SignalMethods[key]
	if method then
		return method
	end
	M.Fail(fmt("%s is not a valid member of RBXScriptSignal", tostring(key)), 2)
end
SignalMeta.__tostring = function(self)
	return "Signal " .. tostring(rawget(self, "Name"))
end

function SignalMethods.Connect(self, fn)
	if type(fn) ~= "function" then
		M.Fail("Attempt to connect failed: Passed value is not a function", 2)
	end
	local conn = setmetatable({ Connected = true, Fn = fn }, ConnectionMeta)
	table.insert(rawget(self, "Connections"), conn)
	local onConnect = rawget(self, "OnConnect")
	if onConnect then
		onConnect()
	end
	return conn
end
SignalMethods.ConnectParallel = SignalMethods.Connect
function SignalMethods.Once(self, fn)
	local conn
	conn = SignalMethods.Connect(self, function(...)
		if rawget(conn, "Connected") then
			rawset(conn, "Connected", false)
			fn(...)
		end
	end)
	return conn
end
function SignalMethods.Wait(self)
	local thread = currentThread()
	table.insert(rawget(self, "Waiting"), thread)
	return coroutine.yield()
end

function M.NewSignal(name, onConnect)
	return setmetatable({ Name = name, Connections = {}, Waiting = {}, OnConnect = onConnect }, SignalMeta)
end
function M.Fire(signal, ...)
	local connections = rawget(signal, "Connections")
	if #connections > 0 then
		local live = {}
		for _, conn in connections do
			if rawget(conn, "Connected") then
				table.insert(live, conn)
			end
		end
		rawset(signal, "Connections", live)
		for _, conn in table.clone(live) do
			if rawget(conn, "Connected") then
				task.spawn(rawget(conn, "Fn"), ...)
			end
		end
	end
	local waiting = rawget(signal, "Waiting")
	if #waiting > 0 then
		rawset(signal, "Waiting", {})
		for _, thread in waiting do
			resume(thread, ...)
		end
	end
end
function M.HasListeners(signal)
	return #rawget(signal, "Connections") > 0 or #rawget(signal, "Waiting") > 0
end
function M.DisconnectAll(signal)
	for _, conn in rawget(signal, "Connections") do
		rawset(conn, "Connected", false)
	end
	rawset(signal, "Connections", {})
end
