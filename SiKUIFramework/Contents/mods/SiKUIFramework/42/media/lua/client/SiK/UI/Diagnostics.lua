require "SiK/UI/Namespace"

SiK = SiK or {}
SiK.UI = SiK.UI or {}

local Diagnostics = SiK.UI.Diagnostics or {}
SiK.UI.Namespace.define("Diagnostics", Diagnostics)

local channels = {}

local function channelActive(channel)
	local value = channel and channel.enabled
	if type(value) == "function" then
		local ok, result = pcall(value)
		return ok and result == true
	end
	return value == true
end

local function active()
	for _, channel in pairs(channels) do
		if channelActive(channel) then return true end
	end
	return false
end

local function write(kind, message)
	local delivered = false
	local event = { source = "SiK.UI", kind = tostring(kind or "event"),
		message = tostring(message or "") }
	for _, channel in pairs(channels) do
		if channelActive(channel) and type(channel.sink) == "function" then
			local ok = pcall(channel.sink, event)
			if ok then delivered = true end
		end
	end
	return delivered
end

function Diagnostics.configure(options)
	return Diagnostics.registerSink("default", options)
end

function Diagnostics.registerSink(ownerId, options)
	ownerId = tostring(ownerId or "")
	if ownerId == "" then return nil, "invalid_owner" end
	options = options or {}
	if type(options.sink) ~= "function" then return nil, "invalid_sink" end
	channels[ownerId] = { enabled = options.enabled, sink = options.sink }
	return Diagnostics
end

function Diagnostics.unregisterSink(ownerId)
	ownerId = tostring(ownerId or "")
	if channels[ownerId] == nil then return false end
	channels[ownerId] = nil
	return true
end

function Diagnostics.enabled()
	return active()
end

function Diagnostics.event(kind, message)
	return write(kind, message)
end

local function visible(widget)
	if not widget then return false end
	if not widget.isVisible then return widget.visible ~= false end
	local ok, result = pcall(widget.isVisible, widget)
	return ok and result == true
end

local function rect(widget)
	local result = { x = widget and widget.x or 0, y = widget and widget.y or 0,
		w = widget and widget.width or 0, h = widget and widget.height or 0 }
	pcall(function()
		result.x, result.y = widget:getX(), widget:getY()
		result.w, result.h = widget:getWidth(), widget:getHeight()
	end)
	return result
end

local function widgetId(widget)
	return tostring(widget and (widget._sikNodeId or widget._sikControlId or widget.controlId
		or widget._gsDebugName or widget.Type) or "widget")
end

--- Returns a neutral, bounded widget-tree snapshot. Products may attach their
--- own sink and labels, but ownership and interpretation stay in SiK.UI.
function Diagnostics.snapshot(root, label, limit)
	local report = { label = tostring(label or "surface"), nodes = {},
		visible = 0, zeroSizedVisible = 0, truncated = false }
	limit = math.max(1, math.floor(tonumber(limit) or 600))
	local function walk(widget, depth)
		if type(widget) ~= "table" or #report.nodes >= limit then
			report.truncated = #report.nodes >= limit
			return
		end
		local bounds, isVisible = rect(widget), visible(widget)
		local node = { depth = depth, visible = isVisible, rect = bounds,
			id = widgetId(widget) }
		report.nodes[#report.nodes + 1] = node
		if isVisible then
			report.visible = report.visible + 1
			if bounds.w <= 0 or bounds.h <= 0 then
				report.zeroSizedVisible = report.zeroSizedVisible + 1
			end
		end
		local children = widget.childrenInOrder or widget.children
		if type(children) == "table" then
			for index = 1, #children do walk(children[index], depth + 1) end
		end
	end
	walk(root, 0)
	write("tree", string.format("%s nodes=%d visible=%d zero=%d truncated=%s",
		report.label, #report.nodes, report.visible, report.zeroSizedVisible,
		tostring(report.truncated)))
	local detailCount = 0
	for index = 1, #report.nodes do
		local node = report.nodes[index]
		if node.visible and (node.rect.w <= 0 or node.rect.h <= 0)
			and detailCount < 12 then
			detailCount = detailCount + 1
			write("geometry-error", string.format("%s id=%s depth=%d rect=%d,%d %dx%d",
				report.label, node.id, node.depth, node.rect.x, node.rect.y,
				node.rect.w, node.rect.h))
		end
	end
	return report
end

local function overlaps(a, b)
	if not (a.x < b.x + b.w and b.x < a.x + a.w
		and a.y < b.y + b.h and b.y < a.y + a.h) then
		return false
	end
	local function contains(outer, inner)
		return outer.x <= inner.x and outer.y <= inner.y
			and outer.x + outer.w >= inner.x + inner.w
			and outer.y + outer.h >= inner.y + inner.h
	end
	return not contains(a, b) and not contains(b, a)
end

--- Reports partial overlaps between visible siblings. Full containment is
--- intentional composition and therefore not reported. Consumers may ignore
--- known chrome through the neutral ignore callback.
function Diagnostics.checkOverlaps(root, label, options)
	options = options or {}
	local report = { label = tostring(label or "surface"), count = 0, pairs = {} }
	local limit = math.max(1, math.floor(tonumber(options.limit) or 200))
	local function ignored(widget)
		if type(options.ignore) ~= "function" then return false end
		local ok, result = pcall(options.ignore, widget)
		return ok and result == true
	end
	local function walk(widget)
		if type(widget) ~= "table" or #report.pairs >= limit then return end
		local children = widget.childrenInOrder or widget.children
		if type(children) ~= "table" then return end
		local candidates = {}
		for index = 1, #children do
			local child = children[index]
			if child and visible(child) and not ignored(child) then
				local bounds = rect(child)
				if bounds.w > 0 and bounds.h > 0 then
					candidates[#candidates + 1] = { widget = child, rect = bounds }
				end
			end
		end
		for left = 1, #candidates do
			for right = left + 1, #candidates do
				if #report.pairs < limit
					and overlaps(candidates[left].rect, candidates[right].rect) then
					report.count = report.count + 1
					report.pairs[#report.pairs + 1] = {
						left = candidates[left].widget,
						right = candidates[right].widget,
						leftRect = candidates[left].rect,
						rightRect = candidates[right].rect,
					}
				end
			end
		end
		for index = 1, #children do walk(children[index]) end
	end
	walk(root)
	report.truncated = #report.pairs >= limit
	write(report.count == 0 and "overlap" or "overlap-error",
		string.format("%s count=%d truncated=%s", report.label, report.count,
			tostring(report.truncated)))
	local detailLimit = math.max(0, math.floor(tonumber(options.detailLimit) or 12))
	for index = 1, math.min(#report.pairs, detailLimit) do
		local pair = report.pairs[index]
		write("overlap-detail", string.format("%s left=%s rect=%d,%d %dx%d right=%s rect=%d,%d %dx%d",
			report.label, widgetId(pair.left), pair.leftRect.x, pair.leftRect.y,
			pair.leftRect.w, pair.leftRect.h, widgetId(pair.right), pair.rightRect.x,
			pair.rightRect.y, pair.rightRect.w, pair.rightRect.h))
	end
	return report
end

--- Reports visible children whose final local rectangle escapes their parent.
--- This detects the runtime failure that sibling-only overlap checks missed:
--- content could be internally well ordered while being positioned over the
--- shell, footer or neighbouring block instead of inside its own container.
function Diagnostics.checkContainment(root, label, options)
	options = options or {}
	local report = { label = tostring(label or "surface"), count = 0, items = {} }
	local limit = math.max(1, math.floor(tonumber(options.limit) or 200))
	local tolerance = math.max(0, tonumber(options.tolerance) or 1)
	local function ignored(widget)
		if type(options.ignore) ~= "function" then return false end
		local ok, result = pcall(options.ignore, widget)
		return ok and result == true
	end
	local function walk(parent)
		if type(parent) ~= "table" or #report.items >= limit then return end
		local children = parent.childrenInOrder or parent.children
		if type(children) ~= "table" then return end
		local parentRect = rect(parent)
		for index = 1, #children do
			local child = children[index]
			if child and visible(child) and not ignored(child) then
				local childRect = rect(child)
				local scrollOverflow = parent._sikScrollViewport == true
					and child._sikScrollContentHost == true
				local escapes = not scrollOverflow and childRect.w > 0 and childRect.h > 0
					and (childRect.x < -tolerance or childRect.y < -tolerance
						or childRect.x + childRect.w > parentRect.w + tolerance
						or childRect.y + childRect.h > parentRect.h + tolerance)
				if escapes and #report.items < limit then
					report.count = report.count + 1
					report.items[#report.items + 1] = {
						parent = parent, child = child,
						parentRect = parentRect, childRect = childRect,
					}
				end
			end
			walk(child)
		end
	end
	walk(root)
	report.truncated = #report.items >= limit
	write(report.count == 0 and "containment" or "containment-error",
		string.format("%s count=%d truncated=%s", report.label, report.count,
			tostring(report.truncated)))
	local detailLimit = math.max(0, math.floor(tonumber(options.detailLimit) or 12))
	for index = 1, math.min(#report.items, detailLimit) do
		local item = report.items[index]
		write("containment-detail", string.format(
			"%s parent=%s size=%dx%d child=%s rect=%d,%d %dx%d",
			report.label, widgetId(item.parent), item.parentRect.w, item.parentRect.h,
			widgetId(item.child), item.childRect.x, item.childRect.y,
			item.childRect.w, item.childRect.h))
	end
	return report
end

--- Validates the failure mode that produced an apparently healthy shell with
--- an empty body: both destination host and adopted content must be live,
--- visible and positively sized after activation.
function Diagnostics.inspectMount(navigation, key)
	local result = { key = key, ok = false, reason = nil }
	local host = navigation and navigation.hosts and navigation.hosts[key]
	if not host or not host.panel then result.reason = "missing_host"
	elseif navigation.activeKey ~= key then result.reason = "inactive_destination"
	elseif not visible(host.panel) then result.reason = "hidden_host"
	elseif not host.mountedContent then result.reason = "missing_content"
	elseif not visible(host.mountedContent) then result.reason = "hidden_content"
	else
		local bounds = rect(host.mountedContent)
		if bounds.w <= 0 or bounds.h <= 0 then result.reason = "empty_geometry"
		else result.ok = true end
	end
	write(result.ok and "mount" or "mount-error",
		tostring(key) .. " " .. (result.ok and "ok" or tostring(result.reason)))
	return result
end

-- The framework owns its diagnostic switch and logger. Product adapters may
-- register additional sinks for integration-specific traces, but enabling or
-- removing a consumer must never control the framework's own observability.
local function frameworkDebugEnabled()
	return SandboxVars ~= nil
		and SandboxVars.SiKUIFramework ~= nil
		and SandboxVars.SiKUIFramework.DebugMode == true
end

local function frameworkDebugSink(event)
	if DebugLog == nil or type(DebugLog.log) ~= "function" then return end
	DebugLog.log(string.format("[SiK.UI][%s] %s",
		tostring(event and event.kind or "event"),
		tostring(event and event.message or "")))
end

Diagnostics.registerSink("SiK.UI.Framework", {
	enabled = frameworkDebugEnabled,
	sink = frameworkDebugSink,
})

return Diagnostics
