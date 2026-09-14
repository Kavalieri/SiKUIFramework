require "ISUI/ISPanel"
require "SiK/UI/Metrics"
require "SiK/UI/Layout"
require "SiK/UI/Theme"
require "SiK/UI/Container"
require "SiK/UI/Scroll"
require "SiK/UI/VirtualList"
require "SiK/UI/OrderedBlocks"
require "SiK/UI/Controls"
require "SiK/UI/Block"

SiK = SiK or {}
SiK.UI = SiK.UI or {}

local Table = SiK.UI.Table or {}
SiK.UI.Namespace.define("Table", Table)

local TableInstance = {}
TableInstance.__index = TableInstance
local patchKey

local function journalSet(journal, target, key, value)
	local seen = journal.seen[target]
	if not seen then seen = {}; journal.seen[target] = seen end
	if not seen[key] then
		seen[key] = true
		journal[#journal + 1] = { target = target, key = key,
			present = target[key] ~= nil, value = target[key] }
	end
	target[key] = value
end

local function restoreJournal(journal)
	for index = #journal, 1, -1 do
		local entry = journal[index]
		if entry.present then entry.target[entry.key] = entry.value
		else entry.target[entry.key] = nil end
	end
end

local function numberOr(value, fallback)
	value = tonumber(value)
	if value == nil or value ~= value then return fallback end
	return value
end

local function createPanel(parent)
	local panel = ISPanel:new(0, 0, 0, 0)
	panel:initialise()
	if panel.instantiate then panel:instantiate() end
	if parent and parent.addChild then parent:addChild(panel) end
	return panel
end

-- Table is a terminal widget, not a visual container.  Its private root only
-- establishes a local coordinate system inside the declarative Block that
-- owns it; it must never introduce another frame, background or padding.
local function createTableRoot(options)
	local container, reason = SiK.UI.Container.create({
		parent = options.parent,
		x = options.x or 0, y = options.y or 0,
		w = options.w or options.width or 0,
		h = options.h or options.height or 0,
		padding = 0, background = false, border = false, theme = options.theme,
		playerNum = options.playerNum, controlId = "table",
	})
	if not container then return nil, reason end
	local root = {
		panel = container.panel, container = container,
		x = options.x or 0, y = options.y or 0,
		w = options.w or options.width or 0,
		h = options.h or options.height or 0,
		contentHeight = 0, listeners = {}, disposed = false,
		block = options.block, directBlock = options.directBlock == true,
		metrics = SiK.UI.Metrics.tokens(options.metrics),
	}
	root.panel._sikUiComponent = "table"

	function root:_sync(reasonId)
		if self.disposed then return end
		SiK.UI.Layout.apply(self.panel, { x = self.x, y = self.y, w = self.w, h = self.h })
		-- The containing Block owns the outer inset. Below an intermediate
		-- layout container, Table reserves only its functional scrollbar.
		local overflow = not self.directBlock and self.contentHeight > self.h
		self.contentRect, self.trackRect = SiK.UI.Block.resolveViewportRect(
			{ x = 0, y = 0, w = self.w, h = self.h }, overflow, { metrics = self.metrics })
		for index = 1, #self.listeners do self.listeners[index](reasonId or "sync") end
	end

	function root:syncBlockBounds()
		if not self.directBlock or not self.block or self.block.disposed then return self end
		local rect = self.block:getContentRect()
		self.x, self.y, self.w, self.h = rect.x, rect.y, rect.w, rect.h
		self:_sync("block")
		return self
	end

	function root:getContentRect()
		local rect = self.contentRect or { x = 0, y = 0, w = self.w, h = self.h }
		return { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
	end

	function root:getTrackRect()
		local rect = self.trackRect
		return rect and { x = rect.x, y = rect.y, w = rect.w, h = rect.h } or nil
	end

	function root:setBounds(x, y, w, h)
		if self.disposed then return nil, "disposed" end
		if self.directBlock then return self:syncBlockBounds() end
		self.x, self.y = tonumber(x) or self.x, tonumber(y) or self.y
		self.w, self.h = math.max(0, tonumber(w) or self.w), math.max(0, tonumber(h) or self.h)
		self:_sync("bounds")
		return self
	end

	function root:setContentHeight(height)
		if self.disposed then return nil, "disposed" end
		self.contentHeight = math.max(0, tonumber(height) or 0)
		self:_sync("content")
		return self
	end

	function root:subscribe(listener)
		if type(listener) ~= "function" then return nil, "invalid_listener" end
		self.listeners[#self.listeners + 1] = listener
		return listener
	end

	function root:unsubscribe(listener)
		for index = 1, #self.listeners do
			if self.listeners[index] == listener then table.remove(self.listeners, index); return true end
		end
		return false
	end

	function root:dispose()
		if self.disposed then return false end
		self.disposed = true
		self.listeners = {}
		if self.container then self.container:dispose() end
		self.container, self.panel = nil, nil
		return true
	end

	if root.directBlock then root:syncBlockBounds() else root:_sync("create") end
	return root
end

local function detach(parent, child)
	if not child then return end
	if parent and parent.removeChild then parent:removeChild(child) end
	if child.removeFromUIManager then child:removeFromUIManager() end
end

local function blockContentOwner(parent)
	if SiK.UI.Block and SiK.UI.Block.contentOwner then
		return SiK.UI.Block.contentOwner(parent)
	end
	return nil, nil
end

local function blockAncestors(parent)
	local blocks, seen, current, depth = {}, {}, parent, 0
	while type(current) == "table" and depth < 64 do
		local block = current._sikUiBlock
		if type(block) == "table" and not block.disposed and not seen[block] then
			seen[block] = true
			blocks[#blocks + 1] = block
		end
		current, depth = current.parent, depth + 1
	end
	return blocks
end

local function normalizedColumns(columns)
	if type(columns) ~= "table" or #columns < 2 or #columns > 5 then
		return nil, "column_count"
	end
	local result, keys = {}, {}
	for index = 1, #columns do
		local column = columns[index]
		if type(column) ~= "table" or type(column.key) ~= "string" or column.key == "" then
			return nil, "column_key"
		end
		if keys[column.key] then return nil, "column_key_duplicate:" .. column.key end
		keys[column.key] = true
		if column.title ~= nil and type(column.title) ~= "string" then return nil, "column_title" end
		if column.label ~= nil and type(column.label) ~= "string" then return nil, "column_label" end
		local flex = column.flex
		if flex == nil then flex = column.weight end
		if flex ~= nil and (tonumber(flex) == nil or tonumber(flex) <= 0) then
			return nil, "column_flex"
		end
		if column.flex ~= nil and column.weight ~= nil
			and tonumber(column.flex) ~= tonumber(column.weight) then
			return nil, "column_flex_conflict"
		end
		local copy = {}
		for key, value in pairs(column) do copy[key] = value end
		copy.title = copy.title or copy.label
		copy.flex = flex
		result[index] = copy
	end
	return result
end

--- Canonical typed boundary for imperative and declarative table schemas.
--- Returns a defensive normalized copy; callers never retain a partly valid
--- descriptor or need to implement their own label/weight compatibility path.
function Table.normalizeColumns(columns)
	return normalizedColumns(columns)
end

local function copyOptions(source)
	local out = {}
	if type(source) ~= "table" then return out end
	for key, value in pairs(source) do out[key] = value end
	return out
end

local function resolveBlockHeader(options)
	if options.blockHeader == false then return nil, 0 end
	local source = type(options.blockHeader) == "table" and options.blockHeader or {}
	local title = source.text or source.title or options.title
	local titleKey = source.titleKey or options.titleKey
	if title == nil and titleKey ~= nil then title = SiK.UI.resolveText(titleKey, titleKey) end
	local tooltip = source.tooltip or options.tooltip
	local info = source.info or options.info
	local action = source.action or options.action
	if title == nil and tooltip == nil and info == nil and action == nil then return nil, 0 end
	local spec = copyOptions(source)
	spec.text = tostring(title or "")
	spec.tooltip = tooltip
	spec.info = info
	spec.action = action
	spec.playerNum = source.playerNum or options.playerNum
	spec.profile = source.profile or options.profile
	spec.theme = source.theme or options.theme
	local defaultHeight = SiK.UI.Controls.metrics(spec.profile).rowHeight
	spec.h = math.max(1, numberOr(source.h or source.height or options.titleHeight, defaultHeight))
	return spec, spec.h
end

local function semanticId(kind, key, parentKey)
	if kind == "child" then
		return "child:" .. tostring(parentKey) .. ":" .. tostring(key)
	end
	return "parent:" .. tostring(key)
end

local function pageState(total, page, pageSize)
	total = math.max(0, math.floor(numberOr(total, 0)))
	pageSize = math.max(1, math.floor(numberOr(pageSize, 15)))
	local pageCount = total > 0 and math.ceil(total / pageSize) or 0
	page = pageCount > 0 and math.max(1, math.min(pageCount,
		math.floor(numberOr(page, 1)))) or 1
	local first = total > 0 and ((page - 1) * pageSize + 1) or 0
	local last = total > 0 and math.min(total, first + pageSize - 1) or 0
	return { total = total, page = page, pageSize = pageSize,
		pageCount = pageCount, first = first, last = last,
		hasPrevious = page > 1, hasNext = pageCount > 0 and page < pageCount }
end

local function manager()
	if type(getTextManager) == "function" then return getTextManager() end
	return nil
end

local function fontHeight(font)
	local value = manager()
	if value and value.getFontHeight then return value:getFontHeight(font) end
	return 14
end

local function measure(font, value)
	local text = tostring(value or "")
	local valueManager = manager()
	if valueManager and valueManager.MeasureStringX then return valueManager:MeasureStringX(font, text) end
	return string.len(text) * 7
end

local function truncate(font, value, width)
	return SiK.UI.Controls.truncateText(value,
		math.max(0, numberOr(width, 0)), font, "...")
end

local function colorParts(color, fallback)
	color = type(color) == "table" and color
		or (type(fallback) == "table" and fallback or {})
	return numberOr(color.r or color[1], 1), numberOr(color.g or color[2], 1),
		numberOr(color.b or color[3], 1), numberOr(color.a or color[4], 1)
end

function Table.metrics(options)
	options = options or {}
	local tokens = SiK.UI.Metrics.tokens(options.metrics)
	local font = options.font or (UIFont and UIFont.Small) or nil
	local resolvedFontHeight = fontHeight(font)
	local compact = options.density == "compact" and tokens.table.compact or nil
	local rowVerticalPadding = compact and numberOr(compact.rowVerticalPadding,
		tokens.table.rowVerticalPadding) or tokens.table.rowVerticalPadding
	local nominalRowHeight = compact and numberOr(compact.rowHeight, tokens.table.rowHeight)
		or tokens.table.rowHeight
	local minimumRowHeight = resolvedFontHeight + math.max(0, rowVerticalPadding) * 2
	return { font = font, fontHeight = resolvedFontHeight,
		rowHeight = math.max(minimumRowHeight, nominalRowHeight, numberOr(options.rowHeight, nominalRowHeight)),
		rowVerticalPadding = math.max(0, rowVerticalPadding), density = compact and "compact" or "standard",
		headerHeight = math.max(resolvedFontHeight + tokens.table.headerVerticalPadding * 2,
			numberOr(options.headerHeight, tokens.table.headerHeight)),
		gap = math.max(0, numberOr(options.columnGap or options.gap, tokens.table.columnGap)),
		left = math.max(0, numberOr(options.left, 0)), right = math.max(0, numberOr(options.right, 0)),
		cellPadding = math.max(0, numberOr(options.cellPadding, tokens.table.cellPadding)) }
end

local function measuredWidth(spec, font)
	local title = spec.title or spec.label or SiK.UI.resolveText(spec.titleKey, spec.key) or ""
	local widest = measure(spec.font or font, title)
	if spec.sortable ~= false then widest = widest + 18 end
	for index = 1, #(spec.measureValues or {}) do
		widest = math.max(widest, measure(spec.font or font, spec.measureValues[index]))
	end
	return math.max(numberOr(spec.minWidth or spec.min, 0), math.floor(widest) + numberOr(spec.measurePad, 12))
end

local function columnMinimum(spec, font)
	return math.max(numberOr(spec and spec.hardMinWidth, 24),
		numberOr(spec and (spec.minWidth or spec.min), 0),
		(spec and spec.measureValues) and measuredWidth(spec, font) or 0)
end

local function layoutKey(width, columns, options, metrics)
	local parts = { tostring(width), tostring(metrics.gap), tostring(metrics.left),
		tostring(metrics.right), tostring(metrics.cellPadding) }
	for index = 1, #columns do
		local spec = columns[index]
		parts[#parts + 1] = table.concat({ tostring(spec.key), tostring(spec.flex or spec.weight or ""),
			tostring(spec.width or ""), tostring(spec.widthFraction or ""),
			tostring(spec.minWidth or spec.min or ""), tostring(spec.hardMinWidth or ""),
			tostring(spec.start or ""), tostring(spec.startFraction or ""),
			tostring(spec.finish or ""), tostring(spec.finishFraction or ""),
			tostring(options.columnWidths and options.columnWidths[spec.key] or "") }, ":")
	end
	return table.concat(parts, "|")
end

local function edge(value, fraction, total, fallback)
	if tonumber(value) then return tonumber(value) end
	if tonumber(fraction) then return math.floor(total * tonumber(fraction)) end
	return fallback
end

function Table.resolveColumns(width, columns, options)
	width = math.max(1, numberOr(width, 1))
	columns, options = normalizedColumns(columns or {}) or {}, options or {}
	local metrics = Table.metrics(options)
	local key = layoutKey(width, columns, options, metrics)
	local cached = columns._sikLayoutCache
	if cached and cached.key == key then return cached.layout end
	local flow = false
	for index = 1, #columns do
		local spec = columns[index]
		if spec.flex or spec.weight or spec.width or spec.widthFraction or spec.measureValues then flow = true break end
	end
	local out = {}
	if not flow then
		for index = 1, #columns do
			local spec = columns[index]
			local first = edge(spec.start, spec.startFraction, width, 0)
			local finish = math.max(first, edge(spec.finish, spec.finishFraction, width,
				width - numberOr(spec.right, 0)))
			out[index] = { key = spec.key, title = spec.title or spec.label, titleKey = spec.titleKey,
				align = spec.align or "left", x = first, finish = finish,
				width = finish - first, w = finish - first,
				pad = numberOr(spec.pad, metrics.cellPadding), spec = spec }
		end
		columns._sikLayoutCache = { key = key, layout = out }
		return out
	end
	local widths, fixed, flexTotal, flexMinimum = {}, 0, 0, 0
	for index = 1, #columns do
		local spec = columns[index]
		local saved = options.columnWidths and tonumber(options.columnWidths[spec.key]) or nil
		if saved then widths[index] = math.max(columnMinimum(spec, metrics.font), math.floor(saved))
		elseif spec.flex or spec.weight then
			widths[index] = 0
			flexTotal = flexTotal + math.max(0, numberOr(spec.flex or spec.weight, 0))
			flexMinimum = flexMinimum + math.max(0, numberOr(spec.minWidth or spec.min, 0))
		elseif spec.widthFraction then
			widths[index] = math.max(numberOr(spec.minWidth or spec.min, 0),
				math.floor(width * numberOr(spec.widthFraction, 0)))
		else widths[index] = numberOr(spec.width, measuredWidth(spec, metrics.font)) end
		fixed = fixed + widths[index]
	end
	local available = math.max(0, width - metrics.left - metrics.right
		- metrics.gap * math.max(0, #columns - 1) - fixed)
	local flexExtra = math.max(0, available - flexMinimum)
	local shrink = flexMinimum > 0 and math.min(1, available / flexMinimum) or 1
	local x = metrics.left
	for index = 1, #columns do
		local spec, colW = columns[index], widths[index]
		if (spec.flex or spec.weight) and not (options.columnWidths and tonumber(options.columnWidths[spec.key])) then
			colW = math.floor(math.max(0, numberOr(spec.minWidth or spec.min, 0)) * shrink)
			if flexExtra > 0 then colW = colW + math.floor(flexExtra * numberOr(spec.flex or spec.weight, 0) / math.max(1, flexTotal)) end
			colW = math.max(numberOr(spec.hardMinWidth, 24), colW)
		end
		out[index] = { key = spec.key, title = spec.title or spec.label, titleKey = spec.titleKey,
			align = spec.align or "left", x = x, finish = x + colW, width = colW, w = colW,
			pad = numberOr(spec.pad, metrics.cellPadding), spec = spec }
		x = x + colW + metrics.gap
	end
	local last, target = out[#out], width - metrics.right
	if last and last.x <= target and last.finish <= target then
		last.finish = target last.width = target - last.x last.w = last.width
	end
	columns._sikLayoutCache = { key = key, layout = out }
	return out
end

--- Returns the exact height that a non-direct Table will claim for a row set.
--- Builder and imperative consumers use this same calculation, including the
--- real font-derived header height, so a table never outgrows its parent Block.
function Table.intrinsicHeight(rowCount, options)
	options = options or {}
	local metrics = Table.metrics(options)
	local count = math.max(0, math.floor(numberOr(rowCount, 0)))
	local minimumRows = math.max(0, math.floor(numberOr(options.minRows, 1)))
	local maximumRows = tonumber(options.maxRows)
	count = math.max(minimumRows, count)
	if maximumRows then count = math.min(count, math.max(minimumRows,
		math.floor(maximumRows))) end
	local pagerHeight = options.pagination and math.max(1,
		numberOr(options.pagination.height,
			SiK.UI.Metrics.tokens(options.metrics).table.pagerHeight)) or 0
	local height = metrics.headerHeight + pagerHeight + count * metrics.rowHeight
	height = math.max(numberOr(options.minHeight, 0), height)
	if options.maxHeight ~= nil then height = math.min(height,
		math.max(1, numberOr(options.maxHeight, height))) end
	return math.max(1, height)
end

function Table.drawExpansionPrefix(panel, options)
	options = options or {}
	if not panel then return 0 end
	local depth = math.max(0, math.floor(numberOr(options.depth, 0)))
	local indent = math.max(14, numberOr(options.indent, 18))
	local x = numberOr(options.x, 0) + depth * indent
	local y = math.max(0, math.floor((panel.height - 14) / 2))
	if options.hasChildren == true then
		SiK.UI.Icon.drawRotatedExact(panel, "sik.arrow.right.14", x + 2, y,
			14, 14, options.expanded and 90 or 0)
		return depth * indent + 18
	end
	if depth > 0 and panel.drawRect then
		local color = SiK.UI.Theme.tokens(options.theme).divider
		local midY = math.floor(panel.height / 2)
		panel:drawRect(x + 6, 0, 1, midY, color.a, color.r, color.g, color.b)
		panel:drawRect(x + 6, midY, 7, 1, color.a, color.r, color.g, color.b)
		return depth * indent + 18
	end
	return 0
end

-- Compatibility renderer for consumers being migrated to Table.create. It
-- uses the same column resolver and chrome as the canonical Table instance.
function Table.drawHeader(panel, columns, sortKey, sortAsc, y, font, options)
	if not panel then return nil, "invalid_panel" end
	local metrics = Table.metrics({ font = font })
	local instance = setmetatable({ columns = columns or {},
		columnOptions = options or {}, columnLayout = Table.resolveColumns(panel.width,
			columns or {}, options or {}), metrics = metrics,
		colors = SiK.UI.Theme.tokens(), sortKey = sortKey,
		sortAsc = sortAsc ~= false }, TableInstance)
	instance:_drawHeader(panel)
	return instance.columnLayout
end

function Table.attachHeaderResize(panel, columns, options)
	if not panel then return nil, "invalid_panel" end
	panel._sikColumns, panel._sikColumnOptions = columns, options or {}
	return panel
end

function Table.resolve(contentRect, columns, options)
	contentRect = contentRect or {}
	local width = math.max(0, numberOr(contentRect.w or contentRect.contentW, 0))
	return { contentRect = { x = numberOr(contentRect.x, 0), y = numberOr(contentRect.y, 0),
		w = width, h = math.max(0, numberOr(contentRect.h, 0)) },
		columns = Table.resolveColumns(width, columns or {}, options) }
end

function Table.rowRect(contentRect, rowIndex, options)
	options = options or {}
	local metrics, index = Table.metrics(options), math.max(1, math.floor(numberOr(rowIndex, 1)))
	local height, header = metrics.rowHeight, numberOr(options.headerHeight, 0)
	return { x = numberOr(contentRect and contentRect.x, 0),
		y = numberOr(contentRect and contentRect.y, 0) + header + (index - 1) * height,
		w = math.max(0, numberOr(contentRect and (contentRect.w or contentRect.contentW), 0)),
		h = height, rowIndex = index }
end

function Table.hitRect(contentRect, rowIndex, options) return Table.rowRect(contentRect, rowIndex, options) end

function Table.columnAtX(layout, x)
	for index = 1, #(layout or {}) do
		local column = layout[index]
		if x >= column.x and (x < column.finish or index == #layout) then return column end
	end
	return nil
end

local function projection(column, item, index)
	local value = nil
	if type(column.value) == "function" then value = column.value(item, index)
	elseif type(item) == "table" then value = item[column.key] end
	if type(value) == "table" then return value end
	return { text = value }
end

local function drawText(panel, text, column, y, font, color)
	if not panel.drawText then return end
	local r, g, b, a = colorParts(color, { r = 1, g = 1, b = 1, a = 1 })
	local clipped = truncate(font, text, math.max(0, column.width - column.pad * 2))
	if column.align == "right" and panel.drawTextRight then
		panel:drawTextRight(clipped, column.finish - column.pad, y, r, g, b, a, font)
	elseif column.align == "center" and panel.drawTextCentre then
		panel:drawTextCentre(clipped, column.x + column.width / 2, y, r, g, b, a, font)
	else panel:drawText(clipped, column.x + column.pad, y, r, g, b, a, font) end
end

function TableInstance:_drawHeader(panel)
	if panel.drawRect and (self.colors.tableHeader or self.colors.surface) then
		local r, g, b, a = colorParts(self.colors.tableHeader, self.colors.surface)
		panel:drawRect(0, 0, panel.width, panel.height, a, r, g, b)
	end
	local y = math.max(0, math.floor((panel.height - self.metrics.fontHeight) / 2))
	for index = 1, #self.columnLayout do
		local column = self.columnLayout[index]
		local label = column.title or SiK.UI.resolveText(column.titleKey, column.key)
		local labelColumn = column
		if self.sortKey == column.key then
			labelColumn = {}
			for key, value in pairs(column) do labelColumn[key] = value end
			labelColumn.width = math.max(1, column.width - 18)
			labelColumn.finish = column.x + labelColumn.width
		end
		drawText(panel, label, labelColumn, y, column.spec.font or self.metrics.font, self.colors.textMuted)
		if self.sortKey == column.key then
			SiK.UI.Icon.drawRotatedExact(panel, "sik.arrow.right.14",
				column.finish - column.pad - 14, math.floor((panel.height - 14) / 2),
				14, 14, self.sortAsc == false and 90 or 270)
		end
		if index < #self.columnLayout and panel.drawRect then
			local r, g, b, a = colorParts(self.colors.tableRowDivider, self.colors.divider)
			panel:drawRect(column.finish, 0, 1, panel.height - 1, a, r, g, b)
		end
	end
	if panel.drawRect then
		local r, g, b, a = colorParts(self.colors.tableRowDivider, self.colors.divider)
		panel:drawRect(0, panel.height - 1, panel.width, 1, a, r, g, b)
	end
end

function TableInstance:_drawRow(panel)
	local projected = panel._sikProjected
	if not projected then return end
	if projected.kind == "pager" then return self:_drawChildPager(panel, projected) end
	local descriptor = panel._sikDescriptor
	local hovered = panel.isMouseOver and panel:isMouseOver() or false
	-- Every row owns a complete SiK surface.  Leaving odd rows transparent made
	-- product tables look like a raw vanilla list even though the data and
	-- interaction came through this component.
	local background = panel._sikSelected and self.colors.selected
		or (hovered and self.colors.tableRowHover)
		or (projected.depth > 0 and self.colors.tableRowChild)
		or (projected.hasChildren and self.colors.tableRowGroup)
		or (panel._sikDataIndex % 2 == 0 and self.colors.tableRowAlt)
		or self.colors.tableRow
	if background and panel.drawRect then
		local r, g, b, a = colorParts(background, self.colors.tableRow)
		panel:drawRect(0, 0, panel.width, panel.height, a, r, g, b)
	end
	if panel.drawRect then
		local r, g, b, a = colorParts(self.colors.tableRowDivider, self.colors.divider)
		panel:drawRect(0, math.max(0, panel.height - 1), panel.width, 1, a, r, g, b)
	end
	for index = 1, #self.columnLayout do
		local column = self.columnLayout[index]
		local rect = { key = column.key, align = column.align, x = column.x,
			finish = column.finish, width = column.width, pad = column.pad, spec = column.spec }
		if index == 1 then
			local prefix = Table.drawExpansionPrefix(panel, {
				x = column.x, depth = projected.depth, indent = self.indent,
				hasChildren = projected.hasChildren,
				expanded = self.expanded[projected.key],
				alpha = descriptor and descriptor.alpha,
			}) or 0
			rect.x, rect.width = rect.x + prefix, math.max(0, rect.width - prefix)
			rect.finish = rect.x + rect.width
		end
		local described = descriptor and descriptor.cells and descriptor.cells[column.key]
		if index == 1 and descriptor and descriptor.texture then
			local iconSize = math.max(1, numberOr(descriptor.iconSize, math.min(32, panel.height - 8)))
			local iconX = rect.x + rect.pad
			local iconY = math.floor((panel.height - iconSize) / 2)
			local alpha = numberOr(descriptor.alpha, 1)
			if panel.drawTextureScaledAspect then
				panel:drawTextureScaledAspect(descriptor.texture, iconX, iconY,
					iconSize, iconSize, alpha, 1, 1, 1)
			end
			if descriptor.overlayTexture and panel.drawTexture then
				panel:drawTexture(descriptor.overlayTexture, iconX, iconY - 1, 1, 1, 1, alpha)
			end
			local iconGap = math.max(0, numberOr(descriptor.iconGap, 8))
			local consumed = rect.pad + iconSize + iconGap
			rect.x, rect.width = rect.x + consumed, math.max(0, rect.width - consumed)
			rect.finish = rect.x + rect.width
		end
		if described then
			local value = type(described) == "table" and described or { text = described }
			local target = { x = rect.x, finish = rect.finish, width = rect.width,
				pad = value.pad ~= nil and value.pad or rect.pad,
				align = value.align or rect.align }
			local font = value.font or column.spec.font or self.metrics.font
			local color = value.color or column.spec.color or self.colors.text
			if descriptor.alpha and type(color) == "table" then
				color = { r = color.r or color[1], g = color.g or color[2],
					b = color.b or color[3], a = numberOr(color.a or color[4], 1) * descriptor.alpha }
			end
			drawText(panel, value.text or "", target,
				math.max(0, math.floor((panel.height - fontHeight(font)) / 2)), font, color)
		elseif type(column.spec.render) == "function" then
			column.spec.render(panel, projected.data, rect, projected.sourceIndex, projected.depth)
		else
			local value = projection(column.spec, projected.data, projected.sourceIndex)
			local target = { x = rect.x, finish = rect.finish, width = rect.width,
				pad = rect.pad, align = value.align or rect.align }
			local font = value.font or column.spec.font or self.metrics.font
			drawText(panel, value.text or "", target,
				math.max(0, math.floor((panel.height - fontHeight(font)) / 2)), font,
				value.color or column.spec.color or self.colors.text)
		end
		self:_layoutCellActions(panel, column, rect, projected)
	end
end

-- The inline pager is projected as a structural row below its own expanded
-- parent.  It deliberately has no semantic selection, descriptor, cell action
-- or product row callback: pagination is navigation, never data.
function TableInstance:_drawChildPager(panel, projected)
	local state = projected.pageState
	if not state then return end
	local background = self.colors.tableRowChild or self.colors.tableRow
	if background and panel.drawRect then
		local r, g, b, a = colorParts(background, self.colors.tableRow)
		panel:drawRect(0, 0, panel.width, panel.height, a, r, g, b)
	end
	if panel.drawRect then
		local r, g, b, a = colorParts(self.colors.tableRowDivider, self.colors.divider)
		panel:drawRect(0, math.max(0, panel.height - 1), panel.width, 1, a, r, g, b)
	end
	local y = math.max(0, math.floor((panel.height - self.metrics.fontHeight) / 2))
	local r, g, b, a = colorParts(self.colors.textMuted, self.colors.text)
	local enabled = not state.disabled
	local labelWidth = math.max(0, panel.width - self.pagerButtonWidth * 2 - 12)
	if panel.drawText then
		panel:drawText(truncate(self.metrics.font, projected.pagerLabel or "", labelWidth), 8, y,
			r, g, b, enabled and a or a * 0.35, self.metrics.font)
		panel:drawText("<", panel.width - self.pagerButtonWidth * 2, y, r, g, b,
			state.hasPrevious and enabled and a or a * 0.35, self.metrics.font)
	end
	if panel.drawTextRight then
		panel:drawTextRight(">", panel.width - 4, y, r, g, b,
			state.hasNext and enabled and a or a * 0.35, self.metrics.font)
	end
end

-- A column may declare one reusable action adapter. The framework owns the
-- control lifecycle and geometry; the consumer only supplies action data and
-- creates/updates the neutral widget through callbacks.
function TableInstance:_actionItems(spec, projected)
	local actions = spec and spec.actions
	if type(actions) ~= "table" then return nil end
	local items = actions.items
	if type(items) == "function" then
		items = items(projected.data, projected.sourceIndex, projected.depth)
	end
	return type(items) == "table" and items or nil
end

function TableInstance:_disposeCellActions(row)
	local controls = row and row._sikActionControls or {}
	for index = 1, #controls do
		local entry = controls[index]
		if entry.adapter and type(entry.adapter.dispose) == "function" then
			entry.adapter.dispose(entry.control, entry.context)
		elseif entry.control and entry.control.removeFromUIManager then
			entry.control:removeFromUIManager()
		end
	end
	if row then row._sikActionControls = {} end
end

function TableInstance:_syncCellActions(row, projected)
	self:_disposeCellActions(row)
	row._sikActionControls = {}
	for columnIndex = 1, #self.columnLayout do
		local column = self.columnLayout[columnIndex]
		local adapter, items = column.spec.actions, self:_actionItems(column.spec, projected)
		if type(adapter) == "table" and type(adapter.create) == "function" then
			for actionIndex = 1, #(items or {}) do
				local context = { table = self, row = row, column = column.spec,
					data = projected.data, sourceIndex = projected.sourceIndex,
					depth = projected.depth, action = items[actionIndex],
					actionIndex = actionIndex }
				local control = adapter.create(context)
				if control then
					row:addChild(control)
					local entry = { control = control, adapter = adapter, context = context,
						columnKey = column.key }
					row._sikActionControls[#row._sikActionControls + 1] = entry
					if type(adapter.update) == "function" then adapter.update(control, context) end
				end
			end
		end
	end
end

function TableInstance:_layoutCellActions(row, column, rect, projected)
	local actions = column.spec.actions
	if type(actions) ~= "table" then return end
	local matching = {}
	for index = 1, #(row._sikActionControls or {}) do
		local entry = row._sikActionControls[index]
		if entry.columnKey == column.key then matching[#matching + 1] = entry end
	end
	local gap = math.max(0, numberOr(actions.gap, 4))
	local count = #matching
	if count == 0 then return end
	local width = math.max(0, (rect.width - gap * (count - 1)) / count)
	for index = 1, count do
		local entry = matching[index]
		local bounds = { x = rect.x + (index - 1) * (width + gap), y = 2,
			w = width, h = math.max(0, row.height - 4) }
		entry.context.bounds = bounds
		local control = entry.control
		if control.setX then control:setX(bounds.x) else control.x = bounds.x end
		if control.setY then control:setY(bounds.y) else control.y = bounds.y end
		if control.setWidth then control:setWidth(bounds.w) else control.width = bounds.w end
		if control.setHeight then control:setHeight(bounds.h) else control.height = bounds.h end
		if type(entry.adapter.layout) == "function" then
			entry.adapter.layout(control, entry.context, bounds)
		end
	end
end

function TableInstance:_children(item, index)
	if not self.expansion then return nil end
	local children = self.expansion.childrenOf(item, index)
	if type(children) ~= "table" then children = nil end
	local hasChildren = children and #children > 0 or false
	if self.expansion.hasChildren then
		hasChildren = self.expansion.hasChildren(item, index) == true
	end
	return children or {}, hasChildren
end

function TableInstance:_registerSemantic(kind, key, parentKey, item, index, parentItem)
	local id = semanticId(kind, key, parentKey)
	local selection = self.semanticById[id]
	if not selection then
		selection = { id = id, kind = kind, key = key, parentKey = parentKey }
		self.semanticById[id] = selection
	end
	selection.item = item
	selection.index = index
	selection.parentItem = parentItem
	if kind == "parent" then self.parentByKey[key] = selection end
	return selection
end

function TableInstance:_rebuildSemanticIndex()
	local previous = self.semanticById
	self.semanticById, self.parentByKey, self.firstPageParentKey = {}, {}, nil
	for index = 1, #self.rows do
		local item = self.rows[index]
		local key = self.keyOf(item, index)
		local id = semanticId("parent", key)
		if previous[id] then self.semanticById[id] = previous[id] end
		local parent = self:_registerSemantic("parent", key, nil, item, index, nil)
		local children, hasChildren = self:_children(item, index)
		parent.children = children
		parent.hasChildren = hasChildren
		if hasChildren and not self.firstPageParentKey then self.firstPageParentKey = key end
		for childIndex = 1, #(children or {}) do
			local child = children[childIndex]
			local childKey = self.expansion.keyOf and self.expansion.keyOf(child, childIndex, item)
				or (tostring(key) .. ":" .. tostring(childIndex))
			local childId = semanticId("child", childKey, key)
			if previous[childId] then self.semanticById[childId] = previous[childId] end
			self:_registerSemantic("child", childKey, key, child, childIndex, item)
		end
	end
	if self.semanticSelection and not self.semanticById[self.semanticSelection.id] then
		self.semanticSelection = nil
	elseif self.semanticSelection then
		self.semanticSelection = self.semanticById[self.semanticSelection.id]
	end
	local liveSelections = {}
	for id in pairs(self.semanticSelections) do
		if self.semanticById[id] then liveSelections[id] = true end
	end
	self.semanticSelections = liveSelections
	local active = self.activePageParentKey and self.parentByKey[self.activePageParentKey] or nil
	if not active or not active.children then self.activePageParentKey = nil end
end

function TableInstance:_projectParent(parent, out, semanticIndex)
	semanticIndex = semanticIndex or self.semanticById
	out[#out + 1] = { data = parent.item, depth = 0, key = parent.key,
		visualKey = parent.id, semantic = parent, sourceIndex = parent.index,
			hasChildren = parent.hasChildren == true }
	local children = parent.children
	if not parent.hasChildren then return end
	if not self.pagination then
		if not self.expanded[parent.key] then return end
		for childIndex = 1, #children do
			local child = children[childIndex]
			local childKey = self.expansion.keyOf and self.expansion.keyOf(child, childIndex, parent.item)
				or (tostring(parent.key) .. ":" .. tostring(childIndex))
			local selection = semanticIndex[semanticId("child", childKey, parent.key)]
			out[#out + 1] = { data = child, depth = 1, key = childKey,
				visualKey = selection.id, semantic = selection, parentKey = parent.key,
				sourceIndex = childIndex, hasChildren = false }
		end
		return
	end
	local size = self.pagination and self.pagination.pageSize or #children
	local total, requestedPage = #children, self.childPages[parent.key]
	local externalState = nil
	if self.pagination and self.pagination.external then
		externalState = self.pagination.stateOf(parent.item, parent.key, self)
		if type(externalState) == "table" then
			-- External hierarchical sources distinguish rendered child rows from
			-- physical units.  Pagination owns rows only; the parent/header is never
			-- part of either count. `total` remains a compatibility alias for rows.
			total = math.max(0, math.floor(numberOr(
				externalState.totalRows, numberOr(externalState.total, total))))
			requestedPage = numberOr(externalState.page, requestedPage)
			size = math.max(1, math.floor(numberOr(externalState.pageSize, size)))
		end
	end
	local state = pageState(total, requestedPage, size)
	state.totalRows = total
	state.totalUnits = type(externalState) == "table"
		and math.max(0, math.floor(numberOr(externalState.totalUnits, total))) or total
	state.pending = type(externalState) == "table" and externalState.pending == true or false
	state.stale = type(externalState) == "table" and externalState.stale == true or false
	state.disabled = type(externalState) == "table" and externalState.disabled == true or false
	state.disabled = state.disabled or state.pending or state.stale
	state.disabledReason = type(externalState) == "table" and externalState.disabledReason or nil
	if state.pending then state.disabledReason = "page_pending"
	elseif state.stale then state.disabledReason = "page_stale" end
	self.childPages[parent.key] = state.page
	self.childPageStates[parent.key] = state
	-- The pager belongs to the expanded hierarchy currently being inspected.
	-- A collapsed row must never become the active pageable parent merely
	-- because it appears earlier in the table.
	if self.expanded[parent.key] and not self.activePageParentKey then
		self.activePageParentKey = parent.key
	end
	if not self.expanded[parent.key] or state.total == 0 then return end
	local firstChild = self.pagination and self.pagination.external and 1 or state.first
	local lastChild = self.pagination and self.pagination.external and #children or state.last
	for childIndex = firstChild, lastChild do
		local child = children[childIndex]
		local childKey = self.expansion.keyOf and self.expansion.keyOf(child, childIndex, parent.item)
			or (tostring(parent.key) .. ":" .. tostring(childIndex))
		local selection = semanticIndex[semanticId("child", childKey, parent.key)]
		out[#out + 1] = { data = child, depth = 1, key = childKey,
			visualKey = selection.id, semantic = selection, parentKey = parent.key,
			sourceIndex = childIndex, hasChildren = false }
	end
	-- A single-page hierarchy needs no navigation row. Keeping it visible adds
	-- noise and consumes the height of a real data row without any possible act.
	if state.pageCount <= 1 then return end
	local label = nil
	if self.pagination and type(self.pagination.labelOf) == "function" then
		label = self.pagination.labelOf(state, parent.item, parent.key, self)
	end
	-- Keep the fallback language-neutral. Product localizers own the approved
	-- sentence, including plural forms and locale-specific unit labels.
	if type(label) ~= "string" or label == "" then
		label = tostring(state.first) .. "-" .. tostring(state.last) .. " / "
			.. tostring(state.totalRows) .. " - " .. tostring(state.totalUnits)
	end
	out[#out + 1] = { kind = "pager", data = nil, depth = 1,
		key = "pager:" .. tostring(parent.key), visualKey = "pager:" .. tostring(parent.key),
		parentKey = parent.key, sourceIndex = 0, hasChildren = false,
		pageState = state, pagerLabel = label }
end

function TableInstance:_projectRows()
	local visible = {}
	self.projectedByParentKey = {}
	if self.expansion then
		self.childPageStates = {}
		for index = 1, #self.rows do
			local key = self.keyOf(self.rows[index], index)
			local first = #visible + 1
			self:_projectParent(self.parentByKey[key], visible)
			local block = {}
			for projectedIndex = first, #visible do block[#block + 1] = visible[projectedIndex] end
			self.projectedByParentKey[key] = block
		end
		-- Pagination belongs exclusively to the hierarchy the player opened.
		-- Falling back to the first expandable root paints a misleading global
		-- pager at the bottom of an otherwise virtualized/scrollable table.
		local active = self.activePageParentKey
		self.pageState = active and self.childPageStates[active]
			or pageState(0, 1, self.pagination and self.pagination.pageSize or 15)
		self.page = self.pageState.page
		return visible
	end
	for index = 1, #self.rows do
		local key = self.keyOf(self.rows[index], index)
		local selection = self.parentByKey[key]
		local projected = { data = selection.item, depth = 0, key = key,
			visualKey = selection.id, semantic = selection, sourceIndex = index, hasChildren = false }
		visible[#visible + 1] = projected
		self.projectedByParentKey[key] = { projected }
	end
	if not self.pagination then
		self.pageState = pageState(#visible, 1, math.max(1, #visible))
		return visible
	end
	self.pageState = pageState(#visible, self.page, self.pagination.pageSize)
	self.page = self.pageState.page
	local paged = {}
	for index = self.pageState.first, self.pageState.last do paged[#paged + 1] = visible[index] end
	return paged
end

function TableInstance:_createRow(_, width, height)
	local row = ISPanel:new(0, 0, width, height)
	row:initialise()
	if row.instantiate then row:instantiate() end
	row._sikTable = self
	row.prerender = function(panel)
		local owner = panel._sikTable
		if owner and not owner.disposed then
			owner:_drawRow(panel)
			local adapter = owner.rowAdapter
			if panel._sikProjected and panel._sikProjected.kind ~= "pager"
					and adapter and adapter.afterRender then
				adapter.afterRender(owner:_rowContext(panel))
			end
		end
	end
	row.dispose = function(panel)
		local owner = panel._sikTable
		if owner then
			if panel._sikProjected and panel._sikProjected.kind ~= "pager"
					and owner.rowAdapter and owner.rowAdapter.dispose then
				owner.rowAdapter.dispose(owner:_rowContext(panel))
			end
			owner:_disposeCellActions(panel)
		end
	end
	return row
end

function TableInstance:_rowContext(row, event)
	-- Virtual rows can be recycled between pointer-down and pointer-up. Prefer
	-- the semantic snapshot carried by VirtualList for every adapter callback.
	local projected = event and event.item or (row and row._sikProjected or nil)
	return { playerNum = self.playerNum, component = self, row = row,
		item = projected and projected.data or nil,
		index = projected and projected.sourceIndex or nil,
		visibleIndex = event and event.index or (row and row._sikDataIndex or nil),
		key = projected and projected.key or nil,
		parentKey = projected and projected.parentKey or nil,
		kind = projected and projected.semantic and projected.semantic.kind or nil,
		selection = projected and projected.semantic or nil,
		event = event }
end

function TableInstance:_isExpansionHit(row, x)
	local projected = row and row._sikProjected or nil
	if not projected or not projected.hasChildren then return false end
	local firstColumn = self.columnLayout[1]
	local prefixStart = (firstColumn and firstColumn.x or 0) + projected.depth * self.indent
	x = tonumber(x) or 0
	return x >= prefixStart and x <= prefixStart + self.expansionHitbox
end

function TableInstance:_updateRow(row, projected, index)
	row._sikProjected, row._sikDataIndex, row._sikTable = projected, index, self
	row._sikSelected = projected.semantic and self.semanticSelections[projected.semantic.id] == true or false
	if projected.kind == "pager" then
		self:_disposeCellActions(row)
		row._sikDescriptor = nil
		return
	end
	self:_syncCellActions(row, projected)
	if self.rowAdapter and self.rowAdapter.update then
		self.rowAdapter.update(self:_rowContext(row))
	end
	row._sikDescriptor = nil
	if self.rowAdapter and self.rowAdapter.describe then
		row._sikDescriptor = self.rowAdapter.describe(self:_rowContext(row))
	end
end

function TableInstance:_drawPager(panel)
	if not self.pagination or not self.pageState then return end
	local state, y = self.pageState, math.max(0, math.floor((panel.height - self.metrics.fontHeight) / 2))
	local r, g, b, a = colorParts(self.colors.textMuted, self.colors.text)
	local enabledAlpha = state.disabled and a * 0.35 or a
	if panel.drawTextCentre then panel:drawTextCentre(tostring(state.page) .. " / " .. tostring(math.max(1, state.pageCount)),
		panel.width / 2, y, r, g, b, enabledAlpha, self.metrics.font) end
	if panel.drawText then panel:drawText("<", self.pagerPrevX, y, r, g, b,
		state.hasPrevious and not state.disabled and a or a * 0.35, self.metrics.font) end
	if panel.drawTextRight then panel:drawTextRight(">", self.pagerNextX, y, r, g, b,
		state.hasNext and not state.disabled and a or a * 0.35, self.metrics.font) end
end

local function reservedPagerHeight(instance)
	if not instance.pager or not instance.pageState
			or instance.pageState.pageCount <= 1 then return 0 end
	return instance.pagerHeight
end

function TableInstance:_visibleRowCount()
	if self.keyedMode then return SiK.UI.OrderedBlocks.projectedCount(self.keyedRoot) end
	return #self.projectedRows
end

function TableInstance:_syncGeometry()
	if self.disposed then return end
	local visiblePagerHeight = reservedPagerHeight(self)
	local content = self.root:getContentRect()
	local signature = table.concat({ tostring(content.x), tostring(content.y),
		tostring(content.w), tostring(content.h), tostring(self.root.w),
		tostring(self.root.h), tostring(self.blockHeaderHeight),
		tostring(self.metrics.headerHeight), tostring(visiblePagerHeight),
		tostring(self:_visibleRowCount()) }, ":")
	if self._geometrySignature == signature then return self end
	self._geometrySignature = signature
	local y = content.y
	if self.blockHeader then
		SiK.UI.Layout.apply(self.blockHeader, { x = content.x, y = y,
			w = content.w, h = self.blockHeaderHeight })
		if self.blockHeader.reflow then self.blockHeader:reflow(content.w) end
		y = y + self.blockHeaderHeight + self.blockHeaderGap
	end
	SiK.UI.Layout.apply(self.header, { x = content.x, y = y, w = content.w, h = self.metrics.headerHeight })
	local rowsY = y + self.metrics.headerHeight
	local rowsBottom = content.y + content.h
	if visiblePagerHeight > 0 then
		SiK.UI.Layout.apply(self.pager, { x = content.x, y = rowsBottom - visiblePagerHeight,
			w = content.w, h = visiblePagerHeight })
		self.pagerPrevX, self.pagerNextX = math.max(4, content.w / 2 - 40), math.min(content.w - 4, content.w / 2 + 40)
		rowsBottom = rowsBottom - visiblePagerHeight
	end
	local rowsRect = { x = content.x, y = rowsY, w = content.w,
		h = math.max(0, rowsBottom - rowsY) }
	local trackRect = self.root:getTrackRect()
	if trackRect then
		trackRect.y = rowsRect.y
		trackRect.h = rowsRect.h
	end
	-- Header, rows and pager are siblings inside the framed block.  The rows
	-- viewport must begin below the header; using the whole Block content rect
	-- made row one paint over the column labels and placed the table above its
	-- own container.
	self.columnLayout = Table.resolveColumns(content.w, self.columns, self.columnOptions)
	local _, refreshed = self.scroll:update({ viewportRect = rowsRect, trackRect = trackRect,
		trackRectSet = true, contentHeight = self:_visibleRowCount() * self.metrics.rowHeight }, "table-geometry")
	if self.emptyPanel then SiK.UI.Layout.apply(self.emptyPanel, rowsRect) end
	if self.list and not refreshed then self.list:refresh() end
	return self
end

function TableInstance:getRequiredHeight(rowCount)
	local count = math.max(0, math.floor(numberOr(rowCount, self:_visibleRowCount())))
	count = math.max(self.minRows, count)
	if self.maxRows then count = math.min(self.maxRows, count) end
	local height = self.paddingY * 2 + self.blockHeaderHeight + self.blockHeaderGap + self.metrics.headerHeight
		+ reservedPagerHeight(self) + count * self.metrics.rowHeight
	height = math.max(self.minHeight, height)
	if self.maxHeight then height = math.min(self.maxHeight, height) end
	return height
end

--- Explicit content mode is for a parent ScrollDock: every projected row is
--- visible in this widget and the outer Dock is the only vertical scroller.
function TableInstance:getIntrinsicHeight()
	return self:getRequiredHeight(self:_visibleRowCount())
end

function TableInstance:_applyAutoHeight()
	if not self.autoHeight or self.disposed then return self end
	local height = self:getRequiredHeight()
	if self.root.h ~= height then
		if self.root.directBlock then
			local block = self.root.block
			block:setBounds(block.x, block.y, block.w,
				math.max(0, block.h + height - self.root.h))
		else
			self.root:setBounds(self.root.x, self.root.y, self.root.w, height)
		end
	end
	return self
end

function TableInstance:_publishProjected(projected, preserveOffset)
	local previousOffset = preserveOffset == true and self.scroll:getScrollOffset() or 0
	self.projectedRows = projected
	if self.pager then self.pager:setVisible(reservedPagerHeight(self) > 0) end
	local chromeHeight = self.blockHeaderHeight + self.blockHeaderGap
		+ self.metrics.headerHeight + reservedPagerHeight(self)
	local contentHeight = chromeHeight + #projected * self.metrics.rowHeight
	self.root:setContentHeight(contentHeight)
	-- The framed Block is the sole overflow owner. It publishes W-16 when the
	-- rows fit and W-40 only when they do not; Table then consumes that rect.
	if self.root.directBlock then self.root.block:setContentHeight(contentHeight) end
	self:_applyAutoHeight()
	if self.emptyPanel then self.emptyPanel:setVisible(#projected == 0) end
	local result, reason = self.list:setData(projected, preserveOffset == true)
	if result and preserveOffset == true then self.scroll:setScrollOffset(previousOffset) end
	return result, reason
end

function TableInstance:_keyedProvider(root)
	local owner = self
	return {
		count = function() return SiK.UI.OrderedBlocks.projectedCount(root) end,
		get = function(index)
			local projected, rootIndex, entry = SiK.UI.OrderedBlocks.projectedAt(root, index)
			if projected and projected.depth == 0 then
				projected.sourceIndex = rootIndex
				if projected.semantic then projected.semantic.index = rootIndex end
			end
			if entry and entry.block and entry.block[1] and entry.block[1].semantic then
				entry.block[1].semantic.index = rootIndex
			end
			return projected
		end,
		containsKey = function(key) return owner.semanticById[key] ~= nil end,
	}
end

function TableInstance:_publishKeyed(root, preserveOffset)
	local previousOffset = preserveOffset == true and self.scroll:getScrollOffset() or 0
	self.keyedRoot = root
	self.keyedMode = true
	self.rows, self.projectedRows = {}, {}
	if self.pager then self.pager:setVisible(reservedPagerHeight(self) > 0) end
	local count = SiK.UI.OrderedBlocks.projectedCount(root)
	local chromeHeight = self.blockHeaderHeight + self.blockHeaderGap
		+ self.metrics.headerHeight + reservedPagerHeight(self)
	local contentHeight = chromeHeight + count * self.metrics.rowHeight
	self.root:setContentHeight(contentHeight)
	if self.root.directBlock then self.root.block:setContentHeight(contentHeight) end
	self:_applyAutoHeight()
	if self.emptyPanel then self.emptyPanel:setVisible(count == 0) end
	local result, reason = self.list:setProvider(self:_keyedProvider(root), preserveOffset == true)
	if result and preserveOffset == true then self.scroll:setScrollOffset(previousOffset) end
	return result, reason
end

function TableInstance:_refreshRows(preserveOffset)
	if self.keyedMode then return self:_publishKeyed(self.keyedRoot, preserveOffset) end
	return self:_publishProjected(self:_projectRows(), preserveOffset)
end

function TableInstance:setRows(rows, preserveOffset)
	if self._patchRootsActive then return nil, "patch_in_progress" end
	if self.disposed then return nil, "disposed" end
	self.keyedMode, self.keyedRoot, self.rootEntryByKey = false, nil, {}
	self.rows = type(rows) == "table" and rows or {}
	self:_rebuildSemanticIndex()
	local projected = self:_projectRows()
	if self.keyedComparator then
		local root, entries = nil, {}
		local function less(left, right) return self.keyedComparator(left.row, right.row) end
		for index = 1, #self.rows do
			local row = self.rows[index]
			local key, keyReason = patchKey(self, row, index)
			if key == nil then return nil, keyReason end
			if entries[key] ~= nil then return nil, "duplicate_current_key:" .. tostring(key) end
			local entry = { key = key, row = row, block = self.projectedByParentKey[key] or {} }
			local ok, nextRoot = pcall(SiK.UI.OrderedBlocks.insert, root, entry, less)
			if not ok then return nil, nextRoot end
			if SiK.UI.OrderedBlocks.count(nextRoot) ~= SiK.UI.OrderedBlocks.count(root) + 1 then
				return nil, "keyed_comparator_collision:" .. tostring(key)
			end
			root, entries[key] = nextRoot, entry
		end
		self.rootEntryByKey = entries
		local accepted, reason = self:_publishKeyed(root, preserveOffset ~= false)
		if accepted ~= false and accepted ~= nil then self._rowImageToken = {} end
		return accepted, reason
	end
	-- A data refresh is not a navigation request.  Keep the user's semantic
	-- position unless the caller explicitly starts a new result set.
	local accepted, reason = self:_publishProjected(projected, preserveOffset ~= false)
	if accepted ~= false and accepted ~= nil then
		self._rowImageToken = {}
	end
	return accepted, reason
end

patchKey = function(instance, row, index)
	local ok, key = pcall(instance.keyOf, row, index)
	if not ok then return nil, key end
	if (type(key) ~= "string" and type(key) ~= "number") or tostring(key) == "" then
		return nil, "invalid_key"
	end
	if type(key) == "number" and key ~= key then return nil, "invalid_key" end
	return key
end

local function copyMap(source)
	local result = {}
	for key, value in pairs(source or {}) do result[key] = value end
	return result
end

local function validateDenseArray(value, label)
	if type(value) ~= "table" then return nil, "invalid_" .. label end
	local length, count = #value, 0
	for key in pairs(value) do
		if type(key) ~= "number" or key ~= key or key ~= math.floor(key)
			or key < 1 or key > length then
			return nil, "invalid_" .. label .. "_index"
		end
		count = count + 1
	end
	if count ~= length then return nil, "sparse_" .. label end
	return true
end

local function restorePatchImage(self, old, indexChanges)
	self.rows, self.semanticById, self.parentByKey = old.rows, old.semanticById, old.parentByKey
	self.projectedRows, self.projectedByParentKey = old.projectedRows, old.projectedByParentKey
	self.firstPageParentKey, self.childPageStates = old.firstPageParentKey, old.childPageStates
	self.childPages, self.expanded, self.activePageParentKey, self.pageState, self.page = old.childPages,
		old.expanded, old.activePageParentKey, old.pageState, old.page
	self.semanticSelection, self.semanticSelections = old.semanticSelection, old.semanticSelections
	for index = 1, #(indexChanges or {}) do
		local change = indexChanges[index]
		if change.parent then change.parent.index = change.index
		else change.projected.sourceIndex = change.index end
	end
	self.list.data = old.listData
	local ok, accepted, reason = pcall(self._publishProjected, self, old.projectedRows, true)
	self.list.data = old.listData
	self.scroll:setScrollOffset(old.offset)
	if not ok then return nil, accepted end
	if accepted == false or accepted == nil then return nil, reason or "undo_rejected" end
	return true
end

local function prepareRowPatch(self, spec)
	if self.disposed then return nil, "disposed" end
	if type(spec) ~= "table" then return nil, "invalid_patch" end
	local upserts = spec.upserts or {}
	local removeKeys = spec.removeKeys or {}
	local order = spec.order
	if type(upserts) ~= "table" or type(removeKeys) ~= "table"
		or (order ~= nil and type(order) ~= "table") then return nil, "invalid_patch" end
	local dense, denseReason = validateDenseArray(upserts, "upserts")
	if not dense then return nil, denseReason end
	dense, denseReason = validateDenseArray(removeKeys, "remove_keys")
	if not dense then return nil, denseReason end
	if order ~= nil then
		dense, denseReason = validateDenseArray(order, "order")
		if not dense then return nil, denseReason end
	end

	local currentByKey, currentToken, seen, semanticSeen = {}, {}, {}, {}
	for index = 1, #self.rows do
		local key, reason = patchKey(self, self.rows[index], index)
		if key == nil then return nil, reason end
		local token = type(key) .. ":" .. tostring(key)
		local semanticToken = tostring(key)
		if seen[token] or semanticSeen[semanticToken] then return nil, "duplicate_current_key:" .. tostring(key) end
		seen[token], currentByKey[key], currentToken[token] = true, self.rows[index], key
		semanticSeen[semanticToken] = true
	end
	local removed, changed, replacements = {}, {}, {}
	for index = 1, #removeKeys do
		local key = removeKeys[index]
		if (type(key) ~= "string" and type(key) ~= "number") or tostring(key) == "" then
			return nil, "invalid_remove_key"
		end
		if type(key) == "number" and key ~= key then return nil, "invalid_remove_key" end
		local token = type(key) .. ":" .. tostring(key)
		if removed[token] then return nil, "duplicate_remove_key:" .. tostring(key) end
		if not currentToken[token] then return nil, "unknown_remove_key:" .. tostring(key) end
		removed[token], changed[token] = true, true
	end
	for index = 1, #upserts do
		local row = upserts[index]
		if type(row) ~= "table" then return nil, "invalid_upsert" end
		local key, reason = patchKey(self, row, index)
		if key == nil then return nil, reason end
		local token = type(key) .. ":" .. tostring(key)
		if replacements[token] or removed[token] then return nil, "duplicate_patch_key:" .. tostring(key) end
		replacements[token], changed[token] = { key = key, row = row }, true
	end

	local finalByToken = {}
	for token, key in pairs(currentToken) do
		if not removed[token] then finalByToken[token] = { key = key, row = replacements[token] and replacements[token].row or currentByKey[key] } end
	end
	for token, entry in pairs(replacements) do finalByToken[token] = entry end
	local finalSemanticKeys = {}
	for _, entry in pairs(finalByToken) do
		local semanticToken = tostring(entry.key)
		if finalSemanticKeys[semanticToken] then return nil, "duplicate_semantic_key:" .. semanticToken end
		finalSemanticKeys[semanticToken] = true
	end
	local nextRows, finalTokens = {}, {}
	if order ~= nil then
		for index = 1, #order do
			local key = order[index]
			if type(key) ~= "string" and type(key) ~= "number" then return nil, "invalid_order_key" end
			if type(key) == "number" and key ~= key then return nil, "invalid_order_key" end
			local token = type(key) .. ":" .. tostring(key)
			if finalTokens[token] then return nil, "duplicate_order_key:" .. tostring(key) end
			local entry = finalByToken[token]
			if not entry then return nil, "unknown_order_key:" .. tostring(key) end
			finalTokens[token], nextRows[#nextRows + 1] = true, entry.row
		end
		for token in pairs(finalByToken) do
			if not finalTokens[token] then return nil, "incomplete_order" end
		end
	else
		for index = 1, #self.rows do
			local key = patchKey(self, self.rows[index], index)
			local token = type(key) .. ":" .. tostring(key)
			if not removed[token] then
				local entry = replacements[token]
				nextRows[#nextRows + 1] = entry and entry.row or self.rows[index]
				finalTokens[token] = true
			end
		end
		for index = 1, #upserts do
			local key = patchKey(self, upserts[index], index)
			local token = type(key) .. ":" .. tostring(key)
			if not currentToken[token] then nextRows[#nextRows + 1], finalTokens[token] = upserts[index], true end
		end
	end
	return { nextRows=nextRows, finalByToken=finalByToken, currentToken=currentToken,
		changed=changed, removed=removed }
end


--- Applies a validated keyed delta without rebuilding semantics or projection
--- for unchanged roots. `order`, when present, is the complete final key order.
function TableInstance:patchRows(spec)
	if self.disposed then return nil, "disposed" end
	if self.keyedMode then return nil, "keyed_patch_required" end
	local plan, planReason = prepareRowPatch(self, spec)
	if not plan then return nil, planReason end
	local nextRows, finalByToken, currentToken = plan.nextRows, plan.finalByToken, plan.currentToken
	local changed, removed = plan.changed, plan.removed
	local old = { rows=self.rows, semanticById=self.semanticById, parentByKey=self.parentByKey,
		projectedRows=self.projectedRows, projectedByParentKey=self.projectedByParentKey,
		firstPageParentKey=self.firstPageParentKey, childPageStates=self.childPageStates,
		activePageParentKey=self.activePageParentKey, pageState=self.pageState, page=self.page,
		childPages=self.childPages, expanded=self.expanded, semanticSelection=self.semanticSelection,
		semanticSelections=self.semanticSelections, offset=self.scroll:getScrollOffset(), listData=self.list.data,
		imageToken=self._rowImageToken }
	local semantics, parents = copyMap(self.semanticById), copyMap(self.parentByKey)
	for token in pairs(changed) do
		local oldKey = currentToken[token]
		if oldKey ~= nil then
			parents[oldKey] = nil
			local oldParent = self.parentByKey[oldKey]
			semantics[semanticId("parent", oldKey)] = nil
			for childIndex = 1, #(oldParent and oldParent.children or {}) do
				local child = oldParent.children[childIndex]
				local childKey = self.expansion and self.expansion.keyOf
					and self.expansion.keyOf(child, childIndex, oldParent.item)
					or (tostring(oldKey) .. ":" .. tostring(childIndex))
				semantics[semanticId("child", childKey, oldKey)] = nil
			end
		end
	end
	local firstExpandable = nil
	for index = 1, #nextRows do
		local row = nextRows[index]
		local key, reason = patchKey(self, row, index)
		if key == nil then return nil, reason end
		local token = type(key) .. ":" .. tostring(key)
		if changed[token] then
			local id = semanticId("parent", key)
			local parent = { id=id, kind="parent", key=key, item=row, index=index }
			local ok, children, hasChildren = pcall(self._children, self, row, index)
			if not ok then return nil, children end
			parent.children, parent.hasChildren = children, hasChildren
			semantics[id], parents[key] = parent, parent
			if hasChildren and not firstExpandable then firstExpandable = key end
			local childKeys = {}
			for childIndex = 1, #(children or {}) do
				local child = children[childIndex]
				local childKey = self.expansion.keyOf and self.expansion.keyOf(child, childIndex, row)
					or (tostring(key) .. ":" .. tostring(childIndex))
				if (type(childKey) ~= "string" and type(childKey) ~= "number") or tostring(childKey) == ""
					or type(childKey) == "number" and childKey ~= childKey then return nil, "invalid_child_key" end
				local childToken = tostring(childKey)
				if childKeys[childToken] then return nil, "duplicate_child_key:" .. childToken end
				childKeys[childToken] = true
				local childId = semanticId("child", childKey, key)
				semantics[childId] = { id=childId, kind="child", key=childKey,
					parentKey=key, item=child, index=childIndex, parentItem=row }
			end
		else
			local parent = parents[key]
			if not parent then return nil, "missing_semantic:" .. tostring(key) end
			if parent.hasChildren and not firstExpandable then firstExpandable = key end
		end
	end

	local blocks = copyMap(self.projectedByParentKey)
	local stagedChildStates = copyMap(self.childPageStates)
	local stagedChildPages = copyMap(self.childPages)
	local stagedExpanded = copyMap(self.expanded)
	for token in pairs(removed) do
		local key = currentToken[token]
		stagedChildStates[key], stagedChildPages[key] = nil, nil
		stagedExpanded[key] = nil
	end
	self.childPageStates, self.childPages, self.expanded = stagedChildStates, stagedChildPages, stagedExpanded
	self.activePageParentKey, self.pageState, self.page = old.activePageParentKey, old.pageState, old.page
	if self.activePageParentKey ~= nil and not parents[self.activePageParentKey] then
		self.activePageParentKey = nil
	end
	for token in pairs(changed) do
		local key = finalByToken[token] and finalByToken[token].key or currentToken[token]
		blocks[key] = nil
		if finalByToken[token] then
			local block = {}
			local ok, cause = true, nil
			if self.expansion then
				ok, cause = pcall(self._projectParent, self, parents[key], block, semantics)
			else
				local parent = parents[key]
				block[1] = { data=parent.item, depth=0, key=key, visualKey=parent.id,
					semantic=parent, sourceIndex=parent.index, hasChildren=false }
			end
			if not ok then self.childPageStates=old.childPageStates; self.childPages=old.childPages; self.expanded=old.expanded; self.activePageParentKey=old.activePageParentKey; self.pageState=old.pageState; self.page=old.page; return nil, cause end
			blocks[key] = block
		end
	end
	local stagedActive = self.activePageParentKey
	local stagedPageState = stagedActive and stagedChildStates[stagedActive]
		or pageState(0, 1, self.pagination and self.pagination.pageSize or 15)
	local stagedPage = stagedPageState.page
	self.childPageStates, self.childPages, self.expanded, self.activePageParentKey, self.pageState, self.page = old.childPageStates, old.childPages, old.expanded, old.activePageParentKey, old.pageState, old.page
	local projected, indexChanges = {}, {}
	for index = 1, #nextRows do
		local key = patchKey(self, nextRows[index], index)
		local parent = parents[key]
		indexChanges[#indexChanges + 1] = { parent=parent, index=parent.index }
		parent.index = index
		local block = blocks[key] or {}
		for blockIndex = 1, #block do
			if block[blockIndex].depth == 0 then
				indexChanges[#indexChanges + 1] = { projected=block[blockIndex], index=block[blockIndex].sourceIndex }
			end
			block[blockIndex].sourceIndex = block[blockIndex].depth == 0 and index or block[blockIndex].sourceIndex
			projected[#projected + 1] = block[blockIndex]
		end
	end
	if not self.expansion and self.pagination then
		local state = pageState(#projected, self.page, self.pagination.pageSize)
		local paged = {}
		for index = state.first, state.last do paged[#paged + 1] = projected[index] end
		projected, stagedPageState, stagedPage = paged, state, state.page
	end

	self.rows, self.semanticById, self.parentByKey = nextRows, semantics, parents
	self.projectedByParentKey, self.firstPageParentKey = blocks, firstExpandable
	self.childPageStates, self.childPages, self.expanded, self.activePageParentKey = stagedChildStates, stagedChildPages, stagedExpanded, stagedActive
	self.pageState, self.page = stagedPageState, stagedPage
	local selectionId = old.semanticSelection and old.semanticSelection.id
	self.semanticSelection = selectionId and semantics[selectionId] or nil
	local liveSelections = {}
	for id in pairs(self.semanticSelections) do if semantics[id] then liveSelections[id] = true end end
	self.semanticSelections = liveSelections
	local ok, accepted, reason = pcall(self._publishProjected, self, projected, true)
	if ok and accepted ~= false and accepted ~= nil then
		local imageToken = {}
		self._rowImageToken = imageToken
		local used = false
		local function undo()
			if used or self.disposed or self._rowImageToken ~= imageToken then
				return false, "image_superseded"
			end
			used = true
			local restored, restoreReason = restorePatchImage(self, old, indexChanges)
			if restored then self._rowImageToken = old.imageToken end
			return restored, restoreReason
		end
		local function isCurrent() return not self.disposed and self._rowImageToken == imageToken end
		return true, nil, undo, isCurrent
	end
	restorePatchImage(self, old, indexChanges)
	if not ok then return nil, accepted end
	return nil, reason or "patch_rejected"
end

local function keyedChildKey(self, child, childIndex, parent, parentKey)
	if self.expansion and self.expansion.keyOf then
		return self.expansion.keyOf(child, childIndex, parent)
	end
	return tostring(parentKey) .. ":" .. tostring(childIndex)
end

local function prepareKeyedParent(self, row, key, rootIndex)
	local parentId = semanticId("parent", key)
	local parent = { id = parentId, kind = "parent", key = key, item = row, index = rootIndex }
	local ok, children, hasChildren = pcall(self._children, self, row, rootIndex)
	if not ok then return nil, children end
	parent.children, parent.hasChildren = children, hasChildren
	local semantics = { parent }
	local ids = { [parentId] = true }
	for childIndex = 1, #(children or {}) do
		local child = children[childIndex]
		local childOk, childKey = pcall(keyedChildKey, self, child, childIndex, row, key)
		if not childOk then return nil, childKey end
		if (type(childKey) ~= "string" and type(childKey) ~= "number") or tostring(childKey) == ""
			or type(childKey) == "number" and childKey ~= childKey then return nil, "invalid_child_key" end
		local childId = semanticId("child", childKey, key)
		if ids[childId] then return nil, "duplicate_child_key:" .. tostring(childKey) end
		ids[childId] = true
		semantics[#semantics + 1] = { id = childId, kind = "child", key = childKey,
			parentKey = key, item = child, index = childIndex, parentItem = row }
	end
	return { parent = parent, semantics = semantics, ids = ids }
end

local function restoreKeyedImage(self, old, journal)
	restoreJournal(journal)
	self.firstPageParentKey, self.activePageParentKey = old.firstPageParentKey, old.activePageParentKey
	self.pageState, self.page, self.semanticSelection = old.pageState, old.page, old.semanticSelection
	self.keyedRoot = old.root
	local ok, accepted, reason = pcall(self._publishKeyed, self, old.root, true)
	self.scroll:setScrollOffset(old.offset)
	if not ok then return nil, accepted end
	if accepted == false or accepted == nil then return nil, reason or "undo_rejected" end
	return true
end

--- Applies a root-keyed persistent delta. This path never materializes or sorts
--- the complete root order; only affected semantic and projected blocks mutate.
function TableInstance:_patchRoots(spec)
	if self.disposed then return nil, "disposed" end
	if not self.keyedMode or not self.keyedComparator then return nil, "keyed_mode_disabled" end
	if type(spec) ~= "table" then return nil, "invalid_patch" end
	local upserts, removeKeys = spec.upserts or {}, spec.removeKeys or {}
	if spec.order ~= nil or type(upserts) ~= "table" or type(removeKeys) ~= "table" then
		return nil, "invalid_root_patch"
	end
	local dense, reason = validateDenseArray(upserts, "upserts")
	if not dense then return nil, reason end
	dense, reason = validateDenseArray(removeKeys, "remove_keys")
	if not dense then return nil, reason end

	local removals, removalTokens, upsertPlans, patchTokens, semanticPatchTokens = {}, {}, {}, {}, {}
	for index = 1, #removeKeys do
		local key = removeKeys[index]
		if (type(key) ~= "string" and type(key) ~= "number") or tostring(key) == ""
			or type(key) == "number" and key ~= key then return nil, "invalid_remove_key" end
		local token = type(key) .. ":" .. tostring(key)
		if patchTokens[token] then return nil, "duplicate_remove_key:" .. tostring(key) end
		local oldEntry = self.rootEntryByKey[key]
		if not oldEntry then return nil, "unknown_remove_key:" .. tostring(key) end
		patchTokens[token], removalTokens[token] = true, true
		removals[#removals + 1] = { key = key, entry = oldEntry }
	end
	for index = 1, #upserts do
		local row = upserts[index]
		if type(row) ~= "table" then return nil, "invalid_upsert" end
		local key, keyReason = patchKey(self, row, index)
		if key == nil then return nil, keyReason end
		local token = type(key) .. ":" .. tostring(key)
		if patchTokens[token] then return nil, "duplicate_patch_key:" .. tostring(key) end
		local semanticToken = tostring(key)
		if semanticPatchTokens[semanticToken] then
			return nil, "duplicate_semantic_key:" .. semanticToken
		end
		local existingSemantic = self.semanticById[semanticId("parent", key)]
		if existingSemantic and existingSemantic.key ~= key then
			local existingToken = type(existingSemantic.key) .. ":" .. tostring(existingSemantic.key)
			if not removalTokens[existingToken] then return nil, "duplicate_semantic_key:" .. semanticToken end
		end
		patchTokens[token] = true
		semanticPatchTokens[semanticToken] = true
		upsertPlans[#upsertPlans + 1] = { key = key, row = row,
			oldEntry = self.rootEntryByKey[key] }
	end

	local old = { root = self.keyedRoot, offset = self.scroll:getScrollOffset(),
		firstPageParentKey = self.firstPageParentKey, activePageParentKey = self.activePageParentKey,
		pageState = self.pageState, page = self.page, semanticSelection = self.semanticSelection,
		imageToken = self._rowImageToken }
	local nextRoot = old.root
	local function less(left, right) return self.keyedComparator(left.row, right.row) end
	for index = 1, #removals do
		local ok, value = pcall(SiK.UI.OrderedBlocks.remove, nextRoot, removals[index].entry, less)
		if not ok then return nil, value end
		nextRoot = value
	end
	for index = 1, #upsertPlans do
		local plan = upsertPlans[index]
		if plan.oldEntry then
			local ok, value = pcall(SiK.UI.OrderedBlocks.remove, nextRoot, plan.oldEntry, less)
			if not ok then return nil, value end
			nextRoot = value
		end
		plan.entry = { key = plan.key, row = plan.row, block = {} }
		local before = SiK.UI.OrderedBlocks.count(nextRoot)
		local ok, value = pcall(SiK.UI.OrderedBlocks.insert, nextRoot, plan.entry, less)
		if not ok then return nil, value end
		if SiK.UI.OrderedBlocks.count(value) ~= before + 1 then
			return nil, "keyed_comparator_collision:" .. tostring(plan.key)
		end
		nextRoot = value
	end
	for index = 1, #upsertPlans do
		local plan = upsertPlans[index]
		local rankOk, rootIndex = pcall(SiK.UI.OrderedBlocks.rank, nextRoot, plan.entry, less)
		if not rankOk then return nil, rootIndex end
		local prepared, prepareReason = prepareKeyedParent(self, plan.row, plan.key, rootIndex)
		if not prepared then return nil, prepareReason end
		plan.prepared = prepared
	end

	local journal = { seen = {} }
	local touchedIds = {}
	local function touchOld(entry)
		if not entry then return true end
		local oldParent = self.parentByKey[entry.key]
		if oldParent then
			touchedIds[oldParent.id] = true
			journalSet(journal, self.semanticById, oldParent.id, nil)
			for childIndex = 1, #(oldParent.children or {}) do
				local child = oldParent.children[childIndex]
				local childOk, childKey = pcall(keyedChildKey, self, child, childIndex,
					oldParent.item, entry.key)
				if not childOk then return nil, childKey end
				local childId = semanticId("child", childKey, entry.key)
				touchedIds[childId] = true
				journalSet(journal, self.semanticById, childId, nil)
			end
		end
		journalSet(journal, self.parentByKey, entry.key, nil)
		journalSet(journal, self.projectedByParentKey, entry.key, nil)
		journalSet(journal, self.rootEntryByKey, entry.key, nil)
		return true
	end
	for index = 1, #removals do
		local touched, cause = touchOld(removals[index].entry)
		if not touched then restoreJournal(journal); return nil, cause end
	end
	for index = 1, #upsertPlans do
		local touched, cause = touchOld(upsertPlans[index].oldEntry)
		if not touched then restoreJournal(journal); return nil, cause end
	end
	for index = 1, #removals do
		local key = removals[index].key
		journalSet(journal, self.childPageStates, key, nil)
		journalSet(journal, self.childPages, key, nil)
		journalSet(journal, self.expanded, key, nil)
		if self.activePageParentKey == key then self.activePageParentKey = nil end
		if self.firstPageParentKey == key then self.firstPageParentKey = nil end
	end
	for index = 1, #upsertPlans do
		local plan, prepared = upsertPlans[index], upsertPlans[index].prepared
		journalSet(journal, self.parentByKey, plan.key, prepared.parent)
		for semanticIndex = 1, #prepared.semantics do
			local semantic = prepared.semantics[semanticIndex]
			touchedIds[semantic.id] = true
			journalSet(journal, self.semanticById, semantic.id, semantic)
		end
		if prepared.parent.hasChildren and self.firstPageParentKey == nil then
			self.firstPageParentKey = plan.key
		end
	end

	for index = 1, #upsertPlans do
		local plan = upsertPlans[index]
		journalSet(journal, self.childPageStates, plan.key, nil)
		if not plan.prepared.parent.hasChildren then
			journalSet(journal, self.childPages, plan.key, nil)
			if self.activePageParentKey == plan.key then self.activePageParentKey = nil end
			if self.firstPageParentKey == plan.key then self.firstPageParentKey = nil end
		end
		local block = {}
		local ok, cause = true, nil
		if self.expansion then
			ok, cause = pcall(self._projectParent, self, plan.prepared.parent, block, self.semanticById)
		else
			local parent = plan.prepared.parent
			block[1] = { data = parent.item, depth = 0, key = plan.key, visualKey = parent.id,
				semantic = parent, sourceIndex = parent.index, hasChildren = false }
		end
		if not ok then
			restoreJournal(journal)
			self.firstPageParentKey, self.activePageParentKey = old.firstPageParentKey, old.activePageParentKey
			self.pageState, self.page, self.semanticSelection = old.pageState, old.page, old.semanticSelection
			return nil, cause
		end
		plan.entry = { key = plan.key, row = plan.row, block = block }
		local insertOk, value = pcall(SiK.UI.OrderedBlocks.insert, nextRoot, plan.entry, less)
		if not insertOk then
			restoreJournal(journal)
			self.firstPageParentKey, self.activePageParentKey = old.firstPageParentKey, old.activePageParentKey
			self.pageState, self.page, self.semanticSelection = old.pageState, old.page, old.semanticSelection
			return nil, value
		end
		nextRoot = value
		journalSet(journal, self.projectedByParentKey, plan.key, block)
		journalSet(journal, self.rootEntryByKey, plan.key, plan.entry)
	end
	for id in pairs(touchedIds) do
		if self.semanticById[id] == nil then journalSet(journal, self.semanticSelections, id, nil)
		else journalSet(journal, self.semanticSelections, id, self.semanticSelections[id]) end
	end
	local selectionId = old.semanticSelection and old.semanticSelection.id
	self.semanticSelection = selectionId and self.semanticById[selectionId] or nil
	local active = self.activePageParentKey
	self.pageState = active and self.childPageStates[active]
		or pageState(0, 1, self.pagination and self.pagination.pageSize or 15)
	self.page = self.pageState.page

	local imageToken = {}
	self._rowImageToken = imageToken
	local ok, accepted, publishReason = pcall(self._publishKeyed, self, nextRoot, true)
	if self._rowImageToken ~= imageToken then
		pcall(self._publishKeyed, self, self.keyedRoot, true)
		return nil, "image_superseded"
	end
	if ok and accepted ~= false and accepted ~= nil then
		local used = false
		local function undo()
			if used or self.disposed or self._rowImageToken ~= imageToken then
				return false, "image_superseded"
			end
			used = true
			local restoreToken = {}
			self._rowImageToken = restoreToken
			local restored, restoreReason = restoreKeyedImage(self, old, journal)
			if self._rowImageToken ~= restoreToken then
				pcall(self._publishKeyed, self, self.keyedRoot, true)
				return false, "image_superseded"
			end
			if restored then self._rowImageToken = old.imageToken
			else self._rowImageToken = imageToken end
			return restored, restoreReason
		end
		local function isCurrent() return not self.disposed and self._rowImageToken == imageToken end
		return true, nil, undo, isCurrent
	end
	local restoreToken = {}
	self._rowImageToken = restoreToken
	local restored, restoreReason = restoreKeyedImage(self, old, journal)
	if self._rowImageToken ~= restoreToken then
		pcall(self._publishKeyed, self, self.keyedRoot, true)
		return nil, "image_superseded"
	end
	self._rowImageToken = old.imageToken
	if not restored then return nil, restoreReason end
	if not ok then return nil, accepted end
	return nil, publishReason or "patch_rejected"
end

-- Product callbacks can run while the visible provider binds its rows. They
-- cannot start a second write over an uncommitted semantic-map journal.
function TableInstance:patchRoots(spec)
	if self._patchRootsActive then return nil, "patch_in_progress" end
	self._patchRootsActive = true
	local called, accepted, reason, undo, isCurrent = pcall(self._patchRoots, self, spec)
	self._patchRootsActive = nil
	if not called then return nil, accepted end
	return accepted, reason, undo, isCurrent
end

function TableInstance:setColumns(columns)
	if self.disposed then return nil, "disposed" end
	local normalized, reason = normalizedColumns(columns)
	if not normalized then return nil, "invalid_columns:" .. tostring(reason) end
	self.columns = normalized
	self._geometrySignature = nil
	self:_syncGeometry()
	return self
end

function TableInstance:setBounds(x, y, w, h)
	if self.disposed then return nil, "disposed" end
	self.root:setBounds(x, y, w, h)
	return self
end

function TableInstance:getBounds()
	return { x = self.root.x, y = self.root.y, w = self.root.w, h = self.root.h }
end

function TableInstance:getHeight() return self.root.h end

-- Snapshot of the current page/expansion order, independent of virtual row
-- recycling. Data references belong to the consumer; synthetic pagers do not.
function TableInstance:getVisibleDataRows()
	local rows = {}
	if self.disposed then return rows end
	local count = self:_visibleRowCount()
	for i = 1, count do
		local projected = self.keyedMode and SiK.UI.OrderedBlocks.projectedAt(self.keyedRoot, i)
			or self.projectedRows[i]
		if projected.kind ~= "pager" and projected.data ~= nil then rows[#rows + 1] = projected.data end
	end
	return rows
end

function TableInstance:getRootRows()
	local rows = {}
	if self.disposed then return rows end
	if not self.keyedMode then
		for index = 1, #self.rows do rows[index] = self.rows[index] end
		return rows
	end
	for index = 1, SiK.UI.OrderedBlocks.count(self.keyedRoot) do
		local entry = SiK.UI.OrderedBlocks.at(self.keyedRoot, index)
		rows[index] = entry.row
	end
	return rows
end

-- Declarative staging captures the persistent root in O(1). Only exceptional
-- rollback materializes it again; ordinary geometry and deltas do not.
function TableInstance:captureRowImage()
	return {owner=self,keyed=self.keyedMode,root=self.keyedRoot,rows=self.rows}
end
function TableInstance:restoreRowImage(image)
	if type(image)~="table" or image.owner~=self then return nil,"invalid_row_image" end
	if self._patchRootsActive then return nil,"patch_in_progress" end
	local rows=image.rows
	if image.keyed then
		rows={}
		for i=1,SiK.UI.OrderedBlocks.count(image.root) do rows[i]=SiK.UI.OrderedBlocks.at(image.root,i).row end
	end
	return self:setRows(rows,false)
end
function TableInstance:getRootCount()
	return self.keyedMode and SiK.UI.OrderedBlocks.count(self.keyedRoot) or #self.rows
end

function TableInstance:layout(spec)
	if self.disposed then return nil, "disposed" end
	if type(spec) ~= "table" then return nil, "invalid_layout" end
	local bounds = self:getBounds()
	self:setBounds(spec.x or bounds.x, spec.y or bounds.y,
		spec.w or spec.width or bounds.w, spec.h or spec.height or bounds.h)
	if spec.rows ~= nil then
		local result, reason = self:setRows(spec.rows, spec.preserveOffset ~= false)
		if not result then return nil, reason end
	elseif self.autoHeight and spec.fitRows ~= false then
		self:_applyAutoHeight()
	end
	return self
end

function TableInstance:reflow(x, y, w, h)
	if type(x) == "table" then return self:layout(x) end
	return self:setBounds(x, y, w, h)
end
function TableInstance:getSelectedKey()
	return self.semanticSelection and self.semanticSelection.key or nil
end

function TableInstance:getSemanticSelection()
	return self.semanticSelection
end

function TableInstance:getSemanticSelections()
	local out = {}
	for id in pairs(self.semanticSelections) do
		local selection = self.semanticById[id]
		if selection then out[#out + 1] = selection end
	end
	return out
end

function TableInstance:isSelected(key, parentKey)
	local kind = parentKey ~= nil and "child" or "parent"
	return self.semanticSelections[semanticId(kind, key, parentKey)] == true
end

function TableInstance:setSelectedKeys(keys)
	if self.disposed then return nil, "disposed" end
	local selected = {}
	for index = 1, #(keys or {}) do
		local value = keys[index]
		local selection = type(value) == "table" and value or self.parentByKey[value]
		if not selection then
			for _, candidate in pairs(self.semanticById) do
				if candidate.key == value then selection = candidate break end
			end
		end
		if selection and self.semanticById[selection.id] then selected[selection.id] = true end
	end
	self.semanticSelections = selected
	local first = self:getSemanticSelections()[1]
	self.semanticSelection = first
	self.list.selectedKey = first and first.id or nil
	self.list:refresh()
	return self:getSemanticSelections()
end

function TableInstance:setEmptyText(text)
	if self.disposed then return nil, "disposed" end
	self.options.emptyText = tostring(text or "")
	if self.emptyPanel then self.emptyPanel._sikEmptyText = self.options.emptyText end
	return self
end

function TableInstance:selectParent(key)
	if self.disposed then return nil, "disposed" end
	local selection = self.parentByKey[key]
	if not selection then return nil, "unknown_parent" end
	self.semanticSelection = selection
	if self.selectionMode ~= "multiple" then self.semanticSelections = {} end
	self.semanticSelections[selection.id] = true
	self.list:setSelectedKey(selection.id)
	return selection
end

function TableInstance:selectChild(parentKey, childKey)
	if self.disposed then return nil, "disposed" end
	local selection = self.semanticById[semanticId("child", childKey, parentKey)]
	if not selection then return nil, "unknown_child" end
	self.semanticSelection = selection
	if self.selectionMode ~= "multiple" then self.semanticSelections = {} end
	self.semanticSelections[selection.id] = true
	self.list:setSelectedKey(selection.id)
	return selection
end

function TableInstance:setSelectedKey(key)
	local parent = self.parentByKey[key]
	if parent then return self:selectParent(key) end
	local found = nil
	for _, selection in pairs(self.semanticById) do
		if selection.kind == "child" and selection.key == key then
			if found then return nil, "ambiguous_child_key" end
			found = selection
		end
	end
	if not found then return nil, "unknown_selection" end
	return self:selectChild(found.parentKey, found.key)
end

function TableInstance:getFocusedKey()
	local focused = self.semanticById[self.list:getFocusedKey()]
	return focused and focused.key or nil
end

function TableInstance:setFocusedKey(key)
	local target = self.parentByKey[key]
	if not target then
		for _, selection in pairs(self.semanticById) do
			if selection.kind == "child" and selection.key == key then
				if target then return nil, "ambiguous_child_key" end
				target = selection
			end
		end
	end
	if not target then return nil, "unknown_focus" end
	return self.list:setFocusedKey(target.id)
end
function TableInstance:getScrollOffset() return self.list:getScrollOffset() end
function TableInstance:setScrollOffset(offset) return self.list:setScrollOffset(offset) end
function TableInstance:getPageState(parentKey)
	if parentKey ~= nil and self.expansion then return self.childPageStates[parentKey] end
	return self.pageState
end

function TableInstance:setPage(page)
	if self._patchRootsActive then return nil, "patch_in_progress" end
	if not self.pagination then return nil, "pagination_disabled" end
	if self.expansion then
		local parentKey = self.activePageParentKey
		if parentKey == nil then return nil, "no_pageable_parent" end
		return self:setChildPage(parentKey, page)
	end
	self.page = math.max(1, math.floor(numberOr(page, 1)))
	return self:_refreshRows(false)
end

function TableInstance:setChildPage(parentKey, page)
	if self._patchRootsActive then return nil, "patch_in_progress" end
	if not self.pagination or not self.expansion then return nil, "child_pagination_disabled" end
	if not self.parentByKey[parentKey] or not self.parentByKey[parentKey].children then
		return nil, "unknown_parent"
	end
	local current = self.childPageStates[parentKey]
	if current and current.disabled then return nil, current.disabledReason or "page_change_disabled" end
	self.activePageParentKey = parentKey
	self.childPages[parentKey] = math.max(1, math.floor(numberOr(page, 1)))
	if self.pagination.external then
		return self.pagination.onPageChange({ playerNum = self.playerNum,
			component = self, parentKey = parentKey,
			parent = self.parentByKey[parentKey].item,
			page = self.childPages[parentKey] })
	end
	if self.keyedMode then
		local parent = self.parentByKey[parentKey]
		local accepted, reason = self:patchRoots({ upserts = { parent.item } })
		return accepted, reason
	end
	return self:_refreshRows(true)
end

function TableInstance:getChildren(parentKey)
	local parent = self.parentByKey[parentKey]
	if not parent or not parent.children then return {} end
	local snapshot = {}
	for index = 1, #parent.children do snapshot[index] = parent.children[index] end
	return snapshot
end

function TableInstance:setSort(key, ascending)
	if self._patchRootsActive then return nil, "patch_in_progress" end
	if self.disposed then return nil, "disposed" end
	self.sortKey = key
	self.sortAsc = ascending ~= false
	return self
end

local function sortableValue(column, item, index)
	local value = projection(column, item, index)
	value = type(value) == "table" and (value.sortValue ~= nil and value.sortValue or value.text) or value
	if type(value) == "number" then return 0, value end
	if type(value) == "boolean" then return 1, value and 1 or 0 end
	return 2, string.lower(tostring(value or ""))
end

function TableInstance:_applyLocalSort(column)
	local source = self.keyedMode and self:getRootRows() or self.rows
	local decorated = {}
	for index = 1, #source do decorated[index] = { item = source[index], index = index } end
	table.sort(decorated, function(left, right)
		local leftType, leftValue = sortableValue(column, left.item, left.index)
		local rightType, rightValue = sortableValue(column, right.item, right.index)
		local before = leftType < rightType or (leftType == rightType and leftValue < rightValue)
		local equal = leftType == rightType and leftValue == rightValue
		if equal then return left.index < right.index end
		return self.sortAsc and before or not before
	end)
	local sorted = {}
	for index = 1, #decorated do sorted[index] = decorated[index].item end
	if self.keyedMode then return self:setRows(sorted, true) end
	self.rows = sorted
	self:_rebuildSemanticIndex()
	return self:_refreshRows(true)
end

function TableInstance:previousPage() return self:setPage(self.page - 1) end
function TableInstance:nextPage() return self:setPage(self.page + 1) end

function TableInstance:toggleExpanded(key)
	if self._patchRootsActive then return nil, "patch_in_progress" end
	if not self.expansion then return nil, "expansion_disabled" end
	if not self.parentByKey[key] then return nil, "unknown_parent" end
	-- Do not use `expanded[key] and nil or true`: Lua evaluates that form to
	-- true in both branches.  Expansion must be a real two-state toggle.
	if self.expanded[key] then
		self.expanded[key] = nil
		if self.activePageParentKey == key then self.activePageParentKey = nil end
	else
		self.expanded[key] = true
		self.activePageParentKey = key
	end
	local result, reason
	if self.keyedMode then
		local parent = self.parentByKey[key]
		result, reason = self:patchRoots({ upserts = { parent.item } })
	else
		result, reason = self:_refreshRows(true)
	end
	if result and type(self.options.onExpansionChange) == "function" then
		local parent = self.parentByKey[key]
		self.options.onExpansionChange({ playerNum = self.playerNum,
			component = self, key = key, expanded = self.expanded[key] == true,
			item = parent and parent.item or nil })
	end
	return result, reason
end

function TableInstance:captureState()
	local expanded = {}
	for key, value in pairs(self.expanded) do expanded[key] = value end
	local childPages = {}
	for key, value in pairs(self.childPages) do childPages[key] = value end
	local selection = self.semanticSelection
	return { selection = self:getSelectedKey(), focus = self:getFocusedKey(),
		selectionKind = selection and selection.kind or nil,
		selectionParentKey = selection and selection.parentKey or nil,
		offset = self:getScrollOffset(), page = self.page, expanded = expanded,
		childPages = childPages, activePageParentKey = self.activePageParentKey,
		selections = self:getSemanticSelections() }
end

function TableInstance:restoreState(state)
	if self._patchRootsActive then return nil, "patch_in_progress" end
	if type(state) ~= "table" then return nil, "invalid_state" end
	local keyedRefresh = {}
	local keyedSeen = {}
	if self.keyedMode then
		for key, value in pairs(self.expanded) do
			if type(state.expanded) == "table" and state.expanded[key] ~= value then
				local parent = self.parentByKey[key]
				if parent then keyedSeen[key], keyedRefresh[#keyedRefresh + 1] = true, parent.item end
			end
		end
		for key, value in pairs(state.expanded or {}) do
			if self.expanded[key] ~= value and not keyedSeen[key] then
				local parent = self.parentByKey[key]
				if parent then keyedSeen[key], keyedRefresh[#keyedRefresh + 1] = true, parent.item end
			end
		end
		for key, value in pairs(state.childPages or {}) do
			if self.childPages[key] ~= value and not keyedSeen[key] then
				local parent = self.parentByKey[key]
				if parent then keyedSeen[key], keyedRefresh[#keyedRefresh + 1] = true, parent.item end
			end
		end
	end
	if type(state.expanded) == "table" then self.expanded = state.expanded end
	if type(state.childPages) == "table" then self.childPages = state.childPages end
	self.activePageParentKey = state.activePageParentKey
	self.page = math.max(1, math.floor(numberOr(state.page, self.page)))
	if self.keyedMode and #keyedRefresh > 0 then
		local accepted, reason = self:patchRoots({ upserts = keyedRefresh })
		if not accepted then return nil, reason end
	else
		self:_refreshRows(false)
	end
	if state.selectionKind == "child" then
		self:selectChild(state.selectionParentKey, state.selection)
	elseif state.selection ~= nil then
		self:setSelectedKey(state.selection)
	end
	if type(state.selections) == "table" then self:setSelectedKeys(state.selections) end
	if state.focus ~= nil then self:setFocusedKey(state.focus) end
	self.list:setScrollOffset(state.offset)
	return self
end

function TableInstance:dispose()
	if self.disposed then return false end
	self.disposed = true
	-- Ancestors are stored nearest-first. Restore their materials outside-in so
	-- every nested Block resolves against the parent's final effective surface,
	-- rather than retaining the temporary opaque table descriptor.
	for index = #(self.blocks or {}), 1, -1 do
		local block = self.blocks[index]
		if block and block._tableUnmounted then block:_tableUnmounted() end
	end
	self.blocks = {}
	if self.header and self.header.setCapture then self.header:setCapture(false) end
	if self.rootListener then self.root:unsubscribe(self.rootListener) end
	if self.root and self.root.block and self.blockListener then
		self.root.block:unsubscribe(self.blockListener)
	end
	if self.list then self.list:dispose() end
	if self.scroll then self.scroll:dispose() end
	detach(self.root and self.root.panel, self.header)
	if self.blockHeader and self.blockHeader.dispose then self.blockHeader:dispose() end
	detach(self.root and self.root.panel, self.pager)
	detach(self.root and self.root.panel, self.emptyPanel)
	if self.root then self.root:dispose() end
	self.rows, self.projectedRows, self.projectedByParentKey, self.expanded = {}, {}, {}, {}
	self.semanticById, self.parentByKey, self.childPages, self.childPageStates = {}, {}, {}, {}
	self.keyedRoot, self.rootEntryByKey, self.keyedMode = nil, {}, false
	self.semanticSelections = {}
	self.semanticSelection = nil
	self.list, self.scroll, self.header, self.blockHeader = nil, nil, nil, nil
	self.pager, self.emptyPanel, self.root = nil, nil, nil
	return true
end

local function attachHeaderInteraction(instance)
	local panel = instance.header
	panel.onMouseDown = function(self, x, y)
		self._sikHeaderPress = nil
		if numberOr(x, -1) < 0 or numberOr(x, -1) >= self.width
			or numberOr(y, -1) < 0 or numberOr(y, -1) >= self.height then return false end
		for index = 1, #instance.columnLayout - 1 do
			local left = instance.columnLayout[index]
			if left.spec.resizable ~= false and math.abs(numberOr(x, 0) - left.finish) <= 6 then
				local right = instance.columnLayout[index + 1]
				self._sikResize = { index = index, delta = 0, left = left.width, right = right.width }
				if self.setCapture then self:setCapture(true) end
				return true
			end
		end
		self._sikHeaderPress = Table.columnAtX(instance.columnLayout, numberOr(x, -1))
		-- Arm an ordinary header click without claiming it as a resize gesture.
		-- Vanilla still delivers onMouseUp to the header, where the matching
		-- visible header cell is verified before sorting.
		return false
	end
	panel.onMouseMove = function(self, dx)
		local drag = self._sikResize
		if not drag then return false end
		drag.delta = drag.delta + numberOr(dx, 0)
		local leftSpec, rightSpec = instance.columns[drag.index], instance.columns[drag.index + 1]
		local leftMin, rightMin = columnMinimum(leftSpec, instance.metrics.font), columnMinimum(rightSpec, instance.metrics.font)
		local delta = math.max(leftMin - drag.left, math.min(drag.delta, drag.right - rightMin))
		instance.columnOptions.columnWidths[leftSpec.key] = math.floor(drag.left + delta)
		instance.columnOptions.columnWidths[rightSpec.key] = math.floor(drag.right - delta)
		instance.columnLayout = Table.resolveColumns(self.width, instance.columns, instance.columnOptions)
		instance.list:refresh()
		return true
	end
	local function release(self, x, y)
		if self._sikResize then
			self._sikResize = nil
			if self.setCapture then self:setCapture(false) end
			if instance.onColumnResize then instance.onColumnResize(instance.columnOptions.columnWidths, instance) end
			return true
		end
		local pressed = self._sikHeaderPress
		self._sikHeaderPress = nil
		if not pressed or numberOr(x, -1) < 0 or numberOr(x, -1) >= self.width
			or numberOr(y, -1) < 0 or numberOr(y, -1) >= self.height then return false end
		local column = Table.columnAtX(instance.columnLayout, numberOr(x, -1))
		if column and column.key == pressed.key and column.spec.sortable ~= false then
			local ascending = true
			if column.key == instance.sortKey then ascending = not instance.sortAsc end
			instance:setSort(column.key, ascending)
			if instance.onSort then
				instance.onSort({ playerNum = instance.playerNum, component = instance,
					key = column.key, ascending = ascending })
			else instance:_applyLocalSort(column.spec) end
			return true
		end
		return false
	end
	panel.onMouseUp = release
	panel.onMouseUpOutside = function(self)
		local resized = self._sikResize ~= nil
		self._sikResize, self._sikHeaderPress = nil, nil
		if self.setCapture then self:setCapture(false) end
		return resized
	end
end

--- Canonical professional table composition: one Block owns padding and
--- overflow, while this handle owns BlockHeader, table header, virtual rows,
--- selection, expansion, pagination, resize and disposal.
function Table.create(options)
	options = options or {}
	if type(options.parent) ~= "table" then return nil, "invalid_parent" end
	-- A caller cannot opt into a fake embedded mode.  The physical ancestry is
	-- the contract: without a real declarative Block content host, no table is
	-- created and therefore no orphan panel can be painted.
	local blocks = blockAncestors(options.parent)
	local block = blocks[1] or blockContentOwner(options.parent)
	if options.embedded ~= true or not block then return nil, "table_requires_block" end
	local columns, columnsReason = normalizedColumns(options.columns)
	if not columns then return nil, "invalid_columns:" .. tostring(columnsReason) end
	options.columns = columns
	if options.expansion ~= nil and (type(options.expansion) ~= "table"
		or type(options.expansion.childrenOf) ~= "function") then return nil, "invalid_expansion" end
	if options.keyedComparator ~= nil and type(options.keyedComparator) ~= "function" then
		return nil, "invalid_keyed_comparator"
	end
	if options.pagination ~= nil and (type(options.pagination) ~= "table"
		or numberOr(options.pagination.pageSize, 0) < 1) then return nil, "invalid_pagination" end
	if options.pagination and options.pagination.external == true
		and (type(options.pagination.stateOf) ~= "function"
			or type(options.pagination.onPageChange) ~= "function") then
		return nil, "invalid_external_pagination"
	end
	local metrics, tokens = Table.metrics(options), SiK.UI.Metrics.tokens(options.metrics)
	local paddingX, paddingY = 0, 0
	local blockHeaderSpec, blockHeaderHeight, blockHeaderGap = nil, 0, 0
	local pagerHeight = options.pagination and math.max(1, numberOr(options.pagination.height, tokens.table.pagerHeight)) or 0
	options.block = block
	-- Direct Block ownership is the legacy/convenience mode for a table that is
	-- the Block's sole content. Declarative Builder callers can explicitly turn
	-- it off because their resolved rectangle already accounts for siblings.
	local directBlockRequested = options.directBlock
	options.directBlock = block.panel == options.parent
	if directBlockRequested == false then options.directBlock = false end
	local root, reason = createTableRoot(options)
	if not root then return nil, reason end
	local header = createPanel(root.panel)
	local blockHeader = blockHeaderSpec and SiK.UI.Controls.blockHeader(root.panel, blockHeaderSpec) or nil
	-- Hierarchical pagination is a row belonging to the expanded parent; retain
	-- the legacy footer pager only for a flat table.
	local pager = options.pagination and not options.expansion and createPanel(root.panel) or nil
	local emptyPanel = options.emptyText and createPanel(root.panel) or nil
	local scroll, scrollReason = SiK.UI.Scroll.create({ parent = root.panel,
		viewportRect = root:getContentRect(), trackRect = root:getTrackRect(), wheelStep = options.wheelStep,
		contentHeight = 0, playerNum = options.playerNum })
	if not scroll then detach(root.panel, header)
		if blockHeader and blockHeader.dispose then blockHeader:dispose() end
		detach(root.panel, pager)
		detach(root.panel, emptyPanel)
		root:dispose() return nil, scrollReason end
	-- Empty feedback overlays the viewport only while the data source is empty.
	if emptyPanel and root.panel.removeChild and root.panel.addChild then
		root.panel:removeChild(emptyPanel)
		root.panel:addChild(emptyPanel)
	end
	-- Table owns the viewport below its header and above its pager.  Attaching
	-- this internal Scroll to Block makes Block:_sync() reset it to the whole
	-- content rect whenever contentHeight changes; the first row then paints
	-- over the header and short tables leave an apparent empty framed body.
	-- Block still owns padding/overflow calculation, while _syncGeometry owns
	-- the table-specific viewport and track rectangles.
	local minimumRows = math.max(0, math.floor(numberOr(options.minRows, 1)))
	local maximumRows = tonumber(options.maxRows)
	if maximumRows then maximumRows = math.max(minimumRows, math.floor(maximumRows)) end
	local minimumHeight = math.max(0, numberOr(options.minHeight, 0))
	local maximumHeight = tonumber(options.maxHeight)
	if maximumHeight then maximumHeight = math.max(minimumHeight, maximumHeight) end
	local instance = setmetatable({ root = root, panel = root.panel, block = block,
		scroll = scroll, header = header,
		blockHeader = blockHeader, pager = pager, emptyPanel = emptyPanel,
		columns = options.columns, columnLayout = {},
		columnOptions = { font = metrics.font, rowHeight = metrics.rowHeight,
			headerHeight = metrics.headerHeight, gap = metrics.gap, cellPadding = metrics.cellPadding,
			left = options.left, right = options.right, columnWidths = options.columnWidths or {} },
			metrics = metrics, blockHeaderHeight = blockHeaderHeight, blockHeaderGap = blockHeaderGap, pagerHeight = pagerHeight,
		autoHeight = options.autoHeight == true or options.allRowsVisible == true
			or options.heightMode == "content", minRows = minimumRows,
			allRowsVisible = options.allRowsVisible == true or options.heightMode == "content",
		maxRows = maximumRows, minHeight = minimumHeight, maxHeight = maximumHeight,
		rows = {}, projectedRows = {}, keyOf = type(options.keyOf) == "function"
			and options.keyOf or function(_, index) return index end,
			keyedComparator = options.keyedComparator, keyedMode = false,
			keyedRoot = nil, rootEntryByKey = {},
			expansion = options.expansion, expanded = {},
			semanticById = {}, parentByKey = {}, semanticSelection = nil,
			semanticSelections = {}, selectionMode = options.selectionMode == "multiple" and "multiple" or "single",
			rowAdapter = type(options.row) == "table" and options.row or nil,
		childPages = {}, childPageStates = {}, activePageParentKey = nil,
		expansionHitbox = math.max(1, numberOr(options.expansionHitbox, tokens.table.expansionHitbox)),
		indent = math.max(0, numberOr(options.indent, tokens.table.expansionIndent)),
		pagination = options.pagination and {
			pageSize = math.floor(numberOr(options.pagination.pageSize, 15)),
			external = options.pagination.external == true,
			stateOf = options.pagination.stateOf,
			onPageChange = options.pagination.onPageChange,
			labelOf = options.pagination.labelOf,
		} or nil,
		pagerButtonWidth = math.max(12, numberOr(options.pagerButtonWidth, 24)),
		page = 1, pageState = nil, options = options,
		colors = SiK.UI.Theme.tokens(root.panel._sikThemeContext or options.theme),
		themeContext = root.panel._sikThemeContext, blocks = blocks,
		paddingX = paddingX, paddingY = paddingY,
		sortKey = options.sortKey, sortAsc = options.sortAsc ~= false,
		onColumnResize = options.onColumnResize, onSort = type(options.onSort) == "function" and options.onSort or nil,
		onRowClick = type(options.onRowClick) == "function" and options.onRowClick or nil,
		playerNum = math.max(0, math.floor(numberOr(options.playerNum, 0))),
		disposed = false, _sikUiComponent = "table" }, TableInstance)
	root.panel._sikUiTable = instance
	function instance:_refreshTheme(context)
		self.colors = SiK.UI.Theme.tokens(context or self.themeContext or self.options.theme)
		return self
	end
	SiK.UI.Theme.bind(root.panel, instance.themeContext, function(_, context)
		instance:_refreshTheme(context)
	end)
	header._sikUiComponent = "tableHeader"
	scroll.viewport._sikUiComponent = "tableViewport"
	scroll.host._sikUiComponent = "tableRows"
	header._sikTable = instance
	header.prerender = function(panel) instance:_drawHeader(panel) end
	attachHeaderInteraction(instance)
	if pager then
		pager.prerender = function(panel) instance:_drawPager(panel) end
		pager.onMouseUp = function(_, x)
			if x < pager.width / 2 then return instance:previousPage() ~= nil end
			return instance:nextPage() ~= nil
		end
	end
	if emptyPanel then
		emptyPanel.prerender = function(panel)
			local r, g, b, a = colorParts(instance.colors.textMuted, instance.colors.text)
			local label = panel._sikEmptyText or tostring(options.emptyText)
			if panel.drawTextCentre then panel:drawTextCentre(label, panel.width / 2,
				math.max(0, math.floor((panel.height - metrics.fontHeight) / 2)), r, g, b, a, metrics.font) end
		end
		emptyPanel._sikEmptyText = tostring(options.emptyText)
		SiK.UI.Layout.apply(emptyPanel, root:getContentRect())
		emptyPanel:setVisible(false)
	end
	local list, listReason = SiK.UI.VirtualList.create({ scroll = scroll, rowHeight = metrics.rowHeight,
		buffer = options.buffer, playerNum = options.playerNum,
		retainMissingSelection = true,
		keyOf = function(projected) return projected.visualKey end,
		createRow = function(owner, width, height) return instance:_createRow(owner, width, height) end,
		updateRow = function(row, projected, index) instance:_updateRow(row, projected, index) end,
		onSelect = function(context)
			local selection = instance.semanticById[context.key]
			if selection then
				instance.semanticSelection = selection
				if instance.selectionMode ~= "multiple" then instance.semanticSelections = {} end
				instance.semanticSelections[selection.id] = true
			end
			if selection and type(options.onSelect) == "function" then
				options.onSelect({ playerNum = instance.playerNum, component = instance,
					key = selection.key, parentKey = selection.parentKey,
					kind = selection.kind, item = selection.item, selection = selection })
			end
		end,
		onActivate = function(context)
			local projected = context.item
			local firstColumn = instance.columnLayout[1]
			local prefixStart = (firstColumn and firstColumn.x or 0) + projected.depth * instance.indent
			if projected.hasChildren and context.x >= prefixStart
				and context.x <= prefixStart + instance.expansionHitbox then
				instance:toggleExpanded(projected.key) return
			end
			if instance.onRowClick then instance.onRowClick({
				playerNum = instance.playerNum, component = instance, item = projected.data,
				index = projected.sourceIndex, key = projected.key, depth = projected.depth,
				parentKey = projected.parentKey, kind = projected.semantic.kind,
				selection = projected.semantic, x = context.x, y = context.y }) end
		end,
		interaction = {
			onMouseDown = function(context)
				if context.item.kind == "pager" then
					if context.row.setCapture then context.row:setCapture(true) end
					return true
				end
				if instance:_isExpansionHit(context.row, context.x) then
					context.row._sikExpansionPressed = true
					if context.row.setCapture then context.row:setCapture(true) end
					return true
				end
				local adapter = instance.rowAdapter
				if not adapter or not adapter.onMouseDown then return false end
				local rowContext = instance:_rowContext(context.row, context)
				return adapter.onMouseDown(rowContext) == true
			end,
			onMouseMove = function(context)
				if context.item.kind == "pager" then return true end
				if context.row._sikExpansionPressed then return true end
				local adapter = instance.rowAdapter
				if not adapter or not adapter.onMouseMove then return false end
				return adapter.onMouseMove(instance:_rowContext(context.row, context)) == true
			end,
			onMouseUp = function(context)
				if context.item.kind == "pager" then
					if context.row.setCapture then context.row:setCapture(false) end
					local state = context.item.pageState
					if not state or state.disabled then return true end
					local previousStart = context.row.width - instance.pagerButtonWidth * 2
					local nextStart = context.row.width - instance.pagerButtonWidth
					if context.x >= previousStart and context.x < nextStart and state.hasPrevious then
						instance:setChildPage(context.item.parentKey, state.page - 1)
					elseif context.x >= nextStart and state.hasNext then
						instance:setChildPage(context.item.parentKey, state.page + 1)
					end
					return true
				end
				if context.row._sikExpansionPressed then
					context.row._sikExpansionPressed = nil
					if context.row.setCapture then context.row:setCapture(false) end
					return instance:toggleExpanded(context.item.key) ~= nil
				end
				local adapter = instance.rowAdapter
				if not adapter or not adapter.onMouseUp then return false end
				return adapter.onMouseUp(instance:_rowContext(context.row, context)) == true
			end,
			onMouseUpOutside = function(context)
				if context.item.kind == "pager" then
					if context.row.setCapture then context.row:setCapture(false) end
					return true
				end
				if context.row._sikExpansionPressed then
					context.row._sikExpansionPressed = nil
					if context.row.setCapture then context.row:setCapture(false) end
					return true
				end
				local adapter = instance.rowAdapter
				if not adapter or not adapter.onMouseUpOutside then return false end
				return adapter.onMouseUpOutside(instance:_rowContext(context.row, context)) == true
			end,
			onDoubleClick = function(context)
				if context.item.kind == "pager" then return true end
				local adapter = instance.rowAdapter
				if not adapter or not adapter.onDoubleClick then return false end
				return adapter.onDoubleClick(instance:_rowContext(context.row, context)) == true
			end,
			onRightClick = function(context)
				if context.item.kind == "pager" then return true end
				local adapter = instance.rowAdapter
				if not adapter or not adapter.onRightClick then return false end
				return adapter.onRightClick(instance:_rowContext(context.row, context)) == true
			end,
		} })
	if not list then scroll:dispose() detach(root.panel, header)
		if blockHeader and blockHeader.dispose then blockHeader:dispose() end
		detach(root.panel, pager) detach(root.panel, emptyPanel)
		root:dispose() return nil, listReason end
	instance.list = list
	for index = 1, #blocks do
		if blocks[index]._tableMounted then blocks[index]:_tableMounted() end
	end
	instance.rootListener = function() instance:_syncGeometry() end
	root:subscribe(instance.rootListener)
	if root.directBlock then instance.blockListener = block:subscribe(function()
		if instance.disposed then return end
		root:syncBlockBounds()
		instance._geometrySignature = nil
		instance:_syncGeometry()
	end) end
	instance:_syncGeometry()
	local ok, rowsReason = instance:setRows(options.rows or {}, options.preserveOffset == true)
	if not ok then instance:dispose() return nil, rowsReason end
	return instance
end

return Table
