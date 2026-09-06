local T = require "tests/geometry/pz_ui_stub"
local Table = require "SiK/UI/Table"
local Block = require "SiK/UI/Block"

local parent = T.panel(640, 360)
local remoteChildren = {
	{ id = "remote-4", name = "Remote 4" },
	{ id = "remote-5", name = "Remote 5" },
	{ id = "remote-6", name = "Remote 6" },
}
local source = {
	{ id = "parent", name = "Remote parent", children = remoteChildren },
}
local requested = {}
local pageState = { totalRows = 23, totalUnits = 34, page = 2, pageSize = 3 }

local tableBlock = assert(Block.create({
	parent = parent, w = 420, h = 180, scrollable = true,
}))
local tableView = assert(Table.create({
	parent = tableBlock.panel, w = 420, h = 180, embedded = true,
	columns = {
		{ key = "name", title = "Name", flex = 1 },
		{ key = "id", title = "ID", width = 100 },
	},
	rows = source,
	keyOf = function(item) return item.id end,
	expansion = {
		childrenOf = function(item) return item.children end,
		keyOf = function(item) return item.id end,
	},
	pagination = {
		pageSize = 3,
		external = true,
		stateOf = function()
			return pageState
		end,
		onPageChange = function(context)
			requested[#requested + 1] = context
			return "requested"
		end,
	},
}))

local function structuralPager()
        for _, projected in ipairs(tableView.projectedRows) do
                if projected.kind == "pager" then return projected end
        end
        return nil
end

T.eq(tableView.pager, nil,
        "hierarchical pagination does not expose a legacy global pager")
local rootPage, rootReason = tableView:setPage(2)
T.eq(rootPage, nil, "collapsed hierarchy cannot change a child page")
T.eq(rootReason, "no_pageable_parent",
	"collapsed hierarchy reports that no pageable group is active")

tableView:toggleExpanded("parent")
local pager = structuralPager()
T.ok(pager, "expanded multi-page hierarchy exposes a structural pager")
T.eq(pager.data, nil, "structural pager carries no selectable data")
T.eq(pager.sourceIndex, 0, "structural pager is outside source row indices")
T.eq(pager.semantic, nil, "structural pager is outside semantic rows")
T.eq(#tableView.projectedRows, 5,
        "external page keeps the parent and every already-paged child")
T.eq(tableView.projectedRows[2].data, remoteChildren[1],
	"external page starts at the first physical child instead of cropping again")
T.eq(tableView.projectedRows[4].data, remoteChildren[3],
	"external page retains the last physical child")

local state = tableView:getPageState("parent")
T.eq(state.total, 23, "external total is preserved")
T.eq(state.totalRows, 23, "pagination counts rendered child rows")
T.eq(state.totalUnits, 34, "physical units remain independent from rendered rows")
T.eq(#tableView.projectedRows, 5,
        "the parent header is rendered but excluded from row and unit totals")
T.eq(state.page, 2, "external current page is preserved")
T.eq(state.pageCount, 8, "external page count uses the declared total and page size")
T.eq(state.first, 4, "external logical first position remains accurate")
T.eq(state.last, 6, "external logical last position remains accurate")

local originalSource = tableView.rows
local originalChildren = source[1].children
local originalFirst = originalChildren[1]
local result = tableView:setChildPage("parent", 3)
T.eq(result, "requested", "external page request returns the adapter result")
T.eq(#requested, 1, "external page request invokes onPageChange once")
T.eq(requested[1].parentKey, "parent", "page request identifies its parent")
T.eq(requested[1].parent, source[1], "page request exposes the original parent")
T.eq(requested[1].page, 3, "page request exposes the requested page")
T.eq(tableView.rows, originalSource, "page request does not replace the source rows")
T.eq(source[1].children, originalChildren, "page request does not replace source children")
T.eq(source[1].children[1], originalFirst, "page request does not mutate child records")
T.eq(#source[1].children, 3, "page request does not change the physical page size")

tableView:toggleExpanded("parent")
T.eq(structuralPager(), nil,
        "collapsing the active hierarchy removes its structural pager")
tableView:toggleExpanded("parent")
pageState.totalRows = 3
pageState.totalUnits = 7
pageState.page = 1
tableView:setRows(source)
pager = structuralPager()
T.ok(pager, "expanded hierarchy retains its structural pager row on one page")
T.eq(pager.data, nil, "one-page structural pager remains non-selectable")
state = tableView:getPageState("parent")
T.eq(state.totalRows, 3, "fixture keeps three rendered children")
T.eq(state.totalUnits, 7, "fixture keeps seven physical objects")
T.eq(#tableView.projectedRows, 5,
        "parent header is visual only and does not turn seven units into eight")

pageState.totalRows = 0
pageState.totalUnits = 0
source[1].children = {}
tableView:setRows(source)
T.eq(#tableView.projectedRows, 1,
	"an empty parent header remains excluded from every semantic total")

source[1].children = remoteChildren
pageState.totalRows = 3
pageState.totalUnits = 7

pageState.disabled = true
pageState.disabledReason = "page_pending"
tableView:setRows(source)
local blockedResult, blockedReason = tableView:setChildPage("parent", 4)
T.eq(blockedResult, nil, "pending external page does not emit a second request")
T.eq(blockedReason, "page_pending", "pending external page exposes the adapter reason")
T.eq(#requested, 1, "pending external page preserves the single emitted request")

tableView:dispose()

return true
