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
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
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
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local LineWidget = require("ui/widget/linewidget")
    local TextWidget = require("ui/widget/textwidget")
    local Screen = Device.screen

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

function LibraryModal:refresh()
    -- Rebuild the inner content. Called on tab change, chip tap, search submit,
    -- page change. Avoids rebuilding the modal frame itself (which would
    -- re-trigger :init in some paint cycles).
end

return LibraryModal
