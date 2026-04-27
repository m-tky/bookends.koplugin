--- Tokens library: replaces menu/token_picker.lua. Renders the token +
--- conditional catalogues as a chip-filtered list, with conditionals as
--- the "If/else" chip. Search submits across descriptions, token literals,
--- and (for conditionals) expressions.

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LibraryModal = require("menu.library_modal")
local Size = require("ui/size")
local Tokens = require("bookends_tokens")
local UIManager = require("ui/uimanager")
local Utils = require("bookends_utils")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("bookends_i18n").gettext

local Screen = Device.screen

local TokensLibrary = {}

-- Chip strip. "all" merges TOKENS + CONDITIONALS; per-category chips show
-- their tagged tokens; "ifelse" shows only conditionals.
local CHIPS = {
    { key = "all",      label = _("All") },
    { key = "book",     label = _("Book") },
    { key = "progress", label = _("Progress") },
    { key = "bars",     label = _("Bars") },
    { key = "time",     label = _("Time") },
    { key = "session",  label = _("Session") },
    { key = "device",   label = _("Device") },
    { key = "snippets", label = _("Snippets") },
    { key = "ifelse",   label = _("If/else") },
}

-- Token catalogue ported from menu/token_picker.lua's TOKEN_CATALOG. Each
-- entry has a chip key tagging which category-chip filter shows it.
TokensLibrary.TOKENS = {
    -- Metadata → Book
    { description = _("Document title"),                          token = "%title",       chip = "book" },
    { description = _("First author"),                            token = "%author",      chip = "book" },
    { description = _("All authors"),                             token = "%authors",     chip = "book" },
    { description = _("Second author (empty if none)"),           token = "%author_2",    chip = "book" },
    { description = _("Series with index (combined)"),            token = "%series",      chip = "book" },
    { description = _("Series name only"),                        token = "%series_name", chip = "book" },
    { description = _("Series number only"),                      token = "%series_num",  chip = "book" },
    { description = _("Chapter title (deepest)"),                 token = "%chap_title",  chip = "book" },
    { description = _("Chapter title at depth 1"),                token = "%chap_title_1", chip = "book" },
    { description = _("Chapter title at depth 2"),                token = "%chap_title_2", chip = "book" },
    { description = _("Chapter title at depth 3"),                token = "%chap_title_3", chip = "book" },
    { description = _("Current chapter number"),                  token = "%chap_num",    chip = "book" },
    { description = _("Total chapter count"),                     token = "%chap_count",  chip = "book" },
    { description = _("File name"),                               token = "%filename",    chip = "book" },
    { description = _("Book language"),                           token = "%lang",        chip = "book" },
    { description = _("Document format (EPUB, PDF, etc.)"),       token = "%format",      chip = "book" },
    { description = _("Number of highlights"),                    token = "%highlights",  chip = "book" },
    { description = _("Number of notes"),                         token = "%notes",       chip = "book" },
    { description = _("Number of bookmarks"),                     token = "%bookmarks",   chip = "book" },
    { description = _("Total annotations (bookmarks + highlights + notes)"), token = "%annotations", chip = "book" },
    -- Page / progress → Progress
    { description = _("Current page number"),                     token = "%page_num",    chip = "progress" },
    { description = _("Total pages"),                             token = "%page_count",  chip = "progress" },
    { description = _("Book percentage read"),                    token = "%book_pct",    chip = "progress" },
    { description = _("Book percentage left"),                    token = "%book_pct_left", chip = "progress" },
    { description = _("Chapter percentage read"),                 token = "%chap_pct",    chip = "progress" },
    { description = _("Chapter percentage left"),                 token = "%chap_pct_left", chip = "progress" },
    { description = _("Pages read in chapter"),                   token = "%chap_read",   chip = "progress" },
    { description = _("Total pages in chapter"),                  token = "%chap_pages",  chip = "progress" },
    { description = _("Pages left in chapter"),                   token = "%chap_pages_left", chip = "progress" },
    { description = _("Pages left in book"),                      token = "%pages_left",  chip = "progress" },
    -- Progress bars → Bars
    { description = _("Progress bar (configure type in line editor)"), token = "%bar",          chip = "bars" },
    { description = _("Fixed-width progress bar (100px)"),        token = "%bar{100}",         chip = "bars" },
    { description = _("Progress bar, 10px tall"),                 token = "%bar{v10}",         chip = "bars" },
    { description = _("Progress bar, 200px wide and 4px tall"),   token = "%bar{200v4}",       chip = "bars" },
    -- Time / date → Time
    { description = _("Current time (24h, same as %time_24h)"),   token = "%time",         chip = "time" },
    { description = _("12-hour clock"),                           token = "%time_12h",     chip = "time" },
    { description = _("24-hour clock"),                           token = "%time_24h",     chip = "time" },
    { description = _("Date short (28 Mar)"),                     token = "%date",         chip = "time" },
    { description = _("Date long (28 March 2026)"),               token = "%date_long",    chip = "time" },
    { description = _("Date numeric (28/03/2026)"),               token = "%date_numeric", chip = "time" },
    { description = _("Weekday (Friday)"),                        token = "%weekday",      chip = "time" },
    { description = _("Weekday short (Fri)"),                     token = "%weekday_short",chip = "time" },
    { description = _("Custom date/time format (strftime spec)"), token = "%datetime{%d %B}", chip = "time" },
    { description = _("Time left in chapter"),                    token = "%chap_time_left",  chip = "time" },
    { description = _("Time left in book"),                       token = "%book_time_left",  chip = "time" },
    -- Session / reading → Session
    { description = _("Session reading time"),                    token = "%session_time",     chip = "session" },
    { description = _("Session pages read"),                      token = "%session_pages",    chip = "session" },
    { description = _("Pages read today (all books)"),            token = "%pages_today",      chip = "session" },
    { description = _("Reading time today (all books)"),          token = "%time_today",       chip = "session" },
    { description = _("Reading speed (pages/hour)"),              token = "%speed",            chip = "session" },
    { description = _("Average time per page"),                   token = "%avg_page_time",    chip = "session" },
    { description = _("Total reading time for book"),             token = "%book_read_time",   chip = "session" },
    { description = _("Pages read of this book (lifetime)"),      token = "%book_pages_read",  chip = "session" },
    { description = _("Book read percentage (skip-aware)"),       token = "%book_pct_read",    chip = "session" },
    { description = _("Days reading this book"),                  token = "%days_reading_book",chip = "session" },
    { description = _("Pages per day for this book"),             token = "%pages_per_day",    chip = "session" },
    -- Device
    { description = _("Battery level"),                           token = "%batt",         chip = "device" },
    { description = _("Battery icon (dynamic)"),                  token = "%batt_icon",    chip = "device" },
    { description = _("Wi-Fi icon (dynamic)"),                    token = "%wifi",         chip = "device" },
    { description = _("Plugin content (dynamic)"),                token = "%plugin_content", chip = "device" },
    { description = _("Page-turn direction \xE2\x87\x84 (shows when inverted)"), token = "%invert", chip = "device" },
    { description = _("Frontlight brightness"),                   token = "%light",        chip = "device" },
    { description = _("Frontlight warmth"),                       token = "%warmth",       chip = "device" },
    { description = _("RAM used %"),                              token = "%mem",          chip = "device" },
    { description = _("RAM used (MiB)"),                          token = "%ram",          chip = "device" },
    { description = _("Free disk space"),                         token = "%disk",         chip = "device" },
    -- Snippets (full templates rather than single tokens)
    { description = _("Page X of Y, em-dash framed"), token = "\xE2\x80\x94 Page %page_num of %page_count \xE2\x80\x94", chip = "snippets", is_snippet = true },
    { description = _("Title \xE2\x8B\xAE author italic"),                       token = "%title \xE2\x8B\xAE [i]%author[/i]", chip = "snippets", is_snippet = true },
    { description = _("Bookmarks count + label"),                                token = "%bookmarks Bookmark(s)",            chip = "snippets", is_snippet = true },
    { description = _("Highlights count + label"),                               token = "%highlights Highlight(s)",          chip = "snippets", is_snippet = true },
    { description = _("Hourglass session timer + pages"),                        token = "\xE2\x8C\x9B %session_time \xC2\xBB %session_pages page session", chip = "snippets", is_snippet = true },
}

-- Conditional catalogue. Same shape as TOKENS but with `expression` instead
-- of `token` and `chip = "ifelse"`.
TokensLibrary.CONDITIONALS = {
    -- Reference
    { description = _("If Wi-Fi is on"),                              expression = "[if:wifi=on]...[/if]",                chip = "ifelse" },
    { description = _("If connected"),                                expression = "[if:connected=yes]...[/if]",          chip = "ifelse" },
    { description = _("Battery 0\xE2\x80\x93100"),                    expression = "[if:batt<50]...[/if]",                chip = "ifelse" },
    { description = _("If charging"),                                 expression = "[if:charging=yes]...[/if]",           chip = "ifelse" },
    { description = _("If page-turn flipped"),                        expression = "[if:invert=yes]...[/if]",             chip = "ifelse" },
    { description = _("Book progress 0\xE2\x80\x93100"),              expression = "[if:book_pct>50]...[/if]",            chip = "ifelse" },
    { description = _("Chapter progress 0\xE2\x80\x93100"),           expression = "[if:chap_pct>50]...[/if]",            chip = "ifelse" },
    { description = _("Current chapter number"),                      expression = "[if:chap_num=1]...[/if]",             chip = "ifelse" },
    { description = _("Total chapters"),                              expression = "[if:chap_count>20]...[/if]",          chip = "ifelse" },
    { description = _("Pages per hour"),                              expression = "[if:speed>0]...[/if]",                chip = "ifelse" },
    { description = _("Minutes this session"),                        expression = "[if:session>30]...[/if]",             chip = "ifelse" },
    { description = _("Pages this session"),                          expression = "[if:session_pages>0]...[/if]",        chip = "ifelse" },
    { description = _("Pages read today"),                            expression = "[if:pages_today>0]...[/if]",          chip = "ifelse" },
    { description = _("Book read % (skip-aware)"),                    expression = "[if:book_pct_read>50]...[/if]",       chip = "ifelse" },
    { description = _("odd / even"),                                  expression = "[if:page=odd]...[/if]",               chip = "ifelse" },
    { description = _("If frontlight on"),                            expression = "[if:light=on]...[/if]",               chip = "ifelse" },
    { description = _("EPUB / PDF / CBZ / \xE2\x80\xA6"),             expression = "[if:format=EPUB]...[/if]",            chip = "ifelse" },
    { description = _("Current HH:MM (24h)"),                         expression = "[if:time>18:00]...[/if]",             chip = "ifelse" },
    { description = _("Mon\xE2\x80\x93Sun"),                          expression = "[if:day=Mon]...[/if]",                chip = "ifelse" },
    { description = _("If book has title"),                           expression = "[if:title]...[/if]",                  chip = "ifelse" },
    { description = _("If book has author"),                          expression = "[if:author]...[/if]",                 chip = "ifelse" },
    { description = _("If book in series"),                           expression = "[if:series]...[/if]",                 chip = "ifelse" },
    { description = _("If chapter has title"),                        expression = "[if:chap_title]...[/if]",             chip = "ifelse" },
    { description = _("Chapter title at depth 1/2/3"),                expression = "[if:chap_title_2]...[/if]",           chip = "ifelse" },
    { description = _("If book has 2+ authors"),                      expression = "[if:authors>1]...[/if]",              chip = "ifelse" },
    -- Examples (full templates with else branches and content)
    { description = _("Author with et al. for multi-author"),         expression = "[if:authors>1]%author, et al.[else]%author[/if]", chip = "ifelse" },
    { description = _("Wi-Fi icon only when Wi-Fi enabled"),          expression = "[if:wifi=on]%wifi[/if]",              chip = "ifelse" },
    { description = _("Low-battery warning"),                         expression = "[if:batt<20]LOW %batt[/if]",          chip = "ifelse" },
    { description = _("Bolt when charging"),                          expression = "[if:charging=yes]\xE2\x9A\xA1[/if] %batt", chip = "ifelse" },
    { description = _("Arrow when page-turn flipped"),                expression = "[if:invert=yes]\xE2\x87\x84[/if]",    chip = "ifelse" },
    { description = _("Speed once calculated"),                       expression = "[if:speed>0]%speed pg/hr[/if]",       chip = "ifelse" },
    { description = _("Session time after start"),                    expression = "[if:session>0]%session_time[/if]",    chip = "ifelse" },
    { description = _("Odd/even variations"),                         expression = "[if:page=odd]%page_num[else]%page_num[/if]", chip = "ifelse" },
    { description = _("Near end of book"),                            expression = "[if:book_pct>90]Almost done![/if]",   chip = "ifelse" },
    { description = _("Frontlight on/off label"),                     expression = "[if:light=off]Light off[else]Light on[/if]", chip = "ifelse" },
    { description = _("Only for PDFs"),                               expression = "[if:format=PDF]%page_num / %page_count[/if]", chip = "ifelse" },
    { description = _("Late-night reading"),                          expression = "[if:time>22:00]Late night reading![/if]", chip = "ifelse" },
    { description = _("Weekends"),                                    expression = "[if:day=Sat or day=Sun]Weekend![/if]", chip = "ifelse" },
    { description = _("Time window"),                                 expression = "[if:time>=18:00 and time<18:30]6\xE2\x80\x936:30[/if]", chip = "ifelse" },
    { description = _("Non-series books"),                            expression = "[if:not series]Standalone[/if]",     chip = "ifelse" },
    { description = _("Fall back to shallower chapter"),              expression = "[if:chap_title_2]%chap_title_2[else]%chap_title_1[/if]", chip = "ifelse" },
    { description = _("Long books (20+ chapters)"),                   expression = "[if:chap_count>20]Long read[/if]",   chip = "ifelse" },
    { description = _("Chapter title only when different from book title"), expression = "%title[if:chap_title_1!=@title] \xE2\x80\xA2 %chap_title_1[/if]", chip = "ifelse" },
}

--- Filter the merged token + conditional list by chip and search query.
--- All chip → both lists merged; If/else chip → conditionals only; other
--- chips → tokens with matching chip tag.
function TokensLibrary._currentItems(active_chip, search_query)
    local items = {}
    if active_chip == "all" or not active_chip then
        for _i, t in ipairs(TokensLibrary.TOKENS) do items[#items + 1] = t end
        for _i, c in ipairs(TokensLibrary.CONDITIONALS) do items[#items + 1] = c end
    elseif active_chip == "ifelse" then
        for _i, c in ipairs(TokensLibrary.CONDITIONALS) do items[#items + 1] = c end
    else
        for _i, t in ipairs(TokensLibrary.TOKENS) do
            if t.chip == active_chip then items[#items + 1] = t end
        end
    end
    if search_query and #search_query >= 2 then
        local filtered = {}
        for _i, item in ipairs(items) do
            local hay = (item.description or "")
                .. " " .. (item.token or "")
                .. " " .. (item.expression or "")
            if LibraryModal._matchesQuery(hay, search_query) then
                filtered[#filtered + 1] = item
                if #filtered >= 200 then break end
            end
        end
        return filtered
    end
    return items
end

--- Render a single token / conditional row as a card. Two-line:
---   Line 1 (bold): description
---   Line 2:        for tokens: "%token → expansion"; for conditionals: expression
function TokensLibrary._renderRow(item, slot_dimen, doc_ctx)
    local Font = require("ui/font")
    local TextWidget = require("ui/widget/textwidget")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local GestureRange = require("ui/gesturerange")
    local inner_pad = Screen:scaleBySize(12)
    local card_h = slot_dimen.h
    local content_w = slot_dimen.w - 2 * inner_pad - 2 * Size.border.thin

    local line1 = TextWidget:new{
        text = item.description or "",
        face = Font:getFace("cfont", 16),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = content_w,
    }

    local line2_text
    if item.expression then
        line2_text = item.expression
    elseif item.is_snippet then
        line2_text = item.token
    else
        local expansion = ""
        if doc_ctx and item.token then
            local ok, val = pcall(Tokens.expand, item.token, doc_ctx.ui,
                doc_ctx.session_elapsed, doc_ctx.session_pages,
                nil, doc_ctx.tick_mult, nil, nil,
                { stats_cache = doc_ctx.stats_cache })
            if ok and val and val ~= "" and val ~= item.token then
                expansion = " \xE2\x86\x92 " .. Utils.truncateUtf8(val, 25)
            end
        end
        line2_text = (item.token or "") .. expansion
    end
    local line2 = TextWidget:new{
        text = line2_text,
        face = Font:getFace("cfont", 13),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = content_w,
    }

    local stack = VerticalGroup:new{
        align = "left",
        line1,
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
        line2,
    }
    local card_frame = FrameContainer:new{
        bordersize = Size.border.thin,
        radius = Size.radius.default,
        padding = 0,
        padding_left = inner_pad,
        padding_right = inner_pad,
        padding_top = 0,
        padding_bottom = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        LeftContainer:new{
            dimen = Geom:new{ w = content_w, h = card_h - 2 * Size.border.thin },
            stack,
        },
    }
    local card = InputContainer:new{
        dimen = Geom:new{ w = slot_dimen.w, h = card_h },
        card_frame,
    }
    card.ges_events = {
        TapSelect = { GestureRange:new{ ges = "tap", range = card.dimen } },
    }
    return card
end

--- Build a per-render document context for live token expansion. Builds a
--- shared stats_cache so v5.6 SQLite-backed tokens don't re-query per row.
local function buildDocContext(self)
    if not (self.bookends and self.bookends.ui) then return nil end
    local b = self.bookends
    return {
        ui              = b.ui,
        session_elapsed = b:getSessionElapsed(),
        session_pages   = b:getSessionPages(),
        tick_mult       = b.settings:readSetting("tick_width_multiplier", b.DEFAULT_TICK_WIDTH_MULTIPLIER),
        stats_cache     = {},
    }
end

--- Show the tokens library modal. on_select(value) is called with the
--- chosen token / expression when the user taps a row.
function TokensLibrary:show(bookends, on_select)
    self.bookends = bookends
    local state = { active_chip = "all", search_query = nil }
    -- Doc context refreshed on each render so live token expansions reflect
    -- the current session (elapsed time / pages read tick over while the
    -- modal is open).
    local function freshDocCtx() return buildDocContext(self) end
    local doc_ctx = freshDocCtx()
    local self_ref = self

    local config = {
        title = _("Tokens library"),
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
            -- Mirror the icons-modal contract: chip taps clear active search
            -- so the chip-filtered view becomes the consistent visible state.
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
        search_placeholder = function() return _("Search tokens by name, value, or expression…") end,
        on_search_submit = function(query) state.search_query = query end,
        rows_per_page = 6,
        item_count = function() return #TokensLibrary._currentItems(state.active_chip, state.search_query) end,
        item_at = function(idx) return TokensLibrary._currentItems(state.active_chip, state.search_query)[idx] end,
        row_renderer = function(item, dimen)
            local row = TokensLibrary._renderRow(item, dimen, doc_ctx)
            -- Bind the tap inside the row_renderer closure rather than via a
            -- generic config.on_item_tap hook — the row's InputContainer is
            -- already gesture-ranged in _renderRow, we just need to attach
            -- the action that fires the on_select callback + closes the modal.
            row.onTapSelect = function()
                local val = item.token or item.expression
                if self_ref.modal then UIManager:close(self_ref.modal); self_ref.modal = nil end
                if on_select and val then on_select(val) end
                return true
            end
            return row
        end,
        footer_actions = {
            { key = "close", label = _("Close"), on_tap = function()
                if self_ref.modal then UIManager:close(self_ref.modal); self_ref.modal = nil end
            end },
        },
    }
    self.modal = LibraryModal:new{ config = config }
    UIManager:show(self.modal)
end

return TokensLibrary
