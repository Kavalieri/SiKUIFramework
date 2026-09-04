require "SiK/UI/Namespace"
require "SiK/UI/Diagnostics"
require "SiK/UI/Lifecycle"
require "SiK/UI/StateMachine"
require "SiK/UI/Version"
require "SiK/UI/Surface"
require "SiK/UI/Builder"
require "SiK/UI/Container"
require "SiK/UI/Collection"
require "SiK/UI/ActionGroup"
require "SiK/UI/Block"
require "SiK/UI/Card"
require "SiK/UI/CardCollection"
require "SiK/UI/Factories"
require "SiK/UI/Capabilities"
require "SiK/UI/Feedback"
require "SiK/UI/Popover"
require "SiK/UI/DropTarget"
require "SiK/UI/WorldPicker"

local UI = SiK.UI

function UI.bootstrap()
	if UI._runtimeBootstrapped then return true end
	local ok, err = UI.Factories.registerDefaults()
	if not ok then return nil, err end
	ok, err = UI.Capabilities.registerDefaults()
	if not ok then return nil, err end
	UI._runtimeBootstrapped = true
	return true
end

function UI.validateSurface(spec)
	local ok, err = UI.bootstrap()
	if not ok then return nil, err end
	return UI.Surface.validate(spec)
end

function UI.buildSurface(parent, spec, context)
	local ok, err = UI.bootstrap()
	if not ok then return nil, err end
	return UI.Builder.build(parent, spec, context)
end

require "SiK/UI/SurfaceHost"

UI.bootstrap()

return UI
