#!/usr/bin/env bash
set -euo pipefail

# Build C++ HyprVibeLauncher QML plugin and hyprvibe-dmenu client in Release mode.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
USER_HOME="${USER_HOME:-${HOME}}"
SRC_DIR="${ROOT_DIR}/dotfiles/quickshell/.config/quickshell/Launcher/engine"
PLUGIN_OUT="${ROOT_DIR}/dotfiles/quickshell/.config/quickshell/Launcher/HyprVibeLauncher/libhyprvibelauncher.so"
BIN_OUT="${USER_HOME}/.local/bin/hyprvibe-dmenu"
BUILD_DIR="${XDG_CACHE_HOME:-${USER_HOME}/.cache}/hyprvibe/launcher-build"

if [[ ! -d "$SRC_DIR" ]]; then
    echo "Error: Missing launcher engine source directory: $SRC_DIR" >&2
    exit 1
fi

for tool in cmake g++; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Error: Missing required build tool: $tool" >&2
        exit 1
    fi
done

GENERATOR_ARGS=()
if command -v ninja >/dev/null 2>&1; then
    GENERATOR_ARGS=(-G Ninja)
fi

mkdir -p "$BUILD_DIR" "$(dirname "$BIN_OUT")" "$(dirname "$PLUGIN_OUT")"
cmake -S "$SRC_DIR" -B "$BUILD_DIR" "${GENERATOR_ARGS[@]}" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD_DIR" --parallel

install -Dm755 "${BUILD_DIR}/hyprvibe-dmenu" "$BIN_OUT"
if [[ ! -f "$PLUGIN_OUT" ]]; then
    echo "Error: Failed to produce QML plugin: $PLUGIN_OUT" >&2
    exit 1
fi

echo "Built HyprVibe launcher plugin -> $PLUGIN_OUT"
echo "Installed hyprvibe-dmenu -> $BIN_OUT"
