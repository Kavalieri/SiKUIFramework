require "SiK/UI/Namespace"

local Theme = SiK.UI.Theme or {}
SiK.UI.Namespace.define("Theme", Theme)

local function rgba(r, g, b, a)
	return { r = r, g = g, b = b, a = a or 1 }
end

Theme.defaults = Theme.defaults or {
	background = rgba(0.043137, 0.043137, 0.043137, 0.98),
	header = rgba(0.066667, 0.066667, 0.066667, 1),
	surface = rgba(0.066667, 0.066667, 0.066667, 0.96),
	surfaceAlt = rgba(0.11, 0.11, 0.11, 0.96),
	border = rgba(0.203922, 0.203922, 0.203922, 0.90),
	divider = rgba(0.18, 0.18, 0.18, 0.80),
	text = rgba(0.909804, 0.929412, 0.949020, 1),
	textMuted = rgba(0.611765, 0.647059, 0.682353, 1),
	accent = rgba(0.941176, 0.639216, 0.227451, 1),
	hover = rgba(0.20, 0.20, 0.20, 0.90),
	pressed = rgba(0.08, 0.08, 0.08, 0.96),
	selected = rgba(0.20, 0.30, 0.42, 0.50),
	-- Table chrome is a first-class visual contract. Rows must not inherit the
	-- brighter generic panel and hover colours.
	tableHeader = rgba(13 / 255, 13 / 255, 13 / 255, 1),
	tableRow = rgba(15 / 255, 15 / 255, 15 / 255, 1),
	tableRowAlt = rgba(18 / 255, 18 / 255, 18 / 255, 1),
	tableRowHover = rgba(24 / 255, 32 / 255, 42 / 255, 1),
	tableRowGroup = rgba(17 / 255, 17 / 255, 17 / 255, 1),
	tableRowChild = rgba(12 / 255, 12 / 255, 12 / 255, 1),
	tableRowDivider = rgba(28 / 255, 28 / 255, 28 / 255, 1),
	success = rgba(0.32, 0.82, 0.46, 1),
	warning = rgba(0.92, 0.72, 0.22, 1),
	danger = rgba(0.94, 0.30, 0.28, 1),
	info = rgba(0.42, 0.68, 0.92, 1),
}

local active = Theme._active or {}
Theme._active = active

local function channel(value, fallback)
	value = tonumber(value)
	if value == nil or value ~= value then value = fallback end
	return math.max(0, math.min(1, value))
end

local function cloneColor(value)
	if type(value) ~= "table" then return nil end
	return {
		r = channel(value.r or value[1], 0),
		g = channel(value.g or value[2], 0),
		b = channel(value.b or value[3], 0),
		a = channel(value.a or value[4], 1),
	}
end

--- Normalizes a renderer colour without sharing mutable token tables.
--- Invalid, non-finite or out-of-range channels fall back to a safe RGBA value.
function Theme.normalizeColor(value, fallback)
	return cloneColor(value) or cloneColor(fallback) or { r = 0, g = 0, b = 0, a = 1 }
end

function Theme.tokens(overrides)
	local out = {}
	for key, value in pairs(Theme.defaults) do out[key] = cloneColor(value) end
	for key, value in pairs(active) do out[key] = cloneColor(value) end
	if type(overrides) == "table" then
		for key, value in pairs(overrides) do
			if type(value) == "table" then out[key] = cloneColor(value) end
		end
	end
	return out
end

function Theme.set(overrides)
	if type(overrides) ~= "table" then return nil, "invalid_theme" end
	local replacement = {}
	for key, value in pairs(overrides) do
		local color = cloneColor(value)
		if not color then return nil, "invalid_color" end
		replacement[key] = color
	end
	active = replacement
	Theme._active = active
	return true
end

function Theme.color(name, overrides)
	local tokens = Theme.tokens(overrides)
	return tokens[name] or tokens.text
end

local function triplet(color)
	return { color.r, color.g, color.b, color.a }
end

--- Semantic palette for product renderers that draw directly with PZ's
--- positional colour API. Values are derived from the active theme, so these
--- renderers do not duplicate or freeze visual constants outside SiK UI.
function Theme.palette(overrides)
	local tokens = Theme.tokens(overrides)
	return {
		bgHeader = triplet(tokens.header), bgBody = triplet(tokens.background),
		bgCard = triplet(tokens.surface), cardBg = triplet(tokens.surface),
		btnDefault = triplet(tokens.surfaceAlt), btnHover = triplet(tokens.hover),
		btnPressed = triplet(tokens.pressed), btnActive = triplet(tokens.accent),
		border = triplet(tokens.border), accentLine = triplet(tokens.divider),
		divider = triplet(tokens.divider), textPrimary = triplet(tokens.text),
		textSecondary = triplet(tokens.textMuted), textMuted = triplet(tokens.textMuted),
		statusOk = triplet(tokens.success), statusWarn = triplet(tokens.warning),
		statusDanger = triplet(tokens.danger), statusInfo = triplet(tokens.info),
		ruleOr = triplet(tokens.info), ruleAnd = triplet(tokens.warning),
		ruleNot = triplet(tokens.danger), accent = triplet(tokens.accent),
	}
end

function Theme.apply(widget, role, overrides)
	if type(widget) ~= "table" then return nil, "invalid_widget" end
	local tokens = Theme.tokens(overrides)
	role = role or "surface"
	widget.backgroundColor = cloneColor(tokens[role] or tokens.surface)
	widget.borderColor = cloneColor(tokens.border)
	widget._sikThemeRole = role
	return widget
end

return Theme
