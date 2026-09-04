require "SiK/UI/Namespace"

local Menu = SiK.UI.Menu or {}
SiK.UI.Namespace.define("Menu", Menu)

local function menuContext(playerNum, x, y, supplied)
	if supplied then return supplied end
	if type(ISContextMenu) == "table" and type(ISContextMenu.get) == "function" then
		local ok, value = pcall(ISContextMenu.get, playerNum, x, y)
		if ok then return value end
	end
	return nil
end

local function invoke(instance, item, target)
	if item.enabled == false or type(item.onSelect) ~= "function" then return end
	return item.onSelect(SiK.UI.Namespace.context(instance, {
		playerNum = instance.playerNum, payload = item.payload or instance.payload,
	}, "select", target))
end

local function populate(instance, context, items)
	for index = 1, #items do
		local item = items[index]
		local option = context:addOption(tostring(item.text or ""),
			item.target or instance, function(target) return invoke(instance, item, target) end)
		if option and item.enabled == false then option.notAvailable = true end
		if option and item.tooltip ~= nil then option.toolTip = item.tooltip end
		if option and item.checked ~= nil then option.checkMark = item.checked == true end
		if option and type(item.items) == "table" and #item.items > 0
			and type(context.getNew) == "function" and type(context.addSubMenu) == "function" then
			local ok, child = pcall(context.getNew, context, context)
			if ok and child then
				populate(instance, child, item.items)
				context:addSubMenu(option, child)
			end
		end
	end
end

function Menu.create(options)
	options = options or {}
	local instance = {
		playerNum = math.max(0, math.floor(tonumber(options.playerNum) or 0)),
		payload = options.payload,
		items = {},
	}
	function instance:add(item)
		if type(item) ~= "table" or item.text == nil then return nil, "invalid_item" end
		self.items[#self.items + 1] = item
		return item
	end
	function instance:clear() self.items = {}; return self end
	function instance:setItems(items)
		self.items = {}
		if type(items) == "table" then
			for index = 1, #items do self:add(items[index]) end
		end
		return self
	end
	function instance:show(x, y, supplied)
		if self.disposed then return nil, "disposed" end
		local context = menuContext(self.playerNum, x, y, supplied)
		if not context or type(context.addOption) ~= "function" then
			return nil, "context_unavailable"
		end
		populate(self, context, self.items)
		if context.setVisible then context:setVisible(true) end
		self.context = context
		return context
	end
	function instance:isShown() return self.context ~= nil end
	function instance:hide()
		if self.context and self.context.setVisible then self.context:setVisible(false) end
		self.context = nil
	end
	function instance:dispose()
		if self.disposed then return false end
		self:hide(); self.items = {}; self.disposed = true
		return true
	end
	if type(options.items) == "table" then
		for index = 1, #options.items do instance:add(options.items[index]) end
	end
	return instance
end

function Menu.attach(control, options)
	if options == nil and type(control) == "table" and control.control then
		options = control; control = options.control
	end
	if type(control) ~= "table" then return nil, "invalid_control" end
	options = options or {}
	local previous = control.onRightMouseUp
	local instance = Menu.create(options)
	local wrapper = function(self, x, y, ...)
		local previousResult = nil
		if type(previous) == "function" then previousResult = previous(self, x, y, ...) end
		local items = options.items
		if type(options.provider) == "function" then
			local ok, value = pcall(options.provider,
				SiK.UI.Namespace.context(self, options, "menu"))
			if ok then items = value end
		end
		instance:clear()
		if type(items) == "table" then
			for index = 1, #items do instance:add(items[index]) end
		end
		if #instance.items > 0 then instance:show(x, y, options.context) end
		return previousResult
	end
	control.onRightMouseUp = wrapper
	local instanceDispose = instance.dispose
	instance.dispose = function(self)
		if self.disposed then return false end
		if control.onRightMouseUp == wrapper then control.onRightMouseUp = previous end
		return instanceDispose(self)
	end
	return instance
end

--- Lifecycle-neutral vanilla side-menu extension. The consumer supplies its
--- own asset and action; the framework only owns mounting, visibility and cleanup.
function Menu.sideMenuExtension(options)
	options = options or {}
	if type(options.mount) ~= "function" then return nil, "side_menu_mount_required" end
	if type(options.action) ~= "function" then return nil, "side_menu_action_required" end
	if options.asset == nil then return nil, "side_menu_asset_required" end
	local instance = { asset = options.asset, action = options.action, tooltip = options.tooltip,
		variant = options.variant, visible = options.visible ~= false }
	function instance:mount(anchor)
		if self.disposed then return nil, "disposed" end
		self.control = options.mount(anchor, { asset = self.asset, action = self.action,
			tooltip = self.tooltip, variant = self.variant, visible = self.visible,
			assetSize = options.assetSize })
		return self.control
	end
	function instance:setVisible(value)
		self.visible = value == true
		if self.control and self.control.setVisible then self.control:setVisible(self.visible) end
		return self
	end
	function instance:dispose()
		if self.disposed then return false end
		if type(options.unmount) == "function" then options.unmount(self.control) end
		self.control, self.disposed = nil, true; return true
	end
	return instance
end

return Menu
