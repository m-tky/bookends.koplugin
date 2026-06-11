-- Unit tests for token favourites helpers (issue #59):
-- _isFavourite / _toggleFavourite / _filterFavourites in menu/tokens_library.lua.
-- Pure-Lua: stub the KOReader + plugin modules the library requires at load,
-- then require it and exercise the helpers on plain tables.
-- Usage: cd into the plugin dir, then `lua tests/_test_token_favourites.lua`.

package.path = "menu/?.lua;" .. package.path

-- ---- Stubs: tokens_library.lua only needs these to LOAD; the pure helpers
-- ---- under test touch none of them. ----------------------------------------
local function stub(t) return t or {} end
package.loaded["ffi/blitbuffer"]                          = { COLOR_BLACK = 0, COLOR_WHITE = 1, COLOR_GRAY_5 = 0x55 }
package.loaded["device"]                                  = { screen = { scaleBySize = function(_, n) return n end, getWidth = function() return 600 end, getHeight = function() return 800 end } }
package.loaded["ui/widget/container/framecontainer"]      = stub()
package.loaded["ui/geometry"]                             = { new = function(_, t) return t end }
package.loaded["ui/widget/container/leftcontainer"]       = stub()
package.loaded["menu.library_modal"]                      = { _matchesQuery = function() return true end }
package.loaded["ui/size"]                                 = { border = { thin = 1 }, radius = { default = 4 } }
package.loaded["bookends_tokens"]                         = { expand = function() return "" end }
package.loaded["ui/uimanager"]                            = stub()
package.loaded["bookends_utils"]                          = { truncateUtf8 = function(s) return s end }
package.loaded["ui/widget/verticalgroup"]                 = stub()
package.loaded["ui/widget/verticalspan"]                  = stub()
package.loaded["ui/widget/horizontalgroup"]               = stub()
package.loaded["ui/widget/horizontalspan"]                = stub()
package.loaded["ui/font"]                                 = { getFace = function() return {} end }
package.loaded["ui/widget/textwidget"]                    = stub()
package.loaded["ui/widget/container/inputcontainer"]      = stub()
package.loaded["ui/gesturerange"]                         = stub()
package.loaded["bookends_i18n"]                           = { gettext = function(s) return s end }
package.loaded["menu.tokens_catalogue"]                   = {
    CHIPS = { { key = "all", label = "All" }, { key = "book", label = "Book" } },
    TOKENS = {
        { description = "Document title", token = "%title", chip = "book" },
        { description = "Book percentage read", token = "%book_pct", chip = "progress" },
    },
    CONDITIONALS = {
        { description = "If Wi-Fi is on", expression = "[if:wifi=on]on[/if]", chip = "ifelse" },
    },
}

local TokensLibrary = require("tokens_library")

-- ---- Tiny harness -----------------------------------------------------------
local pass, fail = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1
    else fail = fail + 1; io.stderr:write("FAIL  " .. name .. "\n  " .. tostring(err) .. "\n") end
end
local function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "") .. " expected=" .. string.format("%q", tostring(expected))
            .. " got=" .. string.format("%q", tostring(actual)), 2)
    end
end

-- ---- _isFavourite -----------------------------------------------------------
test("isFavourite: present", function()
    eq(TokensLibrary._isFavourite({ "%title", "%book_pct" }, "%title"), true)
end)
test("isFavourite: absent", function()
    eq(TokensLibrary._isFavourite({ "%title" }, "%author"), false)
end)
test("isFavourite: empty list", function()
    eq(TokensLibrary._isFavourite({}, "%title"), false)
end)
test("isFavourite: nil-safe", function()
    eq(TokensLibrary._isFavourite(nil, "%title"), false)
    eq(TokensLibrary._isFavourite({ "%title" }, nil), false)
end)

-- ---- _toggleFavourite (returns NEW array, does not mutate) -------------------
test("toggle: add prepends (most-recent first)", function()
    local out = TokensLibrary._toggleFavourite({ "%title" }, "%author")
    eq(#out, 2); eq(out[1], "%author"); eq(out[2], "%title")
end)
test("toggle: add to empty", function()
    local out = TokensLibrary._toggleFavourite({}, "%title")
    eq(#out, 1); eq(out[1], "%title")
end)
test("toggle: nil favs treated as empty", function()
    local out = TokensLibrary._toggleFavourite(nil, "%title")
    eq(#out, 1); eq(out[1], "%title")
end)
test("toggle: remove existing", function()
    local out = TokensLibrary._toggleFavourite({ "%author", "%title" }, "%title")
    eq(#out, 1); eq(out[1], "%author")
end)
test("toggle: re-add moves to front (toggle off then on)", function()
    local off = TokensLibrary._toggleFavourite({ "%book_pct", "%title", "%author" }, "%title")
    eq(#off, 2); eq(off[1], "%book_pct"); eq(off[2], "%author")
    local on = TokensLibrary._toggleFavourite(off, "%title")
    eq(#on, 3); eq(on[1], "%title")
end)
test("toggle: does not mutate input", function()
    local input = { "%title" }
    TokensLibrary._toggleFavourite(input, "%author")
    eq(#input, 1); eq(input[1], "%title")
end)

-- ---- _filterFavourites (intersect catalogue with favs, fav order) -----------
local CATALOGUE = {
    { description = "Document title", token = "%title" },
    { description = "Book pct", token = "%book_pct" },
    { description = "If Wi-Fi", expression = "[if:wifi=on]on[/if]" },
}
test("filter: keeps only favourited, in fav order", function()
    local out = TokensLibrary._filterFavourites(CATALOGUE, { "%book_pct", "%title" })
    eq(#out, 2)
    eq(out[1].token, "%book_pct")
    eq(out[2].token, "%title")
end)
test("filter: matches conditional by expression", function()
    local out = TokensLibrary._filterFavourites(CATALOGUE, { "[if:wifi=on]on[/if]" })
    eq(#out, 1); eq(out[1].expression, "[if:wifi=on]on[/if]")
end)
test("filter: orphan favourite (not in catalogue) is dropped", function()
    local out = TokensLibrary._filterFavourites(CATALOGUE, { "%removed_by_curator", "%title" })
    eq(#out, 1); eq(out[1].token, "%title")
end)
test("filter: empty favs returns empty", function()
    eq(#TokensLibrary._filterFavourites(CATALOGUE, {}), 0)
end)
test("filter: nil favs returns empty", function()
    eq(#TokensLibrary._filterFavourites(CATALOGUE, nil), 0)
end)

-- ---- _currentItems favourites branch ----------------------------------------
test("currentItems: favourites chip filters merged catalogue in fav order", function()
    local out = TokensLibrary._currentItems("favourites", nil, { "%book_pct", "%title" })
    eq(#out, 2); eq(out[1].token, "%book_pct"); eq(out[2].token, "%title")
end)
test("currentItems: favourites chip with empty favs returns empty", function()
    eq(#TokensLibrary._currentItems("favourites", nil, {}), 0)
end)

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
