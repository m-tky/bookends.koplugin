-- Unit tests for [font=Name]…[/font] inline styling in
-- OverlayWidget.parseStyledSegments (issue #62).
-- Pure-Lua: stubs the KOReader/ffi modules the overlay widget requires at
-- load, then dofiles it and exercises the parser directly.
-- Usage: cd into the plugin dir, then `lua tests/_test_font_tag.lua`.

-- ---- Stubs (overlay widget only executes ffi.typeof + Device.screen at load) -
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

-- ---- Tiny harness -----------------------------------------------------------
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
-- Return only the text-bearing segments (drop bars), for stable indexing.
local function textSegs(text, bold, italic, upper)
    local segs = parse(text, bold or false, italic or false, upper or false, nil)
    if not segs then return nil end
    local out = {}
    for _, s in ipairs(segs) do if not s.bar then out[#out + 1] = s end end
    return out
end

-- ============================================================================
-- Baseline: existing [b]/[c] behaviour must keep working after the change.
-- ============================================================================
test("baseline: [b]x[/b] sets bold", function()
    local s = textSegs("[b]x[/b]")
    assert(s, "expected segments")
    eq(#s, 1, "segment count"); eq(s[1].text, "x"); eq(s[1].bold, true)
end)

-- ============================================================================
-- [font=Name] support (issue #62)
-- ============================================================================
test("single [font=Name] span attaches font to segment", function()
    local s = textSegs("[font=Noto Sans]hi[/font]")
    assert(s, "expected segments, got nil")
    eq(#s, 1, "segment count"); eq(s[1].text, "hi"); eq(s[1].font, "Noto Sans")
end)

test("text outside the span has no font", function()
    local s = textSegs("[font=A]x[/font]y")
    assert(s, "expected segments")
    eq(#s, 2, "segment count")
    eq(s[1].text, "x"); eq(s[1].font, "A")
    eq(s[2].text, "y"); eq(s[2].font, nil)
end)

test("nested [font] — innermost wins, outer restored on close", function()
    local s = textSegs("[font=A]x[font=B]y[/font]z[/font]")
    assert(s, "expected segments")
    eq(#s, 3, "segment count")
    eq(s[1].text, "x"); eq(s[1].font, "A")
    eq(s[2].text, "y"); eq(s[2].font, "B")
    eq(s[3].text, "z"); eq(s[3].font, "A")
end)

test("font name with spaces is read whole and trimmed", function()
    local s = textSegs("[font=  BIZ UDPMincho  ]x[/font]")
    assert(s, "expected segments")
    eq(s[1].font, "BIZ UDPMincho")
end)

test("[font] composes with [b]", function()
    local s = textSegs("[font=A][b]x[/b][/font]")
    assert(s, "expected segments")
    eq(s[1].text, "x"); eq(s[1].font, "A"); eq(s[1].bold, true)
end)

test("[font] composes with [c=N] colour", function()
    local s = textSegs("[font=A][c=50]x[/c][/font]")
    assert(s, "expected segments")
    eq(s[1].text, "x"); eq(s[1].font, "A")
    assert(s[1].color, "expected colour on segment")
end)

test("mismatched [/font] with empty stack → nil (plain text)", function()
    local segs = parse("x[/font]", false, false, false, nil)
    eq(segs, nil, "expected nil")
end)

test("unclosed [font] → nil (plain text)", function()
    local segs = parse("[font=A]x", false, false, false, nil)
    eq(segs, nil, "expected nil")
end)

-- ----------------------------------------------------------------------------
io.write(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
