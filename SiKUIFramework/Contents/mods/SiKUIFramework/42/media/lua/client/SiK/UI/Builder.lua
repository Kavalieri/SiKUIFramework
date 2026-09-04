require "SiK/UI/Namespace"
require "SiK/UI/Surface"
require "SiK/UI/Bindings"
require "SiK/UI/Capabilities"
require "SiK/UI/Viewport"
require "SiK/UI/Layout"
require "SiK/UI/Container"
require "SiK/UI/Controls"

local Builder = SiK.UI.Builder or {}
SiK.UI.Namespace.define("Builder", Builder)

local factories = Builder._factories or {}
Builder._factories = factories
local factoryContracts = Builder._factoryContracts or {}
Builder._factoryContracts = factoryContracts

local function n(value, fallback)
	value = tonumber(value)
	if value == nil or value ~= value then return fallback end
	return value
end

local function lookup(source, path)
	if type(source) ~= "table" or type(path) ~= "string" then return nil end
	if source[path] ~= nil then return source[path] end
	local value = source
	for part in string.gmatch(path, "[^.]+") do
		if type(value) ~= "table" then return nil end
		value = value[part]
	end
	return value
end

function Builder.resolve(value, context)
	if type(value) ~= "table" or type(value.kind) ~= "string" then return value end
	context = context or {}
	if value.kind == "literal" then return value.value end
	if value.kind == "data" then return lookup(context.data, value.path) end
	if value.kind == "state" then return lookup(context.state, value.path) end
	if value.kind == "asset" then return lookup(context.assets, value.ref) end
	if value.kind == "token" then return lookup(context.tokens, value.ref) end
	if value.kind == "i18n" then
		local fallback = lookup(context.i18n, value.ref)
		return SiK.UI.resolveText(value.ref, fallback)
	end
	return nil
end

function Builder.resolveSurface(reference, context)
	if type(reference) ~= "table" or type(context) ~= "table" then
		return nil, "invalid_surface_reference_context"
	end
	local artifact, err
	if type(context.surfaceResolver) == "function" then
		artifact, err = context.surfaceResolver(reference, context)
	elseif type(context.surfaces) == "table" then
		artifact = context.surfaces[reference.id]
	end
	if type(artifact) ~= "table" then
		return nil, err or ("surface_reference_unavailable:" .. tostring(reference.id))
	end
	return artifact
end

local function copy(source)
	local out = {}
	for key, value in pairs(source or {}) do out[key] = value end
	return out
end

local function replace(target, source)
	for key, _ in pairs(target or {}) do target[key] = nil end
	for key, value in pairs(source or {}) do target[key] = value end
	return target
end

local function merged(base, patch)
	local result = copy(base)
	for key, value in pairs(patch or {}) do result[key] = value end
	return result
end

local function sameValue(left, right, seen)
	if left == right then return true end
	if type(left) ~= type(right) or type(left) ~= "table" then return false end
	seen = seen or {}
	if seen[left] == right then return true end
	seen[left] = right
	for key, value in pairs(left) do
		if not sameValue(value, right[key], seen) then return false end
	end
	for key, _ in pairs(right) do
		if left[key] == nil then return false end
	end
	return true
end

local function indexedValues(values, field, transform)
	local result = {}
	for index = 1, #(values or {}) do
		local entry = values[index]
		result[entry[field]] = transform and transform(entry) or entry
	end
	return result
end

local function translation(entry, locale)
	local first = entry.translations and entry.translations[1]
	for index = 1, #(entry.translations or {}) do
		local candidate = entry.translations[index]
		if candidate.locale == locale then return candidate.text end
	end
	return first and first.text or entry.id
end

local function parentRect(parent, context)
        if type(context.viewport) == "table" then
                -- A surface is always built inside `parent`.  Viewport x/y are
                -- screen coordinates used to select a responsive profile, not
                -- coordinates that can be applied again to a child of that parent.
                -- Keeping them here applied the shell/tab offset twice at runtime.
                return { x = 0, y = 0,
                        w = math.max(1, n(context.viewport.w or context.viewport.width, 1)),
                        h = math.max(1, n(context.viewport.h or context.viewport.height, 1)) }
	end
	local width = type(parent) == "table" and n(parent.width,
		parent.getWidth and parent:getWidth() or nil) or nil
	local height = type(parent) == "table" and n(parent.height,
		parent.getHeight and parent:getHeight() or nil) or nil
	if width and height and width > 0 and height > 0 then
		return { x = 0, y = 0, w = width, h = height }
	end
	return SiK.UI.Viewport.resolve(context.playerNum, context.environment)
end

local function selectProfile(spec, context, viewport)
	local byId = indexedValues(spec.profiles, "id")
	if context.profile and byId[context.profile] then return context.profile end
	local selected, score = nil, -1
	for index = 1, #spec.profiles do
		local profile = spec.profiles[index]
		local minW, minH = n(profile.minViewportWidth, 0), n(profile.minViewportHeight, 0)
		if viewport.w >= minW and viewport.h >= minH then
			local nextScore = minW * 100000 + minH
			if nextScore > score or (nextScore == score and profile.id < selected) then
				selected, score = profile.id, nextScore
			end
		end
	end
	return selected or (spec.profiles[1] and spec.profiles[1].id)
end

local function runtimeContext(parent, spec, source)
	local context = copy(source)
	context.playerNum = math.max(0, math.floor(n(context.playerNum, 0)))
	context.data = context.data or {}
	context.state = context.state or {}
	context.conditions = copy(source.conditions)
	context.viewport = parentRect(parent, context)
	context.profileId = selectProfile(spec, context, context.viewport)
	context.tokens = indexedValues(spec.tokens, "id", function(entry) return entry.value end)
	local declaredI18n = indexedValues(spec.i18n, "id", function(entry)
		return translation(entry, context.locale or "es")
	end)
	-- El consumidor puede proporcionar las cadenas runtime ya resueltas por su
	-- propio sistema de localizacion. La especificacion conserva un fallback
	-- visual, pero nunca obliga a que un producto externo adopte ese idioma.
	for id, value in pairs(source.i18n or {}) do declaredI18n[id] = value end
	context.i18n = declaredI18n
	context.assetOverrides = copy(source.assetOverrides or source.assets)
	local declaredAssets = indexedValues(spec.assets, "id", function(entry) return entry.path end)
	for id, value in pairs(context.assetOverrides) do declaredAssets[id] = value end
	context.assets = declaredAssets
	context.actions = context.actions or {}
	context.surfaceId = spec.surface.id
	context.surfaceReferenceIndex = indexedValues(spec.surfaceReferences, "id")
	context.surfaceStack = copy(source.surfaceStack)
	return context
end

local function visibilityCondition(node)
	local visual = type(node) == "table" and node.visual or nil
	if type(visual) ~= "table" then return nil end
	return visual.visibleWhen
end

local function nodeVisible(node, context)
	local conditionId = visibilityCondition(node)
	if conditionId == nil then return true end
	if type(conditionId) ~= "string" or conditionId == "" then
		return nil, "condition_invalid_id:" .. tostring(node and node.id)
	end
	local value = context.conditions and context.conditions[conditionId]
	if value == nil then return nil, "condition_unavailable:" .. conditionId end
	if type(value) ~= "boolean" then return nil, "condition_invalid_type:" .. conditionId end
	return value
end

local function validateConditions(node, context)
	local visible, reason = nodeVisible(node, context)
	if visible == nil then return nil, reason end
	for index = 1, #(node.children or {}) do
		local ok, childReason = validateConditions(node.children[index], context)
		if not ok then return nil, childReason end
	end
	return true
end

local function layoutValues(node, context)
	local result = {}
	local function apply(values)
		for index = 1, #(values or {}) do
			local binding = values[index]
			result[binding.name] = Builder.resolve(binding.value, context)
		end
	end
	apply(node.layout.base)
	for index = 1, #(node.layout.overrides or {}) do
		local override = node.layout.overrides[index]
		if override.profileId == context.profileId then apply(override.bindings) end
	end
	result.mode = node.layout.mode
	return result
end

local function clampSize(value, minimum, maximum)
	value = math.max(1, n(value, 1))
	if minimum ~= nil then value = math.max(value, n(minimum, value)) end
	if maximum ~= nil then value = math.min(value, n(maximum, value)) end
	return value
end

local function nodeRect(node, available, context)
	local layout = layoutValues(node, context)
	local width = layout.fill and available.w or n(layout.width, available.w)
	local height = layout.fill and available.h or n(layout.height, available.h)
	local rect = SiK.UI.Layout.alignRect(available, {
		w = clampSize(width, layout["min-width"], layout["max-width"]),
		h = clampSize(height, layout["min-height"], layout["max-height"]),
	}, {
		defaultPadding = 0, padding = 0,
		align = layout["align-x"] or layout.align or "start",
		verticalAlign = layout["align-y"] or layout["vertical-align"] or "start",
		offsetX = layout.x, offsetY = layout.y,
	})
	return rect
end

local intrinsicHeight
local nodeProperty

-- The declarative shorthand used by consumers belongs to the same layout
-- contract whether it is measured before construction or resolved during a
-- reflow.  Keeping this normalization in one place prevents a row from being
-- measured as a column and then painted as a row.
local function compositionMode(node, layout, context)
	local mode = layout.mode
	for index = 1, #(node.props or {}) do
		local prop = node.props[index]
		if prop.name == "direction" and mode == nil then
			mode = Builder.resolve(prop.value, context)
		elseif prop.name == "mode" and node.type == "action-group" then
			local actionMode = Builder.resolve(prop.value, context)
			if actionMode == "stack" then mode = "column"
			elseif actionMode == "wrap" then mode = "wrap"
			else mode = "row" end
		end
	end
	return mode or "column"
end

-- Content-first measurement keeps a column of declarative blocks from being
-- split into arbitrary equal-height strips.  A consumer describes structure;
-- the framework reserves the standard chrome and asks the scroll host to carry
-- any remaining height.  Coordinates never leak back to product surfaces.
local function minimumContentHeight(node, context)
	local children = node.children or {}
	if #children == 0 then return 0 end
	local layout = layoutValues(node, context)
	local gap = math.max(0, n(layout.gap, 0))
	local mode = compositionMode(node, layout, context)
	local total, largest, visible = 0, 0, 0
	for index = 1, #children do
		if nodeVisible(children[index], context) ~= false then
			local childLayout = layoutValues(children[index], context)
			local height = intrinsicHeight(children[index], childLayout, context, mode, true)
			if height == nil then height = minimumContentHeight(children[index], context) end
			height = math.max(1, n(height, 1))
			visible, total, largest = visible + 1, total + height, math.max(largest, height)
		end
	end
	if visible == 0 then return 0 end
	if mode == "row" or mode == "wrap" then return largest end
	if mode == "grid" then
		local columns = math.max(1, math.floor(n(layout.columns, 1)))
		local rows, occupied, seen = 1, 0, 0
		for index = 1, #children do
			if nodeVisible(children[index], context) ~= false then
				seen = seen + 1
				local childLayout = layoutValues(children[index], context)
				local span = math.max(1, math.min(columns,
					math.floor(n(childLayout.span, 1))))
				if occupied > 0 and occupied + span > columns then
					rows, occupied = rows + 1, 0
				end
				occupied = occupied + span
				if occupied >= columns and seen < visible then
					rows, occupied = rows + 1, 0
				end
			end
		end
		return rows * largest + math.max(0, rows - 1) * gap
	end
	return total + math.max(0, visible - 1) * gap
end

intrinsicHeight = function(node, layout, context, parentMode, measuring)
	if layout.height ~= nil then return layout.height end
	-- Grow controls only the parent's main axis. During intrinsic measurement we
	-- still need the child's minimum content height; during real column layout a
	-- growing child must leave that axis unsized so Container can assign all
	-- remaining space. Rows keep the same control height and grow horizontally.
	if measuring ~= true and layout.grow ~= nil
		and parentMode ~= "row" and parentMode ~= "wrap" and parentMode ~= "grid" then
		return nil
	end
	-- `grow` belongs to the main axis only.  It must not erase the standard
	-- cross-axis height of a control: doing so turned every field in a row into
	-- a viewport-tall rectangle during runtime reflow.
	if node.type == "control" or node.type == "form" or node.type == "action-group" then
		return SiK.UI.Controls.metrics(context.profileId).rowHeight
	end
	if node.type == "table" or node.type == "virtual-list" then
		local tableMetrics = SiK.UI.Metrics.tokens().table
		return math.max(120, tableMetrics.headerHeight + tableMetrics.rowHeight * 2)
	end
	if node.type == "card" then
		return math.max(72, minimumContentHeight(node, context) + 16)
	end
	if node.type == "card-collection" then return math.max(120, minimumContentHeight(node, context)) end
	if node.type == "block" then
		local metrics = SiK.UI.Controls.metrics(context.profileId)
		local title = nodeProperty(node, "title", context)
		local header = title ~= nil and metrics.rowHeight + metrics.rowGap or 0
		return header + SiK.UI.Metrics.block.padding * 2 + minimumContentHeight(node, context)
	end
	if node.type == "container" then
		local padding = SiK.UI.Layout.insets(layout.padding, SiK.UI.Metrics.block.padding)
		return padding.top + padding.bottom + minimumContentHeight(node, context)
	end
	if node.type == "scroll" then
		return minimumContentHeight(node, context)
	end
	if layout.grow ~= nil then return nil end
	return nil
end

nodeProperty = function(node, name, context)
	for index = 1, #(node.props or {}) do
		local prop = node.props[index]
		if prop.name == name then return Builder.resolve(prop.value, context) end
	end
	return nil
end

local function intrinsicWidth(node, layout, context, parentMode)
        if layout.width ~= nil or layout.fill == true or layout.grow ~= nil then return layout.width end
        if parentMode ~= "row" or node.type ~= "control" then return nil end
        local kind = nodeProperty(node, "kind", context)
        local metrics = SiK.UI.Controls.metrics(context.profileId)
        if kind == "icon-button" then return metrics.rowHeight end
	-- Ordinary unsized controls are flex entries. Content-based button widths
	-- made sibling actions depend on translated label length and left unused
	-- space; only intrinsically square icon controls opt out of row growth.
        return nil
end

local function childArea(handle, fallback)
        if type(handle) ~= "table" then return fallback end
        local host = handle.childParent
        -- Composite controls such as Block already position their dedicated
        -- content host at the padded/header-adjusted content rectangle. Children
        -- are parented to that host, therefore their coordinate origin is (0,0).
        -- Returning the block-local content rectangle here applied the inset a
        -- second time and let descendants escape their apparent container.
        if type(host) == "table" and host ~= handle.panel then
                return { x = 0, y = 0, w = math.max(1, n(host.width, fallback.w)),
                        h = math.max(1, n(host.height, fallback.h)) }
        end
        if type(handle.contentRect) == "function" then
                return handle:contentRect()
	end
	-- A composed container owns the rectangle available to descendants.
	-- Block, for example, reserves canonical padding and header/footer space in
	-- getContentRect(); using its backing panel would paint children over chrome.
	if type(handle.getContentRect) == "function" then
		local rect = handle:getContentRect()
		if type(rect) == "table" then return rect end
	end
        if type(host) == "table" then
		return { x = 0, y = 0, w = math.max(1, n(host.width, fallback.w)),
			h = math.max(1, n(host.height, fallback.h)) }
	end
	local panel = handle.panel
	if type(panel) == "table" then
		return { x = 0, y = 0, w = math.max(1, n(panel.width, fallback.w)),
			h = math.max(1, n(panel.height, fallback.h)) }
	end
	return fallback
end

local function resolveChildGeometry(node, area, context)
	local children, entries = node.children or {}, {}
	if #children == 0 then return entries end
	local parentLayout = layoutValues(node, context)
	parentLayout.mode = compositionMode(node, parentLayout, context)
        for index = 1, #children do
		local visible = nodeVisible(children[index], context)
		local layout = layoutValues(children[index], context)
		entries[index] = {
                visible = visible, x = layout.x, y = layout.y,
                        width = intrinsicWidth(children[index], layout, context, parentLayout.mode),
			height = intrinsicHeight(children[index], layout, context, parentLayout.mode, false),
			fill = layout.fill,
                        minWidth = layout["min-width"], maxWidth = layout["max-width"],
                        minHeight = layout["min-height"], maxHeight = layout["max-height"],
                        grow = layout.grow, align = layout.align,
			shrink = layout.shrink, span = layout.span, order = layout.order,
                        alignX = layout["align-x"], alignY = layout["align-y"],
                        verticalAlign = layout["vertical-align"],
                }
        end
        return SiK.UI.Container.resolveRects(area, entries, {
                mode = parentLayout.mode, padding = parentLayout.padding,
                gap = parentLayout.gap, columns = parentLayout.columns,
                justify = parentLayout.justify,
        })
end

local function resolvedOptions(node, context)
	local result = {}
	for index = 1, #(node.options or {}) do
		local source, option = node.options[index], copy(node.options[index])
		if source.labelRef then option.label = lookup(context.i18n, source.labelRef) end
		if source.reasonRef then option.reason = lookup(context.i18n, source.reasonRef) end
		if source.iconRef then option.icon = lookup(context.assets, source.iconRef) end
		result[index] = option
	end
	return result
end

local function resolvedColumns(node, context)
	local result = {}
	for index = 1, #(node.columns or {}) do
		local column = copy(node.columns[index])
		column.title = column.labelRef and lookup(context.i18n, column.labelRef) or column.title
		result[index] = column
	end
	return result
end

local function resolvedProps(node, context, bounds)
	local visible, visibilityReason = nodeVisible(node, context)
	if visible == nil then return nil, visibilityReason end
	local result = { nodeId = node.id, surfaceId = context.surfaceId,
		variant = node.variant, bounds = bounds, columns = resolvedColumns(node, context),
		options = resolvedOptions(node, context), layout = layoutValues(node, context),
		visible = visible }
	for index = 1, #(node.props or {}) do
		local prop = node.props[index]
		result[prop.name] = Builder.resolve(prop.value, context)
	end
	if (node.type == "block" or node.type == "container" or node.type == "scroll")
		and result.contentHeight == nil then
		result.contentHeight = minimumContentHeight(node, context)
	end
	local caps, err = SiK.UI.Capabilities.resolve(node, context, Builder.resolve)
	if not caps then return nil, err end
	result.capabilities = caps
	return result
end

local function actionCallback(context, actionId)
	local action = lookup(context.actions, actionId)
	if type(action) == "function" then return action end
	if type(action) == "table" and type(action.run) == "function" then
		return function(payload) return action.run(action, payload) end
	end
	return nil
end

local function actionTarget(handle)
	if type(handle) ~= "table" then return handle end
	return handle.actionTarget or handle.control or handle.panel or handle
end

local recordRuntimeVisible

local function bindActions(handle, node, context, tree)
	local target = actionTarget(handle)
	for index = 1, #(node.actions or {}) do
		local declaration = node.actions[index]
		if not actionCallback(context, declaration.actionId) then
			error("SiK UI action unavailable: " .. declaration.actionId, 2)
		end
		-- Resolve on invocation so tree:update() can replace the action context
		-- without stacking wrappers or rebuilding controls.
		local callback = function(actionPayload)
			local record = tree.records[node.id]
			local visible, reason = recordRuntimeVisible(record, tree, tree.context)
			if visible == nil then return nil, reason end
			if visible == false then return nil, "action_hidden" end
			local active = actionCallback(tree.context, declaration.actionId)
			if not active then return nil, "action_unavailable" end
			return active(actionPayload)
		end
		local binding, err = SiK.UI.Bindings.bind(target, declaration, callback, {
			surfaceId = context.surfaceId, nodeId = node.id, componentType = node.type,
			playerNum = context.playerNum,
			payload = nil,
			onError = context.onActionError, onCancel = context.onActionCancel,
		})
		if not binding then error("SiK UI binding failed: " .. tostring(err), 2) end
		tree.bindings[#tree.bindings + 1] = binding
	end
end

function Builder.register(typeId, factory, contract)
	if type(factory) ~= "function" then return nil, "invalid_factory" end
	if factories[typeId] and factories[typeId] ~= factory then return nil, "factory_conflict" end
	local ok, err = SiK.UI.Surface.registerType(typeId, contract)
	if not ok then return nil, err end
	factories[typeId] = factory
	factoryContracts[typeId] = copy(contract)
	return true
end

function Builder.unregister(typeId)
	factories[typeId] = nil
	factoryContracts[typeId] = nil
	SiK.UI.Surface.unregisterType(typeId)
	return true
end

local function disposeHandle(handle)
	if type(handle) ~= "table" then return end
	if type(handle.dispose) == "function" then pcall(handle.dispose, handle)
	elseif type(handle.removeFromUIManager) == "function" then pcall(handle.removeFromUIManager, handle) end
end

local buildNode

local function recordHandle(handle, node, tree, props, owned, placement, adopted)
	local function tag(widget, suffix)
		if type(widget) ~= "table" then return end
		widget._sikNodeId = tostring(node.id) .. (suffix or "")
		widget._sikNodeType = node.type
	end
	tag(handle)
	tag(handle.panel)
	tag(handle.body, "/body")
	tag(handle.header, "/header")
	tag(handle.content, "/content")
	tag(handle.childParent, "/children")
	tree.nodes[node.id] = handle
	tree.order[#tree.order + 1] = handle
	local record = { handle = handle, node = node, props = props, owned = owned ~= false,
		adopted = adopted == true,
		typeId = node.type, placement = placement, contract = factoryContracts[node.type] or {} }
	tree.records[node.id] = record
	tree.recordOrder[#tree.recordOrder + 1] = record
	return record
end

recordRuntimeVisible = function(record, tree, context)
	local current = record
	while current do
		local visible, reason = nodeVisible(current.node, context)
		if visible == nil then return nil, reason end
		if visible == false then return false end
		local placement = current.placement
		current = placement and placement.parentId and tree.records[placement.parentId] or nil
	end
	return true
end

local function refreshRuntimeLookup(tree, context)
	for key, _ in pairs(tree.nodes) do tree.nodes[key] = nil end
	for index = 1, #tree.recordOrder do
		local record = tree.recordOrder[index]
		local visible, reason = recordRuntimeVisible(record, tree, context)
		if visible == nil then return nil, reason end
		if visible then tree.nodes[record.node.id] = record.handle end
	end
	return true
end

local function refreshBindingPayloads(tree)
	for index = 1, #tree.bindings do
		local binding = tree.bindings[index]
		if binding then binding.payload = nil end
	end
	return true
end

local function nodeMap(root)
	local result = {}
	local function visit(node)
		if type(node) ~= "table" then return end
		result[node.id] = node
		for index = 1, #(node.children or {}) do visit(node.children[index]) end
	end
	visit(root)
	return result
end

local function normalizedAdoptions(spec, source)
	local supplied = source.adopt or source.adoptions
	if supplied == nil then return {} end
	if type(supplied) ~= "table" then return nil, "invalid_adoptions" end
	local nodes, result = nodeMap(spec.surface.root), {}
	for nodeId, declaration in pairs(supplied) do
		local node = nodes[nodeId]
		if not node then return nil, "adoption_unknown_node:" .. tostring(nodeId) end
                if type(declaration) ~= "table" or type(declaration.handle) ~= "table" then
                        return nil, "adoption_invalid_handle:" .. tostring(nodeId)
                end
                if declaration.owned ~= nil and type(declaration.owned) ~= "boolean" then
                        return nil, "adoption_invalid_ownership:" .. tostring(nodeId)
                end
                local registered = factoryContracts[node.type]
		local runtimeFactory = registered and registered.runtimeFactory
		if declaration.typeId ~= node.type then
			return nil, "adoption_type_mismatch:" .. tostring(nodeId)
		end
		if type(runtimeFactory) ~= "string" or declaration.runtimeFactory ~= runtimeFactory then
			return nil, "adoption_factory_mismatch:" .. tostring(nodeId)
		end
		if declaration.handle.disposed then return nil, "adoption_disposed:" .. tostring(nodeId) end
		if registered and type(registered.validateAdopt) == "function" then
			local ok, reason = registered.validateAdopt(declaration.handle, node)
			if ok == false then return nil, reason or ("adoption_rejected:" .. tostring(nodeId)) end
		end
		result[nodeId] = { handle = declaration.handle, owned = declaration.owned == true }
	end
	return result
end

local function genericReflow(handle, bounds)
        if type(handle) ~= "table" then return nil, "invalid_handle" end
	local target = handle.panel or handle.control or handle
	if type(target) ~= "table" then return nil, "geometry_unsupported" end
	-- B42 ISUIElement:setBounds accepts a descriptive table, while several SiK
	-- composite handles expose a positional convenience method with the same
	-- name. Dispatching four positional arguments here made runtime geometry
	-- dependent on the concrete child and could discard resolved gaps. The
	-- canonical path uses the four primitive setters for every handle.
	if target.setX then target:setX(bounds.x) else target.x = bounds.x end
	if target.setY then target:setY(bounds.y) else target.y = bounds.y end
	if target.setWidth then target:setWidth(bounds.w) else target.width = bounds.w end
	if target.setHeight then target:setHeight(bounds.h) else target.height = bounds.h end
	return handle
end

local function applyVisibility(handle, visible)
	if type(handle) ~= "table" then return nil, "invalid_handle" end
	local target = handle
	if type(target.setVisible) == "function" then target:setVisible(visible == true)
	else target.visible = visible == true end
	local panel = handle.panel or handle.control
	if type(panel) == "table" and panel ~= target then
		if type(panel.setVisible) == "function" then panel:setVisible(visible == true)
		else panel.visible = visible == true end
	end
	return handle
end

local function applyReflow(record, bounds, context)
	local callback = record.contract and record.contract.reflow
	if type(callback) == "function" then return callback(record.handle, bounds, context, record.node) end
	return genericReflow(record.handle, bounds)
end

local function applyUpdate(record, props, context)
	local callback = record.contract and record.contract.update
	if type(callback) == "function" then return callback(record.handle, props, context, record.node) end
	return record.handle
end

local function captureRecord(record)
	local callback = record.contract and record.contract.capture
	local state = type(callback) == "function" and callback(record.handle) or nil
	return { props = copy(record.props), state = state }
end

local function preserveRecord(record, snapshot)
        local callback = record.contract and record.contract.preserve
        if type(callback) == "function" and snapshot ~= nil then
                return callback(record.handle, snapshot)
        end
        return record.handle
end

local function restoreRecord(record, snapshot, context)
	if not snapshot then return true end
	local ok, reason = applyUpdate(record, snapshot.props, context)
	if ok == nil or ok == false then return nil, reason or "rollback_update_failed" end
	local callback = record.contract and record.contract.restore
	if type(callback) == "function" and snapshot.state ~= nil then
		local restored, restoreReason = callback(record.handle, snapshot.state)
		if restored == nil or restored == false then return nil, restoreReason or "rollback_state_failed" end
	end
	local shown, visibleReason = applyVisibility(record.handle, snapshot.props.visible ~= false)
	if not shown then return nil, visibleReason or "rollback_visibility_failed" end
	record.props = snapshot.props
	return true
end

local function handleBounds(handle)
	if type(handle) ~= "table" then return nil end
	if type(handle.getBounds) == "function" then
		local ok, value = pcall(handle.getBounds, handle)
		if ok and type(value) == "table" then return copy(value) end
	end
	local target = handle.panel or handle.control or handle
	if type(target) ~= "table" then return nil end
	return { x = n(target.x, 0), y = n(target.y, 0),
		w = math.max(1, n(target.width, 1)), h = math.max(1, n(target.height, 1)) }
end

local function validateActions(node, context)
	for index = 1, #(node.actions or {}) do
		local actionId = node.actions[index].actionId
		if not actionCallback(context, actionId) then return nil, "action_unavailable:" .. tostring(actionId) end
	end
	for index = 1, #(node.children or {}) do
		local ok, reason = validateActions(node.children[index], context)
		if not ok then return nil, reason end
	end
	return true
end

local function recordBounds(record, tree, context)
	local placement = record.placement or { kind = "root" }
	if placement.kind == "root" then return nodeRect(record.node, context.viewport, context) end
	if placement.kind == "host" then
		local host = placement.host
		local available = { x = 0, y = 0, w = math.max(1, n(host and host.width, 1)),
			h = math.max(1, n(host and host.height, 1)) }
		return nodeRect(record.node, available, context)
	end
	if placement.kind == "collection-card" then return handleBounds(record.handle) end
	local parent = tree.records[placement.parentId]
	if not parent then return nil, "layout_parent_missing:" .. tostring(placement.parentId) end
	local parentBounds = parent.props and parent.props.bounds or handleBounds(parent.handle)
	local area = childArea(parent.handle, parentBounds)
	local rects = resolveChildGeometry(parent.node, area, context)
	return rects[placement.index], rects[placement.index] and nil or "layout_child_missing"
end

local function rollbackRecords(tree, snapshots, context, lastIndex)
	local failed = nil
	for index = lastIndex or #tree.recordOrder, 1, -1 do
		local record, snapshot = tree.recordOrder[index], snapshots[index]
		if record and snapshot and record.placement and record.placement.kind ~= "collection-card" then
			local restored, reason = restoreRecord(record, snapshot, context)
			if restored and snapshot.bounds then restored, reason = applyReflow(record, snapshot.bounds, context) end
			if not restored and not failed then failed = reason or "rollback_failed" end
		end
	end
	return failed == nil, failed
end

local function referencedContext(context, host)
	return {
		playerNum = context.playerNum, locale = context.locale,
		environment = context.environment, theme = context.theme,
		data = context.data, state = context.state, conditions = context.conditions,
		actions = context.actions, assets = context.assetOverrides,
		surfaceResolver = context.surfaceResolver, surfaces = context.surfaces,
		surfaceStack = context.surfaceStack,
		viewport = { x = 0, y = 0, w = math.max(1, n(host.width, 1)),
			h = math.max(1, n(host.height, 1)) },
	}
end

local function buildTabs(handle, node, context, tree)
	for index = 1, #(node.children or {}) do
		local child = node.children[index]
		local host = handle.contentHosts and handle.contentHosts[child.id]
		if not host then error("SiK UI tab content host unavailable: " .. child.id, 2) end
		local area = { x = 0, y = 0, w = math.max(1, n(host.width, 1)), h = math.max(1, n(host.height, 1)) }
		buildNode(host, child, context, tree, area,
			{ kind = "host", parentId = node.id, host = host, index = index })
	end
	for index = 1, #(node.options or {}) do
		local option = node.options[index]
		if option.surfaceRef then
			local reference = context.surfaceReferenceIndex[option.surfaceRef]
			local host = handle.surfaceHosts and handle.surfaceHosts[option.surfaceRef]
			if not reference or not host then
				error("SiK UI tab surface host unavailable: " .. option.surfaceRef, 2)
			end
			local artifact, resolveErr = Builder.resolveSurface(reference, context)
			if not artifact then error(resolveErr, 2) end
			local valid, validationErr = SiK.UI.Surface.validateReferenceArtifact(reference, artifact)
			if not valid then error(validationErr, 2) end
			local childTree, buildErr = Builder.build(host, artifact, referencedContext(context, host))
			if not childTree then error(buildErr, 2) end
			tree.surfaces[option.surfaceRef] = childTree
			tree.surfaceOrder[#tree.surfaceOrder + 1] = childTree
		end
	end
end

local function cardItem(child, context, rect)
        local props, err = resolvedProps(child, context, rect)
        if not props then error(err, 2) end
        local actions = props.capabilities["card.actions"]
        return { title = props.title, text = props.text, icon = props.icon,
                value = props.value, description = props.description,
                status = props.status or props.statusLabel,
                statusTone = props.statusTone or props.tone,
                tooltip = props.tooltip, locked = props.locked,
                payload = props.data, height = rect.h,
                contentHeight = props.contentHeight or rect.h,
                action = actions and type(actions.actions) == "table" and actions.actions[1] or nil }
end

local function buildCardCollection(parent, node, context, tree, bounds, factory, placement)
	local props, err = resolvedProps(node, context, bounds)
	if not props then error(err, 2) end
	props.actionTarget = {}
	bindActions(props.actionTarget, node, context, tree)
	local area = bounds
        local rects = resolveChildGeometry(node, area, context)
	if #(node.children or {}) > 0 then
		props.items = {}
		for index = 1, #node.children do props.items[index] = cardItem(node.children[index], context, rects[index]) end
	end
	local adoption = tree.adoptions[node.id]
	local handle, factoryErr
	if adoption then
		handle = adoption.handle
		local temporary = { handle = handle, node = node, props = props,
			contract = factoryContracts[node.type] or {} }
                local captured = captureRecord(temporary)
                tree.adoptionSnapshots[node.id] = { record = temporary,
                        state = captured.state, bounds = handleBounds(handle),
                        actionTarget = handle.actionTarget }
                local applied, applyErr = applyUpdate(temporary, props, context)
                if applied then applied, applyErr = preserveRecord(temporary, captured.state) end
                if not applied then error("SiK UI adoption failed for " .. node.id .. ": " .. tostring(applyErr), 2) end
	else
		handle, factoryErr = factory(parent, props, context, node)
	end
	if not handle then error("SiK UI factory failed for " .. node.id .. ": " .. tostring(factoryErr), 2) end
	handle.actionTarget = props.actionTarget
	local shown, visibilityReason = applyVisibility(handle, props.visible ~= false)
	if not shown then error("SiK UI visibility failed for " .. node.id .. ": " .. tostring(visibilityReason), 2) end
	recordHandle(handle, node, tree, props, not adoption or adoption.owned, placement, adoption ~= nil)
	for index = 1, #node.children do
		local child, card = node.children[index], handle.cards and handle.cards[index]
		if not card then error("SiK UI declarative card unavailable: " .. child.id, 2) end
		card.actionTarget = {}
		bindActions(card.actionTarget, child, context, tree)
		recordHandle(card, child, tree, cardItem(child, context, rects[index]), false,
			{ kind = "collection-card", parentId = node.id, index = index })
        end
	return handle
end

buildNode = function(parent, node, context, tree, available, placement)
	local factory = factories[node.type]
	if type(factory) ~= "function" then error("No SiK UI factory for " .. tostring(node.type), 2) end
	local bounds = nodeRect(node, available, context)
	if node.type == "card-collection" and #(node.children or {}) > 0 then
		return buildCardCollection(parent, node, context, tree, bounds, factory, placement)
	end
	local props, err = resolvedProps(node, context, bounds)
	if not props then error(err, 2) end
	props.actionTarget = {}
	bindActions(props.actionTarget, node, context, tree)
	local adoption = tree.adoptions[node.id]
	local handle, factoryErr
	if adoption then
		handle = adoption.handle
		local temporary = { handle = handle, node = node, props = props,
			contract = factoryContracts[node.type] or {} }
                local captured = captureRecord(temporary)
                tree.adoptionSnapshots[node.id] = { record = temporary,
                        state = captured.state, bounds = handleBounds(handle),
                        actionTarget = handle.actionTarget }
                local applied, applyErr = applyUpdate(temporary, props, context)
                if applied then applied, applyErr = applyReflow(temporary, bounds, context) end
                if applied then applied, applyErr = preserveRecord(temporary, captured.state) end
		if not applied then error("SiK UI adoption failed for " .. node.id .. ": " .. tostring(applyErr), 2) end
	else
		handle, factoryErr = factory(parent, props, context, node)
	end
	if not handle then error("SiK UI factory failed for " .. node.id .. ": " .. tostring(factoryErr), 2) end
	handle.actionTarget = props.actionTarget
	local shown, visibilityReason = applyVisibility(handle, props.visible ~= false)
	if not shown then error("SiK UI visibility failed for " .. node.id .. ": " .. tostring(visibilityReason), 2) end
	recordHandle(handle, node, tree, props, not adoption or adoption.owned, placement, adoption ~= nil)
	if node.type == "tabs" then buildTabs(handle, node, context, tree); return handle end
	if handle.navigation then buildTabs(handle.navigation, node, context, tree); return handle end
	if handle.ownsChildren ~= true then
		local area = childArea(handle, bounds)
                local rects = resolveChildGeometry(node, area, context)
		local childParent = handle.childParent or handle.body or handle.panel or handle
		for index = 1, #(node.children or {}) do
			buildNode(childParent, node.children[index], context, tree, rects[index],
				{ kind = "child", parentId = node.id, index = index })
		end
	end
	return handle
end

local function restoreAdoptions(tree, borrowedOnly)
        local failed = nil
        for nodeId, snapshot in pairs(tree.adoptionSnapshots or {}) do
                local adoption = tree.adoptions and tree.adoptions[nodeId]
                if not borrowedOnly or (adoption and adoption.owned ~= true) then
                        local record = tree.records[nodeId] or snapshot.record
                        local callback = record.contract and record.contract.restore
                        local ok, reason = true, nil
                        if type(callback) == "function" and snapshot.state ~= nil then
                                ok, reason = callback(record.handle, snapshot.state)
                        end
                        if ok and snapshot.bounds then ok, reason = applyReflow(record, snapshot.bounds, tree.context) end
                        record.handle.actionTarget = snapshot.actionTarget
                        if not ok and not failed then failed = reason or "adoption_rollback_failed" end
                end
        end
        return failed == nil, failed
end

local function disposePartial(tree, rollbackAdopted)
	for index = #tree.surfaceOrder, 1, -1 do tree.surfaceOrder[index]:dispose() end
	for index = #tree.bindings, 1, -1 do tree.bindings[index]:dispose() end
	for index = #tree.recordOrder, 1, -1 do
		local record = tree.recordOrder[index]
		if record.owned and (not rollbackAdopted or not record.adopted) then disposeHandle(record.handle) end
	end
	if rollbackAdopted then return restoreAdoptions(tree) end
	return true
end

local function updateTree(tree, nextContext)
	if tree.disposed then return nil, "disposed" end
	if type(nextContext) ~= "table" then return nil, "invalid_context" end
	local source = merged(tree.sourceContext, nextContext)
	local context = runtimeContext(tree.parent, tree.spec, source)
	local actionsOk, actionsReason = validateActions(tree.spec.surface.root, context)
	if not actionsOk then return nil, actionsReason end
	local conditionsOk, conditionsReason = validateConditions(tree.spec.surface.root, context)
	if not conditionsOk then return nil, conditionsReason end
	-- Capturing a Table/Collection can snapshot selection, expansion and scroll.
	-- Doing it for every node on every data refresh made a search keystroke walk
	-- the complete surface twice and reflow controls whose geometry had not
	-- changed.  Capture lazily: unchanged records are deliberately untouched.
	local snapshots = {}
	local previousContext, previousSource = tree.context, tree.sourceContext
	tree.context, tree.sourceContext, tree.profileId = context, source, context.profileId
	local appliedCount = 0
	for index = 1, #tree.recordOrder do
		local record = tree.recordOrder[index]
		if record.placement and record.placement.kind ~= "collection-card" then
			local bounds, boundsReason = recordBounds(record, tree, context)
			if not bounds then
				rollbackRecords(tree, snapshots, previousContext, appliedCount)
				tree.context, tree.sourceContext, tree.profileId = previousContext, previousSource,
					previousContext.profileId
				return nil, "surface_reflow_failed:" .. record.node.id .. ":" .. tostring(boundsReason)
			end
			local props, propsReason = resolvedProps(record.node, context, bounds)
			if not props then
				rollbackRecords(tree, snapshots, previousContext, appliedCount)
				tree.context, tree.sourceContext, tree.profileId = previousContext, previousSource,
					previousContext.profileId
				return nil, "surface_update_failed:" .. record.node.id .. ":" .. tostring(propsReason)
			end
			props.actionTarget = record.props.actionTarget
			local changed = not sameValue(record.props, props)
			local updated, updateReason = true, nil
			if changed then
				snapshots[index] = captureRecord(record)
				snapshots[index].bounds = handleBounds(record.handle)
				updated, updateReason = applyUpdate(record, props, context)
				if updated then updated, updateReason = applyReflow(record, bounds, context) end
				if updated then updated, updateReason = applyVisibility(record.handle, props.visible ~= false) end
				if updated then updated, updateReason = preserveRecord(record, snapshots[index].state) end
			end
			if not updated then
				local rollbackOk, rollbackReason = rollbackRecords(tree, snapshots, previousContext,
					math.max(appliedCount, index))
				tree.context, tree.sourceContext, tree.profileId = previousContext, previousSource,
					previousContext.profileId
				if not rollbackOk then
					return nil, "surface_update_rollback_failed:" .. record.node.id .. ":" .. tostring(rollbackReason)
				end
				return nil, "surface_update_failed:" .. record.node.id .. ":" .. tostring(updateReason)
			end
			if changed then
				replace(record.props, props)
				appliedCount = index
			end
		end
	end
        local childSources = {}
	for index = 1, #tree.surfaceOrder do
                local child = tree.surfaceOrder[index]
                childSources[index] = copy(child.sourceContext)
                local host = child.parent
                local childContext = referencedContext(context, host)
                local childOk, childReason = child:update(childContext)
                if not childOk then
                        local childRollbackReason = nil
                        for rollbackIndex = index - 1, 1, -1 do
                                local restored, reason = tree.surfaceOrder[rollbackIndex]:update(childSources[rollbackIndex])
                                if not restored and not childRollbackReason then childRollbackReason = reason end
                        end
                        local restored, parentReason = rollbackRecords(tree, snapshots, previousContext)
                        tree.context, tree.sourceContext, tree.profileId = previousContext, previousSource,
                                previousContext.profileId
                        if childRollbackReason or not restored then
                                return nil, "surface_reference_rollback_failed:"
                                        .. tostring(childRollbackReason or parentReason)
                        end
                        return nil, "surface_reference_update_failed:" .. tostring(childReason)
                end
        end
	local lookupOk, lookupReason = refreshRuntimeLookup(tree, context)
	if not lookupOk then
		local restored, rollbackReason = rollbackRecords(tree, snapshots, previousContext)
		tree.context, tree.sourceContext, tree.profileId = previousContext, previousSource,
			previousContext.profileId
		refreshRuntimeLookup(tree, previousContext)
		if not restored then
			return nil, "surface_update_rollback_failed:lookup:" .. tostring(rollbackReason)
		end
		return nil, "surface_update_failed:lookup:" .. tostring(lookupReason)
	end
	refreshBindingPayloads(tree)
	SiK.UI.observe("surface.update", { surfaceId = tree.surfaceId,
		playerNum = context.playerNum, profileId = context.profileId })
	return tree
end

function Builder.build(parent, spec, sourceContext)
	SiK.UI.Surface.assertValid(spec)
	sourceContext = sourceContext or {}
	-- Building against the 0/1 px placeholders emitted while a PZ tab is being
	-- assembled permanently bakes invalid rectangles into every descendant.
	-- SurfaceHost normally waits for real geometry, but Builder is public and
	-- must enforce the same lifecycle contract for direct callers and nested
	-- surface references.
	local parentWidth = type(parent) == "table" and n(parent.width,
		parent.getWidth and parent:getWidth() or nil) or nil
	local parentHeight = type(parent) == "table" and n(parent.height,
		parent.getHeight and parent:getHeight() or nil) or nil
	if not parentWidth or not parentHeight or parentWidth <= 1 or parentHeight <= 1 then
		SiK.UI.observe("surface.build.deferred", {
			surfaceId = spec.surface.id,
			parentWidth = parentWidth or 0,
			parentHeight = parentHeight or 0,
			constructionStage = "waiting_for_parent",
		})
		return nil, "surface_parent_geometry_pending"
	end
	local surfaceStack = copy(sourceContext.surfaceStack)
	if surfaceStack[spec.surface.id] then
		return nil, "surface_reference_cycle:" .. spec.surface.id
	end
	surfaceStack[spec.surface.id] = true
	local buildContext = copy(sourceContext)
	buildContext.surfaceStack = surfaceStack
	local context = runtimeContext(parent, spec, buildContext)
	local adoptions, adoptionErr = normalizedAdoptions(spec, sourceContext)
	if not adoptions then return nil, adoptionErr end
	local actionsOk, actionsReason = validateActions(spec.surface.root, context)
	if not actionsOk then return nil, actionsReason end
	local conditionsOk, conditionsReason = validateConditions(spec.surface.root, context)
	if not conditionsOk then return nil, conditionsReason end
	local tree = { surfaceId = spec.surface.id, nodes = {}, order = {}, bindings = {},
		records = {}, recordOrder = {}, surfaces = {}, surfaceOrder = {}, context = context,
		profileId = context.profileId, parent = parent, spec = spec, sourceContext = copy(sourceContext),
		adoptions = adoptions, adoptionSnapshots = {} }
	SiK.UI.observe("surface.build.begin", {
		surfaceId = spec.surface.id,
		parentWidth = parentWidth,
		parentHeight = parentHeight,
		constructionStage = "root_container",
	})
	local ok, result = pcall(buildNode, parent, spec.surface.root, context, tree, context.viewport,
		{ kind = "root" })
	if not ok then
		local rolledBack, rollbackReason = disposePartial(tree, true)
		if not rolledBack then return nil, "surface_build_rollback_failed:" .. tostring(rollbackReason) end
		return nil, tostring(result)
	end
	local lookupOk, lookupReason = refreshRuntimeLookup(tree, context)
	if not lookupOk then
		disposePartial(tree, true)
		return nil, tostring(lookupReason)
	end
	refreshBindingPayloads(tree)
	tree.root = result
	function tree:update(nextContext) return updateTree(self, nextContext) end
	function tree:reflow(bounds, profileId)
		if type(bounds) ~= "table" then return nil, "invalid_bounds" end
		local contextPatch = { viewport = { x = n(bounds.x, 0), y = n(bounds.y, 0),
			w = math.max(1, n(bounds.w or bounds.width, 1)),
			h = math.max(1, n(bounds.h or bounds.height, 1)) } }
		if profileId ~= nil then contextPatch.profile = profileId end
		return updateTree(self, contextPatch)
	end
        function tree:dispose()
                if self.disposed then return false end
                self.disposed = true
                disposePartial(self, false)
                restoreAdoptions(self, true)
                self.nodes, self.order, self.records, self.recordOrder, self.bindings,
			self.surfaces, self.surfaceOrder, self.context, self.root, self.parent,
			self.spec, self.sourceContext, self.adoptions, self.adoptionSnapshots =
			nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
		SiK.UI.observe("surface.dispose", { surfaceId = self.surfaceId })
		return true
	end
	SiK.UI.observe("surface.create", { surfaceId = tree.surfaceId,
		playerNum = context.playerNum, profileId = context.profileId })
	return tree
end

return Builder
