require "SiK/UI/Namespace"

local Lifecycle = SiK.UI.Lifecycle or {}
SiK.UI.Namespace.define("Lifecycle", Lifecycle)

local function disposeOwned(resource)
	if type(resource) == "function" then
		return pcall(resource)
	end
	if type(resource) == "table" and type(resource.dispose) == "function" then
		return pcall(resource.dispose, resource)
	end
	return false, "invalid_resource"
end

--- Makes a UI owner responsible for disposing a reusable component or cleanup
--- callback. Resources are released once, in reverse registration order, and a
--- failing cleanup never prevents the remaining resources or the owner's prior
--- dispose implementation from running.
function Lifecycle.own(owner, resource)
	if type(owner) ~= "table" then return nil, "invalid_owner" end
	if type(resource) ~= "function"
		and not (type(resource) == "table" and type(resource.dispose) == "function") then
		return nil, "invalid_resource"
	end
	if owner._sikOwnedDisposed then return nil, "owner_disposed" end
	owner._sikOwnedResources = owner._sikOwnedResources or {}
	owner._sikOwnedResources[#owner._sikOwnedResources + 1] = resource
	if owner._sikOwnedDisposeInstalled then return resource end

	local previousDispose = owner.dispose
	local wrapper
	wrapper = function(self, ...)
		if self._sikOwnedDisposed then return false end
		self._sikOwnedDisposed = true
		local resources = self._sikOwnedResources or {}
		self._sikOwnedResources = nil
		for index = #resources, 1, -1 do disposeOwned(resources[index]) end
		self._sikOwnedDisposeInstalled = nil
		if type(previousDispose) == "function" and previousDispose ~= wrapper then
			return previousDispose(self, ...)
		end
		return true
	end
	owner.dispose = wrapper
	owner._sikOwnedDisposeInstalled = true
	return resource
end

local function visible(owner)
	if not owner then return false end
	if owner.getIsVisible then return owner:getIsVisible() ~= false end
	return owner.visible ~= false
end

function Lifecycle.bindVisibleRefresh(owner, options)
	if type(owner) ~= "table" then return nil, "invalid_owner" end
	options = options or {}
	local refresh = options.refresh or options.onRefresh
	if type(refresh) ~= "function" then return nil, "missing_refresh" end
	local interval = math.max(1, math.floor(tonumber(options.intervalTicks) or 1))
	local active, installed, disposed, ticks = options.active ~= false, false, false, 0
	local event = type(Events) == "table" and Events.OnTick or nil
	local previousSetVisible = owner.setVisible
	local previousAdd, previousRemove = owner.addToUIManager, owner.removeFromUIManager

	local function invoke(reason)
		if disposed or not active or not visible(owner) then return false end
		refresh(SiK.UI.Namespace.context(owner, options, reason or "refresh"))
		return true
	end
	local function onTick()
		if not active or not visible(owner) then return end
		ticks = ticks + 1
		if ticks >= interval then ticks = 0; invoke("tick") end
	end
	local function removeTick()
		if installed and event and type(event.Remove) == "function" then event.Remove(onTick) end
		installed = false
	end
	local function sync()
		local shouldInstall = not disposed and active and visible(owner)
			and event and type(event.Add) == "function" and type(event.Remove) == "function"
		if shouldInstall and not installed then event.Add(onTick); installed = true
		elseif not shouldInstall then removeTick() end
		return installed and "event" or "manual"
	end
	local visibleWrapper = function(self, value)
		local result = nil
		if type(previousSetVisible) == "function" then result = previousSetVisible(self, value)
		else self.visible = value end
		sync()
		return result
	end
	owner.setVisible = visibleWrapper
	local addWrapper = function(self, ...)
		local result = type(previousAdd) == "function" and previousAdd(self, ...) or nil
		sync(); return result
	end
	local removeWrapper = function(self, ...)
		removeTick()
		return type(previousRemove) == "function" and previousRemove(self, ...) or nil
	end
	if previousAdd then owner.addToUIManager = addWrapper end
	if previousRemove then owner.removeFromUIManager = removeWrapper end
	local handle = { owner = owner }
	function handle:refresh(reason) return invoke(reason or "manual") end
	function handle:sync() return sync() end
	function handle:setActive(value) active = value ~= false; sync(); return self end
	function handle:isActive() return active and not disposed end
	function handle:mode() return installed and "event" or "manual" end
	function handle:dispose()
		if disposed then return false end
		disposed = true; removeTick()
		if owner.setVisible == visibleWrapper then owner.setVisible = previousSetVisible end
		if owner.addToUIManager == addWrapper then owner.addToUIManager = previousAdd end
		if owner.removeFromUIManager == removeWrapper then owner.removeFromUIManager = previousRemove end
		return true
	end
	sync()
	if options.immediate == true then invoke("bind") end
	return handle
end

local function pointerOver(control)
	if type(control) ~= "table" then return false end
	if type(control.isMouseOver) == "function" then
		local ok, hovered = pcall(control.isMouseOver, control)
		if ok and hovered == true then return true end
	end
	if type(getMouseX) ~= "function" or type(getMouseY) ~= "function" then return false end
	local getX = control.getAbsoluteX or control.getX
	local getY = control.getAbsoluteY or control.getY
	local getW = control.getWidth
	local getH = control.getHeight
	if type(getX) ~= "function" or type(getY) ~= "function"
		or type(getW) ~= "function" or type(getH) ~= "function" then return false end
	local ok, x, y, width, height = pcall(function()
		return getX(control), getY(control), getW(control), getH(control)
	end)
	if not ok then return false end
	local mouseX, mouseY = getMouseX(), getMouseY()
	return type(mouseX) == "number" and type(mouseY) == "number"
		and mouseX >= x and mouseX < x + width
		and mouseY >= y and mouseY < y + height
end

--- Keeps a hover-revealed surface alive across its trigger, the revealed
--- surface and the small pointer transition between them.  Consumers provide
--- content and actions; SiK UI owns hover geometry, grace and cleanup.
function Lifecycle.bindHoverReveal(owner, options)
	if type(owner) ~= "table" then return nil, "invalid_owner" end
	options = options or {}
	local target = options.target
	if type(target) ~= "table" or type(target.setVisible) ~= "function" then
		return nil, "invalid_target"
	end
	local graceTicks = math.max(0, math.floor(tonumber(options.graceTicks) or 3))
	local graceRemaining = 0
	local lastVisible = nil

	local function resolveSources()
		local sources = options.sources or options.triggers or {}
		if type(sources) == "function" then sources = sources(owner, target) end
		if type(sources) ~= "table" then return {} end
		return sources
	end
	local function predicate(name, fallback)
		local callback = options[name]
		if type(callback) ~= "function" then return fallback end
		local ok, value = pcall(callback, owner, target)
		return ok and value == true
	end
	local function refresh(context)
		if type(options.beforeUpdate) == "function" then options.beforeUpdate(context, owner, target) end
		local hovered = pointerOver(target)
		local sources = resolveSources()
		for index = 1, #sources do
			if pointerOver(sources[index]) then hovered = true; break end
		end
		if hovered then graceRemaining = graceTicks end
		local graceActive = not hovered and graceRemaining > 0
		local shown = hovered or graceActive or predicate("forceVisible", false)
		if graceActive then graceRemaining = graceRemaining - 1 end
		if predicate("forceHidden", false) then shown = false; graceRemaining = 0 end
		target:setVisible(shown)
		if shown and type(target.bringToTop) == "function" then target:bringToTop() end
		if shown ~= lastVisible then
			lastVisible = shown
			local callback = shown and options.onShow or options.onHide
			if type(callback) == "function" then callback(context, owner, target) end
		end
		return shown
	end
	local handle, reason = Lifecycle.bindVisibleRefresh(owner, {
		intervalTicks = options.intervalTicks or 1,
		active = options.active,
		immediate = options.immediate,
		refresh = refresh,
	})
	if not handle then return nil, reason end
	handle.isPointerOver = pointerOver
	return handle
end

return Lifecycle
