require "SiK/UI/Namespace"
require "SiK/UI/Controls"
require "SiK/UI/Icon"
require "SiK/UI/Layout"
require "SiK/UI/Theme"

local Card = SiK.UI.Card or {}
SiK.UI.Namespace.define("Card", Card)

local function fontHeight(font)
	if type(getTextManager) == "function" then
		local manager = getTextManager()
		if manager and manager.getFontHeight then return manager:getFontHeight(font) end
	end
	return 16
end

function Card.metrics(variant)
	if variant == "summary" then
		return { minWidth = 140, minHeight = 72, iconSize = 32, padding = 8,
			gap = 8, stateDotSize = 6, headerHeight = 24 }
	end
	if variant == "feature" then
		return { minWidth = 260, minHeight = 164, iconSize = 88, padding = 12,
			gap = 12, stateDotSize = 7, actionHeight = 32, headerHeight = 24 }
	end
	if variant == "process" then
		return { minWidth = 260, minHeight = 156, iconSize = 40, padding = 12,
			gap = 10, stateDotSize = 6, actionHeight = 32, headerHeight = 24 }
	end
	if variant == "output" then
		return { minWidth = 260, minHeight = 120, iconSize = 32, padding = 8,
			gap = 8, stateDotSize = 6, actionHeight = 32, headerHeight = 26,
			requirementIconSize = 32, requirementMinHeight = 38 }
	end
	if variant == "palette" then
		local padding, swatchHeight, titleGap = 8, 50, 5
		return { minWidth = 160,
			minHeight = math.max(92, padding * 2 + swatchHeight + titleGap
				+ fontHeight(UIFont.Small)),
			iconSize = 32, padding = padding, gap = 8, stateDotSize = 6,
			swatchHeight = swatchHeight, titleGap = titleGap, headerHeight = 24 }
	end
	return { minWidth = 160, minHeight = 64, iconSize = 32, padding = 8,
		gap = 8, stateDotSize = 6, headerHeight = 24 }
end

function Card.summaryMetrics() return Card.metrics("summary") end

-- Pure measurement is shared by declarative parents and mounted cards. No
-- temporary controls are created while resolving a parent's content height.
function Card.measureData(data, width, variant)
	data = type(data) == "table" and data or {}
	local metrics = Card.metrics(data.variant or variant)
	if type(data.output) ~= "table" then return metrics.minHeight end
	local contentWidth = math.max(1, (tonumber(width) or metrics.minWidth) - metrics.padding * 2)
	local function rowHeight(spec)
		if type(spec) ~= "table" then return 0 end
		local icon = spec.icon or spec.texture
		local iconSize = math.max(0, tonumber(spec.iconSize) or metrics.requirementIconSize or metrics.iconSize)
		local textWidth = math.max(1, contentWidth - (icon and (iconSize + metrics.gap) or 0))
		local lines = SiK.UI.Controls.wrapText(tostring(spec.text or spec.label or ""), textWidth, UIFont.Small)
		return math.max(metrics.requirementMinHeight or 1, icon and iconSize or 0,
			#lines * fontHeight(UIFont.Small) + math.max(0, #lines - 1) * 2)
	end
	local rowGap = type(data.requirement) == "table" and metrics.gap or 0
	return math.max(metrics.minHeight, metrics.padding * 2 + metrics.headerHeight + metrics.gap
		+ rowHeight(data.requirement) + rowHeight(data.output) + rowGap
		+ metrics.gap + (metrics.actionHeight or 0))
end

local function clipped(text, width, font)
	return SiK.UI.Controls.wrapText(tostring(text or ""), math.max(1, width), font)[1] or ""
end

-- Atomic final content. A Card exposes named terminal slots only; it is never
-- a recursive host and deliberately has no childParent/buildContent/Scroll.
function Card.create(options)
	options = options or {}
	if type(options.parent) ~= "table" then return nil, "invalid_parent" end
	local variant = options.variant or options.preset or "standard"
	local metrics = Card.metrics(variant)
	local panel = SiK.UI.Controls.panel(options.parent, {
		x = options.x or 0, y = options.y or 0,
                w = options.w or options.width or metrics.minWidth,
                h = options.h or options.height or metrics.minHeight,
		controlId = "card", playerNum = options.playerNum,
	})
	local instance = { panel = panel, options = options, variant = variant,
		payload = options.payload, data = {}, actions = options.actions or {} }
	panel._sikUiControl, panel._sikCardInstance = "card", instance
	local infoSpec = type(options.info) == "table" and options.info or {}
	instance.header = SiK.UI.Controls.blockHeader(panel, {
		x = metrics.padding, y = metrics.padding,
		w = math.max(1, panel.width - metrics.padding * 2),
		h = metrics.headerHeight,
		text = options.title or options.text or "",
		tooltip = infoSpec.tooltip or options.tooltip or options.title or options.text or "",
		info = infoSpec,
		profile = options.profile, theme = options.theme,
		playerNum = options.playerNum,
	})

	local function normalizeRequirement(value)
		if type(value) == "table" then
			return {
				text = tostring(value.text or value.label or ""),
				icon = value.icon or value.texture,
				state = value.state ~= nil and value.state or value.met,
				tone = value.tone,
				iconSize = value.iconSize,
			}
		end
		return tostring(value or "")
	end
	function instance:measure(width)
		return Card.measureData(self.data, width or self.panel.width, self.variant)
	end

	local function layoutRequirement()
		if not instance.requirementRow then return end
		if instance.outputRow then return end
		local actionReserve = instance.actionButton and (metrics.actionHeight + metrics.gap) or 0
		local bodyTop = metrics.padding + metrics.headerHeight + metrics.gap
		local bodyHeight = math.max(1, panel.height - bodyTop - metrics.padding - actionReserve)
		instance.requirementRow:setX(metrics.padding)
		instance.requirementRow:reflow(math.max(1, panel.width - metrics.padding * 2))
		local rowHeight = math.min(bodyHeight, instance.requirementRow.height)
		instance.requirementRow:setY(bodyTop + math.max(0, bodyHeight - rowHeight))
	end
	local function layoutOutputRows()
		if not instance.outputRow then return end
		local width = math.max(1, panel.width - metrics.padding * 2)
		local y = metrics.padding + metrics.headerHeight + metrics.gap
		if instance.requirementRow then
			instance.requirementRow:setX(metrics.padding)
			instance.requirementRow:reflow(width)
			instance.requirementRow:setY(y)
			y = y + instance.requirementRow.height + metrics.gap
		end
		instance.outputRow:setX(metrics.padding)
		instance.outputRow:reflow(width)
		instance.outputRow:setY(y)
	end

	function instance:setData(data)
		data = type(data) == "table" and data or {}
		self.data = {
			icon = data.icon or data.texture or options.icon or options.texture,
			title = tostring(data.title or data.text or options.title or options.text or ""),
			value = data.value ~= nil and tostring(data.value) or (options.value ~= nil and tostring(options.value) or ""),
			description = tostring(data.description or options.description or ""),
			status = tostring(data.status or data.statusLabel or options.status or options.statusLabel or ""),
			statusTone = data.statusTone or data.tone or options.statusTone or options.tone or "textMuted",
			requirement = normalizeRequirement(data.requirement or options.requirement),
			output = normalizeRequirement(data.output or options.output),
			actionLabel = tostring(data.actionLabel or options.actionLabel or ""),
			swatches = data.swatches or options.swatches,
			selected = data.selected == true or (data.selected == nil and options.selected == true),
			locked = data.locked == true or (data.locked == nil and options.locked == true),
		}
		if self.actionButton then
			self.actionButton.title = self.data.actionLabel
			self.actionButton:setEnabled(not self.data.locked)
		end
		if self.header then
			self.header:setText(self.data.title)
			if self.header.info then
				SiK.UI.Controls.setTooltip(self.header.info,
					infoSpec.tooltip or options.tooltip or self.data.description or self.data.title,
					{ playerNum = options.playerNum, kind = "descriptive", profile = "informational",
						placement = options.tooltipPlacement,
						channel = "informational-help" })
			end
		end
		if data.payload ~= nil then self.payload = data.payload end
		if self.requirementRow and type(self.data.requirement) == "table" then
			self.requirementRow:setData(self.data.requirement)
		end
		if self.outputRow and type(self.data.output) == "table" then self.outputRow:setData(self.data.output) end
		layoutRequirement()
		layoutOutputRows()
		return self
	end

	local previousPrerender = panel.prerender
	panel.prerender = function(self)
		if type(previousPrerender) == "function" then previousPrerender(self) end
		local theme = SiK.UI.Theme.tokens(options.theme)
		local background = options.background or (instance.data.selected and theme.selected or theme.surface)
		local border = options.border or (instance.data.selected and theme.accent or theme.border)
		self:drawRect(0, 0, self.width, self.height, background.a or 1,
			background.r, background.g, background.b)
		self:drawRectBorder(0, 0, self.width, self.height, border.a or 1,
			border.r, border.g, border.b)
		if options.accent then
			local accent = type(options.accent) == "table" and options.accent or theme.accent
			self:drawRect(0, 0, 3, self.height, accent.a or 0.8,
				accent.r or accent[1], accent.g or accent[2], accent.b or accent[3])
		end
	end

	local previousRender = panel.render
	panel.render = function(self)
		if type(previousRender) == "function" then previousRender(self) end
		local data = instance.data
		local theme = SiK.UI.Theme.tokens(options.theme)
		local alpha = data.locked and 0.45 or 1
		local x = metrics.padding
		local actionReserve = instance.actionButton and (metrics.actionHeight + metrics.gap) or 0
		local bodyTop = metrics.padding + metrics.headerHeight + metrics.gap
		local bodyHeight = math.max(1, self.height - bodyTop - metrics.padding - actionReserve)
		if instance.requirementRow then
			bodyHeight = math.max(1, bodyHeight - instance.requirementRow.height - metrics.gap)
		end
		if type(data.swatches) == "table" and #data.swatches > 0 then
			local previewW = math.max(1, self.width - metrics.padding * 2)
			local previewH = metrics.swatchHeight or 34
			local swatchW = math.max(1, math.floor(previewW / #data.swatches))
			for index = 1, #data.swatches do
				local swatch = SiK.UI.Theme.normalizeColor(data.swatches[index], theme.surfaceAlt)
				local drawW = index == #data.swatches and previewW - swatchW * (index - 1) or swatchW
				self:drawRect(x + (index - 1) * swatchW, bodyTop, drawW, previewH,
					swatch.a or 1, swatch.r, swatch.g, swatch.b)
			end
			self:drawRectBorder(x, bodyTop, previewW, previewH,
				theme.border.a or 1, theme.border.r, theme.border.g, theme.border.b)
			if data.selected then
				SiK.UI.Icon.drawExact(self, "sik.check.18",
					self.width - metrics.padding - 18, bodyTop,
					18, 18)
			end
			return
		end
		if instance.outputRow then return end
		if data.icon then
			local iconY = bodyTop + math.max(0,
				math.floor((bodyHeight - metrics.iconSize) / 2))
			SiK.UI.Icon.draw(self, data.icon, x, iconY, metrics.iconSize, metrics.iconSize,
				{ alpha = alpha })
			x = x + metrics.iconSize + metrics.gap
		end
		local width = math.max(1, self.width - x - metrics.padding)
		local line = fontHeight(UIFont.Small)
		local requirementText = type(data.requirement) == "string" and data.requirement or ""
		local rows = (data.value ~= "" and 1 or 0)
			+ (data.description ~= "" and 1 or 0) + (requirementText ~= "" and 1 or 0)
			+ (data.status ~= "" and 1 or 0)
		local textHeight = rows > 0 and rows * line + math.max(0, rows - 1) * 2 or 0
		local y = bodyTop + math.max(0, math.floor((bodyHeight - textHeight) / 2))
		local drewLine = false
		local function nextLineY()
			if drewLine then y = y + line + 2 end
			drewLine = true
			return y
		end
		if data.value ~= "" then self:drawText(clipped(data.value, width, UIFont.Small), x, nextLineY(),
			theme.accent.r, theme.accent.g, theme.accent.b, alpha, UIFont.Small) end
		if data.description ~= "" then self:drawText(clipped(data.description, width, UIFont.Small), x, nextLineY(),
			theme.textMuted.r, theme.textMuted.g, theme.textMuted.b, alpha, UIFont.Small) end
		if requirementText ~= "" then self:drawText(clipped(requirementText, width, UIFont.Small), x, nextLineY(),
			theme.warning.r, theme.warning.g, theme.warning.b, alpha, UIFont.Small) end
		if data.status ~= "" then
			y = nextLineY()
			local color = SiK.UI.Theme.color(data.statusTone, options.theme)
			self:drawRect(x, y + math.floor((line - metrics.stateDotSize) / 2),
				metrics.stateDotSize, metrics.stateDotSize, alpha, color.r, color.g, color.b)
			self:drawText(clipped(data.status, width - metrics.stateDotSize - 6, UIFont.Small),
				x + metrics.stateDotSize + 6, y, color.r, color.g, color.b, alpha, UIFont.Small)
		end
	end

	if metrics.actionHeight and tostring(options.actionLabel or "") ~= "" then
		instance.actionButton = SiK.UI.Controls.button(panel, {
			x = metrics.padding,
			y = math.max(metrics.padding, panel.height - metrics.padding - metrics.actionHeight),
			w = math.max(1, panel.width - metrics.padding * 2),
			h = metrics.actionHeight,
			text = "",
			enabled = false,
			onClick = function()
				if instance.data.locked then return false end
				if type(options.onActivate) == "function" then options.onActivate(instance.payload, instance) end
				return true
			end,
		})
	end

	local function createRequirementRow(spec)
		return SiK.UI.Controls.requirementRow(panel, {
			x = metrics.padding, y = 0, w = math.max(1, panel.width - metrics.padding * 2),
			text = spec.text or spec.label,
			icon = spec.icon or spec.texture,
			state = spec.state ~= nil and spec.state or spec.met,
			tone = spec.tone,
			iconSize = spec.iconSize or metrics.requirementIconSize or metrics.iconSize,
			minHeight = metrics.requirementMinHeight,
			playerNum = options.playerNum, theme = options.theme,
		})
	end
	if type(options.requirement) == "table" then
		instance.requirementRow = createRequirementRow(options.requirement)
	end
	if type(options.output) == "table" then
		instance.outputRow = createRequirementRow(options.output)
	end

	panel.onMouseDown = function() return not instance.data.locked end
	panel.onMouseUp = function()
		if instance.actionButton then return false end
		if instance.data.locked then return false end
		if type(options.onActivate) == "function" then options.onActivate(instance.payload, instance) end
		return true
	end
	function instance:reflow(bounds)
		if self.disposed then return nil, "disposed" end
		bounds = bounds or {}
		SiK.UI.Layout.apply(self.panel, { x = bounds.x or self.panel.x, y = bounds.y or self.panel.y,
			w = math.max(1, bounds.w or bounds.width or self.panel.width),
			h = math.max(1, bounds.h or bounds.height or self.panel.height) })
		if self.actionButton then
			SiK.UI.Layout.apply(self.actionButton, {
				x = metrics.padding,
				y = math.max(metrics.padding, self.panel.height - metrics.padding - metrics.actionHeight),
				w = math.max(1, self.panel.width - metrics.padding * 2),
				h = metrics.actionHeight,
			})
		end
		if self.header then
			SiK.UI.Layout.apply(self.header, {
				x = metrics.padding, y = metrics.padding,
				w = math.max(1, self.panel.width - metrics.padding * 2),
				h = metrics.headerHeight,
			})
			self.header:reflow(math.max(1, self.panel.width - metrics.padding * 2))
		end
		layoutRequirement()
		layoutOutputRows()
		return self
	end
	function instance:dispose()
		if self.disposed then return false end
		self.disposed = true
		local target = self.panel
		if self.header then self.header:dispose(); self.header = nil end
		if target and target.dispose then target:dispose() end
		if target then target._sikCardInstance = nil end
		self.panel = nil; return true
	end
	panel.destroy = function() return instance:dispose() end
	instance:setData(options)
	return instance
end

return Card
