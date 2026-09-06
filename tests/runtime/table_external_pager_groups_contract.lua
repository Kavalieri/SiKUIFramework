-- Dynamic external child-pager contract: two independent expanded groups.
local T = require "tests/geometry/pz_ui_stub"
local Table = require "SiK/UI/Table"
local Block = require "SiK/UI/Block"

local parent = T.panel(720, 420)
local a = { id = "A", children = {{ id = "A3" }, { id = "A4" }} }
local b = { id = "B", children = {{ id = "B1" }, { id = "B2" }} }
local rows = { a, b }
local states = {
    A = { totalRows = 4, totalUnits = 7, page = 1, pageSize = 2 },
    B = { totalRows = 3, totalUnits = 5, page = 1, pageSize = 2 },
}
local requests = {}
local tickAdds = 0
_G.Events = { OnTick = { Add = function() tickAdds = tickAdds + 1 end } }

local block = assert(Block.create({ parent = parent, w = 500, h = 260, scrollable = true }))
local view = assert(Table.create({
    parent = block.panel, w = 500, h = 260, embedded = true,
    columns = {{ key = "id", title = "ID", flex = 1 }, { key = "kind", title = "Kind", width = 80 }}, rows = rows,
    keyOf = function(item) return item.id end,
    expansion = {
        childrenOf = function(item) return item.children end,
        keyOf = function(item) return item.id end,
    },
    pagination = {
        pageSize = 2, external = true,
        stateOf = function(_, key) return states[key] end,
        onPageChange = function(context) requests[#requests + 1] = context; return "requested" end,
    },
}))

view:toggleExpanded("A")
local stateA = assert(view:getPageState("A"))
T.eq(stateA.pageCount, 2, "A page count uses child rows, not physical units")
T.eq(stateA.first, 1, "A first row is one-based")
T.eq(stateA.last, 2, "A last row is page-size bounded")
local pagerA
for _, projected in ipairs(view.projectedRows) do
    if projected.kind == "pager" then pagerA = projected end
end
assert(pagerA, "expanded A projects a pager row")
T.eq(pagerA.parentKey, "A", "pager belongs to A")
T.eq(pagerA.data, nil, "pager has no selectable data object")
T.eq(#view.projectedRows, 5, "A projects parent, children, pager and B parent")

local scrollBefore = view:getScrollOffset()
T.eq(view:setChildPage("A", 2), "requested", "A page change calls the external adapter")
T.eq(#requests, 1, "A emits exactly one callback")
T.eq(requests[1].parentKey, "A", "A callback carries its parent key")
T.eq(requests[1].component, view, "callback carries the table component")
T.eq(requests[1].page, 2, "A callback carries the requested page")
T.eq(view:getScrollOffset(), scrollBefore, "external request preserves scroll offset")

states.A.page = 2
a.children = {{ id = "A5" }, { id = "A6" }}
view:setRows(rows)
stateA = assert(view:getPageState("A"))
T.eq(stateA.page, 2, "A remains on its returned last page")
T.eq(stateA.first, 3, "A logical first row counts rows, not units")
T.eq(stateA.last, 4, "A logical last row has no off-by-one")

view:toggleExpanded("B")
local stateB = assert(view:getPageState("B"))
T.eq(stateB.page, 1, "B starts independently on page one")
T.eq(stateB.totalRows, 3, "B has its own row total")
T.eq(stateB.totalUnits, 5, "B has its own physical-unit total")
T.eq(view.activePageParentKey, "B", "active pager follows the expanded group")
T.eq(view:setChildPage("B", 2), "requested", "B page change calls the external adapter")
T.eq(#requests, 2, "B does not reuse A callback")
T.eq(requests[2].parentKey, "B", "B callback is correlated independently")

states.B.pending = true
states.B.disabled = true
states.B.disabledReason = "page_pending"
view:setRows(rows)
T.eq(view:setChildPage("B", 1), nil, "pending B page does not issue another request")
T.eq(#requests, 2, "pending state deduplicates the callback")
states.B.disabledReason = "page_stale"
view:setRows(rows)
T.eq(view:setChildPage("B", 1), nil, "stale B page remains blocked until refreshed")
T.eq(#requests, 2, "stale state does not issue a speculative request")

states.B.disabled = false
states.B.disabledReason = nil
states.B.page = 2
b.children = {{ id = "B3" }}
view:setRows(rows)

local function hasPager(parentKey)
    for _, projected in ipairs(view.projectedRows) do
        if projected.kind == "pager" and projected.parentKey == parentKey then return true end
    end
    return false
end
view:toggleExpanded("B")
T.eq(hasPager("B"), false, "collapsing B hides its pager")
view:toggleExpanded("B")
T.eq(hasPager("B"), true, "reopening B restores its pager")
T.eq(view:getPageState("A").page, 2, "collapsing/reopening B preserves A state")
T.eq(view:getPageState("B").page, 2, "collapsing/reopening B preserves B state")

for _, row in ipairs(view.projectedRows) do
    if row.kind == "pager" then
        T.eq(row.sourceIndex, 0, "pager is not a source row")
        T.eq(row.semantic, nil, "pager has no selection/drag/tooltip semantic")
    end
end
T.eq(tickAdds, 0, "external paging does not install an OnTick hook")
view:dispose()
return true
