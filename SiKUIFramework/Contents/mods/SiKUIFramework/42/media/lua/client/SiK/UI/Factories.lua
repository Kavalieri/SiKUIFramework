require "SiK/UI/Namespace"
require "SiK/UI/Builder"
require "SiK/UI/Bindings"
require "SiK/UI/Window"
require "SiK/UI/Modal"
require "SiK/UI/Scroll"
require "SiK/UI/VirtualList"
require "SiK/UI/Table"
require "SiK/UI/Block"
require "SiK/UI/Form"
require "SiK/UI/Card"
require "SiK/UI/CardCollection"
require "SiK/UI/Container"
require "SiK/UI/Collection"
require "SiK/UI/ActionGroup"
require "SiK/UI/Navigation"
require "SiK/UI/Tooltip"
require "SiK/UI/Menu"
require "SiK/UI/Drag"
require "SiK/UI/DragGhost"
require "SiK/UI/Controls"
require "SiK/UI/Tabs"

local Factories = SiK.UI.Factories or {}
SiK.UI.Namespace.define("Factories", Factories)

local function n(value, fallback)
	value = tonumber(value)
	if value == nil or value ~= value then return fallback end
	return value
end

local function boundsOptions(parent, props, context)
	local rect = props.bounds or {}
	return {
		parent = parent, x = n(rect.x, 0), y = n(rect.y, 0),
		w = math.max(1, n(rect.w, 1)), h = math.max(1, n(rect.h, 1)),
		playerNum = context.playerNum, profile = context.profileId,
		environment = context.environment, theme = context.theme,
		payload = props.data,
	}
end

local function removePanel(parent, panel)
	if not panel then return end
	if parent and parent.removeChild then parent:removeChild(panel) end
	if panel.removeFromUIManager then panel:removeFromUIManager() end
end

local function emit(props, eventId, payload)
	local result, reason = SiK.UI.Bindings.emit(props.actionTarget, eventId, payload)
	if reason == "event_unbound" then return true end
	return result, reason
end

local function windowFactory(_, props, context)
	local options = boundsOptions(nil, props, context)
	local chrome = props.capabilities["window.chrome"] or {}
	local modal = props.capabilities["window.modal"] or {}
	options.title = props.title or ""
	options.resizable = props.resizable ~= false and chrome["resize-grip"] ~= false
	options.closable = modal.dismissible ~= false
	options.closeOnEscape = modal.escape ~= false
	options.headerContext = chrome["header-context"]
	options.headerStatus = chrome["header-status"]
	options.headerOperation = chrome["header-operation"]
	options.headerSeparator = chrome["header-separator"]
	options.footerItems = chrome["footer-items"]
	options.footerAlign = chrome["footer-align"]
	options.footerHeight = chrome["footer-visible"] == false and 0 or n(props.footerHeight, nil)
	options.onClose = function(payload) return emit(props, "cancel", payload) end
        if chrome["header-visible"] == false then
                options.headerHeight, options.title = 1, ""
                options.headerContext, options.headerStatus = nil, nil
        end
        options.header = { productName = options.title,
                contextName = options.headerContext, status = options.headerStatus,
                separator = options.headerSeparator,
                close = { visible = options.closable } }
        options.footer = { versions = options.footerItems,
                align = options.footerAlign,
                visible = chrome["footer-visible"] ~= false }
        if modal.enabled == true then
		options.kind = props.variant == "task" and "task" or "compact"
		options.contentHeight = math.max(0, n(props.contentHeight, options.h))
		return SiK.UI.Modal.create(options)
	end
	return SiK.UI.Window.create(options)
end

local function containerFactory(parent, props, context)
	local options = boundsOptions(parent, props, context)
	local layout = props.layout or {}
	options.direction = layout.direction or props.direction or "column"
	options.padding = layout.padding or props.padding
	options.gap = layout.gap or props.gap
	options.align = layout["align-x"] or layout.align or props.align
	options.verticalAlign = layout["align-y"] or layout["vertical-align"]
		or props.verticalAlign
	options.justify = layout.justify or props.justify
	options.overflow = props.overflow or layout.overflow or "clip"
	options.contentHeight = n(props.contentHeight, options.h)
	local navigation = props.capabilities["container.navigation"]
	if type(navigation) == "table" and navigation.enabled ~= false then
		options.navigation = {
			placement = navigation.placement, activeKey = navigation["active-key"],
			extent = navigation.extent, contentGap = navigation["content-gap"],
			itemExtent = navigation["item-extent"], iconSize = navigation["icon-size"],
			iconFit = navigation["icon-fit"], iconPadding = navigation["icon-padding"],
			iconOnly = navigation["icon-only"], tooltipMode = navigation["tooltip-mode"],
			selectionStyle = navigation["selection-style"], items = props.options,
			onActivate = function(payload) return emit(props, "change", payload) end,
		}
	end
	return SiK.UI.Container.create(options)
end

local function collectionFactory(parent, props, context)
	local options = boundsOptions(parent, props, context)
	local runtime = context.collectionOptions and context.collectionOptions[props.nodeId] or {}
	for key, value in pairs(runtime) do
		if key ~= "parent" and key ~= "bounds" then options[key] = value end
	end
	options.items = props.data or props.items or {}
	options.gap = props.layout and props.layout.gap
	options.minItemWidth = props.minItemWidth
	options.maxColumns = props.maxColumns
	options.columns = props.layout and props.layout.columns or props.columns
	options.exactColumns = props.exactColumns == true
	if type(options.itemFactory) ~= "function" then return nil, "collection_item_factory_required" end
	return SiK.UI.Collection.create(options)
end

local function actionGroupFactory(parent, props, context)
	local options = boundsOptions(parent, props, context)
	local layout = props.layout or {}
	options.mode = props.mode or layout.mode or "content"
	options.direction = layout.direction or props.direction or "row"
	options.padding, options.gap = layout.padding or props.padding, layout.gap or props.gap
	options.align = layout["align-x"] or layout.align or props.align
	options.verticalAlign = layout["align-y"] or layout["vertical-align"]
	options.justify = layout.justify or props.justify
	return SiK.UI.ActionGroup.create(options)
end

local function scrollFactory(parent, props, context)
	local options = boundsOptions(parent, props, context)
	options.viewportRect = { x = options.x, y = options.y, w = options.w, h = options.h }
	options.contentHeight = n(props.contentHeight, options.h)
	local instance, err = SiK.UI.Scroll.create(options)
	if not instance then return nil, err end
	instance.panel, instance.childParent, instance.actionTarget = instance.viewport, instance.host, instance.viewport
	return instance
end

local function virtualListFactory(parent, props, context)
	local options = boundsOptions(parent, props, context)
	options.data = props.data or {}
	options.rowHeight = props.rowHeight
	options.keyOf = context.keyOf and context.keyOf[props.nodeId]
	options.createRow = context.createRow and context.createRow[props.nodeId]
	options.updateRow = context.updateRow and context.updateRow[props.nodeId]
	options.onSelect = function(payload) return emit(props, "change", payload) end
	options.onActivate = function(payload) return emit(props, "activate", payload) end
	local instance, err = SiK.UI.VirtualList.create(options)
	if not instance then return nil, err end
	instance.panel, instance.actionTarget = instance.scroll.viewport, instance.scroll.viewport
	return instance
end

local function tableModel(data)
        if type(data) == "table" and type(data.rows) == "table" then return data end
        return { rows = type(data) == "table" and data or {} }
end

local function isInsideBlockContent(parent)
	local current = parent
	local depth = 0
	while type(current) == "table" and depth < 64 do
		-- Block used to expose a second physical `blockContent` panel.  The
		-- canonical hierarchy now mounts children directly in the Block panel,
		-- so that panel itself is the containing boundary.  Keep the legacy
		-- markers only for consumers that have not remounted yet.
		if current._sikUiComponent == "block"
			or current._sikUiComponent == "blockContent"
			or current._sikUiBlockContent == true then
			return true
		end
		current = current.parent
		depth = depth + 1
	end
	return false
end

local function tableFactory(parent, props, context)
	local options = boundsOptions(parent, props, context)
	-- A declarative Block is the table's sole visual container.  Keep Table's
	-- header/rows/scroll lifecycle without painting another frame or padding.
	-- Layout wrappers may sit between both, so resolve the established parent
	-- chain instead of assuming that the immediate parent is the Block host.
	options.embedded = isInsideBlockContent(parent)
	-- Runtime adapters are product-owned behaviour injected into the neutral
	-- Table widget. They may configure row rendering, exact identity,
	-- expansion and selection, but never replace the declarative parent,
	-- geometry, columns or data owned by the surface specification.
	local runtimeOptions = context.tableOptions and context.tableOptions[props.nodeId]
	if type(runtimeOptions) == "table" then
		for key, value in pairs(runtimeOptions) do
			if key ~= "parent" and key ~= "x" and key ~= "y"
				and key ~= "w" and key ~= "h" and key ~= "width"
				and key ~= "height" and key ~= "columns" and key ~= "rows" then
				options[key] = value
			end
		end
	end
        local model = tableModel(props.data)
        options.columns = props.columns
        options.rows = model.rows
        if model.emptyText ~= nil then options.emptyText = model.emptyText end
        if model.sortKey ~= nil then options.sortKey = model.sortKey end
        if model.sortAsc ~= nil then options.sortAsc = model.sortAsc end
	options.keyOf = options.keyOf or function(item, index)
                if type(item) == "table" and item.id ~= nil then return item.id end
                return index
        end
        options.title = props.title
	options.onSelect = function(payload) return emit(props, "change", payload) end
	options.onRowClick = function(payload) return emit(props, "activate", payload) end
	local expandable = props.capabilities["table.expandable"]
	if not options.expansion and expandable and expandable.expandable then
		options.expansion = {
			childrenOf = function(item) return type(item) == "table" and item.children or {} end,
			keyOf = function(item, index, owner)
				if type(item) == "table" and item.id ~= nil then return item.id end
				return tostring(type(owner) == "table" and owner.id or "row") .. ":" .. index
			end,
		}
	end
	local pagination = props.capabilities["table.pagination"]
	if pagination then
		options.pagination = options.pagination or {}
		options.pagination.pageSize = pagination["page-size"]
	end
        local instance, err = SiK.UI.Table.create(options)
        if not instance then return nil, err end
        if type(model.expanded) == "table" then instance.expanded = model.expanded end
        if type(model.selectedKeys) == "table" then instance:setSelectedKeys(model.selectedKeys) end
        if model.scrollOffset ~= nil then instance:setScrollOffset(model.scrollOffset) end
		instance.panel, instance.actionTarget = instance.root.panel, instance.list
        return instance
end

local function blockFactory(parent, props, context)
	local options = boundsOptions(parent, props, context)
	local headerCapability = props.capabilities["block.header"] or {}
	local headerActions = type(headerCapability.actions) == "table"
		and headerCapability.actions or {}
	-- A declarative Block must reach the runtime primitive without losing its
	-- visual contract.  Rebuilding a second header here used to discard the
	-- variant/frame/padding and reserve the title twice, which made every
	-- product surface look like an unframed vanilla panel.
		-- Declarative product surfaces consume the SiK UI standard. Visual and
		-- spacing overrides remain available only to direct framework consumers;
		-- generated product descriptors cannot compensate geometry per screen.
		options.variant = "standard"
		options.title = props.title
		options.tooltip = props.help or props.tooltip
	options.info = options.tooltip and headerCapability["info-visible"] ~= false
		and { tooltip = options.tooltip } or nil
	options.actions = headerActions
		options.scrollable = props.scrollable == true
	options.fill = props.variant == "fill" or props.fill == true
	options.contentHeight = n(props.contentHeight, 0)
	options.onActivate = function(payload) return emit(props, "activate", payload) end
	local instance, err = SiK.UI.Block.create(options)
	if not instance then return nil, err end
	instance.actionTarget = instance.panel
	instance.headerControl = instance.header
	if props.scrollable then
		local scroll, scrollErr = SiK.UI.Scroll.create({ parent = instance.panel,
			viewportRect = instance:getContentRect(), trackRect = instance:getTrackRect(),
			contentHeight = options.contentHeight, playerNum = context.playerNum })
		if not scroll then instance:dispose(); return nil, scrollErr end
		instance:attachScroll(scroll, true)
		instance.childParent = scroll.host
	end
	-- Builder may insert children through either the direct Block content host
	-- or the host owned by its Scroll. Preserve the semantic parent in both
	-- cases so nested Table/List controls do not create a second visual frame.
	if instance.childParent then
		instance.childParent._sikUiBlockContent = true
		instance.childParent._sikUiBlock = instance
	end
	local disposeBlock = instance.dispose
	function instance:dispose()
		if self._sikFactoryDisposed then return false end
		self._sikFactoryDisposed = true
		-- Block owns its canonical header lifecycle.  This alias exists only for
		-- consumers migrating from the previous factory contract.
		self.headerControl = nil
		disposeBlock(self)
		return true
	end
	return instance
end

local function formFactory(parent, props, context)
	local options = boundsOptions(parent, props, context)
	options.variant = props.variant
	local fields = props.capabilities["form.fields"]
	options.fields = fields and fields.fields or props.fields or {}
	local actions = fields and fields.actions or props.actions
	if type(actions) == "table" and actions[1] then options.submit = actions[1] end
	options.onChange = function(payload) return emit(props, "change", payload) end
	options.onSubmit = function(payload) return emit(props, "submit", payload) end
	local instance, err = SiK.UI.Form.create(options)
	if not instance then return nil, err end
	if fields or props.fields then instance.ownsChildren = true end
	instance.actionTarget = instance
	return instance
end

local function cardFactory(parent, props, context)
	local options = boundsOptions(parent, props, context)
	options.title, options.payload = props.title, props.data
	options.tooltip = props.help or props.tooltip
	options.contentHeight = n(props.contentHeight, options.h)
	local actions = props.capabilities["card.actions"]
	if actions and type(actions.actions) == "table" then
		options.actions = actions.actions
	end
	options.onActivate = function(payload) return emit(props, "activate", payload) end
	return SiK.UI.Card.create(options)
end

local function cardCollectionFactory(parent, props, context)
	local options = boundsOptions(parent, props, context)
	options.items = {}
	local sourceItems = type(props.items) == "table" and props.items or props.data or {}
	for index = 1, #sourceItems do
		local source = sourceItems[index]
		local item = {}
		for key, value in pairs(source) do item[key] = value end
		local previousAction = source.action
		item.action = function(payload)
			if type(previousAction) == "function" then previousAction(payload) end
			return emit(props, "activate", payload or source.payload or source)
		end
		options.items[index] = item
	end
	options.bounds = props.bounds
	options.gap = props.layout and props.layout.gap
	options.minCardWidth = props.minCardWidth
	options.columns = props.columns
	options.maxColumns = props.maxColumns
	options.exactColumns = props.exactColumns == true
	options.cardVariant = props.variant
	return SiK.UI.CardCollection.create(options)
end

local function collectionItems(props)
	local items = props.items
	if type(items) ~= "table" and type(props.data) == "table" then items = props.data end
	local result = {}
	for index = 1, #(items or {}) do
		local source = items[index]
		local item = {}
		for key, value in pairs(source) do item[key] = value end
		local previousAction = source.action
		item.action = function(payload)
			if type(previousAction) == "function" then previousAction(payload) end
			return emit(props, "activate", payload or source.payload or source)
		end
		result[index] = item
	end
	return result
end

local function cardCollectionUpdate(handle, props)
	return handle:setItems(collectionItems(props))
end

local function tooltipFactory(parent, props, context)
	local data = props.data
	local options = { control = parent, playerNum = context.playerNum,
		text = type(data) == "table" and data.text or data }
	local capability = props.capabilities["tooltip.vanilla-chain"]
	if capability and capability.lazy and type(data) == "table" then options.factory = data.factory end
	local handle, err = SiK.UI.Tooltip.attach(options)
	if not handle then return nil, err end
	local previousMove = parent.onMouseMove
	local moveWrapper = function(self, ...)
		local result = previousMove and previousMove(self, ...) or nil
		emit(props, "hover", { control = self })
		return result
	end
	parent.onMouseMove = moveWrapper
	local disposeTooltip = handle.dispose
	function handle:dispose()
		if self._sikFactoryDisposed then return false end
		self._sikFactoryDisposed = true
		if parent.onMouseMove == moveWrapper then parent.onMouseMove = previousMove end
		return disposeTooltip(self)
	end
	return handle
end

local function menuFactory(_, props, context)
	local instance = SiK.UI.Menu.create({ items = props.data or props.options or {},
		playerNum = context.playerNum, payload = props.data })
	local showMenu = instance.show
	function instance:show(x, y, supplied)
		local allowed = emit(props, "contextmenu", { x = x, y = y })
		if allowed == false then return false, "cancelled" end
		return showMenu(self, x, y, supplied)
	end
	return instance
end

local function dragFactory(_, props, context)
        local data = type(props.data) == "table" and props.data or {}
        local ghost = props.capabilities["drag.ghost"]
        local createGhost = data.createGhost
        if type(createGhost) ~= "function" and type(ghost) == "table"
                and type(ghost.rows) == "table" then
                createGhost = function()
                        return SiK.UI.DragGhost.create({ rows = ghost.rows,
                                maxRows = ghost["max-visible"], playerNum = context.playerNum,
                                environment = context.environment })
                end
        end
        return SiK.UI.Drag.begin({ playerNum = context.playerNum, payload = data,
                x = data.x, y = data.y, createGhost = createGhost,
		onBegin = function(payload)
			if type(data.onBegin) == "function" then data.onBegin(payload) end
			return emit(props, "dragstart", payload)
		end,
		onMove = function(payload)
			if type(data.onMove) == "function" then data.onMove(payload) end
			return emit(props, "dragover", payload)
		end,
		onDrop = function(payload)
			if type(data.onDrop) == "function" then data.onDrop(payload) end
			return emit(props, "drop", payload)
		end,
		onCancel = function(payload)
			if type(data.onCancel) == "function" then data.onCancel(payload) end
			return emit(props, "dragcancel", payload)
		end,
                ghost = ghost })
end

local controlKinds = {
	["icon-button"] = "iconButton",
	["section-title"] = "sectionTitle",
	["alert-row"] = "alertRow",
	["header-operation"] = "headerOperation",
	["requirement-row"] = "requirementRow",
}

local function controlPresentation(props)
	local data = props.data
	local result = {
		text = props.label or props.text, payload = nil,
		items = props.items or props.options, selected = props.selected,
		tone = props.tone, color = props.color, indicator = props.indicator,
		value = props.value, label = props.label, enabled = props.enabled,
		status = props.status, mode = props.mode, severity = props.severity,
		glow = props.glow, size = props.size,
		icon = props.icon or props["icon-key"], state = props.state,
		met = props.met, iconSize = props.iconSize or props["icon-size"],
	}
	if type(data) == "table" then
		if data.text ~= nil then result.text = data.text end
		if data.label ~= nil then result.label = data.label end
		if data.items ~= nil then result.items = data.items
		elseif data.options ~= nil then result.items = data.options end
		if data.selected ~= nil then result.selected = data.selected end
		if data.tone ~= nil then result.tone = data.tone end
		if data.color ~= nil then result.color = data.color end
		if data.indicator ~= nil then result.indicator = data.indicator end
		if data.value ~= nil then result.value = data.value end
		if data.status ~= nil then result.status = data.status end
		if data.mode ~= nil then result.mode = data.mode end
		if data.severity ~= nil then result.severity = data.severity end
		if data.glow ~= nil then result.glow = data.glow end
		if data.size ~= nil then result.size = data.size end
		if data.icon ~= nil then result.icon = data.icon
		elseif data.texture ~= nil then result.icon = data.texture end
		if data.state ~= nil then result.state = data.state end
		if data.met ~= nil then result.met = data.met end
		if data.iconSize ~= nil then result.iconSize = data.iconSize end
		if data.enabled ~= nil then result.enabled = data.enabled end
		result.payload = data.payload or data
	elseif data ~= nil then
		if props.kind == "combo" then result.selected = data
		elseif props.kind == "progress" then result.value = data
		else result.text = data end
		result.payload = data
	end
	return result
end

local function controlFactory(parent, props, context)
        local kind = controlKinds[props.kind] or props.kind
        local presentation = controlPresentation(props)
        -- `icon-button` is the compact action primitive.  Its label remains an
        -- accessible tooltip, never visible text competing with the glyph.  A
        -- labelled action uses the regular button primitive instead.
        local text = presentation.text
        local tooltip = props.tooltip
        if kind == "iconButton" then
                tooltip = tooltip or presentation.label or presentation.text
                text = ""
        end
        local fieldAction = kind == "iconButton" and props.variant == "field-action"
        return SiK.UI.Controls.create(kind, { parent = parent, x = props.bounds.x, y = props.bounds.y,
                w = props.bounds.w, h = props.bounds.h, text = text, tooltip = tooltip,
		payload = presentation.payload, icon = presentation.icon, state = presentation.state,
		met = presentation.met, enabled = presentation.enabled,
		iconSize = presentation.iconSize,
                iconFit = props.iconFit or props["icon-fit"] or (fieldAction and "fill" or nil),
				iconPadding = props.iconPadding or props["icon-padding"] or (fieldAction and 4 or nil),
                items = presentation.items, selected = presentation.selected,
		tone = presentation.tone, color = presentation.color, indicator = presentation.indicator,
		value = presentation.value, label = presentation.label, status = presentation.status,
		mode = presentation.mode, severity = presentation.severity, glow = presentation.glow,
		size = presentation.size, playerNum = context.playerNum,
		profile = context.profileId,
		onClick = function(payload) return emit(props, "activate", payload) end,
		onChange = function(payload) return emit(props, "change", payload) end,
		onSubmit = function(payload) return emit(props, "submit", payload) end,
	})
end

local function tabsFactory(parent, props, context)
	local items = {}
	for index = 1, #(props.options or {}) do
		local source = props.options[index]
		items[index] = { key = source.id or source.value or tostring(index),
			text = source.label or source.labelRef or "", tooltip = source.tooltip,
			icon = source.icon, iconOnly = source.iconOnly,
			enabled = source.disabled ~= true, payload = source.value,
			contentId = source.contentId, surfaceRef = source.surfaceRef,
			pin = source.pin, pinned = source.pinned }
	end
	local instance, err = SiK.UI.Navigation.create({ parent = parent,
		placement = props.placement, items = items, activeKey = props.activeKey,
		bounds = props.bounds, extent = props.barSize,
		playerNum = context.playerNum, gap = props.layout and props.layout.gap,
		iconFit = props.iconFit, iconPadding = props.iconPadding,
		iconOnly = props.iconOnly, tooltipMode = props.tooltipMode,
		onActivate = function(payload) return emit(props, "change", payload) end,
	})
	if not instance then return nil, err end
	instance.ownsChildren, instance.actionTarget = true, instance
	return instance
end

local function requireMethods(methods)
	return function(handle)
		for index = 1, #methods do
			if type(handle[methods[index]]) ~= "function" then
				return false, "adoption_missing_method:" .. methods[index]
			end
		end
		return true
	end
end

local function tableCapture(handle)
        return { rows = handle.rows, columns = handle.columns,
                state = handle.captureState and handle:captureState() or nil,
                onSelect = handle.options and handle.options.onSelect or nil,
                onRowClick = handle.options and handle.options.onRowClick or nil }
end

local function tableRestore(handle, snapshot)
	if type(snapshot) ~= "table" then return nil, "invalid_table_snapshot" end
        local ok, reason = handle:setColumns(snapshot.columns)
        if not ok then return nil, reason end
        ok, reason = handle:setRows(snapshot.rows, false)
        if not ok then return nil, reason end
        if handle.options then
                handle.options.onSelect = snapshot.onSelect
                handle.options.onRowClick = snapshot.onRowClick
        end
        if snapshot.state and handle.restoreState then return handle:restoreState(snapshot.state) end
	return handle
end

local function tablePreserve(handle, snapshot)
        if snapshot and snapshot.state then return handle:restoreState(snapshot.state) end
        return handle
end

local function tableUpdate(handle, props)
        if handle.disposed then return nil, "disposed" end
        local model = tableModel(props.data)
        local ok, reason = handle:setColumns(props.columns)
        if not ok then return nil, reason end
	if handle.options then
		handle.options.onSelect = function(payload) return emit(props, "change", payload) end
		handle.options.onRowClick = function(payload) return emit(props, "activate", payload) end
	end
        if model.emptyText ~= nil then handle:setEmptyText(model.emptyText) end
        if model.sortKey ~= nil then handle:setSort(model.sortKey, model.sortAsc) end
        if type(model.expanded) == "table" then handle.expanded = model.expanded end
        ok, reason = handle:setRows(model.rows, true)
        if not ok then return nil, reason end
        if type(model.selectedKeys) == "table" then handle:setSelectedKeys(model.selectedKeys) end
        if model.scrollOffset ~= nil then handle:setScrollOffset(model.scrollOffset) end
        return handle
end

local function tableReflow(handle, bounds)
	return handle:reflow(bounds)
end

local function scrollCapture(handle)
	return { state = handle:captureState(), contentHeight = handle.contentHeight,
		viewportRect = handle:getViewportRect(), trackRect = handle.trackRect }
end

local function scrollRestore(handle, snapshot)
	local ok, reason = handle:setGeometry(snapshot.viewportRect, snapshot.trackRect)
	if not ok then return nil, reason end
	ok, reason = handle:setContentHeight(snapshot.contentHeight)
	if not ok then return nil, reason end
	return handle:restoreState(snapshot.state)
end

local function scrollPreserve(handle, snapshot)
        if snapshot and snapshot.state then return handle:restoreState(snapshot.state) end
        return handle
end

local function scrollUpdate(handle, props)
	return handle:setContentHeight(n(props.contentHeight, props.bounds and props.bounds.h or 0))
end

local function scrollReflow(handle, bounds)
	return handle:reflow(bounds)
end

local function listCapture(handle)
	return { data = handle.data, state = handle:captureState() }
end

local function listRestore(handle, snapshot)
	local ok, reason = handle:setData(snapshot.data, false)
	if not ok then return nil, reason end
	return handle:restoreState(snapshot.state)
end

local function listPreserve(handle, snapshot)
        if snapshot and snapshot.state then return handle:restoreState(snapshot.state) end
        return handle
end

local function listUpdate(handle, props)
	return handle:setData(props.data or {}, true)
end

local function listReflow(handle, bounds)
	return handle:reflow(bounds)
end

local function containerUpdate(handle, props)
	if type(handle.setContentHeight) == "function" then
		return handle:setContentHeight(n(props.contentHeight, props.bounds and props.bounds.h or 0))
	end
	return handle
end

local function blockUpdate(handle, props)
	local ok, reason = handle:setContentHeight(n(props.contentHeight, props.bounds and props.bounds.h or 0))
	if not ok then return nil, reason end
	local header = handle.headerControl
	if header then
		local headerCapability = props.capabilities["block.header"] or {}
		local headerActions = type(headerCapability.actions) == "table"
			and headerCapability.actions or {}
		if header.setName then header:setName(tostring(props.title or ""))
		elseif header.setText then header:setText(tostring(props.title or "")) end
		if header.setActions then header:setActions(headerActions) end
	end
	return handle
end

local function blockReflow(handle, bounds)
        local ok, reason = handle:setBounds(bounds.x, bounds.y, bounds.w, bounds.h)
        if not ok then return nil, reason end
        -- Block:_sync owns the final header rectangle, including the narrower
        -- content width while a scrollbar is visible.  Rewriting it to W-16 here
        -- made headers and actions invade the scrollbar/last table column.
        return handle
end

local function formCapture(handle) return handle:getValues() end
local function formRestore(handle, values)
	for key, value in pairs(values or {}) do handle:setValue(key, value) end
	return handle
end
local function formUpdate(handle, props)
	local values = props.data
	if type(values) ~= "table" then return handle end
	for key, value in pairs(values) do
		if handle.byKey and handle.byKey[key] then handle:setValue(key, value) end
	end
	return handle
end

local function tabsCapture(handle) return { activeKey = handle:getSelectedKey() } end
local function tabsRestore(handle, state)
	if state and state.activeKey and handle.tabs and handle.tabs.byKey[state.activeKey] then
		return handle:setActive(state.activeKey, false)
	end
	return handle
end
local function tabsUpdate(handle, props)
	for index = 1, #(props.options or {}) do
		local option = props.options[index]
		local key = option.id or option.value or tostring(index)
		if handle.tabs and handle.tabs.byKey[key] then
			handle:updateItem(key, { text = option.label or option.labelRef or "",
				tooltip = option.tooltip, enabled = option.disabled ~= true, payload = option.value })
		end
	end
	return handle
end

local function tabsReflow(handle, bounds) return handle:reflow(bounds) end

local function controlUpdate(handle, props)
        local presentation = controlPresentation(props)
        local text = presentation.text
        if handle._sikUiControl == "iconButton" then
                local tooltip = props.tooltip or presentation.label or presentation.text
                if handle.setTitle then handle:setTitle("")
                elseif handle.setName then handle:setName("")
                elseif handle.setText then handle:setText("") end
                if SiK.UI.Controls.setTooltip then SiK.UI.Controls.setTooltip(handle, tooltip) end
                text = nil
        end
	if handle._sikUiControl == "alertRow" and handle.setAlert then
		handle:setAlert(presentation)
	elseif handle.setStatus then handle:setStatus(text, presentation.tone, presentation.color)
	elseif handle.setFeedback then handle:setFeedback(text, presentation.tone)
	elseif handle._sikUiControl == "progress" and handle.setProgress then
		handle:setProgress(presentation)
	elseif text ~= nil then
		if handle.setTitle then handle:setTitle(tostring(text))
		elseif handle.setName then handle:setName(tostring(text))
		elseif handle.setText then handle:setText(tostring(text)) end
	end
	if handle._sikUiControl == "combo" then
		if presentation.items and handle.setItems then
			handle:setItems(presentation.items, presentation.selected)
		end
		if presentation.selected ~= nil and handle.setSelected then
			handle:setSelected(presentation.selected, false)
		elseif presentation.selected ~= nil then handle.selected = presentation.selected end
	elseif presentation.selected ~= nil and handle.setSelected then
		handle:setSelected(presentation.selected, false)
	end
	if presentation.enabled ~= nil then
		if handle.setEnabled then handle:setEnabled(presentation.enabled ~= false)
		elseif handle.setEnable then handle:setEnable(presentation.enabled ~= false) end
	end
	if handle.setData and presentation.payload ~= nil then handle:setData(presentation.payload)
	else handle.payload = presentation.payload end
        return handle
end

local function panelReflow(handle, bounds)
        if handle.setX then handle:setX(bounds.x) else handle.x = bounds.x end
        if handle.setY then handle:setY(bounds.y) else handle.y = bounds.y end
        if handle.setWidth then handle:setWidth(bounds.w) else handle.width = bounds.w end
        if handle.setHeight then handle:setHeight(bounds.h) else handle.height = bounds.h end
        return handle
end

local function windowUpdate(handle, props)
        local chrome = props.capabilities["window.chrome"] or {}
        handle:setHeader({ productName = props.title or "", contextName = chrome["header-context"],
                separator = chrome["header-separator"], status = chrome["header-status"],
                statusVisible = chrome["header-visible"] ~= false })
        handle:setFooterItems(chrome["footer-items"], chrome["footer-align"])
        handle:setFooterVisible(chrome["footer-visible"] ~= false)
        return handle
end

local function windowReflow(handle, bounds)
        panelReflow(handle, bounds)
        if handle.reflow then handle:reflow() end
        return handle
end

local function controlReflow(handle, bounds)
        panelReflow(handle, bounds)
        if handle.reflow then handle:reflow(bounds.w) end
        return handle
end

Factories.definitions = Factories.definitions or {
		window = { runtimeFactory = "SiK.UI.Window.create", create = windowFactory,
		allowedChildren = { "container" }, parents = {},
                update = windowUpdate, reflow = windowReflow,
			validateAdopt = requireMethods({ "setHeader", "setFooterItems", "setFooterVisible", "reflow" }) },
                container = { runtimeFactory = "SiK.UI.Container.create", create = containerFactory,
                allowedChildren = { "container", "scroll", "table", "virtual-list", "block", "form", "card", "card-collection", "collection", "action-group", "control" },
                parents = { "window", "container", "scroll", "block", "tabs" },
				update = containerUpdate, reflow = function(handle, bounds) return handle:reflow(bounds) end,
			validateAdopt = requireMethods({ "add", "contentRect", "reflow" }) },
		collection = { runtimeFactory = "SiK.UI.Collection.create", create = collectionFactory,
		allowedChildren = {}, parents = { "container", "block" },
			update = function(handle, props) return handle:setItems(props.data or props.items or {}) end,
			reflow = function(handle, bounds) return handle:reflow(bounds) end,
			validateAdopt = requireMethods({ "setItems", "reflow" }) },
		["action-group"] = { runtimeFactory = "SiK.UI.ActionGroup.create", create = actionGroupFactory,
		allowedChildren = { "control" }, parents = { "container", "block" },
			reflow = function(handle, bounds) return handle:reflow(bounds) end,
			validateAdopt = requireMethods({ "add", "reflow" }) },
        scroll = { runtimeFactory = "SiK.UI.Scroll.create", create = scrollFactory,
		allowedChildren = { "container" }, parents = { "container", "block" },
                capture = scrollCapture, restore = scrollRestore, update = scrollUpdate,
                preserve = scrollPreserve, reflow = scrollReflow,
                validateAdopt = requireMethods({ "setGeometry", "reflow", "setContentHeight", "captureState" }) },
        ["virtual-list"] = { runtimeFactory = "SiK.UI.VirtualList.create", create = virtualListFactory,
		allowedChildren = {}, parents = { "container", "block" },
                capture = listCapture, restore = listRestore, update = listUpdate,
                preserve = listPreserve, reflow = listReflow,
                validateAdopt = requireMethods({ "setData", "captureState", "refresh", "reflow" }) },
        table = { runtimeFactory = "SiK.UI.Table.create", create = tableFactory,
		allowedChildren = {}, parents = { "container", "block" },
                capture = tableCapture, restore = tableRestore, update = tableUpdate,
                preserve = tablePreserve, reflow = tableReflow,
                validateAdopt = requireMethods({ "setRows", "setColumns", "captureState", "restoreState", "reflow" }) },
        block = { runtimeFactory = "SiK.UI.Block.create", create = blockFactory,
		allowedChildren = { "container", "scroll", "table", "virtual-list", "form", "card", "card-collection", "collection", "action-group", "control" },
		parents = { "container" },
		update = blockUpdate, reflow = blockReflow,
		validateAdopt = requireMethods({ "setBounds", "reflow", "setContentHeight", "getContentRect" }) },
        form = { runtimeFactory = "SiK.UI.Form.create", create = formFactory,
		allowedChildren = { "control" }, parents = { "container", "block" },
		capture = formCapture, restore = formRestore, update = formUpdate,
		reflow = function(handle, bounds) return handle:reflow(bounds) end,
		validateAdopt = requireMethods({ "getValues", "setValue", "reflow" }) },
	card = { runtimeFactory = "SiK.UI.Card.create", create = cardFactory,
		allowedChildren = {}, parents = { "container", "block", "card-collection" },
		reflow = function(handle, bounds) return handle:reflow(bounds) end,
		validateAdopt = requireMethods({ "reflow", "dispose" }) },
	["card-collection"] = { runtimeFactory = "SiK.UI.CardCollection.create", create = cardCollectionFactory,
		allowedChildren = { "card" }, parents = { "container", "block" },
		update = cardCollectionUpdate,
		reflow = function(handle, bounds) return handle:reflow(bounds) end,
		validateAdopt = requireMethods({ "setItems", "reflow", "dispose" }) },
        tooltip = { runtimeFactory = "SiK.UI.Tooltip.attach", create = tooltipFactory,
		allowedChildren = {}, parents = {} },
        menu = { runtimeFactory = "SiK.UI.Menu.create", create = menuFactory,
		allowedChildren = {}, parents = {} },
        drag = { runtimeFactory = "SiK.UI.Drag.begin", create = dragFactory,
		allowedChildren = {}, parents = {} },
        control = { runtimeFactory = "SiK.UI.Controls.create", create = controlFactory,
		allowedChildren = {}, parents = { "container", "block", "form", "action-group" },
                update = controlUpdate, reflow = controlReflow },
		tabs = { runtimeFactory = "SiK.UI.Navigation.create", create = tabsFactory,
		allowedChildren = { "container" }, parents = {},
                capture = tabsCapture, restore = tabsRestore, preserve = tabsRestore,
                update = tabsUpdate, reflow = tabsReflow,
		validateAdopt = requireMethods({ "getSelectedKey", "setActive", "reflow" }) },
}

function Factories.registerDefaults()
	for typeId, definition in pairs(Factories.definitions) do
		local ok, err = SiK.UI.Builder.register(typeId, definition.create, {
			runtimeFactory = definition.runtimeFactory,
                        capture = definition.capture, restore = definition.restore,
                        preserve = definition.preserve, update = definition.update, reflow = definition.reflow,
			validateAdopt = definition.validateAdopt,
			allowedChildren = definition.allowedChildren,
			parents = definition.parents,
		})
		if not ok then return nil, err end
	end
	return true
end

return Factories
