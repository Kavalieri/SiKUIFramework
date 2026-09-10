require "SiK/UI/Controls"
require "SiK/UI/Block"
require "SiK/UI/Metrics"

local UI = SiK.UI
local Requirements = UI.Requirements or {}
UI.Namespace.define("Requirements", Requirements)

function Requirements.create(options)
	options = options or {}
	if type(options.parent) ~= "table" then return nil, "invalid_parent" end
	local groups, count = {}, 0
	for _, group in ipairs(options.groups or {}) do
		if type(group) == "table" and type(group.rows) == "table" and #group.rows > 0 then
			groups[#groups + 1] = group
			count = count + #group.rows
		end
	end
	local panel = UI.Controls.panel(options.parent, {
		x = tonumber(options.x) or 0, y = tonumber(options.y) or 0,
		w = math.max(1, tonumber(options.w) or 1), h = 0, playerNum = options.playerNum,
	})
	local handle = { panel = panel, height = 0, disposed = false, children = {} }
	local function clear()
		for i = #handle.children, 1, -1 do
			local child = handle.children[i]
			if child.dispose then child:dispose() end
			handle.children[i] = nil
		end
	end
	local function row(parent, spec, width, y)
		return UI.Controls.requirementRow(parent, {
			x = 0, y = y or 0, w = width, text = spec.text,
			texture = spec.texture, state = spec.state, tone = spec.tone,
			iconSize = 32, gap = UI.Metrics.tokens().spacing.sm,
			playerNum = options.playerNum,
		})
	end
	function handle:reflow(width)
		if self.disposed then return self end
		clear()
		panel:setWidth(math.max(1, tonumber(width) or panel.width))
		local gap = UI.Metrics.tokens().spacing.sm
		local grouped = count >= 4 and #groups == 2
		-- The approved HTML breakpoint is 900 px. Requirements live inside
		-- resizable Blocks, so this must use their actual content width rather
		-- than the monitor viewport: a narrow modal on a wide display still
		-- needs one readable requirement column.
		local columns = grouped and UI.Metrics.gridColumns({ w = panel.width,
			h = UI.Metrics.grid.minimumTwoColumnHeight }) or 1
		local columnW = math.max(1, (panel.width - gap * (columns - 1)) / columns)
		local bottom, cursor = 0, 0
		for index, group in ipairs(groups) do
			if grouped then
				local x = columns == 2 and (index - 1) * (columnW + gap) or 0
				local y = columns == 2 and 0 or cursor
				local block = assert(UI.Block.create({ parent = panel, x = x, y = y, w = columnW }))
				self.children[#self.children + 1] = block
				local column = block:beginColumn()
				for _, spec in ipairs(group.rows) do
					local widget = row(column.parent, spec, block:getContentRect().w)
					column:block(widget, widget.height)
				end
				local height = column:finish()
				bottom = math.max(bottom, y + height)
				cursor = bottom + gap
			else
				for _, spec in ipairs(group.rows) do
					local widget = row(panel, spec, panel.width, cursor)
					self.children[#self.children + 1] = widget
					bottom = cursor + widget.height
					cursor = bottom + gap
				end
			end
		end
		panel:setHeight(bottom)
		self.height = bottom
		return self
	end
	local baseDispose = panel.dispose
	function handle:dispose()
		if self.disposed then return false end
		self.disposed = true
		clear()
		return baseDispose(panel)
	end
	panel.dispose = function() return handle:dispose() end
	return handle:reflow(panel.width)
end
return Requirements
