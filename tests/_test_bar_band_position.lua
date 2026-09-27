-- Full-width bars positioned relative to the line text ("Position relative to
-- line text" in the bar menu).
--
-- Text, and the fill band behind it, scale with the screen: KOReader's
-- scaleBySize goes by the short side / 600. A full-width bar's margin_v is raw
-- pixels. So a bar placed just under a header on one screen ends up inside the
-- text on a bigger one and out on the page on a smaller one - which is what
-- happened to the "Inverted header" preset (#76) at anything but 1072 wide.
--
-- band_offset is an optional field on the bar: its distance from the edge of
-- the text band (the edge the background fill uses), the same way at the top
-- and bottom. 0 = directly outside the band; negative = into the band; positive
-- = out towards the page. When it is absent, or the bar is vertical, or that
-- side has no text, margin_v applies exactly as before - so older bookends,
-- which ignore the field, draw the preset as they always did.
--
-- Usage: lua tests/_test_bar_band_position.lua

local function permissive()
    local t, mt = {}, nil
    mt = { __index = function() return setmetatable({}, mt) end,
           __call  = function() return setmetatable({}, mt) end }
    return setmetatable(t, mt)
end
_G.require = (function(orig)
    return function(name)
        if package.loaded[name] then return package.loaded[name] end
        local ok, mod = pcall(orig, name)
        if ok then return mod end
        local stub = permissive(); package.loaded[name] = stub; return stub
    end
end)(require)
package.loaded["device"] = { screen = permissive() }
package.loaded["bookends_i18n"] = { gettext = function(s) return s end }

local OW = dofile("bookends_overlay_widget.lua")

local pass, fail = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1
    else fail = fail + 1; io.stderr:write("FAIL  " .. name .. "\n  " .. tostring(err) .. "\n") end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected=" .. tostring(b) .. " got=" .. tostring(a), 2) end
end

-- The top band ends at 52, the bottom band starts at 1400 (screen 1448 tall).
local EXT = { top_y = 52, bottom_y = 1400, top_any_enabled = true, bottom_any_enabled = true }

-- ── top ────────────────────────────────────────────────────────────────────

test("top, offset 0: the bar sits directly below the band", function()
    eq(OW.bandBarY("top", 0, 2, EXT, 0), 52)
end)

test("top, negative offset: the bar moves up into the band", function()
    -- The #76 progress bar: 5px tall, rows 43-47 under a band ending at 52.
    eq(OW.bandBarY("top", -9, 5, EXT, 0), 43)
end)

test("top: the bar follows the band when the text is bigger", function()
    local bigger = { top_y = 60, bottom_y = 1400, top_any_enabled = true, bottom_any_enabled = true }
    eq(OW.bandBarY("top", -9, 5, bigger, 0), 51, "moved down with the band")
end)

test("top: bookshelf's reserved strip is included, as the fill includes it", function()
    eq(OW.bandBarY("top", 0, 2, EXT, 78), 130)
end)

-- ── bottom ─────────────────────────────────────────────────────────────────

test("bottom, offset 0: the bar sits directly above the band", function()
    eq(OW.bandBarY("bottom", 0, 2, EXT, 0), 1398, "occupies 1398-1399, touching the band at 1400")
end)

test("bottom, negative offset: the bar moves down into the band", function()
    eq(OW.bandBarY("bottom", -9, 5, EXT, 0), 1404)
end)

-- ── when it does not apply ─────────────────────────────────────────────────

test("no band_offset: nothing, so margin_v is used as before", function()
    eq(OW.bandBarY("top", nil, 5, EXT, 0), nil)
    eq(OW.bandBarY("bottom", nil, 5, EXT, 0), nil)
end)

test("vertical bars ignore it", function()
    eq(OW.bandBarY("left", 0, 5, EXT, 0), nil)
    eq(OW.bandBarY("right", -9, 5, EXT, 0), nil)
end)

test("a side with no text has no band, so margin_v is used", function()
    local no_top = { top_y = 0, bottom_y = 1400, top_any_enabled = false, bottom_any_enabled = true }
    eq(OW.bandBarY("top", -9, 5, no_top, 0), nil)
end)

test("no extents at all (nothing painted yet): margin_v is used", function()
    eq(OW.bandBarY("top", 0, 2, nil, 0), nil)
end)

-- ── converting, for the menu toggle ────────────────────────────────────────

test("an existing bar position converts to the offset that keeps it in place", function()
    -- Turning the option on must not make the bar jump.
    eq(OW.bandOffsetFor("top", 43, 5, EXT, 0), -9)
    eq(OW.bandOffsetFor("bottom", 1404, 5, EXT, 0), -9)
end)

test("converting and positioning round-trip", function()
    for _i, a in ipairs({ "top", "bottom" }) do
        for _j, y in ipairs({ 10, 43, 52, 60, 1390, 1404 }) do
            local off = OW.bandOffsetFor(a, y, 5, EXT, 12)
            eq(OW.bandBarY(a, off, 5, EXT, 12), y, a .. " y=" .. y)
        end
    end
end)

test("converting with no band gives nothing", function()
    local no_top = { top_y = 0, bottom_y = 1400, top_any_enabled = false, bottom_any_enabled = true }
    eq(OW.bandOffsetFor("top", 43, 5, no_top, 0), nil)
end)

print(pass .. " passed, " .. fail .. " failed")
os.exit(fail == 0 and 0 or 1)
