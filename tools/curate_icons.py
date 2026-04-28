#!/usr/bin/env python3
"""Bookends icon curator — localhost web editor for menu/icons_catalogue.lua.

Loads the current chip definitions, curated picks, pattern-fill rules,
and per-chip excludes; renders them in a browser tab with the actual
Nerd Font glyph for every icon; on Save writes a regenerated catalogue
file back to disk.

Usage:
    python3 tools/curate_icons.py [--port 8765] [--no-browser]
"""

import argparse
import http.server
import json
import os
import socket
import socketserver
import subprocess
import sys
import tempfile
import threading
import urllib.parse
import webbrowser
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CATALOGUE_PATH = REPO_ROOT / "menu" / "icons_catalogue.lua"
SYMBOLS_TTF = Path("/usr/lib/koreader/fonts/nerdfonts/symbols.ttf")
SCRATCH_PATH = REPO_ROOT / "tools" / ".curator_scratch.json"

# Lua dump script: stubs i18n so _() acts as identity, requires the
# catalogue + cmap, and prints a JSON blob the curator consumes.
DUMP_LUA = r'''
package.path = arg[1] .. "/?.lua;" .. arg[1] .. "/menu/?.lua;" .. package.path

package.preload["bookends_i18n"] = function()
    return { gettext = function(s) return s end }
end

local catalogue = require("menu.icons_catalogue")
local names = require("bookends_nerdfont_names")

local function encode_string(s)
    s = s:gsub('\\', '\\\\'):gsub('"', '\\"')
    s = s:gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
    return '"' .. s .. '"'
end

local function encode(v)
    local t = type(v)
    if t == "string" then
        return encode_string(v)
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "table" then
        local n = 0
        for _ in pairs(v) do n = n + 1 end
        local is_array = (#v == n)
        if is_array and n > 0 then
            local parts = {}
            for i, x in ipairs(v) do parts[i] = encode(x) end
            return "[" .. table.concat(parts, ",") .. "]"
        elseif n == 0 then
            return "{}"
        else
            local parts = {}
            for k, x in pairs(v) do
                parts[#parts+1] = encode_string(tostring(k)) .. ":" .. encode(x)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

print(encode({
    chips = catalogue.CHIPS,
    curated = catalogue.CURATED_BY_CHIP,
    patterns = catalogue.PATTERNS_BY_CHIP,
    excludes = catalogue.PATTERN_EXCLUDES,
    cmap = names,
}))
'''


def load_catalogue():
    """Run lua to dump catalogue + cmap as JSON."""
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False) as f:
        f.write(DUMP_LUA)
        dump_path = f.name
    try:
        result = subprocess.run(
            ["lua", dump_path, str(REPO_ROOT)],
            capture_output=True, text=True, check=True,
        )
        return json.loads(result.stdout)
    finally:
        os.unlink(dump_path)


def lua_string_literal(s):
    """Quote a Python string as a Lua string literal with \\xHH escapes for
    non-ASCII bytes so the resulting file stays ASCII-clean."""
    out = ['"']
    for ch in s.encode("utf-8"):
        if ch == 0x22:
            out.append('\\"')
        elif ch == 0x5C:
            out.append('\\\\')
        elif 0x20 <= ch < 0x7F:
            out.append(chr(ch))
        else:
            out.append('\\x{:02X}'.format(ch))
    out.append('"')
    return ''.join(out)


def render_lua(catalogue, cmap):
    """Build the new icons_catalogue.lua source from a JSON catalogue."""
    names_by_code = {e["code"]: e["name"] for e in cmap}

    lines = []
    lines.append('--- Icons library catalogue: chip definitions, curated picks, pattern-fill')
    lines.append('--- rules, and per-chip exclusions. This file is data-only — the projection')
    lines.append('--- and rendering live in menu/icons_library.lua.')
    lines.append('---')
    lines.append('--- Edit by hand or via the curator web app at tools/curate_icons.py. The')
    lines.append('--- curator overwrites this whole file on save, so any structural changes')
    lines.append('--- (new tables, helpers) belong in menu/icons_library.lua, not here.')
    lines.append('---')
    lines.append('--- Curated entry shapes:')
    lines.append('---   { code = 0xNNNN, ... }   - Nerd Font glyph picked by codepoint. Label')
    lines.append('---                              comes from the font\'s cmap unless overridden')
    lines.append('---                              by `label = ...`.')
    lines.append('---   { glyph = "<bytes>", label = "..." }')
    lines.append('---                            - Pure-Unicode glyph (not in the cmap). Label')
    lines.append('---                              is the hand-written description.')
    lines.append('--- Optional fields: `label` (override the cmap name), `insert_value` (token')
    lines.append('--- string inserted instead of the literal glyph — used for dynamic icons).')
    lines.append('')
    lines.append('local _ = require("bookends_i18n").gettext')
    lines.append('')
    lines.append('local M = {}')
    lines.append('')

    lines.append('M.CHIPS = {')
    for chip in catalogue['chips']:
        lines.append('    {{ key = {key}, label = _({label}) }},'.format(
            key=lua_string_literal(chip['key']),
            label=lua_string_literal(chip['label']),
        ))
    lines.append('}')
    lines.append('')

    lines.append('M.CURATED_BY_CHIP = {')
    for chip in catalogue['chips']:
        key = chip['key']
        if key == 'all':
            continue
        items = catalogue['curated'].get(key) or []
        if not items:
            continue
        lines.append('    {} = {{'.format(key))
        for item in items:
            parts = []
            if 'code' in item:
                parts.append('code = 0x{:04X}'.format(item['code']))
            if 'glyph' in item:
                parts.append('glyph = {}'.format(lua_string_literal(item['glyph'])))
            if 'label' in item:
                parts.append('label = _({})'.format(lua_string_literal(item['label'])))
            if 'insert_value' in item:
                parts.append('insert_value = {}'.format(lua_string_literal(item['insert_value'])))
            comment = ''
            if 'code' in item and item['code'] in names_by_code:
                comment = '   -- ' + names_by_code[item['code']]
            lines.append('        {{ {} }},{}'.format(', '.join(parts), comment))
        lines.append('    },')
    lines.append('}')
    lines.append('')

    lines.append('M.PATTERNS_BY_CHIP = {')
    for chip in catalogue['chips']:
        key = chip['key']
        patterns = catalogue['patterns'].get(key) or []
        if not patterns:
            continue
        formatted = ', '.join(lua_string_literal(p) for p in patterns)
        lines.append('    {} = {{ {} }},'.format(key, formatted))
    lines.append('}')
    lines.append('')

    lines.append('M.PATTERN_EXCLUDES = {')
    for chip in catalogue['chips']:
        key = chip['key']
        excludes = catalogue['excludes'].get(key) or {}
        if not excludes:
            continue
        lines.append('    {} = {{'.format(key))
        for name in sorted(excludes):
            lines.append('        [{}] = true,'.format(lua_string_literal(name)))
        lines.append('    },')
    lines.append('}')
    lines.append('')

    lines.append('return M')
    lines.append('')

    return '\n'.join(lines)


# Static markup only — every place dynamic data flows in (chip labels,
# cmap names, pattern lines) goes through DOM construction or the `esc`
# helper, never raw template interpolation, so untrusted strings can't
# inject markup if a label or pattern ever contains HTML.
INDEX_HTML = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Bookends icon curator</title>
<style>
@font-face {
    font-family: "NerdSymbols";
    src: url("/api/font") format("truetype");
}
* { box-sizing: border-box; }
body {
    margin: 0; font-family: -apple-system, "Segoe UI", system-ui, sans-serif;
    font-size: 14px; color: #222; background: #fafafa;
    display: grid; grid-template-rows: auto 1fr auto;
    height: 100vh;
}
.topbar {
    padding: 10px 16px; border-bottom: 1px solid #ddd; background: #fff;
    display: flex; align-items: center; gap: 12px;
}
.topbar h1 { font-size: 16px; font-weight: 600; margin: 0; flex: 1; }
.status { font-size: 12px; color: #888; }
button {
    border: 1px solid #ccc; background: #fff; padding: 6px 12px;
    border-radius: 4px; cursor: pointer; font-size: 13px;
}
button:hover { background: #f0f0f0; }
button.primary { background: #2563eb; color: #fff; border-color: #2563eb; }
button.primary:hover { background: #1d4ed8; }
main { display: grid; grid-template-columns: 200px 1fr; overflow: hidden; }
nav { border-right: 1px solid #ddd; background: #fff; overflow-y: auto; padding: 8px 0; }
nav .chip {
    display: flex; justify-content: space-between; padding: 8px 16px;
    cursor: pointer; border-left: 3px solid transparent;
}
nav .chip:hover { background: #f0f0f0; }
nav .chip.active { background: #eff6ff; border-left-color: #2563eb; font-weight: 600; }
nav .chip .count { color: #888; font-size: 12px; font-variant-numeric: tabular-nums; }
section.detail { overflow-y: auto; padding: 16px 24px; }
section.detail h2 { font-size: 18px; margin: 0 0 4px; }
section.detail h2 small { font-weight: normal; color: #888; }
section.detail .subhead { color: #666; font-size: 12px; margin-bottom: 16px; }
.subsection {
    background: #fff; border: 1px solid #e5e5e5; border-radius: 6px;
    padding: 14px 16px; margin-bottom: 16px;
}
.subsection h3 {
    font-size: 14px; font-weight: 600; margin: 0 0 8px;
    display: flex; justify-content: space-between; align-items: center;
}
.subsection h3 .count { color: #888; font-size: 12px; font-weight: normal; }
.icon-grid {
    display: grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
    gap: 6px;
}
.icon-cell {
    border: 1px solid #e5e5e5; border-radius: 4px; padding: 8px 6px;
    background: #fff; display: flex; flex-direction: column; align-items: center;
    cursor: default; font-size: 11px; color: #444; word-break: break-all;
    text-align: center; position: relative; min-height: 76px;
}
.icon-cell .glyph {
    font-family: "NerdSymbols", monospace; font-size: 28px; line-height: 1;
    margin-bottom: 6px; color: #111;
}
.icon-cell.curated { background: #eff6ff; border-color: #93c5fd; }
.icon-cell.excluded { background: #fef2f2; border-color: #fca5a5; opacity: 0.7; }
.icon-cell .remove {
    position: absolute; top: 2px; right: 2px; background: transparent;
    border: 0; padding: 2px 6px; color: #dc2626; font-size: 14px; cursor: pointer;
    visibility: hidden;
}
.icon-cell:hover .remove { visibility: visible; }
.icon-cell .code { color: #888; font-size: 10px; }
textarea {
    width: 100%; min-height: 80px; padding: 8px; border: 1px solid #ddd;
    border-radius: 4px; font-family: "SF Mono", Menlo, monospace; font-size: 13px;
    resize: vertical;
}
.row { display: flex; gap: 8px; align-items: center; }
.search-box {
    flex: 1; padding: 6px 10px; border: 1px solid #ccc; border-radius: 4px;
    font-size: 13px;
}
.modal-bg {
    position: fixed; inset: 0; background: rgba(0,0,0,.4); display: none;
    align-items: center; justify-content: center; z-index: 100;
}
.modal-bg.show { display: flex; }
.modal {
    background: #fff; border-radius: 8px; width: min(800px, 90vw);
    height: min(600px, 80vh); display: flex; flex-direction: column;
}
.modal .modal-head {
    padding: 12px 16px; border-bottom: 1px solid #e5e5e5; display: flex;
    gap: 8px; align-items: center;
}
.modal .body { flex: 1; overflow-y: auto; padding: 12px; }
.modal .modal-foot {
    padding: 10px 16px; border-top: 1px solid #e5e5e5;
    display: flex; justify-content: flex-end;
}
.statusbar {
    padding: 8px 16px; border-top: 1px solid #ddd; background: #fff;
    display: flex; align-items: center; gap: 12px; font-size: 12px;
    color: #555;
}
.dirty { color: #c2410c; font-weight: 600; }
.clean { color: #16a34a; }
</style>
</head>
<body>
<div class="topbar">
    <h1>Bookends icon curator</h1>
    <span class="status" id="status">Loading…</span>
    <button id="reset">Discard changes</button>
    <button id="apply" class="primary">Save catalogue</button>
</div>
<main>
    <nav id="chips"></nav>
    <section class="detail" id="detail"></section>
</main>
<div class="statusbar">
    <span>Catalogue file: <code>menu/icons_catalogue.lua</code></span>
    <span style="flex:1"></span>
    <span id="apply-result"></span>
</div>

<div class="modal-bg" id="picker-modal">
    <div class="modal">
        <div class="modal-head">
            <input type="text" class="search-box" id="picker-search"
                placeholder="Search by name (e.g. memory, av-timer, chevron-double)…">
            <button id="picker-close">Close</button>
        </div>
        <div class="body" id="picker-body"></div>
        <div class="modal-foot">
            <span id="picker-count" style="margin-right:auto; font-size:12px; color:#666;"></span>
            <button id="picker-done" class="primary">Done</button>
        </div>
    </div>
</div>

<script>
const PATTERN_CHIPS = ['device','reading','time','status','arrows'];

const state = {
    catalogue: null,
    cmap: null,
    cmapByCode: {},
    activeChip: 'all',
    dirty: false,
    pickerSearch: '',
    pickerTarget: null,
};

// ---- Utilities ----------------------------------------------------------

function utf8FromCodepoint(cp) {
    if (cp < 0x80) return String.fromCodePoint(cp);
    return String.fromCodePoint(cp);
}

function glyphFor(item) {
    if (item.code != null) return utf8FromCodepoint(item.code);
    return item.glyph || '';
}

function labelFor(item) {
    if (item.label) return item.label;
    if (item.code != null) {
        const e = state.cmapByCode[item.code];
        return (e && e.name) || ('U+' + item.code.toString(16).toUpperCase());
    }
    return '';
}

function nameMatchesAny(name, patterns, excludes) {
    if (excludes && excludes[name]) return false;
    for (const p of patterns) {
        if (name.includes(p)) return true;
    }
    return false;
}

function projectChip(key) {
    if (key === 'all') return state.cmap.slice();
    const curated = state.catalogue.curated[key] || [];
    const patterns = state.catalogue.patterns[key] || [];
    const excludes = state.catalogue.excludes[key] || {};
    const seen = new Set();
    const out = [];
    for (const item of curated) {
        const cell = Object.assign({}, item);
        cell.glyph = glyphFor(item);
        cell.label = labelFor(item);
        if (item.code != null) {
            cell.canonical = (state.cmapByCode[item.code] || {}).name || null;
            seen.add(item.code);
        }
        out.push(cell);
    }
    if (patterns.length) {
        for (const e of state.cmap) {
            if (seen.has(e.code)) continue;
            if (!nameMatchesAny(e.name, patterns, excludes)) continue;
            seen.add(e.code);
            out.push({
                code: e.code, glyph: utf8FromCodepoint(e.code),
                label: e.name, canonical: e.name,
            });
        }
    }
    out.sort((a, b) => {
        const ka = (a.canonical || a.label || '').toLowerCase();
        const kb = (b.canonical || b.label || '').toLowerCase();
        return ka < kb ? -1 : ka > kb ? 1 : 0;
    });
    return out;
}

function setDirty() {
    state.dirty = true;
    const s = document.getElementById('status');
    s.textContent = 'Unsaved changes';
    s.className = 'status dirty';
    autosave();
}

function setClean(msg) {
    state.dirty = false;
    const s = document.getElementById('status');
    s.textContent = msg || 'Saved';
    s.className = 'status clean';
}

let autosaveTimer = null;
function autosave() {
    clearTimeout(autosaveTimer);
    autosaveTimer = setTimeout(async () => {
        await fetch('/api/save', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify(state.catalogue),
        });
    }, 500);
}

function clearChildren(node) {
    while (node.firstChild) node.removeChild(node.firstChild);
}

function el(tag, props, ...children) {
    const node = document.createElement(tag);
    if (props) {
        for (const [k, v] of Object.entries(props)) {
            if (k === 'class') node.className = v;
            else if (k === 'text') node.textContent = v;
            else if (k.startsWith('on') && typeof v === 'function') {
                node.addEventListener(k.slice(2), v);
            } else if (k === 'value') node.value = v;
            else if (k === 'placeholder' || k === 'type' || k === 'title') {
                node.setAttribute(k, v);
            } else {
                node.setAttribute(k, v);
            }
        }
    }
    for (const c of children) {
        if (c == null) continue;
        node.appendChild(typeof c === 'string'
            ? document.createTextNode(c) : c);
    }
    return node;
}

// ---- Sidebar ------------------------------------------------------------

// Dynamic chip is intentionally hidden from the curator — those entries
// must be edited in code (they need label overrides + insert_value
// tokens that the curator's "+ Add icon" flow can't produce). The
// chip's data still round-trips through state.catalogue unchanged.
const HIDDEN_CHIPS = new Set(['dynamic']);

function visibleChips() {
    return state.catalogue.chips.filter(c => !HIDDEN_CHIPS.has(c.key));
}

function renderChips() {
    const nav = document.getElementById('chips');
    clearChildren(nav);
    for (const chip of visibleChips()) {
        const count = chip.key === 'all'
            ? state.cmap.length
            : projectChip(chip.key).length;
        const div = el('div', {
            class: 'chip' + (chip.key === state.activeChip ? ' active' : ''),
            onclick: () => { state.activeChip = chip.key; renderAll(); },
        },
            el('span', { text: chip.label }),
            el('span', { class: 'count', text: String(count) }),
        );
        nav.appendChild(div);
    }
}

// ---- Detail pane --------------------------------------------------------

function renderDetail() {
    const wrap = document.getElementById('detail');
    clearChildren(wrap);
    const chip = state.catalogue.chips.find(c => c.key === state.activeChip);
    if (!chip) return;
    if (chip.key === 'all') {
        renderAllChip(wrap);
        return;
    }
    const supportsPatterns = PATTERN_CHIPS.includes(chip.key)
        || (state.catalogue.patterns[chip.key] || []).length > 0;
    const projected = projectChip(chip.key);

    const head = el('h2', null, chip.label, ' ',
        el('small', { text: '(' + chip.key + ')' }));
    wrap.appendChild(head);
    wrap.appendChild(el('div', {
        class: 'subhead',
        text: 'Curated picks render in their hand-written order; pattern matches '
            + 'append, all sorted alphabetically by name. Hover an icon to remove it.',
    }));
    wrap.appendChild(curatedSection(chip.key));
    if (supportsPatterns) {
        wrap.appendChild(patternsSection(chip.key));
        wrap.appendChild(excludesSection(chip.key));
    }
    wrap.appendChild(previewSection(projected, chip.key));
}

function renderAllChip(wrap) {
    wrap.appendChild(el('h2', null, 'All ',
        el('small', { text: '(' + state.cmap.length + ' entries)' })));
    wrap.appendChild(el('div', {
        class: 'subhead',
        text: 'The full Nerd Font cmap. Read-only here; use a chip\'s "+ Add icon" '
            + 'button to copy entries into curated picks.',
    }));
    const row = el('div', { class: 'row' },
        el('input', {
            class: 'search-box', id: 'all-search', type: 'text',
            placeholder: 'Filter by name…',
        }),
        el('span', { id: 'all-count', style: 'font-size:12px;color:#666;' }),
    );
    row.style.marginBottom = '12px';
    wrap.appendChild(row);
    const grid = el('div', { class: 'icon-grid', id: 'all-grid' });
    wrap.appendChild(grid);
    document.getElementById('all-search').addEventListener('input', (e) => {
        renderAllGrid(e.target.value.trim().toLowerCase());
    });
    renderAllGrid('');
}

function renderAllGrid(q) {
    const grid = document.getElementById('all-grid');
    const cnt = document.getElementById('all-count');
    clearChildren(grid);
    let shown = 0;
    for (const e of state.cmap) {
        if (q && !e.name.includes(q)) continue;
        grid.appendChild(makeCell({ code: e.code, label: e.name }, false));
        shown++;
    }
    cnt.textContent = shown + ' / ' + state.cmap.length;
}

function curatedSection(key) {
    const items = state.catalogue.curated[key] || [];
    const grid = el('div', { class: 'icon-grid' });
    items.forEach((item, i) => {
        grid.appendChild(makeCell(item, true, () => {
            items.splice(i, 1);
            setDirty();
            renderAll();
        }));
    });
    return el('div', { class: 'subsection' },
        el('h3', null, 'Curated picks ',
            el('span', { class: 'count', text: String(items.length) })),
        grid,
        el('button', {
            onclick: () => openPicker(key),
            style: 'margin-top:10px;',
            text: '+ Add icon from cmap…',
        }),
    );
}

function patternsSection(key) {
    const patterns = state.catalogue.patterns[key] || [];
    const ta = el('textarea', { id: 'patterns-text', value: patterns.join('\n') });
    ta.addEventListener('change', () => {
        const lines = ta.value.split('\n').map(s => s.trim()).filter(Boolean);
        state.catalogue.patterns[key] = lines;
        setDirty();
        renderAll();
    });
    return el('div', { class: 'subsection' },
        el('h3', null, 'Patterns ',
            el('span', { class: 'count', text: String(patterns.length) })),
        el('div', {
            class: 'subhead',
            text: 'One pattern per line. Plain substring match against the cmap name.',
        }),
        ta,
    );
}

function excludesSection(key) {
    const excludes = state.catalogue.excludes[key] || {};
    const lines = Object.keys(excludes).sort();
    const ta = el('textarea', { id: 'excludes-text', value: lines.join('\n') });
    ta.addEventListener('change', () => {
        const newLines = ta.value.split('\n').map(s => s.trim()).filter(Boolean);
        state.catalogue.excludes[key] = Object.fromEntries(
            newLines.map(n => [n, true]));
        setDirty();
        renderAll();
    });
    return el('div', { class: 'subsection' },
        el('h3', null, 'Excludes ',
            el('span', { class: 'count', text: String(lines.length) })),
        el('div', {
            class: 'subhead',
            text: 'Names matched by patterns above that don\'t belong in this chip. One per line.',
        }),
        ta,
    );
}

function previewSection(projected, key) {
    const exMap = state.catalogue.excludes[key] || {};
    const grid = el('div', { class: 'icon-grid' });
    for (const cell of projected) {
        const enriched = Object.assign({}, cell, { _excluded: !!exMap[cell.canonical] });
        grid.appendChild(makeCell(enriched, false));
    }
    return el('div', { class: 'subsection' },
        el('h3', null, 'Final chip output ',
            el('span', { class: 'count', text: String(projected.length) })),
        el('div', {
            class: 'subhead',
            text: 'What the Kindle will render after curated + pattern-fill + sort.',
        }),
        grid,
    );
}

function makeCell(item, removable, onRemove) {
    const classes = ['icon-cell'];
    if (item._curated) classes.push('curated');
    if (item._excluded) classes.push('excluded');
    const cell = el('div', { class: classes.join(' ') });
    cell.appendChild(el('div', { class: 'glyph', text: glyphFor(item) }));
    cell.appendChild(el('div', { text: labelFor(item) }));
    if (item.code != null) {
        cell.appendChild(el('div', {
            class: 'code',
            text: 'U+' + item.code.toString(16).toUpperCase(),
        }));
    }
    if (removable) {
        const x = el('button', {
            class: 'remove', title: 'Remove from chip', text: '✕',
            onclick: (ev) => { ev.stopPropagation(); onRemove(); },
        });
        cell.appendChild(x);
    }
    return cell;
}

// ---- Add-icon picker modal ---------------------------------------------

function openPicker(targetChipKey) {
    const modal = document.getElementById('picker-modal');
    modal.classList.add('show');
    state.pickerTarget = targetChipKey;
    state.pickerSearch = '';
    document.getElementById('picker-search').value = '';
    document.getElementById('picker-search').focus();
    renderPicker();
}

function closePicker() {
    document.getElementById('picker-modal').classList.remove('show');
}

function renderPicker() {
    const body = document.getElementById('picker-body');
    clearChildren(body);
    const q = state.pickerSearch.trim().toLowerCase();
    const targetKey = state.pickerTarget;
    const inCurated = new Set(
        (state.catalogue.curated[targetKey] || [])
            .filter(i => i.code != null).map(i => i.code));
    const grid = el('div', { class: 'icon-grid' });
    let shown = 0;
    for (const e of state.cmap) {
        if (q && !e.name.includes(q)) continue;
        const inCur = inCurated.has(e.code);
        const cell = makeCell({ code: e.code, label: e.name, _curated: inCur }, false);
        cell.style.cursor = 'pointer';
        cell.addEventListener('click', () => {
            const cur = state.catalogue.curated[targetKey] || [];
            if (inCur) {
                const idx = cur.findIndex(x => x.code === e.code);
                if (idx >= 0) cur.splice(idx, 1);
            } else {
                cur.push({ code: e.code });
            }
            state.catalogue.curated[targetKey] = cur;
            setDirty();
            renderPicker();
            renderChips();
        });
        grid.appendChild(cell);
        shown++;
    }
    body.appendChild(grid);
    document.getElementById('picker-count').textContent = shown + ' shown';
}

// ---- Save / Reset -------------------------------------------------------

async function applyCatalogue() {
    const btn = document.getElementById('apply');
    btn.disabled = true;
    const r = await fetch('/api/apply', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify(state.catalogue),
    });
    btn.disabled = false;
    const result = document.getElementById('apply-result');
    if (r.ok) {
        const j = await r.json();
        result.textContent = 'Wrote ' + j.path + ' (' + j.bytes + ' bytes)';
        result.style.color = '#16a34a';
        setClean('Saved to disk');
    } else {
        const text = await r.text();
        result.textContent = 'Apply failed: ' + text;
        result.style.color = '#dc2626';
    }
}

async function resetChanges() {
    if (state.dirty && !confirm('Discard unsaved changes?')) return;
    await fetch('/api/reset', { method: 'POST' });
    location.reload();
}

// ---- Top-level -----------------------------------------------------------

function renderAll() {
    if (HIDDEN_CHIPS.has(state.activeChip)) state.activeChip = 'all';
    renderChips();
    renderDetail();
}

async function init() {
    const r = await fetch('/api/data');
    const d = await r.json();
    state.catalogue = {
        chips: d.chips,
        curated: d.curated,
        patterns: d.patterns,
        excludes: d.excludes,
    };
    state.cmap = d.cmap;
    state.cmapByCode = Object.fromEntries(d.cmap.map(e => [e.code, e]));
    setClean('Loaded ' + d.cmap.length + ' icons, ' + d.chips.length + ' chips');
    renderAll();
}

document.getElementById('apply').addEventListener('click', applyCatalogue);
document.getElementById('reset').addEventListener('click', resetChanges);
document.getElementById('picker-search').addEventListener('input', (e) => {
    state.pickerSearch = e.target.value;
    renderPicker();
});
document.getElementById('picker-close').addEventListener('click', closePicker);
document.getElementById('picker-done').addEventListener('click', closePicker);
document.getElementById('picker-modal').addEventListener('click', (e) => {
    if (e.target.id === 'picker-modal') closePicker();
});

init();
</script>
</body>
</html>
"""


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        # Quiet successful requests.
        if args and isinstance(args[1], str) and args[1].startswith('2'):
            return
        sys.stderr.write("%s - - [%s] %s\n" % (
            self.address_string(), self.log_date_time_string(), fmt % args))

    def _send(self, status, body, ctype='text/html; charset=utf-8'):
        if isinstance(body, str):
            body = body.encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_json(self, status, obj):
        self._send(status, json.dumps(obj), 'application/json; charset=utf-8')

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path in ('/', '/index.html'):
            self._send(200, INDEX_HTML)
            return
        if path == '/api/data':
            try:
                data = load_catalogue()
                self._send_json(200, data)
            except Exception as e:
                self._send(500, 'Failed to load catalogue: ' + str(e), 'text/plain')
            return
        if path == '/api/font':
            if not SYMBOLS_TTF.exists():
                self._send(404, 'Nerd Font not found at ' + str(SYMBOLS_TTF), 'text/plain')
                return
            data = SYMBOLS_TTF.read_bytes()
            self.send_response(200)
            self.send_header('Content-Type', 'font/ttf')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        self._send(404, 'Not found', 'text/plain')

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length).decode('utf-8') if length else ''
        if path == '/api/save':
            try:
                SCRATCH_PATH.write_text(body)
                self._send_json(200, {'ok': True})
            except Exception as e:
                self._send(500, str(e), 'text/plain')
            return
        if path == '/api/apply':
            try:
                catalogue = json.loads(body)
                cmap = load_catalogue()['cmap']
                source = render_lua(catalogue, cmap)
                CATALOGUE_PATH.write_text(source)
                # Roundtrip: re-parse via lua to confirm syntactic validity.
                load_catalogue()
                self._send_json(200, {
                    'ok': True,
                    'path': str(CATALOGUE_PATH.relative_to(REPO_ROOT)),
                    'bytes': len(source.encode('utf-8')),
                })
            except Exception as e:
                self._send(500, 'Apply failed: ' + str(e), 'text/plain')
            return
        if path == '/api/reset':
            if SCRATCH_PATH.exists():
                SCRATCH_PATH.unlink()
            self._send_json(200, {'ok': True})
            return
        self._send(404, 'Not found', 'text/plain')


def find_free_port(preferred):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        try:
            s.bind(('127.0.0.1', preferred))
            return preferred
        except OSError:
            s.bind(('127.0.0.1', 0))
            return s.getsockname()[1]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--port', type=int, default=8765)
    ap.add_argument('--no-browser', action='store_true')
    args = ap.parse_args()

    if not CATALOGUE_PATH.exists():
        sys.exit('Catalogue not found: ' + str(CATALOGUE_PATH))
    if not SYMBOLS_TTF.exists():
        sys.stderr.write('WARNING: ' + str(SYMBOLS_TTF) + ' not found; '
                         'icons will render as fallback boxes\n')
    try:
        load_catalogue()
    except subprocess.CalledProcessError as e:
        sys.exit('Could not parse catalogue via lua:\n' + (e.stderr or ''))
    except FileNotFoundError:
        sys.exit('lua interpreter not found in PATH')

    port = find_free_port(args.port)
    url = 'http://127.0.0.1:{}/'.format(port)
    httpd = socketserver.ThreadingTCPServer(('127.0.0.1', port), Handler)
    httpd.daemon_threads = True
    print('Curator running at', url)
    print('Catalogue file:', CATALOGUE_PATH)
    print('Press Ctrl+C to stop.')

    if not args.no_browser:
        threading.Timer(0.4, lambda: webbrowser.open(url)).start()

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print()


if __name__ == '__main__':
    main()
