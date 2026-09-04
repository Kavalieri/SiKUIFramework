require "SiK/UI/Namespace"
require "SiK/UI/Metrics"

local Collection = SiK.UI.Collection or {}
SiK.UI.Namespace.define("Collection", Collection)

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
		local gap = math.max(0, tonumber(options.gap) or SiK.UI.Metrics.spacing.sm)
		local minWidth = math.max(1, tonumber(options.minItemWidth) or 260)
		local requested = tonumber(options.columns or options.maxColumns) or 4
		local columns = math.max(1, math.min(math.max(1, requested),
			math.floor((bounds.w + gap) / (minWidth + gap))))
		if options.exactColumns == true and math.floor((bounds.w + gap) / (minWidth + gap)) < requested then
			columns = math.max(1, math.floor((bounds.w + gap) / (minWidth + gap)))
		end
		local width = math.max(1, math.floor((bounds.w - gap * (columns - 1)) / columns))
		local y, rowHeight = bounds.y, 0
		for index = 1, #self.entries do
			local column = (index - 1) % columns
			if column == 0 and index > 1 then y = y + rowHeight + gap; rowHeight = 0 end
			local item = self.items[index] or {}
			local height = math.max(1, tonumber(item.height) or tonumber(options.itemHeight) or 120)
			local entry = self.entries[index]
			if entry.reflow then entry:reflow({ x = bounds.x + column * (width + gap), y = y, w = width, h = height }) end
			rowHeight = math.max(rowHeight, height)
		end
		self.contentHeight = #self.entries > 0 and y + rowHeight - bounds.y or 0
		self.columns = columns
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
