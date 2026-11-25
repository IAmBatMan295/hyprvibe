#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Title: Rename Theme Wallpapers
# Description: Helper script to standardize theme wallpapers to <theme>-<index>.<ext>
# ==============================================================================

HELPER_TITLE="Rename Theme Wallpapers"
HELPER_ICON=""
HELPER_ORDER=30

REAL_SCRIPT="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd -- "$(dirname -- "${REAL_SCRIPT}")/../.." && pwd)"
# shellcheck source=../lib/helper-ui.sh
source "${ROOT_DIR}/bin/lib/helper-ui.sh"

helper_maybe_spawn_window "$0" 0.40 0.40 600 380 "--inner --headless" "$@"

THEMES_DIR="${THEMES_DIR:-${ROOT_DIR}/themes}"

# Non-interactive / headless & optional args check
AUTO_YES=false
while (( $# > 0 )); do
    case "$1" in
        --yes|-y|--headless)
            AUTO_YES=true
            HELPER_HEADLESS=true
            shift
            ;;
        --themes-dir)
            [[ $# -ge 2 ]] || helper_fail "Missing directory path after --themes-dir"
            THEMES_DIR="$2"
            shift 2
            ;;
        --inner)
            shift
            ;;
        *)
            shift
            ;;
    esac
done

clear 2>/dev/null || true
helper_print_title
helper_enable_error_pause

if [[ ! -d "$THEMES_DIR" ]]; then
    helper_fail "themes directory not found at $THEMES_DIR"
fi

if [[ "$AUTO_YES" != "true" ]]; then
    echo "  Standardize theme wallpapers to <theme>-<index>.<ext>?"
    echo ""
    read -rp "  Proceed? [Y/n]: " response
    response="${response:-Y}"
    if [[ "$response" =~ ^[qQ]$ ]] || [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo ""
        echo "  Aborted."
        helper_wait_for_q "  Press 'q' to close..."
        exit 0
    fi
    echo ""
fi

echo "  Validating theme backgrounds before renaming..."
echo ""

if ! python3 - "$THEMES_DIR" << 'EOF'
import os
import sys

themes_dir = sys.argv[1]
if not os.path.isdir(themes_dir):
    sys.exit(f"  Directory not found: {themes_dir}")

VALID_EXTS = {".jpg", ".jpeg", ".png", ".webp"}
invalid_entries = []
theme_batches = []

for theme in sorted(os.listdir(themes_dir)):
    bg_dir = os.path.join(themes_dir, theme, "backgrounds")
    if not os.path.isdir(bg_dir):
        continue

    files = []
    for entry in sorted(os.listdir(bg_dir)):
        if entry.startswith("."):
            continue
        full_path = os.path.join(bg_dir, entry)
        if not os.path.isfile(full_path):
            invalid_entries.append(full_path)
            continue
        ext = os.path.splitext(entry)[1].lower()
        if ext not in VALID_EXTS:
            invalid_entries.append(full_path)
            continue
        files.append(entry)

    if files:
        theme_batches.append((theme, bg_dir, files))

if invalid_entries:
    print("  Non-image file(s) detected in theme backgrounds:", file=sys.stderr)
    for bad in invalid_entries:
        print(f"    - {bad}", file=sys.stderr)
    print("  Aborting before renaming any files.", file=sys.stderr)
    sys.exit(1)

total = 0
for theme, bg_dir, files in theme_batches:
    print(f"  [{theme}] Renaming {len(files)} wallpaper(s)...")

    # Phase 1: Temporary names to prevent collision
    temp_files = []
    for i, fname in enumerate(files, 1):
        ext = os.path.splitext(fname)[1]
        temp_name = f"__tmp_renaming_{theme}_{i}{ext}"
        src = os.path.join(bg_dir, fname)
        dst = os.path.join(bg_dir, temp_name)
        os.rename(src, dst)
        temp_files.append((dst, ext))

    # Phase 2: Standardized names
    for i, (temp_path, ext) in enumerate(temp_files, 1):
        final_name = f"{theme}-{i}{ext}"
        final_path = os.path.join(bg_dir, final_name)
        os.rename(temp_path, final_path)
        total += 1

print(f"\n  ✅ All {total} theme wallpapers standardized successfully.")
EOF
then
    helper_fail "Non-image file(s) found in theme backgrounds; nothing was renamed."
fi

helper_notify normal "Successfully standardized theme wallpapers"
helper_wait_for_q "  Press 'q' to close..."
