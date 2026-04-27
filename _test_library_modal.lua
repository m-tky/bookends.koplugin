-- Dev-box test for menu/library_modal.lua's match function.
-- Pure-Lua, no KOReader dependencies.

-- Stub the requires that library_modal pulls in for chrome rendering — only
-- the match function is exercised here.
local stub_meta = setmetatable({}, {
    __index = function()
        return setmetatable({}, {
            __index = function() return function() end end,
        })
    end,
})
package.loaded["ffi/blitbuffer"] = setmetatable({}, { __index = function() return 0 end })
package.loaded["ui/widget/container/centercontainer"] = stub_meta
package.loaded["device"] = { screen = setmetatable({}, {
    __index = function() return function() return 1024 end end,
}) }
package.loaded["ui/widget/container/framecontainer"] = stub_meta
package.loaded["ui/geometry"] = { new = function(_, t) return t end }
package.loaded["ui/widget/container/inputcontainer"] = setmetatable({ extend = function(_, t) return t end }, { __index = stub_meta })
package.loaded["ui/gesturerange"] = { new = function(_, t) return t end }
package.loaded["ui/size"] = setmetatable({}, {
    __index = function()
        return setmetatable({}, {
            __index = function() return 1 end,
        })
    end,
})
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

-- Load the matches() helper. We expose it on the module for testability.
local LM = require("menu.library_modal")
local matches = LM._matchesQuery  -- to be added in next step

test("returns false for query under 2 chars", function()
    eq(matches("nf-fa-bookmark", ""), false, "empty")
    eq(matches("nf-fa-bookmark", "a"), false, "single char")
end)

test("single-term substring match", function()
    eq(matches("nf-fa-bookmark", "book"), true, "book in bookmark")
    eq(matches("nf-fa-bookmark", "BOOK"), true, "case-insensitive")
    eq(matches("nf-fa-bookmark", "xyzz"), false, "no match")
end)

test("multi-term AND match", function()
    eq(matches("nf-mdi-clock-outline", "clock outline"), true, "both terms present")
    eq(matches("nf-mdi-clock-outline", "clock smashed"), false, "second term absent")
    eq(matches("nf-fa-clock-o", "fa clock"), true, "set-prefix + concept")
end)

print(("\n%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
