#!/usr/bin/env bash

LOCK="  Lock"
LOGOUT="  Logout"
RESTART="  Reboot"
SHUTDOWN="  Shutdown"

dmenu_cmd() {
  hyprvibe-dmenu -dmenu --preset power
}

run_launcher() {
  # order preserved exactly as in original: lock → logout → restart → shutdown
  printf '%s\n%s\n%s\n%s\n' "$LOCK" "$LOGOUT" "$RESTART" "$SHUTDOWN" | dmenu_cmd
}

run_cmd() {
  case $1 in
  --shutdown)
    systemctl poweroff
    ;;
  --restart)
    systemctl reboot
    ;;
  --logout)
    hyprctl dispatch 'hl.dsp.exit()'
    ;;
  --lock)
    sleep 0.2
    hyprlock
    ;;
  esac
}

chosen="$(run_launcher || true)"

case $chosen in
$SHUTDOWN)
  run_cmd --shutdown
  ;;
$RESTART)
  run_cmd --restart
  ;;
$LOGOUT)
  run_cmd --logout
  ;;
$LOCK)
  run_cmd --lock
  ;;
esac

