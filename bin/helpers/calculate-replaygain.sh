#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Title: Calculate ReplayGain
# Description: Helper script to calculate and apply ReplayGain tags via rsgain
# ==============================================================================

HELPER_TITLE="Calculate ReplayGain"
HELPER_ICON="󰎈"
HELPER_ORDER=40

REAL_SCRIPT="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd -- "$(dirname -- "${REAL_SCRIPT}")/../.." && pwd)"
# shellcheck source=../lib/helper-ui.sh
source "${ROOT_DIR}/bin/lib/helper-ui.sh"

helper_maybe_spawn_window "$0" 0.40 0.40 600 380 "--inner --headless --dry-run" "$@"

DEFAULT_DIR="${HOME}/Music/music"
[[ ! -d "$DEFAULT_DIR" ]] && DEFAULT_DIR="${HOME}/Music"
[[ ! -d "$DEFAULT_DIR" ]] && DEFAULT_DIR="${HOME}"

# ------------------------------------------------------------------------------
# Argument Parsing
# ------------------------------------------------------------------------------
HEADLESS=false
DRY_RUN=false
PRESET_SKIP=""
TARGET_DIR=""

for arg in "$@"; do
    case "$arg" in
        --headless)
            HEADLESS=true
            HELPER_HEADLESS=true
            ;;
        --dry-run) DRY_RUN=true ;;
        --skip) PRESET_SKIP="y" ;;
        --no-skip) PRESET_SKIP="n" ;;
        --dir=*) TARGET_DIR="${arg#*=}" ;;
        --inner) ;;
        *)
            if [[ -z "$TARGET_DIR" ]]; then
                TARGET_DIR="$arg"
            fi
            ;;
    esac
done

# ------------------------------------------------------------------------------
# Dependency Verification
# ------------------------------------------------------------------------------
if ! command -v rsgain >/dev/null 2>&1; then
    if [[ "$HEADLESS" != "true" ]]; then
        clear 2>/dev/null || true
        helper_print_title
    fi
    helper_fail "'rsgain' is not installed or not in PATH."
fi

# ------------------------------------------------------------------------------
# Non-Interactive / Headless / Dry-Run Mode
# ------------------------------------------------------------------------------
if [[ "$HEADLESS" == "true" ]]; then
    if [[ -z "$TARGET_DIR" ]]; then
        TARGET_DIR="$DEFAULT_DIR"
    fi
    TARGET_DIR="${TARGET_DIR/#\~/$HOME}"
    if [[ ! -d "$TARGET_DIR" ]]; then
        helper_fail "Directory not found: $TARGET_DIR"
    fi

    SKIP_ARGS=()
    if [[ "$PRESET_SKIP" == "y" || -z "$PRESET_SKIP" ]]; then
        SKIP_ARGS=("-S")
    fi

    CMD=(rsgain easy -m MAX -p no_album "${SKIP_ARGS[@]}" "$TARGET_DIR")
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "${CMD[*]}"
        exit 0
    fi

    if ! "${CMD[@]}"; then
        helper_fail "rsgain exited with an error."
    fi
    helper_notify normal "ReplayGain tags applied to $(basename "$TARGET_DIR")"
    exit 0
fi

# ------------------------------------------------------------------------------
# Interactive Execution
# ------------------------------------------------------------------------------
clear 2>/dev/null || true
helper_print_title
helper_enable_error_pause

echo "  Skip files with existing ReplayGain metadata?"
echo ""
read -r -p "  Proceed? [Y/n]: " choice

if [[ "$choice" =~ ^[qQ]$ ]]; then
    echo ""
    echo "  Exiting."
    helper_wait_for_q "  Press 'q' to close..."
    exit 0
fi

SKIP_ARGS=()
SKIP_DESC="Re-calculating all files"
case "${choice,,}" in
    n|no)
        SKIP_ARGS=()
        SKIP_DESC="Re-calculating all files"
        ;;
    *)
        SKIP_ARGS=("-S")
        SKIP_DESC="Skipping files with existing metadata (-S)"
        ;;
esac

# Directory selection via Zenity if not passed via CLI
if [[ -z "$TARGET_DIR" ]]; then
    echo ""
    echo "  Opening directory picker for music folder..."
    if command -v zenity >/dev/null 2>&1; then
        TARGET_DIR=$(zenity --file-selection --directory \
            --title="${HELPER_TITLE} - Select Music Directory" \
            --filename="${DEFAULT_DIR}/" \
            2>/dev/null || true)
    fi

    if [[ -z "$TARGET_DIR" ]]; then
        if command -v zenity >/dev/null 2>&1; then
            echo ""
            echo "  No directory selected. Cancelled."
            helper_wait_for_q "  Press 'q' to close..."
            exit 0
        else
            echo ""
            read -r -e -p "  Enter music directory [default: ${DEFAULT_DIR}]: " manual_dir
            TARGET_DIR="${manual_dir:-$DEFAULT_DIR}"
        fi
    fi
fi

TARGET_DIR="${TARGET_DIR/#\~/$HOME}"
if [[ ! -d "$TARGET_DIR" ]]; then
    helper_fail "Directory not found: $TARGET_DIR"
fi

echo ""
echo "  Target: $TARGET_DIR"
echo "  Mode:   $SKIP_DESC"
echo ""
echo "  Running rsgain..."
echo ""

if ! rsgain easy -m MAX -p no_album "${SKIP_ARGS[@]}" "$TARGET_DIR"; then
    helper_fail "rsgain failed while processing $TARGET_DIR"
fi

helper_notify normal "ReplayGain tags applied to $(basename "$TARGET_DIR")"

echo ""
echo "  ✅ ReplayGain tags processed successfully."
helper_wait_for_q "  Press 'q' to close..."
