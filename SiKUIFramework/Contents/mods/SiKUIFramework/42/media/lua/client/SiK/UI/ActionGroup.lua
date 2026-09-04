require "SiK/UI/Namespace"
require "SiK/UI/Container"

local ActionGroup = SiK.UI.ActionGroup or {}
SiK.UI.Namespace.define("ActionGroup", ActionGroup)

-- Semantic preset for related controls. It adds no product behavior and uses
-- the same Container geometry as every other composition.
function ActionGroup.create(options)
	options = options or {}
	local mode = options.mode or "content"
	-- content keeps natural action widths; equal distributes available width;
	-- wrap creates additional rows; stack is the narrow-screen column preset.
	if mode == "equal" then options.direction = "row"; options.equal = true
	elseif mode == "wrap" then options.direction = "row"; options.wrap = true
	elseif mode == "stack" then options.direction = "column"
	else mode = "content" end
	options.modeName = mode
	options.direction = options.direction or "row"
	-- Equal rows and stacked action sets are structural groups: unless a
	-- caller explicitly opts out, they keep consuming the width of their
	-- parent after that parent is reflowed. This is essential for Blocks,
	-- whose final content rectangle may not exist when children are created.
	if options.fillParentWidth == nil then
		options.fillParentWidth = mode == "equal" or mode == "stack"
	end
	-- Container owns geometry and accepts row/column/wrap, not the semantic
	-- ActionGroup preset names.  Passing "equal" through made its children
	-- fall back to a vertical layout and escape the group's one-row bounds.
	options.mode = options.wrap and "wrap" or options.direction
	options.align = options.align or "stretch"
	options.verticalAlign = options.verticalAlign or "middle"
	options.justify = options.justify or "start"
	options.defaultPadding = options.defaultPadding or 0
	options.controlId = options.controlId or "actionGroup"
	local instance, err = SiK.UI.Container.create(options)
	if instance and instance.panel then instance.panel._sikUiControl = "action-group" end
	if instance then
		local add = instance.add
		function instance:add(widget, spec)
			local normalized = {}
			for key, value in pairs(spec or {}) do normalized[key] = value end
			if self.options.equal then
				-- Equal actions consume the available row as equal flex units. A
				-- caller's construction width is intentionally not a layout hint.
				normalized.width = nil
				normalized.w = nil
				normalized.grow = 1
				normalized.shrink = 1
			end
			return add(self, widget, normalized)
		end
	end
	return instance, err
end

return ActionGroup
