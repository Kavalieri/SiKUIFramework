require "SiK/UI/Namespace"

local Sandbox = SiK.UI.Sandbox or {}
SiK.UI.Namespace.define("Sandbox", Sandbox)

local MIN_UI_OPACITY = 45
local DEFAULT_UI_OPACITY = 80
local MAX_UI_OPACITY = 100
local cachedRaw, cachedOpacity = nil, nil

--- Returns the configured target on a normalized 0..1 scale.
--- Sandbox settings are static for a running world; this getter is invoked
--- only while a material is resolved, never from a render or tick callback.
function Sandbox.uiOpacity()
	local values = SandboxVars and SandboxVars.SiKUIFramework or nil
	local raw = values and values.UIOpacity or nil
	if cachedOpacity ~= nil and raw == cachedRaw then return cachedOpacity end
	local percent = tonumber(raw) or DEFAULT_UI_OPACITY
	percent = math.max(MIN_UI_OPACITY, math.min(MAX_UI_OPACITY, percent))
	cachedRaw, cachedOpacity = raw, percent / 100
	return cachedOpacity
end

--- Maps a material alpha around the approved 80% visual baseline. Lower
--- values make every non-zero surface proportionally lighter; higher values
--- approach a physically opaque surface. An explicit alpha zero stays zero.
function Sandbox.materialAlpha(baseAlpha)
	baseAlpha = tonumber(baseAlpha) or 0
	baseAlpha = math.max(0, math.min(1, baseAlpha))
	if baseAlpha == 0 then return 0 end
	local opacity = Sandbox.uiOpacity()
	local baseline = DEFAULT_UI_OPACITY / 100
	if opacity <= baseline then return baseAlpha * (opacity / baseline) end
	return baseAlpha + (1 - baseAlpha) * ((opacity - baseline) / (1 - baseline))
end

return Sandbox
