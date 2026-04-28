--- Icons library: replaces bookends_icon_picker.lua. Renders the curated
--- catalogue in browse mode (chip-filtered grid) and the full Nerd Font
--- name set in search mode (lazy-loaded on first search submit).

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local LibraryModal = require("menu.library_modal")
local Notification = require("ui/widget/notification")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("bookends_i18n").gettext
local T = require("ffi/util").template

local Screen = Device.screen

local IconsLibrary = {}

-- Chip ordering (left-to-right). "all" is the full Nerd Font index;
-- the curated category chips below show smaller hand-picked lists.
local CHIPS = {
    { key = "all",        label = _("All") },
    { key = "dynamic",    label = _("Dynamic") },
    { key = "device",     label = _("Device") },
    { key = "reading",    label = _("Reading") },
    { key = "time",       label = _("Time") },
    { key = "status",     label = _("Status") },
    { key = "symbols",    label = _("Symbols") },
    { key = "arrows",     label = _("Arrows") },
    { key = "blocks",     label = _("Blocks") },
    { key = "separators", label = _("Separators") },
}

-- Curated catalogue. Two entry shapes:
--   { code = 0xNNNN, ... }   - Nerd Font glyph picked by codepoint. Label
--                              comes from the font's cmap unless overridden.
--   { glyph = "<bytes>", label = "..." }
--                            - Pure-Unicode glyph (not in the Nerd Font cmap).
--                              Label is the hand-written description.
-- Optional fields: `label` (override the cmap name), `insert_value` (token
-- string inserted instead of the literal glyph — used for dynamic icons).
IconsLibrary.CURATED_BY_CHIP = {
    -- Dynamic icons resolve at render time to a glyph that reflects current
    -- state (battery level, Wi-Fi status). Labels stay human-written so the
    -- "(changes with level)" cue is preserved.
    dynamic = {
        { code = 0xE790, label = _("Battery (changes with level)"), insert_value = "%batt_icon" },
        { code = 0xECA8, label = _("Wi-Fi (changes with status)"),  insert_value = "%wifi" },
    },
    device = {
        { code = 0xE778 },   -- battery
        { code = 0xE783 },   -- battery-charging
        { code = 0xE782 },   -- battery-alert
        { code = 0xE78D },   -- battery-outline
        { code = 0xECA8 },   -- wifi
        { code = 0xECA9 },   -- wifi-off
        { code = 0xEBA1 },   -- signal
        { code = 0xEDF1 },   -- network
        { code = 0xE7AE },   -- bluetooth
        { code = 0xE81B },   -- cellphone
        { code = 0xE266 },   -- chip
        { code = 0xECED },   -- disk
        { code = 0xE268 },   -- cloud
        { code = 0xF013 },   -- cog
    },
    reading = {
        { code = 0xE7B9 },   -- book
        { code = 0xE7BD },   -- book-open-variant
        { code = 0xE7BE },   -- book-variant
        { code = 0xE7BA },   -- book-multiple
        { code = 0xEA30 },   -- library
        { code = 0xE7BF },   -- bookmark
        { code = 0xE7C2 },   -- bookmark-outline
        { code = 0xE7C0 },   -- bookmark-check
        { code = 0xEA99 },   -- note
        { code = 0xEAEA },   -- pencil
        { code = 0xEAE9 },   -- pen
        { code = 0xEB46 },   -- read
    },
    time = {
        { code = 0xE84F },   -- clock
        { code = 0xE851 },   -- clock-fast
        { code = 0xE850 },   -- clock-end
        { code = 0xE71F },   -- alarm
        { code = 0xEE8C },   -- alarm-bell
        { code = 0xE7EC },   -- calendar
        { code = 0xE7ED },   -- calendar-blank
        { code = 0xE7EF },   -- calendar-clock
        { code = 0xE7F5 },   -- calendar-today
        { code = 0xE7EE },   -- calendar-check
        { code = 0xEC1A },   -- timer
        { code = 0xEC1E },   -- timer-sand
        { code = 0xEC88 },   -- watch
    },
    status = {
        { code = 0xE82B },   -- check
        { code = 0xE82C },   -- check-all
        { code = 0xECDF },   -- check-circle
        { code = 0xE855 },   -- close
        { code = 0xE858 },   -- close-circle
        { code = 0xE725 },   -- alert
        { code = 0xE727 },   -- alert-circle
        { code = 0xE728 },   -- alert-octagon
        { code = 0xF449 },   -- info
        { code = 0xE904 },   -- exclamation
        { code = 0xF420 },   -- question
        { code = 0xEA3D },   -- lock
        { code = 0xEA3E },   -- lock-open
        { code = 0xEB97 },   -- shield
        { code = 0xEE7E },   -- shield-half-full
    },
    -- Symbols are pure Unicode (suit symbols, dagger, pilcrow, etc.) — they
    -- aren't in the Nerd Font cmap, so we hand-label them. Check / cross
    -- have moved to the Status chip where they have richer cmap-named
    -- variants (check, check-all, check-circle, …).
    symbols = {
        { glyph = "\xE2\x98\xBC", label = _("Sun (outline)") },
        { glyph = "\xE2\x99\xA8", label = _("Hot springs / warmth") },
        { glyph = "\xE2\x99\xA0", label = _("Spade") },
        { glyph = "\xE2\x99\xA3", label = _("Club") },
        { glyph = "\xE2\x99\xA5", label = _("Heart") },
        { glyph = "\xE2\x99\xA6", label = _("Diamond suit") },
        { glyph = "\xE2\x98\x85", label = _("Star (filled)") },
        { glyph = "\xE2\x98\x86", label = _("Star (outline)") },
        { glyph = "\xE2\x88\x9E", label = _("Infinity") },
        { glyph = "\xC2\xA7",     label = _("Section sign") },
        { glyph = "\xC2\xB6",     label = _("Pilcrow / paragraph") },
        { glyph = "\xE2\x80\xA0", label = _("Dagger") },
        { glyph = "\xE2\x80\xA1", label = _("Double dagger") },
        { glyph = "\xC2\xA9",     label = _("Copyright") },
        { glyph = "\xE2\x84\x96", label = _("Numero") },
        { glyph = "\xE2\x9A\xA1", label = _("High voltage") },
    },
    arrows = {
        { glyph = "\xE2\x86\x90", label = _("Arrow left") },
        { glyph = "\xE2\x86\x92", label = _("Arrow right") },
        { glyph = "\xE2\x86\x91", label = _("Arrow up") },
        { glyph = "\xE2\x86\x93", label = _("Arrow down") },
        { glyph = "\xE2\x87\x90", label = _("Double arrow left") },
        { glyph = "\xE2\x87\x92", label = _("Double arrow right") },
        { glyph = "\xE2\x87\x91", label = _("Double arrow up") },
        { glyph = "\xE2\x87\x93", label = _("Double arrow down") },
        { glyph = "\xE2\x87\x84", label = _("Arrows left-right") },
        { glyph = "\xE2\x87\x89", label = _("Double arrows right") },
        { glyph = "\xE2\xA5\x96", label = _("Left harpoon with right arrow") },
        { glyph = "\xE2\xA4\xBB", label = _("Curved back arrow") },
        { glyph = "\xE2\x86\xA2", label = _("Arrow left with tail") },
        { glyph = "\xE2\x86\xA3", label = _("Arrow right with tail") },
        { glyph = "\xE2\xA4\x9F", label = _("Arrow left to bar") },
        { glyph = "\xE2\xA4\xA0", label = _("Arrow right to bar") },
        { glyph = "\xE2\x86\xA9", label = _("Arrow left hooked") },
        { glyph = "\xE2\x86\xAA", label = _("Arrow right hooked") },
        { glyph = "\xE2\xA4\xB4", label = _("Arrow right then up") },
        { glyph = "\xE2\xA4\xB5", label = _("Arrow right then down") },
        { glyph = "\xE2\x86\xB0", label = _("Arrow up then left") },
        { glyph = "\xE2\x86\xB1", label = _("Arrow up then right") },
        { glyph = "\xE2\x86\xB2", label = _("Arrow down then left") },
        { glyph = "\xE2\x86\xB3", label = _("Arrow down then right") },
        { glyph = "\xE2\x86\xBA", label = _("Circle arrow left") },
        { glyph = "\xE2\x86\xBB", label = _("Circle arrow right") },
        { glyph = "\xE2\x9E\x94", label = _("Heavy arrow right") },
        { glyph = "\xE2\x9E\x9C", label = _("Heavy round arrow right") },
        { glyph = "\xE2\x9E\x9D", label = _("Triangle-head right") },
        { glyph = "\xE2\x9E\x9E", label = _("Heavy triangle right") },
        { glyph = "\xE2\x9E\xA4", label = _("Arrowhead right") },
        { glyph = "\xE2\x9F\xB5", label = _("Long arrow left") },
        { glyph = "\xE2\x9F\xB6", label = _("Long arrow right") },
        { glyph = "\xE2\x96\xB6", label = _("Triangle right") },
        { glyph = "\xE2\x97\x80", label = _("Triangle left") },
        { glyph = "\xE2\x96\xB2", label = _("Triangle up") },
        { glyph = "\xE2\x96\xBC", label = _("Triangle down") },
        { glyph = "\xE2\x80\xB9", label = _("Single angle left") },
        { glyph = "\xE2\x80\xBA", label = _("Single angle right") },
        { glyph = "\xC2\xAB",     label = _("Double angle left") },
        { glyph = "\xC2\xBB",     label = _("Double angle right") },
        { glyph = "\xE2\x98\x9B", label = _("Pointing right (black)") },
        { glyph = "\xE2\x98\x9E", label = _("Pointing right") },
        { glyph = "\xE2\x98\x9C", label = _("Pointing left") },
        { glyph = "\xE2\x98\x9D", label = _("Pointing up") },
        { glyph = "\xE2\x98\x9F", label = _("Pointing down") },
    },
    -- Solid block / shape palette. Designed for hand-rolled progress bars
    -- assembled with [if:book_pct>X]…[/if] nesting — pairs of filled/empty
    -- variants let you compose proportional fills, and the eighth-block
    -- ramps give finer granularity than the four shading levels.
    blocks = {
        -- Full blocks and shading
        { glyph = "\xE2\x96\x88", label = _("Block (full)") },
        { glyph = "\xE2\x96\x93", label = _("Block (dark)") },
        { glyph = "\xE2\x96\x92", label = _("Block (medium)") },
        { glyph = "\xE2\x96\x91", label = _("Block (light)") },
        -- Half blocks
        { glyph = "\xE2\x96\x80", label = _("Upper half block") },
        { glyph = "\xE2\x96\x84", label = _("Lower half block") },
        { glyph = "\xE2\x96\x8C", label = _("Left half block") },
        { glyph = "\xE2\x96\x90", label = _("Right half block") },
        -- Lower N/8 ramp
        { glyph = "\xE2\x96\x81", label = _("Lower 1/8 block") },
        { glyph = "\xE2\x96\x82", label = _("Lower 1/4 block") },
        { glyph = "\xE2\x96\x83", label = _("Lower 3/8 block") },
        { glyph = "\xE2\x96\x85", label = _("Lower 5/8 block") },
        { glyph = "\xE2\x96\x86", label = _("Lower 3/4 block") },
        { glyph = "\xE2\x96\x87", label = _("Lower 7/8 block") },
        -- Left N/8 ramp (right-to-left fill)
        { glyph = "\xE2\x96\x8F", label = _("Left 1/8 block") },
        { glyph = "\xE2\x96\x8E", label = _("Left 1/4 block") },
        { glyph = "\xE2\x96\x8D", label = _("Left 3/8 block") },
        { glyph = "\xE2\x96\x8B", label = _("Left 5/8 block") },
        { glyph = "\xE2\x96\x8A", label = _("Left 3/4 block") },
        { glyph = "\xE2\x96\x89", label = _("Left 7/8 block") },
        -- Squares and rectangles
        { glyph = "\xE2\x96\xA0", label = _("Square (filled)") },
        { glyph = "\xE2\x96\xA1", label = _("Square (empty)") },
        { glyph = "\xE2\x96\xAC", label = _("Rectangle (filled)") },
        { glyph = "\xE2\x96\xAD", label = _("Rectangle (empty)") },
        { glyph = "\xE2\x96\xAE", label = _("Vertical block") },
        { glyph = "\xE2\x96\xAF", label = _("Vertical block (empty)") },
        { glyph = "\xE2\x96\xB0", label = _("Slant block") },
        { glyph = "\xE2\x96\xB1", label = _("Slant block (empty)") },
        -- Circles
        { glyph = "\xE2\x97\x8F", label = _("Circle (filled)") },
        { glyph = "\xE2\x97\x8B", label = _("Circle (empty)") },
        { glyph = "\xE2\x97\x90", label = _("Circle (left half)") },
        { glyph = "\xE2\x97\x91", label = _("Circle (right half)") },
        { glyph = "\xE2\x97\x92", label = _("Circle (lower half)") },
        { glyph = "\xE2\x97\x93", label = _("Circle (upper half)") },
        -- Diamonds
        { glyph = "\xE2\x97\x86", label = _("Diamond (filled)") },
        { glyph = "\xE2\x97\x87", label = _("Diamond (empty)") },
    },
    separators = {
        { glyph = "|",             label = _("Vertical bar") },
        { glyph = "\xE2\x80\xA2", label = _("Bullet") },
        { glyph = "\xC2\xB7",     label = _("Middle dot") },
        { glyph = "\xE2\x8B\xAE", label = _("Vertical ellipsis") },
        { glyph = "\xE2\x97\x86", label = _("Diamond") },
        { glyph = "\xE2\x80\x94", label = _("Em dash") },
        { glyph = "\xE2\x80\x93", label = _("En dash") },
        { glyph = "\xE2\x80\xA6", label = _("Horizontal ellipsis") },
        { glyph = "/",             label = _("Slash") },
        { glyph = "\xE2\x88\x95", label = _("Division slash") },
        { glyph = "\xE2\x81\x84", label = _("Fraction slash") },
        { glyph = "\xE2\x81\x84\xE2\x81\x84", label = _("Double fraction slash") },
        { glyph = "~",             label = _("Tilde") },
        { glyph = "\xE2\x80\xA3", label = _("Triangular bullet") },
    },
}

-- Lazy-loaded full Nerd Font names data. nil until first search.
local nerdfont_names = nil

local function loadNerdFontNames()
    if nerdfont_names == nil then
        nerdfont_names = require("bookends_nerdfont_names") or {}
    end
    return nerdfont_names
end

-- Convert a Unicode codepoint integer to its UTF-8 byte sequence.
local function utf8FromCodepoint(cp)
    if cp < 0x80 then
        return string.char(cp)
    elseif cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40),
                           0x80 + (cp % 0x40))
    elseif cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000),
                           0x80 + math.floor((cp % 0x1000) / 0x40),
                           0x80 + (cp % 0x40))
    else
        return string.char(0xF0 + math.floor(cp / 0x40000),
                           0x80 + math.floor((cp % 0x40000) / 0x1000),
                           0x80 + math.floor((cp % 0x1000) / 0x40),
                           0x80 + (cp % 0x40))
    end
end

-- One-time cell projection of the full Nerd Font names list. Both the All
-- view and the search filter consume this same list, so we build it once
-- on first access and reuse it for the rest of the session. Label uses the
-- font's own cmap name verbatim (e.g. "checkbox-blank-circle-outline") so
-- the displayed string matches what search hits — earlier code stripped a
-- leading hyphen-segment under a wrong assumption that the data carried
-- set prefixes like `mdi-`/`fa-`/`cod-`, which mangled half the labels and
-- caused mystery search hits like "box" → "blank-circle".
local _all_cells = nil
local function getAllNerdFontCells()
    if _all_cells then return _all_cells end
    local names = loadNerdFontNames()
    _all_cells = {}
    for _i, entry in ipairs(names) do
        _all_cells[#_all_cells + 1] = {
            glyph = utf8FromCodepoint(entry.code),
            label = entry.name,
            canonical = entry.name,
            code = entry.code,
            insert_value = utf8FromCodepoint(entry.code),
        }
    end
    return _all_cells
end

-- Reverse lookup of the Nerd Font index by UTF-8 byte sequence. Used to
-- swap curated entries' hand-written labels for their canonical cmap name
-- (e.g. "Memory chip" → "memory") so search by partial name finds them.
local _bytes_to_entry = nil
local function getNerdFontEntryByBytes(bytes)
    if _bytes_to_entry == nil then
        _bytes_to_entry = {}
        local names = loadNerdFontNames()
        for _i, entry in ipairs(names) do
            _bytes_to_entry[utf8FromCodepoint(entry.code)] = entry
        end
    end
    return _bytes_to_entry[bytes]
end

-- Project a curated chip's entries into render cells. Two input shapes:
--   { code = 0xNNNN, ... }   - Nerd Font glyph; bytes derived via
--                              utf8FromCodepoint, label from cmap unless
--                              the entry overrides via `label = ...`
--                              (used by the `dynamic` chip to preserve the
--                              "(changes with level)" cue on tokens).
--   { glyph = "<bytes>", label = "..." }
--                            - Pure-Unicode glyph not in the Nerd Font cmap.
--                              Bytes and label flow through as-is.
local function projectCuratedItems(chip_key)
    local items = IconsLibrary.CURATED_BY_CHIP[chip_key] or {}
    local out = {}
    for _i, item in ipairs(items) do
        local cell = { insert_value = item.insert_value }
        if item.code then
            cell.glyph = utf8FromCodepoint(item.code)
            cell.code = item.code
            local entry = getNerdFontEntryByBytes(cell.glyph)
            cell.canonical = entry and entry.name or nil
            cell.label = item.label or cell.canonical or string.format("U+%04X", item.code)
        else
            cell.glyph = item.glyph
            cell.label = item.label
        end
        out[#out + 1] = cell
    end
    return out
end

-- Build the visible item list for the current chip + search state.
local function currentItemList(state)
    if state.search_query and #state.search_query >= 2 then
        -- Search across the full Nerd Font index; cap at 200 to keep
        -- pagination sensible. Reuse the cached cell projections.
        local cells = getAllNerdFontCells()
        local items = {}
        for _i, cell in ipairs(cells) do
            if LibraryModal._matchesQuery(cell.canonical, state.search_query) then
                items[#items + 1] = cell
                if #items >= 200 then break end
            end
        end
        return items
    end
    if state.active_chip == "all" or not state.active_chip then
        -- All: the entire Nerd Font index (~2,800 entries) for free browsing,
        -- alphabetised by cmap name. Curated category chips show smaller
        -- hand-picked lists, with cmap-name labels where applicable.
        return getAllNerdFontCells()
    end
    return projectCuratedItems(state.active_chip)
end

-- Render a single icon cell: glyph centred large, label below.
function IconsLibrary._renderCell(item, dimen)
    local Font = require("ui/font")
    local TextWidget = require("ui/widget/textwidget")
    local glyph_w = TextWidget:new{
        text = item.glyph or "",
        face = Font:getFace("symbols", 36),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }
    local label_w = TextWidget:new{
        text = item.label or "",
        face = Font:getFace("cfont", 11),
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = dimen.w - Screen:scaleBySize(8),
    }
    local stack = VerticalGroup:new{
        align = "center",
        glyph_w,
        VerticalSpan:new{ width = Size.span.vertical_default or 4 },
        label_w,
    }
    return FrameContainer:new{
        bordersize = Size.border.thin,
        radius = Size.radius.default,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = dimen.w, h = dimen.h },
            stack,
        },
    }
end

-- Brief notification with the canonical name + codepoint on long-tap.
function IconsLibrary._showCellTooltip(item)
    if not item.canonical then return end
    local code_str = item.code and string.format("U+%04X", item.code) or ""
    local body = item.canonical .. (code_str ~= "" and (" · " .. code_str) or "")
    UIManager:show(Notification:new{ text = body, timeout = 3 })
end

--- Open the icons library modal. on_select is called with the chosen
--- glyph (or token, for dynamic entries) when the user taps a cell.
function IconsLibrary:show(on_select)
    -- Captures the runtime state used by the config callbacks. This lives in
    -- a closure rather than on the modal so taps/chips/search can mutate it
    -- without going through LibraryModal's own state.
    local state = { active_chip = "all", search_query = nil }
    local self_ref = self
    local config
    config = {
        title = _("Icons library"),
        chip_strip = function()
            local out = {}
            for _i, c in ipairs(CHIPS) do
                out[#out + 1] = {
                    key = c.key, label = c.label,
                    is_active = (c.key == state.active_chip) and true or false,
                }
            end
            return out
        end,
        on_chip_tap = function(chip_key)
            state.active_chip = chip_key
            -- Tapping a category chip while a search is active doesn't make
            -- sense (the chips filter the curated catalogue, search hits the
            -- full Nerd Font index — there's no overlap). Clear the search
            -- across all three layers — the icons-state, the modal-level
            -- search_query (which gets re-applied to the InputText on next
            -- refresh), and the InputText's own text — so the chip-filtered
            -- curated view becomes the consistent visible state.
            if state.search_query then
                state.search_query = nil
                if self_ref.modal then
                    self_ref.modal.search_query = nil
                    if self_ref.modal._search_input then
                        self_ref.modal._search_input:setText("")
                    end
                end
            end
        end,
        search_placeholder = function()
            local names = loadNerdFontNames()
            return T(_("Search %1 icons by name…"), tostring(#names))
        end,
        on_search_submit = function(query)
            state.search_query = query
            -- Search hits the full Nerd Font index regardless of the active
            -- chip, so the chip strip should reflect that by snapping back
            -- to "All" — otherwise the highlighted chip lies about what's
            -- visible. The chip-strip callback rebuilds is_active from
            -- state.active_chip on the next refresh.
            if query then state.active_chip = "all" end
        end,
        grid_cols = 4,
        cells_per_page = function() return 4 * 4 end,    -- 4 cols × 4 rows
        cell_renderer = IconsLibrary._renderCell,
        cell_long_tap = IconsLibrary._showCellTooltip,
        on_cell_tap = function(item)
            local val = item.insert_value or item.glyph
            if self_ref.modal then UIManager:close(self_ref.modal); self_ref.modal = nil end
            if on_select then on_select(val) end
        end,
        item_count = function() return #currentItemList(state) end,
        item_at = function(idx) return currentItemList(state)[idx] end,
        footer_actions = {
            { key = "close", label = _("Close"), on_tap = function()
                if self_ref.modal then UIManager:close(self_ref.modal); self_ref.modal = nil end
            end },
        },
    }
    self.modal = LibraryModal:new{ config = config }
    UIManager:show(self.modal)
end

return IconsLibrary
