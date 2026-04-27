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

local LibraryModal = WidgetContainer:extend{
    name = "library_modal",
    config = nil,           -- domain config table (see spec)
    -- runtime state
    active_tab = nil,       -- key of active tab, or nil if no tabs
    active_chip = nil,      -- key of active chip, or nil
    page = 1,
    search_query = nil,     -- current submitted query, or nil
}

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
    -- Frame-level dimensions match the existing preset modal's modal dimensions
    -- (90% of screen width, content-driven height up to 85% screen height).
    -- Implementation populates self[1] via :refresh().
end

function LibraryModal:_renderTitleBar(content_width)
    local Font = require("ui/font")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local LineWidget = require("ui/widget/linewidget")
    local TextWidget = require("ui/widget/textwidget")

    local title_w = TextWidget:new{
        text = self.config.title,
        face = Font:getFace("cfont", 22),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    local right_widget
    if self.config.tabs then
        -- Build segmented [Tab1 | Tab2] pill row; active tab is filled black,
        -- inactive is outlined. Tap on an inactive tab fires on_tab_change.
        right_widget = self:_renderTabSegments()
    else
        right_widget = HorizontalSpan:new{ width = 0 }
    end

    -- Title left, tab segments right, with the gap absorbed by a flexible spacer.
    local row = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ w = content_width - right_widget:getSize().w, h = title_w:getSize().h },
            title_w,
        },
        right_widget,
    }

    return VerticalGroup:new{
        row,
        VerticalSpan:new{ width = Size.span.vertical_default },
        LineWidget:new{
            background = Blitbuffer.COLOR_BLACK,
            dimen = Geom:new{ w = content_width, h = Size.line.thin },
        },
    }
end

function LibraryModal:_renderTabSegments()
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
    local seg_pad_v = Screen:scaleBySize(6)

    local function seg(label, is_active, on_tap)
        local fg = is_active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
        local bg = is_active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
        local tw = TextWidget:new{
            text = label, face = Font:getFace("cfont", 14), bold = is_active, fgcolor = fg,
        }
        local fc = FrameContainer:new{
            bordersize = 0, padding = 0,
            padding_left = seg_pad_h, padding_right = seg_pad_h,
            padding_top = seg_pad_v, padding_bottom = seg_pad_v,
            margin = 0, background = bg, tw,
        }
        local ic = InputContainer:new{ dimen = Geom:new{ w = fc:getSize().w, h = fc:getSize().h }, fc }
        ic.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = ic.dimen } } }
        ic.onTapSelect = function() on_tap(); return true end
        return ic
    end

    local hg = HorizontalGroup:new{ align = "center" }
    for i, tab in ipairs(self.config.tabs) do
        if i > 1 then table.insert(hg, HorizontalSpan:new{ width = Screen:scaleBySize(8) }) end
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
    if self.config.on_tab_change then self.config.on_tab_change(tab_key) end
    self:refresh()
end

function LibraryModal:_renderSearchInput(content_width)
    local Font = require("ui/font")
    local TextWidget = require("ui/widget/textwidget")
    local Screen = Device.screen
    local placeholder = self.config.search_placeholder
        and self.config.search_placeholder(self.active_tab)
        or _("Search…")
    local label_text = self.search_query and (self.search_query) or placeholder
    local label_color = self.search_query and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY
    local label = TextWidget:new{
        text = label_text,
        face = Font:getFace("cfont", 16),
        fgcolor = label_color,
    }

    local pad_h = Screen:scaleBySize(12)
    local pad_v = Screen:scaleBySize(8)
    local inner_h = label:getSize().h + 2 * pad_v
    local frame = FrameContainer:new{
        bordersize = Size.border.thin,
        padding = 0,
        padding_left = pad_h, padding_right = pad_h,
        padding_top = pad_v, padding_bottom = pad_v,
        margin = 0,
        radius = Screen:scaleBySize(4),
        background = Blitbuffer.COLOR_WHITE,
        dimen = Geom:new{ w = content_width, h = inner_h },
        label,
    }

    local ic = InputContainer:new{
        dimen = Geom:new{ w = content_width, h = inner_h },
        frame,
    }
    local GestureRange = require("ui/gesturerange")
    ic.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = ic.dimen } } }
    ic.onTapSelect = function() self:_openSearchDialog(); return true end
    return ic
end

function LibraryModal:_openSearchDialog()
    local InputDialog = require("ui/widget/inputdialog")
    local placeholder = self.config.search_placeholder
        and self.config.search_placeholder(self.active_tab) or _("Search…")
    local dlg
    dlg = InputDialog:new{
        title = placeholder,
        input = self.search_query or "",
        input_type = "text",
        buttons = {{
            { text = _("Cancel"), id = "cancel", callback = function() UIManager:close(dlg) end },
            { text = _("Search"), id = "search", is_enter_default = true, callback = function()
                local q = dlg:getInputText()
                UIManager:close(dlg)
                self:_onSearchSubmit(q)
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
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
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local TextWidget = require("ui/widget/textwidget")
    local Screen = Device.screen

    if not self.config.chip_strip then return nil end
    local chips = self.config.chip_strip(self.active_tab)
    if not chips or #chips == 0 then return nil end

    local pad_h = Screen:scaleBySize(10)
    local pad_v = Screen:scaleBySize(4)
    local chip_gap = Screen:scaleBySize(6)
    local row_gap = Screen:scaleBySize(6)

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
            margin = 0, background = bg, radius = Screen:scaleBySize(12),
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

    local row_height = area_height / rows_per_page
    local vg = VerticalGroup:new{ align = "left" }
    for idx = start_idx, end_idx do
        local item = self.config.item_at(idx)
        if item then
            local slot_dimen = Geom:new{ w = content_width, h = row_height }
            table.insert(vg, self.config.row_renderer(item, slot_dimen))
        end
    end
    local rendered = end_idx - start_idx + 1
    if rendered < rows_per_page then
        local Spacer = require("ui/widget/spacer")
        for _i = rendered + 1, rows_per_page do
            table.insert(vg, VerticalSpan:new{ width = row_height })
        end
    end
    return vg
end

function LibraryModal:_renderGridArea(content_width, area_height)
    local cells_per_page = self.config.cells_per_page(content_width)
    local total = self.config.item_count and self.config.item_count() or 0
    local total_pages = math.max(1, math.ceil(total / cells_per_page))
    if self.page > total_pages then self.page = total_pages end

    local target_cell_w = Device.screen:scaleBySize(290)
    local cols = math.max(3, math.floor(content_width / target_cell_w))
    local rows = math.ceil(cells_per_page / cols)
    local cell_w = math.floor(content_width / cols)
    local cell_h = math.floor(area_height / rows)

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
                table.insert(vg, hg)
                hg = HorizontalGroup:new{ align = "top" }
                in_row = 0
            end
        end
    end
    if in_row > 0 then table.insert(vg, hg) end
    return vg
end

function LibraryModal:_renderPagination(content_width)
    local Button = require("ui/widget/button")
    local Font = require("ui/font")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local TextWidget = require("ui/widget/textwidget")
    local T = require("ffi/util").template

    local total = self.config.item_count and self.config.item_count() or 0
    local per_page = self.config.rows_per_page
        or (self.config.cells_per_page and self.config.cells_per_page(content_width))
        or 1
    local total_pages = math.max(1, math.ceil(total / per_page))

    local function chev(label, callback, enabled)
        return Button:new{
            text = label,
            text_func = nil,
            bordersize = 0,
            radius = 0,
            padding = Device.screen:scaleBySize(8),
            face = Font:getFace("cfont", 16),
            callback = enabled and callback or function() end,
            enabled = enabled,
        }
    end

    local first = chev("\xE2\x80\xB9\xE2\x80\xB9", function() self.page = 1; self:refresh() end, self.page > 1)
    local prev  = chev("\xE2\x80\xB9", function() self.page = self.page - 1; self:refresh() end, self.page > 1)
    local pageinfo = TextWidget:new{
        text = T(_("Page %1 of %2"), self.page, total_pages),
        face = Font:getFace("cfont", 14),
    }
    local nxt = chev("\xE2\x80\xBA", function() self.page = self.page + 1; self:refresh() end, self.page < total_pages)
    local last = chev("\xE2\x80\xBA\xE2\x80\xBA", function() self.page = total_pages; self:refresh() end, self.page < total_pages)
    local gap = HorizontalSpan:new{ width = Device.screen:scaleBySize(20) }

    return HorizontalGroup:new{ align = "center", first, gap, prev, gap, pageinfo, gap, nxt, gap, last }
end

function LibraryModal:refresh()
    -- Rebuild the inner content. Called on tab change, chip tap, search submit,
    -- page change. Avoids rebuilding the modal frame itself (which would
    -- re-trigger :init in some paint cycles).
end

return LibraryModal
