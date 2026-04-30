#!/usr/bin/env bash
# Build the release zip for the version currently in _meta.lua.
# Usage: tools/build-release.sh [output_dir]
# Output: <output_dir>/bookends.koplugin-v<version>.zip (default /tmp/bookends-release)
#
# Excludes anything not needed by KOReader at runtime: dev workspace
# (.claude/), repo chrome (README.md, .gitignore, .github/), README assets
# (assets/), translation source templates (*.pot — only .po files are loaded),
# tests/, tools/, docs/, screenshots/.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
out_dir="${1:-/tmp/bookends-release}"

version="$(awk -F'"' '/^[[:space:]]*version[[:space:]]*=/{print $2; exit}' "$repo_root/_meta.lua")"
test -n "$version" || { echo "ERROR: could not parse version from _meta.lua" >&2; exit 1; }

stage_dir="$out_dir/stage"
zip_path="$out_dir/bookends.koplugin-v${version}.zip"

rm -rf "$stage_dir" "$zip_path"
mkdir -p "$stage_dir"

rsync -a \
    --exclude='.git/' \
    --exclude='.claude/' \
    --exclude='.gitignore' \
    --exclude='.github/' \
    --exclude='docs/' \
    --exclude='screenshots/' \
    --exclude='tests/' \
    --exclude='tools/' \
    --exclude='assets/' \
    --exclude='README.md' \
    --exclude='_test_*.lua' \
    --exclude='*.pot' \
    --exclude='*.swp' --exclude='*.swo' --exclude='*~' --exclude='.DS_Store' \
    "$repo_root/" "$stage_dir/bookends.koplugin/"

(cd "$stage_dir" && zip -rq "$zip_path" bookends.koplugin)

echo "Built: $zip_path"
unzip -l "$zip_path" | tail -1
echo
echo "First-time release for v${version}:"
echo "  gh -R AndyHazz/bookends.koplugin release create v${version} \"$zip_path\" --title \"v${version}\" --notes \"...\""
echo
echo "Re-upload to existing v${version} release (replaces asset, keeps publish state):"
echo "  gh -R AndyHazz/bookends.koplugin release upload v${version} \"$zip_path\" --clobber"
