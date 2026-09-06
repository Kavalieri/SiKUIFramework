local root = "SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/"
package.path = root .. "?.lua;" .. package.path

local passed, failed = 0, 0
local function check(name, condition, detail)
	if condition then passed = passed + 1; io.write("PASS ", name, "\n")
	else failed = failed + 1; io.write("FAIL ", name, ": ", tostring(detail), "\n") end
end

UIFont = { Small = "small", Medium = "medium" }
Keyboard = { KEY_ESCAPE = 1 }
local tickHandlers = {}
Events = { OnTick = {
	Add = function(callback) tickHandlers[callback] = true end,
	Remove = function(callback) tickHandlers[callback] = nil end,
} }
local mouseX, mouseY = 100, 100
function getMouseX() return mouseX end
function getMouseY() return mouseY end
function getPlayerScreenLeft(playerNum) return playerNum * 640 end
function getPlayerScreenTop() return 0 end
function getPlayerScreenWidth() return 640 end
function getPlayerScreenHeight() return 720 end
function getText(key) return key end
function getTexture(path) return { path = path } end
function getTextManager()
	return {
		getFontHeight = function(_, font) return font == UIFont.Medium and 24 or 18 end,
		MeasureStringX = function(_, _, text) return #tostring(text or "") * 8 end,
	}
end

local Base = {}
Base.__index = Base
function Base:new(x, y, w, h)
	return setmetatable({ x = x or 0, y = y or 0, width = w or 0, height = h or 0,
		children = {}, visible = true }, self)
end
function Base:derive() local out = {}; out.__index = out; setmetatable(out, self); return out end
function Base:initialise() self.initialised = true end
function Base:instantiate() self.instantiated = true end
function Base:addChild(child) child.parent = self; self.children[#self.children + 1] = child end
function Base:removeChild(child)
	for index = #self.children, 1, -1 do
		if self.children[index] == child then table.remove(self.children, index) end
	end
	child.parent = nil
end
function Base:setX(value) self.x = value end
function Base:setY(value) self.y = value end
function Base:setWidth(value) self.width = value end
function Base:setHeight(value) self.height = value end
function Base:getX() return self.x end
function Base:getY() return self.y end
function Base:getWidth() return self.width end
function Base:getHeight() return self.height end
function Base:setVisible(value) self.visible = value end
function Base:getIsVisible() return self.visible end
function Base:addToUIManager() self.inManager = true end
function Base:removeFromUIManager() self.inManager = false end
function Base:bringToTop() self.onTop = true end
function Base:setAlwaysOnTop() self.alwaysOnTop = true end
function Base:setCapture(value) self.capture = value end
function Base:setMouseTransparent(value) self.mouseTransparent = value end
function Base:drawRect() end
function Base:drawRectBorder() end
function Base:drawText() end
function Base:drawTextureScaledAspect() end
function Base:drawTextureScaled() end
function Base:prerender() end
function Base:render() end

ISPanel = Base:derive("ISPanel")
ISButton = Base:derive("ISButton")
function ISButton:new(x, y, w, h, title, target, onclick)
	local out = Base.new(self, x, y, w, h)
	out.title, out.target, out.onclick, out.enable = title, target, onclick, true
	return out
end
function ISButton:setEnable(value) self.enable = value end
function ISButton:setTooltip(value) self.tooltip = value end

ISLabel = Base:derive("ISLabel")
function ISLabel:new(x, y, h, name, r, g, b, a, font)
	local out = Base.new(self, x, y, 0, h)
	out.name, out.r, out.g, out.b, out.a, out.font = name, r, g, b, a, font
	return out
end

ISTextEntryBox = Base:derive("ISTextEntryBox")
function ISTextEntryBox:new(text, x, y, w, h)
	local out = Base.new(self, x, y, w, h); out.text = text; return out
end
function ISTextEntryBox:getText() return self.text end
function ISTextEntryBox:setText(value) self.text = value end
function ISTextEntryBox:setEditable(value) self.editable = value end
function ISTextEntryBox:setOnlyNumbers(value) self.onlyNumbers = value end
function ISTextEntryBox:setMaxTextLength(value) self.maxLength = value end
function ISTextEntryBox:setPlaceholderText(value) self.placeholder = value end
function ISTextEntryBox:setTooltip(value) self.tooltip = value end
function ISTextEntryBox:focus() self.focused = true end

ISComboBox = Base:derive("ISComboBox")
function ISComboBox:new(x, y, w, h, target, onChange)
	local out = Base.new(self, x, y, w, h)
	out.target, out.onChange, out.options, out.selected = target, onChange, {}, 1
	return out
end
function ISComboBox:addOptionWithData(text, data)
	self.options[#self.options + 1] = { text = text, data = data }
end
function ISComboBox:setEnable(value) self.enabled = value end

package.preload["ISUI/ISPanel"] = function() return ISPanel end
package.preload["ISUI/ISButton"] = function() return ISButton end
package.preload["ISUI/ISLabel"] = function() return ISLabel end
package.preload["ISUI/ISTextEntryBox"] = function() return ISTextEntryBox end
package.preload["ISUI/ISComboBox"] = function() return ISComboBox end

local context = { options = {} }
function context:addOption(text, target, callback)
	local item = { text = text, target = target, callback = callback }
	self.options[#self.options + 1] = item
	return item
end
function context:setVisible(value) self.visible = value end
ISContextMenu = { get = function() context.options = {}; return context end }

require "SiK/UI/Namespace"
require "SiK/UI/Theme"
require "SiK/UI/Icon"
require "SiK/UI/FocusStack"
require "SiK/UI/Lifecycle"
require "SiK/UI/Tooltip"
require "SiK/UI/Menu"
require "SiK/UI/Popover"
require "SiK/UI/Drag"
require "SiK/UI/DragGhost"
require "SiK/UI/DropTarget"
require "SiK/UI/WorldPicker"
require "SiK/UI/Controls"
require "SiK/UI/Window"
require "SiK/UI/Modal"
require "SiK/UI/Tabs"
require "SiK/UI/Card"
require "SiK/UI/CardCollection"
require "SiK/UI/Form"
require "SiK/UI/Factories"

check("public namespace", type(SiK.UI) == "table" and GlobalStorageSiK == nil)
local parent = ISPanel:new(0, 0, 600, 600); parent:initialise()

local function testBasicControls()
local resolverCalls = 0
SiK.UI.setTextResolver(function(key, fallback) resolverCalls = resolverCalls + 1; return fallback end)
check("neutral text resolver", SiK.UI.resolveText("key", "Fallback") == "Fallback" and resolverCalls == 1)

local iconHandle = SiK.UI.Icon.register("test", "asset.png")
check("icon registration", SiK.UI.Icon.resolve("test").path == "asset.png")
local directDescriptor = { path = "direct-asset.png", width = 56, height = 56 }
local directTexture = SiK.UI.Icon.resolve(directDescriptor)
check("direct icon descriptor resolves to texture",
	directTexture ~= directDescriptor and directTexture.path == "direct-asset.png")
check("icon dispose idempotent", iconHandle:dispose() and iconHandle:dispose() == false)

local clicked = nil
local button = SiK.UI.Controls.button({ parent = parent, text = "Run", playerNum = 2,
	payload = "payload", onClick = function(ctx) clicked = ctx end })
button.onclick(button.target, button)
check("control callback context", clicked and clicked.playerNum == 2 and clicked.payload == "payload")
check("button color tables are owned and render-safe", type(button.textColor) == "table"
	and type(button.backgroundColor) == "table" and type(button.borderColor) == "table"
	and type(button.textColor.r) == "number" and type(button.textColor.g) == "number"
	and type(button.textColor.b) == "number" and type(button.textColor.a) == "number")
button.textColor = nil
SiK.UI.Controls.styleButton(button, {})
check("external button styling repairs nil text color", type(button.textColor) == "table"
        and type(button.textColor.r) == "number")
button.textColor = nil
button:prerender()
check("button prerender repairs later invalid color mutation", type(button.textColor) == "table"
        and type(button.textColor.r) == "number" and type(button.textColor.a) == "number")
local normalized = SiK.UI.Theme.tokens({ text = { r = -1, g = 2, b = "invalid", a = 4 } }).text
check("theme clamps malformed color channels", normalized.r == 0 and normalized.g == 1
	and normalized.b == 0 and normalized.a == 1)
local malformedPanel = SiK.UI.Controls.panel({ parent = parent, w = 20, h = 20,
	backgroundColor = "invalid", borderColor = { r = -3, g = 2, b = 0.5, a = 8 } })
check("panel normalizes malformed renderer colors", malformedPanel.backgroundColor.a == 0
	and malformedPanel.borderColor.r == 0 and malformedPanel.borderColor.g == 1
	and malformedPanel.borderColor.b == 0.5 and malformedPanel.borderColor.a == 1)
malformedPanel:dispose()
check("control lifecycle", button:dispose() and button:dispose() == false)

local genericPanel = SiK.UI.Controls.panel({ parent = parent, w = 80, h = 12 })
local separator = SiK.UI.Controls.separator({ parent = parent, x = 4, y = 6, w = 120 })
local themedSeparator = SiK.UI.Controls.create("separator", parent, {
	w = 90, h = 2, theme = { divider = { r = 0.1, g = 0.2, b = 0.3, a = 0.4 } },
})
check("panel and separator retain distinct semantics",
	genericPanel._sikUiControl == "panel" and genericPanel.drawBackground == false
		and separator._sikUiControl == "separator" and separator.drawBackground == true
		and separator.width == 120 and separator.height == 1
		and separator.backgroundColor.r == SiK.UI.Theme.defaults.divider.r
		and separator.borderColor.a == 0)
check("separator registry and theme override",
	themedSeparator._sikUiControl == "separator" and themedSeparator.height == 2
		and themedSeparator.backgroundColor.r == 0.1
		and themedSeparator.backgroundColor.g == 0.2
		and themedSeparator.backgroundColor.b == 0.3
		and themedSeparator.backgroundColor.a == 0.4)
genericPanel:dispose(); separator:dispose(); themedSeparator:dispose()
check("separator lifecycle is idempotent", separator.parent == nil
	and separator:dispose() == false and themedSeparator:dispose() == false)

local copy = SiK.UI.Controls.copyText({ parent = parent, w = 80,
	text = "Reusable wrapped copy" })
check("neutral chrome controls", copy._sikUiControl == "copyText" and #copy.lines > 1)
copy:dispose()

local passiveIcon = SiK.UI.Controls.icon({ parent = parent, texture = { path = "asset.png" },
	w = 32, h = 32, tone = "accent" })
check("passive icon slot", passiveIcon._sikUiControl == "icon"
	and passiveIcon:getTexture().path == "asset.png" and passiveIcon:dispose())
end
testBasicControls()

local function testDynamicIconButtonContract()
	local host = ISPanel:new(0, 0, 120, 60); host:initialise()
	local childCount = #host.children
	local baseRenders, providerCalls, tintCalls = 0, 0, 0
	local previousButtonRender = ISButton.render
	ISButton.render = function() baseRenders = baseRenders + 1 end
	-- Plain tables model already-loaded Texture userdata in this harness. Path
	-- tables are asset descriptors and must be resolved before PZ draw calls.
	local iconA, iconB = { textureId = "dynamic-a" }, { textureId = "dynamic-b" }
	local button = SiK.UI.Controls.iconButton({ parent = host, w = 80, h = 40,
		chrome = false, iconPadding = 4, iconFit = "fill", tooltip = "Dynamic icon",
		iconProvider = function()
			providerCalls = providerCalls + 1
			return iconA
		end,
		iconTintProvider = function()
			tintCalls = tintCalls + 1
			return { r = 0.2, g = 0.3, b = 0.4, a = 0.5 }
		end,
	})
	ISButton.render = previousButtonRender
	local draws = {}
	button.drawTextureScaledAspect = function(_, texture, x, y, w, h, a, r, g, b)
		draws[#draws + 1] = { texture = texture, x = x, y = y, w = w, h = h,
			a = a, r = r, g = g, b = b }
	end
	button:render()
	local fillOk = #draws == 1 and draws[1].texture == iconA
		and draws[1].x == 4 and draws[1].y == 4
		and draws[1].w == 72 and draws[1].h == 32
		and draws[1].a == 0.5 and draws[1].r == 0.2
		and draws[1].g == 0.3 and draws[1].b == 0.4
	local noDuplicate = #host.children == childCount + 1
		and button:setTexture(iconB) == button
		and button:setIconProvider(function() return iconB end) == button
		and button:setIconTint({ r = 0.6, g = 0.7, b = 0.8, a = 0.9 }) == button
		and button:setIconTintProvider(nil) == button
		and button:setChrome(false) == button
		and #host.children == childCount + 1
	button.iconFit = "square"; button.iconSize = 24; draws = {}; button:render()
	local squareOk = #draws == 1 and draws[1].texture == iconB
		and draws[1].x == 28 and draws[1].y == 8
		and draws[1].w == 24 and draws[1].h == 24
		and draws[1].a == 0.9 and draws[1].r == 0.6
		and draws[1].g == 0.7 and draws[1].b == 0.8
	button:setChrome(true); button:render()
	local chromeOk = baseRenders == 0 and button._sikUiControl == "iconButton"
	local tooltipHandle = button._sikTooltipHandle
	local disposed = button:dispose()
	check("icon button dynamic providers and fit modes", fillOk and squareOk
		and providerCalls == 1 and tintCalls == 1)
	check("icon button uses only SiK chrome and setters keep one widget", noDuplicate and chromeOk)
	check("icon button tooltip lifecycle follows control", tooltipHandle ~= nil
		and tooltipHandle.disposed == true and disposed and button:dispose() == false
		and #host.children == childCount)
end
testDynamicIconButtonContract()

local function testStatusControls()
local refreshOwner = ISPanel:new(0, 0, 20, 20)
local refreshCount = 0
local refreshHandle = SiK.UI.Lifecycle.bindVisibleRefresh(refreshOwner, {
	refresh = function() refreshCount = refreshCount + 1 end,
})
local registeredVisible = refreshHandle:mode() == "event"
for callback in pairs(tickHandlers) do callback() end
refreshOwner:setVisible(false)
local unregisteredHidden = refreshHandle:mode() == "manual"
refreshOwner:setVisible(true)
refreshHandle:setActive(false)
check("visible refresh owns tick only while visible", registeredVisible and refreshCount == 1
	and unregisteredHidden and refreshHandle:mode() == "manual"
	and refreshHandle:dispose() and refreshHandle:dispose() == false)

local framedStatus = SiK.UI.Controls.status({ parent = parent, framed = true,
	w = 240, text = "Waiting", tone = "warning" })
framedStatus:setStatus("Ready", "success")
local requirement = SiK.UI.Controls.requirementRow({ parent = parent, w = 150,
	text = "A reusable requirement with wrapped text", state = "missing",
	texture = { path = "requirement.png" } })
local requirementHeight = requirement.height
requirement:setData({ text = "Available", state = "met" })
check("status frame and requirement row", framedStatus._sikFramed
	and framedStatus.text == "Ready" and framedStatus.tone == "success"
	and requirement._sikUiControl == "requirementRow"
	and requirement:getTexture().path == "requirement.png"
	and requirementHeight > 32 and requirement.tone == "success")
framedStatus:dispose(); requirement:dispose()

local selectedOption = nil
local listOption = SiK.UI.Controls.listOption({ parent = parent, w = 132,
        text = "A long reusable selectable option", payload = { id = "network" },
        selected = true, onClick = function(context) selectedOption = context.payload end })
local listOptionHeight = listOption.height
listOption.onclick(listOption.target, listOption)
listOption:setData({ text = "Unavailable option", payload = { id = "offline" },
        selected = false, enabled = false })
check("typed list option lifecycle", listOptionHeight > 32
        and selectedOption.id == "network" and not listOption:isSelected()
        and not listOption:isEnabled() and listOption._sikUiControl == "listOption"
        and listOption:dispose() and listOption:dispose() == false)
end
testStatusControls()

local function testTooltipContracts()
local previousMoveCalls = 0
local tooltipControl = ISButton:new(0, 0, 20, 20, "", nil, nil)
tooltipControl.onMouseMove = function() previousMoveCalls = previousMoveCalls + 1 end
local tooltipHandle = SiK.UI.Tooltip.attach(tooltipControl, { text = "Help" })
tooltipControl:onMouseMove(0, 0)
local chained = previousMoveCalls == 1 and tooltipControl.tooltip == "Help"
tooltipHandle:dispose()
check("tooltip preserves chain", chained and tooltipControl.tooltip == nil)

local informationControl = ISButton:new(0, 0, 20, 20, "", nil, nil)
local informationHandle = SiK.UI.Tooltip.attach(informationControl, {
	text = "Long explanatory help", profile = "informational",
})
informationControl:onMouseMove(0, 0)
local informationPanel = informationHandle:getActive()
check("informational tooltip uses the readable wide profile",
	informationPanel ~= nil and informationPanel.width > 520)
informationHandle:dispose()

local tooltipPanel = nil
local lazyControl = ISButton:new(0, 0, 20, 20, "", nil, nil)
local lazyHandle = SiK.UI.Tooltip.attach(lazyControl, { factory = function()
	tooltipPanel = ISPanel:new(0, 0, 80, 30); tooltipPanel:initialise(); return tooltipPanel
end })
lazyControl:onMouseMove(0, 0)
local lazyOk = lazyHandle:getActive() == tooltipPanel and tooltipPanel._sikUiTooltip
lazyControl:onMouseMoveOutside(0, 0); lazyHandle:dispose()
check("tooltip lazy passive lifecycle", lazyOk and tooltipPanel.inManager == false)

local tooltipDocument = {}
local sectionHandle = SiK.UI.Tooltip.appendSection(tooltipDocument,
	{ title = "Info", text = "Reusable measured tooltip section", tone = "info" })
local measuredSection = SiK.UI.Tooltip.measureSection(tooltipDocument._sikTooltipSections[1], 120)
local renderedSection = SiK.UI.Tooltip.renderSection(parent,
	tooltipDocument._sikTooltipSections[1], 0, 0, 120)
check("tooltip measured section lifecycle", measuredSection.height > 16
	and renderedSection.height == measuredSection.height
	and #measuredSection.lines > 1 and sectionHandle:dispose()
	and #tooltipDocument._sikTooltipSections == 0)

local previousDrawRect = parent.drawRect
local previousDrawRectBorder = parent.drawRectBorder
local previousDrawText = parent.drawText
local tooltipFills, tooltipBorders, tooltipTexts = {}, {}, {}
parent.drawRect = function(_, x, y, w, h, a, r, g, b)
	tooltipFills[#tooltipFills + 1] = {
		x = x, y = y, w = w, h = h, a = a, r = r, g = g, b = b,
	}
end
parent.drawRectBorder = function(_, x, y, w, h, a, r, g, b)
	tooltipBorders[#tooltipBorders + 1] = {
		x = x, y = y, w = w, h = h, a = a, r = r, g = g, b = b,
	}
end
parent.drawText = function(_, text, x, y, r, g, b, a, font)
	tooltipTexts[#tooltipTexts + 1] = {
		text = text, x = x, y = y, r = r, g = g, b = b, a = a, font = font,
	}
end

local invalidFrame, invalidFrameReason = SiK.UI.Tooltip.renderFrame(nil, 0, 0, 10, 10)
local directFrame = SiK.UI.Tooltip.renderFrame(parent, 2, 3, 100, 50, {
	backgroundColor = { 0.1, 0.2, 0.3, 0.4 },
	borderColor = { r = 0.5, g = 0.6, b = 0.7, a = 0.8 },
})
check("tooltip frame validates and normalizes colors",
	invalidFrame == nil and invalidFrameReason == "invalid_panel"
	and directFrame.x == 2 and directFrame.y == 3
	and directFrame.width == 100 and directFrame.height == 50
	and #tooltipFills == 1 and tooltipFills[1].a == 0.4
	and tooltipFills[1].r == 0.1 and tooltipFills[1].g == 0.2
	and tooltipFills[1].b == 0.3 and #tooltipBorders == 1
	and tooltipBorders[1].a == 0.8 and tooltipBorders[1].r == 0.5
	and tooltipBorders[1].g == 0.6 and tooltipBorders[1].b == 0.7)

SiK.UI.Tooltip.renderFrame(parent, 4, 5, -10, -20, { border = false })
check("tooltip frame can omit border and clamps negative size",
	#tooltipFills == 2 and #tooltipBorders == 1
	and tooltipFills[2].x == 4 and tooltipFills[2].y == 5
	and tooltipFills[2].w == 0 and tooltipFills[2].h == 0)

tooltipFills, tooltipBorders, tooltipTexts = {}, {}, {}
local paddedSection = {
	title = "Title", lines = { "Body" }, framed = true,
	lineColor = { 0.11, 0.22, 0.33, 0.44 },
}
local paddedOptions = { padding = 2, paddingX = 7, paddingY = 5, gap = 3 }
local paddedMeasure = SiK.UI.Tooltip.measureSection(paddedSection, 100, paddedOptions)
local paddedRender = SiK.UI.Tooltip.renderSection(parent,
	paddedSection, 10, 20, 100, paddedOptions)
check("tooltip section supports independent horizontal and vertical padding",
	paddedMeasure.padding == 2 and paddedMeasure.paddingX == 7
	and paddedMeasure.paddingY == 5 and paddedMeasure.innerWidth == 86
	and paddedMeasure.height == 49 and paddedRender.height == paddedMeasure.height
	and #tooltipFills == 1 and #tooltipBorders == 1 and #tooltipTexts == 2
	and tooltipTexts[1].text == "Title" and tooltipTexts[1].x == 17
	and tooltipTexts[1].y == 25 and tooltipTexts[2].text == "Body"
	and tooltipTexts[2].x == 17 and tooltipTexts[2].y == 46)
check("tooltip section accepts array line color",
	tooltipTexts[2].r == 0.11 and tooltipTexts[2].g == 0.22
	and tooltipTexts[2].b == 0.33 and tooltipTexts[2].a == 0.44)

tooltipTexts = {}
SiK.UI.Tooltip.renderSection(parent, { text = "Named color", framed = false },
	0, 0, 100, { paddingX = 3, paddingY = 4,
		lineColor = { r = 0.61, g = 0.62, b = 0.63, a = 0.64 } })
check("tooltip section accepts keyed line color from render options",
	#tooltipTexts == 1 and tooltipTexts[1].x == 3 and tooltipTexts[1].y == 4
	and tooltipTexts[1].r == 0.61 and tooltipTexts[1].g == 0.62
	and tooltipTexts[1].b == 0.63 and tooltipTexts[1].a == 0.64)

parent.drawRect = previousDrawRect
parent.drawRectBorder = previousDrawRectBorder
parent.drawText = previousDrawText

local ephemeral = SiK.UI.Tooltip.createDocument({ sectionGap = 6,
	sections = { { title = "First", text = "One" } } })
ephemeral:set({ { title = "Replacement", text = "Two" } })
ephemeral:set({ { title = "Final", text = "Three" } })
local ephemeralMeasure = ephemeral:measure(140)
local ephemeralRender = ephemeral:render(parent, 0, 0, 140)
ephemeral:clear()
check("tooltip document replaces without accumulation", ephemeralMeasure.height == ephemeralRender.height
	and #ephemeral.sections == 0 and ephemeral:dispose() and ephemeral:dispose() == false)
end
testTooltipContracts()

local function testInteractionContracts()
local popoverControl = ISButton:new(10, 10, 30, 20, "", nil, nil)
local popoverHandle = SiK.UI.Popover.attach(popoverControl, { playerNum = 0,
	factory = function() local value = ISPanel:new(0, 0, 100, 60); value:initialise(); return value end })
popoverControl:onMouseUp(0, 0)
local popoverOpened = popoverHandle:getActive() and popoverHandle:getActive().inManager
SiK.UI.FocusStack.handleEscape(0)
check("popover focus and escape lifecycle", popoverOpened and popoverHandle:getActive() == nil
	and popoverHandle:dispose() and popoverHandle:dispose() == false)

local manualControl = ISButton:new(0, 0, 20, 20, "", nil, nil)
local originalManualUp = manualControl.onMouseUp
local manualPopover = SiK.UI.Popover.attach(manualControl, { trigger = "manual", focus = false,
	factory = function() return ISPanel:new(0, 0, 60, 30) end })
local manualWidget = manualPopover:open()
check("popover manual trigger and optional focus", manualControl.onMouseUp == originalManualUp
	and manualWidget ~= nil and SiK.UI.FocusStack.top(0) == nil
	and manualPopover:close("test") and manualPopover:dispose())

local passiveControl = ISButton:new(0, 0, 20, 20, "", nil, nil)
local passivePopover = SiK.UI.Popover.attach(passiveControl, { trigger = "passive",
	factory = function() return ISPanel:new(0, 0, 60, 30) end })
passiveControl:onMouseMove(0, 0); local passiveOpen = passivePopover:getActive() ~= nil
passiveControl:onMouseMoveOutside(0, 0)
check("popover passive hover lifecycle", passiveOpen and passivePopover:getActive() == nil
	and passivePopover:dispose())

local rightCalls = 0
local menuControl = ISButton:new(0, 0, 20, 20, "", nil, nil)
menuControl.onRightMouseUp = function() rightCalls = rightCalls + 1 end
local menu = SiK.UI.Menu.attach(menuControl, { playerNum = 1,
	items = { { text = "Action", onSelect = function() end } } })
menuControl:onRightMouseUp(4, 5)
local menuOk = rightCalls == 1 and #context.options == 1
menu:dispose()
check("menu preserves chain", menuOk and menuControl.onRightMouseUp ~= nil)

local escaped = {}
local low = SiK.UI.FocusStack.push({ playerNum = 0, priority = 1,
	onEscape = function() escaped[#escaped + 1] = "low" end })
local high = SiK.UI.FocusStack.push({ playerNum = 0, priority = 2,
	onEscape = function() escaped[#escaped + 1] = "high" end })
SiK.UI.FocusStack.handleEscape(0)
high:dispose(); SiK.UI.FocusStack.handleEscape(0); low:dispose()
check("focus isolated priority", escaped[1] == "high" and escaped[2] == "low")

local cancelled = 0
local drag = SiK.UI.Drag.begin({ playerNum = 1, onCancel = function() cancelled = cancelled + 1 end })
drag:cancel("test")
check("drag lifecycle", cancelled == 1 and SiK.UI.Drag.active(1) == nil and drag:dispose() == false)

local dropped = nil
local dropControl = ISPanel:new(0, 0, 80, 40)
local dropHandle = SiK.UI.DropTarget.attach(dropControl, { playerNum = 1,
	accept = function(payload) return payload == "item" end,
	onDrop = function(payload) dropped = payload end })
local targetDrag = SiK.UI.Drag.begin({ playerNum = 1, payload = "item" })
dropControl:onMouseMove(0, 0); dropControl:onMouseUp(0, 0)
check("drop target uses active drag lifecycle", dropped == "item"
	and SiK.UI.Drag.active(1) == nil and dropHandle:dispose())

local externalFinished, externalSession = 0, { payload = "external" }
local externalControl = ISPanel:new(0, 0, 80, 40)
local externalDrop = SiK.UI.DropTarget.attach(externalControl, { playerNum = 2,
	dragProvider = function(playerNum) return playerNum == 2 and externalSession or nil end,
	finishDrag = function(session) if session == externalSession then externalFinished = externalFinished + 1 end end })
externalControl:onMouseMove(0, 0); local externalOver = externalDrop:isOver()
externalControl:setVisible(false); local clearedWhenHidden = not externalDrop:isOver()
externalControl:setVisible(true); externalControl:onMouseMove(0, 0); externalControl:onMouseUp(0, 0)
check("drop target external provider visible lifecycle", externalOver and clearedWhenHidden
	and externalFinished == 1 and externalDrop:dispose())

local monitorControl = ISPanel:new(0, 0, 80, 40)
local monitorDragging, monitorPayload, monitoredDrop = false, nil, nil
local monitor = SiK.UI.DropTarget.monitor(monitorControl, {
	isDragging = function() return monitorDragging end,
	payload = function() return monitorPayload end,
	isOver = function() return true end,
	onDrop = function(value) monitoredDrop = value end,
})
local function runTicks()
	local callbacks = {}
	for callback in pairs(tickHandlers) do callbacks[#callbacks + 1] = callback end
	for index = 1, #callbacks do callbacks[index]() end
end
monitorDragging, monitorPayload = true, "vanilla-item"; runTicks()
monitorDragging = false; runTicks()
local monitorDropped = monitoredDrop == "vanilla-item" and monitor:isInstalled()
monitorControl:setVisible(false)
local monitorStopped = not monitor:isInstalled()
monitorControl:setVisible(true)
local monitorRestarted = monitor:isInstalled()
monitorControl:removeFromUIManager()
check("drop target monitored source lifecycle", monitorDropped and monitorStopped
	and monitorRestarted and not monitor:isInstalled() and monitor:dispose() == false)
end
testInteractionContracts()

local function testWorldPickerContracts()
local picked = nil
local picker = SiK.UI.WorldPicker.create({ playerNum = 0, autoShow = true,
	resolvePoint = function(point) point.worldX = point.screenX + 1; return point end,
	onConfirm = function(context) picked = context.value end })
picker:onMouseDown(3, 4); picker:onMouseUp(3, 4)
check("world picker capture and dispose", picked and picked.worldX == 4
	and picker.capture == false and picker.visible == false and picker:dispose()
	and picker.setVisible == Base.setVisible and picker:dispose() == false)

local multiConfirmed = nil
local multiPicker = SiK.UI.WorldPicker.create({ playerNum = 0, multiStep = true,
	stepsRequired = 2, onConfirm = function(context) multiConfirmed = context.value.steps end })
multiPicker:onMouseDown(1, 2); multiPicker:onMouseUp(1, 2)
local persistedBetweenClicks = multiPicker.visible and #multiPicker:getSteps() == 1
multiPicker:onMouseDown(3, 4); multiPicker:onMouseUp(3, 4)
check("world picker multi-step completion", persistedBetweenClicks and #multiConfirmed == 2
	and multiPicker.visible == false and multiPicker:dispose())

local cancelledSteps = nil
local cancellablePicker = SiK.UI.WorldPicker.create({ playerNum = 0, multiStep = true,
	onCancel = function(context) cancelledSteps = context.value.steps end })
cancellablePicker:onMouseDown(5, 6); cancellablePicker:onMouseUp(5, 6)
SiK.UI.FocusStack.handleEscape(0)
check("world picker cancels between clicks", cancelledSteps and #cancelledSteps == 1
	and #cancellablePicker:getSteps() == 0 and cancellablePicker.visible == false
	and cancellablePicker:dispose())

local idleCancelled, idleReason = 0, nil
local idlePicker = SiK.UI.WorldPicker.create({ playerNum = 0, autoShow = true,
	onCancel = function(context)
		idleCancelled = idleCancelled + 1
		idleReason = context.value.reason
	end })
local idleFocused = SiK.UI.FocusStack.top(0) ~= nil
local idleResult = idlePicker:cancel("button")
local idleAgain = idlePicker:cancel("duplicate")
check("world picker idle cancel is complete and idempotent", idleFocused and idleResult
	and idleAgain == false and idleCancelled == 1 and idleReason == "button"
	and idlePicker.capture == false and idlePicker.visible == false
	and SiK.UI.FocusStack.top(0) == nil and idlePicker:dispose())
end
testWorldPickerContracts()

local function testWindowContracts()
local window = SiK.UI.Window.create({ title = "Window", playerNum = 0,
	profile = "compact", width = 500, height = 300 })
local rect = window:contentRect()
local windowOk = window._sikWindowApplied and rect.w > 0 and rect.h > 0
local wheelCaptured = window:onMouseWheel(1) == true
local resizeHit = SiK.UI.Window.hitTestResizeHandle(window,
	window.width - 1, window.height - 1) == "bottom-right"
window:setSize(520, 340); window:dispose()
check("window shell lifecycle", windowOk and wheelCaptured and resizeHit
	and window:dispose() == false)

local framed = SiK.UI.Window.create({ playerNum = 0, profile = "compact",
	width = 500, height = 300,
	header = { productName = "Product", contextName = "Context",
		status = { text = "Live", tone = "success",
			color = { r = 0.2, g = 0.8, b = 0.4, a = 1 } },
		close = { text = "X", tooltip = "Close" } },
	footer = { versions = { { label = "Core", value = "1.0" },
		{ label = "Addon", value = "2.0" } }, align = "center" },
})
local initialContent = framed:contentRect().h
local initialFooter = framed.footerHeight
local slotsOk = framed.titleControl.label.name == "Product | Context"
	and framed.headerStatusControl.name == "Live"
	and framed.headerStatusControl.r == 0.2
	and framed.closeControl ~= nil and framed._sikFooterAlign == "center"
	and framed._sikFooterText == "Core: 1.0 | Addon: 2.0" and initialFooter > 0
framed:setSize(framed.width, framed.height + 40)
local resizeOk = framed:contentRect().h == initialContent + 40
framed:setHeaderStatus({ text = "Idle", tone = "warning" })
local liveOk = framed.headerStatusControl.name == "Idle"
	and framed.headerStatusControl.tone == "warning"
	and framed.headerStatusControl.r == SiK.UI.Theme.defaults.warning.r
framed:setHeaderStatus(nil)
local statusRemoved = framed.headerStatusControl == nil
framed:setHeaderStatus("Back", "success")
liveOk = liveOk and statusRemoved and framed.headerStatusControl.name == "Back"
framed:setVersions(nil)
local hiddenFooterOk = framed.footerHeight == 0 and framed._sikFooterText == ""
framed:setVersions({ { label = "Core", value = "1.1" } })
local restoredFooterOk = framed.footerHeight == initialFooter
	and framed._sikFooterText == "Core: 1.1"
framed:dispose()
check("declarative window slots and resize", slotsOk and resizeOk and liveOk)
check("automatic versions footer lifecycle", hiddenFooterOk and restoredFooterOk
	and #framed.children == 0 and framed._sikWindowOptions == nil)

local noFooter = SiK.UI.Window.create({ productName = "No footer",
	profile = "compact", width = 460, height = 240 })
local noFooterOk = noFooter.footerHeight == 0 and noFooter:contentRect().h > 0
noFooter:dispose()
check("window without footer reserves nothing", noFooterOk)

local accent = SiK.UI.Window.create({ productName = "Accent", profile = "compact",
	width = 460, height = 240, accentEdge = { side = "left", width = 3, tone = "accent" } })
local accentContent = accent:contentRect()
accent.drawRects = {}
accent.drawRect = function(self, x, y, w, h)
	self.drawRects[#self.drawRects + 1] = { x = x, y = y, w = w, h = h }
end
accent:prerender()
local accentDrawn = false
for _, drawn in ipairs(accent.drawRects) do
	if drawn.x == 0 and drawn.y == 0 and drawn.w == 3 and drawn.h == accent.height then accentDrawn = true end
end
check("optional window accent preserves layout", accentContent.x == accent.contentPadding
	and accent._sikWindowOptions.accentEdge.width == 3 and accentDrawn)
accent:dispose()
end
testWindowContracts()

local function testModalContracts()
local modal = SiK.UI.Modal.create({ title = "Task", kind = "task", playerNum = 0,
	contentHeight = 900, buildContent = function(host) host.built = true end })
local modalOk = modal and modal.contentHost.built and modal.contentBlock.overflow == true
SiK.UI.Modal.show(modal); SiK.UI.Modal.close(modal, "test")
check("modal block scroll lifecycle", modalOk and modal._sikDisposed == true)

local appliedModal = ISPanel:new(10, 10, 460, 200); appliedModal:initialise()
SiK.UI.Modal.apply(appliedModal, { kind = "compact", title = "Applied",
	width = 460, height = 200, resizable = false })
SiK.UI.Modal.fitContent(appliedModal, 260,
	{ contentBottom = true, bottomPadding = 12, center = true })
SiK.UI.Modal.show(appliedModal)
check("applied modal direct fit", appliedModal._sikModal
	and appliedModal.height == 272 and appliedModal.x >= 0 and appliedModal.y >= 0)
appliedModal:dispose()
check("applied modal direct dispose clears stack",
	SiK.UI.Modal.top(appliedModal.playerNum) == nil and appliedModal:dispose() == false)

local accepted, invalid, cancelled = nil, 0, 0
local inputModal, inputField = SiK.UI.Modal.input({ title = "Quantity",
	numeric = true, maxLength = 3,
	validate = function(value)
		local amount = tonumber(value)
		if not amount or amount < 1 then return false, "invalid" end
		return true, amount
	end,
	onInvalid = function(reason) if reason == "invalid" then invalid = invalid + 1 end end,
	onAccept = function(value) accepted = value end,
	onCancel = function() cancelled = cancelled + 1 end,
})
local inputParentsCorrect = inputModal.inputBlock ~= nil and inputModal.actionsBlock ~= nil
	and inputModal.inputBlock.parent == inputModal.dialogueDock.contentHost
	and inputModal.actionsBlock.parent == inputModal.dialogueDock.fixedBottomHost
-- The padded field owns chrome; numeric/length constraints belong to its
-- native text backend. Capture before successful submit disposes the field.
local inputNativeOptions = inputField.entry.onlyNumbers == true
	and inputField.entry.maxLength == 3
inputField:setOnlyNumbers(false); inputField:setMaxTextLength(5)
local inputNativeForwarded = inputField.entry.onlyNumbers == false
	and inputField.entry.maxLength == 5
inputField:setOnlyNumbers(true); inputField:setMaxTextLength(3)
inputNativeForwarded = inputNativeForwarded and inputField.entry.onlyNumbers == true
	and inputField.entry.maxLength == 3
inputField:setText("bad"); local invalidSubmit = inputField:onPressEnter()
local inputStayedOpen = not inputModal._sikDisposed and invalid == 1
inputField:setText("4"); local validSubmit = inputField:onPressEnter()
check("input validation and field options", inputNativeOptions and inputNativeForwarded
        and invalidSubmit == false and validSubmit == true
	and inputStayedOpen and accepted == 4
	and inputModal._sikDisposed and cancelled == 0
	and inputParentsCorrect and inputModal.inputBlock == nil and inputModal.actionsBlock == nil)

local cancelModal = SiK.UI.Modal.input({ title = "Cancel",
	onCancel = function() cancelled = cancelled + 1 end })
local cancelButton = cancelModal.actionsBlock.childParent.children[1]
cancelButton.onclick(cancelButton.target, cancelButton)
check("input explicit cancel", cancelModal._sikDisposed and cancelled == 1)

local quantityModal, quantityField = SiK.UI.Modal.input({ title = "Amount", text = "2", numeric = true,
	quantity = { min = 1, max = 5, step = 1, decrementText = "-", incrementText = "+", maxText = "Max" },
	validate = function(value) return tonumber(value) ~= nil end,
})
local quantityChildren = quantityModal.inputBlock.childParent.children
quantityChildren[2].onclick(quantityChildren[2].target, quantityChildren[2])
local afterDecrease = quantityField:getText() == "1"
quantityChildren[3].onclick(quantityChildren[3].target, quantityChildren[3])
quantityChildren[4].onclick(quantityChildren[4].target, quantityChildren[4])
check("quantity changes field without accepting", afterDecrease and quantityField:getText() == "5"
	and not quantityModal._sikDisposed)
SiK.UI.Modal.close(quantityModal, "cancel")

local rejected, confirmed = 0, 0
local confirmation = SiK.UI.Modal.confirm({ title = "Confirm", question = "Remove this entry?",
	consequences = "The configured entry will no longer participate.",
	alert = { icon = "alert.png", tooltip = "Warning", severity = "danger", glow = true },
	actionsTitle = "Actions", reject = { text = "No", icon = "close.png" },
	accept = { text = "Yes", icon = "check.png" },
	onReject = function() rejected = rejected + 1 end,
	onAccept = function() confirmed = confirmed + 1 end,
})
local confirmParentsCorrect = confirmation.questionBlock ~= nil and confirmation.actionsBlock ~= nil
	and confirmation.questionBlock.parent == confirmation.dialogueDock.contentHost
	and confirmation.actionsBlock.parent == confirmation.dialogueDock.fixedBottomHost
local confirmButtons = confirmation.actionsBlock.childParent.children
confirmButtons[3].onclick(confirmButtons[3].target, confirmButtons[3])
check("confirmation uses question and action Blocks", confirmParentsCorrect
	and confirmation._sikDisposed and confirmed == 1 and rejected == 0
	and confirmation.questionBlock == nil and confirmation.actionsBlock == nil)
end
testModalContracts()

local function testTabsContracts()
local firstContent, secondContent = ISPanel:new(), ISPanel:new()
local tabs = SiK.UI.Tabs.create({ parent = parent, activeKey = "a",
	items = { { key = "a", text = "A", content = firstContent },
		{ key = "b", text = "B", content = secondContent } },
	bounds = { x = 0, y = 0, w = 200, h = 30 } })
tabs:setActive("b", false)
check("tabs canonical activation", not firstContent.visible and secondContent.visible)
tabs:dispose()

local bottomTabs = SiK.UI.Tabs.create({ parent = parent, placement = "bottom",
	items = { { key = "ready", text = "Ready", content = firstContent },
		{ key = "locked", text = "Locked", enabled = false, content = secondContent } },
	bounds = { x = 0, y = 0, w = 200, h = 30 } })
local disabledResult, disabledReason = bottomTabs:setActive("locked", false)
check("tabs bottom and disabled contract", bottomTabs.placement == "bottom"
	and disabledResult == nil and disabledReason == "disabled_tab")
bottomTabs:dispose()

local railTabs = SiK.UI.Tabs.create({ parent = parent, placement = "left",
	activeKey = "warehouse", iconOnly = true, itemExtent = 76, iconSize = 68,
	padding = 0, gap = 0, separator = true, separatorOffset = 6,
	selectionStyle = "border", tooltipMode = "flyout", tooltipSide = "before",
	items = {
		{ key = "warehouse", text = "Warehouse", tooltip = "Warehouse",
			icon = "warehouse.png" },
		{ key = "network", text = "Network", tooltip = "Network",
			icon = "network.png" },
		{ key = "addons", text = "Addons", tooltip = "Addons",
			icon = "addons.png", pin = "end" },
	}, bounds = { x = 0, y = 0, w = 104, h = 400 } })
local warehouseButton = railTabs:getButton("warehouse")
local networkButton = railTabs:getButton("network")
local addonsButton = railTabs:getButton("addons")
networkButton:onMouseMove(0, 0)
local networkTooltip = networkButton._sikTooltipHandle
local railLayoutOk = warehouseButton.y == 12 and warehouseButton.height == 76
	and networkButton.y == 88 and addonsButton.y == 312
	and railTabs.separator.y == 306 and addonsButton.texture.path == "addons.png"
	and networkButton.tooltip == "Network" and networkTooltip ~= nil
	and networkTooltip:getActive() ~= nil
railTabs:updateItem("network", { badge = { text = "!", tone = "warning",
	tooltip = "Network warning" } })
networkButton:onMouseMove(0, 0)
local railStateOk = networkButton.tooltip == "Network"
	and networkButton._sikTabItem.badge.tone == "warning"
warehouseButton:onMouseMove(0, 0)
railStateOk = railStateOk and warehouseButton.tooltip == "Warehouse"
	and warehouseButton._sikTooltipHandle:getActive() ~= nil
addonsButton:onMouseMove(0, 0)
railStateOk = railStateOk and addonsButton.tooltip == "Addons"
	and addonsButton._sikTooltipHandle:getActive() ~= nil
warehouseButton.onclick(warehouseButton.target, warehouseButton)
railStateOk = railStateOk and warehouseButton:isSelected()
railTabs:setItems({
	{ key = "warehouse", text = "Warehouse", icon = "warehouse.png" },
	{ key = "craft", text = "Craft", icon = "craft.png" },
	{ key = "addons", text = "Addons", icon = "addons.png", pin = "end" },
})
check("tabs vertical icon rail and footer pin", railLayoutOk and railStateOk
	and railTabs:getSelectedKey() == "warehouse" and railTabs:getButton("craft").y == 88)
railTabs:dispose()
check("tabs rail cleanup", railTabs:dispose() == false and railTabs.parent == nil)
end
testTabsContracts()

local function testDragGhostContracts()
local ghost = SiK.UI.DragGhost.create({ playerNum = 0, autoShow = false, maxRows = 2,
	rows = { { name = "One", icon = "test", count = 2 }, { name = "Two" },
		{ name = "Three" } } })
local ghostOk = ghost._sikVisualOnly and ghost.height == 120 and ghost.width >= 180
	and ghost:moveTo(630, 710).x < 630
check("drag ghost visual lifecycle", ghostOk and ghost:dispose()
	and ghost:dispose() == false)

local factoryDrag = SiK.UI.Factories.definitions.drag.create(nil, {
	data = {}, capabilities = { ["drag.ghost"] = {
		rows = { { name = "Factory row" } }, ["max-visible"] = 3,
	} },
}, { playerNum = 0 })
local factoryGhostOk = factoryDrag and factoryDrag.ghost
	and factoryDrag.ghost._sikVisualOnly == true
factoryDrag:cancel("test")
check("drag factory wires neutral ghost", factoryGhostOk)
end
testDragGhostContracts()

local function testCardAndFormContracts()
local cardActivated = false
local card = SiK.UI.Card.create({ parent = parent, title = "Card", value = "42",
        description = "Atomic final content", status = "Ready", w = 280, h = 120,
        payload = { id = "card-1" }, onActivate = function(payload)
                cardActivated = payload and payload.id == "card-1"
        end })
check("card is atomic final content", card and card.panel and card.data.title == "Card"
        and card.data.value == "42" and card.block == nil and card.scroll == nil
        and card.content == nil and card.childParent == nil)
card.panel:onMouseUp(0, 0)
check("card activation uses stable payload", cardActivated == true)
card:setData({ title = "Updated", value = 7, locked = true })
check("card updates named slots", card.data.title == "Updated"
        and card.data.value == "7" and card.data.locked == true)
card:reflow({ x = 10, y = 20, w = 320, h = 160 })
check("card follows declarative reflow", card.panel.x == 10 and card.panel.y == 20
        and card.panel.width == 320 and card.panel.height == 160)
local cardPanel = card.panel
check("card panel destroy owns cleanup", cardPanel:destroy()
        and cardPanel._sikCardInstance == nil and cardPanel:destroy() == false)
check("card dispose idempotent", card:dispose() == false)

local collection = SiK.UI.CardCollection.create({ parent = parent, width = 600,
	items = { { title = "One" }, { title = "Two" } }, bounds = { x = 0, y = 0, w = 600, h = 300 } })
check("card collection responsive", collection and collection.columns == 2)
collection:dispose()

local processActivated = false
local processCollection = SiK.UI.CardCollection.create({ parent = parent,
	cardHeight = 148, columns = 2, exactColumns = true,
	items = { { variant = "process", title = "Program", description = "Purpose",
		requirement = { text = "Requirement" }, actionLabel = "Run", payload = { id = "run" },
		action = function(payload) processActivated = payload and payload.id == "run" end } },
	bounds = { x = 0, y = 0, w = 600, h = 300 } })
local processCard = processCollection and processCollection.cards[1]
check("process card exposes a framework action slot", processCard
	and processCard.actionButton and processCard.data.actionLabel == "Run"
	and processCard.data.requirement.text == "Requirement")
local processMetrics = SiK.UI.Card.metrics("process")
check("process card keeps validated inner spacing", processMetrics.padding == 12
	and processMetrics.gap == 10 and processMetrics.minHeight == 156)
processCard.requirementRow:setData({ text = string.rep("Long learned recipe requirement ", 8) })
processCard.requirementRow:setHeight(1)
processCard:reflow({ x = 0, y = 0, w = 280, h = 156 })
local processBodyTop = processMetrics.padding + processMetrics.headerHeight + processMetrics.gap
local processBodyBottom = processCard.actionButton.y - processMetrics.gap
check("process requirement reflows before final placement",
	processCard.requirementRow.height > 1
	and processCard.requirementRow.y >= processBodyTop
	and processCard.requirementRow.y + math.min(processCard.requirementRow.height,
		processBodyBottom - processBodyTop) <= processBodyBottom)
processCard.actionButton:onMouseDown(1, 1)
processCard.actionButton:onMouseUp(1, 1)
check("card collection forwards process action payload", processActivated == true)
processCollection:dispose()

local form = SiK.UI.Form.create({ parent = parent, width = 300,
	fields = { { key = "name", label = "Name", default = "",
		validate = function(value) return value ~= "", "required" end },
		{ key = "active", label = "Active", type = "toggle", default = true } } })
local valid, errors = form:validate()
form:setValue("name", "value")
local validAfter = form:validate()
check("form typed validation", not valid and errors.name == "required" and validAfter == true)
form:dispose(); check("form dispose idempotent", form:dispose() == false)
end
testCardAndFormContracts()

local function testProductLeakContract()
local ownedFiles = { "Namespace", "Theme", "Icon", "Controls", "Window", "Modal",
        "Tabs", "Tooltip", "Menu", "Popover", "Drag", "DragGhost", "DropTarget",
        "WorldPicker", "Lifecycle", "FocusStack", "Layout", "Container", "Navigation",
        "Collection", "ActionGroup", "Card", "CardCollection", "Form" }
local productLeak = false
for index = 1, #ownedFiles do
	local file = assert(io.open(root .. "SiK/UI/" .. ownedFiles[index] .. ".lua", "rb"))
	local source = file:read("*a"); file:close()
	if source:find("GlobalStorageSiK", 1, true) or source:find("GSSiK", 1, true)
		or source:find("IGUI_GS", 1, true) then productLeak = true end
end
check("no product namespace or i18n leak", not productLeak)
end
testProductLeakContract()

io.write(string.format("RESULT %d passed, %d failed\n", passed, failed))
if failed > 0 then os.exit(1) end
