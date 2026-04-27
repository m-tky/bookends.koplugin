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
    for _, chip in ipairs(chips) do
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

function LibraryModal:refresh()
    -- Rebuild the inner content. Called on tab change, chip tap, search submit,
    -- page change. Avoids rebuilding the modal frame itself (which would
    -- re-trigger :init in some paint cycles).
end

return LibraryModal
