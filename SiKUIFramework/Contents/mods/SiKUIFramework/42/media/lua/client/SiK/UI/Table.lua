require "ISUI/ISPanel"
require "SiK/UI/Metrics"
require "SiK/UI/Layout"
require "SiK/UI/Theme"
require "SiK/UI/Block"
require "SiK/UI/Scroll"
require "SiK/UI/VirtualList"
require "SiK/UI/Controls"

SiK = SiK or {}
SiK.UI = SiK.UI or {}

local Table = SiK.UI.Table or {}
SiK.UI.Namespace.define("Table", Table)

local TableInstance = {}
TableInstance.__index = TableInstance

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

local function detach(parent, child)
	if not child then return end
	if parent and parent.removeChild then parent:removeChild(child) end
	if child.removeFromUIManager then child:removeFromUIManager() end
end

local function validColumns(columns)
	if type(columns) ~= "table" or #columns < 2 or #columns > 5 then return false end
	for index = 1, #columns do
		local column = columns[index]
		if type(column) ~= "table" or type(column.key) ~= "string" or column.key == "" then return false end
	end
	return true
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
	return { font = font, fontHeight = resolvedFontHeight,
		rowHeight = math.max(1, numberOr(options.rowHeight, tokens.table.rowHeight)),
		headerHeight = math.max(resolvedFontHeight + tokens.table.headerVerticalPadding * 2,
			numberOr(options.headerHeight, tokens.table.headerHeight)),
		gap = math.max(0, numberOr(options.columnGap or options.gap, tokens.table.columnGap)),
		left = math.max(0, numberOr(options.left, 0)), right = math.max(0, numberOr(options.right, 0)),
		cellPadding = math.max(0, numberOr(options.cellPadding, tokens.table.cellPadding)) }
end

local function measuredWidth(spec, font)
	local title = spec.title or SiK.UI.resolveText(spec.titleKey, spec.key) or ""
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
		parts[#parts + 1] = table.concat({ tostring(spec.key), tostring(spec.flex or ""),
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
	columns, options = columns or {}, options or {}
	local metrics = Table.metrics(options)
	local key = layoutKey(width, columns, options, metrics)
	local cached = columns._sikLayoutCache
	if cached and cached.key == key then return cached.layout end
	local flow = false
	for index = 1, #columns do
		local spec = columns[index]
		if spec.flex or spec.width or spec.widthFraction or spec.measureValues then flow = true break end
	end
	local out = {}
	if not flow then
		for index = 1, #columns do
			local spec = columns[index]
			local first = edge(spec.start, spec.startFraction, width, 0)
			local finish = math.max(first, edge(spec.finish, spec.finishFraction, width,
				width - numberOr(spec.right, 0)))
			out[index] = { key = spec.key, title = spec.title, titleKey = spec.titleKey,
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
		elseif spec.flex then
			widths[index] = 0
			flexTotal = flexTotal + math.max(0, numberOr(spec.flex, 0))
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
		if spec.flex and not (options.columnWidths and tonumber(options.columnWidths[spec.key])) then
			colW = math.floor(math.max(0, numberOr(spec.minWidth or spec.min, 0)) * shrink)
			if flexExtra > 0 then colW = colW + math.floor(flexExtra * numberOr(spec.flex, 0) / math.max(1, flexTotal)) end
			colW = math.max(numberOr(spec.hardMinWidth, 24), colW)
		end
		out[index] = { key = spec.key, title = spec.title, titleKey = spec.titleKey,
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
	local height, header = numberOr(options.rowHeight, metrics.rowHeight), numberOr(options.headerHeight, 0)
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

function TableInstance:_projectParent(parent, out)
	out[#out + 1] = { data = parent.item, depth = 0, key = parent.key,
		visualKey = parent.id, semantic = parent, sourceIndex = parent.index,
			hasChildren = parent.hasChildren == true }
	local children = parent.children
	if not parent.hasChildren then return end
	local size = self.pagination and self.pagination.pageSize or #children
	local total, requestedPage = #children, self.childPages[parent.key]
	local externalState = nil
	if self.pagination and self.pagination.external then
		externalState = self.pagination.stateOf(parent.item, parent.key, self)
		if type(externalState) == "table" then
			total = math.max(0, math.floor(numberOr(externalState.total, total)))
			requestedPage = numberOr(externalState.page, requestedPage)
			size = math.max(1, math.floor(numberOr(externalState.pageSize, size)))
		end
	end
	local state = pageState(total, requestedPage, size)
	state.disabled = type(externalState) == "table" and externalState.disabled == true or false
	state.disabledReason = type(externalState) == "table" and externalState.disabledReason or nil
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
		local selection = self.semanticById[semanticId("child", childKey, parent.key)]
		out[#out + 1] = { data = child, depth = 1, key = childKey,
			visualKey = selection.id, semantic = selection, parentKey = parent.key,
			sourceIndex = childIndex, hasChildren = false }
	end
end

function TableInstance:_projectRows()
	local visible = {}
	if self.expansion then
		self.childPageStates = {}
		for index = 1, #self.rows do
			local key = self.keyOf(self.rows[index], index)
			self:_projectParent(self.parentByKey[key], visible)
		end
		local active = self.activePageParentKey or self.firstPageParentKey
		self.activePageParentKey = active
		self.pageState = active and self.childPageStates[active]
			or pageState(0, 1, self.pagination and self.pagination.pageSize or 15)
		self.page = self.pageState.page
		return visible
	end
	for index = 1, #self.rows do
		local key = self.keyOf(self.rows[index], index)
		local selection = self.parentByKey[key]
		visible[#visible + 1] = { data = selection.item, depth = 0, key = key,
			visualKey = selection.id, semantic = selection, sourceIndex = index, hasChildren = false }
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
			if adapter and adapter.afterRender then
				adapter.afterRender(owner:_rowContext(panel))
			end
		end
	end
	row.dispose = function(panel)
		local owner = panel._sikTable
		if owner then
			if owner.rowAdapter and owner.rowAdapter.dispose then
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
	row._sikSelected = self.semanticSelections[projected.semantic.id] == true
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

function TableInstance:_syncGeometry()
	if self.disposed then return end
	local visiblePagerHeight = reservedPagerHeight(self)
	local content = self.block:getContentRect()
	local signature = table.concat({ tostring(content.x), tostring(content.y),
		tostring(content.w), tostring(content.h), tostring(self.block.w),
		tostring(self.block.h), tostring(self.blockHeaderHeight),
		tostring(self.metrics.headerHeight), tostring(visiblePagerHeight),
		tostring(#self.projectedRows) }, ":")
	if self._geometrySignature == signature then return self end
	self._geometrySignature = signature
	local padding, y = self.paddingY, self.paddingY
	if self.blockHeader then
		SiK.UI.Layout.apply(self.blockHeader, { x = content.x, y = y,
			w = content.w, h = self.blockHeaderHeight })
		if self.blockHeader.reflow then self.blockHeader:reflow(content.w) end
		y = y + self.blockHeaderHeight + self.blockHeaderGap
	end
	SiK.UI.Layout.apply(self.header, { x = content.x, y = y, w = content.w, h = self.metrics.headerHeight })
	local rowsY = y + self.metrics.headerHeight
	local rowsBottom = self.block.h - padding
	if visiblePagerHeight > 0 then
		SiK.UI.Layout.apply(self.pager, { x = content.x, y = self.block.h - padding - visiblePagerHeight,
			w = content.w, h = visiblePagerHeight })
		self.pagerPrevX, self.pagerNextX = math.max(4, content.w / 2 - 40), math.min(content.w - 4, content.w / 2 + 40)
		rowsBottom = self.block.h - padding - visiblePagerHeight
	end
	local rowsRect = { x = content.x, y = rowsY, w = content.w,
		h = math.max(0, rowsBottom - rowsY) }
	local trackRect = self.block:getTrackRect()
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
		trackRectSet = true, contentHeight = #self.projectedRows * self.metrics.rowHeight }, "table-geometry")
	if self.emptyPanel then SiK.UI.Layout.apply(self.emptyPanel, rowsRect) end
	if self.list and not refreshed then self.list:refresh() end
	return self
end

function TableInstance:getRequiredHeight(rowCount)
	local count = math.max(0, math.floor(numberOr(rowCount, #self.projectedRows)))
	count = math.max(self.minRows, count)
	if self.maxRows then count = math.min(self.maxRows, count) end
	local height = self.paddingY * 2 + self.blockHeaderHeight + self.blockHeaderGap + self.metrics.headerHeight
		+ reservedPagerHeight(self) + count * self.metrics.rowHeight
	height = math.max(self.minHeight, height)
	if self.maxHeight then height = math.min(self.maxHeight, height) end
	return height
end

function TableInstance:_applyAutoHeight()
	if not self.autoHeight or self.disposed then return self end
	local height = self:getRequiredHeight()
	if self.block.h ~= height then
		self.block:setBounds(self.block.x, self.block.y, self.block.w, height)
	end
	return self
end

function TableInstance:_refreshRows(preserveOffset)
	local previousOffset = preserveOffset == true and self.scroll:getScrollOffset() or 0
	local projected = self:_projectRows()
	self.projectedRows = projected
	if self.pager then self.pager:setVisible(reservedPagerHeight(self) > 0) end
	local chromeHeight = self.blockHeaderHeight + self.blockHeaderGap
		+ self.metrics.headerHeight + reservedPagerHeight(self)
	self.block:setContentHeight(chromeHeight + #projected * self.metrics.rowHeight)
	self:_applyAutoHeight()
	if self.emptyPanel then self.emptyPanel:setVisible(#projected == 0) end
	local result, reason = self.list:setData(projected, preserveOffset == true)
	if result and preserveOffset == true then self.scroll:setScrollOffset(previousOffset) end
	return result, reason
end

function TableInstance:setRows(rows, preserveOffset)
	if self.disposed then return nil, "disposed" end
	self.rows = type(rows) == "table" and rows or {}
	self:_rebuildSemanticIndex()
	-- A data refresh is not a navigation request.  Keep the user's semantic
	-- position unless the caller explicitly starts a new result set.
	return self:_refreshRows(preserveOffset ~= false)
end

function TableInstance:setColumns(columns)
	if self.disposed then return nil, "disposed" end
	if not validColumns(columns) then return nil, "invalid_columns" end
	self.columns = columns
	self._geometrySignature = nil
	self:_syncGeometry()
	return self
end

function TableInstance:setBounds(x, y, w, h)
	if self.disposed then return nil, "disposed" end
	self.block:setBounds(x, y, w, h)
	return self
end

function TableInstance:getBounds()
	return { x = self.block.x, y = self.block.y, w = self.block.w, h = self.block.h }
end

function TableInstance:getHeight() return self.block.h end

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
	if not self.pagination then return nil, "pagination_disabled" end
	if self.expansion then
		local parentKey = self.activePageParentKey or self.firstPageParentKey
		if parentKey == nil then return nil, "no_pageable_parent" end
		return self:setChildPage(parentKey, page)
	end
	self.page = math.max(1, math.floor(numberOr(page, 1)))
	return self:_refreshRows(false)
end

function TableInstance:setChildPage(parentKey, page)
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
	local decorated = {}
	for index = 1, #self.rows do decorated[index] = { item = self.rows[index], index = index } end
	table.sort(decorated, function(left, right)
		local leftType, leftValue = sortableValue(column, left.item, left.index)
		local rightType, rightValue = sortableValue(column, right.item, right.index)
		local before = leftType < rightType or (leftType == rightType and leftValue < rightValue)
		local equal = leftType == rightType and leftValue == rightValue
		if equal then return left.index < right.index end
		return self.sortAsc and before or not before
	end)
	for index = 1, #decorated do self.rows[index] = decorated[index].item end
	self:_rebuildSemanticIndex()
	return self:_refreshRows(true)
end

function TableInstance:previousPage() return self:setPage(self.page - 1) end
function TableInstance:nextPage() return self:setPage(self.page + 1) end

function TableInstance:toggleExpanded(key)
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
	local result, reason = self:_refreshRows(true)
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
	if type(state) ~= "table" then return nil, "invalid_state" end
	if type(state.expanded) == "table" then self.expanded = state.expanded end
	if type(state.childPages) == "table" then self.childPages = state.childPages end
	self.activePageParentKey = state.activePageParentKey
	self.page = math.max(1, math.floor(numberOr(state.page, self.page)))
	self:_refreshRows(false)
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
	if self.header and self.header.setCapture then self.header:setCapture(false) end
	if self.blockListener then self.block:unsubscribe(self.blockListener) end
	if self.list then self.list:dispose() end
	if self.scroll then self.scroll:dispose() end
	detach(self.block and self.block.panel, self.header)
	if self.blockHeader and self.blockHeader.dispose then self.blockHeader:dispose() end
	detach(self.block and self.block.panel, self.pager)
	detach(self.block and self.block.panel, self.emptyPanel)
	if self.block then self.block:dispose() end
	self.rows, self.projectedRows, self.expanded = {}, {}, {}
	self.semanticById, self.parentByKey, self.childPages, self.childPageStates = {}, {}, {}, {}
	self.semanticSelections = {}
	self.semanticSelection = nil
	self.list, self.scroll, self.header, self.blockHeader = nil, nil, nil, nil
	self.pager, self.emptyPanel, self.block = nil, nil, nil
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
	if not validColumns(options.columns) then return nil, "invalid_columns" end
	if options.expansion ~= nil and (type(options.expansion) ~= "table"
		or type(options.expansion.childrenOf) ~= "function") then return nil, "invalid_expansion" end
	if options.pagination ~= nil and (type(options.pagination) ~= "table"
		or numberOr(options.pagination.pageSize, 0) < 1) then return nil, "invalid_pagination" end
	if options.pagination and options.pagination.external == true
		and (type(options.pagination.stateOf) ~= "function"
			or type(options.pagination.onPageChange) ~= "function") then
		return nil, "invalid_external_pagination"
	end
	local metrics, tokens = Table.metrics(options), SiK.UI.Metrics.tokens(options.metrics)
	local embedded = options.embedded == true
	local paddingX = embedded and 0 or numberOr(options.paddingX, tokens.block.padding)
	local paddingY = embedded and 0 or numberOr(options.paddingY, tokens.block.padding)
	local blockHeaderSpec, blockHeaderHeight = resolveBlockHeader(options)
	local blockHeaderGap = blockHeaderSpec and tokens.spacing.md or 0
	local pagerHeight = options.pagination and math.max(1, numberOr(options.pagination.height, tokens.table.pagerHeight)) or 0
	local block, reason = SiK.UI.Block.create({ parent = options.parent, x = options.x, y = options.y,
		w = options.w or options.width, h = options.h or options.height,
		-- Header, rows and pager are positioned by TableInstance itself. Reserving
		-- them again in Block shortens the same viewport a second time and leaves
		-- an apparent empty framed block under short embedded tables.
		reservedTop = 0, reservedBottom = 0,
		contentHeight = 0, metrics = options.metrics,
		variant = embedded and "transparent" or options.variant,
		paddingX = paddingX, paddingY = paddingY,
		background = embedded and false or options.background,
		border = embedded and false or options.border,
		fill = not embedded and options.fill == true, scrollable = true })
	if not block then return nil, reason end
	local header = createPanel(block.panel)
	local blockHeader = blockHeaderSpec and SiK.UI.Controls.blockHeader(block.panel, blockHeaderSpec) or nil
	local pager = options.pagination and createPanel(block.panel) or nil
	local emptyPanel = options.emptyText and createPanel(block.panel) or nil
	local scroll, scrollReason = SiK.UI.Scroll.create({ parent = block.panel,
		viewportRect = block:getContentRect(), trackRect = block:getTrackRect(), wheelStep = options.wheelStep,
		contentHeight = 0, playerNum = options.playerNum })
	if not scroll then detach(block.panel, header)
		if blockHeader and blockHeader.dispose then blockHeader:dispose() end
		detach(block.panel, pager)
		detach(block.panel, emptyPanel)
		block:dispose() return nil, scrollReason end
	-- Empty feedback overlays the viewport only while the data source is empty.
	if emptyPanel and block.panel.removeChild and block.panel.addChild then
		block.panel:removeChild(emptyPanel)
		block.panel:addChild(emptyPanel)
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
		local instance = setmetatable({ block = block, scroll = scroll, header = header,
		blockHeader = blockHeader, pager = pager, emptyPanel = emptyPanel,
		columns = options.columns, columnLayout = {},
		columnOptions = { font = metrics.font, rowHeight = metrics.rowHeight,
			headerHeight = metrics.headerHeight, gap = metrics.gap, cellPadding = metrics.cellPadding,
			left = options.left, right = options.right, columnWidths = options.columnWidths or {} },
			metrics = metrics, blockHeaderHeight = blockHeaderHeight, blockHeaderGap = blockHeaderGap, pagerHeight = pagerHeight,
		autoHeight = options.autoHeight == true, minRows = minimumRows,
		maxRows = maximumRows, minHeight = minimumHeight, maxHeight = maximumHeight,
		rows = {}, projectedRows = {}, keyOf = type(options.keyOf) == "function"
			and options.keyOf or function(_, index) return index end,
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
		} or nil,
		page = 1, pageState = nil, options = options, colors = SiK.UI.Theme.tokens(options.theme),
		paddingX = paddingX, paddingY = paddingY,
		sortKey = options.sortKey, sortAsc = options.sortAsc ~= false,
		onColumnResize = options.onColumnResize, onSort = type(options.onSort) == "function" and options.onSort or nil,
		playerNum = math.max(0, math.floor(numberOr(options.playerNum, 0))),
				disposed = false, _sikUiComponent = "table" }, TableInstance)
		block.panel._sikUiTable = instance
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
		SiK.UI.Layout.apply(emptyPanel, block:getContentRect())
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
			if type(options.onRowClick) == "function" then options.onRowClick({
				playerNum = instance.playerNum, component = instance, item = projected.data,
				index = projected.sourceIndex, key = projected.key, depth = projected.depth,
				parentKey = projected.parentKey, kind = projected.semantic.kind,
				selection = projected.semantic, x = context.x, y = context.y }) end
			end,
		interaction = {
			onMouseDown = function(context)
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
				if context.row._sikExpansionPressed then return true end
				local adapter = instance.rowAdapter
				if not adapter or not adapter.onMouseMove then return false end
				return adapter.onMouseMove(instance:_rowContext(context.row, context)) == true
			end,
			onMouseUp = function(context)
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
				local adapter = instance.rowAdapter
				if not adapter or not adapter.onDoubleClick then return false end
				return adapter.onDoubleClick(instance:_rowContext(context.row, context)) == true
			end,
			onRightClick = function(context)
				local adapter = instance.rowAdapter
				if not adapter or not adapter.onRightClick then return false end
				return adapter.onRightClick(instance:_rowContext(context.row, context)) == true
			end,
		} })
	if not list then scroll:dispose() detach(block.panel, header)
		if blockHeader and blockHeader.dispose then blockHeader:dispose() end
		detach(block.panel, pager) detach(block.panel, emptyPanel)
		block:dispose() return nil, listReason end
	instance.list = list
	instance.blockListener = function() instance:_syncGeometry() end
	block:subscribe(instance.blockListener)
	instance:_syncGeometry()
	local ok, rowsReason = instance:setRows(options.rows or {}, options.preserveOffset == true)
	if not ok then instance:dispose() return nil, rowsReason end
	return instance
end

return Table
