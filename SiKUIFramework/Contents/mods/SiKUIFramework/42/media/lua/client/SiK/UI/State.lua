require "SiK/UI/Namespace"
require "SiK/UI/Layout"

SiK = SiK or {}
SiK.UI = SiK.UI or {}

local State = SiK.UI.State or {}
SiK.UI.Namespace.define("State", State)

local stores = {}

local function playerKey(playerNum)
	return tostring(math.max(0, math.floor(tonumber(playerNum) or 0)))
end

local function validKey(key)
	return type(key) == "string" and key ~= ""
end

local function clone(value, depth)
	if type(value) ~= "table" then return value end
	if depth >= 4 then return nil end
	local out = {}
	for key, child in pairs(value) do out[key] = clone(child, depth + 1) end
	return out
end

function State.snapshot(value)
	return clone(value, 0)
end

function State.merge(target, snapshot)
	if type(target) ~= "table" or type(snapshot) ~= "table" then
		return nil, "invalid_state"
	end
	for key, value in pairs(snapshot) do target[key] = clone(value, 0) end
	return target
end

function State.save(playerNum, key, value)
	return State.set(playerNum, key, value)
end

function State.load(playerNum, key, fallback)
	return State.get(playerNum, key, fallback)
end

local function bucket(playerNum, create)
	local key = playerKey(playerNum)
	local out = stores[key]
	if not out and create then
		out = {}
		stores[key] = out
	end
	return out
end

function State.set(playerNum, key, value)
	if not validKey(key) then return nil, "invalid_key" end
	local target = bucket(playerNum, true)
	target[key] = clone(value, 0)
	return true
end

function State.get(playerNum, key, fallback)
	if not validKey(key) then return clone(fallback, 0) end
	local target = bucket(playerNum, false)
	if not target or target[key] == nil then return clone(fallback, 0) end
	return clone(target[key], 0)
end

function State.clear(playerNum, key)
	if not validKey(key) then return false end
	local target = bucket(playerNum, false)
	if not target then return false end
	target[key] = nil
	return true
end

function State.clearPlayer(playerNum)
	stores[playerKey(playerNum)] = nil
end

function State.clearAll()
	stores = {}
end

function State.capture(playerNum, key, widget, extra)
	if type(widget) ~= "table" then return nil, "invalid_widget" end
	local value = clone(extra or {}, 0)
	value.bounds = {
		x = tonumber(widget.x) or (widget.getX and widget:getX()) or 0,
		y = tonumber(widget.y) or (widget.getY and widget:getY()) or 0,
		w = tonumber(widget.width) or (widget.getWidth and widget:getWidth()) or 0,
		h = tonumber(widget.height) or (widget.getHeight and widget:getHeight()) or 0,
	}
	if widget.getScrollOffset then value.offset = widget:getScrollOffset() end
	if widget.getSelectedKey then value.selection = widget:getSelectedKey() end
	if widget.hasFocus then value.focused = widget:hasFocus() == true end
	return State.set(playerNum, key, value)
end

function State.restore(playerNum, key, widget)
	local value = State.get(playerNum, key)
	if not value or type(widget) ~= "table" then return nil, "missing_state" end
	local rect = value.bounds
	if rect then
		SiK.UI.Layout.apply(widget, SiK.UI.Layout.resolveRect(rect, nil, 0))
	end
	if value.offset ~= nil and widget.setScrollOffset then widget:setScrollOffset(value.offset) end
	if value.selection ~= nil and widget.setSelectedKey then widget:setSelectedKey(value.selection) end
	if value.focused and widget.focus then widget:focus() end
	return value
end

return State
