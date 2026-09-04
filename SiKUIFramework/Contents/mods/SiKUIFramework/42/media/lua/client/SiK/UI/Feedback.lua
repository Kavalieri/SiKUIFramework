require "SiK/UI/Namespace"

local Feedback = SiK.UI.Feedback or {}
SiK.UI.Namespace.define("Feedback", Feedback)

local DEFAULT_MAX_QUEUE = 8
local MAX_QUEUE = 16
local MIN_DURATION = 100
local MAX_DURATION = 10000
local DEFAULT_DURATION = 300

local DEFAULT_COLORS = {
	info = { 220, 220, 220 },
	success = { 180, 220, 160 },
	warning = { 220, 180, 100 },
	danger = { 235, 90, 90 },
}

local function clamp(value, low, high)
	value = tonumber(value) or low
	return math.max(low, math.min(high, value))
end

local function nowMs(clock)
	if type(clock) == "function" then return tonumber(clock()) or 0 end
	if type(getTimestampMs) == "function" then return tonumber(getTimestampMs()) or 0 end
	if type(getTimestamp) == "function" then return (tonumber(getTimestamp()) or 0) * 1000 end
	return os.clock() * 1000
end

local function resolvedPlayerNum(options)
	local explicit = tonumber(options.playerNum)
	local player = options.player
	local derived = player and player.getPlayerNum and tonumber(player:getPlayerNum()) or nil
	if explicit ~= nil and derived ~= nil and explicit ~= derived then return nil, "player_mismatch" end
	local value = explicit ~= nil and explicit or derived
	if value == nil then return nil, "missing_player_num" end
	return math.max(0, math.floor(value))
end

local function entryKey(entry)
	return tostring(entry.dedupeKey or (entry.tone or "info") .. "\31" .. entry.text)
end

local function emitNote(entry)
	local player = entry.player
	if not player or type(player.setHaloNote) ~= "function" then return nil, "unavailable" end
	local fallback = DEFAULT_COLORS[entry.tone] or DEFAULT_COLORS.info
	local color = type(entry.color) == "table" and entry.color or fallback
	local r = clamp(color.r or color[1], 0, 255)
	local g = clamp(color.g or color[2], 0, 255)
	local b = clamp(color.b or color[3], 0, 255)
	player:setHaloNote(entry.text, r, g, b, entry.durationMs)
	return true
end

local function emitSemantic(entry)
	if type(HaloTextHelper) ~= "table" then return nil, "unavailable" end
	local fn = entry.tone == "danger" and HaloTextHelper.addBadText or HaloTextHelper.addGoodText
	if type(fn) ~= "function" then return nil, "unavailable" end
	fn(entry.player, entry.text)
	return true
end

local function normalize(options, clock)
	if type(options) ~= "table" then return nil, "invalid_options" end
	local text = tostring(options.text or "")
	if text == "" then return nil, "missing_text" end
	local playerNum, reason = resolvedPlayerNum(options)
	if playerNum == nil then return nil, reason end
	local channel = tostring(options.channel or "default")
	if channel == "" or #channel > 64 then return nil, "invalid_channel" end
	local policy = options.policy or "dedupe"
	if policy ~= "replace" and policy ~= "dedupe" and policy ~= "queue" then
		return nil, "invalid_policy"
	end
	local presentation = options.presentation or "note"
	if presentation ~= "note" and presentation ~= "semantic" then
		return nil, "invalid_presentation"
	end
	local duration = clamp(options.durationMs or options.duration or DEFAULT_DURATION,
		MIN_DURATION, MAX_DURATION)
	local createdAt = nowMs(clock)
	return {
		player = options.player, playerNum = playerNum, text = text,
		tone = options.tone or "info", color = options.color,
		durationMs = duration, channel = channel, policy = policy,
		presentation = presentation, dedupeKey = options.dedupeKey,
		throttleMs = math.max(0, tonumber(options.throttleMs) or 0),
		maxQueue = clamp(options.maxQueue or DEFAULT_MAX_QUEUE, 1, MAX_QUEUE),
		createdAt = createdAt, expiresAt = createdAt + duration,
		queueExpiresAt = createdAt + clamp(options.ttlMs or math.max(5000, duration * 4),
			MIN_DURATION, 60000),
	}, nil
end

local function emit(entry, customEmitter)
	local function invoke()
		if type(customEmitter) == "function" then return customEmitter(entry) end
		if entry.presentation == "semantic" then return emitSemantic(entry) end
		return emitNote(entry)
	end
	local ok, result, reason = pcall(invoke)
	if not ok then return nil, "emit_failed" end
	return result, reason
end

function Feedback.create(options)
	options = options or {}
	local service = { _channels = {}, _clock = options.clock, _emit = options.emit }
	local tickInstalled, disposed = false, false

	local function channelKey(entry)
		return tostring(entry.playerNum) .. "\31" .. entry.channel
	end

	local function removeTick()
		if tickInstalled and Events and Events.OnTick and Events.OnTick.Remove then
			Events.OnTick.Remove(service._onTick)
		end
		tickInstalled = false
	end

	local function hasPending()
		for _, state in pairs(service._channels) do
			if state.current or #state.queue > 0 then return true end
		end
		return false
	end

	local function installTick()
		if tickInstalled or not Events or not Events.OnTick or not Events.OnTick.Add then return end
		Events.OnTick.Add(service._onTick)
		tickInstalled = true
	end

	local function show(entry, state)
		local ok, reason = emit(entry, service._emit)
		if not ok then return nil, reason or "unavailable" end
		state.current = entry
		state.lastShownAt = nowMs(service._clock)
		entry.expiresAt = state.lastShownAt + entry.durationMs
		installTick()
		return true
	end

	local function ownEntry(entry, key)
		entry._channelKey = key
		function entry:dispose()
			if self.disposed then return false end
			self.disposed = true
			local state = service._channels[self._channelKey]
			if not state then return true end
			if state.current == self then state.current = nil end
			for index = #state.queue, 1, -1 do
				if state.queue[index] == self then table.remove(state.queue, index) end
			end
			service:_advance()
			return true
		end
		return entry
	end

	function service:_advance()
		local currentTime = nowMs(self._clock)
		local keys = {}
		for key in pairs(self._channels) do keys[#keys + 1] = key end
		for index = 1, #keys do
			local key, state = keys[index], self._channels[keys[index]]
			if state.current and state.current.expiresAt <= currentTime then state.current = nil end
			while #state.queue > 0 and state.queue[1].queueExpiresAt <= currentTime do
				table.remove(state.queue, 1)
			end
			if not state.current and #state.queue > 0 then
				local entry = table.remove(state.queue, 1)
				show(entry, state)
			end
			if not state.current and #state.queue == 0 then self._channels[key] = nil end
		end
		if not hasPending() then removeTick() end
	end

	service._onTick = function() service:_advance() end

	function service:halo(request)
		if disposed then return nil, "disposed" end
		local entry, reason = normalize(request, self._clock)
		if not entry then return nil, reason end
		self:_advance()
		local key = channelKey(entry)
		local state = self._channels[key]
		if not state then
			state = { queue = {}, playerNum = entry.playerNum, channel = entry.channel }
			self._channels[key] = state
		end
		ownEntry(entry, key)
		local dedupeKey = entryKey(entry)
		if state.current and entryKey(state.current) == dedupeKey then
			if entry.policy ~= "replace" then return "deduped", state.current end
		end
		for index = 1, #state.queue do
			if entryKey(state.queue[index]) == dedupeKey then return "deduped", state.queue[index] end
		end
		if entry.throttleMs > 0 and state.lastShownAt
			and nowMs(self._clock) - state.lastShownAt < entry.throttleMs then
			return "deduped", state.current
		end
		if entry.policy == "queue" and state.current then
			if #state.queue >= entry.maxQueue then return nil, "queue_full" end
			state.queue[#state.queue + 1] = entry
			installTick()
			return "queued", entry
		end
		if entry.policy == "replace" then state.queue = {} end
		local ok, emitReason = show(entry, state)
		if not ok then
			if #state.queue == 0 then self._channels[key] = nil end
			return "unavailable", emitReason
		end
		return "shown", entry
	end

	function service:clear(playerNum, channel)
		if disposed then return false end
		local prefix = playerNum ~= nil and tostring(math.max(0, math.floor(tonumber(playerNum) or 0))) .. "\31" or nil
		local keys = {}
		for key, state in pairs(self._channels) do
			if (not prefix or key:sub(1, #prefix) == prefix)
				and (channel == nil or state.channel == channel) then
				keys[#keys + 1] = key
			end
		end
		for index = 1, #keys do self._channels[keys[index]] = nil end
		if not hasPending() then removeTick() end
		return true
	end

	function service:dispose()
		if disposed then return false end
		disposed = true
		removeTick()
		self._channels = {}
		return true
	end

	function service:isScheduled() return tickInstalled end
	function service:pendingCount()
		local count = 0
		for _, state in pairs(self._channels) do count = count + #state.queue end
		return count
	end
	return service
end

Feedback._default = Feedback._default or Feedback.create()

function Feedback.halo(options)
	return Feedback._default:halo(options)
end

function Feedback.clear(playerNum, channel)
	return Feedback._default:clear(playerNum, channel)
end

return Feedback
