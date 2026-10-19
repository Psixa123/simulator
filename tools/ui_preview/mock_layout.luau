--!nocheck
-- UI preview mock, part 3 of 4: layout, text and the draw list.
--
-- Computes AbsolutePosition / AbsoluteSize the way Roblox does: UDim2 Size and Position against the
-- parent's content area (after UIPadding), AnchorPoint, SizeConstraint, UIAspectRatioConstraint,
-- UISizeConstraint, UIScale (scales the object around its anchor point, and every offset, stroke and
-- text size below it), AutomaticSize, UIListLayout / UIGridLayout / UIPageLayout, ScrollingFrame
-- canvases (AutomaticCanvasSize, CanvasPosition) and the Roblox top bar inset (ScreenInsets /
-- IgnoreGuiInset). AbsolutePosition is in GUI space like in Roblox: y = 0 is the bottom of the top bar,
-- so full-screen guis start at -InsetTop.
--
-- Text is measured with per-glyph advance widths that preview_ui.py measured in Chromium with the
-- fonts the page draws with (M.Metrics), so TextScaled, TextWrapped, TextBounds and AutomaticSize agree
-- with the picture. Lines are broken here and drawn as-is by page.js.
--
-- Layout is lazy: any change to a layout input marks it dirty, and the next read of a computed
-- property (or the end of the frame) lays out every ScreenGui in the PlayerGui again. At the end of
-- each frame, objects whose AbsoluteSize / AbsolutePosition / ... signals are connected get them fired
-- when the values changed.

local M = ...
local fmt = string.format
local isA = M.ClassIsA
local v2 = M.v2

local Layout = {}
M.Layout = Layout

M.Screen = M.Screen or { W = 1280, H = 720, InsetTop = 58, SafeLeft = 0, SafeRight = 0, SafeBottom = 0, Chat = { 8, 66, 400, 220 } }

-- UI components that change layout (others, like UIStroke and UIGradient, only change paint)
M.LayoutComponents = {
	UIScale = true, UIPadding = true, UIListLayout = true, UIGridLayout = true, UIPageLayout = true,
	UITableLayout = true, UIAspectRatioConstraint = true, UISizeConstraint = true, UITextSizeConstraint = true,
	UIFlexItem = true,
}

local dirty = true
local version = 0
local G = setmetatable({}, { __mode = "k" }) -- [GuiBase2d or layout] = geometry of the current layout
local textCache = setmetatable({}, { __mode = "k" }) -- [text object] = { Key, Result }

function M.MarkLayoutDirty()
	dirty = true
end

local function P(o)
	return rawget(o, "__props")
end
local function C(o)
	return rawget(o, "__class")
end
local function kids(o)
	return rawget(o, "__children")
end
local function isGuiObject(o)
	return isA(C(o), "GuiObject")
end

local function alignFrac(name)
	if name == "Center" then
		return 0.5
	elseif name == "Right" or name == "Bottom" then
		return 1
	end
	return 0
end

---------------------------------------------------------------------------------------------------- components
local function components(obj)
	local found = {}
	for _, child in kids(obj) do
		local cls = C(child)
		if cls == "UIScale" then
			found.Scale = found.Scale or child
		elseif cls == "UIPadding" then
			found.Padding = found.Padding or child
		elseif cls == "UIListLayout" or cls == "UIGridLayout" or cls == "UIPageLayout" or cls == "UITableLayout" then
			found.Layout = found.Layout or child
		elseif cls == "UIAspectRatioConstraint" then
			found.Aspect = found.Aspect or child
		elseif cls == "UISizeConstraint" then
			found.SizeLimit = found.SizeLimit or child
		elseif cls == "UITextSizeConstraint" then
			found.TextLimit = found.TextLimit or child
		elseif cls == "UICorner" then
			found.Corner = found.Corner or child
		elseif cls == "UIStroke" then
			if P(child).Enabled then
				local contextual = P(child).ApplyStrokeMode.Name == "Contextual"
				if contextual and found.TextStroke == nil then
					found.TextStroke = child
				elseif not contextual and found.BorderStroke == nil then
					found.BorderStroke = child
				end
			end
		elseif cls == "UIGradient" then
			if P(child).Enabled and found.Gradient == nil then
				found.Gradient = child
			end
		elseif cls == "UIFlexItem" then
			found.Flex = found.Flex or child
		end
	end
	return found
end
Layout.Components = components

local TEXT_CLASSES = { TextLabel = true, TextButton = true, TextBox = true }
local function isText(obj)
	return TEXT_CLASSES[C(obj)] == true
end

---------------------------------------------------------------------------------------------------- text: fonts and metrics
-- Roblox font family -> metrics key + CSS family drawn by page.js (Gotham is drawn with Montserrat, the
-- closest free face; families without a bundled font fall back to the browser's sans-serif)
local FAMILIES = {
	FredokaOne = { Key = "fredoka", Css = "Fredoka One", Weighted = false },
	LuckiestGuy = { Key = "luckiest", Css = "Luckiest Guy", Weighted = false },
	GothamSSm = { Key = "gotham", Css = "Gotham Preview", Weighted = true },
	Gotham = { Key = "gotham", Css = "Gotham Preview", Weighted = true },
	BuilderSans = { Key = "gotham", Css = "Gotham Preview", Weighted = true },
	Montserrat = { Key = "gotham", Css = "Gotham Preview", Weighted = true },
}
local SANS = { Key = "sans", Css = "Sans Preview", Weighted = true }
local GOTHAM_WEIGHTS = { 400, 500, 600, 700, 800, 900 }
M.FontFamilies = FAMILIES

local function familyName(font)
	local family = rawget(font, "Family") or ""
	return string.match(family, "families/(.-)%.json") or string.match(family, "^([%w]+)$") or family
end

-- { Key (metrics), Css, Weight, Italic } for a Font datatype; overrides from rich text
local function fontInfo(font, overrides)
	local name = familyName(font)
	local weight = rawget(font, "Weight").Value
	local italic = rawget(font, "Style").Name == "Italic"
	if overrides then
		if overrides.Face then
			name = overrides.Face
		end
		if overrides.Weight then
			weight = overrides.Weight
		end
		if overrides.Bold then
			weight = math.max(weight, 700)
		end
		if overrides.Italic then
			italic = true
		end
	end
	local fam = FAMILIES[name] or SANS
	local key = fam.Key
	if not fam.Weighted then
		-- single-face families (Fredoka One, Luckiest Guy): Roblox has no bold or italic to switch to
		weight, italic = 400, false
	end
	if fam == SANS then
		key = if weight >= 600 then "sans700" else "sans400"
	elseif fam.Weighted then
		local best, bestDist = 400, math.huge
		for _, w in GOTHAM_WEIGHTS do
			if math.abs(w - weight) < bestDist then
				best, bestDist = w, math.abs(w - weight)
			end
		end
		key = key .. best
		weight = best
	end
	return { Key = key, Css = fam.Css, Weight = weight, Italic = italic, Family = name, Known = fam ~= SANS }
end
Layout.FontInfo = fontInfo

local function metricsTable(key)
	local metrics = M.Metrics
	if not metrics then
		return nil
	end
	return metrics.Fonts[key] or metrics.Fonts.sans400
end

local wordCache = {} -- [key] = { [string] = width at size 100 }
local function isZeroWidth(cp)
	return cp == 0xFE0F or cp == 0xFE0E or cp == 0x200B or cp == 0x20E3 or (cp >= 0x1F3FB and cp <= 0x1F3FF) or (cp >= 0xE0020 and cp <= 0xE007F)
end

-- Advance width of a string at size 100 (emoji, ZWJ sequences, flags and variation selectors included)
local function width100(str, key)
	local cache = wordCache[key]
	if not cache then
		cache = {}
		wordCache[key] = cache
	end
	local cached = cache[str]
	if cached then
		return cached
	end
	local widths = metricsTable(key)
	local emoji = (M.Metrics and M.Metrics.Emoji) or 118
	local avg = (M.Metrics and M.Metrics.Avg and M.Metrics.Avg[key]) or 55
	local cps = {}
	local ok = pcall(function()
		for _, cp in utf8.codes(str) do
			table.insert(cps, cp)
		end
	end)
	if not ok then
		cps = { string.byte(str, 1, -1) }
	end
	local total = 0
	local joined = false
	local i = 1
	while i <= #cps do
		local cp = cps[i]
		local nxt = cps[i + 1]
		if cp == 0x200D then
			joined = true
		elseif isZeroWidth(cp) then
			-- combines with the previous glyph
		elseif joined then
			joined = false
		elseif cp >= 0x1F000 or nxt == 0xFE0F then
			total += emoji
			if cp >= 0x1F1E6 and cp <= 0x1F1FF and nxt and nxt >= 0x1F1E6 and nxt <= 0x1F1FF then
				i += 1 -- a flag is one glyph
			end
		else
			total += (widths and widths[cp]) or (if cp < 32 then 0 else avg)
		end
		i += 1
	end
	cache[str] = total
	return total
end
Layout.Width100 = width100

---------------------------------------------------------------------------------------------------- text: rich text
local ENTITIES = { lt = "<", gt = ">", amp = "&", quot = "\"", apos = "'" }
local function decodeEntities(text)
	return (string.gsub(text, "&(%a+);", function(name)
		return ENTITIES[name]
	end))
end

local function parseColor(value)
	if not value then
		return nil
	end
	local hex = string.match(value, "^#(%x%x%x%x%x%x)$")
	if hex then
		return M.Color3.fromHex(hex)
	end
	local r, g, b = string.match(value, "rgb%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*%)")
	if r then
		return M.Color3.fromRGB(tonumber(r), tonumber(g), tonumber(b))
	end
	return nil
end

local WEIGHT_NAMES = { thin = 100, extralight = 200, light = 300, regular = 400, medium = 500, semibold = 600, bold = 700, extrabold = 800, heavy = 900 }

local function tagStyle(name, attrs)
	local style = {}
	if name == "b" then
		style.Bold = true
	elseif name == "i" then
		style.Italic = true
	elseif name == "u" then
		style.Underline = true
	elseif name == "s" then
		style.Strike = true
	elseif name == "uppercase" or name == "uc" then
		style.Upper = true
	elseif name == "smallcaps" or name == "sc" then
		style.SmallCaps = true
	elseif name == "font" then
		style.Color = parseColor(attrs.color)
		style.Size = tonumber(attrs.size)
		style.Transparency = tonumber(attrs.transparency)
		if attrs.face then
			style.Face = attrs.face
		elseif attrs.family then
			style.Face = string.match(attrs.family, "families/(.-)%.json") or attrs.family
		end
		if attrs.weight then
			style.Weight = tonumber(attrs.weight) or WEIGHT_NAMES[string.lower(attrs.weight)]
		end
	elseif name == "stroke" then
		style.StrokeColor = parseColor(attrs.color) or M.Color3.new(0, 0, 0)
		style.StrokeThickness = tonumber(attrs.thickness) or 1
		style.StrokeTransparency = tonumber(attrs.transparency) or 0
	elseif name == "mark" then
		style.Mark = parseColor(attrs.color) or M.Color3.fromRGB(255, 255, 0)
		style.MarkTransparency = tonumber(attrs.transparency) or 0
	else
		return nil
	end
	return style
end

-- Rich text -> { { Text, Style } }; unknown tags stay as text like in Roblox
local function parseRich(text)
	local segments = {}
	local stack = { {} }
	local function add(piece)
		if piece ~= "" then
			table.insert(segments, { Text = decodeEntities(piece), Style = stack[#stack] })
		end
	end
	local pos = 1
	local len = #text
	while pos <= len do
		local lt = string.find(text, "<", pos, true)
		if not lt then
			add(string.sub(text, pos))
			break
		end
		add(string.sub(text, pos, lt - 1))
		local gt = string.find(text, ">", lt, true)
		if not gt then
			add(string.sub(text, lt))
			break
		end
		local tag = string.sub(text, lt + 1, gt - 1)
		local closing = string.sub(tag, 1, 1) == "/"
		local name = string.lower(string.match(tag, "^/?%s*([%a]+)") or "")
		if name == "br" then
			add("\n")
		elseif string.sub(tag, 1, 3) == "!--" then
			-- comment
		elseif closing then
			if #stack > 1 then
				table.remove(stack)
			end
		else
			local attrs = {}
			for key, value in string.gmatch(tag, "(%a+)%s*=%s*[\"']([^\"']*)[\"']") do
				attrs[string.lower(key)] = value
			end
			local style = tagStyle(name, attrs)
			if style then
				local merged = table.clone(stack[#stack])
				for k, v in style do
					merged[k] = v
				end
				if string.sub(tag, -1) ~= "/" then
					table.insert(stack, merged)
				end
			else
				add("<" .. tag .. ">")
			end
		end
		pos = gt + 1
	end
	return segments
end
Layout.ParseRich = parseRich

function M.StripRichText(text, rich)
	if not rich then
		return text
	end
	local out = {}
	for _, segment in parseRich(text) do
		table.insert(out, segment.Text)
	end
	return table.concat(out)
end

---------------------------------------------------------------------------------------------------- text: line breaking
-- tokens: word groups (unbreakable runs of non-space text, possibly over several styled segments),
-- spaces and newlines
local function tokenize(segments, baseFont)
	local tokens = {}
	local group = nil
	local function flush()
		if group then
			table.insert(tokens, group)
			group = nil
		end
	end
	for _, segment in segments do
		local style = segment.Style
		local font = fontInfo(baseFont, style)
		local text = segment.Text
		if style.Upper or style.SmallCaps then
			text = string.upper(text)
		end
		text = string.gsub(text, "\r\n", "\n")
		text = string.gsub(text, "\t", "    ")
		local pos, len = 1, #text
		while pos <= len do
			local c = string.sub(text, pos, pos)
			if c == "\n" then
				flush()
				table.insert(tokens, { Kind = "nl" })
				pos += 1
			elseif c == " " then
				flush()
				local _, e = string.find(text, "^ +", pos)
				local piece = string.sub(text, pos, e)
				table.insert(tokens, { Kind = "space", Parts = { { Text = piece, Style = style, Font = font, W100 = width100(piece, font.Key) } } })
				pos = e + 1
			else
				local _, e = string.find(text, "^[^ \n]+", pos)
				local piece = string.sub(text, pos, e)
				group = group or { Kind = "word", Parts = {} }
				table.insert(group.Parts, { Text = piece, Style = style, Font = font, W100 = width100(piece, font.Key) })
				pos = e + 1
			end
		end
	end
	flush()
	return tokens
end

local function partSize(part, size)
	return part.Style.Size or size
end
local function partWidth(part, size)
	local w = part.W100 * partSize(part, size) / 100
	if part.Style.SmallCaps then
		w *= 0.82
	end
	return w
end
local function tokenWidth(token, size)
	local w = 0
	for _, part in token.Parts do
		w += partWidth(part, size)
	end
	return w
end

-- Splits a part into single characters (for words wider than the line)
local function charsOf(part)
	local out = {}
	for _, cp in utf8.codes(part.Text) do
		local ch = utf8.char(cp)
		if isZeroWidth(cp) and #out > 0 then
			out[#out].Text ..= ch
		else
			table.insert(out, { Text = ch, Style = part.Style, Font = part.Font })
		end
	end
	for _, piece in out do
		piece.W100 = width100(piece.Text, piece.Font.Key)
	end
	return out
end

-- Greedy line breaking at `size`; maxW = nil for no wrapping. Returns lines { Parts, W, Size }.
local function breakLines(tokens, size, maxW)
	local lines = {}
	local cur = { Parts = {}, W = 0 }
	local pending = nil
	local function push()
		table.insert(lines, cur)
		cur = { Parts = {}, W = 0 }
		pending = nil
	end
	local function append(part, w)
		table.insert(cur.Parts, part)
		cur.W += w
	end
	for _, token in tokens do
		if token.Kind == "nl" then
			push()
		elseif token.Kind == "space" then
			if #cur.Parts == 0 and #lines == 0 then
				for _, part in token.Parts do
					append(part, partWidth(part, size)) -- leading spaces of the text are kept
				end
			else
				pending = token
			end
		else
			local gw = tokenWidth(token, size)
			local sw = if pending then tokenWidth(pending, size) else 0
			if maxW and #cur.Parts > 0 and cur.W + sw + gw > maxW + 0.01 then
				push()
				sw = 0
			end
			if pending and #cur.Parts > 0 then
				for _, part in pending.Parts do
					append(part, partWidth(part, size))
				end
			end
			pending = nil
			if maxW and gw > maxW + 0.01 then
				-- a word wider than the line breaks between characters
				for _, part in token.Parts do
					for _, ch in charsOf(part) do
						local cw = partWidth(ch, size)
						if #cur.Parts > 0 and cur.W + cw > maxW + 0.01 then
							push()
						end
						append(ch, cw)
					end
				end
			else
				for _, part in token.Parts do
					append(part, partWidth(part, size))
				end
			end
		end
	end
	table.insert(lines, cur)
	local maxLine = 0
	for _, line in lines do
		local tallest = 0
		for _, part in line.Parts do
			tallest = math.max(tallest, partSize(part, size))
		end
		line.Size = if tallest > 0 then tallest else size
		maxLine = math.max(maxLine, line.W)
	end
	return lines, maxLine
end

local function blockHeight(lines, lineHeight)
	local h = 0
	for _, line in lines do
		h += line.Size * lineHeight
	end
	return h
end

-- Trims the last line that fits with "..." (TextTruncate.AtEnd)
local function truncate(lines, size, boxW, boxH, lineHeight)
	local kept = {}
	local h = 0
	for _, line in lines do
		if #kept > 0 and h + line.Size * lineHeight > boxH + 0.5 then
			break
		end
		h += line.Size * lineHeight
		table.insert(kept, line)
	end
	local last = kept[#kept]
	local truncated = #kept < #lines or (last and last.W > boxW + 0.5)
	if not truncated or not last then
		return kept, false
	end
	local style = (last.Parts[#last.Parts] or {}).Style or {}
	local font = (last.Parts[#last.Parts] or {}).Font
	local chars = {}
	for _, part in last.Parts do
		for _, ch in charsOf(part) do
			table.insert(chars, ch)
		end
	end
	local dots = font and { Text = "...", Style = style, Font = font, W100 = width100("...", font.Key) } or nil
	local dotsW = dots and partWidth(dots, size) or 0
	local parts, w = {}, 0
	for _, ch in chars do
		local cw = partWidth(ch, size)
		if w + cw + dotsW > boxW + 0.5 then
			break
		end
		table.insert(parts, ch)
		w += cw
	end
	if dots then
		table.insert(parts, dots)
		w += dotsW
	end
	last.Parts, last.W = parts, w
	return kept, true
end

-- Lays out an object's text in a box (unscaled units: pixels / accumulated UIScale)
local function textLayout(obj, boxW, boxH, limits)
	local p = P(obj)
	local text = p.Text
	if C(obj) == "TextBox" and text == "" then
		text = p.PlaceholderText
	end
	local font = p.FontFace
	local key = table.concat({
		text, tostring(p.RichText), rawget(font, "Family"), rawget(font, "Weight").Name, rawget(font, "Style").Name,
		tostring(p.TextSize), tostring(p.TextScaled), tostring(p.TextWrapped), tostring(p.LineHeight), p.TextTruncate.Name,
		fmt("%.2f|%.2f", boxW, boxH), tostring(limits and limits.Min), tostring(limits and limits.Max), tostring(p.MaxVisibleGraphemes),
	}, "|")
	local cached = textCache[obj]
	if cached and cached.Key == key then
		return cached.Result
	end
	local segments = if p.RichText then parseRich(text) else { { Text = text, Style = {} } }
	if p.MaxVisibleGraphemes >= 0 then
		local left = p.MaxVisibleGraphemes
		local cut = {}
		for _, segment in segments do
			if left <= 0 then
				break
			end
			local n = utf8.len(segment.Text) or #segment.Text
			if n <= left then
				table.insert(cut, segment)
				left -= n
			else
				local stop = utf8.offset(segment.Text, left + 1) or (#segment.Text + 1)
				table.insert(cut, { Text = string.sub(segment.Text, 1, stop - 1), Style = segment.Style })
				left = 0
			end
		end
		segments = cut
	end
	local tokens = tokenize(segments, font)
	local lineHeight = p.LineHeight
	local wrapW = if p.TextWrapped then boxW else nil
	local minSize = (limits and limits.Min) or 1
	local maxSize = math.min(100, (limits and limits.Max) or 100)
	local size
	if p.TextScaled then
		local function fits(s)
			local lines, maxLine = breakLines(tokens, s, wrapW)
			return maxLine <= boxW + 0.5 and blockHeight(lines, lineHeight) <= boxH + 0.5
		end
		local lo, hi = math.max(1, math.floor(minSize)), math.max(1, math.floor(maxSize))
		if fits(hi) then
			size = hi
		elseif not fits(lo) then
			size = lo
		else
			while hi - lo > 1 do
				local mid = (lo + hi) // 2
				if fits(mid) then
					lo = mid
				else
					hi = mid
				end
			end
			size = lo
		end
	else
		size = math.clamp(p.TextSize, minSize, math.max(minSize, maxSize))
	end
	local lines, maxLine = breakLines(tokens, size, wrapW)
	local height = blockHeight(lines, lineHeight)
	local fitsBox = maxLine <= boxW + 0.5 and height <= boxH + 0.5
	local truncated = false
	if p.TextTruncate.Name ~= "None" and not fitsBox then
		lines, truncated = truncate(lines, size, boxW, boxH, lineHeight)
		maxLine = 0
		for _, line in lines do
			maxLine = math.max(maxLine, line.W)
		end
		height = blockHeight(lines, lineHeight)
	end
	local result = { Size = size, Lines = lines, W = maxLine, H = height, Fits = fitsBox, Truncated = truncated, LineHeight = lineHeight, Empty = text == "" }
	textCache[obj] = { Key = key, Result = result }
	return result
end

local function textLimits(comps)
	if comps.TextLimit then
		local lp = P(comps.TextLimit)
		return { Min = lp.MinTextSize, Max = lp.MaxTextSize }
	end
	return nil
end

---------------------------------------------------------------------------------------------------- layout
local build, buildChildren

local function constrain(comps, w, h, s, autoOnly)
	local aspect = comps.Aspect
	if aspect and not autoOnly then
		local ap = P(aspect)
		local ratio = ap.AspectRatio
		if ratio > 0 then
			if ap.AspectType.Name == "ScaleWithParentSize" then
				if ap.DominantAxis.Name == "Width" then
					h = w / ratio
				else
					w = h * ratio
				end
			elseif w / math.max(h, 1e-9) > ratio then
				w = h * ratio
			else
				h = w / ratio
			end
		end
	end
	local limit = comps.SizeLimit
	if limit then
		local lp = P(limit)
		local mn, mx = lp.MinSize, lp.MaxSize
		w = math.clamp(w, mn.X * s, math.max(mn.X * s, mx.X * s))
		h = math.clamp(h, mn.Y * s, math.max(mn.Y * s, mx.Y * s))
	end
	return w, h
end

-- Content box of a laid-out object: padding (left, top, right, bottom) in pixels
local function padding(comps, w, h, s)
	local pad = comps.Padding
	if not pad then
		return 0, 0, 0, 0
	end
	local pp = P(pad)
	return pp.PaddingLeft.Scale * w + pp.PaddingLeft.Offset * s,
		pp.PaddingTop.Scale * h + pp.PaddingTop.Offset * s,
		pp.PaddingRight.Scale * w + pp.PaddingRight.Offset * s,
		pp.PaddingBottom.Scale * h + pp.PaddingBottom.Offset * s
end

-- How big the content of an AutomaticSize object is (pixels, from its top-left)
local function contentExtent(obj, g, autoX)
	local l, t, r, b = padding(g.Comps, g.W, g.H, g.S)
	local maxR, maxB = l + r, t + b
	local layout = g.Comps.Layout
	local lg = layout and G[layout]
	if lg and lg.V == version then
		maxR = math.max(maxR, l + lg.ContentW + r)
		maxB = math.max(maxB, t + lg.ContentH + b)
	else
		for _, child in kids(obj) do
			local cg = G[child]
			if cg and cg.V == version and isGuiObject(child) and P(child).Visible then
				maxR = math.max(maxR, cg.RX + cg.W + r)
				maxB = math.max(maxB, cg.RY + cg.H + b)
			end
		end
	end
	if isText(obj) then
		local boxW = if autoX then math.huge else math.max(0, g.W - l - r) / g.S
		local result = textLayout(obj, boxW, math.huge, textLimits(g.Comps))
		maxR = math.max(maxR, l + r + result.W * g.S)
		maxB = math.max(maxB, t + b + result.H * g.S)
	end
	return maxR, maxB
end

local function sortItems(layout, items)
	local order = P(layout).SortOrder.Name
	local index = {}
	for i, item in items do
		index[item] = i
	end
	if order == "LayoutOrder" then
		table.sort(items, function(a, b)
			local la, lb = P(a).LayoutOrder, P(b).LayoutOrder
			if la ~= lb then
				return la < lb
			end
			return index[a] < index[b]
		end)
	elseif order == "Name" then
		table.sort(items, function(a, b)
			local na, nb = P(a).Name, P(b).Name
			if na ~= nb then
				return na < nb
			end
			return index[a] < index[b]
		end)
	end
end

local function arrangeList(layout, items, ox, oy, aw, ah, s)
	local lp = P(layout)
	local vertical = lp.FillDirection.Name == "Vertical"
	local pad = lp.Padding
	local gap = if vertical then pad.Scale * ah + pad.Offset * s else pad.Scale * aw + pad.Offset * s
	local mainAvail = if vertical then ah else aw
	local crossAvail = if vertical then aw else ah
	local sizes = {}
	for i, item in items do
		local w, h = build(item, aw, ah, s)
		sizes[i] = { w, h }
	end
	local function main(i)
		return if vertical then sizes[i][2] else sizes[i][1]
	end
	local function cross(i)
		return if vertical then sizes[i][1] else sizes[i][2]
	end

	local lines = {}
	local cur = { Items = {}, Main = 0, Cross = 0 }
	for i in items do
		local m = main(i)
		if lp.Wraps and #cur.Items > 0 and cur.Main + gap + m > mainAvail + 0.01 then
			table.insert(lines, cur)
			cur = { Items = {}, Main = 0, Cross = 0 }
		end
		cur.Main += (if #cur.Items > 0 then gap else 0) + m
		cur.Cross = math.max(cur.Cross, cross(i))
		table.insert(cur.Items, i)
	end
	table.insert(lines, cur)

	local flex = if vertical then lp.VerticalFlex.Name else lp.HorizontalFlex.Name
	local mainFrac = if vertical then alignFrac(lp.VerticalAlignment.Name) else alignFrac(lp.HorizontalAlignment.Name)
	local crossFrac = if vertical then alignFrac(lp.HorizontalAlignment.Name) else alignFrac(lp.VerticalAlignment.Name)
	local lineAlign = lp.ItemLineAlignment.Name

	local totalCross = 0
	for index, line in lines do
		totalCross += line.Cross + (if index > 1 then gap else 0)
	end
	local single = #lines == 1
	local crossCursor = if single then 0 else (crossAvail - totalCross) * crossFrac
	local contentMain, contentCross = 0, 0

	for _, line in lines do
		local extra = mainAvail - line.Main
		local n = #line.Items
		local lineGap, lead = gap, 0
		-- flex: items grow (or shrink) to fill the line, or the free space goes between them
		local weights, totalWeight = {}, 0
		for k, i in line.Items do
			local flexItem = G[items[i]] and G[items[i]].Comps.Flex
			local mode = flexItem and P(flexItem).FlexMode.Name or "None"
			local weight = 0
			if flex == "Fill" or mode == "Fill" or (mode == "Grow" and extra > 0) or (mode == "Shrink" and extra < 0) then
				weight = if flexItem and mode == "Custom" then P(flexItem).GrowRatio else 1
			elseif mode == "Custom" then
				weight = if extra > 0 then P(flexItem).GrowRatio else P(flexItem).ShrinkRatio
			end
			weights[k] = weight
			totalWeight += weight
		end
		local consumed = false
		if totalWeight > 0 and math.abs(extra) > 0.01 then
			for k, i in line.Items do
				if weights[k] > 0 then
					local grow = extra * weights[k] / totalWeight
					local item = items[i]
					local w, h = sizes[i][1], sizes[i][2]
					if vertical then
						h = math.max(0, h + grow)
					else
						w = math.max(0, w + grow)
					end
					build(item, aw, ah, s, w, h)
					sizes[i] = { w, h }
				end
			end
			consumed = true
		elseif flex == "SpaceBetween" and n > 1 and extra > 0 then
			lineGap = gap + extra / (n - 1)
			consumed = true
		elseif flex == "SpaceAround" and extra > 0 then
			lineGap = gap + extra / n
			lead = extra / n / 2
			consumed = true
		elseif flex == "SpaceEvenly" and extra > 0 then
			lineGap = gap + extra / (n + 1)
			lead = extra / (n + 1)
			consumed = true
		end
		local lineMain = 0
		for k, i in line.Items do
			lineMain += main(i) + (if k > 1 then gap else 0)
		end
		local cursor = if consumed then lead else (mainAvail - lineMain) * mainFrac
		for k, i in line.Items do
			local item = items[i]
			local frac = crossFrac
			local flexItem = G[item].Comps.Flex
			local align = if flexItem and P(flexItem).ItemLineAlignment.Name ~= "Automatic" then P(flexItem).ItemLineAlignment.Name else lineAlign
			if align == "Start" then
				frac = 0
			elseif align == "Center" then
				frac = 0.5
			elseif align == "End" then
				frac = 1
			elseif align == "Stretch" then
				local span = if single then crossAvail else line.Cross
				if vertical then
					build(item, aw, ah, s, span, sizes[i][2])
					sizes[i] = { span, sizes[i][2] }
				else
					build(item, aw, ah, s, sizes[i][1], span)
					sizes[i] = { sizes[i][1], span }
				end
				frac = 0
			end
			local span = if single then crossAvail else line.Cross
			local crossPos = crossCursor + (span - cross(i)) * frac
			local ig = G[item]
			if vertical then
				ig.RX, ig.RY = ox + crossPos, oy + cursor
			else
				ig.RX, ig.RY = ox + cursor, oy + crossPos
			end
			cursor += main(i) + lineGap
		end
		contentMain = math.max(contentMain, cursor - lineGap - (if consumed then lead else (mainAvail - lineMain) * mainFrac))
		crossCursor += line.Cross + gap
		contentCross += line.Cross + (if contentCross > 0 then gap else 0)
	end
	local contentW = if vertical then contentCross else contentMain
	local contentH = if vertical then contentMain else contentCross
	G[layout] = { V = version, ContentW = contentW, ContentH = contentH }
end

local function arrangeGrid(layout, items, ox, oy, aw, ah, s)
	local lp = P(layout)
	local cs, cp = lp.CellSize, lp.CellPadding
	local cw = cs.X.Scale * aw + cs.X.Offset * s
	local ch = cs.Y.Scale * ah + cs.Y.Offset * s
	local px = cp.X.Scale * aw + cp.X.Offset * s
	local py = cp.Y.Scale * ah + cp.Y.Offset * s
	local aspect = nil
	for _, child in kids(layout) do
		if C(child) == "UIAspectRatioConstraint" then
			aspect = P(child).AspectRatio
		end
	end
	if aspect and aspect > 0 then
		if cw / math.max(ch, 1e-9) > aspect then
			cw = ch * aspect
		else
			ch = cw / aspect
		end
	end
	local horizontal = lp.FillDirection.Name == "Horizontal"
	local n = #items
	local fit = if horizontal then math.floor((aw + px + 0.001) / math.max(cw + px, 1e-6)) else math.floor((ah + py + 0.001) / math.max(ch + py, 1e-6))
	fit = math.max(1, fit)
	local per = if lp.FillDirectionMaxCells > 0 then math.min(lp.FillDirectionMaxCells, fit) else fit
	local cols, rows
	if horizontal then
		cols, rows = math.min(n, per), math.ceil(n / per)
	else
		rows, cols = math.min(n, per), math.ceil(n / per)
	end
	local blockW = cols * cw + math.max(0, cols - 1) * px
	local blockH = rows * ch + math.max(0, rows - 1) * py
	local bx = ox + (aw - blockW) * alignFrac(lp.HorizontalAlignment.Name)
	local by = oy + (ah - blockH) * alignFrac(lp.VerticalAlignment.Name)
	local corner = lp.StartCorner.Name
	for i, item in items do
		local k = i - 1
		local col, row
		if horizontal then
			col, row = k % per, k // per
		else
			row, col = k % per, k // per
		end
		if corner == "TopRight" or corner == "BottomRight" then
			col = cols - 1 - col
		end
		if corner == "BottomLeft" or corner == "BottomRight" then
			row = rows - 1 - row
		end
		build(item, aw, ah, s, cw, ch)
		local ig = G[item]
		ig.RX, ig.RY = bx + col * (cw + px), by + row * (ch + py)
	end
	G[layout] = { V = version, ContentW = blockW, ContentH = blockH }
end

local function arrangePages(layout, items, ox, oy, aw, ah, s)
	local lp = P(layout)
	local horizontal = lp.FillDirection.Name == "Horizontal"
	local pad = lp.Padding
	local gap = if horizontal then pad.Scale * aw + pad.Offset * s else pad.Scale * ah + pad.Offset * s
	local current = rawget(layout, "__page")
	local currentIndex = rawget(layout, "__pageIndex")
	local index = 1
	for i, item in items do
		if item == current or (currentIndex and i - 1 == currentIndex) then
			index = i
		end
	end
	local cursor = 0
	local positions = {}
	for i, item in items do
		local w, h = build(item, aw, ah, s)
		positions[i] = cursor
		cursor += (if horizontal then w else h) + gap
	end
	local shift = positions[index] or 0
	for i, item in items do
		local ig = G[item]
		local w, h = ig.W, ig.H
		if horizontal then
			ig.RX, ig.RY = ox + positions[i] - shift + (aw - w) * alignFrac(lp.HorizontalAlignment.Name), oy + (ah - h) * alignFrac(lp.VerticalAlignment.Name)
		else
			ig.RX, ig.RY = ox + (aw - w) * alignFrac(lp.HorizontalAlignment.Name), oy + positions[i] - shift + (ah - h) * alignFrac(lp.VerticalAlignment.Name)
		end
	end
	rawset(layout, "__currentPage", items[index])
	G[layout] = { V = version, ContentW = if horizontal then cursor - gap else aw, ContentH = if horizontal then ah else cursor - gap }
end

-- Lays out obj's children inside its content box. g = obj's geometry (W, H, S).
buildChildren = function(obj, g)
	local comps = g.Comps
	local p = P(obj)
	local s = g.S
	local w, h = g.W, g.H
	local ox, oy, aw, ah = 0, 0, w, h
	local scroll = C(obj) == "ScrollingFrame"
	local canvasW, canvasH, winW, winH
	if scroll then
		local thick = p.ScrollBarThickness * s
		winW, winH = w, h
		-- "ScrollBar" insets only while the canvas scrolls (decided by the previous pass, see below)
		if p.VerticalScrollBarInset.Name == "Always" or (p.VerticalScrollBarInset.Name == "ScrollBar" and g.InsetY) then
			winW = math.max(0, w - thick)
		end
		if p.HorizontalScrollBarInset.Name == "Always" or (p.HorizontalScrollBarInset.Name == "ScrollBar" and g.InsetX) then
			winH = math.max(0, h - thick)
		end
		local cs = p.CanvasSize
		canvasW = cs.X.Scale * winW + cs.X.Offset * s
		canvasH = cs.Y.Scale * winH + cs.Y.Offset * s
		aw, ah = math.max(canvasW, winW), math.max(canvasH, winH)
		ox, oy = -p.CanvasPosition.X * s, -p.CanvasPosition.Y * s
	end
	local l, t, r, b = padding(comps, aw, ah, s)
	ox += l
	oy += t
	aw = math.max(0, aw - l - r)
	ah = math.max(0, ah - t - b)
	g.Area = { ox, oy, aw, ah }
	g.Pad = { l, t, r, b }

	local layout = comps.Layout
	local items = {}
	for _, child in kids(obj) do
		if isGuiObject(child) then
			local cp = P(child)
			if layout and cp.Visible then
				table.insert(items, child)
			else
				local cw, ch = build(child, aw, ah, s)
				local px = ox + cp.Position.X.Scale * aw + cp.Position.X.Offset * s
				local py = oy + cp.Position.Y.Scale * ah + cp.Position.Y.Offset * s
				local cg = G[child]
				cg.RX = px - cp.AnchorPoint.X * cw
				cg.RY = py - cp.AnchorPoint.Y * ch
			end
		end
	end
	if layout then
		sortItems(layout, items)
		local cls = C(layout)
		if cls == "UIGridLayout" then
			arrangeGrid(layout, items, ox, oy, aw, ah, s)
		elseif cls == "UIPageLayout" then
			arrangePages(layout, items, ox, oy, aw, ah, s)
		else
			arrangeList(layout, items, ox, oy, aw, ah, s)
		end
	end

	if scroll then
		local auto = p.AutomaticCanvasSize.Name
		local extentW, extentH = 0, 0
		local lg = layout and G[layout]
		if lg then
			extentW, extentH = l + lg.ContentW + r, t + lg.ContentH + b
		else
			for _, child in kids(obj) do
				local cg = G[child]
				if cg and isGuiObject(child) and P(child).Visible then
					extentW = math.max(extentW, cg.RX - (ox - l) + cg.W + r)
					extentH = math.max(extentH, cg.RY - (oy - t) + cg.H + b)
				end
			end
		end
		if auto == "X" or auto == "XY" then
			canvasW = math.max(canvasW, extentW)
		end
		if auto == "Y" or auto == "XY" then
			canvasH = math.max(canvasH, extentH)
		end
		g.Canvas = { math.max(canvasW, winW), math.max(canvasH, winH) }
		g.Window = { winW, winH }
		local dir = p.ScrollingDirection.Name
		local thick = p.ScrollBarThickness * s
		g.Bars = {}
		if (dir == "Y" or dir == "XY") and canvasH > winH + 0.5 and thick > 0 then
			local len = winH * winH / canvasH
			local at = (p.CanvasPosition.Y * s) / math.max(1, canvasH - winH) * (winH - len)
			table.insert(g.Bars, { (if p.VerticalScrollBarPosition.Name == "Left" then 0 else w - thick), math.clamp(at, 0, winH - len), thick, len })
		end
		if (dir == "X" or dir == "XY") and canvasW > winW + 0.5 and thick > 0 then
			local len = winW * winW / canvasW
			local at = (p.CanvasPosition.X * s) / math.max(1, canvasW - winW) * (winW - len)
			table.insert(g.Bars, { math.clamp(at, 0, winW - len), h - thick, len, thick })
		end
		local needY = p.VerticalScrollBarInset.Name == "ScrollBar" and canvasH > winH + 0.5 and (dir == "Y" or dir == "XY")
		local needX = p.HorizontalScrollBarInset.Name == "ScrollBar" and canvasW > winW + 0.5 and (dir == "X" or dir == "XY")
		if (needY and not g.InsetY) or (needX and not g.InsetX) then
			g.InsetY = g.InsetY or needY
			g.InsetX = g.InsetX or needX
			buildChildren(obj, g)
		end
	end
end

-- Sizes obj for a parent area (aw x ah, parent scale ps) and lays out its subtree. forcedW/H: size set
-- by a layout (grid cell, flex). Geometry is stored with RX/RY = 0 (the caller places it).
build = function(obj, aw, ah, ps, forcedW, forcedH)
	local p = P(obj)
	local comps = components(obj)
	local own = if comps.Scale then P(comps.Scale).Scale else 1
	local s = ps * own
	local bw, bh
	if forcedW then
		bw, bh = forcedW / own, forcedH / own
	else
		local size = p.Size
		local constraint = p.SizeConstraint.Name
		bw = (if constraint == "RelativeYY" then size.X.Scale * ah else size.X.Scale * aw) + size.X.Offset * ps
		bh = (if constraint == "RelativeXX" then size.Y.Scale * aw else size.Y.Scale * ah) + size.Y.Offset * ps
		bw, bh = constrain(comps, bw, bh, ps)
	end
	local g = { V = version, RX = 0, RY = 0, W = bw * own, H = bh * own, S = s, Rot = p.Rotation, Comps = comps }
	G[obj] = g
	buildChildren(obj, g)
	local auto = p.AutomaticSize.Name
	if auto ~= "None" and not forcedW then
		local autoX = auto == "X" or auto == "XY"
		local autoY = auto == "Y" or auto == "XY"
		local cw, ch = contentExtent(obj, g, autoX)
		local nw = if autoX then math.max(g.W, cw) else g.W
		local nh = if autoY then math.max(g.H, ch) else g.H
		nw, nh = constrain(comps, nw / own, nh / own, ps, true)
		nw, nh = nw * own, nh * own
		if math.abs(nw - g.W) > 0.01 or math.abs(nh - g.H) > 0.01 then
			g.W, g.H = nw, nh
			buildChildren(obj, g)
		end
	end
	return g.W, g.H
end

local function screenRect(gui)
	local p = P(gui)
	local screen = M.Screen
	local insets = p.ScreenInsets.Name
	if p.IgnoreGuiInset or insets == "None" then
		return 0, 0, screen.W, screen.H
	elseif insets == "DeviceSafeInsets" then
		local l, r, b = screen.SafeLeft or 0, screen.SafeRight or 0, screen.SafeBottom or 0
		local top = screen.SafeTop or 0
		return l, top, screen.W - l - r, screen.H - top - b
	end
	local l, r, b = screen.SafeLeft or 0, screen.SafeRight or 0, screen.SafeBottom or 0
	return l, screen.InsetTop, screen.W - l - r, screen.H - screen.InsetTop - b
end

local function resolve(obj, px, py)
	local g = G[obj]
	g.X, g.Y = px + g.RX, py + g.RY
	for _, child in kids(obj) do
		local cg = G[child]
		if cg and cg.V == version and cg.RX then
			resolve(child, g.X, g.Y)
		end
	end
end

local function layoutRoot(root)
	local cls = C(root)
	if isA(cls, "LayerCollector") then
		local x, y, w, h = screenRect(root)
		G[root] = { V = version, RX = x, RY = y, W = w, H = h, S = 1, Rot = 0, Comps = components(root), Root = true }
		buildChildren(root, G[root])
		resolve(root, 0, 0)
	elseif cls == "BillboardGui" or cls == "SurfaceGui" then
		-- in-world guis are not drawn; their children still get sizes (offsets of the gui's Size)
		local size = P(root).Size
		local w = if size then size.X.Offset else 0
		local h = if size then size.Y.Offset else 0
		G[root] = { V = version, RX = 0, RY = 0, W = w, H = h, S = 1, Rot = 0, Comps = components(root), World = true }
		buildChildren(root, G[root])
		resolve(root, 0, 0)
	end
end

local layoutCount = 0
local function relayout()
	dirty = false
	version += 1
	layoutCount += 1
	local playerGui = M.PlayerGui
	if playerGui then
		for _, root in kids(playerGui) do
			layoutRoot(root)
		end
	end
end
Layout.Relayout = relayout
function Layout.Count()
	return layoutCount
end

-- Geometry of any GuiBase2d. Objects outside the PlayerGui's guis are laid out on their own against a
-- 0 x 0 parent (Roblox reports offsets only for unparented objects).
local function geometry(obj)
	if dirty then
		relayout()
	end
	local g = G[obj]
	if g and g.V == version and g.X then
		return g
	end
	local top = obj
	while true do
		local parent = rawget(top, "__parent")
		if parent and isA(C(parent), "GuiBase2d") then
			top = parent
		else
			break
		end
	end
	if isA(C(top), "GuiObject") then
		build(top, 0, 0, 1)
		local tp = P(top)
		G[top].RX, G[top].RY = tp.Position.X.Offset, tp.Position.Y.Offset
		resolve(top, 0, M.Screen.InsetTop)
	else
		layoutRoot(top)
	end
	g = G[obj]
	if g and g.V == version and g.X then
		return g
	end
	return { X = 0, Y = M.Screen.InsetTop, W = 0, H = 0, S = 1, Rot = 0, Comps = components(obj) }
end
Layout.Geometry = geometry

function Layout.AbsolutePosition(obj)
	local g = geometry(obj)
	return v2(g.X, g.Y - M.Screen.InsetTop)
end
function Layout.AbsoluteSize(obj)
	local g = geometry(obj)
	return v2(g.W, g.H)
end
function Layout.AbsoluteRotation(obj)
	local total = 0
	local current = obj
	while current and isA(C(current), "GuiObject") do
		total += P(current).Rotation
		current = rawget(current, "__parent")
	end
	return total
end
function Layout.ContentSize(layout)
	local parent = rawget(layout, "__parent")
	if parent and isA(C(parent), "GuiBase2d") then
		geometry(parent)
		local lg = G[layout]
		if lg and lg.V == version then
			return v2(lg.ContentW, lg.ContentH)
		end
	end
	return v2(0, 0)
end
function Layout.CurrentPage(layout)
	Layout.ContentSize(layout)
	return rawget(layout, "__currentPage")
end
function Layout.CanvasInfo(scroll)
	local g = geometry(scroll)
	local canvas = g.Canvas or { g.W, g.H }
	local window = g.Window or { g.W, g.H }
	return { Canvas = v2(canvas[1], canvas[2]), Window = v2(window[1], window[2]) }
end

local function textBox(obj, g)
	local l, t, r, b = padding(g.Comps, g.W, g.H, g.S)
	return l, t, math.max(0, g.W - l - r), math.max(0, g.H - t - b)
end
function Layout.TextLayout(obj)
	local g = geometry(obj)
	local _, _, bw, bh = textBox(obj, g)
	return textLayout(obj, bw / g.S, bh / g.S, textLimits(g.Comps)), g
end
function Layout.TextBounds(obj)
	local result, g = Layout.TextLayout(obj)
	if result.Empty then
		return v2(0, 0)
	end
	return v2(result.W * g.S, result.H * g.S)
end
function Layout.TextFits(obj)
	local result = Layout.TextLayout(obj)
	return result.Fits
end
-- TextService:GetTextSize
function Layout.MeasureText(text, size, fontEnum, frame)
	local font = M.Font.fromEnum(fontEnum)
	local tokens = tokenize({ { Text = text, Style = {} } }, font)
	local wrapW = if frame and frame.X > 0 then frame.X else nil
	local lines, maxLine = breakLines(tokens, size, wrapW)
	return v2(maxLine, blockHeight(lines, 1))
end
function Layout.MeasureFont(text, size, font, width)
	local tokens = tokenize({ { Text = text, Style = {} } }, font)
	local lines, maxLine = breakLines(tokens, size, if width and width > 0 then width else nil)
	return v2(maxLine, blockHeight(lines, 1))
end

---------------------------------------------------------------------------------------------------- change signals
local watched = setmetatable({}, { __mode = "k" })
local WATCH = { "AbsoluteSize", "AbsolutePosition", "AbsoluteRotation", "AbsoluteContentSize", "AbsoluteCanvasSize", "AbsoluteWindowSize", "TextBounds", "TextFits", "ViewportSize" }
function M.WatchComputed(obj)
	if watched[obj] then
		return
	end
	local computed = M.ClassInfo(C(obj)).Computed
	local entry = {}
	for _, name in WATCH do
		if computed[name] then
			local ok, value = pcall(function()
				return obj[name]
			end)
			if ok then
				entry[name] = value
			end
		end
	end
	watched[obj] = entry
end

local checkedVersion = -1
M.AfterFrame = function()
	if dirty then
		relayout()
	end
	if checkedVersion == version then
		return
	end
	checkedVersion = version
	for obj, entry in watched do
		if rawget(obj, "__destroyed") then
			watched[obj] = nil
			continue
		end
		for name, old in entry do
			local ok, now = pcall(function()
				return obj[name]
			end)
			if ok and now ~= old then
				entry[name] = now
				local signal = rawget(obj, "__propSignals")[name]
				if signal then
					M.Fire(signal)
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------- draw list
local function hex(color)
	return color:ToHex()
end

-- UIGradient -> { Rot, Offset, Keys = { { t, "RRGGBB", alpha } } } with colour and transparency merged
local function gradientOf(gradient)
	if not gradient then
		return nil
	end
	local gp = P(gradient)
	local colors = rawget(gp.Color, "Keypoints")
	local alphas = rawget(gp.Transparency, "Keypoints")
	local times = {}
	local seen = {}
	for _, list in { colors, alphas } do
		for _, key in list do
			local t = math.floor(key.Time * 10000 + 0.5) / 10000
			if not seen[t] then
				seen[t] = true
				table.insert(times, t)
			end
		end
	end
	table.sort(times)
	local function sampleColor(t)
		for i = 1, #colors - 1 do
			local a, b = colors[i], colors[i + 1]
			if t <= b.Time + 1e-6 then
				local span = b.Time - a.Time
				local f = if span > 0 then math.clamp((t - a.Time) / span, 0, 1) else 0
				return a.Value:Lerp(b.Value, f)
			end
		end
		return colors[#colors].Value
	end
	local function sampleAlpha(t)
		for i = 1, #alphas - 1 do
			local a, b = alphas[i], alphas[i + 1]
			if t <= b.Time + 1e-6 then
				local span = b.Time - a.Time
				local f = if span > 0 then math.clamp((t - a.Time) / span, 0, 1) else 0
				return 1 - (a.Value + (b.Value - a.Value) * f)
			end
		end
		return 1 - alphas[#alphas].Value
	end
	local keys = {}
	for _, t in times do
		table.insert(keys, { t, hex(sampleColor(t)), math.clamp(sampleAlpha(t), 0, 1) })
	end
	return { Rot = gp.Rotation, Offset = { gp.Offset.X, gp.Offset.Y }, Keys = keys }
end

local function strokeOf(stroke, s, alpha, minSide)
	if not stroke then
		return nil
	end
	local sp = P(stroke)
	local a = (1 - sp.Transparency) * alpha
	if sp.Thickness <= 0 or a <= 0.001 then
		return nil
	end
	local gradient = nil
	for _, child in kids(stroke) do
		if C(child) == "UIGradient" and P(child).Enabled then
			gradient = gradientOf(child)
			break
		end
	end
	-- ScaledSize: Thickness is a fraction of the object's shorter side
	local thickness = if sp.StrokeSizingMode.Name == "ScaledSize" then sp.Thickness * (minSide or 0) else sp.Thickness * s
	return { T = thickness, Color = hex(sp.Color), A = a, Grad = gradient, Join = sp.LineJoinMode.Name, Pos = sp.BorderStrokePosition.Name }
end

local function matMul(a, b)
	return {
		a[1] * b[1] + a[3] * b[2], a[2] * b[1] + a[4] * b[2],
		a[1] * b[3] + a[3] * b[4], a[2] * b[3] + a[4] * b[4],
		a[1] * b[5] + a[3] * b[6] + a[5], a[2] * b[5] + a[4] * b[6] + a[6],
	}
end
local function rotateAbout(cx, cy, degrees)
	local r = math.rad(degrees)
	local c, s = math.cos(r), math.sin(r)
	-- T(c) R T(-c)
	return { c, s, -s, c, cx - c * cx + s * cy, cy - s * cx - c * cy }
end

local function textItem(obj, g, comps, alpha)
	local p = P(obj)
	local l, t, bw, bh = textBox(obj, g)
	local result = textLayout(obj, bw / g.S, bh / g.S, textLimits(comps))
	if result.Empty and not (C(obj) == "TextBox" and p.PlaceholderText ~= "") then
		return nil
	end
	local placeholder = C(obj) == "TextBox" and p.Text == ""
	local color = if placeholder then p.PlaceholderColor3 else p.TextColor3
	local a = (1 - p.TextTransparency) * alpha
	if a <= 0.001 then
		return nil
	end
	local base = fontInfo(p.FontFace)
	local lines = {}
	for _, line in result.Lines do
		local runs = {}
		for _, part in line.Parts do
			local st = part.Style
			local run = { T = part.Text }
			if part.Font.Css ~= base.Css or part.Font.Weight ~= base.Weight or part.Font.Italic ~= base.Italic then
				run.F, run.Wt, run.It = part.Font.Css, part.Font.Weight, part.Font.Italic or nil
			end
			if st.Size then
				run.Sz = st.Size * g.S
			end
			if st.Color then
				run.C = hex(st.Color)
			end
			if st.Transparency then
				run.A = (1 - st.Transparency) * alpha
			end
			if st.Underline then
				run.U = true
			end
			if st.Strike then
				run.St = true
			end
			if st.SmallCaps then
				run.Sc = true
			end
			if st.StrokeColor then
				run.Sk = { T = st.StrokeThickness * g.S, Color = hex(st.StrokeColor), A = (1 - st.StrokeTransparency) * alpha }
			end
			if st.Mark then
				run.Mk = { Color = hex(st.Mark), A = (1 - st.MarkTransparency) * alpha }
			end
			table.insert(runs, run)
		end
		table.insert(lines, { W = line.W * g.S, H = line.Size * result.LineHeight * g.S, Runs = runs })
	end
	local item = {
		Box = { l, t, bw, bh },
		Lines = lines,
		Size = result.Size * g.S,
		Font = base.Css,
		Weight = base.Weight,
		Italic = base.Italic or nil,
		Color = hex(color),
		A = a,
		X = p.TextXAlignment.Name,
		Y = p.TextYAlignment.Name,
		H = result.H * g.S,
		Rich = p.RichText or nil,
	}
	local stroke = comps.TextStroke
	if stroke then
		item.Stroke = strokeOf(stroke, g.S, alpha, math.min(g.W, g.H))
		if item.Stroke and P(stroke).Transparency > 0 and p.TextTransparency > 0 then
			-- both fading: Roblox fades the outline with the text
			item.Stroke.A = math.min(item.Stroke.A, a)
		end
	elseif p.TextStrokeTransparency < 1 then
		item.Stroke = { T = 1 * g.S, Color = hex(p.TextStrokeColor3), A = (1 - p.TextStrokeTransparency) * alpha, Legacy = true }
	end
	return item
end

local function imageItem(obj, alpha)
	local p = P(obj)
	if p.Image == "" or p.ImageTransparency >= 1 then
		return nil
	end
	local item = {
		Src = p.Image,
		Color = hex(p.ImageColor3),
		A = (1 - p.ImageTransparency) * alpha,
		Scale = p.ScaleType.Name,
	}
	if p.ImageRectSize.X > 0 and p.ImageRectSize.Y > 0 then
		item.Rect = { p.ImageRectOffset.X, p.ImageRectOffset.Y, p.ImageRectSize.X, p.ImageRectSize.Y }
	end
	if p.ScaleType.Name == "Slice" then
		local sc = p.SliceCenter
		item.Slice = { sc.Min.X, sc.Min.Y, sc.Max.X, sc.Max.Y, p.SliceScale }
	elseif p.ScaleType.Name == "Tile" then
		item.Tile = { p.TileSize.X.Scale, p.TileSize.X.Offset, p.TileSize.Y.Scale, p.TileSize.Y.Offset }
	end
	return item
end

local function paint(obj, g, alpha)
	local p = P(obj)
	local cls = C(obj)
	local comps = g.Comps
	local item = { Id = rawget(obj, "__id"), Class = cls, Name = p.Name }
	local minSide = math.min(g.W, g.H)
	if comps.Corner then
		local cr = P(comps.Corner).CornerRadius
		item.R = math.max(0, math.min(cr.Scale * minSide + cr.Offset * g.S, minSide / 2))
	end
	local bgA = (1 - p.BackgroundTransparency) * alpha
	local gradient = gradientOf(comps.Gradient)
	if bgA > 0.001 then
		item.Bg = hex(p.BackgroundColor3)
		item.BgA = bgA
	end
	if gradient then
		item.Grad = gradient
	end
	if comps.BorderStroke or (comps.TextStroke and not isText(obj)) then
		item.Stroke = strokeOf(comps.BorderStroke or comps.TextStroke, g.S, alpha, minSide)
	elseif p.BorderSizePixel > 0 and bgA > 0.001 and not comps.Corner then
		item.Border = { T = p.BorderSizePixel * g.S, Color = hex(p.BorderColor3), A = bgA, Mode = p.BorderMode.Name }
	end
	if isText(obj) then
		item.Text = textItem(obj, g, comps, alpha)
	elseif cls == "ImageLabel" or cls == "ImageButton" then
		item.Image = imageItem(obj, alpha)
	elseif cls == "ViewportFrame" then
		local describe = M.DescribeViewport
		local view = if describe then describe(obj) else { Kind = "Empty" }
		if view then
			view.A = (1 - p.ImageTransparency) * alpha
			view.Color = hex(p.ImageColor3)
			item.View = view
		end
	elseif cls == "VideoFrame" then
		item.Video = true
	end
	if g.Bars and #g.Bars > 0 and p.ScrollBarImageTransparency < 1 then
		item.Bars = g.Bars
		item.BarColor = hex(p.ScrollBarImageColor3)
		item.BarA = (1 - p.ScrollBarImageTransparency) * alpha
	end
	return item
end

local function sortedChildren(obj, global)
	local list = {}
	for index, child in kids(obj) do
		if isGuiObject(child) then
			table.insert(list, { child, index })
		end
	end
	if not global then
		table.sort(list, function(a, b)
			local za, zb = P(a[1]).ZIndex, P(b[1]).ZIndex
			if za ~= zb then
				return za < zb
			end
			return a[2] < b[2]
		end)
	end
	return list
end

local function intersect(a, b)
	if not a then
		return b
	end
	return { math.max(a[1], b[1]), math.max(a[2], b[2]), math.min(a[3], b[3]), math.min(a[4], b[4]) }
end

-- Every drawn GuiObject in paint order: { ..., X, Y, W, H (screen px), M (2D matrix for rotation),
-- Clip (screen rect from ClipsDescendants / scrolling frames) }
function Layout.DrawList()
	if dirty then
		relayout()
	end
	local items = {}
	local guis = {}
	local playerGui = M.PlayerGui
	for index, gui in kids(playerGui) do
		if C(gui) == "ScreenGui" and P(gui).Enabled then
			table.insert(guis, { gui, index })
		end
	end
	table.sort(guis, function(a, b)
		local da, db = P(a[1]).DisplayOrder, P(b[1]).DisplayOrder
		if da ~= db then
			return da < db
		end
		return a[2] < b[2]
	end)
	for guiIndex, entry in guis do
		local gui = entry[1]
		local global = P(gui).ZIndexBehavior.Name == "Global"
		local list = {}
		local order = 0
		local function walk(obj, matrix, clip, alpha)
			for _, pair in sortedChildren(obj, global) do
				local child = pair[1]
				local cp = P(child)
				local g = G[child]
				if cp.Visible and g and g.V == version and g.X then
					local m = matrix
					if g.Rot % 360 ~= 0 then
						m = matMul(matrix or { 1, 0, 0, 1, 0, 0 }, rotateAbout(g.X + g.W / 2, g.Y + g.H / 2, g.Rot))
					end
					local a = alpha
					if C(child) == "CanvasGroup" then
						a *= 1 - cp.GroupTransparency
					end
					local item = paint(child, g, a)
					item.X, item.Y, item.W, item.H = g.X, g.Y, g.W, g.H
					item.M = m
					item.Clip = clip
					item.Path = M.FullName(child)
					order += 1
					item.Z, item.Order = cp.ZIndex, order
					item.Gui = guiIndex
					if item.Bg or item.Grad or item.Stroke or item.Border or item.Text or item.Image or item.View or item.Bars or item.Video then
						table.insert(list, item)
					end
					local childClip = clip
					if cp.ClipsDescendants or C(child) == "ScrollingFrame" or C(child) == "CanvasGroup" then
						local winW = if g.Window then g.Window[1] else g.W
						local winH = if g.Window then g.Window[2] else g.H
						childClip = intersect(clip, { g.X, g.Y, g.X + winW, g.Y + winH })
					end
					if a > 0.001 then
						walk(child, m, childClip, a)
					end
				end
			end
		end
		walk(gui, nil, nil, 1)
		if global then
			table.sort(list, function(a, b)
				if a.Z ~= b.Z then
					return a.Z < b.Z
				end
				return a.Order < b.Order
			end)
		end
		for _, item in list do
			table.insert(items, item)
		end
	end
	return items
end

-- The PlayerGui as a tree for the JSON dump / --tree: every GuiBase2d with its computed geometry
function Layout.Tree()
	if dirty then
		relayout()
	end
	local inset = M.Screen.InsetTop
	local function node(obj, shown)
		local p = P(obj)
		local g = G[obj]
		local out = { Name = p.Name, Class = C(obj) }
		if g and g.V == version and g.X then
			out.Position = { math.floor(g.X * 100 + 0.5) / 100, math.floor((g.Y - inset) * 100 + 0.5) / 100 }
			out.Size = { math.floor(g.W * 100 + 0.5) / 100, math.floor(g.H * 100 + 0.5) / 100 }
			out.Screen = { math.floor(g.X * 10 + 0.5) / 10, math.floor(g.Y * 10 + 0.5) / 10 } -- PNG pixels
		end
		if isA(C(obj), "GuiObject") then
			out.Visible = p.Visible
			out.Shown = shown and p.Visible
			out.ZIndex = p.ZIndex
			if p.LayoutOrder ~= 0 then
				out.LayoutOrder = p.LayoutOrder
			end
			if p.Rotation ~= 0 then
				out.Rotation = p.Rotation
			end
			if isText(obj) then
				out.Text = p.Text
				local ok, result = pcall(textLayout, obj, math.max(0, (g and g.W or 0)) / (g and g.S or 1), math.max(0, (g and g.H or 0)) / (g and g.S or 1), textLimits(g and g.Comps or components(obj)))
				if ok and g then
					out.TextSize = math.floor(result.Size * g.S * 10 + 0.5) / 10
					if not result.Fits then
						out.TextOverflows = true
					end
				end
			elseif p.Image then
				out.Image = p.Image
			end
		elseif C(obj) == "ScreenGui" then
			out.Enabled = p.Enabled
			out.DisplayOrder = p.DisplayOrder
			shown = shown and p.Enabled
		end
		local children, ui = {}, {}
		for _, child in kids(obj) do
			if isA(C(child), "GuiBase2d") then
				table.insert(children, node(child, shown and (not isA(C(obj), "GuiObject") or p.Visible)))
			elseif isA(C(child), "UIBase") then
				table.insert(ui, C(child))
			end
		end
		if #ui > 0 then
			out.UI = ui
		end
		if #children > 0 then
			out.Children = children
		end
		return out
	end
	local roots = {}
	if M.PlayerGui then
		for _, gui in kids(M.PlayerGui) do
			if C(gui) == "ScreenGui" then
				table.insert(roots, node(gui, true))
			end
		end
	end
	return roots
end

-- PlayerGui:GetGuiObjectsAtPosition (x, y in GUI space): visible GuiObjects under the point, topmost first
function Layout.HitTest(x, y)
	if dirty then
		relayout()
	end
	local sy = y + M.Screen.InsetTop
	local hits = {}
	local function walk(obj)
		for _, pair in sortedChildren(obj, false) do
			local child = pair[1]
			local g = G[child]
			if P(child).Visible and g and g.V == version and g.X then
				if x >= g.X and x <= g.X + g.W and sy >= g.Y and sy <= g.Y + g.H then
					table.insert(hits, child)
				end
				walk(child)
			end
		end
	end
	local guis = {}
	for index, gui in kids(M.PlayerGui) do
		if C(gui) == "ScreenGui" and P(gui).Enabled then
			table.insert(guis, { gui, index })
		end
	end
	table.sort(guis, function(a, b)
		local da, db = P(a[1]).DisplayOrder, P(b[1]).DisplayOrder
		if da ~= db then
			return da < db
		end
		return a[2] < b[2]
	end)
	for _, entry in guis do
		walk(entry[1])
	end
	local out = {}
	for i = #hits, 1, -1 do
		table.insert(out, hits[i])
	end
	return out
end
