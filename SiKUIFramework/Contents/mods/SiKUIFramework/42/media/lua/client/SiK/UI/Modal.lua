require "SiK/UI/Namespace"
require "SiK/UI/Window"
require "SiK/UI/Block"
require "SiK/UI/Scroll"
require "SiK/UI/Controls"

local Modal = SiK.UI.Modal or {}
SiK.UI.Namespace.define("Modal", Modal)

Modal.STANDARD_MODAL_W = 460
local stacks = {}
local ownerBindings = setmetatable({}, { __mode = "k" })
local unbindOwner

local function playerKey(playerNum)
	return tostring(math.max(0, math.floor(tonumber(playerNum) or 0)))
end

local function stackFor(playerNum, create)
	local key = playerKey(playerNum)
	local stack = stacks[key]
	if not stack and create then stack = {}; stacks[key] = stack end
	return stack
end

local function removeFromStack(panel)
	local stack = stackFor(panel.playerNum, false)
	if stack then
		for index = #stack, 1, -1 do
			if stack[index] == panel then table.remove(stack, index) end
		end
	end
	if unbindOwner then unbindOwner(panel) end
end

function Modal.top(playerNum)
	local stack = stackFor(playerNum, false)
	return stack and stack[#stack] or nil
end

local function modalVisible(panel)
	if not panel or panel._sikDisposed or panel._sikModalDisposed then return false end
	if panel.getIsVisible then return panel:getIsVisible() ~= false end
	return panel.visible ~= false
end

function Modal.topForOwner(owner)
	local binding = owner and ownerBindings[owner] or nil
	if not binding then return nil end
	for index = #binding.children, 1, -1 do
		local child = binding.children[index]
		if modalVisible(child) then return child end
	end
	return nil
end

function Modal.raiseOwned(owner)
	local binding = owner and ownerBindings[owner] or nil
	if not binding then return false end
	local snapshot = {}
	for index = 1, #binding.children do snapshot[index] = binding.children[index] end
	local raised = false
	for index = 1, #snapshot do
		local child = snapshot[index]
		if modalVisible(child) and child.bringToTop then
			child:bringToTop()
			raised = true
		end
	end
	return raised
end

local function bindOwner(panel, owner)
	if type(panel) ~= "table" or type(owner) ~= "table" or panel == owner then return false end
	local binding = ownerBindings[owner]
	if not binding then
		binding = { owner = owner, original = owner.bringToTop, children = {} }
		binding.wrapper = function(self, ...)
			local result = nil
			if type(binding.original) == "function" then result = binding.original(self, ...) end
			Modal.raiseOwned(self)
			return result
		end
		ownerBindings[owner] = binding
		if type(binding.original) == "function" then owner.bringToTop = binding.wrapper end
	end
	for index = 1, #binding.children do
		if binding.children[index] == panel then return true end
	end
	binding.children[#binding.children + 1] = panel
	panel._sikModalOwner = owner
	return true
end

unbindOwner = function(panel)
	local owner = panel and panel._sikModalOwner or nil
	local binding = owner and ownerBindings[owner] or nil
	if not binding then return false end
	for index = #binding.children, 1, -1 do
		if binding.children[index] == panel then table.remove(binding.children, index) end
	end
	if #binding.children == 0 then
		if owner.bringToTop == binding.wrapper then owner.bringToTop = binding.original end
		ownerBindings[owner] = nil
	end
	return true
end

function Modal.setOwner(panel, owner)
	if not panel then return false end
	unbindOwner(panel)
	panel._sikModalOwner = owner
	return owner == nil or bindOwner(panel, owner)
end

function Modal.raiseOwner(owner)
	if not owner then return false end
	local binding = ownerBindings[owner]
	if binding and owner.bringToTop == binding.wrapper then
		owner:bringToTop()
		return true
	end
	local raised = false
	if owner.bringToTop then owner:bringToTop(); raised = true end
	return Modal.raiseOwned(owner) or raised
end

local function modalProfile(kind)
	if kind == "task" then return "task" end
	return "compact"
end

function Modal.resolve(kind, contentSize, options)
	options = options or {}; contentSize = contentSize or {}
	local resolved = {}
	for key, value in pairs(options) do resolved[key] = value end
	resolved.kind = kind or resolved.kind or "compact"
	resolved.profile = resolved.profile or modalProfile(resolved.kind)
	if contentSize.w ~= nil and resolved.width == nil and resolved.w == nil then
		resolved.width = tonumber(contentSize.w)
	end
	if contentSize.h ~= nil and resolved.height == nil and resolved.h == nil then
		resolved.height = tonumber(contentSize.h)
	end
	local bounds = SiK.UI.Window.resolveBounds(resolved)
	bounds.kind = resolved.kind
	bounds.overflow = tonumber(contentSize.h) ~= nil
		and tonumber(contentSize.h) > bounds.h or false
	return bounds
end

local function buildContentHost(panel, options)
	local rect = panel:contentRect()
	local contentHeight = math.max(0, tonumber(options.contentHeight) or rect.h)
	local block, err = SiK.UI.Block.create({ parent = panel, x = rect.x, y = rect.y,
		w = rect.w, h = rect.h, contentHeight = contentHeight })
	if not block then return nil, err end
	local scroll = SiK.UI.Scroll.create({ parent = block.panel,
		viewportRect = block:getContentRect(), trackRect = block:getTrackRect(),
		contentHeight = contentHeight, playerNum = panel.playerNum })
	if not scroll then block:dispose(); return nil, "scroll_unavailable" end
	block:attachScroll(scroll, true)
	panel.contentBlock, panel.contentScroll = block, scroll
	panel.contentHost = scroll.host
	local contentRect = block:getContentRect()
	return scroll.host, { x = 0, y = 0, w = contentRect.w, h = contentRect.h }
end

function Modal.apply(panel, options)
	options = options or {}
	options.profile = options.profile or modalProfile(options.kind)
	if options.resizable == nil then options.resizable = false end
	options.focusPriority = tonumber(options.focusPriority) or 80
	local applied, err = SiK.UI.Window.apply(panel, options)
	if not applied then return nil, err end
	applied._sikModal = true
	applied._sikModalKind = options.kind or "compact"
	applied._sikModalOwner = options.owner
	if not applied._sikModalDisposeWrapped then
		applied._sikModalDisposeWrapped = true
		local originalDispose = applied.dispose
		applied.dispose = function(self)
			if self._sikModalDisposed then return false end
			self._sikModalDisposed = true
			removeFromStack(self)
			return originalDispose(self)
		end
	end
	return applied
end

function Modal.create(options)
	options = options or {}
	local kind = options.kind or "compact"
	local windowOptions = {}
	for key, value in pairs(options) do windowOptions[key] = value end
	windowOptions.profile = windowOptions.profile or modalProfile(kind)
	windowOptions.width = windowOptions.width or windowOptions.w
		or (kind == "task" and 640 or Modal.STANDARD_MODAL_W)
	windowOptions.resizable = windowOptions.resizable == true
	local panel = SiK.UI.Window.create(windowOptions)
	panel._sikModal = true
	panel._sikModalKind = kind
	panel._sikModalOwner = options.owner
	local host, contentRect = buildContentHost(panel, options)
	if not host then panel:dispose(); return nil, contentRect end
	panel.childParent = panel.contentHost
	if type(options.buildContent) == "function" then
		options.buildContent(host, {
			x = contentRect.x, y = contentRect.y, w = contentRect.w, h = contentRect.h,
		}, panel)
	end
	local originalReflow = panel.reflow
	panel.reflow = function(self)
		originalReflow(self)
		local rect = self:contentRect()
		self.contentBlock:setBounds(rect.x, rect.y, rect.w, rect.h)
		return self
	end
	local originalDispose = panel.dispose
	panel.dispose = function(self)
		if self._sikModalDisposed then return false end
		self._sikModalDisposed = true
		removeFromStack(self)
		if self.contentBlock then self.contentBlock:dispose(); self.contentBlock = nil end
		self.contentScroll, self.contentHost, self.childParent = nil, nil, nil
		return originalDispose(self)
	end
	return panel
end

function Modal.show(panel, focusControl)
	if not panel or panel._sikDisposed then return nil, "invalid_modal" end
	removeFromStack(panel)
	local stack = stackFor(panel.playerNum, true)
	stack[#stack + 1] = panel
	if panel._sikModalOwner then bindOwner(panel, panel._sikModalOwner) end
	panel:show()
	if focusControl then
		if focusControl.focus then focusControl:focus()
		elseif focusControl.javaObject and focusControl.javaObject.focus then
			focusControl.javaObject:focus()
		end
	end
	return panel
end

function Modal.close(panel, reason)
	if not panel then return false end
	local owner = panel._sikModalOwner
	local closed = panel:close(reason or "modal")
	if closed then removeFromStack(panel) end
	if owner then
		Modal.raiseOwner(owner)
	else
		local top = Modal.top(panel.playerNum)
		if top and top.bringToTop then top:bringToTop() end
	end
	return closed
end

function Modal.fitContent(panel, contentHeight, options)
	if not panel or panel._sikDisposed then return nil, "invalid_modal" end
	options = options or {}
	contentHeight = math.max(0, tonumber(contentHeight) or 0)
	if panel.contentBlock and panel.contentBlock.setContentHeight then
		panel.contentBlock:setContentHeight(contentHeight)
	end
	local desired
	if options.contentBottom == true then
		desired = contentHeight + math.max(0, tonumber(options.bottomPadding) or 0)
	else
		desired = (panel.headerHeight or 0) + (panel.footerHeight or 0)
			+ (panel.windowPadding or 0) * 2 + contentHeight
	end
	if options.center == true then
		local bounds = SiK.UI.Window.resolveBounds({
			playerNum = panel.playerNum,
			profile = panel._sikWindowOptions and panel._sikWindowOptions.profile,
			width = panel.width, height = desired,
			environment = options.environment,
		})
		panel:setX(bounds.x); panel:setY(bounds.y)
		panel:setSize(bounds.w, bounds.h)
	else
		SiK.UI.Window.updateConstraints(panel, {
			width = panel.width, height = desired,
			environment = options.environment,
		})
	end
	panel:reflow()
	return panel
end

local function translated(key, fallback)
	return SiK.UI.resolveText(key, fallback)
end

function Modal.confirm(options)
	options = options or {}
	local metrics = SiK.UI.Controls.metrics("compact")
	local messageWidth = math.max(1, (options.width or Modal.STANDARD_MODAL_W) - 44)
	local messageLines = SiK.UI.Controls.wrapText(options.message, messageWidth, UIFont.Small)
	local messageHeight = #messageLines * (metrics.fontHeight + 3) + 16
	local contentHeight = messageHeight + metrics.rowGap + metrics.buttonHeight
	local panel
	panel = Modal.create({
		kind = "confirm", title = options.title, playerNum = options.playerNum,
		width = options.width or Modal.STANDARD_MODAL_W,
		height = options.height or (contentHeight + metrics.rowGap * 2 + 52),
		contentHeight = options.contentHeight or contentHeight,
		resizable = false, closeOnEscape = true, onClose = options.onClose,
		buildContent = function(host, rect)
			local message = SiK.UI.Controls.feedback(host, { x = rect.x, y = rect.y,
				w = rect.w, text = options.message or "",
				tone = options.tone or "info", playerNum = options.playerNum })
			local y = message.y + message.height + metrics.rowGap
			local width = math.floor((rect.w - metrics.controlGap) / 2)
			SiK.UI.Controls.button(host, { x = rect.x, y = y, w = width,
				text = options.cancelText or translated("UI_Cancel", "Cancel"), fullWidth = true,
				playerNum = options.playerNum, onClick = function()
					Modal.close(panel, "cancel")
					if options.onCancel then options.onCancel() end
				end })
			SiK.UI.Controls.button(host, { x = rect.x + width + metrics.controlGap,
				y = y, w = width, text = options.acceptText or translated("UI_Ok", "OK"),
				fullWidth = true, playerNum = options.playerNum, onClick = function()
					if options.onAccept then options.onAccept() end
					Modal.close(panel, "accept")
				end })
		end,
	})
	Modal.show(panel)
	return panel
end

function Modal.input(options)
	options = options or {}
	local metrics = SiK.UI.Controls.metrics("compact")
	local field, panel
	local function onWindowClose(context)
		local reason = context and context.value or nil
		if reason ~= "accept" and options.onCancel then
			options.onCancel(context)
		end
		if options.onClose then return options.onClose(context) end
	end
	panel = Modal.create({
		kind = "input", title = options.title, playerNum = options.playerNum,
		width = options.width or Modal.STANDARD_MODAL_W,
		height = options.height or 190, contentHeight = options.contentHeight or 100,
		resizable = false, closeOnEscape = true, onClose = onWindowClose,
		buildContent = function(host, rect)
			field = SiK.UI.Controls.field(host, { x = rect.x, y = rect.y, w = rect.w,
				text = options.text, placeholder = options.placeholder,
				numeric = options.numeric, maxLength = options.maxLength,
				playerNum = options.playerNum, onChange = options.onChange })
			local buttonY = rect.y + metrics.inputHeight + metrics.rowGap
			local buttonW = math.floor((rect.w - metrics.controlGap) / 2)
			SiK.UI.Controls.button(host, { x = rect.x, y = buttonY, w = buttonW,
				text = options.cancelText or translated("UI_Cancel", "Cancel"),
				fullWidth = true, playerNum = options.playerNum,
				onClick = function() Modal.close(panel, "cancel") end })
			SiK.UI.Controls.button(host, { x = rect.x + buttonW + metrics.controlGap,
				y = buttonY, w = buttonW,
				text = options.acceptText or translated("UI_Ok", "OK"), fullWidth = true,
				playerNum = options.playerNum, onClick = function()
					local value = field:getText()
					if options.validate then
						local valid, replacement = options.validate(value, panel)
						if valid == false then
							if options.onInvalid then
								options.onInvalid(replacement, value, panel)
							end
							return
						end
						if replacement ~= nil then value = replacement end
					end
					local result = options.onAccept and options.onAccept(value, panel)
					if result ~= false then Modal.close(panel, "accept") end
				end })
		end,
	})
	Modal.show(panel, field)
	return panel, field
end

function Modal.compact(options)
	options = options or {}; options.kind = "compact"
	return Modal.create(options)
end

function Modal.task(options)
	options = options or {}; options.kind = "task"
	return Modal.create(options)
end

return Modal
