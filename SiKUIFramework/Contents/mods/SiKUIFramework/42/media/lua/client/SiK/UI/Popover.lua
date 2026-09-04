require "SiK/UI/Namespace"
require "SiK/UI/Viewport"
require "SiK/UI/FocusStack"

local Popover = SiK.UI.Popover or {}
SiK.UI.Namespace.define("Popover", Popover)

local function boundsOf(control, options)
	if type(options.anchorBounds) == "function" then return options.anchorBounds(control) end
	local x = control.getAbsoluteX and control:getAbsoluteX() or control.x or 0
	local y = control.getAbsoluteY and control:getAbsoluteY() or control.y or 0
	return { x = x, y = y, w = control.width or 0, h = control.height or 0 }
end

function Popover.attach(control, options)
	if type(control) ~= "table" then return nil, "invalid_control" end
	options = options or {}
	local trigger = options.trigger or "click"
	if trigger ~= "click" and trigger ~= "manual" and trigger ~= "passive" then
		return nil, "invalid_trigger"
	end
	local focusEnabled = options.focus
	if focusEnabled == nil then focusEnabled = trigger ~= "passive" end
	local previousUp, previousMove = control.onMouseUp, control.onMouseMove
	local previousOutside = control.onMouseMoveOutside
	local active, focus, disposed = nil, nil, false
	local handle = { control = control, playerNum = options.playerNum or 0 }
	local function close(reason)
		if not active then return false end
		if focus then focus:dispose(); focus = nil end
		if active.setVisible then active:setVisible(false) end
		if active.removeFromUIManager then active:removeFromUIManager() end
		if options.disposeContent ~= false and active.dispose then active:dispose() end
		active = nil
		if type(options.onClose) == "function" then
			options.onClose(SiK.UI.Namespace.context(control, options, "close", reason))
		end
		return true
	end
	local function position(widget)
		local anchor, safe = boundsOf(control, options), SiK.UI.Viewport.safe(handle.playerNum,
			options.environment, tonumber(options.safeMargin) or 8)
		local gap, width, height = tonumber(options.gap) or 8, widget.width or 0, widget.height or 0
		local x, y = anchor.x, anchor.y + anchor.h + gap
		if options.side == "before" then x, y = anchor.x - width - gap, anchor.y
		elseif options.side == "after" then x, y = anchor.x + anchor.w + gap, anchor.y
		elseif options.side == "above" then y = anchor.y - height - gap end
		x = math.max(safe.x, math.min(x, safe.x + safe.w - width))
		y = math.max(safe.y, math.min(y, safe.y + safe.h - height))
		if widget.setX then widget:setX(x) else widget.x = x end
		if widget.setY then widget:setY(y) else widget.y = y end
		return widget
	end
	local function open()
		if disposed then return nil, "disposed" end
		if active then position(active); return active end
		if type(options.factory) ~= "function" then return nil, "missing_factory" end
		local ok, widget = pcall(options.factory,
			SiK.UI.Namespace.context(control, options, "open"))
		if not ok or type(widget) ~= "table" then return nil, "factory_failed" end
		active = widget; position(active)
		if active.addToUIManager then active:addToUIManager() end
		if active.setVisible then active:setVisible(true) end
		if active.bringToTop then active:bringToTop() end
		if focusEnabled then
			focus = SiK.UI.FocusStack.install(active, function() close("escape"); return true end,
				{ playerNum = handle.playerNum, priority = SiK.UI.FocusStack.PRIORITY.TRANSIENT })
		end
		if type(options.onOpen) == "function" then
			options.onOpen(SiK.UI.Namespace.context(control, options, "open", active))
		end
		return active
	end
	local clickWrapper = function(self, ...)
		local result = type(previousUp) == "function" and previousUp(self, ...) or nil
		if result == true then return result end
		if active then close("toggle") else open() end
		return options.consumeTrigger == false and result or true
	end
	local moveWrapper = function(self, ...)
		local result = type(previousMove) == "function" and previousMove(self, ...) or nil
		open(); return result
	end
	local outsideWrapper = function(self, ...)
		local result = type(previousOutside) == "function" and previousOutside(self, ...) or nil
		close("pointer-outside"); return result
	end
	if trigger == "click" then control.onMouseUp = clickWrapper
	elseif trigger == "passive" then
		control.onMouseMove, control.onMouseMoveOutside = moveWrapper, outsideWrapper
	end
	handle.trigger, handle.focusEnabled = trigger, focusEnabled
	function handle:open() return open() end
	function handle:close(reason) return close(reason or "explicit") end
	function handle:toggle() if active then close("toggle"); return nil end; return open() end
	function handle:reposition() return active and position(active) or nil end
	function handle:getActive() return active end
	function handle:dispose()
		if disposed then return false end
		disposed = true; close("dispose")
		if control.onMouseUp == clickWrapper then control.onMouseUp = previousUp end
		if control.onMouseMove == moveWrapper then control.onMouseMove = previousMove end
		if control.onMouseMoveOutside == outsideWrapper then
			control.onMouseMoveOutside = previousOutside
		end
		return true
	end
	return handle
end

return Popover
