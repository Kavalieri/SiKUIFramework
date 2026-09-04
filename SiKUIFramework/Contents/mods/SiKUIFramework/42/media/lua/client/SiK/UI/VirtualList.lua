require "ISUI/ISPanel"
require "SiK/UI/Scroll"

SiK = SiK or {}
SiK.UI = SiK.UI or {}

local VirtualList = SiK.UI.VirtualList or {}
SiK.UI.Namespace.define("VirtualList", VirtualList)

local ListInstance = {}
ListInstance.__index = ListInstance

local function attachRow(list, row)
	list.scroll:addChild(row)
	list.pool[#list.pool + 1] = row
end

local function disposeRow(list, row)
	if row and row.dispose then row:dispose() end
	list.scroll:removeChild(row)
end

local function defaultRow(_, width, height)
	local row = ISPanel:new(0, 0, width, height)
	row:initialise()
	if row.instantiate then row:instantiate() end
	return row
end

function ListInstance:_key(item, index)
	if self.keyOf then return self.keyOf(item, index) end
	return index
end

function ListInstance:_poolSize()
	local rect = self.scroll:getViewportRect()
	return SiK.UI.Scroll.rowPoolSizeForViewport(rect.h, self.rowHeight, self.buffer)
end

function ListInstance:_resizePool()
	local wanted = math.min(#self.data, self:_poolSize())
	while #self.pool < wanted do
		local rect = self.scroll:getViewportRect()
		local row = (self.createRow or defaultRow)(self, rect.w, self.rowHeight)
		if not row then return nil, "row_factory_failed" end
		row._sikList = self
		row.onMouseDown = function(target, x, y)
			local owner = target._sikList
			if not owner or owner.disposed or not target._sikItem then return false end
			if owner.interaction and owner.interaction.onMouseDown then
				return owner.interaction.onMouseDown(owner:_interactionContext(target, x, y)) == true
			end
			return false
		end
		row.onMouseMove = function(target, dx, dy)
			local owner = target._sikList
			if not owner or owner.disposed or not target._sikItem then return false end
			if owner.interaction and owner.interaction.onMouseMove then
				local context = owner:_interactionContext(target)
				context.dx, context.dy = dx, dy
				return owner.interaction.onMouseMove(context) == true
			end
			return false
		end
		row.onMouseMoveOutside = row.onMouseMove
		row.onMouseUp = function(target, x, y)
			local owner = target._sikList
			if not owner or owner.disposed or not target._sikItem then return false end
			if owner.interaction and owner.interaction.onMouseUp
				and owner.interaction.onMouseUp(owner:_interactionContext(target, x, y)) == true then
				return true
			end
			-- Selection refreshes the virtual pool synchronously. Snapshot the exact
			-- row before that refresh so activation can never observe a recycled row.
			local item, index, key = target._sikItem, target._sikIndex, target._sikKey
			owner:setSelectedKey(key)
			if owner.onActivate then
				owner.onActivate({
					playerNum = owner.playerNum,
					component = owner,
					item = item,
					index = index,
					key = key,
					x = x,
					y = y,
				})
			end
			return true
		end
		row.onMouseUpOutside = function(target, x, y)
			local owner = target._sikList
			if not owner or owner.disposed or not target._sikItem then return false end
			if owner.interaction and owner.interaction.onMouseUpOutside then
				return owner.interaction.onMouseUpOutside(owner:_interactionContext(target, x, y)) == true
			end
			return false
		end
		row.onMouseDoubleClick = function(target, x, y)
			local owner = target._sikList
			if not owner or owner.disposed or not target._sikItem then return false end
			if owner.interaction and owner.interaction.onDoubleClick then
				return owner.interaction.onDoubleClick(owner:_interactionContext(target, x, y)) == true
			end
			return false
		end
		row.onRightMouseUp = function(target, x, y)
			local owner = target._sikList
			if not owner or owner.disposed or not target._sikItem then return false end
			if owner.interaction and owner.interaction.onRightClick then
				return owner.interaction.onRightClick(owner:_interactionContext(target, x, y)) == true
			end
			return false
		end
		attachRow(self, row)
	end
	while #self.pool > wanted do
		local row = table.remove(self.pool)
		disposeRow(self, row)
	end
	return true
end

function ListInstance:_interactionContext(row, x, y)
	return { playerNum = self.playerNum, component = self, row = row,
		item = row._sikItem, index = row._sikIndex, key = row._sikKey,
		x = x, y = y }
end

function ListInstance:refresh()
	if self.disposed then return nil, "disposed" end
	local ok, reason = self:_resizePool()
	if not ok then return nil, reason end
	local rect = self.scroll:getViewportRect()
	local first = math.floor(self.scroll:getScrollOffset() / self.rowHeight) + 1
	for poolIndex = 1, #self.pool do
		local dataIndex = first + poolIndex - 1
		local row = self.pool[poolIndex]
		local item = self.data[dataIndex]
		if item ~= nil then
			local key = self:_key(item, dataIndex)
			row._sikItem = item
			row._sikIndex = dataIndex
			row._sikKey = key
			row._sikSelected = key == self.selectedKey
			row._sikFocused = key == self.focusedKey
			row:setVisible(true)
			SiK.UI.Layout.apply(row, {
				x = 0,
				y = (dataIndex - 1) * self.rowHeight,
				w = rect.w,
				h = self.rowHeight,
			})
			if self.updateRow then self.updateRow(row, item, dataIndex, row._sikSelected) end
		else
			row._sikItem = nil
			row._sikIndex = nil
			row._sikKey = nil
			row._sikSelected = false
			row._sikFocused = false
			row:setVisible(false)
		end
	end
	return true
end

function ListInstance:setData(data, preserveOffset)
	if self.disposed then return nil, "disposed" end
	self.data = type(data) == "table" and data or {}
	local _, refreshed = self.scroll:update({
		offset = preserveOffset and self.scroll:getScrollOffset() or 0,
		contentHeight = #self.data * self.rowHeight,
	}, "data")
	if self.selectedKey ~= nil and not self.retainMissingSelection then
		local found = false
		for index = 1, #self.data do
			if self:_key(self.data[index], index) == self.selectedKey then found = true break end
		end
		if not found then self.selectedKey = nil end
	end
	if refreshed then return true end
	return self:refresh()
end

function ListInstance:getSelectedKey()
	return self.selectedKey
end

function ListInstance:setSelectedKey(key)
	if self.disposed then return nil, "disposed" end
	self.selectedKey = key
	self:refresh()
	if self.onSelect then
		self.onSelect({ playerNum = self.playerNum, component = self, key = key })
	end
	return key
end

function ListInstance:getFocusedKey()
	return self.focusedKey
end

function ListInstance:setFocusedKey(key)
	if self.disposed then return nil, "disposed" end
	self.focusedKey = key
	self:refresh()
	return key
end

function ListInstance:isEmpty()
	return #self.data == 0
end

function ListInstance:captureState()
	return { offset = self:getScrollOffset(), selection = self.selectedKey, focus = self.focusedKey }
end

function ListInstance:restoreState(state)
	if type(state) ~= "table" then return nil, "invalid_state" end
	self.selectedKey = state.selection
	self.focusedKey = state.focus
	self.scroll:setScrollOffset(state.offset)
	return self:refresh()
end

function ListInstance:getScrollOffset()
	return self.scroll:getScrollOffset()
end

function ListInstance:setScrollOffset(offset)
	if self.disposed then return nil, "disposed" end
	return self.scroll:setScrollOffset(offset)
end

function ListInstance:setBounds(x, y, w, h, trackRect)
	if self.disposed then return nil, "disposed" end
	if not self.ownsScroll then return nil, "external_scroll_geometry" end
	self.scroll:setGeometry({ x = x, y = y, w = w, h = h }, trackRect)
	return self:refresh()
end

function ListInstance:reflow(bounds, y, width, height)
	if self.disposed then return nil, "disposed" end
	if self.ownsScroll then
		local ok, reason = self.scroll:reflow(bounds, y, width, height)
		if not ok then return nil, reason end
	end
	return self:refresh()
end

function ListInstance:dispose()
	if self.disposed then return end
	self.disposed = true
	if self.scrollListener then self.scroll:unsubscribe(self.scrollListener) end
	local snapshot = {}
	for index = 1, #self.pool do snapshot[index] = self.pool[index] end
	self.pool = {}
	for index = 1, #snapshot do disposeRow(self, snapshot[index]) end
	if self.ownsScroll then self.scroll:dispose() end
	self.data = {}
	self.scroll = nil
	self.createRow = nil
	self.updateRow = nil
	self.onSelect = nil
	self.onActivate = nil
	self.interaction = nil
end

function VirtualList.create(options)
	options = options or {}
	local scroll = options.scroll
	local ownsScroll = false
	if not scroll then
		local created, reason = SiK.UI.Scroll.create(options)
		if not created then return nil, reason end
		scroll = created
		ownsScroll = true
	end
	if type(scroll) ~= "table" or type(scroll.subscribe) ~= "function" then
		return nil, "invalid_scroll"
	end
	local instance = setmetatable({
		scroll = scroll,
		ownsScroll = ownsScroll,
		data = {},
		pool = {},
		rowHeight = math.max(1, tonumber(options.rowHeight) or 32),
		buffer = math.max(1, math.floor(tonumber(options.buffer) or 2)),
		keyOf = type(options.keyOf) == "function" and options.keyOf or nil,
		createRow = type(options.createRow) == "function" and options.createRow or nil,
		updateRow = type(options.updateRow) == "function" and options.updateRow or nil,
			onSelect = type(options.onSelect) == "function" and options.onSelect or nil,
			onActivate = type(options.onActivate) == "function" and options.onActivate or nil,
			interaction = type(options.interaction) == "table" and options.interaction or nil,
		selectedKey = options.selectedKey,
		retainMissingSelection = options.retainMissingSelection == true,
		focusedKey = options.focusedKey,
		emptyText = tostring(options.emptyText or ""),
		playerNum = math.max(0, math.floor(tonumber(options.playerNum or scroll.playerNum) or 0)),
		disposed = false,
	}, ListInstance)
	instance.scrollListener = function() instance:refresh() end
	scroll:subscribe(instance.scrollListener)
	local ok, reason = instance:setData(options.data or {}, options.preserveOffset == true)
	if not ok then
		instance:dispose()
		return nil, reason
	end
	return instance
end

return VirtualList
