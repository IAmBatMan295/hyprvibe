#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Title: Battery Conservation
# Description: Helper script to toggle laptop battery conservation charging cap
# ==============================================================================

HELPER_TITLE="Battery Conservation"
HELPER_ICON="󰂄"
HELPER_ORDER=25

REAL_SCRIPT="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd -- "$(dirname -- "${REAL_SCRIPT}")/../.." && pwd)"
# shellcheck source=../lib/helper-ui.sh
source "${ROOT_DIR}/bin/lib/helper-ui.sh"

helper_maybe_spawn_window "$0" 0.40 0.40 600 380 "--inner --headless --status --set -s" "$@"

# ------------------------------------------------------------------------------
# Multi-Vendor Hardware Discovery (Lenovo IdeaPad OR Generic Kernel Threshold)
# ------------------------------------------------------------------------------
SYSFS_POWER_SUPPLY_DIR="${SYSFS_POWER_SUPPLY_DIR:-/sys/class/power_supply}"
SYSFS_PLATFORM_DIR="${SYSFS_PLATFORM_DIR:-/sys/devices}"
CONSERVATION_LIMIT="${CONSERVATION_LIMIT:-80}"

CONSERVATION_BACKEND=""
CONSERVATION_PATH=""
START_THRESHOLD_PATH=""

discover_conservation_backend() {
    local candidate ps ps_scope

    # 1. Lenovo IdeaPad ACPI conservation_mode
    if [[ "$SYSFS_PLATFORM_DIR" == "/sys/devices" ]]; then
        for candidate in \
            "/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode" \
            "/sys/devices/platform/ideapad_acpi/VPC2004:00/conservation_mode"; do
            if [[ -f "$candidate" ]]; then
                CONSERVATION_BACKEND="ideapad"
                CONSERVATION_PATH="$candidate"
                return 0
            fi
        done
    fi

    if [[ -d "$SYSFS_PLATFORM_DIR" ]]; then
        candidate="$(find "$SYSFS_PLATFORM_DIR" -maxdepth 5 -name "conservation_mode" 2>/dev/null | head -n 1 || true)"
        if [[ -n "$candidate" && -f "$candidate" ]]; then
            CONSERVATION_BACKEND="ideapad"
            CONSERVATION_PATH="$candidate"
            return 0
        fi
    fi

    # 2. Standard Linux kernel charge_control_end_threshold (ThinkPad, ASUS, Framework, MSI, Dell)
    if [[ -d "$SYSFS_POWER_SUPPLY_DIR" ]]; then
        for ps in "$SYSFS_POWER_SUPPLY_DIR"/*; do
            [[ -d "$ps" && -f "$ps/charge_control_end_threshold" ]] || continue
            if [[ -f "$ps/scope" ]]; then
                ps_scope="$(< "$ps/scope")"
                ps_scope="${ps_scope//[[:space:]]/}"
                [[ "$ps_scope" == "Device" ]] && continue
            fi
            CONSERVATION_BACKEND="threshold"
            CONSERVATION_PATH="$ps/charge_control_end_threshold"
            if [[ -f "$ps/charge_control_start_threshold" ]]; then
                START_THRESHOLD_PATH="$ps/charge_control_start_threshold"
            fi
            return 0
        done
    fi
    return 1
}

discover_conservation_backend || true

read_conservation_raw() {
    local raw
    raw="$(cat "$CONSERVATION_PATH" 2>/dev/null || true)"
    printf '%s' "${raw//[[:space:]]/}"
}

get_conservation_status() {
    if [[ -z "$CONSERVATION_PATH" || ! -f "$CONSERVATION_PATH" ]]; then
        echo "unsupported"
        return 0
    fi
    local raw
    raw="$(read_conservation_raw)"
    if [[ "$CONSERVATION_BACKEND" == "ideapad" ]]; then
        printf '%s\n' "$raw"
    else
        if [[ "$raw" =~ ^[0-9]+$ ]] && (( raw < 95 )); then
            echo "1"
        else
            echo "0"
        fi
    fi
}

write_sysfs_node() {
    local path="$1" value="$2"
    if [[ -w "$path" ]]; then
        printf '%s\n' "$value" > "$path"
    else
        printf '%s\n' "$value" | sudo tee "$path" >/dev/null
    fi
}

set_conservation_state() {
    local enable="$1"
    if [[ -z "$CONSERVATION_PATH" || ! -f "$CONSERVATION_PATH" ]]; then
        return 1
    fi

    if [[ "$CONSERVATION_BACKEND" == "ideapad" ]]; then
        write_sysfs_node "$CONSERVATION_PATH" "$enable"
        return $?
    fi

    if [[ "$enable" == "1" ]]; then
        if [[ -n "$START_THRESHOLD_PATH" && -f "$START_THRESHOLD_PATH" ]]; then
            local cur_start
            cur_start="$(cat "$START_THRESHOLD_PATH" 2>/dev/null || true)"
            cur_start="${cur_start//[[:space:]]/}"
            if [[ "$cur_start" =~ ^[0-9]+$ ]] && (( cur_start >= CONSERVATION_LIMIT )); then
                local new_start=$(( CONSERVATION_LIMIT > 5 ? CONSERVATION_LIMIT - 5 : 0 ))
                write_sysfs_node "$START_THRESHOLD_PATH" "$new_start" || return 1
            fi
        fi
        write_sysfs_node "$CONSERVATION_PATH" "$CONSERVATION_LIMIT"
    else
        write_sysfs_node "$CONSERVATION_PATH" "100"
    fi
}

# ------------------------------------------------------------------------------
# Headless / CLI Support
# ------------------------------------------------------------------------------
for ((i=1; i<=$#; i++)); do
    arg="${!i}"
    case "$arg" in
        --headless)
            HELPER_HEADLESS=true
            ;;
        --status)
            get_conservation_status
            exit 0
            ;;
        --set|-s)
            HELPER_HEADLESS=true
            next_idx=$((i+1))
            val="${!next_idx:-}"
            if [[ "$val" != "0" && "$val" != "1" ]]; then
                echo "Error: $arg requires 0 or 1" >&2
                exit 1
            fi
            if [[ -z "$CONSERVATION_PATH" || ! -f "$CONSERVATION_PATH" ]]; then
                echo "Error: Battery conservation unsupported on this hardware" >&2
                exit 1
            fi
            set_conservation_state "$val"
            exit $?
            ;;
    esac
done

# ------------------------------------------------------------------------------
# Interactive UI
# ------------------------------------------------------------------------------
clear 2>/dev/null || true
helper_print_title
helper_enable_error_pause

if [[ -z "$CONSERVATION_PATH" || ! -f "$CONSERVATION_PATH" ]]; then
    helper_fail "Conservation Mode / charge threshold not supported or kernel driver not loaded."
fi

current_raw="$(read_conservation_raw)"
status_flag="$(get_conservation_status)"

if [[ "$CONSERVATION_BACKEND" == "ideapad" ]]; then
    limit_pct=60
    backend_label="Lenovo IdeaPad ACPI"
else
    limit_pct="$CONSERVATION_LIMIT"
    backend_label="Kernel power_supply ($(basename "$(dirname "$CONSERVATION_PATH")"))"
fi

echo "  Hardware: ${backend_label}"
echo "  Status:"
if [[ "$status_flag" == "1" ]]; then
    cur_display="$current_raw"
    [[ "$CONSERVATION_BACKEND" == "ideapad" ]] && cur_display="60%" || cur_display="${current_raw}%"
    echo "    • Current:  󰂄 Conservation Mode (Active - ${cur_display} cap)"
    echo "    • Limit:    Charging capped at ${cur_display} (protects battery life)"
elif [[ "$status_flag" == "0" ]]; then
    echo "    • Current:  ⚡ Normal Mode (Active)"
    echo "    • Limit:    Full 100% charge (maximum portable runtime)"
else
    echo "    • Current:  ❓ Unknown State ('$current_raw')"
fi

echo ""
echo "  Options:"
echo "    [1]  󰂄  Enable Conservation Mode (${limit_pct}% cap)"
echo "    [2]  ⚡  Enable Normal Mode (100% full charge)"
echo "    [q]  Exit"
echo ""

read -rp "  Select an option [1/2/q]: " choice

case "$choice" in
    1)
        if set_conservation_state 1 2>/dev/null; then
            echo ""
            echo "  ✅ Switched to Conservation Mode (${limit_pct}% cap)"
            helper_notify normal "Switched to Conservation Mode (${limit_pct}% cap)"
            helper_wait_for_q "  Press 'q' to close..."
        else
            helper_fail "Failed to write conservation threshold (permission denied or sudo failed)"
        fi
        ;;
    2)
        if set_conservation_state 0 2>/dev/null; then
            echo ""
            echo "  ✅ Switched to Normal Mode (100% charge)"
            helper_notify normal "Switched to Normal Mode (100% charge)"
            helper_wait_for_q "  Press 'q' to close..."
        else
            helper_fail "Failed to write conservation threshold (permission denied or sudo failed)"
        fi
        ;;
    [qQ]|"")
        echo ""
        echo "  Exiting without changes."
        exit 0
        ;;
    *)
        helper_fail "Invalid choice."
        ;;
esac
