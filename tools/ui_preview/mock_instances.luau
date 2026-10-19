--!nocheck
-- UI preview mock, part 2 of 4: the Instance tree.
--
-- GUI classes (everything that draws: GuiObjects, ScreenGui and the UI components) are STRICT: every
-- property has a typed default, reading or writing an unknown member fails the way Roblox does, and a
-- value of the wrong type is refused. If the game uses a real Roblox property the mock lacks, add it
-- to the class below (and teach mock_layout / page.js to draw it when it matters).
-- Everything else (parts, sounds, remotes, values, ...) is PERMISSIVE: any property can be set and
-- read back, unknown reads give nil, so world-side code the preview stubs out never trips it up.

local M = ...
local fmt = string.format
local kindOf = M.KindOf
local Enum = M.Enum
local Color3, Vector2, Vector3, UDim, UDim2, CFrame = M.Color3, M.Vector2, M.Vector3, M.UDim, M.UDim2, M.CFrame
local NumberSequence, ColorSequence = M.NumberSequence, M.ColorSequence

local NIL = setmetatable({}, { __tostring = function()
	return "nil"
end })
M.NIL = NIL

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GREY = Color3.fromRGB(163, 162, 165)
local DARK = Color3.fromRGB(27, 42, 53)
local E = Enum

---------------------------------------------------------------------------------------------------- class table
local CLASSES = {}
M.Classes = CLASSES

-- opts: Events = { names }, Methods = { name = fn }, Computed = { name = fn(self) }, Abstract, Permissive,
--       Service, Gui (draws / takes part in layout)
local function class(name, super, props, opts)
	opts = opts or {}
	local events = {}
	for _, eventName in opts.Events or {} do
		events[eventName] = true
	end
	CLASSES[name] = {
		Name = name,
		Super = super,
		Props = props or {},
		Events = events,
		Methods = opts.Methods or {},
		Computed = opts.Computed or {},
		Abstract = opts.Abstract,
		Permissive = opts.Permissive,
		Service = opts.Service,
	}
end
M.DefineClass = class

local flat = {} -- [className] = merged lookup tables
local function info(className)
	local cached = flat[className]
	if cached then
		return cached
	end
	local chain = {}
	local current = className
	while current do
		local def = CLASSES[current]
		if not def then
			break
		end
		table.insert(chain, 1, def)
		current = def.Super
	end
	local merged = { Props = {}, Events = {}, Methods = {}, Computed = {}, Ancestors = {}, Permissive = false }
	for _, def in chain do
		for k, v in def.Props do
			merged.Props[k] = v
		end
		for k in def.Events do
			merged.Events[k] = true
		end
		for k, v in def.Methods do
			merged.Methods[k] = v
		end
		for k, v in def.Computed do
			merged.Computed[k] = v
		end
		merged.Ancestors[def.Name] = true
		if def.Permissive then
			merged.Permissive = true
		end
	end
	flat[className] = merged
	return merged
end
M.ClassInfo = info

local function isA(className, target)
	return info(className).Ancestors[target] == true
end
M.ClassIsA = isA

---------------------------------------------------------------------------------------------------- base classes
class("Instance", nil, { Name = "Instance", Archivable = true }, {
	Abstract = true,
	Events = { "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "AncestryChanged", "Destroying", "Changed", "AttributeChanged" },
})
class("PermissiveInstance", "Instance", {}, { Abstract = true, Permissive = true })

local GUI_EVENTS = {
	"InputBegan", "InputChanged", "InputEnded", "MouseEnter", "MouseLeave", "MouseMoved", "MouseWheelBackward",
	"MouseWheelForward", "SelectionGained", "SelectionLost", "TouchLongPress", "TouchPan", "TouchPinch", "TouchRotate",
	"TouchSwipe", "TouchTap", "SelectionChanged",
}
local BUTTON_EVENTS = {
	"Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseButton2Click", "MouseButton2Down", "MouseButton2Up",
}

class("GuiBase", "Instance", {}, { Abstract = true })
class("GuiBase2d", "GuiBase", {
	AutoLocalize = true,
	RootLocalizationTable = NIL,
	SelectionBehaviorDown = E.SelectionBehavior.Escape,
	SelectionBehaviorLeft = E.SelectionBehavior.Escape,
	SelectionBehaviorRight = E.SelectionBehavior.Escape,
	SelectionBehaviorUp = E.SelectionBehavior.Escape,
	SelectionGroup = false,
}, {
	Abstract = true,
	Computed = {
		AbsolutePosition = function(self)
			return M.Layout.AbsolutePosition(self)
		end,
		AbsoluteSize = function(self)
			return M.Layout.AbsoluteSize(self)
		end,
		AbsoluteRotation = function(self)
			return M.Layout.AbsoluteRotation(self)
		end,
	},
})

local function tweenLegacy(self, props, callback, duration)
	for key, value in props do
		self[key] = value
	end
	if callback then
		M.task.delay(duration or 1, callback, Enum.TweenStatus.Completed)
	end
	return true
end

class("GuiObject", "GuiBase2d", {
	Active = false,
	AnchorPoint = Vector2.zero,
	AutomaticSize = E.AutomaticSize.None,
	BackgroundColor3 = GREY,
	BackgroundTransparency = 0,
	BorderColor3 = DARK,
	BorderMode = E.BorderMode.Outline,
	BorderSizePixel = 1,
	ClipsDescendants = false,
	Draggable = false,
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
	Events = GUI_EVENTS,
	Computed = {
		GuiState = function()
			return Enum.GuiState.Idle
		end,
		Transparency = function(self)
			return rawget(self, "__props").BackgroundTransparency
		end,
	},
	Methods = {
		TweenPosition = function(self, position, _, _, duration, _, callback)
			return tweenLegacy(self, { Position = position }, callback, duration)
		end,
		TweenSize = function(self, size, _, _, duration, _, callback)
			return tweenLegacy(self, { Size = size }, callback, duration)
		end,
		TweenSizeAndPosition = function(self, size, position, _, _, duration, _, callback)
			return tweenLegacy(self, { Size = size, Position = position }, callback, duration)
		end,
	},
})

class("Frame", "GuiObject", { Style = E.FrameStyle.Custom })
class("CanvasGroup", "GuiObject", { GroupColor3 = WHITE, GroupTransparency = 0 })

local TEXT_PROPS = {
	Font = E.Font.Legacy,
	FontFace = M.Font.fromEnum(E.Font.Legacy),
	LineHeight = 1,
	MaxVisibleGraphemes = -1,
	OpenTypeFeatures = "",
	RichText = false,
	Text = "Label",
	TextColor3 = DARK,
	TextDirection = E.TextDirection.Auto,
	TextScaled = false,
	TextSize = 14,
	TextStrokeColor3 = BLACK,
	TextStrokeTransparency = 1,
	TextTransparency = 0,
	TextTruncate = E.TextTruncate.None,
	TextWrapped = false,
	TextXAlignment = E.TextXAlignment.Center,
	TextYAlignment = E.TextYAlignment.Center,
}
local TEXT_COMPUTED = {
	TextBounds = function(self)
		return M.Layout.TextBounds(self)
	end,
	TextFits = function(self)
		return M.Layout.TextFits(self)
	end,
	ContentText = function(self)
		return M.StripRichText(rawget(self, "__props").Text, rawget(self, "__props").RichText)
	end,
	LocalizedText = function(self)
		return rawget(self, "__props").Text
	end,
	TextWrap = function(self)
		return rawget(self, "__props").TextWrapped
	end,
	Transparency = function(self)
		return rawget(self, "__props").BackgroundTransparency
	end,
}
local function withText(extra)
	local props = table.clone(TEXT_PROPS)
	for k, v in extra or {} do
		props[k] = v
	end
	return props
end

local BUTTON_PROPS = { AutoButtonColor = true, Modal = false, Selected = false, Style = E.ButtonStyle.Custom, Active = true, Selectable = true }

-- Roblox's abstract bases: TextLabel / ImageLabel are GuiLabels, TextButton / ImageButton are GuiButtons
class("GuiLabel", "GuiObject", {}, { Abstract = true })
class("GuiButton", "GuiObject", {}, { Abstract = true, Events = BUTTON_EVENTS })
class("TextLabel", "GuiLabel", withText({}), { Computed = TEXT_COMPUTED })
do
	local props = withText(table.clone(BUTTON_PROPS))
	props.Text = "Button"
	class("TextButton", "GuiButton", props, { Computed = TEXT_COMPUTED, Events = BUTTON_EVENTS })
end
do
	local props = withText({ Text = "", ClearTextOnFocus = true, CursorPosition = 1, MultiLine = false, PlaceholderColor3 = Color3.fromRGB(178, 178, 178), PlaceholderText = "", SelectionStart = -1, ShowNativeInput = true, TextEditable = true, Active = true, Selectable = true })
	props.Text = "TextBox"
	class("TextBox", "GuiObject", props, {
		Computed = TEXT_COMPUTED,
		Events = { "FocusLost", "Focused", "ReturnPressedFromOnScreenKeyboard" },
		Methods = {
			CaptureFocus = function() end,
			ReleaseFocus = function() end,
			IsFocused = function()
				return false
			end,
		},
	})
end

local IMAGE_PROPS = {
	Image = "",
	ImageColor3 = WHITE,
	ImageContent = NIL,
	ImageRectOffset = Vector2.zero,
	ImageRectSize = Vector2.zero,
	ImageTransparency = 0,
	ResampleMode = E.ResamplerMode.Default,
	ScaleType = E.ScaleType.Stretch,
	SliceCenter = M.Rect.new(0, 0, 0, 0),
	SliceScale = 1,
	TileSize = UDim2.fromScale(1, 1),
}
local IMAGE_COMPUTED = {
	IsLoaded = function()
		return true
	end,
	Transparency = function(self)
		return rawget(self, "__props").BackgroundTransparency
	end,
}
class("ImageLabel", "GuiLabel", table.clone(IMAGE_PROPS), { Computed = IMAGE_COMPUTED })
do
	local props = table.clone(IMAGE_PROPS)
	for k, v in BUTTON_PROPS do
		props[k] = v
	end
	props.HoverImage = ""
	props.PressedImage = ""
	class("ImageButton", "GuiButton", props, { Computed = IMAGE_COMPUTED, Events = BUTTON_EVENTS })
end

class("ScrollingFrame", "GuiObject", {
	AutomaticCanvasSize = E.AutomaticSize.None,
	BottomImage = "rbxasset://textures/ui/Scroll/scroll-bottom.png",
	CanvasPosition = Vector2.zero,
	CanvasSize = UDim2.new(0, 0, 2, 0),
	ElasticBehavior = E.ElasticBehavior.WhenScrollable,
	HorizontalScrollBarInset = E.ScrollBarInset.None,
	MidImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
	ScrollBarImageColor3 = BLACK,
	ScrollBarImageTransparency = 0,
	ScrollBarThickness = 12,
	ScrollingDirection = E.ScrollingDirection.XY,
	ScrollingEnabled = true,
	TopImage = "rbxasset://textures/ui/Scroll/scroll-top.png",
	VerticalScrollBarInset = E.ScrollBarInset.None,
	VerticalScrollBarPosition = E.VerticalScrollBarPosition.Right,
}, {
	Computed = {
		AbsoluteCanvasSize = function(self)
			return M.Layout.CanvasInfo(self).Canvas
		end,
		AbsoluteWindowSize = function(self)
			return M.Layout.CanvasInfo(self).Window
		end,
	},
})

class("ViewportFrame", "GuiObject", {
	Ambient = Color3.fromRGB(200, 200, 200),
	CurrentCamera = NIL,
	ImageColor3 = WHITE,
	ImageTransparency = 0,
	LightColor = Color3.fromRGB(140, 140, 140),
	LightDirection = Vector3.new(-1, -1, -1),
})
class("VideoFrame", "GuiObject", { Video = "", Looped = false, Playing = false, Volume = 1, TimePosition = 0 })

class("LayerCollector", "GuiBase2d", { Enabled = true, ResetOnSpawn = true, ZIndexBehavior = E.ZIndexBehavior.Sibling }, { Abstract = true })
class("ScreenGui", "LayerCollector", {
	ClipToDeviceSafeArea = true,
	DisplayOrder = 0,
	IgnoreGuiInset = false,
	SafeAreaCompatibility = E.SafeAreaCompatibility.FullscreenExtension,
	ScreenInsets = E.ScreenInsets.CoreUISafeInsets,
})
-- In-world guis are not drawn by the preview; they take any property
class("BillboardGui", "PermissiveInstance", { Enabled = true, Size = UDim2.new(), AlwaysOnTop = false })
class("SurfaceGui", "PermissiveInstance", { Enabled = true })

---------------------------------------------------------------------------------------------------- UI components
class("UIBase", "Instance", {}, { Abstract = true })
class("UIComponent", "UIBase", {}, { Abstract = true })
class("UICorner", "UIComponent", { CornerRadius = UDim.new(0, 8) })
class("UIStroke", "UIComponent", {
	ApplyStrokeMode = E.ApplyStrokeMode.Contextual,
	BorderOffset = UDim.new(0, 0),
	BorderStrokePosition = E.BorderStrokePosition.Outer,
	Color = BLACK,
	Enabled = true,
	LineJoinMode = E.LineJoinMode.Round,
	StrokeSizingMode = E.StrokeSizingMode.FixedSize,
	Thickness = 1,
	Transparency = 0,
	ZIndex = 1,
})
class("UIGradient", "UIComponent", {
	Color = ColorSequence.new(WHITE),
	Enabled = true,
	Offset = Vector2.zero,
	Rotation = 0,
	Transparency = NumberSequence.new(0),
})
class("UIPadding", "UIComponent", { PaddingBottom = UDim.new(), PaddingLeft = UDim.new(), PaddingRight = UDim.new(), PaddingTop = UDim.new() })
class("UIScale", "UIComponent", { Scale = 1 })
class("UIConstraint", "UIComponent", {}, { Abstract = true })
class("UIAspectRatioConstraint", "UIConstraint", { AspectRatio = 1, AspectType = E.AspectType.FitWithinMaxSize, DominantAxis = E.DominantAxis.Width })
class("UISizeConstraint", "UIConstraint", { MaxSize = Vector2.new(math.huge, math.huge), MinSize = Vector2.zero })
class("UITextSizeConstraint", "UIConstraint", { MaxTextSize = 100, MinTextSize = 1 })
class("UIFlexItem", "UIComponent", { FlexMode = E.UIFlexMode.None, GrowRatio = 1, ShrinkRatio = 1, ItemLineAlignment = E.ItemLineAlignment.Automatic })
class("UILayout", "UIComponent", {}, { Abstract = true })
class("UIGridStyleLayout", "UILayout", {
	FillDirection = E.FillDirection.Horizontal,
	HorizontalAlignment = E.HorizontalAlignment.Left,
	SortOrder = E.SortOrder.LayoutOrder,
	VerticalAlignment = E.VerticalAlignment.Top,
}, {
	Abstract = true,
	Computed = {
		AbsoluteContentSize = function(self)
			return M.Layout.ContentSize(self)
		end,
	},
	Methods = {
		ApplyLayout = function() end,
	},
})
class("UIListLayout", "UIGridStyleLayout", {
	FillDirection = E.FillDirection.Vertical,
	HorizontalFlex = E.UIFlexAlignment.None,
	ItemLineAlignment = E.ItemLineAlignment.Automatic,
	Padding = UDim.new(0, 0),
	VerticalFlex = E.UIFlexAlignment.None,
	Wraps = false,
})
class("UIGridLayout", "UIGridStyleLayout", {
	CellPadding = UDim2.fromOffset(5, 5),
	CellSize = UDim2.fromOffset(100, 100),
	FillDirectionMaxCells = 0,
	StartCorner = E.StartCorner.TopLeft,
})
class("UIPageLayout", "UIGridStyleLayout", {
	Animated = true,
	Circular = false,
	EasingDirection = E.EasingDirection.Out,
	EasingStyle = E.EasingStyle.Back,
	GamepadInputEnabled = true,
	Padding = UDim.new(0, 0),
	ScrollWheelInputEnabled = true,
	TouchInputEnabled = true,
	TweenTime = 1,
}, {
	Computed = {
		CurrentPage = function(self)
			return M.Layout.CurrentPage(self)
		end,
	},
	Methods = {
		JumpTo = function(self, page)
			rawset(self, "__page", page)
			M.MarkLayoutDirty()
		end,
		JumpToIndex = function(self, index)
			rawset(self, "__pageIndex", index)
			M.MarkLayoutDirty()
		end,
		Next = function() end,
		Previous = function() end,
	},
	Events = { "PageEnter", "PageLeave", "Stopped" },
})
class("UITableLayout", "UIGridStyleLayout", { FillEmptySpaceColumns = false, FillEmptySpaceRows = false, MajorAxis = E.TableMajorAxis.RowMajor, Padding = UDim2.new() })
class("UIDragDetector", "PermissiveInstance", {})

---------------------------------------------------------------------------------------------------- permissive world-side classes
local function permissive(name, props, opts)
	opts = opts or {}
	class(name, opts.Super or "PermissiveInstance", props or {}, opts)
end

permissive("Folder")
permissive("Configuration")
permissive("ModuleScript", { Source = "" })
permissive("LocalScript", { Source = "", Enabled = true, Disabled = false })
permissive("Script", { Source = "", Enabled = true, Disabled = false })
for _, valueClass in { { "StringValue", "" }, { "NumberValue", 0 }, { "IntValue", 0 }, { "BoolValue", false } } do
	permissive(valueClass[1], { Value = valueClass[2] }, { Events = { "Changed" } })
end
permissive("ObjectValue", {})
permissive("Color3Value", { Value = BLACK })
permissive("Vector3Value", { Value = Vector3.zero })
permissive("CFrameValue", { Value = CFrame.identity })

permissive("RemoteEvent", {}, {
	Events = { "OnClientEvent", "OnServerEvent" },
	Methods = {
		FireServer = function(self, ...)
			M.Server.Event(self.Name, ...)
		end,
		FireClient = function()
			M.Fail("FireClient can only be called from the server", 2)
		end,
		FireAllClients = function()
			M.Fail("FireAllClients can only be called from the server", 2)
		end,
	},
})
permissive("UnreliableRemoteEvent", {}, {
	Events = { "OnClientEvent", "OnServerEvent" },
	Methods = {
		FireServer = function(self, ...)
			M.Server.Event(self.Name, ...)
		end,
	},
})
permissive("RemoteFunction", {}, {
	Methods = {
		InvokeServer = function(self, ...)
			return M.Server.Invoke(self.Name, ...)
		end,
		InvokeClient = function()
			M.Fail("InvokeClient can only be called from the server", 2)
		end,
	},
})
permissive("BindableEvent", {}, {
	Events = { "Event" },
	Methods = {
		Fire = function(self, ...)
			M.Fire(M.GetSignal(self, "Event"), ...)
		end,
	},
})
permissive("BindableFunction", {}, {
	Methods = {
		Invoke = function(self, ...)
			local fn = rawget(self, "__props").OnInvoke
			if type(fn) == "function" then
				return fn(...)
			end
			return nil
		end,
	},
})

local function soundMethod(playing)
	return function(self)
		rawget(self, "__props").Playing = playing
		rawget(self, "__props").IsPlaying = playing
	end
end
permissive("Sound", { SoundId = "", Volume = 0.5, PlaybackSpeed = 1, Looped = false, Playing = false, IsPlaying = false, IsLoaded = true, TimePosition = 0, TimeLength = 1 }, {
	Events = { "Ended", "Loaded", "Played", "Paused", "Resumed", "Stopped", "DidLoop" },
	Methods = { Play = soundMethod(true), Stop = soundMethod(false), Pause = soundMethod(false), Resume = soundMethod(true) },
})
permissive("SoundGroup", { Volume = 0.5 })
for _, effect in { "EqualizerSoundEffect", "ReverbSoundEffect", "PitchShiftSoundEffect", "ChorusSoundEffect", "DistortionSoundEffect", "EchoSoundEffect", "FlangeSoundEffect", "TremoloSoundEffect", "CompressorSoundEffect" } do
	permissive(effect, { Enabled = true })
end

-- Models and parts: enough for the pet / egg viewports and world bits the UI code touches
local function pivotOf(self)
	local props = rawget(self, "__props")
	return props.WorldPivot or props.CFrame or CFrame.identity
end
local function setPivot(self, value)
	local props = rawget(self, "__props")
	if isA(rawget(self, "__class"), "BasePart") then
		props.CFrame = value
		props.Position = value.Position
	else
		props.WorldPivot = value
	end
end
local PV_METHODS = {
	GetPivot = function(self)
		return pivotOf(self)
	end,
	PivotTo = function(self, value)
		setPivot(self, value)
	end,
}
permissive("PVInstance", {}, { Abstract = true, Methods = PV_METHODS })
permissive("Model", { PrimaryPart = nil, WorldPivot = CFrame.identity }, {
	Super = "PVInstance",
	Methods = {
		GetPivot = PV_METHODS.GetPivot,
		PivotTo = PV_METHODS.PivotTo,
		GetBoundingBox = function(self)
			local size = rawget(self, "__attrs").PreviewSize or Vector3.new(4, 4, 4)
			return pivotOf(self), size
		end,
		GetExtentsSize = function(self)
			return rawget(self, "__attrs").PreviewSize or Vector3.new(4, 4, 4)
		end,
		GetScale = function(self)
			return rawget(self, "__props").Scale or 1
		end,
		ScaleTo = function(self, scale)
			rawget(self, "__props").Scale = scale
		end,
		MoveTo = function(self, position)
			setPivot(self, CFrame.new(position))
		end,
		TranslateBy = function(self, offset)
			setPivot(self, pivotOf(self) + offset)
		end,
		SetPrimaryPartCFrame = function(self, value)
			setPivot(self, value)
		end,
		GetPrimaryPartCFrame = function(self)
			return pivotOf(self)
		end,
		BreakJoints = function() end,
		MakeJoints = function() end,
	},
})
permissive("Actor", {}, { Super = "Model" })
permissive("Tool", { CanBeDropped = true, RequiresHandle = true, Enabled = true }, { Super = "Model", Events = { "Activated", "Deactivated", "Equipped", "Unequipped" } })
permissive("WorldModel", {}, { Super = "Model" })

local PART_PROPS = {
	Anchored = false, CanCollide = true, CanQuery = true, CanTouch = true, CastShadow = true, Massless = false,
	Transparency = 0, Reflectance = 0, Color = GREY, Material = E.Material.Plastic, Size = Vector3.new(4, 1, 2),
	CFrame = CFrame.identity, Position = Vector3.zero, Orientation = Vector3.zero, Locked = false,
}
permissive("BasePart", PART_PROPS, {
	Super = "PVInstance",
	Abstract = true,
	Events = { "Touched", "TouchEnded" },
	Methods = {
		GetPivot = PV_METHODS.GetPivot,
		PivotTo = PV_METHODS.PivotTo,
		GetMass = function()
			return 1
		end,
		GetTouchingParts = function()
			return {}
		end,
		GetConnectedParts = function()
			return {}
		end,
		ApplyImpulse = function() end,
		ApplyAngularImpulse = function() end,
		SetNetworkOwner = function() end,
		BreakJoints = function() end,
	},
})
for _, partClass in { "Part", "MeshPart", "WedgePart", "CornerWedgePart", "TrussPart", "UnionOperation", "SpawnLocation", "Seat", "VehicleSeat" } do
	permissive(partClass, { Shape = E.PartType.Block, MeshId = "", TextureID = "" }, { Super = "BasePart" })
end
permissive("Terrain", {}, { Super = "BasePart", Methods = { FillBlock = function() end, FillBall = function() end, Clear = function() end } })

local function noop() end
permissive("Humanoid", { Health = 100, MaxHealth = 100, WalkSpeed = 16, JumpPower = 50, JumpHeight = 7.2, DisplayName = "", RootPart = nil }, {
	Events = { "Died", "Running", "StateChanged", "HealthChanged", "MoveToFinished", "Jumping" },
	Methods = {
		EquipTool = noop,
		UnequipTools = noop,
		MoveTo = noop,
		ChangeState = noop,
		TakeDamage = noop,
		GetState = function()
			return Enum.HumanoidStateType.Running
		end,
		LoadAnimation = function()
			return M.Stub("AnimationTrack")
		end,
		GetPlayingAnimationTracks = function()
			return {}
		end,
	},
})
permissive("Animator", {}, {
	Methods = {
		LoadAnimation = function()
			return M.Stub("AnimationTrack")
		end,
		GetPlayingAnimationTracks = function()
			return {}
		end,
	},
})
permissive("Camera", { CFrame = CFrame.new(0, 10, 20), Focus = CFrame.identity, FieldOfView = 70, CameraType = E.CameraType.Custom, CameraSubject = nil }, {
	Super = "PVInstance",
	Methods = {
		WorldToViewportPoint = function()
			return Vector3.new(-1000, -1000, -1), false
		end,
		WorldToScreenPoint = function()
			return Vector3.new(-1000, -1000, -1), false
		end,
		ViewportPointToRay = function()
			return { Origin = Vector3.zero, Direction = Vector3.new(0, 0, -1) }
		end,
		ScreenPointToRay = function()
			return { Origin = Vector3.zero, Direction = Vector3.new(0, 0, -1) }
		end,
		GetPartsObscuringTarget = function()
			return {}
		end,
	},
	Computed = {
		ViewportSize = function()
			return Vector2.new(M.Screen.W, M.Screen.H)
		end,
	},
})
for _, plain in {
	"Attachment", "Beam", "Trail", "ParticleEmitter", "PointLight", "SpotLight", "SurfaceLight", "Fire", "Smoke", "Sparkles",
	"SpecialMesh", "BlockMesh", "Decal", "Texture", "Highlight", "SelectionBox", "BoxHandleAdornment", "WeldConstraint", "Weld",
	"Motor6D", "AlignPosition", "AlignOrientation", "LinearVelocity", "AngularVelocity", "VectorForce", "BodyVelocity",
	"BodyPosition", "BodyGyro", "ProximityPrompt", "ClickDetector", "Animation", "Explosion", "ForceField",
	"ColorCorrectionEffect", "BlurEffect", "BloomEffect", "SunRaysEffect", "DepthOfFieldEffect", "Atmosphere", "Sky", "Clouds",
	"Shirt", "Pants", "ShirtGraphic", "Accessory", "BodyColors", "HumanoidDescription", "PlayerScripts", "StarterGear",
	"Backpack", "PlayerGui", "TextChannel", "TextSource", "ChatInputBarConfiguration", "BubbleChatConfiguration",
	"ChannelTabsConfiguration", "Dialog", "PathfindingModifier", "Team", "Light",
} do
	permissive(plain)
end
permissive("ParticleEmitterStub", {}, { Abstract = true })
for name, def in {
	ParticleEmitter = { Methods = { Emit = noop, Clear = noop } },
	PlayerGui = {
		Methods = {
			GetGuiObjectsAtPosition = function(_, x, y)
				return M.Layout.HitTest(x, y)
			end,
			SetTopbarTransparency = noop,
			GetTopbarTransparency = function()
				return 0.5
			end,
		},
	},
} do
	CLASSES[name].Methods = def.Methods
end
permissive("ChatWindowConfiguration", { Enabled = true, HeightScale = 1, WidthScale = 1, BackgroundColor3 = BLACK, BackgroundTransparency = 0.3 }, {
	Computed = {
		AbsolutePosition = function()
			local chat = M.Screen.Chat
			return Vector2.new(chat[1], chat[2] - M.Screen.InsetTop)
		end,
		AbsoluteSize = function()
			local chat = M.Screen.Chat
			return Vector2.new(chat[3], chat[4])
		end,
	},
})

---------------------------------------------------------------------------------------------------- instances
local Instance = {}
local IM = { __kind = "Instance" }
M.InstanceMeta = IM
M.Instance = Instance
local nextId = 0

local function fullName(object)
	local parts = {}
	local current = object
	while current and current ~= M.game do
		table.insert(parts, 1, rawget(current, "__props").Name)
		current = rawget(current, "__parent")
	end
	return table.concat(parts, ".")
end
M.FullName = fullName

local function describe(object)
	return fmt("%s \"%s\"", rawget(object, "__class"), fullName(object))
end
M.Describe = describe

local function isInstance(value)
	return type(value) == "table" and getmetatable(value) == IM
end
M.IsInstance = isInstance

local function newObject(className)
	local def = info(className)
	nextId += 1
	local props = {}
	for key, default in def.Props do
		if default ~= NIL then
			props[key] = default
		end
	end
	props.Name = className
	local object = setmetatable({
		__class = className,
		__props = props,
		__children = {},
		__parent = nil,
		__attrs = {},
		__signals = {},
		__propSignals = {},
		__attrSignals = {},
		__tags = {},
		__id = nextId,
	}, IM)
	return object
end
M.NewObject = newObject

function Instance.new(className, parent)
	if type(className) ~= "string" then
		M.Fail("Instance.new expects a class name", 2)
	end
	local def = CLASSES[className]
	if not def then
		-- Unknown class: a permissive stand-in, so world-side code keeps going (noted in the report)
		M.Note("Instance.new(\"" .. className .. "\") is a permissive stand-in in the preview")
		permissive(className)
		def = CLASSES[className]
	end
	if def.Abstract or def.Service then
		M.Fail(fmt("Unable to create an Instance of type \"%s\"", className), 2)
	end
	local object = newObject(className)
	if parent ~= nil then
		object.Parent = parent
	end
	return object
end
function Instance.fromExisting(object)
	return object:Clone()
end

function M.GetSignal(object, name)
	local signals = rawget(object, "__signals")
	local signal = signals[name]
	if not signal then
		signal = M.NewSignal(name)
		signals[name] = signal
	end
	return signal
end

local function fireIfAny(object, name, ...)
	local signal = rawget(object, "__signals")[name]
	if signal then
		M.Fire(signal, ...)
	end
end

-- Layout-relevant properties: changing them marks the layout dirty
local LAYOUT_KEYS = {
	Size = true, Position = true, AnchorPoint = true, Visible = true, AutomaticSize = true, SizeConstraint = true,
	LayoutOrder = true, Name = true, Text = true, TextSize = true, Font = true, FontFace = true, TextWrapped = true,
	TextScaled = true, LineHeight = true, RichText = true, CanvasSize = true, CanvasPosition = true,
	AutomaticCanvasSize = true, ScrollBarThickness = true, VerticalScrollBarInset = true, ScreenInsets = true,
	IgnoreGuiInset = true, Enabled = true, ZIndex = true, Rotation = true, BorderSizePixel = true,
}
M.LayoutKeys = LAYOUT_KEYS

local function changed(object, key, value)
	local props = rawget(object, "__props")
	if props[key] == value then
		return
	end
	props[key] = value
	local className = rawget(object, "__class")
	-- only layout inputs dirty the layout (strokes, gradients and colours animate every frame)
	if M.MarkLayoutDirty and ((M.LayoutComponents and M.LayoutComponents[className]) or (LAYOUT_KEYS[key] and isA(className, "GuiBase2d"))) then
		M.MarkLayoutDirty()
	end
	local signal = rawget(object, "__propSignals")[key]
	if signal then
		M.Fire(signal)
	end
	fireIfAny(object, "Changed", key)
end

local INT_KEYS = { ZIndex = true, LayoutOrder = true, BorderSizePixel = true, DisplayOrder = true, ScrollBarThickness = true, MaxTextSize = true, MinTextSize = true, FillDirectionMaxCells = true, MaxVisibleGraphemes = true }

local function coerce(object, key, default, value)
	local want = kindOf(default)
	local got = kindOf(value)
	if default == NIL then
		if value == nil or isInstance(value) then
			return value
		end
		M.Fail(fmt("Unable to assign property %s. Object expected, got %s", key, got), 4)
	elseif want == "EnumItem" then
		local enumName = M.EnumTypeOf(default)
		local item = M.CoerceEnum(enumName, value)
		if item == nil then
			M.Fail(fmt("Unable to assign property %s. Enum.%s expected, got %s", key, enumName, if got == "EnumItem" then tostring(value) else got), 4)
		end
		return item
	elseif want == "number" then
		local n = tonumber(value)
		if n == nil or type(value) == "boolean" then
			M.Fail(fmt("Unable to assign property %s. number expected, got %s", key, got), 4)
		end
		if INT_KEYS[key] then
			n = if n >= 0 then math.floor(n) else -math.floor(-n)
		end
		return n
	elseif want == "string" then
		if type(value) == "number" then
			return tostring(value)
		elseif type(value) ~= "string" then
			M.Fail(fmt("Unable to assign property %s. string expected, got %s", key, got), 4)
		end
		return value
	elseif want ~= got then
		M.Fail(fmt("Unable to assign property %s. %s expected, got %s", key, want, got), 4)
	end
	return value
end

local function setParent(object, parent)
	if rawget(object, "__parentLocked") then
		M.Fail(fmt("The Parent property of %s is locked, current parent: NULL, new parent %s", rawget(object, "__props").Name, if parent then rawget(parent, "__props").Name else "NULL"), 3)
	end
	if parent ~= nil and not isInstance(parent) then
		M.Fail("Unable to assign property Parent. Instance expected, got " .. kindOf(parent), 3)
	end
	local old = rawget(object, "__parent")
	if old == parent then
		return
	end
	local current = parent
	while current do
		if current == object then
			M.Fail(fmt("Attempt to set %s as its own parent", describe(object)), 3)
		end
		current = rawget(current, "__parent")
	end
	if old then
		local list = rawget(old, "__children")
		local index = table.find(list, object)
		if index then
			table.remove(list, index)
		end
		local ancestor = old
		while ancestor do
			fireIfAny(ancestor, "DescendantRemoving", object)
			ancestor = rawget(ancestor, "__parent")
		end
		fireIfAny(old, "ChildRemoved", object)
	end
	rawset(object, "__parent", parent)
	if parent then
		table.insert(rawget(parent, "__children"), object)
	end
	if M.MarkLayoutDirty then
		M.MarkLayoutDirty()
	end
	if parent then
		fireIfAny(parent, "ChildAdded", object)
		local ancestor = parent
		while ancestor do
			if rawget(ancestor, "__signals").DescendantAdded then
				fireIfAny(ancestor, "DescendantAdded", object)
				for _, descendant in object:GetDescendants() do
					fireIfAny(ancestor, "DescendantAdded", descendant)
				end
			end
			ancestor = rawget(ancestor, "__parent")
		end
	end
	fireIfAny(object, "AncestryChanged", object, parent)
	local propSignal = rawget(object, "__propSignals").Parent
	if propSignal then
		M.Fire(propSignal)
	end
	fireIfAny(object, "Changed", "Parent")
end
M.SetParent = setParent

local methods = {}
M.InstanceMethods = methods

IM.__index = function(self, key)
	local className = rawget(self, "__class")
	local def = info(className)
	local method = def.Methods[key] or methods[key]
	if method then
		return method
	end
	if key == "Parent" then
		return rawget(self, "__parent")
	elseif key == "ClassName" then
		return className
	end
	local computed = def.Computed[key]
	if computed then
		return computed(self)
	end
	local props = rawget(self, "__props")
	local value = props[key]
	if value ~= nil then
		return value
	end
	if def.Props[key] ~= nil then
		return nil -- an object property that is nil
	end
	if def.Events[key] then
		return M.GetSignal(self, key)
	end
	for _, child in rawget(self, "__children") do
		if rawget(child, "__props").Name == key then
			return child
		end
	end
	if def.Permissive then
		return nil
	end
	M.Fail(fmt("%s is not a valid member of %s", tostring(key), describe(self)), 2)
end

IM.__newindex = function(self, key, value)
	if key == "Parent" then
		setParent(self, value)
		return
	end
	local className = rawget(self, "__class")
	local def = info(className)
	if key == "Transparency" and def.Props.BackgroundTransparency ~= nil then
		key = "BackgroundTransparency"
	end
	if key == "TextWrap" and def.Props.TextWrapped ~= nil then
		key = "TextWrapped"
	end
	local default = def.Props[key]
	if default == nil then
		if def.Computed[key] or key == "ClassName" then
			M.Fail(fmt("Unable to assign property %s. Property is read only", key), 2)
		end
		if def.Permissive then
			changed(self, key, value)
			return
		end
		M.Fail(fmt("%s is not a valid member of %s", tostring(key), describe(self)), 2)
	end
	value = coerce(self, key, default, value)
	if key == "Font" then
		changed(self, "FontFace", M.Font.fromEnum(value))
	elseif key == "FontFace" then
		rawget(self, "__props").Font = M.EnumFromFont(value)
	end
	changed(self, key, value)
end

IM.__tostring = function(self)
	return rawget(self, "__props").Name
end

---------------------------------------------------------------------------------------------------- Instance methods
local function checkSelf(self, name)
	if not isInstance(self) then
		M.Fail(fmt("Expected ':' not '.' calling member function %s", name), 3)
	end
end

function methods.IsA(self, className)
	checkSelf(self, "IsA")
	return isA(rawget(self, "__class"), className)
end
function methods.GetChildren(self)
	checkSelf(self, "GetChildren")
	return table.clone(rawget(self, "__children"))
end
function methods.GetDescendants(self)
	checkSelf(self, "GetDescendants")
	local out = {}
	local function walk(object)
		for _, child in rawget(object, "__children") do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end
function methods.FindFirstChild(self, name, recursive)
	checkSelf(self, "FindFirstChild")
	for _, child in rawget(self, "__children") do
		if rawget(child, "__props").Name == name then
			return child
		end
	end
	if recursive then
		for _, child in rawget(self, "__children") do
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
	for _, child in rawget(self, "__children") do
		if rawget(child, "__class") == className then
			return child
		end
	end
	return nil
end
function methods.FindFirstChildWhichIsA(self, className, recursive)
	checkSelf(self, "FindFirstChildWhichIsA")
	for _, child in rawget(self, "__children") do
		if isA(rawget(child, "__class"), className) then
			return child
		end
	end
	if recursive then
		for _, child in rawget(self, "__children") do
			local found = methods.FindFirstChildWhichIsA(child, className, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function methods.FindFirstAncestor(self, name)
	local current = rawget(self, "__parent")
	while current do
		if rawget(current, "__props").Name == name then
			return current
		end
		current = rawget(current, "__parent")
	end
	return nil
end
function methods.FindFirstAncestorOfClass(self, className)
	local current = rawget(self, "__parent")
	while current do
		if rawget(current, "__class") == className then
			return current
		end
		current = rawget(current, "__parent")
	end
	return nil
end
function methods.FindFirstAncestorWhichIsA(self, className)
	local current = rawget(self, "__parent")
	while current do
		if isA(rawget(current, "__class"), className) then
			return current
		end
		current = rawget(current, "__parent")
	end
	return nil
end
function methods.WaitForChild(self, name, timeout)
	checkSelf(self, "WaitForChild")
	local child = methods.FindFirstChild(self, name)
	if child then
		return child
	end
	local thread, isMain = coroutine.running()
	if isMain or not coroutine.isyieldable() then
		M.Gap(fmt("WaitForChild(\"%s\") on %s outside a task", name, describe(self)), 2)
	end
	local found = nil
	local done = false
	local signal = M.GetSignal(self, "ChildAdded")
	local conn
	conn = signal:Connect(function(added)
		if not done and rawget(added, "__props").Name == name then
			done = true
			found = added
			conn:Disconnect()
			M.Resume(thread)
		end
	end)
	local limit = timeout or 5
	M.task.delay(limit, function()
		if not done then
			if timeout then
				done = true
				conn:Disconnect()
				M.Resume(thread)
			else
				table.insert(M.Warnings, fmt("Infinite yield possible on '%s:WaitForChild(\"%s\")' (%s)", fullName(self), name, M.Where(2) or "?"))
			end
		end
	end)
	coroutine.yield()
	return found
end
function methods.IsDescendantOf(self, ancestor)
	local current = rawget(self, "__parent")
	while current do
		if current == ancestor then
			return true
		end
		current = rawget(current, "__parent")
	end
	return false
end
function methods.IsAncestorOf(self, descendant)
	return methods.IsDescendantOf(descendant, self)
end
function methods.GetFullName(self)
	return fullName(self)
end
function methods.GetDebugId(self)
	return tostring(rawget(self, "__id"))
end

local ATTRIBUTE_KINDS = {
	["nil"] = true, boolean = true, number = true, string = true, UDim = true, UDim2 = true, BrickColor = true, Color3 = true,
	Vector2 = true, Vector3 = true, CFrame = true, NumberSequence = true, ColorSequence = true, NumberRange = true, Rect = true,
	Font = true, EnumItem = true,
}
function methods.SetAttribute(self, name, value)
	checkSelf(self, "SetAttribute")
	if not ATTRIBUTE_KINDS[kindOf(value)] then
		M.Fail(fmt("%s is not a supported attribute type", kindOf(value)), 2)
	end
	local attrs = rawget(self, "__attrs")
	if attrs[name] == value then
		return
	end
	attrs[name] = value
	local signal = rawget(self, "__attrSignals")[name]
	if signal then
		M.Fire(signal)
	end
	fireIfAny(self, "AttributeChanged", name)
end
function methods.GetAttribute(self, name)
	checkSelf(self, "GetAttribute")
	return rawget(self, "__attrs")[name]
end
function methods.GetAttributes(self)
	return table.clone(rawget(self, "__attrs"))
end
function methods.GetAttributeChangedSignal(self, name)
	local signals = rawget(self, "__attrSignals")
	if not signals[name] then
		signals[name] = M.NewSignal("AttributeChanged:" .. name)
	end
	return signals[name]
end
function methods.GetPropertyChangedSignal(self, name)
	checkSelf(self, "GetPropertyChangedSignal")
	local def = info(rawget(self, "__class"))
	if def.Props[name] == nil and not def.Computed[name] and name ~= "Parent" and name ~= "Name" and not def.Permissive then
		M.Fail(fmt("%s is not a valid property name.", tostring(name)), 2)
	end
	local signals = rawget(self, "__propSignals")
	if not signals[name] then
		local onConnect = nil
		if def.Computed[name] and M.WatchComputed then
			onConnect = function()
				M.WatchComputed(self)
			end
		end
		signals[name] = M.NewSignal("PropertyChanged:" .. name, onConnect)
	end
	return signals[name]
end
function methods.ClearAllChildren(self)
	for _, child in table.clone(rawget(self, "__children")) do
		methods.Destroy(child)
	end
end
function methods.Destroy(self)
	checkSelf(self, "Destroy")
	if rawget(self, "__destroyed") then
		return
	end
	rawset(self, "__destroyed", true)
	fireIfAny(self, "Destroying")
	for _, child in table.clone(rawget(self, "__children")) do
		methods.Destroy(child)
	end
	if rawget(self, "__parent") then
		setParent(self, nil)
	end
	rawset(self, "__parentLocked", true)
	for _, signal in rawget(self, "__signals") do
		M.DisconnectAll(signal)
	end
	for _, signal in rawget(self, "__propSignals") do
		M.DisconnectAll(signal)
	end
	for _, signal in rawget(self, "__attrSignals") do
		M.DisconnectAll(signal)
	end
end
methods.Remove = function(self)
	setParent(self, nil)
end
function methods.AddTag(self, tag)
	rawget(self, "__tags")[tag] = true
end
function methods.RemoveTag(self, tag)
	rawget(self, "__tags")[tag] = nil
end
function methods.HasTag(self, tag)
	return rawget(self, "__tags")[tag] == true
end
function methods.GetTags(self)
	local list = {}
	for tag in rawget(self, "__tags") do
		table.insert(list, tag)
	end
	return list
end
function methods.GetActor()
	return nil
end
function methods.GetStyled(self, name)
	return self[name]
end

local function cloneTree(object)
	if not rawget(object, "__props").Archivable then
		return nil
	end
	local copy = newObject(rawget(object, "__class"))
	for k, v in rawget(object, "__props") do
		rawget(copy, "__props")[k] = v
	end
	for k, v in rawget(object, "__attrs") do
		rawget(copy, "__attrs")[k] = v
	end
	for k in rawget(object, "__tags") do
		rawget(copy, "__tags")[k] = true
	end
	rawset(copy, "__loader", rawget(object, "__loader"))
	rawset(copy, "__chunk", rawget(object, "__chunk"))
	for _, child in rawget(object, "__children") do
		local childCopy = cloneTree(child)
		if childCopy then
			rawset(childCopy, "__parent", copy)
			table.insert(rawget(copy, "__children"), childCopy)
		end
	end
	return copy
end
function methods.Clone(self)
	checkSelf(self, "Clone")
	return cloneTree(self)
end

---------------------------------------------------------------------------------------------------- stubs
-- A stand-in object: any field is a function that does nothing and returns nil (noted in the report)
function M.Stub(name, overrides)
	local stub = overrides or {}
	return setmetatable(stub, {
		__index = function(t, key)
			if type(key) ~= "string" then
				return nil
			end
			local fn = function()
				M.Note("stub: " .. name .. "." .. key .. "()")
				return nil
			end
			rawset(t, key, fn)
			return fn
		end,
	})
end
