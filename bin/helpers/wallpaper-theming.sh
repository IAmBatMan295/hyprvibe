#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Title: Wallpaper Theming
# Description: Interactive wallpaper color recoloring using lutgen and Hyprland
# ==============================================================================

HELPER_TITLE="Wallpaper Theming"
HELPER_ICON=""
HELPER_ORDER=10

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
THEMES_DIR="${ROOT_DIR}/themes"
USER_THEMES_DIR="${HOME}/.config/hyprvibe/themes"

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
        PALETTE_COLORS+=("${hex_colors[*]}")
    done
done

apply_lutgen() {
    local slug="$1"
    local idx="$2"
    local infile="$3"
    local outfile="$4"

    # Optimal wallpaper parameters:
    # -R: Gaussian RBF interpolation (eliminates color banding and artifacts)
    # -s=192: Shape parameter (sharper detail, prevents smudging)
    # -n=12: Nearest colors to consider (prevents accidental accent color bleed)
    # -P: Preserve luminosity (guarantees inky blacks without foggy wash)
    # -c: Cache generated Hald CLUT (speeds up batch wallpaper processing)
    local lut_opts=(-R -s=192 -n=12 -P -c)

    # Monochrome uses built-in pure grayscale-dark (no color hues)
    if [[ "$slug" == "grayscale-dark" || "$slug" == "grayscale-light" || "$slug" == "monochrome" ]]; then
        lutgen apply -p "grayscale-dark" "${lut_opts[@]}" "$infile" -o "$outfile"
        return $?
    fi

    # Check if slug is recognized by lutgen built-in palettes
    if [[ -n "${LUTGEN_BUILTINS[$slug]:-}" ]]; then
        lutgen apply -p "$slug" "${lut_opts[@]}" "$infile" -o "$outfile"
    else
        # Pass dynamic custom colors from colors.toml for custom colored themes
        read -r -a custom_cols <<< "${PALETTE_COLORS[$idx]:-}"
        if (( ${#custom_cols[@]} > 0 )); then
            lutgen apply "${lut_opts[@]}" "$infile" -o "$outfile" -- "${custom_cols[@]}"
        else
            lutgen apply -p "grayscale-dark" "${lut_opts[@]}" "$infile" -o "$outfile"
        fi
    fi
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
    shift
    HEADLESS_PALETTE_INDEX=""
    HEADLESS_FILES=()
    HEADLESS_OUT_DIR=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --palette)
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
                HEADLESS_OUT_DIR="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    IDX=0
    if [[ "$HEADLESS_PALETTE_INDEX" =~ ^[0-9]+$ ]]; then
        IDX=$((HEADLESS_PALETTE_INDEX - 1))
    else
        for i in "${!PALETTE_SLUGS[@]}"; do
            if [[ "${PALETTE_SLUGS[$i]}" == "$HEADLESS_PALETTE_INDEX" || "${PALETTES[$i]%%|*}" == "$HEADLESS_PALETTE_INDEX" ]]; then
                IDX=$i
                break
            fi
        done
    fi

    PALETTE_DATA="${PALETTES[$IDX]}"
    PALETTE_SLUG="${PALETTE_DATA%%|*}"
    PALETTE_NAME="${PALETTE_DATA##*|}"

    MAX_JOBS=$(nproc 2>/dev/null || echo 4)
    STATUS_FILE=$(mktemp /tmp/theming_status.XXXXXX)
    running=0

    for f in "${HEADLESS_FILES[@]}"; do
        if [[ -f "$f" ]]; then
            target_path=$(get_safe_target_path "$HEADLESS_OUT_DIR" "$f" "$PALETTE_SLUG")
            touch "$target_path"
            (
                if apply_lutgen "$PALETTE_SLUG" "$IDX" "$f" "$target_path" >/dev/null 2>&1; then
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

    COUNT=$(grep -c "^0$" "$STATUS_FILE" 2>/dev/null || echo 0)
    rm -f "$STATUS_FILE"

    command -v notify-send >/dev/null 2>&1 && notify-send -a "${HELPER_TITLE}" "${HELPER_TITLE}" "Successfully themed $COUNT wallpaper(s) ($PALETTE_NAME)" || true
    exit 0
fi

# ------------------------------------------------------------------------------
# Floating Window Spawn Logic
# ------------------------------------------------------------------------------
# If not already running inside our dedicated floating window, calculate active
# screen resolution (40% width x 40% height) and launch foot via hyprctl eval (hl. API)
if [[ "${1:-}" != "--inner" ]]; then
    SCRIPT_FILE=$(readlink -f "$0")

    # Fetch active/focused monitor resolution dynamically
    MON_INFO=$(hyprctl monitors -j 2>/dev/null || true)
    WIDTH=$(echo "$MON_INFO" | jq -r '.[] | select(.focused == true) | .width // empty' 2>/dev/null || true)
    if [[ -z "$WIDTH" ]]; then
        WIDTH=$(echo "$MON_INFO" | jq -r '.[0].width // 1920' 2>/dev/null || true)
        HEIGHT=$(echo "$MON_INFO" | jq -r '.[0].height // 1080' 2>/dev/null || true)
        SCALE=$(echo "$MON_INFO" | jq -r '.[0].scale // 1.0' 2>/dev/null || true)
    else
        HEIGHT=$(echo "$MON_INFO" | jq -r '.[] | select(.focused == true) | .height // 1080' 2>/dev/null || true)
        SCALE=$(echo "$MON_INFO" | jq -r '.[] | select(.focused == true) | .scale // 1.0' 2>/dev/null || true)
    fi

    # Dynamic 40% scaling (accounting for display scale)
    TARGET_W=$(awk -v w="$WIDTH" -v s="$SCALE" 'BEGIN { printf "%d", (w / s) * 0.40 }')
    TARGET_H=$(awk -v h="$HEIGHT" -v s="$SCALE" 'BEGIN { printf "%d", (h / s) * 0.40 }')
    [[ "$TARGET_W" -lt 600 ]] && TARGET_W=600
    [[ "$TARGET_H" -lt 380 ]] && TARGET_H=380

    # Register rule and launch foot via Hyprland Lua eval API
    if command -v hyprctl >/dev/null 2>&1 && pgrep -x Hyprland >/dev/null 2>&1; then
        hyprctl eval "hl.window_rule({ match = { class = 'wallpaper-theming' }, float = true, center = true, size = '${TARGET_W} ${TARGET_H}' })" >/dev/null 2>&1 || true
        hyprctl eval "hl.exec_cmd('foot -a wallpaper-theming -T \"${HELPER_TITLE}\" -w ${TARGET_W}x${TARGET_H} bash \"${SCRIPT_FILE}\" --inner')" >/dev/null 2>&1 || true
        exit 0
    fi
fi

# ------------------------------------------------------------------------------
# Title Display (Clean left-aligned text, no wrapping)
# ------------------------------------------------------------------------------
print_title() {
    echo ""
    echo "  ${HELPER_ICON}  ${HELPER_TITLE}"
    echo ""
}

# ------------------------------------------------------------------------------
# Interactive Menu
# ------------------------------------------------------------------------------
clear 2>/dev/null || true
print_title
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
    echo "Exiting."
    exit 0
fi

if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#PALETTES[@]} )); then
    echo "Invalid choice. Exiting."
    exit 1
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
RAW_FILES=$(zenity --file-selection --multiple --separator="|" \
    --title="Wallpaper Theming - Select Wallpapers" \
    --file-filter="Images (*.png, *.jpg, *.jpeg, *.webp, *.avif) | *.png *.jpg *.jpeg *.webp *.avif *.PNG *.JPG *.JPEG *.WEBP *.AVIF" \
    2>/dev/null || true)

if [[ -z "$RAW_FILES" ]]; then
    echo "No files selected. Cancelled."
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
    --filename="$HOME/Pictures/Current-Wallpapers/" \
    2>/dev/null || true)

if [[ -z "$DEST_DIR" ]]; then
    echo "No destination directory selected. Cancelled."
    exit 0
fi

mkdir -p "$DEST_DIR"

# ------------------------------------------------------------------------------
# Process with lutgen (Zenity GUI progress bar, parallel workers)
# ------------------------------------------------------------------------------
TOTAL_FILES=${#INPUT_FILES[@]}
MAX_JOBS=$(nproc 2>/dev/null || echo 4)
STATUS_FILE=$(mktemp /tmp/theming_status.XXXXXX)

clear 2>/dev/null || true
print_title
echo "  Theming $TOTAL_FILES wallpaper(s) with $SELECTED_NAME in parallel ($MAX_JOBS workers)..."
echo "  Follow progress in the dialog window."
echo ""

(
    running=0
    completed=0
    for img in "${INPUT_FILES[@]}"; do
        if [[ ! -f "$img" ]]; then
            continue
        fi

        target_file=$(get_safe_target_path "$DEST_DIR" "$img" "$SELECTED_PALETTE")
        touch "$target_file"
        (
            if apply_lutgen "$SELECTED_PALETTE" "$SELECTED_IDX" "$img" "$target_file" >/dev/null 2>&1; then
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

SUCCESS_COUNT=$(grep -c "^0$" "$STATUS_FILE" 2>/dev/null || echo 0)
rm -f "$STATUS_FILE"

# Notify via notification daemon (Mako)
notify-send -a "${HELPER_TITLE}" "${HELPER_TITLE}" "Successfully themed $SUCCESS_COUNT wallpaper(s) with $SELECTED_NAME" 2>/dev/null || true
exit 0
