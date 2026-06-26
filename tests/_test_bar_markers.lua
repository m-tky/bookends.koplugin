-- Tests for bar markers (#77): Bookends:buildBarMarkers maps the per-line
-- marker config (top/bottom: type/size/offset/colour) plus the chosen bar_info's
-- session_frac / book_open_frac into the renderer-facing markers table.
--
-- Run: cd into the plugin dir, then `lua tests/_test_bar_markers.lua`.

local function permissive()
    local t, mt = {}, nil
    mt = { __index = function() return setmetatable({}, mt) end,
           __call  = function() return setmetatable({}, mt) end }
    return setmetatable(t, mt)
end

-- Specific stubs that buildBarMarkers depends on (Colour + Device.screen).
-- parseColorValue passes the stored value straight through so we can assert it.
package.loaded["bookends_colour"] = {
    parseColorValue = function(v) return v end,
    toStorageShape = function(x) return x end,
}
package.loaded["device"] = { screen = { isColorEnabled = function() return false end } }
package.loaded["ui/widget/container/widgetcontainer"] = {
    extend = function(self, t) t = t or {}; return setmetatable(t, { __index = self }) end,
    new    = function(self, t) return setmetatable(t or {}, { __index = self }) end,
}
package.loaded["bookends_i18n"] = { gettext = function(s) return s end }
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

local SRC = { session_frac = 0.25, book_open_frac = 0.10 }

test("top=session resolves to session_frac with explicit size/offset/style/colour", function()
    local m = self:buildBarMarkers(
        { top = { type = "session", size = 150, offset = 3, style = "chevron", color = { grey = 0 } } }, SRC)
    eq(m.top.frac, 0.25, "frac")
    eq(m.top.size, 150, "size")
    eq(m.top.offset, 3, "offset")
    eq(m.top.style, "chevron", "style passed through")
    eq(m.top.color.grey, 0, "colour passed through parseColorValue")
    eq(m.bottom, nil, "no bottom slot")
end)

test("type=book_open resolves to book_open_frac; defaults size=50 offset=0 style=chevron", function()
    local m = self:buildBarMarkers({ top = { type = "book_open" } }, SRC)
    eq(m.top.frac, 0.10, "book_open frac")
    eq(m.top.size, 50, "default size")
    eq(m.top.offset, 0, "default offset")
    eq(m.top.style, "chevron", "default style")
    eq(m.top.color, nil, "no colour -> nil (painter uses default)")
end)

test("both slots populated independently", function()
    local m = self:buildBarMarkers(
        { top = { type = "book_open" }, bottom = { type = "session" } }, SRC)
    eq(m.top.frac, 0.10, "top book_open")
    eq(m.bottom.frac, 0.25, "bottom session")
end)

test("nil fraction omits the slot (e.g. session outside current chapter)", function()
    local m = self:buildBarMarkers({ top = { type = "session" } },
        { session_frac = nil, book_open_frac = 0.5 })
    eq(m, nil, "no resolvable slot -> nil whole table")
end)

test("slot without a type is ignored", function()
    local m = self:buildBarMarkers({ top = { size = 200 } }, SRC)
    eq(m, nil, "type absent -> Off -> omitted")
end)

test("nil src -> nil (no bar_info this paint)", function()
    eq(self:buildBarMarkers({ top = { type = "session" } }, nil), nil, "nil src")
end)

test("nil config -> nil", function()
    eq(self:buildBarMarkers(nil, SRC), nil, "nil cfg")
end)

print(pass .. " pass / " .. fail .. " fail")
os.exit(fail == 0 and 0 or 1)
