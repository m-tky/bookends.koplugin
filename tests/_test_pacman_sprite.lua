-- Pure-Lua test for bookends_pacman_sprite.
-- Run: cd into the plugin dir, then `lua tests/_test_pacman_sprite.lua`.

local Pacman = dofile("bookends_pacman_sprite.lua")

local pass, fail = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1
    else fail = fail + 1; io.stderr:write("FAIL  " .. name .. "\n  " .. tostring(err) .. "\n") end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected=" .. tostring(b) .. " got=" .. tostring(a), 2) end
end
local function truthy(v, msg)
    if not v then error((msg or "value was falsy"), 2) end
end

-- Helper: read bit (x, y) from a frame.
local function bit(frame, x, y)
    local row = frame[y + 1]
    -- LuaJIT/Lua 5.1: use math, not bitops.
    local mask = 2 ^ x
    return (math.floor(row / mask) % 2) == 1
end

-- Helper: count "on" cells in a frame.
local function popcount(frame)
    local n = 0
    for y = 0, 12 do
        for x = 0, 12 do
            if bit(frame, x, y) then n = n + 1 end
        end
    end
    return n
end

test("frame size constant is 13", function()
    eq(Pacman.SPRITE_SIZE, 13)
end)

test("closed frame is a 13-row array", function()
    local f = Pacman.getFrame("closed")
    eq(#f, 13)
end)

test("closed frame: centre pixel is on", function()
    local f = Pacman.getFrame("closed")
    truthy(bit(f, 6, 6), "centre pixel should be on")
end)

test("closed frame: corners are off (outside disc)", function()
    local f = Pacman.getFrame("closed")
    eq(bit(f, 0, 0), false, "top-left")
    eq(bit(f, 12, 0), false, "top-right")
    eq(bit(f, 0, 12), false, "bottom-left")
    eq(bit(f, 12, 12), false, "bottom-right")
end)

test("closed frame: vertically symmetric (disc is symmetric)", function()
    local f = Pacman.getFrame("closed")
    for y = 0, 12 do
        for x = 0, 12 do
            eq(bit(f, x, y), bit(f, x, 12 - y),
                "asymmetric at (" .. x .. "," .. y .. ")")
        end
    end
end)

test("closed frame: horizontally symmetric (disc is symmetric)", function()
    local f = Pacman.getFrame("closed")
    for y = 0, 12 do
        for x = 0, 12 do
            eq(bit(f, x, y), bit(f, 12 - x, y),
                "asymmetric at (" .. x .. "," .. y .. ")")
        end
    end
end)

test("open frame: same row count as closed", function()
    eq(#Pacman.getFrame("open"), 13)
end)

test("open frame: strictly fewer cells than closed (wedge removed)", function()
    local open_n = popcount(Pacman.getFrame("open"))
    local closed_n = popcount(Pacman.getFrame("closed"))
    truthy(open_n < closed_n, "open=" .. open_n .. " closed=" .. closed_n)
end)

test("open frame: left half (dx<=0) matches closed frame", function()
    -- Wedge only affects dx > 0; the left half should be identical.
    local open = Pacman.getFrame("open")
    local closed = Pacman.getFrame("closed")
    for y = 0, 12 do
        for x = 0, 6 do
            eq(bit(open, x, y), bit(closed, x, y),
                "open != closed at (" .. x .. "," .. y .. ")")
        end
    end
end)

test("open frame: vertically symmetric (wedge is symmetric about midline)", function()
    local f = Pacman.getFrame("open")
    for y = 0, 12 do
        for x = 0, 12 do
            eq(bit(f, x, y), bit(f, x, 12 - y),
                "asymmetric at (" .. x .. "," .. y .. ")")
        end
    end
end)

test("open frame: mouth tip cells are off (apex at centre)", function()
    -- (7, 6) is one cell right of centre, on the wedge axis -> should be off.
    local f = Pacman.getFrame("open")
    eq(bit(f, 7, 6), false, "(7,6) should be in wedge")
    eq(bit(f, 8, 6), false, "(8,6) should be in wedge")
end)

test("unknown frame raises", function()
    local ok = pcall(Pacman.getFrame, "ghost")
    eq(ok, false, "should have errored on unknown frame")
end)

test("rotate: 0 steps returns input unchanged", function()
    local f = Pacman.getFrame("open")
    local r = Pacman.rotate(f, 0)
    for y = 0, 12 do eq(r[y + 1], f[y + 1], "row " .. y) end
end)

test("rotate: 4 steps returns input unchanged (full turn)", function()
    local f = Pacman.getFrame("open")
    local r = Pacman.rotate(f, 4)
    for y = 0, 12 do eq(r[y + 1], f[y + 1], "row " .. y) end
end)

test("rotate: 1 step (90 CW) puts mouth at bottom", function()
    -- After CW rotation, what was the right edge becomes the bottom edge.
    -- The wedge tip cells (7..12, 6) on the open frame become column 6,
    -- rows 7..12 after 1 CW rotation. They must remain off.
    local rotated = Pacman.rotate(Pacman.getFrame("open"), 1)
    for y = 7, 12 do
        eq(bit(rotated, 6, y), false, "cell (6," .. y .. ") should be off")
    end
end)

test("rotate: 2 steps flips horizontally and vertically", function()
    -- 180 rotation: (x, y) -> (12 - x, 12 - y).
    local f = Pacman.getFrame("open")
    local r = Pacman.rotate(f, 2)
    for y = 0, 12 do
        for x = 0, 12 do
            eq(bit(r, x, y), bit(f, 12 - x, 12 - y),
                "180 mismatch at (" .. x .. "," .. y .. ")")
        end
    end
end)

test("rotate: 3 steps (90 CCW) puts mouth at top", function()
    -- After 3 CW (= 1 CCW), the right wedge tip becomes the top edge.
    -- Cells (6, 0..5) of the rotated frame must be off.
    local rotated = Pacman.rotate(Pacman.getFrame("open"), 3)
    for y = 0, 5 do
        eq(bit(rotated, 6, y), false, "cell (6," .. y .. ") should be off")
    end
end)

test("directionToSteps maps direction strings to 0..3", function()
    eq(Pacman.directionToSteps("right"), 0)
    eq(Pacman.directionToSteps("down"), 1)
    eq(Pacman.directionToSteps("left"), 2)
    eq(Pacman.directionToSteps("up"), 3)
end)

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail > 0 and 1 or 0)
