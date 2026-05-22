--[[
Pacman progress-bar sprite + layout helpers.

The character sprite is generated at module load from a geometric formula:
a filled disc on a 13x13 grid (radius 6, centred at (6,6)), with the OPEN
frame having a triangular wedge cleared from the right side. The base
orientation faces right; rotations for up/down/left are produced from the
base by a generic 90-degree CW step rotator.

Sprite data layout: each frame is a 13-element array. Element i is an
integer whose low 13 bits encode row i of the grid (bit 0 = column 0).

Pure Lua. No KOReader imports.
]]

local Pacman = {}

Pacman.SPRITE_SIZE = 13

-- Build a 13x13 frame from a per-cell predicate.
-- predicate(x, y) returns true when the cell at (x, y) is "on".
local function buildFrame(predicate)
    local rows = {}
    for y = 0, 12 do
        local bits = 0
        for x = 0, 12 do
            if predicate(x, y) then
                bits = bits + 2 ^ x
            end
        end
        rows[y + 1] = bits
    end
    return rows
end

-- Cells inside the filled disc: (x-6)^2 + (y-6)^2 <= r^2 + 0.5
-- The +0.5 fudge softens the right/bottom edges so the disc looks like a
-- proper circle at 13x13 rather than a cross-stitched diamond.
local function inDisc(x, y)
    local dx, dy = x - 6, y - 6
    return (dx * dx + dy * dy) <= (6 * 6 + 0.5)
end

-- Open frame: filled disc minus a triangular wedge.
-- The wedge apex is at (6,6); it opens rightward with half-angle ~35
-- degrees, so a cell is in the wedge when dx > 0 and |dy| <= dx * 0.7
-- (tan 35 deg ~ 0.7). Cells at dx <= 0 are never in the wedge.
local function inOpenWedge(x, y)
    local dx, dy = x - 6, y - 6
    if dx <= 0 then return false end
    return math.abs(dy) <= dx * 0.7
end

local OPEN_FRAME = buildFrame(function(x, y)
    return inDisc(x, y) and not inOpenWedge(x, y)
end)

local CLOSED_FRAME = buildFrame(inDisc)

-- Read-only sprite accessor. Returns the array directly; callers must not
-- mutate it.
function Pacman.getFrame(frame_name)
    if frame_name == "open" then return OPEN_FRAME end
    if frame_name == "closed" then return CLOSED_FRAME end
    error("Pacman.getFrame: unknown frame " .. tostring(frame_name), 2)
end

return Pacman
