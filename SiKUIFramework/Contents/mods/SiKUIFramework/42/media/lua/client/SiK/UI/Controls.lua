require "SiK/UI/Namespace"
require "SiK/UI/Metrics"
require "SiK/UI/Layout"
require "SiK/UI/Theme"
local Icon = require "SiK/UI/Icon"
require "SiK/UI/Tooltip"
require "SiK/UI/Combo"
require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"

local Controls = SiK.UI.Controls or {}
SiK.UI.Namespace.define("Controls", Controls)

local DEFAULT_INFO_ICON = "sik.info.24"

local function n(value, fallback)
	value = tonumber(value)
	if value == nil or value ~= value then return fallback end
	return value
end

local function fontHeight(font)
	if type(getTextManager) == "function" then
		return getTextManager():getFontHeight(font or UIFont.Small)
	end
	return 18
end

local function attach(parent, child)
	if parent and child and parent.addChild then parent:addChild(child) end
	return child
end

local function controlArgs(parent, options)
	if options == nil then
		options = parent or {}
		parent = options.parent
	end
	return parent, options or {}
end

local function removeChild(widget)
	if widget and widget.parent and widget.parent.removeChild then
		widget.parent:removeChild(widget)
	elseif widget and widget.removeFromUIManager then
		widget:removeFromUIManager()
	end
end

local function decorate(widget, kind, options)
	widget._sikUiControl = kind
	widget.playerNum = math.max(0, math.floor(n(options.playerNum, 0)))
	widget.payload = options.payload
	widget._sikTooltipHandle = nil
	if options.tooltip ~= nil then
		widget._sikTooltipHandle = SiK.UI.Tooltip.attach(widget, {
			text = options.tooltip, playerNum = widget.playerNum,
			placement = options.tooltipPlacement,
			profile = options.tooltipProfile, maxWidth = options.tooltipMaxWidth,
			kind = options.tooltipKind,
			channel = options.tooltipChannel,
		})
	end
	function widget:setData(payload)
		options.payload = payload
		self.payload = payload
		return self
	end
	local previousDispose = widget.dispose
	widget.dispose = function(self)
		if self._sikDisposed then return false end
		self._sikDisposed = true
		if self._sikTooltipHandle then self._sikTooltipHandle:dispose() end
		if type(previousDispose) == "function" and previousDispose ~= self.dispose then
			pcall(previousDispose, self)
		end
		removeChild(self)
		return true
	end
	return widget
end

--- Sets or replaces a control tooltip through the SiK UI lifecycle contract.
--- Consumers must not assume that the underlying vanilla control implements
--- setTooltip: several valid PZ widgets expose only the tooltip field.
function Controls.setTooltip(control, value, options)
	if type(control) ~= "table" then return nil, "invalid_control" end
	if control._sikTooltipHandle and not control._sikTooltipHandle.disposed then
		local updated, reason = control._sikTooltipHandle:setText(value)
		if not updated then return nil, reason end
		return control
	end
	options = options or {}
	local handle, reason = SiK.UI.Tooltip.attach(control, {
		text = value,
		replace = true,
		playerNum = options.playerNum or control.playerNum or 0,
		factory = options.factory,
		gap = options.gap,
		placement = options.placement or options.tooltipPlacement,
		environment = options.environment,
		profile = options.profile or options.tooltipProfile,
		kind = options.kind or options.tooltipKind,
		maxWidth = options.maxWidth or options.tooltipMaxWidth,
		channel = options.channel or options.tooltipChannel,
	})
	if not handle then return nil, reason end
	control._sikTooltipHandle = handle
	return control
end

local function callback(component, options, name, value)
	local fn = options[name]
	if type(fn) ~= "function" then return nil end
	return fn(SiK.UI.Namespace.context(component, options, name, value))
end

function Controls.metrics(profileName)
	local height = fontHeight(UIFont.Small)
	local profile = SiK.UI.Metrics.profile(0, profileName)
	local rowHeight = math.max(height + 10, profile.rowHeight or 0)
	return {
		fontHeight = height,
		buttonHeight = height + 10,
		inputHeight = height + 10,
		rowHeight = rowHeight,
		sectionHeight = rowHeight,
		controlGap = profile.contentGap or 8,
		rowGap = 8,
		windowPadding = 14,
		iconSize = 32,
	}
end

--- Resolves one axis without relying on the alignment defaults of a vanilla
--- control.  Components use the same contract for text, icons and child
--- content: start/left/top, center/middle, or end/right/bottom.
function Controls.alignOffset(containerSize, contentSize, alignment, paddingStart, paddingEnd)
	local offset = SiK.UI.Layout.axis(containerSize, contentSize, alignment,
		paddingStart, paddingEnd)
	return offset
end

--- Returns the framework-owned position for a single line inside a rectangle.
--- `align` controls the horizontal axis and `verticalAlign` the vertical one.
function Controls.textPosition(bounds, text, options)
	bounds, options = bounds or {}, options or {}
	local font = options.font or UIFont.Small
	local manager = type(getTextManager) == "function" and getTextManager() or nil
	local value = tostring(text or "")
	local width = manager and manager.MeasureStringX
		and manager:MeasureStringX(font, value) or #value * 8
	local height = fontHeight(font)
	local rect = SiK.UI.Layout.alignRect(bounds, { w = width, h = height }, {
		defaultPadding = 0,
		padding = { left = options.paddingX or 0,
			right = options.paddingRight or options.paddingX or 0,
			top = options.paddingY or 0,
			bottom = options.paddingBottom or options.paddingY or 0 },
		align = options.align or "left",
		verticalAlign = options.verticalAlign or "middle",
	})
	return rect.x, rect.y, rect.w, rect.h
end

local function utf8Prefix(text, byteLimit)
	local length, index, last = string.len(text), 1, 0
	byteLimit = math.max(0, math.min(length, math.floor(n(byteLimit, 0))))
	while index <= byteLimit do
		local first = string.byte(text, index)
		local size = 1
		if first and first >= 194 and first <= 223 then size = 2
		elseif first and first >= 224 and first <= 239 then size = 3
		elseif first and first >= 240 and first <= 244 then size = 4 end
		if index + size - 1 > byteLimit or index + size - 1 > length then break end
		last = index + size - 1
		index = last + 1
	end
	return string.sub(text, 1, last), last
end

local function firstUtf8Character(text)
	local first = string.byte(text, 1)
	if not first then return "", 0 end
	local size = 1
	if first >= 194 and first <= 223 then size = 2
	elseif first >= 224 and first <= 239 then size = 3
	elseif first >= 240 and first <= 244 then size = 4 end
	size = math.min(size, string.len(text))
	return string.sub(text, 1, size), size
end

local function measuredWidth(manager, font, text)
	if manager and manager.MeasureStringX then return manager:MeasureStringX(font, text) end
	return string.len(text) * 8
end

local function fittedPrefix(text, maxWidth, font, manager, suffix)
	suffix = tostring(suffix or "")
	local suffixWidth = measuredWidth(manager, font, suffix)
	if suffixWidth > maxWidth then return "", 0 end
	local low, high, bestText, bestEnd = 0, string.len(text), "", 0
	while low <= high do
		local middle = math.floor((low + high) / 2)
		local prefix, prefixEnd = utf8Prefix(text, middle)
		if measuredWidth(manager, font, prefix) + suffixWidth <= maxWidth then
			bestText, bestEnd, low = prefix, prefixEnd, middle + 1
		else
			high = middle - 1
		end
	end
	return bestText, bestEnd
end

function Controls.truncateText(text, maxWidth, font, suffix)
	text, font = tostring(text or ""), font or UIFont.Small
	maxWidth = math.max(0, n(maxWidth, 0))
	local manager = type(getTextManager) == "function" and getTextManager() or nil
	if measuredWidth(manager, font, text) <= maxWidth then return text end
	suffix = suffix == nil and "..." or tostring(suffix)
	local prefix = fittedPrefix(text, maxWidth, font, manager, suffix)
	if prefix == "" and measuredWidth(manager, font, suffix) > maxWidth then return "" end
	return prefix .. suffix
end

local function appendWrappedWord(lines, word, maxWidth, font, manager)
	local remaining = word
	while remaining ~= "" and measuredWidth(manager, font, remaining) > maxWidth do
		local chunk, consumed = fittedPrefix(remaining, maxWidth, font, manager, "")
		if consumed <= 0 then
			chunk, consumed = firstUtf8Character(remaining)
		end
		lines[#lines + 1] = chunk
		remaining = string.sub(remaining, consumed + 1)
	end
	return remaining
end

function Controls.wrapText(text, maxWidth, font)
	font = font or UIFont.Small
	maxWidth = math.max(1, n(maxWidth, 1))
	local manager = type(getTextManager) == "function" and getTextManager() or nil
	local lines, current = {}, ""
	for word in string.gmatch(tostring(text or ""), "%S+") do
		local candidate = current == "" and word or current .. " " .. word
		local width = measuredWidth(manager, font, candidate)
		if width > maxWidth and current ~= "" then
			lines[#lines + 1] = current
			current = appendWrappedWord(lines, word, maxWidth, font, manager)
		elseif width > maxWidth then
			current = appendWrappedWord(lines, word, maxWidth, font, manager)
		else
			current = candidate
		end
	end
	if current ~= "" then lines[#lines + 1] = current end
	if #lines == 0 then lines[1] = "" end
	return lines
end

--- Reuses a caller-owned label pool for wrapped informational copy.  The
--- framework owns wrapping, typography and visibility; the product keeps the
--- pool so frequent refreshes do not allocate new controls every frame.
function Controls.renderWrappedLinePool(host, pool, options)
	options = options or {}
	pool = pool or {}
	local font = options.font or UIFont.Small
	local lineGap = math.max(0, n(options.lineGap, 2))
	local lineHeight = fontHeight(font) + lineGap
	local x = n(options.x, 0)
	local y = n(options.y, 0)
	local lines = Controls.wrapText(options.text or "",
		math.max(1, n(options.w or options.width, 1)), font)
	local color = SiK.UI.Theme.normalizeColor(options.color,
		SiK.UI.Theme.color(options.tone or "textMuted", options.theme))
	local r = n(color.r or color[1], 0.72)
	local g = n(color.g or color[2], 0.75)
	local b = n(color.b or color[3], 0.8)
	local a = n(color.a or color[4], 1)
	local hostVisible = not host or not host.isVisible or host:isVisible()
	for index = 1, #lines do
		local label = pool[index]
		if not label then
			label = ISLabel:new(x, y, fontHeight(font), "", r, g, b, a,
				font, true)
			label:initialise()
			if type(options.attach) == "function" then
				options.attach(host, label)
			else
				attach(host, label)
			end
			pool[index] = label
		else
			label:setX(x)
			label:setY(y)
			label.r, label.g, label.b, label.a = r, g, b, a
		end
		label:setVisible(hostVisible)
		label:setName(lines[index])
		y = y + lineHeight
	end
	for index = #lines + 1, #pool do
		if pool[index] then pool[index]:setVisible(false) end
	end
	return y
end

local function applyButtonTheme(button, options)
	local theme = SiK.UI.Theme.tokens(options.theme)
	local background = options.danger and theme.danger
		or (options.success and theme.success
			or (options.active and theme.selected or theme.surfaceAlt))
	-- ISButton renders textColor unconditionally whenever it is enabled.  Own
	-- each table so no consumer can leave a shared vanilla control with nil
	-- colour fields or mutate a theme token.
	button.backgroundColor = { r = background.r, g = background.g,
		b = background.b, a = background.a }
	button.backgroundColorMouseOver = { r = theme.hover.r, g = theme.hover.g,
		b = theme.hover.b, a = theme.hover.a }
	button.backgroundColorClicked = { r = theme.pressed.r, g = theme.pressed.g,
		b = theme.pressed.b, a = theme.pressed.a }
	button.borderColor = { r = theme.border.r, g = theme.border.g,
		b = theme.border.b, a = theme.border.a }
	button.textColor = { r = theme.text.r, g = theme.text.g,
		b = theme.text.b, a = theme.text.a }
	button._sikLocked = options.locked == true
        return button
end

-- A product may keep a vanilla button it owns, but it must not be able to
-- leave that button in a state that ISButton cannot render.  Vanilla reads
-- textColor.r without a nil guard.  Keep the repair at the framework boundary
-- and run it immediately before prerender too, so an accidental later
-- assignment cannot blank the whole terminal on the next frame.
local function ensureButtonRenderSafety(button, options)
        button._sikButtonChromeOptions = options or {}
        if button._sikButtonChromeInstalled then return button end
        button._sikButtonChromeInstalled = true
        local basePrerender = button.prerender
        button.prerender = function(self, ...)
                applyButtonTheme(self, self._sikButtonChromeOptions or {})
                if type(basePrerender) == "function" then
                        return basePrerender(self, ...)
                end
        end
        return button
end

--- Styles a caller-owned ISButton with canonical, runtime-safe chrome.
--- Product controls can preserve their vanilla callback signature.  This also
--- repairs a missing textColor, which vanilla renders without a nil guard.
function Controls.styleButton(button, options)
        if type(button) ~= "table" then return nil, "invalid_button" end
        options = options or {}
        applyButtonTheme(button, options)
        ensureButtonRenderSafety(button, options)
        button._sikUiControl = "button"
	button._sikUiButtonStyled = true
	return button
end

--- Applies the canonical field chrome to an already-created vanilla text
--- entry.  Product UIs can keep their existing lifecycle/callbacks while the
--- framework remains the single owner of colors and interaction states.
function Controls.styleField(entry, options)
	if type(entry) ~= "table" then return nil, "invalid_field" end
	options = options or {}
	local theme = SiK.UI.Theme.tokens(options.theme)
	entry.backgroundColor = { r = theme.surface.r, g = theme.surface.g,
		b = theme.surface.b, a = theme.surface.a }
	entry.borderColor = { r = theme.border.r, g = theme.border.g,
		b = theme.border.b, a = theme.border.a }
	entry.textColor = { r = theme.text.r, g = theme.text.g,
		b = theme.text.b, a = theme.text.a }
	entry._sikUiControl = "field"
	entry._sikUiInputStyled = true
	return entry
end

--- Applies the canonical combo chrome to an already-created vanilla combo.
--- This is deliberately separate from combo() because some game controls
--- must be instantiated with product-owned target/callback signatures.
function Controls.styleCombo(combo, options)
	if type(combo) ~= "table" then return nil, "invalid_combo" end
	options = options or {}
	local theme = SiK.UI.Theme.tokens(options.theme)
	combo.backgroundColor = { r = theme.surface.r, g = theme.surface.g,
		b = theme.surface.b, a = theme.surface.a }
	combo.borderColor = { r = theme.border.r, g = theme.border.g,
		b = theme.border.b, a = theme.border.a }
	combo.textColor = { r = theme.text.r, g = theme.text.g,
		b = theme.text.b, a = theme.text.a }
	combo._sikUiControl = "combo"
	combo._sikUiInputStyled = true
	return combo
end

function Controls.panel(parent, options)
        parent, options = controlArgs(parent, options)
	local panel = ISPanel:new(n(options.x, 0), n(options.y, 0),
		math.max(1, n(options.w or options.width, 240)),
		math.max(1, n(options.h or options.height, 1)))
	panel:initialise()
        local background = options.backgroundColor or options.background
        local border = options.borderColor or options.border
        panel.backgroundColor = SiK.UI.Theme.normalizeColor(background,
                { r = 0, g = 0, b = 0, a = 0 })
        panel.borderColor = SiK.UI.Theme.normalizeColor(border,
                { r = 0, g = 0, b = 0, a = 0 })
        panel.drawBackground = options.drawBackground == true
                or (background ~= nil and (panel.backgroundColor.a or panel.backgroundColor[4] or 0) > 0)
        -- ISPanel does not reliably paint a border when drawBackground is false
        -- in every B42 bridge. SiK panels own both layers explicitly so a framed
        -- transparent block still has the approved visible frame.
        panel.prerender = function(self)
                local fill = self.backgroundColor or { r = 0, g = 0, b = 0, a = 0 }
                local edge = self.borderColor or { r = 0, g = 0, b = 0, a = 0 }
                local fillA = fill.a or fill[4] or 0
                local edgeA = edge.a or edge[4] or 0
                if self.drawBackground and fillA > 0 then
                        self:drawRect(0, 0, self.width, self.height, fillA,
                                fill.r or fill[1], fill.g or fill[2], fill.b or fill[3])
                end
                if edgeA > 0 then
                        self:drawRectBorder(0, 0, self.width, self.height, edgeA,
                                edge.r or edge[1], edge.g or edge[2], edge.b or edge[3])
                end
        end
        decorate(panel, options.controlId or "panel", options)
	return attach(parent, panel)
end

function Controls.separator(parent, options)
	parent, options = controlArgs(parent, options)
	local color = options.color or SiK.UI.Theme.color(options.tone or "divider", options.theme)
	return Controls.panel(parent, {
		x = options.x, y = options.y,
		w = options.w or options.width,
		h = options.h or options.height or 1,
		drawBackground = true,
		backgroundColor = color,
		borderColor = { r = 0, g = 0, b = 0, a = 0 },
		controlId = options.controlId or "separator",
		playerNum = options.playerNum,
		payload = options.payload,
	})
end

function Controls.button(parent, options)
	parent, options = controlArgs(parent, options)
	local button = ISPanel:new(n(options.x, 0), n(options.y, 0),
		math.max(1, n(options.w or options.width, 80)),
		math.max(1, n(options.h or options.height, Controls.metrics(options.profile).buttonHeight)))
	button:initialise()
	if button.instantiate then button:instantiate() end
	button.drawBackground = false
	button.title = tostring(options.text or "")
	button.enable = options.enabled ~= false
	button._sikPressed = false
	button._sikFullWidth = options.fullWidth == true

	local function invoke()
		if button and button.enable ~= false and options.enabled ~= false
			and options.locked ~= true then
			return callback(button, options, "onClick")
		end
	end
	-- Compatibility fields preserve the vanilla callback shape for consumers,
	-- but the visible widget is a framework-owned ISPanel canvas.
	button.target = button
	button.onclick = function() return invoke() end
	button.onMouseDown = function(self)
		if self.enable == false or options.locked == true then return true end
		self._sikPressed = true
		return true
	end
	button.onMouseUp = function(self)
		local activate = self._sikPressed == true and self.enable ~= false
		self._sikPressed = false
		if activate then return invoke() end
		return true
	end
	button.onMouseUpOutside = function(self) self._sikPressed = false end
	button.prerender = function(self)
		applyButtonTheme(self, options)
		local color = self.backgroundColor
		if self._sikPressed then color = self.backgroundColorClicked
		elseif self.isMouseOver and self:isMouseOver() then color = self.backgroundColorMouseOver end
		if self.enable == false or options.locked == true then
			color = SiK.UI.Theme.tokens(options.theme).background
		end
		self:drawRect(0, 0, self.width, self.height, color.a, color.r, color.g, color.b)
		local border = self.borderColor
		self:drawRectBorder(0, 0, self.width, self.height, border.a, border.r, border.g, border.b)
	end
	button.render = function(self)
		if self.title == "" and not options.leadingIcon then return end
		local color = self.enable ~= false and self.textColor
			or SiK.UI.Theme.tokens(options.theme).textMuted
		local iconSize = options.leadingIcon and math.max(1, n(options.iconSize, 18)) or 0
		local gap = iconSize > 0 and math.max(0, n(options.iconGap, 6)) or 0
		local labelWidth = measuredWidth(type(getTextManager) == "function" and getTextManager() or nil,
			options.font or UIFont.Small, self.title)
		local contentWidth = labelWidth + iconSize + gap
		local origin = math.floor((self.width - contentWidth) / 2)
		if options.leadingIcon then
			local iconY = math.floor((self.height - iconSize) / 2)
			local drawn = SiK.UI.Icon.drawExact(self, options.leadingIcon, origin, iconY, iconSize, iconSize)
			if not drawn then SiK.UI.Icon.draw(self, options.leadingIcon, origin, iconY, iconSize, iconSize) end
		end
		local _, y = Controls.textPosition({ x = 0, y = 0, w = self.width, h = self.height },
			self.title, { font = options.font or UIFont.Small, align = "left", verticalAlign = "middle" })
		local x = origin + iconSize + gap
		self:drawText(self.title, x, y, color.r, color.g, color.b, color.a,
			options.font or UIFont.Small)
	end
	applyButtonTheme(button, options)
	decorate(button, "button", options)
	function button:setEnable(value)
		self.enable = value ~= false
		if not self.enable then self._sikPressed = false end
		return self
	end
	function button:setEnabled(value)
		options.enabled = value ~= false
		self:setEnable(options.enabled)
		return self
	end
	function button:setLocked(value)
		options.locked = value == true; self._sikLocked = options.locked
		return self
	end
	function button:setText(value)
		self.title = tostring(value or "")
		options.text = self.title
		return self
	end
	return attach(parent, button)
end

function Controls.fitButtonToContent(button, options)
	if type(button) ~= "table" then return nil, "invalid_button" end
	options = options or {}
	local manager = type(getTextManager) == "function" and getTextManager() or nil
	local font = options.font or UIFont.Small
	local text = tostring(options.text or button.title or "")
	local measured = manager and manager:MeasureStringX(font, text) or (#text * 8)
	local width = measured + math.max(0, n(options.padding, 24))
	width = math.max(1, n(options.minWidth, width), width)
	if options.maxWidth ~= nil then width = math.min(width, math.max(1, n(options.maxWidth, width))) end
	if button.setWidth then button:setWidth(math.floor(width + 0.5)) else button.width = math.floor(width + 0.5) end
	return button
end

function Controls.measureButtonWidth(text, font, padding, minWidth, maxWidth)
	local manager = type(getTextManager) == "function" and getTextManager() or nil
	local measured = measuredWidth(manager, font or UIFont.Small, tostring(text or ""))
	local width = measured + math.max(0, n(padding, 24))
	width = math.max(math.max(1, n(minWidth, 1)), width)
	if maxWidth ~= nil then width = math.min(width, math.max(1, n(maxWidth, width))) end
	return math.floor(width + 0.5)
end

function Controls.iconButton(parent, options)
	parent, options = controlArgs(parent, options)
	local button = Controls.button(parent, options)
	button._sikUiControl = "iconButton"
	button.iconSource = options.icon or options.texture
	button.texture = SiK.UI.Icon.resolve(button.iconSource)
	local sourceMeta = SiK.UI.Icon.metadata(button.iconSource)
	local nativeSize = sourceMeta and math.max(1,
		math.min(n(sourceMeta.width, 1), n(sourceMeta.height, 1))) or nil
	button.iconSize = math.max(1, n(options.iconSize,
		nativeSize or (math.min(button.width, button.height) - 8)))
	button.iconPadding = math.max(0, n(options.iconPadding, 2))
	button.iconFit = options.iconFit or "square"
	button.iconTint = options.iconTint
	button.iconProvider = options.iconProvider
	button.iconTintProvider = options.iconTintProvider
	button.chrome = options.chrome ~= false
	local previousPrerender = button.prerender
	button.prerender = function(self)
		if self.chrome and type(previousPrerender) == "function" then previousPrerender(self) end
	end
	button.render = function(self)
		-- Icon buttons deliberately suppress the text renderer. Chrome remains
		-- framework-owned and the icon is drawn once at its registered size.
		local source, texture = self.iconSource, self.texture
		if type(self.iconProvider) == "function" then
			local ok, value = pcall(self.iconProvider,
				SiK.UI.Namespace.context(self, options, "icon"))
			if ok then source, texture = value, SiK.UI.Icon.resolve(value) end
		end
		if not texture then return end
		local tint = self.iconTint
		if type(self.iconTintProvider) == "function" then
			local ok, value = pcall(self.iconTintProvider,
				SiK.UI.Namespace.context(self, options, "iconTint"))
			if ok then tint = value end
		end
		tint = type(tint) == "table" and tint or {}
		local availableW = math.max(1, self.width - self.iconPadding * 2)
		local availableH = math.max(1, self.height - self.iconPadding * 2)
		local drawW, drawH = availableW, availableH
		if self.iconFit ~= "fill" then
			local size = math.min(self.iconSize, availableW, availableH)
			drawW, drawH = size, size
		end
		local drawX, drawY = math.floor((self.width - drawW) / 2),
			math.floor((self.height - drawH) / 2)
		local exact = SiK.UI.Icon.metadata(source)
			and SiK.UI.Icon.drawExact(self, source, drawX, drawY, drawW, drawH, {
				alpha = tonumber(tint.a or tint.alpha or tint[4]) or 1,
				r = tonumber(tint.r or tint[1]) or 1,
				g = tonumber(tint.g or tint[2]) or 1,
				b = tonumber(tint.b or tint[3]) or 1,
			})
		if not exact then SiK.UI.Icon.draw(self, texture, drawX, drawY, drawW, drawH, {
				aspect = self.iconFit ~= "stretch",
				alpha = tonumber(tint.a or tint.alpha or tint[4]) or 1,
				r = tonumber(tint.r or tint[1]) or 1,
				g = tonumber(tint.g or tint[2]) or 1,
				b = tonumber(tint.b or tint[3]) or 1,
			}) end
	end
	function button:getTexture() return self.texture end
	function button:setTexture(value)
		self.iconSource = value
		self.texture = SiK.UI.Icon.resolve(value)
		return self
	end
	function button:setIconProvider(value) self.iconProvider = value; return self end
	function button:setIconTint(value) self.iconTint = value; return self end
	function button:setIconTintProvider(value) self.iconTintProvider = value; return self end
	function button:setChrome(value) self.chrome = value ~= false; return self end
	return button
end

function Controls.icon(parent, options)
	parent, options = controlArgs(parent, options)
	local panel = decorate(ISPanel:new(options.x or 0, options.y or 0,
		options.w or options.width or 32, options.h or options.height or 32), "icon", options)
	panel:initialise(); if panel.instantiate then panel:instantiate() end
	panel.iconSource = options.icon or options.texture
	panel.texture = SiK.UI.Icon.resolve(panel.iconSource)
	local sourceMeta = SiK.UI.Icon.metadata(panel.iconSource)
	panel.iconSize = tonumber(options.iconSize)
		or (sourceMeta and math.min(n(sourceMeta.width, 1), n(sourceMeta.height, 1)))
		or math.min(panel.width, panel.height)
	panel.tone = options.tone
        -- ISPanel does not expose setMouseTransparent on every B42 UI bridge.
        -- An icon is decorative, so use the API when present and otherwise keep
        -- the panel inert through the mouse callbacks below.  Calling it
        -- unconditionally made every program card refresh fail at runtime.
        if type(panel.setMouseTransparent) == "function" then
                panel:setMouseTransparent(true)
        end
        panel.onMouseDown = function() return false end
        panel.onMouseUp = function() return false end
	local previousRender = panel.render
	panel.render = function(self)
		if type(previousRender) == "function" then previousRender(self) end
		local color = self.tone and SiK.UI.Theme.color(self.tone, options.theme)
			or { r = 1, g = 1, b = 1, a = 1 }
		local size = math.min(self.iconSize, self.width, self.height)
		local x, y = math.floor((self.width - size) / 2), math.floor((self.height - size) / 2)
		local exact = SiK.UI.Icon.metadata(self.iconSource)
			and SiK.UI.Icon.drawExact(self, self.iconSource, x, y, size, size,
				{ r = color.r, g = color.g, b = color.b, alpha = color.a })
		if not exact then
			SiK.UI.Icon.draw(self, self.texture, x, y, size, size,
				{ r = color.r, g = color.g, b = color.b, alpha = color.a })
		end
	end
	function panel:getTexture() return self.texture end
	function panel:setTexture(value)
		self.iconSource = value
		self.texture = SiK.UI.Icon.resolve(value)
		return self
	end
	function panel:setTone(value) self.tone = value; return self end
	function panel:reflow(width, height)
		if width then self:setWidth(width) end
		if height then self:setHeight(height) end
		return self
	end
	attach(parent, panel)
	return panel
end

function Controls.field(parent, options)
        parent, options = controlArgs(parent, options)
        local metrics = Controls.metrics(options.profile)
        local inset = math.max(0, math.floor(n(options.textInset or options.contentInset,
                metrics.controlGap)))
        local field = ISPanel:new(n(options.x, 0), n(options.y, 0),
                math.max(1, n(options.w or options.width, 160)),
                math.max(1, n(options.h or options.height, metrics.inputHeight)))
        field:initialise(); field.drawBackground = false
        field._sikTextInset = inset
        field._sikUiControl = "field"
        local entry = ISTextEntryBox:new(tostring(options.text or ""), inset, 0,
                math.max(1, field.width - inset * 2), field.height)
        entry:initialise()
	-- ISTextEntryBox:setEditable delegates to its Java text box.  Project
	-- Zomboid only creates that object from instantiate(), not initialise().
	-- Controls.field applies its initial enabled state before it is attached, so
	-- the framework must complete the vanilla lifecycle here.
	if entry.instantiate then entry:instantiate() end
        field.prerender = function(self)
                local theme = SiK.UI.Theme.tokens(options.theme)
                local fill = options.enabled == false and theme.background or theme.surface
                self:drawRect(0, 0, self.width, self.height, fill.a, fill.r, fill.g, fill.b)
                self:drawRectBorder(0, 0, self.width, self.height, theme.border.a,
                        theme.border.r, theme.border.g, theme.border.b)
                ISPanel.prerender(self)
        end
        local basePrerender = entry.prerender
        entry.prerender = function(self)
                -- ISTextEntryBox remains only the keyboard/text backend. Its visible
                -- background and border are suppressed; the field owns the final chrome.
                -- The native text rectangle is already inset before this runs, so its
                -- placeholder, caret and selection all use the same symmetric bounds.
                local theme = SiK.UI.Theme.tokens(options.theme)
                self.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
                self.borderColor = { r = 0, g = 0, b = 0, a = 0 }
                self.textColor = { r = theme.text.r, g = theme.text.g,
			b = theme.text.b, a = theme.text.a }
		if type(basePrerender) == "function" then return basePrerender(self) end
	end
	if options.numeric and entry.setOnlyNumbers then entry:setOnlyNumbers(true) end
	if options.maxLength and entry.setMaxTextLength then entry:setMaxTextLength(options.maxLength) end
	-- These are immutable construction descriptors on the public wrapper.  The
	-- native entry remains the only mutable input backend.
	field.onlyNumbers = options.numeric == true
	field.maxLength = options.maxLength
	if options.placeholder and entry.setPlaceholderText then
		entry:setPlaceholderText(tostring(options.placeholder))
	end
        function field:getText()
                return entry.getText and entry:getText() or entry.text
        end
        function field:setText(value)
                self.text = tostring(value or "")
                if entry.setText then entry:setText(self.text) else entry.text = self.text end
                return self
        end
        function field:setEnabled(value)
                options.enabled = value ~= false
                if entry.setEditable then entry:setEditable(options.enabled) end
                return self
        end
        function field:setEditable(value) return self:setEnabled(value) end
        function field:setOnlyNumbers(value)
                if entry.setOnlyNumbers then entry:setOnlyNumbers(value == true) end
                return self
        end
        function field:setMaxTextLength(value)
                if entry.setMaxTextLength then entry:setMaxTextLength(value) end
                return self
        end
        function field:setPlaceholderText(value)
                if entry.setPlaceholderText then entry:setPlaceholderText(tostring(value or "")) end
                return self
        end
        -- Forward text operations, never native identity or lifecycle. Vanilla
        -- addChild instantiates the panel separately: sharing the entry's Java
        -- object here would make UITextBox2 its own child during rendering.
        local function forward(method)
                return function(self, ...)
                        if type(entry[method]) == "function" then return entry[method](entry, ...) end
                        return nil
                end
        end
        for _, method in ipairs({ "focus", "getInternalText", "selectAll",
                "setTextEntryBox", "setFont" }) do
                field[method] = forward(method)
        end
        field.onTextChange = function(self)
                return callback(self, options, "onChange", self:getText())
        end
        field.onPressEnter = function(self)
                if options.enabled == false then return false end
                return callback(self, options, "onSubmit", self:getText())
        end
        entry.onTextChange = function() return field:onTextChange() end
        entry.onPressEnter = function() return field:onPressEnter() end
        local function reflow(self)
                entry:setX(self._sikTextInset)
                entry:setY(0)
                entry:setWidth(math.max(1, self.width - self._sikTextInset * 2))
                entry:setHeight(self.height)
                return self
        end
        local baseSetWidth, baseSetHeight = field.setWidth, field.setHeight
        field.setWidth = function(self, width)
                baseSetWidth(self, width)
                return reflow(self)
        end
        field.setHeight = function(self, height)
                baseSetHeight(self, height)
                return reflow(self)
        end
        function field:setBounds(x, y, width, height)
                self:setX(x); self:setY(y)
                self:setWidth(width); self:setHeight(height)
                return self
        end
        field.entry = entry
        field:addChild(entry)
        decorate(field, "field", options)
        local fieldDispose = field.dispose
        field.dispose = function(self)
                if self.entry then
                        self:removeChild(self.entry)
                        if self.entry.dispose then self.entry:dispose() end
                        self.entry = nil
                end
                return fieldDispose(self)
        end
        field:setEnabled(options.enabled ~= false)
        reflow(field)
        return attach(parent, field)
end

function Controls.combo(parent, options)
	parent, options = controlArgs(parent, options)
	local combo = SiK.UI.Combo.create({
		x = n(options.x, 0), y = n(options.y, 0),
		w = math.max(1, n(options.w or options.width, 160)),
		h = math.max(1, n(options.h or options.height, Controls.metrics(options.profile).inputHeight)),
		playerNum = options.playerNum, theme = options.theme, enabled = options.enabled,
		maxVisibleRows = options.maxVisibleRows,
		onChange = function(component, item)
			return callback(component, options, "onChange", item)
		end,
	})
	decorate(combo, "combo", options)
	combo:setItems(options.items or options.options or {}, options.selected)
	combo:setEnabled(options.enabled ~= false)
	return attach(parent, combo)
end

local function searchTextInfo(text)
	text = tostring(text or "")
	local count, wide, index, length = 0, false, 1, string.len(text)
	while index <= length do
		local first = string.byte(text, index) or 0
		local size = 1
		if first >= 194 and first <= 223 then size = 2
		elseif first >= 224 and first <= 239 then size = 3; wide = true
		elseif first >= 240 and first <= 244 then size = 4; wide = true end
		count = count + 1
		index = index + size
	end
	return count, wide
end

local function searchNow(panel, options)
	if type(options.now) == "function" then
		return n(options.now(), panel._sikSearchClock or 0)
	end
	if type(getTimestampMs) == "function" then return getTimestampMs() end
	return panel._sikSearchClock or 0
end

local function searchThreshold(options, wide)
	local regular = math.max(0, math.floor(n(options.minChars, 3)))
	local wideValue = math.max(0, math.floor(n(options.wideMinChars, 2)))
	return wide and wideValue or regular
end

--- Returns a query only when it has reached the framework search threshold.
--- The optional thresholds remain declarative: regular text defaults to three
--- characters and wide UTF-8 text to two. Consumers use the raw text when
--- clearing a previous result, and this helper for filtering decisions.
---@param text any
---@param options table|nil
---@return string|nil query
---@return boolean active
function Controls.effectiveSearchQuery(text, options)
	options = type(options) == "table" and options or {}
	local value = tostring(text or "")
	local count, wide = searchTextInfo(value)
	local active = value ~= "" and count >= searchThreshold(options, wide)
	return active and value or nil, active
end

function Controls.search(parent, options)
	parent, options = controlArgs(parent, options)
	local metrics = Controls.metrics(options.profile)
	local panel = ISPanel:new(n(options.x, 0), n(options.y, 0),
		math.max(1, n(options.w or options.width, 240)),
		math.max(1, n(options.h or options.height, metrics.inputHeight)))
	panel:initialise(); panel.drawBackground = false
	decorate(panel, "search", options)
	panel._sikSearchClock = 0
	panel._sikSearchDeadline = nil
	panel._sikSearchLastEffective = false
	panel._sikSearchDebounceMs = math.max(0, n(options.debounceMs, 180))
	local buttonW = panel.height

	local function cancelPending(self)
		self._sikSearchDeadline = nil
		self._sikSearchPendingText = nil
		return self
	end

	local function emitChange(self)
		local text = self.entry and self.entry:getText() or ""
		local _, active = Controls.effectiveSearchQuery(text, options)
		if active then
			self._sikSearchLastEffective = true
			callback(self, options, "onChange", text)
		elseif self._sikSearchLastEffective then
			self._sikSearchLastEffective = false
			callback(self, options, "onChange", text)
		end
		return active
	end

	local function scheduleChange(self)
		cancelPending(self)
		self._sikSearchPendingText = self.entry and self.entry:getText() or ""
		if self._sikSearchDebounceMs <= 0 then return emitChange(self) end
		self._sikSearchDeadline = searchNow(self, options) + self._sikSearchDebounceMs
		return false
	end

	local function submit(self)
		cancelPending(self)
		local text = self.entry and self.entry:getText() or ""
		local _, active = Controls.effectiveSearchQuery(text, options)
		self._sikSearchLastEffective = active
		return callback(self, options, "onSubmit", text)
	end

	panel.entry = Controls.field(panel, {
		x = 0, y = 0, w = math.max(1, panel.width - buttonW - metrics.controlGap), h = panel.height,
		text = options.text, placeholder = options.placeholder, playerNum = options.playerNum,
		payload = options.payload, onChange = function() scheduleChange(panel) end,
	})
	panel.entry.onPressEnter = function() return submit(panel) end
	panel.action = Controls.iconButton(panel, {
		x = panel.width - buttonW, y = 0, w = buttonW, h = panel.height,
		icon = options.icon, text = options.buttonText or "", tooltip = options.tooltip,
		playerNum = options.playerNum, payload = options.payload,
		onClick = function() return submit(panel) end,
	})
	local previousUpdate = panel.update
	panel.update = function(self)
		if type(previousUpdate) == "function" then previousUpdate(self) end
		if self._sikSearchDisposed or not self._sikSearchDeadline then return end
		if type(options.now) ~= "function" and type(getTimestampMs) ~= "function" then
			self._sikSearchClock = self._sikSearchClock
				+ math.max(1, n(options.frameMs, 16))
		end
		if searchNow(self, options) >= self._sikSearchDeadline then
			cancelPending(self)
			emitChange(self)
		end
	end
	local previousSetVisible = panel.setVisible
	panel.setVisible = function(self, visible)
		if visible == false then cancelPending(self) end
		if type(previousSetVisible) == "function" then
			return previousSetVisible(self, visible)
		end
		self.visible = visible == true
	end
	local searchDispose = panel.dispose
	panel.dispose = function(self)
		if self._sikSearchDisposed then return false end
		self._sikSearchDisposed = true
		cancelPending(self)
		if self.entry then self.entry:dispose(); self.entry = nil end
		if self.action then self.action:dispose(); self.action = nil end
		return searchDispose(self)
	end
	function panel:getText() return self.entry:getText() end
	function panel:setText(value) self.entry:setText(tostring(value or "")); return self end
	function panel:cancelPending() return cancelPending(self) end
	function panel:flushChange()
		cancelPending(self)
		return emitChange(self)
	end
	function panel:submit() return submit(self) end
	function panel:setBounds(x, y, width, height)
		self:setX(x); self:setY(y); self:setWidth(width); self:setHeight(height)
		local actionW = height
		self.entry:setX(0); self.entry:setY(0)
		self.entry:setWidth(math.max(1, width - actionW - metrics.controlGap)); self.entry:setHeight(height)
		self.action:setX(width - actionW); self.action:setY(0)
		self.action:setWidth(actionW); self.action:setHeight(height)
		return self
	end
	return attach(parent, panel)
end

function Controls.toggle(parent, options)
	parent, options = controlArgs(parent, options)
	local selected = options.selected == true
	local button
	local function update()
		button._sikSelected = selected
		button.backgroundColor = SiK.UI.Theme.color(selected and "selected" or "surfaceAlt", options.theme)
	end
	local forwarded = {}
	for key, value in pairs(options) do forwarded[key] = value end
	forwarded.onClick = function()
		if options.enabled == false then return end
		selected = not selected; update()
		callback(button, options, "onChange", selected)
	end
	button = Controls.button(parent, forwarded)
	button._sikUiControl = "toggle"
	function button:isSelected() return selected end
	function button:setSelected(value, emit)
		selected = value == true; update()
		if emit then callback(self, options, "onChange", selected) end
		return self
	end
	update()
	return button
end

--- Full-hitbox, wrapping list choice for product-owned records.
--- The control owns presentation only; callers retain selection and data rules.
function Controls.listOption(parent, options)
	parent, options = controlArgs(parent, options)
	local metrics = Controls.metrics(options.profile)
	local font = options.font or UIFont.Small
	local padding = math.max(0, n(options.padding, 8))
	local lineGap = math.max(0, n(options.lineGap, 2))
	local minHeight = math.max(1, n(options.minHeight, metrics.rowHeight))
	local selected = options.selected == true
	local enabled = options.enabled ~= false
	local loading = options.loading == true
	local forwarded = {}
	for key, value in pairs(options) do forwarded[key] = value end
	forwarded.text = ""
	forwarded.h = minHeight
	forwarded.enabled = enabled and not loading
	forwarded.onClick = function(context)
		if not enabled or loading then return false end
		if type(options.onClick) == "function" then return options.onClick(context) end
		return true
	end
	local option = Controls.button(parent, forwarded)
	option._sikUiControl = "listOption"
	option.text = tostring(options.text or "")
	option.lines = {}
	option.selected = selected
	option.loading = loading
	local baseSetEnabled = option.setEnabled

	local function syncState(self)
		baseSetEnabled(self, enabled and not loading)
		self.backgroundColor = SiK.UI.Theme.color(selected and "selected"
			or "surfaceAlt", options.theme)
		self._sikSelected = selected
		self._sikLoading = loading
		return self
	end
	local function reflow(self, width)
		if width ~= nil then self:setWidth(math.max(1, n(width, self.width))) end
		self.lines = Controls.wrapText(self.text,
			math.max(1, self.width - padding * 2), font)
		local lineHeight = fontHeight(font) + lineGap
		self:setHeight(math.max(minHeight,
			#self.lines * lineHeight - lineGap + padding * 2))
		return syncState(self)
	end
	local previousRender = option.render
	option.render = function(self)
		if type(previousRender) == "function" then previousRender(self) end
		local tone = (enabled and not loading) and "text" or "textMuted"
		local color = SiK.UI.Theme.color(tone, options.theme)
		local y = padding
		for index = 1, #self.lines do
			self:drawText(self.lines[index], padding, y,
				color.r, color.g, color.b, color.a, font)
			y = y + fontHeight(font) + lineGap
		end
	end
	function option:setData(data)
		data = data or {}
		if data.text ~= nil then self.text = tostring(data.text) end
		if data.payload ~= nil then options.payload = data.payload
		else options.payload = data end
		self.payload = options.payload
		if data.selected ~= nil then selected = data.selected == true end
		if data.enabled ~= nil then enabled = data.enabled ~= false end
		if data.loading ~= nil then loading = data.loading == true end
		return reflow(self)
	end
	function option:setSelected(value) selected = value == true; return syncState(self) end
	function option:isSelected() return selected end
	function option:setEnabled(value) enabled = value ~= false; return syncState(self) end
	function option:isEnabled() return enabled and not loading end
	function option:setLoading(value) loading = value == true; return syncState(self) end
	function option:isLoading() return loading end
	function option:setText(value) self.text = tostring(value or ""); return reflow(self) end
	function option:reflow(width) return reflow(self, width) end
	reflow(option, option.width)
	return option
end

function Controls.status(parent, options)
	parent, options = controlArgs(parent, options)
	local tone = options.tone or "textMuted"
	local function statusColor(value)
		if type(value) == "table" then
			return { r = n(value.r or value[1], 1), g = n(value.g or value[2], 1),
				b = n(value.b or value[3], 1), a = n(value.a or value[4], 1) }
		end
		return SiK.UI.Theme.color(value or "textMuted", options.theme)
	end
	if options.wrap == true then
		local framed, indicator = options.framed == true, options.indicator == true
		local padX = framed and 10 or 0
		local padY = framed and 6 or 0
		local leading = indicator and 16 or 0
		local lineHeight = fontHeight(options.font or UIFont.Small) + 2
		local panel = Controls.panel(nil, { x = options.x, y = options.y,
			w = options.w or options.width or 200, h = 1, drawBackground = false,
			playerNum = options.playerNum, controlId = "wrappedStatus" })
		panel.text, panel.tone = tostring(options.text or ""), tone
		panel.statusColor = options.color
		function panel:reflow(width)
			if width then self:setWidth(math.max(1, n(width, self.width))) end
			self.lines = Controls.wrapText(self.text, math.max(1, self.width - padX * 2 - leading),
				options.font or UIFont.Small)
			self:setHeight(math.max(framed and 30 or lineHeight, #self.lines * lineHeight + padY * 2))
			return self
		end
		function panel:setStatus(text, nextTone, nextColorValue)
			self.text = tostring(text or "")
			if nextTone ~= nil then self.tone = nextTone; self.statusColor = nil end
			if nextColorValue ~= nil then self.statusColor = nextColorValue end
			return self:reflow()
		end
		panel.prerender = function(self)
			local theme = SiK.UI.Theme.tokens(options.theme)
			local color = statusColor(self.statusColor or self.tone)
			if framed then
				local background, border = theme.surfaceAlt, theme.border
				self:drawRect(0, 0, self.width, self.height, background.a, background.r, background.g, background.b)
				self:drawRectBorder(0, 0, self.width, self.height, border.a, border.r, border.g, border.b)
			end
			if indicator then
				-- Eight-pixel semantic state marker, independent of product assets.
				for row = 0, 7 do
					local inset = (row == 0 or row == 7) and 2 or ((row == 1 or row == 6) and 1 or 0)
					self:drawRect(padX + inset, padY + 4 + row, 8 - inset * 2, 1,
						color.a, color.r, color.g, color.b)
				end
			end
			local textColor = indicator and statusColor(options.textTone or "textMuted") or color
			for index = 1, #self.lines do
				self:drawText(self.lines[index], padX + leading, padY + (index - 1) * lineHeight,
					textColor.r, textColor.g, textColor.b, textColor.a, options.font or UIFont.Small)
			end
		end
		panel:reflow()
		return attach(parent, panel)
	end
	if options.indicator == true then
		local metrics = Controls.metrics(options.profile)
		local width = math.max(1, n(options.w or options.width, 200))
		local height = math.max(1, n(options.h or options.height, metrics.rowHeight))
		local panel = Controls.panel(nil, { x = options.x, y = options.y,
			w = width, h = height, playerNum = options.playerNum,
			payload = options.payload, controlId = "statusIndicator" })
		panel.text = tostring(options.text or "")
		panel.tone = tone
		panel.statusColor = options.color
		panel.textTone = options.textTone or "text"
		panel.textColor = options.textColor
		panel.prerender = function(self)
			local indicatorColor = statusColor(self.statusColor or self.tone or tone)
			local textColor = statusColor(self.textColor or self.textTone or "text")
			local dotSize = 6
			local dotY = math.max(0, math.floor((self.height - dotSize) / 2))
			self:drawRect(2, dotY, dotSize, dotSize, indicatorColor.a,
				indicatorColor.r, indicatorColor.g, indicatorColor.b)
			local text = Controls.truncateText(self.text,
				math.max(1, self.width - 14), options.font or UIFont.Small)
			local textY = math.max(0, math.floor((self.height
				- fontHeight(options.font or UIFont.Small)) / 2))
			self:drawText(text, 14, textY, textColor.r, textColor.g, textColor.b,
				textColor.a, options.font or UIFont.Small)
		end
		function panel:setStatus(text, nextTone, nextColorValue)
			self.text = tostring(text or "")
			if nextTone ~= nil then self.tone = nextTone; self.statusColor = nil end
			if nextColorValue ~= nil then self.statusColor = nextColorValue end
			return self
		end
		function panel:reflow(nextWidth, nextHeight)
			if nextWidth ~= nil then self:setWidth(math.max(1, n(nextWidth, self.width))) end
			if nextHeight ~= nil then self:setHeight(math.max(1, n(nextHeight, self.height))) end
			return self
		end
		return attach(parent, panel)
	end
	if options.framed == true then
		local metrics = Controls.metrics(options.profile)
		local width = math.max(1, n(options.w or options.width, 200))
		local height = math.max(1, n(options.h or options.height, metrics.rowHeight))
		local padding = math.max(0, n(options.padding, 8))
		local panel = ISPanel:new(n(options.x, 0), n(options.y, 0), width, height)
		panel:initialise(); panel.drawBackground = false
		decorate(panel, "status", options)
		panel._sikFramed = true
		panel.text = tostring(options.text or "")
		panel.tone = tone
		panel.statusColor = options.color
		panel.prerender = function(self)
			ISPanel.prerender(self)
			local theme = SiK.UI.Theme.tokens(options.theme)
			local background = options.backgroundColor or theme.surfaceAlt
			local border = options.borderColor or theme.border
			local color = statusColor(self.statusColor or self.tone or tone)
			self:drawRect(0, 0, self.width, self.height, background.a,
				background.r, background.g, background.b)
			self:drawRectBorder(0, 0, self.width, self.height, border.a,
				border.r, border.g, border.b)
			local textY = math.max(0, math.floor((self.height
				- fontHeight(options.font or UIFont.Small)) / 2))
			self:drawText(self.text, padding, textY, color.r, color.g, color.b,
				color.a, options.font or UIFont.Small)
		end
		function panel:setStatus(text, nextTone, nextColorValue)
			self.text = tostring(text or ""); self.tone = nextTone or self.tone
			if nextColorValue ~= nil then self.statusColor = nextColorValue
			elseif nextTone ~= nil then self.statusColor = nil end
			return self
		end
		return attach(parent, panel)
	end
	local color = statusColor(options.color or tone)
	local label = ISLabel:new(n(options.x, 0), n(options.y, 0),
		n(options.h or options.height, fontHeight(options.font or UIFont.Small)),
		tostring(options.text or ""), color.r, color.g, color.b, color.a,
		options.font or UIFont.Small, true)
	label:initialise(); decorate(label, "status", options)
	function label:setStatus(text, nextTone, nextColorValue)
		self.name = tostring(text or ""); self.tone = nextTone or self.tone
		if nextColorValue ~= nil then self.statusColor = nextColorValue
		elseif nextTone ~= nil then self.statusColor = nil end
		local nextColor = statusColor(self.statusColor or self.tone or tone)
		self.r, self.g, self.b, self.a = nextColor.r, nextColor.g, nextColor.b, nextColor.a
		return self
	end
	label.tone = tone
	label.statusColor = options.color
	return attach(parent, label)
end

function Controls.feedback(parent, options)
	parent, options = controlArgs(parent, options)
	local feedbackWidth = math.max(1, n(options.w or options.width, 200))
	local lineHeight = fontHeight(options.font or UIFont.Small) + 3
	local lines = Controls.wrapText(options.text, feedbackWidth - 16,
		options.font or UIFont.Small)
	local automaticHeight = options.h == nil and options.height == nil
	local panel = ISPanel:new(n(options.x, 0), n(options.y, 0),
		feedbackWidth, math.max(1, n(options.h or options.height,
			#lines * lineHeight + 16)))
	panel:initialise(); decorate(panel, "feedback", options)
	panel.tone = options.tone or "info"
	panel.text = tostring(options.text or "")
	panel.lines = lines
	panel.prerender = function(self)
		ISPanel.prerender(self)
		local color = SiK.UI.Theme.color(self.tone, options.theme)
		self:drawRect(0, 0, self.width, self.height, 0.12, color.r, color.g, color.b)
		self:drawRect(0, 0, 3, self.height, 1, color.r, color.g, color.b)
		local y = 8
		for index = 1, #self.lines do
			self:drawText(self.lines[index], 8, y, color.r, color.g, color.b, 1,
				options.font or UIFont.Small)
			y = y + lineHeight
		end
	end
	function panel:setFeedback(text, tone)
		self.text = tostring(text or ""); self.tone = tone or self.tone
		self.lines = Controls.wrapText(self.text, math.max(1, self.width - 16),
			options.font or UIFont.Small)
		if automaticHeight then self:setHeight(#self.lines * lineHeight + 16) end
		return self
	end
	function panel:reflow(width)
		if width then self:setWidth(width) end
		self.lines = Controls.wrapText(self.text, math.max(1, self.width - 16),
			options.font or UIFont.Small)
		if automaticHeight then self:setHeight(#self.lines * lineHeight + 16) end
		return self
	end
	return attach(parent, panel)
end

--- Canonical progress indicator with a framework-owned semantic tone.
function Controls.progress(parent, options)
	parent, options = controlArgs(parent, options)
	local metrics = Controls.metrics(options.profile)
	local panel = Controls.panel(nil, {
		x = options.x, y = options.y,
		w = options.w or options.width or 200,
		h = options.h or options.height or math.max(8, math.floor(metrics.rowHeight / 3)),
		playerNum = options.playerNum, payload = options.payload,
		controlId = "progress",
	})
	panel.value = math.max(0, math.min(1, n(options.value, 0)))
	panel.label = tostring(options.label or "")
	panel.tone = options.tone
	panel.status = options.status
	panel.mode = options.mode == "indeterminate" and "indeterminate" or "determinate"
	panel.progressColor = options.color
	panel.prerender = function(self)
		local theme = SiK.UI.Theme.tokens(options.theme)
		local tone = self.tone
		if tone == nil and self.status ~= nil then
			local map = { ok = "success", success = "success", warning = "warning",
				critical = "danger", full = "danger", danger = "danger" }
			tone = map[tostring(self.status)] or "textMuted"
		elseif tone == nil then
			tone = self.value >= 0.9 and "danger"
				or (self.value >= 0.75 and "warning" or "success")
		end
		local fill = SiK.UI.Theme.normalizeColor(self.progressColor,
			SiK.UI.Theme.color(tone, options.theme))
		self:drawRect(0, 0, self.width, self.height, 1,
			theme.background.r, theme.background.g, theme.background.b)
		local fillWidth = math.floor(math.max(0, self.width - 2) * self.value)
		local fillX = 1
		if self.mode == "indeterminate" then
			fillWidth = math.max(2, math.floor(math.max(0, self.width - 2) * 0.32))
			self._sikProgressPhase = ((self._sikProgressPhase or 0) + 1) % math.max(1, self.width)
			fillX = 1 + math.min(math.max(0, self.width - 2 - fillWidth), self._sikProgressPhase)
		end
		if fillWidth > 0 then
			self:drawRect(fillX, 1, fillWidth, math.max(0, self.height - 2),
				n(fill.a or fill[4], 1), n(fill.r or fill[1], 1),
				n(fill.g or fill[2], 1), n(fill.b or fill[3], 1))
		end
		self:drawRectBorder(0, 0, self.width, self.height, theme.border.a,
			theme.border.r, theme.border.g, theme.border.b)
		if self.label ~= "" then
			local y = math.max(0, math.floor((self.height - fontHeight(UIFont.Small)) / 2))
			self:drawTextCentre(self.label, math.floor(self.width / 2), y,
				theme.text.r, theme.text.g, theme.text.b, theme.text.a, UIFont.Small)
		end
	end
	function panel:setValue(value, label, tone)
		self.value = math.max(0, math.min(1, n(value, 0)))
		if label ~= nil then self.label = tostring(label) end
		if tone ~= nil then self.tone = tone end
		return self
	end
	function panel:setProgress(spec)
		spec = type(spec) == "table" and spec or { value = spec }
		if spec.value ~= nil then self.value = math.max(0, math.min(1, n(spec.value, 0))) end
		if spec.label ~= nil then self.label = tostring(spec.label) end
		if spec.status ~= nil then self.status = spec.status; self.tone = spec.tone end
		if spec.tone ~= nil then self.tone = spec.tone end
		if spec.mode ~= nil then self.mode = spec.mode == "indeterminate" and "indeterminate" or "determinate" end
		return self
	end
	function panel:reflow(width, height)
		if width ~= nil then self:setWidth(math.max(1, n(width, self.width))) end
		if height ~= nil then self:setHeight(math.max(1, n(height, self.height))) end
		return self
	end
	return attach(parent, panel)
end

--- Neutral icon-plus-message row. Product code supplies the message and asset;
--- this component only guarantees the 1:1 symbol slot and centred text baseline.
function Controls.alertRow(parent, options)
        parent, options = controlArgs(parent, options)
        local size = math.max(1, n(options.size, 24))
        local gap = math.max(0, n(options.gap, 8))
        local font = options.font or UIFont.Small
        local lineGap = math.max(0, n(options.lineGap, 2))
        local panel = Controls.panel(nil, { x = options.x, y = options.y,
                w = options.w or options.width or 240, h = options.h or options.height or size,
		playerNum = options.playerNum, controlId = "alertRow", tooltip = options.tooltip })
	panel.icon, panel.text, panel.severity = options.icon or options.texture,
		tostring(options.text or ""), options.severity or "warning"
        panel.glow = options.glow == true
        panel.tone = options.tone or "text"
        panel.lines = {}
	panel.progress = nil
	local progressWidth = 72
	local progressHeight = 10
	local progressGap = 8
	local minInlineTextWidth = 80
	local function removeProgress(self)
		if not self.progress then return end
		self:removeChild(self.progress)
		if self.progress.dispose then self.progress:dispose() end
		self.progress = nil
	end
	local function setProgress(self, spec)
		if spec == false then
			removeProgress(self)
			return self
		end
		if type(spec) ~= "table" then return self end
		if not self.progress then
			self.progress = Controls.progress(self, { w = progressWidth, h = progressHeight,
				value = spec.value, status = spec.status, tone = spec.tone,
				mode = spec.mode, theme = options.theme, label = "" })
		else
			self.progress:setProgress(spec)
		end
		self.progress.label = ""
		return self
	end
        local function reflow(self, width)
                if width ~= nil then self:setWidth(math.max(1, n(width, self.width))) end
		local textX = size + gap
		local available = math.max(1, self.width - textX)
		local inline = self.progress ~= nil
			and available - progressWidth - progressGap >= minInlineTextWidth
		local textWidth = inline and available - progressWidth - progressGap or available
                self.lines = Controls.wrapText(self.text, textWidth, font)
                local textHeight = #self.lines * fontHeight(font)
                        + math.max(0, #self.lines - 1) * lineGap
		self._sikAlertTextX = textX
		self._sikAlertTextWidth = textWidth
		self._sikAlertInlineProgress = inline
		if self.progress then
			local barWidth = math.max(1, math.min(progressWidth, self.width))
			self.progress:setWidth(barWidth)
			self.progress:setHeight(progressHeight)
			self.progress:setX(math.max(0, self.width - barWidth))
			if inline then
				self:setHeight(math.max(size, textHeight, progressHeight))
				self.progress:setY(math.max(0, math.floor((self.height - progressHeight) / 2)))
			else
				self:setHeight(math.max(size, textHeight) + progressGap + progressHeight)
				self.progress:setY(self.height - progressHeight)
			end
		else
			self:setHeight(math.max(size, textHeight))
		end
                return self
        end
        panel.prerender = function(self)
                local color = SiK.UI.Theme.color(self.severity == "danger" and "danger" or "warning", options.theme)
                local y = math.floor((self.height - size) / 2)
		if self.icon then
			if self.glow == true then Icon.draw(self, self.icon, 0, y, size, size,
				{ alpha = 0.28, r = color.r, g = color.g, b = color.b }) end
			-- Framework symbols are shipped pre-sized.  A mismatched source is a
			-- packaging error; never hide it with a blurred runtime rescale.
			Icon.drawExact(self, self.icon, 0, y, size, size)
		end
                local textColor = SiK.UI.Theme.color(self.tone, options.theme)
                local textHeight = #self.lines * fontHeight(font)
                        + math.max(0, #self.lines - 1) * lineGap
                local textY = math.floor((self.height - textHeight) / 2)
		if self.progress and not self._sikAlertInlineProgress then textY = 0 end
                for index = 1, #self.lines do
			self:drawText(self.lines[index], self._sikAlertTextX, textY,
                                textColor.r, textColor.g, textColor.b, textColor.a, font)
                        textY = textY + fontHeight(font) + lineGap
                end
        end
	function panel:setAlert(spec)
		spec = type(spec) == "table" and spec or { text = spec }
		if spec.text ~= nil then self.text = tostring(spec.text) end
		if spec.icon ~= nil then self.icon = spec.icon end
                if spec.severity ~= nil then self.severity = spec.severity end
                if spec.glow ~= nil then self.glow = spec.glow == true end
                if spec.tone ~= nil then self.tone = spec.tone end
		if spec.progress ~= nil then setProgress(self, spec.progress) end
                return reflow(self)
        end
	local previousDispose = panel.dispose
	panel.dispose = function(self)
		if self._sikAlertRowDisposed then return false end
		self._sikAlertRowDisposed = true
		removeProgress(self)
		return previousDispose(self)
	end
	setProgress(panel, options.progress)
        panel.reflow = function(self, width) return reflow(self, width) end
        reflow(panel)
        return attach(parent, panel)
end

--- Compact removable row used by rule chips and other atomic selections.
--- The row owns its close control; callers only provide the semantic removal.
function Controls.dismissibleRow(parent, options)
	parent, options = controlArgs(parent, options)
	local metrics = Controls.metrics(options.profile)
	local pad, gap = math.max(0, n(options.padding, 8)), math.max(0, n(options.gap, 8))
	local closeSize = math.max(1, n(options.closeSize, metrics.buttonHeight))
	local height = math.max(closeSize + pad * 2, n(options.h or options.height, metrics.buttonHeight + pad * 2))
	local tooltip = options.tooltip or tostring(options.text or "")
	local panel = Controls.panel(nil, { x = options.x, y = options.y,
		w = math.max(1, n(options.w or options.width, 240)), h = height,
		playerNum = options.playerNum, controlId = "dismissibleRow", tooltip = tooltip })
	panel.text = tostring(options.text or "")
	panel.tone, panel.padding, panel.gap, panel.closeSize = options.tone or "text", pad, gap, closeSize
	panel.prerender = function(self)
		local theme = SiK.UI.Theme.tokens(options.theme)
		self:drawRect(0, 0, self.width, self.height, theme.surfaceAlt.a, theme.surfaceAlt.r, theme.surfaceAlt.g, theme.surfaceAlt.b)
		self:drawRectBorder(0, 0, self.width, self.height, theme.border.a, theme.border.r, theme.border.g, theme.border.b)
		local closeW = math.min(self.closeSize, math.max(0, self.width - self.padding))
		local available = math.max(0, self.width - self.padding * 2 - closeW - self.gap)
		if available < 1 then return end
		local text = Controls.truncateText(self.text, available, options.font or UIFont.Small)
		local color = SiK.UI.Theme.color(self.tone, options.theme)
		local _, y = Controls.textPosition({ x = self.padding, y = 0, w = available, h = self.height }, text,
			{ font = options.font or UIFont.Small, align = "left", verticalAlign = "middle" })
		self:drawText(text, self.padding, y, color.r, color.g, color.b, color.a, options.font or UIFont.Small)
	end
	panel.close = Controls.button(nil, { x = 0, y = 0, w = closeSize, h = closeSize, text = "",
		leadingIcon = "sik.close.18", iconSize = 18, fullWidth = true, playerNum = options.playerNum,
		tooltip = options.actionTooltip or tooltip, onClick = function() return callback(panel, options, "onRemove") end })
	panel:addChild(panel.close)
	function panel:reflow(width)
		if width then self:setWidth(math.max(1, n(width, self.width))) end
		local closeW = math.min(self.closeSize, math.max(0, self.width - self.padding))
		self.close:setWidth(closeW)
		self.close:setX(math.max(0, self.width - self.padding - closeW))
		self.close:setY(math.floor((self.height - self.closeSize) / 2))
		return self
	end
	local previousDispose = panel.dispose
	function panel:dispose()
		if self._sikDismissibleDisposed then return false end
		self._sikDismissibleDisposed = true
		if self.close then self:removeChild(self.close); if self.close.dispose then self.close:dispose() end; self.close = nil end
		if type(previousDispose) == "function" then previousDispose(self) end
		return true
	end
	panel:reflow()
	return attach(parent, panel)
end

function Controls.dismissibleRowHeight(options)
	options = options or {}
	local metrics = Controls.metrics(options.profile)
	local pad = math.max(0, n(options.padding, 8))
	local closeSize = math.max(1, n(options.closeSize, metrics.buttonHeight))
	return math.max(closeSize + pad * 2, n(options.h or options.height, metrics.buttonHeight + pad * 2))
end

function Controls.headerOperation(parent, options)
	parent, options = controlArgs(parent, options)
	local label = tostring(options.label or "")
	local progressWidth = math.max(24, n(options.progressWidth, 72))
	local progressHeight = math.max(1, n(options.progressHeight, 10))
	local labelGap = math.max(0, n(options.labelGap, Controls.metrics(options.profile).controlGap))
	local font = options.font or UIFont.Small
	local height = math.max(fontHeight(font), n(options.h or options.height, 16))
	local width = n(options.w or options.width,
		Controls.measureButtonWidth(label, font, 0, 1)
			+ (options.showProgress ~= false and labelGap + progressWidth or 0))
	local panel = Controls.panel(nil, { x = options.x, y = options.y, w = width, h = height,
		playerNum = options.playerNum, controlId = "headerOperation" })
	panel.label = label
	panel.labelGap = labelGap
	panel.showProgress = options.showProgress ~= false
	panel.progress = Controls.progress(panel, { x = math.max(0, width - progressWidth), y = math.max(0, math.floor((height - progressHeight) / 2)),
		w = progressWidth, h = progressHeight, value = options.value, status = options.status, tone = options.tone,
		mode = options.mode, theme = options.theme, label = "" })
	-- The label owns the only local stencil. It must be a sibling of progress:
	-- a stencil on the operation panel would also clip the right-hand bar during
	-- the child pass.
	panel.labelClip = Controls.panel(panel, { x = 0, y = 0, w = 1, h = height,
		playerNum = options.playerNum, controlId = "headerOperationLabel" })
	panel._sikNaturalWidth = width
	local function reflowOperation(self)
		local barW = self.showProgress and math.min(progressWidth, math.max(1, self.width)) or 0
		local barX = math.max(0, self.width - barW)
		self.progress:setVisible(self.showProgress)
		self.progress:setX(barX)
		self.progress:setY(math.max(0, math.floor((self.height - progressHeight) / 2)))
		self.progress:setWidth(math.max(1, barW))
		self.progress:setHeight(math.min(progressHeight, math.max(1, self.height)))
		local labelW = self.showProgress and math.max(0, barX - self.labelGap) or self.width
		self.labelRect = { x = 0, y = 0, w = labelW, h = self.height }
		self.labelClip:setX(0)
		self.labelClip:setY(0)
		self.labelClip:setWidth(math.max(1, labelW))
		self.labelClip:setHeight(self.height)
		self.labelClip:setVisible(labelW > 0)
	end
	panel.labelClip.prerender = function(self)
		local owner = panel
		self._sikHeaderOperationStencil = false
		if owner.labelRect.w < 1 then return end
		local color = SiK.UI.Theme.color("textMuted", options.theme)
		local fitted = Controls.truncateText(owner.label, owner.labelRect.w, font)
		if fitted == "" then return end
		if self.setStencilRect then
			self:setStencilRect(0, 0, self.width, self.height)
			self._sikHeaderOperationStencil = true
		end
		self:drawText(fitted, 0, math.floor((self.height - fontHeight(font)) / 2), color.r, color.g, color.b, color.a, font)
	end
	panel.labelClip.render = function(self)
		if self._sikHeaderOperationStencil and self.clearStencilRect then self:clearStencilRect() end
		self._sikHeaderOperationStencil = false
	end
	panel.prerender = function(self) reflowOperation(self) end
	function panel:setOperation(spec)
		spec = type(spec) == "table" and spec or { label = spec }
		if spec.label ~= nil then self.label = tostring(spec.label) end
		if spec.showProgress ~= nil then self.showProgress = spec.showProgress ~= false end
		-- The operation owns the text. Passing the complete operation spec to the
		-- nested progress bar also copied `label` into it, so every refresh painted
		-- the same message twice (once here and once centred over the bar).
		self.progress:setProgress({
			value = spec.value,
			status = spec.status,
			tone = spec.tone,
			mode = spec.mode,
		})
		self.progress.label = ""
		self._sikNaturalWidth = Controls.measureButtonWidth(self.label, font, 0, 1)
			+ (self.showProgress and self.labelGap + progressWidth or 0)
		reflowOperation(self)
		return self
	end
	function panel:reflow(nextWidth, nextHeight)
		if nextWidth ~= nil then self:setWidth(math.max(1, n(nextWidth, self.width))) end
		if nextHeight ~= nil then self:setHeight(math.max(1, n(nextHeight, self.height))) end
		reflowOperation(self)
		return self
	end
	return attach(parent, panel)
end

function Controls.copyText(parent, options)
	parent, options = controlArgs(parent, options)
	local width = math.max(1, n(options.w or options.width, 240))
	local font = options.font or UIFont.Small
	local lineHeight = fontHeight(font) + math.max(0, n(options.lineGap, 3))
	local panel = Controls.panel(parent, { x = options.x, y = options.y, w = width,
		h = lineHeight, playerNum = options.playerNum, payload = options.payload,
		controlId = "copyText" })
	panel.text = tostring(options.text or "")
	panel.font = font
	panel.tone = options.tone or "textMuted"
	panel.align = options.align or "left"
	panel.verticalAlign = options.verticalAlign or "top"
	local function rewrap(self)
		self.lines = Controls.wrapText(self.text, math.max(1, self.width), self.font)
		self:setHeight(math.max(fontHeight(self.font), #self.lines * lineHeight))
	end
	panel.prerender = function(self)
		local color = SiK.UI.Theme.color(self.tone, options.theme)
		local totalHeight = #self.lines * lineHeight - math.max(0, n(options.lineGap, 3))
		local y = Controls.alignOffset(self.height, totalHeight, self.verticalAlign,
			options.paddingY, options.paddingBottom)
		for index = 1, #self.lines do
			local line = self.lines[index]
			local x = Controls.textPosition({ x = 0, y = 0, w = self.width, h = lineHeight },
				line, { font = self.font, align = self.align,
					paddingX = options.paddingX, paddingRight = options.paddingRight })
			self:drawText(line, x, y,
				color.r, color.g, color.b, color.a, self.font)
			y = y + lineHeight
		end
	end
	function panel:setText(value) self.text = tostring(value or ""); rewrap(self); return self end
	function panel:reflow(nextWidth)
		if nextWidth then self:setWidth(math.max(1, nextWidth)) end
		rewrap(self); return self
	end
	function panel:setAlignment(align, verticalAlign)
		if align ~= nil then self.align = align end
		if verticalAlign ~= nil then self.verticalAlign = verticalAlign end
		return self
	end
	rewrap(panel)
	return panel
end

Controls.copy = Controls.copyText

function Controls.sectionTitle(parent, options)
	parent, options = controlArgs(parent, options)
	local metrics = Controls.metrics(options.profile)
	local font = options.font or UIFont.Small
	local labelHeight = fontHeight(font)
	local hasInfo = options.tooltip ~= nil or options.info ~= nil
	local requestedHeight = n(options.h or options.height, metrics.rowHeight)
	local infoSpec = type(options.info) == "table" and options.info or {}
	local infoHeight = hasInfo and math.max(24, n(infoSpec.size, 24)) or 0
	local panel = ISPanel:new(n(options.x, 0), n(options.y, 0),
		math.max(1, n(options.w or options.width, 200)),
		math.max(1, requestedHeight, labelHeight, infoHeight))
	panel:initialise(); panel.drawBackground = false
	-- A section title is geometry, not a nested card. ISPanel keeps a visible
	-- vanilla border unless both colours are cleared, which used to draw boxes
	-- around window titles and BlockHeader labels.
	panel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	-- The title itself is geometry. Help belongs exclusively to the leading info
	-- control; attaching the same tooltip to this full-width parent created a
	-- second compact tooltip which raced the informational one on hover.
	local titleOptions = {}
	for key, value in pairs(options) do
		if key ~= "tooltip" and key ~= "tooltipProfile" and key ~= "tooltipMaxWidth"
			and key ~= "tooltipPlacement" and key ~= "tooltipChannel" then
			titleOptions[key] = value
		end
	end
	decorate(panel, "sectionTitle", titleOptions)
	local color = SiK.UI.Theme.color("text", options.theme)
	local cursorX = 0
	if hasInfo then
		local info = infoSpec
		-- Framework symbols are pre-sized; preserve the exact 24 px source.
		local size = math.min(panel.height, math.max(24, n(info.size, 24)))
		panel.info = Controls.iconButton(panel, {
			x = 0, y = math.floor((panel.height - size) / 2), w = size, h = size,
			icon = info.icon or options.infoIcon or DEFAULT_INFO_ICON,
			text = "", chrome = false, iconPadding = 0, iconSize = size,
			tooltip = info.tooltip or options.tooltip, playerNum = options.playerNum,
			tooltipProfile = info.profile or options.infoTooltipProfile or "informational",
			tooltipKind = info.kind or options.infoTooltipKind or "descriptive",
			tooltipMaxWidth = info.maxWidth or options.infoTooltipMaxWidth,
			tooltipPlacement = info.placement or options.infoTooltipPlacement
				or { anchor = "pointer", gap = 16 },
			tooltipChannel = info.channel or "informational-help",
			payload = info.payload, onClick = info.onClick,
		})
		cursorX = size + metrics.controlGap
	end
	panel._sikFullText = tostring(options.text or "")
	panel.align = options.align or "left"
	panel.verticalAlign = options.verticalAlign or "middle"
	panel.label = ISLabel:new(cursorX, math.floor((panel.height - labelHeight) / 2),
		labelHeight, panel._sikFullText,
		color.r, color.g, color.b, color.a, font, true)
	panel.label:initialise(); panel:addChild(panel.label)
	local action = options.action
	if action then
		local actionOptions = type(action) == "table" and action or { onClick = action }
		local size = math.min(panel.height, n(actionOptions.size, panel.height))
		panel.action = Controls.iconButton(panel, {
			x = panel.width - size, y = 0, w = size, h = size,
			icon = actionOptions.icon, text = actionOptions.text,
			tooltip = actionOptions.tooltip, playerNum = options.playerNum,
			payload = actionOptions.payload, onClick = actionOptions.onClick,
		})
	end
	local titleDispose = panel.dispose
	panel.dispose = function(self)
		if self._sikTitleDisposed then return false end
		self._sikTitleDisposed = true
		if self.action then self.action:dispose(); self.action = nil end
		if self.info then self.info:dispose(); self.info = nil end
		if self.label then removeChild(self, self.label); self.label = nil end
		return titleDispose(self)
	end
	function panel:_syncLabelText(availableWidth)
		local fitted = Controls.truncateText(self._sikFullText,
			math.max(0, n(availableWidth, self.label.width or 0)), font)
		if self.label.setName then self.label:setName(fitted) else self.label.name = fitted end
		return fitted
	end
	function panel:setText(value)
		self._sikFullText = tostring(value or "")
		self:_syncLabelText(self.label.width or 0)
		return self
	end
	function panel:reflow(width)
		if width then self:setWidth(width) end
		local left = self.info and self.info.width + metrics.controlGap or 0
		local right = 0
		if self.info then self.info:setY(math.floor((self.height - self.info.height) / 2)) end
		if self.action then
			self.action:setX(self.width - self.action.width)
			self.action:setY(math.floor((self.height - self.action.height) / 2))
			right = self.action.width + metrics.controlGap
		end
		local labelWidth = math.max(1, self.width - left - right)
		self.label:setWidth(labelWidth)
		local fitted = self:_syncLabelText(labelWidth)
		local textX, textY = Controls.textPosition({ x = left, y = 0,
			w = labelWidth, h = self.height }, fitted, { font = font,
			align = self.align, verticalAlign = self.verticalAlign })
		self.label:setX(textX)
		self.label:setY(textY)
		self.label:setHeight(labelHeight)
		return self
	end
	function panel:setAlignment(align, verticalAlign)
		if align ~= nil then self.align = align end
		if verticalAlign ~= nil then self.verticalAlign = verticalAlign end
		return self:reflow(self.width)
	end
	panel:reflow(panel.width)
	return attach(parent, panel)
end

function Controls.blockHeader(parent, options)
	parent, options = controlArgs(parent, options)
	local baseOptions = {}
	for key, value in pairs(options) do baseOptions[key] = value end
	baseOptions.action = nil
	baseOptions.actions = nil
	local header = Controls.sectionTitle(parent, baseOptions)
	header._sikUiControl = "blockHeader"
	header.actionControls = {}
	header._sikHeaderOptions = options
	local titleDispose = header.dispose

	local function actionWidth(descriptor)
		local height = header.height
		if descriptor.icon and not descriptor.text then return height end
		return Controls.measureButtonWidth(descriptor.text or "", options.font,
			descriptor.padding or 20, descriptor.minWidth or height,
			descriptor.maxWidth)
	end

	local function createAction(descriptor)
		local controlOptions = {
			x = 0, y = 0, w = actionWidth(descriptor), h = header.height,
			text = descriptor.text or "", icon = descriptor.icon,
			tooltip = descriptor.tooltip, enabled = descriptor.enabled ~= false,
			tone = descriptor.tone, playerNum = options.playerNum,
			onClick = function()
				if descriptor.enabled == false then return false end
				if type(descriptor.onClick) == "function" then
					return descriptor.onClick(descriptor.payload, descriptor)
				end
				if type(options.onActivate) ~= "function" then return true end
				return options.onActivate({ id = descriptor.id,
					payload = descriptor.payload })
			end,
		}
		local control = descriptor.icon and Controls.iconButton(header, controlOptions)
			or Controls.button(header, controlOptions)
		control._sikActionId = descriptor.id
		control._sikPreferredWidth = control.width
		return control
	end

	function header:setActions(actions)
		if self._sikBlockHeaderDisposed then return nil, "disposed" end
		for index = 1, #(self.actionControls or {}) do
			self.actionControls[index]:dispose()
		end
		self.actionControls = {}
		for index = 1, #(actions or {}) do
			local descriptor = actions[index]
			if type(descriptor) == "table" then
				local normalized = descriptor
				if descriptor.id == nil then
					normalized = {}
					for key, value in pairs(descriptor) do normalized[key] = value end
					normalized.id = "action-" .. tostring(index)
				end
				self.actionControls[#self.actionControls + 1] = createAction(normalized)
			end
		end
		self.action = #self.actionControls == 1 and self.actionControls[1] or nil
		return self:reflow(self.width)
	end

	-- Read-only contextual indicator: Info -> Indicator -> Title -> Actions.
	-- The consumer owns its meaning and text; removing it releases its slot.
	function header:setLeadingIndicator(descriptor)
		if self._sikBlockHeaderDisposed then return nil, "disposed" end
		if type(descriptor) ~= "table" or descriptor.icon == nil then
			if self.leadingIndicator then self.leadingIndicator:dispose() end
			self.leadingIndicator = nil
			return self:reflow(self.width)
		end
		local tooltipOptions = {
			kind = "descriptive", tooltipProfile = "informational",
			tooltipChannel = "informational-help",
			tooltipPlacement = { anchor = "pointer", gap = 16 },
			playerNum = options.playerNum,
		}
		if not self.leadingIndicator then
			self.leadingIndicator = Controls.iconButton(self, {
				x = 0, y = 0, w = 24, h = 24, icon = descriptor.icon,
				text = "", chrome = false, iconPadding = 0, iconSize = 24,
				tooltip = descriptor.tooltip, tooltipKind = tooltipOptions.kind,
				tooltipProfile = tooltipOptions.tooltipProfile,
				tooltipChannel = tooltipOptions.tooltipChannel,
				tooltipPlacement = tooltipOptions.tooltipPlacement, playerNum = options.playerNum,
				onClick = function() return true end,
			})
		else
			self.leadingIndicator:setTexture(descriptor.icon)
			Controls.setTooltip(self.leadingIndicator, descriptor.tooltip, tooltipOptions)
		end
		self.leadingIndicator:setIconTint(descriptor.severity
			and SiK.UI.Theme.color(descriptor.severity, options.theme) or nil)
		return self:reflow(self.width)
	end

	function header:reflow(width)
		if width ~= nil then self:setWidth(math.max(1, n(width, self.width))) end
		local left = self.info and self.info.width + Controls.metrics(options.profile).controlGap or 0
		local right = self.width
		local gap = Controls.metrics(options.profile).controlGap
		if self.info then self.info:setY(math.floor((self.height - self.info.height) / 2)) end
		if self.leadingIndicator then
			self.leadingIndicator:setX(left)
			self.leadingIndicator:setY(math.floor((self.height - self.leadingIndicator.height) / 2))
			left = left + self.leadingIndicator.width + gap
		end
		local count = #self.actionControls
		local available = math.max(count, self.width - left - 1
			- (count > 0 and gap * count or 0))
		local preferred = 0
		for index = 1, count do
			preferred = preferred + (self.actionControls[index]._sikPreferredWidth
				or self.actionControls[index].width)
		end
		local scale = preferred > available and available / math.max(1, preferred) or 1
		for index = 1, count do
			local control = self.actionControls[index]
			control:setWidth(math.max(1, math.floor((control._sikPreferredWidth
				or control.width) * scale)))
		end
		for index = #self.actionControls, 1, -1 do
			local control = self.actionControls[index]
			control:setHeight(self.height)
			right = right - control.width
			control:setX(math.max(0, right)); control:setY(0)
			right = right - gap
		end
		self.label:setX(left)
		local labelWidth = math.max(1, right - left)
		self.label:setWidth(labelWidth)
		self:_syncLabelText(labelWidth)
		return self
	end

	header.dispose = function(self)
		if self._sikBlockHeaderDisposed then return false end
		self._sikBlockHeaderDisposed = true
		if self.leadingIndicator then self.leadingIndicator:dispose(); self.leadingIndicator = nil end
		for index = 1, #(self.actionControls or {}) do
			self.actionControls[index]:dispose()
		end
		self.actionControls, self.action = nil, nil
		return titleDispose(self)
	end
	local actions = options.actions
	if actions == nil and options.action ~= nil then
		local descriptor = type(options.action) == "table" and options.action
			or { onClick = options.action }
		actions = { descriptor }
	end
	header:setActions(actions or {})
	header:setLeadingIndicator(options.leadingIndicator)
	return header
end

local function requirementTone(state, tone)
	if tone ~= nil then return tone end
	if state == true or state == "met" or state == "success" or state == "ok" then
		return "success"
	end
	if state == false or state == "missing" or state == "error" then
		return "danger"
	end
	return state or "text"
end

--- Neutral requirement/status row with optional icon and wrapped copy.
--- Products resolve their own item/perk identifiers and pass a texture or a
--- framework icon key; this control owns only presentation and lifecycle.
function Controls.requirementRow(parent, options)
	parent, options = controlArgs(parent, options)
	local metrics = Controls.metrics(options.profile)
	local font = options.font or UIFont.Small
	local iconSize = math.max(0, n(options.iconSize, metrics.iconSize))
	local gap = math.max(0, n(options.gap, metrics.controlGap))
	local lineGap = math.max(0, n(options.lineGap, 2))
	local minHeight = math.max(1, n(options.minHeight, iconSize))
	local width = math.max(1, n(options.w or options.width, 240))
	local row = ISPanel:new(n(options.x, 0), n(options.y, 0), width, minHeight)
	row:initialise(); row.drawBackground = false
	row.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	row.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	decorate(row, "requirementRow", options)
	row.text = tostring(options.text or "")
	row.state = options.state
	if row.state == nil then row.state = options.met end
	row.tone = requirementTone(row.state, options.tone)
	row.texture = SiK.UI.Icon.resolve(options.icon or options.texture)
	row.lines = {}

	local function reflow(self)
		local textX = self.texture and (iconSize + gap) or 0
		local textWidth = math.max(1, self.width - textX)
		self.lines = Controls.wrapText(self.text, textWidth, font)
		local textHeight = #self.lines * fontHeight(font)
			+ math.max(0, #self.lines - 1) * lineGap
		self:setHeight(math.max(minHeight, self.texture and iconSize or 0, textHeight))
		self._sikTextX = textX
		return self
	end

	row.prerender = function(self)
		ISPanel.prerender(self)
		local color = SiK.UI.Theme.color(self.tone, options.theme)
		if self.texture then
			SiK.UI.Icon.draw(self, self.texture, 0,
				math.max(0, math.floor((self.height - iconSize) / 2)),
				iconSize, iconSize)
		end
		local textHeight = #self.lines * fontHeight(font)
			+ math.max(0, #self.lines - 1) * lineGap
		local y = math.max(0, math.floor((self.height - textHeight) / 2))
		for index = 1, #self.lines do
			self:drawText(self.lines[index], self._sikTextX, y,
				color.r, color.g, color.b, color.a, font)
			y = y + fontHeight(font) + lineGap
		end
	end
	function row:getTexture() return self.texture end
	function row:setData(data)
		data = data or {}
		if data.text ~= nil then self.text = tostring(data.text) end
		if data.icon ~= nil or data.texture ~= nil then
			self.texture = SiK.UI.Icon.resolve(data.icon or data.texture)
		end
		if data.state ~= nil or data.met ~= nil or data.tone ~= nil then
			if data.state ~= nil then self.state = data.state
			elseif data.met ~= nil then self.state = data.met end
			self.tone = requirementTone(self.state, data.tone)
		end
		return reflow(self)
	end
	function row:setState(state, tone)
		self.state = state; self.tone = requirementTone(state, tone)
		return self
	end
	function row:reflow(nextWidth)
		if nextWidth ~= nil then self:setWidth(math.max(1, n(nextWidth, self.width))) end
		return reflow(self)
	end
	if row.setMouseTransparent then row:setMouseTransparent(true) end
	row.onMouseDown = function() return false end
	row.onMouseUp = function() return false end
	reflow(row)
	return attach(parent, row)
end

Controls._constructors = Controls._constructors or {}
for key, value in pairs({ button = Controls.button, iconButton = Controls.iconButton,
	icon = Controls.icon,
	field = Controls.field, combo = Controls.combo, search = Controls.search,
	toggle = Controls.toggle, status = Controls.status, feedback = Controls.feedback,
	sectionTitle = Controls.sectionTitle, panel = Controls.panel, separator = Controls.separator,
	copyText = Controls.copyText,
        blockHeader = Controls.blockHeader, requirementRow = Controls.requirementRow,
        listOption = Controls.listOption,
	progress = Controls.progress, alertRow = Controls.alertRow,
	headerOperation = Controls.headerOperation }) do
	Controls._constructors[key] = value
end

function Controls.create(kind, parent, options)
	local constructor = Controls._constructors[kind]
	if not constructor then return nil, "unknown_control" end
	if options == nil then
		options = parent or {}; options.kind = kind
		return constructor(options)
	end
	return constructor(parent, options)
end

return Controls
