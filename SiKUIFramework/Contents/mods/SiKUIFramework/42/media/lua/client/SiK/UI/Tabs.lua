require "SiK/UI/Namespace"
require "SiK/UI/Controls"
require "SiK/UI/Layout"
require "SiK/UI/Theme"
require "SiK/UI/Icon"
require "SiK/UI/Viewport"

local Tabs = SiK.UI.Tabs or {}
SiK.UI.Namespace.define("Tabs", Tabs)

local function number(value, fallback)
	value = tonumber(value)
	if value == nil or value ~= value then return fallback end
	return value
end

local function visible(widget, value)
	if not widget then return end
	if widget.setVisible then widget:setVisible(value) else widget.visible = value end
end

local function widgetSize(widget, axis)
	if not widget then return 0 end
	local getter = axis == "width" and widget.getWidth or widget.getHeight
	if getter then
		local ok, value = pcall(getter, widget)
		if ok and tonumber(value) then return tonumber(value) end
	end
	return number(widget[axis], 0)
end

local function childBounds(child, rect)
	if not child then return end
	SiK.UI.Layout.apply(child, rect)
end

local function isPinned(item)
	return item and (item.pin == "end" or item.pinned == "end"
		or item.pinned == true or item.footer == true)
end

local function exactIconMainExtent(item, horizontal, padding)
	if not item or item.iconExact ~= true then return 0 end
	local descriptor = item.icon or item.texture
	if type(descriptor) ~= "table" then return 0 end
	local size = horizontal and number(descriptor.width or descriptor.w, 0)
		or number(descriptor.height or descriptor.h, 0)
	return math.max(0, math.floor(size + padding * 2))
end

local function mouseOver(widget)
	return widget and type(widget.isMouseOver) == "function" and widget:isMouseOver()
end

local function tooltipText(item)
	if not item then return nil end
	local alert = item.alert
	if type(alert) == "table" and alert.tooltip ~= nil then return tostring(alert.tooltip) end
	local badge = item.badge
	if type(badge) == "table" and badge.tooltip ~= nil then
		return tostring(badge.tooltip)
	end
	if item.tooltip ~= nil then return tostring(item.tooltip) end
	return nil
end

local function optionTooltipText(item)
	if not item or item.tooltip == nil then return nil end
	return tostring(item.tooltip)
end

local function resolvedColor(value, fallback, theme)
	if type(value) == "table" then
		return { r = number(value.r or value[1], 1),
			g = number(value.g or value[2], 1),
			b = number(value.b or value[3], 1),
			a = number(value.a or value[4], 1) }
	end
	return SiK.UI.Theme.color(value or fallback, theme)
end

local function removeChild(parent, child)
	if not child then return end
	if parent and parent.removeChild then parent:removeChild(child)
	elseif child.removeFromUIManager then child:removeFromUIManager() end
end

local function createSeparator(parent, options)
	local color = resolvedColor(options.separatorColor, "border", options.theme)
	local separator = ISPanel:new(0, 0, 1, math.max(1,
		math.floor(number(options.separatorSize, 1))))
	separator:initialise()
	separator.drawBackground = true
	separator.backgroundColor = color
	separator.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	if separator.setMouseTransparent then separator:setMouseTransparent(true) end
	parent:addChild(separator)
	return separator
end

local function drawTabAlert(button, item, options)
	local alert = item and item.alert
	if type(alert) ~= "table" or alert.visible == false or not (alert.icon or alert.texture) then return end
	local size = math.max(1, math.floor(number(alert.size, 18)))
	local margin = math.max(0, number(alert.margin, 3))
	local x, y = widgetSize(button, "width") - size - margin,
		widgetSize(button, "height") - size - margin
	local color = resolvedColor(alert.color, alert.severity == "danger" and "danger" or "warning", options.theme)
	if alert.glow ~= false then SiK.UI.Icon.draw(button, alert.icon or alert.texture, x, y, size, size,
		{ alpha = 0.28, r = color.r, g = color.g, b = color.b }) end
	-- Alert assets are supplied in their final slot size. Do not blur a bad
	-- package by silently rescaling it at render time.
	SiK.UI.Icon.drawExact(button, alert.icon or alert.texture, x, y, size, size)
end

local function applyTabColors(button, selected, options)
	button.backgroundColor = resolvedColor(selected and options.selectedBackgroundColor
		or options.backgroundColor, selected and "selected" or "surfaceAlt", options.theme)
	button.backgroundColorMouseOver = resolvedColor(options.hoverBackgroundColor,
		"hover", options.theme)
	button.backgroundColorClicked = resolvedColor(options.pressedBackgroundColor,
		"pressed", options.theme)
	button.borderColor = resolvedColor(options.borderColor, "border", options.theme)
end

local function decorateTabButton(button, item, placement, options)
	button._sikTabItem = item
	button._sikTabPlacement = placement
	button.texture = SiK.UI.Icon.resolve(item.icon or item.texture)
	button.iconSize = math.max(1, number(item.iconSize, number(options.iconSize,
		math.min(widgetSize(button, "width"), widgetSize(button, "height"))
			- number(options.iconPadding, 8))))
	button._sikIconOnly = item.iconOnly == true or options.iconOnly == true
	local baseSetSelected = button.setSelected
	button.setSelected = function(self, value, emit)
		baseSetSelected(self, value, emit)
		applyTabColors(self, value == true, options)
		return self
	end
	applyTabColors(button, button._sikSelected == true, options)
	local previousRender = button.render
	button.render = function(self)
		if type(previousRender) == "function" then previousRender(self) end
		local hovered = mouseOver(self)
		local selected = self._sikSelected == true
		local scale = (item.iconExact == true or options.iconExact == true) and 1
			or (hovered and number(options.hoverIconScale, 1.08) or 1)
	local padding = math.max(0, number(options.iconPadding,
		(placement == "left" or placement == "right") and 0 or 4))
		local width, height = widgetSize(self, "width"), widgetSize(self, "height")
		local availableW, availableH = math.max(1, width - padding * 2),
			math.max(1, height - padding * 2)
		local iconSize = options.iconFit == "fill"
			and math.min(availableW, availableH)
			or math.min(self.iconSize * scale, availableW, availableH)
		local exact = item.iconExact == true or options.iconExact == true
		-- Las texturas de producto pueden registrarse de forma perezosa la
		-- primera vez que se solicitan. No convertir un nil transitorio durante
		-- la construcción del rail en un icono vacío permanente: el renderer
		-- exacto resuelve el descriptor en cada frame y el escalable reintenta
		-- hasta recibir la Texture nativa.
		if not exact and not self.texture then
			self.texture = SiK.UI.Icon.resolve(item.icon or item.texture)
		end
		if exact or self.texture then
			-- Exact product artwork is already authored in its final colours. A
			-- semantic multiply tint darkens its halo and transparent edge pixels,
			-- making a 56x56 source look smaller even though the draw rect is exact.
			-- Keep source colours unless the consumer explicitly opts into masking.
			local tintExact = item.tintExact == true or options.tintExact == true
			local tint = exact and not tintExact and { r = 1, g = 1, b = 1, a = 1 }
				or resolvedColor(selected and options.selectedIconColor
					or (hovered and options.hoverIconColor or options.iconColor),
					selected and "accent" or "text", options.theme)
			local draw = exact and SiK.UI.Icon.drawExact or SiK.UI.Icon.draw
			-- The scalable renderer consumes the resolved native Texture. Passing
			-- the descriptor table reaches ISUIElement:drawTextureScaledAspect and
			-- raises once per frame. Exact rendering still needs the descriptor to
			-- verify its declared slot before resolving it internally.
			local drawn, drawReason = draw(self,
				exact and (item.icon or item.texture) or self.texture,
				math.floor((width - iconSize) / 2),
				math.floor((height - iconSize) / 2), iconSize, iconSize,
				{ alpha = tint.a, r = tint.r, g = tint.g, b = tint.b })
			self._sikIconDrawn, self._sikIconDrawReason = drawn == true, drawReason
			self._sikIconDrawWidth, self._sikIconDrawHeight = iconSize, iconSize
			self._sikIconTintMode = exact and (tintExact and "explicit" or "source")
				or "semantic"
		end
		if selected then
			local color = resolvedColor(options.selectedBorderColor, "accent", options.theme)
			if options.selectionStyle == "border" then
				-- PZ rasteriza drawRectBorder sobre el limite recibido. En un rail
				-- pegado al borde del viewport, x=0 deja medio trazo fuera del clip
				-- del padre y la iluminacion izquierda desaparece. Mantener el trazo
				-- completo dentro del slot sin alterar su geometria ni la del icono.
				self:drawRectBorder(1, 1, math.max(0, width - 2),
					math.max(0, height - 2), color.a,
					color.r, color.g, color.b)
			else
				local thickness = math.max(1, number(options.accentSize, 3))
				if self._sikTabPlacement == "bottom" then
					self:drawRect(0, 0, width, thickness, color.a,
						color.r, color.g, color.b)
				elseif self._sikTabPlacement == "left" then
					self:drawRect(width - thickness, 0, thickness, height,
						color.a, color.r, color.g, color.b)
				elseif self._sikTabPlacement == "right" then
					self:drawRect(0, 0, thickness, height, color.a,
						color.r, color.g, color.b)
				else
					self:drawRect(0, height - thickness, width, thickness,
						color.a, color.r, color.g, color.b)
				end
			end
		end
		drawTabAlert(self, self._sikTabItem, options)
	end
	function button:setTabItem(nextItem)
		self._sikTabItem = nextItem
		self.texture = SiK.UI.Icon.resolve(nextItem.icon or nextItem.texture)
		self.iconSize = math.max(1, number(nextItem.iconSize,
			number(options.iconSize, self.iconSize)))
		return self
	end
	return button
end

function Tabs.create(options)
	options = options or {}
	if type(options.parent) ~= "table" then return nil, "invalid_parent" end
	local placement = options.placement or options.orientation or "top"
	if placement == "side" then placement = options.side or "left" end
	if placement ~= "left" and placement ~= "right" and placement ~= "bottom" then
		placement = "top"
	end
	local instance = {
		parent = options.parent,
		playerNum = math.max(0, math.floor(number(options.playerNum, 0))),
		orientation = (placement == "left" or placement == "right") and "side" or "top",
		placement = placement,
		items = {}, buttons = {}, byKey = {}, activeKey = options.activeKey,
		options = options, separator = nil,
	}

	function instance:_clearButtons()
		for index = 1, #self.buttons do self.buttons[index]:dispose() end
		self.buttons, self.byKey = {}, {}
	end

	function instance:_firstEnabledKey()
		for index = 1, #self.items do
			local item = self.items[index]
			if item.enabled ~= false then return item.key or tostring(index) end
		end
		return nil
	end

	function instance:setItems(items)
		if self.disposed then return nil, "disposed" end
		self:_clearButtons(); self.items = items or {}
		local activeExists = false
		for index = 1, #self.items do
			local item = self.items[index]
			local key = item.key or tostring(index)
			if key == self.activeKey and item.enabled ~= false then activeExists = true end
		end
		if not activeExists then self.activeKey = self:_firstEnabledKey() end
		for index = 1, #self.items do
			local item = self.items[index]
			local key = item.key or tostring(index)
			local button
			local tabTooltip = options.tooltipMode == "flyout"
				and optionTooltipText(item) or tooltipText(item)
			button = SiK.UI.Controls.toggle({ parent = self.parent,
				text = (item.iconOnly == true or options.iconOnly == true) and ""
					or (item.text or ""),
				selected = key == self.activeKey,
				tooltip = tabTooltip,
				tooltipProfile = options.tooltipMode == "flyout"
					and (options.tooltipProfile or "option") or options.tooltipProfile,
				tooltipMaxWidth = options.tooltipMode == "flyout"
					and (options.tooltipMaxWidth or 220) or options.tooltipMaxWidth,
				tooltipPlacement = options.tooltipMode == "flyout" and {
					anchor = "control", side = options.tooltipSide or "before",
					gap = options.tooltipGap or 4,
				} or options.tooltipPlacement,
				tooltipChannel = options.tooltipMode == "flyout"
					and (options.tooltipChannel or "option") or options.tooltipChannel,
				enabled = item.enabled ~= false,
				playerNum = self.playerNum, payload = item.payload,
				onChange = function(context)
					if context.value then self:setActive(key, true)
					elseif self.activeKey == key and button then
						button:setSelected(true, false)
					end
				end,
			})
			decorateTabButton(button, item, self.placement, options)
			button._sikTabKey = key
			self.buttons[#self.buttons + 1] = button
			self.byKey[key] = { item = item, button = button }
		end
		if self.activeKey then self:setActive(self.activeKey, false) end
		self:reflow(self.bounds or options.bounds)
		return self
	end

	function instance:setActive(key, emit)
		if self.disposed then return nil, "disposed" end
		if not self.byKey[key] then return nil, "unknown_tab" end
		if self.byKey[key].item.enabled == false then return nil, "disabled_tab" end
		local unchanged = self.activeKey == key and self._activeApplied == true
		self.activeKey = key
		if unchanged then return key end
		for itemKey, entry in pairs(self.byKey) do
			entry.button:setSelected(itemKey == key, false)
			visible(entry.item.content, itemKey == key)
		end
		self._activeApplied = true
		if emit and type(options.onActivate) == "function" then
			options.onActivate(SiK.UI.Namespace.context(self, options, "activate",
				self.byKey[key].item))
		end
		return key
	end

	function instance:updateItem(key, patch)
		if self.disposed then return nil, "disposed" end
		local entry = self.byKey[key]
		if not entry then return nil, "unknown_tab" end
		patch = patch or {}
		for name, value in pairs(patch) do entry.item[name] = value end
		entry.button:setTabItem(entry.item)
		if entry.button.setEnabled then entry.button:setEnabled(entry.item.enabled ~= false) end
		local text = options.tooltipMode == "flyout"
			and optionTooltipText(entry.item) or tooltipText(entry.item)
		if entry.button._sikTooltipHandle then
			entry.button._sikTooltipHandle:setText(text)
		else
			if entry.button.setTooltip then entry.button:setTooltip(text)
			else entry.button.tooltip = text end
		end
		return entry.item
	end

	function instance:getSelectedKey() return self.activeKey end
	function instance:setSelectedKey(key, emit) return self:setActive(key, emit) end
	function instance:getButton(key)
		return self.byKey[key] and self.byKey[key].button or nil
	end
	function instance:hideTooltip()
		for index = 1, #self.buttons do
			local handle = self.buttons[index]._sikTooltipHandle
			if handle and handle.hide then handle:hide() end
		end
		return self
	end

	function instance:setLayoutOptions(nextOptions)
		if self.disposed then return nil, "disposed" end
		for key, value in pairs(nextOptions or {}) do options[key] = value end
		for index = 1, #self.buttons do
			local button = self.buttons[index]
			button.iconSize = math.max(1, number(button._sikTabItem.iconSize,
				number(options.iconSize, button.iconSize)))
		end
		return self:reflow(self.bounds or options.bounds)
	end

	function instance:_layoutSequential(buttons, bounds, horizontal, startAt, extent, gap)
		local cursor = startAt
		for index = 1, #buttons do
			local button = buttons[index]
			if horizontal then
				childBounds(button, { x = cursor, y = bounds.y, w = extent, h = bounds.h })
			else
				childBounds(button, { x = bounds.x, y = cursor, w = bounds.w, h = extent })
			end
			cursor = cursor + extent + gap
		end
		return cursor
	end

	function instance:reflow(bounds)
		if self.disposed then return nil, "disposed" end
		bounds = bounds or options.bounds or { x = options.x or 0, y = options.y or 0,
			w = options.w or options.width or 1, h = options.h or options.height or 1 }
		self.bounds = { x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h }
		local count = #self.buttons
		if count == 0 then return self end
		local profile = SiK.UI.Metrics.profile(bounds.w, options.profile)
		local defaultGap = self.orientation == "side"
			and number(profile.window and profile.window.railGap, 0) or 0
		local gap = math.max(0, number(options.gap or options.itemGap, defaultGap))
		local padding = math.max(0, number(options.padding, 0))
		-- A rail is a contained strip: top and bottom breathing room are not
		-- horizontal shrinkage. Explicit values keep its icon slots fixed.
		local leadingInset = math.max(0, number(options.leadingInset or options.paddingTop,
			self.orientation == "side" and 12 or padding))
		local trailingInset = math.max(0, number(options.trailingInset or options.paddingBottom,
			self.orientation == "side" and 12 or padding))
		local crossInset = math.max(0, number(options.crossInset,
			self.orientation == "side" and 12 or padding))
		local horizontal = self.orientation ~= "side"
		local mainStart, mainEnd = {}, {}
		for index = 1, #self.items do
			local button = self.buttons[index]
			if isPinned(self.items[index]) then mainEnd[#mainEnd + 1] = button
			else mainStart[#mainStart + 1] = button end
		end
		local available = (horizontal and bounds.w or bounds.h) - leadingInset - trailingInset
		local extent = number(options.itemExtent or options.itemWidth or options.itemHeight, nil)
		if extent == nil then
			extent = self.orientation == "side"
				and number(profile.window and profile.window.railItemHeight, profile.rowHeight)
				or math.floor((available - gap * math.max(0, count - 1)) / count)
		end
		extent = math.max(1, math.floor(extent))
		-- Un asset exacto define su slot. Reducir el botón por debajo de sus
		-- metadatos hacía que Icon.drawExact rechazase el dibujo silenciosamente.
		-- El rail crece sobre su eje principal; nunca escala ni recorta la imagen.
		for index = 1, #self.items do
			extent = math.max(extent, exactIconMainExtent(self.items[index], horizontal,
				math.max(0, number(options.iconPadding, 0))))
		end
		local inner = horizontal
			and { x = bounds.x + leadingInset, y = bounds.y + crossInset, w = available,
				h = math.max(1, bounds.h - crossInset * 2) }
			or { x = bounds.x + crossInset, y = bounds.y + leadingInset,
				w = math.max(1, bounds.w - crossInset * 2), h = available }
		local start = horizontal and inner.x or inner.y
		self:_layoutSequential(mainStart, inner, horizontal, start, extent, gap)
		if #mainEnd > 0 then
			local endSpan = #mainEnd * extent + math.max(0, #mainEnd - 1) * gap
			local finish = horizontal and (inner.x + inner.w) or (inner.y + inner.h)
			local endStart = finish - endSpan
			self:_layoutSequential(mainEnd, inner, horizontal, endStart, extent, gap)
			if options.separator == true then
				if not self.separator then self.separator = createSeparator(self.parent, options) end
				local offset = math.max(0, number(options.separatorOffset, 6))
				if horizontal then
					childBounds(self.separator, { x = endStart - offset, y = inner.y,
						w = math.max(1, number(options.separatorSize, 1)), h = inner.h })
				else
					childBounds(self.separator, { x = inner.x, y = endStart - offset,
						w = inner.w, h = math.max(1, number(options.separatorSize, 1)) })
				end
				self.separator:setVisible(true)
			end
		elseif self.separator then self.separator:setVisible(false) end
		return self
	end

	instance.layout = instance.reflow

	function instance:dispose()
		if self.disposed then return false end
		self:_clearButtons()
		if self.separator then removeChild(self.parent, self.separator); self.separator = nil end
		self.items = {}; self.parent = nil; self.disposed = true
		return true
	end

	instance:setItems(options.items or {})
	instance:reflow(options.bounds)
	return instance
end

return Tabs
