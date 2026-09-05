require "SiK/UI/Namespace"

SiK = SiK or {}
SiK.UI = SiK.UI or {}

local Metrics = SiK.UI.Metrics or {}
SiK.UI.Namespace.define("Metrics", Metrics)

Metrics.spacing = Metrics.spacing or {
	xxs = 4,
	xs = 6,
	sm = 8,
	md = 12,
	lg = 16,
}

Metrics.block = Metrics.block or {
	padding = 8,
	scrollBarWidth = 14,
	scrollGap = 10,
	scrollGutter = 24,
}

Metrics.table = Metrics.table or {
	rowHeight = 40,
	headerHeight = 34,
	columnGap = 8,
	cellPadding = 6,
	rowVerticalPadding = 10,
	headerVerticalPadding = 10,
	pagerHeight = 28,
	expansionHitbox = 32,
	expansionIndent = 20,
}

Metrics.safeMargin = Metrics.safeMargin or 16
-- Shared grid breakpoint, matching the approved HTML viewport media query.
Metrics.grid = Metrics.grid or { minimumTwoColumnWidth = 900, minimumTwoColumnHeight = 700 }

function Metrics.gridColumns(viewport)
	local width = tonumber(viewport and viewport.w) or 0
	local height = tonumber(viewport and viewport.h) or 0
	return width >= Metrics.grid.minimumTwoColumnWidth
		and height >= Metrics.grid.minimumTwoColumnHeight and 2 or 1
end

Metrics.profiles = Metrics.profiles or {
	compact = { minWidth = 0, contentGap = 6, rowHeight = 28 },
	standard = { minWidth = 720, contentGap = 8, rowHeight = 32 },
	wide = { minWidth = 1000, contentGap = 8, rowHeight = 34 },
	terminal = {
		minWidth = 720, minHeight = 480, contentGap = 8, rowHeight = 32,
		window = {
			preferredWidth = 1600, preferredHeight = 900,
			minWidth = 720, minHeight = 480,
                        -- Rail, celda y asset comparten el cuadrado nominal. No se
                        -- reserva una segunda franja horizontal alrededor del icono.
                        railWidth = 76, railItemHeight = 76, railIconSize = 76,
                        railPadding = 0, railGap = 4, railSlotInset = 0,
			headerHeight = 52, footerMinimumHeight = 0,
			footerLines = 1, footerPaddingY = 12, footerLineGap = 0,
		},
		controls = { buttonHeight = 30, inputHeight = 30, rowGap = 8, controlGap = 6 },
	},
	editor = {
		minWidth = 760, minHeight = 620, contentGap = 6, rowHeight = 30,
		window = { preferredWidth = 1180, preferredHeight = 1048,
			minWidth = 760, minHeight = 620, maxWidth = 8192, maxHeight = 8192,
			railWidth = 0, headerHeight = 52, footerHeight = 24 },
		controls = { buttonHeight = 30, inputHeight = 30, rowGap = 6, controlGap = 6 },
	},
	staff = {
		minWidth = 720, minHeight = 520, contentGap = 6, rowHeight = 30,
		window = { preferredWidth = 1000, preferredHeight = 720,
			minWidth = 720, minHeight = 520, maxWidth = 1200, maxHeight = 860,
			railWidth = 0, headerHeight = 52, footerHeight = 24 },
		controls = { buttonHeight = 30, inputHeight = 30, rowGap = 6, controlGap = 6 },
	},
}

local function numberOr(value, fallback)
	value = tonumber(value)
	if value == nil or value ~= value then return fallback end
	return value
end

local function copy(source)
	local out = {}
	if type(source) ~= "table" then return out end
	for key, value in pairs(source) do
		out[key] = type(value) == "table" and copy(value) or value
	end
	return out
end

function Metrics.tokens(overrides)
	local out = {
		spacing = copy(Metrics.spacing),
		block = copy(Metrics.block),
		table = copy(Metrics.table),
		safeMargin = Metrics.safeMargin,
	}
	-- Flat names are compatibility tokens, not a second source of truth.
	out.space4 = out.spacing.xxs
	out.space6 = out.spacing.xs
	out.space8 = out.spacing.sm
	out.space12 = out.spacing.md
	out.space16 = out.spacing.lg
	out.blockPaddingX = out.block.padding
	out.blockPaddingY = out.block.padding
	out.scrollBarWidth = out.block.scrollBarWidth
	out.scrollBarGap = out.block.scrollGap
	out.scrollGutter = out.block.scrollGutter
	out.tableRowHeight = out.table.rowHeight
	out.tableHeaderHeight = out.table.headerHeight
	out.tableColumnGap = out.table.columnGap
	out.tableCellPadding = out.table.cellPadding
	if type(overrides) ~= "table" then return out end
	if type(overrides.spacing) == "table" then
		for key, value in pairs(overrides.spacing) do
			out.spacing[key] = numberOr(value, out.spacing[key])
		end
	end
	if type(overrides.block) == "table" then
		for key, value in pairs(overrides.block) do
			out.block[key] = numberOr(value, out.block[key])
		end
	end
	if type(overrides.table) == "table" then
		for key, value in pairs(overrides.table) do
			out.table[key] = numberOr(value, out.table[key])
		end
	end
	out.safeMargin = numberOr(overrides.safeMargin, out.safeMargin)
	out.blockPaddingX = out.block.padding
	out.blockPaddingY = out.block.padding
	out.scrollBarWidth = out.block.scrollBarWidth
	out.scrollBarGap = out.block.scrollGap
	out.scrollGutter = out.block.scrollGutter
	out.tableRowHeight = out.table.rowHeight
	out.tableHeaderHeight = out.table.headerHeight
	out.tableColumnGap = out.table.columnGap
	out.tableCellPadding = out.table.cellPadding
	return out
end

function Metrics.profile(width, requested)
	if requested and Metrics.profiles[requested] then
		local selected = copy(Metrics.profiles[requested])
		selected.name = requested
		return selected
	end
	width = numberOr(width, 0)
	local name = "compact"
	if width >= Metrics.profiles.wide.minWidth then
		name = "wide"
	elseif width >= Metrics.profiles.standard.minWidth then
		name = "standard"
	end
	local selected = copy(Metrics.profiles[name])
	selected.name = name
	return selected
end

function Metrics.blockRects(width, height, overflow, reservedTop, reservedBottom, overrides,
	paddingX, paddingY)
	local tokens = Metrics.tokens(overrides)
	local block = tokens.block
	local padding = math.max(0, numberOr(block.padding, 8))
	local px = math.max(0, numberOr(paddingX, padding))
	local py = math.max(0, numberOr(paddingY, padding))
	local gutter = overflow and math.max(0, numberOr(block.scrollGutter, 24)) or 0
	local top = math.max(0, numberOr(reservedTop, 0))
	local bottom = math.max(0, numberOr(reservedBottom, 0))
	local innerW = math.max(0, numberOr(width, 0) - px * 2)
	local innerH = math.max(0, numberOr(height, 0) - py * 2 - top - bottom)
	local contentW = math.max(0, innerW - gutter)
	local content = { x = px, y = py + top, w = contentW, h = innerH }
	local track = nil
	if overflow then
		track = {
			x = px + contentW + math.max(0, numberOr(block.scrollGap, 10)),
			y = py + top,
			w = math.max(0, numberOr(block.scrollBarWidth, 14)),
			h = innerH,
		}
	end
	return content, track
end

return Metrics
