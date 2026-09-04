require "SiK/UI/Namespace"
require "SiK/UI/Viewport"
require "SiK/UI/Theme"
require "SiK/UI/Metrics"
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
	if measured.title ~= "" then
		panel:drawText(measured.title, x + measured.paddingX, cursor,
			color.r, color.g, color.b, color.a, measured.font)
		cursor = cursor + measured.lineHeight + (#measured.lines > 0 and measured.gap or 0)
	end
	for _, line in ipairs(measured.lines) do
		panel:drawText(line, x + measured.paddingX, cursor,
			lineColor.r, lineColor.g, lineColor.b, lineColor.a, measured.font)
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
	if placement.anchor == "pointer" or not control then
		return Tooltip.position(widget, options.playerNum or 0,
			placement.gap or options.gap, options.environment)
	end
	local safe = SiK.UI.Viewport.safe(options.playerNum or 0, options.environment, 0)
	local cx, cy, cw, ch = controlRect(control)
	local width = widget.getWidth and widget:getWidth() or widget.width or 0
	local height = widget.getHeight and widget:getHeight() or widget.height or 0
	local gap = math.max(0, tonumber(placement.gap or options.gap) or 4)
	local side = placement.side or "after"
	local x, y = cx + cw + gap, cy
	if side == "before" then x = cx - width - gap
	elseif side == "above" then x, y = cx, cy - height - gap
	elseif side == "below" then x, y = cx, cy + ch + gap end
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
	local profile = options.profile or "compact"
	-- Explanatory BlockHeader help carries guidance rather than the short label
	-- of an item tooltip. Give it a readable line length and only contract when
	-- the player's safe viewport genuinely cannot provide that width.
	local defaultWidth = profile == "informational" and 680 or 320
	local viewportMargin = profile == "informational" and 32 or 0
	local availableWidth = math.max(1, safe.w - viewportMargin)
	local requestedWidth = math.max(120, tonumber(options.maxWidth) or defaultWidth)
	local width = math.max(1, math.min(requestedWidth, availableWidth))
	local document = Tooltip.createDocument({ sections = { {
		title = content.title, text = content.text or options.text,
		tone = content.tone or options.tone, framed = false,
	} } })
	local measured = document:measure(width)
	local panel = ISPanel:new(0, 0, measured.width, math.min(measured.height, math.max(1, safe.h)))
	panel:initialise()
	panel._sikTooltipDocument = document
	panel.prerender = function(self)
		Tooltip.renderFrame(self, 0, 0, self.width, self.height, options)
		document:render(self, 0, 0, self.width, { backgroundColor = { a = 0 }, border = false })
	end
	local previousDispose = panel.dispose
	panel.dispose = function(self)
		if self._sikDisposed then return false end
		self._sikDisposed = true
		document:dispose()
		if type(previousDispose) == "function" then previousDispose(self) end
		return true
	end
	return panel
end

function Tooltip.attach(control, options)
	if options == nil and type(control) == "table" and control.control then
		options = control; control = options.control
	end
	if type(control) ~= "table" then return nil, "invalid_control" end
	options = options or {}
	local previousText = control.tooltip
	local staticText = options.text or options.tooltip
	local composed = staticText
	if previousText and staticText and tostring(previousText) ~= tostring(staticText) then
		composed = options.replace == true and staticText
			or tostring(previousText) .. tostring(options.separator or "\n")
				.. tostring(staticText)
	elseif previousText and not staticText then
		composed = previousText
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
		end
	end

	local previousMove = control.onMouseMove
	local previousOutside = control.onMouseMoveOutside
	local active, activeOwned = nil, false
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

	local function show(self, supplied)
		if supplied and supplied ~= active then
			disposeActive(); active, activeOwned = supplied, false
		end
		if not active then
			if type(options.factory) == "function" then
				local context = SiK.UI.Namespace.context(self, options, "tooltip")
				local ok, value = pcall(options.factory, context)
				if ok then active, activeOwned = value, value ~= nil end
			elseif options.variant == "transient" and options.content then
				active, activeOwned = transientPanel(options), true
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
			if options.variant == "transient" then placeTransient(active, control, options)
			else Tooltip.position(active, handle.playerNum, options.gap, options.environment) end
			local timeoutMs = math.max(0, tonumber(options.timeoutMs) or 0)
			if timeoutMs > 0 then
				expiresAt = transientNow(options) + timeoutMs
				if not timeoutInstalled and Events and Events.OnTick and Events.OnTick.Add then
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
		disposeActive()
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
		return placeTransient(active, control, options)
	end
	function handle:setContent(content)
		options.content = content
		if activeOwned then disposeActive(); show(control) end
		return self
	end
	function handle:setText(value)
		staticText = value
		composed = value
		if previousText and value and options.replace ~= true then
			composed = tostring(previousText) .. tostring(options.separator or "\n")
				.. tostring(value)
		end
		if control.setTooltip then control:setTooltip(composed) else control.tooltip = composed end
		return self
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
