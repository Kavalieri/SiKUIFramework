require "SiK/UI/Namespace"

local Version = SiK.UI.Version or {
	major = 1,
	minor = 0,
	patch = 2,
	stage = "dev1.5",
}

function Version.string()
	local base = tostring(Version.major) .. "." .. tostring(Version.minor)
		.. "." .. tostring(Version.patch)
	if Version.stage and Version.stage ~= "" then
		return base .. "-" .. tostring(Version.stage)
	end
	return base
end

function Version.atLeast(major, minor, patch)
	major = math.floor(tonumber(major) or 0)
	minor = math.floor(tonumber(minor) or 0)
	patch = math.floor(tonumber(patch) or 0)
	if Version.major ~= major then return Version.major > major end
	if Version.minor ~= minor then return Version.minor > minor end
	return Version.patch >= patch
end

SiK.UI.Namespace.define("Version", Version)

return Version
