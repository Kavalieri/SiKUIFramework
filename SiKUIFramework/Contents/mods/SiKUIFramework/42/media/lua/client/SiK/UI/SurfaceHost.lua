require "SiK/UI/Namespace"

local UI = SiK.UI
local SurfaceHost = UI.SurfaceHost or {}
UI.Namespace.define("SurfaceHost", SurfaceHost)

local function finite(value)
	value = tonumber(value)
	if value == nil or value ~= value or value == math.huge or value == -math.huge then return nil end
	return value
end

local function snapshot(value, seen)
	if type(value) ~= "table" then return value end
	if value._sikThemeContext == true then return value end
	if getmetatable(value) ~= nil then return value end
	seen = seen or {}
	if seen[value] then return seen[value] end
	local result = {}
	seen[value] = result
	for key, child in pairs(value) do result[key] = snapshot(child, seen) end
	return result
end

local function callDimension(parent, methodName, fieldName)
	if type(parent) ~= "table" then return nil end
	local method = parent[methodName]
	if type(method) == "function" then
		local ok, value = pcall(method, parent)
		if ok then return finite(value) end
	end
	return finite(parent[fieldName])
end

local function normalizeBounds(bounds, fallback, parent)
	if bounds ~= nil and type(bounds) ~= "table" then return nil, "invalid_bounds" end
	fallback = type(fallback) == "table" and fallback or {}
	bounds = bounds or {}
	local x = finite(bounds.x) or finite(fallback.x) or 0
	local y = finite(bounds.y) or finite(fallback.y) or 0
	local width = finite(bounds.w or bounds.width) or finite(fallback.w or fallback.width)
		or callDimension(parent, "getWidth", "width") or 1
	local height = finite(bounds.h or bounds.height) or finite(fallback.h or fallback.height)
		or callDimension(parent, "getHeight", "height") or 1
	return { x = x, y = y, w = math.max(1, width), h = math.max(1, height) }
end

local function mergeContext(current, patch)
	local result = snapshot(current or {})
	if type(patch) == "table" then
		for key, value in pairs(patch) do result[key] = snapshot(value) end
	end
	return result
end

local function contextForBounds(context, bounds, profileId)
	local result = snapshot(context or {})
	result.viewport = snapshot(bounds)
	if profileId ~= nil then result.profile = profileId end
	return result
end

local function parentBounds(host)
	if not host._followParent then return nil end
	local width = callDimension(host._parent, "getWidth", "width")
	local height = callDimension(host._parent, "getHeight", "height")
	if not width or not height or width <= 1 or height <= 1 then return nil end
	return {
		x = finite(host._bounds and host._bounds.x) or 0,
		y = finite(host._bounds and host._bounds.y) or 0,
		w = math.max(1, width), h = math.max(1, height),
	}
end

local function sameBounds(left, right)
	return left and right and left.x == right.x and left.y == right.y
		and left.w == right.w and left.h == right.h
end

local function visibilityTarget(tree)
	local root = tree and tree.root
	if type(root) ~= "table" then return nil end
	if type(root.setVisible) == "function" then return root end
	if type(root.panel) == "table" then return root.panel end
	return root
end

local function applyVisible(host, visible)
	local target = visibilityTarget(host._tree)
	if not target and host._tree == nil then return true end
	if not target then return nil, "visibility_target_missing" end
	if type(target.setVisible) == "function" then
		local ok, reason = pcall(target.setVisible, target, visible)
		if not ok then return nil, reason end
	else
		target.visible = visible
	end
	return true
end

local function usableBounds(bounds)
	return type(bounds) == "table" and finite(bounds.w) and finite(bounds.h)
		and bounds.w > 1 and bounds.h > 1
end

-- A surface is never allowed to construct descendants against a provisional
-- 0/1 px parent.  The host may exist pending, but the widget tree is mounted
-- exactly once only after the real parent geometry exists.
local function ensureTree(host, candidateBounds)
	if host._tree then return host._tree end
	local bounds
	if host._followParent then
		bounds = parentBounds(host)
		if not bounds then return nil, "parent_geometry_pending" end
	else
		bounds = candidateBounds or host._bounds
	end
	if host._followParent and not usableBounds(bounds) then
		return nil, "parent_geometry_pending"
	end
	host._bounds = bounds
	host._context = contextForBounds(host._context, bounds, host._context and host._context.profile)
	local ok, tree, reason = pcall(UI.buildSurface, host._parent, host._spec, host._context)
	if not ok then return nil, tree end
	if not tree then return nil, reason end
	host._tree = tree
	local visibleOk, visibleReason = applyVisible(host, host._visible)
	if not visibleOk then
		pcall(tree.dispose, tree)
		host._tree = nil
		return nil, visibleReason
	end
	UI.observe("surface.host.tree_mounted", {
		surfaceId = host.surfaceId,
		playerNum = finite(host._context and host._context.playerNum) or 0,
		parentWidth = bounds.w,
		parentHeight = bounds.h,
		constructionStage = "tree_mounted",
	})
	return tree
end

local function reportError(host, operation, reason)
	local message = "surface_host_" .. tostring(operation) .. "_failed:" .. tostring(reason or "unknown")
	host._lastError = message
	local payload = {
		operation = operation,
		reason = tostring(reason or "unknown"),
		surfaceId = host.surfaceId,
		playerNum = finite(host._context and host._context.playerNum) or 0,
	}
	UI.observe("surface.host.error", payload)
	if type(host._onError) == "function" then pcall(host._onError, payload, host) end
	return nil, message
end

local function beginOperation(host, operation)
	if host._disposed then return reportError(host, operation, "disposed") end
	if host._busy then return reportError(host, operation, "operation_in_progress") end
	host._busy = true
	return true
end

local function finishOperation(host, eventName)
	host._busy = false
	host._lastError = nil
	UI.observe(eventName, {
		surfaceId = host.surfaceId,
		playerNum = finite(host._context and host._context.playerNum) or 0,
		visible = host._visible,
	})
	return host
end

function SurfaceHost.snapshotContext(context)
	if context ~= nil and type(context) ~= "table" then return nil, "invalid_context" end
	return snapshot(context or {})
end

function SurfaceHost.sanitizeBounds(bounds, fallback, parent)
	return normalizeBounds(bounds, fallback, parent)
end

function SurfaceHost.mount(parent, spec, options)
	if type(parent) ~= "table" then return nil, "surface_host_mount_failed:invalid_parent" end
	if type(spec) ~= "table" then return nil, "surface_host_mount_failed:invalid_spec" end
	if options ~= nil and type(options) ~= "table" then
		return nil, "surface_host_mount_failed:invalid_options"
	end
	options = options or {}
	if options.context ~= nil and type(options.context) ~= "table" then
		return nil, "surface_host_mount_failed:invalid_context"
	end
	if options.contextProvider ~= nil and type(options.contextProvider) ~= "function" then
		return nil, "surface_host_mount_failed:invalid_context_provider"
	end
	if options.onError ~= nil and type(options.onError) ~= "function" then
		return nil, "surface_host_mount_failed:invalid_error_handler"
	end

	local bounds, boundsReason = normalizeBounds(options.bounds, nil, parent)
	if not bounds then return nil, "surface_host_mount_failed:" .. tostring(boundsReason) end
	local context = contextForBounds(options.context or {}, bounds, options.profileId)
	local host = {
		surfaceId = spec.surface and spec.surface.id or nil,
		_parent = parent,
		_spec = spec,
		_context = context,
		_bounds = bounds,
		_contextProvider = options.contextProvider,
		_onError = options.onError,
		_followParent = options.followParent == true,
		_visible = options.visible ~= false,
		_busy = false,
		_disposed = false,
	}
	local initialBounds = host._followParent and parentBounds(host) or bounds
	local tree, reason = ensureTree(host, initialBounds)
	if not tree and reason ~= "parent_geometry_pending" then return reportError(host, "mount", reason) end
	if not tree then
		UI.observe("surface.host.pending", {
			surfaceId = host.surfaceId,
			playerNum = finite(context.playerNum) or 0,
			reason = reason,
			constructionStage = "waiting_for_parent",
		})
	end

	function host:getTree() return self._tree end
	function host:getBounds() return snapshot(self._bounds) end
	function host:getContextSnapshot() return snapshot(self._context) end
	function host:getLastError() return self._lastError end
	function host:isDisposed() return self._disposed == true end
	function host:isVisible() return self._visible == true end

	function host:update(nextContext)
		if type(nextContext) ~= "table" then return reportError(self, "update", "invalid_context") end
		if not beginOperation(self, "update") then return nil, self._lastError end
		local liveBounds = parentBounds(self)
		local candidate = contextForBounds(mergeContext(self._context, nextContext),
			liveBounds or self._bounds)
		local tree, mountReason = ensureTree(self, liveBounds)
		if not tree then
			-- Keep the latest state while geometry is pending.  No widget exists yet,
			-- so the first real mount consumes the current state rather than the
			-- stale snapshot captured when the provisional host was created.
			self._context = candidate
			self._busy = false
			if mountReason == "parent_geometry_pending" then return self end
			return reportError(self, "update_mount", mountReason)
		end
		if liveBounds and not sameBounds(liveBounds, self._bounds) then
			local reflowCalled, reflowed, reflowReason = pcall(tree.reflow,
				tree, liveBounds, self._context and self._context.profile)
			if not reflowCalled or not reflowed then
				self._busy = false
				return reportError(self, "update_reflow", reflowCalled and reflowReason or reflowed)
			end
			self._bounds = liveBounds
		end
		candidate = contextForBounds(candidate, self._bounds)
		local called, updated, updateReason = pcall(tree.update, tree, candidate)
		if not called or not updated then
			self._busy = false
			return reportError(self, "update", called and updateReason or updated)
		end
		self._context = candidate
		local visibleOk, visibleReason = applyVisible(self, self._visible)
		if not visibleOk then
			self._busy = false
			return reportError(self, "update", visibleReason)
		end
		return finishOperation(self, "surface.host.update")
	end

	function host:reflow(nextBounds, profileId)
		if not beginOperation(self, "reflow") then return nil, self._lastError end
		local candidate, candidateReason = normalizeBounds(nextBounds, self._bounds, self._parent)
		if not candidate then
			self._busy = false
			return reportError(self, "reflow", candidateReason)
		end
		local tree, mountReason = ensureTree(self, candidate)
		if not tree then
			self._busy = false
			if mountReason == "parent_geometry_pending" then return self end
			return reportError(self, "reflow_mount", mountReason)
		end
		local currentProfile = self._context and self._context.profile
		if sameBounds(candidate, self._bounds)
			and (profileId == nil or profileId == currentProfile) then
			return finishOperation(self, "surface.host.reflow.unchanged")
		end
		local called, updated, updateReason = pcall(tree.reflow, tree, candidate, profileId)
		if not called or not updated then
			self._busy = false
			return reportError(self, "reflow", called and updateReason or updated)
		end
		self._bounds = candidate
		self._context = contextForBounds(self._context, candidate, profileId)
		local visibleOk, visibleReason = applyVisible(self, self._visible)
		if not visibleOk then
			self._busy = false
			return reportError(self, "reflow", visibleReason)
		end
		return finishOperation(self, "surface.host.reflow")
	end

	function host:setVisible(value)
		if not beginOperation(self, "visibility") then return nil, self._lastError end
		local visible = value ~= false
		local visibleOk, visibleReason = applyVisible(self, visible)
		if not visibleOk then
			self._busy = false
			return reportError(self, "visibility", visibleReason)
		end
		self._visible = visible
		return finishOperation(self, "surface.host.visibility")
	end

	function host:refresh(nextContext)
		local patch = nextContext
		if patch == nil and type(self._contextProvider) == "function" then
			local okProvider, supplied, providerReason = pcall(self._contextProvider,
				self:getContextSnapshot(), self)
			if not okProvider then return reportError(self, "refresh", supplied) end
			if type(supplied) ~= "table" then
				return reportError(self, "refresh", providerReason or "invalid_provider_context")
			end
			patch = supplied
		end
		if patch == nil then patch = {} end
		if type(patch) ~= "table" then return reportError(self, "refresh", "invalid_context") end
		local updated, updateReason = self:update(patch)
		if not updated then return nil, updateReason end
		UI.observe("surface.host.refresh", {
			surfaceId = self.surfaceId,
			playerNum = finite(self._context and self._context.playerNum) or 0,
		})
		return self
	end

	function host:dispose()
		if self._disposed then return false end
		self._disposed = true
		self._busy = false
		local activeTree = self._tree
		self._tree = nil
		local called, disposed, disposeReason = true, true, nil
		if activeTree and type(activeTree.dispose) == "function" then
			called, disposed, disposeReason = pcall(activeTree.dispose, activeTree)
		end
		UI.observe("surface.host.dispose", { surfaceId = self.surfaceId })
		self._parent, self._spec, self._contextProvider, self._onError = nil, nil, nil, nil
		if not called or disposed == nil then
			return nil, "surface_host_dispose_failed:" .. tostring(called and disposeReason or disposed)
		end
		return true
	end

	UI.observe("surface.host.mount", {
		surfaceId = host.surfaceId,
		playerNum = finite(context.playerNum) or 0,
		visible = host._visible,
	})
	return host
end

return SurfaceHost
