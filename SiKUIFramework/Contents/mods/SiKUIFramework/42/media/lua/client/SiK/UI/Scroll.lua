require "SiK/UI/Namespace"
require "ISUI/ISPanel"
require "SiK/UI/Layout"
require "SiK/UI/Metrics"

SiK = SiK or {}
SiK.UI = SiK.UI or {}

local Scroll = SiK.UI.Scroll or {}
SiK.UI.Namespace.define("Scroll", Scroll)

local ScrollInstance = {}
ScrollInstance.__index = ScrollInstance

local function attach(parent, child)
	if parent and parent.addChild then parent:addChild(child) end
end

local function detach(parent, child)
	if not child then return end
	if parent and parent.removeChild then parent:removeChild(child) end
	if child.removeFromUIManager then child:removeFromUIManager() end
end

local function copyRect(rect)
        if not rect then return nil end
        return {
                x = rect.x, y = rect.y, w = rect.w, h = rect.h,
                contentW = rect.contentW, contentH = rect.contentH,
                scrollGutter = rect.scrollGutter, overflow = rect.overflow,
        }
end

local function sameRect(left, right)
	if left == nil or right == nil then return left == right end
	return left.x == right.x and left.y == right.y
		and left.w == right.w and left.h == right.h
end

local function containsChild(parent, child)
        local children = parent and parent.childrenInOrder
        if type(children) ~= "table" then return false end
        for index = 1, #children do
                if children[index] == child then return true end
        end
        return false
end

local function thumbRect(scroll)
	local track = scroll.trackRect
	if not track or track.h <= 0 or scroll.contentHeight <= scroll.viewportRect.h then return nil end
	local ratio = scroll.viewportRect.h / math.max(1, scroll.contentHeight)
	local height = math.max(18, math.floor(track.h * ratio + 0.5))
	height = math.min(track.h, height)
	local range = math.max(0, track.h - height)
	local maxOffset = math.max(1, scroll.contentHeight - scroll.viewportRect.h)
	local y = range * scroll.offset / maxOffset
	return { x = 0, y = math.floor(y + 0.5), w = track.w, h = height }
end

function Scroll.rowPoolSizeForViewport(viewportHeight, rowHeight, buffer)
	rowHeight = math.max(1, tonumber(rowHeight) or 1)
	buffer = math.max(0, math.floor(tonumber(buffer) or 2))
	return math.max(0, math.ceil(math.max(0, tonumber(viewportHeight) or 0) / rowHeight) + buffer)
end

function ScrollInstance:_maxOffset()
	return math.max(0, self.contentHeight - self.viewportRect.h)
end

function ScrollInstance:_notify(reason)
	for index = 1, #self.listeners do
		local listener = self.listeners[index]
		if listener then listener(self, reason) end
	end
end

function ScrollInstance:_sync(reason)
	if self.disposed then return end
	self.offset = math.max(0, math.min(self.offset, self:_maxOffset()))
	SiK.UI.Layout.apply(self.viewport, self.viewportRect)
	SiK.UI.Layout.apply(self.host, { x = 0, y = -self.offset,
		w = self.viewportRect.w, h = math.max(self.viewportRect.h, self.contentHeight) })
	local visible = self.trackRect ~= nil and self:_maxOffset() > 0
	self.bar:setVisible(visible)
	if self.trackRect then SiK.UI.Layout.apply(self.bar, self.trackRect) end
	self:_notify(reason)
end

-- Geometry, content and offset commonly change as one layout transaction.
-- Applying them atomically prevents every intermediate value from refreshing
-- a virtual list and exposing provisional 1 px geometry to its rows.
function ScrollInstance:update(options, reason)
	if self.disposed or type(options) ~= "table" then return nil, "invalid_update" end
	local viewportRect = options.viewportRect and copyRect(options.viewportRect) or self.viewportRect
	local trackRect = options.trackRectSet and copyRect(options.trackRect) or self.trackRect
	local contentHeight = options.contentHeight ~= nil
		and math.max(0, tonumber(options.contentHeight) or 0) or self.contentHeight
	local offset = options.offset ~= nil and (tonumber(options.offset) or 0) or self.offset
	local changed = not sameRect(self.viewportRect, viewportRect)
		or not sameRect(self.trackRect, trackRect)
		or self.contentHeight ~= contentHeight or self.offset ~= offset
	if not changed then return self, false end
	self.viewportRect = viewportRect
	self.trackRect = trackRect
	self.contentHeight = contentHeight
	self.offset = offset
	self:_sync(reason or "update")
	return self, true
end

function ScrollInstance:setGeometry(viewportRect, trackRect)
	if self.disposed or type(viewportRect) ~= "table" then return nil, "invalid_geometry" end
	return self:update({ viewportRect = viewportRect, trackRect = trackRect,
		trackRectSet = true }, "geometry")
end

function ScrollInstance:reflow(bounds, y, width, height)
	if self.disposed then return nil, "disposed" end
	local current = self.viewportRect
	local nextViewport
	if type(bounds) == "table" then
		nextViewport = {
			x = bounds.x ~= nil and bounds.x or current.x,
			y = bounds.y ~= nil and bounds.y or current.y,
			w = bounds.w or bounds.width or current.w,
			h = bounds.h or bounds.height or current.h,
		}
	else
		nextViewport = {
			x = bounds ~= nil and bounds or current.x,
			y = y ~= nil and y or current.y,
			w = width ~= nil and width or current.w,
			h = height ~= nil and height or current.h,
		}
	end
	local nextTrack = copyRect(self.trackRect)
	if nextTrack then
		local deltaX = nextViewport.x - current.x
		local deltaY = nextViewport.y - current.y
		local deltaW = nextViewport.w - current.w
		local deltaH = nextViewport.h - current.h
		nextTrack.x = nextTrack.x + deltaX + deltaW
		nextTrack.y = nextTrack.y + deltaY
		nextTrack.h = math.max(0, nextTrack.h + deltaH)
	end
	return self:setGeometry(nextViewport, nextTrack)
end

function ScrollInstance:setContentHeight(height)
	if self.disposed then return nil, "disposed" end
	return self:update({ contentHeight = height }, "content")
end

function ScrollInstance:getScrollOffset()
	return self.offset
end

function ScrollInstance:setScrollOffset(offset)
	if self.disposed then return nil, "disposed" end
	self:update({ offset = offset }, "offset")
	return self.offset
end

function ScrollInstance:scrollBy(delta)
	return self:setScrollOffset(self.offset + (tonumber(delta) or 0))
end

function ScrollInstance:getViewportRect()
	return copyRect(self.viewportRect)
end

function ScrollInstance:getContentRect()
	return self:getViewportRect()
end

function ScrollInstance:captureState()
	return { offset = self.offset, playerNum = self.playerNum }
end

function ScrollInstance:restoreState(state)
	if type(state) ~= "table" then return nil, "invalid_state" end
	return self:setScrollOffset(state.offset)
end

function ScrollInstance:addChild(child)
        if self.disposed or not child then return nil, "invalid_child" end
        if not containsChild(self.host, child) then attach(self.host, child) end
        for index = 1, #self.children do
                if self.children[index] == child then return child end
        end
        self.children[#self.children + 1] = child
        return child
end

function ScrollInstance:removeChild(child)
	for index = 1, #self.children do
		if self.children[index] == child then
			table.remove(self.children, index)
			detach(self.host, child)
			return true
		end
	end
	return false
end

function ScrollInstance:clear()
	local snapshot = {}
	for index = 1, #self.children do snapshot[index] = self.children[index] end
	self.children = {}
	for index = 1, #snapshot do detach(self.host, snapshot[index]) end
end

function ScrollInstance:subscribe(listener)
	if type(listener) ~= "function" then return nil, "invalid_listener" end
	self.listeners[#self.listeners + 1] = listener
	return listener
end

function ScrollInstance:unsubscribe(listener)
	for index = 1, #self.listeners do
		if self.listeners[index] == listener then
			table.remove(self.listeners, index)
			return true
		end
	end
	return false
end

function ScrollInstance:dispose()
	if self.disposed then return end
	self.disposed = true
	if self.bar.setCapture then self.bar:setCapture(false) end
	self:clear()
	self.listeners = {}
	detach(self.viewport, self.host)
	detach(self.parent, self.viewport)
	detach(self.parent, self.bar)
	self.host = nil
	self.viewport = nil
	self.bar = nil
	self.parent = nil
end

local function createPanel(x, y, w, h)
        local panel = ISPanel:new(x, y, w, h)
        panel:initialise()
        if panel.instantiate then panel:instantiate() end
	-- Viewport, content host and scrollbar track are structural layers.  A raw
	-- ISPanel carries visual defaults, which made these helpers paint empty
	-- framed rectangles behind their owner's content.
	panel.drawBackground = false
	panel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
        if panel.setScrollWithParent then panel:setScrollWithParent(false) end
        if panel.setScrollChildren then panel:setScrollChildren(false) end
        return panel
end

local function createInstance(options)
	options = options or {}
	if type(options.parent) ~= "table" then return nil, "invalid_parent" end
	local viewportRect = copyRect(options.viewportRect or {
		x = options.x or 0, y = options.y or 0,
		w = options.w or options.width or 0, h = options.h or options.height or 0,
	})
	local viewport = createPanel(viewportRect.x, viewportRect.y, viewportRect.w, viewportRect.h)
	local host = createPanel(0, 0, viewportRect.w, viewportRect.h)
	local trackRect = copyRect(options.trackRect)
	local bar = createPanel(trackRect and trackRect.x or 0, trackRect and trackRect.y or 0,
		trackRect and trackRect.w or 0, trackRect and trackRect.h or 0)
	attach(options.parent, viewport)
	attach(viewport, host)
	attach(options.parent, bar)
	local instance = setmetatable({
		parent = options.parent,
		viewport = viewport,
		host = host,
		bar = bar,
		viewportRect = viewportRect,
		trackRect = trackRect,
		contentHeight = math.max(0, tonumber(options.contentHeight) or 0),
		offset = math.max(0, tonumber(options.offset) or 0),
		wheelStep = math.max(1, tonumber(options.wheelStep) or 32),
		children = {},
		listeners = {},
		playerNum = math.max(0, math.floor(tonumber(options.playerNum) or 0)),
		disposed = false,
	}, ScrollInstance)
	viewport._sikScrollViewport = true
	host._sikScrollContentHost = true
	bar._sikScrollOwner = instance
	viewport.prerender = function(self)
		if self.setStencilRect then self:setStencilRect(0, 0, self.width, self.height) end
	end
	viewport.render = function(self)
		if self.clearStencilRect then self:clearStencilRect() end
	end
	viewport.onMouseWheel = function(_, delta)
		instance:scrollBy((tonumber(delta) or 0) * instance.wheelStep)
		return true
	end
	host.onMouseWheel = viewport.onMouseWheel
	bar.prerender = function(self)
		if self.drawRect then self:drawRect(0, 0, self.width, self.height, 0.30, 0.08, 0.08, 0.08) end
		local thumb = thumbRect(instance)
		if thumb and self.drawRect then
			self:drawRect(thumb.x, thumb.y, thumb.w, thumb.h, 0.85, 0.55, 0.55, 0.55)
		end
	end
	bar.onMouseDown = function(self, _, y)
		local thumb = thumbRect(instance)
		if not thumb then return false end
		if y < thumb.y or y > thumb.y + thumb.h then
			local range = math.max(1, self.height - thumb.h)
			local ratio = math.max(0, math.min(1, (y - thumb.h / 2) / range))
			instance:setScrollOffset(ratio * instance:_maxOffset())
			thumb = thumbRect(instance)
		end
		self._dragDelta = y - thumb.y
		if self.setCapture then self:setCapture(true) end
		return true
	end
	bar.onMouseMove = function(self, _, dy)
		if self._dragDelta == nil then return false end
		local thumb = thumbRect(instance)
		if not thumb then return false end
		local mouseY = (self.getMouseY and self:getMouseY()) or (thumb.y + dy)
		local range = math.max(1, self.height - thumb.h)
		local ratio = math.max(0, math.min(1, (mouseY - self._dragDelta) / range))
		instance:setScrollOffset(ratio * instance:_maxOffset())
		return true
	end
	local function release(self)
		self._dragDelta = nil
		if self.setCapture then self:setCapture(false) end
		return true
	end
	bar.onMouseUp = release
	bar.onMouseUpOutside = release
	instance:_sync("create")
	return instance
end

local function regionInstance(region)
	if type(region) ~= "table" then return nil end
	if getmetatable(region) == ScrollInstance then return region end
	return region._sikScrollInstance
end

local function regionRect(region, contentHeight)
	local width = region and (region.width or (region.getWidth and region:getWidth())) or 0
	local height = region and (region.height or (region.getHeight and region:getHeight())) or 0
	local base = SiK.UI.Metrics.blockRects(width, height, false, 0, 0)
	local overflow = math.max(0, tonumber(contentHeight) or 0) > base.h
	local content, track = SiK.UI.Metrics.blockRects(width, height, overflow, 0, 0)
	content.contentH = math.max(0, tonumber(contentHeight) or 0)
	content.overflow = overflow
	return content, track
end

local function notifyRegion(region, previous, current, reason)
	local callback = region and region._sikOnContentRectChanged
	if type(callback) ~= "function" or region._sikNotifyingContentRect then return end
	local changed = not previous or previous.x ~= current.x or previous.y ~= current.y
		or previous.w ~= current.w or previous.h ~= current.h
		or previous.overflow ~= current.overflow
	if not changed then return end
	region._sikNotifyingContentRect = true
	pcall(callback, region, copyRect(current), copyRect(previous), reason)
	region._sikNotifyingContentRect = false
end

local function syncRegion(region, reason)
	local instance = regionInstance(region)
	if not instance then return nil end
	local previous = region._sikContentRect and copyRect(region._sikContentRect) or nil
	local current, track = regionRect(region, region._sikContentHeight)
	region._sikContentRect = current
	instance:setGeometry(current, track)
	instance:setContentHeight(region._sikContentHeight)
	notifyRegion(region, previous, current, reason)
	return current
end

local function createRegion(parent, x, y, w, h)
	if type(parent) ~= "table" then return nil, "invalid_parent" end
	local region = createPanel(tonumber(x) or 0, tonumber(y) or 0,
		math.max(0, tonumber(w) or 0), math.max(0, tonumber(h) or 0))
	region.drawBackground = false
	region.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	region.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	region.clipChildren = true
	attach(parent, region)
	local content, track = regionRect(region, 0)
	local instance = createInstance({ parent = region, viewportRect = content,
		trackRect = track, contentHeight = 0 })
        region._sikScrollInstance = instance
        region._sikContentHeight = 0
        -- Positional regions are the compatibility composition used by
        -- scrollable product blocks. Keep the canonical trailing breathing
        -- room without affecting modern option-table Scroll instances.
        region._sikContentPad = 24
        region._sikContentRect = content
        region.contentPanel = instance.host
        region.sikScrollRegion = true
        region.onMouseWheel = function(_, delta)
                return Scroll.applyWheelDelta(region, delta, instance.wheelStep) ~= nil
        end
        return region
end

--- Creates either a modern scroll instance (`Scroll.create(options)`) or a
--- widget-hosted region (`Scroll.create(parent, x, y, w, h)`). Both forms use
--- the same Block geometry and scrollbar implementation.
function Scroll.create(options, x, y, w, h)
	if x ~= nil then return createRegion(options, x, y, w, h) end
	return createInstance(options)
end

function Scroll.childHost(scroll)
	local instance = regionInstance(scroll)
	if instance then return instance.host end
	return scroll and scroll.contentPanel or scroll
end

function Scroll.contentRect(scroll)
	local instance = regionInstance(scroll)
	if instance and scroll._sikContentRect then return copyRect(scroll._sikContentRect) end
	if instance then return instance:getContentRect() end
	return { x = 0, y = 0, w = 0, h = 0, contentW = 0,
		contentH = 0, scrollGutter = 0, overflow = false }
end

function Scroll.contentWidth(scroll)
	return Scroll.contentRect(scroll).w
end

function Scroll.setContentHeight(scroll, height)
	local instance = regionInstance(scroll)
        if not instance then return nil, "invalid_scroll" end
        if scroll._sikScrollInstance then
                scroll._sikContentHeight = math.max(0, tonumber(height) or 0)
                        + math.max(0, tonumber(scroll._sikContentPad) or 0)
                syncRegion(scroll, "content")
                return scroll._sikContentHeight
	end
	return instance:setContentHeight(height)
end

function Scroll.finish(scroll, height)
	return Scroll.setContentHeight(scroll, height)
end

function Scroll.getScrollOffset(scroll)
	local instance = regionInstance(scroll)
	return instance and instance:getScrollOffset() or 0
end

function Scroll.setScrollOffset(scroll, offset)
	local instance = regionInstance(scroll)
	if not instance then return nil, "invalid_scroll" end
	return instance:setScrollOffset(offset)
end

function Scroll.resetPosition(scroll)
	return Scroll.setScrollOffset(scroll, 0)
end

function Scroll.applyPanelOffset(scroll)
	return Scroll.setScrollOffset(scroll, Scroll.getScrollOffset(scroll))
end

function Scroll.applyWheelDelta(scroll, delta, step)
	local instance = regionInstance(scroll)
	if not instance then return nil, "invalid_scroll" end
	-- Runtime evidence in B42.20 confirms that PZ already supplies the delta
	-- in content-offset direction for these ISPanel handlers. Do not invert it.
	return instance:scrollBy((tonumber(delta) or 0) * (tonumber(step) or instance.wheelStep))
end

function Scroll.resize(scroll, width, height)
	local instance = regionInstance(scroll)
	if not instance then return nil, "invalid_scroll" end
	if scroll._sikScrollInstance then
		if scroll.setWidth then scroll:setWidth(math.max(0, tonumber(width) or 0)) end
		if scroll.setHeight then scroll:setHeight(math.max(0, tonumber(height) or 0)) end
		syncRegion(scroll, "resize")
		return scroll
	end
	local viewport = instance:getViewportRect()
	viewport.w, viewport.h = math.max(0, tonumber(width) or 0),
		math.max(0, tonumber(height) or 0)
	return instance:setGeometry(viewport, instance.trackRect)
end

function Scroll.setOnContentRectChanged(scroll, callback)
	if type(scroll) ~= "table" then return nil, "invalid_scroll" end
	if scroll._sikScrollInstance then
		scroll._sikOnContentRectChanged = type(callback) == "function" and callback or nil
		return scroll
	end
	local instance = regionInstance(scroll)
	if not instance then return nil, "invalid_scroll" end
	if instance._contentRectListener then instance:unsubscribe(instance._contentRectListener) end
	instance._contentRectListener = type(callback) == "function" and
		instance:subscribe(function(owner, reason)
			callback(owner, owner:getContentRect(), nil, reason)
		end) or nil
	return scroll
end

function Scroll.addChild(scroll, child)
	local instance = regionInstance(scroll)
	if not instance then return nil, "invalid_scroll" end
	return instance:addChild(child)
end

function Scroll.disposeChild(parent, child)
	if not child then return false end
	if parent and parent.removeChild then parent:removeChild(child) end
	if child.removeFromUIManager then child:removeFromUIManager() end
	if child.destroy then child:destroy() end
	return true
end

function Scroll.isLiveWidget(widget)
	if not widget then return false end
	return pcall(function()
		if widget.getWidth then widget:getWidth()
		elseif widget.setX then widget:setX(widget.x or 0) end
	end)
end

function Scroll.forEachChild(scroll, visitor)
	if type(visitor) ~= "function" then return 0 end
	local host = Scroll.childHost(scroll)
	if not host or not host.childrenInOrder then return 0 end
	local snapshot = {}
	for index = 1, #host.childrenInOrder do snapshot[index] = host.childrenInOrder[index] end
	local visited = 0
	for index = 1, #snapshot do
		local child = snapshot[index]
		if Scroll.isLiveWidget(child) then
			visited = visited + 1
			visitor(child, visited, host)
		end
	end
	return visited
end

function Scroll.childCount(scroll)
	local count = 0
	Scroll.forEachChild(scroll, function() count = count + 1 end)
	return count
end

function Scroll.clearTagged(scroll, tagField)
	if type(tagField) ~= "string" or tagField == "" then return 0 end
	local host = Scroll.childHost(scroll)
	local children = {}
	Scroll.forEachChild(scroll, function(child)
		if child[tagField] then children[#children + 1] = child end
	end)
	for index = 1, #children do Scroll.disposeChild(host, children[index]) end
	return #children
end

function Scroll.clear(scroll, preserveOffset)
	local offset = preserveOffset and Scroll.getScrollOffset(scroll) or 0
	local host = Scroll.childHost(scroll)
	local children = {}
	Scroll.forEachChild(scroll, function(child) children[#children + 1] = child end)
	for index = 1, #children do Scroll.disposeChild(host, children[index]) end
	local instance = regionInstance(scroll)
	if instance then instance.children = {} end
	Scroll.setScrollOffset(scroll, offset)
	return #children
end

function Scroll.setContentX(_, child, contentX)
	if child and child.setX then child:setX(tonumber(contentX) or 0) end
end

function Scroll.setContentY(_, child, contentY)
	if child and child.setY then child:setY(tonumber(contentY) or 0) end
end

function Scroll.bindScrollEvents(scroll, callback)
	local instance = regionInstance(scroll)
	if not instance then return nil, "invalid_scroll" end
	if instance._boundScrollListener then instance:unsubscribe(instance._boundScrollListener) end
	instance._boundScrollListener = type(callback) == "function" and
		instance:subscribe(function() callback() end) or nil
	return scroll
end

function Scroll.ensureScrollBars(scroll)
	local instance = regionInstance(scroll)
	if instance and scroll._sikScrollInstance then syncRegion(scroll, "ensure") end
	return scroll
end

function Scroll.setScrollBarsVisible(scroll)
	return Scroll.ensureScrollBars(scroll)
end

function Scroll.isScrollBarWidget(widget)
	if not widget then return false end
	if widget.Type == "ISScrollBar" then return true end
	local owner = widget._sikScrollOwner
	return owner ~= nil and owner.bar == widget
end

--- Reflows every SiK scroll region in an arbitrary widget subtree. The
--- traversal is neutral: product code decides which root is relevant.
function Scroll.syncTree(root, depth)
	if not root then return 0 end
	depth = math.max(0, math.floor(tonumber(depth) or 0))
	if depth > 32 then return 0 end
	local synced = 0
	if root._sikScrollInstance then
		syncRegion(root, "tree")
		synced = 1
	end
	local snapshot = {}
	for index = 1, #(root.childrenInOrder or {}) do
		snapshot[index] = root.childrenInOrder[index]
	end
	for index = 1, #snapshot do
		synced = synced + Scroll.syncTree(snapshot[index], depth + 1)
	end
	return synced
end

function Scroll.contentBottomInset() return 32 end
function Scroll.viewportBottomGap() return 32 end
function Scroll.listBottomGap() return 12 end
function Scroll.bottomPad() return 24 end

return Scroll
