#!/usr/bin/env bash
# Shared helper window launcher, visual header, error trap, and q-to-close utilities.

if [[ -n "${_HYPRVIBE_HELPER_UI_LOADED:-}" ]]; then
    return 0
fi
_HYPRVIBE_HELPER_UI_LOADED=1

HELPER_HEADLESS="${HELPER_HEADLESS:-false}"
HELPER_FAIL_HANDLED=false

# Shared ANSI palette for rich terminal helpers
CLR_RESET="\033[0m"
CLR_BOLD="\033[1m"
CLR_GREEN="\033[32m"
CLR_RED="\033[31m"
CLR_YELLOW="\033[33m"
CLR_CYAN="\033[36m"
CLR_GRAY="\033[90m"
export CLR_RESET CLR_BOLD CLR_GREEN CLR_RED CLR_YELLOW CLR_CYAN CLR_GRAY

helper_has_flag() {
    local bypass_list="$1"
    shift
    local arg flag
    for arg in "$@"; do
        for flag in $bypass_list; do
            if [[ "$arg" == "$flag" ]]; then
                return 0
            fi
        done
    done
    return 1
}

helper_maybe_spawn_window() {
    local self_path="$1"
    local pct_w="${2:-0.40}"
    local pct_h="${3:-0.40}"
    local min_w="${4:-600}"
    local min_h="${5:-380}"
    local bypass_flags="${6:---inner --headless}"
    shift 6

    if helper_has_flag "$bypass_flags" "$@"; then
        return 0
    fi

    if ! command -v hyprctl >/dev/null 2>&1 || ! pgrep -x Hyprland >/dev/null 2>&1; then
        return 0
    fi

    local script_file mon_info width height scale target_w target_h
    script_file="$(readlink -f "$self_path")"
    mon_info="$(hyprctl monitors -j 2>/dev/null || true)"

    IFS=$'\t' read -r width height scale < <(
        printf '%s' "$mon_info" | jq -r '
            (([.[] | select(.focused == true)] | .[0]) // .[0] // empty)
            | [(.width // 1920), (.height // 1080), (.scale // 1.0)]
            | @tsv
        ' 2>/dev/null || printf '1920\t1080\t1.0\n'
    )
    width="${width:-1920}"
    height="${height:-1080}"
    scale="${scale:-1.0}"

    target_w="$(awk -v w="$width" -v s="$scale" -v p="$pct_w" 'BEGIN { printf "%d", (w / s) * p }')"
    target_h="$(awk -v h="$height" -v s="$scale" -v p="$pct_h" 'BEGIN { printf "%d", (h / s) * p }')"
    (( target_w < min_w )) && target_w="$min_w"
    (( target_h < min_h )) && target_h="$min_h"

    local inner_args="" _arg
    for _arg in "$@"; do
        inner_args+=" $(printf '%q' "$_arg")"
    done

    local title="${HELPER_TITLE:-hyprvibe Helper}"
    local inner_cmd="foot -a hyprvibe-helper -T \"${title}\" -w ${target_w}x${target_h} bash \"${script_file}\" --inner${inner_args}"
    local inner_cmd_lua="${inner_cmd//\\/\\\\}"
    inner_cmd_lua="${inner_cmd_lua//\'/\\\'}"

    hyprctl eval "hl.exec_cmd('${inner_cmd_lua}')" >/dev/null 2>&1 || true
    exit 0
}

helper_print_title() {
    echo ""
    echo "  ${HELPER_ICON:-*}  ${HELPER_TITLE:-hyprvibe Helper}"
    echo ""
}

helper_notify() {
    local urgency="$1"
    local message="$2"
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u "$urgency" -a "${HELPER_TITLE:-hyprvibe}" "${HELPER_TITLE:-hyprvibe}" "$message" 2>/dev/null || true
    fi
}

helper_wait_for_q() {
    if [[ "${HELPER_HEADLESS:-false}" == "true" ]]; then
        return 0
    fi

    local prompt="${1:-  Press 'q' to close...}"
    echo ""
    printf '%s' "$prompt"
    local key=""
    while IFS= read -rsn1 key; do
        if [[ "$key" == "q" || "$key" == "Q" ]]; then
            echo ""
            return 0
        fi
    done
    echo ""
    return 0
}

helper_fail() {
    local msg="${1:-Operation failed.}"
    trap - ERR
    HELPER_FAIL_HANDLED=true
    echo "" >&2
    echo "  ❌ Error: ${msg}" >&2
    helper_notify critical "$msg"
    helper_wait_for_q "  Press 'q' to close..."
    exit 1
}

helper_on_err() {
    local line="${1:-?}"
    trap - ERR
    if [[ "${HELPER_FAIL_HANDLED:-false}" == "true" ]]; then
        exit 1
    fi
    HELPER_FAIL_HANDLED=true
    echo "" >&2
    echo "  ❌ Unexpected error at line ${line}." >&2
    helper_notify critical "Unexpected error at line ${line}"
    helper_wait_for_q "  Press 'q' to close..."
    exit 1
}

helper_enable_error_pause() {
    set -E
    trap 'helper_on_err "$LINENO"' ERR
}
