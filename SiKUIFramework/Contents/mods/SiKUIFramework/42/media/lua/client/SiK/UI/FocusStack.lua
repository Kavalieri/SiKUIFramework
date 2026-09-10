require "SiK/UI/Namespace"

local FocusStack = SiK.UI.FocusStack or {}
SiK.UI.Namespace.define("FocusStack", FocusStack)

-- Neutral stacking bands. Products choose a band but keep ownership and
-- behaviour in their own callback; the framework only orders visible layers.
FocusStack.PRIORITY = FocusStack.PRIORITY or {
	STAFF = 100,
	TERMINAL = 200,
	MODAL = 300,
	TRANSIENT = 400,
}

local stacks = {}
local sequence = 0
local installations = setmetatable({}, { __mode = "k" })

local function playerKey(playerNum)
	return tostring(math.max(0, math.floor(tonumber(playerNum) or 0)))
end

local function stackFor(playerNum, create)
	local key = playerKey(playerNum)
	local stack = stacks[key]
	if not stack and create then stack = {}; stacks[key] = stack end
	return stack
end

local function isVisible(layer)
	if layer.disposed or layer.enabled == false then return false end
	if type(layer.isVisible) == "function" then
		local ok, value = pcall(layer.isVisible, layer.owner)
		return ok and value ~= false
	end
	local owner = layer.owner
	if owner and owner.getIsVisible then return owner:getIsVisible() ~= false end
	if owner and owner.visible ~= nil then return owner.visible ~= false end
	return true
end

local function removeLayer(layer)
	local stack = stackFor(layer.playerNum, false)
	if not stack then return false end
	for index = #stack, 1, -1 do
		if stack[index] == layer then table.remove(stack, index); return true end
	end
	return false
end

function FocusStack.push(options)
	options = options or {}
	if type(options.onEscape) ~= "function" then return nil, "missing_escape_handler" end
	sequence = sequence + 1
	local layer = {
		owner = options.owner,
		playerNum = math.max(0, math.floor(tonumber(options.playerNum) or 0)),
		priority = tonumber(options.priority) or 0,
		sequence = sequence,
		onEscape = options.onEscape,
		isVisible = options.isVisible,
		enabled = options.enabled ~= false,
	}
	local stack = stackFor(layer.playerNum, true)
	stack[#stack + 1] = layer
	function layer:setEnabled(value) self.enabled = value ~= false end
	function layer:dispose()
		if self.disposed then return false end
		self.disposed = true
		removeLayer(self)
		return true
	end
	return layer
end

function FocusStack.top(playerNum)
	local stack = stackFor(playerNum, false)
	local best = nil
	if not stack then return nil end
	for index = 1, #stack do
		local layer = stack[index]
		-- Every visible layer joins with a monotonic opening sequence, and an
		-- explicit activation receives a newer one.  This makes a clicked window
		-- the Escape target even when another visible layer chose a higher legacy
		-- band; priority remains descriptive compatibility metadata only.
		if isVisible(layer) and (not best or layer.sequence > best.sequence) then
			best = layer
		end
	end
	return best
end

function FocusStack.isTop(owner, playerNum)
	local layer = FocusStack.top(playerNum)
	return layer ~= nil and layer.owner == owner
end

--- Makes an installed visible layer the newest peer without changing its band.
function FocusStack.activate(owner, playerNum)
	local stack = stackFor(playerNum, false)
	if not stack then return false end
	for index = 1, #stack do
		local layer = stack[index]
		if layer.owner == owner and isVisible(layer) then
			sequence = sequence + 1
			layer.sequence = sequence
			return true
		end
	end
	return false
end

local function windowOf(owner)
	local current, visited = owner, {}
	while type(current) == "table" and not visited[current] do
		visited[current] = true
		if current._sikWindowApplied then return current end
		current = current._sikFocusOwner or current._sikModalOwner or current.parent
	end
	return nil
end

function FocusStack.activeWindow(playerNum)
	local layer = FocusStack.top(playerNum)
	return layer and windowOf(layer.owner) or nil
end

function FocusStack.handleEscape(playerNum)
	local layer = FocusStack.top(playerNum)
	if not layer then return false end
	local ok, consumed = pcall(layer.onEscape, layer.owner, layer)
	return ok and consumed ~= false
end

function FocusStack.remove(owner, playerNum)
	local stack = stackFor(playerNum, false)
	if not stack then return false end
	local removed = false
	local snapshot = {}
	for index = 1, #stack do snapshot[index] = stack[index] end
	for index = 1, #snapshot do
		if snapshot[index].owner == owner then snapshot[index]:dispose(); removed = true end
	end
	return removed
end

local function escapeKey(key)
	if type(Keyboard) == "table" and Keyboard.KEY_ESCAPE ~= nil then
		return key == Keyboard.KEY_ESCAPE
	end
	return key == 1 or key == 27
end

function FocusStack.install(owner, onEscape, options)
	options = options or {}
	if type(owner) ~= "table" then return nil, "invalid_owner" end
	if type(onEscape) ~= "function" then return nil, "missing_escape_handler" end
	local existing = installations[owner]
	if existing and not existing.disposed then return existing end

	local state = {
		owner = owner,
		playerNum = math.max(0, math.floor(tonumber(options.playerNum) or 0)),
		priority = tonumber(options.priority) or 0,
		onEscape = onEscape,
		isVisible = options.isVisible,
	}
	installations[owner] = state
	local previousPress = owner.onKeyPress
	local previousRelease = owner.onKeyRelease
	local previousConsumed = owner.isKeyConsumed
	local previousSetVisible = owner.setVisible
	local previousRemove = owner.removeFromUIManager

	local function unregister()
		if state.layer then state.layer:dispose(); state.layer = nil end
	end
	local function register()
		if state.disposed or (state.layer and not state.layer.disposed) then return state.layer end
		local layer, err = FocusStack.push({ owner = owner,
			playerNum = state.playerNum, priority = state.priority,
			isVisible = state.isVisible,
			onEscape = function(layerOwner, activeLayer)
				unregister()
				return state.onEscape(layerOwner, activeLayer)
			end,
		})
		if not layer then return nil, err end
		state.layer = layer
		return layer
	end
	local function cancelPendingEscape()
		local callback = state.pendingEscapeTick
		state.pendingEscapeTick = nil
		if callback and Events and Events.OnTick and Events.OnTick.Remove then
			Events.OnTick.Remove(callback)
		end
	end
	local function executeArmedEscape()
		if state.disposed then return false end
		-- Focus may legitimately change between key-up and the next UI update.
		-- Never close whichever layer replaced the one that armed this pulse.
		if not FocusStack.isTop(owner, state.playerNum) then return false end
		return FocusStack.handleEscape(state.playerNum)
	end
	local function deferArmedEscape()
		if state.pendingEscapeTick then return true end
		if Events and Events.OnTick and Events.OnTick.Add and Events.OnTick.Remove then
			local callback
			callback = function()
				Events.OnTick.Remove(callback)
				if state.pendingEscapeTick ~= callback then return end
				state.pendingEscapeTick = nil
				executeArmedEscape()
			end
			state.pendingEscapeTick = callback
			Events.OnTick.Add(callback)
			return true
		end
		-- Pure-Lua harnesses and non-PZ consumers have no event bus. Preserve the
		-- deterministic fallback while the game runtime uses the pulse barrier.
		return executeArmedEscape()
	end
	local pressWrapper = function(self, key, ...)
		if escapeKey(key) and (state.pendingEscapeTick
			or FocusStack.isTop(self, state.playerNum)) then
			-- Keep this owner installed until key-up. Closing on key-down restores
			-- the previous callbacks too early and the same physical pulse can then
			-- reach vanilla and open the pause menu.
			state.handledOnPress = true
			return true
		end
		if type(previousPress) == "function" then return previousPress(self, key, ...) end
		return false
	end
	local releaseWrapper = function(self, key, ...)
		if escapeKey(key) and state.pendingEscapeTick then return true end
		if escapeKey(key) and state.handledOnPress then
			state.handledOnPress = nil
			-- Do not close a different layer if focus changed during the pulse. The
			-- key remains consumed either way, and the next pulse targets the new top.
			if FocusStack.isTop(self, state.playerNum) then
				deferArmedEscape()
			end
			return true
		end
		if type(previousRelease) == "function" then return previousRelease(self, key, ...) end
		return false
	end
	local consumedWrapper = function(self, key)
		if escapeKey(key) and (state.handledOnPress or state.pendingEscapeTick
			or FocusStack.isTop(self, state.playerNum)) then return true end
		if type(previousConsumed) == "function" then return previousConsumed(self, key) end
		return false
	end
	local visibleWrapper = nil
	if type(previousSetVisible) == "function" then
		visibleWrapper = function(self, visible)
			local result = previousSetVisible(self, visible)
			if visible == false then unregister()
			else register() end
			if self.setWantKeyEvents then self:setWantKeyEvents(visible ~= false) end
			return result
		end
	end
	local removeWrapper = nil
	if type(previousRemove) == "function" then
		removeWrapper = function(self, ...)
			state:dispose()
			return previousRemove(self, ...)
		end
	end

	owner.onKeyPress = pressWrapper
	owner.onKeyRelease = releaseWrapper
	owner.isKeyConsumed = consumedWrapper
	if visibleWrapper then owner.setVisible = visibleWrapper end
	if removeWrapper then owner.removeFromUIManager = removeWrapper end
	function state:dispose()
		if self.disposed then return false end
		self.disposed = true
		cancelPendingEscape()
		unregister()
		if owner.onKeyPress == pressWrapper then owner.onKeyPress = previousPress end
		if owner.onKeyRelease == releaseWrapper then owner.onKeyRelease = previousRelease end
		if owner.isKeyConsumed == consumedWrapper then owner.isKeyConsumed = previousConsumed end
		if visibleWrapper and owner.setVisible == visibleWrapper then owner.setVisible = previousSetVisible end
		if removeWrapper and owner.removeFromUIManager == removeWrapper then
			owner.removeFromUIManager = previousRemove
		end
		if installations[owner] == self then installations[owner] = nil end
		if owner.setWantKeyEvents then owner:setWantKeyEvents(false) end
		return true
	end
	if owner.setWantKeyEvents then owner:setWantKeyEvents(true) end
	local layer, err = register()
	if not layer then state:dispose(); return nil, err end
	return state
end

function FocusStack.clearPlayer(playerNum)
	local stack = stackFor(playerNum, false)
	if not stack then return end
	local snapshot = {}
	for index = 1, #stack do snapshot[index] = stack[index] end
	for index = 1, #snapshot do
		local layer = snapshot[index]
		local installation = layer.owner and installations[layer.owner] or nil
		if installation and installation.playerNum == layer.playerNum then
			installation:dispose()
		else
			layer:dispose()
		end
	end
	stacks[playerKey(playerNum)] = nil
end

return FocusStack
