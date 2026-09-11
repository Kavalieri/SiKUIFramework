require "SiK/UI/Namespace"

local Sandbox = SiK.UI.Sandbox or {}
SiK.UI.Namespace.define("Sandbox", Sandbox)

local MIN_UI_OPACITY = 45
local DEFAULT_UI_OPACITY = 80
local MAX_UI_OPACITY = 100
local cachedRaw, cachedOpacity = nil, nil
local localOpacityByPlayer = {}

local function opacityPercent(value)
	value = tonumber(value)
	if value == nil or value ~= value or value < MIN_UI_OPACITY or value > MAX_UI_OPACITY
		or value ~= math.floor(value) then return nil end
	return value
end

--- Returns the configured target on a normalized 0..1 scale.
--- Sandbox settings are static for a running world; this getter is invoked
--- only while a material is resolved, never from a render or tick callback.
function Sandbox.uiOpacity(playerNum)
	local localPercent = playerNum ~= nil and localOpacityByPlayer[tostring(playerNum)] or nil
	if localPercent ~= nil then return localPercent / 100 end
	local values = SandboxVars and SandboxVars.SiKUIFramework or nil
	local raw = values and values.UIOpacity or nil
	if cachedOpacity ~= nil and raw == cachedRaw then return cachedOpacity end
	local percent = tonumber(raw) or DEFAULT_UI_OPACITY
	percent = math.max(MIN_UI_OPACITY, math.min(MAX_UI_OPACITY, percent))
	cachedRaw, cachedOpacity = raw, percent / 100
	return cachedOpacity
end

--- Returns the effective local UI opacity percentage for one player.
--- A player without an override inherits the world's sandbox default.
function Sandbox.uiOpacityPercent(playerNum)
	return math.floor(Sandbox.uiOpacity(playerNum) * 100 + 0.5)
end

--- Stores an in-memory local opacity override. Theme owns player validation
--- and rebinding; Sandbox deliberately persists neither this value nor product state.
function Sandbox.setLocalUIOpacity(playerNum, percent)
	local normalized = opacityPercent(percent)
	if not normalized then return nil, "invalid_opacity" end
	local key = tostring(playerNum)
	if localOpacityByPlayer[key] == normalized then return false end
	localOpacityByPlayer[key] = normalized
	return true
end

function Sandbox.clearLocalUIOpacity(playerNum)
	local key = tostring(playerNum)
	if localOpacityByPlayer[key] == nil then return false end
	localOpacityByPlayer[key] = nil
	return true
end

--- Maps a material alpha around the approved 80% visual baseline. Lower
--- values make every non-zero surface proportionally lighter; higher values
--- approach a physically opaque surface. An explicit alpha zero stays zero.
function Sandbox.materialAlpha(baseAlpha, playerNum)
	baseAlpha = tonumber(baseAlpha) or 0
	baseAlpha = math.max(0, math.min(1, baseAlpha))
	if baseAlpha == 0 then return 0 end
	local opacity = Sandbox.uiOpacity(playerNum)
	local baseline = DEFAULT_UI_OPACITY / 100
	if opacity <= baseline then return baseAlpha * (opacity / baseline) end
	return baseAlpha + (1 - baseAlpha) * ((opacity - baseline) / (1 - baseline))
end

return Sandbox
