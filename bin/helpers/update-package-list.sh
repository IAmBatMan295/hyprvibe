#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Title: Update Package List
# Description: Helper script to snapshot pacman and yay installed packages
# ==============================================================================

HELPER_TITLE="Update Package List"
HELPER_ICON=""
HELPER_ORDER=20

REAL_SCRIPT="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd -- "$(dirname -- "${REAL_SCRIPT}")/../.." && pwd)"
# shellcheck source=../lib/helper-ui.sh
source "${ROOT_DIR}/bin/lib/helper-ui.sh"

helper_maybe_spawn_window "$0" 0.40 0.40 600 380 "--inner --headless" "$@"

PACKAGES_DIR="${PACKAGES_DIR:-${ROOT_DIR}/packages}"
PACMAN_TXT="${PACKAGES_DIR}/pacman.txt"
YAY_TXT="${PACKAGES_DIR}/yay.txt"

AUTO_YES=false
for arg in "$@"; do
    if [[ "$arg" == "--yes" || "$arg" == "-y" || "$arg" == "--headless" ]]; then
        AUTO_YES=true
        HELPER_HEADLESS=true
    fi
done

clear 2>/dev/null || true
helper_print_title
helper_enable_error_pause

if [[ "$AUTO_YES" != "true" ]]; then
    echo "  Update pacman.txt & yay.txt in hyprvibe packages/?"
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

if ! command -v pacman >/dev/null 2>&1; then
    helper_fail "'pacman' command not found."
fi

echo "  Running pacman queries..."

TMP_PKG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hyprvibe-pkgs.XXXXXX")"
trap 'rm -rf "$TMP_PKG_DIR"' EXIT

if pacman -Qneq > "${TMP_PKG_DIR}/pacman.txt" && pacman -Qmeq > "${TMP_PKG_DIR}/yay.txt"; then
    mkdir -p "$PACKAGES_DIR"
    mv -f "${TMP_PKG_DIR}/pacman.txt" "$PACMAN_TXT"
    mv -f "${TMP_PKG_DIR}/yay.txt" "$YAY_TXT"
    PAC_COUNT=$(wc -l < "$PACMAN_TXT")
    YAY_COUNT=$(wc -l < "$YAY_TXT")
    echo ""
    echo "  ✅ Successfully updated package lists:"
    echo "     - pacman.txt: $PAC_COUNT packages"
    echo "     - yay.txt:    $YAY_COUNT packages"
    helper_notify normal "Successfully updated pacman ($PAC_COUNT) & yay ($YAY_COUNT) lists"
    helper_wait_for_q "  Press 'q' to close..."
else
    helper_fail "Failed to query package lists via pacman."
fi
