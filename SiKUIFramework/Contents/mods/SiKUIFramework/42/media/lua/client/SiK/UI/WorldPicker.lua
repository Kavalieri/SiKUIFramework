require "ISUI/ISPanel"
require "SiK/UI/Namespace"
require "SiK/UI/Viewport"
require "SiK/UI/FocusStack"
require "SiK/UI/Lifecycle"

local WorldPicker = SiK.UI.WorldPicker or {}
SiK.UI.Namespace.define("WorldPicker", WorldPicker)

function WorldPicker.create(options)
	options = options or {}
	local playerNum = tonumber(options.playerNum) or 0
	local bounds = options.bounds or SiK.UI.Viewport.safe(playerNum, options.environment, 0)
	local multiStep = options.multiStep == true
	local steps = {}
	local resolved = false
	local panel = ISPanel:new(bounds.x, bounds.y, bounds.w, bounds.h)
	panel:initialise(); if panel.instantiate then panel:instantiate() end
	panel.playerNum, panel._sikWorldPicker, panel._sikPicking = playerNum, true, false
	panel.backgroundColor, panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }, { r = 0, g = 0, b = 0, a = 0 }
	local focus = nil
	local function context(self, phase, x, y)
		local point = { screenX = x, screenY = y, playerNum = playerNum }
		if type(options.resolvePoint) == "function" then
			local resolved = options.resolvePoint(point)
			if resolved ~= nil then point = resolved end
		end
		return SiK.UI.Namespace.context(self, options, phase, point)
	end
	local refresh = SiK.UI.Lifecycle.bindVisibleRefresh(panel, {
		active = false, intervalTicks = options.intervalTicks,
		refresh = function(ctx)
			if type(options.onRefresh) == "function" then options.onRefresh(ctx) end
		end,
	})
	local function snapshotSteps()
		local snapshot = {}
		for index = 1, #steps do snapshot[index] = steps[index] end
		return snapshot
	end
	local function releaseCapture(self)
		self._sikPicking = false; refresh:setActive(false)
		if self.setCapture then self:setCapture(false) end
	end
	local function hideResolved(self, phase)
		if (phase == "cancel" or options.keepOpen ~= true) and self.setVisible then
			self:setVisible(false)
		end
	end
	local function stop(self, phase, x, y, reason)
		if resolved then return false end
		if phase ~= "cancel" and not self._sikPicking then return false end
		resolved = true
		releaseCapture(self)
		local callback = phase == "confirm" and options.onConfirm or options.onCancel
		if type(callback) == "function" then
			local callbackContext = multiStep
				and SiK.UI.Namespace.context(self, options, phase,
					{ reason = reason, steps = snapshotSteps() })
				or reason ~= nil
				and SiK.UI.Namespace.context(self, options, phase, { reason = reason })
				or context(self, phase, x, y)
			callback(callbackContext)
		end
		if multiStep and phase == "cancel" then
			for index = #steps, 1, -1 do steps[index] = nil end
		end
		hideResolved(self, phase)
		return true
	end
	local function complete(self, result)
		if not multiStep then return nil, "not_multi_step" end
		if resolved then return false end
		resolved = true
		releaseCapture(self)
		if type(options.onConfirm) == "function" then
			options.onConfirm(SiK.UI.Namespace.context(self, options, "confirm",
				{ steps = snapshotSteps(), result = result }))
		end
		hideResolved(self, "confirm")
		return true
	end
	function panel:onMouseDown(x, y)
		if resolved then
			if options.keepOpen ~= true then return false end
			resolved = false
		end
		self._sikPicking = true; refresh:setActive(true)
		if self.setCapture then self:setCapture(true) end
		if type(options.onStart) == "function" then options.onStart(context(self, "start", x, y)) end
		return true
	end
	function panel:onMouseMove(x, y)
		if self._sikPicking and type(options.onMove) == "function" then
			options.onMove(context(self, "move", x, y))
		end
		return self._sikPicking
	end
	panel.onMouseMoveOutside = panel.onMouseMove
	function panel:onMouseUp(x, y)
		if not multiStep then return stop(self, "confirm", x, y) end
		if not self._sikPicking then return false end
		releaseCapture(self)
		local point = context(self, "step", x, y).value
		steps[#steps + 1] = point
		local result = nil
		if type(options.onStep) == "function" then
			result = options.onStep(SiK.UI.Namespace.context(self, options, "step",
				{ point = point, stepIndex = #steps, steps = snapshotSteps() }))
		end
		local completeNow = result == "complete"
			or (type(result) == "table" and result.complete == true)
			or (tonumber(options.stepsRequired) and #steps >= math.max(1,
				math.floor(tonumber(options.stepsRequired))))
		if completeNow then
			return complete(self, type(result) == "table" and result.value or nil)
		end
		return true
	end
	panel.onMouseUpOutside = panel.onMouseUp
	function panel:onRightMouseUp(x, y) stop(self, "cancel", x, y); return true end
	function panel:show()
		if self._sikDisposed then return nil, "disposed" end
		resolved = false
		if self.addToUIManager then self:addToUIManager() end
		if self.setVisible then self:setVisible(true) end
		if self.bringToTop then self:bringToTop() end
		return self
	end
	function panel:cancel(reason)
		return stop(self, "cancel", nil, nil, reason)
	end
	function panel:complete(result) return complete(self, result) end
	function panel:getSteps() return snapshotSteps() end
	function panel:clearSteps()
		for index = #steps, 1, -1 do steps[index] = nil end
		return self
	end
	local previousRender = panel.render
	function panel:render()
		if type(previousRender) == "function" then previousRender(self) end
		if type(options.onRender) == "function" then options.onRender(context(self, "render")) end
	end
	focus = SiK.UI.FocusStack.install(panel, function() panel:cancel("escape"); return true end,
		{ playerNum = playerNum, priority = SiK.UI.FocusStack.PRIORITY.TRANSIENT })
	local previousDispose = panel.dispose
	function panel:dispose()
		if self._sikDisposed then return false end
		self._sikDisposed = true
		if focus then focus:dispose(); focus = nil end
		if refresh then refresh:dispose(); refresh = nil end
		if self.setCapture then self:setCapture(false) end
		if type(previousDispose) == "function" and previousDispose ~= self.dispose then previousDispose(self) end
		if self.removeFromUIManager then self:removeFromUIManager() end
		return true
	end
	if options.autoShow ~= false then panel:show() else panel:setVisible(false) end
	return panel
end

return WorldPicker
