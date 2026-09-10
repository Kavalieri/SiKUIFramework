require "SiK/UI/Metrics"

SiK = SiK or {}
SiK.UI = SiK.UI or {}

local Viewport = SiK.UI.Viewport or {}
SiK.UI.Namespace.define("Viewport", Viewport)

local function finite(value)
	value = tonumber(value)
	if value == nil or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

local function callNumber(callback, argument)
	if type(callback) ~= "function" then return nil end
	local ok, value = pcall(callback, argument)
	if not ok then return nil end
	return finite(value)
end

local function validRect(rect)
	if type(rect) ~= "table" then return nil end
	local x = finite(rect.x)
	local y = finite(rect.y)
	local w = finite(rect.w or rect.width)
	local h = finite(rect.h or rect.height)
	if not x or not y or not w or not h or w <= 0 or h <= 0 then return nil end
	return { x = x, y = y, w = w, h = h }
end

local function environmentRect(playerNum, environment)
	if type(environment) ~= "table" or type(environment.playerRect) ~= "function" then
		return nil
	end
	local ok, rect = pcall(environment.playerRect, playerNum)
	if not ok then return nil end
	return validRect(rect)
end

local function runtimePlayerRect(playerNum)
	local x = callNumber(getPlayerScreenLeft, playerNum)
	local y = callNumber(getPlayerScreenTop, playerNum)
	local w = callNumber(getPlayerScreenWidth, playerNum)
	local h = callNumber(getPlayerScreenHeight, playerNum)
	if x and y and w and h and w > 0 and h > 0 then
		return { x = x, y = y, w = w, h = h }
	end
	return nil
end

local function runtimeScreenRect(environment)
	if type(environment) == "table" and type(environment.screenRect) == "function" then
		local ok, rect = pcall(environment.screenRect)
		if ok then
			local valid = validRect(rect)
			if valid then return valid end
		end
	end
	local core = nil
	if type(getCore) == "function" then
		local ok, resolved = pcall(getCore)
		if ok then core = resolved end
	end
	local width = core and callNumber(function() return core:getScreenWidth() end) or nil
	local height = core and callNumber(function() return core:getScreenHeight() end) or nil
	if not width and type(getPlayerScreenWidth) == "function" then
		width = callNumber(getPlayerScreenWidth, 0)
	end
	if not height and type(getPlayerScreenHeight) == "function" then
		height = callNumber(getPlayerScreenHeight, 0)
	end
	return { x = 0, y = 0, w = width or 1280, h = height or 720 }
end

function Viewport.resolve(playerNum, environment)
	playerNum = math.max(0, math.floor(tonumber(playerNum) or 0))
	return environmentRect(playerNum, environment)
		or runtimePlayerRect(playerNum)
		or runtimeScreenRect(environment)
end

function Viewport.safe(playerNum, environment, margin)
	local rect = Viewport.resolve(playerNum, environment)
	margin = math.max(0, tonumber(margin) or SiK.UI.Metrics.safeMargin)
	return {
		x = rect.x + margin,
		y = rect.y + margin,
		w = math.max(0, rect.w - margin * 2),
		h = math.max(0, rect.h - margin * 2),
	}
end

function Viewport.clamp(rect, playerNum, environment, margin)
	local safe = Viewport.safe(playerNum, environment, margin)
	local width = math.min(math.max(0, tonumber(rect and (rect.w or rect.width)) or 0), safe.w)
	local height = math.min(math.max(0, tonumber(rect and (rect.h or rect.height)) or 0), safe.h)
	local x = tonumber(rect and rect.x) or safe.x
	local y = tonumber(rect and rect.y) or safe.y
	x = math.max(safe.x, math.min(x, safe.x + safe.w - width))
	y = math.max(safe.y, math.min(y, safe.y + safe.h - height))
	return { x = x, y = y, w = width, h = height }
end

-- A dragged window may extend past a horizontal edge, but retains a small
-- reachable header grip. Ordinary surfaces keep using clamp(), which remains
-- strict. The grip deliberately does not force the close control on screen:
-- players may park almost the whole window outside the viewport and recover it
-- by dragging the visible header strip.
function Viewport.clampAccessible(rect, playerNum, environment, margin, access)
	local safe = Viewport.safe(playerNum, environment, margin)
	local width = math.min(math.max(0, tonumber(rect and (rect.w or rect.width)) or 0), safe.w)
	local height = math.min(math.max(0, tonumber(rect and (rect.h or rect.height)) or 0), safe.h)
	local x = tonumber(rect and rect.x) or safe.x
	local y = tonumber(rect and rect.y) or safe.y
	access = type(access) == "table" and access or {}
	local headerH = math.max(1, math.min(height, finite(access.headerHeight) or 1))
	local headerW = math.max(1, math.min(width, finite(access.headerWidth) or 32))
	local minX = safe.x - width + headerW
	local maxX = safe.x + safe.w - headerW
	if minX > maxX then minX, maxX = safe.x, safe.x + safe.w - width end
	x = math.max(minX, math.min(x, maxX))
	y = math.max(safe.y, math.min(y, safe.y + safe.h - headerH))
	return { x = x, y = y, w = width, h = height }
end

return Viewport
