-- #102: background fill set separately for the top and bottom sections.
--
-- The fill used to be one colour, `background_color`, drawn behind both
-- sections. It is now two, set from two menu rows (Top background, Bottom
-- background), with no combined row.
--
-- Rules under test, all in bookends_colour.lua:
--
-- READING. A section's colour is its own key, background_color_top or
-- background_color_bottom, and failing that the original background_color. So
-- a preset that only ever had background_color fills both sections in it,
-- exactly as it did before - no migration.
--
-- SAVING. After any edit, the two effective colours are stored:
--   - the SAME (both off included) -> as the single background_color every
--     version of bookends understands, with the section keys removed;
--   - DIFFERENT -> as the two section keys, with background_color removed, so
--     a section that is off has nothing to fall back to.
-- So a preset only needs this version if it really uses two colours, and an
-- older bookends shows such a preset with no fill rather than breaking.
--
-- Usage: lua tests/_test_bg_fill_sections.lua

package.loaded["ffi/blitbuffer"] = {
    ColorRGB32 = function(r, g, b, a) return { kind = "rgb32", r = r, g = g, b = b, a = a } end,
    Color8 = function(v) return { kind = "color8", v = v } end,
}
local Colour = dofile("bookends_colour.lua")
local Config = dofile("bookends_config.lua")

local pass, fail = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1
    else fail = fail + 1; io.stderr:write("FAIL  " .. name .. "\n  " .. tostring(err) .. "\n") end
end
local function same(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function eqv(actual, expected, msg)
    if not same(actual, expected) then
        local function show(v)
            if type(v) ~= "table" then return tostring(v) end
            local t = {}; for k, x in pairs(v) do t[#t + 1] = k .. "=" .. tostring(x) end
            return "{" .. table.concat(t, ",") .. "}"
        end
        error((msg or "") .. " expected=" .. show(expected) .. " got=" .. show(actual), 2)
    end
end

-- A settings store: read(key) and write(key, value), nil value = delete.
local function store(initial)
    local data = {}
    for k, v in pairs(initial or {}) do data[k] = v end
    local s = { data = data }
    s.read = function(k) return data[k] end
    s.write = function(k, v) data[k] = v end
    return s
end

local GREY = { grey = 0xBF }
local RED  = { hex = "#AA0000" }
local BLUE = { hex = "#0000AA" }

-- ── reading ────────────────────────────────────────────────────────────────

test("a preset with only background_color fills both sections in it", function()
    local s = store({ background_color = GREY })
    eqv(Colour.backgroundFor(s.read, "top"), GREY, "top")
    eqv(Colour.backgroundFor(s.read, "bottom"), GREY, "bottom")
end)

test("a section's own colour wins over the shared one", function()
    local s = store({ background_color = GREY, background_color_top = RED })
    eqv(Colour.backgroundFor(s.read, "top"), RED, "top uses its own")
    eqv(Colour.backgroundFor(s.read, "bottom"), GREY, "bottom still falls back")
end)

test("nothing set means no fill in either section", function()
    local s = store({})
    eqv(Colour.backgroundFor(s.read, "top"), nil)
    eqv(Colour.backgroundFor(s.read, "bottom"), nil)
end)

-- ── saving ─────────────────────────────────────────────────────────────────

test("the same colour in both sections is saved as background_color alone", function()
    local s = store({ background_color_top = RED, background_color_bottom = BLUE })
    Colour.storeBackground(s.write, GREY, GREY)
    eqv(s.data, { background_color = GREY }, "one key, the one older versions read")
end)

test("both sections off clears every background key", function()
    local s = store({ background_color = GREY, background_color_top = RED })
    Colour.storeBackground(s.write, nil, nil)
    eqv(s.data, {}, "nothing left")
end)

test("different colours are saved per section, with no shared key", function()
    local s = store({ background_color = GREY })
    Colour.storeBackground(s.write, RED, BLUE)
    eqv(s.data, { background_color_top = RED, background_color_bottom = BLUE })
end)

test("one section off: only the other is stored, so the off one reads as off", function()
    local s = store({ background_color = GREY })
    Colour.storeBackground(s.write, RED, nil)
    eqv(s.data, { background_color_top = RED })
    eqv(Colour.backgroundFor(s.read, "bottom"), nil, "bottom must not fall back to anything")
end)

test("equal is judged by value, not by table identity", function()
    local s = store({})
    Colour.storeBackground(s.write, { hex = "#AA0000" }, { hex = "#AA0000" })
    eqv(s.data, { background_color = { hex = "#AA0000" } })
end)

test("grey and hex that happen to differ are not collapsed", function()
    local s = store({})
    Colour.storeBackground(s.write, { grey = 0xBF }, { hex = "#BFBFBF" })
    eqv(s.data, { background_color_top = { grey = 0xBF }, background_color_bottom = { hex = "#BFBFBF" } })
end)

-- ── editing one row, the way the menu does it ──────────────────────────────

test("changing one section of a both-sections preset keeps the other", function()
    local s = store({ background_color = GREY })
    Colour.storeBackground(s.write, RED, Colour.backgroundFor(s.read, "bottom"))
    eqv(Colour.backgroundFor(s.read, "top"), RED)
    eqv(Colour.backgroundFor(s.read, "bottom"), GREY, "untouched section kept its colour")
end)

test("setting a section back to match the other collapses to one key again", function()
    local s = store({ background_color_top = RED, background_color_bottom = GREY })
    Colour.storeBackground(s.write, GREY, Colour.backgroundFor(s.read, "bottom"))
    eqv(s.data, { background_color = GREY })
end)

-- ── presets ────────────────────────────────────────────────────────────────

test("presets carry the two section keys", function()
    local have = {}
    for _i, k in ipairs(Config.PRESET_OPTIONAL_KEYS) do have[k] = true end
    assert(have.background_color, "the shared key must stay, for older presets")
    assert(have.background_color_top, "background_color_top is not saved in presets")
    assert(have.background_color_bottom, "background_color_bottom is not saved in presets")
end)

-- ── the Colours menu rows ──────────────────────────────────────────────────
--
-- Drives the real menu module against a stub settings store, with the
-- greyscale nudge dialog captured rather than shown. Proves the two rows exist
-- (and the old combined row does not), that each shows its own section, and
-- that saving and holding go through the rules above.

package.loaded["device"] = { screen = { isColorEnabled = function() return false end } }
package.loaded["bookends_i18n"] = { gettext = function(x) return x end }
package.loaded["bookends_colour"] = Colour

local function menuFor(initial)
    local data = {}
    for k, v in pairs(initial or {}) do data[k] = v end
    local B = {}
    dofile("menu/colours_menu.lua")(B)
    local inst = setmetatable({}, { __index = B })
    inst.settings = {
        readSetting = function(_s, k) return data[k] end,
        saveSetting = function(_s, k, v) data[k] = v end,
        delSetting  = function(_s, k) data[k] = nil end,
    }
    inst.markDirty = function() end
    local nudge = {}
    inst.showNudgeDialog = function(_s, title, current, _lo, _hi, _def, _unit, on_save, ...)
        local rest = { ... }
        nudge.title, nudge.current, nudge.save, nudge.default = title, current, on_save, rest[5]
    end
    local rows = {}
    for _i, item in ipairs(inst:buildTextColourMenu()) do
        local label = item.text_func and item.text_func() or item.text
        rows[label:match("^[^:]+")] = { item = item, label = label }
    end
    return rows, data, nudge
end

test("the menu has a Top and a Bottom background row, and no combined row", function()
    local rows = menuFor({})
    assert(rows["Top background"], "no Top background row")
    assert(rows["Bottom background"], "no Bottom background row")
    assert(not rows["Background colour"], "the combined row should be gone")
end)

test("each row shows its own section, reading an older preset as both", function()
    local rows = menuFor({ background_color = { grey = 0xBF } })   -- 25%
    eqv(rows["Top background"].label, "Top background: 25%")
    eqv(rows["Bottom background"].label, "Bottom background: 25%")
end)

test("saving a colour in one row keeps the other section's colour", function()
    local rows, data, nudge = menuFor({ background_color = { grey = 0xBF } })
    rows["Top background"].item.callback(nil)
    nudge.save(75)                                                  -- 75% black
    eqv(data, { background_color_top = { grey = 0x40 }, background_color_bottom = { grey = 0xBF } })
end)

test("holding a row turns only that section off", function()
    local rows, data = menuFor({ background_color = { grey = 0xBF } })
    rows["Bottom background"].item.hold_callback(nil)
    eqv(data, { background_color_top = { grey = 0xBF } })
end)

print(pass .. " passed, " .. fail .. " failed")
os.exit(fail == 0 and 0 or 1)
