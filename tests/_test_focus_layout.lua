-- Pure-Lua test for LibraryModal's focus-layout helpers. No KOReader deps.
-- Stub the requires library_modal pulls in at load time.
local stub_meta = setmetatable({}, { __index = function()
    return setmetatable({}, { __index = function() return function() end end })
end })
package.loaded["ffi/blitbuffer"] = setmetatable({}, { __index = function() return 0 end })
package.loaded["ui/widget/container/centercontainer"] = stub_meta
package.loaded["device"] = {
    screen = setmetatable({}, { __index = function() return function() return 1024 end end }),
    hasDPad = function() return true end,
    input = { group = { Back = { "Back" } } },
}
package.loaded["ui/widget/container/framecontainer"] = stub_meta
package.loaded["ui/geometry"] = { new = function(_, t) return t end }
package.loaded["ui/widget/container/inputcontainer"] = setmetatable({ extend = function(_, t) return t end }, { __index = stub_meta })
package.loaded["ui/widget/focusmanager"] = setmetatable({ extend = function(_, t) return t end }, { __index = stub_meta })
package.loaded["ui/gesturerange"] = { new = function(_, t) return t end }
package.loaded["ui/size"] = setmetatable({}, { __index = function()
    return setmetatable({}, { __index = function() return 1 end }) end })
package.loaded["ui/uimanager"] = stub_meta
package.loaded["ui/widget/verticalgroup"] = stub_meta
package.loaded["ui/widget/verticalspan"] = stub_meta
package.loaded["ui/widget/horizontalspan"] = stub_meta
package.loaded["ui/widget/container/widgetcontainer"] = { extend = function(_, t) return t end }
package.loaded["bookends_i18n"] = { gettext = function(s) return s end }
package.loaded["ui/widget/inputtext"] = stub_meta
package.loaded["ui/widget/button"] = stub_meta
package.loaded["ui/widget/horizontalgroup"] = stub_meta

local pass, fail = 0, 0
local function eq(a, b, msg) if a == b then pass = pass + 1 else fail = fail + 1; print(("FAIL %s: expected %q got %q"):format(msg or "", tostring(b), tostring(a))) end end
local function test(name, fn) print("--- " .. name); fn() end

local LM = require("menu.library_modal")

local A, B, C, D = {id="A"}, {id="B"}, {id="C"}, {id="D"}

test("buildLayout drops empty rows, keeps order", function()
    local layout = LM._buildLayout({ {A}, {}, {B, C}, {} })
    eq(#layout, 2, "two non-empty rows")
    eq(layout[1][1], A, "row1 col1")
    eq(layout[2][1], B, "row2 col1")
    eq(layout[2][2], C, "row2 col2")
end)

test("buildLayout returns empty table when all rows empty", function()
    local layout = LM._buildLayout({ {}, {} })
    eq(#layout, 0, "no rows")
end)

test("clampSelected keeps valid position", function()
    local layout = { {A, B}, {C} }
    local sel = LM._clampSelected(layout, { x = 2, y = 1 })
    eq(sel.x, 2, "x kept"); eq(sel.y, 1, "y kept")
end)

test("clampSelected pulls overshoot back onto the grid", function()
    local layout = { {A, B}, {C} }
    local sel = LM._clampSelected(layout, { x = 5, y = 9 })
    eq(sel.y, 2, "y clamped to last row")
    eq(sel.x, 1, "x clamped to that row's width")
end)

test("clampSelected defaults to 1,1 for empty/absent input", function()
    local sel = LM._clampSelected({ {A} }, nil)
    eq(sel.x, 1, "default x"); eq(sel.y, 1, "default y")
    local sel2 = LM._clampSelected({}, { x = 3, y = 3 })
    eq(sel2.x, 1, "empty grid x"); eq(sel2.y, 1, "empty grid y")
end)

print(("\n%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
