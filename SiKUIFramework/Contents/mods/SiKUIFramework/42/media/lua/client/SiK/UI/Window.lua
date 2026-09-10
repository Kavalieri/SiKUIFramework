require "SiK/UI/Namespace"
require "SiK/UI/Metrics"
require "SiK/UI/Viewport"
require "SiK/UI/State"
require "SiK/UI/Theme"
require "SiK/UI/Controls"
require "SiK/UI/FocusStack"
require "ISUI/ISPanel"

local Window = SiK.UI.Window or {}
SiK.UI.Namespace.define("Window", Window)

local BASE_METHODS = {
	initialise = ISPanel.initialise,
	render = ISPanel.render,
	prerender = ISPanel.prerender,
	onMouseMove = ISPanel.onMouseMove,
	onMouseMoveOutside = ISPanel.onMouseMoveOutside,
	onMouseUp = ISPanel.onMouseUp,
	onMouseUpOutside = ISPanel.onMouseUpOutside,
	onKeyRelease = ISPanel.onKeyRelease,
}

-- Weak lifecycle registry for the opt-in initial cascade; never polled.
local liveWindows = setmetatable({}, { __mode = "k" })

local function visible(panel)
	if not panel or panel._sikDisposed then return false end
	if panel.getIsVisible then return panel:getIsVisible() ~= false end
	return panel.visible ~= false
end

local function overlaps(a, b)
	return a.x < b.x + b.w and a.x + a.w > b.x
		and a.y < b.y + b.h and a.y + a.h > b.y
end

function Window.derive(name)
	if type(name) ~= "string" or name == "" then return nil, "invalid_class_name" end
	return ISPanel:derive(name)
end

function Window.callBase(panel, method, ...)
	if not panel then return nil, "invalid_panel" end
	local callback = BASE_METHODS[method]
	if type(callback) ~= "function" then return nil, "unsupported_base_method" end
	return callback(panel, ...)
end

Window.profiles = Window.profiles or {
	-- Full application shell. It preserves the existing terminal contract:
	-- one responsive geometry that may use the complete safe viewport instead
	-- of switching to a second compact interface.
	terminal = { width = 1600, height = 900, minWidth = 720, minHeight = 480,
		maxWidth = 8192, maxHeight = 8192, capWidth = 1, capHeight = 1 },
	compact = { width = 460, height = 320, minWidth = 360, minHeight = 180,
		maxWidth = 560, maxHeight = 620, capWidth = 0.70, capHeight = 0.70 },
	standard = { width = 860, height = 640, minWidth = 600, minHeight = 460,
		maxWidth = 1000, maxHeight = 800, capWidth = 0.86, capHeight = 0.86 },
	wide = { width = 1000, height = 720, minWidth = 720, minHeight = 520,
		maxWidth = 1200, maxHeight = 860, capWidth = 0.92, capHeight = 0.90 },
	editor = { width = 1180, height = 1048, minWidth = 760, minHeight = 620,
		maxWidth = 8192, maxHeight = 8192, capWidth = 1, capHeight = 1 },
	task = { width = 640, height = 520, minWidth = 420, minHeight = 260,
		maxWidth = 760, maxHeight = 760, capWidth = 0.80, capHeight = 0.80 },
	-- Requirement-driven tasks start wide enough for two independent blocks.
	-- Their only ceiling is the safe viewport, so long localized requirements
	-- can be resized instead of being forced into a second compact layout.
	["task-requirements"] = { width = 960, height = 520, minWidth = 720, minHeight = 260,
		maxWidth = math.huge, maxHeight = math.huge, capWidth = 1, capHeight = 1 },
	-- Editing one installed terminal is narrower than a zone/container editor,
	-- while keeping the same viewport-bounded resize contract.
	["terminal-config"] = { width = 720, height = 320, minWidth = 560, minHeight = 180,
		maxWidth = math.huge, maxHeight = math.huge, capWidth = 1, capHeight = 1 },
}

local function n(value, fallback)
	value = tonumber(value)
	if value == nil or value ~= value then return fallback end
	return value
end

local function rectValue(widget, field, getter)
	return n(widget[field], widget[getter] and widget[getter](widget) or 0)
end

local function removeChild(parent, child)
	if not child then return end
	if parent and parent.removeChild then parent:removeChild(child)
	elseif child.removeFromUIManager then child:removeFromUIManager() end
end

local function displayValue(value, separator)
	if value == nil then return "" end
	if type(value) ~= "table" then return tostring(value) end
	if value.text ~= nil then return tostring(value.text) end
	if value.label ~= nil and value.value ~= nil then
		return tostring(value.label) .. ": " .. tostring(value.value)
	end
	local values = {}
	for index = 1, #value do
		local text = displayValue(value[index], separator)
		if text ~= "" then values[#values + 1] = text end
	end
	return table.concat(values, separator or " | ")
end

local function measuredWidth(text, font)
	local manager = type(getTextManager) == "function" and getTextManager() or nil
	if manager and manager.MeasureStringX then return manager:MeasureStringX(font or UIFont.Small, text) end
	return #tostring(text or "") * 8
end

local function safePrefix(text, last)
	last = math.max(0, math.min(#text, math.floor(n(last, 0))))
	-- Lua 5.1 counts UTF-8 bytes while Kahlua exposes Java string units. Only
	-- move the boundary when it is recognisably inside a UTF-8 continuation;
	-- Kahlua BMP/CJK remains untouched.
	local nextByte = string.byte(text, last + 1)
	while last > 0 and nextByte and nextByte >= 128 and nextByte < 192 do
		last = last - 1
		nextByte = string.byte(text, last + 1)
	end
	return string.sub(text, 1, last)
end

local function fitText(text, maxWidth, font)
	text = tostring(text or "")
	maxWidth = math.max(0, n(maxWidth, 0))
	if text == "" or measuredWidth(text, font) <= maxWidth then return text end
	local suffix = "..."
	if measuredWidth(suffix, font) > maxWidth then return "" end
	local low, high, best = 0, #text, ""
	while low <= high do
		local middle = math.floor((low + high) / 2)
		local candidate = safePrefix(text, middle) .. suffix
		if measuredWidth(candidate, font) <= maxWidth then
			best = candidate
			low = middle + 1
		else
			high = middle - 1
		end
	end
	return best
end

--- Keeps an editor identity readable by sacrificing the optional zone/context
--- suffix before its prefix/name. Consumers pass data only, never offsets.
function Window.composeHeaderTitle(parts, maxWidth, font)
	parts = type(parts) == "table" and parts or { name = parts }
	-- Product punctuation must come from the consumer's Translator-backed i18n.
	-- The neutral fallback stays ASCII: synthesising UTF-8 bytes with
	-- string.char is rendered as mojibake by Kahlua on some PZ installations.
	local defaultSeparator = " | "
	local separator = tostring(parts.separator or defaultSeparator)
	local primary = tostring(parts.prefix or "")
	local name = tostring(parts.name or "")
	if primary ~= "" and name ~= "" then primary = primary .. separator .. name
	elseif name ~= "" then primary = name end
	local zone = tostring(parts.zone or parts.context or "")
	if zone == "" then return fitText(primary, maxWidth, font) end
	if measuredWidth(primary .. separator .. zone, font) <= maxWidth then
		return primary .. separator .. zone
	end
	local zoneBudget = math.max(0, maxWidth - measuredWidth(primary .. separator, font))
	if zoneBudget > measuredWidth("...", font) then
		return primary .. separator .. fitText(zone, zoneBudget, font)
	end
	return fitText(primary, maxWidth, font)
end

local function statusValue(value)
	if type(value) ~= "table" then return displayValue(value), "textMuted" end
	return displayValue(value), value.tone or "textMuted", value.color
end

local function declarativeHeader(options)
	local source = type(options.header) == "table" and options.header or {}
	local variant = source.variant or options.headerVariant or "default"
	local close = source.close
	if close == nil then close = options.close end
	local contextName = source.contextName or options.contextName or options.headerContext
	local status = source.status or options.liveStatus or options.headerStatus
	local operation = source.operation or options.headerOperation
	local contextVisible = source.contextVisible
	if contextVisible == nil then contextVisible = options.headerContextVisible ~= false end
	local statusVisible = source.statusVisible
	if statusVisible == nil then statusVisible = options.headerStatusVisible ~= false end
	if contextVisible == false then contextName = nil end
	if statusVisible == false then status = nil end
	return {
		productName = source.productName or options.productName or options.title or "",
		titleParts = source.titleParts or options.titleParts,
		contextName = contextName,
		status = status,
		operation = operation,
		variant = variant,
		contextVisible = contextVisible ~= false,
		statusVisible = statusVisible ~= false,
		statusPlacement = source.statusPlacement or options.statusPlacement or "separate",
		statusDot = source.statusDot == true or options.statusDot == true,
		statusDotSize = source.statusDotSize or options.statusDotSize,
		statusDotGap = source.statusDotGap or options.statusDotGap,
		separator = source.separator or options.headerSeparator or " | ",
		close = close,
	}
end

local function declarativeFooter(options)
	local source = type(options.footer) == "table" and options.footer or {}
	local items = source.versions or source.items
	if items == nil then items = options.versions or options.footerItems end
	local visible = source.visible
	if visible == nil then visible = options.footerVisible ~= false end
	return {
		items = items,
		align = source.align or options.footerAlign or "center",
		insetLeft = source.insetLeft or options.footerInsetLeft or 0,
		expandWhenTight = source.expandWhenTight == true or options.footerExpandWhenTight == true,
		separator = source.separator or options.footerSeparator
			or options.headerSeparator or " | ",
		visible = visible,
	}
end

local function composeHeaderText(productName, contextName, separator)
	local product = tostring(productName or "")
	local context = displayValue(contextName, separator)
	if product == "" then return context end
	if context == "" then return product end
	return product .. separator .. context
end

function Window.profile(name, overrides)
	local source = Window.profiles[name or "standard"] or Window.profiles.standard
	local out = {}
	for key, value in pairs(source) do out[key] = value end
	if type(overrides) == "table" then
		for key, value in pairs(overrides) do
			if out[key] ~= nil and tonumber(value) then out[key] = tonumber(value) end
		end
	end
	return out
end

function Window.resolveBounds(options)
	options = options or {}
	local playerNum = math.max(0, math.floor(n(options.playerNum, 0)))
	local safe = SiK.UI.Viewport.safe(playerNum, options.environment,
		n(options.safeMargin, SiK.UI.Metrics.safeMargin))
	local spec = Window.profile(options.profile or "standard", options)
	local maxW = math.min(spec.maxWidth, math.floor(safe.w * spec.capWidth))
	local maxH = math.min(spec.maxHeight, math.floor(safe.h * spec.capHeight))
	maxW = math.max(1, math.min(safe.w, maxW))
	maxH = math.max(1, math.min(safe.h, maxH))
	local minW = math.min(maxW, math.max(1, spec.minWidth))
	local minH = math.min(maxH, math.max(1, spec.minHeight))
	local width = math.max(minW, math.min(maxW, n(options.w or options.width, spec.width)))
	local height = math.max(minH, math.min(maxH, n(options.h or options.height, spec.height)))
	local x = n(options.x, safe.x + math.floor((safe.w - width) / 2))
	local y = n(options.y, safe.y + math.floor((safe.h - height) / 2))
	local clamped = SiK.UI.Viewport.clamp({ x = x, y = y, w = width, h = height },
		playerNum, options.environment, n(options.safeMargin, SiK.UI.Metrics.safeMargin))
	clamped.minWidth, clamped.minHeight = minW, minH
	clamped.maxWidth, clamped.maxHeight = maxW, maxH
	clamped.playerNum = playerNum
	return clamped
end

local constraintKeys = {
	"profile", "minWidth", "minHeight", "maxWidth", "maxHeight",
	"capWidth", "capHeight", "safeMargin", "environment", "playerNum",
}

function Window.updateConstraints(panel, overrides)
	if type(panel) ~= "table" or type(panel._sikWindowOptions) ~= "table" then
		return nil, "not_applied"
	end
	overrides = type(overrides) == "table" and overrides or {}
	local options = panel._sikWindowOptions
	for index = 1, #constraintKeys do
		local key = constraintKeys[index]
		if overrides[key] ~= nil then options[key] = overrides[key] end
	end
	local candidate = {}
	for key, value in pairs(options) do candidate[key] = value end
	candidate.x = overrides.x ~= nil and overrides.x or rectValue(panel, "x", "getX")
	candidate.y = overrides.y ~= nil and overrides.y or rectValue(panel, "y", "getY")
	candidate.w = overrides.w or overrides.width or rectValue(panel, "width", "getWidth")
	candidate.h = overrides.h or overrides.height or rectValue(panel, "height", "getHeight")
	local bounds = Window.resolveBounds(candidate)
	panel._sikBounds = bounds
	panel.playerNum = bounds.playerNum
	panel:setX(bounds.x); panel:setY(bounds.y)
	panel:setSize(bounds.w, bounds.h)
	return panel, bounds
end

function Window.safeRect(playerNum, environment, margin)
	return SiK.UI.Viewport.safe(playerNum or 0, environment,
		n(margin, SiK.UI.Metrics.safeMargin))
end

function Window.resizeHandleRect(panel, size)
	if not panel then return nil end
	size = math.max(6, n(size, 14))
	return { x = panel.width - size, y = panel.height - size, w = size, h = size }
end

function Window.hitTestResizeHandle(panel, x, y, size)
	local rect = Window.resizeHandleRect(panel, size)
	if rect and x >= rect.x and x <= rect.x + rect.w
		and y >= rect.y and y <= rect.y + rect.h then return "bottom-right" end
	return nil
end

function Window.forgetGeometry(key, playerNum)
	if not key then return false end
	return SiK.UI.State.clear(playerNum or 0, key)
end

local function saveGeometry(panel)
	if not panel._sikGeometryKey then return end
	SiK.UI.State.set(panel.playerNum, panel._sikGeometryKey, {
		version = panel._sikGeometryVersion,
		bounds = {
		x = rectValue(panel, "x", "getX"), y = rectValue(panel, "y", "getY"),
		w = rectValue(panel, "width", "getWidth"), h = rectValue(panel, "height", "getHeight"),
	} })
end

local function restoreGeometry(options)
	if not options.geometryKey then options._sikGeometryRestored = false; return options end
	local stored = SiK.UI.State.get(options.playerNum, options.geometryKey)
	if type(stored) ~= "table" or type(stored.bounds) ~= "table" then
		options._sikGeometryRestored = false; return options
	end
	-- A geometry schema belongs to the window contract. A new layout must not
	-- inherit compact bounds persisted by an incompatible release.
	if options.geometryVersion ~= nil and stored.version ~= options.geometryVersion then
		options._sikGeometryRestored = false; return options
	end
	local copy = {}
	for key, value in pairs(options) do copy[key] = value end
	copy.x, copy.y = stored.bounds.x, stored.bounds.y
	copy.w, copy.h = stored.bounds.w, stored.bounds.h
	copy._sikGeometryRestored = true
	return copy
end

function Window.hasOverlap(playerNum, bounds)
	for panel in pairs(liveWindows) do
		if panel.playerNum == playerNum and visible(panel) and overlaps(bounds, {
			x = rectValue(panel, "x", "getX"), y = rectValue(panel, "y", "getY"),
			w = rectValue(panel, "width", "getWidth"), h = rectValue(panel, "height", "getHeight"),
		}) then return true end
	end
	return false
end

function Window.resolveInitialPosition(options, bounds)
	if options._sikInitialPositionResolved == true then return bounds end
	options._sikInitialPositionResolved = true
	if options.cascadeOnOverlap ~= true or options._sikGeometryRestored == true
		or options.positionAnchor ~= nil or options.viewportAnchor ~= nil then return bounds end
	if not Window.hasOverlap(bounds.playerNum, bounds) then return bounds end
	local compact = options.profile == "compact"
	local shifted = { x = bounds.x + (compact and 32 or 54),
		y = bounds.y + (compact and 32 or 48), w = bounds.w, h = bounds.h }
	local clamped = SiK.UI.Viewport.clamp(shifted, bounds.playerNum, options.environment,
		n(options.safeMargin, SiK.UI.Metrics.safeMargin))
	for key, value in pairs(bounds) do if clamped[key] == nil then clamped[key] = value end end
	return clamped
end

function Window.chromeRects(panel)
	if type(panel) ~= "table" then return nil, "invalid_window" end
	local options = panel._sikWindowOptions or {}
	local width = math.max(0, rectValue(panel, "width", "getWidth"))
	local height = math.max(0, rectValue(panel, "height", "getHeight"))
	local pad = math.max(0, n(panel.windowPadding, n(options.padding, 14)))
	local contentPad = math.max(0, n(panel.contentPadding,
		n(options.contentPadding, pad)))
	local headerHeight = math.max(0, n(panel.headerHeight, n(options.headerHeight, 52)))
	local footerHeight = math.max(0, n(panel.footerHeight, 0))
	local closeRect = nil
	local right = width - pad
	if panel.closeControl then
		local closeW = math.max(0, rectValue(panel.closeControl, "width", "getWidth"))
		local closeH = math.max(0, rectValue(panel.closeControl, "height", "getHeight"))
		closeRect = { x = math.max(pad, right - closeW),
			y = math.floor((headerHeight - closeH) / 2), w = closeW, h = closeH }
		right = closeRect.x - pad
	end
	local statusRect = nil
	local operationRect = nil
	local dotRect = nil
	local titleX = pad
	local titleRight = right
	if panel.headerStatusControl then
		local naturalW = math.max(0, n(panel.headerStatusControl._sikNaturalWidth,
			rectValue(panel.headerStatusControl, "width", "getWidth")))
		local statusW = math.min(naturalW, math.max(1, math.floor(width * 0.35)))
		local statusH = math.max(0, rectValue(panel.headerStatusControl, "height", "getHeight"))
		local dotReserve = 0
		local dotSize = 0
		local dotGap = 0
		if panel._sikHeaderStatusDot then
			dotSize = math.max(2, n(panel._sikHeaderStatusDotSize, 6))
			dotGap = math.max(0, n(panel._sikHeaderStatusDotGap, 8))
			dotReserve = dotSize + dotGap
		end
		local groupW = statusW + dotReserve
		local groupX = 0
		if panel._sikHeaderStatusPlacement == "inline" then
			local titleFont = panel.titleControl and panel.titleControl.font or UIFont.Medium or UIFont.Small
			local naturalTitleW = measuredWidth(panel._sikHeaderText, titleFont)
			local opW = 0
			if panel.headerOperationControl then
				opW = math.min(math.max(1, n(panel.headerOperationControl._sikNaturalWidth,
					rectValue(panel.headerOperationControl, "width", "getWidth"))),
					math.max(1, math.floor(width * 0.38)))
			end
			local titleW = math.min(naturalTitleW,
				math.max(0, right - titleX - pad - groupW - (opW > 0 and (pad + opW) or 0)))
			groupX = titleX + titleW + pad
			statusRect = { x = groupX + dotReserve,
				y = math.floor((headerHeight - statusH) / 2), w = statusW, h = statusH }
			titleRight = titleX + titleW
			if panel.headerOperationControl then
				local opH = rectValue(panel.headerOperationControl, "height", "getHeight")
				local opX = groupX + groupW + pad
				operationRect = { x = opX, y = math.floor((headerHeight - opH) / 2),
					w = math.max(1, math.min(opW, right - opX)), h = opH }
			end
		else
			if panel.headerOperationControl then
				local opW = math.min(math.max(1, n(panel.headerOperationControl._sikNaturalWidth,
					rectValue(panel.headerOperationControl, "width", "getWidth"))),
					math.max(1, math.floor(width * 0.38)))
				local opH = rectValue(panel.headerOperationControl, "height", "getHeight")
				operationRect = { x = math.max(titleX, right - opW),
					y = math.floor((headerHeight - opH) / 2), w = opW, h = opH }
				right = operationRect.x - pad
			end
			groupX = math.max(titleX, right - groupW)
			statusRect = { x = groupX + dotReserve,
				y = math.floor((headerHeight - statusH) / 2), w = statusW, h = statusH }
			right = groupX - pad
			titleRight = right
		end
		if dotReserve > 0 then
			dotRect = { x = groupX, y = math.floor((headerHeight - dotSize) / 2),
				w = dotSize, h = dotSize, gap = dotGap }
		end
	end
	if panel.headerOperationControl and not operationRect then
		local opW = math.min(math.max(1, n(panel.headerOperationControl._sikNaturalWidth,
			rectValue(panel.headerOperationControl, "width", "getWidth"))),
			math.max(1, math.floor(width * 0.38)))
		local opH = rectValue(panel.headerOperationControl, "height", "getHeight")
		operationRect = { x = math.max(titleX, right - opW),
			y = math.floor((headerHeight - opH) / 2), w = opW, h = opH }
		titleRight = operationRect.x - pad
	end
	local resizeRect = nil
	if options.resizable ~= false then
		resizeRect = Window.resizeHandleRect(panel, math.max(6, n(options.resizeHandle, 14)))
	end
	local footerSafe = pad
	if resizeRect and footerHeight > 0 then footerSafe = math.max(footerSafe, width - resizeRect.x) end
	local footerInset = math.max(0, n(panel._sikFooterInsetLeft, 0))
	local footerExpanded = false
	-- The resize corner reserves the same safe width at both ends. Keeping the
	-- reservation symmetric preserves the visual centre of centered footers.
	local footerX = footerInset + footerSafe
	local footerW = math.max(0, width - footerInset - footerSafe * 2)
	if footerInset > 0 and panel._sikFooterExpandWhenTight
		and measuredWidth(panel._sikFooterText or "", UIFont.Small) > footerW then
		footerInset = 0
		footerExpanded = true
		footerX = footerSafe
		footerW = math.max(0, width - footerSafe * 2)
	end
	local footerY = math.max(0, height - footerHeight)
	local footerBand = { x = footerInset, y = footerY,
		w = math.max(0, width - footerInset), h = footerHeight }
	local footerRect = { x = footerX, y = footerY,
		w = footerW, h = footerHeight, insetLeft = footerInset,
		expanded = footerExpanded }
	return {
		frame = { x = 0, y = 0, w = width, h = height },
		header = { x = 0, y = 0, w = width, h = headerHeight },
		title = { x = titleX, y = 0, w = math.max(0, titleRight - titleX), h = headerHeight },
		status = statusRect,
		operation = operationRect,
		statusDot = dotRect,
		close = closeRect,
		content = { x = contentPad, y = headerHeight + contentPad,
			w = math.max(0, width - contentPad * 2),
			h = math.max(0, height - headerHeight - footerHeight - contentPad * 2) },
		footer = footerRect,
		footerBand = footerBand,
		resize = resizeRect,
	}
end

local function applyWindowTheme(panel, context)
	local options = panel._sikWindowOptions
	if not options then return end
	panel._sikThemeColors = SiK.UI.Theme.tokens(context)
	local function material(role, parent)
		return SiK.UI.Theme.resolveMaterial(role, parent, options.material, context)
			or SiK.UI.Theme.resolveMaterial(role, parent, nil, context)
	end
	panel._sikMaterial = material("window", nil)
	panel._sikHeaderMaterial = material("header", panel._sikMaterial)
	panel._sikFooterMaterial = material("footer", panel._sikMaterial)
end

function Window.render(panel, phase)
	if type(panel) ~= "table" or type(panel._sikWindowOptions) ~= "table" then
		return nil, "not_applied"
	end
	phase = phase or "all"
	if phase ~= "all" and phase ~= "background" and phase ~= "foreground" then
		return nil, "invalid_phase"
	end
	local rects = Window.chromeRects(panel)
	local theme = panel._sikThemeColors or SiK.UI.Theme.tokens(panel._sikWindowOptions.theme)
	local material = panel._sikMaterial
	local headerMaterial = panel._sikHeaderMaterial
	local footerMaterial = panel._sikFooterMaterial
	if phase ~= "foreground" then
		if SiK.UI.FocusStack.activeWindow(panel.playerNum) == panel then
			-- An outer shadow must not darken the translucent window interior.
			-- Two non-overlapping strips reproduce the unblurred 4px CSS shadow.
			panel:drawRect(rects.frame.w, 4, 4, rects.frame.h, 0.46, 0, 0, 0)
			panel:drawRect(4, rects.frame.h, math.max(0, rects.frame.w - 4), 4,
				0.46, 0, 0, 0)
		end
		local paint = material and material.paint or theme.background
		panel:drawRect(rects.frame.x, rects.frame.y, rects.frame.w, rects.frame.h, paint.a,
			paint.r, paint.g, paint.b)
		paint = headerMaterial and headerMaterial.paint or theme.header
		panel:drawRect(rects.header.x, rects.header.y, rects.header.w, rects.header.h, paint.a,
			paint.r, paint.g, paint.b)
		local edge = panel._sikWindowOptions.accentEdge
		if edge then
			if edge == true then edge = {} end
			local side, size = edge.side or "left", math.max(1, tonumber(edge.width) or 3)
			local color = edge.color or SiK.UI.Theme.color(edge.tone or "accent",
				panel._sikWindowOptions.theme)
			local x, y, w, h = 0, 0, rects.frame.w, rects.frame.h
			if side == "left" then w = size elseif side == "right" then x, w = rects.frame.w - size, size
			elseif side == "top" then h = size elseif side == "bottom" then y, h = rects.frame.h - size, size end
			panel:drawRect(x, y, w, h, tonumber(edge.alpha) or color.a,
				color.r, color.g, color.b)
		end
	end
	if phase ~= "foreground" and rects.statusDot and panel.headerStatusControl then
		panel:drawRect(rects.statusDot.x, rects.statusDot.y, rects.statusDot.w, rects.statusDot.h,
			panel.headerStatusControl.a or 1, panel.headerStatusControl.r or 1,
			panel.headerStatusControl.g or 1, panel.headerStatusControl.b or 1)
	end
	if phase ~= "foreground" and rects.footer.h > 0 and panel._sikFooterText ~= "" then
		local color = SiK.UI.Theme.color("textMuted", panel._sikWindowOptions.theme)
		local y = rects.footer.y
		local footerPaint = footerMaterial and footerMaterial.paint or theme.header
		panel:drawRect(rects.footerBand.x, y, rects.footerBand.w, rects.footerBand.h, footerPaint.a,
			footerPaint.r, footerPaint.g, footerPaint.b)
		panel:drawRect(rects.footerBand.x, y, rects.footerBand.w, 1, theme.border.a,
			theme.border.r, theme.border.g, theme.border.b)
		local footerFont = panel._sikFooterFont or UIFont.Small
		local footerText = fitText(panel._sikFooterText, rects.footer.w, footerFont)
		local x, textY = SiK.UI.Controls.textPosition(rects.footer, footerText, {
			font = footerFont, align = panel._sikFooterAlign,
			verticalAlign = panel._sikFooterVerticalAlign,
		})
		panel._sikFooterDisplayText = footerText
		panel:drawText(footerText, x, textY,
			color.r, color.g, color.b, color.a, footerFont)
	end
	if phase ~= "background" then
		local active = SiK.UI.FocusStack.activeWindow(panel.playerNum) == panel
		local border = active and SiK.UI.Theme.color("accent", panel._sikWindowOptions.theme) or theme.border
		panel:drawRectBorder(rects.frame.x, rects.frame.y, rects.frame.w, rects.frame.h, border.a,
			border.r, border.g, border.b)
		if active then
			panel:drawRectBorder(1, 1, math.max(0, rects.frame.w - 2), math.max(0, rects.frame.h - 2),
				0.54, border.r, border.g, border.b)
		end
	end
	if phase ~= "background" and rects.resize then
		for line = 0, 2 do
			for step = 0, line + 1 do
				panel:drawRect(rects.frame.w - 3 - step * 3,
					rects.frame.h - 3 - (line + 1 - step) * 3, 2, 2,
					theme.border.a, theme.border.r, theme.border.g, theme.border.b)
			end
		end
	end
	return panel
end

function Window.reflow(panel)
	if type(panel) ~= "table" or type(panel._sikWindowOptions) ~= "table" then
		return nil, "not_applied"
	end
	local rects = Window.chromeRects(panel)
	if panel.titleControl then
		if panel._sikHeaderTitleParts then
			panel._sikHeaderText = Window.composeHeaderTitle(panel._sikHeaderTitleParts,
				rects.title.w, UIFont.Medium or UIFont.Small)
			panel.titleControl:setText(panel._sikHeaderText)
		end
		panel.titleControl:setX(rects.title.x); panel.titleControl:setY(rects.title.y)
		panel.titleControl:setWidth(math.max(1, rects.title.w))
		panel.titleControl:setHeight(rects.title.h)
		panel.titleControl:reflow(panel.titleControl.width)
	end
	if panel.headerStatusControl and rects.status then
		panel.headerStatusControl:setX(rects.status.x); panel.headerStatusControl:setY(rects.status.y)
		panel.headerStatusControl:setWidth(rects.status.w); panel.headerStatusControl:setHeight(rects.status.h)
	end
	if panel.headerOperationControl and rects.operation then
		panel.headerOperationControl:setX(rects.operation.x); panel.headerOperationControl:setY(rects.operation.y)
		panel.headerOperationControl:reflow(rects.operation.w, rects.operation.h)
	end
	if panel.closeControl and rects.close then
		panel.closeControl:setX(rects.close.x); panel.closeControl:setY(rects.close.y)
		panel.closeControl:setWidth(rects.close.w); panel.closeControl:setHeight(rects.close.h)
	end
	if type(panel._sikWindowOptions.onReflow) == "function" then
		panel._sikWindowOptions.onReflow(SiK.UI.Namespace.context(panel,
			panel._sikWindowOptions, "reflow", rects.content))
	end
	return panel
end

local function installPointerHandlers(panel)
	local options = panel._sikWindowOptions
	local previousDown, previousMove = panel.onMouseDown, panel.onMouseMove
	local previousMoveOutside = panel.onMouseMoveOutside
	local previousUp, previousOutside = panel.onMouseUp, panel.onMouseUpOutside
	local function globalPointer()
		return type(getMouseX) == "function" and getMouseX() or 0,
			type(getMouseY) == "function" and getMouseY() or 0
	end
	local function pointerPayload(self, phase, pointer, cancelled)
		return {
			phase = phase,
			mode = pointer and pointer.mode or nil,
			cancelled = cancelled == true,
			bounds = { x = self.x, y = self.y, w = self.width, h = self.height },
			content = Window.chromeRects(self).content,
		}
	end
	local function allowed(self, callbackName, phase, pointer)
		local callback = options[callbackName]
		if type(callback) ~= "function" then return true end
		return callback(SiK.UI.Namespace.context(self, options, phase,
			pointerPayload(self, phase, pointer, false))) ~= false
	end
	local function notifyResize(self, callbackName, phase, pointer, cancelled)
		local callback = options[callbackName]
		if type(callback) ~= "function" then return end
		callback(SiK.UI.Namespace.context(self, options, phase,
			pointerPayload(self, phase, pointer, cancelled)))
	end
	local function finishPointer(self, phase, cancelled)
		local active = self._sikPointer
		self._sikPointer = nil
		if self.setCapture then self:setCapture(false) end
		if active and active.mode == "resize" then
			notifyResize(self, "onResizeEnd", phase, active, cancelled)
		end
		if active then saveGeometry(self) end
		return active ~= nil
	end
	local function movePointer(self, phase)
		local active = self._sikPointer
		if not active then return false end
		if not allowed(self, "pointerGuard", phase, active) then
			finishPointer(self, phase, true)
			return true
		end
		local gx, gy = globalPointer()
		if active.mode == "drag" then
			local clamped = SiK.UI.Viewport.clamp({ x = active.wx + gx - active.x,
				y = active.wy + gy - active.y, w = self.width, h = self.height },
				self.playerNum, options.environment, n(options.safeMargin, SiK.UI.Metrics.safeMargin))
			self:setX(clamped.x); self:setY(clamped.y)
		else
			self:setSize(active.w + gx - active.x, active.h + gy - active.y)
			notifyResize(self, "onResize", phase, active, false)
		end
		return true
	end
	local downWrapper = function(self, x, y, ...)
		SiK.UI.FocusStack.activate(self, self.playerNum)
		local gx, gy = globalPointer()
		-- Keep the painted corner compact while exposing a more forgiving input
		-- target. Consumers may tune it independently through resizeHitSize.
		local handle = math.max(n(options.resizeHandle, 14),
			n(options.resizeHitSize, 40))
		local candidate = nil
		if options.resizable ~= false and x >= self.width - handle and y >= self.height - handle then
			candidate = { mode = "resize", x = gx, y = gy, w = self.width, h = self.height }
		elseif options.draggable ~= false and y >= 0 and y <= self.headerHeight then
			candidate = { mode = "drag", x = gx, y = gy, wx = self.x, wy = self.y }
		end
		if candidate and allowed(self, "canStartPointer", "pointerDown", candidate)
			and allowed(self, "pointerGuard", "pointerDown", candidate) then
			self._sikPointer = candidate
			if self.setCapture then self:setCapture(true) end
			return true
		end
		return type(previousDown) == "function" and previousDown(self, x, y, ...) or nil
	end
	local moveWrapper = function(self, ...)
		local result = type(previousMove) == "function" and previousMove(self, ...) or nil
		if movePointer(self, "pointerMove") then return true end
		return result
	end
	local moveOutsideWrapper = function(self, ...)
		local result = type(previousMoveOutside) == "function"
			and previousMoveOutside(self, ...) or nil
		if movePointer(self, "pointerMoveOutside") then return true end
		return result
	end
	local function release(self, ...)
		local previous = type(previousUp) == "function" and previousUp(self, ...) or nil
		local active = self._sikPointer
		local permitted = not active or allowed(self, "pointerGuard", "pointerUp", active)
		if finishPointer(self, "pointerUp", not permitted) then return true end
		return previous
	end
	local outsideWrapper = function(self, ...)
		local previous = type(previousOutside) == "function" and previousOutside(self, ...) or nil
		local active = self._sikPointer
		local permitted = not active or allowed(self, "pointerGuard", "pointerUpOutside", active)
		if finishPointer(self, "pointerUpOutside", not permitted) then return true end
		return previous
	end
	panel.onMouseDown, panel.onMouseMove = downWrapper, moveWrapper
	panel.onMouseMoveOutside = moveOutsideWrapper
	panel.onMouseUp, panel.onMouseUpOutside = release, outsideWrapper
	return function()
		if panel.onMouseDown == downWrapper then panel.onMouseDown = previousDown end
		if panel.onMouseMove == moveWrapper then panel.onMouseMove = previousMove end
		if panel.onMouseMoveOutside == moveOutsideWrapper then
			panel.onMouseMoveOutside = previousMoveOutside
		end
		if panel.onMouseUp == release then panel.onMouseUp = previousUp end
		if panel.onMouseUpOutside == outsideWrapper then panel.onMouseUpOutside = previousOutside end
	end
end

local function installWheelCapture(panel)
	local options = panel._sikWindowOptions
	local previous = panel.onMouseWheel
	local wrapper = function(self, delta, ...)
		local handled = type(previous) == "function" and previous(self, delta, ...) or nil
		if handled == true then return true end
		if options.captureMouseWheel == false then return handled end
		return true
	end
	panel.onMouseWheel = wrapper
	return function()
		if panel.onMouseWheel == wrapper then panel.onMouseWheel = previous end
	end
end

function Window.apply(panel, options)
	if type(panel) ~= "table" then return nil, "invalid_window" end
	if panel._sikWindowApplied then return panel end
	options = restoreGeometry(options or {})
	local bounds = Window.resolveInitialPosition(options, Window.resolveBounds(options))
	panel._sikWindowApplied = true
	panel._sikWindowOptions = options
	options.theme = SiK.UI.Theme.context(options.parent or options.owner or panel.parent,
		options.theme or panel._sikThemeContext, bounds.playerNum)
		or SiK.UI.Theme.context(nil, nil, bounds.playerNum)
	SiK.UI.Theme.bind(panel, options.theme, applyWindowTheme)
	-- Factories keep the window as the real parent and place children with
	-- contentRect(); no second panel owns or duplicates the window chrome.
	panel.panel = panel
	panel.childParent = panel
	panel.playerNum = bounds.playerNum
	panel.headerHeight = math.max(1, n(options.headerHeight, 52))
	-- Window owns this inset once. Children receive contentRect(), never add a
	-- second shell-level margin merely because they are a tab or a modal.
	panel.windowPadding = math.max(0, n(options.padding, 12))
	panel.contentPadding = math.max(0, n(options.contentPadding, panel.windowPadding))
	local header = declarativeHeader(options)
	local footer = declarativeFooter(options)
	local separator = tostring(header.separator)
	panel._sikHeaderTitleParts = header.titleParts
	panel._sikHeaderProduct = tostring(header.productName or "")
	if panel._sikHeaderTitleParts then
		panel._sikHeaderProduct = Window.composeHeaderTitle(panel._sikHeaderTitleParts,
			panel.width - panel.windowPadding * 2, UIFont.Medium or UIFont.Small)
	end
	panel._sikHeaderContext = header.contextName
	panel._sikHeaderSeparator = separator
	panel._sikHeaderText = composeHeaderText(panel._sikHeaderProduct,
		panel._sikHeaderContext, separator)
	panel._sikHeaderVariant = header.variant
	panel._sikHeaderContextVisible = header.contextVisible
	panel._sikHeaderStatusVisible = header.statusVisible
	panel._sikHeaderStatusPlacement = header.statusPlacement == "inline" and "inline" or "separate"
	panel._sikHeaderStatusDot = header.statusDot == true
	panel._sikHeaderStatusDotSize = header.statusDotSize
	panel._sikHeaderStatusDotGap = header.statusDotGap
	panel._sikHeaderOperation = header.operation
	panel._sikFooterItems = footer.items
	panel._sikFooterSeparator = tostring(footer.separator)
	panel._sikFooterText = displayValue(footer.items, panel._sikFooterSeparator)
	panel._sikFooterAlign = footer.align == "left" or footer.align == "right"
		and footer.align or "center"
	panel._sikFooterVerticalAlign = (footer.verticalAlign == "top"
		or footer.verticalAlign == "bottom") and footer.verticalAlign or "middle"
	panel._sikFooterFont = footer.font or UIFont.Small
	panel._sikFooterInsetLeft = math.max(0, n(footer.insetLeft, 0))
	panel._sikFooterExpandWhenTight = footer.expandWhenTight == true
	panel._sikFooterVisible = footer.visible ~= false
	panel._sikFooterAutoHeight = options.footerHeight == nil
	panel._sikFooterFixedHeight = options.footerHeight
	local defaultFooter = panel._sikFooterVisible and panel._sikFooterText ~= ""
		and SiK.UI.Controls.metrics(options.profile).rowHeight or 0
	panel.footerHeight = panel._sikFooterVisible
		and math.max(0, n(options.footerHeight, defaultFooter)) or 0
	panel._sikGeometryKey = options.geometryKey
	panel._sikGeometryVersion = options.geometryVersion
	panel._sikBounds = bounds
	panel:setX(bounds.x); panel:setY(bounds.y)
	panel:setWidth(bounds.w); panel:setHeight(bounds.h)
	-- Window.render owns the one exterior frame and the footer's one interior
	-- divider.  Disable ISPanel's implicit border so it cannot paint a second
	-- seam over either edge.
	panel.drawBorder = false
	panel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	local previousPrerender = panel.prerender
	local prerenderWrapper = function(self)
		Window.render(self, "background")
		if type(previousPrerender) == "function" then previousPrerender(self) end
	end
	panel.prerender = prerenderWrapper
	local previousRender = panel.render
	local renderWrapper = function(self)
		if type(previousRender) == "function" then previousRender(self) end
		Window.render(self, "foreground")
	end
	panel.render = renderWrapper

	panel.titleControl = SiK.UI.Controls.sectionTitle(panel, {
		x = panel.windowPadding, y = 0, w = panel.width - panel.windowPadding * 2,
		h = panel.headerHeight, text = panel._sikHeaderText, playerNum = panel.playerNum,
		font = header.titleFont or options.headerTitleFont or UIFont.Medium or UIFont.Small,
		theme = options.theme,
	})
	local statusText, statusTone, statusColor = statusValue(header.status)
	if statusText ~= "" then
		local statusWidth = measuredWidth(statusText, UIFont.Small)
		panel.headerStatusControl = SiK.UI.Controls.status(panel, {
			x = 0, y = 0, w = statusWidth,
			h = SiK.UI.Controls.metrics(options.profile).fontHeight,
			text = statusText, tone = statusTone, color = statusColor,
			playerNum = panel.playerNum,
			theme = options.theme,
		})
		panel.headerStatusControl:setWidth(statusWidth)
		panel.headerStatusControl._sikNaturalWidth = statusWidth
	end
	if type(header.operation) == "table" then
		panel.headerOperationControl = SiK.UI.Controls.headerOperation(panel, {
			x = 0, y = 0, label = header.operation.label or header.operation.text,
			value = header.operation.value, status = header.operation.status,
			tone = header.operation.tone, mode = header.operation.mode,
			showProgress = header.operation.showProgress,
			progressWidth = header.operation.progressWidth, playerNum = panel.playerNum, theme = options.theme,
		})
	end
	local closeSpec = type(header.close) == "table" and header.close or {}
	local closeVisible = options.closable ~= false and header.close ~= false
		and closeSpec.visible ~= false
	if closeVisible then
		local size = math.max(20, n(closeSpec.size or options.closeSize, 32))
		panel.closeControl = SiK.UI.Controls.iconButton(panel, {
			x = 0, y = 0, w = size, h = size,
			icon = closeSpec.icon or options.closeIcon or "sik.close.18",
			text = "",
			tooltip = closeSpec.tooltip or options.closeTooltip,
			playerNum = panel.playerNum, theme = options.theme,
			onClick = function() panel:close("button") end,
		})
	end

	local cleanupPointer = installPointerHandlers(panel)
	local cleanupWheel = installWheelCapture(panel)
	-- Passive controls occupy part of the header and therefore receive the
	-- pointer before the owning Window. Relay them through the same common
	-- pointer contract so title/status chrome never disables drag. Interactive
	-- controls (close and future actions) deliberately remain independent.
	local function relayPassiveHeaderPointer(control)
		if not control then return end
		control.onMouseDown = function(self, x, y, ...)
			return panel:onMouseDown(x + (self.x or 0), y + (self.y or 0), ...)
		end
		control.onMouseMove = function(_, ...)
			return panel:onMouseMove(...)
		end
		control.onMouseMoveOutside = function(_, ...)
			return panel:onMouseMoveOutside(...)
		end
		control.onMouseUp = function(_, ...)
			return panel:onMouseUp(...)
		end
		control.onMouseUpOutside = function(_, ...)
			return panel:onMouseUpOutside(...)
		end
	end
	relayPassiveHeaderPointer(panel.titleControl)
	relayPassiveHeaderPointer(panel.headerStatusControl)
	relayPassiveHeaderPointer(panel.headerOperationControl)
	local focusLayer = nil
	if options.closeOnEscape ~= false then
		focusLayer = SiK.UI.FocusStack.install(panel, function()
			panel:close("escape"); return true
		end, { playerNum = panel.playerNum, priority = n(options.focusPriority, 50) })
	end
	function panel:contentRect() return Window.chromeRects(self).content end
	function panel:setHeader(spec, contextName)
		if type(spec) == "table" then
			if spec.titleParts ~= nil then self._sikHeaderTitleParts = spec.titleParts end
			if spec.productName ~= nil then self._sikHeaderProduct = tostring(spec.productName) end
			if spec.contextName ~= nil then self._sikHeaderContext = spec.contextName end
			if spec.contextVisible ~= nil then
				self._sikHeaderContextVisible = spec.contextVisible ~= false
				if not self._sikHeaderContextVisible then self._sikHeaderContext = nil end
			end
			if spec.separator ~= nil then self._sikHeaderSeparator = tostring(spec.separator) end
			if spec.variant ~= nil then self._sikHeaderVariant = tostring(spec.variant) end
			if spec.statusPlacement ~= nil then
				self._sikHeaderStatusPlacement = spec.statusPlacement == "inline" and "inline" or "separate"
			end
			if spec.statusDot ~= nil then self._sikHeaderStatusDot = spec.statusDot == true end
			if spec.statusDotSize ~= nil then self._sikHeaderStatusDotSize = spec.statusDotSize end
			if spec.statusDotGap ~= nil then self._sikHeaderStatusDotGap = spec.statusDotGap end
			if spec.statusVisible ~= nil then
				self._sikHeaderStatusVisible = spec.statusVisible ~= false
				if not self._sikHeaderStatusVisible then self:setHeaderStatus(nil) end
			end
			if spec.status ~= nil and self._sikHeaderStatusVisible ~= false then
				self:setHeaderStatus(spec.status)
			end
			if spec.operation ~= nil then
				self:setHeaderOperation(spec.operation ~= false and spec.operation or nil)
			end
		else
			self._sikHeaderProduct = tostring(spec or "")
			if contextName ~= nil then self._sikHeaderContext = contextName end
		end
		if self._sikHeaderTitleParts then
			self._sikHeaderProduct = Window.composeHeaderTitle(self._sikHeaderTitleParts,
				self.width - self.windowPadding * 2, UIFont.Medium or UIFont.Small)
			self._sikHeaderContext = nil
		end
		self._sikHeaderText = composeHeaderText(self._sikHeaderProduct,
			self._sikHeaderContext, self._sikHeaderSeparator)
		if self.titleControl then self.titleControl:setText(self._sikHeaderText) end
		Window.reflow(self)
		return self
	end
	function panel:setHeaderOperation(spec)
		if spec == nil then
			if self.headerOperationControl then self.headerOperationControl:dispose(); self.headerOperationControl = nil end
		else
			if not self.headerOperationControl then
				self.headerOperationControl = SiK.UI.Controls.headerOperation(self, { label = spec.label or spec.text,
					value = spec.value, status = spec.status, tone = spec.tone, mode = spec.mode,
					showProgress = spec.showProgress,
					progressWidth = spec.progressWidth,
					playerNum = self.playerNum, theme = self._sikWindowOptions.theme })
				relayPassiveHeaderPointer(self.headerOperationControl)
			else self.headerOperationControl:setOperation(spec) end
		end
		Window.reflow(self); return self
	end
	function panel:setProductName(value)
		self._sikHeaderProduct = tostring(value or "")
		return self:setHeader({})
	end
	function panel:setContextName(value)
		self._sikHeaderContext = value
		return self:setHeader({})
	end
	function panel:setHeaderStatus(value, tone, color)
		local text, nextTone, nextColor = statusValue(value)
		if tone ~= nil then nextTone = tone end
		if color ~= nil then nextColor = color end
		if text == "" then
			if self.headerStatusControl then
				self.headerStatusControl:dispose(); self.headerStatusControl = nil
			end
			Window.reflow(self); return self
		end
		local width = measuredWidth(text, UIFont.Small)
		if not self.headerStatusControl then
			self.headerStatusControl = SiK.UI.Controls.status(self, {
				x = 0, y = 0, w = width,
				h = SiK.UI.Controls.metrics(options.profile).fontHeight,
				text = text, tone = nextTone, color = nextColor,
				playerNum = self.playerNum, theme = options.theme,
			})
			relayPassiveHeaderPointer(self.headerStatusControl)
		else
			self.headerStatusControl:setStatus(text, nextTone, nextColor)
		end
		self.headerStatusControl:setWidth(width)
		self.headerStatusControl._sikNaturalWidth = width
		Window.reflow(self)
		return self
	end
	function panel:setFooterItems(items, align)
		self._sikFooterItems = items
		self._sikFooterText = displayValue(items, self._sikFooterSeparator)
		self._sikFooterDisplayText = ""
		if align == "left" or align == "right" or align == "center" then
			self._sikFooterAlign = align
		end
		if self._sikFooterAutoHeight then
			self.footerHeight = self._sikFooterVisible and self._sikFooterText ~= ""
				and SiK.UI.Controls.metrics(options.profile).rowHeight or 0
		end
		Window.reflow(self)
		return self
	end
	function panel:setVersions(versions) return self:setFooterItems(versions, "center") end
	function panel:setFooterVisible(value)
		self._sikFooterVisible = value ~= false
		if not self._sikFooterVisible then self._sikFooterDisplayText = "" end
		if self._sikFooterAutoHeight then
			self.footerHeight = self._sikFooterVisible and self._sikFooterText ~= ""
				and SiK.UI.Controls.metrics(options.profile).rowHeight or 0
		else
			self.footerHeight = self._sikFooterVisible
				and math.max(0, n(self._sikFooterFixedHeight, 0)) or 0
		end
		Window.reflow(self)
		return self
	end
	function panel:setSize(width, height)
		local limits = self._sikBounds or bounds
		local current = SiK.UI.Viewport.clamp({ x = self.x, y = self.y,
			w = math.max(limits.minWidth, math.min(limits.maxWidth, n(width, self.width))),
			h = math.max(limits.minHeight, math.min(limits.maxHeight, n(height, self.height))) },
			self.playerNum, options.environment, n(options.safeMargin, SiK.UI.Metrics.safeMargin))
		self:setX(current.x); self:setY(current.y)
		self:setWidth(current.w); self:setHeight(current.h)
		Window.reflow(self)
		return self
	end
	function panel:updateConstraints(overrides)
		return Window.updateConstraints(self, overrides)
	end
	function panel:reflow() Window.reflow(self); return self end
	function panel:show()
		if self.addToUIManager then self:addToUIManager() end
		if self.setVisible then self:setVisible(true) end
		if self.bringToTop then self:bringToTop() end
		liveWindows[self] = true
		SiK.UI.FocusStack.activate(self, self.playerNum)
		return self
	end
	function panel:hide()
		if self.setVisible then self:setVisible(false) end
		if self.setCapture then self:setCapture(false) end
		self._sikPointer = nil
		saveGeometry(self)
		return self
	end
	function panel:close(reason)
		if self._sikClosing then return false end
		self._sikClosing = true
		local allow = true
		if type(options.onClose) == "function" then
			local result = options.onClose(SiK.UI.Namespace.context(self, options, "close", reason))
			if result == false then allow = false end
		end
		self._sikClosing = false
		if not allow then return false end
		if options.disposeOnClose == false then self:hide() else self:dispose() end
		return true
	end
	local previousDispose = panel.dispose
	function panel:dispose()
		if self._sikDisposed then return false end
		self._sikDisposed = true
		liveWindows[self] = nil
		SiK.UI.Theme.bind(self, nil)
		self._sikThemeColors = nil
		saveGeometry(self)
		if focusLayer then focusLayer:dispose(); focusLayer = nil end
		cleanupPointer()
		cleanupWheel()
		if self.closeControl then self.closeControl:dispose(); self.closeControl = nil end
		if self.headerStatusControl then self.headerStatusControl:dispose(); self.headerStatusControl = nil end
		if self.headerOperationControl then self.headerOperationControl:dispose(); self.headerOperationControl = nil end
		if self.titleControl then self.titleControl:dispose(); self.titleControl = nil end
		self._sikHeaderProduct, self._sikHeaderContext = nil, nil
		self._sikHeaderText, self._sikFooterText = "", ""
		self._sikFooterItems, self._sikWindowOptions = nil, nil
		if self.prerender == prerenderWrapper then self.prerender = previousPrerender end
		if self.render == renderWrapper then self.render = previousRender end
		if type(previousDispose) == "function" and previousDispose ~= self.dispose then
			pcall(previousDispose, self)
		end
		if self.removeFromUIManager then self:removeFromUIManager() end
		return true
	end
	Window.reflow(panel)
	return panel
end

function Window.create(options)
	options = restoreGeometry(options or {})
	-- apply owns the one initial cascade; resolving it here would consume the
	-- marker and then recompute unshifted bounds when applying the chrome.
	local bounds = Window.resolveBounds(options)
	local panel = ISPanel:new(bounds.x, bounds.y, bounds.w, bounds.h)
	panel:initialise()
	if panel.instantiate then panel:instantiate() end
	return Window.apply(panel, options)
end

-- Construye la instancia base de una clase derivada sin adelantar initialise,
-- createChildren ni Window.apply. El consumidor conserva el lifecycle de su
-- clase, pero nunca necesita crear directamente la primitiva ISPanel.
function Window.newInstance(class, x, y, width, height)
	local panel = ISPanel:new(n(x, 0), n(y, 0), math.max(1, n(width, 1)),
		math.max(1, n(height, 1)))
	if class then
		setmetatable(panel, class)
		class.__index = class
	end
	return panel
end

function Window.applyEditor(panel, options)
	options = options or {}; options.profile = options.profile or "editor"
	return Window.apply(panel, options)
end

return Window
