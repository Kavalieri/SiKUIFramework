require "SiK/UI/Namespace"

SiK = SiK or {}
SiK.UI = SiK.UI or {}

local StateMachine = SiK.UI.StateMachine or {}
SiK.UI.Namespace.define("StateMachine", StateMachine)

local CLEAR = StateMachine.CLEAR or {}
StateMachine.CLEAR = CLEAR

local Instance = {}
Instance.__index = Instance

local function validId(value)
	return type(value) == "string" and value ~= ""
end

local function copyValue(value, seen)
	if value == CLEAR or type(value) ~= "table" then return value end
	seen = seen or {}
	if seen[value] then return seen[value] end
	local result = {}
	seen[value] = result
	for key, child in pairs(value) do
		result[copyValue(key, seen)] = copyValue(child, seen)
	end
	return result
end

local function applyPatch(target, patch)
	for key, value in pairs(patch or {}) do
		if value == CLEAR then target[key] = nil
		else target[key] = copyValue(value) end
	end
	return target
end

local function callbackOrNil(value)
	return value == nil or type(value) == "function"
end

local function compileStates(source)
	if type(source) ~= "table" then return nil, "invalid_states" end
	local states, count = {}, 0
	for stateId, raw in pairs(source) do
		if not validId(stateId) then return nil, "invalid_state_id" end
		if raw == true then raw = {} end
		if type(raw) ~= "table" then return nil, "invalid_state" end
		if not callbackOrNil(raw.onEnter) then return nil, "invalid_on_enter" end
		if not callbackOrNil(raw.onExit) then return nil, "invalid_on_exit" end
		states[stateId] = {
			onEnter = raw.onEnter,
			onExit = raw.onExit,
			terminal = raw.terminal == true,
		}
		count = count + 1
	end
	if count == 0 then return nil, "empty_states" end
	return states
end

local function compileFrom(value, states)
	if value == nil or value == "*" then return "*" end
	local result = {}
	if type(value) == "string" then
		if not states[value] then return nil, "unknown_from_state" end
		result[value] = true
		return result
	end
	if type(value) ~= "table" or #value == 0 then return nil, "invalid_from" end
	for index = 1, #value do
		local stateId = value[index]
		if not validId(stateId) or not states[stateId] then
			return nil, "unknown_from_state"
		end
		result[stateId] = true
	end
	return result
end

local function compileTransition(raw, states)
	if type(raw) ~= "table" then return nil, "invalid_transition" end
	local from, reason = compileFrom(raw.from, states)
	if not from then return nil, reason end
	if type(raw.to) ~= "string" and type(raw.to) ~= "function" then
		return nil, "invalid_target"
	end
	if type(raw.to) == "string" and not states[raw.to] then
		return nil, "unknown_target_state"
	end
	if not callbackOrNil(raw.guard) then return nil, "invalid_guard" end
	if not callbackOrNil(raw.action) then return nil, "invalid_action" end
	return { from = from, to = raw.to, guard = raw.guard, action = raw.action }
end

local function compileTransitions(source, states)
	if type(source) ~= "table" then return nil, "invalid_transitions" end
	local transitions = {}
	for eventId, raw in pairs(source) do
		if not validId(eventId) then return nil, "invalid_event_id" end
		local list = raw
		if type(raw) == "table" and (raw.to ~= nil or raw.from ~= nil
			or raw.guard ~= nil or raw.action ~= nil) then
			list = { raw }
		end
		if type(list) ~= "table" or #list == 0 then
			return nil, "empty_event_transitions"
		end
		transitions[eventId] = {}
		for index = 1, #list do
			local transition, reason = compileTransition(list[index], states)
			if not transition then return nil, reason end
			transitions[eventId][#transitions[eventId] + 1] = transition
		end
	end
	return transitions
end

local function compileDefinition(spec)
	if type(spec) ~= "table" then return nil, "invalid_definition" end
	local states, reason = compileStates(spec.states)
	if not states then return nil, reason end
	if not validId(spec.initial) or not states[spec.initial] then
		return nil, "invalid_initial_state"
	end
	local transitions
	transitions, reason = compileTransitions(spec.transitions or {}, states)
	if not transitions then return nil, reason end
	if spec.disposedState ~= nil
		and (not validId(spec.disposedState) or not states[spec.disposedState]) then
		return nil, "invalid_disposed_state"
	end
	if not callbackOrNil(spec.onObserverError) then
		return nil, "invalid_observer_error_handler"
	end
	local maxObservers = math.floor(tonumber(spec.maxObservers) or 16)
	if maxObservers < 1 or maxObservers > 128 then return nil, "invalid_observer_limit" end
	if spec.data ~= nil and type(spec.data) ~= "table" then return nil, "invalid_data" end
	return {
		initial = spec.initial,
		states = states,
		transitions = transitions,
		disposedState = spec.disposedState,
		maxObservers = maxObservers,
		onObserverError = spec.onObserverError,
		data = copyValue(spec.data or {}),
	}
end

local function definitionDescription(record)
	local result = {
		initial = record.initial,
		disposedState = record.disposedState,
		maxObservers = record.maxObservers,
		states = {},
		transitions = {},
	}
	for stateId, state in pairs(record.states) do
		result.states[stateId] = { terminal = state.terminal }
	end
	for eventId, list in pairs(record.transitions) do
		result.transitions[eventId] = #list
	end
	return result
end

local function transitionContext(record, eventId, payload, target, data)
	return {
		state = record.state,
		target = target,
		event = eventId,
		payload = copyValue(payload),
		data = copyValue(data or record.data),
		generation = record.generation,
	}
end

local function matchesFrom(from, stateId)
	return from == "*" or from[stateId] == true
end

local function resolveTarget(transition, context, states)
	if type(transition.to) == "string" then return transition.to end
	local ok, target, reason = pcall(transition.to, context)
	if not ok then return nil, "target_error", target end
	if not validId(target) or not states[target] then
		return nil, reason or "invalid_target"
	end
	return target
end

local function selectTransition(record, eventId, payload)
	local list = record.definition.transitions[eventId]
	if not list then return nil, "unknown_event" end
	local matchedFrom, rejectedGuard = false, false
	for index = 1, #list do
		local transition = list[index]
		if matchesFrom(transition.from, record.state) then
			matchedFrom = true
			local context = transitionContext(record, eventId, payload, nil)
			local accepted = true
			if transition.guard then
				local ok, result = pcall(transition.guard, context)
				if not ok then return nil, "guard_error", result end
				accepted = result == true
				rejectedGuard = rejectedGuard or not accepted
			end
			if accepted then
				local target, reason, detail = resolveTarget(transition, context,
					record.definition.states)
				if not target then return nil, reason, detail end
				return transition, target
			end
		end
	end
	if rejectedGuard then return nil, "guard_rejected" end
	if matchedFrom then return nil, "transition_rejected" end
	return nil, "transition_not_allowed"
end

local function callHook(callback, context, reason)
	if not callback then return true end
	local ok, detail = pcall(callback, context)
	if not ok then return nil, reason, detail end
	return true
end

local function callAction(callback, context)
	if not callback then return {} end
	local ok, patch, detail = pcall(callback, context)
	if not ok then return nil, "action_error", patch end
	if patch == false then return nil, detail or "action_rejected" end
	if patch ~= nil and type(patch) ~= "table" then
		return nil, "invalid_action_result"
	end
	return patch or {}
end

local function machineSnapshot(record)
	local snapshot = {
		state = record.state,
		generation = record.generation,
		disposed = record.disposed == true,
		data = copyValue(record.data),
	}
	if record.disposed then snapshot.reason = record.disposeReason
	elseif type(record.data.reason) == "string" and record.data.reason ~= "" then
		snapshot.reason = record.data.reason
	end
	if type(record.data.counts) == "table" then
		snapshot.counts = copyValue(record.data.counts)
	end
	return snapshot
end

local function observerError(record, detail, change)
	local callback = record.definition.onObserverError
	if not callback then return end
	pcall(callback, {
		error = tostring(detail),
		change = copyValue(change),
		snapshot = machineSnapshot(record),
	})
end

local function notify(record, change)
	local listeners = {}
	for index = 1, #record.observers do
		local handle = record.observers[index]
		if handle.active then listeners[#listeners + 1] = handle end
	end
	for index = 1, #listeners do
		local handle = listeners[index]
		if handle.active then
			local ok, detail = pcall(handle.listener, machineSnapshot(record),
				copyValue(change))
			if not ok then observerError(record, detail, change) end
		end
	end
end

local function removeObserver(record, handle)
	if not handle.active then return false end
	handle.active = false
	for index = #record.observers, 1, -1 do
		if record.observers[index] == handle then
			table.remove(record.observers, index)
			break
		end
	end
	return true
end

function Instance:getState()
	return self._record.state
end

function Instance:getGeneration()
	return self._record.generation
end

function Instance:isDisposed()
	return self._record.disposed == true
end

function Instance:snapshot()
	return machineSnapshot(self._record)
end

function Instance:can(eventId, payload)
	local record = self._record
	if record.disposed then return false, "disposed" end
	if record.busy then return false, "transition_in_progress" end
	if record.definition.states[record.state].terminal then
		return false, "terminal_state"
	end
	if not validId(eventId) then return false, "invalid_event" end
	local transition, targetOrReason, detail = selectTransition(record, eventId, payload)
	if not transition then return false, targetOrReason, detail end
	return true, targetOrReason
end

function Instance:send(eventId, payload)
	local record = self._record
	if record.disposed then return nil, "disposed" end
	if record.busy then return nil, "transition_in_progress" end
	if record.definition.states[record.state].terminal then
		return nil, "terminal_state"
	end
	if not validId(eventId) then return nil, "invalid_event" end
	local transition, target, detail = selectTransition(record, eventId, payload)
	if not transition then return nil, target, detail end

	record.busy = true
	local from, currentData = record.state, copyValue(record.data)
	local context = transitionContext(record, eventId, payload, target, currentData)
	local ok, reason, callbackDetail = callHook(
		record.definition.states[from].onExit, context, "on_exit_error")
	if not ok then record.busy = false; return nil, reason, callbackDetail end
	local patch
	patch, reason, callbackDetail = callAction(transition.action, context)
	if not patch then record.busy = false; return nil, reason, callbackDetail end
	local nextData = applyPatch(copyValue(currentData), patch)
	context = transitionContext(record, eventId, payload, target, nextData)
	ok, reason, callbackDetail = callHook(
		record.definition.states[target].onEnter, context, "on_enter_error")
	if not ok then record.busy = false; return nil, reason, callbackDetail end

	record.state = target
	record.data = nextData
	record.generation = record.generation + 1
	local change = { event = eventId, from = from, to = target,
		generation = record.generation, payload = copyValue(payload) }
	notify(record, change)
	record.busy = false
	return machineSnapshot(record)
end

function Instance:subscribe(listener, options)
	local record = self._record
	if record.disposed then return nil, "disposed" end
	if type(listener) ~= "function" then return nil, "invalid_observer" end
	if #record.observers >= record.definition.maxObservers then
		return nil, "observer_limit"
	end
	local handle = { active = true, listener = listener }
	function handle:dispose()
		return removeObserver(record, self)
	end
	record.observers[#record.observers + 1] = handle
	if type(options) == "table" and options.immediate == true then
		local ok, detail = pcall(listener, machineSnapshot(record), {
			event = "subscribe", from = record.state, to = record.state,
			generation = record.generation,
		})
		if not ok then observerError(record, detail, { event = "subscribe" }) end
	end
	return handle
end

function Instance:observerCount()
	return #self._record.observers
end

function Instance:dispose(reason)
	local record = self._record
	if record.disposed then return false end
	if record.busy then return nil, "transition_in_progress" end
	record.busy = true
	local from = record.state
	local target = record.definition.disposedState or from
	local context = transitionContext(record, "dispose", { reason = reason },
		target, record.data)
	local _, exitReason, exitDetail = callHook(
		record.definition.states[from].onExit, context, "on_exit_error")
	local enterReason, enterDetail
	if target ~= from then
		local ok
		ok, enterReason, enterDetail = callHook(
			record.definition.states[target].onEnter, context, "on_enter_error")
		if ok then enterReason, enterDetail = nil, nil end
	end
	record.state = target
	record.disposed = true
	record.disposeReason = reason
	record.generation = record.generation + 1
	local change = { event = "dispose", from = from, to = target,
		generation = record.generation, reason = reason }
	notify(record, change)
	for index = 1, #record.observers do record.observers[index].active = false end
	record.observers = {}
	record.busy = false
	return true, exitReason or enterReason, exitDetail or enterDetail
end

local function createInstance(definition, options)
	if type(definition) ~= "table" or definition._kind ~= "SiK.UI.StateMachine.Definition"
		or type(definition._record) ~= "table" then
		return nil, "invalid_definition"
	end
	options = options or {}
	if type(options) ~= "table" then return nil, "invalid_options" end
	if options.data ~= nil and type(options.data) ~= "table" then
		return nil, "invalid_data"
	end
	local definitionRecord = definition._record
	local data = copyValue(definitionRecord.data)
	applyPatch(data, options.data or {})
	local record = {
		definition = definitionRecord,
		state = definitionRecord.initial,
		generation = 0,
		data = data,
		observers = {},
		disposed = false,
		busy = true,
	}
	local instance = setmetatable({ _record = record }, Instance)
	local context = transitionContext(record, "init", nil, record.state, data)
	local ok, reason, detail = callHook(
		definitionRecord.states[record.state].onEnter, context, "initial_enter_error")
	record.busy = false
	if not ok then return nil, reason, detail end
	return instance
end

function StateMachine.validate(spec)
	local record, reason = compileDefinition(spec)
	if not record then return false, reason end
	return true
end

function StateMachine.define(spec)
	local record, reason = compileDefinition(spec)
	if not record then return nil, reason end
	local definition = { _kind = "SiK.UI.StateMachine.Definition", _record = record }
	function definition:create(options)
		return createInstance(self, options)
	end
	function definition:describe()
		return definitionDescription(record)
	end
	return definition
end

function StateMachine.create(definition, options)
	return createInstance(definition, options)
end

local function finiteCount(value)
	value = tonumber(value)
	if not value or value ~= value or value == math.huge or value == -math.huge
		or value < 0 then return nil end
	return math.floor(value)
end

local function resourceCounts(payload, required)
	if payload == nil then
		if required then return nil, "invalid_counts" end
		return { total = 0 }
	end
	if type(payload) ~= "table" then return nil, "invalid_counts" end
	local source = payload.counts
	local counts, found = {}, false
	if source ~= nil then
		if type(source) ~= "table" then return nil, "invalid_counts" end
		for key, value in pairs(source) do
			if type(key) ~= "string" or key == "" then return nil, "invalid_counts" end
			local count = finiteCount(value)
			if count == nil then return nil, "invalid_counts" end
			counts[key] = count
			found = true
		end
	end
	if payload.count ~= nil then
		counts.total = finiteCount(payload.count)
		if counts.total == nil then return nil, "invalid_counts" end
		found = true
	end
	if counts.total == nil and payload.total ~= nil then
		counts.total = finiteCount(payload.total)
		if counts.total == nil then return nil, "invalid_counts" end
		found = true
	end
	if required and not found then return nil, "invalid_counts" end
	counts.total = counts.total or 0
	return counts
end

local function hasResourceCounts(payload)
	return type(payload) == "table" and (payload.counts ~= nil
		or payload.count ~= nil or payload.total ~= nil)
end

local function resourceBegin(context)
	local patch = { reason = CLEAR }
	if not hasResourceCounts(context.payload) then return patch end
	local counts, reason = resourceCounts(context.payload, true)
	if not counts then return false, reason end
	patch.counts = counts
	return patch
end

local function resourceTarget(context)
	local counts, reason = resourceCounts(context.payload, true)
	if not counts then return nil, reason end
	return counts.total == 0 and "empty" or "ready"
end

local function resourceResolve(context)
	local counts, reason = resourceCounts(context.payload, true)
	if not counts then return false, reason end
	return { reason = CLEAR, counts = counts }
end

local function resourceFail(context)
	local payload = type(context.payload) == "table" and context.payload or {}
	local reason = tostring(payload.reason or "unknown")
	if reason == "" then reason = "unknown" end
	local patch = { reason = reason }
	if not hasResourceCounts(payload) then return patch end
	local counts, countReason = resourceCounts(payload, true)
	if not counts then return false, countReason end
	patch.counts = counts
	return patch
end

local function stateHooks(options, stateId)
	local onEnter = type(options.onEnter) == "table" and options.onEnter[stateId] or nil
	local onExit = type(options.onExit) == "table" and options.onExit[stateId] or nil
	return { onEnter = onEnter, onExit = onExit, terminal = stateId == "disposed" }
end

--- Returns a reusable definition for a neutral asynchronous resource.
--- Consumers create isolated instances with definition:create().
function StateMachine.asyncResource(options)
	options = options or {}
	if type(options) ~= "table" then return nil, "invalid_options" end
	local initialCounts, reason = resourceCounts({ counts = options.counts or {} }, false)
	if not initialCounts then return nil, reason end
	return StateMachine.define({
		initial = "loading",
		disposedState = "disposed",
		maxObservers = options.maxObservers,
		onObserverError = options.onObserverError,
		data = { counts = initialCounts },
		states = {
			loading = stateHooks(options, "loading"),
			ready = stateHooks(options, "ready"),
			empty = stateHooks(options, "empty"),
			error = stateHooks(options, "error"),
			disposed = stateHooks(options, "disposed"),
		},
		transitions = {
			begin = { from = { "loading", "ready", "empty", "error" },
				to = "loading", action = resourceBegin },
			resolve = { from = "loading", to = resourceTarget,
				action = resourceResolve },
			fail = { from = "loading", to = "error", action = resourceFail },
		},
	})
end

return StateMachine
