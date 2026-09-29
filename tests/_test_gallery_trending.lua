-- Tests for the gallery's This week / This month sorts: Gallery.parseTrending
-- (shape handling of the worker's /trending response) and Gallery.sortEntries
-- (ordering for every gallery sort mode).
--
-- json isn't available outside KOReader, so decode is stubbed with a lookup of
-- canned bodies: what's under test is how the decoded shape is handled, not
-- JSON parsing.
--
-- Run: cd into the plugin dir, then `lua tests/_test_gallery_trending.lua`.

local DECODED = {}
package.preload["json"] = function()
    return { decode = function(s)
        if DECODED[s] == nil then error("bad json") end
        return DECODED[s]
    end }
end

local Gallery = dofile("preset_gallery.lua")

local pass, fail = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1
    else fail = fail + 1; io.stderr:write("FAIL  " .. name .. "\n  " .. tostring(err) .. "\n") end
end
local function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "")
            .. " expected=" .. string.format("%q", tostring(expected))
            .. " got="      .. string.format("%q", tostring(actual)), 2)
    end
end
local function order(entries)
    local slugs = {}
    for i, e in ipairs(entries) do slugs[i] = e.slug end
    return table.concat(slugs, ",")
end

-- parseTrending ------------------------------------------------------------

test("maps the 7 and 30 day windows to week and month", function()
    DECODED.full = { ok = true, windows = { ["7"] = { a = 3 }, ["30"] = { a = 9, b = 1 } } }
    local t = Gallery.parseTrending("full")
    eq(t.week.a, 3)
    eq(t.month.a, 9)
    eq(t.month.b, 1)
end)

test("a missing window becomes an empty table, not nil", function()
    DECODED.partial = { windows = { ["30"] = { a = 2 } } }
    local t = Gallery.parseTrending("partial")
    eq(type(t.week), "table")
    eq(next(t.week), nil)
    eq(t.month.a, 2)
end)

test("returns nil without a windows table", function()
    DECODED.nowin = { ok = true, counts = { a = 1 } }
    eq(Gallery.parseTrending("nowin"), nil)
end)

test("returns nil for undecodable or non-string input", function()
    eq(Gallery.parseTrending("not json at all"), nil)
    eq(Gallery.parseTrending(nil), nil)
end)

-- sortEntries --------------------------------------------------------------

local function entries()
    return {
        { slug = "old-big",   name = "Old big",   added = "2026-05-01" },
        { slug = "new-hot",   name = "New hot",   added = "2026-09-20" },
        { slug = "mid",       name = "Mid",       added = "2026-07-01" },
        { slug = "newest",    name = "Newest",    added = "2026-09-27" },
    }
end
local counts = { ["old-big"] = 900, ["new-hot"] = 40, mid = 200, newest = 0 }
local trending = {
    week  = { ["new-hot"] = 30, mid = 5, ["old-big"] = 5 },
    month = { ["new-hot"] = 60, ["old-big"] = 80 },
}

test("latest orders by added, ignoring counts", function()
    eq(order(Gallery.sortEntries(entries(), "latest", counts, trending)),
        "newest,new-hot,mid,old-big")
end)

test("popular orders by all-time counts", function()
    eq(order(Gallery.sortEntries(entries(), "popular", counts, trending)),
        "old-big,mid,new-hot,newest")
end)

test("popular without counts falls back to latest", function()
    eq(order(Gallery.sortEntries(entries(), "popular", nil, nil)),
        "newest,new-hot,mid,old-big")
end)

test("week orders by the 7-day window, ties broken by all-time counts", function()
    -- mid and old-big both have 5 this week; old-big has more all-time.
    eq(order(Gallery.sortEntries(entries(), "week", counts, trending)),
        "new-hot,old-big,mid,newest")
end)

test("month orders by the 30-day window", function()
    -- mid and newest have no month installs; mid wins on all-time counts.
    eq(order(Gallery.sortEntries(entries(), "month", counts, trending)),
        "old-big,new-hot,mid,newest")
end)

test("week without trending data falls back to all-time counts", function()
    eq(order(Gallery.sortEntries(entries(), "week", counts, nil)),
        "old-big,mid,new-hot,newest")
end)

test("week with neither trending nor counts falls back to latest", function()
    eq(order(Gallery.sortEntries(entries(), "week", nil, nil)),
        "newest,new-hot,mid,old-big")
end)

test("equal everything falls back to name for a stable order", function()
    local e = {
        { slug = "b", name = "Bravo", added = "2026-09-01" },
        { slug = "a", name = "Alpha", added = "2026-09-01" },
    }
    eq(order(Gallery.sortEntries(e, "week", {}, { week = {} })), "a,b")
end)

test("non-numeric window values count as zero rather than erroring", function()
    local e = entries()
    local bad = { week = { ["new-hot"] = "lots", mid = 1 } }
    eq(order(Gallery.sortEntries(e, "week", nil, bad)), "mid,newest,new-hot,old-big")
end)

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
