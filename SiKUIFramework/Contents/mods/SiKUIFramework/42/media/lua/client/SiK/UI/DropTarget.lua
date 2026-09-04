require "SiK/UI/Namespace"
require "SiK/UI/Theme"
require "SiK/UI/Drag"

local DropTarget = SiK.UI.DropTarget or {}
SiK.UI.Namespace.define("DropTarget", DropTarget)

function DropTarget.attach(control, options)
	if type(control) ~= "table" then return nil, "invalid_control" end
	options = options or {}
	local provider = options.dragProvider
	if provider ~= nil and type(provider) ~= "function"
		and not (type(provider) == "table" and type(provider.active) == "function") then
		return nil, "invalid_drag_provider"
	end
	local enabled, over, disposed = options.enabled ~= false, false, false
	local previousMove, previousOutside = control.onMouseMove, control.onMouseMoveOutside
	local previousUp, previousRender = control.onMouseUp, control.render
	local previousVisible, previousRemove = control.setVisible, control.removeFromUIManager
	local handle = { control = control, playerNum = options.playerNum or 0 }
	local function isVisible()
		if control.getIsVisible then return control:getIsVisible() ~= false end
		return control.visible ~= false
	end
	local function session()
		if not enabled or not isVisible() then return nil end
		if provider == nil then return SiK.UI.Drag.active(handle.playerNum) end
		local ok, value
		if type(provider) == "function" then ok, value = pcall(provider, handle.playerNum, control)
		else ok, value = pcall(provider.active, provider, handle.playerNum, control) end
		if not ok then handle.lastError = "drag_provider_failed"; return nil end
		handle.lastError = nil; return value
	end
	local function accepted(active)
		if not enabled or not active then return false end
		if type(options.accept) ~= "function" then return true end
		return options.accept(active.payload,
			SiK.UI.Namespace.context(control, options, "accept", active)) ~= false
	end
	local function setOver(value, active)
		value = value == true
		if over == value then return end
		over = value
		local callback = value and options.onEnter or options.onLeave
		if type(callback) == "function" then
			callback(active and active.payload,
				SiK.UI.Namespace.context(control, options, value and "enter" or "leave", active))
		end
	end
	local moveWrapper = function(self, ...)
		local result = type(previousMove) == "function" and previousMove(self, ...) or nil
		local active = session(); setOver(accepted(active), active)
		if over and type(options.onOver) == "function" then
			options.onOver(active.payload, SiK.UI.Namespace.context(self, options, "over", active))
		end
		return result
	end
	local outsideWrapper = function(self, ...)
		local result = type(previousOutside) == "function" and previousOutside(self, ...) or nil
		setOver(false, session()); return result
	end
	local upWrapper = function(self, ...)
		local active = session()
		if over and accepted(active) then
			local result = true
			if type(options.onDrop) == "function" then
				result = options.onDrop(active.payload,
					SiK.UI.Namespace.context(self, options, "drop", active))
			end
			setOver(false, active)
			if result ~= false then
				if type(options.finishDrag) == "function" then
					options.finishDrag(active, "drop-target")
				elseif type(active.drop) == "function" then active:drop("drop-target") end
				return true
			end
		end
		return type(previousUp) == "function" and previousUp(self, ...) or nil
	end
	local renderWrapper = function(self)
		if type(previousRender) == "function" then previousRender(self) end
		if over and options.highlight ~= false and self.drawRectBorder then
			local color = SiK.UI.Theme.color(options.tone or "accent", options.theme)
			self:drawRectBorder(0, 0, self.width or 0, self.height or 0,
				color.a, color.r, color.g, color.b)
		end
	end
	control.onMouseMove, control.onMouseMoveOutside = moveWrapper, outsideWrapper
	control.onMouseUp, control.render = upWrapper, renderWrapper
	local visibleWrapper = function(self, value)
		local result = type(previousVisible) == "function" and previousVisible(self, value) or nil
		if value == false then setOver(false, session()) end
		return result
	end
	local removeWrapper = function(self, ...)
		setOver(false, session())
		return type(previousRemove) == "function" and previousRemove(self, ...) or nil
	end
	if previousVisible then control.setVisible = visibleWrapper end
	if previousRemove then control.removeFromUIManager = removeWrapper end
	function handle:setEnabled(value) enabled = value ~= false; if not enabled then setOver(false) end; return self end
	function handle:isOver() return over end
	function handle:getSession() return session() end
	function handle:sync()
		local active = session()
		if over then setOver(accepted(active), active) end
		return active
	end
	function handle:dispose()
		if disposed then return false end
		disposed = true; setOver(false, session())
		if control.onMouseMove == moveWrapper then control.onMouseMove = previousMove end
		if control.onMouseMoveOutside == outsideWrapper then control.onMouseMoveOutside = previousOutside end
		if control.onMouseUp == upWrapper then control.onMouseUp = previousUp end
		if control.render == renderWrapper then control.render = previousRender end
		if control.setVisible == visibleWrapper then control.setVisible = previousVisible end
		if control.removeFromUIManager == removeWrapper then control.removeFromUIManager = previousRemove end
		return true
	end
	return handle
end

-- Observes an external drag source (for example PZ's vanilla inventory drag)
-- without leaving a permanent tick handler behind.  Product code supplies the
-- payload and acceptance callbacks; SiK UI owns registration and cleanup.
function DropTarget.monitor(control, options)
	if type(control) ~= "table" then return nil, "invalid_control" end
	options = options or {}
	if type(options.isDragging) ~= "function" or type(options.payload) ~= "function"
		or type(options.isOver) ~= "function" or type(options.onDrop) ~= "function" then
		return nil, "invalid_monitor_contract"
	end
	local event = options.event or (Events and Events.OnTick)
	if type(event) ~= "table" or type(event.Add) ~= "function" or type(event.Remove) ~= "function" then
		return nil, "invalid_monitor_event"
	end
	local enabled, installed, disposed = options.enabled ~= false, false, false
	local wasDragging, pending = false, nil
	local previousVisible, previousRemove = control.setVisible, control.removeFromUIManager
	local handle = { control = control, playerNum = options.playerNum or control.playerNum or 0 }
	local function visible()
		if control.getIsVisible then return control:getIsVisible() ~= false end
		return control.visible ~= false
	end
	local function context(phase, value)
		return SiK.UI.Namespace.context(control, options, phase, value)
	end
	local function reset()
		wasDragging, pending = false, nil
	end
	local function tick()
		if disposed or not enabled or not visible() then reset(); return end
		local dragging = options.isDragging(context("probe")) == true
		if dragging then
			wasDragging = true
			if options.isOver(context("over")) == true then
				pending = options.payload(context("capture"))
			else pending = nil end
			return
		end
		if wasDragging then
			wasDragging = false
			local value = pending; pending = nil
			if value ~= nil and options.isOver(context("release", value)) == true then
				options.onDrop(value, context("drop", value))
			end
		end
	end
	function handle:start()
		if disposed or installed or not enabled then return false end
		event.Add(tick); installed = true; return true
	end
	function handle:stop()
		if not installed then reset(); return false end
		event.Remove(tick); installed = false; reset(); return true
	end
	function handle:setEnabled(value)
		enabled = value ~= false
		if enabled and visible() then self:start() else self:stop() end
		return self
	end
	function handle:isInstalled() return installed end
	function handle:dispose()
		if disposed then return false end
		self:stop(); disposed = true
		if control.setVisible == handle._visibleWrapper then control.setVisible = previousVisible end
		if control.removeFromUIManager == handle._removeWrapper then control.removeFromUIManager = previousRemove end
		return true
	end
	if previousVisible then
		handle._visibleWrapper = function(self, value)
			local result = previousVisible(self, value)
			if value == false then handle:stop() elseif enabled then handle:start() end
			return result
		end
		control.setVisible = handle._visibleWrapper
	end
	if previousRemove then
		handle._removeWrapper = function(self, ...)
			handle:dispose()
			return previousRemove(self, ...)
		end
		control.removeFromUIManager = handle._removeWrapper
	end
	if enabled and visible() then handle:start() end
	return handle
end

return DropTarget
