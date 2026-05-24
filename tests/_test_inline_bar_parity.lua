-- Dev-box tests for inline-bar parity helpers and plumbing.
-- Usage: lua tests/_test_inline_bar_parity.lua

package.loaded["bookends_i18n"] = { gettext = function(s) return s end }
package.loaded["device"] = {
    getPowerDevice = function() return nil end,
    isKindle = function() return false end,
    home_dir = "/",
}

local Utils = dofile("bookends_utils.lua")

local pass, fail = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1
    else fail = fail + 1; io.stderr:write("FAIL  " .. name .. "\n  " .. tostring(err) .. "\n") end
end
local function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "")
            .. " expected=" .. string.format("%q", tostring(expected))
            .. " got=" .. string.format("%q", tostring(actual)), 2)
    end
end

-- resolveLineBarTypeAndTicks
test("type/ticks: nil -> chapter, no ticks", function()
    local t, d = Utils.resolveLineBarTypeAndTicks(nil, nil)
    eq(t, "chapter"); eq(d, nil)
end)
test("type/ticks: 'chapter' -> chapter, no ticks", function()
    local t, d = Utils.resolveLineBarTypeAndTicks("chapter", nil)
    eq(t, "chapter"); eq(d, nil)
end)
test("type/ticks: 'book' new shape, no ticks", function()
    local t, d = Utils.resolveLineBarTypeAndTicks("book", nil)
    eq(t, "book"); eq(d, nil)
end)
test("type/ticks: 'book' new shape, level1 -> depth 1", function()
    local t, d = Utils.resolveLineBarTypeAndTicks("book", "level1")
    eq(t, "book"); eq(d, 1)
end)
test("type/ticks: 'book' new shape, level2 -> depth 2", function()
    local t, d = Utils.resolveLineBarTypeAndTicks("book", "level2")
    eq(t, "book"); eq(d, 2)
end)
test("type/ticks: 'book' new shape, 'all' -> math.huge", function()
    local t, d = Utils.resolveLineBarTypeAndTicks("book", "all")
    eq(t, "book"); eq(d, math.huge)
end)
test("type/ticks: 'book' new shape, 'off' -> no ticks", function()
    local t, d = Utils.resolveLineBarTypeAndTicks("book", "off")
    eq(t, "book"); eq(d, nil)
end)
test("legacy: 'book_ticks' -> book + depth 1", function()
    local t, d = Utils.resolveLineBarTypeAndTicks("book_ticks", nil)
    eq(t, "book"); eq(d, 1)
end)
test("legacy: 'book_ticks2' -> book + depth 2", function()
    local t, d = Utils.resolveLineBarTypeAndTicks("book_ticks2", nil)
    eq(t, "book"); eq(d, 2)
end)
test("legacy: 'book_ticks_all' -> book + math.huge", function()
    local t, d = Utils.resolveLineBarTypeAndTicks("book_ticks_all", nil)
    eq(t, "book"); eq(d, math.huge)
end)
test("legacy beats new: 'book_ticks2' wins over chapter_ticks='all'", function()
    local t, d = Utils.resolveLineBarTypeAndTicks("book_ticks2", "all")
    eq(t, "book"); eq(d, 2)
end)

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
