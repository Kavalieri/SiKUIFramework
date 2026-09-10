require "SiK/UI/Namespace"

local Surface = SiK.UI.Surface or {}
SiK.UI.Namespace.define("Surface", Surface)

local componentTypes = Surface._componentTypes or {}
local capabilities = Surface._capabilities or {}
local actionEvents = Surface._actionEvents or {
	activate = true, change = true, submit = true, cancel = true, hover = true,
	contextmenu = true, dragstart = true, dragover = true, drop = true, dragcancel = true,
}
Surface._componentTypes = componentTypes
Surface._capabilities = capabilities
Surface._actionEvents = actionEvents

local layoutModes = { flow = true, row = true, column = true, grid = true,
	overlay = true, absolute = true }
local layoutNames = { x = true, y = true, width = true, height = true,
	["min-width"] = true, ["min-height"] = true, ["max-width"] = true,
	["max-height"] = true, gap = true, padding = true, grow = true, shrink = true,
	columns = true, ["stack-below"] = true, span = true, align = true, ["align-x"] = true, ["align-y"] = true,
	["vertical-align"] = true, justify = true, clip = true, fill = true }

local function identifier(value)
        return type(value) == "string" and value ~= "" and not string.find(value, "%s")
end

local function propIdentifier(value)
        if type(value) ~= "string" or not string.find(value, "^[a-z][A-Za-z0-9%._:%-]*$") then
                return false
        end
        for index = 2, #value do
                local char = string.sub(value, index, index)
                if char == "." or char == "_" or char == ":" or char == "-" then
                        local nextChar = string.sub(value, index + 1, index + 1)
                        if not string.find(nextChar, "^[a-z0-9]$") then return false end
                end
        end
        return true
end

local function sha256(value)
	return type(value) == "string" and #value == 64 and not string.find(value, "[^a-f0-9]")
end

local function repositoryId(value)
	return type(value) == "string" and string.find(value, "^[a-z][a-z0-9%._:%-]*$") ~= nil
		and not string.find(value, "[._:%-][._:%-]")
		and not string.find(value, "[._:%-]$")
end

local function relativePath(value)
	if type(value) ~= "string" or value == "" or string.find(value, "\\", 1, true)
		or string.sub(value, 1, 1) == "/" or string.find(value, "^%a:") then return false end
	for part in string.gmatch(value, "[^/]+") do
		if part == ".." then return false end
	end
	return true
end

local function scalar(value)
	local kind = type(value)
	return kind == "nil" or kind == "boolean" or kind == "number" or kind == "string"
end

local function portable(value, depth, seen)
	if scalar(value) then return true end
	if type(value) ~= "table" or depth >= 16 or seen[value] then return false end
	seen[value] = true
	for key, child in pairs(value) do
		if (type(key) ~= "string" and type(key) ~= "number")
			or not portable(child, depth + 1, seen) then
			seen[value] = nil
			return false
		end
	end
	seen[value] = nil
	return true
end

local function contractSet(values)
        if type(values) ~= "table" then return nil end
        local result = {}
        if #values > 0 then
                for index = 1, #values do result[values[index]] = true end
        else
                for key, value in pairs(values) do if value == true then result[key] = true end end
        end
        return result
end

function Surface.registerType(typeId, contract)
	if not identifier(typeId) or type(contract) ~= "table"
		or not identifier(contract.runtimeFactory) then return nil, "invalid_component_contract" end
	local current = componentTypes[typeId]
	if current and current.runtimeFactory ~= contract.runtimeFactory then
		return nil, "component_type_conflict"
	end
        local normalized = {}
        for key, value in pairs(contract) do normalized[key] = value end
        normalized.parents = contractSet(contract.parents)
        normalized.allowedChildren = contractSet(contract.allowedChildren)
        componentTypes[typeId] = normalized
	return true
end

function Surface.unregisterType(typeId)
	componentTypes[typeId] = nil
	return true
end

function Surface.componentContract(typeId)
	return componentTypes[typeId]
end

function Surface.registerCapability(capabilityId, contract)
	if not identifier(capabilityId) or type(contract) ~= "table"
		or not identifier(contract.componentType) then return nil, "invalid_capability_contract" end
	if componentTypes[contract.componentType] == nil then return nil, "unknown_capability_component" end
	local current = capabilities[capabilityId]
	if current and current.componentType ~= contract.componentType then return nil, "capability_conflict" end
	capabilities[capabilityId] = contract
	return true
end

function Surface.capabilityContract(capabilityId)
	return capabilities[capabilityId]
end

function Surface.registerActionEvent(eventId)
	if not identifier(eventId) then return nil, "invalid_action_event" end
	actionEvents[eventId] = true
	return true
end

local function binding(value, path, references)
	if scalar(value) then return true end
	if type(value) ~= "table" or type(value.kind) ~= "string" then
		return false, path .. " must be scalar or binding"
	end
	if value.kind == "literal" then
		return scalar(value.value), path .. ".value must be scalar"
	end
	if value.kind == "data" or value.kind == "state" then
		return identifier(value.path), path .. ".path required"
	end
	if value.kind == "i18n" or value.kind == "asset" or value.kind == "token" then
		if not identifier(value.ref) then return false, path .. ".ref required" end
		if references and references[value.kind] and not references[value.kind][value.ref] then
			return false, path .. ".ref undeclared: " .. value.ref
		end
		return true
	end
	return false, path .. ".kind unknown: " .. tostring(value.kind)
end

local function namedBindings(values, path, references, acceptedNames)
	if type(values) ~= "table" then return false, path .. " must be an array" end
	local names = {}
	for index = 1, #values do
		local entry = values[index]
                if type(entry) ~= "table" or not propIdentifier(entry.name) then
			return false, path .. "[" .. index .. "].name required"
		end
		if names[entry.name] then return false, path .. " name duplicate: " .. entry.name end
		if acceptedNames and not acceptedNames[entry.name] then
			return false, path .. " name unknown: " .. entry.name
		end
		names[entry.name] = true
		local ok, err = binding(entry.value, path .. "[" .. index .. "].value", references)
		if not ok then return false, err end
	end
	return true, names
end

local function arrayIndex(values, path, field)
	if type(values) ~= "table" then return nil, path .. " must be an array" end
	local result = {}
	for index = 1, #values do
		local entry = values[index]
		local key = type(entry) == "table" and entry[field] or entry
		if not identifier(key) then return nil, path .. "[" .. index .. "] invalid" end
		if result[key] then return nil, path .. " duplicate: " .. key end
		result[key] = entry
	end
	return result
end

local function allowlistMap(spec)
	local indexed, err = arrayIndex(spec.actionAllowlist or {}, "actionAllowlist", "id")
	if not indexed then return nil, err end
	local result = {}
	for actionId, entry in pairs(indexed) do
		if type(entry.events) ~= "table" or #entry.events == 0 then
			return nil, "actionAllowlist events required: " .. actionId
		end
		result[actionId] = {}
		for index = 1, #entry.events do
			local eventId = entry.events[index]
			if not actionEvents[eventId] then return nil, "action event unknown: " .. tostring(eventId) end
			result[actionId][eventId] = true
		end
	end
	return result
end

local function validateLayout(layout, profiles, references, path)
	if type(layout) ~= "table" or not layoutModes[layout.mode] then return false, path .. ".mode unknown" end
	local ok, err = namedBindings(layout.base or {}, path .. ".base", references, layoutNames)
	if not ok then return false, err end
	local overrides = layout.overrides or {}
	if type(overrides) ~= "table" then return false, path .. ".overrides must be array" end
	local seen = {}
	for index = 1, #overrides do
		local override = overrides[index]
		if type(override) ~= "table" or not profiles[override.profileId] then
			return false, path .. ".overrides[" .. index .. "].profileId undeclared"
		end
		if seen[override.profileId] then return false, path .. " duplicate profile override" end
		seen[override.profileId] = true
		ok, err = namedBindings(override.bindings or {}, path .. ".overrides[" .. index .. "].bindings",
			references, layoutNames)
		if not ok then return false, err end
	end
	return true
end

local function hasNamed(values, name)
	for index = 1, #(values or {}) do if values[index].name == name then return true end end
	return false
end

local function hasCapability(node, capabilityId)
	for index = 1, #(node.capabilities or {}) do
		if node.capabilities[index].id == capabilityId then return true end
	end
	return false
end

local function specialShape(node, path, state)
	local children = node.children or {}
	if (node.type == "tooltip" or node.type == "menu" or node.type == "drag") and #children > 0 then
		return false, path .. " type cannot host children"
	end
	if node.type == "form" and #children > 0
		and (hasCapability(node, "form.fields") or hasNamed(node.props, "fields")) then
		return false, path .. " form cannot mix declarative children with fields data"
	end
	if node.type == "card-collection" then
		if #children > 0 and hasNamed(node.props, "items") then
			return false, path .. " card-collection cannot mix children with items data"
		end
		for index = 1, #children do
			if children[index].type ~= "card" then return false, path .. " children must be card" end
		end
	end
        local ownsNavigationTargets = node.type == "tabs"
                or (node.type == "container" and hasCapability(node, "container.navigation"))
        if ownsNavigationTargets then
		local childIds, options, targets = {}, node.options or {}, {}
		for index = 1, #children do childIds[children[index].id] = true end
		for index = 1, #options do
			local option = options[index]
			local hasContent, hasSurface = option.contentId ~= nil, option.surfaceRef ~= nil
			if hasContent == hasSurface then
				return false, path .. ".options requires exactly one contentId or surfaceRef"
			end
			local prefix, target = hasContent and "content:" or "surface:",
				hasContent and option.contentId or option.surfaceRef
			if not identifier(target) or targets[prefix .. target] then
				return false, path .. ".options target must be stable and unique"
			end
			targets[prefix .. target] = true
			if hasContent and not childIds[target] then
				return false, path .. ".options contentId must reference a direct child"
			end
			if hasSurface then
				if not state.surfaceReferences[target] then
					return false, path .. ".options surfaceRef undeclared: " .. target
				end
				state.usedSurfaceReferences[target] = true
			end
		end
		for childId, _ in pairs(childIds) do
			if not targets["content:" .. childId] then
				return false, path .. " tab child has no option: " .. childId
			end
		end
	else
		for index = 1, #(node.options or {}) do
			if node.options[index].contentId ~= nil or node.options[index].surfaceRef ~= nil then
                                return false, path .. ".options navigation target requires container.navigation"
			end
		end
	end
	return true
end

local function validateNode(node, state, path, parentType)
	if type(node) ~= "table" or not identifier(node.id) then return false, path .. ".id required" end
	if state.ids[node.id] then return false, path .. ".id duplicate: " .. node.id end
	state.ids[node.id], state.usedTypes[node.type] = true, true
	local contract = componentTypes[node.type]
	if not contract then return false, path .. ".type unknown: " .. tostring(node.type) end
	if parentType and contract.parents and not contract.parents[parentType] then
		return false, path .. " parent type not allowed: " .. parentType
	end
	if not identifier(node.variant) then return false, path .. ".variant required" end
	if not portable(node, 0, {}) then return false, path .. " contains non-portable values" end
	if node.visual ~= nil then
		if type(node.visual) ~= "table" or not identifier(node.visual.visibleWhen) then
			return false, path .. ".visual.visibleWhen required"
		end
	end
	local ok, err = validateLayout(node.layout, state.profiles, state.references, path .. ".layout")
	if not ok then return false, err end
	if type(contract.validateNode) == "function" then
		ok, err = contract.validateNode(node)
		if not ok then return false, path .. "." .. tostring(err or "invalid component shape") end
	end
	ok, err = namedBindings(node.props or {}, path .. ".props", state.references)
	if not ok then return false, err end
	local eventSeen = {}
	for index = 1, #(node.actions or {}) do
		local action = node.actions[index]
		if type(action) ~= "table" or not actionEvents[action.event]
			or not identifier(action.actionId) then return false, path .. ".actions invalid" end
		if eventSeen[action.event] then return false, path .. ".actions event duplicate" end
		eventSeen[action.event] = true
		if not state.actions[action.actionId] or not state.actions[action.actionId][action.event] then
			return false, path .. " action not allowed: " .. action.actionId .. "/" .. action.event
		end
	end
	for index = 1, #(node.capabilities or {}) do
		local declaration = node.capabilities[index]
		local capability = declaration and capabilities[declaration.id]
		if not capability or capability.componentType ~= node.type then
			return false, path .. " capability unknown: " .. tostring(declaration and declaration.id)
		end
		if not state.declaredCapabilities[declaration.id] then
			return false, path .. " capability not declared by artifact: " .. declaration.id
		end
		state.usedCapabilities[declaration.id] = true
		ok, err = namedBindings(declaration.props or {}, path .. ".capabilities[" .. index .. "].props",
			state.references, capability.props)
		if not ok then return false, err end
	end
	ok, err = specialShape(node, path, state)
	if not ok then return false, err end
	local children = node.children or {}
	if type(children) ~= "table" then return false, path .. ".children must be array" end
	for index = 1, #children do
		ok, err = validateNode(children[index], state, path .. ".children[" .. index .. "]", node.type)
		if not ok then return false, err end
	end
	return true
end

local function indexReferences(spec)
	local profiles, err = arrayIndex(spec.profiles or {}, "profiles", "id")
	if not profiles then return nil, err end
	local tokens; tokens, err = arrayIndex(spec.tokens or {}, "tokens", "id")
	if not tokens then return nil, err end
	local i18n; i18n, err = arrayIndex(spec.i18n or {}, "i18n", "id")
	if not i18n then return nil, err end
	local assets; assets, err = arrayIndex(spec.assets or {}, "assets", "id")
	if not assets then return nil, err end
	local surfaces; surfaces, err = arrayIndex(spec.surfaceReferences, "surfaceReferences", "id")
	if not surfaces then return nil, err end
	for surfaceId, reference in pairs(surfaces) do
		if not repositoryId(reference.repository) or not relativePath(reference.specPath)
			or not sha256(reference.sha256) then
			return nil, "invalid surface reference: " .. surfaceId
		end
	end
	return { profiles = profiles, surfaceReferences = surfaces,
		references = { token = tokens, i18n = i18n, asset = assets } }
end

local function validateIdentity(spec)
	if type(spec) ~= "table" then return false, "surface artifact must be table" end
	if spec.documentKind ~= "sik-ui-runtime-surface" then
		return false, "documentKind must be sik-ui-runtime-surface"
	end
	if spec.schemaId ~= "sik-ui-runtime-v1" or tonumber(spec.schemaVersion) ~= 1 then
		return false, "unsupported runtime surface schema"
	end
	local ref = spec.frameworkRef
	if type(ref) ~= "table" or ref.id ~= "SiKUIFramework" or ref.namespace ~= "SiK.UI"
		or not identifier(ref.manifestVersion) or not sha256(ref.manifestSha256) then
		return false, "invalid frameworkRef"
	end
	local provenance = spec.provenance
	if type(provenance) ~= "table" or provenance.frameworkManifestSha256 ~= ref.manifestSha256 then
		return false, "framework provenance mismatch"
	end
	for _, key in ipairs({ "schemaSha256", "frameworkManifestSha256", "surfaceSpecSha256", "generatorSha256" }) do
		if not sha256(provenance[key]) then return false, "invalid provenance: " .. key end
	end
	return true
end

function Surface.validate(spec)
	local ok, err = validateIdentity(spec)
	if not ok then return false, err end
	local references; references, err = indexReferences(spec)
	if not references then return false, err end
	if type(spec.surface) ~= "table" or not identifier(spec.surface.id)
		or type(spec.surface.root) ~= "table" then return false, "surface root required" end
	local surfaceProfiles = {}
	for index = 1, #(spec.surface.profiles or {}) do
		local profileId = spec.surface.profiles[index]
		if not references.profiles[profileId] then return false, "surface profile undeclared: " .. tostring(profileId) end
		surfaceProfiles[profileId] = true
	end
	for profileId, _ in pairs(references.profiles) do
		if not surfaceProfiles[profileId] then return false, "unused runtime profile: " .. profileId end
	end
	local actions; actions, err = allowlistMap(spec)
	if not actions then return false, err end
	local declaredCapabilities; declaredCapabilities, err = arrayIndex(spec.capabilities or {}, "capabilities", "id")
	if not declaredCapabilities then return false, err end
	local state = { ids = {}, usedTypes = {}, usedCapabilities = {}, usedSurfaceReferences = {},
		profiles = references.profiles, references = references.references, actions = actions,
		declaredCapabilities = declaredCapabilities,
		surfaceReferences = references.surfaceReferences }
	ok, err = validateNode(spec.surface.root, state, "surface.root", nil)
	if not ok then return false, err end
	local factories; factories, err = arrayIndex(spec.componentFactories or {}, "componentFactories", "typeId")
	if not factories then return false, err end
	for typeId, _ in pairs(state.usedTypes) do
		local entry, contract = factories[typeId], componentTypes[typeId]
		if not entry then return false, "factory not declared: " .. typeId end
		if entry.runtimeFactory ~= contract.runtimeFactory then return false, "factory mismatch: " .. typeId end
	end
	for typeId, _ in pairs(factories) do
		if not state.usedTypes[typeId] then return false, "unused factory declared: " .. typeId end
	end
	for capabilityId, _ in pairs(state.usedCapabilities) do
		if not declaredCapabilities[capabilityId] then return false, "capability not declared: " .. capabilityId end
	end
	for capabilityId, _ in pairs(declaredCapabilities) do
		if not state.usedCapabilities[capabilityId] then return false, "unused capability declared: " .. capabilityId end
	end
	for surfaceId, _ in pairs(references.surfaceReferences) do
		if not state.usedSurfaceReferences[surfaceId] then
			return false, "unused surface reference: " .. surfaceId
		end
	end
	return true
end

function Surface.validateReferenceArtifact(reference, artifact)
	if type(reference) ~= "table" or not identifier(reference.id)
		or not repositoryId(reference.repository) or not relativePath(reference.specPath)
		or not sha256(reference.sha256) then return false, "invalid surface reference" end
	if type(artifact) ~= "table" or type(artifact.surface) ~= "table"
		or artifact.surface.id ~= reference.id then return false, "surface reference id mismatch" end
	if type(artifact.provenance) ~= "table"
		or artifact.provenance.surfaceSpecSha256 ~= reference.sha256 then
		return false, "surface reference hash mismatch"
	end
	return Surface.validate(artifact)
end

function Surface.assertValid(spec)
	local ok, err = Surface.validate(spec)
	if not ok then error(err, 2) end
	return spec
end

function Surface.actionAllowlist(spec)
	return allowlistMap(spec)
end

return Surface
