require "SiK/UI/Namespace"

local Icon = SiK.UI.Icon or {}
SiK.UI.Namespace.define("Icon", Icon)

local entries = Icon._entries or {}
local cache = Icon._cache or {}
Icon._entries = entries
Icon._cache = cache

function Icon.register(key, source)
	if type(key) ~= "string" or key == "" then return nil, "invalid_icon_key" end
	if type(source) ~= "string" and type(source) ~= "function"
		and type(source) ~= "table" and type(source) ~= "userdata" then
		return nil, "invalid_icon_source"
	end
	entries[key] = source
	cache[key] = nil
	local handle = { key = key, source = source }
	function handle:dispose()
		if self.disposed then return false end
		self.disposed = true
		if entries[self.key] == self.source then entries[self.key] = nil end
		cache[self.key] = nil
		return true
	end
	return handle
end

function Icon.resolve(keyOrTexture)
	if keyOrTexture == nil then return nil end
	local source = keyOrTexture
	local cacheKey = nil
	if type(keyOrTexture) == "string" then
		cacheKey = keyOrTexture
		if cache[cacheKey] ~= nil then return cache[cacheKey] or nil end
		source = entries[cacheKey] or cacheKey
	elseif type(keyOrTexture) == "table" then
		-- A descriptor supplied directly by a consumer is just as valid as a
		-- registered AssetSet entry.  Returning it unchanged made PZ receive a
		-- KahluaTableImpl where drawTextureScaledAspect requires a Texture.
		-- Plain tables are still returned untouched for lightweight render-test
		-- texture sentinels that do not declare descriptor fields.
		if keyOrTexture.texture == nil and keyOrTexture.path == nil
			and keyOrTexture.source == nil then
			return keyOrTexture
		end
	else
		return keyOrTexture
	end
	local texture = nil
	if type(source) == "function" then
		local ok, value = pcall(source, keyOrTexture)
		if ok then texture = value end
	elseif type(source) == "string" and type(getTexture) == "function" then
		local ok, value = pcall(getTexture, source)
		if ok then texture = value end
	elseif type(source) == "table" then
		local value = source.texture or source.path or source.source
		if type(value) == "string" and type(getTexture) == "function" then
			local ok, resolved = pcall(getTexture, value)
			if ok then texture = resolved end
		else
			texture = value
		end
	else
		texture = source
	end
	if cacheKey then cache[cacheKey] = texture or false end
	return texture
end

--- Returns optional producer-declared dimensions for a pre-sized AssetSet entry.
function Icon.metadata(keyOrTexture)
	if type(keyOrTexture) == "string" and type(entries[keyOrTexture]) == "table" then
		return entries[keyOrTexture]
	end
	if type(keyOrTexture) == "table" then return keyOrTexture end
	return nil
end

--- Draws a final asset at native dimensions only. This deliberately refuses
--- slot mismatches instead of hiding transparent margins with consumer scaling.
function Icon.drawExact(target, keyOrTexture, x, y, width, height, options)
	local meta = Icon.metadata(keyOrTexture)
	if type(meta) ~= "table" or tonumber(meta.width) ~= tonumber(width)
		or tonumber(meta.height) ~= tonumber(height) then
		return false, "asset_slot_mismatch"
	end
	-- Kahlua exposes inherited ISUIElement methods as callable members whose
	-- reported Lua type is not consistently `function`. Presence is the stable
	-- capability check used by the rest of the framework.
	if type(target) ~= "table" or (not target.drawTextureScaled
		and not target.drawTexture) then
		return false, "unsupported_native_renderer"
	end
	local texture = Icon.resolve(keyOrTexture)
	if not texture then return false, "missing_texture" end
	options = options or {}
	-- Exact means native: once producer dimensions match the slot, never route
	-- the asset through a scaling API. This preserves an authored bitmap
	-- byte-for-pixel. Scaling remains only as a compatibility fallback for a
	-- target that genuinely lacks the native overload.
	if target.drawTexture then
		target:drawTexture(texture, x, y, tonumber(options.alpha) or 1,
			 tonumber(options.r) or 1, tonumber(options.g) or 1,
			 tonumber(options.b) or 1)
	else
		target:drawTextureScaled(texture, x, y, width, height,
			tonumber(options.alpha) or 1, tonumber(options.r) or 1,
			 tonumber(options.g) or 1, tonumber(options.b) or 1)
	end
	return true
end

--- Draws a pre-sized asset around its native centre without resampling its
--- source canvas. Rotation is the only transform: dimensions must still match
--- the registered AssetSet entry exactly.
function Icon.drawRotatedExact(target, keyOrTexture, x, y, width, height, angle)
	local meta = Icon.metadata(keyOrTexture)
	if type(meta) ~= "table" or tonumber(meta.width) ~= tonumber(width)
		or tonumber(meta.height) ~= tonumber(height) then
		return false, "asset_slot_mismatch"
	end
	if type(target) ~= "table" or not target.DrawTextureAngle then
		return false, "unsupported_native_rotation"
	end
	local texture = Icon.resolve(keyOrTexture)
	if not texture then return false, "missing_texture" end
	target:DrawTextureAngle(texture, x + width / 2, y + height / 2,
		tonumber(angle) or 0)
	return true
end

function Icon.draw(target, keyOrTexture, x, y, width, height, options)
	if type(target) ~= "table" then return false, "invalid_target" end
	local texture = Icon.resolve(keyOrTexture)
	if not texture then return false, "missing_texture" end
	options = options or {}
	local alpha = tonumber(options.alpha) or 1
	local r, g, b = tonumber(options.r) or 1, tonumber(options.g) or 1,
		tonumber(options.b) or 1
	if options.aspect ~= false and target.drawTextureScaledAspect then
		target:drawTextureScaledAspect(texture, x, y, width, height, alpha, r, g, b)
	elseif target.drawTextureScaled then
		target:drawTextureScaled(texture, x, y, width, height, alpha, r, g, b)
	else
		return false, "unsupported_renderer"
	end
	return true
end

function Icon.clearCache(key)
	if key then cache[key] = nil else cache = {}; Icon._cache = cache end
end

-- Framework-owned symbols are final, pre-sized files. Consumers reference a
-- semantic key and never crop, stretch or compensate transparent margins.
local builtins = {
	["sik.info.24"] = { path = "media/ui/SiKUIFramework/SiK_Icon_Info_24.png", width = 24, height = 24 },
	["sik.check.18"] = { path = "media/ui/SiKUIFramework/SiK_Icon_Check_18.png", width = 18, height = 18 },
	["sik.close.18"] = { path = "media/ui/SiKUIFramework/SiK_Icon_Close_18.png", width = 18, height = 18 },
	["sik.search.18"] = { path = "media/ui/SiKUIFramework/SiK_Icon_Search_18.png", width = 18, height = 18 },
	["sik.arrow.right.14"] = { path = "media/ui/SiKUIFramework/SiK_Icon_ArrowRight_14.png", width = 14, height = 14 },
	["sik.arrow.down.14"] = { path = "media/ui/SiKUIFramework/SiK_Icon_ArrowDown_14.png", width = 14, height = 14 },
	["sik.alert.warning.24"] = { path = "media/ui/SiKUIFramework/SiK_Icon_AlertWarning_24.png", width = 24, height = 24 },
	["sik.alert.danger.24"] = { path = "media/ui/SiKUIFramework/SiK_Icon_AlertDanger_24.png", width = 24, height = 24 },
}
for key, source in pairs(builtins) do
	if entries[key] == nil then Icon.register(key, source) end
end

return Icon
