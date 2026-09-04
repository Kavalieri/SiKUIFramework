require "SiK/UI/Namespace"
require "SiK/UI/Controls"
require "SiK/UI/Metrics"
require "SiK/UI/Layout"
require "ISUI/ISPanel"

local Form = SiK.UI.Form or {}
SiK.UI.Namespace.define("Form", Form)

local function controlValue(entry)
	local control, descriptor = entry.control, entry.descriptor
	if descriptor.type == "toggle" then return control:isSelected() end
	if descriptor.type == "combo" then
		local selected = control.selected
		local item = selected and control.options and control.options[selected] or nil
		return item and (item.data ~= nil and item.data or item.text) or nil
	end
	if control.getText then return control:getText() end
	return control.value
end

local function setControlValue(entry, value)
	local control, descriptor = entry.control, entry.descriptor
	if descriptor.type == "toggle" then control:setSelected(value == true, false); return end
	if descriptor.type == "combo" then
		for index = 1, #(control.options or {}) do
			local item = control.options[index]
			if item.data == value or item.text == value then control.selected = index; return end
		end
		return
	end
	if control.setText then control:setText(tostring(value or "")) else control.value = value end
end

function Form.create(options)
	options = options or {}
	if type(options.parent) ~= "table" then return nil, "invalid_parent" end
	local panel = ISPanel:new(options.x or 0, options.y or 0,
		options.w or options.width or 1, options.h or options.height or 1)
	panel:initialise(); panel.drawBackground = false; options.parent:addChild(panel)
	local instance = { panel = panel, parent = options.parent, options = options,
		entries = {}, byKey = {}, errors = {},
		playerNum = math.max(0, math.floor(tonumber(options.playerNum) or 0)) }
	instance.childParent = panel
	local metrics = SiK.UI.Controls.metrics(options.profile)
	local function cleanupPartial()
		for index = 1, #instance.entries do
			local entry = instance.entries[index]
			if entry.label and entry.label.dispose then entry.label:dispose() end
			if entry.control and entry.control.dispose then entry.control:dispose() end
		end
		if instance.parent and instance.parent.removeChild then
			instance.parent:removeChild(instance.panel)
		end
	end

	local function changed(entry, context)
		if type(entry.descriptor.onChange) == "function" then
			entry.descriptor.onChange(context)
		end
		if type(options.onChange) == "function" then
			options.onChange(SiK.UI.Namespace.context(instance, options, "change", {
				key = entry.descriptor.key, value = controlValue(entry),
			}))
		end
	end

	for index = 1, #(options.fields or {}) do
		local descriptor = options.fields[index]
		if type(descriptor.key) ~= "string" or descriptor.key == "" then
			cleanupPartial(); return nil, "invalid_field_key"
		end
		if instance.byKey[descriptor.key] then cleanupPartial(); return nil, "duplicate_field_key" end
		local entry = { descriptor = descriptor }
		entry.label = SiK.UI.Controls.status({ parent = panel, text = descriptor.label or "",
			tone = "text", playerNum = instance.playerNum })
		local controlOptions = {
			parent = panel, text = descriptor.default, items = descriptor.items,
			selected = descriptor.selected ~= nil and descriptor.selected or descriptor.default,
			placeholder = descriptor.placeholder, tooltip = descriptor.tooltip,
			playerNum = instance.playerNum, payload = descriptor.payload,
			onChange = function(context) changed(entry, context) end,
		}
		local kind = descriptor.type or "field"
		entry.control = SiK.UI.Controls.create(kind, controlOptions)
		if not entry.control then cleanupPartial(); return nil, "unsupported_field_type" end
		if descriptor.default ~= nil then setControlValue(entry, descriptor.default) end
		instance.entries[#instance.entries + 1] = entry
		instance.byKey[descriptor.key] = entry
	end

	if options.submit then
		local submitOptions = {}
		for key, value in pairs(options.submit) do submitOptions[key] = value end
		submitOptions.parent = panel; submitOptions.playerNum = instance.playerNum
		submitOptions.onClick = function() instance:submit() end
		instance.submitControl = SiK.UI.Controls.button(submitOptions)
	end

	function instance:getValue(key)
		local entry = self.byKey[key]
		return entry and controlValue(entry) or nil
	end
	function instance:setValue(key, value)
		local entry = self.byKey[key]
		if not entry then return nil, "unknown_field" end
		setControlValue(entry, value); return self
	end
	function instance:getValues()
		local values = {}
		for index = 1, #self.entries do
			local entry = self.entries[index]
			values[entry.descriptor.key] = controlValue(entry)
		end
		return values
	end
	function instance:validate()
		self.errors = {}
		for index = 1, #self.entries do
			local entry = self.entries[index]
			if type(entry.descriptor.validate) == "function" then
				local ok, errorCode = entry.descriptor.validate(controlValue(entry),
					self:getValues(), entry.descriptor)
				if ok == false then self.errors[entry.descriptor.key] = errorCode or "invalid" end
			end
		end
		local count = 0
		for _, _ in pairs(self.errors) do count = count + 1 end
		return count == 0, self.errors
	end
	function instance:submit()
		local valid, errors = self:validate()
		if not valid then
			if type(options.onInvalid) == "function" then options.onInvalid(errors, self) end
			return false, errors
		end
		if type(options.onSubmit) == "function" then
			return options.onSubmit(SiK.UI.Namespace.context(self, options, "submit",
				self:getValues()))
		end
		return true
	end
	function instance:reflow(bounds)
		if self.disposed then return nil, "disposed" end
		bounds = bounds or { x = self.panel.x, y = self.panel.y,
			w = self.panel.width, h = self.panel.height }
		self.panel:setX(bounds.x or 0); self.panel:setY(bounds.y or 0)
		self.panel:setWidth(bounds.w or bounds.width or self.panel.width)
		self.panel:setHeight(bounds.h or bounds.height or self.panel.height)
		local y, labelHeight = 0, metrics.fontHeight
		for index = 1, #self.entries do
			local entry = self.entries[index]
			entry.label:setX(0); entry.label:setY(y); entry.label:setWidth(self.panel.width)
			y = y + labelHeight + 4
			SiK.UI.Layout.apply(entry.control, SiK.UI.Layout.resolveRect({
				x = 0, y = y, w = self.panel.width, h = metrics.inputHeight,
			}, nil, 1))
			y = y + metrics.inputHeight + metrics.rowGap
		end
		if self.submitControl then
			self.submitControl:setX(0); self.submitControl:setY(y)
			self.submitControl:setWidth(self.panel.width); y = y + metrics.buttonHeight
		end
		self.contentHeight = y
		return self
	end
	function instance:dispose()
		if self.disposed then return false end
		self.disposed = true
		for index = 1, #self.entries do
			self.entries[index].label:dispose(); self.entries[index].control:dispose()
		end
		if self.submitControl then self.submitControl:dispose() end
		if self.parent and self.parent.removeChild then self.parent:removeChild(self.panel) end
		self.entries, self.byKey, self.parent, self.childParent, self.panel = {}, {}, nil, nil, nil
		return true
	end
	instance:reflow(options.bounds)
	return instance
end

return Form
