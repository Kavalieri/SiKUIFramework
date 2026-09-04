require "SiK/UI/Namespace"
require "SiK/UI/Container"
require "SiK/UI/Tabs"
require "SiK/UI/Metrics"
require "SiK/UI/Layout"
require "SiK/UI/Diagnostics"

-- Internal navigation capability used by Container. It owns the tab selector
-- and one stable Container host per destination. Product code never creates
-- rails or manually toggles content panels.
local Navigation = SiK.UI.Navigation or {}
SiK.UI.Namespace.define("Navigation", Navigation)

local function number(value, fallback)
	value = tonumber(value)
	if value == nil or value ~= value then return fallback end
	return value
end

local function removePanel(parent, panel)
	if not panel then return end
	if parent and parent.removeChild then parent:removeChild(panel)
	elseif panel.removeFromUIManager then panel:removeFromUIManager() end
end

local function isChildOf(parent, panel)
	local children = parent and parent.childrenInOrder
	if type(children) ~= "table" then return false end
	for index = 1, #children do
		if children[index] == panel then return true end
	end
	return false
end

local function splitBounds(bounds, placement, extent, gap)
	local bar, content
	if placement == "left" then
		bar = { x = bounds.x, y = bounds.y, w = extent, h = bounds.h }
		content = { x = bounds.x + extent + gap, y = bounds.y,
			w = math.max(1, bounds.w - extent - gap), h = bounds.h }
	elseif placement == "right" then
		bar = { x = bounds.x + math.max(0, bounds.w - extent), y = bounds.y,
			w = extent, h = bounds.h }
		content = { x = bounds.x, y = bounds.y,
			w = math.max(1, bounds.w - extent - gap), h = bounds.h }
	elseif placement == "bottom" then
		bar = { x = bounds.x, y = bounds.y + math.max(0, bounds.h - extent),
			w = bounds.w, h = extent }
		content = { x = bounds.x, y = bounds.y, w = bounds.w,
			h = math.max(1, bounds.h - extent - gap) }
	else
		bar = { x = bounds.x, y = bounds.y, w = bounds.w, h = extent }
		content = { x = bounds.x, y = bounds.y + extent + gap, w = bounds.w,
			h = math.max(1, bounds.h - extent - gap) }
	end
	return bar, content
end

function Navigation.create(options)
	options = options or {}
	if type(options.parent) ~= "table" then return nil, "invalid_parent" end
	local placement = options.placement or "top"
	if placement == "side" then placement = options.side or "left" end
	if placement ~= "left" and placement ~= "right" and placement ~= "bottom" then
		placement = "top"
	end
	local instance = { parent = options.parent, options = options, placement = placement,
		hosts = {}, hostOnlyKeys = {}, contentHosts = {}, surfaceHosts = {}, items = {} }
	local initialBounds = SiK.UI.Layout.resolveRect(options.bounds, {
		x = 0, y = 0, w = options.parent.width or 1, h = options.parent.height or 1,
	}, 1)
	local initialMetrics = SiK.UI.Metrics.profile(initialBounds.w, options.profile)
	local initialDefaultExtent = (placement == "left" or placement == "right")
		and math.max(initialMetrics.rowHeight,
			number(options.sideExtent, initialMetrics.rowHeight * 2))
		or initialMetrics.rowHeight + SiK.UI.Metrics.spacing.xs
	local initialExtent = math.max(1,
		number(options.extent or options.barSize, initialDefaultExtent))
	local initialBar, initialContent = splitBounds(initialBounds, placement,
		initialExtent, math.max(0, number(options.contentGap, 0)))
	instance.bounds = initialBounds
	instance.barBounds = SiK.UI.Layout.resolveRect(initialBar, initialBounds, 1)
	instance.contentBounds = SiK.UI.Layout.resolveRect(initialContent, initialBounds, 1)

	function instance:_createHost(padding)
		local bounds = self.contentBounds
		if not bounds or bounds.w <= 1 or bounds.h <= 1 then
			return nil, "navigation_content_geometry_unresolved"
		end
		local host, err = SiK.UI.Container.create({ parent = self.parent,
			x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h,
			bounds = bounds, padding = padding or 0,
			playerNum = options.playerNum, controlId = "navigation-content" })
		if not host then return nil, err end
		host.panel:setVisible(false)
		return host
	end

	function instance:ensureHost(key, hostOptions)
		if self.disposed then return nil, "disposed" end
		if key == nil or key == "" then return nil, "invalid_key" end
		if self.hosts[key] then return self.hosts[key] end
		local host, err = self:_createHost(hostOptions and hostOptions.padding)
		if not host then return nil, err end
		self.hosts[key], self.hostOnlyKeys[key] = host, true
		return host
	end

	function instance:setItems(items)
		if self.disposed then return nil, "disposed" end
		local previousHosts = self.hosts
		self.hosts, self.contentHosts, self.surfaceHosts, self.items = {}, {}, {}, {}
		for key in pairs(self.hostOnlyKeys) do
			if previousHosts[key] then
				self.hosts[key], previousHosts[key] = previousHosts[key], nil
			end
		end
		for index = 1, #(items or {}) do
			local source = items[index]
			local key = source.key or source.id or source.value or tostring(index)
			local host = previousHosts[key]
			if host then previousHosts[key] = nil
			else
				local err
				host, err = self:_createHost(source.padding)
				if not host then return nil, err end
			end
			host.panel:setVisible(false)
			self.hosts[key] = host
			if source.contentId then self.contentHosts[source.contentId] = host.panel end
			if source.surfaceRef then self.surfaceHosts[source.surfaceRef] = host.panel end
			self.items[index] = {
				key = key, text = source.text or source.label or source.labelRef or "",
				icon = source.icon, iconOnly = source.iconOnly,
				tooltip = source.tooltip, badge = source.badge,
				enabled = source.enabled ~= false and source.disabled ~= true,
				content = host.panel, payload = source.payload or source.value,
				pin = source.pin, pinned = source.pinned,
			}
		end
		for _, host in pairs(previousHosts) do host:dispose() end
		if self.tabs then self.tabs:setItems(self.items) end
		-- During construction the final bounds already exist before Tabs does.
		-- Reflow only once the bar has been created; its constructor receives
		-- the same resolved bounds immediately afterwards.
		if self.bounds and self.tabs then self:reflow(self.bounds) end
		return self
	end

	function instance:getHost(key)
		return self.hosts[key]
	end

	-- Adopts an existing product panel into a destination owned by this
	-- capability. Products provide content; Navigation owns parentage,
	-- visibility and destination geometry.
	function instance:mountContent(key, panel)
		if self.disposed then return nil, "disposed" end
		if type(panel) ~= "table" then return nil, "invalid_content" end
		local host = self.hosts[key]
		if not host then return nil, "unknown_destination" end
		local parent = panel.getParent and panel:getParent() or panel.parent
		if parent and parent ~= host.panel and isChildOf(parent, panel) then
			parent:removeChild(panel)
		end
		if not isChildOf(host.panel, panel) then host.panel:addChild(panel) end
		panel.parent = host.panel
		SiK.UI.Layout.apply(panel, SiK.UI.Layout.resolveRect({
			x = 0, y = 0, w = host.panel.width, h = host.panel.height,
		}, nil, 1))
                panel:setVisible(self.activeKey == key)
                host.mountedContent = panel
		if self.activeKey == key and SiK.UI.Diagnostics and SiK.UI.Diagnostics.enabled() then
			SiK.UI.Diagnostics.inspectMount(self, key)
		end
                return panel
	end

	function instance:getSelectedKey()
		return self.activeKey or (self.tabs and self.tabs:getSelectedKey()) or nil
	end

	function instance:setActive(key, emit)
		if self.disposed then return nil, "disposed" end
		if not self.hosts[key] then return nil, "unknown_destination" end
		for hostKey, host in pairs(self.hosts) do
			local active = hostKey == key
			host.panel:setVisible(active)
			-- mountContent() must make an inactive destination safe at adoption
			-- time, but the destination owns visibility afterwards. Previously we
			-- only re-enabled the host here: its mounted product panel remained
			-- explicitly hidden forever, producing a valid Window with an empty
			-- body and no runtime error when the destination was first activated.
			if host.mountedContent and host.mountedContent.setVisible then
				host.mountedContent:setVisible(active)
			end
                end
                self.activeKey = key
		local activeHost = self.hosts[key]
		-- A destination is allowed to become active before its product content
		-- is adopted. Diagnose only live mounts here; mountContent performs the
		-- first complete inspection immediately after adoption.
		if activeHost and activeHost.mountedContent
				and SiK.UI.Diagnostics and SiK.UI.Diagnostics.enabled() then
                        SiK.UI.Diagnostics.inspectMount(self, key)
                end
		if self.tabs and self.tabs.byKey[key] then return self.tabs:setActive(key, emit) end
		return key
	end

	function instance:updateItem(key, patch)
		return self.tabs:updateItem(key, patch)
	end

	function instance:setBarVisible(visible)
		self.barVisible = visible ~= false
		if self.tabs then
			for _, entry in pairs(self.tabs.byKey or {}) do entry.button:setVisible(self.barVisible) end
			if self.tabs.separator then self.tabs.separator:setVisible(self.barVisible) end
			if not self.barVisible then self.tabs:hideTooltip() end
		end
		if self.bounds then self:reflow(self.bounds) end
		return self
	end

	--- Returns a detached, fully numeric content rectangle. Product consumers
	--- never inspect Navigation's mutable internal state directly.
	function instance:getContentBounds(fallback)
		return SiK.UI.Layout.resolveRect(self.contentBounds,
			fallback or self.bounds or options.bounds, 1)
	end

	function instance:reflow(bounds)
		if self.disposed then return nil, "disposed" end
		bounds = SiK.UI.Layout.resolveRect(bounds or options.bounds,
			self.bounds or { x = 0, y = 0, w = 1, h = 1 }, 1)
		local metrics = SiK.UI.Metrics.profile(bounds.w, options.profile)
		local defaultExtent = (placement == "left" or placement == "right")
			and math.max(metrics.rowHeight, number(options.sideExtent, metrics.rowHeight * 2))
			or metrics.rowHeight + SiK.UI.Metrics.spacing.xs
		local extent = math.max(1, number(options.extent or options.barSize, defaultExtent))
		local gap = math.max(0, number(options.contentGap, 0))
		local bar, content = splitBounds(bounds, placement, extent, gap)
		if self.barVisible == false then content = SiK.UI.Layout.resolveRect(bounds, nil, 1) end
		bar = SiK.UI.Layout.resolveRect(bar, bounds, 1)
		content = SiK.UI.Layout.resolveRect(content, bounds, 1)
		self.bounds, self.barBounds, self.contentBounds = bounds, bar, content
		self.tabs:reflow(bar)
		if self.barVisible == false then
			for _, entry in pairs(self.tabs.byKey or {}) do entry.button:setVisible(false) end
			if self.tabs.separator then self.tabs.separator:setVisible(false) end
		end
		for _, host in pairs(self.hosts) do
			host:reflow(content)
			if host.mountedContent then
				SiK.UI.Layout.apply(host.mountedContent, SiK.UI.Layout.resolveRect({
					x = 0, y = 0, w = host.panel.width, h = host.panel.height,
				}, nil, 1))
			end
		end
		return self
	end

	function instance:dispose()
		if self.disposed then return false end
		self.disposed = true
		if self.tabs then self.tabs:dispose(); self.tabs = nil end
		for _, host in pairs(self.hosts) do host:dispose() end
		self.hosts, self.hostOnlyKeys, self.contentHosts, self.surfaceHosts, self.items = {}, {}, {}, {}, {}
		self.parent = nil
		return true
	end

	local ok, err = instance:setItems(options.items or {})
	if not ok then instance:dispose(); return nil, err end
	instance.tabs, err = SiK.UI.Tabs.create({ parent = options.parent,
		placement = placement, items = instance.items, activeKey = options.activeKey,
		playerNum = options.playerNum, profile = options.profile, theme = options.theme,
		gap = options.itemGap or options.gap, padding = options.barPadding,
		itemExtent = options.itemExtent, iconSize = options.iconSize,
		iconFit = options.iconFit or "contain", iconPadding = options.iconPadding,
		iconOnly = options.iconOnly, tooltipMode = options.tooltipMode,
		tooltipSide = options.tooltipSide, tooltipGap = options.tooltipGap,
		tooltipBackgroundColor = options.tooltipBackgroundColor,
		tooltipBorderColor = options.tooltipBorderColor,
		tooltipTextColor = options.tooltipTextColor,
		selectionStyle = options.selectionStyle, separator = options.separator,
		separatorOffset = options.separatorOffset,
		backgroundColor = options.backgroundColor,
		selectedBackgroundColor = options.selectedBackgroundColor,
		hoverBackgroundColor = options.hoverBackgroundColor,
		pressedBackgroundColor = options.pressedBackgroundColor,
		borderColor = options.borderColor,
		selectedBorderColor = options.selectedBorderColor,
		iconColor = options.iconColor, hoverIconColor = options.hoverIconColor,
		selectedIconColor = options.selectedIconColor,
		hoverIconScale = options.hoverIconScale,
		separatorColor = options.separatorColor,
		onActivate = function(context)
			local item = context and context.value
			if item and item.key then instance.activeKey = item.key end
			if type(options.onActivate) == "function" then return options.onActivate(context) end
		end })
	if not instance.tabs then instance:dispose(); return nil, err end
	instance.barVisible = options.barVisible ~= false
	instance:setActive(options.activeKey or (instance.items[1] and instance.items[1].key), false)
	instance:reflow(options.bounds)
	return instance
end

return Navigation
