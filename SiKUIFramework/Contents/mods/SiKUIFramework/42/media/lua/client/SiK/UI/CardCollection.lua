require "SiK/UI/Namespace"
require "SiK/UI/Card"
require "SiK/UI/Collection"
require "SiK/UI/Controls"
require "SiK/UI/Layout"

local CardCollection = SiK.UI.CardCollection or {}
SiK.UI.Namespace.define("CardCollection", CardCollection)

local function normalizedItems(items, options)
	local out = {}
	for index = 1, #(items or {}) do
		local source, item = items[index], {}
		for key, value in pairs(source) do item[key] = value end
		local variant = item.variant or options.cardVariant
		item.height = item.height or options.cardHeight or SiK.UI.Card.metrics(variant).minHeight
		out[index] = item
	end
	return out
end

-- Typed convenience preset over the generic Collection. It repeats atomic
-- Cards and adds no product vocabulary or alternate layout engine.
function CardCollection.create(options)
	options = options or {}
	if type(options.parent) ~= "table" then return nil, "invalid_parent" end
	local owner = options.parent
	local bounds = SiK.UI.Layout.resolveRect(options.bounds or {
		x = options.x or 0, y = options.y or 0,
		w = options.w or options.width or 1,
		h = options.h or options.height or 1,
	}, nil, 1)
	local panel = SiK.UI.Controls.panel(owner, {
		x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h,
		controlId = options.controlId or "card-collection",
		playerNum = options.playerNum,
	})
	panel.clipChildren = true
	local collectionOptions = {}
	for key, value in pairs(options) do collectionOptions[key] = value end
	collectionOptions.parent = panel
	collectionOptions.bounds = { x = 0, y = 0, w = bounds.w, h = bounds.h }
	collectionOptions.items = normalizedItems(options.items, options)
	collectionOptions.minItemWidth = options.minCardWidth or options.minItemWidth
	collectionOptions.itemHeight = options.cardHeight or options.itemHeight
	-- Keep the public CardCollection contract explicit even though Collection
	-- also applies the same safe default. Declarative consumers can therefore
	-- configure the column ceiling without relying on an implementation detail.
	collectionOptions.maxColumns = options.maxColumns
	collectionOptions.itemFactory = function(parent, item)
		return SiK.UI.Card.create({
			parent = parent, x = 0, y = 0, w = 1,
			h = item.height or options.cardHeight or 120,
			variant = item.variant or options.cardVariant,
			title = item.title, text = item.text,
			icon = item.icon or item.texture,
			value = item.value, description = item.description,
			requirement = item.requirement, actionLabel = item.actionLabel,
			status = item.status or item.statusLabel,
			statusTone = item.statusTone or item.tone,
			swatches = item.swatches, selected = item.selected == true,
			actions = item.actions, locked = item.locked,
			tooltip = item.tooltip, tooltipPlacement = item.tooltipPlacement,
			payload = item.payload,
			onActivate = item.action or item.onActivate or options.onActivate,
			playerNum = options.playerNum, theme = options.theme,
		})
	end
	local instance, err = SiK.UI.Collection.create(collectionOptions)
	if not instance then
		if owner.removeChild then owner:removeChild(panel) end
		return nil, err
	end
	instance.panel = panel
	instance.childParent = panel
	instance.cards = instance.entries
	local clear = instance.clear
	function instance:clear()
		local result = clear(self); self.cards = self.entries; return result
	end
	local setItems = instance.setItems
	function instance:setItems(items)
		local result, reason = setItems(self, normalizedItems(items, options)); self.cards = self.entries
		return result, reason
	end
	local reflow = instance.reflow
	function instance:reflow(nextBounds)
		if self.disposed then return nil, "disposed" end
		nextBounds = SiK.UI.Layout.resolveRect(nextBounds or bounds, bounds, 1)
		bounds = nextBounds
		SiK.UI.Layout.apply(self.panel, nextBounds)
		return reflow(self, { x = 0, y = 0, w = nextBounds.w, h = nextBounds.h })
	end
	local dispose = instance.dispose
	function instance:dispose()
		if self.disposed then return false end
		local target = self.panel
		local result = dispose(self)
		if target and owner.removeChild then owner:removeChild(target) end
		self.panel, self.childParent = nil, nil
		return result
	end
	panel._sikCardCollectionInstance = instance
	instance:reflow(bounds)
	return instance
end

return CardCollection
