-- Test for #82: startRefreshTimer must no-op when disable_auto_refresh is set.
-- Run: cd into the plugin dir, then `lua tests/_test_refresh_timer.lua`.

local function permissive()
    local t, mt = {}, nil
    mt = { __index = function() return setmetatable({}, mt) end,
           __call  = function() return setmetatable({}, mt) end }
    return setmetatable(t, mt)
end

package.loaded["bookends_colour"] = { parseColorValue = function(v) return v end, toStorageShape = function(x) return x end }
package.loaded["device"] = { screen = { isColorEnabled = function() return false end } }
package.loaded["ui/widget/container/widgetcontainer"] = {
    extend = function(self, t) t = t or {}; return setmetatable(t, { __index = self }) end,
    new    = function(self, t) return setmetatable(t or {}, { __index = self }) end,
}
package.loaded["bookends_i18n"] = { gettext = function(s) return s end }
local scheduled = {}
package.loaded["ui/uimanager"] = {
    scheduleIn = function(_, delay, fn) table.insert(scheduled, { delay = delay, fn = fn }) end,
    unschedule = function() end,
}
_G.require = function(name)
    if package.loaded[name] then return package.loaded[name] end
    local stub = permissive(); package.loaded[name] = stub; return stub
end
_G.G_reader_settings = permissive()

local Bookends = dofile("main.lua")
local self = setmetatable({}, { __index = Bookends })

local pass, fail = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1
    else fail = fail + 1; io.stderr:write("FAIL  " .. name .. "\n  " .. tostring(err) .. "\n") end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected=" .. tostring(b) .. " got=" .. tostring(a), 2) end
end

test("startRefreshTimer arms the timer when auto-refresh is enabled", function()
    self.disable_auto_refresh = false
    self.refresh_timer_active = nil
    scheduled = {}
    self:startRefreshTimer()
    eq(self.refresh_timer_active, true, "timer should activate")
    eq(#scheduled, 1, "one scheduleIn call")
end)

test("startRefreshTimer is a no-op when disable_auto_refresh is true", function()
    self.disable_auto_refresh = true
    self.refresh_timer_active = nil
    scheduled = {}
    self:startRefreshTimer()
    eq(self.refresh_timer_active, nil, "timer should not activate")
    eq(#scheduled, 0, "no scheduleIn call")
end)

print(pass .. " pass / " .. fail .. " fail")
os.exit(fail == 0 and 0 or 1)
