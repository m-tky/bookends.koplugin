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

-- Closed frame seam: a short horizontal notch at the leading edge,
-- mid-row, so the closed silhouette reads as "mouth closed" instead of
-- a perfect circle. Three cells: (10,6), (11,6), (12,6).
local function inClosedSeam(x, y)
    local dx, dy = x - 6, y - 6
    return dy == 0 and dx >= 4
end

local OPEN_FRAME = buildFrame(function(x, y)
    return inDisc(x, y) and not inOpenWedge(x, y)
end)

local CLOSED_FRAME = buildFrame(function(x, y)
    return inDisc(x, y) and not inClosedSeam(x, y)
end)

-- Read-only sprite accessor. Returns the array directly; callers must not
-- mutate it.
function Pacman.getFrame(frame_name)
    if frame_name == "open" then return OPEN_FRAME end
    if frame_name == "closed" then return CLOSED_FRAME end
    error("Pacman.getFrame: unknown frame " .. tostring(frame_name), 2)
end

-- Read bit (x, y) from a frame array.
local function readBit(frame, x, y)
    local mask = 2 ^ x
    return (math.floor(frame[y + 1] / mask) % 2) == 1
end

-- Write bit (x, y) into a row-array under construction. Mutates `rows`.
local function setBit(rows, x, y)
    rows[y + 1] = (rows[y + 1] or 0) + 2 ^ x
end

-- Rotate a 13x13 frame by `steps` 90-degree CW turns.
-- Returns a new frame; input is not mutated.
-- Coordinate mapping for one CW step (size 13):
--   (x, y) -> (12 - y, x)
function Pacman.rotate(frame, steps)
    steps = steps % 4
    if steps == 0 then
        -- Defensive copy so callers can treat the return as fresh.
        local out = {}
        for y = 0, 12 do out[y + 1] = frame[y + 1] end
        return out
    end
    local current = frame
    for _step = 1, steps do
        local next_rows = {}
        for y = 0, 12 do next_rows[y + 1] = 0 end
        for y = 0, 12 do
            for x = 0, 12 do
                if readBit(current, x, y) then
                    setBit(next_rows, 12 - y, x)
                end
            end
        end
        current = next_rows
    end
    return current
end

-- Map a direction string ("right" | "down" | "left" | "up") to the number
-- of 90-degree CW rotations needed to face that direction from a
-- right-facing base. Unknown directions default to 0.
function Pacman.directionToSteps(direction)
    if direction == "down" then return 1 end
    if direction == "left" then return 2 end
    if direction == "up" then return 3 end
    return 0
end

-- Lay out dots and a power pellet along an unread region of `length` device
-- pixels. Returns:
--   { dots   = { d1, d2, ... },   -- ascending start offsets of each dot
--     pellet = p_start | nil }     -- start offset of the pellet (nil if no room)
--
-- length        total length of the unread region (px)
-- dot_block     dot side length (px), square
-- pellet_block  pellet side length (px), square; should be >= dot_block
--
-- Layout rules:
--   * pellet sits flush against the far end:   pellet = length - pellet_block
--   * dots placed at pitch = max(dot_block*3, floor(length*0.6))
--     ...except the helper picks a pitch that lets at least one dot fit
--     when length is short. Concretely: pitch = max(dot_block*3, floor(length*0.6))
--     evaluated once; dots stride from dot_block (small margin from start)
--     to first overlap with pellet.
--   * any dot whose footprint would overlap the pellet is skipped.
function Pacman.layoutDots(length, dot_block, pellet_block)
    local result = { dots = {} }
    if length < dot_block + pellet_block then
        -- No room for both a dot and a pellet.
        return result
    end
    result.pellet = length - pellet_block

    -- Pitch is a fixed multiple of dot size, not scaled with bar length
    -- (length-scaling was too aggressive on long bars and read as huge
    -- empty gaps between dots).
    local pitch = dot_block * 4
    -- Start half a pitch in (floored to at least one dot width) so the
    -- strip breathes from the sprite. Then stride by pitch.
    local cursor = math.max(dot_block, math.floor(pitch / 2))
    while cursor + dot_block <= result.pellet do
        table.insert(result.dots, cursor)
        cursor = cursor + pitch
    end

    return result
end

return Pacman
