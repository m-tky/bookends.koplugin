-- Regression test: bookends_i18n must ignore fuzzy PO entries.
--
-- After the v5.13.0 colour-string renames, msgmerge fuzzy-matched the new
-- msgids to the old translations (e.g. msgid "Bar colours" -> msgstr
-- "Border colour"). Real gettext ignores fuzzy entries, but the minimal
-- parser applied them, so en_GB titled the "Bar colours" menu "Border
-- colour" and showed stale row labels.
--
-- Usage: lua tests/_test_i18n_fuzzy.lua

package.loaded["logger"] = { info = function() end }
package.loaded["gettext"] = function(s) return s end
-- Force lang=en at require time so it doesn't try to load real locale files.
G_reader_settings = { readSetting = function() return "en" end }

local i18n = dofile("bookends_i18n.lua")
local parsePO = i18n._parsePO

local pass, fail = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1
    else fail = fail + 1; io.stderr:write("FAIL  " .. name .. "\n  " .. tostring(err) .. "\n") end
end
local function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "") .. " expected=" .. tostring(expected) .. " got=" .. tostring(actual), 2)
    end
end

local path = os.tmpname()
local f = assert(io.open(path, "w"))
f:write([[
msgid ""
msgstr ""

msgid "Border color"
msgstr "Border colour"

#, fuzzy
#| msgid "Border color"
msgid "Bar colours"
msgstr "Border colour"

#, fuzzy
#| msgid "Progress bar colors and tick marks"
msgid "Progress bar colour"
msgstr "Progress bar colours and tick marks"

msgid "Tick color"
msgstr "Tick colour"
]])
f:close()

test("fuzzy entries ignored, clean entries kept", function()
    local map = parsePO(path)
    eq(map["Border color"], "Border colour", "non-fuzzy entry must be kept")
    eq(map["Tick color"], "Tick colour", "non-fuzzy entry after a fuzzy one must be kept")
    eq(map["Bar colours"], nil, "fuzzy entry must be ignored (the title bug)")
    eq(map["Progress bar colour"], nil, "fuzzy entry must be ignored")
end)

os.remove(path)

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
