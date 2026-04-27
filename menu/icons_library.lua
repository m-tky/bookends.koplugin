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

-- Chip ordering (left-to-right). "all" is the everything-curated default;
-- the eight category chips below mirror the legacy IconPicker.CATALOG groups.
local CHIPS = {
    { key = "all",        label = _("All") },
    { key = "dynamic",    label = _("Dynamic") },
    { key = "device",     label = _("Device") },
    { key = "reading",    label = _("Reading") },
    { key = "time",       label = _("Time") },
    { key = "status",     label = _("Status") },
    { key = "symbols",    label = _("Symbols") },
    { key = "arrows",     label = _("Arrows") },
    { key = "progress",   label = _("Progress") },
    { key = "separators", label = _("Separators") },
}

-- Curated catalogue lifted from bookends_icon_picker.lua. Each entry has:
--   glyph        - the UTF-8 byte sequence to display (and default insert)
--   label        - user-facing description
--   insert_value - optional override (e.g. "%batt_icon" for dynamic tokens)
IconsLibrary.CURATED_BY_CHIP = {
    dynamic = {
        { glyph = "\xEE\x9E\x90", label = _("Battery (changes with level)"), insert_value = "%batt_icon" },
        { glyph = "\xEE\xB2\xA8", label = _("Wi-Fi (changes with status)"),  insert_value = "%wifi" },
    },
    device = {
        { glyph = "\xEF\x83\xAB", label = _("Lightbulb") },
        { glyph = "\xF0\x9F\x92\xA1", label = _("Lightbulb emoji") },
        { glyph = "\xE2\x98\x80", label = _("Sun (filled)") },
        { glyph = "\xEF\x86\x85", label = _("Sun (outline)") },
        { glyph = "\xEF\x86\x86", label = _("Moon") },
        { glyph = "\xEE\x88\x97", label = _("Paper aeroplane") },
        { glyph = "\xEF\x81\x82", label = _("Adjust / contrast") },
        { glyph = "\xEF\x83\xA7", label = _("Lightning bolt") },
        { glyph = "\xEF\x80\x91", label = _("Power") },
        { glyph = "\xEF\x84\x8B", label = _("Mobile") },
        { glyph = "\xEF\x87\xAB", label = _("Wi-Fi") },
        { glyph = "\xEF\x83\x82", label = _("Cloud") },
        { glyph = "\xEE\xA9\x9A", label = _("Memory chip") },
        { glyph = "\xEF\x82\xA0", label = _("HDD / disk") },
    },
    reading = {
        { glyph = "\xEF\x80\xAD", label = _("Book") },
        { glyph = "\xEF\x80\xAE", label = _("Bookmark (filled)") },
        { glyph = "\xEF\x82\x97", label = _("Bookmark (outline)") },
        { glyph = "\xEF\x81\xAE", label = _("Eye") },
        { glyph = "\xEF\x81\xB0", label = _("Eye (hidden)") },
        { glyph = "\xEF\x80\xA4", label = _("Flag") },
        { glyph = "\xEF\x82\x80", label = _("Bar chart") },
        { glyph = "\xEF\x83\xA4", label = _("Tachometer") },
        { glyph = "\xEF\x87\x9E", label = _("Sliders") },
    },
    time = {
        { glyph = "\xEF\x80\x97", label = _("Clock") },
        { glyph = "\xE2\x8F\xB2", label = _("Stopwatch") },
        { glyph = "\xE2\x8C\x9A", label = _("Watch") },
        { glyph = "\xE2\x8F\xB3", label = _("Hourglass") },
        { glyph = "\xE2\x8C\x9B", label = _("Hourglass (filled)") },
        { glyph = "\xEF\x81\xB3", label = _("Calendar") },
        { glyph = "\xEF\x89\xB4", label = _("Calendar (checked)") },
    },
    status = {
        { glyph = "\xEF\x80\x8C", label = _("Check") },
        { glyph = "\xEF\x80\x8D", label = _("Cross") },
        { glyph = "\xEF\x81\x9A", label = _("Info") },
        { glyph = "\xEF\x81\xB1", label = _("Warning") },
        { glyph = "\xEF\x80\x93", label = _("Cog") },
    },
    symbols = {
        { glyph = "\xE2\x98\xBC", label = _("Sun (outline)") },
        { glyph = "\xE2\x99\xA8", label = _("Hot springs / warmth") },
        { glyph = "\xE2\x99\xA0", label = _("Spade") },
        { glyph = "\xE2\x99\xA3", label = _("Club") },
        { glyph = "\xE2\x99\xA5", label = _("Heart") },
        { glyph = "\xE2\x99\xA6", label = _("Diamond suit") },
        { glyph = "\xE2\x98\x85", label = _("Star (filled)") },
        { glyph = "\xE2\x98\x86", label = _("Star (outline)") },
        { glyph = "\xE2\x9C\x93", label = _("Check mark") },
        { glyph = "\xE2\x9C\x97", label = _("Cross mark") },
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
    progress = {
        { glyph = "\xE2\x96\xB0", label = _("Slant block") },
        { glyph = "\xE2\x96\xB1", label = _("Slant block (empty)") },
        { glyph = "\xE2\x96\xAE", label = _("Vertical block") },
        { glyph = "\xE2\x96\xAF", label = _("Vertical block (empty)") },
        { glyph = "\xE2\x96\xA0", label = _("Square (filled)") },
        { glyph = "\xE2\x96\xA1", label = _("Square (empty)") },
        { glyph = "\xE2\x96\x88", label = _("Block (full)") },
        { glyph = "\xE2\x96\x93", label = _("Block (dark)") },
        { glyph = "\xE2\x96\x92", label = _("Block (medium)") },
        { glyph = "\xE2\x96\x91", label = _("Block (light)") },
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

-- Map upstream glyphnames.json's `{set}-` prefix to a human label. The
-- bundled glyphnames.json uses bare prefixes like `cod-account`, `fa-bookmark`,
-- `mdi-clock-outline` (no `nf-` prefix despite some online docs).
local SET_LABELS = {
    cod = "Codicons", custom = "Nerd Fonts custom", dev = "Devicons",
    fa = "FontAwesome 4", fab = "FontAwesome Brands", fae = "FontAwesome Extra",
    far = "FontAwesome Regular", fas = "FontAwesome Solid",
    iec = "IEC Power", indent = "Indent", indentation = "Indentation",
    linea = "Linea", md = "Material Design Icons",
    mdi = "Material Design Icons", oct = "Octicons", pl = "Powerline",
    ple = "Powerline Extra", pom = "Pomicons", seti = "Seti UI",
    weather = "Weather Icons",
}

function IconsLibrary._setLabelOf(name)
    local set = name:match("^([%w]+)%-")
    return SET_LABELS[set] or "Nerd Fonts"
end

function IconsLibrary._suffixOf(name)
    return (name:gsub("^[%w]+%-", ""))
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

-- One-time cell projection of the full Nerd Font names list. The conversion
-- (utf8FromCodepoint + suffix extraction) is identical across All view and
-- search results, so we build the cells table once on first access and reuse
-- it for the rest of the session.
local _all_cells = nil
local function getAllNerdFontCells()
    if _all_cells then return _all_cells end
    local names = loadNerdFontNames()
    _all_cells = {}
    for _i, entry in ipairs(names) do
        _all_cells[#_all_cells + 1] = {
            glyph = utf8FromCodepoint(entry.code),
            label = IconsLibrary._suffixOf(entry.name),
            canonical = entry.name,
            code = entry.code,
            insert_value = utf8FromCodepoint(entry.code),
        }
    end
    return _all_cells
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
        -- All: the entire Nerd Font index (~3,400 entries) for free browsing,
        -- alphabetised which incidentally groups by source set (cod-, fa-,
        -- mdi-, etc.). Curated category chips show smaller hand-picked lists.
        return getAllNerdFontCells()
    end
    return IconsLibrary.CURATED_BY_CHIP[state.active_chip] or {}
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
        on_search_submit = function(query) state.search_query = query end,
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
