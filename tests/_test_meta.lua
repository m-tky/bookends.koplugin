-- Guards _meta.lua's `name` field. It MUST be present and equal to the plugin
-- directory id ("bookends"). Removing it (to silence the deprecation warning on
-- current KOReader) broke enable/disable on stable releases up to ~v2025.10:
-- those versions read a DISABLED plugin's name from _meta.lua, and without it
-- the enable toggle keyed plugins_disabled by a path-derived name instead of
-- "bookends", so a disabled Bookends could not be re-enabled. See _meta.lua.
-- Usage: cd into the plugin dir, then `lua tests/_test_meta.lua`.
package.loaded["bookends_i18n"] = { gettext = function(s) return s end }

local meta = dofile("_meta.lua")
assert(type(meta) == "table", "_meta.lua must return a table")
assert(meta.name == "bookends",
    "_meta.lua must set name = \"bookends\" (the .koplugin directory id) so a "
    .. "disabled plugin can be re-enabled on older KOReader; got " .. tostring(meta.name))
assert(type(meta.version) == "string", "_meta.lua must carry a version string")

print("PASS _test_meta: name == \"bookends\"")
