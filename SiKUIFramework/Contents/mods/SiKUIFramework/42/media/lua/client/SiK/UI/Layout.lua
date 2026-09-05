require "SiK/UI/Metrics"

SiK = SiK or {}
SiK.UI = SiK.UI or {}

local Layout = SiK.UI.Layout or {}
SiK.UI.Namespace.define("Layout", Layout)

local function n(value, fallback)
	value = tonumber(value)
	if value == nil or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

function Layout.rect(x, y, w, h)
	return { x = n(x, 0), y = n(y, 0), w = math.max(0, n(w, 0)), h = math.max(0, n(h, 0)) }
end

--- Resolves any public rectangle shape into the one canonical geometry
--- contract used by SiK UI. Consumers may provide x/y/w/h or the descriptive
--- x/y/width/height form; missing and non-finite values come from fallback.
--- The returned table is always a fresh value so framework state never aliases
--- a caller-owned mutable table.
function Layout.resolveRect(value, fallback, minimumSize)
	value = type(value) == "table" and value or {}
	fallback = type(fallback) == "table" and fallback or {}
	minimumSize = math.max(0, n(minimumSize, 0))
	local fallbackX = n(fallback.x, n(fallback.left, 0))
	local fallbackY = n(fallback.y, n(fallback.top, 0))
	local fallbackW = n(fallback.w, n(fallback.width, minimumSize))
	local fallbackH = n(fallback.h, n(fallback.height, minimumSize))
	local width = n(value.w, n(value.width, fallbackW))
	local height = n(value.h, n(value.height, fallbackH))
	return Layout.rect(
		n(value.x, n(value.left, fallbackX)),
		n(value.y, n(value.top, fallbackY)),
		math.max(minimumSize, width),
		math.max(minimumSize, height))
end

function Layout.inset(rect, left, top, right, bottom)
	left = math.max(0, n(left, 0))
	top = math.max(0, n(top, left))
	right = math.max(0, n(right, left))
	bottom = math.max(0, n(bottom, top))
	return Layout.rect(rect.x + left, rect.y + top,
		math.max(0, rect.w - left - right), math.max(0, rect.h - top - bottom))
end

local function edge(value, key, axisKey, fallback)
	if type(value) ~= "table" then return math.max(0, n(value, fallback)) end
	return math.max(0, n(value[key], n(value[axisKey], n(value.all, fallback))))
end

--- Normalises the public padding contract. A number applies to every edge;
--- a table may use left/right/top/bottom, x/y or all. The standard preset is
--- deliberately useful without hand-authored coordinates.
function Layout.insets(value, fallback)
	fallback = math.max(0, n(fallback, SiK.UI.Metrics.block.padding))
	return {
		left = edge(value, "left", "x", fallback),
		right = edge(value, "right", "x", fallback),
		top = edge(value, "top", "y", fallback),
		bottom = edge(value, "bottom", "y", fallback),
	}
end

local function axisName(value, horizontal)
	value = tostring(value or "start")
	if value == "left" or value == "top" then return "start" end
	if value == "right" or value == "bottom" then return "end" end
	if value == "middle" then return "center" end
	if value == "stretch" then return "stretch" end
	if value == "center" or value == "end" then return value end
	return "start"
end

--- Resolves one axis for arbitrary content. This is the geometric primitive
--- used by text, icons, controls and nested containers alike.
function Layout.axis(containerSize, contentSize, alignment, startPad, endPad, offset)
	containerSize = math.max(0, n(containerSize, 0))
	contentSize = math.max(0, n(contentSize, 0))
	startPad = math.max(0, n(startPad, 0))
	endPad = math.max(0, n(endPad, startPad))
	local available = math.max(0, containerSize - startPad - endPad)
	local mode = axisName(alignment)
	if mode == "stretch" then contentSize = available end
	contentSize = math.min(contentSize, available)
	local position = startPad
	if mode == "center" then position = startPad + math.floor((available - contentSize) / 2)
	elseif mode == "end" then position = containerSize - endPad - contentSize end
	return position + n(offset, 0), contentSize
end

--- Places any child rectangle inside a container. Defaults are the safe
--- framework standard: canonical padding and start/start alignment. Consumers
--- can opt into center/end/stretch or add small offsets without recalculating
--- surrounding geometry.
function Layout.alignRect(container, content, options)
	container, content, options = container or {}, content or {}, options or {}
	local padding = Layout.insets(options.padding, options.defaultPadding)
	local x, width = Layout.axis(n(container.w, 0), n(content.w, 0),
		options.align or options.horizontalAlign, padding.left, padding.right,
		options.offsetX)
	local y, height = Layout.axis(n(container.h, 0), n(content.h, 0),
		options.verticalAlign, padding.top, padding.bottom, options.offsetY)
	return Layout.rect(n(container.x, 0) + x, n(container.y, 0) + y, width, height)
end

function Layout.place(widget, container, options)
	if type(widget) ~= "table" then return nil, "invalid_target" end
	local width = widget.getWidth and widget:getWidth() or widget.width
	local height = widget.getHeight and widget:getHeight() or widget.height
	local rect = Layout.alignRect(container, {
		w = options and options.width or width,
		h = options and options.height or height,
	}, options)
	Layout.apply(widget, rect)
	return rect
end

--- Composes measured pieces in a row or column. Items may declare width,
--- height and grow; a grow-only spacer pushes following pieces to the far
--- edge. justify supports start/center/end/space-between/space-around.
function Layout.flow(rect, items, options)
	items, options = items or {}, options or {}
	local horizontal = options.direction ~= "column"
	local padding = Layout.insets(options.padding, options.defaultPadding)
	local content = Layout.inset(rect, padding.left, padding.top,
		padding.right, padding.bottom)
	local gap = math.max(0, n(options.gap, SiK.UI.Metrics.spacing.sm))
	local sizes, fixed, growTotal, shrinkTotal = {}, 0, 0, 0
	for index = 1, #items do
		local item = items[index] or {}
		local widget = item.widget
		local natural = horizontal and (item.width or item.w)
			or (item.height or item.h)
		if natural == nil and widget then
			natural = horizontal and (widget.getWidth and widget:getWidth() or widget.width)
				or (widget.getHeight and widget:getHeight() or widget.height)
		end
		natural = math.max(0, n(natural, 0))
		sizes[index] = natural
		fixed = fixed + natural
		growTotal = growTotal + math.max(0, n(item.grow, 0))
		shrinkTotal = shrinkTotal + math.max(0, n(item.shrink, 1))
	end
	local mainSize = horizontal and content.w or content.h
	local baseGaps = gap * math.max(0, #items - 1)
	local rawFree = mainSize - fixed - baseGaps
	if rawFree < 0 and shrinkTotal > 0 then
		local deficit = -rawFree
		for index = 1, #items do
			local weight = math.max(0, n(items[index].shrink, 1))
			local minimum = math.max(0, n(items[index].min, 0))
			if weight > 0 then
				sizes[index] = math.max(minimum,
					sizes[index] - deficit * weight / shrinkTotal)
			end
		end
		fixed = 0
		for index = 1, #sizes do fixed = fixed + sizes[index] end
		rawFree = mainSize - fixed - baseGaps
	end
	local free = math.max(0, rawFree)
	if growTotal > 0 then
		for index = 1, #items do
			local weight = math.max(0, n(items[index].grow, 0))
			if weight > 0 then sizes[index] = sizes[index] + free * weight / growTotal end
		end
		free = 0
	end
	local cursor, actualGap = 0, gap
	local justify = tostring(options.justify or "start")
	if justify == "center" then cursor = free / 2
	elseif justify == "end" or justify == "right" or justify == "bottom" then cursor = free
	elseif justify == "space-between" and #items > 1 then actualGap = gap + free / (#items - 1)
	elseif justify == "space-around" and #items > 0 then
		actualGap = gap + free / #items
		cursor = actualGap / 2
	end
	local out = {}
	for index = 1, #items do
		local item, main = items[index] or {}, sizes[index]
		local slot = horizontal
			and Layout.rect(content.x + cursor, content.y, main, content.h)
			or Layout.rect(content.x, content.y + cursor, content.w, main)
		local widget = item.widget
		local naturalW = item.width or item.w
			or (widget and (widget.getWidth and widget:getWidth() or widget.width))
		local naturalH = item.height or item.h
			or (widget and (widget.getHeight and widget:getHeight() or widget.height))
		out[index] = Layout.alignRect(slot, {
			w = horizontal and math.min(main, n(naturalW, main)) or n(naturalW, slot.w),
			h = horizontal and n(naturalH, slot.h) or math.min(main, n(naturalH, main)),
		}, { defaultPadding = 0, padding = item.padding or 0,
			align = item.align or options.align or (horizontal and "stretch" or "start"),
			verticalAlign = item.verticalAlign or options.verticalAlign
				or (horizontal and "middle" or "stretch"),
			offsetX = item.offsetX, offsetY = item.offsetY })
		if widget then Layout.apply(widget, out[index]) end
		cursor = cursor + main + actualGap
	end
	return out, content
end

--- Wraps items into professional rows without consumer-authored coordinates.
--- Each item may define width/min/grow/shrink/order; rows use the same flow
--- alignment and spacing contract as ordinary containers.
function Layout.wrap(rect, items, options)
	items, options = items or {}, options or {}
	local ordered = {}
	for index = 1, #items do ordered[index] = items[index] end
	table.sort(ordered, function(first, second)
		local a, b = n(first.order, 0), n(second.order, 0)
		if a == b then return false end
		return a < b
	end)
	local padding = Layout.insets(options.padding, options.defaultPadding)
	local content = Layout.inset(rect, padding.left, padding.top, padding.right, padding.bottom)
	local gap = math.max(0, n(options.gap, SiK.UI.Metrics.spacing.sm))
	local rows, row, used = {}, {}, 0
	for index = 1, #ordered do
		local item = ordered[index]
		local width = math.max(1, n(item.width or item.w or item.min, content.w))
		if #row > 0 and used + gap + width > content.w then
			rows[#rows + 1], row, used = row, {}, 0
		end
		row[#row + 1] = item
		used = used + (#row > 1 and gap or 0) + width
	end
	if #row > 0 then rows[#rows + 1] = row end
	local y, out = content.y, {}
	for rowIndex = 1, #rows do
		local height = 1
		for index = 1, #rows[rowIndex] do
			height = math.max(height, n(rows[rowIndex][index].height
				or rows[rowIndex][index].h, SiK.UI.Metrics.rowHeight))
		end
		local rowRects = Layout.flow({ x = content.x, y = y, w = content.w, h = height },
			rows[rowIndex], { direction = "row", padding = 0, gap = gap,
				align = options.align, verticalAlign = options.verticalAlign,
				justify = options.justify })
		for index = 1, #rowRects do out[#out + 1] = rowRects[index] end
		y = y + height + gap
	end
	return out, content
end

--- Grid layout with fixed or responsive column count. Items may span columns;
--- rows and columns remain aligned to framework gaps and padding.
function Layout.grid(rect, items, options)
	items, options = items or {}, options or {}
	local padding = Layout.insets(options.padding, options.defaultPadding)
	local content = Layout.inset(rect, padding.left, padding.top, padding.right, padding.bottom)
	local gap = math.max(0, n(options.gap, SiK.UI.Metrics.spacing.sm))
	local columns = math.max(1, math.floor(n(options.columns, 1)))
	local cellWidth = math.max(1, (content.w - gap * (columns - 1)) / columns)
	local rowHeight = math.max(1, n(options.rowHeight, SiK.UI.Metrics.rowHeight))
	local column, row, out = 1, 1, {}
	for index = 1, #items do
		local item = items[index]
		local span = math.max(1, math.min(columns, math.floor(n(item.span, 1))))
		if column + span - 1 > columns then row, column = row + 1, 1 end
		local slot = Layout.rect(content.x + (column - 1) * (cellWidth + gap),
			content.y + (row - 1) * (rowHeight + gap),
			cellWidth * span + gap * (span - 1),
			math.max(1, n(item.height or item.h, rowHeight)))
		out[index] = Layout.alignRect(slot, { w = slot.w, h = slot.h }, {
			defaultPadding = 0, padding = item.padding or 0,
			align = item.align or options.align or "stretch",
			verticalAlign = item.verticalAlign or options.verticalAlign or "stretch" })
		if item.widget then Layout.apply(item.widget, out[index]) end
		column = column + span
		if column > columns then row, column = row + 1, 1 end
	end
	return out, content
end

function Layout.stack(rect, heights, gap)
	local out = {}
	local y = rect.y
	gap = math.max(0, n(gap, SiK.UI.Metrics.spacing.sm))
	for index = 1, #heights do
		local height = math.max(0, n(heights[index], 0))
		out[index] = Layout.rect(rect.x, y, rect.w, height)
		y = y + height + gap
	end
	return out
end

function Layout.columns(rect, specs, gap)
	local count = #specs
	local out = {}
	if count == 0 then return out end
	gap = math.max(0, n(gap, SiK.UI.Metrics.spacing.sm))
	local available = math.max(0, rect.w - gap * (count - 1))
	local base = {}
	local baseTotal = 0
	local flexTotal = 0
	for index = 1, count do
		local spec = specs[index] or {}
		base[index] = math.max(0, n(spec.width, n(spec.min, 0)))
		baseTotal = baseTotal + base[index]
		if not spec.width then flexTotal = flexTotal + math.max(0, n(spec.flex, 1)) end
	end
	local widths = {}
	if baseTotal > available and baseTotal > 0 then
		local scale = available / baseTotal
		for index = 1, count do widths[index] = base[index] * scale end
	else
		local remaining = available - baseTotal
		for index = 1, count do
			local spec = specs[index] or {}
			local extra = 0
			if not spec.width and flexTotal > 0 then
				extra = remaining * math.max(0, n(spec.flex, 1)) / flexTotal
			end
			widths[index] = base[index] + extra
		end
	end
	local x = rect.x
	for index = 1, count do
		local width = widths[index]
		if index == count then width = math.max(0, rect.x + rect.w - x) end
		out[index] = Layout.rect(math.floor(x + 0.5), rect.y, math.floor(width + 0.5), rect.h)
		x = x + width + gap
	end
	return out
end

function Layout.apply(widget, rect)
	if not widget or not rect then return nil, "invalid_target" end
	-- B42 updates the native ISUIElement rectangle through these setters but it
	-- does not consistently mirror the values back into the Lua fields. SiK UI
	-- renderers intentionally use those fields in hot paths, so a widget created
	-- at 0x0 could remain logically 0x0 even after a valid native reflow. Keep
	-- both representations in lockstep at the framework boundary.
	if widget.setX then widget:setX(rect.x) end
	if widget.setY then widget:setY(rect.y) end
	if widget.setWidth then widget:setWidth(rect.w) end
	if widget.setHeight then widget:setHeight(rect.h) end
	widget.x, widget.y = rect.x, rect.y
	widget.width, widget.height = rect.w, rect.h
	return widget
end

local Column = {}
Column.__index = Column

function Column:_set(widget, x, y, width, height)
	if not widget then return end
	if type(self.position) == "function" then
		self.position(widget, x, y, width, height)
		return
	end
	Layout.apply(widget, {
		x = x ~= nil and x or widget.x or 0,
		y = y ~= nil and y or widget.y or 0,
		w = width ~= nil and width or widget.width or 0,
		h = height ~= nil and height or widget.height or 0,
	})
end

function Layout.column(options)
	options = options or {}
	return setmetatable({
		x = n(options.x, 0), width = math.max(0, n(options.width or options.w, 0)),
		gap = math.max(0, n(options.gap, SiK.UI.Metrics.spacing.sm)),
		startY = n(options.y, 0), cursor = n(options.y, 0),
		bottom = options.bottom, position = options.position,
	}, Column)
end

function Column:space(height)
	self.cursor = self.cursor + math.max(0, n(height, 0))
	return self
end

function Column:place(widget, height, gapAfter)
	self:_set(widget, self.x, self.cursor)
	self.cursor = self.cursor + math.max(0, n(height, 0))
		+ math.max(0, n(gapAfter, self.gap))
	return self
end

function Column:label(widget, height, gapAfter)
	self:_set(widget, self.x, self.cursor, self.width)
	self.cursor = self.cursor + math.max(0, n(height, 0))
		+ math.max(0, n(gapAfter, self.gap))
	return self
end

function Column:block(widget, height, gapAfter)
	self:_set(widget, self.x, self.cursor, self.width, math.max(0, n(height, 0)))
	self.cursor = self.cursor + math.max(0, n(height, 0))
		+ math.max(0, n(gapAfter, self.gap))
	return self
end

function Column:row(height, items, options)
	items, options = items or {}, options or {}
	local specs = {}
	for index = 1, #items do
		local item = items[index]
		specs[index] = item.w and { width = item.w }
			or { flex = item.weight or 1, min = item.min or 0 }
	end
	local rects = Layout.columns(Layout.rect(self.x, self.cursor, self.width,
		math.max(0, n(height, 0))), specs, options.gap or self.gap)
	for index = 1, #items do
		local item, rect = items[index], rects[index]
		self:_set(item.widget, rect.x, rect.y + n(item.yoffset, 0), rect.w,
			item.h or rect.h)
	end
	self.cursor = self.cursor + math.max(0, n(height, 0)) + self.gap
	return self
end

function Column:fill(widget, minimumHeight)
	local height = math.max(n(minimumHeight, 0), n(self.bottom, self.cursor) - self.cursor)
	self:_set(widget, self.x, self.cursor, self.width, height)
	self.cursor = self.cursor + height
	return height
end

function Column:y() return self.cursor end
function Column:consumed() return self.cursor - self.startY end

function Layout.profile(width, requested)
	return SiK.UI.Metrics.profile(width, requested)
end

return Layout
