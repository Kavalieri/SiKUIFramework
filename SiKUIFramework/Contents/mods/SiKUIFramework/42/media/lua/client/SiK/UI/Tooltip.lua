require "SiK/UI/Namespace"
require "SiK/UI/Viewport"
require "SiK/UI/Theme"
require "SiK/UI/Metrics"
require "SiK/UI/Scroll"
require "SiK/UI/FocusStack"
require "ISUI/ISPanel"

local Tooltip = SiK.UI.Tooltip or {}
SiK.UI.Namespace.define("Tooltip", Tooltip)
Tooltip._transientChannels = Tooltip._transientChannels or {}

local function colorValue(value, fallback)
	if type(value) ~= "table" then return fallback end
	return {
		r = tonumber(value.r or value[1]) or fallback.r,
		g = tonumber(value.g or value[2]) or fallback.g,
		b = tonumber(value.b or value[3]) or fallback.b,
		a = tonumber(value.a or value[4]) or fallback.a,
	}
end

local function wrap(value, width, font)
        local text, lines, current = tostring(value or ""), {}, ""
        local manager = type(getTextManager) == "function" and getTextManager() or nil
	local function fits(candidate)
                if not manager or not manager.MeasureStringX then return #candidate * 8 <= width end
                return manager:MeasureStringX(font, candidate) <= width
        end
        local function appendLongToken(token)
                local chunk, index = "", 1
                while index <= #token do
                        local first = string.byte(token, index) or 0
                        local byteCount = first >= 240 and 4 or first >= 224 and 3
                                or first >= 192 and 2 or 1
                        local character = string.sub(token, index,
                                math.min(#token, index + byteCount - 1))
                        local candidate = chunk .. character
                        if chunk ~= "" and not fits(candidate) then
                                lines[#lines + 1], chunk = chunk, character
                        else
                                chunk = candidate
                        end
                        index = index + byteCount
                end
                return chunk
        end
        for word in text:gmatch("%S+") do
                local candidate = current == "" and word or current .. " " .. word
                if current ~= "" and not fits(candidate) then
                        lines[#lines + 1], current = current, ""
                end
                if current == "" and not fits(word) then current = appendLongToken(word)
                else current = current == "" and word or current .. " " .. word end
        end
	if current ~= "" or #lines == 0 then lines[#lines + 1] = current end
	return lines
end

local function sectionLines(section, width, font)
	local lines = {}
	local function append(value)
		for _, line in ipairs(wrap(value, width, font)) do
			lines[#lines + 1] = line
		end
	end
	if type(section.lines) == "table" then
		for _, value in ipairs(section.lines) do append(value) end
	elseif section.text ~= nil then append(section.text) end
	return lines
end

function Tooltip.measureSection(section, width, options)
	section, options = section or {}, options or {}
	local tokens = SiK.UI.Metrics.tokens(options.tokens or section.tokens)
	local font = options.font or section.font or UIFont.Small
	local padding = tonumber(options.padding or section.padding) or tokens.spacing.sm
	local paddingX = tonumber(options.paddingX or section.paddingX) or padding
	local paddingY = tonumber(options.paddingY or section.paddingY) or padding
	local gap = tonumber(options.gap or section.gap) or tokens.spacing.xxs
	local manager = type(getTextManager) == "function" and getTextManager() or nil
	local lineHeight = manager and manager.getFontHeight and manager:getFontHeight(font) or 18
	local innerWidth = math.max(1, (tonumber(width) or 240) - paddingX * 2)
	local title = tostring(section.title or "")
	local lines = sectionLines(section, innerWidth, font)
	local height = paddingY * 2 + #lines * lineHeight
	if title ~= "" then height = height + lineHeight + (#lines > 0 and gap or 0) end
	return { width = tonumber(width) or 240, height = height, innerWidth = innerWidth,
		padding = padding, paddingX = paddingX, paddingY = paddingY, gap = gap,
		lineHeight = lineHeight, title = title, lines = lines, font = font }
end

-- Object sections are data for an already-owned InventoryItem tooltip host.
-- They never create an informational panel or invoke the vanilla renderer.
function Tooltip.objectSection(lines, options)
	options = options or {}
	local section = {}
	for key, value in pairs(options) do section[key] = value end
	section.kind = "object"
	if type(lines) == "table" then section.lines = lines
	else section.text = lines end
	return section
end

function Tooltip.renderFrame(panel, x, y, width, height, options)
	if type(panel) ~= "table" then return nil, "invalid_panel" end
	options = options or {}
	local theme = SiK.UI.Theme.tokens(options.theme)
	local background = colorValue(options.backgroundColor, theme.surface)
	local border = colorValue(options.borderColor, theme.border)
	x, y = tonumber(x) or 0, tonumber(y) or 0
	width, height = math.max(0, tonumber(width) or 0), math.max(0, tonumber(height) or 0)
	if panel.drawRect then
		panel:drawRect(x, y, width, height, background.a,
			background.r, background.g, background.b)
	end
	if options.border ~= false and panel.drawRectBorder then
		panel:drawRectBorder(x, y, width, height, border.a,
			border.r, border.g, border.b)
	end
	return { x = x, y = y, width = width, height = height,
		backgroundColor = background, borderColor = border }
end

function Tooltip.renderSection(panel, section, x, y, width, options)
	if type(panel) ~= "table" then return nil, "invalid_panel" end
	section, options = section or {}, options or {}
	local measured = Tooltip.measureSection(section, width, options)
	local theme = SiK.UI.Theme.tokens(options.theme or section.theme)
	local tone = section.tone or options.tone or "text"
	local color = SiK.UI.Theme.color(tone, options.theme or section.theme)
	local lineColor = colorValue(section.lineColor or options.lineColor, theme.text)
	if section.framed ~= false then
		Tooltip.renderFrame(panel, x, y, measured.width, measured.height, {
			theme = options.theme or section.theme,
			backgroundColor = section.backgroundColor or options.backgroundColor,
			borderColor = section.borderColor or options.borderColor,
			border = section.border ~= false and options.border ~= false,
		})
	end
	local cursor = y + measured.paddingY
	local align = section.align or options.align
	local function draw(value, drawY, drawColor)
		if align == "right" and panel.drawTextRight then
			panel:drawTextRight(value, x + measured.width - measured.paddingX, drawY,
				drawColor.r, drawColor.g, drawColor.b, drawColor.a, measured.font)
		else
			panel:drawText(value, x + measured.paddingX, drawY,
				drawColor.r, drawColor.g, drawColor.b, drawColor.a, measured.font)
		end
	end
	if measured.title ~= "" then
		draw(measured.title, cursor, color)
		cursor = cursor + measured.lineHeight + (#measured.lines > 0 and measured.gap or 0)
	end
	for _, line in ipairs(measured.lines) do
		draw(line, cursor, lineColor)
		cursor = cursor + measured.lineHeight
	end
	return measured
end

function Tooltip.appendSection(target, section, options)
	if type(target) ~= "table" then return nil, "invalid_target" end
	local sections = target.sections or target._sikTooltipSections
	if type(sections) ~= "table" then sections = {}; target._sikTooltipSections = sections end
	sections[#sections + 1] = section or {}
	local entry, disposed = sections[#sections], false
	local handle = { target = target, section = entry, options = options or {} }
	function handle:dispose()
		if disposed then return false end
		disposed = true
		for index = #sections, 1, -1 do
			if sections[index] == entry then table.remove(sections, index); break end
		end
		return true
	end
	return handle
end

local function sectionsOf(target)
	if type(target) ~= "table" then return nil end
	if type(target.sections) == "table" then return target.sections end
	if type(target._sikTooltipSections) ~= "table" then target._sikTooltipSections = {} end
	return target._sikTooltipSections
end

function Tooltip.clearSections(target)
	local sections = sectionsOf(target)
	if not sections then return nil, "invalid_target" end
	for index = #sections, 1, -1 do sections[index] = nil end
	return target
end

function Tooltip.setSections(target, nextSections)
	local sections = sectionsOf(target)
	if not sections then return nil, "invalid_target" end
	if nextSections ~= nil and type(nextSections) ~= "table" then
		return nil, "invalid_sections"
	end
	local snapshot = {}
	for index = 1, #(nextSections or {}) do snapshot[index] = nextSections[index] end
	Tooltip.clearSections(target)
	for index = 1, #snapshot do sections[index] = snapshot[index] end
	return target
end

function Tooltip.measureSections(target, width, options)
	local sections = sectionsOf(target)
	if not sections then return nil, "invalid_target" end
	options = options or {}
	local tokens = SiK.UI.Metrics.tokens(options.tokens)
	local sectionGap = tonumber(options.sectionGap) or tokens.spacing.xs
	local measured, height = {}, 0
	for index = 1, #sections do
		measured[index] = Tooltip.measureSection(sections[index], width, options)
		height = height + measured[index].height
		if index < #sections then height = height + sectionGap end
	end
	return { width = tonumber(width) or 240, height = height,
		sectionGap = sectionGap, sections = measured }
end

function Tooltip.renderSections(panel, target, x, y, width, options)
	if type(panel) ~= "table" then return nil, "invalid_panel" end
	local sections = sectionsOf(target)
	if not sections then return nil, "invalid_target" end
	local measured = Tooltip.measureSections(target, width, options)
	local cursor = y
	for index = 1, #sections do
		Tooltip.renderSection(panel, sections[index], x, cursor, measured.width, options)
		cursor = cursor + measured.sections[index].height + measured.sectionGap
	end
	return measured
end

function Tooltip.createDocument(options)
	options = options or {}
	local document = { sections = {}, options = options, _sikTooltipDocument = true }
	function document:append(section)
		if self.disposed then return nil, "disposed" end
		return Tooltip.appendSection(self, section, self.options)
	end
	function document:set(sections)
		if self.disposed then return nil, "disposed" end
		return Tooltip.setSections(self, sections)
	end
	function document:clear()
		if self.disposed then return nil, "disposed" end
		return Tooltip.clearSections(self)
	end
	function document:measure(width, overrides)
		if self.disposed then return nil, "disposed" end
		return Tooltip.measureSections(self, width, overrides or self.options)
	end
	function document:render(panel, x, y, width, overrides)
		if self.disposed then return nil, "disposed" end
		return Tooltip.renderSections(panel, self, x, y, width, overrides or self.options)
	end
	function document:dispose()
		if self.disposed then return false end
		Tooltip.clearSections(self); self.disposed = true
		return true
	end
	if options.sections then Tooltip.setSections(document, options.sections) end
	return document
end

local function callPrevious(callback, self, ...)
	if type(callback) ~= "function" then return nil end
	return callback(self, ...)
end

local function setPassive(widget)
	if not widget then return end
	if widget.javaObject and widget.javaObject.setConsumeMouseEvents then
		widget.javaObject:setConsumeMouseEvents(false)
	end
	if widget.tooltip and widget.tooltip.javaObject
		and widget.tooltip.javaObject.setConsumeMouseEvents then
		widget.tooltip.javaObject:setConsumeMouseEvents(false)
	end
end

function Tooltip.makePassive(widget)
	if not widget then return nil, "invalid_tooltip" end
	setPassive(widget)
	for _, name in ipairs({ "onMouseDown", "onMouseUp", "onMouseUpOutside",
		"onMouseDownOutside", "onMouseMove", "onMouseMoveOutside",
		"onRightMouseDown", "onRightMouseUp" }) do
		widget[name] = function() return false end
	end
	widget._sikUiTooltip = true
	return widget
end

function Tooltip.pointerPosition(width, height, playerNum, gap, environment)
	local proxy = { width = tonumber(width) or 0, height = tonumber(height) or 0 }
	local x, y = Tooltip.position(proxy, playerNum, gap, environment)
	return x, y
end

function Tooltip.position(widget, playerNum, gap, environment)
	if not widget then return nil, "invalid_tooltip" end
	local mx = type(getMouseX) == "function" and getMouseX() or 0
	local my = type(getMouseY) == "function" and getMouseY() or 0
	local safe = SiK.UI.Viewport.safe(playerNum, environment, 0)
	local width = tonumber(widget.width) or (widget.getWidth and widget:getWidth()) or 0
	local height = tonumber(widget.height) or (widget.getHeight and widget:getHeight()) or 0
	gap = math.max(0, tonumber(gap) or 16)
	local x, y = mx + gap, my + gap
	if x + width > safe.x + safe.w then x = mx - width - gap end
	if y + height > safe.y + safe.h then y = my - height - gap end
	x = math.max(safe.x, math.min(x, safe.x + safe.w - width))
	y = math.max(safe.y, math.min(y, safe.y + safe.h - height))
	if widget.setX then widget:setX(x) else widget.x = x end
	if widget.setY then widget:setY(y) else widget.y = y end
	return x, y
end

function Tooltip.hide(widget)
	if not widget then return false end
	if widget.setVisible then widget:setVisible(false) end
	if widget.removeFromUIManager then widget:removeFromUIManager() end
	return true
end

function Tooltip.anchorToPointer(widget, playerNum, gap, environment)
	if not widget then return nil, "invalid_tooltip" end
	widget.followMouse = true
	widget.anchorBottomLeft = nil
	return Tooltip.position(widget, playerNum, gap, environment)
end

local function transientNow(options)
	if type(options.clock) == "function" then return tonumber(options.clock()) or 0 end
	if type(getTimestampMs) == "function" then return tonumber(getTimestampMs()) or 0 end
	if type(getTimestamp) == "function" then return (tonumber(getTimestamp()) or 0) * 1000 end
	return os.clock() * 1000
end

local function controlRect(control)
	local x = control.getAbsoluteX and control:getAbsoluteX()
		or control.getX and control:getX() or control.x or 0
	local y = control.getAbsoluteY and control:getAbsoluteY()
		or control.getY and control:getY() or control.y or 0
	local w = control.getWidth and control:getWidth() or control.width or 0
	local h = control.getHeight and control:getHeight() or control.height or 0
	return tonumber(x) or 0, tonumber(y) or 0, tonumber(w) or 0, tonumber(h) or 0
end

local function placeTransient(widget, control, options)
	local placement = options.placement or {}
	-- A scrollable descriptive document must be reachable by pointer.  It is the
	-- sole transient that deliberately switches from the ordinary pointer anchor
	-- to a touching control-adjacent edge.
	if widget and widget._sikTooltipScrollable then
		placement = { anchor = "control", side = placement.side or "after", gap = 0 }
	end
	-- Pointer placement is the framework default for ordinary controls and
	-- informational help.  A body/rail flyout must ask for its control anchor.
	if placement.anchor ~= "control" or not control then
		return Tooltip.position(widget, options.playerNum or 0,
				placement.gap or options.gap, options.environment)
	end
	local safe = SiK.UI.Viewport.safe(options.playerNum or 0, options.environment, 0)
	local cx, cy, cw, ch = controlRect(control)
	local width = widget.getWidth and widget:getWidth() or widget.width or 0
	local height = widget.getHeight and widget:getHeight() or widget.height or 0
	local gap = math.max(0, tonumber(placement.gap or options.gap) or 4)
	local side = placement.side or "after"
	local function coordinates(which)
		if which == "before" then return cx - width - gap, cy end
		if which == "above" then return cx, cy - height - gap end
		if which == "below" then return cx, cy + ch + gap end
		return cx + cw + gap, cy
	end
	local function fits(x, y)
		return x >= safe.x and y >= safe.y
			and x + width <= safe.x + safe.w and y + height <= safe.y + safe.h
	end
	local x, y = coordinates(side)
	if not fits(x, y) then
		local opposite = side == "before" and "after"
			or (side == "above" and "below" or (side == "below" and "above" or "before"))
		local oppositeX, oppositeY = coordinates(opposite)
		if fits(oppositeX, oppositeY) then x, y = oppositeX, oppositeY end
	end
	x = math.max(safe.x, math.min(x, safe.x + safe.w - width))
	y = math.max(safe.y, math.min(y, safe.y + safe.h - height))
	if widget.setX then widget:setX(x) else widget.x = x end
	if widget.setY then widget:setY(y) else widget.y = y end
	return x, y
end

local function transientPanel(options)
	local content = options.content or {}
	if type(content) ~= "table" then content = { text = content } end
	local safe = SiK.UI.Viewport.safe(options.playerNum or 0, options.environment, 0)
	local kind = options.kind or "descriptive"
	-- Profile remains a compatibility geometry input only. It does not choose a
	-- class: older compact/omitted calls stay 320 wide, informational stays 680.
	local informational = options.profile == "informational"
	local defaultWidth = informational and 680 or 320
	local viewportMargin = informational and 32 or 0
	local availableWidth = math.max(1, safe.w - viewportMargin)
	local requestedWidth
	if kind == "brief" then
		local text = tostring(content.text or options.text or "")
		local font = content.font or options.font or UIFont.Small
		local manager = type(getTextManager) == "function" and getTextManager() or nil
		local textWidth = manager and manager.MeasureStringX
			and manager:MeasureStringX(font, text) or #text * 8
		local paddingX = math.max(0, tonumber(content.paddingX or options.paddingX) or 8)
		requestedWidth = textWidth + paddingX * 2
	else
		requestedWidth = math.max(120, tonumber(options.maxWidth) or defaultWidth)
	end
	-- briefTextFits has already rejected a width outside this safe rectangle;
	-- never clamp a valid brief into a wrapped layout.
	local width = kind == "brief" and requestedWidth
		or math.max(1, math.min(requestedWidth, availableWidth))
	local sourceSections = options.sections or { {
		title = content.title, text = content.text or options.text,
		tone = content.tone or options.tone, framed = false,
		font = content.font or options.font,
		paddingX = content.paddingX or options.paddingX,
		paddingY = content.paddingY or options.paddingY,
		align = kind == "brief" and "right" or content.align,
	} }
	local sections = {}
	for index = 1, #sourceSections do
		sections[index] = {}
		for key, value in pairs(sourceSections[index]) do sections[index][key] = value end
	end
	local document = Tooltip.createDocument({ sections = sections })
	local measured = document:measure(width)
	local height = math.min(measured.height, math.max(1, math.min(safe.h,
		tonumber(options.maxHeight) or safe.h)))
	local scrollable = kind == "descriptive" and measured.height > height
	local contentRect, trackRect
	local outerWidth = measured.width
	if scrollable then
		-- Use the already-approved Scroll geometry inside the tooltip frame. Its
		-- gutter reduces the actual text width, so measure once again before the
		-- content height is supplied to Scroll; the Scroll region owns the one
		-- canonical 8 px inset, so the document must not apply it twice.
		contentRect, trackRect = SiK.UI.Metrics.blockRects(outerWidth, height, true, 0, 0)
		for index = 1, #document.sections do
			document.sections[index].paddingX, document.sections[index].paddingY = 0, 0
		end
		measured = document:measure(contentRect.w)
	end
	local panel = ISPanel:new(0, 0, outerWidth, height)
	panel:initialise()
	panel._sikTooltipDocument = document
	panel._sikTooltipSafe = { x = safe.x, y = safe.y, w = safe.w, h = safe.h }
	panel._sikTooltipScrollable = scrollable
	if scrollable then
		local scroll = SiK.UI.Scroll.create({ parent = panel, viewportRect = contentRect,
			trackRect = trackRect, contentHeight = measured.height,
			playerNum = options.playerNum or 0 })
		if scroll then
			local host = SiK.UI.Scroll.childHost(scroll)
			panel._sikTooltipScroll = scroll
			panel._sikTooltipScrollHost = host
			host.prerender = function(self)
				document:render(self, 0, 0, contentRect.w,
					{ backgroundColor = { a = 0 }, border = false })
			end
		else
			-- An overflow document without its Scroll host cannot remain accessible.
			-- Dispose the unattached partial panel and propagate a deterministic
			-- construction failure instead of rendering outside the safe viewport.
			document:dispose()
			if panel.dispose then panel:dispose() end
			return nil, "scroll_unavailable"
		end
	end
	panel.prerender = function(self)
		local frameOptions = options
		if kind == "brief" and options.backgroundColor == nil then
			local theme = SiK.UI.Theme.tokens(options.theme)
			frameOptions = {
				theme = options.theme,
				backgroundColor = { r = theme.surface.r, g = theme.surface.g,
					b = theme.surface.b, a = 0.72 },
				borderColor = options.borderColor,
				border = options.border,
			}
		end
		Tooltip.renderFrame(self, 0, 0, self.width, self.height, frameOptions)
		if not self._sikTooltipScrollable then
			document:render(self, 0, 0, self.width, { backgroundColor = { a = 0 }, border = false })
		end
	end
	local previousDispose = panel.dispose
	panel.dispose = function(self)
		if self._sikDisposed then return false end
		self._sikDisposed = true
		if self._sikTooltipFocus and self._sikTooltipFocus.dispose then
			self._sikTooltipFocus:dispose()
		end
		if self._sikTooltipScroll and self._sikTooltipScroll.dispose then
			self._sikTooltipScroll:dispose()
		end
		document:dispose()
		if type(previousDispose) == "function" then previousDispose(self) end
		return true
	end
	return panel
end

-- A caller-owned annex can reuse the approved Tooltip + Scroll document
-- without turning its native host into a descriptive tooltip. Geometry and
-- source identity are supplied by the caller; no product objects are retained.
function Tooltip.createScrollableSections(options)
	options = type(options) == "table" and options or {}
	local handle = { playerNum = tonumber(options.playerNum) or 0 }
	local key, sections, bounds, closedKey
	local function release()
		local panel = handle.panel
		if not panel then return end
		Tooltip.hide(panel)
		panel:dispose()
		handle.panel = nil
	end
	function handle:hide()
		release()
		return true
	end
	function handle:close()
		closedKey = key
		release()
		if type(options.onClose) == "function" then options.onClose(self) end
		return true
	end
	function handle:isPointerOver()
		local panel = self.panel
		if not panel or not getMouseX or not getMouseY then return false end
		if panel.isVisible and not panel:isVisible() then return false end
		if panel.visible == false then return false end
		local x, y, w, h = controlRect(panel)
		local mx, my = getMouseX(), getMouseY()
		return mx >= x and mx < x + w and my >= y and my < y + h
	end
	function handle:update(nextSections, identityKey, nextBounds)
		if self.disposed then return nil, "disposed" end
		if type(nextSections) ~= "table" or #nextSections == 0
			or identityKey == nil or type(nextBounds) ~= "table" then
			release(); return nil, "invalid_document"
		end
		for index = 1, #nextSections do
			if type(nextSections[index]) ~= "table" or type(nextSections[index].lines) ~= "table" then
				release(); return nil, "invalid_section"
			end
		end
		for _, name in ipairs({ "x", "y", "w", "h" }) do
			local value = nextBounds[name]
			if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
				release(); return nil, "invalid_bounds"
			end
		end
		if nextBounds.w <= 0 or nextBounds.h <= 0 then release(); return nil, "empty_bounds" end
		local changed = key ~= identityKey or not bounds
			or bounds.w ~= nextBounds.w or bounds.h ~= nextBounds.h
		if changed then
			release()
			if key ~= identityKey then closedKey = nil end
		end
		key, sections = identityKey, nextSections
		bounds = { x = nextBounds.x, y = nextBounds.y, w = nextBounds.w, h = nextBounds.h }
		if closedKey == key then return nil, "closed" end
		if not self.panel then
			local panel, reason = transientPanel({ kind = "descriptive", sections = sections,
				maxWidth = bounds.w, maxHeight = bounds.h, playerNum = self.playerNum,
				environment = options.environment, theme = options.theme,
				backgroundColor = options.backgroundColor, borderColor = options.borderColor })
			if not panel then return nil, reason end
			self.panel = panel
			local previousUpdate = panel.update
			panel.update = function(widget, ...)
				if previousUpdate then previousUpdate(widget, ...) end
				if type(options.isValid) == "function" then
					local ok, valid = pcall(options.isValid, self)
					if not ok or not valid then
						self:hide()
						if type(options.onInvalid) == "function" then options.onInvalid(self) end
					end
				end
			end
			panel._sikTooltipFocus = SiK.UI.FocusStack.install(panel, function()
				return self:close()
			end, { playerNum = self.playerNum, priority = SiK.UI.FocusStack.PRIORITY.TRANSIENT })
			if panel.addToUIManager then panel:addToUIManager() end
			panel:setVisible(true)
			if panel.bringToTop then panel:bringToTop() end
		end
		local safe = SiK.UI.Viewport.safe(self.playerNum, options.environment, 0)
		self.panel:setX(math.max(safe.x, math.min(bounds.x, safe.x + safe.w - self.panel.width)))
		self.panel:setY(math.max(safe.y, math.min(bounds.y, safe.y + safe.h - self.panel.height)))
		return self.panel
	end
	function handle:dispose()
		if self.disposed then return false end
		release()
		self.disposed, sections, bounds = true, nil, nil
		return true
	end
	return handle
end

local function sameSafeRect(left, right)
	return left and right and left.x == right.x and left.y == right.y
		and left.w == right.w and left.h == right.h
end

local function resolveKind(options)
	local kind = options.kind
	if kind == "object" or kind == "brief" or kind == "descriptive" then return kind end
	if kind ~= nil then return nil, "invalid_tooltip_kind" end
	-- Compatibility through Framework 1.0.x only. Profiles do not infer meaning.
	if options.profile == "option" or options.profile == "rail" then return "brief" end
	return "descriptive"
end

local function briefTextFits(text, options, content)
	text = tostring(text or "")
	content = content or (type(options.content) == "table" and options.content or {})
	if content.title ~= nil and tostring(content.title) ~= "" then
		return nil, "brief_multiline"
	end
	if string.find(text, "\n", 1, true) or string.find(text, "\r", 1, true) then
		return nil, "brief_multiline"
	end
	local safe = SiK.UI.Viewport.safe(options.playerNum or 0, options.environment, 0)
	local font = content.font or options.font or UIFont.Small
	local manager = type(getTextManager) == "function" and getTextManager() or nil
	local textWidth = manager and manager.MeasureStringX
		and manager:MeasureStringX(font, text) or #text * 8
	local paddingX = math.max(0, tonumber(content.paddingX or options.paddingX) or 8)
	if textWidth + paddingX * 2 > safe.w then return nil, "brief_viewport_overflow" end
	return true
end

function Tooltip.attach(control, options)
	if options == nil and type(control) == "table" and control.control then
		options = control; control = options.control
	end
	if type(control) ~= "table" then return nil, "invalid_control" end
	options = options or {}
	local kind, kindReason = resolveKind(options)
	if not kind then return nil, kindReason end
	options.kind = kind
	if kind == "object" then
		if options.text ~= nil or options.tooltip ~= nil then return nil, "object_text_unsupported" end
		if options.content ~= nil or type(options.factory) == "function" then
			return nil, "object_content_unsupported"
		end
	end
	local previousText = control.tooltip
	local initialContent = type(options.content) == "table" and options.content or nil
	local staticText = options.text or options.tooltip
	if staticText == nil and initialContent then staticText = initialContent.text end
	local composed = staticText
	if kind == "object" then
		-- An external object host owns its vanilla body/tooltip field. Do not
		-- compose that field into an informational surface or lifecycle.
		staticText, composed = nil, nil
	elseif previousText and staticText and tostring(previousText) ~= tostring(staticText) then
		composed = options.replace == true and staticText
			or tostring(previousText) .. tostring(options.separator or "\n")
				.. tostring(staticText)
	elseif previousText and not staticText then
		composed = previousText
	end
	if kind == "brief" then
		if composed == nil then return nil, "brief_text_required" end
		local fits, reason = briefTextFits(composed, options)
		if not fits then return nil, reason end
	end
	if composed ~= nil then
		if control.setTooltip then control:setTooltip(tostring(composed))
		else control.tooltip = tostring(composed) end
		-- Most SiK controls are ISPanel-derived and PZ does not render their
		-- `tooltip` field by itself.  A plain text tooltip therefore needs the
		-- same owned transient surface as every other framework tooltip.
		if type(options.factory) ~= "function" and options.content == nil then
			options.variant = "transient"
			options.content = { text = tostring(composed) }
		elseif type(options.content) == "table" then
			options.content.text = tostring(composed)
		end
	end

	local previousMove = control.onMouseMove
	local previousOutside = control.onMouseMoveOutside
	local active, activeOwned = nil, false
	local contentDisabled = false
	local handle = { control = control, playerNum = options.playerNum or 0 }
	local channelKey = tostring(handle.playerNum) .. "\31" .. tostring(options.channel or "default")
	local timeoutCallback, timeoutInstalled, expiresAt = nil, false, nil

	local function removeTimeout()
		if timeoutInstalled and Events and Events.OnTick and Events.OnTick.Remove then
			Events.OnTick.Remove(timeoutCallback)
		end
		timeoutInstalled, expiresAt = false, nil
	end

	local function disposeActive()
		if not active then return end
		Tooltip.hide(active)
		active._sikTransientAttached = nil
		if activeOwned and active.dispose then active:dispose() end
		active, activeOwned = nil, false
		if Tooltip._transientChannels[channelKey] == handle then
			Tooltip._transientChannels[channelKey] = nil
		end
		removeTimeout()
	end

	local function pointerOver(widget)
		if type(widget) ~= "table" then return false end
		if type(widget.isMouseOver) == "function" then
			local ok, hovered = pcall(widget.isMouseOver, widget)
			if ok and hovered == true then return true end
		end
		if type(getMouseX) ~= "function" or type(getMouseY) ~= "function" then return false end
		local x, y, width, height = controlRect(widget)
		local mouseX, mouseY = getMouseX(), getMouseY()
		return type(mouseX) == "number" and type(mouseY) == "number"
			and mouseX >= x and mouseX < x + width and mouseY >= y and mouseY < y + height
	end

	local function expired()
		return expiresAt ~= nil and transientNow(options) >= expiresAt
	end

	local show
	local function remeasureScrollableViewport()
		if not (activeOwned and active and active._sikTooltipScrollable) then return false end
		local safe = SiK.UI.Viewport.safe(options.playerNum or 0, options.environment, 0)
		if sameSafeRect(active._sikTooltipSafe, safe) then return false end
		disposeActive()
		show(control)
		return true
	end

	local function installScrollableLifecycle(panel)
		if not panel or panel._sikTooltipScrollLifecycleInstalled then return end
		panel._sikTooltipScrollLifecycleInstalled = true
		local previousUpdate = panel.update
		local function closeOutside()
			if expired() or (not pointerOver(control) and not pointerOver(panel)) then disposeActive() end
		end
		panel.update = function(self, ...)
			local result = callPrevious(previousUpdate, self, ...)
			if self ~= active or self._sikDisposed then return result end
			if not remeasureScrollableViewport() and expired() then disposeActive() end
			return result
		end
		local function wrap(widget)
			if not widget then return end
			local previousMove, previousOutside = widget.onMouseMove, widget.onMouseMoveOutside
			widget.onMouseMove = function(self, ...)
				local result = callPrevious(previousMove, self, ...)
				if not remeasureScrollableViewport() and expired() then disposeActive() end
				return result
			end
			widget.onMouseMoveOutside = function(self, ...)
				local result = callPrevious(previousOutside, self, ...)
				closeOutside()
				return result
			end
		end
		-- The Scroll viewport and its bar receive pointer events directly in PZ;
		-- retain their existing wheel/drag handlers and only add exit bookkeeping.
		wrap(panel)
		local scroll = panel._sikTooltipScroll
		if scroll then
			-- Tooltip.makePassive deliberately leaves the outer frame transparent to
			-- pointer input. Its interactive Scroll descendants explicitly consume
			-- their own wheel/drag events, so those events cannot fall through to
			-- the underlying control.
			for _, widget in ipairs({ scroll.viewport, scroll.host, scroll.bar }) do
				if widget and widget.javaObject and widget.javaObject.setConsumeMouseEvents then
					widget.javaObject:setConsumeMouseEvents(true)
				end
				wrap(widget)
			end
		end
		panel._sikTooltipFocus = SiK.UI.FocusStack.install(panel, function()
			disposeActive()
			return true
		end, { playerNum = handle.playerNum, priority = SiK.UI.FocusStack.PRIORITY.TRANSIENT })
	end

	show = function(self, supplied)
		if handle.disposed then return nil, "disposed" end
		if contentDisabled then return nil end
		-- The viewport can change between attachment and hover (resize, UI scale or
		-- split-screen). Recheck only at this lifecycle boundary; no polling.
		if kind == "brief" then
			local fits, reason = briefTextFits(composed, options)
			if not fits then
				disposeActive()
				return nil, reason
			end
		end
		if kind == "object" and type(supplied) ~= "table" then
			return nil, "object_host_required"
		end
		-- Descriptive transients derive both wrapping width and height from the
		-- safe player rect. Recreate only when that effective rect changed at a
		-- real show/hover boundary; there is no resize polling.
		if kind == "descriptive" and activeOwned and active and active._sikTooltipSafe then
			local safe = SiK.UI.Viewport.safe(options.playerNum or 0, options.environment, 0)
			if not sameSafeRect(active._sikTooltipSafe, safe) then disposeActive() end
		end
		if supplied and supplied ~= active then
			disposeActive(); active, activeOwned = supplied, false
		end
		if not active then
			if type(options.factory) == "function" then
				local context = SiK.UI.Namespace.context(self, options, "tooltip")
				local ok, value = pcall(options.factory, context)
				if ok then active, activeOwned = value, value ~= nil end
			elseif options.variant == "transient" and options.content then
				local created, reason = transientPanel(options)
				if not created then return nil, reason end
				active, activeOwned = created, true
			end
			if active then Tooltip.makePassive(active) end
		end
		if active then
			if options.variant == "transient" then
				local previous = Tooltip._transientChannels[channelKey]
				if previous and previous ~= handle then previous:hide() end
				Tooltip._transientChannels[channelKey] = handle
			end
			if not active._sikTransientAttached and active.addToUIManager then
				active:addToUIManager(); active._sikTransientAttached = true
			end
			if active.setVisible then active:setVisible(true) end
			if active._sikTooltipScrollable then installScrollableLifecycle(active) end
			-- An object host arrives with its vanilla/product layout already chosen.
			-- Lifecycle may show/hide it, but informational pointer/control placement
			-- must not move its body.
			if kind ~= "object" then
				if options.variant == "transient" then placeTransient(active, control, options)
				else Tooltip.position(active, handle.playerNum, options.gap, options.environment) end
			end
			local timeoutMs = math.max(0, tonumber(options.timeoutMs) or 0)
			if timeoutMs > 0 then
				expiresAt = transientNow(options) + timeoutMs
				-- A scrollable tooltip has local control/panel callbacks that check its
				-- expiry. Do not add a global tick listener for that variant.
				if not active._sikTooltipScrollable and not timeoutInstalled
						and Events and Events.OnTick and Events.OnTick.Add then
					timeoutInstalled = true; Events.OnTick.Add(timeoutCallback)
				end
			end
		end
		return active
	end
	timeoutCallback = function()
		if expiresAt and transientNow(options) >= expiresAt then disposeActive() end
	end

	local moveWrapper = function(self, ...)
		local result = callPrevious(previousMove, self, ...)
		show(self)
		return result
	end
		local outsideWrapper = function(self, ...)
			local result = callPrevious(previousOutside, self, ...)
			if active and active._sikTooltipScrollable then
				if expired() or not pointerOver(active) then disposeActive() end
			else
				disposeActive()
			end
			return result
		end
        local hoverCreatesTooltip = type(options.factory) == "function"
                or (options.variant == "transient" and options.content ~= nil)
        if hoverCreatesTooltip then
                control.onMouseMove = moveWrapper
                control.onMouseMoveOutside = outsideWrapper
        end

	function handle:show(widget) return show(control, widget) end
	function handle:hide() disposeActive() end
	function handle:getActive() return active end
	function handle:reposition()
		if not active then return nil, "not_visible" end
		-- Object layout remains entirely with the caller-created host. Return the
		-- active host so this lifecycle operation stays harmless and chainable.
		if kind == "object" then return active end
		return placeTransient(active, control, options)
	end
	local function copyContentWithText(content, value)
		if value == nil then return nil end
		local result = {}
		if type(content) == "table" then
			for key, entry in pairs(content) do result[key] = entry end
		end
		result.text = tostring(value)
		return result
	end
	local function sameRenderedContent(left, right)
		if left == right then return true end
		if type(left) ~= "table" or type(right) ~= "table" then return false end
		for _, key in ipairs({ "text", "title", "tone", "font", "paddingX", "paddingY", "align" }) do
			if left[key] ~= right[key] then return false end
		end
		return true
	end
	local function commitText(value, nextComposed, nextContent, refresh)
		local changed = tostring(composed or "") ~= tostring(nextComposed or "")
		staticText, composed = value, nextComposed
		options.content = nextContent
		contentDisabled = nextComposed == nil
		if control.setTooltip then control:setTooltip(nextComposed) else control.tooltip = nextComposed end
		if nextComposed == nil then
			disposeActive()
			return handle
		end
		if activeOwned and (changed or refresh) then
			disposeActive()
			show(control)
		end
		return handle
	end
	function handle:setContent(content)
		if kind == "object" then return nil, "object_content_unsupported" end
		local value
		if type(content) == "table" then value = content.text else value = content end
		local nextComposed = value
		if previousText and value and options.replace ~= true then
			nextComposed = tostring(previousText) .. tostring(options.separator or "\n")
				.. tostring(value)
		end
		local nextContent = copyContentWithText(content, nextComposed)
		if kind == "brief" then
			if nextComposed ~= nil then
				local fits, reason = briefTextFits(nextComposed, options, nextContent)
				if not fits then return nil, reason end
			end
		end
		return commitText(value, nextComposed, nextContent,
			not sameRenderedContent(options.content, nextContent))
	end
	function handle:setText(value)
		if kind == "object" then return nil, "object_text_unsupported" end
		local nextComposed = value
		if previousText and value and options.replace ~= true then
			nextComposed = tostring(previousText) .. tostring(options.separator or "\n")
				.. tostring(value)
		end
		local nextContent = copyContentWithText(options.content, nextComposed)
		if kind == "brief" then
			if nextComposed ~= nil then
				local fits, reason = briefTextFits(nextComposed, options, nextContent)
				if not fits then return nil, reason end
			end
		end
		return commitText(value, nextComposed, nextContent)
	end
	function handle:dispose()
		if self.disposed then return false end
		self.disposed = true
		disposeActive()
		removeTimeout()
		if control.onMouseMove == moveWrapper then control.onMouseMove = previousMove end
		if control.onMouseMoveOutside == outsideWrapper then
			control.onMouseMoveOutside = previousOutside
		end
		if control.tooltip == composed then
			if previousText ~= nil and control.setTooltip then control:setTooltip(previousText)
			else control.tooltip = previousText end
		end
		return true
	end
	return handle
end

return Tooltip
