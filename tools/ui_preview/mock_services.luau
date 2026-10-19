--!nocheck
-- UI preview mock, part 4 of 4: the DataModel (game), the services the client uses, require(), the
-- global environment, JSON, and the helpers the generated bundle calls to build the project tree
-- (M.Node / M.Module / M.SetProps, the same scheme as tools/preview/MapMock.luau).
--
-- Services are mostly permissive stand-ins: what the client code reads gets a sensible value (screen
-- size, top bar inset, touch/keyboard flags from the --screen preset), calls that would talk to Roblox
-- (purchases, data stores, thumbnails) do nothing and are listed in the report as notes.

local M = ...
local fmt = string.format
local Enum = M.Enum
local task = M.task
local Instance = M.Instance
local v2, v3 = M.v2, M.v3
local kindOf = M.KindOf
local class = M.DefineClass
local NIL = M.NIL

M.Config = M.Config or {}

---------------------------------------------------------------------------------------------------- JSON
local function jsonString(s)
	s = string.gsub(s, "[%c\"\\]", function(c)
		if c == "\"" then
			return "\\\""
		elseif c == "\\" then
			return "\\\\"
		elseif c == "\n" then
			return "\\n"
		elseif c == "\r" then
			return "\\r"
		elseif c == "\t" then
			return "\\t"
		end
		return fmt("\\u%04x", string.byte(c))
	end)
	return "\"" .. s .. "\""
end

local function jsonNumber(n)
	if n ~= n or n == math.huge or n == -math.huge then
		return "null"
	end
	if n == math.floor(n) and math.abs(n) < 1e15 then
		return fmt("%d", n)
	end
	return fmt("%.5g", n)
end

local function isArray(t)
	local n = #t
	if n == 0 then
		return next(t) == nil
	end
	local count = 0
	for _ in t do
		count += 1
	end
	return count == n
end

local function encode(value, out, seen, strict)
	local t = type(value)
	if t == "nil" then
		table.insert(out, "null")
	elseif t == "boolean" then
		table.insert(out, if value then "true" else "false")
	elseif t == "number" then
		table.insert(out, jsonNumber(value))
	elseif t == "string" then
		table.insert(out, jsonString(value))
	elseif t == "table" then
		local kind = kindOf(value)
		if kind ~= "table" then
			if strict then
				error("Cannot convert " .. kind .. " to JSON", 0)
			end
			table.insert(out, jsonString(tostring(value)))
			return
		end
		if seen[value] then
			error("Cannot encode a table that contains itself", 0)
		end
		seen[value] = true
		if isArray(value) and next(value) ~= nil then
			table.insert(out, "[")
			for i, item in ipairs(value) do
				if i > 1 then
					table.insert(out, ",")
				end
				encode(item, out, seen, strict)
			end
			table.insert(out, "]")
		elseif next(value) == nil then
			table.insert(out, if strict then "[]" else "{}")
		else
			table.insert(out, "{")
			local keys = {}
			for k in value do
				table.insert(keys, k)
			end
			table.sort(keys, function(a, b)
				return tostring(a) < tostring(b)
			end)
			for i, k in keys do
				if i > 1 then
					table.insert(out, ",")
				end
				table.insert(out, jsonString(tostring(k)))
				table.insert(out, ":")
				encode(value[k], out, seen, strict)
			end
			table.insert(out, "}")
		end
		seen[value] = nil
	else
		if strict then
			error("Cannot convert " .. t .. " to JSON", 0)
		end
		table.insert(out, "null")
	end
end

function M.Json(value)
	local out = {}
	encode(value, out, {}, false)
	return table.concat(out)
end

local function jsonDecode(text)
	local pos = 1
	local function skip()
		pos = string.find(text, "[^ \t\r\n]", pos) or (#text + 1)
	end
	local parseValue
	local function parseString()
		local out = {}
		pos += 1
		while true do
			local c = string.sub(text, pos, pos)
			if c == "" then
				error("Can't parse JSON: unterminated string", 0)
			elseif c == "\"" then
				pos += 1
				break
			elseif c == "\\" then
				local e = string.sub(text, pos + 1, pos + 1)
				local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ["\""] = "\"", ["\\"] = "\\", ["/"] = "/" }
				if e == "u" then
					table.insert(out, utf8.char(tonumber(string.sub(text, pos + 2, pos + 5), 16)))
					pos += 6
				else
					table.insert(out, map[e] or e)
					pos += 2
				end
			else
				table.insert(out, c)
				pos += 1
			end
		end
		return table.concat(out)
	end
	parseValue = function()
		skip()
		local c = string.sub(text, pos, pos)
		if c == "{" then
			pos += 1
			local result = {}
			skip()
			if string.sub(text, pos, pos) == "}" then
				pos += 1
				return result
			end
			while true do
				skip()
				local key = parseString()
				skip()
				pos += 1 -- :
				result[key] = parseValue()
				skip()
				local sep = string.sub(text, pos, pos)
				pos += 1
				if sep == "}" then
					return result
				end
			end
		elseif c == "[" then
			pos += 1
			local result = {}
			skip()
			if string.sub(text, pos, pos) == "]" then
				pos += 1
				return result
			end
			while true do
				table.insert(result, parseValue())
				skip()
				local sep = string.sub(text, pos, pos)
				pos += 1
				if sep == "]" then
					return result
				end
			end
		elseif c == "\"" then
			return parseString()
		elseif string.sub(text, pos, pos + 3) == "true" then
			pos += 4
			return true
		elseif string.sub(text, pos, pos + 4) == "false" then
			pos += 5
			return false
		elseif string.sub(text, pos, pos + 3) == "null" then
			pos += 4
			return nil
		end
		local number = string.match(text, "^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
		if not number or number == "" then
			error("Can't parse JSON at " .. pos, 0)
		end
		pos += #number
		return tonumber(number)
	end
	return parseValue()
end
M.JsonDecode = jsonDecode

---------------------------------------------------------------------------------------------------- the DataModel and services
local function noop() end
local function stubMethod(name)
	return function()
		M.Note("stub: " .. name .. "()")
		return nil
	end
end

local services = {}
local game

local function service(name, props, opts)
	opts = opts or {}
	opts.Service = true
	opts.Permissive = true
	class(name, opts.Super or "PermissiveInstance", props or {}, opts)
end

class("DataModel", "PermissiveInstance", { PlaceId = 0, GameId = 0, JobId = "preview", PlaceVersion = 0, CreatorId = 0 }, {
	Events = { "Loaded", "Close" },
	Methods = {
		GetService = function(self, name)
			return M.GetService(name)
		end,
		FindService = function(self, name)
			return services[name]
		end,
		IsLoaded = function()
			return true
		end,
		BindToClose = noop,
		GetFullName = function()
			return "game"
		end,
	},
})

local function playerGuiOf()
	return M.PlayerGui
end

service("Players", { MaxPlayers = 12, RespawnTime = 3, CharacterAutoLoads = false }, {
	Events = { "PlayerAdded", "PlayerRemoving" },
	Methods = {
		GetPlayers = function(self)
			local list = {}
			for _, child in rawget(self, "__children") do
				if rawget(child, "__class") == "Player" then
					table.insert(list, child)
				end
			end
			return list
		end,
		GetPlayerByUserId = function(self, userId)
			for _, child in rawget(self, "__children") do
				if rawget(child, "__class") == "Player" and rawget(child, "__props").UserId == userId then
					return child
				end
			end
			return nil
		end,
		GetPlayerFromCharacter = function()
			return nil
		end,
		GetUserThumbnailAsync = function(_, userId)
			return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150", true
		end,
		GetNameFromUserIdAsync = function(_, userId)
			return "Player" .. tostring(userId)
		end,
		GetUserIdFromNameAsync = function()
			return 1
		end,
		GetFriendsAsync = stubMethod("Players:GetFriendsAsync"),
		GetHumanoidDescriptionFromUserId = stubMethod("Players:GetHumanoidDescriptionFromUserId"),
	},
})

class("Player", "PermissiveInstance", {
	UserId = 1, DisplayName = "Player", AccountAge = 365, MembershipType = Enum.MembershipType.None,
	Character = nil, Team = nil, CameraMaxZoomDistance = 70, CameraMinZoomDistance = 4, LocaleId = "en-us",
}, {
	Events = { "CharacterAdded", "CharacterRemoving", "CharacterAppearanceLoaded", "Chatted", "Idled", "OnTeleport" },
	Methods = {
		GetMouse = function(self)
			local mouse = rawget(self, "__mouse")
			if not mouse then
				mouse = Instance.new("Mouse")
				rawset(self, "__mouse", mouse)
			end
			return mouse
		end,
		Kick = function(_, message)
			table.insert(M.Warnings, "game called Player:Kick(" .. tostring(message) .. ")")
		end,
		IsInGroup = function()
			return false
		end,
		GetRankInGroup = function()
			return 0
		end,
		GetRoleInGroup = function()
			return "Guest"
		end,
		IsFriendsWith = function()
			return false
		end,
		LoadCharacter = noop,
		DistanceFromCharacter = function()
			return 0
		end,
		GetNetworkPing = function()
			return 0.05
		end,
		GetJoinData = function()
			return {}
		end,
		RequestStreamAroundAsync = noop,
	},
})
class("Mouse", "PermissiveInstance", { X = 640, Y = 360, Hit = M.CFrame.identity, Target = nil, Icon = "" }, {
	Events = { "Button1Down", "Button1Up", "Button2Down", "Button2Up", "Move", "WheelForward", "WheelBackward", "Idle" },
})

service("Workspace", { Gravity = 196.2, DistributedGameTime = 0, StreamingEnabled = false, FallenPartsDestroyHeight = -200 }, {
	Super = "Model",
	Methods = {
		GetServerTimeNow = function()
			return M.ClockBase + M.Now
		end,
		Raycast = function()
			return nil
		end,
		Spherecast = function()
			return nil
		end,
		Blockcast = function()
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
		FindPartOnRay = function()
			return nil, v3(0, 0, 0)
		end,
		FindPartOnRayWithIgnoreList = function()
			return nil, v3(0, 0, 0)
		end,
		FindPartsInRegion3 = function()
			return {}
		end,
		BulkMoveTo = noop,
		GetRealPhysicsFPS = function()
			return 60
		end,
		ArePartsTouchingOthers = function()
			return false
		end,
	},
	Computed = {
		DistributedGameTime = function()
			return M.Now
		end,
	},
})

service("Lighting", {
	ClockTime = 14, Brightness = 2, Ambient = M.Color3.fromRGB(100, 100, 120), OutdoorAmbient = M.Color3.fromRGB(150, 150, 165),
	FogEnd = 100000, FogStart = 0, FogColor = M.Color3.fromRGB(192, 192, 192), GlobalShadows = true, ExposureCompensation = 0,
	EnvironmentDiffuseScale = 1, EnvironmentSpecularScale = 1, GeographicLatitude = 41.7, TimeOfDay = "14:00:00",
	ColorShift_Top = M.Color3.new(0, 0, 0), ColorShift_Bottom = M.Color3.new(0, 0, 0), ShadowSoftness = 0.2,
}, {
	Events = { "LightingChanged" },
	Methods = {
		GetMinutesAfterMidnight = function(self)
			return rawget(self, "__props").ClockTime * 60
		end,
		SetMinutesAfterMidnight = function(self, minutes)
			rawget(self, "__props").ClockTime = minutes / 60
		end,
		GetSunDirection = function()
			return v3(0.3, 0.8, 0.5).Unit
		end,
		GetMoonDirection = function()
			return v3(-0.3, -0.8, -0.5).Unit
		end,
	},
})

---------------------------------------------------------------------------------------------------- TweenService: end values are applied at Play, Completed fires after the tween's time
class("Tween", "PermissiveInstance", { PlaybackState = Enum.PlaybackState.Begin }, {
	Events = { "Completed" },
	Methods = {
		Play = function(self)
			local state = rawget(self, "__tween")
			if state.Played then
				return
			end
			state.Played = true
			local info = state.Info
			local target = state.Instance
			if not info.Reverses then
				for key, value in state.Goals do
					local ok, err = pcall(function()
						target[key] = value
					end)
					if not ok then
						M.RecordGap(fmt("TweenService:Create goal %s: %s", tostring(key), tostring(err)), true)
						table.insert(M.Errors, { Message = "TweenService:Create: " .. tostring(err), Trace = state.Where or "" })
					end
				end
			end
			rawget(self, "__props").PlaybackState = Enum.PlaybackState.Playing
			if info.RepeatCount < 0 then
				return -- loops forever
			end
			local duration = info.DelayTime + info.Time * (info.RepeatCount + 1) * (if info.Reverses then 2 else 1)
			state.Thread = task.delay(duration, function()
				if state.Cancelled then
					return
				end
				rawget(self, "__props").PlaybackState = Enum.PlaybackState.Completed
				M.Fire(M.GetSignal(self, "Completed"), Enum.PlaybackState.Completed)
			end)
		end,
		Cancel = function(self)
			local state = rawget(self, "__tween")
			if state.Cancelled then
				return
			end
			state.Cancelled = true
			rawget(self, "__props").PlaybackState = Enum.PlaybackState.Cancelled
			M.Fire(M.GetSignal(self, "Completed"), Enum.PlaybackState.Cancelled)
		end,
		Pause = function(self)
			rawget(self, "__props").PlaybackState = Enum.PlaybackState.Paused
		end,
	},
})

service("TweenService", {}, {
	Methods = {
		Create = function(_, instance, info, goals)
			if not M.IsInstance(instance) then
				M.Fail("TweenService:Create: instance expected", 2)
			end
			if kindOf(info) ~= "TweenInfo" then
				M.Fail("TweenService:Create: TweenInfo expected, got " .. kindOf(info), 2)
			end
			-- check the goals now like Roblox does (unknown properties fail at Create)
			for key, value in goals do
				local ok, current = pcall(function()
					return instance[key]
				end)
				if not ok then
					M.Fail(fmt("TweenService:Create: %s is not a valid property of %s", tostring(key), M.Describe(instance)), 2)
				end
				if current ~= nil and kindOf(current) ~= kindOf(value) and not (type(current) == "number" and type(value) == "number") then
					M.Fail(fmt("TweenService:Create property named '%s' cannot be tweened due to type mismatch (property is a '%s', but given type is '%s')", tostring(key), kindOf(current), kindOf(value)), 2)
				end
			end
			local tween = Instance.new("Tween")
			rawset(tween, "__tween", { Instance = instance, Info = info, Goals = table.clone(goals), Where = M.Where(2) })
			return tween
		end,
		GetValue = function(_, alpha)
			return alpha
		end,
		SmoothDamp = function(_, current)
			return current, 0
		end,
	},
})

---------------------------------------------------------------------------------------------------- RunService
local renderSteps = {}
service("RunService", {}, {
	Events = { "RenderStepped", "Heartbeat", "Stepped", "PreRender", "PreAnimation", "PreSimulation", "PostSimulation" },
	Methods = {
		IsStudio = function()
			return M.Config.Studio == true
		end,
		IsClient = function()
			return true
		end,
		IsServer = function()
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
		BindToRenderStep = function(_, name, priority, fn)
			renderSteps[name] = { Priority = priority, Fn = fn }
		end,
		UnbindFromRenderStep = function(_, name)
			renderSteps[name] = nil
		end,
		Set3dRenderingEnabled = noop,
	},
})

table.insert(M.FrameHooks, function(dt)
	local run = services.RunService
	if not run then
		return
	end
	local steps = {}
	for _, step in renderSteps do
		table.insert(steps, step)
	end
	table.sort(steps, function(a, b)
		return a.Priority < b.Priority
	end)
	for _, step in steps do
		task.spawn(step.Fn, dt)
	end
	local signals = rawget(run, "__signals")
	for _, name in { "PreRender", "RenderStepped", "PreAnimation", "PreSimulation" } do
		if signals[name] then
			M.Fire(signals[name], dt)
		end
	end
	if signals.Stepped then
		M.Fire(signals.Stepped, M.Now, dt)
	end
	for _, name in { "PostSimulation", "Heartbeat" } do
		if signals[name] then
			M.Fire(signals[name], dt)
		end
	end
end)

---------------------------------------------------------------------------------------------------- input, gui, chat
service("UserInputService", {
	MouseBehavior = Enum.MouseBehavior.Default, MouseIconEnabled = true, MouseDeltaSensitivity = 1,
	ModalEnabled = false, OnScreenKeyboardVisible = false, AccelerometerEnabled = false, GyroscopeEnabled = false,
	VREnabled = false,
}, {
	Events = {
		"InputBegan", "InputChanged", "InputEnded", "TouchStarted", "TouchMoved", "TouchEnded", "TouchTap", "TouchLongPress",
		"TouchPan", "TouchPinch", "TouchSwipe", "TouchTapInWorld", "LastInputTypeChanged", "JumpRequest", "WindowFocused",
		"WindowFocusReleased", "TextBoxFocused", "TextBoxFocusReleased", "GamepadConnected", "GamepadDisconnected",
		"PointerAction",
	},
	Computed = {
		TouchEnabled = function()
			return M.Screen.Touch == true
		end,
		KeyboardEnabled = function()
			return M.Screen.Touch ~= true
		end,
		MouseEnabled = function()
			return M.Screen.Touch ~= true
		end,
		GamepadEnabled = function()
			return false
		end,
		PreferredInput = function()
			return if M.Screen.Touch then Enum.PreferredInput.Touch else Enum.PreferredInput.KeyboardAndMouse
		end,
	},
	Methods = {
		GetLastInputType = function()
			return if M.Screen.Touch then Enum.UserInputType.Touch else Enum.UserInputType.MouseMovement
		end,
		GetMouseLocation = function()
			return v2(M.Screen.W / 2, M.Screen.H / 2)
		end,
		GetMouseDelta = function()
			return v2(0, 0)
		end,
		IsKeyDown = function()
			return false
		end,
		IsMouseButtonPressed = function()
			return false
		end,
		IsGamepadButtonDown = function()
			return false
		end,
		GetKeysPressed = function()
			return {}
		end,
		GetMouseButtonsPressed = function()
			return {}
		end,
		GetConnectedGamepads = function()
			return {}
		end,
		GetNavigationGamepads = function()
			return {}
		end,
		GetGamepadConnected = function()
			return false
		end,
		GetFocusedTextBox = function()
			return nil
		end,
		GetStringForKeyCode = function(_, keyCode)
			return keyCode.Name
		end,
		GetImageForKeyCode = function()
			return ""
		end,
	},
})

service("GuiService", {
	AutoSelectGuiEnabled = true, CoreGuiNavigationEnabled = true, GuiNavigationEnabled = true, MenuIsOpen = false,
	SelectedObject = nil, IsModalDialog = false, IsWindows = false, PreferredTransparency = 1, ReducedMotionEnabled = false,
	TouchControlsEnabled = true,
}, {
	Events = { "MenuOpened", "MenuClosed", "ErrorMessageChanged" },
	Methods = {
		GetGuiInset = function()
			return v2(0, M.Screen.InsetTop), v2(0, 0)
		end,
		IsTenFootInterface = function()
			return false
		end,
		GetScreenResolution = function()
			return v2(M.Screen.W, M.Screen.H)
		end,
		Select = noop,
		AddSelectionParent = noop,
		RemoveSelectionGroup = noop,
		CloseInspectMenu = noop,
	},
	Computed = {
		TopbarInset = function()
			return M.Rect.new(0, 0, M.Screen.W, M.Screen.InsetTop)
		end,
	},
})

service("TextChatService", { ChatVersion = Enum.ChatVersion.TextChatService, CreateDefaultCommands = true, CreateDefaultTextChannels = true }, {
	Events = { "MessageReceived", "SendingMessage" },
	Methods = {
		CanUserChatAsync = function()
			return true
		end,
		CanUsersChatAsync = function()
			return true
		end,
		DisplayBubble = noop,
	},
})

service("StarterGui", { ShowDevelopmentGui = true, ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor }, {
	Methods = {
		SetCoreGuiEnabled = function(_, coreType, enabled)
			M.CoreGui = M.CoreGui or {}
			M.CoreGui[coreType.Name] = enabled
		end,
		GetCoreGuiEnabled = function(_, coreType)
			local state = M.CoreGui and M.CoreGui[coreType.Name]
			return state ~= false
		end,
		SetCore = function(_, name)
			M.Note("stub: StarterGui:SetCore(\"" .. tostring(name) .. "\")")
		end,
		GetCore = function()
			return nil
		end,
	},
})

---------------------------------------------------------------------------------------------------- everything else the client touches
service("SoundService", { AmbientReverb = Enum.ReverbType.NoReverb, RespectFilteringEnabled = true, DistanceFactor = 3.33, RolloffScale = 1 }, {
	Methods = {
		PlayLocalSound = noop,
		SetListener = noop,
		GetListener = function()
			return Enum.ListenerType.Camera, nil
		end,
	},
})

service("ContentProvider", { RequestQueueSize = 0, BaseUrl = "https://www.roblox.com/" }, {
	Methods = {
		PreloadAsync = function(_, list, callback)
			if callback then
				for _, item in list do
					callback(if type(item) == "string" then item else "", Enum.AssetFetchStatus.Success)
				end
			end
		end,
		GetAssetFetchStatus = function()
			return Enum.AssetFetchStatus.Success
		end,
	},
})

service("HttpService", { HttpEnabled = false }, {
	Methods = {
		JSONEncode = function(_, value)
			local out = {}
			local ok, err = pcall(encode, value, out, {}, true)
			if not ok then
				M.Fail(tostring(err), 2)
			end
			return table.concat(out)
		end,
		JSONDecode = function(_, text)
			local ok, result = pcall(jsonDecode, text)
			if not ok then
				error(result, 2)
			end
			return result
		end,
		GenerateGUID = function(_, braces)
			local guid = string.gsub("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx", "[xy]", function(c)
				local v = if c == "x" then math.random(0, 15) else math.random(8, 11)
				return fmt("%X", v)
			end)
			return if braces == false then guid else "{" .. guid .. "}"
		end,
		UrlEncode = function(_, text)
			return (string.gsub(text, "[^%w%-_%.~]", function(c)
				return fmt("%%%02X", string.byte(c))
			end))
		end,
		GetAsync = function()
			error("HTTP requests are not enabled (preview)", 2)
		end,
		PostAsync = function()
			error("HTTP requests are not enabled (preview)", 2)
		end,
		RequestAsync = function()
			error("HTTP requests are not enabled (preview)", 2)
		end,
	},
})

service("MarketplaceService", {}, {
	Events = { "PromptGamePassPurchaseFinished", "PromptProductPurchaseFinished", "PromptPurchaseFinished", "PromptBundlePurchaseFinished", "PromptPremiumPurchaseFinished" },
	Methods = {
		GetProductInfo = function()
			error("HTTP 403 (the preview has no network)", 2)
		end,
		GetProductInfoAsync = function()
			error("HTTP 403 (the preview has no network)", 2)
		end,
		UserOwnsGamePassAsync = function()
			return false
		end,
		PlayerOwnsAsset = function()
			return false
		end,
		PromptGamePassPurchase = function(_, _, id)
			M.Note("stub: MarketplaceService:PromptGamePassPurchase(" .. tostring(id) .. ")")
		end,
		PromptProductPurchase = function(_, _, id)
			M.Note("stub: MarketplaceService:PromptProductPurchase(" .. tostring(id) .. ")")
		end,
		PromptPurchase = stubMethod("MarketplaceService:PromptPurchase"),
		PromptPremiumPurchase = stubMethod("MarketplaceService:PromptPremiumPurchase"),
		GetDeveloperProductsAsync = function()
			return { GetCurrentPage = function()
				return {}
			end, IsFinished = true }
		end,
	},
})

service("PolicyService", {}, {
	Methods = {
		GetPolicyInfoForPlayerAsync = function()
			return {
				ArePaidRandomItemsRestricted = false, AllowedExternalLinkReferences = {}, IsPaidItemTradingAllowed = true,
				IsSubjectToChinaPolicies = false, IsContentSharingAllowed = true, AreAdsAllowed = true,
			}
		end,
	},
})

service("Debris", { MaxItems = 1000 }, {
	Methods = {
		AddItem = function(_, item, lifetime)
			task.delay(lifetime or 10, function()
				if M.IsInstance(item) then
					item:Destroy()
				end
			end)
		end,
	},
})

local tagAdded, tagRemoved = {}, {}
local function tagSignal(list, tag)
	if not list[tag] then
		list[tag] = M.NewSignal("Tag:" .. tag)
	end
	return list[tag]
end
service("CollectionService", {}, {
	Events = { "TagAdded", "TagRemoved" },
	Methods = {
		GetTagged = function(_, tag)
			local found = {}
			for _, object in game:GetDescendants() do
				if rawget(object, "__tags")[tag] then
					table.insert(found, object)
				end
			end
			return found
		end,
		GetTags = function(_, object)
			return object:GetTags()
		end,
		HasTag = function(_, object, tag)
			return object:HasTag(tag)
		end,
		AddTag = function(_, object, tag)
			object:AddTag(tag)
			M.Fire(tagSignal(tagAdded, tag), object)
		end,
		RemoveTag = function(_, object, tag)
			object:RemoveTag(tag)
			M.Fire(tagSignal(tagRemoved, tag), object)
		end,
		GetInstanceAddedSignal = function(_, tag)
			return tagSignal(tagAdded, tag)
		end,
		GetInstanceRemovedSignal = function(_, tag)
			return tagSignal(tagRemoved, tag)
		end,
		GetAllTags = function()
			return {}
		end,
	},
})

service("ProximityPromptService", { Enabled = true, MaxPromptsVisible = 16 }, {
	Events = { "PromptTriggered", "PromptShown", "PromptHidden", "PromptButtonHoldBegan", "PromptButtonHoldEnded", "PromptTriggerEnded" },
})

service("TextService", {}, {
	Methods = {
		GetTextSize = function(_, text, size, font, frame)
			return M.Layout.MeasureText(text, size, font, frame)
		end,
		GetTextBoundsAsync = function(_, params)
			local p = rawget(params, "__props")
			return M.Layout.MeasureFont(p.Text or "", p.Size or 14, p.Font or M.Font.fromEnum(Enum.Font.SourceSans), p.Width)
		end,
		FilterStringAsync = function(_, text)
			return { GetNonChatStringForBroadcastAsync = function()
				return text
			end, GetChatForUserAsync = function()
				return text
			end, GetNonChatStringForUserAsync = function()
				return text
			end }
		end,
	},
})
class("GetTextBoundsParams", "PermissiveInstance", { Text = "", Size = 14, Width = 0 })

service("ContextActionService", {}, {
	Events = { "LocalToolEquipped", "LocalToolUnequipped" },
	Methods = {
		BindAction = noop,
		BindActionAtPriority = noop,
		UnbindAction = noop,
		SetTitle = noop,
		SetImage = noop,
		SetPosition = noop,
		GetButton = function()
			return nil
		end,
	},
})

service("LocalizationService", { RobloxLocaleId = "en-us", SystemLocaleId = "en-us" }, {
	Methods = {
		GetTranslatorForPlayerAsync = function()
			return M.Stub("Translator", { Translate = function(_, _, text)
				return text
			end, FormatByKey = function(_, key)
				return key
			end, LocaleId = "en-us" })
		end,
		GetCountryRegionForPlayerAsync = function()
			return "US"
		end,
	},
})

service("VRService", { VREnabled = false }, { Methods = { GetUserCFrameEnabled = function()
	return false
end } })
service("HapticService", {}, { Methods = { IsVibrationSupported = function()
	return false
end, IsMotorSupported = function()
	return false
end, SetMotor = noop } })
service("SocialService", {}, { Methods = { CanSendGameInviteAsync = function()
	return false
end, PromptGameInvite = noop } })
service("BadgeService", {}, { Methods = { UserHasBadgeAsync = function()
	return false
end, GetBadgeInfoAsync = stubMethod("BadgeService:GetBadgeInfoAsync"), AwardBadge = noop } })
service("TeleportService", {}, { Events = { "TeleportInitFailed", "LocalPlayerArrivedFromTeleport" }, Methods = { Teleport = stubMethod("TeleportService:Teleport"), TeleportAsync = stubMethod("TeleportService:TeleportAsync"), GetLocalPlayerTeleportData = function()
	return nil
end, SetTeleportGui = noop } })
service("GroupService", {}, { Methods = { GetGroupInfoAsync = stubMethod("GroupService:GetGroupInfoAsync"), GetGroupsAsync = function()
	return {}
end } })
service("AssetService", {}, { Methods = { CreateEditableImage = stubMethod("AssetService:CreateEditableImage") } })
service("ExperienceNotificationService", {}, { Methods = { CanPromptOptInAsync = function()
	return false
end, PromptOptIn = noop } })
for _, name in {
	"ReplicatedStorage", "ReplicatedFirst", "StarterPlayer", "StarterPack", "ServerStorage", "ServerScriptService", "Teams",
	"Chat", "SoundService2", "PhysicsService", "PathfindingService", "InsertService", "KeyframeSequenceProvider",
	"AnimationClipProvider", "Selection", "TestService", "Stats", "AvatarEditorService", "MemoryStoreService",
	"DataStoreService", "MessagingService", "UserService", "PlayerEmulatorService", "AdService", "StarterPlayerScripts",
	"StarterCharacterScripts", "CoreGui", "NetworkClient", "VoiceChatService", "PermissionsService", "EncodingService",
} do
	if not M.Classes[name] then
		service(name)
	end
end
M.Classes.StarterPlayerScripts.Service = nil
M.Classes.StarterCharacterScripts.Service = nil

-- Services the game asks for get created on first use (unknown ones become permissive stand-ins)
function M.GetService(name)
	local existing = services[name]
	if existing then
		return existing
	end
	if type(name) ~= "string" then
		M.Fail("GetService expects a string", 3)
	end
	if not M.Classes[name] then
		M.Note("game:GetService(\"" .. name .. "\") is a permissive stand-in in the preview")
		service(name)
	end
	local object = M.NewObject(name)
	rawget(object, "__props").Name = name
	rawset(object, "__parentLocked", false)
	services[name] = object
	M.SetParent(object, game)
	rawset(object, "__parentLocked", true)
	if name == "Workspace" then
		local camera = Instance.new("Camera")
		camera.Name = "Camera"
		camera.Parent = object
		rawget(object, "__props").CurrentCamera = camera
		local terrain = M.NewObject("Terrain")
		rawget(terrain, "__props").Name = "Terrain"
		M.SetParent(terrain, object)
		rawget(object, "__props").Terrain = terrain
	elseif name == "TextChatService" then
		local config = Instance.new("ChatWindowConfiguration")
		config.Name = "ChatWindowConfiguration"
		config.Enabled = M.Config.Chat ~= false
		config.Parent = object
		local input = Instance.new("ChatInputBarConfiguration")
		input.Name = "ChatInputBarConfiguration"
		input.Parent = object
		local bubbles = Instance.new("BubbleChatConfiguration")
		bubbles.Name = "BubbleChatConfiguration"
		bubbles.Parent = object
		local channels = Instance.new("Folder")
		channels.Name = "TextChannels"
		channels.Parent = object
	end
	return object
end

game = M.NewObject("DataModel")
rawget(game, "__props").Name = "Game"
M.game = game

---------------------------------------------------------------------------------------------------- require and the project tree
local moduleResults = {}
local moduleLoading = {}
local function require(module)
	if type(module) == "number" then
		M.Fail(fmt("require(%d): requiring assets by id is not supported by the preview", module), 2)
	end
	if not M.IsInstance(module) or rawget(module, "__class") ~= "ModuleScript" then
		M.Fail("Attempted to call require with invalid argument(s).", 2)
	end
	local result = moduleResults[module]
	if result ~= nil then
		return result
	end
	if moduleLoading[module] then
		M.Fail("Requested module was required recursively: " .. M.FullName(module), 2)
	end
	local loader = rawget(module, "__loader")
	if not loader then
		M.Fail("require(" .. M.FullName(module) .. "): the preview bundle has no source for this module", 2)
	end
	moduleLoading[module] = true
	local ok, value = pcall(loader, module)
	moduleLoading[module] = nil
	if not ok then
		error(value, 0)
	end
	if value == nil then
		M.Fail("Module code did not return exactly one value: " .. M.FullName(module), 2)
	end
	moduleResults[module] = value
	return value
end
M.require = require

local function nodeAt(path, className)
	local node = game
	if path == "" then
		return node
	end
	local segments = string.split(path, "/")
	for index, segment in segments do
		local child = M.InstanceMethods.FindFirstChild(node, segment)
		if not child then
			if node == game then
				child = M.GetService(segment)
			else
				local wanted = if index == #segments then className or "Folder" else "Folder"
				child = Instance.new(wanted)
				rawget(child, "__props").Name = segment
				M.SetParent(child, node)
			end
		end
		node = child
	end
	return node
end
M.NodeAt = nodeAt

function M.Node(path, className)
	return nodeAt(path, className)
end

function M.Module(path, chunkName, source)
	local segments = string.split(path, "/")
	local name = table.remove(segments)
	local parent = nodeAt(table.concat(segments, "/"))
	local module = M.InstanceMethods.FindFirstChild(parent, name)
	if module and rawget(module, "__class") ~= "ModuleScript" then
		rawset(module, "__class", "ModuleScript")
	elseif not module then
		module = Instance.new("ModuleScript")
		rawget(module, "__props").Name = name
		M.SetParent(module, parent)
	end
	rawset(module, "__chunk", chunkName)
	rawset(module, "__loader", function(script)
		local fn, err = loadstring("local script = ...; " .. source, "=" .. chunkName)
		if not fn then
			error("syntax error in " .. tostring(err), 0)
		end
		return fn(script)
	end)
	return module
end

-- A LocalScript's source, run by Boot (Main.client.luau)
function M.Script(path, chunkName, source)
	local node = nodeAt(path, "LocalScript")
	rawset(node, "__chunk", chunkName)
	rawset(node, "__source", source)
	return node
end

function M.RunScript(node)
	local source = rawget(node, "__source")
	local fn, err = loadstring("local script = ...; " .. source, "=" .. rawget(node, "__chunk"))
	if not fn then
		error("syntax error in " .. tostring(err), 0)
	end
	return fn(node)
end

function M.SetProps(path, props)
	local node = nodeAt(path)
	for key, value in props do
		local ok = pcall(function()
			local current = node[key]
			if type(value) == "table" and kindOf(current) == "Color3" then
				value = M.c3(value[1], value[2], value[3])
			elseif type(value) == "table" and kindOf(current) == "Vector3" then
				value = v3(value[1], value[2], value[3])
			elseif type(value) == "string" and kindOf(current) == "EnumItem" then
				value = M.CoerceEnum(M.EnumTypeOf(current), value) or value
			end
			node[key] = value
		end)
		if not ok then
			M.Note("project property " .. path .. "." .. key .. " ignored")
		end
	end
end

-- Replaces a module's code with a ready table (controller stand-ins)
function M.ReplaceModule(module, value)
	moduleResults[module] = value
end

---------------------------------------------------------------------------------------------------- globals
local realPrint = print
M.RealPrint = realPrint

local function describeArgs(...)
	local parts = {}
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		table.insert(parts, tostring(value))
	end
	return table.concat(parts, " ")
end

local function typeof(value)
	local kind = kindOf(value)
	if kind == "Enums" then
		return "Enums"
	end
	return kind
end

M.Globals = {
	Vector3 = M.Vector3, Vector2 = M.Vector2, CFrame = M.CFrame, Color3 = M.Color3, UDim = M.UDim, UDim2 = M.UDim2,
	Rect = M.Rect, NumberSequence = M.NumberSequence, NumberSequenceKeypoint = M.NumberSequenceKeypoint,
	ColorSequence = M.ColorSequence, ColorSequenceKeypoint = M.ColorSequenceKeypoint, NumberRange = M.NumberRange,
	PhysicalProperties = M.PhysicalProperties, TweenInfo = M.TweenInfo, Ray = M.Ray, Region3 = M.Region3,
	RaycastParams = M.RaycastParams, OverlapParams = M.OverlapParams, BrickColor = M.BrickColor, Font = M.Font,
	DateTime = M.DateTime, Random = M.Random, Enum = M.Enum, Instance = M.Instance,
	game = game,
	task = task,
	typeof = typeof,
	require = require,
	warn = function(...)
		table.insert(M.Warnings, describeArgs(...))
	end,
	print = function(...)
		table.insert(M.Prints, describeArgs(...))
	end,
	tick = function()
		return M.ClockBase + M.Now
	end,
	time = function()
		return M.Now
	end,
	elapsedTime = function()
		return M.Now
	end,
	wait = task.wait,
	delay = task.delay,
	spawn = function(fn, ...)
		return task.defer(fn, ...)
	end,
	settings = function()
		return M.Stub("settings", { Rendering = { QualityLevel = Enum.QualityLevel.Automatic } })
	end,
	UserSettings = function()
		local gameSettings = M.Stub("UserGameSettings", { SavedQualityLevel = Enum.SavedQualitySetting.Automatic, MasterVolume = 1 })
		return M.Stub("UserSettings", {
			GetService = function(_, name)
				if name == "UserGameSettings" then
					return gameSettings
				end
				return M.Stub(name)
			end,
			GameSettings = gameSettings,
		})
	end,
	shared = {},
	plugin = nil,
}

function M.InstallGlobals()
	M.Globals.workspace = M.GetService("Workspace")
	M.Globals.Workspace = M.Globals.workspace
	local env = getfenv(1)
	for name, value in M.Globals do
		env[name] = value
	end
	local realOs = os
	env.os = setmetatable({
		clock = function()
			return M.Now
		end,
		time = function(t)
			if t then
				return realOs.time(t)
			end
			return math.floor(M.ClockBase + M.Now)
		end,
	}, { __index = realOs })
	math.randomseed(1)
end
