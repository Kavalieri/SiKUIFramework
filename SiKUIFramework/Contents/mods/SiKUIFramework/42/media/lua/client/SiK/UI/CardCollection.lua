require "SiK/UI/Namespace"
require "SiK/UI/Card"
require "SiK/UI/Collection"

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
	local collectionOptions = {}
	for key, value in pairs(options) do collectionOptions[key] = value end
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
			tooltip = item.tooltip, payload = item.payload,
			onActivate = item.action or item.onActivate or options.onActivate,
			playerNum = options.playerNum, theme = options.theme,
		})
	end
	local instance, err = SiK.UI.Collection.create(collectionOptions)
	if not instance then return nil, err end
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
	return instance
end

return CardCollection
