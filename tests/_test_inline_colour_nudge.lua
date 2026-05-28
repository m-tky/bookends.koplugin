-- Regression test for issue #57: inline custom-colour nudge stacked dialogs.
--
-- The inline `%bar` line editor reuses _buildColorItems for its Custom
-- colours list. When a colour row opens a nudge dialog, the colour list
-- must reopen when that nudge CLOSES, not on every +/- increment. The
-- original bug wired the reopen to the per-change save callback (which
-- showNudgeDialog fires on every increment), so each tap stacked a fresh
-- colour list on top of the still-open nudge.
--
-- Usage: lua tests/_test_inline_colour_nudge.lua

package.loaded["bookends_i18n"] = { gettext = function(s) return s end }
package.loaded["device"] = { screen = { isColorEnabled = function() return false end } }
package.loaded["bookends_colour"] = {
    defaultHexFor = function() return "#000000" end,
    toStorageShape = function(h) return { hex = h } end,
}

local attach = dofile("menu/colours_menu.lua")

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

test("greyscale colour nudge reopens on close, not per change (issue #57)", function()
    local Bookends = {}
    attach(Bookends)

    -- Capture how _buildColorItems wires the nudge callbacks.
    local captured = {}
    function Bookends:showNudgeDialog(title, value, min, max, def, unit, on_change, on_close)
        captured.on_change = on_change
        captured.on_close = on_close
    end

    local saveCount, reopenCount = 0, 0
    local bc = {}
    local items = Bookends:_buildColorItems(bc,
        function() saveCount = saveCount + 1 end,   -- persist + live preview
        function() reopenCount = reopenCount + 1 end) -- on_reopen (reopen colour list)

    -- First row is "Progress bar colour"; tapping it (no touchmenu_instance)
    -- opens the greyscale nudge.
    items[1].callback(nil)
    assert(captured.on_change, "nudge on_change must be wired")
    assert(captured.on_close, "nudge on_close (reopen hook) must be wired")

    -- Three +/- increments: persists each time, but must NOT reopen the list.
    captured.on_change(80)
    captured.on_change(81)
    captured.on_change(82)
    eq(reopenCount, 0, "must NOT reopen the colour list on value change")
    assert(saveCount >= 3, "each value change should persist")

    -- Closing the nudge reopens the colour list exactly once.
    captured.on_close()
    eq(reopenCount, 1, "reopen exactly once when the nudge closes")
end)

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
