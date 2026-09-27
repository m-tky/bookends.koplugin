-- DialogHelpers.showNudgeGrid: a row may set its own floor (row.min_val),
-- otherwise the grid's (opts.min_val, default 0) applies. Needed for a bar
-- positioned relative to the line text, whose offset goes negative (into the
-- text band) while the left and right margins beside it must not.
--
-- Usage: lua tests/_test_nudge_grid_floor.lua

local function permissive()
    local t, mt = {}, nil
    mt = { __index = function() return setmetatable({}, mt) end,
           __call  = function() return setmetatable({}, mt) end }
    return setmetatable(t, mt)
end
local shown
package.loaded["ui/widget/buttondialog"] = {
    new = function(_self, o)
        shown = o
        o.key_events = o.key_events or {}
        o.reinit = function() end
        o.refocusWidget = function() end
        return o
    end,
}
package.loaded["ui/uimanager"] = { show = function() end, close = function() end,
                                   nextTick = function(_, f) f() end, scheduleIn = function() end }
package.loaded["bookends_i18n"] = { gettext = function(s) return s end }
_G.require = (function(orig)
    return function(name)
        if package.loaded[name] then return package.loaded[name] end
        local ok, mod = pcall(orig, name)
        if ok then return mod end
        local stub = permissive(); package.loaded[name] = stub; return stub
    end
end)(require)

local DH = dofile("bookends_dialog_helpers.lua")

local pass, fail = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1
    else fail = fail + 1; io.stderr:write("FAIL  " .. name .. "\n  " .. tostring(err) .. "\n") end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected=" .. tostring(b) .. " got=" .. tostring(a), 2) end
end

local function grid(rows, values, min_val)
    shown = nil
    DH.showNudgeGrid{
        title = "t", rows = rows, min_val = min_val,
        get_value = function(f) return values[f] end,
        set_value = function(f, v) values[f] = v end,
    }
    assert(shown and shown.buttons, "no dialog was built")
    return shown.buttons
end
local function press(buttons, row, text)
    for _i, b in ipairs(buttons[row]) do
        if b.text == text then b.callback(); return end
    end
    error("no " .. text .. " button on row " .. row)
end

test("a row with its own floor can go below the grid's", function()
    local v = { off = 0, left = 0 }
    local b = grid({ { label = "V", field = "off", min_val = -50 }, { label = "L", field = "left" } }, v)
    press(b, 1, "-10")
    eq(v.off, -10, "the offset row should allow negative")
end)

test("a row without one keeps the grid's floor", function()
    local v = { off = 0, left = 0 }
    local b = grid({ { label = "V", field = "off", min_val = -50 }, { label = "L", field = "left" } }, v)
    press(b, 2, "-10")
    eq(v.left, 0, "the margin row must stay at 0")
end)

test("a row's floor still stops it", function()
    local v = { off = -45 }
    local b = grid({ { label = "V", field = "off", min_val = -50 } }, v)
    press(b, 1, "-10")
    eq(v.off, -50)
end)

test("no row floors: the grid behaves as before", function()
    local v = { a = 5 }
    local b = grid({ { label = "A", field = "a" } }, v, nil)
    press(b, 1, "-10")
    eq(v.a, 0)
end)

print(pass .. " passed, " .. fail .. " failed")
os.exit(fail == 0 and 0 or 1)
