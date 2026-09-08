require "SiK/UI/Namespace"
require "SiK/UI/Surface"

local Capabilities = SiK.UI.Capabilities or {}
SiK.UI.Namespace.define("Capabilities", Capabilities)

Capabilities.contracts = Capabilities.contracts or {
	["container.navigation"] = { componentType = "container", props = {
		enabled = { kind = "boolean", required = true, default = true },
		placement = { kind = "string", default = "top",
			enum = { left = true, right = true, top = true, bottom = true } },
		["active-key"] = { kind = "string" },
		extent = { kind = "number" },
		["content-gap"] = { kind = "number", default = 0 },
		["item-extent"] = { kind = "number" },
		["icon-size"] = { kind = "number" },
		["icon-fit"] = { kind = "string", default = "contain",
			enum = { contain = true, cover = true, fill = true } },
		["icon-padding"] = { kind = "number", default = 0 },
		["icon-only"] = { kind = "boolean", default = false },
		["tooltip-mode"] = { kind = "string", default = "native",
			enum = { native = true, flyout = true } },
		["selection-style"] = { kind = "string", default = "accent",
			enum = { accent = true, border = true } },
	} },
	["table.expandable"] = { componentType = "table", props = {
		expandable = { kind = "boolean", required = true, default = false },
		depth = { kind = "number", default = 0 },
		connectors = { kind = "boolean", default = true },
		["child-pagination"] = { kind = "boolean", default = false },
	} },
	["table.pagination"] = { componentType = "table", props = {
		["page-size"] = { kind = "number", required = true, default = 15 },
	} },
	["table.row-interactions"] = { componentType = "table", props = {
		adapter = { kind = "string", required = true,
			enum = { ["context.tableOptions"] = true } },
		tooltip = { kind = "boolean", default = false },
		contextMenu = { kind = "boolean", default = false },
		drag = { kind = "boolean", default = false },
		preserveVanillaTooltip = { kind = "boolean", default = true },
		exactSelection = { kind = "boolean", default = true },
		dragGhostMode = { kind = "string", default = "visible-rows",
			enum = { ["visible-rows"] = true, ["logical-selection"] = true } },
		transferScope = { kind = "string", default = "visible-rows",
			enum = { ["visible-rows"] = true, ["logical-selection"] = true } },
	} },
	["window.chrome"] = { componentType = "window", props = {
		["header-visible"] = { kind = "boolean", default = true },
		["footer-visible"] = { kind = "boolean", default = true },
		["header-context"] = { kind = "data" },
		["header-status"] = { kind = "data" },
		["header-separator"] = { kind = "string", default = " | " },
		["footer-items"] = { kind = "data" },
		["footer-align"] = { kind = "string", default = "center",
			enum = { left = true, center = true, right = true } },
		["resize-grip"] = { kind = "boolean", default = true },
	} },
	["window.tabs"] = { componentType = "window", props = {
		enabled = { kind = "boolean", required = true, default = true },
		rail = { kind = "boolean", default = true },
	} },
	["window.modal"] = { componentType = "window", props = {
		enabled = { kind = "boolean", required = true, default = true },
		dismissible = { kind = "boolean", default = true },
		escape = { kind = "boolean", default = true },
	} },
	["block.header"] = { componentType = "block", props = {
		["info-visible"] = { kind = "boolean", default = false },
		["leading-indicator"] = { kind = "data" },
		actions = { kind = "data" },
	} },
	["form.fields"] = { componentType = "form", props = {
		fields = { kind = "data", required = true },
		actions = { kind = "data" },
	} },
	["card.actions"] = { componentType = "card", props = {
		actions = { kind = "data", required = true },
		equal = { kind = "boolean", default = true },
	} },
	["tooltip.vanilla-chain"] = { componentType = "tooltip", props = {
		["preserve-vanilla"] = { kind = "boolean", required = true, default = true },
		lazy = { kind = "boolean", default = true },
		append = { kind = "data" },
	} },
	["drag.ghost"] = { componentType = "drag", props = {
		rows = { kind = "data", required = true },
		["exact-clone"] = { kind = "boolean", required = true, default = true },
		["max-visible"] = { kind = "number", default = 15 },
	} },
}

local function valueMatches(kind, value)
	if value == nil or kind == "data" then return true end
	return type(value) == kind
end

local function enumMatches(definition, value)
	return value == nil or type(definition.enum) ~= "table" or definition.enum[value] == true
end

function Capabilities.registerDefaults()
	for capabilityId, contract in pairs(Capabilities.contracts) do
		local ok, err = SiK.UI.Surface.registerCapability(capabilityId, contract)
		if not ok then return nil, err end
	end
	return true
end

function Capabilities.resolve(node, context, resolver)
	local resolved = {}
	for index = 1, #(node.capabilities or {}) do
		local declaration = node.capabilities[index]
		local contract = Capabilities.contracts[declaration.id]
		if not contract or contract.componentType ~= node.type then
			return nil, "invalid_capability:" .. tostring(declaration.id)
		end
		local values = {}
		for name, definition in pairs(contract.props or {}) do values[name] = definition.default end
		for propIndex = 1, #(declaration.props or {}) do
			local prop = declaration.props[propIndex]
			local definition = contract.props and contract.props[prop.name]
			if not definition then return nil, "unknown_capability_prop:" .. prop.name end
			local value = resolver(prop.value, context)
			if not valueMatches(definition.kind, value) or not enumMatches(definition, value) then
				return nil, "invalid_capability_value:" .. declaration.id .. "/" .. prop.name
			end
			values[prop.name] = value
		end
		for name, definition in pairs(contract.props or {}) do
			if definition.required and values[name] == nil then
				return nil, "missing_capability_prop:" .. declaration.id .. "/" .. name
			end
		end
		resolved[declaration.id] = values
	end
	return resolved
end

return Capabilities
