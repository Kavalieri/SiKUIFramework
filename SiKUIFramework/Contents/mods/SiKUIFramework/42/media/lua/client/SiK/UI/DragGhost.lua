require "SiK/UI/Namespace"
require "SiK/UI/Theme"
require "SiK/UI/Icon"
require "SiK/UI/Tooltip"
require "SiK/UI/Viewport"
require "ISUI/ISPanel"

local DragGhost = SiK.UI.DragGhost or {}
SiK.UI.Namespace.define("DragGhost", DragGhost)

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

local function textWidth(text, font)
	local manager = type(getTextManager) == "function" and getTextManager() or nil
	if manager and manager.MeasureStringX then
		return manager:MeasureStringX(font or UIFont.Small, tostring(text or ""))
	end
	return #tostring(text or "") * 8
end

local function truncate(text, width, font)
	text = tostring(text or "")
	if textWidth(text, font) <= width then return text end
	local suffix = "..."
	while #text > 0 and textWidth(text .. suffix, font) > width do
		text = string.sub(text, 1, #text - 1)
	end
	return text .. suffix
end

local function clampPointer(panel, pointerX, pointerY)
	local gap = panel.pointerGap
	local safe = SiK.UI.Viewport.safe(panel.playerNum, panel.environment, 0)
	local x, y = pointerX + gap, pointerY + gap
	if x + panel.width > safe.x + safe.w then x = pointerX - panel.width - gap end
	if y + panel.height > safe.y + safe.h then y = pointerY - panel.height - gap end
	return math.max(safe.x, math.min(x, safe.x + safe.w - panel.width)),
		math.max(safe.y, math.min(y, safe.y + safe.h - panel.height))
end

local function visibleRows(panel)
	return math.min(#panel.rows, panel.maxRows)
end

local function resolveSize(panel)
	local width = panel.minWidth
	local count = visibleRows(panel)
	for index = 1, count do
		local row = panel.rows[index]
		local counter = row.count ~= nil and tostring(row.count) or ""
		local prefixWidth = row.prefix ~= nil and textWidth(row.prefix, panel.font) + panel.gap or 0
		local counterWidth = counter ~= "" and textWidth(counter, panel.font) + panel.gap or 0
		width = math.max(width, panel.padding * 2 + prefixWidth + panel.iconSize
			+ panel.gap + textWidth(row.name or row.text or row.label, panel.font)
			+ counterWidth)
	end
	panel:setWidth(math.min(panel.maxWidth, width))
	local summary = #panel.rows > panel.maxRows and 1 or 0
	panel:setHeight(math.max(panel.rowHeight, (count + summary) * panel.rowHeight))
end

local function drawRow(panel, row, index)
	local theme = SiK.UI.Theme.tokens(panel.theme)
	local y = (index - 1) * panel.rowHeight
	panel:drawRect(0, y, panel.width, panel.rowHeight, panel.alpha,
		theme.surface.r, theme.surface.g, theme.surface.b)
	panel:drawRectBorder(0, y, panel.width, panel.rowHeight, panel.alpha,
		theme.border.r, theme.border.g, theme.border.b)
	local cursor = panel.padding
	local textY = y + math.floor((panel.rowHeight - fontHeight(panel.font)) / 2)
	if row.prefix ~= nil then
		local prefix = tostring(row.prefix)
		panel:drawText(prefix, cursor, textY, theme.textMuted.r, theme.textMuted.g,
			theme.textMuted.b, panel.alpha, panel.font)
		cursor = cursor + textWidth(prefix, panel.font) + panel.gap
	end
	local texture = SiK.UI.Icon.resolve(row.texture or row.icon)
	if texture then
		SiK.UI.Icon.draw(panel, texture, cursor,
			y + math.floor((panel.rowHeight - panel.iconSize) / 2),
			panel.iconSize, panel.iconSize, { alpha = panel.alpha })
	end
	cursor = cursor + panel.iconSize + panel.gap
	local counter = row.count ~= nil and tostring(row.count) or nil
	local counterWidth = counter and textWidth(counter, panel.font) or 0
	local available = math.max(1, panel.width - cursor - panel.padding
		- (counter and counterWidth + panel.gap or 0))
	panel:drawText(truncate(row.name or row.text or row.label, available, panel.font),
		cursor, textY, theme.text.r, theme.text.g, theme.text.b, panel.alpha, panel.font)
	if counter then
		local x = panel.width - panel.padding - counterWidth
		panel:drawText(counter, x, textY, theme.textMuted.r, theme.textMuted.g,
			theme.textMuted.b, panel.alpha, panel.font)
	end
end

function DragGhost.create(options)
	options = options or {}
	local panel = ISPanel:new(0, 0, 1, 1)
	panel:initialise()
	panel.drawBackground = false
	panel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	panel.playerNum = math.max(0, math.floor(n(options.playerNum, 0)))
	panel.environment = options.environment
	panel.rows = options.rows or options.descriptors or options.items or {}
	panel.maxRows = math.max(1, math.floor(n(options.maxRows, 5)))
	panel.rowHeight = math.max(1, n(options.rowHeight, 40))
	panel.iconSize = math.max(1, n(options.iconSize, 32))
	panel.padding = math.max(0, n(options.padding, 8))
	panel.gap = math.max(0, n(options.gap, 8))
	panel.pointerGap = math.max(0, n(options.pointerGap, 16))
	panel.minWidth = math.max(1, n(options.minWidth, 180))
	panel.maxWidth = math.max(panel.minWidth, n(options.maxWidth, 320))
	panel.alpha = math.max(0, math.min(1, n(options.alpha, 0.78)))
	panel.font = options.font or UIFont.Small
	panel.theme = options.theme
	panel.moreText = options.moreText
	panel._sikUiDragGhost = true
	panel._sikVisualOnly = true
	SiK.UI.Tooltip.makePassive(panel)
	panel.prerender = function(self)
		for index = 1, visibleRows(self) do drawRow(self, self.rows[index], index) end
		local hidden = #self.rows - self.maxRows
		if hidden > 0 then
			local theme = SiK.UI.Theme.tokens(self.theme)
			local y = self.maxRows * self.rowHeight
			local text = self.moreText or ("+" .. tostring(hidden))
			self:drawRect(0, y, self.width, self.rowHeight, self.alpha,
				theme.surface.r, theme.surface.g, theme.surface.b)
			self:drawText(text, self.padding,
				y + math.floor((self.rowHeight - fontHeight(self.font)) / 2),
				theme.textMuted.r, theme.textMuted.g, theme.textMuted.b,
				self.alpha, self.font)
		end
	end
	function panel:setRows(rows)
		self.rows = type(rows) == "table" and rows or {}; resolveSize(self); return self
	end
	function panel:moveTo(pointerX, pointerY)
		local x, y = clampPointer(self, n(pointerX, 0), n(pointerY, 0))
		self:setX(x); self:setY(y); return self
	end
	function panel:moveToPointer()
		local x = type(getMouseX) == "function" and getMouseX() or 0
		local y = type(getMouseY) == "function" and getMouseY() or 0
		return self:moveTo(x, y)
	end
	function panel:show()
		if self.addToUIManager then self:addToUIManager() end
		if self.setVisible then self:setVisible(true) end
		if self.setAlwaysOnTop then self:setAlwaysOnTop(true) end
		return self
	end
	function panel:dispose()
		if self._sikDisposed then return false end
		self._sikDisposed = true
		if self.setVisible then self:setVisible(false) end
		if self.removeFromUIManager then self:removeFromUIManager() end
		self.rows = {}
		return true
	end
	panel.destroy = panel.dispose
	resolveSize(panel)
	panel:moveToPointer()
	if options.autoShow ~= false then panel:show() end
	return panel
end

function DragGhost.moveToPointer(panel)
	if not panel or type(panel.moveToPointer) ~= "function" then return false end
	panel:moveToPointer(); return true
end

function DragGhost.destroy(panel)
	if not panel or type(panel.dispose) ~= "function" then return false end
	return panel:dispose()
end

return DragGhost
