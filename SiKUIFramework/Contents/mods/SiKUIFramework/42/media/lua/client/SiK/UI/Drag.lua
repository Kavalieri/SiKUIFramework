require "SiK/UI/Namespace"
require "SiK/UI/FocusStack"

local Drag = SiK.UI.Drag or {}
SiK.UI.Namespace.define("Drag", Drag)

local activeByPlayer = {}

local function playerKey(playerNum)
	return tostring(math.max(0, math.floor(tonumber(playerNum) or 0)))
end

local function pointer(x, y)
	return tonumber(x) or (type(getMouseX) == "function" and getMouseX()) or 0,
		tonumber(y) or (type(getMouseY) == "function" and getMouseY()) or 0
end

function Drag.active(playerNum)
	return activeByPlayer[playerKey(playerNum)]
end

function Drag.begin(options)
	options = options or {}
	local playerNum = math.max(0, math.floor(tonumber(options.playerNum) or 0))
	local key = playerKey(playerNum)
	local previous = activeByPlayer[key]
	if previous then previous:cancel("replaced") end
	local x, y = pointer(options.x, options.y)
	local session = {
		playerNum = playerNum,
		payload = options.payload,
		startX = x, startY = y, x = x, y = y,
		options = options,
	}
	if type(options.createGhost) == "function" then
		local ok, ghost = pcall(options.createGhost,
			SiK.UI.Namespace.context(session, options, "begin", { x = x, y = y }))
		if ok then session.ghost = ghost end
	end
	local focus = SiK.UI.FocusStack.push({
		owner = session, playerNum = playerNum, priority = options.priority or 100,
		onEscape = function() session:cancel("escape"); return true end,
	})
	session.focusLayer = focus

	function session:update(nextX, nextY)
		if self.disposed then return false end
		nextX, nextY = pointer(nextX, nextY)
		self.x, self.y = nextX, nextY
		if self.ghost then
			if self.ghost.moveTo then self.ghost:moveTo(nextX, nextY)
			elseif self.ghost.setX and self.ghost.setY then
				self.ghost:setX(nextX); self.ghost:setY(nextY)
			end
		end
		if type(options.onMove) == "function" then
			options.onMove(SiK.UI.Namespace.context(self, options, "move", {
				x = nextX, y = nextY, dx = nextX - self.startX, dy = nextY - self.startY,
			}))
		end
		return true
	end

	function session:finish(eventName, reason)
		if self.disposed then return false end
		local callback = eventName == "drop" and options.onDrop or options.onCancel
		if type(callback) == "function" then
			callback(SiK.UI.Namespace.context(self, options, eventName, {
				x = self.x, y = self.y, dx = self.x - self.startX,
				dy = self.y - self.startY, reason = reason,
			}))
		end
		self:dispose()
		return true
	end
	function session:drop(reason) return self:finish("drop", reason) end
	function session:cancel(reason) return self:finish("cancel", reason) end
	function session:dispose()
		if self.disposed then return false end
		self.disposed = true
		if self.focusLayer then self.focusLayer:dispose(); self.focusLayer = nil end
		if self.ghost then
			if self.ghost.dispose then self.ghost:dispose()
			elseif self.ghost.removeFromUIManager then self.ghost:removeFromUIManager() end
			self.ghost = nil
		end
		if activeByPlayer[key] == self then activeByPlayer[key] = nil end
		return true
	end
	activeByPlayer[key] = session
	if type(options.onBegin) == "function" then
		options.onBegin(SiK.UI.Namespace.context(session, options, "begin", { x = x, y = y }))
	end
	return session
end

function Drag.bind(control, options)
	if type(control) ~= "table" then return nil, "invalid_control" end
	options = options or {}
	local previousDown = control.onMouseDown
	local previousMove = control.onMouseMove
	local previousUp = control.onMouseUp
	local binding = { control = control }
	local downWrapper = function(self, x, y, ...)
		local result = type(previousDown) == "function" and previousDown(self, x, y, ...) or nil
		local allowed = result ~= true
		if type(options.canStart) == "function" then
			local ok, value = pcall(options.canStart,
				SiK.UI.Namespace.context(self, options, "canStart", { x = x, y = y }))
			allowed = ok and value ~= false
		end
		if allowed then
		local dragOptions = {}
			for key, value in pairs(options) do dragOptions[key] = value end
			if options.coordinateSpace == "local" then dragOptions.x, dragOptions.y = x, y
			else dragOptions.x, dragOptions.y = nil, nil end
			binding.session = Drag.begin(dragOptions)
		end
		return result
	end
	local moveWrapper = function(self, x, y, ...)
		local result = type(previousMove) == "function" and previousMove(self, x, y, ...) or nil
		if binding.session then binding.session:update(x, y) end
		return result
	end
	local upWrapper = function(self, x, y, ...)
		local result = type(previousUp) == "function" and previousUp(self, x, y, ...) or nil
		if binding.session then
			binding.session:update(x, y); binding.session:drop("mouseUp")
			binding.session = nil
		end
		return result
	end
	control.onMouseDown, control.onMouseMove, control.onMouseUp = downWrapper, moveWrapper, upWrapper
	function binding:dispose()
		if self.disposed then return false end
		self.disposed = true
		if self.session then self.session:cancel("disposed"); self.session = nil end
		if control.onMouseDown == downWrapper then control.onMouseDown = previousDown end
		if control.onMouseMove == moveWrapper then control.onMouseMove = previousMove end
		if control.onMouseUp == upWrapper then control.onMouseUp = previousUp end
		return true
	end
	return binding
end

return Drag
