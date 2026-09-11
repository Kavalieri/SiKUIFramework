require "SiK/UI/Namespace"
require "SiK/UI/Theme"
require "SiK/UI/Icon"
require "SiK/UI/Popover"
require "SiK/UI/Viewport"
require "ISUI/ISPanel"

local Combo = SiK.UI.Combo or {}
SiK.UI.Namespace.define("Combo", Combo)

local function n(value, fallback)
	value = tonumber(value)
	if value == nil or value ~= value then return fallback end
	return value
end

local function fontHeight(font)
	local manager = type(getTextManager) == "function" and getTextManager() or nil
	return manager and manager:getFontHeight(font or UIFont.Small) or 18
end

local function itemText(item)
	if type(item) ~= "table" then return tostring(item or "") end
	return tostring(item.text or item.label or item.name or "")
end

local function itemValue(item)
	if type(item) ~= "table" then return item end
	if item.value ~= nil then return item.value end
	return item.id or item.key
end

local function itemDisabled(item)
	return type(item) == "table" and (item.disabled == true or item.placeholder == true)
end

local function casefold(value)
	-- Lua's lower is safe for byte strings. UTF-8 names without a Latin case
	-- mapping remain literal, which is the required CJK behaviour.
	return string.lower(tostring(value or ""))
end

local function matchesQuery(item, query)
	if query == "" then return true end
	return string.find(casefold(itemText(item)), query, 1, true) ~= nil
end

local function visibleEntries(owner, query)
	local entries, lastGroup = {}, nil
	for index = 1, #owner._sikItems do
		local item = owner._sikItems[index]
		if matchesQuery(item, query) then
			local group = type(item) == "table" and (item.group or item.groupLabel) or nil
			if group ~= nil and tostring(group) ~= "" and tostring(group) ~= lastGroup then
				entries[#entries + 1] = { heading = true, text = tostring(item.groupLabel or group) }
				lastGroup = tostring(group)
			elseif group == nil or tostring(group) == "" then
				lastGroup = nil
			end
			entries[#entries + 1] = { item = item, originalIndex = index,
				disabled = itemDisabled(item) }
		end
	end
	return entries
end

local function drawArrow(panel, x, y)
	-- A down-facing asset avoids relying on DrawTextureAngle, which is absent
	-- from some B42 render bridges and otherwise made this affordance vanish.
	return SiK.UI.Icon.drawExact(panel, "sik.arrow.down.14", x, y, 14, 14)
end

local function drawClippedText(panel, text, x, y, width, color)
	if width <= 0 then return end
	local stencil = type(panel.setStencilRect) == "function"
	if stencil then panel:setStencilRect(x, 0, width, panel.height) end
	panel:drawText(tostring(text or ""), x, y, color.r, color.g, color.b, color.a, UIFont.Small)
	if stencil and panel.clearStencilRect then panel:clearStencilRect() end
end

local function resolveContext(options)
	local supplied = options.theme
	local context = type(supplied) == "table" and supplied._sikThemeContext == true
		and supplied or SiK.UI.Theme.context(options.parent, supplied, options.playerNum)
	if context then options.theme = context end
	return context
end

local function resolveMaterial(role, parent, options)
	return SiK.UI.Theme.resolveMaterial(role, parent, options.material, options.theme)
end

local function createPopup(owner, options)
	local rowHeight = math.max(24, n(options.rowHeight, owner.height))
	local maxRows = math.max(1, math.floor(n(options.maxVisibleRows, 9)))
	local searchable = options.searchable == true and type(SiK.UI.Controls) == "table"
		and type(SiK.UI.Controls.search) == "function"
	local inputHeight = searchable and rowHeight or 0
	local entries = visibleEntries(owner, "")
	local safe = SiK.UI.Viewport.safe(owner.playerNum, options.environment, 8)
	local popupWidth = math.max(1, math.min(owner.width, safe.w))
	local maximumRows = math.max(1, math.floor(math.max(0, safe.h - inputHeight - 2) / rowHeight))
	local visibleRows = math.max(1, math.min(#entries, maxRows, maximumRows))
	local popupHeight = math.max(rowHeight, inputHeight + visibleRows * rowHeight + 2)
	popupHeight = math.max(1, math.min(popupHeight, safe.h))
	local popup = ISPanel:new(0, 0, popupWidth, popupHeight)
	popup:initialise()
	if popup.instantiate then popup:instantiate() end
	popup.drawBackground = false
	popup.owner = owner
	popup.rowHeight = rowHeight
	popup.offset = 0
	popup.playerNum = owner.playerNum
	popup._sikVisibleEntries = entries
	popup._sikSearchQuery = ""
	popup._sikUiComponent = "combo-popup"
	popup._sikThemeContext = options.theme
	popup._sikMaterial = resolveMaterial("popover", owner, options)
	if type(options.theme) == "table" and options.theme._sikThemeContext == true then
		SiK.UI.Theme.bind(popup, options.theme, function(widget, context)
			widget._sikThemeContext = context
			widget._sikMaterial = resolveMaterial("popover", owner, options)
		end)
	end

	function popup:visibleRowCount()
		return math.max(1, math.floor((self.height - inputHeight - 2) / self.rowHeight))
	end

	function popup:rebuildVisible(query)
		self._sikSearchQuery = casefold(query)
		self._sikVisibleEntries = visibleEntries(self.owner, self._sikSearchQuery)
		local maximum = math.max(0, #self._sikVisibleEntries - self:visibleRowCount())
		self.offset = math.max(0, math.min(maximum, self.offset))
		return self
	end

	if searchable then
		popup.search = SiK.UI.Controls.search(popup, {
			x = 0, y = 0, w = popup.width, h = inputHeight, text = "",
			placeholder = tostring(options.searchPlaceholder or ""), minChars = 0, wideMinChars = 0,
			debounceMs = 0, showButton = false, playerNum = owner.playerNum, theme = options.theme,
			onChange = function(context) popup:rebuildVisible(context.value) end,
		})
	end

	function popup:prerender()
		local theme = SiK.UI.Theme.tokens(options.theme)
		local material = self._sikMaterial
		local fill = material and material.paint or theme.surfaceAlt
		self:drawRect(0, 0, self.width, self.height, fill.a, fill.r, fill.g, fill.b)
		local visible = self:visibleRowCount()
		for row = 1, visible do
			local index = self.offset + row
			local entry = self._sikVisibleEntries[index]
			if entry ~= nil then
				local y = inputHeight + 1 + (row - 1) * self.rowHeight
				local pointerY = self:getMouseY()
				local hovered = self:isMouseOver() and pointerY >= y
					and pointerY < y + self.rowHeight
				local fill = not entry.heading and entry.originalIndex == self.owner.selected and theme.selected
					or (hovered and theme.hover or nil)
				if fill then self:drawRect(1, y, self.width - 2, self.rowHeight,
					fill.a, fill.r, fill.g, fill.b) end
				local textY = y + math.floor((self.rowHeight - fontHeight(UIFont.Small)) / 2)
				local tone = (entry.heading or entry.disabled) and theme.textMuted or theme.text
				drawClippedText(self, entry.heading and entry.text or itemText(entry.item), 9,
					textY, self.width - 18, tone)
			end
		end
		if #self._sikVisibleEntries > visible then
			local trackX = self.width - 6
			self:drawRect(trackX, inputHeight + 3, 3, self.height - inputHeight - 6, theme.background.a,
				theme.background.r, theme.background.g, theme.background.b)
			local trackH = self.height - inputHeight - 6
			local thumbH = math.max(10, math.floor(trackH * visible / #self._sikVisibleEntries))
			local maxOffset = math.max(1, #self._sikVisibleEntries - visible)
			local thumbY = inputHeight + 3 + math.floor((trackH - thumbH) * self.offset / maxOffset)
			self:drawRect(trackX, thumbY, 3, thumbH, theme.accent.a,
				theme.accent.r, theme.accent.g, theme.accent.b)
		end
		self:drawRectBorder(0, 0, self.width, self.height, theme.accent.a,
			theme.accent.r, theme.accent.g, theme.accent.b)
	end

	function popup:onMouseWheel(delta)
		local visible = self:visibleRowCount()
		local maximum = math.max(0, #self._sikVisibleEntries - visible)
		self.offset = math.max(0, math.min(maximum, self.offset + (delta > 0 and 1 or -1)))
		return true
	end

	function popup:onMouseUp(_, y)
		if y < inputHeight then return true end
		local row = math.floor((y - inputHeight - 1) / self.rowHeight) + 1
		local index = self.offset + row
		local entry = self._sikVisibleEntries[index]
		if entry and not entry.heading and not entry.disabled then
			self.owner:setSelected(entry.originalIndex, true)
			if self.owner._sikPopover then self.owner._sikPopover:close("selection") end
		end
		return true
	end

	local popupDispose = popup.dispose
	function popup:dispose()
		if self._sikComboPopupDisposed then return false end
		self._sikComboPopupDisposed = true
		if self.search then self.search:dispose(); self.search = nil end
		if type(popupDispose) == "function" then return popupDispose(self) end
		return true
	end

	return popup
end

function Combo.create(options)
	options = options or {}
	local themeSource = options.theme
	if options.themeSourceSet == true then themeSource = options.themeSource end
	local context = resolveContext(options)
	local panel = ISPanel:new(n(options.x, 0), n(options.y, 0),
		math.max(1, n(options.w or options.width, 160)),
		math.max(1, n(options.h or options.height, 30)))
	panel:initialise()
	if panel.instantiate then panel:instantiate() end
	panel.drawBackground = false
	panel.playerNum = math.max(0, math.floor(n(options.playerNum, 0)))
	panel._sikItems, panel.options, panel.selected = {}, {}, 0
	panel._sikSearchable = options.searchable == true
	panel._sikPlaceholder = options.placeholder ~= nil and tostring(options.placeholder) or nil
	panel.enable = options.enabled ~= false
	panel._sikUiComponent = "combo"
	panel._sikThemeContext = options.theme
	panel._sikMaterial = resolveMaterial("control", options.parent, options)
	local function applyComboTheme(widget, liveContext)
			widget._sikThemeContext = liveContext
			widget._sikMaterial = resolveMaterial("control", options.parent, options)
	end
	if type(context) == "table" and context._sikThemeContext == true then
		SiK.UI.Theme.bind(panel, context, applyComboTheme)
	end
	function panel:_sikRebindThemeParent(nextParent)
		options.parent = nextParent
		local playerNum = options.playerNum or (nextParent and nextParent.playerNum) or self.playerNum
		local nextContext, reason = SiK.UI.Theme.context(nextParent, themeSource, playerNum)
		if not nextContext then return nil, reason end
		options.theme = nextContext
		self.playerNum = math.max(0, math.floor(n(playerNum, 0)))
		return SiK.UI.Theme.bind(self, nextContext, applyComboTheme)
	end

	function panel:prerender()
		local theme = SiK.UI.Theme.tokens(options.theme)
		local material = self._sikMaterial
		local fill = self.enable and (material and material.paint or theme.surfaceAlt) or theme.background
		self:drawRect(0, 0, self.width, self.height, fill.a, fill.r, fill.g, fill.b)
		local popup = self._sikPopover and self._sikPopover:getActive()
		local error = options.error == true or options.state == "error"
		local border = error and theme.danger or (popup and theme.accent or theme.border)
		self:drawRectBorder(0, 0, self.width, self.height, border.a,
			border.r, border.g, border.b)
		local item = self._sikItems[self.selected]
		local color = self.enable and (item and theme.text or theme.textMuted) or theme.textMuted
		local y = math.floor((self.height - fontHeight(UIFont.Small)) / 2)
		local label = item and itemText(item) or (self._sikPlaceholder or "")
		drawClippedText(self, label, 9, y, self.width - 34, color)
		local arrowY = math.floor((self.height - 14) / 2)
		drawArrow(self, self.width - 22, arrowY)
	end

	function panel:clear()
		self._sikItems, self.options, self.selected = {}, {}, 0
		return self
	end

	function panel:addOption(text)
		return self:addOptionWithData(text, text)
	end

	function panel:addOptionWithData(text, data)
		local item = { text = tostring(text or ""), value = data }
		self._sikItems[#self._sikItems + 1] = item
		self.options[#self.options + 1] = item.text
		if self.selected == 0 then self.selected = 1 end
		return #self._sikItems
	end

	function panel:setItems(items, selected)
		if self._sikPopover and self._sikPopover:getActive() then
			self._sikPopover:close("items-replaced")
		end
		self:clear()
		for index = 1, #(items or {}) do
			local item = items[index]
			self._sikItems[index] = item
			self.options[index] = itemText(item)
		end
		self.selected = 0
		if selected ~= nil then self:setSelected(selected, false)
		elseif self._sikPlaceholder == nil and not self._sikSearchable then
			for index = 1, #self._sikItems do
				if not itemDisabled(self._sikItems[index]) then self.selected = index; break end
			end
		end
		return self
	end

	function panel:setSelected(value, emit)
		if value == false then
			self.selected = 0
			return self
		end
		local selected = tonumber(value)
		if selected and selected <= 0 then
			self.selected = 0
			return self
		elseif selected then selected = math.max(1, math.min(#self._sikItems, math.floor(selected)))
		else
			for index = 1, #self._sikItems do
				if itemValue(self._sikItems[index]) == value then selected = index; break end
			end
		end
		local accepted = selected and self._sikItems[selected] ~= nil
			and not itemDisabled(self._sikItems[selected])
		if accepted then self.selected = selected end
		if accepted and emit == true and type(options.onChange) == "function" then
			options.onChange(self, self._sikItems[self.selected])
		end
		return self
	end

	function panel:getSelectedItem() return self._sikItems[self.selected] end
	function panel:setPlaceholderText(value)
		self._sikPlaceholder = tostring(value or "")
		return self
	end
	function panel:setEnabled(value)
		self.enable = value ~= false
		if not self.enable and self._sikPopover then self._sikPopover:close("disabled") end
		return self
	end
	function panel:setEnable(value) return self:setEnabled(value) end

	panel._sikPopover = SiK.UI.Popover.attach(panel, {
		trigger = "click", gap = 4, playerNum = panel.playerNum,
		factory = function() return createPopup(panel, options) end,
	})
        local baseMouseUp = panel.onMouseUp
        panel.onMouseUp = function(self, ...)
                if not self.enable then return true end
                return baseMouseUp and baseMouseUp(self, ...) or true
        end
        -- Controls.decorate() wraps this lifecycle method after construction.
        -- Keep popup ownership here so disposing a tab/surface cannot leave a
        -- detached option list or FocusStack entry above the next window.
        function panel:dispose()
                if self._sikPopover then
                        self._sikPopover:dispose()
                        self._sikPopover = nil
                end
                return true
        end
        return panel
end

return Combo
