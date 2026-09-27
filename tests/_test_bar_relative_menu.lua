-- The bar menu's "Position relative to line text" toggle, and "Adjust margins"
-- while it is on. The position rule itself is in _test_bar_band_position; these
-- drive the real menu module against the paint's own computeBarRect.
--
-- What must hold:
--   - switching it on or off never moves the bar on screen;
--   - it can't be switched on for a side with no text, or for a vertical bar;
--   - while it is on, Adjust margins edits band_offset, which may go negative,
--     and margin_v is kept equal to where the bar is now, so an older bookends
--     (which ignores band_offset) draws it in the same place on this screen;
--   - changing the anchor clears it, since an offset from one band means
--     nothing against the other.
--
-- Usage: lua tests/_test_bar_relative_menu.lua

local function permissive()
    local t, mt = {}, nil
    mt = { __index = function() return setmetatable({}, mt) end,
           __call  = function() return setmetatable({}, mt) end }
    return setmetatable(t, mt)
end
local SCREEN_W, SCREEN_H = 1072, 1448
package.loaded["bookends_colour"] = { parseColorValue = function(v) return v end,
                                      toStorageShape = function(x) return x end }
package.loaded["device"] = { screen = {
    isColorEnabled = function() return false end,
    getWidth = function() return SCREEN_W end,
    getHeight = function() return SCREEN_H end,
} }
package.loaded["ui/widget/container/widgetcontainer"] = {
    extend = function(s, t) t = t or {}; return setmetatable(t, { __index = s }) end,
    new    = function(s, t) return setmetatable(t or {}, { __index = s }) end,
}
package.loaded["bookends_i18n"] = { gettext = function(s) return s end }
package.loaded["bookends_tokens"] = permissive()

-- The margins dialog, captured rather than shown.
local grid
package.loaded["bookends_dialog_helpers"] = { showNudgeGrid = function(opts) grid = opts end }

_G.require = function(name)
    if package.loaded[name] then return package.loaded[name] end
    local stub = permissive(); package.loaded[name] = stub; return stub
end
_G.G_reader_settings = permissive()
package.loaded["bookends_overlay_widget"] = dofile("bookends_overlay_widget.lua")
package.loaded["bookends_utils"] = dofile("bookends_utils.lua")   -- the real cycleNext

local Bookends = dofile("main.lua")
dofile("menu/progress_bar_menu.lua")(Bookends)

local pass, fail = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1
    else fail = fail + 1; io.stderr:write("FAIL  " .. name .. "\n  " .. tostring(err) .. "\n") end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected=" .. tostring(b) .. " got=" .. tostring(a), 2) end
end

-- A band ending at 52 at the top, starting at 1400 at the bottom.
local EXT = { top_y = 52, bottom_y = 1400, top_any_enabled = true, bottom_any_enabled = true }

local function instance(bar_cfg, extents)
    local inst = setmetatable({}, { __index = Bookends })
    inst.settings = { saveSetting = function() end }
    inst.markDirty = function() end
    inst._band_extents = extents
    inst._bs_strip_h = 0
    local items = inst:buildSingleBarMenu(1, bar_cfg)
    local by = {}
    for _i, it in ipairs(items) do
        local label = it.text or (it.text_func and it.text_func()) or ""
        by[label:match("^[^(:]+"):gsub("%s+$", "")] = it
    end
    return inst, by
end
local function y_of(bar_cfg, extents)
    local _x, y = Bookends._computeBarRect(bar_cfg, 0, 0, SCREEN_W, SCREEN_H, 0, extents)
    return y
end

test("the menu has a Position relative to line text toggle", function()
    local _i, by = instance({ enabled = true, v_anchor = "top", margin_v = 43, height = 5 }, EXT)
    assert(by["Position relative to line text"], "toggle missing")
end)

test("switching it on keeps the bar exactly where it was", function()
    local bar = { enabled = true, v_anchor = "top", margin_v = 43, height = 5 }
    local _i, by = instance(bar, EXT)
    local before = y_of(bar, EXT)
    by["Position relative to line text"].callback()
    eq(bar.band_offset, -9, "offset from the band edge at 52")
    eq(y_of(bar, EXT), before, "the bar moved")
end)

test("switching it off keeps the bar where it was, back on margin_v", function()
    local bar = { enabled = true, v_anchor = "top", margin_v = 0, height = 5, band_offset = -9 }
    local _i, by = instance(bar, EXT)
    local before = y_of(bar, EXT)
    by["Position relative to line text"].callback()
    eq(bar.band_offset, nil)
    eq(bar.margin_v, 43, "margin_v now holds the position")
    eq(y_of(bar, EXT), before, "the bar moved")
end)

test("it reads as on when band_offset is set", function()
    local _i, by = instance({ enabled = true, v_anchor = "top", margin_v = 0, height = 5, band_offset = 0 }, EXT)
    eq(by["Position relative to line text"].checked_func(), true)
end)

test("it can't be switched on with no text on the bar's side", function()
    local no_top = { top_y = 0, bottom_y = 1400, top_any_enabled = false, bottom_any_enabled = true }
    local _i, by = instance({ enabled = true, v_anchor = "top", margin_v = 43, height = 5 }, no_top)
    eq(by["Position relative to line text"].enabled_func(), false)
end)

test("it can't be switched on for a vertical bar", function()
    local _i, by = instance({ enabled = true, v_anchor = "left", margin_v = 10, height = 5 }, EXT)
    eq(by["Position relative to line text"].enabled_func(), false)
end)

test("while on, Adjust margins edits band_offset and allows negative", function()
    local bar = { enabled = true, v_anchor = "top", margin_v = 43, height = 5, band_offset = -9 }
    local inst, by = instance(bar, EXT)
    grid = nil
    by["Adjust margins"].callback()
    assert(grid, "the margins dialog did not open")
    eq(grid.rows[1].field, "band_offset", "first row should edit the offset")
    assert(grid.rows[1].min_val and grid.rows[1].min_val < 0, "the offset row must allow negative values")
    grid.set_value("band_offset", -12)
    eq(bar.band_offset, -12)
    eq(bar.margin_v, 40, "margin_v follows, for older versions")
end)

test("while off, Adjust margins edits margin_v as before", function()
    local bar = { enabled = true, v_anchor = "top", margin_v = 43, height = 5 }
    local _i, by = instance(bar, EXT)
    grid = nil
    by["Adjust margins"].callback()
    eq(grid.rows[1].field, "margin_v")
end)

test("changing the anchor clears it", function()
    local bar = { enabled = true, v_anchor = "top", margin_v = 43, height = 5, band_offset = -9 }
    local _i, by = instance(bar, EXT)
    by["Anchor"].callback()
    eq(bar.v_anchor, "bottom")
    eq(bar.band_offset, nil, "an offset from the top band carried over to the bottom")
end)

print(pass .. " passed, " .. fail .. " failed")
os.exit(fail == 0 and 0 or 1)
