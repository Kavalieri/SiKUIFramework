local T = require "tests/geometry/pz_ui_stub"
local Table = require "SiK/UI/Table"
local Block = require "SiK/UI/Block"

local function createTable(options)
	local block = assert(Block.create({ parent = options.parent,
		w = options.w, h = options.h, scrollable = true }))
	options.parent = block.panel
	options.embedded = true
	return assert(Table.create(options))
end

local children = {}
for index = 1, 5 do
	children[index] = { id = "c" .. index, name = "Child " .. index, count = index }
end
local parent = { id = "p", name = "Parent", count = 5, children = children }
local actions = {}

local view = createTable({
	parent = T.panel(600, 400), w = 480, h = 220,
	columns = {
		{ key = "name", title = "Name", flex = 1 },
		{ key = "count", title = "Count", width = 70, align = "right" },
	},
	rows = { parent }, keyOf = function(item) return item.id end,
	expansion = {
		childrenOf = function(item) return item.children end,
		keyOf = function(item) return item.id end,
	},
	pagination = { pageSize = 2 },
	onRowClick = function(context) actions[#actions + 1] = context end,
})

T.eq(#view.projectedRows, 1, "collapsed projection contains parent only")
view.list.pool[1]:onMouseUp(80, 4)
T.eq(actions[1].kind, "parent", "collapsed action is parent semantic action")
local stableParentSelection = actions[1].selection

view:toggleExpanded("p")
T.eq(#view.projectedRows, 4, "page one shows parent, two children, and structural pager")
T.eq(view.projectedRows[4].kind, "pager", "page one pager is structural")
T.eq(view.projectedRows[4].data, nil, "page one pager has no selectable data")
T.eq(view:getPageState("p").pageCount, 3, "five children produce N pages")
view.list.pool[1]:onMouseUp(80, 4)
T.eq(actions[2].selection, stableParentSelection, "parent payload identity survives expansion")
T.eq(actions[2].item, parent, "parent action retains source item")

view:setChildPage("p", 2)
T.eq(#view.projectedRows, 4, "page two shows parent, two children, and structural pager")
T.eq(view.projectedRows[2].key, "c3", "page two begins at exact child")
T.eq(view.projectedRows[4].kind, "pager", "page two pager remains structural")
view:layout({ w = 520, rows = { parent } })
T.eq(view:getPageState("p").page, 2, "row reflow preserves child pagination")
view:setPage(3)
T.eq(#view.projectedRows, 3, "last page shows parent, final child, and structural pager")
T.eq(view.projectedRows[2].key, "c5", "last page keeps exact child")
T.eq(view.projectedRows[3].kind, "pager", "last page pager remains structural")
T.eq(#children, 5, "visual projection never mutates complete children")
T.eq(#view:getChildren("p"), 5, "complete child snapshot remains available")

local selected = assert(view:selectChild("p", "c2"))
T.eq(selected.kind, "child", "explicit child selection stays exact")
T.eq(selected.parentKey, "p", "child selection retains parent identity")
T.eq(selected.item, children[2], "child selection retains exact source item")
T.eq(view:getSelectedKey(), "c2", "selected key is semantic, not visible page index")
view:setChildPage("p", 1)
T.eq(view:getSemanticSelection(), selected, "selection survives page projection")
local saved = view:captureState()
view:selectParent("p")
view:restoreState(saved)
T.eq(view:getSemanticSelection().item, children[2], "child selection roundtrip remains exact")

view:toggleExpanded("p")
T.eq(view:getSemanticSelection(), selected, "child selection survives collapse")
view.list.pool[1]:onMouseUp(80, 4)
T.eq(actions[3].selection, stableParentSelection, "parent action payload is stable after repagination")

view:dispose()

local onePage = createTable({
	parent = T.panel(400, 240), w = 320, h = 160,
	columns = {
		{ key = "name", title = "Name", flex = 1 },
		{ key = "count", title = "Count", width = 60 },
	},
	rows = { { id = "one", name = "One", count = 1,
		children = { { id = "only", name = "Only child", count = 1 } } } },
	keyOf = function(item) return item.id end,
	expansion = {
		childrenOf = function(item) return item.children end,
		keyOf = function(item) return item.id end,
	},
	pagination = { pageSize = 2 },
})
T.eq(onePage:getPageState("one").pageCount, 1, "single child remains one visual page")
onePage:dispose()
return true
