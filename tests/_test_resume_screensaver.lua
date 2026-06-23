-- Regression test for issue #73: Bookends must not repaint over a screensaver
-- that is still showing on resume (some devices, e.g. Kobo Clara Color, keep the
-- screensaver up with a delay / tap-to-dismiss). onResume should DEFER the
-- repaint while Device.screen_saver_mode is true, and onOutOfScreenSaver should
-- perform the deferred repaint. The session reset must still happen on every
-- resume (it doesn't paint, so it isn't the bug).
--
-- Run: cd into the plugin dir, then `lua tests/_test_resume_screensaver.lua`.

-- ── Stub the KOReader module graph that main.lua requires at load time. ──
-- A permissive stub: indexable to any depth and callable, returning itself.
local function permissive()
    local t = {}
    local mt
    mt = {
        __index = function() return setmetatable({}, mt) end,
        __call  = function() return setmetatable({}, mt) end,
    }
    return setmetatable(t, mt)
end

local scheduled = {}  -- captured UIManager:scheduleIn callbacks
local setdirty_calls = 0

package.loaded["ui/uimanager"] = {
    scheduleIn = function(_, _sec, fn) scheduled[#scheduled + 1] = fn end,
    unschedule = function() end,
    setDirty   = function() setdirty_calls = setdirty_calls + 1 end,
    nextTick   = function(_, fn) if fn then fn() end end,
}
package.loaded["ui/widget/container/widgetcontainer"] = {
    extend = function(self, t) t = t or {}; return setmetatable(t, { __index = self }) end,
    new    = function(self, t) return setmetatable(t or {}, { __index = self }) end,
}
local Device = { screen_saver_mode = false }
package.loaded["device"] = Device
package.loaded["bookends_i18n"] = { gettext = function(s) return s end }

-- Everything else main.lua (and its local modules) require, transitively:
-- intercept require and hand back a permissive stub, so no real KOReader or
-- bookends module actually loads. The specific stubs preset above win.
_G.require = function(name)
    if package.loaded[name] then return package.loaded[name] end
    local stub = permissive()
    package.loaded[name] = stub
    return stub
end
_G.G_reader_settings = permissive()

local Bookends = dofile("main.lua")

-- ── Test scaffolding ──
local pass, fail = 0, 0
local function test(name, fn)
    scheduled = {}; setdirty_calls = 0; Device.screen_saver_mode = false
    local ok, err = pcall(fn)
    if ok then pass = pass + 1
    else fail = fail + 1; io.stderr:write("FAIL  " .. name .. "\n  " .. tostring(err) .. "\n") end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected=" .. tostring(b) .. " got=" .. tostring(a), 2) end
end

-- A fake plugin instance: real methods via __index, with the painting and
-- network calls stubbed so we can count them.
local function newSelf(footer_visible)
    return setmetatable({
        ui = { view = { footer_visible = footer_visible or false } },
        session_max_page = 7,
        _md = 0, _bg = 0,
        markDirty = function(s) s._md = s._md + 1 end,
        backgroundUpdateCheck = function(s) s._bg = s._bg + 1 end,
    }, { __index = Bookends })
end

test("resume while screensaver still showing: no repaint, marks pending", function()
    Device.screen_saver_mode = true
    local s = newSelf(false)
    Bookends.onResume(s)
    eq(s._md, 0, "must NOT repaint while screensaver is up")
    eq(s._resume_repaint_pending, true, "should mark repaint pending")
    eq(s._bg, 1, "background update check still runs")
    eq(s.session_resume_time ~= nil, true, "session still reset on resume")
    eq(s.session_start_page, 7, "session_start_page reset to max page")
end)

test("OutOfScreenSaver performs the deferred repaint (mode still true)", function()
    Device.screen_saver_mode = true
    local s = newSelf(false)
    Bookends.onResume(s)
    -- screensaver dismissal broadcasts OutOfScreenSaver *before* cleanup, so
    -- screen_saver_mode is still true here; the handler must not re-guard on it.
    Bookends.onOutOfScreenSaver(s)
    eq(s._md, 1, "deferred repaint runs on OutOfScreenSaver")
    eq(s._resume_repaint_pending, nil, "pending flag cleared")
end)

test("resume with no screensaver up: repaints immediately", function()
    Device.screen_saver_mode = false
    local s = newSelf(false)
    Bookends.onResume(s)
    eq(s._md, 1, "repaint immediately when no screensaver")
    eq(s._resume_repaint_pending, nil, "no pending flag")
end)

test("OutOfScreenSaver with nothing pending is a no-op", function()
    local s = newSelf(false)
    Bookends.onOutOfScreenSaver(s)
    eq(s._md, 0, "no repaint when nothing was deferred")
end)

test("footer visible schedules the 1.5s follow-up repaint", function()
    Device.screen_saver_mode = false
    local s = newSelf(true)
    Bookends.onResume(s)
    eq(s._md, 1, "initial repaint")
    eq(#scheduled, 1, "one follow-up scheduled when footer visible")
    scheduled[1]()  -- fire the 1.5s callback
    eq(s._md, 2, "follow-up repaint fires")
end)

test("suspend clears any pending resume repaint", function()
    Device.screen_saver_mode = true
    local s = newSelf(false)
    Bookends.onResume(s)
    eq(s._resume_repaint_pending, true, "pending after screensaver resume")
    Bookends.onSuspend(s)
    eq(s._resume_repaint_pending, nil, "suspend clears pending flag")
end)

print(pass .. " pass / " .. fail .. " fail")
os.exit(fail == 0 and 0 or 1)
