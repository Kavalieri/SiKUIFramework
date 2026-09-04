require "SiK/UI/Namespace"

local Bindings = SiK.UI.Bindings or {}
SiK.UI.Namespace.define("Bindings", Bindings)

local slots = {
	activate = "onSikActivate",
	change = "onSikChange",
	submit = "onSikSubmit",
	cancel = "onSikCancel",
	hover = "onSikHover",
	contextmenu = "onSikContextMenu",
	dragstart = "onSikDragStart",
	dragover = "onSikDragOver",
	drop = "onSikDrop",
	dragcancel = "onSikDragCancel",
}

local privatePayloadKeys = {
	component = true, widget = true, eventPayload = true,
	items = true, options = true, rows = true, selection = true,
	content = true, item = true, payload = true,
}

local function copyPublic(source, target, seen)
	if type(source) ~= "table" then return target end
	seen = seen or {}
	if seen[source] then return target end
	seen[source] = true
	for key, value in pairs(source) do
		if not privatePayloadKeys[key] then
			local valueType = type(value)
			if valueType == "table" then
				target[key] = copyPublic(value, {}, seen)
			elseif valueType ~= "function" and valueType ~= "userdata"
				and valueType ~= "thread" then
				target[key] = value
			end
		end
	end
	seen[source] = nil
	return target
end

local function selectedValue(value)
	if type(value) ~= "table" then return value end
	if value.value ~= nil then return value.value end
	if value.key ~= nil then return value.key end
	if value.id ~= nil then return value.id end
	return nil
end

local function semanticPayload(binding, eventPayload)
	local semantic = copyPublic(binding.payload, {})
	if type(eventPayload) ~= "table" then
		if eventPayload ~= nil then semantic.value = eventPayload end
		return semantic
	end
	-- Component adapters are allowed to emit their semantic data directly
	-- (cards use addonId/definition; tables use item/index/depth).  Keeping only
	-- the nested `payload` silently erased those contracts before dispatch.
	copyPublic(eventPayload, semantic)
	copyPublic(eventPayload.payload, semantic)
	if binding.componentType == "table" or binding.componentType == "virtual-list" then
		-- Keep pooled row objects private. Consumers resolve the stable semantic
		-- key against their own current model, so a refresh cannot publish stale
		-- product data or leak the framework's selection descriptor.
		semantic.rowKey = eventPayload.key or eventPayload.rowKey
	elseif binding.componentType == "tabs" then
		semantic.key = selectedValue(eventPayload.value)
	elseif binding.componentType == "combo" then
		semantic.value = selectedValue(eventPayload.value)
	else
		local value = selectedValue(eventPayload.value)
		if value ~= nil then semantic.value = value end
		if eventPayload.id ~= nil then semantic.id = eventPayload.id end
		if eventPayload.key ~= nil then semantic.key = eventPayload.key end
	end
	return semantic
end

local function stablePayload(binding, eventPayload)
	return {
		framework = "SiK.UI",
		surfaceId = binding.surfaceId,
		nodeId = binding.nodeId,
		componentType = binding.componentType,
		actionId = binding.actionId,
		event = binding.event,
		playerNum = binding.playerNum,
		payload = semanticPayload(binding, eventPayload),
	}
end

function Bindings.bind(target, declaration, callback, options)
	if type(target) ~= "table" then return nil, "invalid_target" end
	if type(declaration) ~= "table" or not slots[declaration.event]
		or type(declaration.actionId) ~= "string" then
		return nil, "invalid_declaration"
	end
	if type(callback) ~= "function" then return nil, "invalid_callback" end
	options = options or {}
	local binding = {
		target = target,
		event = declaration.event,
		actionId = declaration.actionId,
		surfaceId = options.surfaceId,
		nodeId = options.nodeId,
		componentType = options.componentType,
		playerNum = math.max(0, math.floor(tonumber(options.playerNum) or 0)),
		payload = options.payload,
	}
	local slot = slots[binding.event]
	binding.slot = slot
	binding.previous = target[slot]
	binding.dispatch = function(_, eventPayload)
		if binding.disposed then return nil, "disposed" end
		local payload = stablePayload(binding, eventPayload)
		SiK.UI.observe("action.begin", payload)
		local ok, result, detail = pcall(callback, payload)
		if not ok then
			payload.error = tostring(result)
			SiK.UI.observe("action.error", payload)
			if type(options.onError) == "function" then pcall(options.onError, payload) end
			return nil, "action_failed"
		end
		if result == false then
			payload.reason = detail or "cancelled"
			SiK.UI.observe("action.cancel", payload)
			if type(options.onCancel) == "function" then pcall(options.onCancel, payload) end
			return false, payload.reason
		end
		payload.result = result
		SiK.UI.observe("action.complete", payload)
		return result, detail
	end
	target[slot] = binding.dispatch
	function binding:dispose()
		if self.disposed then return false end
		self.disposed = true
		if self.target and self.target[self.slot] == self.dispatch then
			self.target[self.slot] = self.previous
		end
		self.target = nil
		self.previous = nil
		self.dispatch = nil
		return true
	end
	return binding
end

function Bindings.emit(target, eventId, eventPayload)
	local slot = slots[eventId]
	if type(target) ~= "table" or not slot then return nil, "invalid_event" end
	local callback = target[slot]
	if type(callback) ~= "function" then return nil, "event_unbound" end
	return callback(target, eventPayload)
end

return Bindings
