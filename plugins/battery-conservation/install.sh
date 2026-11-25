#!/usr/bin/env bash

set -euE -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
COMMON_LIB="${ROOT_DIR}/bin/lib/common.sh"

if [[ -r "$COMMON_LIB" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_LIB"
fi

PLUGIN_NAME="Battery Conservation Mode"

log_info() {
    printf "[INFO] %s\n" "$1"
}

log_success() {
    printf "[OK] %s\n" "$1"
}

log_warn() {
    printf "[WARN] %s\n" "$1"
}

log_error() {
    printf "[ERROR] %s\n" "$1" >&2
}

echo "==> Installing Plugin: ${PLUGIN_NAME}"

SYSFS_POWER_SUPPLY_DIR="${SYSFS_POWER_SUPPLY_DIR:-/sys/class/power_supply}"
SYSFS_PLATFORM_DIR="${SYSFS_PLATFORM_DIR:-/sys/devices}"
UDEV_RULE_FILE="${UDEV_RULE_FILE:-/etc/udev/rules.d/99-battery-conservation.rules}"
HYPRVIBE_SKIP_SUDO="${HYPRVIBE_SKIP_SUDO:-0}"

# Probe for Lenovo ideapad_acpi conservation_mode OR generic kernel charge_control_end_threshold
found_ideapad=""
if [[ "$SYSFS_PLATFORM_DIR" == "/sys/devices" ]]; then
    for candidate in \
        "/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode" \
        "/sys/devices/platform/ideapad_acpi/VPC2004:00/conservation_mode"; do
        if [[ -f "$candidate" ]]; then
            found_ideapad="$candidate"
            break
        fi
    done
fi
if [[ -z "$found_ideapad" && -d "$SYSFS_PLATFORM_DIR" ]]; then
    found_ideapad="$(find "$SYSFS_PLATFORM_DIR" -maxdepth 5 -name "conservation_mode" 2>/dev/null | head -n 1 || true)"
fi

found_threshold=""
found_start_threshold=""
if [[ -d "$SYSFS_POWER_SUPPLY_DIR" ]]; then
    for ps in "$SYSFS_POWER_SUPPLY_DIR"/*; do
        [[ -d "$ps" && -f "$ps/charge_control_end_threshold" ]] || continue
        if [[ -f "$ps/scope" ]]; then
            ps_scope="$(< "$ps/scope")"
            ps_scope="${ps_scope//[[:space:]]/}"
            [[ "$ps_scope" == "Device" ]] && continue
        fi
        found_threshold="$ps/charge_control_end_threshold"
        [[ -f "$ps/charge_control_start_threshold" ]] && found_start_threshold="$ps/charge_control_start_threshold"
        break
    done
fi

if [[ -n "$found_ideapad" || -n "$found_threshold" ]]; then
    [[ -n "$found_ideapad" ]] && log_success "Detected Lenovo conservation node: ${found_ideapad}"
    [[ -n "$found_threshold" ]] && log_success "Detected power_supply charge limit node: ${found_threshold}"

    rules_content="# HyprVibe passwordless battery charge conservation rules"$'\n'
    if [[ -n "$found_ideapad" ]]; then
        rules_content+='ACTION=="add|change", SUBSYSTEM=="platform", KERNEL=="VPC2004:*", TEST=="conservation_mode", RUN+="/bin/chmod 0666 %S%p/conservation_mode"'$'\n'
    fi
    if [[ -n "$found_threshold" ]]; then
        rules_content+='ACTION=="add|change", SUBSYSTEM=="power_supply", TEST=="charge_control_end_threshold", RUN+="/bin/chmod 0666 %S%p/charge_control_end_threshold"'$'\n'
        rules_content+='ACTION=="add|change", SUBSYSTEM=="power_supply", TEST=="charge_control_start_threshold", RUN+="/bin/chmod 0666 %S%p/charge_control_start_threshold"'$'\n'
    fi

    log_info "Creating udev rule at ${UDEV_RULE_FILE}"
    if [[ "$HYPRVIBE_SKIP_SUDO" == "1" || -w "$(dirname "$UDEV_RULE_FILE")" ]]; then
        mkdir -p "$(dirname "$UDEV_RULE_FILE")"
        printf '%s' "$rules_content" > "$UDEV_RULE_FILE"
    else
        printf '%s' "$rules_content" | sudo tee "$UDEV_RULE_FILE" >/dev/null 2>&1 || true
        [[ -n "$found_ideapad" ]] && sudo chmod 666 "$found_ideapad" 2>/dev/null || true
        [[ -n "$found_threshold" ]] && sudo chmod 666 "$found_threshold" 2>/dev/null || true
        [[ -n "$found_start_threshold" ]] && sudo chmod 666 "$found_start_threshold" 2>/dev/null || true
    fi

    log_success "${PLUGIN_NAME} configured successfully."
else
    log_warn "No supported battery conservation / charge threshold hardware detected on this machine."
    log_info "Plugin registered, but feature will remain inactive until run on supported hardware."
fi
