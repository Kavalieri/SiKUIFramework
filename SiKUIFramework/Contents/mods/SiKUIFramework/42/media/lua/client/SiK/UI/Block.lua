require "SiK/UI/Container"
require "SiK/UI/Controls"
require "SiK/UI/Metrics"
require "SiK/UI/Layout"
require "SiK/UI/Theme"

SiK = SiK or {}
SiK.UI = SiK.UI or {}

local Block = SiK.UI.Block or {}
SiK.UI.Namespace.define("Block", Block)

local BlockInstance = {}
BlockInstance.__index = BlockInstance

local function sameRect(first, second)
	return first and second and first.x == second.x and first.y == second.y
		and first.w == second.w and first.h == second.h
end

local function copyRect(rect)
	if not rect then return nil end
	return { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
end

local function numberOr(value, fallback)
	value = tonumber(value)
	if value == nil or value ~= value then return fallback end
	return value
end

local function instanceRects(instance, overflow)
	return SiK.UI.Metrics.blockRects(instance.w, instance.h, overflow,
		instance.reservedTop, instance.reservedBottom, instance.metrics,
		instance.paddingX, instance.paddingY)
end

function Block.resolveContentRect(bounds, options)
	bounds = bounds or {}
	options = options or {}
	local tokens = SiK.UI.Metrics.tokens(options.metrics)
	local paddingX = math.max(0, numberOr(options.paddingX, tokens.block.padding))
	local paddingY = math.max(0, numberOr(options.paddingY, tokens.block.padding))
	local height = math.max(0, numberOr(bounds.h, 0) - paddingY * 2)
	local overflow = options.scrollable == true
		and math.max(0, numberOr(options.contentHeight, 0)) > height
	local gutter = overflow and math.max(0, numberOr(tokens.block.scrollGutter, 24)) or 0
	local width = math.max(0, numberOr(bounds.w, 0) - paddingX * 2 - gutter)
	return {
		x = numberOr(bounds.x, 0) + paddingX,
		y = numberOr(bounds.y, 0) + paddingY,
		w = width, h = height, contentW = width,
		contentH = math.max(0, numberOr(options.contentHeight, 0)),
		paddingX = paddingX, paddingY = paddingY,
		scrollGutter = gutter, overflow = overflow,
	}
end

function Block.resolveScrollBarRect(bounds, options)
	bounds = bounds or {}
	options = options or {}
	local content = Block.resolveContentRect(bounds, options)
	if not content.overflow then return nil end
	local tokens = SiK.UI.Metrics.tokens(options.metrics)
	return {
		x = numberOr(bounds.x, 0) + math.max(0, numberOr(bounds.w, 0)
			- content.paddingX - tokens.block.scrollBarWidth),
		y = content.y,
		w = tokens.block.scrollBarWidth,
		h = content.h,
		gap = tokens.block.scrollGap,
		visible = true, overflow = true,
	}
end

--- Pure trailing scrollbar geometry for descendants that own a viewport but
--- not the Block's outer padding.  `bounds` is already the parent content rect.
function Block.resolveViewportRect(bounds, overflow, options)
	bounds, options = bounds or {}, options or {}
	local tokens = SiK.UI.Metrics.tokens(options.metrics)
	local w, h = math.max(0, numberOr(bounds.w, 0)), math.max(0, numberOr(bounds.h, 0))
	local x, y = numberOr(bounds.x, 0), numberOr(bounds.y, 0)
	local bar = math.max(0, numberOr(tokens.block.scrollBarWidth, 14))
	local gap = math.max(0, numberOr(tokens.block.scrollGap, 10))
	local gutter = overflow == true and bar + gap or 0
	return { x = x, y = y, w = math.max(0, w - gutter), h = h },
		overflow == true and { x = x + math.max(0, w - bar), y = y, w = bar, h = h } or nil
end

--- Returns the natural framed height for content that does not request a
--- functional viewport. `fill` is deliberately opt-in; callers use this
--- value to stack ordinary Blocks without turning spare surface space into a
--- misleading framed region.
function Block.intrinsicHeight(contentHeight, options)
	options = options or {}
	local tokens = SiK.UI.Metrics.tokens(options.metrics)
	local paddingY = math.max(0, numberOr(options.paddingY, tokens.block.padding))
	local headerHeight = math.max(0, numberOr(options.headerHeight, 0))
	local headerGap = headerHeight > 0 and math.max(0,
		numberOr(options.headerGap, tokens.spacing.sm)) or 0
	local footerHeight = math.max(0, numberOr(options.footerHeight, 0))
	local footerGap = footerHeight > 0 and math.max(0,
		numberOr(options.footerGap, tokens.spacing.sm)) or 0
	return paddingY * 2 + headerHeight + headerGap + footerHeight + footerGap
		+ math.max(0, numberOr(contentHeight, 0))
end

function Block.resolveLayout(bounds, options)
	bounds = bounds or {}
	options = options or {}
	local tokens = SiK.UI.Metrics.tokens(options.metrics)
	local headerHeight = math.max(0, numberOr(options.headerHeight, 0))
	local footerHeight = math.max(0, numberOr(options.footerHeight, 0))
	local headerGap = headerHeight > 0 and math.max(0,
		numberOr(options.headerGap, tokens.spacing.sm)) or 0
	local footerGap = footerHeight > 0 and math.max(0,
		numberOr(options.footerGap, tokens.spacing.sm)) or 0
	local available = math.max(0, numberOr(bounds.h, 0) - headerHeight
		- headerGap - footerHeight - footerGap)
	local regionHeight = available
	if options.fill ~= true and options.contentHeight ~= nil then
		local desired = Block.intrinsicHeight(options.contentHeight, options)
		regionHeight = math.min(available, math.max(
			math.max(0, numberOr(options.minContentHeight, 0)), desired))
	end
	local body = { x = numberOr(bounds.x, 0),
		y = numberOr(bounds.y, 0) + headerHeight + headerGap,
		w = math.max(0, numberOr(bounds.w, 0)), h = regionHeight }
	local contentOptions = {
		scrollable = options.scrollable, contentHeight = options.contentHeight,
		paddingX = options.paddingX, paddingY = options.paddingY, metrics = options.metrics,
	}
	return {
		bounds = copyRect(bounds),
		headerRect = { x = numberOr(bounds.x, 0), y = numberOr(bounds.y, 0),
			w = math.max(0, numberOr(bounds.w, 0)), h = headerHeight },
		bodyRect = body,
		contentRect = Block.resolveContentRect(body, contentOptions),
		footerRect = { x = numberOr(bounds.x, 0),
			y = numberOr(bounds.y, 0) + math.max(0, numberOr(bounds.h, 0) - footerHeight),
			w = math.max(0, numberOr(bounds.w, 0)), h = footerHeight },
		fill = options.fill == true, availableHeight = available,
	}
end

function Block.bindScrollable(widget, options)
	if type(widget) ~= "table" then return nil, "invalid_widget" end
	options = options or {}
	local rect = Block.resolveContentRect({ x = 0, y = 0,
		w = widget.width or 0, h = widget.height or 0 }, {
		scrollable = true, contentHeight = options.contentHeight,
		paddingX = options.paddingX, paddingY = options.paddingY, metrics = options.metrics,
	})
	local previous = widget._sikBlockContentRect
	widget._sikBlockContentRect = rect
	local changed = not previous or previous.x ~= rect.x or previous.y ~= rect.y
		or previous.w ~= rect.w or previous.h ~= rect.h
		or previous.overflow ~= rect.overflow
	return rect, changed
end

--- Resolves the actual Block content host for a descendant panel. This is a
--- geometry boundary: terminal widgets bind to the Block that owns padding
--- and scrollbar reservation instead of recreating either reservation.
function Block.contentOwner(parent)
	local current, depth = parent, 0
	while type(current) == "table" and depth < 64 do
		local owner = current._sikUiBlock
		if type(owner) == "table" and type(owner.getContentRect) == "function" then
			return owner, current
		end
		current = current.parent
		depth = depth + 1
	end
	return nil, nil
end

function BlockInstance:_notify(reason, previous)
	if sameRect(previous, self.contentRect) then return end
	for index = 1, #self.listeners do
		local listener = self.listeners[index]
		if listener then listener(self, copyRect(self.contentRect), copyRect(previous), reason) end
	end
end

function BlockInstance:_sync(reason)
	if self.disposed then return end
	local previous = copyRect(self.contentRect)
	local baseContent = instanceRects(self, false)
	-- Attaching a Scroll is itself an explicit scrollable contract. Preserve
	-- that public path while keeping ordinary framed blocks free of a phantom
	-- scrollbar gutter.
	self.overflow = (self.scrollable or self.scroll ~= nil)
		and self.contentHeight > baseContent.h
	self.contentRect, self.trackRect = instanceRects(self, self.overflow)
	SiK.UI.Layout.apply(self.panel, { x = self.x, y = self.y, w = self.w, h = self.h })
	if self.header then
		SiK.UI.Layout.apply(self.header, { x = self.contentRect.x,
			y = self.headerY, w = self.contentRect.w, h = self.headerHeight })
		if self.header.reflow then self.header:reflow(self.contentRect.w) end
	end
	if self.scroll and not self.scroll.disposed then
		if type(self.scroll.update) == "function" then
			self.scroll:update({ viewportRect = self.contentRect,
				trackRect = self.trackRect, trackRectSet = true,
				contentHeight = self.contentHeight }, "block")
		else
			self.scroll:setGeometry(self.contentRect, self.trackRect)
			self.scroll:setContentHeight(self.contentHeight)
		end
	end
	self:_notify(reason, previous)
end

function BlockInstance:getContentRect()
	return copyRect(self.contentRect)
end

function BlockInstance:getTrackRect()
	return copyRect(self.trackRect)
end

--- Material changes are lifecycle-driven by Theme.bind and table mount/unmount;
--- no visual tree is searched while a panel is rendering.
function BlockInstance:_refreshMaterial(context)
	if self.disposed or not self.panel then return self end
	context = context or self.panel._sikThemeContext
	if self.variant == "plain" or self.variant == "transparent" then
		self.panel._sikMaterial = SiK.UI.Theme.resolveMaterial("transparent",
			self.parent and self.parent._sikMaterial or nil, nil, context)
		self.panel.drawBackground = false
		self.panel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
		self.panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
		return self
	end
	local overrides = type(self.background) == "table" and { surface = self.background } or nil
	local material = SiK.UI.Theme.resolveMaterial("surface",
		self.parent and self.parent._sikMaterial or nil, overrides, context)
	if self._sikTableCount > 0 then
		local surface = SiK.UI.Theme.tokens(context).surface
		material.paint = SiK.UI.Theme.normalizeColor(surface, material.paint)
		material.paint.a = 1
		material.effective = SiK.UI.Theme.normalizeColor(material.paint, material.paint)
	end
	self.panel._sikMaterial = material
	self.panel.drawBackground = true
	self.panel.backgroundColor = SiK.UI.Theme.normalizeColor(material.paint, material.paint)
	local tokens = SiK.UI.Theme.tokens(context)
	self.panel.borderColor = SiK.UI.Theme.normalizeColor(self.border, tokens.border)
	return self
end

function BlockInstance:_tableMounted()
	if self.disposed then return end
	self._sikTableCount = self._sikTableCount + 1
	return self:_refreshMaterial()
end

function BlockInstance:_tableUnmounted()
	if self.disposed then return end
	self._sikTableCount = math.max(0, self._sikTableCount - 1)
	return self:_refreshMaterial()
end

--- Compose intrinsic content in the canonical Block rectangle. Widgets are
--- adopted by the Block, never painted as siblings behind its frame.
function BlockInstance:beginColumn(options)
	options = options or {}
	local owner = self
	local rect = self:getContentRect()
	local tokens = SiK.UI.Metrics.tokens(self.metrics)
	local column = SiK.UI.Layout.column({ x = rect.x, y = rect.y, w = rect.w,
		parent = self.childParent, metrics = self.metrics,
		gap = tokens.spacing.sm, retain = options.retain == true,
		position = function(widget, x, y, w, h)
			local panel = widget.panel or widget
			if panel.parent ~= owner.childParent then
				if panel.parent and panel.parent.removeChild then panel.parent:removeChild(panel) end
				owner.childParent:addChild(panel)
			end
			-- Composite handles (Table, CardCollection, etc.) own internal
			-- geometry that cannot be updated by moving their root panel alone.
			-- Give the public handle the resolved rectangle so every descendant
			-- reflows from the same source of truth.
			if widget ~= panel and widget.reflow then
				widget:reflow({ x = x, y = y, w = w or panel.width,
					h = h or panel.height })
			else
				local block = panel._sikUiBlock
				if block then block:setBounds(x, y, w, h)
				else
					SiK.UI.Layout.apply(panel, { x = x, y = y,
						w = w or panel.width, h = h or panel.height })
					if options.retain == true and panel.reflow then panel:reflow(w, h) end
				end
			end
		end })
	column.parent = self.childParent
	function column:finish()
		local trailingGap = self.cursor > self.startY and self.gap or 0
		local height = self.cursor - trailingGap + owner.headerY
		owner:setBounds(owner.x, owner.y, owner.w, height)
		return height
	end
	if options.retain == true then self._sikColumn = column end
	return column
end

function BlockInstance:setBounds(x, y, w, h)
	if self.disposed then return nil, "disposed" end
	local nextX = tonumber(x) or self.x
	local nextY = tonumber(y) or self.y
	local nextW = math.max(0, tonumber(w) or self.w)
	local nextH = math.max(0, tonumber(h) or self.h)
	if self.x == nextX and self.y == nextY and self.w == nextW and self.h == nextH then
		return self
	end
	local widthChanged = self.w ~= nextW
	self.x, self.y, self.w, self.h = nextX, nextY, nextW, nextH
	self:_sync("bounds")
	if widthChanged and self._sikColumn and not self._sikColumn.replaying then
		self._sikColumn:reflow(self:getContentRect())
		self._sikColumn:finish()
	end
	return self
end

--- Applies declarative geometry using the same public verb as the other
--- compositional SiK UI handles. `setBounds` remains the lower-level Block
--- primitive used by Builder adapters; consumers must not have to guess a
--- different resize method when exchanging compositional handles.
---@param bounds table|number
---@param y number|nil
---@param w number|nil
---@param h number|nil
---@return table|nil
---@return string|nil
function BlockInstance:reflow(bounds, y, w, h)
	if self.disposed then return nil, "disposed" end
	if type(bounds) == "table" then
		return self:setBounds(bounds.x, bounds.y,
			bounds.w or bounds.width, bounds.h or bounds.height)
	end
	return self:setBounds(bounds, y, w, h)
end

--- Content changed at the same width: replay the retained tree once, bottom-up.
--- This recalculates geometry without rebuilding controls or querying models.
function BlockInstance:refreshLayout()
	if self.disposed or not self._sikColumn or self._sikColumn.replaying then return self end
	for _, entry in ipairs(self._sikColumn.entries or {}) do
		if entry.method == "block" then
			local widget = entry.args[1]
			local child = widget and (widget._sikColumn and widget or widget._sikUiBlock)
			if child and child ~= self and child.refreshLayout then child:refreshLayout() end
		end
	end
	self._sikColumn:reflow(self:getContentRect())
	self._sikColumn:finish()
	return self
end

function BlockInstance:setReserved(top, bottom)
	if self.disposed then return nil, "disposed" end
	self.extraReservedTop = math.max(0, tonumber(top) or 0)
	self.reservedTop = self.headerReservedTop + self.extraReservedTop
	self.reservedBottom = math.max(0, tonumber(bottom) or 0)
	self:_sync("reserved")
	return self
end

function BlockInstance:setContentHeight(height)
	if self.disposed then return nil, "disposed" end
	local nextHeight = math.max(0, tonumber(height) or 0)
	if self.contentHeight == nextHeight then return self end
	self.contentHeight = nextHeight
	self:_sync("content")
	return self
end

function BlockInstance:attachScroll(scroll, owned)
	if self.disposed or type(scroll) ~= "table" or type(scroll.setGeometry) ~= "function" then
		return nil, "invalid_scroll"
	end
	if self.scroll and self.scroll ~= scroll and self.ownsScroll and self.scroll.dispose then
		self.scroll:dispose()
	end
	self.scroll = scroll
	self.ownsScroll = owned == true
	self:_sync("scroll")
	return scroll
end

function BlockInstance:subscribe(listener)
	if type(listener) ~= "function" then return nil, "invalid_listener" end
	self.listeners[#self.listeners + 1] = listener
	return listener
end

function BlockInstance:unsubscribe(listener)
	for index = 1, #self.listeners do
		if self.listeners[index] == listener then
			table.remove(self.listeners, index)
			return true
		end
	end
	return false
end

function BlockInstance:dispose()
	if self.disposed then return end
	self.disposed = true
	self._sikColumn = nil
	self._sikTableCount = 0
	if self.scroll and self.ownsScroll and self.scroll.dispose then self.scroll:dispose() end
	self.scroll = nil
	self.listeners = {}
	self.header = nil
	if self.container then self.container:dispose(); self.container = nil end
	self.panel = nil
	self.parent = nil
end

function Block.create(options)
	options = options or {}
	if options.parent ~= nil and type(options.parent) ~= "table" then
		return nil, "invalid_parent"
	end
	local x = tonumber(options.x) or 0
	local y = tonumber(options.y) or 0
	local w = math.max(0, tonumber(options.w or options.width) or 0)
	local h = math.max(0, tonumber(options.h or options.height) or 0)
	local variant = options.variant or "standard"
	local metrics = SiK.UI.Metrics.inherit(options.parent, options.metrics)
	local container, err = SiK.UI.Container.create({ parent = options.parent,
		x = x, y = y, w = w, h = h, padding = 0,
		metrics = metrics,
		theme = options.theme, background = false, border = false,
		accent = options.accent, accentTone = options.accentTone,
		playerNum = options.playerNum, controlId = "block" })
	if not container then return nil, err end
	local panel = container.panel
	local hasHeader = options.title ~= nil or options.tooltip ~= nil
		or options.info ~= nil or options.leadingIndicator ~= nil or options.actions ~= nil
	local controlMetrics = SiK.UI.Controls.metrics(options.profile)
	local metricTokens = metrics
	local headerHeight = hasHeader and math.max(1,
		tonumber(options.headerHeight) or controlMetrics.rowHeight) or 0
	local headerGap = hasHeader and math.max(0,
		tonumber(options.headerGap) or metricTokens.spacing.sm) or 0
	local extraReservedTop = math.max(0, tonumber(options.reservedTop) or 0)
	local headerReservedTop = headerHeight + headerGap
	local instance = setmetatable({
		parent = options.parent,
		panel = panel,
		container = container,
		childParent = panel,
		x = x, y = y, w = w, h = h,
		reservedTop = headerReservedTop + extraReservedTop,
		extraReservedTop = extraReservedTop,
		headerReservedTop = headerReservedTop,
		headerHeight = headerHeight,
		headerY = math.max(0, tonumber(options.paddingY)
			or metrics.block.padding),
		reservedBottom = math.max(0, tonumber(options.reservedBottom) or 0),
		fill = options.fill == true,
		scrollable = options.scrollable == true,
		contentHeight = math.max(0, tonumber(options.contentHeight) or 0),
		metrics = metrics,
		variant = variant,
		background = options.background,
		border = options.border,
		_sikTableCount = 0,
		paddingX = options.paddingX,
		paddingY = options.paddingY,
		listeners = {},
		disposed = false,
	}, BlockInstance)
	panel._sikUiComponent = "block"
	panel._sikUiBlock = instance
	SiK.UI.Theme.bind(panel, panel._sikThemeContext, function(_, context)
		instance:_refreshMaterial(context)
		if instance.container and instance.container.refreshAccent then
			instance.container:refreshAccent(context)
		end
	end)
	if hasHeader then
		instance.header = SiK.UI.Controls.blockHeader(panel, {
			x = 0, y = 0, w = math.max(1, w), h = headerHeight,
			text = options.title or "", tooltip = options.tooltip,
			info = options.info, leadingIndicator = options.leadingIndicator,
			actions = options.actions,
			profile = options.profile, theme = options.theme,
			playerNum = options.playerNum,
			onActivate = options.onActivate,
		})
	end
	instance:_sync("create")
	return instance
end

return Block
