require "ISUI/ISPanel"
require "SiK/UI/Namespace"
require "SiK/UI/Layout"
require "SiK/UI/Metrics"
require "SiK/UI/Scroll"

SiK = SiK or {}
SiK.UI = SiK.UI or {}

local ScrollDock = SiK.UI.ScrollDock or {}
SiK.UI.Namespace.define("ScrollDock", ScrollDock)

local ScrollDockInstance = {}
ScrollDockInstance.__index = ScrollDockInstance

local function numberOr(value, fallback)
	value = tonumber(value)
	if value == nil or value ~= value then return fallback end
	return value
end

local function copyRect(rect)
	return { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
end

local function panel(x, y, w, h)
	local value = ISPanel:new(x, y, w, h)
	value:initialise()
	if value.instantiate then value:instantiate() end
	value.drawBackground = false
	value.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	value.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	return value
end

local function attach(parent, child)
	if parent and parent.addChild then parent:addChild(child) end
end

local function detach(parent, child)
	if parent and child and parent.removeChild then parent:removeChild(child) end
	if child and child.removeFromUIManager then child:removeFromUIManager() end
end

function ScrollDockInstance:_bottomHeight()
	if type(self.measureFixedBottom) == "function" then
		return math.max(0, numberOr(self.measureFixedBottom(self.fixedBottomHost, self), 0))
	end
	return math.max(0, self.fixedBottomHeight)
end

function ScrollDockInstance:_rects()
	local inner = SiK.UI.Layout.inset({ x = 0, y = 0, w = self.w, h = self.h },
		self.padding.left, self.padding.top, self.padding.right, self.padding.bottom)
	local bottomHeight = math.min(inner.h, self:_bottomHeight())
	local gap = bottomHeight > 0 and self.gap or 0
	local contentHeight = math.max(0, inner.h - bottomHeight - gap)
	local overflow = self.contentHeight > contentHeight
	local gutter = overflow and self.scrollGutter or 0
	local viewport = { x = inner.x, y = inner.y,
		w = math.max(0, inner.w - gutter), h = contentHeight }
	local track = overflow and { x = inner.x + inner.w - self.scrollBarWidth,
		y = inner.y, w = self.scrollBarWidth, h = contentHeight } or nil
	local bottom = { x = inner.x, y = inner.y + contentHeight + gap,
		w = inner.w, h = bottomHeight }
	return viewport, track, bottom
end

function ScrollDockInstance:_sync(reason)
	if self.disposed then return nil, "disposed" end
	SiK.UI.Layout.apply(self.panel, { x = self.x, y = self.y, w = self.w, h = self.h })
	local viewport, track, bottom = self:_rects()
	self.viewportRect, self.fixedBottomRect = viewport, bottom
	SiK.UI.Layout.apply(self.fixedBottomHost, bottom)
	self.scroll:update({ viewportRect = viewport, trackRect = track, trackRectSet = true,
		contentHeight = self.contentHeight }, reason or "sync")
	if type(self.onContentRectChanged) == "function" then
		self.onContentRectChanged(self, copyRect(viewport), reason or "sync")
	end
	return self
end

function ScrollDockInstance:setContentHeight(height)
	if self.disposed then return nil, "disposed" end
	self.contentHeight = math.max(0, numberOr(height, 0))
	return self:_sync("content")
end

function ScrollDockInstance:setFixedBottomHeight(height)
	if self.disposed then return nil, "disposed" end
	self.fixedBottomHeight = math.max(0, numberOr(height, 0))
	return self:_sync("bottom")
end

function ScrollDockInstance:reflow(bounds, y, w, h)
	if self.disposed then return nil, "disposed" end
	if type(bounds) == "table" then
		self.x, self.y = numberOr(bounds.x, self.x), numberOr(bounds.y, self.y)
		self.w = math.max(0, numberOr(bounds.w or bounds.width, self.w))
		self.h = math.max(0, numberOr(bounds.h or bounds.height, self.h))
	else
		self.x, self.y = numberOr(bounds, self.x), numberOr(y, self.y)
		self.w, self.h = math.max(0, numberOr(w, self.w)), math.max(0, numberOr(h, self.h))
	end
	return self:_sync("reflow")
end

function ScrollDockInstance:getContentRect() return copyRect(self.viewportRect) end
function ScrollDockInstance:getFixedBottomRect() return copyRect(self.fixedBottomRect) end
function ScrollDockInstance:getScrollOffset() return self.scroll:getScrollOffset() end
function ScrollDockInstance:setScrollOffset(offset) return self.scroll:setScrollOffset(offset) end

function ScrollDockInstance:dispose()
	if self.disposed then return false end
	self.disposed = true
	if self.scroll then self.scroll:dispose() end
	detach(self.panel, self.fixedBottomHost)
	detach(self.parent, self.panel)
	self.scroll, self.contentHost, self.fixedBottomHost, self.panel = nil, nil, nil, nil
	return true
end

function ScrollDock.create(options)
	options = options or {}
	if type(options.parent) ~= "table" then return nil, "invalid_parent" end
	local tokens = SiK.UI.Metrics.tokens(options.metrics)
	local padding = SiK.UI.Layout.insets(options.padding, 12)
	local instance = setmetatable({
		parent = options.parent, x = numberOr(options.x, 0), y = numberOr(options.y, 0),
		w = math.max(0, numberOr(options.w or options.width, 0)),
		h = math.max(0, numberOr(options.h or options.height, 0)),
		padding = padding, gap = math.max(0, numberOr(options.gap, tokens.spacing.sm)),
		scrollBarWidth = math.max(0, numberOr(tokens.block.scrollBarWidth, 14)),
		scrollGutter = math.max(0, numberOr(tokens.block.scrollGutter, 24)),
		fixedBottomHeight = math.max(0, numberOr(options.fixedBottomHeight, 0)),
		measureFixedBottom = options.measureFixedBottom,
		contentHeight = math.max(0, numberOr(options.contentHeight, 0)),
		onContentRectChanged = options.onContentRectChanged, disposed = false,
	}, ScrollDockInstance)
	instance.panel = panel(instance.x, instance.y, instance.w, instance.h)
	instance.panel._sikUiComponent = "scrollDock"
	attach(options.parent, instance.panel)
	instance.fixedBottomHost = panel(0, 0, 0, 0)
	instance.fixedBottomHost._sikUiComponent = "scrollDockFixedBottom"
	attach(instance.panel, instance.fixedBottomHost)
	local scroll, reason = SiK.UI.Scroll.create({ parent = instance.panel,
		viewportRect = { x = 0, y = 0, w = 0, h = 0 }, contentHeight = instance.contentHeight,
		playerNum = options.playerNum })
	if not scroll then instance:dispose(); return nil, reason end
	instance.scroll, instance.contentHost = scroll, scroll.host
	instance.contentHost._sikUiComponent = "scrollDockContent"
	instance:_sync("create")
	return instance
end

return ScrollDock
