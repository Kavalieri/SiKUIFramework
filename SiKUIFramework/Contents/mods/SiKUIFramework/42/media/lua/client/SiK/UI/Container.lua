require "SiK/UI/Namespace"
require "SiK/UI/Controls"
require "SiK/UI/Layout"
require "SiK/UI/Metrics"
require "SiK/UI/Theme"

local Container = SiK.UI.Container or {}
SiK.UI.Namespace.define("Container", Container)

local function number(value, fallback)
	value = tonumber(value)
	if value == nil or value ~= value then return fallback end
	return value
end

local function clamped(value, minimum, maximum)
	local lower = math.max(1, number(minimum, 1))
	local upper = nil
	if maximum ~= nil then upper = math.max(lower, number(maximum, lower)) end
	value = math.max(lower, number(value, lower))
	if upper ~= nil then value = math.min(value, upper) end
	return value
end

local function aligned(available, spec, fillX, fillY)
	-- `fill` is a flow shorthand, not permission to consume the main axis.  In a
	-- column it fills width; in a row it fills height.  The resolver has already
	-- allocated the main-axis slot, so stretching that axis here used to turn
	-- every un-sized control into a viewport-sized rectangle.
	local width = fillX and available.w or number(spec.width, available.w)
	local height = fillY and available.h or number(spec.height, available.h)
	return SiK.UI.Layout.alignRect(available, {
		w = clamped(width, spec.minWidth, spec.maxWidth),
		h = clamped(height, spec.minHeight, spec.maxHeight),
	}, { defaultPadding = 0, padding = 0, align = spec.alignX or spec.align or "start",
		verticalAlign = spec.alignY or spec.verticalAlign or "start",
		offsetX = spec.x, offsetY = spec.y })
end

local function scrollGeometry(instance)
	local panel, options = instance.panel, instance.options
	local padding = SiK.UI.Layout.insets(options.padding, options.defaultPadding or 0)
	local contentHeight = math.max(0, number(instance.contentHeight, 0))
	local viewportH = math.max(1, panel.height - padding.top - padding.bottom)
	local overflow = contentHeight > viewportH
	local tokens = SiK.UI.Metrics.tokens(options.metrics)
	local gutter = overflow and tokens.block.scrollGutter or 0
	local viewport = { x = padding.left, y = padding.top,
		w = math.max(1, panel.width - padding.left - padding.right - gutter), h = viewportH }
	local track = overflow and { x = viewport.x + viewport.w + tokens.block.scrollGap,
		y = viewport.y, w = tokens.block.scrollBarWidth, h = viewport.h } or nil
	return viewport, track
end

-- Shared geometry resolver used by declarative Builder and live Containers.
-- Consumers provide intent; only Container owns composition mathematics.
function Container.resolveRects(area, entries, options)
	options = options or {}
	local result, active = {}, {}
	local padding = SiK.UI.Layout.insets(options.padding, options.defaultPadding or 0)
	local content = SiK.UI.Layout.inset(area, padding.left, padding.top, padding.right, padding.bottom)
	local gap = math.max(0, number(options.gap, 0))
	for index = 1, #(entries or {}) do
		if entries[index].visible ~= false then active[#active + 1] = index
		else result[index] = { x = content.x, y = content.y, w = 1, h = 1 } end
	end
	table.sort(active, function(left, right)
		local leftOrder = number(entries[left].order, left)
		local rightOrder = number(entries[right].order, right)
		if leftOrder == rightOrder then return left < right end
		return leftOrder < rightOrder
	end)
	if #active == 0 then return result end
	local mode = options.mode or "column"
	if mode == "overlay" or mode == "absolute" then
		for position = 1, #active do
			local index = active[position]
			result[index] = aligned(content, entries[index], entries[index].fill == true,
				entries[index].fill == true)
		end
		return result
	end
        if mode == "grid" then
                local columns = math.max(1, math.floor(number(options.columns, 1)))
                local rows, occupied, rowOf, rowHeights = 1, 0, {}, {}
                for position = 1, #active do
                        local index = active[position]
                        local span = math.max(1, math.min(columns,
                                math.floor(number(entries[index].span, 1))))
                        if occupied > 0 and occupied + span > columns then
                                rows, occupied = rows + 1, 0
                        end
                        rowOf[index] = rows
                        local naturalHeight = clamped(options.rowHeight or entries[index].height
                                or entries[index].minHeight or 1,
                                entries[index].minHeight, entries[index].maxHeight)
                        rowHeights[rows] = math.max(rowHeights[rows] or 1, naturalHeight)
                        occupied = occupied + span
			if occupied >= columns and position < #active then
				rows, occupied = rows + 1, 0
			end
                end
                local width = math.max(1, (content.w - gap * (columns - 1)) / columns)
                -- Grid rows are content-sized. Filling the entire viewport by
                -- default created huge blank bands on tall windows and compressed
                -- or clipped cards on short ones. Only explicit grow may consume
                -- remaining height.
                local usedHeight, growWeight = gap * math.max(0, rows - 1), 0
                local rowGrow = {}
                for position = 1, #active do
                        local index, row = active[position], rowOf[active[position]]
                        local weight = math.max(0, number(entries[index].grow, 0))
                        rowGrow[row] = math.max(rowGrow[row] or 0, weight)
                end
                for row = 1, rows do
                        usedHeight = usedHeight + (rowHeights[row] or 1)
                        growWeight = growWeight + (rowGrow[row] or 0)
                end
                local remaining = math.max(0, content.h - usedHeight)
                local rowY, cursorY = {}, content.y
                for row = 1, rows do
                        rowY[row] = cursorY
                        if growWeight > 0 then
                                rowHeights[row] = (rowHeights[row] or 1)
                                        + remaining * (rowGrow[row] or 0) / growWeight
                        end
                        cursorY = cursorY + rowHeights[row] + gap
                end
                local column = 0
                for position = 1, #active do
                        local index = active[position]
                        local span = math.max(1, math.min(columns, math.floor(number(entries[index].span, 1))))
                        local row = rowOf[index]
                        if column + span > columns then column = 0 end
                        result[index] = aligned({ x = content.x + column * (width + gap),
                                        y = rowY[row],
                                        w = width * span + gap * (span - 1), h = rowHeights[row] }, entries[index],
                                entries[index].fill == true,
				options.equalRowHeight ~= false or entries[index].fill == true)
                        column = column + span
                        if column >= columns then column = 0 end
                end
		return result
	end
	if mode == "wrap" then
		local cursorX, cursorY, rowHeight = content.x, content.y, 0
		for position = 1, #active do
			local index, spec = active[position], entries[active[position]]
			local width = clamped(spec.width or spec.minWidth or options.minItemWidth or content.w,
				spec.minWidth, spec.maxWidth)
			local height = clamped(spec.height or options.rowHeight or 1,
				spec.minHeight, spec.maxHeight)
			if cursorX > content.x and cursorX + width > content.x + content.w then
				cursorX, cursorY, rowHeight = content.x, cursorY + rowHeight + gap, 0
			end
			result[index] = aligned({ x = cursorX, y = cursorY, w = width, h = height }, spec,
				spec.fill == true, false)
			cursorX, rowHeight = cursorX + width + gap, math.max(rowHeight, height)
		end
		return result
	end
	local horizontal = mode == "row"
	local total = (horizontal and content.w or content.h) - gap * (#active - 1)
	local fixed, weights = 0, 0
	for position = 1, #active do
		local spec = entries[active[position]]
		-- Do not use `horizontal and spec.width or spec.height`: when a flex
		-- row intentionally omits width, Lua falls through to height and turns
		-- a 47 px-high button into a fixed 47 px-wide button.
		local size
		if horizontal then size = spec.width else size = spec.height end
		local weight = math.max(0, number(spec.grow, 0))
		if size then
			fixed = fixed + (horizontal and clamped(size, spec.minWidth, spec.maxWidth)
				or clamped(size, spec.minHeight, spec.maxHeight))
		elseif weight > 0 then
			weights = weights + weight
		else
			-- An omitted main-axis size is content-sized unless the consumer
			-- explicitly opts into flex growth. Treating every omission as grow=1
			-- made headers, tables and footer blocks divide the whole viewport
			-- between themselves and detached children from their visual parent.
			fixed = fixed + (horizontal and clamped(spec.minWidth or 1, spec.minWidth, spec.maxWidth)
				or clamped(spec.minHeight or 1, spec.minHeight, spec.maxHeight))
		end
	end
	local sizes, used = {}, gap * (#active - 1)
	for position = 1, #active do
		local index, spec = active[position], entries[active[position]]
		local size
		if horizontal then size = spec.width else size = spec.height end
		if size then
			size = horizontal and clamped(size, spec.minWidth, spec.maxWidth)
				or clamped(size, spec.minHeight, spec.maxHeight)
		end
		if not size then
			local weight = math.max(0, number(spec.grow, 0))
			if weight > 0 then
				size = math.max(1, (total - fixed) * weight / math.max(1, weights))
			else
				size = horizontal and clamped(spec.minWidth or 1, spec.minWidth, spec.maxWidth)
					or clamped(spec.minHeight or 1, spec.minHeight, spec.maxHeight)
			end
		end
		sizes[index], used = size, used + size
	end
	local remaining = math.max(0, (horizontal and content.w or content.h) - used)
	local justify, lead, actualGap = tostring(options.justify or "start"), 0, gap
	if justify == "center" then lead = remaining / 2
	elseif justify == "end" or justify == "right" or justify == "bottom" then lead = remaining
	elseif justify == "space-between" and #active > 1 then actualGap = gap + remaining / (#active - 1)
	elseif justify == "space-around" then actualGap = gap + remaining / #active; lead = actualGap / 2 end
	local cursor = (horizontal and content.x or content.y) + lead
	for position = 1, #active do
		local index, size = active[position], sizes[active[position]]
		local available = horizontal and { x = cursor, y = content.y, w = size, h = content.h }
			or { x = content.x, y = cursor, w = content.w, h = size }
			result[index] = aligned(available, entries[index],
				entries[index].fill == true and not horizontal,
				entries[index].fill == true and horizontal)
		cursor = cursor + size + actualGap
	end
	return result
end

-- The only recursive visual composition primitive. Product code supplies
-- children and data; Container owns alignment, spacing and responsive flow.
function Container.create(options)
	options = options or {}
	if type(options.parent) ~= "table" then return nil, "invalid_parent" end
	local panel = SiK.UI.Controls.panel(options.parent, {
		x = options.x or 0, y = options.y or 0,
		w = options.w or options.width or 1, h = options.h or options.height or 1,
		controlId = options.controlId or "container", playerNum = options.playerNum,
	})
	panel.drawBackground = options.background ~= nil and options.background ~= false
	panel.clipChildren = options.overflow ~= "visible"
	if options.background ~= nil and options.background ~= false then
		panel.backgroundColor = SiK.UI.Theme.normalizeColor(options.background,
			{ r = 0, g = 0, b = 0, a = 0 })
	elseif options.background == false then
		panel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	end
	if options.border ~= nil and options.border ~= false then
		panel.borderColor = SiK.UI.Theme.normalizeColor(options.border,
			{ r = 0, g = 0, b = 0, a = 0 })
	elseif options.border == false then
		panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	end
	if options.accent ~= nil then
		local previousPrerender = panel.prerender
		panel.prerender = function(self)
			if type(previousPrerender) == "function" then previousPrerender(self) end
			local accent = SiK.UI.Theme.normalizeColor(options.accent,
				{ r = 0, g = 0, b = 0, a = 0 })
			self:drawRect(0, 0, math.max(1, number(options.accentWidth, 3)), self.height,
				accent.a or accent[4] or 0.8, accent.r or accent[1], accent.g or accent[2], accent.b or accent[3])
		end
	end
	local instance = { panel = panel, childParent = panel, items = {}, options = options,
		overflow = options.overflow or "clip", contentHeight = math.max(0, number(options.contentHeight, 0)) }
	panel._sikUiControl = "container"
	panel._sikContainerInstance = instance

	function instance:add(widget, spec)
		if self.disposed or type(widget) ~= "table" then return nil, "invalid_child" end
		self.items[#self.items + 1] = { widget = widget, spec = spec or {} }
		return widget
	end

	function instance:setNavigation(navigationOptions)
		if self.disposed then return nil, "disposed" end
		if self.navigation then self.navigation:dispose(); self.navigation = nil end
		if navigationOptions == nil or navigationOptions.enabled == false then
			self.childParent = self.panel
			return self
		end
		require "SiK/UI/Navigation"
		local config = {}
		for key, value in pairs(navigationOptions) do config[key] = value end
		config.parent, config.playerNum = self.panel, self.options.playerNum
		config.profile, config.theme = self.options.profile, self.options.theme
		-- Navigation children use coordinates local to this container.  Supplying
		-- the already-resolved content rectangle prevents Navigation from ever
		-- creating destination hosts with provisional 1x1 geometry.
		config.bounds = config.bounds or self:contentRect()
		local navigation, err = SiK.UI.Navigation.create(config)
		if not navigation then return nil, err end
		self.navigation = navigation
		return self
	end

	function instance:getContentHost(key)
		if not self.navigation then return key == nil and self or nil end
		return self.navigation:getHost(key)
	end

	function instance:ensureContentHost(key)
		if not self.navigation then return nil, "navigation_unavailable" end
		return self.navigation:ensureHost(key)
	end

	function instance:mountContent(key, panel)
		if not self.navigation then return nil, "navigation_unavailable" end
		return self.navigation:mountContent(key, panel)
	end

	function instance:setActive(key, emit)
		if not self.navigation then return nil, "navigation_unavailable" end
		return self.navigation:setActive(key, emit)
	end

	function instance:setNavigationVisible(visible)
		if not self.navigation then return nil, "navigation_unavailable" end
		self.navigation:setBarVisible(visible == true)
		return self
	end

	function instance:getContentBounds(fallback)
		if self.navigation then
			return self.navigation:getContentBounds(fallback or self:contentRect())
		end
		return SiK.UI.Layout.resolveRect(self:contentRect(), fallback, 1)
	end

	function instance:remove(widget)
		for index = #self.items, 1, -1 do
			if self.items[index].widget == widget then table.remove(self.items, index); return true end
		end
		return false
	end

	function instance:contentRect()
		if self.scroll then
			local viewport = self.scroll:getViewportRect()
			return { x = 0, y = 0, w = viewport.w,
				h = math.max(viewport.h, self.contentHeight) }
		end
		local padding = SiK.UI.Layout.insets(self.options.padding,
			self.options.defaultPadding or SiK.UI.Metrics.block.padding)
		return SiK.UI.Layout.inset({ x = 0, y = 0, w = self.panel.width, h = self.panel.height },
			padding.left, padding.top, padding.right, padding.bottom)
	end

	function instance:setContentHeight(height)
		if self.disposed then return nil, "disposed" end
		self.contentHeight = math.max(0, number(height, 0))
		if self.scroll then
			local viewport, track = scrollGeometry(self)
			self.scroll:setGeometry(viewport, track)
			self.scroll:setContentHeight(self.contentHeight)
			self.childParent = self.scroll.host
		end
		return self
	end

	function instance:layout()
		if self.disposed then return self end
		local content = self:contentRect()
		if self.navigation then self.navigation:reflow(content) end
		if #self.items == 0 then return self end
		local flowItems = {}
		for index = 1, #self.items do
			local item = self.items[index]
			flowItems[index] = {}
			for key, value in pairs(item.spec) do flowItems[index][key] = value end
			flowItems[index].widget = item.widget
		end
		local mode = self.options.mode or self.options.layoutMode
			or (self.options.wrap == true and "wrap")
			or self.options.direction or self.options.flow or "column"
		local rects = Container.resolveRects(content, flowItems, {
			mode = mode, columns = self.options.columns, rowHeight = self.options.rowHeight,
			minItemWidth = self.options.minItemWidth, padding = 0, gap = self.options.gap,
			align = self.options.align, verticalAlign = self.options.verticalAlign,
			justify = self.options.justify, equalRowHeight = self.options.equalRowHeight,
		})
		for index = 1, #flowItems do
			if rects[index] then SiK.UI.Layout.apply(flowItems[index].widget, rects[index]) end
		end
		return self
	end

	function instance:reflow(bounds)
		if self.disposed then return nil, "disposed" end
		bounds = bounds or {}
		SiK.UI.Layout.apply(self.panel, { x = number(bounds.x, self.panel.x),
			y = number(bounds.y, self.panel.y), w = math.max(1, number(bounds.w or bounds.width, self.panel.width)),
			h = math.max(1, number(bounds.h or bounds.height, self.panel.height)) })
		if self.scroll then self:setContentHeight(self.contentHeight) end
		return self:layout()
	end

	function instance:dispose()
		if self.disposed then return false end
		self.disposed = true; self.items = {}
		if self.navigation then self.navigation:dispose(); self.navigation = nil end
		if self.scroll then self.scroll:dispose(); self.scroll = nil end
		if self.panel and self.panel.dispose then self.panel:dispose() end
		if self.panel then self.panel._sikContainerInstance = nil end
		self.panel, self.childParent = nil, nil
		return true
	end

	if options.navigation then
		local configured, err = instance:setNavigation(options.navigation)
		if not configured then instance:dispose(); return nil, err end
	end
	if instance.overflow == "scroll" then
		require "SiK/UI/Scroll"
		local viewport, track = scrollGeometry(instance)
		local scroll, scrollErr = SiK.UI.Scroll.create({ parent = panel,
			viewportRect = viewport, trackRect = track, contentHeight = instance.contentHeight,
			playerNum = options.playerNum })
		if not scroll then instance:dispose(); return nil, scrollErr end
		instance.scroll, instance.childParent = scroll, scroll.host
	end
	instance:reflow(options.bounds)
	return instance
end

return Container
