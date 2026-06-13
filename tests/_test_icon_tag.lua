-- Unit tests for [icon=NAME] inline image segments in
-- OverlayWidget.parseStyledSegments (issue #63).
-- Pure-Lua: stubs the KOReader/ffi modules the overlay widget requires at
-- load, then dofiles it and exercises the parser directly.
-- Usage: cd into the plugin dir, then `lua tests/_test_icon_tag.lua`.

package.loaded["ffi"] = {
    typeof  = function() return {} end,
    istype  = function() return false end,
}
package.loaded["ffi/blitbuffer"] = {}
package.loaded["bookends_colour"] = {
    normaliseHex    = function(h) return h end,
    parseColorValue = function() return nil end,
}
package.loaded["device"] = {
    screen = {
        isColorEnabled = function() return false end,
        getWidth       = function() return 600 end,
    },
}
package.loaded["ui/font"] = {}
package.loaded["ui/widget/textwidget"] = {}
package.loaded["ffi/utf8proc"] = { uppercase_dumb = function(s) return s:upper() end }
package.loaded["bookends_pacman_sprite"] = {}

local OverlayWidget = dofile("bookends_overlay_widget.lua")

local pass, fail = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1
    else fail = fail + 1; io.stderr:write("FAIL  " .. name .. "\n  " .. tostring(err) .. "\n") end
end
local function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "") .. " expected=" .. string.format("%q", tostring(expected))
            .. " got=" .. string.format("%q", tostring(actual)), 2)
    end
end

local parse = OverlayWidget.parseStyledSegments

test("[icon=heart] yields one icon segment, name preserved", function()
    local segs = parse("[icon=heart]", false, false, false, nil)
    assert(segs, "expected segments, got nil")
    eq(#segs, 1, "segment count")
    eq(segs[1].icon, "heart", "icon name")
    assert(segs[1].text == nil, "icon segment must carry no text")
end)

test("icon tag mixes with surrounding text", function()
    local segs = parse("a[icon=star]b", false, false, false, nil)
    assert(segs, "expected segments")
    eq(#segs, 3, "segment count")
    eq(segs[1].text, "a")
    eq(segs[2].icon, "star")
    eq(segs[3].text, "b")
end)

test("name with spaces is trimmed", function()
    local segs = parse("[icon= my-icon ]", false, false, false, nil)
    assert(segs, "expected segments")
    eq(segs[1].icon, "my-icon", "trimmed name")
end)

test("icon tag does not break [b] stack balance", function()
    local segs = parse("[b][icon=x][/b]", false, false, false, nil)
    assert(segs, "expected non-nil (tags balanced)")
end)

test("empty icon name emits no segment", function()
    -- [icon=] is swallowed (no segment, no tags found) -> parser returns nil.
    local segs = parse("[icon=]", false, false, false, nil)
    assert(segs == nil, "empty-name icon tag should not produce segments")
end)

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
