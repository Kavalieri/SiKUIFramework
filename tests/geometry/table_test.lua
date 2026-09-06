local T = require "tests/geometry/pz_ui_stub"
local Table = require "SiK/UI/Table"
local Block = require "SiK/UI/Block"

T.eq(SiK.UI.Namespace.module("Table"), Table, "table registered in public namespace")
T.eq(Table.createVirtual, nil, "no legacy table constructor")
T.eq(Table.createBlock, nil, "no parallel table constructor")
T.ok(type(Table.create) == "function", "canonical Table.create composition is public")
T.ok(type(Table.resolveColumns) == "function", "shared declarative geometry")
T.eq(SiK.UI.Metrics.tokens().table.expansionHitbox, 32,
	"warehouse expansion hitbox is the framework-wide table standard")
local tableColors = SiK.UI.Theme.tokens()
T.eq(tableColors.tableHeader.r, 13 / 255, "table header has approved chrome")
T.eq(tableColors.tableRow.r, 15 / 255, "table row does not inherit generic surface")
T.eq(tableColors.tableRowAlt.r, 18 / 255, "table alternate row keeps approved density")
T.eq(tableColors.tableRowChild.r, 12 / 255, "expanded child keeps production depth")

local cjk = "\228\184\173\230\150\135\230\181\139\232\175\149"
local previousTextManager = _G.getTextManager
_G.getTextManager = function()
	return { MeasureStringX = function(_, _, text)
		local count = 0
		for index = 1, string.len(text) do
			local byte = string.byte(text, index)
			if byte < 128 then count = count + 1
			elseif byte >= 192 then count = count + 2 end
		end
		return count
	end }
end
T.eq(SiK.UI.Controls.truncateText(cjk, 5, UIFont.Small),
	"\228\184\173...", "table text truncation preserves UTF-8 boundaries")
local cjkLines = SiK.UI.Controls.wrapText(cjk, 4, UIFont.Small)
T.eq(#cjkLines, 2, "unspaced CJK text wraps into measured lines")
T.eq(cjkLines[1], "\228\184\173\230\150\135", "CJK wrap preserves complete glyphs")
T.eq(cjkLines[2], "\230\181\139\232\175\149", "CJK wrap preserves remaining glyphs")
_G.getTextManager = previousTextManager

local parent = T.panel(800, 600)
local function createTable(options)
	local outer = options.parent
	local header = type(options.blockHeader) == "table" and options.blockHeader or nil
	local block = assert(Block.create({ parent = outer,
		x = options.x or 0, y = options.y or 0,
		w = options.w or options.width or 0,
		h = options.h or options.height or 0,
		title = options.title or (header and header.title),
		tooltip = header and header.tooltip,
		actions = header and header.action and { header.action } or nil,
		scrollable = true }))
	options.parent = block.panel
	options.embedded = true
	return assert(Table.create(options))
end
local rows = {}
for index = 1, 12 do rows[index] = { id = "r" .. index, name = "Row " .. index, state = "OK" } end
local tableView = createTable({
	parent = parent,
	x = 10, y = 10, w = 500, h = 220,
	title = "Members",
	columns = {
		{ key = "name", title = "Name", flex = 2, min = 120 },
		{ key = "state", title = "State", width = 90, align = "right" },
	},
	rows = rows,
	keyOf = function(item) return item.id end,
	rowHeight = 30,
})
T.eq(#tableView.columnLayout, 2, "declarative columns")
T.eq(tableView.block.header._sikUiControl, "blockHeader", "title uses standard BlockHeader")
T.eq(tableView.block.header.label.name, "Members", "declarative title reaches BlockHeader")
T.eq(tableView.blockHeader, nil, "Table does not paint a local block title")
T.eq(tableView._sikUiComponent, "table", "table handle carries public marker")
T.eq(tableView.root.panel._sikUiTable, tableView, "table root belongs to exactly one table")
T.eq(tableView.header._sikUiComponent, "tableHeader", "professional header is marked")
T.eq(tableView.scroll.viewport._sikUiComponent, "tableViewport", "viewport is marked")
T.eq(tableView.scroll.host._sikUiComponent, "tableRows", "virtual row host is marked")
T.eq(tableView.header.width, tableView.block:getContentRect().w, "header uses content rect")
T.eq(tableView.scroll.viewport.width, tableView.header.width, "rows use same content rect")
T.eq(tableView.block.scroll, nil, "Table keeps ownership of its internal rows viewport")
T.eq(tableView.scroll.viewport.y, tableView.header.y + tableView.header.height,
	"row viewport starts below the column header")
T.ok(tableView.metrics.headerHeight >= tableView.metrics.fontHeight + 20,
	"header always preserves ten pixels of vertical breathing room")
T.ok(tableView.block:getTrackRect() ~= nil, "overflow owned by block")
T.eq(tableView.columnLayout[2].x + tableView.columnLayout[2].w,
	 tableView.header.width, "last column ends at content edge")

tableView.block:setBounds(0, 0, 640, 300)
T.eq(tableView.header.width, tableView.scroll.viewport.width, "resize keeps header and rows aligned")
T.eq(tableView.scroll.viewport.y, tableView.header.y + tableView.header.height,
	"resize cannot move row one back over the header")
T.eq(tableView:getBounds().w, tableView.block:getContentRect().w,
	"stable bounds expose the resized Block content width")
T.eq(tableView:getHeight(), tableView.block:getContentRect().h,
	"stable height exposes the resized Block content height")
tableView:setSelectedKey("r5")
T.eq(tableView:getSelectedKey(), "r5", "table selection")
T.ok(tableView.root.panel.onKeyRelease == nil,
	"selection does not install a keyboard activation handler")
tableView:dispose()
tableView:dispose()
T.ok(tableView.disposed, "table dispose idempotent")

local embeddedParent = T.panel(500, 240)
embeddedParent._sikUiComponent = "blockContent"
local orphan, orphanReason = Table.create({
	parent = embeddedParent, w = 500, h = 240, embedded = true,
	columns = {
		{ key = "name", title = "Name", flex = 1 },
		{ key = "state", title = "State", width = 80 },
	},
})
T.eq(orphan, nil, "a marker cannot impersonate a physical Block")
T.eq(orphanReason, "table_requires_block", "orphan table is rejected before painting")
local embeddedBlock = assert(Block.create({ parent = embeddedParent,
	w = 500, h = 240, scrollable = false }))
local nestedParent = T.panel(500, 240)
embeddedBlock.panel:addChild(nestedParent)
local embedded = assert(Table.create({
	parent = nestedParent, w = 500, h = 240, embedded = true,
	columns = {
		{ key = "name", title = "Name", flex = 1 },
		{ key = "state", title = "State", width = 80 },
	},
	rows = {
		{ id = "c", name = "Charlie", state = "OK" },
		{ id = "a", name = "Alpha", state = "OK" },
		{ id = "b", name = "Bravo", state = "OK" },
	},
	keyOf = function(item) return item.id end,
}))
T.eq(embedded.paddingX, 0, "embedded table does not add a second horizontal frame")
T.eq(embedded.paddingY, 0, "embedded table does not add a second vertical frame")
T.eq(embedded.header.width, 500, "embedded header consumes the parent content width")
embedded.header:onMouseUpOutside(20, 4)
T.eq(embedded.rows[1].name, "Charlie", "release outside an unarmed header never sorts")
embedded.header:onMouseDown(20, 4)
embedded.header:onMouseUp(20, 4)
T.eq(embedded.rows[1].name, "Alpha", "first header click applies local ascending sort")
embedded.header:onMouseDown(20, 4)
embedded.header:onMouseUp(20, 4)
T.eq(embedded.rows[1].name, "Charlie", "second header click applies local descending sort")
T.eq(embedded.header:onMouseDown(20, embedded.header.height + 1), false,
	"press outside the visible header hitbox is rejected")
embedded.header:onMouseUp(20, 4)
T.eq(embedded.rows[1].name, "Charlie", "rejected press cannot arm a later release")
embedded:dispose()

local actionInvoked = false
local auto = createTable({
	parent = parent, x = 5, y = 6, w = 420, h = 300,
	blockHeader = {
		title = "Terminals", tooltip = "Network terminals",
		action = { text = "+", tooltip = "Add", onClick = function() actionInvoked = true end },
	},
	columns = {
		{ key = "name", title = "Name", flex = 1 },
		{ key = "state", title = "State", width = 80 },
	},
	rows = { rows[1], rows[2] }, keyOf = function(item) return item.id end,
	autoHeight = true, minRows = 1, maxRows = 3,
})
T.eq(auto.block.header._sikUiControl, "blockHeader", "declarative spec composes BlockHeader")
T.eq(auto.root.y, auto.block:getContentRect().y,
	"BlockHeader reserves the canonical content origin")
T.ok(auto.block.header.info ~= nil, "tooltip composes Info before title")
T.ok(auto.block.header.action ~= nil, "declarative action composes after title")
T.eq(auto:getHeight(), auto:getRequiredHeight(), "auto height follows projected rows")
local twoRowHeight = auto:getHeight()
auto:setSelectedKey("r2")
auto:setScrollOffset(12)
auto:layout({ w = 500, rows = { rows[1], rows[2], rows[3], rows[4] } })
T.eq(auto:getHeight(), auto:getRequiredHeight(), "row reflow recomputes stable height")
T.eq(auto:getHeight(), twoRowHeight + auto.metrics.rowHeight,
	"maxRows caps auto reflow without changing row data")
T.eq(auto:getSelectedKey(), "r2", "row reflow preserves semantic selection")
T.eq(#auto.rows, 4, "row reflow preserves complete data outside height projection")
auto:setScrollOffset(4)
auto:layout({ rows = { rows[1], rows[2], rows[3], rows[4], rows[5] } })
T.eq(auto:getScrollOffset(), 4, "row reflow preserves a valid scroll offset")
auto.block.header.action.onclick(auto.block.header.action.target)
T.ok(actionInvoked, "declarative BlockHeader action remains callable")
auto:dispose()

local semanticParent = { id = "p", name = "Parent", state = "OK", children = {
		{ id = "c1", name = "Child 1", state = "OK" },
		{ id = "c2", name = "Child 2", state = "OK" },
		{ id = "c3", name = "Child 3", state = "OK" },
	} }
local activated, expansionEvents = {}, {}
local expanded = createTable({
	parent = parent, w = 400, h = 180,
	columns = {
		{ key = "name", title = "Name", flex = 1 },
		{ key = "state", title = "State", width = 80 },
	},
	rows = { semanticParent },
	keyOf = function(item) return item.id end,
	expansion = {
		childrenOf = function(item) return item.children end,
		keyOf = function(item) return item.id end,
	},
	pagination = { pageSize = 2 },
	onExpansionChange = function(context) expansionEvents[#expansionEvents + 1] = context end,
	onRowClick = function(context) activated[#activated + 1] = context end,
})
T.eq(#expanded.projectedRows, 1, "collapsed projection")
T.eq(expanded.pagination.pageSize, 2, "pagination contract preserved by Table")
expanded.list.pool[1]:onMouseUp(80, 4)
T.eq(activated[1].item, semanticParent, "collapsed parent activation returns original semantic row")
T.eq(activated[1].selection.kind, "parent", "collapsed parent exposes semantic parent selection")
T.eq(activated[1].selection.key, "p", "collapsed parent keeps stable semantic key")
expanded:toggleExpanded("p")
T.eq(#expanded.projectedRows, 4, "child pagination keeps parent, first child page and structural pager")
T.eq(expansionEvents[1].key, "p", "expansion callback keeps semantic parent key")
T.ok(expansionEvents[1].expanded, "expansion callback reports resulting state")
local firstPager = expanded.projectedRows[4]
T.eq(firstPager.kind, "pager", "child pager is an explicit structural row")
T.eq(firstPager.data, nil, "pager row carries no selectable data unit")
T.eq(firstPager.sourceIndex, 0, "pager row has no source object index")
T.eq(firstPager.semantic, nil, "pager row is excluded from semantic selection")
expanded:setPage(2)
T.eq(#expanded.projectedRows, 3, "second child page keeps parent, final child and structural pager")
T.eq(expanded:getPageState().pageCount, 2, "page state remains internal")
T.eq(expanded.projectedRows[3].kind, "pager", "last child page retains the structural pager")
local selectionsBeforePager = #expanded:getSemanticSelections()
T.eq(selectionsBeforePager, 1, "parent selection remains the only semantic selection")
local pagerRow = expanded.list.pool[3]
T.ok(pagerRow and pagerRow._sikProjected.kind == "pager", "pager mounts as a neutral row handle")
T.ok(pagerRow:onMouseDown(4, 4), "pager consumes its own press")
T.ok(pagerRow:onMouseUp(4, 4), "pager consumes its own release")
T.eq(#activated, 1, "pager interaction does not invoke row activation")
T.eq(#expanded:getSemanticSelections(), selectionsBeforePager,
	"pager interaction does not add a semantic selection")
expanded:setPage(1)
expanded.list.pool[1]:onMouseUp(80, 4)
T.eq(activated[2].item, semanticParent, "expanded parent activation returns original semantic row")
T.eq(activated[2].selection, activated[1].selection,
	"parent semantic selection is independent from expansion and pagination")
expanded:toggleExpanded("p")
T.eq(#expanded.projectedRows, 1, "second toggle collapses the parent")
T.ok(not expanded.expanded.p, "collapse clears expansion state")
expanded:dispose()

local firstCollapsed = { id = "first", name = "First", state = "OK", children = {
	{ id = "first-child", name = "First child", state = "OK" },
} }
local secondExpanded = { id = "second", name = "Second", state = "OK", children = {
	{ id = "s1", name = "Child 1", state = "OK" },
	{ id = "s2", name = "Child 2", state = "OK" },
	{ id = "s3", name = "Child 3", state = "OK" },
} }
local activePager = createTable({
	parent = parent, w = 400, h = 180,
	columns = {
		{ key = "name", title = "Name", flex = 1 },
		{ key = "state", title = "State", width = 80 },
	},
	rows = { firstCollapsed, secondExpanded },
	keyOf = function(item) return item.id end,
	expansion = {
		childrenOf = function(item) return item.children end,
		keyOf = function(item) return item.id end,
	},
	pagination = { pageSize = 2 },
})
T.eq(activePager.pager, nil,
		"hierarchical pagination does not create a global footer pager")
local collapsedPage, collapsedPageReason = activePager:setPage(2)
T.eq(collapsedPage, nil, "collapsed roots cannot change a child page")
T.eq(collapsedPageReason, "no_pageable_parent",
	"collapsed roots report that no pageable group is active")
activePager:toggleExpanded("first")
T.eq(activePager:getPageState().pageCount, 1,
	"one-page expanded group keeps a single page state")
T.eq(#activePager.projectedRows, 4,
		"expanded group keeps its structural pager row")
local activePagerRow
for index = 1, #activePager.projectedRows do
	if activePager.projectedRows[index].kind == "pager" then activePagerRow = activePager.projectedRows[index] end
end
T.ok(activePagerRow, "expanded group pager remains structural")
activePager:toggleExpanded("first")
activePager:toggleExpanded("second")
T.eq(activePager.activePageParentKey, "second",
	"expanded group becomes the active visual pager target")
T.eq(activePager:getPageState().pageCount, 2,
	"collapsed group before it cannot hide the expanded group pagination")
T.eq(#activePager.projectedRows, 5,
		"multi-page expanded group adds one structural pager row")
T.eq(activePager.projectedRows[5].kind, "pager", "active hierarchical pager is a structural row")
activePager:dispose()

local adapterEvents = {}
local multiple = createTable({
	parent = parent, w = 420, h = 160, selectionMode = "multiple",
	columns = {
		{ key = "name", title = "Name", flex = 1 },
		{ key = "state", title = "State", width = 80 },
	},
	rows = { rows[1], rows[2], rows[3] }, keyOf = function(item) return item.id end,
	row = {
		renderMode = "replace",
		update = function(context) adapterEvents[#adapterEvents + 1] = "update:" .. context.key end,
		render = function(context) adapterEvents[#adapterEvents + 1] = "render:" .. context.key end,
		onMouseDown = function(context)
			adapterEvents[#adapterEvents + 1] = "down:" .. context.key
			return true
		end,
	},
})
multiple:setSelectedKeys({ "r1", "r3" })
T.eq(#multiple:getSemanticSelections(), 2, "multiple semantic selections are table-owned")
T.ok(multiple:isSelected("r1"), "first semantic key remains selected")
T.ok(multiple:isSelected("r3"), "second semantic key remains selected")
multiple.list.pool[1]:prerender()
multiple.list.pool[1]:onMouseDown(4, 4)
T.ok(#adapterEvents >= 5, "row adapter receives lifecycle without owning row panels")
multiple:dispose()

local lazy = createTable({
	parent = parent, w = 400, h = 120,
	columns = {
		{ key = "name", title = "Name", flex = 1 },
		{ key = "state", title = "State", width = 80 },
	},
	rows = { { id = "lazy", name = "Lazy", state = "OK" } },
	keyOf = function(item) return item.id end,
	expansion = {
		childrenOf = function() return {} end,
		hasChildren = function() return true end,
	},
})
T.ok(lazy.projectedRows[1].hasChildren, "lazy parent keeps expansion hitbox before children arrive")
local lazyRow = lazy.list.pool[1]
T.ok(lazyRow:onMouseDown(2, 4), "table owns expansion press geometry")
T.ok(lazyRow:onMouseUp(2, 4), "table owns expansion release geometry")
T.ok(lazy.expanded.lazy, "framework expansion hitbox toggles lazy parent")
lazy:dispose()

local actionCalls, actionDisposals = 0, 0
local actionTable = createTable({
	parent = parent, w = 420, h = 140,
	columns = {
		{ key = "name", title = "Name", flex = 1 },
		{ key = "actions", title = "Actions", width = 160, actions = {
			gap = 4,
			items = function(item) return item.actions end,
			create = function(context)
				local control = T.panel(1, 1)
				control.action = context.action
				return control
			end,
			update = function(control, context)
				control.action = context.action; actionCalls = actionCalls + 1
			end,
			dispose = function() actionDisposals = actionDisposals + 1 end,
		} },
	},
	rows = { { id = "actions", name = "Row", actions = { "up", "down", "open" } } },
	keyOf = function(item) return item.id end,
})
T.ok(actionCalls >= 3, "one declarative adapter creates every cell action")
local actionRow = actionTable.list.pool[1]
T.eq(#actionRow._sikActionControls, 3, "table owns row action controls")
actionRow:prerender()
T.ok(actionRow._sikActionControls[3].control.x > actionRow._sikActionControls[1].control.x,
	"action controls share resolved cell geometry")
actionTable:setRows({}, true)
T.eq(actionDisposals, actionCalls, "row recycling disposes every created action control")
actionTable:dispose()

return true
