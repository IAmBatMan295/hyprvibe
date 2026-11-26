#!/usr/bin/env bash
set -euo pipefail

if ! command -v powerprofilesctl >/dev/null 2>&1; then
  notify-send -u critical "Power Profile" "powerprofilesctl is not installed or unavailable" 2>/dev/null || true
  exit 1
fi

if ! active=$(powerprofilesctl get 2>/dev/null) || [[ -z "$active" ]]; then
  notify-send -u critical "Power Profile" "Failed to query active power profile" 2>/dev/null || true
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
TOGGLE_REFRESH="${SCRIPT_DIR}/toggle-refresh.sh"

c_active=""
c_dim=""
if [[ -f "${HOME}/.local/state/hyprvibe/current/colors.toml" ]]; then
  c_active=$(grep -m1 '^foreground' "${HOME}/.local/state/hyprvibe/current/colors.toml" | cut -d'"' -f2 || true)
  c_dim=$(grep -m1 '^muted' "${HOME}/.local/state/hyprvibe/current/colors.toml" | cut -d'"' -f2 || true)
elif command -v hyprvibe-theme >/dev/null 2>&1; then
  c_active=$(hyprvibe-theme get foreground 2>/dev/null || true)
  c_dim=$(hyprvibe-theme get muted 2>/dev/null || true)
fi
[[ -z "$c_active" ]] && c_active="#ffffff"
[[ -z "$c_dim" ]] && c_dim="#8e8e8e"

c_perf="$c_dim"
c_bal="$c_dim"
c_save="$c_dim"

[[ "$active" == "performance" ]] && c_perf="$c_active"
[[ "$active" == "balanced" ]] && c_bal="$c_active"
[[ "$active" == "power-saver" ]] && c_save="$c_active"

PERF="<span color=\"$c_perf\">  Performance</span>"
BAL="<span color=\"$c_bal\">  Balanced</span>"
SAVE="<span color=\"$c_save\">󰌪  Power Saver</span>"

active_label=""
case "$active" in
  performance) active_label="  Performance" ;;
  balanced) active_label="  Balanced" ;;
  power-saver) active_label="󰌪  Power Saver" ;;
esac

dmenu_cmd() {
  hyprvibe-dmenu -dmenu \
    --preset profiles \
    -p "Profile ($active)" \
    -markup-rows \
    -select "$active_label"
}

run_launcher() {
  printf '%s\n%s\n%s\n' "$PERF" "$BAL" "$SAVE" | dmenu_cmd
}

run_cmd() {
  case $1 in
  --performance)
    if ! powerprofilesctl set performance; then
      notify-send -u critical "Power Profile" "Failed to switch to Performance Mode" 2>/dev/null || true
      exit 1
    fi
    notify-send -t 3000 "Power Profile" "Set to  Performance Mode" 2>/dev/null || true

    # One-shot restore to native max refresh + VRR; manual toggles afterward stay respected.
    if [[ -x "$TOGGLE_REFRESH" ]] && command -v hyprctl >/dev/null 2>&1; then
      local switched_info switched_out switched_rate
      if switched_info=$("$TOGGLE_REFRESH" --high --quiet 2>/dev/null); then
        IFS=$'\t' read -r switched_out switched_rate <<<"$switched_info"
        if [[ -n "${switched_out:-}" && -n "${switched_rate:-}" ]]; then
          notify-send -t 4000 "Performance Active" "Refresh rate restored to ${switched_rate}Hz VRR (${switched_out})" 2>/dev/null || true
        fi
      fi
    fi
    ;;
  --balanced)
    powerprofilesctl set balanced
    notify-send -t 3000 "Power Profile" "Set to   Balanced Mode" 2>/dev/null || true
    ;;
  --power-saver)
    powerprofilesctl set power-saver
    notify-send -t 3000 "Power Profile" "Set to 󰌪 Power Saver Mode" 2>/dev/null || true

    if [[ -x "$TOGGLE_REFRESH" ]] && command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
      local vrr_state switched_info switched_out switched_rate
      vrr_state=$(hyprctl getoption misc.vrr -j 2>/dev/null | jq -r '.int // empty' 2>/dev/null || true)
      if [[ "$vrr_state" != "0" ]]; then
        if switched_info=$("$TOGGLE_REFRESH" --low --quiet 2>/dev/null); then
          IFS=$'\t' read -r switched_out switched_rate <<<"$switched_info"
          if [[ -n "${switched_out:-}" ]]; then
            notify-send -t 4000 "Power Saver Active" "Refresh rate locked to 60Hz (${switched_out})" 2>/dev/null || true
          fi
        else
          notify-send -u critical "Power Saver Active" "Failed to lock refresh rate to 60Hz" 2>/dev/null || true
        fi
      fi
    fi
    ;;
  esac
}

chosen="$(run_launcher || true)"

case "$chosen" in
	*"Performance"*)
	  run_cmd --performance
	  ;;
	*"Balanced"*)
	  run_cmd --balanced
	  ;;
	*"Power Saver"*)
	  run_cmd --power-saver
	  ;;
esac
