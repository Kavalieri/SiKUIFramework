-- Independent public namespace and neutral integration hooks.
SiK = SiK or {}
SiK.UI = SiK.UI or {}

local UI = SiK.UI
local Namespace = UI.Namespace or {}
UI.Namespace = Namespace

local modules = Namespace._modules or {}
Namespace._modules = modules

function Namespace.define(name, value)
	if type(name) ~= "string" or name == "" then return nil, "invalid_module_name" end
	if type(value) ~= "table" then return nil, "invalid_module" end
	if modules[name] and modules[name] ~= value then return nil, "module_conflict" end
	modules[name] = value
	UI[name] = value
	return value
end

function Namespace.module(name)
	return modules[name] or UI[name]
end

function UI.setTextResolver(resolver)
	if resolver ~= nil and type(resolver) ~= "function" then
		return nil, "invalid_text_resolver"
	end
	UI._textResolver = resolver
	return true
end

function UI.resolveText(key, fallback, ...)
	local args = { ... }
	if type(UI._textResolver) == "function" then
		local ok, value = pcall(UI._textResolver, key, fallback, unpack(args))
		if ok and value ~= nil and value ~= "" then return tostring(value) end
	end
	if type(key) == "string" and key ~= "" and type(getText) == "function" then
		local ok, value = pcall(getText, key, unpack(args))
		if ok and value ~= nil and value ~= "" and value ~= key then return tostring(value) end
	end
	if fallback ~= nil then return tostring(fallback) end
	return tostring(key or "")
end

function UI.setObserver(observer)
	if observer ~= nil and type(observer) ~= "function" then
		return nil, "invalid_observer"
	end
	UI._observer = observer
	return true
end

function UI.observe(eventName, payload)
	if type(UI._observer) ~= "function" then return true end
	local ok = pcall(UI._observer, tostring(eventName or "event"), payload or {})
	return ok
end

function Namespace.context(component, options, eventName, value)
	options = options or {}
	return {
		playerNum = math.max(0, math.floor(tonumber(options.playerNum) or 0)),
		component = component,
		payload = options.payload,
		event = eventName,
		value = value,
	}
end

function Namespace.owned(instance, release)
	if type(instance) ~= "table" then return nil, "invalid_instance" end
	local previous = instance.dispose
	instance.dispose = function(self)
		if self._sikDisposed then return false end
		self._sikDisposed = true
		if type(release) == "function" then pcall(release, self) end
		if type(previous) == "function" and previous ~= instance.dispose then
			pcall(previous, self)
		end
		return true
	end
	return instance
end

return UI
