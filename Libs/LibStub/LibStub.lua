-- LibStub is a simple versioning stub meant for use in Libraries.
-- http://www.wowace.com/wiki/LibStub for more info
-- LibStub is hereby placed in the Public Domain
-- Credits: Kaelten, Cladhaire, ckknight, Mikk, Ammo, Nevcairiel, joshborke

local LIBSTUB_MAJOR, LIBSTUB_MINOR = "LibStub", 2 -- NEVER MAKE THIS AN SVN REVISION! IT NEEDS TO BE USABLE IN ALL REPOS!
local libstub = _G[LIBSTUB_MAJOR]

if not libstub or libstub.minor < LIBSTUB_MINOR then
	libstub = libstub or {libs = {}, minors = {} }
	_G[LIBSTUB_MAJOR] = libstub
	libstub.minor = LIBSTUB_MINOR

	function libstub:NewLibrary(major, minor)
		assert(type(major) == "string", "Bad argument #2 to `NewLibrary' (string expected)")
		minor = assert(tonumber(minor), "Bad argument #3 to `NewLibrary' (numeric minor version expected)")

		local xminor = self.minors[major]
		if xminor then
			if xminor >= minor then return end -- already loaded, no upgrade needed
		end

		self.minors[major], self.libs[major] = minor, self.libs[major] or {}
		return self.libs[major], self.libs[major]
	end

	function libstub:GetLibrary(major, silent)
		if not self.libs[major] and not silent then
			error(("Cannot find a library instance of %q."):format(tostring(major)), 2)
		end
		return self.libs[major], self.minors[major]
	end

	function libstub:IterateLibraries() return pairs(self.libs) end
	setmetatable(libstub, { __call = function(self, ...) return self:GetLibrary(...) end })
end
