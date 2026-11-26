#!/bin/bash

if ! command -v cliphist >/dev/null 2>&1; then
    notify-send -u critical "Clipboard Menu" "cliphist is not installed" 2>/dev/null || true
    exit 1
fi

# 1. Get History
HISTORY_SNAPSHOT=$(cliphist list | head -n 20)

# 2. Options
EMPTY_MESSAGE="   [Empty]"

if [ -z "$HISTORY_SNAPSHOT" ]; then
    MENU_ITEMS="$EMPTY_MESSAGE"
else
    # Map IDs
    mapfile -t CLIPHIST_IDS < <(printf '%s\n' "$HISTORY_SNAPSHOT" | awk '{print $1}')
    # Format List: Strip binary tags, remove IDs, number them in single sed | awk pass
    MENU_ITEMS=$(printf '%s\n' "$HISTORY_SNAPSHOT" | \
                 sed -E 's/\[\[ binary data (.*) \]\]/[\1]/' | \
                 awk '{$1=""; sub(/^[ \t]+/, ""); printf "%d. %s\n", NR, $0}')
fi

# 3. Launch Quickshell C++ launcher (Ctrl+C exits with 10 to wipe history)
DMENU_STATUS=0
SELECTED_ITEM=$(printf '%s\n' "$MENU_ITEMS" | hyprvibe-dmenu -dmenu \
    --preset clipboard \
    -p " " \
    -i) || DMENU_STATUS=$?

# 4. Logic
if [ "$DMENU_STATUS" -eq 10 ]; then
    cliphist wipe
    wl-copy --clear
    exit 0
fi

if [ "$DMENU_STATUS" -ne 0 ] || [ -z "$SELECTED_ITEM" ]; then exit 0; fi

if [ "$SELECTED_ITEM" = "$EMPTY_MESSAGE" ]; then exit 0; fi

# Extract ID in pure Bash and Copy
LINE_NUMBER="${SELECTED_ITEM%%.*}"
LINE_NUMBER="${LINE_NUMBER//[[:space:]]/}"
if [[ -z "$LINE_NUMBER" || ! "$LINE_NUMBER" =~ ^[0-9]+$ || "$LINE_NUMBER" -le 0 ]]; then
    exit 0
fi

ARRAY_INDEX=$((LINE_NUMBER - 1))
if [[ -z "${CLIPHIST_IDS[ARRAY_INDEX]:-}" ]]; then
    exit 0
fi

ID_TO_COPY=${CLIPHIST_IDS[ARRAY_INDEX]}

cliphist decode "$ID_TO_COPY" | wl-copy
