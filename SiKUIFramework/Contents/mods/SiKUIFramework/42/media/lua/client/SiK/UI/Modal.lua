require "SiK/UI/Namespace"
require "SiK/UI/Window"
require "SiK/UI/Block"
require "SiK/UI/Scroll"
require "SiK/UI/ScrollDock"
require "SiK/UI/Controls"

local Modal = SiK.UI.Modal or {}
SiK.UI.Namespace.define("Modal", Modal)

Modal.WIDTH_MIN, Modal.WIDTH_STANDARD, Modal.WIDTH_MAX = 560, 720, 900
Modal.STANDARD_MODAL_W = Modal.WIDTH_STANDARD
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

local function removeFromStack(panel, preserveOwner)
	local stack = stackFor(panel.playerNum, false)
	if stack then
		for index = #stack, 1, -1 do
			if stack[index] == panel then table.remove(stack, index) end
		end
	end
	if not preserveOwner and unbindOwner then unbindOwner(panel) end
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

local function createOwnerBlocker(owner)
	if not owner or not owner.addChild or not ISPanel then return nil end
	local blocker = ISPanel:new(0, 0, math.max(1, owner.width or 1),
		math.max(1, owner.height or 1))
	blocker:initialise()
	if blocker.instantiate then blocker:instantiate() end
	blocker.background = false
	blocker.border = false
	blocker.moveWithMouse = false
	blocker.onMouseDown = function() return true end
	blocker.onMouseUp = function() return true end
	blocker.onMouseUpOutside = function() return true end
	blocker.onMouseMove = function() return true end
	blocker.onMouseMoveOutside = function() return true end
	blocker.onRightMouseDown = function() return true end
	blocker.onRightMouseUp = function() return true end
	blocker.onMouseWheel = function() return true end
	local previousPrerender = blocker.prerender
	blocker.prerender = function(self)
		if self.setWidth then self:setWidth(math.max(1, owner.width or 1)) end
		if self.setHeight then self:setHeight(math.max(1, owner.height or 1)) end
		if previousPrerender then previousPrerender(self) end
	end
	owner:addChild(blocker)
	if blocker.bringToTop then blocker:bringToTop() end
	return blocker
end

local function disposeOwnerBlocker(binding)
	local blocker = binding and binding.blocker or nil
	if not blocker then return end
	if blocker.setCapture then blocker:setCapture(false) end
	if blocker.parent and blocker.parent.removeChild then blocker.parent:removeChild(blocker) end
	if blocker.setVisible then blocker:setVisible(false) end
	binding.blocker = nil
end

local function bindOwner(panel, owner)
	if type(panel) ~= "table" or type(owner) ~= "table" or panel == owner then return false end
	local binding = ownerBindings[owner]
	if not binding then
		binding = {
			owner = owner,
			children = {},
			wasAlwaysOnTop = owner.isAlwaysOnTop and owner:isAlwaysOnTop() or false,
			ownerBringToTop = owner.bringToTop,
		}
		ownerBindings[owner] = binding
		-- Only the visible descendant keeps native always-on-top priority.  The
		-- owner remains mounted, but this blocker absorbs every pointer path until
		-- the last child closes.
		if owner.setAlwaysOnTop then owner:setAlwaysOnTop(false) end
		binding.blocker = createOwnerBlocker(owner)
		-- Any native/UI activation of the owner must finish by restoring the
		-- complete owner -> blocker -> child order.  Scope the wrapper to the
		-- lifetime of the binding and restore the exact method afterwards.
		if binding.ownerBringToTop then
			owner.bringToTop = function(self, ...)
				local current = ownerBindings[self]
				local original = current and current.ownerBringToTop or binding.ownerBringToTop
				if original then original(self, ...) end
				if current and current.blocker and current.blocker.bringToTop then
					current.blocker:bringToTop()
				end
				Modal.raiseOwned(self)
			end
		end
	end
	for index = 1, #binding.children do
		if binding.children[index] == panel then return true end
	end
	binding.children[#binding.children + 1] = panel
	panel._sikModalOwner = owner
	if binding.blocker and binding.blocker.bringToTop then binding.blocker:bringToTop() end
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
		disposeOwnerBlocker(binding)
		if owner.setAlwaysOnTop then owner:setAlwaysOnTop(binding.wasAlwaysOnTop == true) end
		if binding.ownerBringToTop then owner.bringToTop = binding.ownerBringToTop end
		ownerBindings[owner] = nil
	end
	panel._sikModalOwner = nil
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
	if binding then
		if owner.bringToTop then owner:bringToTop(); return true end
		if binding.blocker and binding.blocker.bringToTop then binding.blocker:bringToTop() end
		return Modal.raiseOwned(owner)
	end
	local raised = false
	if owner.bringToTop then owner:bringToTop(); raised = true end
	return Modal.raiseOwned(owner) or raised
end

local function restoreOwnerFocus(owner)
	if not owner then return false end
	Modal.raiseOwner(owner)
	if owner.focus then owner:focus()
	elseif owner.javaObject and owner.javaObject.focus then owner.javaObject:focus() end
	return true
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
	-- A dock owns scroll/fixed-action composition but not a second inset or
	-- frame. Window.contentRect() has already applied Window.contentPadding.
	if options.contentMode == "dock" then
		local host = SiK.UI.Controls.panel(panel, { x = rect.x, y = rect.y,
			w = rect.w, h = rect.h, controlId = "modalDockHost" })
		if not host then return nil, "dock_host_unavailable" end
		panel.contentBlock, panel.contentScroll, panel.contentHost = nil, nil, host
		panel._sikModalContentMode = "dock"
		return host, { x = 0, y = 0, w = rect.w, h = rect.h }
	end
	local contentHeight = math.max(0, tonumber(options.contentHeight) or rect.h)
	local block, err = SiK.UI.Block.create({ parent = panel, x = rect.x, y = rect.y,
		w = rect.w, h = rect.h, contentHeight = contentHeight })
	if not block then return nil, err end
	if options.scroll == false then
		panel.contentBlock, panel.contentScroll = block, nil
		panel.contentHost = block.panel
		local contentRect = block:getContentRect()
		return block.panel, contentRect
	end
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
	local host, contentRect = buildContentHost(applied, options)
	if not host then
		applied:dispose()
		return nil, contentRect
	end
	applied.childParent = applied.contentHost
	local originalReflow = applied.reflow
	applied.reflow = function(self)
		originalReflow(self)
		local rect = self:contentRect()
		if self._sikModalContentMode == "dock" then
			SiK.UI.Layout.apply(self.contentHost, { x = rect.x, y = rect.y, w = rect.w, h = rect.h })
		elseif self.contentBlock then
			self.contentBlock:setBounds(rect.x, rect.y, rect.w, rect.h)
		end
		return self
	end
	if not applied._sikModalDisposeWrapped then
		applied._sikModalDisposeWrapped = true
		local originalDispose = applied.dispose
		applied.dispose = function(self)
			if self._sikModalDisposed then return false end
			self._sikModalDisposed = true
			local owner = self._sikModalOwner
			removeFromStack(self)
			if self.contentBlock then self.contentBlock:dispose(); self.contentBlock = nil end
			self.contentScroll, self.contentHost, self.childParent = nil, nil, nil
			local result = originalDispose(self)
			restoreOwnerFocus(owner)
			return result
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
		or (kind == "task" and Modal.WIDTH_STANDARD or Modal.STANDARD_MODAL_W)
	windowOptions.minWidth = windowOptions.minWidth or Modal.WIDTH_MIN
	windowOptions.maxWidth = windowOptions.maxWidth or Modal.WIDTH_MAX
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
		if self._sikModalContentMode == "dock" then
			SiK.UI.Layout.apply(self.contentHost, { x = rect.x, y = rect.y, w = rect.w, h = rect.h })
		elseif self.contentBlock and self.contentBlock.setBounds then
			self.contentBlock:setBounds(rect.x, rect.y, rect.w, rect.h)
		end
		return self
	end
	local originalDispose = panel.dispose
	panel.dispose = function(self)
		if self._sikModalDisposed then return false end
		self._sikModalDisposed = true
		local owner = self._sikModalOwner
		removeFromStack(self)
		if self.contentBlock then self.contentBlock:dispose(); self.contentBlock = nil end
		self.contentScroll, self.contentHost, self.childParent = nil, nil, nil
		local result = originalDispose(self)
		restoreOwnerFocus(owner)
		return result
	end
	return panel
end

function Modal.show(panel, focusControl)
	if not panel or panel._sikDisposed then return nil, "invalid_modal" end
	-- A modal opened by another modal inherits the visible top layer when the
	-- consumer did not provide an explicit owner. Product windows that are not
	-- themselves modals still pass `owner`/`setOwner` explicitly. This makes the
	-- safe stacking rule the default and prevents a newly opened descendant from
	-- being hidden when its parent is raised again.
	if not panel._sikModalOwner then
		local inheritedOwner = Modal.top(panel.playerNum)
		if inheritedOwner and inheritedOwner ~= panel then
			Modal.setOwner(panel, inheritedOwner)
		end
	end
	removeFromStack(panel, true)
	local stack = stackFor(panel.playerNum, true)
	stack[#stack + 1] = panel
	if panel._sikModalOwner then bindOwner(panel, panel._sikModalOwner) end
	if panel.setAlwaysOnTop then panel:setAlwaysOnTop(true) end
	panel:show()
	if focusControl then
		if focusControl.focus then focusControl:focus()
		elseif focusControl.javaObject and focusControl.javaObject.focus then
			focusControl.javaObject:focus()
		end
	end
	return panel
end

--- Presents a descendant as one atomic ownership operation.  Product code
--- must not coordinate native always-on-top flags independently.
function Modal.presentChild(owner, child, focusControl)
	if not owner or not child or owner == child then return nil, "invalid_modal_owner" end
	local childPlayer = math.max(0, math.floor(tonumber(child.playerNum) or 0))
	local ownerPlayer = math.max(0, math.floor(tonumber(owner.playerNum) or 0))
	if childPlayer ~= ownerPlayer then return nil, "modal_owner_player_mismatch" end
	if not Modal.setOwner(child, owner) then return nil, "modal_owner_rejected" end
	return Modal.show(child, focusControl)
end

function Modal.close(panel, reason)
	if not panel then return false end
	local owner = panel._sikModalOwner
	local closed = panel:close(reason or "modal")
	if closed then removeFromStack(panel) end
	if owner then
		restoreOwnerFocus(owner)
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

-- Both simple dialog types use the same bounded composition as editors:
-- intrinsic content above an intrinsic action block, with overflow confined
-- to the content. The Window is the only owner of its outer 12px inset.
local function dialogueDock(panel, host, rect)
	local dock = SiK.UI.ScrollDock.create({ parent = host, x = 0, y = 0,
		w = rect.w, h = rect.h, padding = 0, playerNum = panel.playerNum })
	panel.dialogueDock = dock
	return dock
end

local function finishDialogue(panel)
	local baseReflow, baseDispose = panel.reflow, panel.dispose
	panel.reflow = function(self)
		baseReflow(self)
		if self._sikDialogueReflow or not self.dialogueDock then return self end
		self._sikDialogueReflow = true
		local rect = self:contentRect()
		local dock = self.dialogueDock
		dock:reflow(0, 0, rect.w, rect.h)
		-- Re-measure after overflow changes the usable width. Only the dock
		-- reserves its scrollbar; neither the Block nor its controls do so.
		for pass = 1, 3 do
			local width = SiK.UI.Scroll.contentWidth(dock.scroll)
			local bodyHeight, actionsHeight = self._sikDialogueLayout(width, rect.w)
			dock:setFixedBottomHeight(actionsHeight)
			dock:setContentHeight(bodyHeight)
			self._sikDialogueHeight = bodyHeight + dock.gap + actionsHeight
			if width == SiK.UI.Scroll.contentWidth(dock.scroll) then break end
		end
		self._sikDialogueReflow = nil
		return self
	end
	panel.dispose = function(self)
		if self.dialogueDock then
			local body = self.questionBlock or self.inputBlock
			if body then body:dispose() end
			if self.actionsBlock then self.actionsBlock:dispose() end
			self.dialogueDock:dispose()
			self.dialogueDock, self.questionBlock, self.inputBlock, self.actionsBlock = nil, nil, nil, nil
			self._sikDialogueLayout, self.inputField = nil, nil
		end
		return baseDispose(self)
	end
	panel:reflow()
	Modal.fitContent(panel, panel._sikDialogueHeight, { center = true })
	return panel
end

function Modal.confirm(options)
	options = options or {}
	local metrics = SiK.UI.Controls.metrics("compact")
	local width = options.width or Modal.STANDARD_MODAL_W
	local messageWidth = math.max(1, width - 24)
	local question = tostring(options.question or options.message or "")
	local consequences = tostring(options.consequences or "")
	local questionLines = SiK.UI.Controls.wrapText(question, messageWidth - 32, UIFont.Small)
	local consequenceLines = consequences == "" and 0
		or #SiK.UI.Controls.wrapText(consequences, messageWidth, UIFont.Small)
	local questionHeight = math.max(24, #questionLines * (metrics.fontHeight + 3))
		+ consequenceLines * (metrics.fontHeight + 3) + 16
	if options.questionTitle or options.questionTooltip or options.questionInfo then
		questionHeight = questionHeight + metrics.rowHeight + metrics.rowGap
	end
	local actionsHeight = metrics.buttonHeight + 16
	if options.actionsTitle or options.actionsTooltip or options.actionsInfo then
		actionsHeight = actionsHeight + metrics.rowHeight + metrics.rowGap
	end
	local contentHeight = questionHeight + metrics.rowGap + actionsHeight
	local panel, rejectButton
	local resolved = false
	local function reject(reason)
		if resolved then return end
		resolved = true
		if options.onReject then options.onReject(reason, panel) end
		if options.onCancel then options.onCancel(reason, panel) end
	end
	local function accept()
		if resolved then return end
		resolved = true
		if options.onAccept then options.onAccept(panel) end
	end
	panel = Modal.create({
		kind = "confirm", title = options.title, playerNum = options.playerNum,
		owner = options.owner,
		width = width,
		height = options.height or (contentHeight + metrics.rowGap * 2 + 52),
		contentHeight = options.contentHeight or contentHeight,
		contentMode = "dock", resizable = false, closeOnEscape = true,
		onClose = function(context)
			local reason = context and context.value or "close"
			if reason ~= "accept" then reject(reason) end
			if options.onClose then return options.onClose(context) end
		end,
		buildContent = function(host, rect, modalPanel)
			local dock = dialogueDock(modalPanel, host, rect)
			-- A confirmation consists of two framed semantic groups.  The alert is
			-- the question marker itself; no second informational glyph is added.
			local questionBlock = SiK.UI.Block.create({ parent = dock.contentHost, x = 0, y = 0,
				w = rect.w, h = questionHeight, title = options.questionTitle,
				tooltip = options.questionTooltip, info = options.questionInfo,
				playerNum = options.playerNum })
			modalPanel.questionBlock = questionBlock
			local questionRect = questionBlock:getContentRect()
			local y, header, copy
			if type(options.alert) == "table" and (options.alert.icon or options.alert.texture) then
				header = SiK.UI.Controls.alertRow(questionBlock.childParent, { x = questionRect.x,
					y = questionRect.y, w = questionRect.w, icon = options.alert.icon or options.alert.texture,
					severity = options.alert.severity, glow = options.alert.glow,
					text = question, playerNum = options.playerNum, tooltip = options.alert.tooltip })
			else
				header = SiK.UI.Controls.copyText(questionBlock.childParent, { x = questionRect.x,
					y = questionRect.y, w = questionRect.w,
					text = question, tone = "text", playerNum = options.playerNum })
			end
			y = header.y + header.height + metrics.rowGap
			if consequences ~= "" then
				copy = SiK.UI.Controls.copyText(questionBlock.childParent, { x = questionRect.x,
					y = y, w = questionRect.w,
					text = consequences, tone = "textMuted", playerNum = options.playerNum })
				y = copy.y + copy.height
			end
			questionBlock:setBounds(rect.x, rect.y, rect.w,
				math.max(questionHeight, y - rect.y + 8))
			local actionsY = rect.y + questionBlock.h + metrics.rowGap
			local actionsBlock = SiK.UI.Block.create({ parent = dock.fixedBottomHost, x = 0, y = 0,
				w = rect.w, h = actionsHeight, title = options.actionsTitle,
				tooltip = options.actionsTooltip, info = options.actionsInfo,
				playerNum = options.playerNum })
				modalPanel.actionsBlock = actionsBlock
			local actionsRect = actionsBlock:getContentRect()
			local buttonWidth = math.floor((actionsRect.w - metrics.controlGap) / 2)
			local rejectSpec, acceptSpec = options.reject or {}, options.accept or {}
			rejectButton = SiK.UI.Controls.button(actionsBlock.childParent, { x = actionsRect.x,
				y = actionsRect.y, w = buttonWidth,
				text = rejectSpec.text or options.rejectText or "No", leadingIcon = rejectSpec.icon,
				iconSize = rejectSpec.iconSize or 18, danger = rejectSpec.danger ~= false,
				playerNum = options.playerNum, onClick = function()
					reject("reject"); Modal.close(panel, "reject")
				end })
				local acceptButton = SiK.UI.Controls.button(actionsBlock.childParent, { x = actionsRect.x + buttonWidth + metrics.controlGap,
				y = actionsRect.y, w = buttonWidth, text = acceptSpec.text or options.acceptText or "Yes",
				leadingIcon = acceptSpec.icon, iconSize = acceptSpec.iconSize or 18,
				success = acceptSpec.success ~= false, playerNum = options.playerNum,
					onClick = function() accept(); Modal.close(panel, "accept") end })
			modalPanel._sikDialogueLayout = function(bodyWidth, actionWidth)
				questionBlock:setBounds(0, 0, bodyWidth, questionBlock.h)
				local column = questionBlock:beginColumn()
				header:reflow(column.width)
				column:block(header, header.height)
				if copy then copy:reflow(column.width); column:block(copy, copy.height) end
				local bodyHeight = column:finish()
				actionsBlock:setBounds(0, 0, actionWidth, actionsBlock.h)
				local actions = actionsBlock:beginColumn()
				actions:row(metrics.buttonHeight, { { widget = rejectButton }, { widget = acceptButton } })
				return bodyHeight, actions:finish()
			end
		end,
	})
	finishDialogue(panel)
	if options.owner then Modal.presentChild(options.owner, panel, rejectButton)
	else Modal.show(panel, rejectButton) end
	return panel
end

function Modal.input(options)
        options = options or {}
        local metrics = SiK.UI.Controls.metrics("compact")
        local field, panel
        local quantity = type(options.quantity) == "table" and options.quantity or nil
        local function hasBlockHeader(title, tooltip, info)
                return title ~= nil or tooltip ~= nil or info ~= nil
        end
        local function blockHeight(content, title, tooltip, info)
                local height = content + 16
                if hasBlockHeader(title, tooltip, info) then
                        height = height + metrics.rowHeight + metrics.rowGap
                end
                return height
        end
        local fieldContentHeight = metrics.inputHeight
        if quantity and quantity.max ~= nil then
                fieldContentHeight = fieldContentHeight + metrics.rowGap + metrics.buttonHeight
        end
        local fieldBlockHeight = blockHeight(fieldContentHeight,
                options.fieldTitle or options.inputTitle, options.fieldTooltip, options.fieldInfo)
        local actionsBlockHeight = blockHeight(metrics.buttonHeight,
                options.actionsTitle, options.actionsTooltip, options.actionsInfo)
        local modalContentHeight = fieldBlockHeight + metrics.rowGap + actionsBlockHeight
        local function setQuantity(delta)
                if not field or not quantity then return false end
                local minimum = tonumber(quantity.min) or 0
                local maximum = tonumber(quantity.max)
                local step = math.max(1, tonumber(quantity.step) or 1)
                local current = tonumber(field:getText()) or minimum
                current = math.floor(current + 0.0001) + delta * step
                if current < minimum then current = minimum end
                if maximum and current > maximum then current = maximum end
                field:setText(tostring(current))
                if field.onTextChange then field:onTextChange() end
                return true
        end
        local function acceptValue()
                local value = field and field:getText() or ""
                if options.validate then
                        local valid, replacement = options.validate(value, panel)
                        if not valid then
                                if options.onInvalid then options.onInvalid(replacement, value, panel) end
                                return false, "invalid"
                        end
                        if replacement ~= nil then value = replacement end
                end
                local result = options.onAccept and options.onAccept(value, panel)
                if result == false then return false, "rejected" end
                Modal.close(panel, "accept")
                return true, value
        end
        local function onWindowClose(context)
		local reason = context and context.value or nil
		if reason ~= "accept" and options.onCancel then
			options.onCancel(context)
		end
		if options.onClose then return options.onClose(context) end
	end
	panel = Modal.create({
		kind = "input", title = options.title, playerNum = options.playerNum,
		owner = options.owner,
                width = options.width or Modal.STANDARD_MODAL_W,
                height = options.height or (modalContentHeight + metrics.rowGap * 2 + 52),
                contentHeight = options.contentHeight or modalContentHeight,
                contentMode = "dock", resizable = false, closeOnEscape = true, onClose = onWindowClose,
                buildContent = function(host, rect, modalPanel)
                        local dock = dialogueDock(modalPanel, host, rect)
                        local decreaseButton, increaseButton, maximumButton
                        local fieldBlock = SiK.UI.Block.create({ parent = dock.contentHost, x = 0, y = 0,
                                w = rect.w, h = fieldBlockHeight,
                                title = options.fieldTitle or options.inputTitle,
                                tooltip = options.fieldTooltip, info = options.fieldInfo,
                                playerNum = options.playerNum })
			modalPanel.inputBlock = fieldBlock
                        local fieldRect = fieldBlock:getContentRect()
                        local fieldWidth = fieldRect.w
                        if quantity then
                                fieldWidth = math.max(metrics.inputHeight,
                                        fieldRect.w - metrics.inputHeight * 2 - metrics.controlGap * 2)
                        end
                        local fieldX = fieldRect.x
                        if quantity then fieldX = fieldRect.x + metrics.inputHeight + metrics.controlGap end
                        field = SiK.UI.Controls.field(fieldBlock.childParent, { x = fieldX, y = fieldRect.y, w = fieldWidth,
                                text = options.text, placeholder = options.placeholder,
                                numeric = options.numeric, maxLength = options.maxLength,
                                playerNum = options.playerNum, onChange = options.onChange,
                                onSubmit = function() return acceptValue() end })
			modalPanel.inputField = field
                        if quantity then
                                decreaseButton = SiK.UI.Controls.button(fieldBlock.childParent, { x = fieldRect.x, y = fieldRect.y,
                                        w = metrics.inputHeight, text = quantity.decrementText or "-",
                                        tooltip = quantity.decrementTooltip,
                                        playerNum = options.playerNum, onClick = function() setQuantity(-1) end })
                                increaseButton = SiK.UI.Controls.button(fieldBlock.childParent, { x = fieldX + fieldWidth + metrics.controlGap,
                                        y = fieldRect.y, w = metrics.inputHeight, text = quantity.incrementText or "+",
                                        tooltip = quantity.incrementTooltip,
                                        playerNum = options.playerNum, onClick = function() setQuantity(1) end })
                                if quantity.max ~= nil then
                                        maximumButton = SiK.UI.Controls.button(fieldBlock.childParent, { x = fieldRect.x,
                                                y = fieldRect.y + metrics.inputHeight + metrics.rowGap, w = fieldRect.w,
                                                text = quantity.maxText or tostring(quantity.max), fullWidth = true,
                                                playerNum = options.playerNum, onClick = function()
                                                        field:setText(tostring(quantity.max))
                                                        if field.onTextChange then field:onTextChange() end
                                                end })
                                end
                        end
                        local actionsY = rect.y + fieldBlock.h + metrics.rowGap
                        local actionsBlock = SiK.UI.Block.create({ parent = dock.fixedBottomHost, x = 0, y = 0,
                                w = rect.w, h = actionsBlockHeight, title = options.actionsTitle,
                                tooltip = options.actionsTooltip, info = options.actionsInfo,
                                playerNum = options.playerNum })
			modalPanel.actionsBlock = actionsBlock
                        local actionsRect = actionsBlock:getContentRect()
                        local buttonW = math.floor((actionsRect.w - metrics.controlGap) / 2)
                        local cancelButton = SiK.UI.Controls.button(actionsBlock.childParent, { x = actionsRect.x, y = actionsRect.y, w = buttonW,
                                text = options.cancelText or translated("UI_Cancel", "Cancel"),
                                fullWidth = true, playerNum = options.playerNum,
                                onClick = function() Modal.close(panel, "cancel") end })
                        local acceptButton = SiK.UI.Controls.button(actionsBlock.childParent, { x = actionsRect.x + buttonW + metrics.controlGap,
                                y = actionsRect.y, w = buttonW,
                                text = options.acceptText or translated("UI_Ok", "OK"), fullWidth = true,
                                active = options.acceptActive == true,
                                playerNum = options.playerNum, onClick = acceptValue })
			modalPanel._sikDialogueLayout = function(bodyWidth, actionWidth)
				fieldBlock:setBounds(0, 0, bodyWidth, fieldBlock.h)
				local column = fieldBlock:beginColumn()
				if quantity then
					column:row(metrics.inputHeight, {
						{ widget = decreaseButton, w = metrics.inputHeight },
						{ widget = field },
						{ widget = increaseButton, w = metrics.inputHeight },
					})
				else column:block(field, metrics.inputHeight) end
				if maximumButton then column:block(maximumButton, metrics.buttonHeight) end
				local bodyHeight = column:finish()
				actionsBlock:setBounds(0, 0, actionWidth, actionsBlock.h)
				local actions = actionsBlock:beginColumn()
				actions:row(metrics.buttonHeight, { { widget = cancelButton }, { widget = acceptButton } })
				return bodyHeight, actions:finish()
			end
		end,
	})
	finishDialogue(panel)
	if options.owner then Modal.presentChild(options.owner, panel, field)
	else Modal.show(panel, field) end
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
