require "SiK/UI/Namespace"
require "SiK/UI/Metrics"

local Collection = SiK.UI.Collection or {}
SiK.UI.Namespace.define("Collection", Collection)

local function measuredHeight(callback, entry, item, width, index, collection)
	if type(callback) ~= "function" then return nil end
	local ok, value = pcall(callback, entry, item, width, index, collection)
	if not ok or type(value) ~= "number" or value ~= value
		or value == math.huge or value == -math.huge then return nil end
	return math.max(1, value)
end

-- The same resolver serves preflight measurement and mounted collections.
-- Its callback may inspect data only; it never constructs or mutates a widget.
function Collection.measure(items, options, bounds, entries, collection)
	items, options = items or {}, options or {}
	bounds = bounds or options.bounds or { x = 0, y = 0, w = options.width or 1 }
	local gap = math.max(0, tonumber(options.gap) or SiK.UI.Metrics.spacing.sm)
	local minWidth = math.max(1, tonumber(options.minItemWidth) or 260)
	local requested = math.max(1, math.floor(tonumber(options.columns or options.maxColumns) or 4))
	local columns = math.max(1, math.min(requested,
		math.floor((bounds.w + gap) / (minWidth + gap))))
	local width = math.max(1, math.floor((bounds.w - gap * (columns - 1)) / columns))
	local heights, rects, y = {}, {}, bounds.y or 0
	for index = 1, #items do
		local item = items[index] or {}
		local measured = measuredHeight(options.measureItem, entries and entries[index], item, width, index, collection)
		heights[index] = math.max(1, tonumber(item.height) or tonumber(options.itemHeight) or 120, measured or 0)
	end
	for rowStart = 1, #items, columns do
		local rowEnd, rowHeight = math.min(#items, rowStart + columns - 1), 0
		for index = rowStart, rowEnd do rowHeight = math.max(rowHeight, heights[index]) end
		for index = rowStart, rowEnd do
			rects[index] = { x = (bounds.x or 0) + (index - rowStart) * (width + gap), y = y,
				w = width, h = options.equalRowHeight ~= false and rowHeight or heights[index] }
		end
		y = y + rowHeight + gap
	end
	return { rects = rects, columns = columns,
		contentHeight = #items > 0 and y - gap - (bounds.y or 0) or 0 }
end

-- Generic repeated-item layout. The item factory determines the terminal
-- visual type; Collection knows nothing about cards, addons or products.
function Collection.create(options)
	options = options or {}
	if type(options.parent) ~= "table" then return nil, "invalid_parent" end
	if type(options.itemFactory) ~= "function" then return nil, "invalid_item_factory" end
	local instance = { parent = options.parent, options = options, items = {}, entries = {} }
	function instance:clear()
		for index = 1, #self.entries do
			local entry = self.entries[index]
			if entry and entry.dispose then entry:dispose()
			elseif entry and entry.destroy then entry:destroy() end
		end
		self.entries, self.items = {}, {}
	end
	function instance:setItems(items)
		if self.disposed then return nil, "disposed" end
		self:clear(); self.items = items or {}
		for index = 1, #self.items do
			local entry, err = options.itemFactory(self.parent, self.items[index], index, self)
			if not entry then self:clear(); return nil, err or "item_create_failed" end
			self.entries[index] = entry
		end
		return self
	end
	function instance:reflow(bounds)
		if self.disposed then return nil, "disposed" end
		bounds = bounds or options.bounds or { x = options.x or 0, y = options.y or 0,
			w = options.w or options.width or 1, h = options.h or options.height or 1 }
		local measured = Collection.measure(self.items, options, bounds, self.entries, self)
		for index = 1, #self.entries do
			local entry = self.entries[index]
			if entry.reflow then entry:reflow(measured.rects[index]) end
		end
		self.contentHeight, self.columns = measured.contentHeight, measured.columns
		return self
	end
	function instance:dispose()
		if self.disposed then return false end
		self:clear(); self.parent = nil; self.disposed = true; return true
	end
	local ok, err = instance:setItems(options.items or {})
	if not ok then return nil, err end
	instance:reflow(options.bounds)
	return instance
end

return Collection
