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
		local desired = math.max(0, numberOr(options.contentHeight, 0))
			+ tokens.block.padding * 2
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

function BlockInstance:setBounds(x, y, w, h)
	if self.disposed then return nil, "disposed" end
	local nextX = tonumber(x) or self.x
	local nextY = tonumber(y) or self.y
	local nextW = math.max(0, tonumber(w) or self.w)
	local nextH = math.max(0, tonumber(h) or self.h)
	if self.x == nextX and self.y == nextY and self.w == nextW and self.h == nextH then
		return self
	end
	self.x, self.y, self.w, self.h = nextX, nextY, nextW, nextH
	self:_sync("bounds")
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
	local background, border = options.background, options.border
	if variant ~= "plain" and variant ~= "transparent" then
		local theme = SiK.UI.Theme.tokens(options.theme)
		if background == nil then background = theme.surface end
		if border == nil then border = theme.border end
	end
	local container, err = SiK.UI.Container.create({ parent = options.parent,
		x = x, y = y, w = w, h = h, padding = 0,
		background = background, border = border,
		playerNum = options.playerNum, controlId = "block" })
	if not container then return nil, err end
	local panel = container.panel
	local hasHeader = options.title ~= nil or options.tooltip ~= nil
		or options.info ~= nil or options.actions ~= nil
	local controlMetrics = SiK.UI.Controls.metrics(options.profile)
	local metricTokens = SiK.UI.Metrics.tokens(options.metrics)
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
			or SiK.UI.Metrics.tokens(options.metrics).block.padding),
		reservedBottom = math.max(0, tonumber(options.reservedBottom) or 0),
		fill = options.fill == true,
		scrollable = options.scrollable == true,
		contentHeight = math.max(0, tonumber(options.contentHeight) or 0),
		metrics = options.metrics,
		paddingX = options.paddingX,
		paddingY = options.paddingY,
		listeners = {},
		disposed = false,
	}, BlockInstance)
	panel._sikUiComponent = "block"
	panel._sikUiBlock = instance
	if hasHeader then
		instance.header = SiK.UI.Controls.blockHeader(panel, {
			x = 0, y = 0, w = math.max(1, w), h = headerHeight,
			text = options.title or "", tooltip = options.tooltip,
			info = options.info, actions = options.actions,
			profile = options.profile, theme = options.theme,
			playerNum = options.playerNum,
			onActivate = options.onActivate,
		})
	end
	instance:_sync("create")
	return instance
end

return Block
