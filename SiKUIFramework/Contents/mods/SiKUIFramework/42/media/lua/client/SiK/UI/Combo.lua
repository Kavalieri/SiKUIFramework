require "SiK/UI/Namespace"
require "SiK/UI/Theme"
require "SiK/UI/Icon"
require "SiK/UI/Popover"
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

local function drawArrow(panel, x, y)
	return SiK.UI.Icon.drawRotatedExact(panel, "sik.arrow.right.14",
		x, y, 14, 14, 90)
end

local function createPopup(owner, options)
	local rowHeight = math.max(24, n(options.rowHeight, owner.height))
	local visibleRows = math.max(1, math.min(#owner._sikItems,
		math.floor(n(options.maxVisibleRows, 9))))
	local popup = ISPanel:new(0, 0, owner.width,
		math.max(rowHeight, visibleRows * rowHeight + 2))
	popup:initialise()
	if popup.instantiate then popup:instantiate() end
	popup.drawBackground = false
	popup.owner = owner
	popup.rowHeight = rowHeight
	popup.offset = 0
	popup.playerNum = owner.playerNum
	popup._sikUiComponent = "combo-popup"

	function popup:prerender()
		local theme = SiK.UI.Theme.tokens(options.theme)
		self:drawRect(0, 0, self.width, self.height, theme.surface.a,
			theme.surface.r, theme.surface.g, theme.surface.b)
		local visible = math.max(1, math.floor((self.height - 2) / self.rowHeight))
		for row = 1, visible do
			local index = self.offset + row
			local item = self.owner._sikItems[index]
			if item ~= nil then
				local y = 1 + (row - 1) * self.rowHeight
				local pointerY = self:getMouseY()
				local hovered = self:isMouseOver() and pointerY >= y
					and pointerY < y + self.rowHeight
				local fill = index == self.owner.selected and theme.selected
					or (hovered and theme.hover or nil)
				if fill then self:drawRect(1, y, self.width - 2, self.rowHeight,
					fill.a, fill.r, fill.g, fill.b) end
				local textY = y + math.floor((self.rowHeight - fontHeight(UIFont.Small)) / 2)
				self:drawText(itemText(item), 9, textY, theme.text.r, theme.text.g,
					theme.text.b, theme.text.a, UIFont.Small)
			end
		end
		if #self.owner._sikItems > visible then
			local trackX = self.width - 6
			self:drawRect(trackX, 3, 3, self.height - 6, theme.background.a,
				theme.background.r, theme.background.g, theme.background.b)
			local thumbH = math.max(10, math.floor((self.height - 6) * visible
				/ #self.owner._sikItems))
			local maxOffset = math.max(1, #self.owner._sikItems - visible)
			local thumbY = 3 + math.floor((self.height - 6 - thumbH) * self.offset / maxOffset)
			self:drawRect(trackX, thumbY, 3, thumbH, theme.accent.a,
				theme.accent.r, theme.accent.g, theme.accent.b)
		end
		self:drawRectBorder(0, 0, self.width, self.height, theme.border.a,
			theme.border.r, theme.border.g, theme.border.b)
	end

	function popup:onMouseWheel(delta)
		local visible = math.max(1, math.floor((self.height - 2) / self.rowHeight))
		local maximum = math.max(0, #self.owner._sikItems - visible)
		self.offset = math.max(0, math.min(maximum, self.offset + (delta > 0 and 1 or -1)))
		return true
	end

	function popup:onMouseUp(_, y)
		local row = math.floor((y - 1) / self.rowHeight) + 1
		local index = self.offset + row
		if index >= 1 and index <= #self.owner._sikItems then
			self.owner:setSelected(index, true)
			if self.owner._sikPopover then self.owner._sikPopover:close("selection") end
		end
		return true
	end

	return popup
end

function Combo.create(options)
	options = options or {}
	local panel = ISPanel:new(n(options.x, 0), n(options.y, 0),
		math.max(1, n(options.w or options.width, 160)),
		math.max(1, n(options.h or options.height, 30)))
	panel:initialise()
	if panel.instantiate then panel:instantiate() end
	panel.drawBackground = false
	panel.playerNum = math.max(0, math.floor(n(options.playerNum, 0)))
	panel._sikItems, panel.options, panel.selected = {}, {}, 0
	panel.enable = options.enabled ~= false
	panel._sikUiComponent = "combo"

	function panel:prerender()
		local theme = SiK.UI.Theme.tokens(options.theme)
		local fill = self.enable and theme.surface or theme.background
		self:drawRect(0, 0, self.width, self.height, fill.a, fill.r, fill.g, fill.b)
		self:drawRectBorder(0, 0, self.width, self.height, theme.border.a,
			theme.border.r, theme.border.g, theme.border.b)
		local item = self._sikItems[self.selected]
		local color = self.enable and theme.text or theme.textMuted
		local y = math.floor((self.height - fontHeight(UIFont.Small)) / 2)
		self:drawText(itemText(item), 9, y, color.r, color.g, color.b, color.a, UIFont.Small)
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
		self:clear()
		for index = 1, #(items or {}) do
			local item = items[index]
			self._sikItems[index] = item
			self.options[index] = itemText(item)
		end
		self.selected = #self._sikItems > 0 and 1 or 0
		if selected ~= nil then self:setSelected(selected, false) end
		return self
	end

	function panel:setSelected(value, emit)
		local selected = tonumber(value)
		if selected then selected = math.max(1, math.min(#self._sikItems, math.floor(selected)))
		else
			for index = 1, #self._sikItems do
				if itemValue(self._sikItems[index]) == value then selected = index; break end
			end
		end
		if selected then self.selected = selected end
		if emit == true and type(options.onChange) == "function" then
			options.onChange(self, self._sikItems[self.selected])
		end
		return self
	end

	function panel:getSelectedItem() return self._sikItems[self.selected] end
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
