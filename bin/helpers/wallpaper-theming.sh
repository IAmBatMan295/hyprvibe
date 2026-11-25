#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Title: Wallpaper Theming
# Description: Interactive wallpaper color recoloring using lutgen and Hyprland
# ==============================================================================

HELPER_TITLE="Wallpaper Theming"
HELPER_ICON=""
HELPER_ORDER=10

REAL_SCRIPT="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd -- "$(dirname -- "${REAL_SCRIPT}")/../.." && pwd)"
# shellcheck source=../lib/helper-ui.sh
source "${ROOT_DIR}/bin/lib/helper-ui.sh"

helper_maybe_spawn_window "$0" 0.40 0.40 600 380 "--inner --headless" "$@"

THEMES_DIR="${THEMES_DIR:-${ROOT_DIR}/themes}"
USER_THEMES_DIR="${USER_THEMES_DIR:-${HOME}/.config/hyprvibe/themes}"
WORK_TMP="$(mktemp -d "${TMPDIR:-/tmp}/hyprvibe-theming.XXXXXX")"
trap 'rm -rf "$WORK_TMP"' EXIT

declare -A BUILTIN_LUTGEN_MAP=(
    ["catppuccin"]="catppuccin-mocha"
    ["everforest"]="everforest-dark-medium"
    ["gruvbox"]="gruvbox-dark"
    ["monochrome"]="grayscale-dark"
)

# Cache lutgen built-in palettes in memory
declare -A LUTGEN_BUILTINS=()
while IFS= read -r pname; do
    [[ -n "$pname" ]] && LUTGEN_BUILTINS["$pname"]=1
done < <(lutgen palette names 2>/dev/null || true)

format_title() {
    local name="$1"
    local spaced="${name//[-_]/ }"
    awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1' <<< "$spaced"
}

# Dynamically discover all themes from repo and user config directories
PALETTES=()
PALETTE_COLORS=()
PALETTE_SLUGS=()
PALETTE_NAMES=()
declare -A SEEN_THEMES=()

for tdir in "$THEMES_DIR" "$USER_THEMES_DIR"; do
    [[ -d "$tdir" ]] || continue
    for tpath in "$tdir"/*; do
        [[ -d "$tpath" && -f "$tpath/colors.toml" ]] || continue
        tname="$(basename "$tpath")"
        [[ -n "${SEEN_THEMES[$tname]:-}" ]] && continue
        SEEN_THEMES["$tname"]=1

        title="$(format_title "$tname")"
        if [[ "$tname" == "catppuccin" ]]; then
            title="Catppuccin Mocha"
        elif [[ "$tname" == "everforest" ]]; then
            title="Everforest Dark"
        elif [[ "$tname" == "gruvbox" ]]; then
            title="Gruvbox Dark"
        elif [[ "$tname" == "monochrome" ]]; then
            title="Monochrome"
        fi

        # Extract unique hex colors from colors.toml
        mapfile -t hex_colors < <(grep -oE '#[0-9a-fA-F]{6}' "$tpath/colors.toml" | sort -u)

        slug="${BUILTIN_LUTGEN_MAP[$tname]:-$tname}"
        PALETTES+=("${slug}|${title}")
        PALETTE_SLUGS+=("$slug")
        PALETTE_NAMES+=("$tname")
        PALETTE_COLORS+=("${hex_colors[*]}")
    done
done

apply_lutgen_atomic() {
    local slug="$1"
    local idx="$2"
    local infile="$3"
    local outfile="$4"
    local worker_id="${5:-0}"

    local base_name="${infile##*/}"
    local ext="${base_name##*.}"
    [[ "$base_name" == "$ext" || -z "$ext" ]] && ext="png"
    local tmp_out="${WORK_TMP}/render_${worker_id}_${RANDOM}.${ext}"

    # Optimal wallpaper parameters:
    # -R: Gaussian RBF interpolation (eliminates color banding and artifacts)
    # -s=192: Shape parameter (sharper detail, prevents smudging)
    # -n=12: Nearest colors to consider (prevents accidental accent color bleed)
    # -P: Preserve luminosity (guarantees inky blacks without foggy wash)
    # -c: Cache generated Hald CLUT (speeds up batch wallpaper processing)
    local lut_opts=(-R -s=192 -n=12 -P -c)
    local rc=1

    if [[ "$slug" == "grayscale-dark" || "$slug" == "grayscale-light" || "$slug" == "monochrome" ]]; then
        lutgen apply -p "grayscale-dark" "${lut_opts[@]}" "$infile" -o "$tmp_out" && rc=0 || rc=$?
    elif [[ -n "${LUTGEN_BUILTINS[$slug]:-}" ]]; then
        lutgen apply -p "$slug" "${lut_opts[@]}" "$infile" -o "$tmp_out" && rc=0 || rc=$?
    else
        read -r -a custom_cols <<< "${PALETTE_COLORS[$idx]:-}"
        if (( ${#custom_cols[@]} > 0 )); then
            lutgen apply "${lut_opts[@]}" "$infile" -o "$tmp_out" -- "${custom_cols[@]}" && rc=0 || rc=$?
        else
            lutgen apply -p "grayscale-dark" "${lut_opts[@]}" "$infile" -o "$tmp_out" && rc=0 || rc=$?
        fi
    fi

    if (( rc == 0 )) && [[ -s "$tmp_out" ]]; then
        mv -f "$tmp_out" "$outfile"
        return 0
    fi
    rm -f "$tmp_out"
    return 1
}

# ------------------------------------------------------------------------------
# Safe Filename Generator (Non-destructive, never overwrites original)
# Automatically adds theme suffix and (copy) / (copy N) if file already exists
# ------------------------------------------------------------------------------
get_safe_target_path() {
    local dest_dir="$1"
    local orig_file="$2"
    local palette="$3"

    local base
    base=$(basename "$orig_file")
    local name="${base%.*}"
    local ext="${base##*.}"

    local target="${dest_dir}/${name}_${palette}.${ext}"
    local count=1

    while [[ -e "$target" ]]; do
        if [[ $count -eq 1 ]]; then
            target="${dest_dir}/${name}_${palette} (copy).${ext}"
        else
            target="${dest_dir}/${name}_${palette} (copy ${count}).${ext}"
        fi
        ((count++)) || true
    done
    printf '%s\n' "$target"
}

# ------------------------------------------------------------------------------
# Headless / Batch processing support (for tests & scripting)
# ------------------------------------------------------------------------------
if [[ "${1:-}" == "--headless" ]]; then
    HELPER_HEADLESS=true
    shift
    HEADLESS_PALETTE_INDEX=""
    HEADLESS_FILES=()
    HEADLESS_OUT_DIR=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --palette)
                [[ $# -ge 2 && "$2" != --* ]] || helper_fail "Missing value for --palette"
                HEADLESS_PALETTE_INDEX="$2"
                shift 2
                ;;
            --files)
                shift
                while [[ $# -gt 0 && "$1" != --* ]]; do
                    HEADLESS_FILES+=("$1")
                    shift
                done
                ;;
            --out-dir)
                [[ $# -ge 2 && "$2" != --* ]] || helper_fail "Missing value for --out-dir"
                HEADLESS_OUT_DIR="$2"
                shift 2
                ;;
            *)
                helper_fail "Unknown option: $1"
                ;;
        esac
    done

    [[ -n "$HEADLESS_PALETTE_INDEX" ]] || helper_fail "--palette is required in --headless mode"
    [[ -n "$HEADLESS_OUT_DIR" ]] || helper_fail "--out-dir is required in --headless mode"
    (( ${#HEADLESS_FILES[@]} > 0 )) || helper_fail "--files requires at least one image path"
    (( ${#PALETTES[@]} > 0 )) || helper_fail "No theme palettes discovered under $THEMES_DIR"

    IDX=-1
    if [[ "$HEADLESS_PALETTE_INDEX" =~ ^[0-9]+$ ]]; then
        if (( HEADLESS_PALETTE_INDEX >= 1 && HEADLESS_PALETTE_INDEX <= ${#PALETTES[@]} )); then
            IDX=$((HEADLESS_PALETTE_INDEX - 1))
        fi
    else
        for i in "${!PALETTES[@]}"; do
            if [[ "${PALETTE_SLUGS[$i]}" == "$HEADLESS_PALETTE_INDEX" || "${PALETTE_NAMES[$i]}" == "$HEADLESS_PALETTE_INDEX" || "${PALETTES[$i]%%|*}" == "$HEADLESS_PALETTE_INDEX" ]]; then
                IDX=$i
                break
            fi
        done
    fi

    if (( IDX < 0 || IDX >= ${#PALETTES[@]} )); then
        helper_fail "Unknown palette '${HEADLESS_PALETTE_INDEX}'"
    fi

    PALETTE_DATA="${PALETTES[$IDX]}"
    PALETTE_SLUG="${PALETTE_DATA%%|*}"
    PALETTE_NAME="${PALETTE_DATA##*|}"

    MAX_JOBS=$(nproc 2>/dev/null || echo 4)
    STATUS_FILE="${WORK_TMP}/status.log"
    : > "$STATUS_FILE"
    mkdir -p "$HEADLESS_OUT_DIR"
    running=0
    job_seq=0

    for f in "${HEADLESS_FILES[@]}"; do
        if [[ -f "$f" ]]; then
            target_path=$(get_safe_target_path "$HEADLESS_OUT_DIR" "$f" "$PALETTE_SLUG")
            ((job_seq++)) || true
            (
                if apply_lutgen_atomic "$PALETTE_SLUG" "$IDX" "$f" "$target_path" "$job_seq" >/dev/null 2>&1; then
                    echo 0 >> "$STATUS_FILE"
                else
                    echo 1 >> "$STATUS_FILE"
                fi
            ) &
            ((running++)) || true

            if (( running >= MAX_JOBS )); then
                wait -n 2>/dev/null || true
                ((running--)) || true
            fi
        fi
    done

    while (( running > 0 )); do
        wait -n 2>/dev/null || true
        ((running--)) || true
    done

    COUNT=$(grep -c "^0$" "$STATUS_FILE" 2>/dev/null || true)
    helper_notify normal "Successfully themed $COUNT wallpaper(s) ($PALETTE_NAME)"
    exit 0
fi

# ------------------------------------------------------------------------------
# Interactive Menu
# ------------------------------------------------------------------------------
clear 2>/dev/null || true
helper_print_title
helper_enable_error_pause

if (( ${#PALETTES[@]} == 0 )); then
    helper_fail "No theme palettes discovered in ${THEMES_DIR}."
fi

echo "  Select Palette:"
for i in "${!PALETTES[@]}"; do
    num=$((i + 1))
    name="${PALETTES[$i]##*|}"
    echo "    $num) $name"
done
echo "    q) Quit"
echo ""

read -rp "  Choice [1-${#PALETTES[@]}]: " choice

if [[ "$choice" =~ ^[qQ]$ ]]; then
    echo "  Exiting."
    exit 0
fi

if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#PALETTES[@]} )); then
    helper_fail "Invalid choice '${choice}'."
fi

SELECTED_IDX=$((choice - 1))
SELECTED_PALETTE="${PALETTES[$SELECTED_IDX]%%|*}"
SELECTED_NAME="${PALETTES[$SELECTED_IDX]##*|}"

echo ""
echo "  Selected: $SELECTED_NAME ($SELECTED_PALETTE)"
echo "  Opening file picker for input wallpapers..."

# ------------------------------------------------------------------------------
# File Picker (Zenity Multi-file)
# ------------------------------------------------------------------------------
if ! command -v zenity >/dev/null 2>&1; then
    helper_fail "'zenity' is required for interactive file selection."
fi
if ! command -v lutgen >/dev/null 2>&1; then
    helper_fail "'lutgen' is not installed or not in PATH."
fi

RAW_FILES=$(zenity --file-selection --multiple --separator="|" \
    --title="Wallpaper Theming - Select Wallpapers" \
    --filename="$HOME/Pictures/" \
    --file-filter="Images (*.png, *.jpg, *.jpeg, *.webp, *.avif) | *.png *.jpg *.jpeg *.webp *.avif *.PNG *.JPG *.JPEG *.WEBP *.AVIF" \
    2>/dev/null || true)

if [[ -z "$RAW_FILES" ]]; then
    echo "  No files selected. Cancelled."
    helper_wait_for_q "  Press 'q' to close..."
    exit 0
fi

IFS="|" read -r -a INPUT_FILES <<< "$RAW_FILES"
echo "  Selected ${#INPUT_FILES[@]} file(s)."
echo ""
echo "  Opening directory picker for destination..."

# ------------------------------------------------------------------------------
# Destination Directory Picker (Zenity Directory)
# ------------------------------------------------------------------------------
DEST_DIR=$(zenity --file-selection --directory \
    --title="Wallpaper Theming - Select Target Directory" \
    --filename="$HOME/Pictures/" \
    2>/dev/null || true)

if [[ -z "$DEST_DIR" ]]; then
    echo "  No destination directory selected. Cancelled."
    helper_wait_for_q "  Press 'q' to close..."
    exit 0
fi

mkdir -p "$DEST_DIR"

# ------------------------------------------------------------------------------
# Process with lutgen (Zenity GUI progress bar, parallel workers)
# ------------------------------------------------------------------------------
TOTAL_FILES=${#INPUT_FILES[@]}
MAX_JOBS=$(nproc 2>/dev/null || echo 4)
STATUS_FILE="${WORK_TMP}/status.log"
: > "$STATUS_FILE"

clear 2>/dev/null || true
helper_print_title
echo "  Theming $TOTAL_FILES wallpaper(s) with $SELECTED_NAME in parallel ($MAX_JOBS workers)..."
echo "  Follow progress in the dialog window."
echo ""

(
    running=0
    completed=0
    job_seq=0
    for img in "${INPUT_FILES[@]}"; do
        if [[ ! -f "$img" ]]; then
            ((completed++)) || true
            continue
        fi

        target_file=$(get_safe_target_path "$DEST_DIR" "$img" "$SELECTED_PALETTE")
        ((job_seq++)) || true
        (
            if apply_lutgen_atomic "$SELECTED_PALETTE" "$SELECTED_IDX" "$img" "$target_file" "$job_seq" >/dev/null 2>&1; then
                echo 0 >> "$STATUS_FILE"
            else
                echo 1 >> "$STATUS_FILE"
            fi
        ) &
        ((running++)) || true

        if (( running >= MAX_JOBS )); then
            wait -n 2>/dev/null || true
            ((running--)) || true
            ((completed++)) || true
            pct=$(( completed * 100 / TOTAL_FILES ))
            echo "$pct"
            echo "# Theming wallpapers ($completed of $TOTAL_FILES)..."
        fi
    done

    while (( running > 0 )); do
        wait -n 2>/dev/null || true
        ((running--)) || true
        ((completed++)) || true
        pct=$(( completed * 100 / TOTAL_FILES ))
        echo "$pct"
        echo "# Theming wallpapers ($completed of $TOTAL_FILES)..."
    done
) | zenity --progress \
    --title="Wallpaper Theming" \
    --text="Theming wallpapers..." \
    --percentage=0 \
    --auto-close \
    --no-cancel 2>/dev/null || true

SUCCESS_COUNT=$(grep -c "^0$" "$STATUS_FILE" 2>/dev/null || true)
FAIL_COUNT=$(grep -c "^1$" "$STATUS_FILE" 2>/dev/null || true)

if (( FAIL_COUNT > 0 )); then
    echo "  ⚠ Completed with ${SUCCESS_COUNT} succeeded and ${FAIL_COUNT} failed."
    helper_notify normal "Themed ${SUCCESS_COUNT} wallpaper(s) (${FAIL_COUNT} failed)"
else
    echo "  ✅ Successfully themed ${SUCCESS_COUNT} wallpaper(s) with ${SELECTED_NAME}."
    helper_notify normal "Successfully themed $SUCCESS_COUNT wallpaper(s) with $SELECTED_NAME"
fi
helper_wait_for_q "  Press 'q' to close..."
