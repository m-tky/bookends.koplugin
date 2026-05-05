-- Pure-Lua test for OverlayWidget.computeEndFillExtents.
-- Run: cd into the plugin dir, then `lua tests/_test_overlay_fill.lua`.
package.loaded["ffi"] = {
    typeof = function() return function() return {} end end,
    istype = function() return false end,
}
package.loaded["ffi/blitbuffer"] = {
    ColorRGB32 = function() return {} end,
    Color8 = function() return {} end,
}
package.loaded["ffi/utf8proc"] = {}
package.loaded["device"] = { screen = { scaleBySize = function(_, n) return n end, isColorEnabled = function() return false end, getSize = function() return {w=600,h=800} end } }
package.loaded["ui/font"] = { fontmap = {} }
package.loaded["ui/widget/textwidget"] = {}
package.loaded["bookends_colour"] = { parseColorValue = function() return nil end }

local OverlayWidget = dofile("bookends_overlay_widget.lua")

local pass, fail = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1
    else fail = fail + 1; io.stderr:write("FAIL  " .. name .. "\n  " .. tostring(err) .. "\n") end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected=" .. tostring(b) .. " got=" .. tostring(a), 2) end
end

local SCREEN_H = 800

local function pos(height_px, v_offset, v_margin, disabled)
    return { height_px = height_px or 0,
             v_offset = v_offset or 0, v_margin = v_margin or 0,
             disabled = disabled or false }
end

test("all six empty: no fill on either end", function()
    local r = OverlayWidget.computeEndFillExtents({
        tl = pos(0), tc = pos(0), tr = pos(0),
        bl = pos(0), bc = pos(0), br = pos(0),
    }, SCREEN_H)
    eq(r.top_any_enabled, false)
    eq(r.bottom_any_enabled, false)
    eq(r.top_y, 0)
    eq(r.bottom_y, SCREEN_H)
end)

test("top has 1 enabled (tc, 2 lines @ 24px, 0 offset/margin): fill = 0..48", function()
    local r = OverlayWidget.computeEndFillExtents({
        tl = pos(0), tc = pos(48), tr = pos(0),
        bl = pos(0), bc = pos(0), br = pos(0),
    }, SCREEN_H)
    eq(r.top_any_enabled, true)
    eq(r.top_y, 48)
    eq(r.bottom_any_enabled, false)
end)

test("top: max across enabled positions wins", function()
    local r = OverlayWidget.computeEndFillExtents({
        tl = pos(24), tc = pos(72), tr = pos(48),
        bl = pos(0), bc = pos(0), br = pos(0),
    }, SCREEN_H)
    eq(r.top_y, 72)  -- tc has 72px height
end)

test("bottom: min y wins (max height from screen bottom)", function()
    local r = OverlayWidget.computeEndFillExtents({
        tl = pos(0), tc = pos(0), tr = pos(0),
        bl = pos(24), bc = pos(72), br = pos(48),
    }, SCREEN_H)
    eq(r.bottom_any_enabled, true)
    eq(r.bottom_y, SCREEN_H - 72)  -- bc with 72px height wins
end)

test("disabled position still contributes height (A+C rule)", function()
    -- tc has 72px disabled height, tl has 24px enabled. Fill should still be max(tl,tc) = tc's 72.
    local r = OverlayWidget.computeEndFillExtents({
        tl = pos(24, 0, 0, false), tc = pos(72, 0, 0, true), tr = pos(0),
        bl = pos(0), bc = pos(0), br = pos(0),
    }, SCREEN_H)
    eq(r.top_any_enabled, true)
    eq(r.top_y, 72)  -- tc's disabled-but-configured height counts toward fill
end)

test("all-disabled end: any_enabled is false even if height_px > 0", function()
    local r = OverlayWidget.computeEndFillExtents({
        tl = pos(48, 0, 0, true), tc = pos(0), tr = pos(24, 0, 0, true),
        bl = pos(0), bc = pos(0), br = pos(0),
    }, SCREEN_H)
    eq(r.top_any_enabled, false)
    eq(r.top_y, 48)  -- top_y is still computed from configured heights, but caller skips per top_any_enabled
end)

test("v_offset and v_margin shift the fill edge outward", function()
    local r = OverlayWidget.computeEndFillExtents({
        tl = pos(0), tc = pos(48, 5, 10), tr = pos(0),  -- 48px height + 5 offset + 10 margin
        bl = pos(0), bc = pos(0), br = pos(0),
    }, SCREEN_H)
    eq(r.top_y, 5 + 10 + 48)  -- 63
end)

-- Padding tests: the propping position contributes 0.5 × inner-edge line-height
-- as breathing room between the text and the EPUB content area.
local function pos_lh(height_px, first_line_h, last_line_h)
    return { height_px = height_px, v_offset = 0, v_margin = 0,
             disabled = false, first_line_h = first_line_h, last_line_h = last_line_h }
end

test("padding: top_y extends by 0.5 × last_line_h of the propping position", function()
    local r = OverlayWidget.computeEndFillExtents({
        tl = pos(0), tc = pos_lh(72, 30, 20), tr = pos(0),  -- last_line_h=20 → +10
        bl = pos(0), bc = pos(0), br = pos(0),
    }, SCREEN_H)
    eq(r.top_y, 72 + 10)
end)

test("padding: bottom_y extends by 0.5 × first_line_h of the propping position", function()
    local r = OverlayWidget.computeEndFillExtents({
        tl = pos(0), tc = pos(0), tr = pos(0),
        bl = pos(0), bc = pos_lh(72, 30, 20), br = pos(0),  -- first_line_h=30 → +15
    }, SCREEN_H)
    eq(r.bottom_y, SCREEN_H - 72 - 15)
end)

test("padding: tie at same edge picks the larger basis", function()
    -- Both tc and tr land at edge=72; tr's last_line_h=24 should win over tc's 12.
    local r = OverlayWidget.computeEndFillExtents({
        tl = pos(0), tc = pos_lh(72, 12, 12), tr = pos_lh(72, 24, 24),
        bl = pos(0), bc = pos(0), br = pos(0),
    }, SCREEN_H)
    eq(r.top_y, 72 + 12)  -- floor(24 * 0.5 + 0.5) = 12
end)

test("padding: positions without line-height fields default to 0 (back-compat)", function()
    -- pos() omits first_line_h / last_line_h — the helper must treat these
    -- as 0 so existing call shapes keep working.
    local r = OverlayWidget.computeEndFillExtents({
        tl = pos(0), tc = pos(48), tr = pos(0),
        bl = pos(0), bc = pos(0), br = pos(0),
    }, SCREEN_H)
    eq(r.top_y, 48)
end)

io.write(string.format("%d pass / %d fail\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
