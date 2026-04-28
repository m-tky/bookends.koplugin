--- Tokens library: replaces menu/token_picker.lua. Renders the token +
--- conditional catalogues as a chip-filtered list. Conditionals are split
--- across two chips: "If/else" (reference patterns with `...` placeholders)
--- and "Examples" (full templates with content). Icon-only tokens
--- (%batt_icon, %wifi, %light_icon, %warmth_icon, %nightmode, %invert) live
--- in the icons library Dynamic chip, not here. Search submits across
--- descriptions, token literals, and (for conditionals) expressions.

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
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

-- Catalogue tables (chip list, regular tokens, conditional templates)
-- live in menu/tokens_catalogue.lua so the curator web app at
-- tools/curate_catalogues.py has a single file to round-trip.
local Catalogue = require("menu.tokens_catalogue")
local CHIPS = Catalogue.CHIPS
TokensLibrary.TOKENS = Catalogue.TOKENS
TokensLibrary.CONDITIONALS = Catalogue.CONDITIONALS

--- Filter the merged token + conditional list by chip and search query.
--- All chip → both lists merged; If/else chip → conditionals only; other
--- chips → tokens with matching chip tag.
function TokensLibrary._currentItems(active_chip, search_query)
    local items = {}
    if active_chip == "all" or not active_chip then
        for _i, t in ipairs(TokensLibrary.TOKENS) do items[#items + 1] = t end
        for _i, c in ipairs(TokensLibrary.CONDITIONALS) do items[#items + 1] = c end
    else
        -- Single uniform filter — works for both regular tokens (chip in
        -- {book, progress, time, session, device}) and conditionals
        -- (chip = "ifelse"). The "templates" chip merges plain-text
        -- snippets (TOKENS with chip = "templates") and conditional
        -- templates (CONDITIONALS with chip = "templates").
        for _i, t in ipairs(TokensLibrary.TOKENS) do
            if t.chip == active_chip then items[#items + 1] = t end
        end
        for _i, c in ipairs(TokensLibrary.CONDITIONALS) do
            if c.chip == active_chip then items[#items + 1] = c end
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

--- Per-render document context for live token expansion. pcall'd so any
--- nil-deref or missing API on the Bookends instance just disables
--- expansion rather than crashing the modal open.
local function buildDocContext(bookends)
    if not bookends then return nil end
    local ok, ctx = pcall(function()
        if not bookends.ui then return nil end
        return {
            ui              = bookends.ui,
            session_elapsed = bookends:getSessionElapsed(),
            session_pages   = bookends:getSessionPages(),
            tick_mult       = bookends.settings:readSetting(
                "tick_width_multiplier", bookends.DEFAULT_TICK_WIDTH_MULTIPLIER),
            stats_cache     = {},
        }
    end)
    return ok and ctx or nil
end

--- Render a single token / conditional row as a card. Two-line:
---   Line 1 (bold): description
---   Line 2:        for conditionals: expression; for tokens: '%token → live'
---                  (or just the literal if expansion fails or no ctx);
---                  for snippets: full template.
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
            -- Tokens.expand can throw on edge cases (eg %datetime{format} with
            -- bad format spec, or stats tokens before SQLite is ready) — pcall
            -- so a single bad token doesn't take the whole list down.
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

--- Show the tokens library modal. on_select(value) is called with the
--- chosen token / expression when the user taps a row.
function TokensLibrary:show(bookends, on_select)
    self.bookends = bookends
    local state = { active_chip = "all", search_query = nil }
    -- Doc context built once at modal-open. Live-token expansions in row 2
    -- reference this; if buildDocContext returned nil (e.g. ui not ready),
    -- _renderRow falls back to showing the raw token literal.
    local doc_ctx = buildDocContext(bookends)
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
        on_search_submit = function(query)
            state.search_query = query
            -- Search hits the merged TOKENS + CONDITIONALS pool regardless
            -- of the active chip, so snap the chip strip back to "All" so
            -- it reflects what's actually visible. Mirrors the icons
            -- library's behaviour (menu/icons_library.lua).
            if query then state.active_chip = "all" end
        end,
        rows_per_page = 5,
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
