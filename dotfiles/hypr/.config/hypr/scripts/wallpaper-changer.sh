#!/usr/bin/env bash

# ---- CONFIG ----
WALL_DIR="${WALL_DIR:-$HOME/Pictures/Current-Wallpapers}"
INTERVAL=45
STATE_FILE="$HOME/.local/state/hyprvibe/current_wallpaper"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/hyprvibe-wallpaper-changer.lock"
PID_FILE="${WALLPAPER_PID_FILE:-${XDG_RUNTIME_DIR:-/tmp}/hyprvibe-wallpaper-changer.pid}"

if ! command -v awww >/dev/null 2>&1; then
  exit 0
fi

# Ensure single running instance
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  exit 0
fi

printf '%s\n' "$$" > "$PID_FILE"
mkdir -p "$(dirname "$STATE_FILE")"

SLEEP_PID=""
RELOAD_REQUESTED=0
LAST_WALL=""
DECK=()

ensure_daemon() {
  if ! pgrep -x awww-daemon >/dev/null 2>&1; then
    awww-daemon 200>&- >/dev/null 2>&1 &
    for ((i = 0; i < 30; i++)); do
      if awww query >/dev/null 2>&1; then
        break
      fi
      sleep 0.05
    done
  fi
}

# Detect currently displayed wallpaper on startup
if [[ -f "$STATE_FILE" ]]; then
  LAST_WALL="$(cat "$STATE_FILE" 2>/dev/null)"
fi

get_current_fps() {
  local rate=""
  if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    rate=$(hyprctl monitors -j 2>/dev/null | jq -r '(([.[] | select(.focused == true)] | .[0]) // .[0] // empty) | .refreshRate // empty | floor' 2>/dev/null || true)
  fi
  if [[ -z "$rate" ]]; then
    rate=$(hyprctl monitors 2>/dev/null | awk -F'[@.]' '/@/ {print $2; exit}')
  fi
  if [[ -n "$rate" && "$rate" =~ ^[0-9]+$ && "$rate" -ge 30 ]]; then
    echo "$rate"
  else
    echo "60"
  fi
}

refill_deck() {
  readarray -d '' -t DECK < <(find -L "$WALL_DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) -print0 2>/dev/null | shuf -z)

  local count=${#DECK[@]}
  if (( count == 0 )); then
    return
  fi

  # Prevent repeating the last wallpaper across cycle boundaries
  if (( count > 1 )) && [[ -n "$LAST_WALL" && "${DECK[0]}" == "$LAST_WALL" ]]; then
    local swap_idx=$(( (RANDOM % (count - 1)) + 1 ))
    local tmp="${DECK[0]}"
    DECK[0]="${DECK[swap_idx]}"
    DECK[swap_idx]="$tmp"
  fi
}

change_wallpaper() {
  if [[ ! -d "$WALL_DIR" ]]; then
    return
  fi

  # Refill and shuffle deck when empty
  if (( ${#DECK[@]} == 0 )); then
    refill_deck
  fi

  local count=${#DECK[@]}
  if (( count == 0 )); then
    return
  fi

  # If only 1 wallpaper and already showing it, avoid re-rendering
  if (( count == 1 )) && [[ "${DECK[0]}" == "$LAST_WALL" ]]; then
    return
  fi

  local wall="${DECK[0]}"
  DECK=("${DECK[@]:1}")

  ensure_daemon

  local fps
  fps=$(get_current_fps)

  # Surprise effect animated transition matched to active display refresh rate
  awww img "$wall" \
    --transition-type random \
    --transition-duration 1.2 \
    --transition-fps "$fps" \
    --transition-bezier .23,1,.32,1 \
    --resize crop 200>&- >/dev/null 2>&1 || true

  LAST_WALL="$wall"
  echo "$wall" > "$STATE_FILE" 2>/dev/null || true
}

on_usr1() {
  # Clear deck + LAST_WALL so theme switch applies immediately even if filenames repeat or signal hits pre-sleep
  RELOAD_REQUESTED=1
  DECK=()
  LAST_WALL=""
  if [[ -n "$SLEEP_PID" ]]; then
    kill "$SLEEP_PID" 2>/dev/null || true
  fi
}

cleanup() {
  if [[ -n "${SLEEP_PID:-}" ]]; then
    kill "$SLEEP_PID" 2>/dev/null || true
  fi
  rm -f "$PID_FILE" 2>/dev/null || true
  exit 0
}

trap 'cleanup' SIGINT SIGTERM
trap '' SIGHUP
trap 'on_usr1' SIGUSR1

# Ensure daemon is running immediately on launch
ensure_daemon

while true; do
  RELOAD_REQUESTED=0
  change_wallpaper
  if (( RELOAD_REQUESTED == 1 )); then
    continue
  fi
  sleep "$INTERVAL" 200>&- &
  SLEEP_PID=$!
  wait "$SLEEP_PID" 2>/dev/null || true
  SLEEP_PID=""
done
