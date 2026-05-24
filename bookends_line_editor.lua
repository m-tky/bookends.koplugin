--- Line-level editing: the InputDialog-based format editor and the
-- long-press manage dialog (delete/reorder/move-to-region).

local ButtonDialog = require("ui/widget/buttondialog")
local Colour = require("bookends_colour")
local ConfirmBox = require("ui/widget/confirmbox")
local Config = require("bookends_config")
local Device = require("device")
local DialogHelpers = require("bookends_dialog_helpers")
local Font = require("ui/font")
local InputDialog = require("ui/widget/inputdialog")
local Tokens = require("bookends_tokens")
local UIManager = require("ui/uimanager")
local Utils = require("bookends_utils")
local util = require("util")
local _ = require("bookends_i18n").gettext
local T = require("ffi/util").template
local Screen = Device.screen

local LineEditor = {}

--- Remove all per-line attribute fields at index `idx`, shifting higher indices down.
local function removeLineFields(ps, idx)
    for _, field in ipairs(Config.LINE_FIELDS) do
        Utils.sparseRemove(ps[field], idx)
    end
end

--- Swap all per-line attribute fields between indices `a` and `b`.
local function swapLineFields(ps, a, b)
    for _, field in ipairs(Config.LINE_FIELDS) do
        if ps[field] then
            ps[field][a], ps[field][b] = ps[field][b], ps[field][a]
        end
    end
end

function LineEditor.attach(Bookends)
    -- Expose helpers in case buildPreset or other code needs them
    Bookends.removeLineFields = removeLineFields
    Bookends.swapLineFields = swapLineFields

    function Bookends:editLineString(pos, line_idx, touchmenu_instance)
        local restoreMenu = self:hideMenu(touchmenu_instance)
        local IconsLibrary = require("menu.icons_library")

        local pos_settings = self.positions[pos.key]

        -- Stored text is guaranteed to be on the current schema (v5) because
        -- migrateSchemaIfNeeded ran at startup. No per-open canonicalise
        -- needed; the editor just shows whatever is stored.
        local current_text = pos_settings.lines[line_idx] or ""

        -- Per-line style state
        pos_settings.line_style = pos_settings.line_style or {}
        pos_settings.line_font_size = pos_settings.line_font_size or {}
        pos_settings.line_font_face = pos_settings.line_font_face or {}
        pos_settings.line_v_nudge = pos_settings.line_v_nudge or {}
        pos_settings.line_h_nudge = pos_settings.line_h_nudge or {}
        pos_settings.line_uppercase = pos_settings.line_uppercase or {}
        pos_settings.line_page_filter = pos_settings.line_page_filter or {}
        pos_settings.line_bar_type = pos_settings.line_bar_type or {}
        pos_settings.line_bar_height = pos_settings.line_bar_height or {}
        pos_settings.line_bar_style = pos_settings.line_bar_style or {}
        pos_settings.line_bar_chapter_ticks = pos_settings.line_bar_chapter_ticks or {}
        pos_settings.line_bar_direction = pos_settings.line_bar_direction or {}
        pos_settings.line_bar_unread_height = pos_settings.line_bar_unread_height or {}
        pos_settings.line_bar_colors = pos_settings.line_bar_colors or {}

        -- Snapshot for cancel/restore (style / font / nudge / etc.; the
        -- canonicalise migration above is already baked into this snapshot
        -- on purpose, so Cancel keeps it).
        local original_settings = util.tableDeepCopy(pos_settings)

        local line_style = pos_settings.line_style[line_idx] or "regular"
        local line_size = pos_settings.line_font_size[line_idx] -- nil = use default
        local line_face = pos_settings.line_font_face[line_idx] -- nil = use default
        local line_v_nudge = pos_settings.line_v_nudge[line_idx] or 0
        local line_h_nudge = pos_settings.line_h_nudge[line_idx] or 0
        local line_uppercase = pos_settings.line_uppercase[line_idx] or false
        local line_page_filter = pos_settings.line_page_filter[line_idx] -- nil = all pages
        local line_bar_type = pos_settings.line_bar_type[line_idx] -- nil = "chapter"
        local line_bar_height = pos_settings.line_bar_height[line_idx] -- nil = use font size
        local line_bar_style = pos_settings.line_bar_style[line_idx] -- nil = "bordered"
        local line_bar_chapter_ticks = pos_settings.line_bar_chapter_ticks[line_idx] -- nil = "off"
        local line_bar_direction = pos_settings.line_bar_direction[line_idx] -- nil = "ltr"
        local line_bar_unread_height = pos_settings.line_bar_unread_height[line_idx] -- nil = symmetric
        local line_bar_colors = pos_settings.line_bar_colors[line_idx] -- nil = inherit global

        -- Live preview: write current local state to settings and repaint.
        local function applyLivePreview()
            pos_settings.line_style[line_idx] = line_style ~= "regular" and line_style or nil
            pos_settings.line_font_size[line_idx] = line_size
            pos_settings.line_font_face[line_idx] = line_face
            pos_settings.line_v_nudge[line_idx] = line_v_nudge ~= 0 and line_v_nudge or nil
            pos_settings.line_h_nudge[line_idx] = line_h_nudge ~= 0 and line_h_nudge or nil
            pos_settings.line_uppercase[line_idx] = line_uppercase or nil
            pos_settings.line_page_filter[line_idx] = line_page_filter
            pos_settings.line_bar_type[line_idx] = line_bar_type
            pos_settings.line_bar_height[line_idx] = line_bar_height
            pos_settings.line_bar_style[line_idx] = line_bar_style
            pos_settings.line_bar_chapter_ticks[line_idx] = line_bar_chapter_ticks
            pos_settings.line_bar_direction[line_idx] = line_bar_direction
            pos_settings.line_bar_unread_height[line_idx] = line_bar_unread_height
            pos_settings.line_bar_colors[line_idx] = line_bar_colors
            self:markDirty()
        end

        -- Style cycle button
        local style_button = {
            text_func = function()
                return self.STYLE_LABELS[line_style] or _("Regular")
            end,
            callback = function() end,
        }
        local size_button = {
            text_func = function()
                return _("Size") .. ": " .. (line_size or self:getPositionSetting(pos.key, "font_size"))
            end,
            callback = function() end,
        }
        local font_button = {
            text_func = function()
                if line_face then
                    return _("Font") .. " \xE2\x9C\x93"
                end
                return _("Font...")
            end,
            callback = function() end,
        }
        local case_button = {
            text_func = function()
                return line_uppercase and "AA" or "Aa"
            end,
            callback = function() end,
        }
        local page_filter_button = {
            text_func = function()
                if line_page_filter == "odd" then return _("Odd pg")
                elseif line_page_filter == "even" then return _("Even pg")
                else return _("All pg") end
            end,
            callback = function() end,
        }

        local format_dialog

        case_button.callback = function()
            format_dialog:onCloseKeyboard()
            line_uppercase = not line_uppercase
            applyLivePreview()
            format_dialog:reinit()
        end

        page_filter_button.callback = function()
            format_dialog:onCloseKeyboard()
            if line_page_filter == nil then
                line_page_filter = "odd"
            elseif line_page_filter == "odd" then
                line_page_filter = "even"
            else
                line_page_filter = nil
            end
            applyLivePreview()
            format_dialog:reinit()
        end

        -- Bar row: [+ Bar] [Ch./Book/Book+] [Bdr/Sld]
        local function hasBarToken()
            if not format_dialog then return current_text:find("%%bar") ~= nil end
            local t = format_dialog:getInputText()
            return t and t:find("%%bar") ~= nil
        end

        local bar_insert_button = {
            text_func = function()
                return hasBarToken() and _("- Progress bar") or _("+ Progress bar")
            end,
            callback = function() end,
        }
        local bar_style_menu_button = {
            text = _("Bar style…"),
            enabled_func = hasBarToken,
            callback = function() end,  -- wired below
        }

        bar_insert_button.callback = function()
            format_dialog:onCloseKeyboard()
            if hasBarToken() then
                local t = format_dialog:getInputText()
                t = t:gsub("%s*%%bar%s*", " "):gsub("^%s+", ""):gsub("%s+$", "")
                format_dialog._input_widget:setText(t)
                pos_settings.lines[line_idx] = t
                self:markDirty()
            else
                format_dialog:addTextToInput("%bar")
                -- Ensure single space before/after %bar (but not at string edges)
                local t = format_dialog:getInputText() or ""
                t = t:gsub("(%S)(%%bar)", "%1 %%bar")   -- space before if touching text
                t = t:gsub("(%%bar)(%S)", "%%bar %2")    -- space after if touching text
                t = t:gsub("%s+%%bar", " %%bar")          -- collapse multiple spaces before
                t = t:gsub("%%bar%s+", "%%bar ")           -- collapse multiple spaces after
                t = t:gsub("^%s+", ""):gsub("%s+$", "")  -- trim edges
                format_dialog._input_widget:setText(t)
                pos_settings.lines[line_idx] = t
                self:markDirty()
            end
            format_dialog:reinit()
        end

        local STYLE_CYCLE = { "bordered", "solid", "rounded", "metro", "wavy", "radial", "radial_hollow", "pacman" }
        local STYLE_LABELS = {
            bordered = _("Bordered"), solid = _("Solid"), rounded = _("Rounded"),
            metro = _("Metro"), wavy = _("Wave"), radial = _("Radial"),
            radial_hollow = _("Radial hollow"), pacman = _("Pacman"),
        }
        local TICKS_CYCLE = { "off", "level1", "level2", "all" }
        local TICKS_LABELS = {
            off = _("Chapter ticks: off"),
            level1 = _("Chapter ticks: top level"),
            level2 = _("Chapter ticks: top 2 levels"),
            all = _("Chapter ticks: all levels"),
        }

        local plugin = self  -- captured so nested colour callbacks can reach showColourPicker
        local _bar_style_dialog

        -- Forward declare so the two menus can call each other.
        local openBarStyleMenu, openColoursMenu

        openColoursMenu = function()
            local lc = line_bar_colors or {}
            local function persist()
                if next(lc) == nil then
                    line_bar_colors = nil
                else
                    line_bar_colors = lc
                end
                applyLivePreview()
            end

            local DEFAULT_PCT = { fill = 75, bg = 25 }

            local function pctLabel(field)
                local v = lc[field]
                local t = type(v)
                if t == "nil" then return _("default") end
                if t == "boolean" then return _("transparent") end
                if t == "table" and v.hex then return v.hex end
                local byte
                if t == "table" and v.grey then byte = v.grey
                elseif t == "number" then byte = v end
                if byte then
                    -- 0% = white (real colour) since v5.10.2; no longer
                    -- aliased to "transparent". See issue #43.
                    local pct = math.floor((0xFF - byte) * 100 / 0xFF + 0.5)
                    return pct .. "%"
                end
                return _("default")
            end

            local function colourRow(title, field)
                local default_pct = DEFAULT_PCT[field] or 50
                return {{
                    text = title .. ": " .. pctLabel(field),
                    callback = function()
                        UIManager:close(_bar_style_dialog)
                        if Screen:isColorEnabled() then
                            -- Colour device: hex palette picker.
                            local v = lc[field]
                            local current_hex
                            if type(v) == "table" and v.hex then current_hex = v.hex
                            elseif type(v) == "table" and v.grey then
                                local g = string.format("%02X", v.grey)
                                current_hex = "#" .. g .. g .. g
                            elseif type(v) == "number" then
                                local g = string.format("%02X", v)
                                current_hex = "#" .. g .. g .. g
                            end
                            local default_hex = Colour.defaultHexFor(field)
                            plugin:showColourPicker(title, current_hex, default_hex,
                                function(new_hex)
                                    lc[field] = Colour.toStorageShape(new_hex)
                                    persist(); openColoursMenu()
                                end,
                                function()
                                    lc[field] = nil; persist(); openColoursMenu()
                                end,
                                function() openColoursMenu() end,
                                nil)
                            return
                        end
                        -- Greyscale device: % black nudge dialog, mirroring colours_menu.lua.
                        -- 0% paints pure white since v5.10.2; the Transparent
                        -- extra-button writes `false` for explicit no-fill (#43).
                        local v = lc[field]
                        local byte
                        if type(v) == "table" and v.grey then byte = v.grey
                        elseif type(v) == "number" then byte = v end
                        local current = byte and math.floor((0xFF - byte) * 100 / 0xFF + 0.5) or default_pct
                        plugin:showNudgeDialog(title, current, 0, 100, default_pct, "%",
                            function(val)
                                lc[field] = { grey = 0xFF - math.floor(val * 0xFF / 100 + 0.5) }
                                persist()
                            end,
                            function() openColoursMenu() end,  -- on_close
                            nil, nil, nil,
                            function() lc[field] = nil; persist() end,  -- on_default
                            _("Default") .. " (" .. _("per style") .. ")",
                            {
                                text = _("Transparent"),
                                callback = function()
                                    lc[field] = false
                                    persist()
                                end,
                            })
                    end,
                }}
            end

            local sub_rows = {}
            table.insert(sub_rows, {{
                text = line_bar_colors and _("Disable custom colours") or _("Enable custom colours"),
                callback = function()
                    if line_bar_colors then
                        line_bar_colors = nil
                    else
                        line_bar_colors = {}
                    end
                    applyLivePreview()
                    UIManager:close(_bar_style_dialog); openColoursMenu()
                end,
            }})
            if line_bar_colors then
                table.insert(sub_rows, colourRow(_("Read colour"), "fill"))
                table.insert(sub_rows, colourRow(_("Track colour"), "bg"))
            end
            table.insert(sub_rows, {{
                text = _("Back"),
                callback = function()
                    UIManager:close(_bar_style_dialog); openBarStyleMenu()
                end,
            }})

            _bar_style_dialog = ButtonDialog:new{
                title = _("Bar colours"),
                buttons = sub_rows,
            }
            UIManager:show(_bar_style_dialog)
        end

        openBarStyleMenu = function()
            -- Normalise legacy book_ticks* into the new (type, ticks) split so
            -- the submenu always reads the new shape regardless of preset age.
            -- The legacy mapping wins: see Utils.resolveLineBarTypeAndTicks.
            local norm_type, norm_depth = Utils.resolveLineBarTypeAndTicks(line_bar_type, line_bar_chapter_ticks)
            line_bar_type = norm_type ~= "chapter" and norm_type or nil
            if norm_type == "book" then
                if norm_depth == 1 then line_bar_chapter_ticks = "level1"
                elseif norm_depth == 2 then line_bar_chapter_ticks = "level2"
                elseif norm_depth == math.huge then line_bar_chapter_ticks = "all"
                else line_bar_chapter_ticks = nil end
            else
                line_bar_chapter_ticks = nil
            end

            local current_type  = line_bar_type or "chapter"
            local current_style = line_bar_style or "bordered"
            local current_dir   = line_bar_direction or "ltr"
            local current_ticks = line_bar_chapter_ticks or "off"

            local rows = {}

            -- Row 1: Type
            table.insert(rows, {{
                text = _("Type") .. ": " .. (current_type == "book" and _("Book") or _("Chapter")),
                callback = function()
                    local next_type = current_type == "book" and "chapter" or "book"
                    line_bar_type = next_type ~= "chapter" and next_type or nil
                    applyLivePreview()
                    UIManager:close(_bar_style_dialog); openBarStyleMenu()
                end,
            }})

            -- Row 2: Chapter ticks (only meaningful for Book + non-Pacman)
            local ticks_enabled = current_type == "book" and current_style ~= "pacman"
            table.insert(rows, {{
                text = TICKS_LABELS[current_ticks] or TICKS_LABELS.off,
                enabled = ticks_enabled,
                callback = function()
                    local next_ticks = Utils.cycleNext(TICKS_CYCLE, current_ticks)
                    line_bar_chapter_ticks = next_ticks ~= "off" and next_ticks or nil
                    applyLivePreview()
                    UIManager:close(_bar_style_dialog); openBarStyleMenu()
                end,
            }})

            -- Row 3: Style
            table.insert(rows, {{
                text = _("Style") .. ": " .. (STYLE_LABELS[current_style] or _("Bordered")),
                callback = function()
                    local next_style = Utils.cycleNext(STYLE_CYCLE, current_style)
                    line_bar_style = next_style ~= "bordered" and next_style or nil
                    applyLivePreview()
                    UIManager:close(_bar_style_dialog); openBarStyleMenu()
                end,
            }})

            -- Row 4: Fill direction (hidden for radial — direction is fixed clockwise)
            if current_style ~= "radial" and current_style ~= "radial_hollow" then
                table.insert(rows, {{
                    text = current_dir == "rtl" and _("Fill: right to left") or _("Fill: left to right"),
                    callback = function()
                        local next_dir = current_dir == "rtl" and "ltr" or "rtl"
                        line_bar_direction = next_dir ~= "ltr" and next_dir or nil
                        applyLivePreview()
                        UIManager:close(_bar_style_dialog); openBarStyleMenu()
                    end,
                }})
            end

            -- Row 5: Thickness (Read / Unread)
            do
                local read_h = line_bar_height
                local unread_h = line_bar_unread_height
                local label
                if not read_h then
                    label = _("Thickness") .. ": " .. _("auto")
                elseif unread_h and unread_h ~= read_h then
                    label = _("Thickness") .. ": " .. read_h .. "/" .. unread_h .. "px"
                else
                    label = _("Thickness") .. ": " .. read_h .. "px"
                end
                table.insert(rows, {{
                    text = label,
                    callback = function()
                        UIManager:close(_bar_style_dialog)
                        local default = 12
                        DialogHelpers.showNudgeGrid{
                            title = _("Bar thickness"),
                            rows = {
                                { label = _("Read"),   field = "height" },
                                { label = _("Unread"), field = "unread_height" },
                            },
                            get_value = function(field)
                                if field == "height" then return line_bar_height or default end
                                return line_bar_unread_height or line_bar_height or default
                            end,
                            set_value = function(field, value)
                                if field == "height" then
                                    line_bar_height = value
                                else
                                    local r = line_bar_height or default
                                    line_bar_unread_height = (value ~= r) and value or nil
                                end
                                applyLivePreview()
                            end,
                            on_row_change = function() applyLivePreview() end,
                            on_cancel = function() applyLivePreview() end,
                            on_default = function()
                                line_bar_height = nil
                                line_bar_unread_height = nil
                                applyLivePreview()
                            end,
                            default_text = _("Default") .. " (" .. _("auto") .. ")",
                            on_close = function() openBarStyleMenu() end,
                        }
                    end,
                }})
            end

            -- Row 6: Custom colours (Read + Track)
            local colour_label = line_bar_colors and (_("Custom colours") .. " \u{2713}") or _("Custom colours")
            table.insert(rows, {{
                text = colour_label,
                callback = function()
                    UIManager:close(_bar_style_dialog)
                    openColoursMenu()
                end,
            }})

            -- Close row
            table.insert(rows, {{
                text = _("Close"),
                callback = function() UIManager:close(_bar_style_dialog) end,
            }})

            _bar_style_dialog = ButtonDialog:new{
                title = _("Bar style"),
                buttons = rows,
            }
            UIManager:show(_bar_style_dialog)
        end

        bar_style_menu_button.callback = function()
            format_dialog:onCloseKeyboard()
            openBarStyleMenu()
        end

        style_button.callback = function()
            format_dialog:onCloseKeyboard()
            line_style = Utils.cycleNext(self.STYLES, line_style)
            applyLivePreview()
            format_dialog:reinit()
        end

        size_button.callback = function()
            format_dialog:onCloseKeyboard()
            local current = line_size or self:getPositionSetting(pos.key, "font_size")
            self:showNudgeDialog(_("Font size") .. " " .. _("line") .. " " .. line_idx,
                current, 1, 36, self:getPositionSetting(pos.key, "font_size"), "px",
                function(val)
                    line_size = val
                    applyLivePreview()
                end,
                function()
                    format_dialog:reinit()
                end, 1, false)
        end

        font_button.callback = function()
            format_dialog:onCloseKeyboard()
            self:showFontPicker(
                line_face or self:getPositionSetting(pos.key, "font_face"),
                function(font_filename)
                    line_face = font_filename
                    applyLivePreview()
                    format_dialog:reinit()
                end,
                self:getPositionSetting(pos.key, "font_face")
            )
        end

        -- Nudge buttons (1px per tap). Use Nerd Font chevron glyphs rendered
        -- as button text rather than KOReader stock icons: ButtonTable doesn't
        -- forward icon_rotation_angle to Button (its forwarded-fields allowlist
        -- omits it), and stock KOReader ships chevron.up/left/right but not
        -- chevron.down. The bundled Symbols Nerd Font has matched chevrons in
        -- all four directions (mdi range U+E83F-E842), and ButtonTable does
        -- forward `font_face` to text_font_face — so no patches, no shared-
        -- icons-folder workaround, no stylistic split inside the dialog.
        -- font_size matches the SVG-icon canvas of the previous chevron icons
        -- so they read as buttons rather than tiny glyphs against the
        -- adjacent "Position" text label.
        local NUDGE_GLYPH_SIZE = 28
        local nudge_up = {
            text = "\xEE\xA1\x82",  -- U+E842 mdi-chevron-up
            font_face = "symbols",
            font_size = NUDGE_GLYPH_SIZE,
            callback = function() end,
        }
        local nudge_down = {
            text = "\xEE\xA0\xBF",  -- U+E83F mdi-chevron-down
            font_face = "symbols",
            font_size = NUDGE_GLYPH_SIZE,
            callback = function() end,
        }
        local nudge_left = {
            text = "\xEE\xA1\x80",  -- U+E840 mdi-chevron-left
            font_face = "symbols",
            font_size = NUDGE_GLYPH_SIZE,
            callback = function() end,
        }
        local nudge_right = {
            text = "\xEE\xA1\x81",  -- U+E841 mdi-chevron-right
            font_face = "symbols",
            font_size = NUDGE_GLYPH_SIZE,
            callback = function() end,
        }
        local nudge_label = {
            text_func = function()
                if line_v_nudge == 0 and line_h_nudge == 0 then
                    return _("Position")
                end
                return line_h_nudge .. "," .. line_v_nudge
            end,
            callback = function() end,  -- reset, wired below
        }

        local function doNudge(axis, delta)
            format_dialog:onCloseKeyboard()
            if axis == "v" then
                line_v_nudge = line_v_nudge + delta
            else
                line_h_nudge = line_h_nudge + delta
            end
            applyLivePreview()
            format_dialog:reinit()
        end
        nudge_up.callback = function() doNudge("v", -1) end
        nudge_up.hold_callback = function() doNudge("v", -10) end
        nudge_down.callback = function() doNudge("v", 1) end
        nudge_down.hold_callback = function() doNudge("v", 10) end
        nudge_left.callback = function() doNudge("h", -1) end
        nudge_left.hold_callback = function() doNudge("h", -10) end
        nudge_right.callback = function() doNudge("h", 1) end
        nudge_right.hold_callback = function() doNudge("h", 10) end
        nudge_label.callback = function()
            format_dialog:onCloseKeyboard()
            line_v_nudge = 0
            line_h_nudge = 0
            applyLivePreview()
            format_dialog:reinit()
        end

        local function buildDialogButtons()
            local rows = {
                { style_button, size_button, font_button, case_button, page_filter_button },
                { nudge_left, nudge_right, nudge_label, nudge_up, nudge_down },
                { bar_insert_button, bar_style_menu_button },
            }
            table.insert(rows, {
                {
                    text = _("Cancel"),
                    callback = function()
                        self._live_edit_position = nil
                        self._live_edit_line_idx = nil
                        self.positions[pos.key] = util.tableDeepCopy(original_settings)
                        self:savePositionSetting(pos.key)
                        UIManager:close(format_dialog)
                        self:markDirty()
                        if touchmenu_instance then
                            touchmenu_instance.item_table = self:buildPositionMenu(pos)
                        end
                        restoreMenu()
                    end,
                },
                {
                    text = _("Icons"),
                    callback = function()
                        format_dialog:onCloseKeyboard()
                        IconsLibrary:show(function(value)
                            format_dialog:addTextToInput(value)
                        end)
                    end,
                },
                {
                    text = _("Tokens"),
                    callback = function()
                        format_dialog:onCloseKeyboard()
                        local TokensLibrary = require("menu.tokens_library")
                        TokensLibrary:show(self, function(token)
                            format_dialog:addTextToInput(token)
                        end)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        self._live_edit_position = nil
                        self._live_edit_line_idx = nil
                        local new_text = format_dialog:getInputText()
                        if new_text == "" then
                            table.remove(pos_settings.lines, line_idx)
                            removeLineFields(pos_settings, line_idx)
                        else
                            pos_settings.lines[line_idx] = new_text
                            applyLivePreview()
                        end
                        self:savePositionSetting(pos.key)
                        UIManager:close(format_dialog)
                        self:markDirty()
                        if touchmenu_instance then
                            touchmenu_instance.item_table = self:buildPositionMenu(pos)
                        end
                        restoreMenu()
                    end,
                },
            })
            return rows
        end

        -- Measure line height for the InputDialog's default font to set a 3-line text area
        local input_face = Font:getFace("x_smallinfofont")
        local TextBoxWidget = require("ui/widget/textboxwidget")
        local measure = TextBoxWidget:new{
            text = "M",
            face = input_face,
            width = Screen:getWidth(),
            for_measurement_only = true,
        }
        local input_text_height = measure:getLineHeight() * 2
        measure:free(true)

        self._live_edit_position = pos.key
        self._live_edit_line_idx = line_idx
        format_dialog = InputDialog:new{
            title = pos.label .. " \xE2\x80\x94 " .. _("Line") .. " " .. line_idx,
            input = current_text,
            allow_newline = true,
            text_height = input_text_height,
            edited_callback = function()
                -- Live preview of text changes (guard: fires during init before format_dialog is assigned)
                if not format_dialog then return end
                local live_text = format_dialog:getInputText()
                if live_text and live_text ~= "" then
                    pos_settings.lines[line_idx] = live_text
                    -- Mark dirty and request repaint immediately (not via nextTick)
                    -- so it merges into the InputDialog's own paint cycle.  A deferred
                    -- repaint causes a *separate* e-ink refresh that briefly flashes
                    -- book text through the Bookends area.
                    --
                    -- Tick cache is intentionally NOT cleared here: the format
                    -- string doesn't affect tick fractions (those depend on TOC
                    -- pages / total pages, keyed by flow id at the rebuild
                    -- check). Sparing this clear lets typing in the editor
                    -- skip the per-keystroke TOC walk on books with many
                    -- chapters or hidden flows.
                    self.dirty = true
                    UIManager:setDirty(self.ui, "fast")
                end
            end,
            buttons = buildDialogButtons(),
        }
        -- Allow tap-outside to hide keyboard, but never close dialog
        function format_dialog:onTap(arg, ges)
            if self:isKeyboardVisible() then
                if self._input_widget.keyboard and self._input_widget.keyboard.dimen
                        and ges.pos:notIntersectWith(self._input_widget.keyboard.dimen) then
                    self:onCloseKeyboard()
                end
            end
            -- Never close the dialog on tap-outside
        end
        -- Always report keyboard as visible so dialog layout stays in upper portion.
        -- But track real keyboard state to avoid reopening it on reinit.
        local real_kb_visible = false
        local orig_onShowKeyboard = format_dialog.onShowKeyboard
        function format_dialog:isKeyboardVisible()
            return true  -- layout always reserves keyboard space
        end
        function format_dialog:onShowKeyboard(...)
            real_kb_visible = true
            return orig_onShowKeyboard(self, ...)
        end
        local orig_onCloseKeyboard = format_dialog.onCloseKeyboard
        function format_dialog:onCloseKeyboard(...)
            real_kb_visible = false
            return orig_onCloseKeyboard(self, ...)
        end
        local orig_reinit = format_dialog.reinit
        function format_dialog:reinit(...)
            -- reinit checks isKeyboardVisible (returns true for layout),
            -- then calls onShowKeyboard if true. Suppress that when kb was actually hidden.
            local was_visible = real_kb_visible
            orig_reinit(self, ...)
            if not was_visible then
                self._input_widget:onCloseKeyboard()
                real_kb_visible = false
            end
            if self.movable then
                self.movable.ges_events.MovableHold = nil
                self.movable.ges_events.MovableHoldPan = nil
                self.movable.ges_events.MovableHoldRelease = nil
            end
        end
        if format_dialog.movable then
            format_dialog.movable.ges_events.MovableHold = nil
            format_dialog.movable.ges_events.MovableHoldPan = nil
            format_dialog.movable.ges_events.MovableHoldRelease = nil
        end
        UIManager:show(format_dialog)
        -- Hide keyboard after show — dialog is already positioned for keyboard-open,
        -- so it stays in the upper portion of screen, clear of the keyboard when reopened.
        format_dialog:onCloseKeyboard()
    end

    function Bookends:showLineManageDialog(pos, line_idx, touchmenu_instance)
        local ps = self.positions[pos.key]
        local num_lines = #ps.lines

        local function refreshMenu()
            if touchmenu_instance then
                touchmenu_instance.item_table = self:buildPositionMenu(pos)
                touchmenu_instance:updateItems()
            end
        end

        local function removeLine()
            table.remove(ps.lines, line_idx)
            removeLineFields(ps, line_idx)
            self:savePositionSetting(pos.key)
            self:markDirty()
            refreshMenu()
        end

        local function swapLines(a, b)
            ps.lines[a], ps.lines[b] = ps.lines[b], ps.lines[a]
            swapLineFields(ps, a, b)
            self:savePositionSetting(pos.key)
            self:markDirty()
            refreshMenu()
        end

        local other_buttons = {}
        if line_idx > 1 then
            table.insert(other_buttons, {
                {
                    text = _("Move up"),
                    callback = function()
                        swapLines(line_idx, line_idx - 1)
                    end,
                },
            })
        end
        if line_idx < num_lines then
            table.insert(other_buttons, {
                {
                    text = _("Move down"),
                    callback = function()
                        swapLines(line_idx, line_idx + 1)
                    end,
                },
            })
        end

        -- Move to another region
        local function moveToRegion(target_key)
            local target = self.positions[target_key]
            target.lines = target.lines or {}
            target.line_style = target.line_style or {}
            target.line_font_size = target.line_font_size or {}
            target.line_font_face = target.line_font_face or {}
            target.line_v_nudge = target.line_v_nudge or {}
            target.line_h_nudge = target.line_h_nudge or {}
            target.line_uppercase = target.line_uppercase or {}
            target.line_bar_type = target.line_bar_type or {}
            target.line_bar_height = target.line_bar_height or {}
            target.line_bar_style = target.line_bar_style or {}
            target.line_bar_chapter_ticks = target.line_bar_chapter_ticks or {}
            target.line_bar_direction = target.line_bar_direction or {}
            target.line_bar_unread_height = target.line_bar_unread_height or {}
            target.line_bar_colors = target.line_bar_colors or {}

            -- Append to target
            local ti = #target.lines + 1
            target.lines[ti] = ps.lines[line_idx]
            target.line_style[ti] = ps.line_style and ps.line_style[line_idx] or nil
            target.line_font_size[ti] = ps.line_font_size and ps.line_font_size[line_idx] or nil
            target.line_font_face[ti] = ps.line_font_face and ps.line_font_face[line_idx] or nil
            target.line_v_nudge[ti] = ps.line_v_nudge and ps.line_v_nudge[line_idx] or nil
            target.line_h_nudge[ti] = ps.line_h_nudge and ps.line_h_nudge[line_idx] or nil
            target.line_uppercase[ti] = ps.line_uppercase and ps.line_uppercase[line_idx] or nil
            target.line_bar_type[ti] = ps.line_bar_type and ps.line_bar_type[line_idx] or nil
            target.line_bar_height[ti] = ps.line_bar_height and ps.line_bar_height[line_idx] or nil
            target.line_bar_style[ti] = ps.line_bar_style and ps.line_bar_style[line_idx] or nil
            target.line_bar_chapter_ticks[ti] = ps.line_bar_chapter_ticks and ps.line_bar_chapter_ticks[line_idx] or nil
            target.line_bar_direction[ti] = ps.line_bar_direction and ps.line_bar_direction[line_idx] or nil
            target.line_bar_unread_height[ti] = ps.line_bar_unread_height and ps.line_bar_unread_height[line_idx] or nil
            target.line_bar_colors[ti] = ps.line_bar_colors and ps.line_bar_colors[line_idx] or nil

            -- Remove from source
            removeLine()

            self:savePositionSetting(target_key)
        end

        -- Build "Move to" buttons — one row per available region (excluding current)
        for _i, p in ipairs(self.POSITIONS) do
            if p.key ~= pos.key then
                table.insert(other_buttons, {
                    {
                        text = _("Move to") .. " " .. p.label,
                        callback = function()
                            moveToRegion(p.key)
                        end,
                    },
                })
            end
        end

        UIManager:show(ConfirmBox:new{
            text = T(_("Line %1: %2"), line_idx, ps.lines[line_idx]),
            icon = "notice-question",
            ok_text = _("Delete"),
            ok_callback = function()
                removeLine()
            end,
            cancel_text = _("Cancel"),
            other_buttons_first = true,
            other_buttons = other_buttons,
        })
    end
end

return LineEditor
