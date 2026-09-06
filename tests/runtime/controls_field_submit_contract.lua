local T = require "tests/geometry/pz_ui_stub"
local Controls = require "SiK/UI/Controls"

local query, active = Controls.effectiveSearchQuery("ab")
T.eq(query, nil, "regular two-character search is not effective")
T.eq(active, false, "regular threshold reports inactive")
query, active = Controls.effectiveSearchQuery("abc")
T.eq(query, "abc", "regular three-character search is effective")
T.eq(active, true, "regular threshold reports active")
query, active = Controls.effectiveSearchQuery("中文")
T.eq(query, "中文", "wide UTF-8 text uses the two-character threshold")
T.eq(active, true, "wide UTF-8 threshold reports active")

local parent = T.panel(320, 120)
local submissions = {}
local payload = { id = "field-payload" }
local field = Controls.field(parent, {
        x = 8, y = 8, w = 220,
        text = "initial",
        playerNum = 2,
	payload = payload,
	onSubmit = function(context)
		submissions[#submissions + 1] = context
		return "submitted"
	end,
})

-- Editable belongs to the native text child, never to the padded panel.
-- The companion field_native_identity_contract covers the native parent graph.
T.ok(field.entry.javaObject ~= nil, "text child completes the vanilla instantiate lifecycle")
T.eq(field.entry.javaObject.editable, true, "enabled field applies editable after instantiate")

local disabled = Controls.field(parent, { enabled = false })
T.eq(disabled.entry.javaObject.editable, false, "disabled field applies editable after instantiate")
disabled:dispose()

field:setText("value from enter")
local result = field:onPressEnter()
T.eq(result, "submitted", "Enter returns the onSubmit result")
T.eq(#submissions, 1, "Enter invokes onSubmit exactly once")
T.eq(submissions[1].event, "onSubmit", "Enter publishes the submit event")
T.eq(submissions[1].value, "value from enter", "Enter submits the current field value")
T.eq(submissions[1].component, field, "Enter identifies the field component")
T.eq(submissions[1].playerNum, 2, "Enter preserves player ownership")
T.eq(submissions[1].payload, payload, "Enter preserves caller payload")

field:dispose()

return true
