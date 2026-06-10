-- Dev-box test runner for bookends_updater.lua.
-- Runs pure-Lua (no KOReader) by stubbing every module the updater requires.
-- Usage: cd into the plugin dir, then `lua tests/_test_updater.lua`.

package.loaded["ui/widget/confirmbox"] = setmetatable({}, { __index = function() return function() end end })
package.loaded["device"] = {
    canOpenLink = function() return false end,
    openLink = function() end,
    unpackArchive = function() return true end,
}
package.loaded["ui/widget/infomessage"] = setmetatable({}, { __index = function() return function() end end })
package.loaded["ui/uimanager"] = {
    show = function() end,
    close = function() end,
    scheduleIn = function() end,
    restartKOReader = function() end,
}
package.loaded["bookends_i18n"] = { gettext = function(s) return s end }

-- NetworkMgr stub: record runWhenOnline invocations. The callback is NOT run,
-- so the wrapped fetch/download bodies never execute (no http stubs needed) —
-- we only assert the user-initiated paths route through runWhenOnline.
-- Simulate Wi-Fi OFF so the user-initiated paths must route through
-- runWhenOnline (rather than bail). The recorded callback is NOT invoked,
-- so the wrapped fetch/download bodies never run (no http stubs needed).
local net = { run_when_online = 0 }
package.loaded["ui/network/manager"] = {
    isWifiOn    = function() return false end,
    isOnline    = function() return false end,
    isConnected = function() return false end,
    runWhenOnline = function(_self, _cb) net.run_when_online = net.run_when_online + 1 end,
}

local Updater = dofile("bookends_updater.lua")
-- Stub version detection (needs datastorage); irrelevant to network routing.
Updater.getInstalledVersion = function() return "5.0.0" end

local pass, fail = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1
    else fail = fail + 1; io.stderr:write("FAIL  " .. name .. "\n  " .. tostring(err) .. "\n") end
end

local function eq(actual, expected)
    if actual ~= expected then
        error(("expected=%q got=%q"):format(tostring(expected), tostring(actual)), 2)
    end
end

-- Smoke: module loads
test("module loads", function()
    assert(Updater, "Updater module did not load")
    assert(type(Updater.getInstalledVersion) == "function")
end)

test("composeBranchUrl: simple branch", function()
    eq(Updater.composeBranchUrl("master"),
       "https://github.com/AndyHazz/bookends.koplugin/archive/refs/heads/master.zip")
end)

test("composeBranchUrl: branch with slash kept literal", function()
    eq(Updater.composeBranchUrl("feature/v5.2-test"),
       "https://github.com/AndyHazz/bookends.koplugin/archive/refs/heads/feature/v5.2-test.zip")
end)

test("composeBranchUrl: special chars are URL-encoded", function()
    -- Spaces, semicolons, etc. encoded; alnum/-/_/./~// preserved
    eq(Updater.composeBranchUrl("a b;c"),
       "https://github.com/AndyHazz/bookends.koplugin/archive/refs/heads/a%20b%3Bc.zip")
end)

-- Wi-Fi / runWhenOnline routing (parity with bookshelf issue #77): user-initiated
-- network paths must bring Wi-Fi up via NetworkMgr:runWhenOnline, not bail when off.
test("Updater.check routes through runWhenOnline", function()
    net.run_when_online = 0
    Updater.check()
    eq(net.run_when_online, 1)
end)
test("Updater.install routes through runWhenOnline", function()
    net.run_when_online = 0
    Updater.install("https://example.invalid/x.zip", "5.0.0", "5.1.0")
    eq(net.run_when_online, 1)
end)
test("Updater.installBranch routes through runWhenOnline (no isWifiOn bail)", function()
    net.run_when_online = 0
    Updater.installBranch("master")
    eq(net.run_when_online, 1)
end)
test("Updater.installLatestStable routes through runWhenOnline", function()
    net.run_when_online = 0
    Updater.installLatestStable()
    eq(net.run_when_online, 1)
end)

print(pass .. " passed, " .. fail .. " failed")
os.exit(fail == 0 and 0 or 1)
