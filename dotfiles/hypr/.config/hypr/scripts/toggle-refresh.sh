#!/usr/bin/env bash
set -euo pipefail

MODE="toggle"
QUIET=false

while (( $# > 0 )); do
    case "$1" in
        --high) MODE="high" ;;
        --low)  MODE="low" ;;
        --toggle) MODE="toggle" ;;
        --quiet) QUIET=true ;;
        *)
            echo "Usage: $(basename "$0") [--toggle|--high|--low] [--quiet]" >&2
            exit 1
            ;;
    esac
    shift
done

notify_msg() {
    local urgency="$1" title="$2" body="$3"
    if [[ "$QUIET" == true ]]; then
        return 0
    fi
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u "$urgency" "$title" "$body" 2>/dev/null || true
    fi
}

if ! command -v hyprctl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    notify_msg critical "Screen Mode" "hyprctl or jq is not installed"
    exit 1
fi

# Fetch active monitors dynamically and select focused display (fallback to first)
MON_INFO=$(hyprctl monitors -j 2>/dev/null || true)
if [[ -z "$MON_INFO" || "$MON_INFO" == "[]" ]]; then
    notify_msg critical "Screen Mode" "No active monitor found / Not supported on this display"
    exit 1
fi

IFS=$'\t' read -r OUTPUT WIDTH HEIGHT SCALE MAX_RATE SUPPORTS_10BIT < <(
    printf '%s' "$MON_INFO" | jq -r '
        (([.[] | select(.focused == true)] | .[0]) // .[0] // empty) as $m
        | if $m == null then empty else
            ($m.availableModes // []
                | map(
                    select(startswith("\($m.width)x\($m.height)@"))
                    | ltrimstr("\($m.width)x\($m.height)@")
                    | rtrimstr("Hz")
                    | split(".")[0]
                    | tonumber?
                )
                | max // (($m.refreshRate // 120) | floor)
            ) as $max
            | (
                (($m.currentFormat // "" | test("2101010|16161616|F16"))
                 or ($m.hardwareDetails.hdr // false))
                | if . then "1" else "0" end
            ) as $tenbit
            | [($m.name // ""), ($m.width // ""), ($m.height // ""), ($m.scale // 1.0), $max, $tenbit]
            | @tsv
          end
    ' 2>/dev/null || true
)

if [[ -z "${OUTPUT:-}" || -z "${WIDTH:-}" || -z "${HEIGHT:-}" ]]; then
    notify_msg critical "Screen Mode" "Could not detect active monitor resolution"
    exit 1
fi

MAX_RATE="${MAX_RATE:-120}"
SUPPORTS_10BIT="${SUPPORTS_10BIT:-0}"

# Fetch current vrr state reliably (0 = off, 1 = on, 2 = fullscreen)
VRR_STATE=$(hyprctl getoption misc.vrr -j 2>/dev/null | jq -r '.int // empty' 2>/dev/null || true)

apply_mode() {
    local target_rate="$1"
    local target_vrr="$2"
    local bitdepth_opt=""
    if [[ "$SUPPORTS_10BIT" == "1" ]]; then
        bitdepth_opt=", bitdepth = 10"
    fi

    if hyprctl eval "hl.monitor({ output = \"${OUTPUT}\", mode = \"${WIDTH}x${HEIGHT}@${target_rate}\", position = \"auto\", scale = ${SCALE}${bitdepth_opt} })" >/dev/null 2>&1 \
        && hyprctl eval "hl.config({ misc = { vrr = ${target_vrr} } })" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

if [[ "$MODE" == "toggle" ]]; then
    if (( MAX_RATE <= 60 )); then
        notify_msg normal "Screen Mode" "Display only supports ${MAX_RATE}Hz. High refresh rate toggle not applicable."
        exit 0
    fi
    if [[ "$VRR_STATE" == "0" ]]; then
        MODE="high"
    else
        MODE="low"
    fi
fi

if [[ "$MODE" == "high" ]]; then
    if (( MAX_RATE <= 60 )); then
        notify_msg normal "Screen Mode" "Display only supports ${MAX_RATE}Hz."
        exit 0
    fi
    if apply_mode "$MAX_RATE" 2; then
        notify_msg normal "Screen Mode" "${MAX_RATE}Hz VRR (${OUTPUT})"
        if [[ "$QUIET" == true ]]; then
            printf '%s\t%s\n' "$OUTPUT" "$MAX_RATE"
        fi
    else
        notify_msg critical "Screen Mode" "VRR mode switch not supported on ${OUTPUT}"
        exit 1
    fi
else
    if apply_mode 60 0; then
        notify_msg normal "Screen Mode" "60Hz Locked (${OUTPUT})"
        if [[ "$QUIET" == true ]]; then
            printf '%s\t%s\n' "$OUTPUT" "60"
        fi
    else
        notify_msg critical "Screen Mode" "60Hz mode switch not supported on ${OUTPUT}"
        exit 1
    fi
fi
