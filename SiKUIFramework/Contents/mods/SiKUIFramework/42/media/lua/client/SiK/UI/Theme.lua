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
	-- Button danger is a calm chrome role, separate from the saturated semantic
	-- danger token used by status and progress renderers.
	dangerButtonFill = rgba(41 / 255, 21 / 255, 20 / 255, 1),
	dangerButtonBorder = rgba(116 / 255, 56 / 255, 51 / 255, 1),
	dangerButtonText = rgba(241 / 255, 138 / 255, 129 / 255, 1),
	info = rgba(0.42, 0.68, 0.92, 1),
}

local active = Theme._active or {}
Theme._active = active
Theme._activeByPlayer = Theme._activeByPlayer or {}
Theme._bindings = Theme._bindings or setmetatable({}, { __mode = "k" })
Theme._revision = Theme._revision or 0

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

local function playerKey(playerNum)
	if playerNum == nil then return nil end
	local value = tonumber(playerNum)
	if value == nil or value ~= value or value < 0 or value > 3
		or value ~= math.floor(value) then return nil, "invalid_player" end
	return tostring(value)
end

local function copyColors(source)
	local copy = {}
	for key, value in pairs(source or {}) do copy[key] = cloneColor(value) end
	return copy
end

local function normalizeOverrides(overrides)
	if overrides == nil then return {} end
	if type(overrides) ~= "table" then return nil, "invalid_theme" end
	local out = {}
	for key, value in pairs(overrides) do
		local color = cloneColor(value)
		if not color then return nil, "invalid_color" end
		out[key] = color
	end
	return out
end

local function mergeColors(target, source)
	for key, value in pairs(source or {}) do target[key] = cloneColor(value) end
	return target
end

local function colorsEqual(left, right)
	for key, value in pairs(left or {}) do
		local other = right and right[key] or nil
		if not other or value.r ~= other.r or value.g ~= other.g
			or value.b ~= other.b or value.a ~= other.a then return false end
	end
	for key in pairs(right or {}) do if not left or not left[key] then return false end end
	return true
end

local function isContext(value)
	return type(value) == "table" and value._sikThemeContext == true
end

local function parentContext(parent)
	if isContext(parent) then return parent end
	if type(parent) == "table" and isContext(parent._sikThemeContext) then
		return parent._sikThemeContext
	end
	return nil
end

--- A context remains live: it stores only partial overrides and ancestry.
--- Snapshot tokens are always returned independently by Theme.tokens(context).
function Theme.context(parent, overrides, playerNum)
	-- Factories forward a live context through options.theme; it is not a
	-- colour dictionary and must retain its identity/ancestry.
	if isContext(overrides) then return overrides end
	local inherited = parentContext(parent)
	local normalized, reason = normalizeOverrides(overrides)
	if not normalized then return nil, reason end
	if playerNum == nil and inherited then playerNum = inherited.playerNum end
	if playerNum == nil and type(parent) == "table" and not isContext(parent) then
		playerNum = parent.playerNum
	end
	local key, playerReason = playerKey(playerNum)
	if playerReason then return nil, playerReason end
	return { _sikThemeContext = true, parent = inherited, overrides = normalized,
		playerNum = key and tonumber(key) or nil }
end

local function resolveContext(context, depth)
	if context._cachedRevision == Theme._revision then return context._cachedTokens end
	local out = copyColors(Theme.defaults)
	mergeColors(out, active)
	local key = playerKey(context.playerNum)
	if key then mergeColors(out, Theme._activeByPlayer[key]) end
	-- Contexts are created as acyclic ancestry. Bound traversal also degrades
	-- safely if a third-party consumer mutates that public table incorrectly.
	local inherited = {}
	if isContext(context.parent) and depth < 64 then
		resolveContext(context.parent, depth + 1)
		mergeColors(inherited, context.parent._cachedOverrides)
	end
	mergeColors(inherited, context.overrides)
	mergeColors(out, inherited)
	context._cachedOverrides = inherited
	context._cachedRevision, context._cachedTokens = Theme._revision, out
	return out
end

function Theme.tokens(overrides)
	local context = isContext(overrides) and overrides or nil
	if context then return copyColors(resolveContext(context, 0)) end
	local out = copyColors(Theme.defaults)
	mergeColors(out, active)
	if type(overrides) == "table" then mergeColors(out, overrides) end
	return out
end

local function notifyBindings()
	local widgets = {}
	for widget in pairs(Theme._bindings) do
		local depth, parent = 0, widget.parent
		while type(parent) == "table" and depth < 64 do
			depth = depth + 1
			parent = parent.parent
		end
		widgets[#widgets + 1] = { widget = widget, depth = depth }
	end
	-- Parent material must be current before descendants compose their source
	-- layers. This ordering is evaluated only on a changed palette.
	table.sort(widgets, function(left, right) return left.depth < right.depth end)
	for index = 1, #widgets do
		local widget = widgets[index].widget
		local binding = widget and widget._sikThemeBinding or nil
		if binding and binding.apply then
			local nextTokens = Theme.tokens(binding.context)
			if not colorsEqual(binding.tokens, nextTokens) then
				binding.tokens = nextTokens
				pcall(binding.apply, widget, binding.context)
			end
		end
	end
end

--- Replaces the global or player override layer; omitted tokens inherit.
--- An empty table restores that layer's inherited defaults, as before.
--- Equal values are a no-op and do not invoke bound widget callbacks.
function Theme.set(overrides, playerNum)
	if type(overrides) ~= "table" then return nil, "invalid_theme" end
	local normalized, reason = normalizeOverrides(overrides)
	if not normalized then return nil, reason end
	local key, playerReason = playerKey(playerNum)
	if playerReason then return nil, playerReason end
	local target = key and (Theme._activeByPlayer[key] or {}) or active
	local replacement = normalized
	if colorsEqual(target, replacement) then return false end
	if key then Theme._activeByPlayer[key] = replacement
	else active = replacement; Theme._active = active end
	Theme._revision = Theme._revision + 1
	notifyBindings()
	return true
end

--- Binds a widget without retaining it from the context graph. The callback
--- receives (widget, context); it may read its defensive snapshot via tokens.
function Theme.bind(widget, context, apply)
	if type(widget) ~= "table" then return nil, "invalid_widget" end
	if context == nil then
		Theme._bindings[widget] = nil
		widget._sikThemeBinding, widget._sikThemeContext = nil, nil
		return true
	end
	if not isContext(context) or type(apply) ~= "function" then return nil, "invalid_binding" end
	local binding = { context = context, apply = apply, tokens = Theme.tokens(context) }
	widget._sikThemeBinding = binding
	widget._sikThemeContext = context
	Theme._bindings[widget] = true
	pcall(apply, widget, context)
	return widget
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

-- Window chrome is layered source material. `paint` is the one colour a
-- renderer draws at this node; `effective` is bookkeeping for descendants.
Theme.materialDefaults = Theme.materialDefaults or {
	window = { token = "background", alpha = 0.80 },
	header = { token = "header", alpha = 0.20 },
	footer = { token = "header", alpha = 0.20 },
	-- Structural surfaces share the nearest non-surface base.  A Block inside
	-- another Block therefore retains one translucent layer instead of becoming
	-- darker at every nesting level.  Tables use their deliberate opaque palette
	-- directly and never resolve either role.
	surface = { token = "surface", alpha = 0.13, stableSurfaceBase = true,
		maxEffectiveAlpha = 0.84 },
	surfaceAlt = { token = "surfaceAlt", alpha = 0.18, stableSurfaceBase = true,
		maxEffectiveAlpha = 0.86 },
	-- UIManager renders a popover over the world, rather than compositing it
	-- into its owner window. Its paint must therefore be its physical target.
	popover = { token = "surfaceAlt", alpha = 0.92, detached = true },
	-- Controls may sit on the translucent window shell.  Cap their composed
	-- alpha so the source layer remains visible without turning that stack into
	-- a second opaque panel.  Explicit role overrides still select the colour;
	-- the cap only prevents a further source-over accumulation.
	control = { token = "surfaceAlt", alpha = 0.88, maxEffectiveAlpha = 0.92 },
}

local function materialParent(parent)
	if type(parent) ~= "table" then return nil end
	if type(parent._sikMaterial) == "table" then return parent._sikMaterial end
	if type(parent.effective) == "table" then return parent end
	return nil
end

local function materialContext(parent, themeContext)
	if isContext(themeContext) then return themeContext end
	return parentContext(parent)
end

--- Resolves one source layer without allocating theme tokens during render.
--- `overrides[role]={r,g,b,a}` is explicit and accepts alpha 0.
--- themeContext is optional and carries the live inherited palette.
function Theme.resolveMaterial(role, parent, overrides, themeContext)
	role = role or "inherit"
	local inherited = materialParent(parent)
	local parentColor = inherited and inherited.effective or nil
	if role == "inherit" or role == "transparent" then
		return { role = role, paint = nil, effective = cloneColor(parentColor)
			or { r = 0, g = 0, b = 0, a = 0 } }
	end
	local spec = Theme.materialDefaults[role]
	if not spec then return nil, "invalid_material_role" end
	local override = type(overrides) == "table" and overrides[role] or nil
	if override ~= nil and type(override) ~= "table" then return nil, "invalid_material_override" end
	local tokens = Theme.tokens(materialContext(parent, themeContext))
	local paint = cloneColor(tokens[spec.token] or Theme.defaults[spec.token])
	paint.a = spec.alpha
	if override then
		paint.r = channel(override.r or override[1], paint.r)
		paint.g = channel(override.g or override[2], paint.g)
		paint.b = channel(override.b or override[3], paint.b)
		paint.a = channel(override.a or override[4], paint.a)
	end
	local surfaceBase = spec.stableSurfaceBase and inherited and inherited.surfaceBase
	local actualBase = parentColor or { r = paint.r, g = paint.g, b = paint.b, a = 0 }
	if spec.detached then actualBase = { r = paint.r, g = paint.g, b = paint.b, a = 0 } end
	if surfaceBase then
		-- `surfaceBase` describes the desired alpha, while the immediate parent is
		-- the real backdrop PZ has already painted. Derive only the delta needed
		-- to reach the target; using surfaceBase itself as the compositor would
		-- make nested Blocks darken despite their bookkeeping descriptor.
		local targetAlpha = paint.a + surfaceBase.a * (1 - paint.a)
		if spec.maxEffectiveAlpha then targetAlpha = math.min(targetAlpha, spec.maxEffectiveAlpha) end
		if targetAlpha > actualBase.a then
			paint.a = (targetAlpha - actualBase.a) / math.max(0.0001, 1 - actualBase.a)
		else
			paint.a = 0
		end
	elseif spec.maxEffectiveAlpha and actualBase.a < spec.maxEffectiveAlpha then
		local allowed = (spec.maxEffectiveAlpha - actualBase.a) / math.max(0.0001, 1 - actualBase.a)
		paint.a = math.min(paint.a, math.max(0, allowed))
	elseif spec.maxEffectiveAlpha and actualBase.a >= spec.maxEffectiveAlpha then
		paint.a = 0
	end
	local alpha = paint.a + actualBase.a * (1 - paint.a)
	local sourceWeight = alpha > 0 and paint.a / alpha or 0
	local baseWeight = alpha > 0 and actualBase.a * (1 - paint.a) / alpha or 0
	local effective = {
		r = paint.r * sourceWeight + actualBase.r * baseWeight,
		g = paint.g * sourceWeight + actualBase.g * baseWeight,
		b = paint.b * sourceWeight + actualBase.b * baseWeight,
		a = alpha,
	}
	return { role = role, paint = paint, effective = effective,
		surfaceBase = spec.detached and cloneColor(effective)
			or spec.stableSurfaceBase and cloneColor(surfaceBase or actualBase)
			or (inherited and cloneColor(inherited.surfaceBase)) or cloneColor(effective) }
end

return Theme
