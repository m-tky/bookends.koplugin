--- BookendsLibraryModal — shared chrome widget for the preset, icons, and
--- tokens libraries. Renders header, optional tabs, search input, chip strip
--- (with two-row wrap), paginated list-or-grid result area, and footer.
--- Domain-specific data and per-row rendering are supplied by the caller via
--- a config table. See docs/superpowers/specs/2026-04-27-bookends-library-modal-design.md
--- for the full config shape.

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("bookends_i18n").gettext

-- Uniform gap applied everywhere below the title bar separator.
local MARGIN = Device.screen:scaleBySize(10)

local LibraryModal = WidgetContainer:extend{
    name = "library_modal",
    config = nil,           -- domain config table (see spec)
    -- runtime state
    active_tab = nil,       -- key of active tab, or nil if no tabs
    active_chip = nil,      -- key of active chip, or nil
    page = 1,
    search_query = nil,     -- current submitted query, or nil
}

--- Multi-term substring AND match. Public for unit testing.
--- Empty or 1-char query returns false (avoids surfacing thousands of matches
--- on a single keystroke).
function LibraryModal._matchesQuery(text, query)
    if not query or #query < 2 then return false end
    local lc = (text or ""):lower()
    for term in query:lower():gmatch("%S+") do
        if not lc:find(term, 1, true) then return false end
    end
    return true
end

function LibraryModal:init()
    assert(self.config, "LibraryModal requires a config table")
    -- Pre-populate runtime state from config defaults
    if self.config.tabs and #self.config.tabs > 0 then
        self.active_tab = self.config.tabs[1].key
    end
    -- Default chip is "all" if present in the chip strip
    local chips = self.config.chip_strip and self.config.chip_strip(self.active_tab) or {}
    for _i, chip in ipairs(chips) do
        if chip.is_active then self.active_chip = chip.key; break end
    end
    if not self.active_chip and chips[1] then
        self.active_chip = chips[1].key
    end
    -- Build the modal frame on init; populated lazily via :refresh()
    self:_buildFrame()
end

function LibraryModal:_buildFrame()
    local Screen = Device.screen
    -- Modal width: 85% of screen. Less wide than the 90% it was — visible
    -- breathing room around the dialog for context.
    self.modal_w = math.floor(Screen:getWidth() * 0.85)
    -- Width of inner content (search box, chip strip, cards, etc.) once the
    -- per-section MARGIN insets are applied in refresh().
    self.content_w = self.modal_w - 2 * MARGIN

    -- Frame has zero left/right padding so the title bar separator can run
    -- edge-to-edge. Each non-title section wraps itself in MARGIN padding
    -- via the padHorizontal helper inside refresh().
    self.frame = FrameContainer:new{
        bordersize = Size.border.window,
        padding = 0,
        padding_top = 0,
        padding_bottom = MARGIN,
        padding_left = 0,
        padding_right = 0,
        margin = 0,
        radius = Screen:scaleBySize(8),
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{ align = "left" },
    }
    self[1] = CenterContainer:new{
        dimen = Geom:new{ w = Screen:getWidth(), h = Screen:getHeight() },
        self.frame,
    }
    self:refresh()
end

function LibraryModal:_renderTitleBar(content_width, modal_w)
    local Font = require("ui/font")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local LineWidget = require("ui/widget/linewidget")
    local TextWidget = require("ui/widget/textwidget")
    local Screen = Device.screen
    -- Equal top/bottom padding so the title text reads as vertically centred.
    local bar_pad = Screen:scaleBySize(8)

    local title_w = TextWidget:new{
        text = self.config.title,
        face = Font:getFace("cfont", 22),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    -- Title bar height = text height + equal top/bottom padding.
    -- Passed to _renderTabSegments so each segment can fill the full bar height.
    local title_bar_h = title_w:getSize().h + 2 * bar_pad

    local right_widget
    if self.config.tabs then
        -- Build segmented [Tab1 | Tab2] pill row; active tab is filled black,
        -- inactive is outlined. Tap on an inactive tab fires on_tab_change.
        right_widget = self:_renderTabSegments(title_bar_h)
    else
        right_widget = HorizontalSpan:new{ width = 0 }
    end

    -- Title left, tab segments right, with the gap absorbed by a flexible spacer.
    local row = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ w = content_width - right_widget:getSize().w, h = title_bar_h },
            title_w,
        },
        right_widget,
    }

    -- Separator runs the full frame width (modal_w) so it spans edge-to-edge,
    -- ignoring the frame's content_pad side insets. Thicker than line.thin so
    -- the separator reads as a deliberate structural divider, not a hairline.
    return VerticalGroup:new{
        row,
        LineWidget:new{
            background = Blitbuffer.COLOR_BLACK,
            dimen = Geom:new{ w = modal_w, h = Device.screen:scaleBySize(3) },
        },
    }
end

function LibraryModal:_renderTabSegments(title_bar_h)
    -- Returns a HorizontalGroup of tap-able segment widgets. Active segment
    -- has black bg + white text; inactive has white bg + black text. On tap,
    -- :_onTabSelect(key) is called, which updates active_tab + invokes
    -- self.config.on_tab_change + self:refresh().
    local Font = require("ui/font")
    local GestureRange = require("ui/gesturerange")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local TextWidget = require("ui/widget/textwidget")
    local Screen = Device.screen
    local seg_pad_h = Screen:scaleBySize(12)

    local function seg(label, is_active, on_tap)
        local fg = is_active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
        local bg = is_active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
        local tw = TextWidget:new{
            text = label, face = Font:getFace("cfont", 14), bold = is_active, fgcolor = fg,
        }
        local pill_w = tw:getSize().w + 2 * seg_pad_h
        -- No border on either state — the active fill alone signals selection,
        -- which reads cleaner than a black-bordered inactive pill next to a
        -- black-filled active pill.
        local fc = FrameContainer:new{
            bordersize = 0,
            padding = 0,
            padding_left = seg_pad_h, padding_right = seg_pad_h,
            padding_top = 0, padding_bottom = 0,
            margin = 0, background = bg,
            dimen = Geom:new{ w = pill_w, h = title_bar_h },
            CenterContainer:new{
                dimen = Geom:new{ w = pill_w - 2 * seg_pad_h, h = title_bar_h },
                tw,
            },
        }
        local ic = InputContainer:new{ dimen = Geom:new{ w = pill_w, h = title_bar_h }, fc }
        ic.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = ic.dimen } } }
        ic.onTapSelect = function() on_tap(); return true end
        return ic
    end

    -- Tabs butt together so they read as one segmented control rather than two
    -- floating pills (no HorizontalSpan between segments).
    local hg = HorizontalGroup:new{ align = "center" }
    for _i, tab in ipairs(self.config.tabs) do
        local is_active = tab.key == self.active_tab
        table.insert(hg, seg(tab.label, is_active, function() self:_onTabSelect(tab.key) end))
    end
    return hg
end

function LibraryModal:_onTabSelect(tab_key)
    if self.active_tab == tab_key then return end
    self.active_tab = tab_key
    self.search_query = nil
    self.page = 1
    -- Default chip on the new tab is its first chip (or "all")
    local chips = self.config.chip_strip and self.config.chip_strip(self.active_tab) or {}
    self.active_chip = chips[1] and chips[1].key or nil
    -- The search placeholder may differ per tab. Release the persisted
    -- InputText so _renderSearchInput rebuilds it with the new hint.
    if self._search_input then
        if self._search_input:isKeyboardVisible() then
            self._search_input:onCloseKeyboard()
        end
        self._search_input = nil
    end
    if self.config.on_tab_change then self.config.on_tab_change(tab_key) end
    self:refresh()
end

function LibraryModal:_renderSearchInput(content_width)
    local Button = require("ui/widget/button")
    local Font = require("ui/font")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local Screen = Device.screen

    local placeholder = self.config.search_placeholder
        and self.config.search_placeholder(self.active_tab)
        or _("Search…")

    -- Compute button widths first so InputText gets what remains.
    local btn_pad = Screen:scaleBySize(8)
    local btn_radius = Screen:scaleBySize(4)
    -- Fixed widths derived from the scale factor rather than measuring text,
    -- so the layout is stable across locales without a two-pass measure.
    local search_btn_w = Screen:scaleBySize(80)
    local clear_btn_w  = Screen:scaleBySize(36)
    local gap = Screen:scaleBySize(6)
    local input_w = content_width - search_btn_w - clear_btn_w - 2 * gap

    -- Persist the InputText across refreshes so the keyboard's reference to
    -- it stays valid. Rebuilding it on every refresh leaves the keyboard
    -- pointing at a destroyed widget, which crashes on the next keystroke.
    if not self._search_input then
        local InputText = require("ui/widget/inputtext")
        self._search_input = InputText:new{
            text    = self.search_query or "",
            hint    = placeholder,
            parent  = self,
            width   = input_w,
            -- Smaller face + tighter chrome so the input row matches the
            -- Search/× button heights (~40px). InputText's height param is
            -- the inner text area; padding/margin/border are added on top,
            -- so we shrink all three to keep the outer size in range.
            face    = Font:getFace("cfont", 16),
            padding = Size.padding.small,
            margin  = 0,
            scroll  = false,
            focused = false,
            enter_callback = function()
                self:_onSearchSubmit(self._search_input:getText())
            end,
        }
    else
        -- Re-sync text if the query changed externally (e.g. tab switch resets
        -- search_query to nil, which we represent as empty string in the widget).
        local desired = self.search_query or ""
        if self._search_input:getText() ~= desired then
            self._search_input:setText(desired)
        end
    end

    -- Buttons can be rebuilt fresh; they hold no keyboard lifecycle state.
    local search_btn = Button:new{
        text       = _("Search"),
        bordersize = Size.border.thin,
        radius     = btn_radius,
        padding    = btn_pad,
        width      = search_btn_w,
        callback   = function()
            self:_onSearchSubmit(self._search_input:getText())
        end,
    }

    -- × is always visible as a "reset to browse" affordance, not a clear-text
    -- affordance, so it does not toggle based on whether there is text.
    local clear_btn = Button:new{
        text       = "×",
        bordersize = Size.border.thin,
        radius     = btn_radius,
        padding    = btn_pad,
        width      = clear_btn_w,
        callback   = function()
            -- Dismiss the keyboard before refresh so it doesn't linger
            -- attached to no visible input after the body is rebuilt.
            if self._search_input:isKeyboardVisible() then
                self._search_input:onCloseKeyboard()
            end
            self._search_input:setText("")
            self:_onSearchSubmit("")
        end,
    }

    return HorizontalGroup:new{
        align = "center",
        self._search_input,
        HorizontalSpan:new{ width = gap },
        search_btn,
        HorizontalSpan:new{ width = gap },
        clear_btn,
    }
end

function LibraryModal:_onSearchSubmit(q)
    if not q or #q < 2 then
        self.search_query = nil
    else
        self.search_query = q
    end
    self.page = 1
    if self.config.on_search_submit then self.config.on_search_submit(self.search_query) end
    self:refresh()
end

function LibraryModal:_renderChipStrip(content_width)
    local Font = require("ui/font")
    local GestureRange = require("ui/gesturerange")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local TextWidget = require("ui/widget/textwidget")
    local Screen = Device.screen

    if not self.config.chip_strip then return nil end
    local chips = self.config.chip_strip(self.active_tab)
    if not chips or #chips == 0 then return nil end

    local pad_h = Screen:scaleBySize(10)
    local pad_v = Screen:scaleBySize(4)
    -- Zero gap so chips butt together into a segmented-control strip.
    local chip_gap = 0
    local row_gap = MARGIN

    local function buildChip(chip)
        local is_active = chip.key == self.active_chip
        local fg = is_active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
        local bg = is_active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
        local tw = TextWidget:new{
            text = chip.label, face = Font:getFace("cfont", 13), bold = is_active, fgcolor = fg,
        }
        local fc = FrameContainer:new{
            bordersize = is_active and 0 or Size.border.thin,
            padding = 0,
            padding_left = pad_h, padding_right = pad_h,
            padding_top = pad_v, padding_bottom = pad_v,
            -- Square corners: with chip_gap=0 the chips share a vertical edge,
            -- so we square them off to read as one continuous segmented control.
            -- Rounded outer corners would require per-corner radius which the
            -- FrameContainer doesn't support.
            margin = 0, background = bg, radius = 0,
            tw,
        }
        local ic = InputContainer:new{ dimen = Geom:new{ w = fc:getSize().w, h = fc:getSize().h }, fc }
        ic.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = ic.dimen } } }
        ic.onTapSelect = function() self:_onChipTap(chip.key); return true end
        return ic
    end

    local rows = {}
    local current_row = HorizontalGroup:new{ align = "center" }
    local current_w = 0
    for i, chip in ipairs(chips) do
        local cw = buildChip(chip)
        local cw_w = cw:getSize().w
        local needed = (i == 1) and cw_w or (current_w + chip_gap + cw_w)
        if needed > content_width and #current_row > 0 then
            table.insert(rows, current_row)
            current_row = HorizontalGroup:new{ align = "center", cw }
            current_w = cw_w
        else
            if i > 1 and current_w > 0 then
                table.insert(current_row, HorizontalSpan:new{ width = chip_gap })
                current_w = current_w + chip_gap
            end
            table.insert(current_row, cw)
            current_w = current_w + cw_w
        end
        if #rows >= 2 then break end
    end
    table.insert(rows, current_row)

    local vg = VerticalGroup:new{ align = "left" }
    for i, row in ipairs(rows) do
        if i > 1 then table.insert(vg, VerticalSpan:new{ width = row_gap }) end
        table.insert(vg, row)
    end
    return vg
end

function LibraryModal:_onChipTap(chip_key)
    if self.active_chip == chip_key then return end
    self.active_chip = chip_key
    self.page = 1
    if self.config.on_chip_tap then self.config.on_chip_tap(chip_key) end
    self:refresh()
end

function LibraryModal:_renderListArea(content_width, area_height)
    local rows_per_page = self.config.rows_per_page or 5
    local total = self.config.item_count and self.config.item_count() or 0

    if total == 0 and self.config.empty_state then
        local panel = self.config.empty_state(content_width, area_height)
        if panel then return panel end
    end

    local total_pages = math.max(1, math.ceil(total / rows_per_page))
    if self.page > total_pages then self.page = total_pages end

    local start_idx = (self.page - 1) * rows_per_page + 1
    local end_idx = math.min(start_idx + rows_per_page - 1, total)

    -- Stack: rows × card + (rows-1) × MARGIN inter-row gap, no top/bottom inset.
    -- The MARGIN above the first card and below the last card is supplied by
    -- refresh()'s inter-section gap so the spacing matches the search box's.
    local row_height = math.floor(
        (area_height - (rows_per_page - 1) * MARGIN) / rows_per_page)
    local vg = VerticalGroup:new{ align = "left" }
    for idx = start_idx, end_idx do
        local item = self.config.item_at(idx)
        if item then
            if idx > start_idx then table.insert(vg, VerticalSpan:new{ width = MARGIN }) end
            local slot_dimen = Geom:new{ w = content_width, h = row_height }
            table.insert(vg, self.config.row_renderer(item, slot_dimen))
        end
    end
    local rendered = end_idx - start_idx + 1
    if rendered < rows_per_page then
        for _i = rendered + 1, rows_per_page do
            table.insert(vg, VerticalSpan:new{ width = MARGIN })
            table.insert(vg, VerticalSpan:new{ width = row_height })
        end
    end
    return CenterContainer:new{
        dimen = Geom:new{ w = content_width, h = area_height },
        vg,
    }
end

function LibraryModal:_renderGridArea(content_width, area_height)
    local cells_per_page = self.config.cells_per_page(content_width)
    local total = self.config.item_count and self.config.item_count() or 0
    local total_pages = math.max(1, math.ceil(total / cells_per_page))
    if self.page > total_pages then self.page = total_pages end

    local target_cell_w = Device.screen:scaleBySize(290)
    local cols = math.max(3, math.floor(content_width / target_cell_w))
    local rows = math.ceil(cells_per_page / cols)
    -- Cell height divides the area after subtracting inter-row MARGIN gaps.
    local cell_w = math.floor(content_width / cols)
    local cell_h = math.floor((area_height - (rows - 1) * MARGIN) / rows)

    local start_idx = (self.page - 1) * cells_per_page + 1
    local end_idx = math.min(start_idx + cells_per_page - 1, total)

    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local vg = VerticalGroup:new{ align = "left" }
    local hg = HorizontalGroup:new{ align = "top" }
    local in_row = 0
    for idx = start_idx, end_idx do
        local item = self.config.item_at(idx)
        if item then
            local cell_dimen = Geom:new{ w = cell_w, h = cell_h }
            local cell_widget = self.config.cell_renderer(item, cell_dimen)
            if self.config.cell_long_tap then
                local GestureRange = require("ui/gesturerange")
                local ic = InputContainer:new{
                    dimen = Geom:new{ w = cell_w, h = cell_h },
                    cell_widget,
                }
                ic.ges_events = {
                    Hold = { GestureRange:new{ ges = "hold", range = ic.dimen } },
                }
                ic.onHold = function() self.config.cell_long_tap(item); return true end
                cell_widget = ic
            end
            table.insert(hg, cell_widget)
            in_row = in_row + 1
            if in_row >= cols then
                if #vg > 0 then table.insert(vg, VerticalSpan:new{ width = MARGIN }) end
                table.insert(vg, hg)
                hg = HorizontalGroup:new{ align = "top" }
                in_row = 0
            end
        end
    end
    if in_row > 0 then
        if #vg > 0 then table.insert(vg, VerticalSpan:new{ width = MARGIN }) end
        table.insert(vg, hg)
    end
    return CenterContainer:new{
        dimen = Geom:new{ w = content_width, h = area_height },
        vg,
    }
end

function LibraryModal:_renderPagination(content_width)
    local Button = require("ui/widget/button")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local LineWidget = require("ui/widget/linewidget")
    local T = require("ffi/util").template
    local Screen = Device.screen

    local total = self.config.item_count and self.config.item_count() or 0
    local per_page = self.config.rows_per_page
        or (self.config.cells_per_page and self.config.cells_per_page(content_width))
        or 1
    local total_pages = math.max(1, math.ceil(total / per_page))

    local chev_size = Screen:scaleBySize(32)
    -- show_parent is required for icon buttons to resolve their icon atlas path.
    local function chev(icon_name, enabled, cb)
        return Button:new{
            icon = icon_name, icon_width = chev_size, icon_height = chev_size,
            bordersize = 0, enabled = enabled,
            callback = enabled and cb or function() end,
            show_parent = self,
        }
    end
    -- Fresh span per slot — sharing one widget across HGroup positions
    -- corrupts paint geometry.
    local pn_span = Screen:scaleBySize(32)
    local function gap() return HorizontalSpan:new{ width = pn_span } end

    local page_nav = HorizontalGroup:new{
        align = "center",
        chev("chevron.first", self.page > 1,          function() self.page = 1;              self:refresh() end),
        gap(),
        chev("chevron.left",  self.page > 1,          function() self.page = self.page - 1;  self:refresh() end),
        gap(),
        Button:new{
            text = T(_("Page %1 of %2"), self.page, total_pages),
            text_font_size = 15,
            bordersize = 0,
            callback = function() end,
            show_parent = self,
        },
        gap(),
        chev("chevron.right", self.page < total_pages, function() self.page = self.page + 1; self:refresh() end),
        gap(),
        chev("chevron.last",  self.page < total_pages, function() self.page = total_pages;   self:refresh() end),
    }

    local function divider()
        -- Fresh widget per slot; sharing one across paint positions corrupts
        -- KOReader's geometry calculations.
        return CenterContainer:new{
            dimen = Geom:new{ w = content_width, h = Size.line.thin },
            LineWidget:new{
                background = Blitbuffer.COLOR_DARK_GRAY,
                dimen = Geom:new{ w = content_width - 2 * Size.padding.default, h = Size.line.thin },
            },
        }
    end

    -- Pagination: divider above + MARGIN breathing room + chevron row + MARGIN
    -- + divider below. The lower divider visually separates the pagination
    -- from the footer action buttons.
    return VerticalGroup:new{
        align = "left",
        divider(),
        VerticalSpan:new{ width = MARGIN },
        CenterContainer:new{
            dimen = Geom:new{ w = content_width, h = page_nav:getSize().h },
            page_nav,
        },
        VerticalSpan:new{ width = MARGIN },
        divider(),
    }
end

function LibraryModal:_renderFooter(content_width)
    local Button = require("ui/widget/button")
    local Font = require("ui/font")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local LineWidget = require("ui/widget/linewidget")

    local actions = self.config.footer_actions or {}
    if #actions == 0 then return nil end

    -- Width must be passed at construction; Button bakes it into inner
    -- containers in :init, so post-assigning self.width has no effect.
    local btn_width = #actions > 1 and math.floor(content_width / #actions) or content_width

    local btns = {}
    for _i, action in ipairs(actions) do
        local enabled = true
        if action.enabled_when then enabled = action.enabled_when() end
        -- Dynamic label needed for Apply/Install switching in preset modal;
        -- label_func() takes precedence over the static label fallback.
        local btn_text = action.label_func and action.label_func() or action.label
        table.insert(btns, Button:new{
            text = btn_text,
            face = Font:getFace("cfont", 16),
            bold = action.primary == true,
            bordersize = 0,
            radius = 0,
            width = btn_width,
            callback = function() if enabled then action.on_tap() end end,
            enabled = enabled,
        })
    end

    if #btns == 1 then return btns[1] end

    local hg = HorizontalGroup:new{ align = "center" }
    for i, btn in ipairs(btns) do
        if i > 1 then
            table.insert(hg, LineWidget:new{
                background = Blitbuffer.COLOR_DARK_GRAY,
                dimen = Geom:new{ w = Size.line.thin, h = Device.screen:scaleBySize(28) },
            })
        end
        table.insert(hg, btn)
    end
    return hg
end

function LibraryModal:refresh()
    local Screen = Device.screen
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local cw = self.content_w
    -- modal_w is passed so _renderTitleBar can draw an edge-to-edge separator.
    local title = self:_renderTitleBar(cw, self.modal_w)
    local search = self:_renderSearchInput(cw)
    local chips = self:_renderChipStrip(cw)
    local pagination = self:_renderPagination(cw)
    local footer = self:_renderFooter(cw)

    -- Sized to fit content rather than a screen fraction, so the dialog isn't
    -- bigger than necessary. Uses the row renderer's intrinsic card height
    -- (matches preset_manager's Screen:scaleBySize(64)) so the area accommodates
    -- exactly rows_per_page cards plus inter/outer MARGIN gaps.
    local rows_per_page = self.config.rows_per_page or 5
    local intrinsic_card_h = Screen:scaleBySize(64)
    -- area_height = card stack + inter-row gaps. The MARGIN above the first
    -- card and below the last card is the refresh() inter-section gap.
    local area_height = rows_per_page * intrinsic_card_h
        + (rows_per_page - 1) * MARGIN

    -- Frame's padding_left/right are 0 so the title bar separator runs edge-
    -- to-edge. Each non-title section is padded with HorizontalSpan(MARGIN)
    -- on either side so its content sits inside the same MARGIN inset.
    local function padded(widget)
        if not widget then return nil end
        return HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = MARGIN },
            widget,
            HorizontalSpan:new{ width = MARGIN },
        }
    end

    local result_area
    if self.config.cell_renderer then
        result_area = self:_renderGridArea(cw, area_height)
    else
        result_area = self:_renderListArea(cw, area_height)
    end

    local body = VerticalGroup:new{
        align = "left",
        title,                                       -- spans full modal_w (separator inside)
        VerticalSpan:new{ width = MARGIN },
        padded(search),
        VerticalSpan:new{ width = MARGIN },
    }
    if chips then
        table.insert(body, padded(chips))
        table.insert(body, VerticalSpan:new{ width = MARGIN })
    end
    table.insert(body, padded(result_area))
    table.insert(body, VerticalSpan:new{ width = MARGIN })
    table.insert(body, padded(pagination))
    if footer then
        table.insert(body, VerticalSpan:new{ width = MARGIN })
        table.insert(body, padded(footer))
    end

    self.frame[1] = body
    -- Self-bounded dirty rect is sufficient now that the modal is a fixed,
    -- content-derived size. setDirty(nil, ...) was triggering full-screen
    -- repaints that stacked ~1s each on e-ink.
    UIManager:setDirty(self, "ui")
end

return LibraryModal
